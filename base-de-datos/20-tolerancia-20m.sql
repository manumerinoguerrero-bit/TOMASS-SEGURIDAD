-- ============================================================================
-- Tomass Seguridad — Subir la tolerancia de escaneo QR de 5m a 20m
-- ============================================================================
-- Reportado por el usuario el 01/10/2026: los guardias no pueden escanear los
-- carteles con la tolerancia de 5m. El GPS urbano del teléfono tiene error
-- típico de 6 a 12m incluso al aire libre, y bajo techo pierde precisión;
-- quedándose a 5m la app bloqueaba la marca aunque el guardia estuviera
-- parado al lado del cartel.
--
-- HISTÓRICO DE AJUSTES
--
--   10m → 5m → 3m (muy estricto, el guardia no podía escanear ni al lado)
--   3m  → 5m (margen razonable para GPS al aire libre, resultó insuficiente)
--   5m  → 20m  ← ESTE CAMBIO
--
-- QUÉ TOCA
--
--   1. UPDATE a los puntos existentes (45 filas con valor 5): pasan a 20.
--      Esto resuelve YA el problema para los guardias que ya están en turno.
--      Sin este UPDATE, el fix en Dart solo aplicaría a sectores nuevos.
--
--   2. ALTER COLUMN SET DEFAULT 20: el DEFAULT actual era 60 (muy ancho);
--      la app Dart siempre pasaba un valor explícito así que el DEFAULT
--      nunca se usó. Lo alineamos a 20 por consistencia, por si alguna
--      vez un INSERT no pasa la columna.
--
--   3. crear_punto_control: baja el DEFAULT del parámetro p_tolerancia
--      de 60 a 20. Mismo motivo. El body se preserva EXACTO; solo cambia
--      el DEFAULT del parámetro.
--
-- QUÉ NO TOCA
--
--   * El piso de greatest(..., 15) dentro de crear_punto_control y
--     ubicar_punto_control. Son defensa contra un valor absurdamente bajo
--     y el nuevo 20 ya pasa el piso sin tocarlos.
--
--   * ubicar_punto_control: su p_tolerancia default es NULL (si viene NULL
--     la RPC NO sobreescribe el valor existente). Se queda como está.
-- ============================================================================

UPDATE public.puntos_control
   SET metros_de_tolerancia = 20
 WHERE metros_de_tolerancia <> 20;

ALTER TABLE public.puntos_control
  ALTER COLUMN metros_de_tolerancia SET DEFAULT 20;

-- Rewrite de la RPC: body EXACTO al actual (traído con pg_get_functiondef),
-- solo cambia p_tolerancia DEFAULT 60 → DEFAULT 20.
CREATE OR REPLACE FUNCTION public.crear_punto_control(
  p_nombre          text,
  p_latitud         numeric  DEFAULT NULL::numeric,
  p_longitud        numeric  DEFAULT NULL::numeric,
  p_descripcion     text     DEFAULT NULL::text,
  p_tolerancia      smallint DEFAULT 20,
  p_punto_acceso_id uuid     DEFAULT NULL::uuid
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_condo  uuid := public.mi_condominio();
  v_nombre text := trim(coalesce(p_nombre, ''));
  v_orden  smallint;
  v_id     uuid;
begin
  if not public.es_administrador() then
    raise exception 'Solo la administración puede crear puntos de control.'
      using errcode = 'insufficient_privilege';
  end if;

  if length(v_nombre) < 3 then
    raise exception 'Ponele un nombre al sector, así el guardia sabe dónde está.'
      using errcode = 'check_violation';
  end if;

  -- Si viene una garita, tiene que ser del mismo condominio.
  if p_punto_acceso_id is not null and not exists (
    select 1 from public.puntos_acceso
     where id = p_punto_acceso_id
       and condominio_id = v_condo
       and activo
  ) then
    raise exception 'Esa garita no existe o no es de tu instalación.'
      using errcode = 'insufficient_privilege';
  end if;

  select coalesce(max(orden), 0) + 1 into v_orden
    from public.puntos_control where condominio_id = v_condo;

  insert into public.puntos_control (
    condominio_id, nombre, descripcion, orden,
    latitud, longitud, metros_de_tolerancia, ubicacion_tomada_en,
    punto_acceso_id)
  values (
    v_condo, v_nombre,
    nullif(trim(coalesce(p_descripcion, '')), ''),
    v_orden, p_latitud, p_longitud,
    greatest(coalesce(p_tolerancia, 20), 15),
    case when p_latitud is not null then now() end,
    p_punto_acceso_id)
  returning id into v_id;

  return v_id;
end;
$function$;

-- Verificación posterior:
--
--   SELECT metros_de_tolerancia, count(*) FROM public.puntos_control GROUP BY 1;
--   -- debería devolver (20, 45) y nada más
--
--   SELECT column_default FROM information_schema.columns
--    WHERE table_schema='public' AND table_name='puntos_control'
--      AND column_name='metros_de_tolerancia';
--   -- debería devolver 20
