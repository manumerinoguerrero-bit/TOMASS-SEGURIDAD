-- ============================================================================
-- Tomass Seguridad — 12 · El administrador ve y limpia fotos de encomiendas
-- ============================================================================
-- ⚠️ ESTE ARCHIVO YA ESTÁ APLICADO EN EL SERVIDOR. Queda para el historial.
--
-- LA DECISIÓN, Y POR QUÉ
--
--   Manuel pidió que, una vez a la semana, el administrador pueda sacar un
--   informe en PDF de las encomiendas entregadas CON SU FOTO, y que una vez
--   impreso ese informe se puedan borrar esas fotos de la aplicación. Eso
--   reemplaza (para las fotos de encomiendas) la espera de 6 meses del
--   archivo 11: en vez de esperar medio año, se borran apenas quedan
--   impresas en un papel que sí se puede guardar para siempre sin ocupar
--   espacio en el servidor.
--
--   La limpieza automática de los 6 meses (archivo 11) SIGUE ACTIVA. Es la
--   red de seguridad para las fotos que nadie incluyó nunca en un informe.
--
-- EL PROBLEMA QUE HABÍA QUE RESOLVER PRIMERO
--
--   Hasta ahora la tabla paquetes solo la podían tocar dos personas:
--     · el residente, para ver LAS SUYAS
--     · portería, para recibirlas y entregarlas
--
--   El administrador no tenía ningún permiso sobre esta tabla (más allá de
--   poder borrar una fila entera, que es otra cosa). Sin permiso de LECTURA,
--   ni siquiera podía armar la lista de qué se entregó esta semana.
--
-- POR QUÉ EL PERMISO DE ACTUALIZAR NO SE LIMITA A LAS COLUMNAS DE FOTO
--
--   Postgres no puede decir "puede cambiar esta columna pero no esta otra"
--   dentro de una política de seguridad de fila: eso se resuelve a nivel de
--   fila entera, no de columna. El resto de este proyecto ya vive con esa
--   misma regla (por ejemplo, portería puede actualizar cualquier columna de
--   un paquete de su condominio, no solo las de la entrega). Quien de verdad
--   limita qué columnas se tocan es la APLICACIÓN: el botón de "borrar fotos
--   de este informe" solo manda foto_url, foto_entrega_url y
--   fotos_borradas_en, nunca el resto.
-- ============================================================================


-- ============================================================================
-- 1 · EL ADMINISTRADOR PUEDE VER LAS ENCOMIENDAS DE SU INSTALACIÓN
-- ============================================================================

create policy "administrador ve paquetes del condominio" on public.paquetes
  for select to authenticated
  using (condominio_id = public.mi_condominio() and public.es_administrador());


-- ============================================================================
-- 2 · EL ADMINISTRADOR PUEDE BORRAR LAS FOTOS DESPUÉS DE IMPRIMIR EL INFORME
-- ============================================================================
-- El texto anotado a mano (quién retiró, cuándo, quién entregó) y la firma
-- NUNCA se tocan acá: la app solo vacía las columnas de foto. Eso es lo que
-- sigue sirviendo como constancia después de borrar.
-- ============================================================================

create policy "administrador limpia fotos de paquetes" on public.paquetes
  for update to authenticated
  using (condominio_id = public.mi_condominio() and public.es_administrador())
  with check (condominio_id = public.mi_condominio());


-- ============================================================================
-- 3 · REVISIÓN
-- ============================================================================

-- Esperado: 2 filas nuevas (además de las 5 que ya existían de portería y
-- residente)
select policyname, cmd
  from pg_policies
 where schemaname = 'public' and tablename = 'paquetes'
 order by policyname;


-- ============================================================================
-- FIN DEL ARCHIVO 12
-- ============================================================================
