-- ============================================================================
-- Tomass Seguridad — 03 · FUNCIONES Y VISTAS
-- ============================================================================
-- Qué hace este archivo:
--   Crea "atajos" para que la app no tenga que hacer cálculos complicados.
--
--   Una VISTA es como una consulta guardada con nombre: en vez de que la app
--   tenga que cruzar cinco tablas para armar la pantalla de autos esperando la
--   barrera, le pide la vista y ya viene todo listo.
--
--   Una FUNCIÓN es una operación que hace varias cosas de una sola vez y sin
--   dejar nada a medias. Por ejemplo, aprobar un auto: marca la solicitud como
--   aprobada Y crea el registro del movimiento. Si algo falla, no queda una
--   cosa hecha y la otra no.
--
-- Cómo se usa:
--   Pegá TODO este archivo en el editor SQL de Supabase y presioná "Run".
--   Ejecutar DESPUÉS de 02-seguridad.sql.
--
-- Nota técnica: todas las vistas llevan security_invoker = true. Eso significa
-- que respetan los candados del archivo 02. Sin esa línea, una vista sería un
-- agujero por donde un residente vería los datos de todos.
-- ============================================================================


-- ============================================================================
-- VISTA 1 · ¿QUIÉNES ESTÁN DENTRO DEL CONDOMINIO AHORA MISMO?
-- ============================================================================
-- Toma el último movimiento de cada persona. Si fue una entrada, está adentro.
-- Si fue una salida, está afuera.
--
-- PARA QUÉ SIRVE DE VERDAD: si hay un incendio y los bomberos preguntan cuánta
-- gente queda adentro, esta es la respuesta. También sirve para detectar cosas
-- raras, como una visita que entró hace 14 horas y nunca salió.
-- ============================================================================

create or replace view public.v_personas_dentro
with (security_invoker = true) as
with ultimo_movimiento as (
  select distinct on (
           m.persona_tipo,
           coalesce(m.residente_id, m.visita_id, m.personal_servicio_id)
         )
         m.*
    from public.movimientos_acceso m
   where m.estado = 'aprobado'
   order by m.persona_tipo,
            coalesce(m.residente_id, m.visita_id, m.personal_servicio_id),
            m.ocurrido_en desc
)
select
  u.condominio_id,
  u.persona_tipo,
  coalesce(u.residente_id, u.visita_id, u.personal_servicio_id) as persona_id,
  u.nombre_snapshot   as nombre,
  u.unidad_snapshot   as unidad,
  u.tipo_acceso,
  u.patente_snapshot  as patente,
  u.ocurrido_en        as entro_en,
  -- Cuánto tiempo lleva adentro
  (now() - u.ocurrido_en) as tiempo_adentro,
  -- Marca las estadías raramente largas para revisarlas
  case
    when u.persona_tipo = 'visita'            and now() - u.ocurrido_en > interval '12 hours' then true
    when u.persona_tipo = 'personal_servicio' and now() - u.ocurrido_en > interval '14 hours' then true
    else false
  end as estadia_inusual,
  p.nombre as entro_por
from ultimo_movimiento u
join public.puntos_acceso p on p.id = u.punto_acceso_id
where u.sentido = 'entrada';

comment on view public.v_personas_dentro is
  'Personas actualmente dentro del condominio, según su último movimiento aprobado.';


-- ============================================================================
-- VISTA 2 · AUTOS ESPERANDO LA BARRERA
-- ============================================================================
-- Alimenta la pantalla crítica del guardia. Trae todo lo que necesita ver en la
-- tarjeta: foto del residente, nombre, unidad, patente, marca, modelo, color y
-- foto del auto, más cuántos segundos lleva esperando.
-- ============================================================================

create or replace view public.v_solicitudes_vehiculares_pendientes
with (security_invoker = true) as
select
  s.id                    as solicitud_id,
  s.condominio_id,
  s.punto_acceso_id,
  pa.nombre               as punto_acceso,
  s.sentido,
  s.solicitado_en,
  s.expira_en,
  -- Es el contador "hace 4 s" que aparece en la tarjeta
  extract(epoch from (now() - s.solicitado_en))::int as segundos_esperando,

  r.id                    as residente_id,
  r.nombre_completo       as residente,
  r.foto_url              as residente_foto_url,
  r.telefono              as residente_telefono,
  un.numero               as unidad,
  un.torre,

  v.id                    as vehiculo_id,
  v.patente,
  v.marca,
  v.modelo,
  v.color,
  v.foto_url              as vehiculo_foto_url
from public.solicitudes_vehiculares s
join public.usuarios      r  on r.id  = s.residente_id
join public.vehiculos     v  on v.id  = s.vehiculo_id
join public.puntos_acceso pa on pa.id = s.punto_acceso_id
left join public.unidades un on un.id = r.unidad_id
where s.estado = 'pendiente'
  and s.expira_en > now()
order by s.solicitado_en asc;

comment on view public.v_solicitudes_vehiculares_pendientes is
  'Cola en vivo de vehículos esperando que el guardia abra la barrera.';


-- ============================================================================
-- VISTA 3 · INVENTARIO DE PORTERÍA
-- ============================================================================
-- Los paquetes guardados, con los días que llevan esperando ya calculados y la
-- marca de alerta según el límite configurado en el condominio.
-- ============================================================================

create or replace view public.v_paquetes_porteria
with (security_invoker = true) as
select
  p.id,
  p.condominio_id,
  p.numero_seguimiento,
  p.empresa_courier,
  p.descripcion,
  p.foto_url,
  p.recibido_en,
  extract(day from (now() - p.recibido_en))::int as dias_en_porteria,
  -- true = se pinta en rojo en la app
  (now() - p.recibido_en) > (c.dias_alerta_paquete * interval '1 day') as alerta_antiguedad,
  c.dias_alerta_paquete,

  r.id              as residente_id,
  r.nombre_completo as residente,
  r.telefono        as residente_telefono,
  un.numero         as unidad,
  un.torre,

  g.nombre_completo as recibido_por
from public.paquetes p
join public.condominios c on c.id = p.condominio_id
join public.usuarios    r on r.id = p.residente_id
left join public.unidades un on un.id = p.unidad_id
left join public.usuarios  g on g.id = p.guardia_receptor_id
where p.estado = 'en_porteria'
order by p.recibido_en asc;


-- ============================================================================
-- VISTA 4 · VEHÍCULOS ESPERANDO TU APROBACIÓN
-- ============================================================================

create or replace view public.v_vehiculos_por_aprobar
with (security_invoker = true) as
select
  v.id,
  v.condominio_id,
  v.patente,
  v.marca,
  v.modelo,
  v.color,
  v.anio,
  v.foto_url,
  v.foto_patente_url,
  v.creado_en,
  extract(day from (now() - v.creado_en))::int as dias_esperando,

  r.id              as residente_id,
  r.nombre_completo as residente,
  r.foto_url        as residente_foto_url,
  r.telefono        as residente_telefono,
  un.numero         as unidad,
  un.torre,
  -- Cuántos autos ya tiene aprobados este residente
  (select count(*) from public.vehiculos v2
    where v2.residente_id = v.residente_id and v2.estado = 'aprobado') as vehiculos_ya_aprobados
from public.vehiculos v
join public.usuarios r on r.id = v.residente_id
left join public.unidades un on un.id = r.unidad_id
where v.estado = 'pendiente'
order by v.creado_en asc;


-- ============================================================================
-- VISTA 5 · RESUMEN PARA EL PANEL
-- ============================================================================
-- Los números grandes que se ven arriba en el panel del guardia y del
-- administrador, todos en una sola consulta.
-- ============================================================================

create or replace view public.v_resumen_condominio
with (security_invoker = true) as
select
  c.id as condominio_id,
  c.nombre as condominio,

  -- "Hoy" se calcula en la hora de Chile, no en la del servidor. El doble
  -- "at time zone" es lo que hace la conversión ida y vuelta correctamente.
  (select count(*) from public.movimientos_acceso m
    where m.condominio_id = c.id
      and m.ocurrido_en >= (date_trunc('day', now() at time zone c.zona_horaria)
                            at time zone c.zona_horaria)
      and m.sentido = 'entrada' and m.estado = 'aprobado')       as accesos_hoy,

  (select count(*) from public.solicitudes_vehiculares s
    where s.condominio_id = c.id and s.estado = 'pendiente'
      and s.expira_en > now())                                    as autos_esperando,

  (select count(*) from public.paquetes p
    where p.condominio_id = c.id and p.estado = 'en_porteria')     as paquetes_en_porteria,

  (select count(*) from public.paquetes p
    where p.condominio_id = c.id and p.estado = 'en_porteria'
      and (now() - p.recibido_en) > (c.dias_alerta_paquete * interval '1 day'))
                                                                   as paquetes_atrasados,

  (select count(*) from public.vehiculos v
    where v.condominio_id = c.id and v.estado = 'pendiente')       as vehiculos_por_aprobar,

  (select count(*) from public.usuarios u
    where u.condominio_id = c.id and u.rol = 'residente'
      and u.estado = 'activo')                                     as residentes_activos,

  (select count(*) from public.unidades un
    where un.condominio_id = c.id)                                 as unidades,

  (select count(*) from public.turnos t
    where t.condominio_id = c.id and t.cerrado_en is null)         as guardias_en_turno,

  (select count(*) from public.incidentes i
    where i.condominio_id = c.id and i.estado <> 'cerrado')        as incidentes_abiertos,

  (select count(*) from public.visitas vi
    where vi.condominio_id = c.id
      and vi.estado = 'esperando_aprobacion')                      as visitas_esperando_aprobacion,

  (select count(*) from public.v_personas_dentro pd
    where pd.condominio_id = c.id)                                 as personas_dentro
from public.condominios c;


-- ============================================================================
-- FUNCIÓN 1 · REGISTRAR UN MOVIMIENTO
-- ============================================================================
-- La usa la app cada vez que alguien entra o sale.
--
-- Hace dos cosas importantes por su cuenta:
--   1. Guarda una copia del nombre, la unidad y la patente en el momento exacto.
--      Así, si el residente se muda dentro de dos años, el registro viejo sigue
--      leyéndose completo.
--   2. Si la app manda el mismo movimiento dos veces (típico cuando se recupera
--      el internet y reintenta), lo ignora en vez de duplicarlo. Eso lo logra
--      con el id_local que genera el teléfono.
-- ============================================================================

create or replace function public.registrar_movimiento(
  p_id_local          uuid,
  p_persona_tipo      text,
  p_persona_id        uuid,
  p_punto_acceso_id   uuid,
  p_sentido           text,
  p_estado            text     default 'aprobado',
  p_vehiculo_id       uuid     default null,
  p_motivo_denegacion text     default null,
  p_ocurrido_en       timestamptz default null,
  p_offline           boolean  default false,
  p_dispositivo_id    uuid     default null,
  p_geo_lat           numeric  default null,
  p_geo_lng           numeric  default null,
  -- Normalmente la función descubre sola qué guardia está registrando el
  -- movimiento, mirando quién tiene la sesión abierta. Pero cuando la llama el
  -- servidor (no un celular), no hay sesión de nadie, y hay que decírselo.
  p_guardia_id        uuid     default null
)
returns uuid
language plpgsql
set search_path = public, pg_temp
as $$
declare
  v_condominio  uuid;
  v_tipo_acceso text;
  v_nombre      text;
  v_unidad      text;
  v_patente     text;
  v_movimiento  uuid;
begin
  -- El movimiento hereda el condominio y el tipo del punto de acceso
  select pa.condominio_id, pa.tipo
    into v_condominio, v_tipo_acceso
    from public.puntos_acceso pa
   where pa.id = p_punto_acceso_id and pa.activo;

  if v_condominio is null then
    raise exception 'El punto de acceso indicado no existe o está desactivado.';
  end if;

  -- Copia del nombre y la unidad según el tipo de persona
  if p_persona_tipo = 'residente' then
    select u.nombre_completo,
           coalesce(un.numero, '') ||
             coalesce(' ' || nullif(un.torre, ''), '')
      into v_nombre, v_unidad
      from public.usuarios u
      left join public.unidades un on un.id = u.unidad_id
     where u.id = p_persona_id;

  elsif p_persona_tipo = 'visita' then
    select vi.nombre_visitante,
           coalesce(un.numero, '') ||
             coalesce(' ' || nullif(un.torre, ''), ''),
           vi.patente_vehiculo
      into v_nombre, v_unidad, v_patente
      from public.visitas vi
      left join public.usuarios  r  on r.id  = vi.residente_id
      left join public.unidades  un on un.id = coalesce(vi.unidad_id, r.unidad_id)
     where vi.id = p_persona_id;

  elsif p_persona_tipo = 'personal_servicio' then
    select ps.nombre_completo,
           coalesce(un.numero, '') ||
             coalesce(' ' || nullif(un.torre, ''), ''),
           ps.patente_vehiculo
      into v_nombre, v_unidad, v_patente
      from public.personal_servicio ps
      left join public.usuarios r  on r.id  = ps.residente_id
      left join public.unidades un on un.id = coalesce(ps.unidad_id, r.unidad_id)
     where ps.id = p_persona_id;
  else
    raise exception 'Tipo de persona no válido: %', p_persona_tipo;
  end if;

  if v_nombre is null then
    raise exception 'No se encontró la persona indicada (% con id %).',
      p_persona_tipo, p_persona_id;
  end if;

  -- Si el acceso es con vehículo registrado, se copia su patente
  if p_vehiculo_id is not null then
    select v.patente into v_patente
      from public.vehiculos v where v.id = p_vehiculo_id;
  end if;

  insert into public.movimientos_acceso (
    condominio_id, id_local, persona_tipo,
    residente_id, visita_id, personal_servicio_id,
    nombre_snapshot, unidad_snapshot,
    punto_acceso_id, tipo_acceso, sentido,
    vehiculo_id, patente_snapshot,
    estado, motivo_denegacion,
    guardia_id, turno_id, dispositivo_id,
    ocurrido_en, sincronizado_offline, geo_lat, geo_lng
  ) values (
    v_condominio, p_id_local, p_persona_tipo,
    case when p_persona_tipo = 'residente'         then p_persona_id end,
    case when p_persona_tipo = 'visita'            then p_persona_id end,
    case when p_persona_tipo = 'personal_servicio' then p_persona_id end,
    v_nombre, nullif(trim(v_unidad), ''),
    p_punto_acceso_id, v_tipo_acceso, p_sentido,
    p_vehiculo_id, v_patente,
    p_estado, p_motivo_denegacion,
    coalesce(p_guardia_id, case when public.es_guardia() then auth.uid() end),
    public.mi_turno_activo(), p_dispositivo_id,
    coalesce(p_ocurrido_en, now()), p_offline, p_geo_lat, p_geo_lng
  )
  -- Acá está la magia del modo sin internet: si ya existe, no duplica
  on conflict (id_local) do nothing
  returning id into v_movimiento;

  -- Si no insertó nada es porque ya estaba: devolvemos el que ya existía
  if v_movimiento is null then
    select id into v_movimiento
      from public.movimientos_acceso where id_local = p_id_local;
  end if;

  return v_movimiento;
end;
$$;

comment on function public.registrar_movimiento is
  'Registra una entrada o salida. Seguro de reintentar: el mismo id_local no se duplica.';


-- ============================================================================
-- FUNCIÓN 2 · EL GUARDIA APRIETA "ABRIR ACCESO"
-- ============================================================================
-- Todo lo que pasa al tocar el botón gigante verde, en una sola operación:
--   marca la solicitud como aprobada, crea el movimiento de entrada y los deja
--   conectados. Si algo fallara a mitad de camino, no queda nada a medias.
-- ============================================================================

create or replace function public.resolver_solicitud_vehicular(
  p_solicitud_id uuid,
  p_aprobar      boolean,
  p_motivo       text default null
)
returns uuid
language plpgsql
set search_path = public, pg_temp
as $$
declare
  s            public.solicitudes_vehiculares;
  v_movimiento uuid;
begin
  if not public.es_porteria() then
    raise exception 'Solo un guardia o el administrador puede resolver una solicitud.';
  end if;

  select * into s from public.solicitudes_vehiculares
   where id = p_solicitud_id for update;

  if s.id is null then
    raise exception 'La solicitud indicada no existe.';
  end if;

  if s.estado <> 'pendiente' then
    raise exception 'Esta solicitud ya fue resuelta (estado actual: %).', s.estado;
  end if;

  if not p_aprobar and p_motivo is null then
    raise exception 'Para denegar hay que indicar el motivo.';
  end if;

  v_movimiento := public.registrar_movimiento(
    p_id_local          => gen_random_uuid(),
    p_persona_tipo      => 'residente',
    p_persona_id        => s.residente_id,
    p_punto_acceso_id   => s.punto_acceso_id,
    p_sentido           => s.sentido,
    p_estado            => case when p_aprobar then 'aprobado' else 'denegado' end,
    p_vehiculo_id       => s.vehiculo_id,
    p_motivo_denegacion => case when p_aprobar then null else p_motivo end
  );

  update public.solicitudes_vehiculares
     set estado        = case when p_aprobar then 'aprobada' else 'denegada' end,
         resuelto_en   = now(),
         guardia_id    = auth.uid(),
         turno_id      = public.mi_turno_activo(),
         motivo        = p_motivo,
         movimiento_id = v_movimiento
   where id = p_solicitud_id;

  return v_movimiento;
end;
$$;


-- ============================================================================
-- FUNCIÓN 3 · ¿PUEDE ENTRAR ESTE PERSONAL DE SERVICIO?
-- ============================================================================
-- El guardia escanea la credencial de la nana y esta función revisa, en la hora
-- de Chile, si hoy es uno de sus días y si estamos dentro de su horario.
-- La nana de lunes, miércoles y viernes de 8 a 18 no entra un domingo a las 23.
-- ============================================================================

create or replace function public.validar_personal_servicio(p_token text)
returns table (
  permitido    boolean,
  motivo       text,
  personal_id  uuid,
  nombre       text,
  tipo         text,
  foto_url     text,
  unidad       text,
  residente    text
)
language plpgsql
set search_path = public, pg_temp
as $$
declare
  ps          public.personal_servicio;
  v_tz        text;
  v_ahora     timestamp;
  v_dia       smallint;
  v_unidad    text;
  v_residente text;
  v_permitido boolean;
  v_motivo    text;
begin
  select p.* into ps from public.personal_servicio p where p.token_qr = p_token;

  -- Credencial desconocida (o de otro condominio, que para el guardia es lo mismo)
  if ps.id is null then
    return query select false, 'Credencial no reconocida.'::text,
                        null::uuid, null::text, null::text,
                        null::text, null::text, null::text;
    return;
  end if;

  select c.zona_horaria into v_tz
    from public.condominios c where c.id = ps.condominio_id;

  v_ahora := now() at time zone coalesce(v_tz, 'America/Santiago');
  -- isodow: 1 = lunes … 7 = domingo
  v_dia   := extract(isodow from v_ahora)::smallint;

  -- Quién lo contrata y en qué unidad trabaja
  select r.nombre_completo,
         nullif(trim(coalesce(un.numero, '') ||
                     coalesce(' ' || nullif(un.torre, ''), '')), '')
    into v_residente, v_unidad
    from public.usuarios r
    left join public.unidades un on un.id = coalesce(ps.unidad_id, r.unidad_id)
   where r.id = ps.residente_id;

  -- Se revisan los motivos en orden, del más grave al más leve
  if ps.estado = 'pendiente' then
    v_permitido := false;
    v_motivo    := 'Falta que el administrador apruebe esta credencial.';
  elsif ps.estado = 'suspendido' then
    v_permitido := false;
    v_motivo    := 'Credencial suspendida por la administración.';
  elsif ps.estado = 'finalizado' then
    v_permitido := false;
    v_motivo    := 'Ya no trabaja en esta unidad.';
  elsif ps.valido_hasta is not null and v_ahora::date > ps.valido_hasta then
    v_permitido := false;
    v_motivo    := 'La credencial venció el ' ||
                   to_char(ps.valido_hasta, 'DD/MM/YYYY') || '.';
  elsif not (v_dia = any (ps.dias_autorizados)) then
    v_permitido := false;
    v_motivo    := 'Hoy no es uno de sus días autorizados.';
  elsif v_ahora::time not between ps.hora_desde and ps.hora_hasta then
    v_permitido := false;
    v_motivo    := 'Fuera de su horario (' || to_char(ps.hora_desde, 'HH24:MI') ||
                   ' a ' || to_char(ps.hora_hasta, 'HH24:MI') || ').';
  else
    v_permitido := true;
    v_motivo    := 'Autorizado.';
  end if;

  -- Los datos de la persona se devuelven siempre, incluso si no puede entrar:
  -- el guardia necesita ver la foto y el nombre para explicarle por qué no.
  return query select v_permitido, v_motivo, ps.id, ps.nombre_completo,
                      ps.tipo, ps.foto_url, v_unidad, v_residente;
end;
$$;


-- ============================================================================
-- FUNCIÓN 4 · CERRAR TURNO
-- ============================================================================
-- Al cerrar el turno el guardia deja de recibir notificaciones de autos, y su
-- teléfono deja de figurar como el destinatario de ese puesto.
-- ============================================================================

create or replace function public.cerrar_turno(p_notas text default null)
returns uuid
language plpgsql
set search_path = public, pg_temp
as $$
declare v_turno uuid;
begin
  select id into v_turno from public.turnos
   where guardia_id = auth.uid() and cerrado_en is null
   order by inicio desc limit 1;

  if v_turno is null then
    raise exception 'No tenés ningún turno abierto.';
  end if;

  update public.turnos
     set cerrado_en    = now(),
         cerrado_por   = auth.uid(),
         notas_entrega = p_notas
   where id = v_turno;

  return v_turno;
end;
$$;


-- ============================================================================
-- FUNCIÓN 5 · LIMPIEZA AUTOMÁTICA
-- ============================================================================
-- Marca como vencidos los códigos y solicitudes que ya pasaron su hora.
-- Se ejecuta sola cada 5 minutos (se programa en el panel de Supabase, en
-- Database → Cron Jobs).
-- ============================================================================

create or replace function public.expirar_registros_vencidos()
returns table (solicitudes_expiradas int, visitas_expiradas int)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare v_sol int; v_vis int;
begin
  update public.solicitudes_vehiculares
     set estado = 'expirada', resuelto_en = now()
   where estado = 'pendiente' and expira_en <= now();
  get diagnostics v_sol = row_count;

  update public.visitas
     set estado = 'expirada'
   where estado in ('activa','aprobada','esperando_aprobacion')
     and valido_hasta <= now();
  get diagnostics v_vis = row_count;

  return query select v_sol, v_vis;
end;
$$;


-- ============================================================================
-- PERMISOS DE LAS FUNCIONES
-- ============================================================================
-- Primero se le quita el permiso a TODO el mundo, y después se le devuelve solo
-- a quien corresponde. Hacerlo en este orden es lo que evita dejar una función
-- abierta por descuido.
--
-- Por qué se repite el "revoke" que ya estaba en el archivo 02: porque estas
-- funciones se crearon DESPUÉS de ese archivo, y PostgreSQL le regala permiso de
-- ejecución a todo el mundo cada vez que se crea una función nueva.
-- ============================================================================

revoke execute on all functions in schema public from public;
revoke execute on all functions in schema public from anon;

-- La app (usuario con sesión iniciada) puede usar estas cuatro y nada más:
grant execute on function
  public.registrar_movimiento,
  public.resolver_solicitud_vehicular,
  public.validar_personal_servicio,
  public.cerrar_turno
to authenticated;

-- Y las funciones de apoyo del archivo 02, que las reglas de seguridad necesitan:
grant execute on function
  public.mi_condominio, public.mi_rol, public.es_administrador,
  public.es_guardia, public.es_porteria, public.mi_turno_activo,
  public.mi_punto_acceso
to authenticated;

-- La limpieza automática la corre el servidor con su llave secreta, nunca la app.
-- Esa llave NO va dentro del celular: vive solo en el servidor.
grant execute on all functions in schema public to service_role;


-- ============================================================================
-- AVISOS EN VIVO (lo que reemplaza a Socket.io)
-- ============================================================================
-- Estas tres líneas hacen que la pantalla del guardia se actualice sola, sin
-- que él toque nada y sin que la app pregunte cada dos segundos. Cuando aparece
-- un auto esperando, la tablet lo recibe al instante.
--
-- Esto es lo que en el plan original iba a requerir un servidor aparte con
-- Socket.io. Con Supabase son tres líneas.
-- ============================================================================

alter publication supabase_realtime add table public.solicitudes_vehiculares;
alter publication supabase_realtime add table public.notificaciones;
alter publication supabase_realtime add table public.visitas;


-- ============================================================================
-- FIN DEL ARCHIVO 03
-- Siguiente paso: ejecutar 04-datos-de-ejemplo.sql
-- ============================================================================
