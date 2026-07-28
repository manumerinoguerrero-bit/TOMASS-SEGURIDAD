-- ============================================================================
-- Tomass Seguridad — 07 · UN GUARDIA QUE CUBRE TODO EL CONDOMINIO
-- ============================================================================
-- QUÉ CAMBIA Y POR QUÉ
--
--   El diseño original asumía un guardia por puerta: uno en la garita peatonal
--   y otro en la caseta vehicular, cada uno recibiendo solo los avisos de su
--   puesto.
--
--   En la realidad de este condominio hay UN SOLO GUARDIA, y tiene que atender
--   las dos entradas al mismo tiempo. Con el diseño anterior, si elegía la
--   entrada vehicular no se enteraba de los peatones, y si elegía la peatonal
--   no veía los autos esperando en la barrera. Quedaba ciego a la mitad.
--
-- CÓMO SE RESUELVE
--
--   El turno ahora puede no tener puesto asignado. Cuando el puesto queda
--   vacío, significa "este guardia cubre TODO el condominio" y le llegan
--   absolutamente todos los avisos, de cualquier entrada.
--
--   Se mantiene la posibilidad de asignar un puesto puntual, porque un
--   condominio más grande sí puede tener dos guardias y conviene que cada uno
--   reciba lo suyo. Pero el caso normal pasa a ser "cubre todo".
--
-- Cómo se usa:
--   Pegá TODO este archivo en el editor SQL de Supabase y presioná "Run".
--   Ejecutar DESPUÉS de 06-guardado-de-fotos.sql.
-- ============================================================================


-- ============================================================================
-- 1 · EL PUESTO PASA A SER OPCIONAL
-- ============================================================================

alter table public.turnos
  alter column punto_acceso_id drop not null;

comment on column public.turnos.punto_acceso_id is
  'Puesto donde esta el guardia. Si esta VACIO, cubre todo el condominio y le '
  'llegan los avisos de todas las entradas. Ese es el caso normal cuando hay un '
  'solo guardia.';


-- ============================================================================
-- 2 · A QUIÉN HAY QUE AVISARLE
-- ============================================================================
-- Esta función reemplaza la búsqueda que hacía el servidor. Devuelve los
-- guardias que tienen que enterarse de algo que pasó en una entrada:
--
--   · los que están parados en ESA entrada, y
--   · los que cubren TODO el condominio.
--
-- Está en la base de datos y no en el servidor a propósito: así la regla es una
-- sola y no hay que acordarse de repetirla en cada función que avisa.
-- ============================================================================

create or replace function public.guardias_a_avisar(p_punto_acceso_id uuid)
returns table (guardia_id uuid)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select t.guardia_id
    from public.turnos t
    join public.puntos_acceso pa on pa.id = p_punto_acceso_id
   where t.cerrado_en is null
     and t.condominio_id = pa.condominio_id
     and (
       -- está parado justo en esa entrada
       t.punto_acceso_id = p_punto_acceso_id
       -- o cubre todo el condominio
       or t.punto_acceso_id is null
     );
$$;

revoke execute on function public.guardias_a_avisar(uuid) from public, anon;
grant  execute on function public.guardias_a_avisar(uuid) to authenticated, service_role;


-- ============================================================================
-- 3 · EL PUESTO DEL GUARDIA, PARA LA APP
-- ============================================================================
-- Devuelve null tanto si no tiene turno abierto como si cubre todo. La app
-- distingue los dos casos mirando si hay turno.
-- ============================================================================

create or replace function public.cubro_todo_el_condominio()
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select coalesce(
    (select punto_acceso_id is null
       from public.turnos
      where guardia_id = auth.uid() and cerrado_en is null
      order by inicio desc limit 1),
    false);
$$;

revoke execute on function public.cubro_todo_el_condominio() from public, anon;
grant  execute on function public.cubro_todo_el_condominio() to authenticated, service_role;


-- ============================================================================
-- 4 · LA COLA DE AUTOS, PARA UN GUARDIA QUE CUBRE TODO
-- ============================================================================
-- La vista de autos esperando ya trae el punto de acceso de cada uno, así que
-- la app puede filtrar o no según corresponda. No hace falta cambiarla.
--
-- Lo que sí se agrega es un índice: cuando el guardia cubre todo, la consulta
-- pide TODAS las solicitudes pendientes del condominio en lugar de las de un
-- punto. Sin este índice esa consulta recorrería la tabla entera.
-- ============================================================================

create index if not exists ix_solicitudes_pendientes_condominio
  on public.solicitudes_vehiculares (condominio_id, solicitado_en)
  where estado = 'pendiente';


-- ============================================================================
-- 5 · EL CONDOMINIO DE PRUEBA PASA A TENER UN SOLO GUARDIA
-- ============================================================================
-- Se cierra el turno de Luis y el de Carlos pasa a cubrir todo, que es como
-- va a funcionar de verdad.
--
-- ⚠️ Esta parte es SOLO para el condominio de prueba. No afecta a un condominio
--    real: ahí los turnos los abre cada guardia desde su celular.
-- ============================================================================

do $$
declare v_condominio uuid;
begin
  select id into v_condominio
    from public.condominios
   where nombre = 'Condominio Los Aromos';

  if v_condominio is null then
    raise notice 'No esta el condominio de prueba. Se omite este paso.';
    return;
  end if;

  -- Luis termina su turno
  update public.turnos
     set cerrado_en = now(),
         notas_entrega = 'Turno cerrado: ahora hay un solo guardia que cubre todo.'
   where condominio_id = v_condominio
     and cerrado_en is null
     and guardia_id = '33333333-3333-3333-3333-333333333333';

  -- Carlos pasa a cubrir todo el condominio
  update public.turnos
     set punto_acceso_id = null
   where condominio_id = v_condominio
     and cerrado_en is null
     and guardia_id = '22222222-2222-2222-2222-222222222222';
end $$;


-- ============================================================================
-- 6 · REVISIÓN
-- ============================================================================

-- Esperado: 1 fila (Carlos), con puesto vacío = cubre todo
select u.nombre_completo as guardia,
       coalesce(pa.nombre, 'TODO EL CONDOMINIO') as puesto,
       to_char(t.inicio, 'HH24:MI') as desde
  from public.turnos t
  join public.usuarios u on u.id = t.guardia_id
  left join public.puntos_acceso pa on pa.id = t.punto_acceso_id
 where t.cerrado_en is null
 order by t.inicio;

-- Esperado: Carlos aparece para las DOS entradas, porque cubre todo
select pa.nombre as entrada,
       u.nombre_completo as le_avisa_a
  from public.puntos_acceso pa
  cross join lateral public.guardias_a_avisar(pa.id) g
  join public.usuarios u on u.id = g.guardia_id
 order by pa.nombre;


-- ============================================================================
-- FIN DEL ARCHIVO 07
-- ============================================================================
