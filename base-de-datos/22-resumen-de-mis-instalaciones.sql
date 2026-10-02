-- ============================================================================
-- Tomass Seguridad — Resumen cross-instalación (una fila por condominio)
-- ============================================================================
-- Para la pantalla "Vista general" del admin: Manuel atiende 6 condominios y
-- necesita ver de un vistazo los números de todos sin tener que cambiar de
-- instalación una por una (6 cambios + 6 pantallas de inicio solo para
-- arrancar el día).
--
-- QUÉ DEVUELVE
--
--   Una fila por cada condominio donde el admin tiene permiso (según
--   administra_instalaciones + el titular). Los campos son los mismos que
--   muestra v_resumen_condominio para la instalación activa, recalculados
--   para cada condominio accesible:
--
--     - guardias_de_turno        → cuántos tienen turno abierto AHORA
--     - novedades_abiertas       → total de incidentes con estado 'abierto'
--     - novedades_criticas_abiertas → de las anteriores, con gravedad
--                                      'critica' o 'alta' (coherente con
--                                      el trigger de push al admin)
--     - paquetes_en_porteria     → encomiendas sin entregar
--     - paquetes_atrasados       → sin entregar y pasaron los dias_alerta
--     - autos_esperando          → solicitudes vehiculares pendientes
--     - personas_dentro / accesos_hoy → según hora local del condominio
--
--   El flag es_la_activa sale directo de mis_instalaciones() y sirve para
--   que la UI resalte la instalación en la que el admin está parado.
--
-- SEGURIDAD
--
--   STABLE SECURITY DEFINER. El cuerpo se protege con WHERE
--   es_administrador(), así que si un guardia la invoca por error, devuelve
--   tabla vacía en vez de datos agregados de otras instalaciones.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.resumen_de_mis_instalaciones()
RETURNS TABLE (
  condominio_id              uuid,
  condominio                 text,
  es_la_activa               boolean,
  guardias_de_turno          integer,
  novedades_abiertas         integer,
  novedades_criticas_abiertas integer,
  paquetes_en_porteria       integer,
  paquetes_atrasados         integer,
  autos_esperando            integer,
  personas_dentro            integer,
  accesos_hoy                integer
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
  WITH mias AS (
    SELECT id, nombre, es_la_activa
      FROM public.mis_instalaciones()
  )
  SELECT
    c.id          AS condominio_id,
    c.nombre      AS condominio,
    m.es_la_activa,
    (SELECT count(*)::int FROM public.turnos t
      WHERE t.condominio_id = c.id
        AND t.cerrado_en IS NULL)                         AS guardias_de_turno,
    (SELECT count(*)::int FROM public.incidentes i
      WHERE i.condominio_id = c.id
        AND i.estado = 'abierto')                         AS novedades_abiertas,
    (SELECT count(*)::int FROM public.incidentes i
      WHERE i.condominio_id = c.id
        AND i.estado = 'abierto'
        AND lower(coalesce(i.gravedad, '')) IN ('critica', 'alta'))
                                                          AS novedades_criticas_abiertas,
    (SELECT count(*)::int FROM public.paquetes p
      WHERE p.condominio_id = c.id
        AND p.estado = 'en_porteria')                     AS paquetes_en_porteria,
    (SELECT count(*)::int FROM public.paquetes p
      WHERE p.condominio_id = c.id
        AND p.estado = 'en_porteria'
        AND (now() - p.recibido_en)
            > (c.dias_alerta_paquete::double precision * '1 day'::interval))
                                                          AS paquetes_atrasados,
    (SELECT count(*)::int FROM public.solicitudes_vehiculares s
      WHERE s.condominio_id = c.id
        AND s.estado = 'pendiente'
        AND s.expira_en > now())                          AS autos_esperando,
    (SELECT count(*)::int FROM public.movimientos_acceso ma
      WHERE ma.condominio_id = c.id
        AND ma.estado = 'aprobado'
        AND ma.sentido = 'entrada'
        AND ma.ocurrido_en >= (date_trunc('day', (now() AT TIME ZONE c.zona_horaria))
                                AT TIME ZONE c.zona_horaria))
                                                          AS personas_dentro,
    (SELECT count(*)::int FROM public.movimientos_acceso ma
      WHERE ma.condominio_id = c.id
        AND ma.estado = 'aprobado'
        AND ma.ocurrido_en >= (date_trunc('day', (now() AT TIME ZONE c.zona_horaria))
                                AT TIME ZONE c.zona_horaria))
                                                          AS accesos_hoy
    FROM public.condominios c
    JOIN mias m ON m.id = c.id
   WHERE public.es_administrador()
   ORDER BY c.nombre;
$$;

GRANT EXECUTE ON FUNCTION public.resumen_de_mis_instalaciones() TO authenticated;

-- Verificación:
--
--   SELECT * FROM public.resumen_de_mis_instalaciones();
--   -- devuelve una fila por cada condominio donde el admin tiene permiso
