// ============================================================================
// Tomass Seguridad — VALIDAR CREDENCIAL
// ============================================================================
// QUÉ HACE
//   El guardia escanea el código de un VISITANTE o de una PERSONA DE SERVICIO
//   (la nana, el jardinero) y esta función le dice si puede pasar o no, y por qué.
//
//   El servidor descubre solo de qué tipo de código se trata. El guardia no
//   tiene que elegir nada en la pantalla: escanea y listo.
//
// QUIÉN LA PUEDE LLAMAR
//   Solo un guardia o el administrador. Un residente no puede validar códigos.
//
// DOS DETALLES QUE PARECEN CHICOS Y SON IMPORTANTES
//
//   1. NADIE QUEDA ENCERRADO.
//      El código de un visitante sirve una sola vez para entrar. Pero para SALIR
//      funciona siempre, incluso si ya venció mientras estaba adentro. Si no
//      fuera así, un visitante que se quedó hasta tarde no podría salir y habría
//      que abrirle a mano. Lo mismo con la nana que terminó pasadas sus horas.
//
//   2. EL HORARIO SOLO SE REVISA AL ENTRAR.
//      La nana de lunes, miércoles y viernes de 8 a 18 no entra un domingo. Pero
//      si entró el viernes a las 17:50 y sale a las 18:30, sale sin problema.
//
// CÓMO SE LLAMA DESDE LA APP
//   POST /functions/v1/validar-credencial
//   { "codigo": "...", "codigo_estatico": "...", "id_local": "..." }
//
// CÓMO SABE LA APP CUÁL FUNCIÓN LLAMAR
//   El código de un residente tiene DOS PUNTOS adentro (es un mensaje firmado).
//   Los de visitante y personal de servicio no. Entonces:
//     si el texto escaneado tiene 2 puntos  → llamar a validar-acceso
//     si no                                 → llamar a esta función
// ============================================================================

import { quienPregunta, clienteServidor, ErrorDeSesion } from "../_compartido/clientes.ts";
import { avisar, administradores } from "../_compartido/avisos.ts";
import { exito, error, saludoPrevio, registrar } from "../_compartido/respuesta.ts";

Deno.serve(async (peticion: Request) => {
  if (peticion.method === "OPTIONS") return saludoPrevio();
  if (peticion.method !== "POST") return error("Método no permitido.", 405);

  try {
    const quien = await quienPregunta(peticion);

    if (quien.rol === "residente") {
      return error(
        "Solo el personal de portería puede validar credenciales.",
        403,
      );
    }

    const servidor = clienteServidor();
    const cuerpo = await peticion.json().catch(() => ({})) as {
      codigo?: string;
      codigo_estatico?: string;
      id_local?: string;
    };

    if (!cuerpo.codigo) {
      return error("No se leyó ningún código. Intentá de nuevo.", 400);
    }

    const idLocal = cuerpo.id_local ?? crypto.randomUUID();

    // ------------------------------------------------------------------------
    // 1 · En qué punto de acceso está parado el guardia
    // ------------------------------------------------------------------------
    // Si escaneó el código del muro, se usa ese. Si no, se usa el puesto de su
    // turno abierto, que es el caso normal: el guardia ya eligió su puesto al
    // empezar el turno y no tiene por qué escanear el muro cada vez.
    let punto: { id: string; nombre: string; tipo: string; condominio_id: string } | null = null;

    if (cuerpo.codigo_estatico) {
      const { data } = await servidor
        .from("puntos_acceso")
        .select("id, nombre, tipo, condominio_id, activo")
        .eq("codigo_qr_estatico", cuerpo.codigo_estatico)
        .maybeSingle();
      if (data?.activo) punto = data;
    }

    if (!punto) {
      const { data: turno } = await servidor
        .from("turnos")
        .select("punto_acceso_id")
        .eq("guardia_id", quien.id)
        .is("cerrado_en", null)
        .order("inicio", { ascending: false })
        .limit(1)
        .maybeSingle();

      if (turno?.punto_acceso_id) {
        const { data } = await servidor
          .from("puntos_acceso")
          .select("id, nombre, tipo, condominio_id")
          .eq("id", turno.punto_acceso_id)
          .maybeSingle();
        punto = data;
      }
    }

    if (!punto) {
      return error(
        "No sabemos en qué acceso estás. Abrí tu turno o escaneá el código del muro.",
        400,
        { titulo: "FALTA ABRIR EL TURNO" },
      );
    }

    if (punto.condominio_id !== quien.condominio_id) {
      return error("Ese acceso no pertenece a tu condominio.", 403);
    }

    // ------------------------------------------------------------------------
    // 2 · ¿Es un código de VISITANTE?
    // ------------------------------------------------------------------------
    const { data: visita } = await servidor
      .from("visitas")
      .select(
        "id, condominio_id, residente_id, origen, nombre_visitante, cedula_visitante, " +
        "telefono_visitante, foto_visitante_url, patente_vehiculo, motivo_visita, " +
        "valido_desde, valido_hasta, estado, motivo_rechazo, unidad_id, nota_guardia",
      )
      .eq("token_qr", cuerpo.codigo)
      .maybeSingle();

    if (visita) {
      if (visita.condominio_id !== quien.condominio_id) {
        return error("Ese código es de otro condominio.", 403, {
          titulo: "CÓDIGO NO RECONOCIDO",
        });
      }
      return await resolverVisita(visita);
    }

    // ------------------------------------------------------------------------
    // 3 · ¿Es una credencial de PERSONAL DE SERVICIO?
    // ------------------------------------------------------------------------
    const { data: personal } = await servidor
      .from("personal_servicio")
      .select(
        "id, condominio_id, residente_id, nombre_completo, cedula, telefono, foto_url, " +
        "tipo, descripcion_tipo, patente_vehiculo, dias_autorizados, hora_desde, " +
        "hora_hasta, valido_hasta, estado, unidad_id",
      )
      .eq("token_qr", cuerpo.codigo)
      .maybeSingle();

    if (personal) {
      if (personal.condominio_id !== quien.condominio_id) {
        return error("Esa credencial es de otro condominio.", 403, {
          titulo: "CREDENCIAL NO RECONOCIDA",
        });
      }
      return await resolverPersonal(personal);
    }

    // ------------------------------------------------------------------------
    // 4 · No es ninguno de los dos
    // ------------------------------------------------------------------------
    return error(
      "Este código no corresponde a ninguna visita ni credencial de este condominio.",
      404,
      {
        titulo: "CÓDIGO NO RECONOCIDO",
        detalle: "Si es un residente, usá el escáner de códigos de residente.",
      },
    );

    // ========================================================================
    // VISITANTES
    // ========================================================================
    // deno-lint-ignore no-explicit-any
    async function resolverVisita(v: any): Promise<Response> {
      const unidad = await nombreUnidad(v.unidad_id, v.residente_id);

      const { data: ultimos } = await servidor
        .from("movimientos_acceso")
        .select("sentido, ocurrido_en")
        .eq("visita_id", v.id)
        .eq("estado", "aprobado")
        .order("ocurrido_en", { ascending: false })
        .limit(1);

      const ultimo = ultimos?.[0];
      const esSalida = ultimo?.sentido === "entrada";

      const fichaVisita = {
        tipo_persona: "visita" as const,
        nombre: v.nombre_visitante,
        cedula: v.cedula_visitante,
        telefono: v.telefono_visitante,
        foto_url: v.foto_visitante_url,
        patente: v.patente_vehiculo,
        motivo: v.motivo_visita,
        unidad,
        invita: await nombreResidente(v.residente_id),
        nota_guardia: v.nota_guardia,
        punto_acceso: punto!.nombre,
      };

      // ---- SALIDA: siempre se permite, aunque el código ya haya vencido ----
      if (esSalida) {
        const id = await registrarPaso("visita", v.id, "salida");
        return exito({
          aprobado: true,
          sentido: "salida",
          titulo: "✓ SALIDA REGISTRADA",
          mensaje: `${v.nombre_visitante} se retira.`,
          movimiento_id: id,
          ...fichaVisita,
        });
      }

      // ---- ENTRADA: acá sí se revisa todo ----
      if (ultimo?.sentido === "salida") {
        return denegarVisita(v, fichaVisita,
          "Este código ya se usó.",
          "El visitante ya entró y salió. Si vuelve, el residente tiene que generarle otro código.");
      }

      if (v.estado === "esperando_aprobacion") {
        return exito({
          aprobado: false,
          esperando_residente: true,
          titulo: "ESPERANDO AL RESIDENTE",
          mensaje: `El residente de la unidad ${unidad ?? "?"} todavía no respondió.`,
          detalle: "Cuando apruebe desde su celular, volvé a escanear el código.",
          ...fichaVisita,
        });
      }

      if (v.estado === "rechazada") {
        return denegarVisita(v, fichaVisita,
          "El residente rechazó esta visita.",
          v.motivo_rechazo ?? "No se indicó un motivo.");
      }

      if (v.estado === "cancelada") {
        return denegarVisita(v, fichaVisita,
          "Esta visita fue cancelada.",
          "El residente la dio de baja.");
      }

      if (v.estado === "expirada" || new Date(v.valido_hasta) < new Date()) {
        return denegarVisita(v, fichaVisita,
          "El código de esta visita venció.",
          `Era válido hasta el ${formatearFecha(v.valido_hasta)}. ` +
          "El residente puede generarle uno nuevo desde su celular.");
      }

      if (new Date(v.valido_desde) > new Date()) {
        return denegarVisita(v, fichaVisita,
          "Todavía no es la hora de esta visita.",
          `El código empieza a servir el ${formatearFecha(v.valido_desde)}.`);
      }

      // Todo en orden: entra
      const movimientoId = await registrarPaso("visita", v.id, "entrada");

      await servidor
        .from("visitas")
        .update({ estado: "usada", usada_en: new Date().toISOString() })
        .eq("id", v.id);

      // Se le avisa al residente que su visita llegó
      await avisar(servidor, {
        condominio_id: punto!.condominio_id,
        usuarios: [v.residente_id],
        tipo: "visita_ingreso",
        titulo: "Tu visita llegó",
        mensaje: `${v.nombre_visitante} ingresó por ${punto!.nombre}.`,
        datos: {
          visita_id: v.id,
          nombre: v.nombre_visitante,
          punto_acceso: punto!.nombre,
          pantalla: "mis_visitas",
        },
      });

      return exito({
        aprobado: true,
        sentido: "entrada",
        titulo: "✓ VISITA AUTORIZADA",
        mensaje: `${v.nombre_visitante} puede pasar.`,
        detalle: v.origen === "espontanea"
          ? "Visita aprobada por el residente."
          : "Visita pre-registrada por el residente.",
        movimiento_id: movimientoId,
        ...fichaVisita,
      });
    }

    // deno-lint-ignore no-explicit-any
    async function denegarVisita(v: any, ficha: unknown, mensaje: string, detalle: string) {
      await servidor.rpc("registrar_movimiento", {
        p_id_local: idLocal,
        p_persona_tipo: "visita",
        p_persona_id: v.id,
        p_punto_acceso_id: punto!.id,
        p_sentido: "entrada",
        p_estado: "denegado",
        p_motivo_denegacion: `${mensaje} ${detalle}`.trim(),
        p_guardia_id: quien.rol === "guardia" ? quien.id : null,
      });

      return error(mensaje, 403, {
        titulo: "ACCESO DENEGADO",
        detalle,
        ...(ficha as Record<string, unknown>),
      });
    }

    // ========================================================================
    // PERSONAL DE SERVICIO
    // ========================================================================
    // deno-lint-ignore no-explicit-any
    async function resolverPersonal(p: any): Promise<Response> {
      const unidad = await nombreUnidad(p.unidad_id, p.residente_id);

      const { data: ultimos } = await servidor
        .from("movimientos_acceso")
        .select("sentido, ocurrido_en")
        .eq("personal_servicio_id", p.id)
        .eq("estado", "aprobado")
        .order("ocurrido_en", { ascending: false })
        .limit(1);

      const esSalida = ultimos?.[0]?.sentido === "entrada";

      const ficha = {
        tipo_persona: "personal_servicio" as const,
        nombre: p.nombre_completo,
        cedula: p.cedula,
        telefono: p.telefono,
        foto_url: p.foto_url,
        patente: p.patente_vehiculo,
        oficio: p.descripcion_tipo ?? nombreOficio(p.tipo),
        unidad,
        trabaja_para: await nombreResidente(p.residente_id),
        horario: `${recortarHora(p.hora_desde)} a ${recortarHora(p.hora_hasta)}`,
        dias: nombresDeDias(p.dias_autorizados),
        punto_acceso: punto!.nombre,
      };

      // ---- SALIDA: siempre se permite, aunque terminó fuera de horario ----
      if (esSalida) {
        const id = await registrarPaso("personal_servicio", p.id, "salida");
        return exito({
          aprobado: true,
          sentido: "salida",
          titulo: "✓ SALIDA REGISTRADA",
          mensaje: `${p.nombre_completo} se retira.`,
          movimiento_id: id,
          ...ficha,
        });
      }

      // ---- ENTRADA: la base de datos decide, usando la hora de Chile ----
      const { data: revision } = await servidor
        .rpc("validar_personal_servicio", { p_token: cuerpo.codigo })
        .single();

      const permitido = (revision as { permitido?: boolean } | null)?.permitido === true;
      const motivo = (revision as { motivo?: string } | null)?.motivo ??
        "No se pudo revisar la credencial.";

      if (!permitido) {
        await servidor.rpc("registrar_movimiento", {
          p_id_local: idLocal,
          p_persona_tipo: "personal_servicio",
          p_persona_id: p.id,
          p_punto_acceso_id: punto!.id,
          p_sentido: "entrada",
          p_estado: "denegado",
          p_motivo_denegacion: motivo,
          p_guardia_id: quien.rol === "guardia" ? quien.id : null,
        });

        return error(motivo, 403, {
          titulo: "ACCESO DENEGADO",
          detalle: `${ficha.oficio} de la unidad ${unidad ?? "?"}. ` +
            `Trabaja ${ficha.dias}, de ${ficha.horario}.`,
          puede_llamar_al_residente: true,
          ...ficha,
        });
      }

      const movimientoId = await registrarPaso("personal_servicio", p.id, "entrada");

      await avisar(servidor, {
        condominio_id: punto!.condominio_id,
        usuarios: [p.residente_id],
        tipo: "personal_servicio_ingreso",
        titulo: `${ficha.oficio} ingresó`,
        mensaje: `${p.nombre_completo} entró por ${punto!.nombre}.`,
        datos: {
          personal_id: p.id,
          nombre: p.nombre_completo,
          punto_acceso: punto!.nombre,
          pantalla: "mi_personal_servicio",
        },
      });

      return exito({
        aprobado: true,
        sentido: "entrada",
        titulo: "✓ CREDENCIAL VÁLIDA",
        mensaje: `${p.nombre_completo} puede pasar.`,
        detalle: `${ficha.oficio} de la unidad ${unidad ?? "?"}.`,
        movimiento_id: movimientoId,
        ...ficha,
      });
    }

    // ========================================================================
    // AYUDAS
    // ========================================================================

    async function registrarPaso(
      tipoPersona: "visita" | "personal_servicio",
      personaId: string,
      sentido: "entrada" | "salida",
    ): Promise<string | null> {
      const { data, error: fallo } = await servidor.rpc("registrar_movimiento", {
        p_id_local: idLocal,
        p_persona_tipo: tipoPersona,
        p_persona_id: personaId,
        p_punto_acceso_id: punto!.id,
        p_sentido: sentido,
        p_estado: "aprobado",
        p_guardia_id: quien.rol === "guardia" ? quien.id : null,
      });

      if (fallo) {
        registrar("paso_no_se_pudo_registrar", { detalle: fallo.message });
        return null;
      }
      return data as string;
    }

    async function nombreUnidad(
      unidadId: string | null,
      residenteId: string,
    ): Promise<string | null> {
      let id = unidadId;
      if (!id) {
        const { data } = await servidor
          .from("usuarios").select("unidad_id").eq("id", residenteId).maybeSingle();
        id = data?.unidad_id ?? null;
      }
      if (!id) return null;
      const { data: u } = await servidor
        .from("unidades").select("numero, torre").eq("id", id).maybeSingle();
      return u ? [u.numero, u.torre].filter(Boolean).join(" ") : null;
    }

    async function nombreResidente(residenteId: string): Promise<string | null> {
      const { data } = await servidor
        .from("usuarios").select("nombre_completo").eq("id", residenteId).maybeSingle();
      return data?.nombre_completo ?? null;
    }
  } catch (fallo) {
    if (fallo instanceof ErrorDeSesion) return error(fallo.message, 401);
    registrar("validar_credencial_error_inesperado", { detalle: String(fallo) });
    return error("No se pudo validar la credencial. Intentá de nuevo.", 500);
  }
});

// ============================================================================
// TEXTOS PARA MOSTRAR EN PANTALLA
// ============================================================================

function nombreOficio(tipo: string): string {
  const nombres: Record<string, string> = {
    asesora_hogar: "Asesora del hogar",
    jardinero: "Jardinero",
    profesor: "Profesor",
    cuidador: "Cuidador",
    mantencion: "Mantención",
    paseador_mascotas: "Paseador de mascotas",
    otro: "Personal de servicio",
  };
  return nombres[tipo] ?? "Personal de servicio";
}

function nombresDeDias(dias: number[] | null): string {
  if (!dias || dias.length === 0) return "sin días asignados";
  if (dias.length === 7) return "todos los días";
  const nombres = ["lunes", "martes", "miércoles", "jueves", "viernes", "sábado", "domingo"];
  const lista = [...dias].sort((a, b) => a - b).map((d) => nombres[d - 1]);
  if (lista.length === 1) return lista[0];
  return `${lista.slice(0, -1).join(", ")} y ${lista[lista.length - 1]}`;
}

function recortarHora(hora: string): string {
  return hora?.slice(0, 5) ?? "";
}

function formatearFecha(fecha: string): string {
  const d = new Date(fecha);
  return d.toLocaleString("es-CL", {
    timeZone: "America/Santiago",
    day: "2-digit",
    month: "2-digit",
    year: "numeric",
    hour: "2-digit",
    minute: "2-digit",
  });
}
