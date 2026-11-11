-- ============================================================================
-- 37 · Auditoría de seguridad — Fase 4 (SEG-06)
-- ============================================================================
-- Las RPC de gestión de guardias ahora exigen que la instalación destino sea
-- una de las del administrador (mis_instalaciones). Hoy, con un solo
-- administrador que ve todas las instalaciones, no cambia el comportamiento;
-- deja el sistema correcto para cuando exista un segundo administrador o un
-- mandante por cliente. No se toca el trigger de auto-asignación ni la
-- asignación de administradores (decisión de negocio, ver SEG-06).
-- ============================================================================

create or replace function public.asignar_todos_los_guardias_a(p_condominio_id uuid)
returns integer language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $function$
declare v_nuevos integer;
begin
  if not public.es_administrador() then
    raise exception 'Solo la administración puede asignar guardias.' using errcode='insufficient_privilege';
  end if;
  if p_condominio_id not in (select id from public.mis_instalaciones()) then
    raise exception 'Esa instalación no es una de las tuyas.' using errcode='insufficient_privilege';
  end if;
  if not exists (select 1 from public.condominios where id = p_condominio_id and activo = true) then
    raise exception 'Esa instalación no existe o está desactivada.' using errcode='no_data_found';
  end if;
  with insertados as (
    insert into public.administra_instalaciones (usuario_id, condominio_id)
      select u.id, p_condominio_id from public.usuarios u
       where u.rol in ('guardia','administrador') and u.estado = 'activo'
    on conflict do nothing returning 1
  )
  select count(*)::int into v_nuevos from insertados;
  return v_nuevos;
end; $function$;
revoke execute on function public.asignar_todos_los_guardias_a(uuid) from public, anon;
grant execute on function public.asignar_todos_los_guardias_a(uuid) to authenticated;

create or replace function public.cerrar_sesion_guardia(p_guardia_id uuid)
returns void language plpgsql security definer
set search_path to 'public', 'pg_temp', 'auth'
as $function$
begin
  if not public.es_administrador() then
    raise exception 'Solo la administración puede cerrar sesiones.' using errcode='insufficient_privilege';
  end if;
  if not exists (
    select 1 from public.usuarios u
    where u.id = p_guardia_id and u.rol = 'guardia'
      and (u.condominio_id in (select id from public.mis_instalaciones())
           or exists (select 1 from public.administra_instalaciones ai
                      where ai.usuario_id = u.id and ai.condominio_id in (select id from public.mis_instalaciones())))
  ) then
    raise exception 'Ese guardia no esta en tus instalaciones.' using errcode='insufficient_privilege';
  end if;
  delete from auth.refresh_tokens where user_id = p_guardia_id::text;
  update public.turnos set cerrado_en = now(), notas_entrega = 'Cerrado por el administrador.'
   where guardia_id = p_guardia_id and cerrado_en is null;
end; $function$;
revoke execute on function public.cerrar_sesion_guardia(uuid) from public, anon;
grant execute on function public.cerrar_sesion_guardia(uuid) to authenticated;

create or replace function public.reactivar_guardia(p_guardia_id uuid)
returns void language plpgsql security definer
set search_path to 'public', 'pg_temp', 'auth'
as $function$
declare v_condo_principal uuid;
begin
  if not public.es_administrador() then
    raise exception 'Solo la administración puede reactivar guardias.' using errcode='insufficient_privilege';
  end if;
  select condominio_id into v_condo_principal from public.usuarios where id = p_guardia_id and rol = 'guardia';
  if v_condo_principal is null then
    raise exception 'Ese guardia no existe.' using errcode='insufficient_privilege';
  end if;
  if v_condo_principal not in (select id from public.mis_instalaciones()) then
    raise exception 'Ese guardia no esta en tus instalaciones.' using errcode='insufficient_privilege';
  end if;
  update public.usuarios set estado = 'activo', motivo_inactivo = null, inactivo_desde = null where id = p_guardia_id;
  update auth.users set banned_until = null where id = p_guardia_id;
  insert into public.administra_instalaciones (usuario_id, condominio_id)
  select p_guardia_id, c.id from public.condominios c
  where c.id <> v_condo_principal and c.activo and c.id in (select id from public.mis_instalaciones())
  on conflict do nothing;
end; $function$;
revoke execute on function public.reactivar_guardia(uuid) from public, anon;
grant execute on function public.reactivar_guardia(uuid) to authenticated;

create or replace function public.crear_guardia_nuevo(p_email text, p_password text, p_nombre_completo text, p_condominio_id uuid, p_telefono text default null::text)
returns uuid language plpgsql security definer
set search_path to 'public', 'pg_temp', 'extensions'
as $function$
declare
  v_id uuid := gen_random_uuid();
  v_email text := lower(trim(p_email));
  v_nombre text := trim(p_nombre_completo);
begin
  if not public.es_administrador() then
    raise exception 'Solo la administración puede dar de alta guardias.' using errcode='insufficient_privilege';
  end if;
  if p_condominio_id not in (select id from public.mis_instalaciones()) then
    raise exception 'Esa instalación no es una de las tuyas.' using errcode='insufficient_privilege';
  end if;
  if v_email = '' or v_email !~ '.+@.+\..+' then
    raise exception 'Email inválido.' using errcode='check_violation';
  end if;
  if length(p_password) < 6 then
    raise exception 'La contraseña debe tener al menos 6 caracteres.' using errcode='check_violation';
  end if;
  if length(v_nombre) < 3 then
    raise exception 'Falta el nombre completo del guardia.' using errcode='check_violation';
  end if;
  if exists(select 1 from auth.users where email = v_email) then
    raise exception 'Ya existe una cuenta con ese email.' using errcode='unique_violation';
  end if;
  insert into auth.users (
    id, instance_id, email, encrypted_password, email_confirmed_at,
    aud, role, created_at, updated_at, raw_app_meta_data, raw_user_meta_data,
    confirmation_token, recovery_token, email_change_token_new,
    email_change, email_change_token_current, reauthentication_token, phone_change, phone_change_token
  ) values (
    v_id, '00000000-0000-0000-0000-000000000000', v_email,
    extensions.crypt(p_password, extensions.gen_salt('bf', 10)),
    now(), 'authenticated', 'authenticated', now(), now(),
    '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb,
    '', '', '', '', '', '', '', ''
  );
  insert into auth.identities (id, user_id, identity_data, provider, provider_id, created_at, updated_at, last_sign_in_at)
  values (gen_random_uuid(), v_id,
    jsonb_build_object('sub', v_id::text, 'email', v_email, 'email_verified', true),
    'email', v_id::text, now(), now(), now());
  insert into public.usuarios (id, condominio_id, email, nombre_completo, telefono, rol)
  values (v_id, p_condominio_id, v_email, v_nombre, nullif(trim(coalesce(p_telefono, '')), ''), 'guardia');
  insert into public.administra_instalaciones (usuario_id, condominio_id)
  values (v_id, p_condominio_id) on conflict do nothing;
  return v_id;
end; $function$;
revoke execute on function public.crear_guardia_nuevo(text, text, text, uuid, text) from public, anon;
grant execute on function public.crear_guardia_nuevo(text, text, text, uuid, text) to authenticated;
