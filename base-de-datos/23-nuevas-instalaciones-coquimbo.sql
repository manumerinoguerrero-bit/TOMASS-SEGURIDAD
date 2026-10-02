-- ============================================================================
-- Tomass Seguridad — Alta de 6 instalaciones nuevas en Coquimbo
-- ============================================================================
-- Pedido por Manuel el 02/10/2026. Son instalaciones nuevas que Tomass empieza
-- a atender en Coquimbo (hasta ahora las 6 instalaciones vivían en La Serena).
--
-- CLASIFICACIÓN POR TIPO
--
--   condominio  → Los Fundadores, Baquedano  (residenciales)
--   empresa     → Bodega Las Torres, Sala de Ventas Los Huertos,
--                 Sala de Venta PY  (lugares de trabajo con guardia)
--   otro        → Asiducam  (no se confirmó el tipo exacto; se puede
--                 ajustar después desde el panel admin)
--
-- Zona horaria America/Santiago (default), plan 'basico' (default), 7 días
-- de alerta de paquete (default), 120 minutos entre rondas (default).
--
-- También damos acceso a Manuel (admin general) a las 6 nuevas via
-- administra_instalaciones, para que las vea en la vista consolidada y
-- pueda cambiar de instalación hacia cualquiera de ellas.
-- ============================================================================

INSERT INTO public.condominios (nombre, nombre_corto, tipo, ciudad, zona_horaria)
VALUES
  ('Condominio Los Fundadores',  'Los Fundadores',    'condominio', 'Coquimbo', 'America/Santiago'),
  ('Condominio Baquedano',       'Baquedano',         'condominio', 'Coquimbo', 'America/Santiago'),
  ('Bodega Las Torres',          'Bodega Las Torres', 'empresa',    'Coquimbo', 'America/Santiago'),
  ('Sala de Ventas Los Huertos', 'Sala Los Huertos',  'empresa',    'Coquimbo', 'America/Santiago'),
  ('Sala de Venta PY',           'Sala PY',           'empresa',    'Coquimbo', 'America/Santiago'),
  ('Asiducam',                   'Asiducam',          'otro',       'Coquimbo', 'America/Santiago');

-- Manuel como admin de las 6 nuevas. ON CONFLICT por si se re-corre la
-- migración después de haber agregado permisos a mano.
INSERT INTO public.administra_instalaciones (usuario_id, condominio_id)
SELECT '8a14c540-6745-4122-a7d5-4e7ceb753589', c.id
  FROM public.condominios c
 WHERE c.ciudad = 'Coquimbo'
   AND c.nombre IN (
     'Condominio Los Fundadores',
     'Condominio Baquedano',
     'Bodega Las Torres',
     'Sala de Ventas Los Huertos',
     'Sala de Venta PY',
     'Asiducam'
   )
ON CONFLICT DO NOTHING;

-- Verificación posterior:
--
--   SELECT nombre, nombre_corto, tipo, ciudad FROM public.condominios
--    WHERE ciudad = 'Coquimbo' ORDER BY nombre;
