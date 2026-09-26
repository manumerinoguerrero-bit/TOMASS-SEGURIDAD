-- ============================================================================
-- Tomass Seguridad — Teléfono del guardia en el mapa en vivo
-- ============================================================================
-- El admin ve el mapa en vivo y necesita llamar al guardia en emergencia.
-- Antes tenía que ir a la agenda del celular; ahora el detalle muestra un
-- botón "Llamar" que abre tel: con el número del guardia.
--
-- Se cambia la firma del RETURNS TABLE (nueva columna), por eso DROP explícito.
-- ============================================================================

DROP FUNCTION IF EXISTS public.guardias_activos_en_vivo();

CREATE FUNCTION public.guardias_activos_en_vivo()
RETURNS TABLE(
  turno_id uuid,
  guardia_id uuid,
  guardia_nombre text,
  guardia_telefono text,
  foto_url text,
  inicio timestamp with time zone,
  punto_acceso_nombre text,
  condominio_id uuid,
  condominio_nombre text,
  ultima_geo_lat numeric,
  ultima_geo_lng numeric,
  ultima_ubicacion_en timestamp with time zone,
  minutos_desde_ultima_ubicacion integer
)
LANGUAGE sql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT
    t.id                                 AS turno_id,
    t.guardia_id                         AS guardia_id,
    u.nombre_completo                    AS guardia_nombre,
    u.telefono                           AS guardia_telefono,
    t.foto_url                           AS foto_url,
    t.inicio                             AS inicio,
    pa.nombre                            AS punto_acceso_nombre,
    c.id                                 AS condominio_id,
    c.nombre                             AS condominio_nombre,
    t.ultima_geo_lat                     AS ultima_geo_lat,
    t.ultima_geo_lng                     AS ultima_geo_lng,
    t.ultima_ubicacion_en                AS ultima_ubicacion_en,
    CASE
      WHEN t.ultima_ubicacion_en IS NULL THEN NULL
      ELSE EXTRACT(EPOCH FROM (NOW() - t.ultima_ubicacion_en))::int / 60
    END                                  AS minutos_desde_ultima_ubicacion
  FROM public.turnos t
  JOIN public.usuarios u        ON u.id = t.guardia_id
  JOIN public.condominios c     ON c.id = t.condominio_id
  LEFT JOIN public.puntos_acceso pa ON pa.id = t.punto_acceso_id
  WHERE t.cerrado_en IS NULL
    AND public.es_administrador()
    AND t.condominio_id IN (SELECT id FROM public.mis_instalaciones())
  ORDER BY c.nombre, t.inicio ASC;
$function$;

GRANT EXECUTE ON FUNCTION public.guardias_activos_en_vivo() TO authenticated;
