-- ============================================================================
-- Tomass Seguridad — 06 · GUARDADO DE FOTOS
-- ============================================================================
-- Qué hace este archivo:
--   Crea los "cajones" donde se guardan las fotos del sistema: las de los
--   vehículos, las de los paquetes, las firmas y las fotos de las personas.
--
-- POR QUÉ LAS FOTOS SON PRIVADAS Y NO PÚBLICAS
--
--   Una foto de la patente de un auto, o la cara de un residente, es un dato
--   personal. Si el cajón fuera público, cualquiera con el enlace podría verla,
--   y esos enlaces se filtran solos (aparecen en historiales, en capturas, en
--   mensajes reenviados).
--
--   Acá los cajones son PRIVADOS. Para ver una foto, la app le pide al servidor
--   un enlace temporal que sirve una hora y después deja de funcionar.
--
-- CÓMO SE ORGANIZAN LAS CARPETAS
--
--   condominio_id / usuario_id / nombre_del_archivo.jpg
--
--   La primera carpeta es el condominio. Eso es lo que hace que un condominio no
--   pueda ver las fotos de otro: la regla de seguridad compara esa carpeta con
--   el condominio de quien está preguntando.
--
-- Cómo se usa:
--   Pegá TODO este archivo en el editor SQL de Supabase y presioná "Run".
--   Ejecutar DESPUÉS de 05-llaves-y-limites.sql.
-- ============================================================================


-- ============================================================================
-- 1 · LOS CUATRO CAJONES
-- ============================================================================

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values
  -- Fotos de vehículos y de patentes. 6 MB alcanza de sobra para una foto de
  -- celular ya comprimida.
  ('vehiculos', 'vehiculos', false, 6291456,
   array['image/jpeg','image/png','image/webp','image/heic']),

  -- Fotos de los paquetes que llegan a portería
  ('paquetes', 'paquetes', false, 6291456,
   array['image/jpeg','image/png','image/webp','image/heic']),

  -- Firmas del dedo sobre la pantalla. Son dibujos chicos: 1 MB es suficiente.
  ('firmas', 'firmas', false, 1048576,
   array['image/png','image/jpeg']),

  -- Fotos de residentes, visitantes y personal de servicio
  ('personas', 'personas', false, 6291456,
   array['image/jpeg','image/png','image/webp','image/heic'])
on conflict (id) do nothing;


-- ============================================================================
-- 2 · LAS REGLAS DE ACCESO A LAS FOTOS
-- ============================================================================
-- La regla se repite para los cuatro cajones, y siempre dice lo mismo:
-- "solo si la primera carpeta del archivo es tu propio condominio".
-- ============================================================================

-- Ver fotos: cualquiera del condominio puede ver las fotos de su condominio.
--
-- ¿Por qué no se limita a "cada residente ve solo las suyas"? Porque el guardia
-- necesita ver la foto del auto y la cara del residente para poder compararlas
-- con lo que tiene adelante, y el residente necesita ver la foto de su paquete.
-- Lo que sí está garantizado es que nadie ve nada de otro condominio.
create policy "ver fotos de mi condominio"
  on storage.objects for select to authenticated
  using (
    bucket_id in ('vehiculos','paquetes','firmas','personas')
    and (storage.foldername(name))[1] = public.mi_condominio()::text
  );

-- Subir fotos: además del condominio, se exige que la segunda carpeta sea el
-- propio usuario. Así un residente no puede dejar archivos a nombre de otro.
-- El personal de portería puede subir a cualquier carpeta de su condominio,
-- porque saca fotos de paquetes que son de otras personas.
create policy "subir mis fotos"
  on storage.objects for insert to authenticated
  with check (
    bucket_id in ('vehiculos','paquetes','firmas','personas')
    and (storage.foldername(name))[1] = public.mi_condominio()::text
    and (
      (storage.foldername(name))[2] = auth.uid()::text
      or public.es_porteria()
    )
  );

-- Reemplazar una foto: mismas condiciones que para subirla.
create policy "reemplazar mis fotos"
  on storage.objects for update to authenticated
  using (
    bucket_id in ('vehiculos','paquetes','firmas','personas')
    and (storage.foldername(name))[1] = public.mi_condominio()::text
    and (
      (storage.foldername(name))[2] = auth.uid()::text
      or public.es_porteria()
    )
  );

-- Borrar una foto: solo la propia, o el administrador.
--
-- Ojo: las firmas de entrega de paquetes NO se pueden borrar ni por el
-- administrador. Son el respaldo de que el paquete se entregó.
create policy "borrar mis fotos"
  on storage.objects for delete to authenticated
  using (
    bucket_id in ('vehiculos','paquetes','personas')
    and (storage.foldername(name))[1] = public.mi_condominio()::text
    and (
      (storage.foldername(name))[2] = auth.uid()::text
      or public.es_administrador()
    )
  );


-- ============================================================================
-- 3 · REVISIÓN
-- ============================================================================

-- Esperado: 4 filas, todas con public = false
select id, public as es_publico,
       (file_size_limit / 1048576) || ' MB' as tamano_maximo
  from storage.buckets
 where id in ('vehiculos','paquetes','firmas','personas')
 order by id;

-- Esperado: 4 reglas
select count(*) as reglas_de_fotos
  from pg_policies
 where schemaname = 'storage' and tablename = 'objects'
   and policyname like '%fotos%';


-- ============================================================================
-- FIN DEL ARCHIVO 06
-- ============================================================================
