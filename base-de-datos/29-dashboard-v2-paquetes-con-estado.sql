-- ============================================================================
-- Tomass Seguridad — Dashboard v2: paquetes con filtro por estado
-- ============================================================================
-- La RPC web_mis_paquetes(uuid) solo devolvía los paquetes 'en_porteria'
-- (pendientes de retiro). Para v2 el admin quiere también ver el HISTÓRICO
-- de los entregados, con quién los retiró, cuándo, firma y foto.
--
-- La firma de la función cambia (nuevo parámetro p_estado + nuevas columnas),
-- así que primero hay que DROPear la versión vieja (ver memoria del proyecto
-- sobre overload de RPCs en PostgreSQL).
--
-- COMO USARLA
--   SELECT * FROM web_mis_paquetes();                        -- pendientes de retiro
--   SELECT * FROM web_mis_paquetes(NULL, 'entregado');        -- historico retirados
--   SELECT * FROM web_mis_paquetes(NULL, NULL);               -- todos mezclados
--   SELECT * FROM web_mis_paquetes(mi_condo_id, 'entregado'); -- de una instalación
-- ============================================================================

-- Hay que DROPear la versión vieja porque cambia la firma (parámetros).
DROP FUNCTION IF EXISTS public.web_mis_paquetes(uuid);

CREATE OR REPLACE FUNCTION public.web_mis_paquetes(
  p_condominio_id uuid DEFAULT NULL,
  p_estado        text DEFAULT 'en_porteria'
    -- 'en_porteria' | 'entregado' | NULL (todos)
)
RETURNS TABLE (
  id                   uuid,
  condominio_id        uuid,
  condominio_nombre    text,
  estado               text,
  recibido_en          timestamptz,
  dias_en_porteria     int,
  descripcion          text,
  destinatario         text,
  unidad               text,
  foto_url             text,
  guardia_receptor     text,
  -- Columnas que SOLO tienen valor cuando estado = 'entregado'.
  entregado_en         timestamptz,
  retirado_por         text,
  identidad_validada   boolean,
  firma_url            text,
  foto_entrega_url     text,
  guardia_entrega      text
)
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
  SELECT
    p.id, p.condominio_id, c.nombre, p.estado,
    p.recibido_en,
    EXTRACT(DAY FROM (NOW() - p.recibido_en))::int,
    p.descripcion, p.destinatario_texto, p.unidad_texto, p.foto_url,
    gr.nombre_completo,
    p.entregado_en, p.retirado_por, p.identidad_validada,
    p.firma_url, p.foto_entrega_url, ge.nombre_completo
  FROM public.paquetes p
  JOIN public.condominios c              ON c.id  = p.condominio_id
  LEFT JOIN public.usuarios gr           ON gr.id = p.guardia_receptor_id
  LEFT JOIN public.usuarios ge           ON ge.id = p.guardia_entrega_id
  WHERE public.es_admin_o_mandante()
    AND p.condominio_id IN (SELECT id FROM public.mis_instalaciones())
    AND (p_condominio_id IS NULL OR p.condominio_id = p_condominio_id)
    AND (p_estado        IS NULL OR p.estado        = p_estado)
  ORDER BY
    -- Entregados: más recientes primero (lo que acaba de pasar).
    -- Pendientes: más viejos primero (para que el admin vea los atrasados arriba).
    CASE WHEN p.estado = 'en_porteria' THEN p.recibido_en END ASC,
    CASE WHEN p.estado = 'entregado'   THEN p.entregado_en END DESC
  LIMIT 1000;
$$;

GRANT EXECUTE ON FUNCTION public.web_mis_paquetes(uuid, text) TO authenticated;
