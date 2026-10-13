-- ============================================================================
-- Tomass Seguridad — Fix: estado 'en_porteria' en las RPCs del dashboard
-- ============================================================================
-- La migration 27 creó web_mi_resumen() y web_mis_paquetes() filtrando por
-- p.estado = 'recibido'. Error: el estado real para un paquete pendiente de
-- retiro es 'en_porteria' ('recibido' nunca existió en el schema).
--
-- Consecuencia visible: el dashboard web mostraba 0 paquetes en todas las
-- instalaciones aunque hubiera decenas pendientes (ej. 19 en Milagros al
-- momento del fix).
--
-- Esta migration reescribe las dos funciones con el estado correcto.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.web_mi_resumen()
RETURNS TABLE (
  condominio_id uuid, condominio_nombre text, condominio_tipo text,
  guardias_de_turno int, novedades_abiertas int, novedades_criticas int,
  paquetes_en_porteria int, accesos_hoy int
) LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO 'public', 'pg_temp' AS $$
  WITH mis AS (SELECT id, nombre, tipo FROM public.mis_instalaciones())
  SELECT m.id, m.nombre, m.tipo,
    (SELECT COUNT(*)::int FROM public.turnos t
       WHERE t.condominio_id = m.id AND t.cerrado_en IS NULL),
    (SELECT COUNT(*)::int FROM public.incidentes i
       WHERE i.condominio_id = m.id AND i.estado = 'abierto'),
    (SELECT COUNT(*)::int FROM public.incidentes i
       WHERE i.condominio_id = m.id AND i.estado = 'abierto'
         AND i.gravedad = 'critica'),
    -- 'en_porteria' = pendiente de retiro. 'entregado' = ya se lo llevaron.
    (SELECT COUNT(*)::int FROM public.paquetes p
       WHERE p.condominio_id = m.id AND p.estado = 'en_porteria'),
    (SELECT COUNT(*)::int FROM public.movimientos_acceso ma
       WHERE ma.condominio_id = m.id
         AND ma.ocurrido_en >= DATE_TRUNC('day', NOW()))
  FROM mis m WHERE public.es_admin_o_mandante();
$$;

CREATE OR REPLACE FUNCTION public.web_mis_paquetes(p_condominio_id uuid DEFAULT NULL)
RETURNS TABLE (
  id uuid, condominio_id uuid, condominio_nombre text, recibido_en timestamptz,
  dias_en_porteria int, descripcion text, destinatario text, unidad text,
  foto_url text, guardia_receptor text
) LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO 'public', 'pg_temp' AS $$
  SELECT p.id, p.condominio_id, c.nombre, p.recibido_en,
    EXTRACT(DAY FROM (NOW() - p.recibido_en))::int,
    p.descripcion, p.destinatario_texto, p.unidad_texto, p.foto_url,
    g.nombre_completo
  FROM public.paquetes p
  JOIN public.condominios c ON c.id = p.condominio_id
  LEFT JOIN public.usuarios g ON g.id = p.guardia_receptor_id
  WHERE public.es_admin_o_mandante()
    AND p.condominio_id IN (SELECT id FROM public.mis_instalaciones())
    AND (p_condominio_id IS NULL OR p.condominio_id = p_condominio_id)
    AND p.estado = 'en_porteria'
  ORDER BY p.recibido_en ASC LIMIT 500;
$$;
