-- ============================================================================
-- Tomass Seguridad — Rol 'mandante' + RPCs del dashboard web
-- ============================================================================
-- El dashboard web (/web/) permite al mandante del condominio (administrador
-- de edificio, dueño de la empresa cliente, etc.) ver EN TIEMPO REAL lo que
-- pasa en su instalación: ingresos, novedades, paquetes y guardias de turno.
--
-- No puede modificar nada: es solo lectura. Para altas/bajas sigue el admin
-- de Tomass (que es el único con rol 'administrador').
--
-- DISEÑO
--
--   * Nuevo rol 'mandante' en usuarios.rol. Un mandante se liga a su
--     condominio vía administra_instalaciones (igual que un admin extra).
--   * Nueva función es_admin_o_mandante() que acepta ambos roles. La usan
--     solo las RPCs web_*; el resto del sistema sigue con es_administrador().
--   * Modificada mis_instalaciones() para incluir mandantes.
--   * 5 RPCs nuevas prefijadas web_* exclusivas del dashboard. Prefijo claro
--     para que una revisión futura vea rápido qué toca el dashboard web y
--     qué toca la app móvil. También facilita bloquear ejecución desde la
--     app con un GRANT selectivo si alguna vez hiciera falta.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Permitir rol 'mandante'
-- ----------------------------------------------------------------------------
ALTER TABLE public.usuarios DROP CONSTRAINT IF EXISTS usuarios_rol_check;
ALTER TABLE public.usuarios ADD CONSTRAINT usuarios_rol_check
  CHECK (rol IN ('administrador', 'guardia', 'residente', 'mandante'));

-- ----------------------------------------------------------------------------
-- 2. es_admin_o_mandante() — usada solo por las RPCs web_*
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.es_admin_o_mandante()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
  SELECT coalesce(
    (SELECT rol IN ('administrador', 'mandante')
       FROM public.usuarios
      WHERE id = auth.uid()
        AND estado = 'activo'),
    false
  );
$$;

-- ----------------------------------------------------------------------------
-- 3. mis_instalaciones() ampliada para mandantes
-- ----------------------------------------------------------------------------
-- Antes solo los roles administrador/guardia miraban administra_instalaciones.
-- Ahora los mandantes también: así ven las instalaciones donde fueron
-- delegados.
CREATE OR REPLACE FUNCTION public.mis_instalaciones()
RETURNS TABLE(
  id uuid, nombre text, nombre_corto text, tipo text, ciudad text,
  es_la_activa boolean
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
  WITH yo AS (
    SELECT id, condominio_id, condominio_activo, rol, estado
      FROM public.usuarios WHERE id = auth.uid()
  )
  SELECT c.id, c.nombre, c.nombre_corto, c.tipo, c.ciudad,
         (c.id = public.mi_condominio()) AS es_la_activa
    FROM public.condominios c
   WHERE c.id = (SELECT condominio_id FROM yo)
      OR c.id IN (
        SELECT a.condominio_id
          FROM public.administra_instalaciones a, yo
         WHERE a.usuario_id = yo.id
           AND yo.rol IN ('administrador', 'guardia', 'mandante')
           AND yo.estado = 'activo')
   ORDER BY c.nombre;
$$;

-- ============================================================================
-- RPCs del dashboard web (todas STABLE SECURITY DEFINER)
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 4. web_mi_resumen() — una fila por instalación con contadores
-- ----------------------------------------------------------------------------
-- Equivalente al resumen que el admin ve en /consolidado. Para el mandante
-- típicamente trae 1 fila (su único condominio); para el admin de Tomass
-- trae todas las que tiene delegadas.
CREATE OR REPLACE FUNCTION public.web_mi_resumen()
RETURNS TABLE (
  condominio_id              uuid,
  condominio_nombre          text,
  condominio_tipo            text,
  guardias_de_turno          int,
  novedades_abiertas         int,
  novedades_criticas         int,
  paquetes_en_porteria       int,
  accesos_hoy                int
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
  WITH mis AS (
    SELECT id, nombre, tipo FROM public.mis_instalaciones()
  )
  SELECT
    m.id,
    m.nombre,
    m.tipo,
    (SELECT COUNT(*)::int FROM public.turnos t
      WHERE t.condominio_id = m.id AND t.cerrado_en IS NULL),
    (SELECT COUNT(*)::int FROM public.incidentes i
      WHERE i.condominio_id = m.id AND i.estado = 'abierto'),
    (SELECT COUNT(*)::int FROM public.incidentes i
      WHERE i.condominio_id = m.id
        AND i.estado = 'abierto' AND i.gravedad = 'critica'),
    (SELECT COUNT(*)::int FROM public.paquetes p
      WHERE p.condominio_id = m.id AND p.estado = 'recibido'),
    (SELECT COUNT(*)::int FROM public.movimientos_acceso ma
      WHERE ma.condominio_id = m.id
        AND ma.ocurrido_en >= DATE_TRUNC('day', NOW()))
  FROM mis m
  WHERE public.es_admin_o_mandante();
$$;

GRANT EXECUTE ON FUNCTION public.web_mi_resumen() TO authenticated;

-- ----------------------------------------------------------------------------
-- 5. web_mis_ingresos(desde, hasta, condominio) — accesos del período
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.web_mis_ingresos(
  p_desde         timestamptz DEFAULT NOW() - INTERVAL '7 days',
  p_hasta         timestamptz DEFAULT NOW(),
  p_condominio_id uuid DEFAULT NULL
)
RETURNS TABLE (
  id                uuid,
  condominio_id     uuid,
  condominio_nombre text,
  ocurrido_en       timestamptz,
  nombre            text,
  tipo_acceso       text,
  sentido           text,
  estado            text,
  unidad            text,
  patente           text,
  a_donde_va        text,
  autorizado_por    text,
  guardia_nombre    text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
  SELECT
    ma.id,
    ma.condominio_id,
    c.nombre,
    ma.ocurrido_en,
    ma.nombre_snapshot,
    ma.tipo_acceso,
    ma.sentido,
    ma.estado,
    ma.unidad_snapshot,
    ma.patente_snapshot,
    ma.a_donde_va,
    ma.autorizado_por_texto,
    g.nombre_completo
  FROM public.movimientos_acceso ma
  JOIN public.condominios c ON c.id = ma.condominio_id
  LEFT JOIN public.usuarios g ON g.id = ma.guardia_id
  WHERE public.es_admin_o_mandante()
    AND ma.condominio_id IN (SELECT id FROM public.mis_instalaciones())
    AND (p_condominio_id IS NULL OR ma.condominio_id = p_condominio_id)
    AND ma.ocurrido_en >= p_desde
    AND ma.ocurrido_en <= p_hasta
  ORDER BY ma.ocurrido_en DESC
  LIMIT 500;
$$;

GRANT EXECUTE ON FUNCTION public.web_mis_ingresos(timestamptz, timestamptz, uuid) TO authenticated;

-- ----------------------------------------------------------------------------
-- 6. web_mis_novedades(estado, condominio) — incidentes
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.web_mis_novedades(
  p_estado        text DEFAULT NULL,
  p_condominio_id uuid DEFAULT NULL
)
RETURNS TABLE (
  id                uuid,
  condominio_id     uuid,
  condominio_nombre text,
  ocurrido_en       timestamptz,
  tipo              text,
  gravedad          text,
  titulo            text,
  descripcion       text,
  estado            text,
  fotos             jsonb,
  reportado_por_nombre text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
  SELECT
    i.id,
    i.condominio_id,
    c.nombre,
    i.ocurrido_en,
    i.tipo,
    i.gravedad,
    i.titulo,
    i.descripcion,
    i.estado,
    i.fotos,
    u.nombre_completo
  FROM public.incidentes i
  JOIN public.condominios c ON c.id = i.condominio_id
  LEFT JOIN public.usuarios u ON u.id = i.reportado_por
  WHERE public.es_admin_o_mandante()
    AND i.condominio_id IN (SELECT id FROM public.mis_instalaciones())
    AND (p_condominio_id IS NULL OR i.condominio_id = p_condominio_id)
    AND (p_estado IS NULL OR i.estado = p_estado)
  ORDER BY i.ocurrido_en DESC
  LIMIT 500;
$$;

GRANT EXECUTE ON FUNCTION public.web_mis_novedades(text, uuid) TO authenticated;

-- ----------------------------------------------------------------------------
-- 7. web_mis_paquetes(condominio) — paquetes recibidos pendientes de retiro
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.web_mis_paquetes(
  p_condominio_id uuid DEFAULT NULL
)
RETURNS TABLE (
  id                uuid,
  condominio_id     uuid,
  condominio_nombre text,
  recibido_en       timestamptz,
  dias_en_porteria  int,
  descripcion       text,
  destinatario      text,
  unidad            text,
  foto_url          text,
  guardia_receptor  text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
  SELECT
    p.id,
    p.condominio_id,
    c.nombre,
    p.recibido_en,
    EXTRACT(DAY FROM (NOW() - p.recibido_en))::int,
    p.descripcion,
    p.destinatario_texto,
    p.unidad_texto,
    p.foto_url,
    g.nombre_completo
  FROM public.paquetes p
  JOIN public.condominios c ON c.id = p.condominio_id
  LEFT JOIN public.usuarios g ON g.id = p.guardia_receptor_id
  WHERE public.es_admin_o_mandante()
    AND p.condominio_id IN (SELECT id FROM public.mis_instalaciones())
    AND (p_condominio_id IS NULL OR p.condominio_id = p_condominio_id)
    AND p.estado = 'recibido'
  ORDER BY p.recibido_en ASC
  LIMIT 500;
$$;

GRANT EXECUTE ON FUNCTION public.web_mis_paquetes(uuid) TO authenticated;

-- ----------------------------------------------------------------------------
-- 8. web_guardias_de_turno(condominio) — para el mapa en vivo
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.web_guardias_de_turno(
  p_condominio_id uuid DEFAULT NULL
)
RETURNS TABLE (
  turno_id          uuid,
  condominio_id     uuid,
  condominio_nombre text,
  guardia_id        uuid,
  guardia_nombre    text,
  guardia_telefono  text,
  guardia_foto_url  text,
  punto_acceso      text,
  inicio            timestamptz,
  ultima_lat        numeric,
  ultima_lng        numeric,
  ultima_ubicacion_en timestamptz
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
  SELECT
    t.id,
    t.condominio_id,
    c.nombre,
    u.id,
    u.nombre_completo,
    u.telefono,
    u.foto_url,
    pa.nombre,
    t.inicio,
    COALESCE(t.ultima_geo_lat, t.geo_lat),
    COALESCE(t.ultima_geo_lng, t.geo_lng),
    t.ultima_ubicacion_en
  FROM public.turnos t
  JOIN public.condominios c   ON c.id = t.condominio_id
  JOIN public.usuarios u      ON u.id = t.guardia_id
  LEFT JOIN public.puntos_acceso pa ON pa.id = t.punto_acceso_id
  WHERE public.es_admin_o_mandante()
    AND t.cerrado_en IS NULL
    AND t.condominio_id IN (SELECT id FROM public.mis_instalaciones())
    AND (p_condominio_id IS NULL OR t.condominio_id = p_condominio_id)
  ORDER BY t.inicio DESC;
$$;

GRANT EXECUTE ON FUNCTION public.web_guardias_de_turno(uuid) TO authenticated;

-- ============================================================================
-- VERIFICACIÓN
-- ============================================================================
-- SELECT * FROM web_mi_resumen();
-- SELECT * FROM web_mis_ingresos();
-- SELECT * FROM web_mis_novedades();
-- SELECT * FROM web_mis_paquetes();
-- SELECT * FROM web_guardias_de_turno();
