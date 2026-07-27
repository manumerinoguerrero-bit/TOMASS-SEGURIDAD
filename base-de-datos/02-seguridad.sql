-- ============================================================================
-- Tomass Seguridad — 02 · SEGURIDAD
-- ============================================================================
-- Qué hace este archivo:
--   Pone los candados. Es la parte más importante de todo el sistema.
--
--   Sin esto, cualquier residente con conocimientos podría leer los datos de
--   todos los demás desde su celular. Con esto, la base de datos misma bloquea
--   el acceso: no depende de que la app se acuerde de filtrar.
--
--   Se apoya en una función de PostgreSQL llamada RLS (Row Level Security, o
--   "seguridad a nivel de fila"), que decide fila por fila quién puede verla.
--
-- Las tres garantías que quedan grabadas acá:
--   1. Un condominio NUNCA ve datos de otro condominio.
--   2. Un residente solo ve SUS vehículos, SUS paquetes y SUS movimientos.
--   3. Los movimientos de acceso no se pueden modificar ni borrar. Por nadie.
--
-- Cómo se usa:
--   Pegá TODO este archivo en el editor SQL de Supabase y presioná "Run".
--   Ejecutar DESPUÉS de 01-tablas.sql.
-- ============================================================================


-- ============================================================================
-- PARTE A · FUNCIONES DE APOYO
-- ============================================================================
-- Estas funciones responden "¿quién es el que está preguntando?".
-- Van marcadas como SECURITY DEFINER, que significa que pueden consultar la
-- tabla de usuarios sin quedar atrapadas en las mismas reglas que están
-- ayudando a aplicar (si no, se llamarían a sí mismas para siempre).
-- ============================================================================

-- A qué condominio pertenece la persona que está usando la app ahora mismo
create or replace function public.mi_condominio()
returns uuid
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select condominio_id from public.usuarios where id = auth.uid();
$$;

-- Qué rol tiene: administrador, guardia o residente
create or replace function public.mi_rol()
returns text
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select rol from public.usuarios where id = auth.uid() and estado = 'activo';
$$;

create or replace function public.es_administrador()
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select coalesce(
    (select rol = 'administrador' from public.usuarios
      where id = auth.uid() and estado = 'activo'),
    false);
$$;

create or replace function public.es_guardia()
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select coalesce(
    (select rol = 'guardia' from public.usuarios
      where id = auth.uid() and estado = 'activo'),
    false);
$$;

-- Personal de portería = guardia o administrador. Se usa mucho más abajo.
create or replace function public.es_porteria()
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select coalesce(
    (select rol in ('guardia','administrador') from public.usuarios
      where id = auth.uid() and estado = 'activo'),
    false);
$$;

-- El turno abierto del guardia que está usando la app (null si no tiene)
create or replace function public.mi_turno_activo()
returns uuid
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select id from public.turnos
   where guardia_id = auth.uid() and cerrado_en is null
   order by inicio desc limit 1;
$$;

-- En qué punto de acceso está parado ahora. Esto decide a qué guardia le llegan
-- las notificaciones de autos esperando la barrera.
create or replace function public.mi_punto_acceso()
returns uuid
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select punto_acceso_id from public.turnos
   where guardia_id = auth.uid() and cerrado_en is null
   order by inicio desc limit 1;
$$;

grant execute on function
  public.mi_condominio, public.mi_rol, public.es_administrador,
  public.es_guardia, public.es_porteria, public.mi_turno_activo,
  public.mi_punto_acceso
to authenticated;


-- ============================================================================
-- PARTE B · TABLAS DE SOLO AGREGAR
-- ============================================================================
-- Un registro de acceso que se puede editar no sirve como prueba de nada.
-- Este bloqueo hace que la base de datos rechace cualquier intento de cambiar o
-- borrar un movimiento, incluso si viene del administrador o de un error de
-- programación en la app.
-- ============================================================================

create or replace function public.bloquear_modificacion()
returns trigger
language plpgsql
-- Fijar el search_path es obligatorio por seguridad: sin esto, alguien podría
-- crear una tabla falsa en otro esquema y hacer que la función la use en lugar
-- de la verdadera.
set search_path = public, pg_temp
as $$
begin
  raise exception
    'La tabla % es de solo agregar: sus registros no se pueden modificar ni borrar.',
    tg_table_name
    using errcode = 'restrict_violation';
end;
$$;

create trigger tr_movimientos_solo_agregar
  before update or delete on public.movimientos_acceso
  for each row execute function public.bloquear_modificacion();

create trigger tr_auditoria_solo_agregar
  before update or delete on public.auditoria
  for each row execute function public.bloquear_modificacion();


-- ============================================================================
-- PARTE C · MANTENER actualizado_en AL DÍA
-- ============================================================================

create or replace function public.marcar_actualizado()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  new.actualizado_en := now();
  return new;
end;
$$;

create trigger tr_usuarios_actualizado
  before update on public.usuarios
  for each row execute function public.marcar_actualizado();


-- ============================================================================
-- PARTE D · ENCENDER LOS CANDADOS EN TODAS LAS TABLAS
-- ============================================================================
-- Al activar RLS, la tabla queda cerrada por completo. Solo se puede leer o
-- escribir lo que las reglas de la Parte E autoricen explícitamente.
-- Cualquier tabla nueva que se agregue en el futuro DEBE pasar por acá.
-- ============================================================================

alter table public.condominios            enable row level security;
alter table public.unidades               enable row level security;
alter table public.usuarios               enable row level security;
alter table public.puntos_acceso          enable row level security;
alter table public.vehiculos              enable row level security;
alter table public.turnos                 enable row level security;
alter table public.dispositivos           enable row level security;
alter table public.visitas                enable row level security;
alter table public.personal_servicio      enable row level security;
alter table public.movimientos_acceso     enable row level security;
alter table public.solicitudes_vehiculares enable row level security;
alter table public.paquetes               enable row level security;
alter table public.incidentes             enable row level security;
alter table public.notificaciones         enable row level security;
alter table public.auditoria              enable row level security;


-- ============================================================================
-- PARTE E · LAS REGLAS, TABLA POR TABLA
-- ============================================================================

-- ---------------------------------------------------------------- CONDOMINIOS
-- Todos ven su propio condominio. Solo el administrador puede editarlo.

create policy "ver mi condominio" on public.condominios
  for select to authenticated
  using (id = public.mi_condominio());

create policy "administrador edita su condominio" on public.condominios
  for update to authenticated
  using (id = public.mi_condominio() and public.es_administrador())
  with check (id = public.mi_condominio());


-- ------------------------------------------------------------------- UNIDADES
-- Todos ven las unidades de su condominio (el guardia necesita saber que existe
-- la 101 para asignarle un paquete). Solo el administrador las crea y edita.

create policy "ver unidades de mi condominio" on public.unidades
  for select to authenticated
  using (condominio_id = public.mi_condominio());

create policy "administrador gestiona unidades" on public.unidades
  for all to authenticated
  using (condominio_id = public.mi_condominio() and public.es_administrador())
  with check (condominio_id = public.mi_condominio() and public.es_administrador());


-- ------------------------------------------------------------------- USUARIOS
-- Cada uno ve su propia ficha. El guardia y el administrador ven a todos los de
-- su condominio, porque el guardia necesita la foto y la unidad para verificar
-- identidades. Un residente NO puede ver la lista de residentes.

create policy "ver mi propia ficha" on public.usuarios
  for select to authenticated
  using (id = auth.uid());

create policy "porteria ve usuarios de su condominio" on public.usuarios
  for select to authenticated
  using (condominio_id = public.mi_condominio() and public.es_porteria());

create policy "editar mi propia ficha" on public.usuarios
  for update to authenticated
  using (id = auth.uid())
  with check (id = auth.uid());

create policy "administrador gestiona usuarios" on public.usuarios
  for all to authenticated
  using (condominio_id = public.mi_condominio() and public.es_administrador())
  with check (condominio_id = public.mi_condominio() and public.es_administrador());

-- Nota: a propósito NO hay regla de DELETE para nadie más que el administrador.
-- Cuando alguien se muda se pone estado = 'inactivo', no se borra, para que su
-- historial de accesos siga existiendo.


-- -------------------------------------------------------------- PUNTOS ACCESO

create policy "ver puntos de acceso de mi condominio" on public.puntos_acceso
  for select to authenticated
  using (condominio_id = public.mi_condominio());

create policy "administrador gestiona puntos de acceso" on public.puntos_acceso
  for all to authenticated
  using (condominio_id = public.mi_condominio() and public.es_administrador())
  with check (condominio_id = public.mi_condominio() and public.es_administrador());


-- ------------------------------------------------------------------ VEHÍCULOS
-- El residente ve y registra los suyos. La portería ve todos (el guardia tiene
-- que poder comparar la patente que ve con la registrada). Solo el
-- administrador aprueba o rechaza.

create policy "residente ve sus vehiculos" on public.vehiculos
  for select to authenticated
  using (residente_id = auth.uid());

create policy "porteria ve vehiculos del condominio" on public.vehiculos
  for select to authenticated
  using (condominio_id = public.mi_condominio() and public.es_porteria());

create policy "residente registra sus vehiculos" on public.vehiculos
  for insert to authenticated
  with check (
    residente_id = auth.uid()
    and condominio_id = public.mi_condominio()
    -- Nadie puede registrar un vehículo ya aprobado: siempre nace pendiente
    and estado = 'pendiente'
  );

create policy "residente edita su vehiculo mientras esta pendiente" on public.vehiculos
  for update to authenticated
  using (residente_id = auth.uid() and estado = 'pendiente')
  with check (residente_id = auth.uid() and estado = 'pendiente');

create policy "residente borra su vehiculo" on public.vehiculos
  for delete to authenticated
  using (residente_id = auth.uid());

create policy "administrador aprueba vehiculos" on public.vehiculos
  for all to authenticated
  using (condominio_id = public.mi_condominio() and public.es_administrador())
  with check (condominio_id = public.mi_condominio() and public.es_administrador());


-- --------------------------------------------------------------------- TURNOS
-- El guardia abre y cierra su propio turno. El administrador ve todos.

create policy "guardia ve sus turnos" on public.turnos
  for select to authenticated
  using (guardia_id = auth.uid());

create policy "administrador ve todos los turnos" on public.turnos
  for select to authenticated
  using (condominio_id = public.mi_condominio() and public.es_administrador());

create policy "guardia abre su turno" on public.turnos
  for insert to authenticated
  with check (
    guardia_id = auth.uid()
    and condominio_id = public.mi_condominio()
    and public.es_guardia()
  );

create policy "guardia cierra su turno" on public.turnos
  for update to authenticated
  using (guardia_id = auth.uid())
  with check (guardia_id = auth.uid());

create policy "administrador gestiona turnos" on public.turnos
  for all to authenticated
  using (condominio_id = public.mi_condominio() and public.es_administrador())
  with check (condominio_id = public.mi_condominio() and public.es_administrador());


-- --------------------------------------------------------------- DISPOSITIVOS
-- Cada uno registra su propio teléfono. El administrador puede revocarlo — esto
-- es lo que usás el día que un guardia renuncia y se lleva la app instalada en
-- su celular personal.

create policy "ver mis dispositivos" on public.dispositivos
  for select to authenticated
  using (usuario_id = auth.uid());

create policy "administrador ve dispositivos del condominio" on public.dispositivos
  for select to authenticated
  using (condominio_id = public.mi_condominio() and public.es_administrador());

create policy "registrar mi dispositivo" on public.dispositivos
  for insert to authenticated
  with check (usuario_id = auth.uid() and condominio_id = public.mi_condominio());

create policy "actualizar mi dispositivo" on public.dispositivos
  for update to authenticated
  using (usuario_id = auth.uid())
  with check (usuario_id = auth.uid());

create policy "administrador revoca dispositivos" on public.dispositivos
  for all to authenticated
  using (condominio_id = public.mi_condominio() and public.es_administrador())
  with check (condominio_id = public.mi_condominio() and public.es_administrador());


-- -------------------------------------------------------------------- VISITAS
-- El residente ve las visitas que él invitó y las que le anunciaron. La portería
-- ve todas las del condominio, porque tiene que escanear el código en la garita.

create policy "residente ve sus visitas" on public.visitas
  for select to authenticated
  using (residente_id = auth.uid() or creada_por = auth.uid());

create policy "porteria ve visitas del condominio" on public.visitas
  for select to authenticated
  using (condominio_id = public.mi_condominio() and public.es_porteria());

-- Caso 1: el residente pre-registra una visita desde su celular
create policy "residente preregistra visita" on public.visitas
  for insert to authenticated
  with check (
    residente_id = auth.uid()
    and creada_por = auth.uid()
    and condominio_id = public.mi_condominio()
    and origen = 'preregistrada'
  );

-- Caso 2: llega alguien sin aviso y el guardia lo registra. Nace en
-- 'esperando_aprobacion': el residente tiene que decir sí o no desde su celular.
create policy "guardia registra visita espontanea" on public.visitas
  for insert to authenticated
  with check (
    public.es_guardia()
    and creada_por = auth.uid()
    and condominio_id = public.mi_condominio()
    and origen = 'espontanea'
    and estado = 'esperando_aprobacion'
  );

-- El residente aprueba o rechaza desde la notificación
create policy "residente responde su visita" on public.visitas
  for update to authenticated
  using (residente_id = auth.uid())
  with check (residente_id = auth.uid());

create policy "porteria marca visita como usada" on public.visitas
  for update to authenticated
  using (condominio_id = public.mi_condominio() and public.es_porteria())
  with check (condominio_id = public.mi_condominio());


-- ---------------------------------------------------------- PERSONAL SERVICIO
-- El residente registra a su nana o jardinero. El administrador aprueba.
-- La portería los ve para poder escanear su credencial.

create policy "residente ve su personal de servicio" on public.personal_servicio
  for select to authenticated
  using (residente_id = auth.uid());

create policy "porteria ve personal de servicio" on public.personal_servicio
  for select to authenticated
  using (condominio_id = public.mi_condominio() and public.es_porteria());

create policy "residente registra personal de servicio" on public.personal_servicio
  for insert to authenticated
  with check (
    residente_id = auth.uid()
    and condominio_id = public.mi_condominio()
    and estado = 'pendiente'
  );

create policy "residente edita o finaliza su personal" on public.personal_servicio
  for update to authenticated
  using (residente_id = auth.uid())
  with check (residente_id = auth.uid());

create policy "administrador gestiona personal de servicio" on public.personal_servicio
  for all to authenticated
  using (condominio_id = public.mi_condominio() and public.es_administrador())
  with check (condominio_id = public.mi_condominio() and public.es_administrador());


-- -------------------------------------------------------- MOVIMIENTOS ACCESO
-- El residente ve solo sus propias entradas y salidas.
-- La portería y el administrador ven todo el movimiento del condominio.
-- NADIE puede modificar ni borrar: no hay reglas de UPDATE ni DELETE, y encima
-- está el bloqueo de la Parte B por si alguien las agrega por error.

create policy "residente ve sus movimientos" on public.movimientos_acceso
  for select to authenticated
  using (residente_id = auth.uid());

create policy "porteria ve movimientos del condominio" on public.movimientos_acceso
  for select to authenticated
  using (condominio_id = public.mi_condominio() and public.es_porteria());

create policy "registrar movimiento en mi condominio" on public.movimientos_acceso
  for insert to authenticated
  with check (condominio_id = public.mi_condominio());


-- --------------------------------------------------- SOLICITUDES VEHICULARES
-- El residente crea la solicitud al escanear el QR de la barrera.
-- El guardia la resuelve con el botón ABRIR ACCESO.

create policy "residente ve sus solicitudes" on public.solicitudes_vehiculares
  for select to authenticated
  using (residente_id = auth.uid());

create policy "porteria ve solicitudes del condominio" on public.solicitudes_vehiculares
  for select to authenticated
  using (condominio_id = public.mi_condominio() and public.es_porteria());

create policy "residente solicita apertura" on public.solicitudes_vehiculares
  for insert to authenticated
  with check (
    residente_id = auth.uid()
    and condominio_id = public.mi_condominio()
    and estado = 'pendiente'
  );

create policy "porteria resuelve solicitudes" on public.solicitudes_vehiculares
  for update to authenticated
  using (condominio_id = public.mi_condominio() and public.es_porteria())
  with check (condominio_id = public.mi_condominio());


-- ------------------------------------------------------------------- PAQUETES
-- El residente ve solo los suyos. Solo la portería recibe y entrega.

create policy "residente ve sus paquetes" on public.paquetes
  for select to authenticated
  using (residente_id = auth.uid());

create policy "porteria ve paquetes del condominio" on public.paquetes
  for select to authenticated
  using (condominio_id = public.mi_condominio() and public.es_porteria());

create policy "porteria recibe paquetes" on public.paquetes
  for insert to authenticated
  with check (condominio_id = public.mi_condominio() and public.es_porteria());

create policy "porteria entrega paquetes" on public.paquetes
  for update to authenticated
  using (condominio_id = public.mi_condominio() and public.es_porteria())
  with check (condominio_id = public.mi_condominio());

create policy "administrador borra paquetes" on public.paquetes
  for delete to authenticated
  using (condominio_id = public.mi_condominio() and public.es_administrador());


-- ----------------------------------------------------------------- INCIDENTES
-- La portería los reporta. El residente ve solo los que involucran a su unidad.
-- El administrador ve todos y los cierra.

create policy "porteria ve incidentes del condominio" on public.incidentes
  for select to authenticated
  using (condominio_id = public.mi_condominio() and public.es_porteria());

create policy "residente ve incidentes de su unidad" on public.incidentes
  for select to authenticated
  using (residente_id = auth.uid());

create policy "porteria reporta incidentes" on public.incidentes
  for insert to authenticated
  with check (
    condominio_id = public.mi_condominio()
    and public.es_porteria()
    and reportado_por = auth.uid()
  );

create policy "quien reporto edita su incidente" on public.incidentes
  for update to authenticated
  using (reportado_por = auth.uid())
  with check (reportado_por = auth.uid());

create policy "administrador gestiona incidentes" on public.incidentes
  for all to authenticated
  using (condominio_id = public.mi_condominio() and public.es_administrador())
  with check (condominio_id = public.mi_condominio() and public.es_administrador());


-- ------------------------------------------------------------- NOTIFICACIONES
-- Cada uno ve solo las suyas y solo puede marcarlas como leídas.
-- Las notificaciones NO las crea la app: las crea el servidor (las funciones del
-- archivo de Firebase, que trabajan con una llave especial que se salta estas
-- reglas). Por eso no hay regla de INSERT acá: es a propósito.

create policy "ver mis notificaciones" on public.notificaciones
  for select to authenticated
  using (usuario_id = auth.uid());

create policy "marcar mis notificaciones como leidas" on public.notificaciones
  for update to authenticated
  using (usuario_id = auth.uid())
  with check (usuario_id = auth.uid());


-- ------------------------------------------------------------------ AUDITORÍA
-- Solo el administrador la lee. Cualquiera puede escribir en ella (el sistema
-- registra las acciones), pero nadie puede modificarla ni borrarla.

create policy "administrador lee la auditoria" on public.auditoria
  for select to authenticated
  using (condominio_id = public.mi_condominio() and public.es_administrador());

create policy "el sistema escribe en la auditoria" on public.auditoria
  for insert to authenticated
  with check (condominio_id = public.mi_condominio());


-- ============================================================================
-- PARTE F · PERMISOS BASE
-- ============================================================================
-- Los visitantes sin cuenta (rol "anon") no tienen acceso a NADA. Todo el
-- sistema exige haber iniciado sesión.
--
-- La línea de "from public" es la más importante y la más fácil de olvidar:
-- PostgreSQL, por defecto, le REGALA permiso de ejecutar cualquier función nueva
-- a todo el mundo, incluso a quien no inició sesión. Quitarlo es obligatorio.
-- (Esto lo detectó el chequeo de seguridad de Supabase en la primera prueba.)
-- ============================================================================

revoke all    on all tables    in schema public from anon;
revoke execute on all functions in schema public from public;
revoke execute on all functions in schema public from anon;

grant usage on schema public to authenticated;
grant select, insert, update, delete on all tables in schema public to authenticated;
grant usage, select on all sequences in schema public to authenticated;

-- Y las tablas de solo agregar quedan sin permiso de borrado ni edición ni
-- siquiera a nivel de permiso general, como segunda capa de protección.
revoke update, delete on public.movimientos_acceso from authenticated;
revoke update, delete on public.auditoria from authenticated;


-- ============================================================================
-- FIN DEL ARCHIVO 02
-- Siguiente paso: ejecutar 03-funciones-y-vistas.sql
-- ============================================================================
