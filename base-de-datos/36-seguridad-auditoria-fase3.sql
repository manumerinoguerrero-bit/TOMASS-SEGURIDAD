-- ============================================================================
-- 36 · Auditoría de seguridad — Fase 3 (SEG-07 y SEG-09 parte base)
-- ============================================================================
--   SEG-07 (media) · 40 funciones y varias tablas quedaron ejecutables/
--     accesibles por `anon` (migraciones 15-32 no heredaron el REVOKE). Se
--     conserva explícitamente lo que hoy usa `authenticated`, se cierra todo
--     para public/anon, se bloquean 4 funciones internas, y se fija el default
--     para que no vuelva a pasar. El login NO usa RPC (va por Supabase Auth),
--     así que cerrar anon no lo afecta.
--   SEG-09 (media, parte base) · Las claves que generan crear_guardia_nuevo y
--     cambiar_clave_de_guardia se hasheaban con bcrypt costo por defecto (6),
--     ~16x más baratas de atacar que el costo 10 de Supabase Auth. Se sube a 10.
--     (La longitud mínima 10 y la config de Auth van en un cambio coordinado
--     con la app.)
-- ============================================================================

-- ----------------------------------------------------------------------------
-- SEG-07 · Cerrar la superficie expuesta a anon/public
-- ----------------------------------------------------------------------------

-- 1. Conservar explícitamente lo que authenticated ya puede ejecutar (varias
--    funciones dependían del permiso heredado de PUBLIC).
do $$
declare f record;
begin
  for f in
    select p.oid::regprocedure as firma
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public'
       and p.prokind = 'f'
       and has_function_privilege('authenticated', p.oid, 'EXECUTE')
       and not exists (select 1 from pg_depend d
                        where d.objid = p.oid and d.deptype = 'e')
  loop
    execute format('grant execute on function %s to authenticated', f.firma);
  end loop;
end $$;

-- 2. Cerrar ejecución para public/anon.
revoke execute on all functions in schema public from public, anon;

-- 3. Funciones internas: ni siquiera para usuarios con sesión (las llama el
--    cron o un trigger, nunca el cliente).
revoke execute on function
  public.purgar_ubicaciones_viejas(),
  public.expirar_registros_vencidos(),
  public._disparar_aviso_novedad_critica(),
  public._tg_asignar_guardias_a_nueva_instalacion()
  from authenticated;

-- 4. Tablas: anon no accede a nada (RLS ya lo bloquea, esto es la barrera de
--    más afuera); authenticated no necesita TRUNCATE/REFERENCES/TRIGGER.
revoke all on all tables in schema public from anon;
revoke truncate, references, trigger on all tables in schema public from authenticated;

-- 5. Que no vuelva a pasar, cualquiera sea el rol que cree objetos nuevos.
alter default privileges for role postgres in schema public
  revoke execute on functions from public, anon;
alter default privileges for role postgres in schema public
  revoke all on tables from anon;

-- ----------------------------------------------------------------------------
-- SEG-09 (parte base) · bcrypt costo 10 en las RPC que escriben la clave
-- ----------------------------------------------------------------------------
create or replace function public.cambiar_clave_de_guardia(p_guardia_id uuid, p_nueva_clave text)
returns void language plpgsql security definer
set search_path to 'public', 'pg_temp', 'auth', 'extensions'
as $function$
begin
  if not public.es_administrador() then
    raise exception 'Solo la administración puede cambiar la clave de un guardia.'
      using errcode = 'insufficient_privilege';
  end if;
  if length(p_nueva_clave) < 6 then
    raise exception 'La clave nueva debe tener al menos 6 caracteres.'
      using errcode = 'check_violation';
  end if;
  if not exists (
    select 1 from public.usuarios u
    where u.id = p_guardia_id and u.rol = 'guardia'
      and (u.condominio_id in (select id from public.mis_instalaciones())
           or exists (select 1 from public.administra_instalaciones ai
                      where ai.usuario_id = u.id
                        and ai.condominio_id in (select id from public.mis_instalaciones())))
  ) then
    raise exception 'Ese guardia no esta en tus instalaciones.'
      using errcode = 'insufficient_privilege';
  end if;
  update auth.users
     set encrypted_password = extensions.crypt(p_nueva_clave, extensions.gen_salt('bf', 10)),
         updated_at = now()
   where id = p_guardia_id;
  delete from auth.refresh_tokens where user_id = p_guardia_id::text;
end;
$function$;
revoke execute on function public.cambiar_clave_de_guardia(uuid, text) from public, anon;
grant execute on function public.cambiar_clave_de_guardia(uuid, text) to authenticated;

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
    raise exception 'Solo la administración puede dar de alta guardias.'
      using errcode = 'insufficient_privilege';
  end if;
  if v_email = '' or v_email !~ '.+@.+\..+' then
    raise exception 'Email inválido.' using errcode = 'check_violation';
  end if;
  if length(p_password) < 6 then
    raise exception 'La contraseña debe tener al menos 6 caracteres.'
      using errcode = 'check_violation';
  end if;
  if length(v_nombre) < 3 then
    raise exception 'Falta el nombre completo del guardia.'
      using errcode = 'check_violation';
  end if;
  if exists(select 1 from auth.users where email = v_email) then
    raise exception 'Ya existe una cuenta con ese email.'
      using errcode = 'unique_violation';
  end if;

  insert into auth.users (
    id, instance_id, email, encrypted_password, email_confirmed_at,
    aud, role, created_at, updated_at, raw_app_meta_data, raw_user_meta_data,
    confirmation_token, recovery_token, email_change_token_new,
    email_change, email_change_token_current, reauthentication_token,
    phone_change, phone_change_token
  ) values (
    v_id, '00000000-0000-0000-0000-000000000000', v_email,
    extensions.crypt(p_password, extensions.gen_salt('bf', 10)),
    now(), 'authenticated', 'authenticated', now(), now(),
    '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb,
    '', '', '', '', '', '', '', ''
  );

  insert into auth.identities (
    id, user_id, identity_data, provider, provider_id,
    created_at, updated_at, last_sign_in_at
  ) values (
    gen_random_uuid(), v_id,
    jsonb_build_object('sub', v_id::text, 'email', v_email, 'email_verified', true),
    'email', v_id::text, now(), now(), now()
  );

  insert into public.usuarios (id, condominio_id, email, nombre_completo, telefono, rol)
  values (v_id, p_condominio_id, v_email, v_nombre,
          nullif(trim(coalesce(p_telefono, '')), ''), 'guardia');

  insert into public.administra_instalaciones (usuario_id, condominio_id)
  values (v_id, p_condominio_id)
  on conflict do nothing;

  return v_id;
end;
$function$;
revoke execute on function public.crear_guardia_nuevo(text, text, text, uuid, text) from public, anon;
grant execute on function public.crear_guardia_nuevo(text, text, text, uuid, text) to authenticated;
