-- ============================================================================
-- 40 · Claves de 10 caracteres y secreto interno (SEG-08) + arreglos menores
-- ============================================================================
-- Qué cambia:
--
--   1. CLAVES DE 10 CARACTERES. En el panel de Supabase el largo mínimo de
--      clave pasa a 10. Pero crear_guardia_nuevo y cambiar_clave_de_guardia
--      escriben la clave directo en auth.users y se SALTAN ese ajuste: seguían
--      aceptando 6. Acá se suben a 10. Las claves que ya existen siguen
--      funcionando; la regla solo aplica al crear o cambiar una clave.
--      (Cuerpos copiados de producción el 13/11/2026; solo cambia el número.)
--
--   2. SEG-08 · SECRETO INTERNO. El trigger del aviso de novedad crítica y el
--      cron de limpieza de fotos llaman a funciones del servidor con la llave
--      pública del proyecto (la misma que va en la app). Desde ahora además
--      mandan la cabecera x-tomass-secreto con el valor guardado en el vault
--      como tomass_secreto_interno, y las funciones lo exigen.
--      El cron además dejaba la llave escrita tal cual en su comando; ahora la
--      lee del vault como el trigger.
--
--      EL VALOR DEL SECRETO NO VA EN ESTE ARCHIVO (el repo es público). Se
--      genera al azar dentro de la base, una sola vez, y nunca sale de ahí:
--        select vault.create_secret(
--          encode(extensions.gen_random_bytes(32), 'hex'),
--          'tomass_secreto_interno',
--          'SEG-08: secreto de las llamadas internas a Edge Functions');
--      Las funciones no lo guardan como variable de entorno: le preguntan a
--      la base con _secreto_interno_valido(), que solo puede usar el
--      servidor (service_role).
--
--      Mientras el secreto no exista en el vault, el trigger y el cron llaman
--      igual que antes (sin la cabecera). Así este archivo se puede aplicar
--      antes de publicar las funciones nuevas sin cortar ningún aviso.
--
--   3. ARREGLOS MENORES (avisos de Supabase): metros_entre y
--      palabras_de_la_instalacion quedan con search_path fijo. Solo usan
--      funciones de Postgres, así que no cambia nada de lo que devuelven.
--
--   Queda fuera a propósito: mover pg_net fuera del esquema public. pg_net no
--   se puede mover; habría que desinstalarlo y reinstalarlo, y eso corta los
--   avisos y el cron mientras tanto. Sus funciones igual viven en el esquema
--   "net", así que el riesgo real es mínimo.
-- ============================================================================


-- ----------------------------------------------------------------------------
-- 1 · Claves de al menos 10 caracteres
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.cambiar_clave_de_guardia(p_guardia_id uuid, p_nueva_clave text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp', 'auth', 'extensions'
AS $function$
begin
  if not public.es_administrador() then
    raise exception 'Solo la administración puede cambiar la clave de un guardia.' using errcode='insufficient_privilege';
  end if;
  if length(p_nueva_clave) < 10 then
    raise exception 'La clave nueva debe tener al menos 10 caracteres.' using errcode='check_violation';
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
  update auth.users
     set encrypted_password = extensions.crypt(p_nueva_clave, extensions.gen_salt('bf', 10)), updated_at = now()
   where id = p_guardia_id;
  delete from auth.refresh_tokens where user_id = p_guardia_id::text;
end; $function$;

CREATE OR REPLACE FUNCTION public.crear_guardia_nuevo(p_email text, p_password text, p_nombre_completo text, p_condominio_id uuid, p_telefono text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp', 'extensions'
AS $function$
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
  if length(p_password) < 10 then
    raise exception 'La contraseña debe tener al menos 10 caracteres.' using errcode='check_violation';
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


-- ----------------------------------------------------------------------------
-- 2 · SEG-08 · Cabeceras para llamar a funciones internas del servidor
-- ----------------------------------------------------------------------------
-- Arma las cabeceras de una llamada interna leyendo todo del vault. Si el
-- secreto todavía no existe, devuelve las cabeceras de siempre (sin
-- x-tomass-secreto). Solo la usan el trigger y el cron, nadie desde la app.

CREATE OR REPLACE FUNCTION public._cabeceras_llamada_interna()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp', 'vault'
AS $function$
DECLARE
  v_key     text;
  v_secreto text;
  v_cab     jsonb;
BEGIN
  SELECT decrypted_secret INTO v_key
    FROM vault.decrypted_secrets WHERE name = 'tomass_funciones_auth_key';
  SELECT decrypted_secret INTO v_secreto
    FROM vault.decrypted_secrets WHERE name = 'tomass_secreto_interno';

  IF v_key IS NULL OR length(v_key) = 0 THEN
    RETURN NULL;
  END IF;

  v_cab := jsonb_build_object(
    'Content-Type',  'application/json',
    'Authorization', 'Bearer ' || v_key
  );
  IF v_secreto IS NOT NULL AND length(v_secreto) > 0 THEN
    v_cab := v_cab || jsonb_build_object('x-tomass-secreto', v_secreto);
  END IF;
  RETURN v_cab;
END;
$function$;

REVOKE ALL ON FUNCTION public._cabeceras_llamada_interna() FROM public, anon, authenticated;

-- La función del servidor pregunta acá si el secreto que le llegó es el
-- correcto. Solo service_role la puede ejecutar; si el secreto no existe en
-- el vault, contesta false (falla cerrada).
CREATE OR REPLACE FUNCTION public._secreto_interno_valido(p_secreto text)
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp', 'vault'
AS $function$
  select coalesce(
    (select length(ds.decrypted_secret) >= 32
            and ds.decrypted_secret = p_secreto
       from vault.decrypted_secrets ds
      where ds.name = 'tomass_secreto_interno'),
    false);
$function$;

REVOKE ALL ON FUNCTION public._secreto_interno_valido(text) FROM public, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._secreto_interno_valido(text) TO service_role;

-- El trigger del aviso de novedad crítica, igual que antes pero con las
-- cabeceras nuevas.
CREATE OR REPLACE FUNCTION public._disparar_aviso_novedad_critica()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp', 'net', 'vault'
AS $function$
DECLARE
  v_url      text;
  v_cab      jsonb;
  v_gravedad text := lower(coalesce(NEW.gravedad, ''));
  v_estado   text := lower(coalesce(NEW.estado,   ''));
BEGIN
  IF v_estado <> 'abierto' THEN
    RETURN NEW;
  END IF;
  IF v_gravedad NOT IN ('critica', 'alta') THEN
    RETURN NEW;
  END IF;

  SELECT decrypted_secret INTO v_url
    FROM vault.decrypted_secrets WHERE name = 'tomass_funciones_url';
  v_cab := public._cabeceras_llamada_interna();

  IF v_url IS NULL OR length(v_url) = 0 OR v_cab IS NULL THEN
    RAISE WARNING 'avisar-novedad-critica: faltan secrets tomass_funciones_url / tomass_funciones_auth_key en el vault';
    RETURN NEW;
  END IF;

  PERFORM net.http_post(
    url     := v_url || '/avisar-novedad-critica',
    body    := jsonb_build_object('incidenteId', NEW.id::text),
    headers := v_cab,
    timeout_milliseconds := 5000
  );

  RETURN NEW;
EXCEPTION
  WHEN OTHERS THEN
    RAISE WARNING 'avisar-novedad-critica: fallo silencioso (%): %', SQLSTATE, SQLERRM;
    RETURN NEW;
END;
$function$;

-- El cron de limpieza de fotos: deja de tener la llave escrita en el comando
-- y pasa a leer URL y cabeceras del vault.
DO $$
DECLARE
  v_job bigint;
BEGIN
  SELECT jobid INTO v_job FROM cron.job
   WHERE jobname = 'borrar-fotos-de-encomiendas-viejas';
  IF v_job IS NULL THEN
    RAISE NOTICE 'No existe el cron borrar-fotos-de-encomiendas-viejas; no se cambia nada.';
    RETURN;
  END IF;
  PERFORM cron.alter_job(
    job_id  := v_job,
    command := $cmd$
  select net.http_post(
    url     := (select decrypted_secret from vault.decrypted_secrets
                 where name = 'tomass_funciones_url') || '/limpiar-fotos',
    headers := public._cabeceras_llamada_interna(),
    body    := '{}'::jsonb,
    timeout_milliseconds := 60000
  );
$cmd$
  );
END;
$$;


-- ----------------------------------------------------------------------------
-- 3 · Arreglos menores: search_path fijo
-- ----------------------------------------------------------------------------

ALTER FUNCTION public.metros_entre(numeric, numeric, numeric, numeric) SET search_path = '';
ALTER FUNCTION public.palabras_de_la_instalacion(text) SET search_path = '';


-- ----------------------------------------------------------------------------
-- Para revisar después de aplicar
-- ----------------------------------------------------------------------------
--   -- ¿Las cabeceras llevan el secreto? (debe decir true una vez creado)
--   select public._cabeceras_llamada_interna() ? 'x-tomass-secreto';
--
--   -- ¿Cómo le fue al cron anoche?
--   select status, start_time, return_message
--     from cron.job_run_details order by start_time desc limit 5;
--   select status_code, content from net._http_response
--    order by created desc limit 5;
-- ============================================================================
-- FIN DEL ARCHIVO 40
-- ============================================================================
