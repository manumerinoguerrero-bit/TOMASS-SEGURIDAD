-- ============================================================================
-- 34 · Auditoría de seguridad — Fase 2 (hallazgos SEG-02, SEG-03, SEG-04)
-- ============================================================================
-- Cierra tres agujeros server-side. Todo verificado contra la base real antes
-- de aplicar: ningún flujo legítimo del guardia o del admin se rompe, porque
-- todas las operaciones del guardia pasan por RPC SECURITY DEFINER
-- (registrar_acceso_manual, marcar_punto_*, empezar/cerrar_ronda,
-- actualizar_mi_ubicacion) o por cerrar_turno, que solo toca cerrado_en/notas.
--
--   SEG-02 (alto) · Cualquier usuario del condominio podía INSERTAR en
--     movimientos_acceso por API (fabricar ingresos "aprobados"). Ahora el
--     INSERT exige ser portería y atribuirse a uno mismo; el servidor
--     (service_role) sigue pudiendo atribuir a otro guardia.
--
--   SEG-03 (alto) · El guardia podía reescribir cualquier columna de sus
--     turnos, y INSERT/UPDATE/DELETE directo en rondas y marcas_de_ronda
--     (marcar sin pasar por la validación de distancia). Ahora rondas y
--     marcas son solo por RPC, y un trigger limita qué puede tocar del turno.
--
--   SEG-04 (alto) · Cuatro vistas quedaron como SECURITY DEFINER (saltaban
--     RLS): un residente leía datos de todos (rostros, firmas, encomiendas,
--     patentes). Se vuelven security_invoker. Cuatro RPC de informe sumaban
--     chequeo de rol. La policy de Storage deja de exponer todas las fotos.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- SEG-02 · Solo portería registra movimientos, y atribuidos a sí misma
-- ----------------------------------------------------------------------------
drop policy if exists "registrar movimiento en mi condominio" on public.movimientos_acceso;

create policy "porteria registra movimientos" on public.movimientos_acceso
  for insert to authenticated
  with check (
    condominio_id = public.mi_condominio()
    and public.es_porteria()
    and (guardia_id is null or guardia_id = auth.uid())
  );

-- registrar_movimiento: solo el servidor (service_role) puede atribuir el
-- movimiento a otro guardia. Un cliente autenticado siempre queda como
-- auth.uid(). El resto de la función no cambia.
create or replace function public.registrar_movimiento(
  p_id_local uuid, p_persona_tipo text, p_persona_id uuid, p_punto_acceso_id uuid,
  p_sentido text, p_estado text default 'aprobado'::text, p_vehiculo_id uuid default null::uuid,
  p_motivo_denegacion text default null::text, p_ocurrido_en timestamp with time zone default null::timestamp with time zone,
  p_offline boolean default false, p_dispositivo_id uuid default null::uuid,
  p_geo_lat numeric default null::numeric, p_geo_lng numeric default null::numeric,
  p_guardia_id uuid default null::uuid)
returns uuid
language plpgsql
set search_path to 'public', 'pg_temp'
as $function$
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
    -- Solo el servidor atribuye a otro; el cliente queda como él mismo.
    coalesce(
      case when auth.role() = 'service_role' then p_guardia_id end,
      case when public.es_guardia() then auth.uid() end),
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

-- ----------------------------------------------------------------------------
-- SEG-03 · Rondas y marcas solo por RPC; el turno solo se abre/cierra "ahora"
-- ----------------------------------------------------------------------------
drop policy if exists "guardia abre y cierra sus rondas" on public.rondas;
drop policy if exists "guardia marca sus puntos"         on public.marcas_de_ronda;
revoke insert, update, delete on public.rondas, public.marcas_de_ronda
  from authenticated, anon;

create or replace function public.proteger_turno()
returns trigger
language plpgsql
set search_path to 'public', 'pg_temp'
as $$
begin
  -- Las RPC SECURITY DEFINER (actualizar_mi_ubicacion, cerrar_sesion_guardia,
  -- dar_de_baja_guardia…) y el service_role corren con otro current_user y no
  -- pasan por acá. Tampoco el administrador.
  if current_user <> 'authenticated' or public.es_administrador() then
    return new;
  end if;

  if tg_op = 'INSERT' then
    new.inicio     := now();
    new.cerrado_en := null;
    return new;
  end if;

  if old.cerrado_en is not null then
    raise exception 'Un turno cerrado no se puede modificar.'
      using errcode = 'insufficient_privilege';
  end if;

  -- Lo único que el guardia puede tocar: el cierre y sus notas.
  if (to_jsonb(new) - 'cerrado_en' - 'notas_entrega' - 'cerrado_por')
     is distinct from
     (to_jsonb(old) - 'cerrado_en' - 'notas_entrega' - 'cerrado_por') then
    raise exception 'Solo podés cerrar tu turno y dejar notas de entrega.'
      using errcode = 'insufficient_privilege';
  end if;

  if new.cerrado_en is not null then
    new.cerrado_en := now();
  end if;
  return new;
end; $$;

drop trigger if exists tr_turnos_proteger on public.turnos;
create trigger tr_turnos_proteger
  before insert or update on public.turnos
  for each row execute function public.proteger_turno();

-- ----------------------------------------------------------------------------
-- SEG-04 · Vistas con RLS del que consulta, RPC con rol, Storage acotado
-- ----------------------------------------------------------------------------

-- 1. Vistas: volver al diseño original (RLS del que consulta).
alter view public.v_personas_dentro                    set (security_invoker = true);
alter view public.v_solicitudes_vehiculares_pendientes set (security_invoker = true);
alter view public.v_paquetes_porteria                  set (security_invoker = true);
alter view public.v_resumen_condominio                 set (security_invoker = true);
revoke all on public.v_personas_dentro,
              public.v_solicitudes_vehiculares_pendientes,
              public.v_paquetes_porteria,
              public.v_resumen_condominio,
              public.v_vehiculos_por_aprobar
  from anon;

-- 2. RPC de informe: agregar chequeo de rol (son admin-only o portería).
create or replace function public.sectores_para_el_plano()
returns table(id uuid, nombre text, orden smallint, latitud numeric, longitud numeric, tolerancia smallint)
language sql stable security definer
set search_path to 'public', 'pg_temp'
as $function$
  select pc.id, pc.nombre::text, pc.orden,
         pc.latitud, pc.longitud, pc.metros_de_tolerancia
    from public.puntos_control pc
   where pc.condominio_id = public.mi_condominio()
     and public.es_administrador()
     and pc.activo
   order by pc.orden;
$function$;

create or replace function public.visitas_esperando_respuesta()
returns table(visita_id uuid, nombre_visitante text, patente text, motivo text, residente text, espacio text, estado text, motivo_rechazo text, llamo_por_telefono boolean, creado_en timestamp with time zone, minutos_esperando integer)
language sql stable security definer
set search_path to 'public', 'pg_temp'
as $function$
  select v.id,
         v.nombre_visitante::text,
         v.patente_vehiculo::text,
         v.motivo_visita::text,
         u.nombre_completo::text,
         coalesce(un.numero || ' ' || coalesce(un.torre, ''), '—')::text,
         v.estado::text,
         v.motivo_rechazo::text,
         v.autorizada_por_telefono,
         v.creado_en,
         (extract(epoch from (now() - v.creado_en)) / 60)::int
    from public.visitas v
    join public.usuarios u  on u.id = v.residente_id
    left join public.unidades un on un.id = v.unidad_id
   where v.condominio_id = public.mi_condominio()
     and public.es_porteria()
     and v.creado_en > now() - interval '2 hours'
     and v.origen = 'espontanea'
     and v.estado in ('esperando_aprobacion', 'aprobada', 'rechazada')
   order by v.creado_en desc;
$function$;

create or replace function public.detalle_de_rondas(p_dias integer default 7, p_desde timestamp with time zone default null::timestamp with time zone, p_hasta timestamp with time zone default null::timestamp with time zone)
returns table(ronda_id uuid, guardia text, ronda_inicio timestamp with time zone, ronda_cerrada timestamp with time zone, ronda_notas text, sector text, sector_orden smallint, marcado_en timestamp with time zone, novedad text, sector_lat numeric, sector_lng numeric, tolerancia smallint, marca_lat numeric, marca_lng numeric, metros_de_lejos numeric, lejos boolean)
language sql stable security definer
set search_path to 'public', 'pg_temp'
as $function$
  WITH rango AS (
    SELECT COALESCE(p_desde, NOW() - make_interval(days => p_dias)) AS desde,
           COALESCE(p_hasta, NOW()) AS hasta
  )
  SELECT r.id, u.nombre_completo::text, r.inicio, r.cerrada_en, r.notas::text,
         pc.nombre::text, pc.orden, m.marcado_en, m.novedad::text,
         pc.latitud, pc.longitud, pc.metros_de_tolerancia, m.geo_lat, m.geo_lng,
         public.metros_entre(pc.latitud, pc.longitud, m.geo_lat, m.geo_lng),
         COALESCE(public.metros_entre(pc.latitud, pc.longitud, m.geo_lat, m.geo_lng)
             > pc.metros_de_tolerancia, false)
    FROM public.rondas r
    JOIN public.usuarios u        ON u.id = r.guardia_id
    JOIN public.marcas_de_ronda m ON m.ronda_id = r.id
    JOIN public.puntos_control pc ON pc.id = m.punto_control_id
    CROSS JOIN rango
   WHERE r.condominio_id = public.mi_condominio()
     AND public.es_administrador()
     AND m.marcado_en >= rango.desde
     AND m.marcado_en <= rango.hasta
   ORDER BY r.inicio DESC, m.marcado_en;
$function$;

create or replace function public.informe_de_rondas(p_dias integer default 7, p_desde timestamp with time zone default null::timestamp with time zone, p_hasta timestamp with time zone default null::timestamp with time zone)
returns table(ronda_id uuid, guardia text, garita text, inicio timestamp with time zone, cerrada_en timestamp with time zone, minutos integer, marcados integer, total integer, completa boolean, marcas_lejanas integer, horas_desde_la_anterior numeric, se_paso_del_limite boolean, notas text)
language sql stable security definer
set search_path to 'public', 'pg_temp'
as $function$
  WITH rango AS (
    SELECT COALESCE(p_desde, NOW() - make_interval(days => p_dias)) AS desde,
           COALESCE(p_hasta, NOW()) AS hasta
  ),
  limite AS (
    SELECT COALESCE(NULLIF(minutos_entre_rondas, 0), 120) AS tope
      FROM public.condominios WHERE id = public.mi_condominio()
  ),
  base AS (
    SELECT r.id, u.nombre_completo, r.inicio, r.cerrada_en, r.notas, r.guardia_id,
           t.punto_acceso_id, pa.nombre AS garita_nombre,
           LAG(r.inicio) OVER (PARTITION BY r.guardia_id ORDER BY r.inicio) AS anterior
      FROM public.rondas r
      JOIN public.usuarios u ON u.id = r.guardia_id
      LEFT JOIN public.turnos t ON t.id = r.turno_id
      LEFT JOIN public.puntos_acceso pa ON pa.id = t.punto_acceso_id
      CROSS JOIN rango
     WHERE r.condominio_id = public.mi_condominio()
       AND public.es_administrador()
       AND (
         (r.inicio >= rango.desde AND r.inicio <= rango.hasta)
         OR (r.cerrada_en IS NOT NULL AND r.cerrada_en >= rango.desde AND r.cerrada_en <= rango.hasta)
         OR EXISTS (SELECT 1 FROM public.marcas_de_ronda m2
                     WHERE m2.ronda_id = r.id AND m2.marcado_en >= rango.desde AND m2.marcado_en <= rango.hasta)
       )
  ),
  total_por_ronda AS (
    SELECT b.id AS ronda_id,
           (SELECT COUNT(*)::int FROM public.puntos_control pc
              WHERE pc.condominio_id = public.mi_condominio() AND pc.activo
                AND (b.punto_acceso_id IS NULL OR pc.punto_acceso_id = b.punto_acceso_id OR pc.punto_acceso_id IS NULL)) AS total
      FROM base b
  )
  SELECT b.id, b.nombre_completo::text, b.garita_nombre::text, b.inicio, b.cerrada_en,
         (EXTRACT(EPOCH FROM (COALESCE(b.cerrada_en, NOW()) - b.inicio)) / 60)::int,
         (SELECT COUNT(*)::int FROM public.marcas_de_ronda m WHERE m.ronda_id = b.id),
         tpr.total,
         (SELECT COUNT(*) FROM public.marcas_de_ronda m WHERE m.ronda_id = b.id) >= tpr.total,
         (SELECT COUNT(*)::int FROM public.marcas_de_ronda m
            JOIN public.puntos_control pc ON pc.id = m.punto_control_id
           WHERE m.ronda_id = b.id AND pc.latitud IS NOT NULL AND m.geo_lat IS NOT NULL
             AND public.metros_entre(pc.latitud, pc.longitud, m.geo_lat, m.geo_lng) > pc.metros_de_tolerancia),
         CASE WHEN b.anterior IS NULL THEN NULL
              ELSE ROUND((EXTRACT(EPOCH FROM (b.inicio - b.anterior)) / 3600)::numeric, 1) END,
         CASE WHEN b.anterior IS NULL THEN false
              ELSE (EXTRACT(EPOCH FROM (b.inicio - b.anterior)) / 60) > (SELECT tope FROM limite) END,
         b.notas
    FROM base b JOIN total_por_ronda tpr ON tpr.ronda_id = b.id
   ORDER BY b.inicio DESC;
$function$;

-- 3. Storage: portería y panel ven todo lo de su instalación; el residente,
--    lo que subió él y las fotos de sus propias encomiendas.
drop policy if exists "ver fotos de mi condominio" on storage.objects;
create policy "ver fotos de mi condominio"
  on storage.objects for select to authenticated
  using (
    bucket_id in ('vehiculos','paquetes','firmas','personas')
    and (storage.foldername(name))[1] = public.mi_condominio()::text
    and (
      public.es_porteria()
      or public.es_admin_o_mandante()
      or (storage.foldername(name))[2] = auth.uid()::text
      or (bucket_id = 'paquetes' and exists (
            select 1 from public.paquetes p
             where p.residente_id = auth.uid()
               and objects.name in (p.foto_url, p.foto_entrega_url)))
    )
  );
