-- ============================================================================
-- Tomass Seguridad — Informe de rondas por ACTIVIDAD, no por fecha de inicio
-- ============================================================================
-- QUÉ PASABA
--
--   Al pedir el informe del 23/09 en Milagros del Cerro Grande, el mapa salía
--   vacío. Investigando: Ivan había abierto una ronda el 07/09 que quedó
--   colgada 16 días, y anoche 23/09 la cerró después de escanear los 6
--   sectores entre las 23:12 y las 23:14. Las 6 marcas estaban CLARAMENTE
--   en el 23/09 con GPS válido, pero la RPC informe_de_rondas y
--   detalle_de_rondas filtraban por r.inicio (07/09) — que no cae en el
--   rango 23/09 a 23/09 — así que la ronda no aparecía y el mapa quedaba
--   sin marcas para pintar.
--
--   El bug se dispara CADA vez que un guardia deja una ronda abierta más de
--   un día. Con la app actual pasa seguido (el guardia se olvida de cerrarla
--   y cuando vuelve al turno siguiente aparece la misma ronda "en curso").
--
-- SOLUCIÓN
--
--   Filtrar por ACTIVIDAD dentro del rango, no por inicio. Una ronda aparece
--   en el informe si:
--     * Su inicio cae en el rango, O
--     * Su cierre cae en el rango, O
--     * Alguna de sus marcas cae en el rango.
--
--   Para el detalle_de_rondas (marcas individuales), el filtro se hace sobre
--   marca.marcado_en directamente: si un guardia hace 3 marcas el 23/09 y 3
--   el 24/09, el informe del 23/09 muestra las 3 primeras y el del 24/09 las
--   otras 3.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.informe_de_rondas(
  p_dias integer DEFAULT 7,
  p_desde timestamp with time zone DEFAULT NULL,
  p_hasta timestamp with time zone DEFAULT NULL
)
RETURNS TABLE(
  ronda_id uuid,
  guardia text,
  inicio timestamp with time zone,
  cerrada_en timestamp with time zone,
  minutos integer,
  marcados integer,
  total integer,
  completa boolean,
  marcas_lejanas integer,
  horas_desde_la_anterior numeric,
  se_paso_del_limite boolean,
  notas text
)
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
  WITH rango AS (
    SELECT
      COALESCE(p_desde, NOW() - make_interval(days => p_dias)) AS desde,
      COALESCE(p_hasta, NOW())                                  AS hasta
  ),
  limite AS (
    SELECT COALESCE(NULLIF(minutos_entre_rondas, 0), 120) AS tope
      FROM public.condominios WHERE id = public.mi_condominio()
  ),
  cuantos_puntos AS (
    SELECT COUNT(*)::int AS total FROM public.puntos_control
     WHERE condominio_id = public.mi_condominio() AND activo
  ),
  base AS (
    SELECT r.id, u.nombre_completo, r.inicio, r.cerrada_en, r.notas, r.guardia_id,
           LAG(r.inicio) OVER (PARTITION BY r.guardia_id ORDER BY r.inicio) AS anterior
      FROM public.rondas r
      JOIN public.usuarios u ON u.id = r.guardia_id
      CROSS JOIN rango
     WHERE r.condominio_id = public.mi_condominio()
       AND (
         -- Ronda que arrancó en el rango
         (r.inicio >= rango.desde AND r.inicio <= rango.hasta)
         OR
         -- Ronda que cerró en el rango (arrancó antes)
         (r.cerrada_en IS NOT NULL
          AND r.cerrada_en >= rango.desde
          AND r.cerrada_en <= rango.hasta)
         OR
         -- Ronda con actividad en el rango (marcas dentro), aunque el inicio
         -- y el cierre estén fuera. Este es el caso que hoy se perdía.
         EXISTS (
           SELECT 1 FROM public.marcas_de_ronda m2
            WHERE m2.ronda_id = r.id
              AND m2.marcado_en >= rango.desde
              AND m2.marcado_en <= rango.hasta
         )
       )
  )
  SELECT b.id,
         b.nombre_completo::text,
         b.inicio,
         b.cerrada_en,
         (EXTRACT(EPOCH FROM (COALESCE(b.cerrada_en, NOW()) - b.inicio)) / 60)::int,
         (SELECT COUNT(*)::int FROM public.marcas_de_ronda m WHERE m.ronda_id = b.id),
         (SELECT total FROM cuantos_puntos),
         (SELECT COUNT(*) FROM public.marcas_de_ronda m WHERE m.ronda_id = b.id)
           >= (SELECT total FROM cuantos_puntos),
         (SELECT COUNT(*)::int
            FROM public.marcas_de_ronda m
            JOIN public.puntos_control pc ON pc.id = m.punto_control_id
           WHERE m.ronda_id = b.id
             AND pc.latitud IS NOT NULL AND m.geo_lat IS NOT NULL
             AND public.metros_entre(pc.latitud, pc.longitud, m.geo_lat, m.geo_lng)
                 > pc.metros_de_tolerancia),
         CASE WHEN b.anterior IS NULL THEN NULL
              ELSE ROUND((EXTRACT(EPOCH FROM (b.inicio - b.anterior)) / 3600)::numeric, 1)
         END,
         CASE WHEN b.anterior IS NULL THEN false
              ELSE (EXTRACT(EPOCH FROM (b.inicio - b.anterior)) / 60) > (SELECT tope FROM limite)
         END,
         b.notas
    FROM base b
   ORDER BY b.inicio DESC;
$function$;


CREATE OR REPLACE FUNCTION public.detalle_de_rondas(
  p_dias integer DEFAULT 7,
  p_desde timestamp with time zone DEFAULT NULL,
  p_hasta timestamp with time zone DEFAULT NULL
)
RETURNS TABLE(
  ronda_id uuid,
  guardia text,
  ronda_inicio timestamp with time zone,
  ronda_cerrada timestamp with time zone,
  ronda_notas text,
  sector text,
  sector_orden smallint,
  marcado_en timestamp with time zone,
  novedad text,
  sector_lat numeric,
  sector_lng numeric,
  tolerancia smallint,
  marca_lat numeric,
  marca_lng numeric,
  metros_de_lejos numeric,
  lejos boolean
)
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
  WITH rango AS (
    SELECT
      COALESCE(p_desde, NOW() - make_interval(days => p_dias)) AS desde,
      COALESCE(p_hasta, NOW())                                  AS hasta
  )
  SELECT r.id,
         u.nombre_completo::text,
         r.inicio,
         r.cerrada_en,
         r.notas::text,
         pc.nombre::text,
         pc.orden,
         m.marcado_en,
         m.novedad::text,
         pc.latitud,
         pc.longitud,
         pc.metros_de_tolerancia,
         m.geo_lat,
         m.geo_lng,
         public.metros_entre(pc.latitud, pc.longitud, m.geo_lat, m.geo_lng),
         COALESCE(
           public.metros_entre(pc.latitud, pc.longitud, m.geo_lat, m.geo_lng)
             > pc.metros_de_tolerancia,
           false)
    FROM public.rondas r
    JOIN public.usuarios u        ON u.id = r.guardia_id
    JOIN public.marcas_de_ronda m ON m.ronda_id = r.id
    JOIN public.puntos_control pc ON pc.id = m.punto_control_id
    CROSS JOIN rango
   WHERE r.condominio_id = public.mi_condominio()
     -- Filtramos por MARCADO_EN, no por r.inicio. Así el detalle del 23/09
     -- muestra exactamente las marcas del 23/09, aunque la ronda haya
     -- arrancado el 07/09.
     AND m.marcado_en >= rango.desde
     AND m.marcado_en <= rango.hasta
   ORDER BY r.inicio DESC, m.marcado_en;
$function$;
