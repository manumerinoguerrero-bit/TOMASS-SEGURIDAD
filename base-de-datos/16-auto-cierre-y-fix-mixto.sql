-- ============================================================================
-- Tomass Seguridad — Auto-cierre de rondas/turnos + fix garitas mixtas
-- ============================================================================
-- Dos fixes agrupados de la auditoría del 25/09/2026:
--
-- 1) FIX: registrar_movimiento con garitas 'mixto'
--    puntos_acceso.tipo acepta 'mixto' pero movimientos_acceso.tipo_acceso
--    solo acepta 'peatonal' o 'vehicular'. registrar_movimiento copiaba
--    pa.tipo directo al INSERT, con lo que garitas mixtas (los colegios
--    tienen varias) romperían la RPC con violación de CHECK. Se traduce:
--    si hay vehiculo -> vehicular, si no -> peatonal.
--
-- 2) FEATURE: auto-cierre de rondas y turnos colgados
--    Un guardia se olvida de cerrar la ronda y queda abierta días. Nos
--    pasó con Ivan (16 días) y rompió los informes. Ahora la función
--    expirar_registros_vencidos (que corre en cron cada 5 min) también
--    cierra rondas > 24h y turnos > 12h, con nota "Auto-cerrado por el
--    sistema" visible en el informe.
-- ============================================================================


-- ============================================================================
-- FIX 1: registrar_movimiento traduce 'mixto'
-- ============================================================================

CREATE OR REPLACE FUNCTION public.registrar_movimiento(
  p_id_local uuid,
  p_persona_tipo text,
  p_persona_id uuid,
  p_punto_acceso_id uuid,
  p_sentido text,
  p_estado text DEFAULT 'aprobado',
  p_vehiculo_id uuid DEFAULT NULL,
  p_motivo_denegacion text DEFAULT NULL,
  p_ocurrido_en timestamp with time zone DEFAULT NULL,
  p_offline boolean DEFAULT false,
  p_dispositivo_id uuid DEFAULT NULL,
  p_geo_lat numeric DEFAULT NULL,
  p_geo_lng numeric DEFAULT NULL,
  p_guardia_id uuid DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_condominio  uuid;
  v_tipo_acceso text;
  v_nombre      text;
  v_unidad      text;
  v_patente     text;
  v_movimiento  uuid;
begin
  select pa.condominio_id, pa.tipo into v_condominio, v_tipo_acceso
    from public.puntos_acceso pa
   where pa.id = p_punto_acceso_id and pa.activo;

  if v_condominio is null then
    raise exception 'El punto de acceso indicado no existe o esta desactivado.';
  end if;

  -- Traducir 'mixto' a peatonal/vehicular segun venga vehiculo o no.
  if v_tipo_acceso = 'mixto' then
    if p_vehiculo_id is not null then
      v_tipo_acceso := 'vehicular';
    else
      v_tipo_acceso := 'peatonal';
    end if;
  end if;

  if p_persona_tipo = 'residente' then
    select u.nombre_completo,
           coalesce(un.numero, '') || coalesce(' ' || nullif(un.torre, ''), '')
      into v_nombre, v_unidad
      from public.usuarios u
      left join public.unidades un on un.id = u.unidad_id
     where u.id = p_persona_id;
  elsif p_persona_tipo = 'visita' then
    select vi.nombre_visitante,
           coalesce(un.numero, '') || coalesce(' ' || nullif(un.torre, ''), ''),
           vi.patente_vehiculo
      into v_nombre, v_unidad, v_patente
      from public.visitas vi
      left join public.usuarios  r  on r.id  = vi.residente_id
      left join public.unidades  un on un.id = coalesce(vi.unidad_id, r.unidad_id)
     where vi.id = p_persona_id;
  elsif p_persona_tipo = 'personal_servicio' then
    select ps.nombre_completo,
           coalesce(un.numero, '') || coalesce(' ' || nullif(un.torre, ''), ''),
           ps.patente_vehiculo
      into v_nombre, v_unidad, v_patente
      from public.personal_servicio ps
      left join public.usuarios r  on r.id  = ps.residente_id
      left join public.unidades un on un.id = coalesce(ps.unidad_id, r.unidad_id)
     where ps.id = p_persona_id;
  else
    raise exception 'Tipo de persona no valido: %', p_persona_tipo;
  end if;

  if v_nombre is null then
    raise exception 'No se encontro la persona indicada (% con id %).',
      p_persona_tipo, p_persona_id;
  end if;

  if p_vehiculo_id is not null then
    select v.patente into v_patente from public.vehiculos v where v.id = p_vehiculo_id;
  end if;

  insert into public.movimientos_acceso (
    condominio_id, id_local, persona_tipo,
    residente_id, visita_id, personal_servicio_id,
    nombre_snapshot, unidad_snapshot,
    punto_acceso_id, tipo_acceso, sentido,
    vehiculo_id, patente_snapshot, estado, motivo_denegacion,
    guardia_id, turno_id, dispositivo_id,
    ocurrido_en, sincronizado_offline, geo_lat, geo_lng
  ) values (
    v_condominio, p_id_local, p_persona_tipo,
    case when p_persona_tipo = 'residente'         then p_persona_id end,
    case when p_persona_tipo = 'visita'            then p_persona_id end,
    case when p_persona_tipo = 'personal_servicio' then p_persona_id end,
    v_nombre, nullif(trim(v_unidad), ''),
    p_punto_acceso_id, v_tipo_acceso, p_sentido,
    p_vehiculo_id, v_patente, p_estado, p_motivo_denegacion,
    coalesce(p_guardia_id, case when public.es_guardia() then auth.uid() end),
    public.mi_turno_activo(), p_dispositivo_id,
    coalesce(p_ocurrido_en, now()), p_offline, p_geo_lat, p_geo_lng
  )
  on conflict (id_local) do nothing
  returning id into v_movimiento;

  if v_movimiento is null then
    select id into v_movimiento
      from public.movimientos_acceso where id_local = p_id_local;
  end if;

  return v_movimiento;
end; $function$;


-- ============================================================================
-- FIX 2: auto-cierre de rondas y turnos colgados
-- ============================================================================
-- Se cambia la firma (agrega 2 columnas al RETURNS TABLE), por eso DROP
-- explícito antes del CREATE.

DROP FUNCTION IF EXISTS public.expirar_registros_vencidos();

CREATE FUNCTION public.expirar_registros_vencidos()
RETURNS TABLE(
  solicitudes_expiradas integer,
  visitas_expiradas integer,
  rondas_auto_cerradas integer,
  turnos_auto_cerrados integer
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_sol int;
  v_vis int;
  v_ron int;
  v_tur int;
begin
  update public.solicitudes_vehiculares
     set estado = 'expirada', resuelto_en = now()
   where estado = 'pendiente' and expira_en <= now();
  get diagnostics v_sol = row_count;

  update public.visitas set estado = 'expirada'
   where estado in ('activa','aprobada','esperando_aprobacion')
     and valido_hasta <= now();
  get diagnostics v_vis = row_count;

  -- Rondas > 24h abiertas -> cerrar con la hora de la ultima marca (o
  -- inicio + 30m si nunca se marco nada, probablemente guardia que
  -- arranco ronda y se olvido).
  with rondas_zombis as (
    select r.id,
           coalesce(
             (select max(m.marcado_en) from public.marcas_de_ronda m
              where m.ronda_id = r.id),
             r.inicio + interval '30 minutes'
           ) as cierre_calculado
      from public.rondas r
     where r.cerrada_en is null
       and r.inicio < now() - interval '24 hours'
  )
  update public.rondas r
     set cerrada_en = rz.cierre_calculado,
         notas = coalesce(nullif(trim(r.notas), '') || ' | ', '')
                 || 'Auto-cerrada por el sistema (inactividad > 24h).'
    from rondas_zombis rz
   where r.id = rz.id;
  get diagnostics v_ron = row_count;

  -- Turnos > 12h abiertos -> cerrar con inicio + 12h (no inflar horas
  -- trabajadas del guardia por el olvido).
  update public.turnos t
     set cerrado_en = t.inicio + interval '12 hours',
         notas_entrega = coalesce(nullif(trim(t.notas_entrega), '') || ' | ', '')
                         || 'Auto-cerrado por el sistema (turno > 12h sin cerrar).'
   where t.cerrado_en is null
     and t.inicio < now() - interval '12 hours';
  get diagnostics v_tur = row_count;

  return query select v_sol, v_vis, v_ron, v_tur;
end; $function$;
