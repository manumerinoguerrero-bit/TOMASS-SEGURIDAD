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
-- CONFIGURACIÓN REQUERIDA (UNA VEZ, A MANO)
--
--   El trigger necesita saber la URL de la edge function y el service_role
--   para autenticar la llamada. Se guardan como GUCs de la base:
--
--     ALTER DATABASE postgres
--       SET app.funciones_url = 'https://ymgadpinqxqkjgxslftg.supabase.co/functions/v1';
--     ALTER DATABASE postgres
--       SET app.service_role_key = '<pegar service_role_key del dashboard>';
--
--   Después hay que reiniciar las conexiones del pool para que los GUCs se
--   carguen (o esperar que PgBouncer rote). Si el GUC no está, el trigger
--   NO rompe el INSERT: se absorbe la excepción y la novedad queda
--   grabada igual sin push. Lo peor que puede pasar es que el admin se
--   entere al abrir la app (camino 1 ya funciona).
--
-- DEPLOY DE LA EDGE FUNCTION
--
--   La función `avisar-novedad-critica` está en
--   supabase/functions/avisar-novedad-critica/index.ts y se despliega como
--   cualquier otra function:
--
--     supabase functions deploy avisar-novedad-critica
-- ============================================================================

CREATE OR REPLACE FUNCTION public._disparar_aviso_novedad_critica()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp', 'net'
AS $$
DECLARE
  v_url      text;
  v_key      text;
  v_gravedad text := lower(coalesce(NEW.gravedad, ''));
  v_estado   text := lower(coalesce(NEW.estado,   ''));
BEGIN
  -- Solo nos interesan las novedades reciente abiertas con gravedad alta
  -- o crítica. Las "media"/"baja" van al camino normal (la app admin las
  -- muestra en vivo pero no suenan).
  IF v_estado <> 'abierto' THEN
    RETURN NEW;
  END IF;
  IF v_gravedad NOT IN ('critica', 'alta') THEN
    RETURN NEW;
  END IF;

  -- Los GUCs se leen con `missing_ok = true` (el tercer parámetro de
  -- current_setting en Postgres 12+) para que si no están configurados,
  -- devuelva null en lugar de lanzar excepción.
  v_url := current_setting('app.funciones_url',     true);
  v_key := current_setting('app.service_role_key',  true);

  -- Si no está la configuración, no rompemos el INSERT. El incidente queda
  -- guardado y la app admin lo verá en vivo apenas se abra. Lo único que
  -- se pierde es el "ding" del push al celular.
  IF v_url IS NULL OR v_key IS NULL
     OR length(v_url) = 0 OR length(v_key) = 0 THEN
    RAISE WARNING 'avisar-novedad-critica: faltan GUCs app.funciones_url / app.service_role_key; no se envía push';
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

DROP TRIGGER IF EXISTS tg_avisar_novedad_critica ON public.incidentes;

CREATE TRIGGER tg_avisar_novedad_critica
AFTER INSERT ON public.incidentes
FOR EACH ROW
EXECUTE FUNCTION public._disparar_aviso_novedad_critica();

-- Verificación posterior:
--
--   SELECT tgname, tgenabled FROM pg_trigger
--    WHERE tgrelid = 'public.incidentes'::regclass
--      AND NOT tgisinternal;
--   -- debería listar tg_avisar_novedad_critica con tgenabled = 'O' (ON)
--
--   -- Ver si los GUCs están configurados:
--   SELECT current_setting('app.funciones_url', true),
--          current_setting('app.service_role_key', true) IS NOT NULL;
