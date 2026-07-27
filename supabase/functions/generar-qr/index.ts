// ============================================================================
// Tomass Seguridad — GENERAR QR
// ============================================================================
// QUÉ HACE
//   Le entrega al celular del residente un código QR nuevo, firmado, que vence
//   en 60 segundos. La app la llama cada vez que el código anterior está por
//   vencer, y por eso el QR de la pantalla "cambia solo".
//
// QUIÉN LA PUEDE LLAMAR
//   Solo un residente activo, con su sesión iniciada. Y solo puede pedir un
//   código PARA SÍ MISMO: la identidad se saca de la sesión verificada, no de
//   lo que el celular diga.
//
// LO QUE REVISA ANTES DE ENTREGAR EL CÓDIGO
//   · Que la persona tenga la sesión válida y esté activa
//   · Que el condominio esté activo (si dejó de pagar el servicio, se corta)
//   · Que no haya pedido otro código hace menos de 30 segundos
//   · Si el código es vehicular: que tenga un vehículo APROBADO
//
// CÓMO SE LLAMA DESDE LA APP
//   POST /functions/v1/generar-qr
//   { "tipo": "vehicular", "vehiculo_id": "..." }     ← vehiculo_id es opcional
//   { "tipo": "peatonal" }
// ============================================================================

import { quienPregunta, clienteServidor, ErrorDeSesion } from "../_compartido/clientes.ts";
import { firmarCodigo } from "../_compartido/codigos.ts";
import { exito, error, saludoPrevio, registrar } from "../_compartido/respuesta.ts";

/** Mínimo de segundos entre un código y el siguiente, por residente. */
const ESPERA_ENTRE_CODIGOS = 30;

Deno.serve(async (peticion: Request) => {
  if (peticion.method === "OPTIONS") return saludoPrevio();
  if (peticion.method !== "POST") return error("Método no permitido.", 405);

  try {
    // ------------------------------------------------------------------------
    // 1 · Quién está pidiendo el código
    // ------------------------------------------------------------------------
    const quien = await quienPregunta(peticion);

    if (quien.rol !== "residente") {
      return error(
        "Solo los residentes tienen código de acceso. Los guardias usan el escáner.",
        403,
      );
    }

    const cuerpo = await peticion.json().catch(() => ({})) as {
      tipo?: string;
      vehiculo_id?: string;
    };

    const tipo = cuerpo.tipo === "vehicular" ? "vehicular" : "peatonal";
    const servidor = clienteServidor();

    // ------------------------------------------------------------------------
    // 2 · El condominio tiene que estar activo
    // ------------------------------------------------------------------------
    const { data: condominio } = await servidor
      .from("condominios")
      .select("id, activo, segundos_vida_qr")
      .eq("id", quien.condominio_id)
      .maybeSingle();

    if (!condominio?.activo) {
      return error(
        "El servicio de tu condominio está suspendido. Avisale a la administración.",
        403,
      );
    }

    // ------------------------------------------------------------------------
    // 3 · Límite de códigos: máximo uno cada 30 segundos
    // ------------------------------------------------------------------------
    const { data: fichaCompleta } = await servidor
      .from("usuarios")
      .select("ultimo_qr_emitido_en, unidad_id")
      .eq("id", quien.id)
      .maybeSingle();

    const ultimo = fichaCompleta?.ultimo_qr_emitido_en;
    if (ultimo) {
      const segundosDesdeElUltimo = (Date.now() - new Date(ultimo).getTime()) / 1000;
      if (segundosDesdeElUltimo < ESPERA_ENTRE_CODIGOS) {
        const faltan = Math.ceil(ESPERA_ENTRE_CODIGOS - segundosDesdeElUltimo);
        return error(
          `Esperá ${faltan} segundo${faltan === 1 ? "" : "s"} antes de pedir otro código.`,
          429,
          { segundos_de_espera: faltan },
        );
      }
    }

    // ------------------------------------------------------------------------
    // 4 · La unidad, para mostrarla en pantalla
    // ------------------------------------------------------------------------
    let unidad: string | undefined;
    if (fichaCompleta?.unidad_id) {
      const { data: u } = await servidor
        .from("unidades")
        .select("numero, torre")
        .eq("id", fichaCompleta.unidad_id)
        .maybeSingle();
      if (u) unidad = [u.numero, u.torre].filter(Boolean).join(" ");
    }

    // ------------------------------------------------------------------------
    // 5 · Si es vehicular, tiene que tener un auto APROBADO
    // ------------------------------------------------------------------------
    let vehiculo: {
      id: string;
      patente: string;
      marca: string;
      modelo: string;
      color: string;
      foto_url: string | null;
    } | null = null;

    if (tipo === "vehicular") {
      const consulta = servidor
        .from("vehiculos")
        .select("id, patente, marca, modelo, color, foto_url")
        .eq("residente_id", quien.id)
        .eq("estado", "aprobado");

      // Si el residente eligió uno en particular, se respeta su elección
      if (cuerpo.vehiculo_id) consulta.eq("id", cuerpo.vehiculo_id);

      const { data: autos } = await consulta.order("creado_en", { ascending: true });

      if (!autos || autos.length === 0) {
        // Se le explica exactamente por qué no puede, y qué hacer
        const { data: pendientes } = await servidor
          .from("vehiculos")
          .select("patente, estado")
          .eq("residente_id", quien.id)
          .in("estado", ["pendiente", "rechazado"]);

        const enEspera = (pendientes ?? []).filter((v) => v.estado === "pendiente");

        let detalle: string;
        if (cuerpo.vehiculo_id) {
          detalle = "Ese vehículo no está aprobado o no es tuyo.";
        } else if (enEspera.length > 0) {
          const patentes = enEspera.map((v) => v.patente).join(", ");
          detalle = `Tu vehículo ${patentes} está esperando la aprobación de la ` +
            "administración. Mientras tanto podés entrar caminando con el código peatonal.";
        } else if ((pendientes ?? []).length > 0) {
          detalle = "Tu vehículo fue rechazado por la administración. " +
            "Consultá el motivo en la pantalla Mis Vehículos.";
        } else {
          detalle = "Todavía no registraste ningún vehículo. " +
            "Podés hacerlo en la pantalla Mis Vehículos.";
        }

        return error("No tenés ningún vehículo aprobado.", 403, {
          titulo: "ACCESO VEHICULAR NO DISPONIBLE",
          detalle,
          puede_peatonal: true,
        });
      }

      vehiculo = autos[0];
    }

    // ------------------------------------------------------------------------
    // 6 · La llave secreta del condominio y la firma del código
    // ------------------------------------------------------------------------
    const { data: llave } = await servidor
      .from("secretos_condominio")
      .select("secreto_qr")
      .eq("condominio_id", quien.condominio_id)
      .maybeSingle();

    if (!llave?.secreto_qr) {
      // Nunca debería pasar: la llave se crea sola con el condominio
      registrar("condominio_sin_llave", { condominio_id: quien.condominio_id });
      return error(
        "Hay un problema de configuración en tu condominio. Avisale a la administración.",
        500,
      );
    }

    const segundosDeVida = condominio.segundos_vida_qr ?? 60;

    const codigo = await firmarCodigo(
      llave.secreto_qr,
      {
        sub: quien.id,
        cond: quien.condominio_id,
        uni: unidad,
        tipo,
        veh: vehiculo?.id,
      },
      segundosDeVida,
    );

    // ------------------------------------------------------------------------
    // 7 · Se anota la hora, para el límite del próximo pedido
    // ------------------------------------------------------------------------
    await servidor
      .from("usuarios")
      .update({ ultimo_qr_emitido_en: new Date().toISOString() })
      .eq("id", quien.id);

    // ------------------------------------------------------------------------
    // 8 · Todo lo que la pantalla del residente necesita para dibujarse
    // ------------------------------------------------------------------------
    const vence = new Date(Date.now() + segundosDeVida * 1000);

    return exito({
      codigo,
      tipo,
      segundos_de_vida: segundosDeVida,
      vence_en: vence.toISOString(),
      residente: quien.nombre_completo,
      unidad: unidad ?? null,
      vehiculo: vehiculo
        ? {
          id: vehiculo.id,
          patente: vehiculo.patente,
          marca: vehiculo.marca,
          modelo: vehiculo.modelo,
          color: vehiculo.color,
          foto_url: vehiculo.foto_url,
          descripcion: `${vehiculo.marca} ${vehiculo.modelo} ${vehiculo.color}`,
        }
        : null,
    });
  } catch (fallo) {
    if (fallo instanceof ErrorDeSesion) return error(fallo.message, 401);
    registrar("generar_qr_error_inesperado", { detalle: String(fallo) });
    return error("No se pudo generar el código. Intentá de nuevo.", 500);
  }
});
