-- ============================================================================
-- Tomass Seguridad — 13 · Guardias que atienden más de una instalación
-- ============================================================================
-- ⚠️ ESTE ARCHIVO YA ESTÁ APLICADO EN EL SERVIDOR. Queda para el historial.
--
-- LA DECISIÓN, Y POR QUÉ
--
--   Al cargar la planilla real de guardias, Manuel confirmó que tres personas
--   trabajan en DOS instalaciones cada una (turnos rotativos):
--
--     Hector Cortes Llanos  → Colegio Alemán (su instalación) y Viveros Yapur
--     Ivan Aracena Araya    → Milagros de Cerro Grande (la suya) y Viveros Yapur
--     Riends Saenz Rojas    → Milagros de Cerro Grande (la suya) y Colegio Alemán
--
--   Hasta ahora, solo el administrador podía atender más de una instalación
--   (con el selector "Cambiar" del panel). Un guardia estaba encerrado en la
--   suya para siempre. Con gente real que rota entre dos, esa limitación dejó
--   de ser teórica.
--
-- POR QUÉ NO HIZO FALTA INVENTAR NADA NUEVO
--
--   El mecanismo para "atender más de una instalación" ya existía completo
--   para el administrador: la tabla administra_instalaciones (quién puede
--   entrar a cuál) y la columna usuarios.condominio_activo (en cuál está
--   parado ahora). Las tres funciones que lo usan (mi_condominio,
--   cambiar_de_instalacion, mis_instalaciones) solo revisaban
--   rol = 'administrador'. Se cambió esa única condición para que también
--   acepte rol = 'guardia'. Nada más se tocó.
--
--   El resto de la app ya estaba listo sin saberlo: la lista de puestos de
--   acceso del guardia no filtra por condominio a mano, confía en la política
--   de seguridad de la base, que compara contra mi_condominio() sin mirar el
--   rol. Y el perfil que se muestra en pantalla ya prefería la instalación
--   "activa" por sobre la "propia" también sin mirar el rol. Extender el
--   permiso alcanzó para que todo lo demás funcionara solo.
-- ============================================================================


-- ============================================================================
-- 1 · LAS TRES FUNCIONES, CON rol IN ('administrador', 'guardia')
-- ============================================================================
-- Ver el texto completo en el panel de Supabase, migración
-- guardias_pueden_atender_mas_de_una_instalacion. Acá solo el resumen de qué
-- cambió: en mi_condominio(), cambiar_de_instalacion() y mis_instalaciones(),
-- todas las apariciones de
--
--   u.rol = 'administrador'    /   yo.rol = 'administrador'
--
-- pasaron a
--
--   u.rol in ('administrador', 'guardia')   /   yo.rol in ('administrador', 'guardia')
-- ============================================================================


-- ============================================================================
-- 2 · EL PERMISO PARA LOS TRES GUARDIAS
-- ============================================================================

insert into public.administra_instalaciones (usuario_id, condominio_id)
select u.id, c.id
  from public.usuarios u, public.condominios c
 where (u.email = 'h.cortes.arica@gmail.com'  and c.nombre = 'Viveros Yapur')
    or (u.email = 'ivanaracena422@gmail.com'  and c.nombre = 'Viveros Yapur')
    or (u.email = 'saenzriends@gmail.com'     and c.nombre = 'Colegio Alemán')
on conflict do nothing;


-- ============================================================================
-- 3 · REVISIÓN
-- ============================================================================

-- Esperado: 3 filas
select u.nombre_completo, c.nombre as instalacion_extra
  from public.administra_instalaciones a
  join public.usuarios u on u.id = a.usuario_id
  join public.condominios c on c.id = a.condominio_id
 where u.rol = 'guardia'
 order by u.nombre_completo;


-- ============================================================================
-- FIN DEL ARCHIVO 13
-- ============================================================================
