// ============================================================================
// Tomass Seguridad — Avisar al administrador cuando llega una novedad crítica
// ============================================================================
// El guardia reporta una novedad con gravedad "critica" o "alta" y estado
// "abierto" → esta función hace sonar los celulares de TODOS los admins
// activos de ese condominio, aunque la app esté cerrada.
//
// La llama un trigger de la BD (ver base-de-datos/21-trigger-aviso-novedad-
// critica.sql) con la fila completa en el body (payload de net.http_post).
// La función re-lee desde la BD para asegurarse del dato (el trigger
// podría tener race con otros updates) y porque necesita joinear con
// usuarios para traer el nombre de quien reportó.
//
// SEGURIDAD
//   verify_jwt = true. El trigger manda el service_role_key en el header
//   Authorization. Un cliente anónimo no puede invocar esta función y
//   mandar avisos arbitrarios.
//
// IDEMPOTENCIA
//   Si el trigger disparara dos veces por la misma fila (reintento de red),
//   el camino 1 de avisar() usa INSERT en notificaciones — podría
//   duplicarse una fila. Es aceptable: ambos avisos llevan el mismo
//   incidente_id en `datos`, la UI deduplica si quiere. El camino 2 (push
//   FCM) sí puede sonar dos veces; para el caso real de "alta/critica"
//   preferimos un push duplicado antes que uno perdido.
// ============================================================================

import { clienteServidor } from "../_compartido/clientes.ts";
import { exito, error, registrar, saludoPrevio } from "../_compartido/respuesta.ts";
import { administradores, avisar } from "../_compartido/avisos.ts";

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return saludoPrevio();
  if (req.method !== "POST") {
    return error("Solo se acepta POST", 405);
  }

  let payload: { record?: { id?: string }; incidenteId?: string };
  try {
    payload = await req.json();
  } catch {
    return error("JSON mal formado en el body", 400);
  }

  // El trigger de BD puede mandar `{incidenteId: "..."}` directo o un payload
  // completo tipo webhook con `{record: NEW_ROW}`. Soportamos ambos para que
  // la función se pueda llamar también desde un Database Webhook del dashboard
  // de Supabase si Manuel lo configura en lugar del trigger SQL.
  const incidenteId = payload.incidenteId ?? payload.record?.id;
  if (!incidenteId) {
    return error("Falta incidenteId", 400);
  }

  const cliente = clienteServidor();

  // Leemos la fila completa, joineando con usuarios para traer el nombre
  // de quien reportó.
  const { data: incidente, error: errorQ } = await cliente
    .from("incidentes")
    .select(`
      id, condominio_id, gravedad, estado, titulo, descripcion,
      ocurrido_en, punto_acceso_id,
      reportado_por_usuario:usuarios!incidentes_reportado_por_fkey (
        nombre_completo
      )
    `)
    .eq("id", incidenteId)
    .maybeSingle();

  if (errorQ) {
    registrar("novedad_critica_lectura_falla", { detalle: errorQ.message });
    return error("No se pudo leer el incidente", 500);
  }
  if (!incidente) {
    return error("Incidente no encontrado", 404);
  }

  // Chequeo final de criticidad acá también (defensa en profundidad por si
  // el trigger de BD cambia o alguien llama esta función a mano).
  const gravedad = String(incidente.gravedad ?? "").toLowerCase();
  const estado = String(incidente.estado ?? "").toLowerCase();
  if (!(gravedad === "critica" || gravedad === "alta") || estado !== "abierto") {
    return exito({ enviado: false, razon: "no es crítica abierta" });
  }

  const admins = await administradores(cliente, incidente.condominio_id);
  if (admins.length === 0) {
    registrar("novedad_critica_sin_admins", { condominio: incidente.condominio_id });
    return exito({ enviado: false, razon: "sin admins activos" });
  }

  const quienReporto =
    (incidente.reportado_por_usuario as { nombre_completo?: string } | null)
      ?.nombre_completo ?? "Un guardia";

  const titulo = gravedad === "critica"
    ? `🚨 CRÍTICA: ${incidente.titulo}`
    : `⚠️ Novedad grave: ${incidente.titulo}`;

  const resumen = (incidente.descripcion ?? "").trim();
  const mensaje = resumen.length === 0
    ? `${quienReporto} reportó una novedad ${gravedad === "critica" ? "crítica" : "alta"}.`
    : (resumen.length > 140 ? `${resumen.slice(0, 137)}…` : resumen);

  await avisar(cliente, {
    condominio_id: incidente.condominio_id,
    usuarios: admins,
    tipo: "novedad_critica",
    titulo,
    mensaje,
    urgente: true,
    datos: {
      incidente_id: incidente.id,
      gravedad,
      // La app del admin usa `tab=2` para abrir la pestaña de Novedades
      // directo al tocar el push.
      ruta: "/administracion/informes?tab=2",
    },
  });

  return exito({ enviado: true, admins: admins.length });
});
