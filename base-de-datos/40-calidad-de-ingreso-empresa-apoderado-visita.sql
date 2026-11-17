-- ============================================================================
-- 40 · Calidad del ingreso: Empresa / Apoderado / Visita (+ detalle)
-- ============================================================================
-- Pedido por Manuel (17/11/2026): al anotar un ingreso a mano, además del
-- nombre y el RUT, poder decir EN CALIDAD DE QUÉ entra la persona —
-- Empresa (un contratista/proveedor), Apoderado (de un colegio) o Visita
-- (de un residente) — y un detalle libre (nombre de la empresa, de qué alumno
-- es apoderado, o a qué residente visita).
--
-- Es OPCIONAL: el guardia lo completa si aplica; si no, registra igual.
--
-- Se guarda en dos columnas nuevas de movimientos_acceso:
--   · calidad_ingreso   → 'empresa' | 'apoderado' | 'visita' (o NULL)
--   · calidad_detalle   → texto libre (o NULL)
--
-- La función registrar_acceso_manual se re-crea con dos parámetros nuevos al
-- final (con default NULL), así la app vieja (que no los manda) sigue andando
-- sin cambios. HAY QUE DROPEAR la versión anterior antes de crear la nueva:
-- si no, Postgres queda con dos sobrecargas y una llamada sin los parámetros
-- nuevos falla con "function is not unique".
-- ============================================================================

-- ---- 1 · Columnas nuevas ----------------------------------------------------
alter table public.movimientos_acceso
  add column if not exists calidad_ingreso text,
  add column if not exists calidad_detalle text;

alter table public.movimientos_acceso
  drop constraint if exists movimientos_acceso_calidad_ingreso_chk;
alter table public.movimientos_acceso
  add constraint movimientos_acceso_calidad_ingreso_chk
  check (calidad_ingreso is null
         or calidad_ingreso in ('empresa', 'apoderado', 'visita'));

-- ---- 2 · Re-crear la función con los dos parámetros nuevos -------------------
drop function if exists public.registrar_acceso_manual(
  uuid, uuid, text, text, text, text, text, text, text, text, text, uuid, timestamptz);

create or replace function public.registrar_acceso_manual(
  p_id_local uuid,
  p_punto_acceso_id uuid,
  p_nombre text,
  p_tipo_acceso text,
  p_sentido text,
  p_rut text default null,
  p_a_donde_va text default null,
  p_autorizado_por text default null,
  p_patente text default null,
  p_foto_url text default null,
  p_observacion text default null,
  p_residente_id uuid default null,
  p_ocurrido_en timestamptz default null,
  p_calidad text default null,
  p_calidad_detalle text default null
)
returns uuid
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_condominio uuid;
  v_turno      uuid;
  v_inicio     timestamptz;
  v_guardia    uuid := auth.uid();
  v_nombre     text := trim(coalesce(p_nombre, ''));
  v_rut        text := trim(coalesce(p_rut, ''));
  v_donde      text := trim(coalesce(p_a_donde_va, ''));
  v_autoriza   text := trim(coalesce(p_autorizado_por, ''));
  v_patente    text := upper(trim(coalesce(p_patente, '')));
  v_calidad    text := nullif(trim(coalesce(p_calidad, '')), '');
  v_calidad_detalle text := nullif(trim(coalesce(p_calidad_detalle, '')), '');
  v_cuando     timestamptz;
  v_movimiento uuid;
begin
  -- ---- Lo que no puede faltar ----
  if length(v_nombre) < 3 then
    raise exception 'Falta el nombre de quien pasa.'
      using errcode = 'check_violation';
  end if;

  if length(v_rut) < 6 then
    raise exception 'Falta el RUT. Es lo que identifica a la persona en el registro.'
      using errcode = 'check_violation';
  end if;

  if length(v_donde) < 2 then
    raise exception 'Falta anotar a dónde se dirige.'
      using errcode = 'check_violation';
  end if;

  if length(v_autoriza) < 3 then
    raise exception 'Falta anotar quién autoriza el ingreso.'
      using errcode = 'check_violation';
  end if;

  if p_tipo_acceso not in ('peatonal','vehicular') then
    raise exception 'Hay que decir si pasa a pie o en vehículo.'
      using errcode = 'check_violation';
  end if;

  if p_sentido not in ('entrada','salida') then
    raise exception 'Hay que decir si entra o sale.'
      using errcode = 'check_violation';
  end if;

  if p_tipo_acceso = 'vehicular' and length(v_patente) < 4 then
    raise exception 'Falta la patente del vehículo.'
      using errcode = 'check_violation';
  end if;

  -- La calidad es OPCIONAL, pero si viene tiene que ser una de las tres.
  if v_calidad is not null and v_calidad not in ('empresa','apoderado','visita') then
    raise exception 'La calidad del ingreso tiene que ser empresa, apoderado o visita.'
      using errcode = 'check_violation';
  end if;

  -- ---- La garita tiene que ser de SU instalación ----
  select pa.condominio_id into v_condominio
    from public.puntos_acceso pa
   where pa.id = p_punto_acceso_id
     and pa.condominio_id = public.mi_condominio()
     and pa.activo;

  if v_condominio is null then
    raise exception 'Esa garita no existe o no es de tu instalación.'
      using errcode = 'insufficient_privilege';
  end if;

  -- ---- Tiene que tener turno abierto ----
  select t.id, t.inicio into v_turno, v_inicio
    from public.turnos t
   where t.guardia_id = v_guardia
     and t.cerrado_en is null
   order by t.inicio desc
   limit 1;

  if v_turno is null then
    raise exception 'Tenés que abrir tu turno antes de anotar ingresos.'
      using errcode = 'insufficient_privilege';
  end if;

  -- ---- La hora del ingreso ----
  v_cuando := coalesce(p_ocurrido_en, now());

  if v_cuando > now() + interval '1 minute' then
    raise exception 'La hora del ingreso no puede ser en el futuro.'
      using errcode = 'check_violation';
  end if;

  if v_cuando < v_inicio then
    raise exception 'La hora del ingreso no puede ser anterior al inicio de tu turno.'
      using errcode = 'check_violation';
  end if;

  insert into public.movimientos_acceso (
    condominio_id, id_local, persona_tipo, residente_id,
    nombre_snapshot, rut_snapshot, unidad_snapshot, a_donde_va,
    autorizado_por_texto, foto_url,
    punto_acceso_id, tipo_acceso, sentido, patente_snapshot,
    estado, motivo_denegacion, guardia_id, turno_id, ocurrido_en,
    calidad_ingreso, calidad_detalle
  ) values (
    v_condominio, p_id_local,
    case when p_residente_id is null then 'manual' else 'residente' end,
    p_residente_id,
    v_nombre, v_rut, nullif(v_donde, ''), nullif(v_donde, ''),
    v_autoriza, nullif(trim(coalesce(p_foto_url, '')), ''),
    p_punto_acceso_id, p_tipo_acceso, p_sentido, nullif(v_patente, ''),
    'aprobado', nullif(trim(coalesce(p_observacion, '')), ''),
    v_guardia, v_turno, v_cuando,
    v_calidad, v_calidad_detalle
  )
  on conflict (id_local) do nothing
  returning id into v_movimiento;

  if v_movimiento is null then
    select id into v_movimiento
      from public.movimientos_acceso where id_local = p_id_local;
  end if;

  return v_movimiento;
end;
$function$;
