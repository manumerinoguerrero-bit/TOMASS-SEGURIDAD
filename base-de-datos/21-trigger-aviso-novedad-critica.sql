-- ============================================================================
-- Tomass Seguridad — Push al admin ante novedad CRÍTICA o ALTA
-- ============================================================================
-- Pedido por Manuel el 01/10/2026: cuando un guardia reporta una novedad con
-- gravedad "critica" o "alta" (estado "abierto"), hacer sonar los celulares
-- de todos los admins activos del condominio aunque la app esté cerrada.
--
-- CÓMO FUNCIONA
--
--   1. Trigger AFTER INSERT ON incidentes.
--   2. Si gravedad IN ('critica','alta') AND estado = 'abierto', dispara
--      un POST asincrónico a la Edge Function `avisar-novedad-critica`
--      vía pg_net.
--   3. La Edge Function reaprueba la criticidad, lee los admins del
--      condominio y llama al helper `avisar()` existente que hace lo
--      mismo que ya hace para cualquier otro aviso (notificacion in-app
--      + push FCM si Firebase está configurado).
--
-- POR QUÉ NO HAY LLAMADA SÍNCRONA DESDE EL TRIGGER
--
--   El INSERT del incidente no puede esperar a que Google conteste. Si
--   FCM está lento o caído, un acceso del guardia no debe demorarse ni
--   fallar por eso. net.http_post encola el request y vuelve en
--   milisegundos; la Edge Function corre en background.
--
-- CREDENCIALES (secrets en Supabase Vault)
--
--   El trigger necesita saber la URL de la edge function y una llave para
--   autenticar la llamada. Se guardan en vault.secrets por dos razones:
--
--     - Las lecturas son inmediatas (no dependen del pool de PgBouncer).
--     - vault no viaja en los backups de datos ni se ve en el log.
--
--   Dos secrets:
--
--     tomass_funciones_url       → "https://ymgadpinqxqkjgxslftg.supabase.co/functions/v1"
--     tomass_funciones_auth_key  → la anon JWT (pública) del proyecto
--
--   Se usa la anon JWT porque la edge function tiene verify_jwt=true (lo
--   que verifica es que el JWT sea válido del proyecto, no un rol en
--   particular). La function corre internamente con service_role via
--   la env var SUPABASE_SERVICE_ROLE_KEY, así que el caller no necesita
--   privilegios altos. Como la anon JWT es pública (está en la app),
--   guardarla en el vault no agrega secreto que haya que proteger — es
--   solo para mantener el patrón limpio.
--
-- DEPLOY DE LA EDGE FUNCTION
--
--   La función `avisar-novedad-critica` vive en
--   supabase/functions/avisar-novedad-critica/index.ts.
--
-- CHECK CONSTRAINT EN NOTIFICACIONES
--
--   Al final del script se amplía notificaciones_tipo_check para que
--   acepte 'novedad_critica'. Sin esto, el helper avisar() del edge
--   function falla silenciosamente al grabar en notificaciones (el
--   push FCM sí llega, pero la fila en-app no queda guardada).
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Función trigger
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public._disparar_aviso_novedad_critica()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp', 'net', 'vault'
AS $$
DECLARE
  v_url      text;
  v_key      text;
  v_gravedad text := lower(coalesce(NEW.gravedad, ''));
  v_estado   text := lower(coalesce(NEW.estado,   ''));
BEGIN
  -- Solo nos interesan las novedades recién abiertas con gravedad alta o
  -- crítica. Las "media"/"baja" van al camino normal (la app admin las
  -- muestra en vivo pero no suenan).
  IF v_estado <> 'abierto' THEN
    RETURN NEW;
  END IF;
  IF v_gravedad NOT IN ('critica', 'alta') THEN
    RETURN NEW;
  END IF;

  -- Credenciales desde vault. Si no están configuradas, no rompemos el
  -- INSERT: el incidente queda guardado y la app admin lo verá en vivo
  -- apenas se abra. Lo único que se pierde es el "ding" del push.
  SELECT decrypted_secret INTO v_url
    FROM vault.decrypted_secrets WHERE name = 'tomass_funciones_url';
  SELECT decrypted_secret INTO v_key
    FROM vault.decrypted_secrets WHERE name = 'tomass_funciones_auth_key';

  IF v_url IS NULL OR v_key IS NULL
     OR length(v_url) = 0 OR length(v_key) = 0 THEN
    RAISE WARNING 'avisar-novedad-critica: faltan secrets tomass_funciones_url / tomass_funciones_auth_key en el vault';
    RETURN NEW;
  END IF;

  -- pg_net.http_post es asincrónico — encola la petición y devuelve un
  -- request_id en milisegundos. El INSERT del incidente no espera la
  -- respuesta de la edge function.
  PERFORM net.http_post(
    url     := v_url || '/avisar-novedad-critica',
    body    := jsonb_build_object('incidenteId', NEW.id::text),
    headers := jsonb_build_object(
                 'Content-Type',  'application/json',
                 'Authorization', 'Bearer ' || v_key
               ),
    timeout_milliseconds := 5000
  );

  RETURN NEW;
EXCEPTION
  -- Red de seguridad: cualquier fallo acá (RAISE, net.* no disponible,
  -- lo que sea) NUNCA debe hacer caer el INSERT. Un sistema de control
  -- de acceso que no te deja reportar una novedad porque falló el push
  -- es un sistema roto.
  WHEN OTHERS THEN
    RAISE WARNING 'avisar-novedad-critica: fallo silencioso (%): %',
                   SQLSTATE, SQLERRM;
    RETURN NEW;
END;
$$;

-- ----------------------------------------------------------------------------
-- Trigger
-- ----------------------------------------------------------------------------

DROP TRIGGER IF EXISTS tg_avisar_novedad_critica ON public.incidentes;

CREATE TRIGGER tg_avisar_novedad_critica
AFTER INSERT ON public.incidentes
FOR EACH ROW
EXECUTE FUNCTION public._disparar_aviso_novedad_critica();

-- ----------------------------------------------------------------------------
-- Ampliar notificaciones_tipo_check para aceptar el nuevo tipo
-- ----------------------------------------------------------------------------

ALTER TABLE public.notificaciones
  DROP CONSTRAINT IF EXISTS notificaciones_tipo_check;

ALTER TABLE public.notificaciones
  ADD CONSTRAINT notificaciones_tipo_check
  CHECK (tipo = ANY (ARRAY[
    'acceso_peatonal'::text,
    'acceso_vehicular_pendiente'::text,
    'paquete_recibido'::text,
    'paquete_entregado'::text,
    'vehiculo_aprobado'::text,
    'vehiculo_rechazado'::text,
    'visita_esperando_aprobacion'::text,
    'visita_ingreso'::text,
    'personal_servicio_ingreso'::text,
    'incidente_unidad'::text,
    'novedad_critica'::text,
    'paquete_sin_retirar'::text,
    'sistema'::text
  ]));

-- ----------------------------------------------------------------------------
-- Snippet para popular los secrets (correr una vez)
-- ----------------------------------------------------------------------------
--   DO $vault$
--   DECLARE
--     v_id_url uuid;
--     v_id_key uuid;
--   BEGIN
--     SELECT id INTO v_id_url FROM vault.secrets WHERE name = 'tomass_funciones_url';
--     IF v_id_url IS NULL THEN
--       PERFORM vault.create_secret(
--         'https://<ref>.supabase.co/functions/v1',
--         'tomass_funciones_url',
--         'URL base de las Edge Functions.'
--       );
--     END IF;
--
--     SELECT id INTO v_id_key FROM vault.secrets WHERE name = 'tomass_funciones_auth_key';
--     IF v_id_key IS NULL THEN
--       PERFORM vault.create_secret(
--         '<pegar anon JWT legacy del dashboard>',
--         'tomass_funciones_auth_key',
--         'JWT para autenticar invocaciones a Edge Functions desde triggers.'
--       );
--     END IF;
--   END $vault$;

-- Verificación posterior:
--
--   SELECT tgname, tgenabled FROM pg_trigger
--    WHERE tgrelid = 'public.incidentes'::regclass
--      AND NOT tgisinternal;
--   -- debería listar tg_avisar_novedad_critica con tgenabled = 'O'
--
--   SELECT name, length(decrypted_secret) FROM vault.decrypted_secrets
--    WHERE name LIKE 'tomass_funciones_%';
--   -- debería listar las dos filas con largos > 0
