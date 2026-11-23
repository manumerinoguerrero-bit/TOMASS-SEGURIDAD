-- ============================================================================
-- Tomass Seguridad — 43 · El panel web sabe qué fotos ya se borraron
-- ============================================================================
-- PARA QUÉ
--
--   El panel web ahora tiene el botón "Ya guardé el PDF — borrar esas fotos"
--   (función del servidor borrar-fotos-informadas). Para que después de borrar
--   el panel no ofrezca "Ver foto" de una foto que ya no existe, ni intente
--   meterla en el próximo PDF, la lista de paquetes del panel tiene que traer
--   la fecha en que se borraron las fotos.
--
--   Lo único que cambia es UNA columna más al final (fotos_borradas_en). El
--   resto de la función es idéntico al que está hoy en el servidor.
--
--   Postgres no deja agregar columnas a lo que devuelve una función con
--   "create or replace". En vez de borrar la original (web_mis_paquetes), se
--   crea una nueva, web_mis_paquetes_v2, idéntica más la columna. El panel
--   usa la v2 y, si no existiera, vuelve a la original. La original queda
--   intacta por si algo más la usa.
--
--   ✅ APLICADO EN EL SERVIDOR el 2026-11-23.
-- ============================================================================

create or replace function public.web_mis_paquetes_v2(
  p_condominio_id uuid default null,
  p_estado text default 'en_porteria'
)
returns table(
  id uuid, condominio_id uuid, condominio_nombre text, estado text,
  recibido_en timestamptz, dias_en_porteria integer, descripcion text,
  destinatario text, unidad text, foto_url text, guardia_receptor text,
  entregado_en timestamptz, retirado_por text, identidad_validada boolean,
  firma_url text, foto_entrega_url text, guardia_entrega text,
  fotos_borradas_en timestamptz
)
language sql
stable security definer
set search_path to 'public', 'pg_temp'
as $function$
  SELECT
    p.id, p.condominio_id, c.nombre, p.estado,
    p.recibido_en,
    EXTRACT(DAY FROM (NOW() - p.recibido_en))::int,
    p.descripcion, p.destinatario_texto, p.unidad_texto, p.foto_url,
    gr.nombre_completo,
    p.entregado_en, p.retirado_por, p.identidad_validada,
    p.firma_url, p.foto_entrega_url, ge.nombre_completo,
    p.fotos_borradas_en
  FROM public.paquetes p
  JOIN public.condominios c              ON c.id  = p.condominio_id
  LEFT JOIN public.usuarios gr           ON gr.id = p.guardia_receptor_id
  LEFT JOIN public.usuarios ge           ON ge.id = p.guardia_entrega_id
  WHERE public.es_admin_o_mandante()
    AND p.condominio_id IN (SELECT id FROM public.mis_instalaciones())
    AND (p_condominio_id IS NULL OR p.condominio_id = p_condominio_id)
    AND (p_estado        IS NULL OR p.estado        = p_estado)
  ORDER BY
    -- Entregados: mas recientes primero. Pendientes: mas viejos primero
    -- (para que el admin vea los atrasados arriba).
    CASE WHEN p.estado = 'en_porteria' THEN p.recibido_en END ASC,
    CASE WHEN p.estado = 'entregado'   THEN p.entregado_en END DESC
  LIMIT 1000;
$function$;

revoke all on function public.web_mis_paquetes_v2(uuid, text) from public, anon;
grant execute on function public.web_mis_paquetes_v2(uuid, text) to authenticated, service_role;


-- Revisión: debe aparecer fotos_borradas_en al final.
-- select * from public.web_mis_paquetes_v2(null, 'entregado') limit 1;

-- ============================================================================
-- FIN DEL ARCHIVO 43
-- ============================================================================
