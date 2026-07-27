// ============================================================================
// Tomass Seguridad — VALIDAR ACCESO
// ============================================================================
// QUÉ HACE
//   Es el portero digital. Recibe un código QR de residente más el código del
//   muro, decide si la persona entra o no, lo registra y avisa al guardia.
//
// SIRVE PARA LOS DOS CASOS, CON EL MISMO CÓDIGO
//   Caso A — El residente escanea el QR pegado en el muro.
//            Quien llama: el residente. Quien entra: el residente.
//   Caso B — El guardia escanea el QR de la pantalla del residente.
//            Quien llama: el guardia. Quien entra: el residente del código.
//
//   En los dos casos, quién ENTRA sale del código firmado, y quién OPERA sale de
//   la sesión. Nunca se confía en lo que el celular dice ser.
//
// CÓMO DECIDE SI ES ENTRADA O SALIDA
//   Mira el último movimiento de esa persona. Si la última vez entró, ahora sale.
//   Si la última vez salió (o nunca pasó), ahora entra. Así alcanza UN solo QR
//   pegado en el muro para las dos cosas, sin que nadie tenga que elegir nada.
//
//   Y si alguien escanea dos veces seguidas por error, no lo cuenta como salida:
//   dentro de los primeros 2 minutos en el mismo punto lo toma como repetido.
//
// LA DIFERENCIA ENTRE PEATONAL Y VEHICULAR
//   Peatonal  → se registra la entrada al instante y al guardia le llega un
//               aviso informativo. La persona ya pasó.
//   Vehicular → NO se registra la entrada todavía. Se crea una solicitud que
//               aparece en la pantalla del guardia, y le suena un aviso urgente.
//               La entrada se registra cuando el guardia aprieta ABRIR ACCESO.
//               Esto es a propósito: la barrera la abre una persona, no el
//               sistema, así que el registro tiene que reflejar quién la abrió.
//
// CÓMO SE LLAMA DESDE LA APP
//   POST /functions/v1/validar-acceso
//   { "token_qr": "...", "codigo_estatico": "...", "id_local": "..." }
// ============================================================================

import { quienPregunta, clienteServidor, ErrorDeSesion } from "../_compartido/clientes.ts";
import { verificarCodigo } from "../_compartido/codigos.ts";
import { avisar, guardiasEnEsePuesto, administradores } from "../_compartido/avisos.ts";
import { exito, error, saludoPrevio, registrar } from "../_compartido/respuesta.ts";

/** Dentro de este rato, volver a escanear en el mismo punto es "repetido". */
const MINUTOS_PARA_REPETIDO = 2;

Deno.serve(async (peticion: Request) => {
  if (peticion.method === "OPTIONS") return saludoPrevio();
  if (peticion.method !== "POST") return error("Método no permitido.", 405);

  try {
    const quien = await quienPregunta(peticion);
    const servidor = clienteServidor();

    const cuerpo = await peticion.json().catch(() => ({})) as {
      token_qr?: string;
      codigo_estatico?: string;
      id_local?: string;
      geo_lat?: number;
      geo_lng?: number;
    };

    if (!cuerpo.token_qr || !cuerpo.codigo_estatico) {
      return error("Faltan datos del escaneo. Intentá de nuevo.", 400);
    }

    const idLocal = cuerpo.id_local ?? crypto.randomUUID();

    // ------------------------------------------------------------------------
    // 1 · El código del muro: ¿existe y está activo?
    // ------------------------------------------------------------------------
    const { data: punto } = await servidor
      .from("puntos_acceso")
      .select("id, condominio_id, nombre, tipo, activo")
      .eq("codigo_qr_estatico", cuerpo.codigo_estatico)
      .maybeSingle();

    if (!punto) {
      return error("Ese código del muro no pertenece a ningún acceso.", 404, {
        titulo: "CÓDIGO NO RECONOCIDO",
      });
    }

    if (!punto.activo) {
      return error(`El acceso "${punto.nombre}" está fuera de servicio.`, 403, {
        titulo: "ACCESO FUERA DE SERVICIO",
      });
    }

    // Quien opera tiene que ser del mismo condominio que la entrada
    if (punto.condominio_id !== quien.condominio_id) {
      return error("Ese acceso no pertenece a tu condominio.", 403, {
        titulo: "ACCESO DENEGADO",
      });
    }

    // ------------------------------------------------------------------------
    // 2 · El código del residente: ¿es auténtico y está vigente?
    // ------------------------------------------------------------------------
    const { data: llave } = await servidor
      .from("secretos_condominio")
      .select("secreto_qr")
      .eq("condominio_id", punto.condominio_id)
      .maybeSingle();

    if (!llave?.secreto_qr) {
      registrar("condominio_sin_llave", { condominio_id: punto.condominio_id });
      return error("Hay un problema de configuración. Avisale a la administración.", 500);
    }

    const revision = await verificarCodigo(
      llave.secreto_qr,
      cuerpo.token_qr,
      punto.condominio_id,
    );

    if (!revision.valido || !revision.contenido) {
      return error(revision.mensaje ?? "Código no válido.", 403, {
        titulo: "ACCESO DENEGADO",
        motivo: revision.motivo,
        // Un código vencido no es un intento de fraude: es lo normal si la
        // persona tardó en escanear. Se le dice qué hacer.
        puede_reintentar: revision.motivo === "vencido",
      });
    }

    const contenido = revision.contenido;

    // ------------------------------------------------------------------------
    // 3 · La persona del código: ¿sigue activa?
    // ------------------------------------------------------------------------
    const { data: residente } = await servidor
      .from("usuarios")
      .select("id, nombre_completo, estado, foto_url, unidad_id, rol, motivo_inactivo")
      .eq("id", contenido.sub)
      .maybeSingle();

    if (!residente) {
      return error("La persona del código ya no está registrada.", 403, {
        titulo: "ACCESO DENEGADO",
      });
    }

    let unidad: string | null = contenido.uni ?? null;
    if (residente.unidad_id) {
      const { data: u } = await servidor
        .from("unidades")
        .select("numero, torre")
        .eq("id", residente.unidad_id)
        .maybeSingle();
      if (u) unidad = [u.numero, u.torre].filter(Boolean).join(" ");
    }

    /** Registra un intento denegado y arma la respuesta roja. */
    async function denegar(
      mensaje: string,
      detalle: string,
      estadoHttp = 403,
    ): Promise<Response> {
      await servidor.rpc("registrar_movimiento", {
        p_id_local: idLocal,
        p_persona_tipo: "residente",
        p_persona_id: residente!.id,
        p_punto_acceso_id: punto!.id,
        p_sentido: "entrada",
        p_estado: "denegado",
        p_motivo_denegacion: `${mensaje} ${detalle}`.trim(),
        p_guardia_id: quien.rol === "guardia" ? quien.id : null,
        p_geo_lat: cuerpo.geo_lat ?? null,
        p_geo_lng: cuerpo.geo_lng ?? null,
      });

      return error(mensaje, estadoHttp, {
        titulo: "ACCESO DENEGADO",
        detalle,
        residente: residente!.nombre_completo,
        unidad,
        punto_acceso: punto!.nombre,
      });
    }

    if (residente.estado !== "activo") {
      return await denegar(
        residente.estado === "suspendido"
          ? "Este residente está suspendido."
          : "Este residente ya no vive en el condominio.",
        residente.motivo_inactivo ?? "Consultá con la administración.",
      );
    }

    // ------------------------------------------------------------------------
    // 4 · ¿Entrada o salida? Se mira el último movimiento
    // ------------------------------------------------------------------------
    const { data: ultimos } = await servidor
      .from("movimientos_acceso")
      .select("id, sentido, punto_acceso_id, ocurrido_en, tipo_acceso")
      .eq("residente_id", residente.id)
      .eq("estado", "aprobado")
      .order("ocurrido_en", { ascending: false })
      .limit(1);

    const ultimo = ultimos?.[0];
    const sentido: "entrada" | "salida" =
      ultimo?.sentido === "entrada" ? "salida" : "entrada";

    // Doble escaneo por error: no se cuenta como movimiento nuevo
    if (ultimo && ultimo.punto_acceso_id === punto.id) {
      const minutos = (Date.now() - new Date(ultimo.ocurrido_en).getTime()) / 60000;
      if (minutos < MINUTOS_PARA_REPETIDO) {
        return exito({
          aprobado: true,
          repetido: true,
          sentido: ultimo.sentido,
          tipo_acceso: ultimo.tipo_acceso,
          titulo: ultimo.sentido === "entrada" ? "YA REGISTRAMOS TU ENTRADA" : "YA REGISTRAMOS TU SALIDA",
          mensaje: "Escaneaste dos veces. No hace falta volver a hacerlo.",
          residente: residente.nombre_completo,
          unidad,
          punto_acceso: punto.nombre,
          hora: ultimo.ocurrido_en,
        });
      }
    }

    // ------------------------------------------------------------------------
    // 5 · ¿Es un ingreso vehicular de verdad?
    // ------------------------------------------------------------------------
    // El punto manda: si el muro es de la barrera Y el código es vehicular,
    // hay que abrir la barrera. Si el código es peatonal pero la persona pasa
    // por el portón de autos caminando, se registra como peatonal y listo.
    const esVehicular = punto.tipo === "vehicular" && contenido.tipo === "vehicular";

    // ------------------------------------------------------------------------
    // 6A · CAMINO VEHICULAR — se crea la solicitud y suena el aviso urgente
    // ------------------------------------------------------------------------
    if (esVehicular) {
      if (!contenido.veh) {
        return await denegar(
          "El código no indica ningún vehículo.",
          "Volvé a la pantalla principal y generá el código en modo VEHICULAR.",
        );
      }

      const { data: vehiculo } = await servidor
        .from("vehiculos")
        .select("id, patente, marca, modelo, color, foto_url, estado, residente_id")
        .eq("id", contenido.veh)
        .maybeSingle();

      if (!vehiculo || vehiculo.residente_id !== residente.id) {
        return await denegar(
          "El vehículo del código no está registrado a tu nombre.",
          "Revisá la pantalla Mis Vehículos.",
        );
      }

      // Se vuelve a revisar la aprobación: el administrador pudo haberla quitado
      // entre que se generó el código y ahora.
      if (vehiculo.estado !== "aprobado") {
        return await denegar(
          `El vehículo ${vehiculo.patente} no está aprobado.`,
          vehiculo.estado === "pendiente"
            ? "Está esperando la aprobación de la administración. Podés entrar caminando."
            : "Fue rechazado por la administración. Consultá el motivo en Mis Vehículos.",
        );
      }

      // Se crea la solicitud que el guardia va a ver en su pantalla
      const { data: nueva, error: falloSolicitud } = await servidor
        .from("solicitudes_vehiculares")
        .insert({
          condominio_id: punto.condominio_id,
          id_local: idLocal,
          residente_id: residente.id,
          vehiculo_id: vehiculo.id,
          punto_acceso_id: punto.id,
          sentido,
          estado: "pendiente",
        })
        .select("id, solicitado_en")
        .single();

      let solicitudId: string;
      let solicitadoEn: string;
      let esReintento = false;

      if (falloSolicitud) {
        // Si ya había una con ese mismo id_local, es un reintento del celular
        // (se cortó el internet y volvió a mandar). Se usa la que ya estaba, y
        // NO se le vuelve a sonar el aviso al guardia.
        const { data: existente } = await servidor
          .from("solicitudes_vehiculares")
          .select("id, solicitado_en")
          .eq("id_local", idLocal)
          .maybeSingle();

        if (!existente) {
          registrar("solicitud_no_se_pudo_crear", { detalle: falloSolicitud.message });
          return error("No se pudo avisar al guardia. Intentá de nuevo.", 500);
        }

        solicitudId = existente.id;
        solicitadoEn = existente.solicitado_en;
        esReintento = true;
      } else {
        solicitudId = nueva.id;
        solicitadoEn = nueva.solicitado_en;
      }

      // ¿A quién le suena el aviso? Al guardia que está en ESE puesto ahora.
      let destinatarios = esReintento
        ? []
        : await guardiasEnEsePuesto(servidor, punto.id);

      let nadieDeTurno = false;
      if (!esReintento && destinatarios.length === 0) {
        // Nadie de turno: se avisa a los administradores, para que no quede un
        // auto esperando sin que nadie se entere.
        destinatarios = await administradores(servidor, punto.condominio_id);
        nadieDeTurno = true;
      }

      if (destinatarios.length > 0) {
        await avisar(servidor, {
          condominio_id: punto.condominio_id,
          usuarios: destinatarios,
          tipo: "acceso_vehicular_pendiente",
          titulo: nadieDeTurno
            ? "🚗 AUTO ESPERANDO — SIN GUARDIA DE TURNO"
            : "🚗 INGRESO VEHICULAR PENDIENTE",
          mensaje: `${residente.nombre_completo}` +
            `${unidad ? ` (Unidad ${unidad})` : ""} — ` +
            `${vehiculo.patente} (${vehiculo.marca} ${vehiculo.modelo} ${vehiculo.color})`,
          datos: {
            solicitud_id: solicitudId,
            punto_acceso_id: punto.id,
            punto_acceso: punto.nombre,
            residente_id: residente.id,
            residente: residente.nombre_completo,
            residente_foto_url: residente.foto_url ?? "",
            unidad: unidad ?? "",
            patente: vehiculo.patente,
            marca: vehiculo.marca,
            modelo: vehiculo.modelo,
            color: vehiculo.color,
            vehiculo_foto_url: vehiculo.foto_url ?? "",
            sentido,
            pantalla: "accesos_vehiculares_pendientes",
          },
          urgente: true,
        });
      }

      return exito({
        aprobado: true,
        espera_guardia: true,
        solicitud_id: solicitudId,
        sentido,
        tipo_acceso: "vehicular",
        titulo: sentido === "entrada"
          ? "✓ ACCESO VEHICULAR APROBADO"
          : "✓ SALIDA VEHICULAR APROBADA",
        mensaje: nadieDeTurno
          ? "No hay guardia de turno en este acceso. Se avisó a la administración."
          : "El guardia de la caseta ya fue avisado. Esperá que levante la barrera.",
        residente: residente.nombre_completo,
        unidad,
        punto_acceso: punto.nombre,
        vehiculo: {
          patente: vehiculo.patente,
          marca: vehiculo.marca,
          modelo: vehiculo.modelo,
          color: vehiculo.color,
          descripcion: `${vehiculo.marca} ${vehiculo.modelo} ${vehiculo.color}`,
        },
        hora: solicitadoEn,
        vibrar: "corta",
      });
    }

    // ------------------------------------------------------------------------
    // 6B · CAMINO PEATONAL — se registra al instante
    // ------------------------------------------------------------------------
    const { data: movimientoId, error: falloMovimiento } = await servidor
      .rpc("registrar_movimiento", {
        p_id_local: idLocal,
        p_persona_tipo: "residente",
        p_persona_id: residente.id,
        p_punto_acceso_id: punto.id,
        p_sentido: sentido,
        p_estado: "aprobado",
        p_guardia_id: quien.rol === "guardia" ? quien.id : null,
        p_geo_lat: cuerpo.geo_lat ?? null,
        p_geo_lng: cuerpo.geo_lng ?? null,
      });

    if (falloMovimiento) {
      registrar("movimiento_no_se_pudo_registrar", { detalle: falloMovimiento.message });
      return error("No se pudo registrar el acceso. Intentá de nuevo.", 500);
    }

    // Aviso informativo (no urgente) al guardia del puesto
    const guardias = await guardiasEnEsePuesto(servidor, punto.id);
    if (guardias.length > 0) {
      await avisar(servidor, {
        condominio_id: punto.condominio_id,
        usuarios: guardias,
        tipo: "acceso_peatonal",
        titulo: sentido === "entrada" ? "Ingreso peatonal" : "Salida peatonal",
        mensaje: `${residente.nombre_completo}` +
          `${unidad ? ` — Unidad ${unidad}` : ""} está ` +
          `${sentido === "entrada" ? "ingresando" : "saliendo"} por ${punto.nombre}`,
        datos: {
          movimiento_id: String(movimientoId),
          residente_id: residente.id,
          residente: residente.nombre_completo,
          residente_foto_url: residente.foto_url ?? "",
          unidad: unidad ?? "",
          punto_acceso: punto.nombre,
          sentido,
          pantalla: "ultimos_accesos",
        },
        urgente: false,
      });
    }

    // Nota si pasó caminando por el portón de los autos
    const notaPortonVehicular = punto.tipo === "vehicular"
      ? "Pasaste caminando por el acceso vehicular. Quedó registrado como peatonal."
      : null;

    return exito({
      aprobado: true,
      espera_guardia: false,
      movimiento_id: movimientoId,
      sentido,
      tipo_acceso: "peatonal",
      titulo: sentido === "entrada" ? "✓ ACCESO APROBADO" : "✓ SALIDA REGISTRADA",
      mensaje: notaPortonVehicular ??
        (sentido === "entrada"
          ? "Bienvenido. El guardia ya fue avisado."
          : "Que tengas buen día."),
      residente: residente.nombre_completo,
      unidad,
      punto_acceso: punto.nombre,
      hora: new Date().toISOString(),
      vibrar: "corta",
    });
  } catch (fallo) {
    if (fallo instanceof ErrorDeSesion) return error(fallo.message, 401);
    registrar("validar_acceso_error_inesperado", { detalle: String(fallo) });
    return error("No se pudo validar el acceso. Intentá de nuevo.", 500);
  }
});
