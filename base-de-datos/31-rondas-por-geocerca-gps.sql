-- ============================================================================
-- Tomass Seguridad — 31 · Rondas por geocerca GPS (sin códigos QR)
-- ============================================================================
-- ⚠️ ESTE ARCHIVO YA ESTÁ APLICADO EN EL SERVIDOR. Queda para el historial.
--
-- POR QUÉ CAMBIA
--
--   Hasta acá las rondas requerían que el guardia escanee un cartel con código
--   QR pegado en cada punto. Funciona pero es frágil: los carteles se tapan,
--   se despegan, o un chico los arranca. El competidor (Itácora/Bitácora) se
--   mueve a geocerca GPS pura, que es lo que pidió Manuel.
--
--   Ahora: cada punto de control tiene coordenadas y un radio en metros. El
--   guardia hace la ronda caminando, la app sigue su GPS, y cuando entra al
--   radio de un punto pendiente la marca SOLA. Sin escanear nada.
--
-- QUE SE AGREGA
--
--   · Columnas marcada_manual + motivo_manual en marcas_de_ronda, para que el
--     informe pueda distinguir marcas auto (por GPS) de las manuales.
--   · RPC marcar_punto_por_gps: la que usa la app cuando detecta que el
--     guardia entró al radio. Toda la validación de distancia vive en el
--     backend para que no se pueda falsificar desde el cliente.
--   · RPC marcar_punto_manual: fallback si el GPS falla (indoor, sin señal).
--     Obliga a escribir un motivo de mínimo 10 caracteres y queda marcado
--     con bandera manual en el informe.
--
-- LO QUE NO SE TOCA
--
--   La RPC vieja marcar_punto_control (por QR) queda viva para no romper
--   operaciones encoladas offline que la estén esperando. En las versiones
--   nuevas de la app ya no se llama desde ninguna pantalla.
--
-- CARGA DE DATOS QUE SE HIZO ADEMÁS DE LAS FUNCIONES
--
--   · Condominio Cerro Grande: 6 puntos de control → desactivados (no hay
--     ronda ahí, solo guardia de garita).
--   · Condominio Encomenderos: 6 placeholders viejos desactivados, 11 puntos
--     nuevos cargados con coordenadas reales del recorrido (garita + 10
--     puntos del perímetro).
-- ============================================================================

alter table public.marcas_de_ronda
  add column if not exists marcada_manual boolean not null default false,
  add column if not exists motivo_manual text;

comment on column public.marcas_de_ronda.marcada_manual is
  'true si el guardia la marcó a mano (sin GPS). false si fue auto por geocerca';
comment on column public.marcas_de_ronda.motivo_manual is
  'Si marcada_manual = true: por qué tuvo que hacerlo así (sin señal, etc)';


-- ============================================================================
-- MARCAR POR GPS (automática): toda la validación de distancia vive acá
-- ============================================================================

create or replace function public.marcar_punto_por_gps(
  p_id_local uuid,
  p_punto_control_id uuid,
  p_geo_lat numeric,
  p_geo_lng numeric
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
  v_ronda    uuid;
  v_condo    uuid;
  v_punto    record;
  v_repetida boolean := false;
  v_metros   numeric;
begin
  select id, condominio_id into v_ronda, v_condo
    from public.rondas
   where guardia_id = v_guardia and cerrada_en is null;

  if v_ronda is null then
    raise exception 'Primero tocá "Empezar ronda". Todavía no arrancaste ninguna.'
      using errcode = 'insufficient_privilege';
  end if;

  select pc.id, pc.nombre, pc.latitud, pc.longitud, pc.metros_de_tolerancia
    into v_punto
    from public.puntos_control pc
   where pc.id = p_punto_control_id
     and pc.condominio_id = v_condo
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

  v_metros := public.metros_entre(
    v_punto.latitud, v_punto.longitud, p_geo_lat, p_geo_lng);

  if v_metros > v_punto.metros_de_tolerancia then
    raise exception 'Estás a % metros del punto %. Tenés que estar a máximo % metros para marcarlo.',
      round(v_metros), v_punto.nombre, v_punto.metros_de_tolerancia
      using errcode = 'check_violation';
  end if;

  select exists (
    select 1 from public.marcas_de_ronda m
     where m.ronda_id = v_ronda and m.punto_control_id = v_punto.id
  ) into v_repetida;

  if not v_repetida then
    insert into public.marcas_de_ronda (
      ronda_id, punto_control_id, id_local, geo_lat, geo_lng, marcada_manual
    ) values (
      v_ronda, v_punto.id, p_id_local, p_geo_lat, p_geo_lng, false
    )
    on conflict (id_local) do nothing;
  end if;

  return query
  select v_punto.nombre::text,
         (select count(*)::int from public.marcas_de_ronda m where m.ronda_id = v_ronda),
         (select count(*)::int from public.puntos_control pc
           where pc.condominio_id = v_condo and pc.activo),
         v_repetida,
         v_metros;
end;
$$;

grant execute on function
  public.marcar_punto_por_gps(uuid, uuid, numeric, numeric) to authenticated;


-- ============================================================================
-- MARCAR MANUAL (fallback con nota obligatoria)
-- ============================================================================
-- Se usa cuando el GPS no responde (indoor profundo, sin señal) pero el
-- guardia sí pasó por el punto. El motivo queda guardado y el informe lo
-- distingue de las marcas automáticas.
-- ============================================================================

create or replace function public.marcar_punto_manual(
  p_id_local uuid,
  p_punto_control_id uuid,
  p_motivo text
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
  v_ronda    uuid;
  v_condo    uuid;
  v_punto    record;
  v_repetida boolean := false;
  v_motivo   text   := trim(coalesce(p_motivo, ''));
begin
  if length(v_motivo) < 10 then
    raise exception 'Escribí al menos 10 letras explicando por qué marcás a mano (ej: "sin señal GPS en el subsuelo").'
      using errcode = 'check_violation';
  end if;

  select id, condominio_id into v_ronda, v_condo
    from public.rondas
   where guardia_id = v_guardia and cerrada_en is null;

  if v_ronda is null then
    raise exception 'Primero tocá "Empezar ronda". Todavía no arrancaste ninguna.'
      using errcode = 'insufficient_privilege';
  end if;

  select pc.id, pc.nombre
    into v_punto
    from public.puntos_control pc
   where pc.id = p_punto_control_id
     and pc.condominio_id = v_condo
     and pc.activo;

  if v_punto.id is null then
    raise exception 'Ese punto no es de esta instalación o no está activo.'
      using errcode = 'no_data_found';
  end if;

  select exists (
    select 1 from public.marcas_de_ronda m
     where m.ronda_id = v_ronda and m.punto_control_id = v_punto.id
  ) into v_repetida;

  if not v_repetida then
    insert into public.marcas_de_ronda (
      ronda_id, punto_control_id, id_local, marcada_manual, motivo_manual
    ) values (
      v_ronda, v_punto.id, p_id_local, true, v_motivo
    )
    on conflict (id_local) do nothing;
  end if;

  return query
  select v_punto.nombre::text,
         (select count(*)::int from public.marcas_de_ronda m where m.ronda_id = v_ronda),
         (select count(*)::int from public.puntos_control pc
           where pc.condominio_id = v_condo and pc.activo),
         v_repetida;
end;
$$;

grant execute on function
  public.marcar_punto_manual(uuid, uuid, text) to authenticated;


-- ============================================================================
-- FIN DEL ARCHIVO 31
-- ============================================================================
