-- ============================================================================
-- Tomass Seguridad — 05 · LLAVES SECRETAS Y LÍMITES
-- ============================================================================
-- Qué hace este archivo:
--   Prepara dos cosas que necesita la Fase 2 (los códigos QR de seguridad).
--
--   1. LA LLAVE SECRETA que firma los códigos QR.
--
--      Pensalo como el sello de un notario. El servidor firma cada código con
--      esta llave, y cuando alguien presenta un código, el servidor revisa que
--      el sello sea el suyo. Sin la llave es imposible fabricar un código falso.
--
--      Cada condominio tiene SU PROPIA llave. Si algún día se filtrara la de un
--      condominio, los otros siguen seguros. Se crean solas y nunca hay que
--      tocarlas.
--
--   2. EL LÍMITE DE CÓDIGOS por residente.
--
--      Máximo un código nuevo cada 30 segundos. Evita que alguien programe algo
--      para pedir miles de códigos y saturar el servidor.
--
-- Cómo se usa:
--   Pegá TODO este archivo en el editor SQL de Supabase y presioná "Run".
--   Ejecutar DESPUÉS de 04-datos-de-ejemplo.sql.
-- ============================================================================


-- ============================================================================
-- 1 · LA LLAVE SECRETA DE CADA CONDOMINIO
-- ============================================================================
-- ⚠️ Esta tabla es la más sensible de todo el sistema.
--    Nadie que use la app puede leerla, ni el administrador. Solo el servidor,
--    que trabaja con una llave especial que nunca viaja dentro del celular.
-- ============================================================================

create table public.secretos_condominio (
  condominio_id uuid primary key
                references public.condominios(id) on delete cascade,
  -- 64 caracteres al azar. Nunca se muestra en ninguna pantalla.
  secreto_qr    text not null
                default encode(extensions.gen_random_bytes(32), 'hex'),
  -- Si algún día hay que cambiarla, se anota cuándo
  rotado_en     timestamptz,
  rotado_por    uuid references public.usuarios(id) on delete set null,
  creado_en     timestamptz not null default now()
);

comment on table public.secretos_condominio is
  'Llave con la que el servidor firma los codigos QR. Solo alcanzable por el servidor.';

alter table public.secretos_condominio enable row level security;

-- A propósito NO hay ninguna regla de acceso acá.
-- Con la seguridad encendida y sin reglas, la tabla queda completamente cerrada
-- para cualquiera que use la app. Solo el servidor entra.
revoke all on public.secretos_condominio from authenticated, anon;
grant  all on public.secretos_condominio to service_role;


-- La llave se crea sola cuando se da de alta un condominio nuevo.
-- Así nunca hay que acordarse de este paso.
create or replace function public.crear_llave_condominio()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  insert into public.secretos_condominio (condominio_id)
  values (new.id)
  on conflict (condominio_id) do nothing;
  return new;
end;
$$;

create trigger tr_condominio_crea_su_llave
  after insert on public.condominios
  for each row execute function public.crear_llave_condominio();

-- Y para los condominios que ya existían antes de este archivo
insert into public.secretos_condominio (condominio_id)
select id from public.condominios
on conflict (condominio_id) do nothing;


-- ============================================================================
-- 2 · EL LÍMITE DE CÓDIGOS POR RESIDENTE
-- ============================================================================
-- Una sola columna: cuándo fue la última vez que este residente pidió un código.
-- El servidor la revisa antes de emitir uno nuevo.
--
-- Se eligió una columna en lugar de una tabla aparte para que no crezca sin
-- control: acá siempre hay un solo dato por persona, no un historial.
-- ============================================================================

alter table public.usuarios
  add column ultimo_qr_emitido_en timestamptz;

comment on column public.usuarios.ultimo_qr_emitido_en is
  'Ultima vez que se le emitio un codigo QR. Sirve para el limite de 1 cada 30 segundos.';


-- ============================================================================
-- 3 · EL RESIDENTE NO PUEDE MODIFICAR SU PROPIO LÍMITE
-- ============================================================================
-- Sin esto, un residente podría editar su propia ficha para borrar la marca de
-- tiempo y saltarse el límite. Este candado lo impide: si intenta cambiar esa
-- columna, o su rol, o su estado, la base de datos lo rechaza.
--
-- El administrador sí puede (pasa por otra regla de seguridad distinta).
-- ============================================================================

create or replace function public.proteger_campos_sensibles()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  -- Si quien edita es el dueño de la ficha y NO es administrador,
  -- estos campos tienen que quedar tal como estaban.
  if auth.uid() = old.id and not public.es_administrador() then
    if new.rol                  is distinct from old.rol
    or new.estado               is distinct from old.estado
    or new.condominio_id        is distinct from old.condominio_id
    or new.unidad_id            is distinct from old.unidad_id
    or new.ultimo_qr_emitido_en is distinct from old.ultimo_qr_emitido_en then
      raise exception
        'No podés cambiar tu rol, tu estado, tu unidad ni tu límite de códigos. '
        'Pedíselo a la administración.'
        using errcode = 'insufficient_privilege';
    end if;
  end if;
  return new;
end;
$$;

create trigger tr_usuarios_proteger_campos
  before update on public.usuarios
  for each row execute function public.proteger_campos_sensibles();


-- ============================================================================
-- 4 · AVISOS EN VIVO PARA LA COLA DE AUTOS
-- ============================================================================
-- Ya se activó en el archivo 03 para solicitudes_vehiculares y notificaciones.
-- Acá se agrega la tabla de movimientos, para que el panel del guardia muestre
-- las entradas peatonales apareciendo solas, sin recargar.
-- ============================================================================

alter publication supabase_realtime add table public.movimientos_acceso;


-- ============================================================================
-- 5 · CERRAR LOS PERMISOS DE RAÍZ  ← el bloque más importante de este archivo
-- ============================================================================
-- ESTO CORRIGE UN PROBLEMA QUE NO ES OBVIO Y QUE ES FÁCIL DEJAR PASAR.
--
-- Supabase viene configurado para que TODA función nueva que se cree quede
-- automáticamente al alcance de la app. O sea: cada vez que alguien agregue una
-- función interna en el futuro, sin querer la está publicando.
--
-- Este bloque hace tres cosas, en este orden:
--   1. Apaga ese permiso automático, para las funciones que vengan.
--   2. Se lo quita a todas las que ya existen.
--   3. Se lo devuelve SOLO a la lista de abajo.
--
-- Resultado: cualquier función que no esté en esa lista queda inalcanzable desde
-- el celular. Es lo contrario de la configuración de fábrica, y es lo correcto.
--
-- ⚠️ SI EN EL FUTURO SE AGREGA UNA FUNCIÓN QUE LA APP DEBE PODER LLAMAR,
--    HAY QUE SUMARLA A LA LISTA DEL PASO 3. Si no, la app recibirá un error de
--    permisos. Es a propósito: es mejor que falle a la vista que quede abierta
--    en silencio.
--
-- (Lo detectó el chequeo de seguridad de Supabase al probar la Fase 2.)
-- ============================================================================

-- 1 · Que las funciones NUEVAS no reciban el permiso solas
alter default privileges in schema public revoke execute on functions from public;
alter default privileges in schema public revoke execute on functions from anon;
alter default privileges in schema public revoke execute on functions from authenticated;

-- 2 · Quitárselo a todas las que ya existen
revoke execute on all functions in schema public from public;
revoke execute on all functions in schema public from anon;
revoke execute on all functions in schema public from authenticated;

-- 3 · Devolvérselo SOLO a las que la app necesita de verdad
grant execute on function
  public.mi_condominio,
  public.mi_rol,
  public.es_administrador,
  public.es_guardia,
  public.es_porteria,
  public.mi_turno_activo,
  public.mi_punto_acceso,
  public.registrar_movimiento,
  public.resolver_solicitud_vehicular,
  public.validar_personal_servicio,
  public.cerrar_turno
to authenticated;

-- 4 · El servidor puede usar todas, incluida la limpieza automática.
--     Su llave secreta vive solo en el servidor y nunca viaja dentro de la app.
grant execute on all functions in schema public to service_role;


-- ============================================================================
-- 6 · REVISIÓN
-- ============================================================================

-- Esperado: una fila por condominio, con la llave ya creada
select c.nombre,
       length(s.secreto_qr) as largo_de_la_llave,
       s.creado_en is not null as llave_lista
  from public.condominios c
  join public.secretos_condominio s on s.condominio_id = c.id;

-- Esperado: 0. Confirma que la tabla de llaves no tiene ninguna regla de acceso,
-- o sea que está cerrada para todos los que usan la app.
--
-- (El chequeo de seguridad de Supabase marca esto como un aviso informativo:
--  "RLS enabled, no policy". En este caso es CORRECTO y es a propósito. Es la
--  única tabla del sistema pensada para que nadie la lea desde la app.)
select count(*) as reglas_de_acceso_a_las_llaves
  from pg_policies
 where schemaname = 'public' and tablename = 'secretos_condominio';

-- Esperado: 11 en "true" y 5 en "false". Las 11 son las que la app necesita
-- llamar; las 5 son internas y quedan cerradas.
select has_function_privilege('authenticated', p.oid, 'EXECUTE') as la_app_puede_llamarla,
       count(*) as cuantas,
       string_agg(p.proname, ', ' order by p.proname) as funciones
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public'
 group by 1 order by 1 desc;


-- ============================================================================
-- FIN DEL ARCHIVO 05
-- ============================================================================
