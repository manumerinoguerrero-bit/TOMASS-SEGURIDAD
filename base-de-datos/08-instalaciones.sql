-- ============================================================================
-- Tomass Seguridad — 08 · LAS INSTALACIONES QUE ATIENDE LA EMPRESA
-- ============================================================================
-- QUÉ CAMBIA Y POR QUÉ
--
--   El sistema se diseñó pensando en condominios. Pero Tomass Seguridad Privada
--   también atiende COLEGIOS, y a un colegio no se le puede hablar de
--   "residentes", "unidades" ni "copropietarios".
--
--   Se agrega el TIPO de instalación. Con eso la app puede usar las palabras
--   correctas en cada lugar: en un condominio dice "residente" y "unidad", en un
--   colegio dice "apoderado" y "curso".
--
-- POR QUÉ LA TABLA SIGUE LLAMÁNDOSE "condominios"
--
--   Renombrarla obligaría a tocar unas 50 partes de la base de datos, las tres
--   funciones del servidor y unos 20 archivos de la app. Es un cambio grande y
--   riesgoso, y el nombre interno de una tabla no lo ve nunca ningún usuario.
--
--   Lo que SÍ ve el usuario son los textos de la app, y esos usan la palabra
--   correcta según el tipo. Si más adelante conviene renombrarla, se hace en un
--   momento tranquilo y no encima de un sistema que está funcionando.
--
-- Cómo se usa:
--   Pegá TODO este archivo en el editor SQL de Supabase y presioná "Run".
--   Ejecutar DESPUÉS de 07-guardia-cubre-todo.sql.
-- ============================================================================


-- ============================================================================
-- 1 · EL TIPO DE INSTALACIÓN
-- ============================================================================

alter table public.condominios
  add column if not exists tipo text not null default 'condominio'
    check (tipo in ('condominio','colegio','empresa','edificio','otro'));

comment on column public.condominios.tipo is
  'Que clase de instalacion es. Define las palabras que usa la app: en un '
  'condominio "residente" y "unidad", en un colegio "apoderado" y "curso".';

-- Nombre corto para mostrar, por si el nombre oficial es muy largo
alter table public.condominios
  add column if not exists nombre_corto text;

comment on column public.condominios.nombre_corto is
  'Version corta del nombre, para las pantallas angostas del celular.';


-- ============================================================================
-- 2 · LAS PALABRAS DE CADA TIPO
-- ============================================================================
-- La app le pide a esta función cómo llamarle a las cosas, en lugar de tener la
-- palabra "condominio" escrita a mano en cada pantalla.
-- ============================================================================

create or replace function public.palabras_de_la_instalacion(p_tipo text)
returns table (
  la_instalacion  text,   -- "el condominio" / "el colegio"
  el_habitante    text,   -- "residente" / "apoderado"
  los_habitantes  text,   -- "residentes" / "apoderados"
  el_espacio      text,   -- "unidad" / "curso"
  los_espacios    text    -- "unidades" / "cursos"
)
language sql
immutable
as $$
  -- Se nombran las columnas una por una: con "select *" se colaría también la
  -- columna "tipo" y la función devolvería una columna de más.
  select p.la_instalacion, p.el_habitante, p.los_habitantes,
         p.el_espacio, p.los_espacios
    from (values
      ('condominio', 'el condominio', 'residente', 'residentes', 'unidad', 'unidades'),
      ('colegio',    'el colegio',    'apoderado', 'apoderados', 'curso',  'cursos'),
      ('empresa',    'la empresa',    'trabajador','trabajadores','oficina','oficinas'),
      ('edificio',   'el edificio',   'residente', 'residentes', 'departamento', 'departamentos'),
      ('otro',       'la instalación','usuario',   'usuarios',   'unidad', 'unidades')
    ) as p(tipo, la_instalacion, el_habitante, los_habitantes, el_espacio, los_espacios)
   where p.tipo = coalesce(p_tipo, 'condominio');
$$;

grant execute on function public.palabras_de_la_instalacion(text)
  to authenticated, service_role;


-- ============================================================================
-- 3 · LAS INSTALACIONES QUE ATIENDE TOMASS SEGURIDAD PRIVADA
-- ============================================================================
-- Cada una nace con sus dos entradas (peatonal y vehicular) y con su propia
-- llave secreta para firmar los códigos QR, que se crea sola.
--
-- ⚠️ Los códigos de los carteles del muro se generan al azar y son distintos
--    para cada entrada. Están abajo, en el paso 5: hay que imprimirlos.
-- ============================================================================

insert into public.condominios (nombre, nombre_corto, tipo, ciudad, plan)
values
  ('Condominio Cerro Grande',              'Cerro Grande',   'condominio', 'Coquimbo', 'profesional'),
  ('Condominio Milagros de Cerro Grande',  'Los Milagros',   'condominio', 'Coquimbo', 'profesional'),
  ('Colegio Alemán',                       'Colegio Alemán', 'colegio',    'La Serena', 'profesional'),
  ('Colegio International',                'International',  'colegio',    'La Serena', 'profesional'),
  ('Condominio Encomenderos',              'Encomenderos',   'condominio', 'Coquimbo', 'profesional')
on conflict do nothing;


-- ============================================================================
-- 4 · LAS ENTRADAS DE CADA UNA
-- ============================================================================
-- Todas arrancan con una entrada peatonal y una vehicular. Si alguna tiene más
-- puertas, se agregan después desde el panel del administrador.
-- ============================================================================

insert into public.puntos_acceso (condominio_id, nombre, tipo, ubicacion)
select c.id, 'Entrada Peatonal', 'peatonal', 'Portón peatonal principal'
  from public.condominios c
 where c.nombre in (
        'Condominio Cerro Grande',
        'Condominio Milagros de Cerro Grande',
        'Colegio Alemán',
        'Colegio International',
        'Condominio Encomenderos')
   and not exists (
        select 1 from public.puntos_acceso p
         where p.condominio_id = c.id and p.tipo = 'peatonal');

insert into public.puntos_acceso (condominio_id, nombre, tipo, ubicacion)
select c.id, 'Entrada Vehicular', 'vehicular', 'Barrera del estacionamiento'
  from public.condominios c
 where c.nombre in (
        'Condominio Cerro Grande',
        'Condominio Milagros de Cerro Grande',
        'Colegio Alemán',
        'Colegio International',
        'Condominio Encomenderos')
   and not exists (
        select 1 from public.puntos_acceso p
         where p.condominio_id = c.id and p.tipo = 'vehicular');


-- ============================================================================
-- 5 · REVISIÓN Y CÓDIGOS PARA IMPRIMIR
-- ============================================================================

-- Todas las instalaciones, con sus entradas y su llave ya creada
select c.nombre,
       c.tipo,
       (select count(*) from public.puntos_acceso p where p.condominio_id = c.id) as entradas,
       (select count(*) from public.secretos_condominio s where s.condominio_id = c.id) as tiene_llave
  from public.condominios c
 order by c.tipo, c.nombre;

-- ⚠️ ESTOS SON LOS CÓDIGOS QUE VAN IMPRESOS EN LOS CARTELES DEL MURO.
--    Cada entrada tiene el suyo y NO se repiten. Guardalos: son lo que
--    convierte un cartel pegado en la pared en una puerta del sistema.
select c.nombre as instalacion,
       p.nombre as entrada,
       p.codigo_qr_estatico as codigo_para_el_cartel
  from public.puntos_acceso p
  join public.condominios c on c.id = p.condominio_id
 order by c.nombre, p.tipo;


-- ============================================================================
-- FIN DEL ARCHIVO 08
-- ============================================================================
