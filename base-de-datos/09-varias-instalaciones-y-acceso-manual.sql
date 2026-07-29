-- ============================================================================
-- Tomass Seguridad — 09 · Varias instalaciones y acceso manual
-- ============================================================================
-- ⚠️ ESTE ARCHIVO YA ESTÁ APLICADO EN EL SERVIDOR.
--    Queda guardado acá para que el proyecto tenga el historial completo de
--    cómo llegó la base de datos a ser lo que es. Si algún día hay que armar
--    todo de cero, se corre después del 08.
--
-- QUÉ TRAE, EN CRIOLLO
--
--   1. Un administrador puede atender varias instalaciones con una sola cuenta.
--   2. Los colegios no usan código QR: el guardia anota los ingresos a mano.
--   3. Una garita puede controlar peatones y vehículos a la vez.
--   4. Los espacios y las relaciones ahora contemplan colegios y empresas.
-- ============================================================================


-- ============================================================================
-- 1 · UN ADMINISTRADOR PARA VARIAS INSTALACIONES
-- ============================================================================
-- POR QUÉ NO SE TOCÓ NINGUNA DE LAS 38 REGLAS DE SEGURIDAD
--
--   Hay 38 reglas que dicen "solo lo de mi_condominio()". El camino obvio era
--   reescribirlas para que aceptaran una lista en vez de un valor. Es también
--   el camino más peligroso: un renglón mal copiado en cualquiera de las 38
--   hace que un condominio vea los datos de otro, y ese error no da ningún
--   aviso — simplemente aparecen datos de más.
--
--   En vez de eso se cambió lo que CONTESTA mi_condominio(). El administrador
--   trabaja en una instalación a la vez y cambia con un selector. Las 38 reglas
--   dicen exactamente lo mismo que antes y siguen protegiendo igual.
--
-- A PRUEBA DE MANIPULACIÓN
--
--   La instalación elegida se guarda en una columna, pero mi_condominio() la
--   valida antes de usarla. Se probó escribiendo esa columna a la fuerza,
--   salteándose la función, apuntando a un colegio ajeno: el usuario siguió
--   viendo solo lo suyo. El peor resultado de una manipulación es "no pasa
--   nada", nunca "ve datos ajenos".
-- ============================================================================

create table if not exists public.administra_instalaciones (
  usuario_id     uuid not null references public.usuarios(id)    on delete cascade,
  condominio_id  uuid not null references public.condominios(id) on delete cascade,
  creado_en      timestamptz not null default now(),
  primary key (usuario_id, condominio_id)
);

alter table public.administra_instalaciones enable row level security;

drop policy if exists "ver mis instalaciones" on public.administra_instalaciones;
create policy "ver mis instalaciones" on public.administra_instalaciones
  for select to authenticated
  using (usuario_id = auth.uid());

alter table public.usuarios
  add column if not exists condominio_activo uuid
    references public.condominios(id) on delete set null;

create or replace function public.mi_condominio()
returns uuid language sql stable security definer
set search_path = public, pg_temp
as $$
  select coalesce(
    (select u.condominio_activo
       from public.usuarios u
      where u.id = auth.uid()
        and u.estado = 'activo'
        and u.rol = 'administrador'
        and u.condominio_activo is not null
        and (
          u.condominio_activo = u.condominio_id
          or exists (select 1 from public.administra_instalaciones a
                      where a.usuario_id = u.id
                        and a.condominio_id = u.condominio_activo)
        )),
    (select condominio_id from public.usuarios where id = auth.uid())
  );
$$;

-- (mis_instalaciones() y cambiar_de_instalacion() se crearon en la misma
--  migración; ver el panel de Supabase para su texto completo.)


-- ============================================================================
-- 2 · LOS COLEGIOS NO USAN CÓDIGO QR
-- ============================================================================
-- Tienen barrera y portones de cierre, y el guardia abre. No hay nadie
-- apuntando un teléfono a un cartel: lo que hace falta es que el guardia anote
-- el ingreso, para que quede el registro.
-- ============================================================================

alter table public.puntos_acceso
  add column if not exists modo text not null default 'qr'
    check (modo in ('qr','manual'));

-- Una garita puede controlar las dos cosas a la vez (Colegio Alemán)
alter table public.puntos_acceso drop constraint if exists puntos_acceso_tipo_check;
alter table public.puntos_acceso add constraint puntos_acceso_tipo_check
  check (tipo in ('peatonal','vehicular','mixto'));


-- ============================================================================
-- 3 · UN INGRESO ANOTADO A MANO NO TIENE FICHA, PERO SIEMPRE TIENE NOMBRE
-- ============================================================================
-- En un colegio pasa gente sin ficha: un proveedor, un apoderado que todavía no
-- está cargado, una visita de una sola vez. Antes todo movimiento tenía que
-- apuntar a una ficha, y eso lo hacía imposible.
--
-- Se agrega el tipo "manual", que no exige ficha, pero SÍ exige el nombre. Sin
-- esa condición el guardia podría guardar registros vacíos, y el historial
-- dejaría de servir como prueba, que es para lo único que existe.
-- ============================================================================

alter table public.movimientos_acceso
  drop constraint if exists movimientos_acceso_persona_tipo_check;
alter table public.movimientos_acceso
  add constraint movimientos_acceso_persona_tipo_check
  check (persona_tipo in ('residente','visita','personal_servicio','manual'));

alter table public.movimientos_acceso drop constraint if exists movimientos_acceso_check;
alter table public.movimientos_acceso add constraint movimientos_acceso_check
  check (
       (persona_tipo = 'residente'         and residente_id         is not null)
    or (persona_tipo = 'visita'            and visita_id            is not null)
    or (persona_tipo = 'personal_servicio' and personal_servicio_id is not null)
    or (persona_tipo = 'manual'
        and nombre_snapshot is not null
        and length(trim(nombre_snapshot)) >= 3)
  );

-- La función registrar_acceso_manual() revisa tres cosas antes de anotar:
--   · que el guardia tenga turno abierto (es lo que deja constancia de quién
--     estaba a cargo),
--   · que la garita sea de SU instalación,
--   · que el nombre no venga vacío.
-- Probado: rechaza los tres casos y anota bien los válidos.


-- ============================================================================
-- 4 · LOS ESPACIOS Y LAS RELACIONES DE UN COLEGIO
-- ============================================================================
-- Las listas cerradas se habían quedado cortas: no existía "curso" ni
-- "apoderado", así que dar de alta un apoderado era literalmente imposible.
-- ============================================================================

alter table public.unidades drop constraint if exists unidades_tipo_check;
alter table public.unidades add constraint unidades_tipo_check
  check (tipo in ('apartamento','casa','curso','oficina','otro'));

alter table public.usuarios drop constraint if exists usuarios_relacion_unidad_check;
alter table public.usuarios add constraint usuarios_relacion_unidad_check
  check (relacion_unidad in (
    'propietario', 'arrendatario', 'familiar',  -- condominios y edificios
    'apoderado',                                 -- colegios
    'trabajador',                                -- empresas
    'otro'));


-- ============================================================================
-- FIN DEL ARCHIVO 09
-- ============================================================================
