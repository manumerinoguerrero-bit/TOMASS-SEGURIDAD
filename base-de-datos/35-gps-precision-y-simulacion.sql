-- ============================================================================
-- Tomass Seguridad — 35 · Precisión, hora del fix y GPS simulado (auditoría G)
-- ============================================================================
-- QUÉ AGREGA
--   · ubicaciones_turno: precisión de la muestra y bandera de GPS simulado.
--   · marcas_de_ronda: precisión, bandera de GPS simulado y hora del fix.
--   · actualizar_mi_ubicacion: recibe esos datos y la hora real de muestras
--     que se mandaron tarde por falta de red.
--   · marcar_punto_por_gps / marcar_punto_manual: reciben ronda y hora del
--     teléfono (marcas que viajaron por la cola offline), rechazan la
--     auto-marca con GPS simulado o precisión mala, y cuentan el total de
--     puntos según la garita del turno.
--
-- COMPATIBILIDAD: las funciones se eliminan y recrean con parámetros nuevos
-- con DEFAULT. Los APK viejos y las operaciones ya encoladas (que mandan 2, 3
-- o 4 parámetros con nombre) siguen resolviendo a la función nueva. Se repite
-- el REVOKE a public/anon porque DROP+CREATE restablece el grant por defecto.
-- ============================================================================

begin;

alter table public.ubicaciones_turno
  add column if not exists precision_m numeric(7,1),
  add column if not exists simulada boolean not null default false;

alter table public.marcas_de_ronda
  add column if not exists precision_m numeric(7,1),
  add column if not exists gps_simulado boolean not null default false,
  add column if not exists fix_tomado_en timestamptz;

comment on column public.marcas_de_ronda.gps_simulado is
  'true si el teléfono declaró que la posición venía de una app de GPS falso';
comment on column public.ubicaciones_turno.simulada is
  'true si el teléfono declaró que la posición venía de una app de GPS falso';

-- ----------------------------------------------------------------------------
-- Total de puntos que le tocan a una ronda: los de la garita del turno más
-- los comunes. Mismo criterio que la app (servicio_guardia.puntosDeControl).
-- ----------------------------------------------------------------------------
create or replace function public.total_de_puntos_de_ronda(p_ronda_id uuid)
returns integer
language sql stable security definer
set search_path to 'public', 'pg_temp'
as $$
  select count(*)::int
    from public.rondas r
    left join public.turnos t on t.id = r.turno_id
    join public.puntos_control pc on pc.condominio_id = r.condominio_id
   where r.id = p_ronda_id
     and pc.activo
     and (t.punto_acceso_id is null
          or pc.punto_acceso_id is null
          or pc.punto_acceso_id = t.punto_acceso_id);
$$;

revoke all on function public.total_de_puntos_de_ronda(uuid)
  from public, anon, authenticated;

-- ----------------------------------------------------------------------------
-- actualizar_mi_ubicacion
-- ----------------------------------------------------------------------------
drop function if exists public.actualizar_mi_ubicacion(numeric, numeric);

create function public.actualizar_mi_ubicacion(
  p_lat         numeric,
  p_lng         numeric,
  p_precision_m numeric     default null,
  p_simulada    boolean     default false,
  p_tomada_en   timestamptz default null
)
returns void
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $$
declare
  v_guardia_id uuid := auth.uid();
  v_turno      record;
  v_cuando     timestamptz := now();
begin
  if v_guardia_id is null then
    raise exception 'Sin sesión activa.' using errcode = 'insufficient_privilege';
  end if;

  if p_lat is null or p_lng is null then
    raise exception 'Faltan las coordenadas.' using errcode = 'check_violation';
  end if;

  if p_lat not between -90 and 90 or p_lng not between -180 and 180 then
    raise exception 'Coordenadas fuera de rango.' using errcode = 'check_violation';
  end if;

  select id, inicio, ultima_ubicacion_en into v_turno
    from public.turnos
   where guardia_id = v_guardia_id and cerrado_en is null;

  -- Sin turno abierto salimos callados, como antes.
  if v_turno.id is null then
    return;
  end if;

  -- Muestra atrasada: se respeta su hora solo si cae dentro del turno.
  if p_tomada_en is not null
     and p_tomada_en >= v_turno.inicio
     and p_tomada_en <= now() then
    v_cuando := p_tomada_en;
  end if;

  -- El mapa en vivo solo avanza: una muestra atrasada no pisa una más nueva.
  if v_turno.ultima_ubicacion_en is null
     or v_cuando >= v_turno.ultima_ubicacion_en then
    update public.turnos
       set ultima_geo_lat = p_lat,
           ultima_geo_lng = p_lng,
           ultima_ubicacion_en = v_cuando
     where id = v_turno.id;
  end if;

  insert into public.ubicaciones_turno
    (turno_id, guardia_id, cuando, lat, lng, precision_m, simulada)
  values
    (v_turno.id, v_guardia_id, v_cuando, p_lat, p_lng,
     round(p_precision_m, 1), coalesce(p_simulada, false));
end;
$$;

revoke all on function
  public.actualizar_mi_ubicacion(numeric, numeric, numeric, boolean, timestamptz)
  from public, anon;
grant execute on function
  public.actualizar_mi_ubicacion(numeric, numeric, numeric, boolean, timestamptz)
  to authenticated;

-- ----------------------------------------------------------------------------
-- marcar_punto_por_gps
-- ----------------------------------------------------------------------------
drop function if exists public.marcar_punto_por_gps(uuid, uuid, numeric, numeric);

create function public.marcar_punto_por_gps(
  p_id_local         uuid,
  p_punto_control_id uuid,
  p_geo_lat          numeric,
  p_geo_lng          numeric,
  p_precision_m      numeric     default null,
  p_gps_simulado     boolean     default false,
  p_fix_tomado_en    timestamptz default null,
  p_ronda_id         uuid        default null,
  p_marcado_en       timestamptz default null
) returns table(
  punto text,
  marcados integer,
  total integer,
  ya_estaba boolean,
  metros_de_lejos numeric
)
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $$
declare
  v_guardia  uuid := auth.uid();
  v_ronda    record;
  v_punto    record;
  v_repetida boolean := false;
  v_metros   numeric;
  v_cuando   timestamptz := now();
begin
  if p_ronda_id is not null then
    select id, condominio_id, inicio, cerrada_en into v_ronda
      from public.rondas
     where id = p_ronda_id and guardia_id = v_guardia;
  else
    select id, condominio_id, inicio, cerrada_en into v_ronda
      from public.rondas
     where guardia_id = v_guardia and cerrada_en is null;
  end if;

  if v_ronda.id is null then
    raise exception 'Primero tocá "Empezar ronda". Todavía no arrancaste ninguna.'
      using errcode = 'insufficient_privilege';
  end if;

  if p_marcado_en is not null
     and p_marcado_en >= v_ronda.inicio
     and p_marcado_en <= coalesce(v_ronda.cerrada_en, now()) then
    v_cuando := p_marcado_en;
  elsif v_ronda.cerrada_en is not null then
    raise exception 'Esa ronda ya está cerrada.'
      using errcode = 'insufficient_privilege';
  end if;

  select pc.id, pc.nombre, pc.latitud, pc.longitud, pc.metros_de_tolerancia
    into v_punto
    from public.puntos_control pc
   where pc.id = p_punto_control_id
     and pc.condominio_id = v_ronda.condominio_id
     and pc.activo;

  if v_punto.id is null then
    raise exception 'Ese punto no es de esta instalación o no está activo.'
      using errcode = 'no_data_found';
  end if;

  if v_punto.latitud is null or v_punto.longitud is null then
    raise exception 'Ese punto todavía no tiene coordenadas cargadas. Avisale a la administración.'
      using errcode = 'insufficient_privilege';
  end if;

  if p_geo_lat is null or p_geo_lng is null then
    raise exception 'No pude leer tu ubicación GPS. Salí al aire libre y esperá unos segundos.'
      using errcode = 'insufficient_privilege';
  end if;

  if coalesce(p_gps_simulado, false) then
    raise exception 'El teléfono está entregando una ubicación simulada. Cerrá la app de GPS falso para marcar.'
      using errcode = 'check_violation';
  end if;

  if p_precision_m is not null and p_precision_m > 50 then
    raise exception 'El GPS está muy impreciso (% m). Esperá unos segundos al aire libre o marcá a mano.',
      round(p_precision_m)
      using errcode = 'check_violation';
  end if;

  v_metros := public.metros_entre(
    v_punto.latitud, v_punto.longitud, p_geo_lat, p_geo_lng);

  if v_metros > v_punto.metros_de_tolerancia then
    raise exception 'Estás a % metros del punto %. Tenés que estar a máximo % metros para marcarlo.',
      round(v_metros), v_punto.nombre, v_punto.metros_de_tolerancia
      using errcode = 'check_violation';
  end if;

  select exists (
    select 1 from public.marcas_de_ronda m
     where m.ronda_id = v_ronda.id and m.punto_control_id = v_punto.id
  ) into v_repetida;

  if not v_repetida then
    insert into public.marcas_de_ronda (
      ronda_id, punto_control_id, id_local, marcado_en, geo_lat, geo_lng,
      marcada_manual, precision_m, gps_simulado, fix_tomado_en
    ) values (
      v_ronda.id, v_punto.id, p_id_local, v_cuando, p_geo_lat, p_geo_lng,
      false, round(p_precision_m, 1), false, p_fix_tomado_en
    )
    on conflict (id_local) do nothing;
  end if;

  return query
  select v_punto.nombre::text,
         (select count(*)::int from public.marcas_de_ronda m
           where m.ronda_id = v_ronda.id),
         public.total_de_puntos_de_ronda(v_ronda.id),
         v_repetida,
         v_metros;
end;
$$;

revoke all on function
  public.marcar_punto_por_gps(uuid, uuid, numeric, numeric, numeric, boolean,
                              timestamptz, uuid, timestamptz)
  from public, anon;
grant execute on function
  public.marcar_punto_por_gps(uuid, uuid, numeric, numeric, numeric, boolean,
                              timestamptz, uuid, timestamptz)
  to authenticated;

-- ----------------------------------------------------------------------------
-- marcar_punto_manual
-- ----------------------------------------------------------------------------
drop function if exists public.marcar_punto_manual(uuid, uuid, text);

create function public.marcar_punto_manual(
  p_id_local         uuid,
  p_punto_control_id uuid,
  p_motivo           text,
  p_geo_lat          numeric     default null,
  p_geo_lng          numeric     default null,
  p_precision_m      numeric     default null,
  p_gps_simulado     boolean     default false,
  p_ronda_id         uuid        default null,
  p_marcado_en       timestamptz default null
) returns table(
  punto text,
  marcados integer,
  total integer,
  ya_estaba boolean
)
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $$
declare
  v_guardia  uuid := auth.uid();
  v_ronda    record;
  v_punto    record;
  v_repetida boolean := false;
  v_motivo   text := trim(coalesce(p_motivo, ''));
  v_cuando   timestamptz := now();
begin
  if length(v_motivo) < 10 then
    raise exception 'Escribí al menos 10 letras explicando por qué marcás a mano (ej: "sin señal GPS en el subsuelo").'
      using errcode = 'check_violation';
  end if;

  if p_ronda_id is not null then
    select id, condominio_id, inicio, cerrada_en into v_ronda
      from public.rondas
     where id = p_ronda_id and guardia_id = v_guardia;
  else
    select id, condominio_id, inicio, cerrada_en into v_ronda
      from public.rondas
     where guardia_id = v_guardia and cerrada_en is null;
  end if;

  if v_ronda.id is null then
    raise exception 'Primero tocá "Empezar ronda". Todavía no arrancaste ninguna.'
      using errcode = 'insufficient_privilege';
  end if;

  if p_marcado_en is not null
     and p_marcado_en >= v_ronda.inicio
     and p_marcado_en <= coalesce(v_ronda.cerrada_en, now()) then
    v_cuando := p_marcado_en;
  elsif v_ronda.cerrada_en is not null then
    raise exception 'Esa ronda ya está cerrada.'
      using errcode = 'insufficient_privilege';
  end if;

  select pc.id, pc.nombre into v_punto
    from public.puntos_control pc
   where pc.id = p_punto_control_id
     and pc.condominio_id = v_ronda.condominio_id
     and pc.activo;

  if v_punto.id is null then
    raise exception 'Ese punto no es de esta instalación o no está activo.'
      using errcode = 'no_data_found';
  end if;

  select exists (
    select 1 from public.marcas_de_ronda m
     where m.ronda_id = v_ronda.id and m.punto_control_id = v_punto.id
  ) into v_repetida;

  if not v_repetida then
    insert into public.marcas_de_ronda (
      ronda_id, punto_control_id, id_local, marcado_en, geo_lat, geo_lng,
      marcada_manual, motivo_manual, precision_m, gps_simulado
    ) values (
      v_ronda.id, v_punto.id, p_id_local, v_cuando, p_geo_lat, p_geo_lng,
      true, v_motivo, round(p_precision_m, 1), coalesce(p_gps_simulado, false)
    )
    on conflict (id_local) do nothing;
  end if;

  return query
  select v_punto.nombre::text,
         (select count(*)::int from public.marcas_de_ronda m
           where m.ronda_id = v_ronda.id),
         public.total_de_puntos_de_ronda(v_ronda.id),
         v_repetida;
end;
$$;

revoke all on function
  public.marcar_punto_manual(uuid, uuid, text, numeric, numeric, numeric,
                             boolean, uuid, timestamptz)
  from public, anon;
grant execute on function
  public.marcar_punto_manual(uuid, uuid, text, numeric, numeric, numeric,
                             boolean, uuid, timestamptz)
  to authenticated;

commit;
