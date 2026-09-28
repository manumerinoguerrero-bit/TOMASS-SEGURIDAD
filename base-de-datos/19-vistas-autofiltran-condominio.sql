-- ============================================================================
-- Tomass Seguridad — Vistas del guardia auto-filtran por mi_condominio()
-- ============================================================================
-- Reportado el 27/09/2026: Miguel Sotelo (guardia del Condominio
-- Encomenderos) al abrir la pestaña Encomiendas veía paquetes del
-- Condominio Milagros del Cerro Grande. En Inventario, veía TODAS las
-- encomiendas de todos los condominios. El bug reprodujo exactamente el
-- mismo patrón del 14/09 (ultimosAccesos / personasDentro) — varias
-- queries del servicio_guardia dependían solo de RLS y varios llamadores
-- se olvidaron de agregar .eq('condominio_id', ...) en el cliente.
--
-- Este archivo aplica DEFENSA EN PROFUNDIDAD: agrega el filtro
-- WHERE ... = mi_condominio() DENTRO de las 4 vistas. Así aunque un
-- futuro llamador se olvide, la vista limita a la instalación activa
-- por sí sola.
--
-- Vistas blindadas:
--   * v_paquetes_porteria                      (encomiendas + inventario)
--   * v_personas_dentro                        (quién está adentro)
--   * v_solicitudes_vehiculares_pendientes     (cola de autos)
--   * v_resumen_condominio                     (números del dashboard)
-- ============================================================================

CREATE OR REPLACE VIEW public.v_paquetes_porteria AS
SELECT p.id,
       p.condominio_id,
       p.numero_seguimiento,
       p.empresa_courier,
       p.descripcion,
       p.foto_url,
       p.recibido_en,
       EXTRACT(day FROM now() - p.recibido_en)::integer AS dias_en_porteria,
       (now() - p.recibido_en) > (c.dias_alerta_paquete::double precision
         * '1 day'::interval) AS alerta_antiguedad,
       c.dias_alerta_paquete,
       r.id AS residente_id,
       COALESCE(r.nombre_completo, p.destinatario_texto) AS residente,
       r.telefono AS residente_telefono,
       COALESCE(un.numero, p.unidad_texto) AS unidad,
       un.torre,
       g.nombre_completo AS recibido_por,
       p.residente_id IS NULL AS destinatario_a_mano
  FROM paquetes p
  JOIN condominios c ON c.id = p.condominio_id
  LEFT JOIN usuarios r ON r.id = p.residente_id
  LEFT JOIN unidades un ON un.id = p.unidad_id
  LEFT JOIN usuarios g ON g.id = p.guardia_receptor_id
 WHERE p.estado = 'en_porteria'
   AND p.condominio_id = public.mi_condominio()
 ORDER BY p.recibido_en;


CREATE OR REPLACE VIEW public.v_personas_dentro AS
WITH ultimo_movimiento AS (
  SELECT DISTINCT ON (m.persona_tipo,
                      (COALESCE(m.residente_id, m.visita_id, m.personal_servicio_id)))
    m.id,
    m.condominio_id,
    m.id_local,
    m.persona_tipo,
    m.residente_id,
    m.visita_id,
    m.personal_servicio_id,
    m.nombre_snapshot,
    m.unidad_snapshot,
    m.punto_acceso_id,
    m.tipo_acceso,
    m.sentido,
    m.vehiculo_id,
    m.patente_snapshot,
    m.estado,
    m.motivo_denegacion,
    m.guardia_id,
    m.turno_id,
    m.dispositivo_id,
    m.ocurrido_en,
    m.creado_en,
    m.sincronizado_offline,
    m.geo_lat,
    m.geo_lng
  FROM movimientos_acceso m
  WHERE m.estado = 'aprobado'
    AND m.condominio_id = public.mi_condominio()
  ORDER BY m.persona_tipo,
           (COALESCE(m.residente_id, m.visita_id, m.personal_servicio_id)),
           m.ocurrido_en DESC
)
SELECT u.condominio_id,
       u.persona_tipo,
       COALESCE(u.residente_id, u.visita_id, u.personal_servicio_id) AS persona_id,
       u.nombre_snapshot AS nombre,
       u.unidad_snapshot AS unidad,
       u.tipo_acceso,
       u.patente_snapshot AS patente,
       u.ocurrido_en AS entro_en,
       now() - u.ocurrido_en AS tiempo_adentro,
       CASE
         WHEN u.persona_tipo = 'visita' AND (now() - u.ocurrido_en) > '12:00:00'::interval THEN true
         WHEN u.persona_tipo = 'personal_servicio' AND (now() - u.ocurrido_en) > '14:00:00'::interval THEN true
         ELSE false
       END AS estadia_inusual,
       p.nombre AS entro_por
  FROM ultimo_movimiento u
  JOIN puntos_acceso p ON p.id = u.punto_acceso_id
 WHERE u.sentido = 'entrada';


CREATE OR REPLACE VIEW public.v_solicitudes_vehiculares_pendientes AS
SELECT s.id AS solicitud_id,
       s.condominio_id,
       s.punto_acceso_id,
       pa.nombre AS punto_acceso,
       s.sentido,
       s.solicitado_en,
       s.expira_en,
       EXTRACT(epoch FROM now() - s.solicitado_en)::integer AS segundos_esperando,
       r.id AS residente_id,
       r.nombre_completo AS residente,
       r.foto_url AS residente_foto_url,
       r.telefono AS residente_telefono,
       un.numero AS unidad,
       un.torre,
       v.id AS vehiculo_id,
       v.patente,
       v.marca,
       v.modelo,
       v.color,
       v.foto_url AS vehiculo_foto_url
  FROM solicitudes_vehiculares s
  JOIN usuarios r ON r.id = s.residente_id
  JOIN vehiculos v ON v.id = s.vehiculo_id
  JOIN puntos_acceso pa ON pa.id = s.punto_acceso_id
  LEFT JOIN unidades un ON un.id = r.unidad_id
 WHERE s.estado = 'pendiente'
   AND s.expira_en > now()
   AND s.condominio_id = public.mi_condominio()
 ORDER BY s.solicitado_en;


CREATE OR REPLACE VIEW public.v_resumen_condominio AS
SELECT id AS condominio_id,
       nombre AS condominio,
       (SELECT count(*) FROM movimientos_acceso m
         WHERE m.condominio_id = c.id
           AND m.ocurrido_en >= (date_trunc('day', (now() AT TIME ZONE c.zona_horaria))
                                 AT TIME ZONE c.zona_horaria)
           AND m.sentido = 'entrada'
           AND m.estado = 'aprobado') AS accesos_hoy,
       (SELECT count(*) FROM solicitudes_vehiculares s
         WHERE s.condominio_id = c.id
           AND s.estado = 'pendiente'
           AND s.expira_en > now()) AS autos_esperando,
       (SELECT count(*) FROM paquetes p
         WHERE p.condominio_id = c.id
           AND p.estado = 'en_porteria') AS paquetes_en_porteria,
       (SELECT count(*) FROM paquetes p
         WHERE p.condominio_id = c.id
           AND p.estado = 'en_porteria'
           AND (now() - p.recibido_en) > (c.dias_alerta_paquete::double precision
                                          * '1 day'::interval)) AS paquetes_atrasados,
       (SELECT count(*) FROM vehiculos v
         WHERE v.condominio_id = c.id
           AND v.estado = 'pendiente') AS vehiculos_por_aprobar,
       (SELECT count(*) FROM usuarios u
         WHERE u.condominio_id = c.id
           AND u.rol = 'residente'
           AND u.estado = 'activo') AS residentes_activos,
       (SELECT count(*) FROM unidades un
         WHERE un.condominio_id = c.id) AS unidades,
       (SELECT count(*) FROM turnos t
         WHERE t.condominio_id = c.id
           AND t.cerrado_en IS NULL) AS guardias_en_turno,
       (SELECT count(*) FROM incidentes i
         WHERE i.condominio_id = c.id
           AND i.estado <> 'cerrado') AS incidentes_abiertos,
       (SELECT count(*) FROM visitas vi
         WHERE vi.condominio_id = c.id
           AND vi.estado = 'esperando_aprobacion') AS visitas_esperando_aprobacion,
       (SELECT count(*) FROM movimientos_acceso m
         WHERE m.condominio_id = c.id
           AND m.estado = 'aprobado'
           AND m.sentido = 'entrada'
           AND m.ocurrido_en >= (date_trunc('day', (now() AT TIME ZONE c.zona_horaria))
                                 AT TIME ZONE c.zona_horaria)) AS personas_dentro
  FROM condominios c
 WHERE c.id = public.mi_condominio();
