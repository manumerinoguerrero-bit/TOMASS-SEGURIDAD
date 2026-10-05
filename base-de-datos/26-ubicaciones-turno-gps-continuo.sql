-- ============================================================================
-- Tomass Seguridad — Recorrido GPS continuo del turno
-- ============================================================================
-- Hasta ahora solo guardábamos la ÚLTIMA ubicación del guardia en
-- turnos.ultima_geo_* (se sobrescribía cada 3 min). Servía para el mapa en
-- vivo del admin, pero no para reconstruir POR DÓNDE pasó durante todo el
-- turno.
--
-- Esta migration crea la tabla `ubicaciones_turno` que GUARDA cada muestra
-- GPS en vez de sobrescribirla. Con eso el admin puede ver el recorrido
-- completo de cualquier turno pasado, no solo las marcas de actividad.
--
-- QUÉ CAMBIA EL DÍA 1
--   La RPC actualizar_mi_ubicacion ahora, además de UPDATE sobre turnos
--   (que sigue sirviendo para el mapa en vivo), INSERTA una fila nueva en
--   ubicaciones_turno. El rastreador del guardia NO cambia: ya llama a esa
--   misma RPC, ahora hace dos cosas en vez de una.
--
-- RETENCIÓN
--   Se purga a los 90 días. Con 30 guardias x 120 muestras/turno x 365 días,
--   serían ~1.3M filas/año si guardáramos para siempre. Con 90 días quedan
--   ~325k filas vivas, perfectamente manejable. Las marcas de ronda y los
--   accesos SÍ se guardan para siempre: esas son prueba legal, el GPS es
--   diagnóstico operativo.
--
-- SEGURIDAD
--   * Insert: solo auth.uid() del guardia dueño del turno abierto, vía la
--     RPC con SECURITY DEFINER. No hay INSERT directo.
--   * Select: via la RPC recorrido_gps_del_turno, que respeta
--     mis_instalaciones() + es_administrador() igual que recorrido_del_turno.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. TABLA
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.ubicaciones_turno (
  id         uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  turno_id   uuid        NOT NULL REFERENCES public.turnos(id) ON DELETE CASCADE,
  guardia_id uuid        NOT NULL REFERENCES public.usuarios(id) ON DELETE CASCADE,
  cuando     timestamptz NOT NULL DEFAULT NOW(),
  lat        numeric     NOT NULL,
  lng        numeric     NOT NULL
);

-- Índice para la query típica: traer el recorrido de un turno en orden.
CREATE INDEX IF NOT EXISTS idx_ubicaciones_turno_turno_cuando
  ON public.ubicaciones_turno (turno_id, cuando);

-- Índice para la purga diaria (filtra por cuando < NOW() - 90d).
CREATE INDEX IF NOT EXISTS idx_ubicaciones_turno_cuando
  ON public.ubicaciones_turno (cuando);

-- ----------------------------------------------------------------------------
-- 2. RLS
-- ----------------------------------------------------------------------------
-- Nadie accede a la tabla directo. Las lecturas van por la RPC
-- recorrido_gps_del_turno (SECURITY DEFINER), los inserts por
-- actualizar_mi_ubicacion (ya SECURITY DEFINER).
ALTER TABLE public.ubicaciones_turno ENABLE ROW LEVEL SECURITY;

-- No creamos policies: con RLS habilitado y sin policies, PostgREST devuelve
-- 0 filas y no deja insertar. Las RPCs se ejecutan como superuser (SECURITY
-- DEFINER) así que no les afecta.

-- ----------------------------------------------------------------------------
-- 3. EXTENDER actualizar_mi_ubicacion
-- ----------------------------------------------------------------------------
-- Hace lo mismo que antes (UPDATE sobre turnos para el mapa en vivo) y
-- además INSERTA una muestra en ubicaciones_turno. Si no hay turno abierto,
-- no hace nada (como antes).

CREATE OR REPLACE FUNCTION public.actualizar_mi_ubicacion(
  p_lat numeric, p_lng numeric
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_guardia_id uuid := auth.uid();
  v_turno_id   uuid;
BEGIN
  IF v_guardia_id IS NULL THEN
    RAISE EXCEPTION 'Sin sesión activa.' USING errcode = 'insufficient_privilege';
  END IF;

  IF p_lat IS NULL OR p_lng IS NULL THEN
    RAISE EXCEPTION 'Faltan las coordenadas.' USING errcode = 'check_violation';
  END IF;

  -- UPDATE sobre el turno abierto (para el mapa en vivo).
  -- Captura el turno_id para el INSERT siguiente.
  UPDATE public.turnos
  SET
    ultima_geo_lat = p_lat,
    ultima_geo_lng = p_lng,
    ultima_ubicacion_en = NOW()
  WHERE guardia_id = v_guardia_id
    AND cerrado_en IS NULL
  RETURNING id INTO v_turno_id;

  -- INSERT en el historial GPS si hay turno abierto. Si no, salimos
  -- silenciosos (como antes) para no romper el timer entre cerrar y abrir
  -- turno.
  IF v_turno_id IS NOT NULL THEN
    INSERT INTO public.ubicaciones_turno (turno_id, guardia_id, lat, lng)
    VALUES (v_turno_id, v_guardia_id, p_lat, p_lng);
  END IF;
END;
$$;

-- ----------------------------------------------------------------------------
-- 4. RPC DE LECTURA: recorrido_gps_del_turno
-- ----------------------------------------------------------------------------
-- Separada de recorrido_del_turno (actividad) por tres motivos:
--   * El UI puede traer ambas en paralelo con providers distintos.
--   * Si un día queremos cachear la actividad y refetchear solo el GPS
--     (ej. turno abierto en vivo), no se mezclan.
--   * Devuelve 120+ filas por turno — mejor paginar o filtrar sin tocar la
--     query de actividad.
CREATE OR REPLACE FUNCTION public.recorrido_gps_del_turno(p_turno_id uuid)
RETURNS TABLE (
  cuando timestamptz,
  lat    numeric,
  lng    numeric
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
  SELECT u.cuando, u.lat, u.lng
    FROM public.ubicaciones_turno u
    JOIN public.turnos t ON t.id = u.turno_id
   WHERE u.turno_id = p_turno_id
     AND public.es_administrador()
     AND t.condominio_id IN (SELECT id FROM public.mis_instalaciones())
   ORDER BY u.cuando;
$$;

GRANT EXECUTE ON FUNCTION public.recorrido_gps_del_turno(uuid) TO authenticated;

-- ----------------------------------------------------------------------------
-- 5. PURGA AUTOMÁTICA A LOS 90 DÍAS
-- ----------------------------------------------------------------------------
-- Función que borra ubicaciones viejas. Se ejecuta diaria vía pg_cron a
-- las 03:30 America/Santiago (06:30 UTC), horario sin actividad.
CREATE OR REPLACE FUNCTION public.purgar_ubicaciones_viejas()
RETURNS int
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_borradas int;
BEGIN
  DELETE FROM public.ubicaciones_turno
   WHERE cuando < NOW() - INTERVAL '90 days';
  GET DIAGNOSTICS v_borradas = ROW_COUNT;
  RETURN v_borradas;
END;
$$;

-- Programar la purga diaria. Si pg_cron no está disponible esto falla
-- silencioso (DO block con EXCEPTION).
DO $$
BEGIN
  PERFORM cron.schedule(
    'purgar_ubicaciones_turno_diario',
    '30 6 * * *',  -- 03:30 Santiago = 06:30 UTC
    'SELECT public.purgar_ubicaciones_viejas();'
  );
EXCEPTION
  WHEN undefined_function OR undefined_schema THEN
    RAISE NOTICE 'pg_cron no disponible, purga manual requerida.';
  WHEN unique_violation THEN
    -- Job ya existe, no es error.
    NULL;
END;
$$;

-- ----------------------------------------------------------------------------
-- 6. VERIFICACIÓN
-- ----------------------------------------------------------------------------
-- SELECT count(*) FROM public.ubicaciones_turno;
-- SELECT * FROM cron.job WHERE jobname = 'purgar_ubicaciones_turno_diario';
