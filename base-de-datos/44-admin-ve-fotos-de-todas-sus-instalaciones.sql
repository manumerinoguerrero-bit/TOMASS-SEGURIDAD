-- ============================================================================
-- Tomass Seguridad — 44 · El administrador ve fotos y firmas de TODAS sus
--                          instalaciones en el panel web
-- ============================================================================
-- ✅ APLICADO EN EL SERVIDOR el 2026-11-23 (aprobado por Manuel).
--
-- PROBLEMA: el candado de lectura de fotos/firmas (Storage) solo deja ver las
-- de la instalación ACTIVA en la app (mi_condominio()). El panel web muestra
-- todas las instalaciones, así que el PDF de otra instalación sale sin fotos
-- ni firmas (pasó con Condominio Encomenderos el 2026-11-23).
--
-- SOLUCIÓN: un candado de SOLO LECTURA más, para administrador o mandante,
-- limitado a las instalaciones que le corresponden (mis_instalaciones()), la
-- misma regla que ya usa la lista de paquetes del panel. No da permiso de
-- subir, cambiar ni borrar nada.
-- ============================================================================

create policy "admin y mandante ven fotos de sus instalaciones" on storage.objects
  for select to authenticated
  using (
    bucket_id = any (array['paquetes','firmas'])
    and public.es_admin_o_mandante()
    and (storage.foldername(name))[1] in (select id::text from public.mis_instalaciones())
  );

-- Para deshacerlo:
--   drop policy "admin y mandante ven fotos de sus instalaciones" on storage.objects;
