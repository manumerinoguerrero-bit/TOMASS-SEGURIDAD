-- ============================================================================
-- 41 · Dar salida a CUALQUIER persona adentro (incluidos los ingresos manuales)
-- ============================================================================
-- EL PROBLEMA (reportado por Manuel, 17/11/2026)
--
--   En el Colegio International (y en cualquier instalación con ingresos a
--   mano) la gente entraba, quedaba "adentro", y al darle salida SEGUÍA
--   figurando adentro. Por eso el contador de "personas dentro" crecía sin
--   parar.
--
--   La causa: la salida rápida (registrar_salida_rapida) solo sabía cerrar a
--   residentes, visitas y personal de servicio — los identifica por
--   residente_id / visita_id / personal_servicio_id. Un ingreso MANUAL no
--   tiene ninguno de esos (son NULL), así que la función no lo encontraba y el
--   botón "Marcar salida" de la pantalla no hacía nada (el código salía con un
--   `if id == null return`). La única vía era reescribir la salida a mano, y si
--   el RUT no quedaba IDÉNTICO al de la entrada, la vista v_personas_dentro los
--   tomaba como dos personas distintas y la entrada quedaba abierta para
--   siempre.
--
-- LA SOLUCIÓN
--
--   1. La vista v_personas_dentro ahora expone el id del movimiento de ENTRADA
--      (movimiento_id). Así la app sabe exactamente qué ingreso cerrar.
--
--   2. Una función nueva, registrar_salida_de_movimiento(movimiento_id),
--      clona ESE ingreso de entrada en una salida — con el mismo
--      nombre/RUT/unidad/patente. Como la salida lleva el mismo snapshot que la
--      entrada, la vista las agrupa como la misma persona y la saca de
--      "adentro". Funciona para TODOS: residentes, visitas, personal Y
--      manuales.
--
--   En la app, la salida se registra eligiendo a la persona de la lista de los
--   que están adentro (no se escribe a mano), así siempre cierra la entrada
--   correcta.
--
--   Se conserva security_invoker=true en la vista (SEG-04) y la función es
--   SECURITY DEFINER como las demás de ingreso/salida. Solo INSERTA (la tabla
--   es de solo-agregar, SEG-03).
-- ============================================================================

-- ---- 1 · La vista, ahora con movimiento_id --------------------------------
create or replace view public.v_personas_dentro
with (security_invoker = true) as
  with ultimo_movimiento as (
    select distinct on (
             m.persona_tipo,
             coalesce(
               m.residente_id::text,
               m.visita_id::text,
               m.personal_servicio_id::text,
               nullif(trim(m.rut_snapshot), ''),
               nullif(lower(trim(m.nombre_snapshot)), ''),
               m.id::text
             )
           )
           m.id,
           m.condominio_id,
           m.persona_tipo,
           m.residente_id,
           m.visita_id,
           m.personal_servicio_id,
           m.nombre_snapshot,
           m.unidad_snapshot,
           m.punto_acceso_id,
           m.tipo_acceso,
           m.sentido,
           m.patente_snapshot,
           m.ocurrido_en
      from public.movimientos_acceso m
     where m.estado = 'aprobado'
       and m.condominio_id = mi_condominio()
     order by m.persona_tipo,
              coalesce(
                m.residente_id::text,
                m.visita_id::text,
                m.personal_servicio_id::text,
                nullif(trim(m.rut_snapshot), ''),
                nullif(lower(trim(m.nombre_snapshot)), ''),
                m.id::text
              ),
              m.ocurrido_en desc
  )
  -- movimiento_id va AL FINAL a propósito: create or replace view no deja
  -- insertar una columna en el medio (renombraría las que siguen). La app lee
  -- por nombre, así que el orden no le importa.
  select u.condominio_id,
         u.persona_tipo,
         coalesce(u.residente_id, u.visita_id, u.personal_servicio_id) as persona_id,
         u.nombre_snapshot as nombre,
         u.unidad_snapshot as unidad,
         u.tipo_acceso,
         u.patente_snapshot as patente,
         u.ocurrido_en as entro_en,
         now() - u.ocurrido_en as tiempo_adentro,
         case
           when u.persona_tipo = 'visita'::text
                and (now() - u.ocurrido_en) > '12:00:00'::interval then true
           when u.persona_tipo = 'personal_servicio'::text
                and (now() - u.ocurrido_en) > '14:00:00'::interval then true
           else false
         end as estadia_inusual,
         p.nombre as entro_por,
         u.id as movimiento_id
    from ultimo_movimiento u
    left join public.puntos_acceso p on p.id = u.punto_acceso_id
   where u.sentido = 'entrada'::text;

-- ---- 2 · Salida clonando el movimiento de entrada ---------------------------
create or replace function public.registrar_salida_de_movimiento(
  p_movimiento_id uuid,
  p_id_local uuid,
  p_geo_lat numeric default null,
  p_geo_lng numeric default null
)
returns uuid
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_condominio uuid := public.mi_condominio();
  v_ent        public.movimientos_acceso%rowtype;
  v_movimiento uuid;
begin
  if v_condominio is null then
    raise exception 'No hay condominio activo.';
  end if;

  -- El ingreso a cerrar tiene que ser de ESTA instalación y estar aprobado.
  select * into v_ent
    from public.movimientos_acceso m
   where m.id = p_movimiento_id
     and m.condominio_id = v_condominio
     and m.estado = 'aprobado';

  if v_ent.id is null then
    raise exception 'No se encontró ese ingreso en tu instalación.'
      using errcode = 'insufficient_privilege';
  end if;

  if v_ent.sentido <> 'entrada' then
    raise exception 'Ese registro no es una entrada.'
      using errcode = 'check_violation';
  end if;

  -- La salida lleva el MISMO snapshot que la entrada (nombre, RUT, unidad,
  -- patente, calidad). Eso es lo que hace que v_personas_dentro las agrupe
  -- como la misma persona y la saque de "adentro".
  insert into public.movimientos_acceso (
    condominio_id, id_local, persona_tipo,
    residente_id, visita_id, personal_servicio_id,
    nombre_snapshot, unidad_snapshot, rut_snapshot, a_donde_va,
    punto_acceso_id, tipo_acceso, sentido,
    vehiculo_id, patente_snapshot, estado,
    autorizado_por_texto, calidad_ingreso, calidad_detalle,
    guardia_id, turno_id, ocurrido_en, geo_lat, geo_lng
  ) values (
    v_condominio, p_id_local, v_ent.persona_tipo,
    v_ent.residente_id, v_ent.visita_id, v_ent.personal_servicio_id,
    v_ent.nombre_snapshot, v_ent.unidad_snapshot, v_ent.rut_snapshot, v_ent.a_donde_va,
    v_ent.punto_acceso_id, v_ent.tipo_acceso, 'salida',
    v_ent.vehiculo_id, v_ent.patente_snapshot, 'aprobado',
    v_ent.autorizado_por_texto, v_ent.calidad_ingreso, v_ent.calidad_detalle,
    case when public.es_guardia() then auth.uid() end,
    public.mi_turno_activo(),
    now(), p_geo_lat, p_geo_lng
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
