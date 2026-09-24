-- ============================================================================
-- Tomass Seguridad — Fix: sobrecarga rota de crear_punto_control
-- ============================================================================
-- QUÉ PASABA
--
--   Al querer agregar un sector nuevo desde la pantalla admin, la app fallaba
--   con el error PGRST203 "Could not choose the best candidate function".
--   La RPC había quedado con DOS versiones sobrecargadas después de agregarle
--   el parámetro p_punto_acceso_id:
--
--     * Versión vieja (5 params): p_nombre, p_latitud, p_longitud,
--       p_descripcion, p_tolerancia
--     * Versión nueva (6 params): las mismas + p_punto_acceso_id (DEFAULT NULL)
--
--   Cuando el admin crea un sector sin elegir garita explícita (opción
--   "Común a todas las garitas", o condominios de una sola garita donde el
--   dropdown ni aparece), la app manda solo los 5 primeros params. Como el
--   sexto tiene DEFAULT, PostgREST no puede decidir a cuál llamar y devuelve
--   PGRST203. Resultado: no se puede crear ningún QR nuevo.
--
-- SOLUCIÓN
--
--   Se droppea la versión vieja de 5 params. La nueva ya cubre el caso de
--   sin-garita porque p_punto_acceso_id tiene DEFAULT NULL.
--
-- REFERENCIA DE MEMORIA
--
--   Es el mismo bug que ya nos había pasado con registrar_acceso_manual
--   cuando le agregamos p_ocurrido_en. Anotado en la memoria del proyecto
--   como "Supabase RPC: DROP la versión vieja al cambiar firma".
-- ============================================================================

DROP FUNCTION IF EXISTS public.crear_punto_control(
  p_nombre text,
  p_latitud numeric,
  p_longitud numeric,
  p_descripcion text,
  p_tolerancia smallint
);

-- Verificar después de correr: debe quedar UNA sola fila con 6 parámetros.
--
-- SELECT proname, pg_get_function_identity_arguments(oid) AS argumentos
--   FROM pg_proc p
--   JOIN pg_namespace n ON n.oid = p.pronamespace
--  WHERE n.nspname = 'public' AND p.proname = 'crear_punto_control';
