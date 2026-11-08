-- ============================================================================
-- Tomass Seguridad — 32 · Auto-asignar guardias a instalaciones
-- ============================================================================
-- ⚠️ ESTE ARCHIVO YA ESTÁ APLICADO EN EL SERVIDOR. Queda para el historial.
--
-- POR QUÉ
--
--   El 08/11/2026 Manuel pidió que todos los guardias puedan elegir su
--   instalación desde la app (no solo los que tenían administra_instalaciones
--   con varias entradas). Se hizo un backfill masivo asignando los 37
--   guardias activos a las 14 instalaciones.
--
--   Pero eso resuelve el estado AHORA. Cuando Manuel cree una instalación
--   nueva más adelante (cosa que viene pasando — PY La Serena se agregó
--   esta semana) los guardias NO se van a agregar solos y va a tener que
--   pedirme un UPDATE o entrar a SQL manualmente.
--
--   Dos piezas para automatizar esto:
--
--     1) RPC `asignar_todos_los_guardias_a(condominio_id)` — para disparar a
--        mano cuando Manuel quiera, desde el panel admin.
--
--     2) Trigger en la tabla condominios: cuando se INSERTA un condominio
--        activo, auto-asigna a TODOS los guardias y admins activos. Sin
--        necesidad de llamar la RPC.
-- ============================================================================


-- ============================================================================
-- RPC: ASIGNAR TODOS LOS GUARDIAS A UNA INSTALACIÓN
-- ============================================================================
-- Solo administradores pueden llamarla. Devuelve cuántos nuevos accesos
-- insertó (los guardias que ya tenían la instalación asignada no cuentan).
-- ============================================================================

create or replace function public.asignar_todos_los_guardias_a(
  p_condominio_id uuid
) returns integer
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $$
declare
  v_nuevos integer;
begin
  if not public.es_administrador() then
    raise exception 'Solo la administración puede asignar guardias.'
      using errcode = 'insufficient_privilege';
  end if;

  -- Validar que el condominio exista y esté activo.
  if not exists (
    select 1 from public.condominios
     where id = p_condominio_id and activo = true
  ) then
    raise exception 'Esa instalación no existe o está desactivada.'
      using errcode = 'no_data_found';
  end if;

  with insertados as (
    insert into public.administra_instalaciones (usuario_id, condominio_id)
      select u.id, p_condominio_id
        from public.usuarios u
       where u.rol in ('guardia','administrador')
         and u.estado = 'activo'
    on conflict do nothing
    returning 1
  )
  select count(*)::int into v_nuevos from insertados;

  return v_nuevos;
end;
$$;

grant execute on function
  public.asignar_todos_los_guardias_a(uuid) to authenticated;


-- ============================================================================
-- TRIGGER: AUTO-ASIGNAR AL CREAR INSTALACIÓN
-- ============================================================================
-- Al INSERT de un condominio activo, asigna a todos los guardias y admins
-- activos automáticamente. Así Manuel crea la instalación y listo, sin
-- acordarse de llamar a asignar_todos_los_guardias_a().
-- ============================================================================

create or replace function public._tg_asignar_guardias_a_nueva_instalacion()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $$
begin
  if new.activo then
    insert into public.administra_instalaciones (usuario_id, condominio_id)
      select u.id, new.id
        from public.usuarios u
       where u.rol in ('guardia','administrador')
         and u.estado = 'activo'
    on conflict do nothing;
  end if;
  return new;
end;
$$;

drop trigger if exists asignar_guardias_al_crear_condominio on public.condominios;
create trigger asignar_guardias_al_crear_condominio
  after insert on public.condominios
  for each row
  execute function public._tg_asignar_guardias_a_nueva_instalacion();


-- ============================================================================
-- FIN DEL ARCHIVO 32
-- ============================================================================
