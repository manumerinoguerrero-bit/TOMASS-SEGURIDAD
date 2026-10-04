-- ============================================================================
-- Tomass Seguridad — Recorrido de actividad de un turno
-- ============================================================================
-- Devuelve los puntos con coordenadas conocidas DURANTE el turno, ordenados
-- cronológicamente. Sirve para dibujar un mapa que muestra "estos son los
-- lugares donde el guardia hizo algo mientras estuvo a cargo".
--
-- No es un recorrido GPS continuo (eso requeriría una tabla aparte de
-- muestras cada X minutos — ver nota al final). Es un recorrido DE ACTIVIDAD:
-- cada punto es una acción identificable que dejó rastro.
--
-- Tipos de punto:
--   'apertura'      → donde abrió el turno (turnos.geo_*)
--   'marca_ronda'   → cada escaneo de cartel durante una ronda del turno
--   'acceso'        → cada ingreso/salida registrado dentro del turno
--   'ultima_vista'  → última ubicación conocida del rastreador, si difiere
--                      ≥ 50 m de la apertura (si no, aporta ruido)
--
-- SEGURIDAD
--   SECURITY DEFINER + chequeo con es_administrador() + filtro por
--   mis_instalaciones(). Un guardia que llame a esta RPC por error
--   recibe tabla vacía. Un admin ve los turnos solo de las instalaciones
--   donde tiene acceso (incluyendo la activa y las delegadas por
--   administra_instalaciones).
-- ============================================================================

CREATE OR REPLACE FUNCTION public.recorrido_del_turno(p_turno_id uuid)
RETURNS TABLE (
  tipo            text,
  cuando          timestamptz,
  lat             numeric,
  lng             numeric,
  descripcion     text,
  orden_dibujo    integer
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
  WITH t AS (
    SELECT id, condominio_id, guardia_id, inicio, cerrado_en,
           geo_lat, geo_lng,
           ultima_geo_lat, ultima_geo_lng, ultima_ubicacion_en
      FROM public.turnos
     WHERE id = p_turno_id
       AND public.es_administrador()
       AND condominio_id IN (SELECT id FROM public.mis_instalaciones())
  ),
  puntos AS (
    SELECT 'apertura'::text AS tipo,
           t.inicio         AS cuando,
           t.geo_lat        AS lat,
           t.geo_lng        AS lng,
           'Abrió el turno'::text AS descripcion,
           0 AS orden_dibujo
      FROM t
     WHERE t.geo_lat IS NOT NULL AND t.geo_lng IS NOT NULL
    UNION ALL
    SELECT 'marca_ronda'::text,
           m.marcado_en,
           m.geo_lat,
           m.geo_lng,
           'Marcó: ' || coalesce(pc.nombre, 'sector'),
           1
      FROM public.marcas_de_ronda m
      JOIN public.rondas r         ON r.id = m.ronda_id
      JOIN public.puntos_control pc ON pc.id = m.punto_control_id
      JOIN t                        ON t.id = r.turno_id
     WHERE m.geo_lat IS NOT NULL AND m.geo_lng IS NOT NULL
    UNION ALL
    SELECT 'acceso'::text,
           ma.ocurrido_en,
           ma.geo_lat,
           ma.geo_lng,
           CASE WHEN ma.sentido = 'entrada' THEN '→ Entrada'
                ELSE '← Salida'
                END
           || ' · ' || coalesce(ma.nombre_snapshot, 'sin nombre')
           || CASE WHEN ma.estado = 'denegado'
                   THEN ' (DENEGADO)' ELSE '' END,
           2
      FROM public.movimientos_acceso ma
      JOIN t ON t.id = ma.turno_id
     WHERE ma.geo_lat IS NOT NULL AND ma.geo_lng IS NOT NULL
    UNION ALL
    SELECT 'ultima_vista'::text,
           t.ultima_ubicacion_en,
           t.ultima_geo_lat,
           t.ultima_geo_lng,
           'Última señal GPS'::text,
           3
      FROM t
     WHERE t.ultima_geo_lat IS NOT NULL
       AND t.ultima_geo_lng IS NOT NULL
       AND (t.geo_lat IS NULL
            OR public.metros_entre(t.geo_lat, t.geo_lng,
                                    t.ultima_geo_lat, t.ultima_geo_lng) > 50)
  )
  SELECT tipo, cuando, lat, lng, descripcion, orden_dibujo
    FROM puntos
   ORDER BY cuando NULLS LAST, orden_dibujo;
$$;

GRANT EXECUTE ON FUNCTION public.recorrido_del_turno(uuid) TO authenticated;

-- Nota: si en el futuro queremos un recorrido GPS CONTINUO (línea con una
-- muestra cada 3 minutos durante todo el turno), hace falta una tabla
-- aparte tipo ubicaciones_turno (turno_id, cuando, lat, lng) y modificar
-- RastreadorGuardia para INSERTAR en vez de solo UPDATE sobre turnos.
-- Por ahora el recorrido de actividad cubre el caso 90% (el admin quiere
-- ver POR DÓNDE anduvo el guardia haciendo cosas, no la secuencia GPS
-- precisa).
