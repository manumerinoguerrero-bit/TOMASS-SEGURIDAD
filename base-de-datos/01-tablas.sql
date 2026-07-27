-- ============================================================================
-- Tomass Seguridad — 01 · TABLAS
-- ============================================================================
-- Qué hace este archivo:
--   Crea todas las tablas del sistema. Es el esqueleto de la base de datos.
--
-- Cómo se usa:
--   Pegá TODO este archivo en el editor SQL de Supabase y presioná "Run".
--   Se ejecuta una sola vez, sobre una base de datos nueva y vacía.
--
-- Orden de los archivos (respetalo, cada uno necesita el anterior):
--   01-tablas.sql   ← estás acá
--   02-seguridad.sql
--   03-funciones-y-vistas.sql
--   04-datos-de-ejemplo.sql
--
-- Nota técnica para el desarrollador:
--   Los estados se guardan como TEXT con restricción CHECK en lugar de ENUM.
--   Motivo: agregar un valor nuevo (por ejemplo un tipo de incidente que no
--   habíamos previsto) es una sola línea de ALTER en vez de una migración
--   complicada. Es la opción más fácil de mantener a largo plazo.
-- ============================================================================

create extension if not exists pgcrypto with schema extensions;

-- ============================================================================
-- 1 · CONDOMINIOS
-- ============================================================================
-- Cada condominio es un cliente independiente. Toda la información del sistema
-- cuelga de acá, y las reglas de seguridad garantizan que un condominio NUNCA
-- pueda ver los datos de otro. Esto es lo que permite vender la app a varios
-- condominios sin rehacer nada.
-- ============================================================================

create table public.condominios (
  id               uuid primary key default gen_random_uuid(),
  nombre           text        not null,
  direccion        text,
  comuna           text,
  ciudad           text,
  telefono         text,
  email_contacto   text,
  zona_horaria     text        not null default 'America/Santiago',
  plan             text        not null default 'basico'
                   check (plan in ('basico','profesional','empresa')),
  -- Días que un paquete puede quedarse en portería antes de marcarse en rojo
  dias_alerta_paquete       smallint not null default 7 check (dias_alerta_paquete between 1 and 90),
  -- Segundos que vive un código QR de acceso antes de renovarse
  segundos_vida_qr          smallint not null default 60 check (segundos_vida_qr between 15 and 300),
  activo           boolean     not null default true,
  creado_en        timestamptz not null default now()
);

comment on table public.condominios is
  'Un registro por condominio cliente. Raíz de la separación de datos entre clientes.';

-- ============================================================================
-- 2 · UNIDADES (departamentos y casas)
-- ============================================================================

create table public.unidades (
  id             uuid primary key default gen_random_uuid(),
  condominio_id  uuid not null references public.condominios(id) on delete cascade,
  numero         text not null,
  torre          text,
  tipo           text not null default 'apartamento'
                 check (tipo in ('apartamento','casa')),
  metros_cuadrados numeric(7,2),
  estacionamientos smallint not null default 0 check (estacionamientos >= 0),
  notas          text,
  creado_en      timestamptz not null default now(),
  -- No puede haber dos "101 Torre A" en el mismo condominio
  unique (condominio_id, numero, torre)
);

create index ix_unidades_condominio on public.unidades (condominio_id);

-- ============================================================================
-- 3 · USUARIOS (administradores, guardias y residentes)
-- ============================================================================
-- IMPORTANTE — cambio respecto al plan original:
--   Acá NO se guarda la contraseña. Supabase tiene su propio sistema de login
--   (la tabla auth.users) que guarda las contraseñas encriptadas y maneja el
--   "olvidé mi contraseña", la verificación de email y la biometría.
--   Esta tabla guarda el resto de los datos de la persona y se conecta con el
--   login por el campo id.
--   Ventaja: menos código que escribir y menos riesgo de una filtración de
--   contraseñas, porque nosotros nunca las tocamos.
-- ============================================================================

create table public.usuarios (
  id              uuid primary key references auth.users(id) on delete cascade,
  condominio_id   uuid not null references public.condominios(id) on delete cascade,
  nombre_completo text not null,
  cedula          text,
  telefono        text,
  email           text not null,
  foto_url        text,
  -- Solo aplica a residentes; un guardia o administrador no tiene unidad
  unidad_id       uuid references public.unidades(id) on delete set null,
  relacion_unidad text check (relacion_unidad in ('propietario','arrendatario','familiar')),
  rol             text not null
                  check (rol in ('administrador','guardia','residente')),
  estado          text not null default 'activo'
                  check (estado in ('activo','inactivo','suspendido')),
  -- Cuando alguien se muda NO se borra: se pasa a inactivo y se anota por qué.
  -- Así el historial de sus entradas se conserva pero su código deja de servir.
  motivo_inactivo text,
  inactivo_desde  timestamptz,
  creado_en       timestamptz not null default now(),
  actualizado_en  timestamptz not null default now(),
  unique (condominio_id, cedula)
);

create index ix_usuarios_condominio on public.usuarios (condominio_id);
create index ix_usuarios_unidad     on public.usuarios (unidad_id);
create index ix_usuarios_rol        on public.usuarios (condominio_id, rol) where estado = 'activo';
create index ix_usuarios_busqueda   on public.usuarios using gin (to_tsvector('spanish', nombre_completo));

-- El propietario de una unidad se define acá, después de crear usuarios
alter table public.unidades
  add column propietario_id uuid references public.usuarios(id) on delete set null;

-- ============================================================================
-- 4 · PUNTOS DE ACCESO (las entradas del condominio)
-- ============================================================================
-- El "código QR estático" es el que se imprime y se pega en el muro. Lleva un
-- identificador secreto de 32 caracteres, así nadie puede fabricar un QR falso
-- de una entrada que no existe.
-- ============================================================================

create table public.puntos_acceso (
  id                   uuid primary key default gen_random_uuid(),
  condominio_id        uuid not null references public.condominios(id) on delete cascade,
  nombre               text not null,
  tipo                 text not null check (tipo in ('peatonal','vehicular')),
  ubicacion            text,
  -- Este es el valor que va impreso dentro del QR del muro
  codigo_qr_estatico   text not null unique
                       default encode(extensions.gen_random_bytes(16), 'hex'),
  -- Si es true, el guardia debe confirmar cada paso; si es false, entrada libre
  requiere_guardia     boolean not null default true,
  activo               boolean not null default true,
  creado_en            timestamptz not null default now(),
  unique (condominio_id, nombre)
);

create index ix_puntos_condominio on public.puntos_acceso (condominio_id);

-- ============================================================================
-- 5 · VEHÍCULOS
-- ============================================================================
-- El residente los registra desde su celular y quedan en 'pendiente'.
-- Solo los 'aprobado' sirven para entrar por la barrera.
-- ============================================================================

create table public.vehiculos (
  id                uuid primary key default gen_random_uuid(),
  condominio_id     uuid not null references public.condominios(id) on delete cascade,
  residente_id      uuid not null references public.usuarios(id) on delete cascade,
  patente           text not null,
  marca             text not null,
  modelo            text not null,
  color             text not null,
  anio              smallint check (anio between 1950 and 2100),
  foto_url          text,
  foto_patente_url  text,
  estado            text not null default 'pendiente'
                    check (estado in ('pendiente','aprobado','rechazado')),
  aprobado_por      uuid references public.usuarios(id) on delete set null,
  aprobado_en       timestamptz,
  motivo_rechazo    text,
  creado_en         timestamptz not null default now(),
  -- Una misma patente no puede estar registrada dos veces en el mismo condominio
  unique (condominio_id, patente)
);

create index ix_vehiculos_residente on public.vehiculos (residente_id);
create index ix_vehiculos_patente   on public.vehiculos (condominio_id, patente);
-- Índice para la pantalla "vehículos por aprobar" del administrador
create index ix_vehiculos_pendientes on public.vehiculos (condominio_id, creado_en)
  where estado = 'pendiente';

-- ============================================================================
-- 6 · TURNOS DE GUARDIA
-- ============================================================================
-- El guardia elige su puesto al empezar el turno. Esto es lo que hace que las
-- notificaciones de autos lleguen al guardia de la caseta vehicular y no al de
-- la garita peatonal.
-- ============================================================================

create table public.turnos (
  id                uuid primary key default gen_random_uuid(),
  condominio_id     uuid not null references public.condominios(id) on delete cascade,
  guardia_id        uuid not null references public.usuarios(id) on delete cascade,
  punto_acceso_id   uuid not null references public.puntos_acceso(id) on delete restrict,
  inicio            timestamptz not null default now(),
  fin_programado    timestamptz,
  cerrado_en        timestamptz,
  cerrado_por       uuid references public.usuarios(id) on delete set null,
  notas_entrega     text,
  creado_en         timestamptz not null default now()
);

create index ix_turnos_guardia on public.turnos (guardia_id, inicio desc);
-- Un guardia solo puede tener un turno abierto a la vez
create unique index ux_turnos_abierto on public.turnos (guardia_id)
  where cerrado_en is null;
-- Para saber rápido qué guardia está en cada puesto ahora mismo
create index ix_turnos_activos on public.turnos (punto_acceso_id)
  where cerrado_en is null;

-- ============================================================================
-- 7 · DISPOSITIVOS
-- ============================================================================
-- Cada celular o tablet que usa la app queda registrado acá.
--
-- POR QUÉ ES IMPORTANTE PARA TI: los guardias usan su celular personal. El día
-- que un guardia renuncia, entrás acá y revocás su dispositivo. Deja de recibir
-- notificaciones y la app se cierra sola en su teléfono, aunque él no la borre.
-- ============================================================================

create table public.dispositivos (
  id              uuid primary key default gen_random_uuid(),
  usuario_id      uuid not null references public.usuarios(id) on delete cascade,
  condominio_id   uuid not null references public.condominios(id) on delete cascade,
  -- Token que Firebase usa para mandarle notificaciones a este teléfono
  token_fcm       text,
  plataforma      text not null check (plataforma in ('android','ios')),
  modelo          text,
  version_app     text,
  -- Identificador del aparato, para reconocerlo si reinstala la app
  huella_dispositivo text not null,
  ultimo_uso      timestamptz not null default now(),
  activo          boolean not null default true,
  revocado_en     timestamptz,
  revocado_por    uuid references public.usuarios(id) on delete set null,
  motivo_revocacion text,
  creado_en       timestamptz not null default now(),
  unique (usuario_id, huella_dispositivo)
);

create index ix_dispositivos_usuario on public.dispositivos (usuario_id) where activo;
create index ix_dispositivos_token   on public.dispositivos (token_fcm) where activo;

-- ============================================================================
-- 8 · VISITAS
-- ============================================================================
-- Cubre los dos casos:
--   'preregistrada' → el residente la crea antes y manda el QR por WhatsApp.
--   'espontanea'    → llega alguien sin aviso, el guardia la registra en el
--                     momento y al residente le llega una notificación para
--                     aprobar o rechazar desde su celular. El guardia además
--                     puede dejar anotado que lo llamó por teléfono.
-- ============================================================================

create table public.visitas (
  id                  uuid primary key default gen_random_uuid(),
  condominio_id       uuid not null references public.condominios(id) on delete cascade,
  -- El residente que recibe la visita (y que la autoriza)
  residente_id        uuid not null references public.usuarios(id) on delete cascade,
  unidad_id           uuid references public.unidades(id) on delete set null,
  origen              text not null check (origen in ('preregistrada','espontanea')),

  nombre_visitante    text not null,
  cedula_visitante    text,
  telefono_visitante  text,
  foto_visitante_url  text,
  foto_cedula_url     text,
  patente_vehiculo    text,
  motivo_visita       text,

  -- Código de un solo uso. Se genera al crear la visita.
  token_qr            text not null unique
                      default encode(extensions.gen_random_bytes(24), 'hex'),
  valido_desde        timestamptz not null default now(),
  valido_hasta        timestamptz not null,

  estado              text not null default 'activa'
                      check (estado in ('activa','esperando_aprobacion','aprobada',
                                        'rechazada','usada','expirada','cancelada')),

  -- Quién la creó: el residente (preregistrada) o el guardia (espontánea)
  creada_por          uuid not null references public.usuarios(id) on delete restrict,
  turno_id            uuid references public.turnos(id) on delete set null,
  -- El guardia marca esto si además llamó por teléfono al residente
  autorizada_por_telefono boolean not null default false,
  nota_guardia        text,

  aprobada_en         timestamptz,
  rechazada_en        timestamptz,
  motivo_rechazo      text,
  usada_en            timestamptz,
  creado_en           timestamptz not null default now(),

  check (valido_hasta > valido_desde)
);

create index ix_visitas_residente on public.visitas (residente_id, creado_en desc);
create index ix_visitas_token     on public.visitas (token_qr);
-- Para la pantalla del residente "tenés una visita esperando tu aprobación"
create index ix_visitas_esperando on public.visitas (residente_id)
  where estado = 'esperando_aprobacion';
create index ix_visitas_vigentes  on public.visitas (condominio_id, valido_hasta)
  where estado in ('activa','aprobada');

-- ============================================================================
-- 9 · PERSONAL DE SERVICIO
-- ============================================================================
-- La asesora del hogar, el jardinero, el profesor de tenis. Entran varias veces
-- por semana y no son ni residentes ni visitas.
--
-- Tienen un código permanente que SOLO funciona en los días y el horario que
-- autorizó el residente. Si la nana trabaja lunes, miércoles y viernes de 8 a
-- 18, su código no abre nada un domingo a las 23:00.
--
-- No necesitan instalar la app: se les manda el código por WhatsApp o se les
-- imprime una credencial.
-- ============================================================================

create table public.personal_servicio (
  id                uuid primary key default gen_random_uuid(),
  condominio_id     uuid not null references public.condominios(id) on delete cascade,
  -- El residente que lo contrata y responde por él
  residente_id      uuid not null references public.usuarios(id) on delete cascade,
  unidad_id         uuid references public.unidades(id) on delete set null,

  nombre_completo   text not null,
  cedula            text not null,
  telefono          text,
  foto_url          text,
  patente_vehiculo  text,
  tipo              text not null default 'otro'
                    check (tipo in ('asesora_hogar','jardinero','profesor','cuidador',
                                    'mantencion','paseador_mascotas','otro')),
  descripcion_tipo  text,

  -- Días de la semana autorizados: 1 = lunes … 7 = domingo
  dias_autorizados  smallint[] not null,
  hora_desde        time not null default '07:00',
  hora_hasta        time not null default '20:00',

  token_qr          text not null unique
                    default encode(extensions.gen_random_bytes(24), 'hex'),
  valido_hasta      date,

  estado            text not null default 'pendiente'
                    check (estado in ('pendiente','activo','suspendido','finalizado')),
  aprobado_por      uuid references public.usuarios(id) on delete set null,
  aprobado_en       timestamptz,
  motivo_fin        text,
  creado_en         timestamptz not null default now(),

  check (hora_hasta > hora_desde),
  check (dias_autorizados <@ array[1,2,3,4,5,6,7]::smallint[]),
  check (array_length(dias_autorizados, 1) between 1 and 7),
  unique (condominio_id, cedula, residente_id)
);

create index ix_personal_residente on public.personal_servicio (residente_id);
create index ix_personal_token     on public.personal_servicio (token_qr);
create index ix_personal_activo    on public.personal_servicio (condominio_id)
  where estado = 'activo';

-- ============================================================================
-- 10 · MOVIMIENTOS DE ACCESO  ← el corazón del sistema
-- ============================================================================
-- Esta tabla es SOLO PARA AGREGAR: nadie, ni siquiera el administrador, puede
-- modificar ni borrar un registro. Es lo que la convierte en prueba válida si
-- hay un robo o un juicio. El bloqueo se aplica en el archivo 02.
--
-- Registra ENTRADAS Y SALIDAS. El campo 'sentido' es lo que permite saber en
-- cualquier momento quiénes están dentro del condominio — dato clave si hay un
-- incendio y los bomberos preguntan cuánta gente queda adentro.
--
-- MODO SIN INTERNET: si se cae la conexión, la app del guardia guarda los
-- movimientos en el teléfono y los manda después. Para eso existen dos campos:
--   ocurrido_en → la hora real en que pasó (la del reloj del teléfono)
--   creado_en   → la hora en que llegó al servidor
--   id_local    → identificador que genera el teléfono. Si por mala señal manda
--                 el mismo movimiento dos veces, la base lo ignora en lugar de
--                 duplicarlo.
-- ============================================================================

create table public.movimientos_acceso (
  id                 uuid primary key default gen_random_uuid(),
  condominio_id      uuid not null references public.condominios(id) on delete cascade,
  -- Generado por el teléfono. Evita duplicados al sincronizar sin internet.
  id_local           uuid not null unique,

  -- Quién se movió. Se llena UNO de estos tres, según persona_tipo.
  persona_tipo       text not null
                     check (persona_tipo in ('residente','visita','personal_servicio')),
  residente_id       uuid references public.usuarios(id) on delete set null,
  visita_id          uuid references public.visitas(id) on delete set null,
  personal_servicio_id uuid references public.personal_servicio(id) on delete set null,

  -- Copia del nombre y la unidad al momento del movimiento. Si después la
  -- persona se va del condominio, el registro histórico igual se lee completo.
  nombre_snapshot    text not null,
  unidad_snapshot    text,

  punto_acceso_id    uuid not null references public.puntos_acceso(id) on delete restrict,
  tipo_acceso        text not null check (tipo_acceso in ('peatonal','vehicular')),
  sentido            text not null check (sentido in ('entrada','salida')),

  vehiculo_id        uuid references public.vehiculos(id) on delete set null,
  patente_snapshot   text,

  estado             text not null check (estado in ('aprobado','denegado')),
  motivo_denegacion  text,

  -- Quién estaba de guardia y bajo qué turno
  guardia_id         uuid references public.usuarios(id) on delete set null,
  turno_id           uuid references public.turnos(id) on delete set null,
  dispositivo_id     uuid references public.dispositivos(id) on delete set null,

  ocurrido_en        timestamptz not null default now(),
  creado_en          timestamptz not null default now(),
  sincronizado_offline boolean not null default false,

  geo_lat            numeric(10,7),
  geo_lng            numeric(10,7),

  -- Coherencia: el tipo de persona debe coincidir con el campo que se llenó
  check (
    (persona_tipo = 'residente'          and residente_id is not null) or
    (persona_tipo = 'visita'             and visita_id is not null) or
    (persona_tipo = 'personal_servicio'  and personal_servicio_id is not null)
  ),
  -- Si es acceso vehicular aprobado de un residente, tiene que haber vehículo
  check (not (tipo_acceso = 'vehicular' and estado = 'aprobado'
              and persona_tipo = 'residente' and vehiculo_id is null)),
  -- Si fue denegado, tiene que decir por qué
  check (not (estado = 'denegado' and motivo_denegacion is null))
);

create index ix_mov_condominio  on public.movimientos_acceso (condominio_id, ocurrido_en desc);
create index ix_mov_residente   on public.movimientos_acceso (residente_id, ocurrido_en desc);
create index ix_mov_punto       on public.movimientos_acceso (punto_acceso_id, ocurrido_en desc);
create index ix_mov_turno       on public.movimientos_acceso (turno_id);
create index ix_mov_patente     on public.movimientos_acceso (condominio_id, patente_snapshot)
  where patente_snapshot is not null;
-- Índice para los informes por rango de fechas
create index ix_mov_informes    on public.movimientos_acceso
  (condominio_id, ocurrido_en, tipo_acceso, estado);

-- ============================================================================
-- 11 · SOLICITUDES VEHICULARES  ← la pantalla crítica del guardia
-- ============================================================================
-- Cuando un residente escanea el QR de la barrera, se crea un registro acá en
-- estado 'pendiente'. Eso es lo que aparece en la pantalla "Autos esperando la
-- barrera" del guardia y lo que dispara la notificación con sonido fuerte.
--
-- Cuando el guardia aprieta ABRIR ACCESO, esta solicitud pasa a 'aprobada' y se
-- crea el movimiento definitivo en movimientos_acceso.
-- ============================================================================

create table public.solicitudes_vehiculares (
  id                uuid primary key default gen_random_uuid(),
  condominio_id     uuid not null references public.condominios(id) on delete cascade,
  id_local          uuid not null unique,

  residente_id      uuid not null references public.usuarios(id) on delete cascade,
  vehiculo_id       uuid not null references public.vehiculos(id) on delete cascade,
  punto_acceso_id   uuid not null references public.puntos_acceso(id) on delete restrict,
  sentido           text not null default 'entrada'
                    check (sentido in ('entrada','salida')),

  estado            text not null default 'pendiente'
                    check (estado in ('pendiente','aprobada','denegada','expirada')),

  solicitado_en     timestamptz not null default now(),
  -- Si nadie la atiende en este plazo, se marca como expirada
  expira_en         timestamptz not null default (now() + interval '10 minutes'),
  resuelto_en       timestamptz,
  guardia_id        uuid references public.usuarios(id) on delete set null,
  turno_id          uuid references public.turnos(id) on delete set null,
  motivo            text,
  -- Movimiento definitivo que se creó al aprobar
  movimiento_id     uuid references public.movimientos_acceso(id) on delete set null,

  check (not (estado in ('aprobada','denegada') and resuelto_en is null))
);

-- Este índice es el que hace que la pantalla del guardia cargue al instante
create index ix_solicitudes_pendientes on public.solicitudes_vehiculares
  (punto_acceso_id, solicitado_en) where estado = 'pendiente';
create index ix_solicitudes_residente on public.solicitudes_vehiculares
  (residente_id, solicitado_en desc);

-- ============================================================================
-- 12 · PAQUETES
-- ============================================================================

create table public.paquetes (
  id                  uuid primary key default gen_random_uuid(),
  condominio_id       uuid not null references public.condominios(id) on delete cascade,
  id_local            uuid not null unique,

  numero_seguimiento  text,
  empresa_courier     text,
  descripcion         text,
  -- La foto del paquete es obligatoria: es el respaldo si llega dañado
  foto_url            text not null,

  residente_id        uuid not null references public.usuarios(id) on delete restrict,
  unidad_id           uuid references public.unidades(id) on delete set null,

  estado              text not null default 'en_porteria'
                      check (estado in ('en_porteria','entregado','devuelto')),

  recibido_en         timestamptz not null default now(),
  guardia_receptor_id uuid references public.usuarios(id) on delete set null,
  turno_recepcion_id  uuid references public.turnos(id) on delete set null,

  entregado_en        timestamptz,
  guardia_entrega_id  uuid references public.usuarios(id) on delete set null,
  turno_entrega_id    uuid references public.turnos(id) on delete set null,
  -- Firma del dedo del residente sobre la pantalla
  firma_url           text,
  foto_entrega_url    text,
  -- Si lo retira otra persona (el conserje, un familiar), se anota acá
  retirado_por        text,
  -- true si se validó al residente escaneando su código
  identidad_validada  boolean not null default false,

  motivo_devolucion   text,
  creado_en           timestamptz not null default now(),

  check (not (estado = 'entregado' and entregado_en is null))
);

create index ix_paquetes_residente on public.paquetes (residente_id, recibido_en desc);
-- Índice para el inventario de portería, ordenado por antigüedad
create index ix_paquetes_porteria  on public.paquetes (condominio_id, recibido_en)
  where estado = 'en_porteria';
create index ix_paquetes_seguimiento on public.paquetes (condominio_id, numero_seguimiento);

-- ============================================================================
-- 13 · INCIDENTES
-- ============================================================================
-- El cuaderno de novedades del guardia, pero digital y con fotos.
-- "Auto mal estacionado en el 302", "portón dañado", "ruido a las 2 AM".
--
-- Es lo más simple de todo el sistema y lo que más valor tiene cuando vendas la
-- app a otros condominios: es el registro que el administrador lleva a la
-- reunión de copropietarios.
-- ============================================================================

create table public.incidentes (
  id                uuid primary key default gen_random_uuid(),
  condominio_id     uuid not null references public.condominios(id) on delete cascade,
  id_local          uuid not null unique,

  tipo              text not null
                    check (tipo in ('estacionamiento','ruido','dano_propiedad',
                                    'persona_sospechosa','mascota','basura',
                                    'emergencia_medica','falla_tecnica','otro')),
  gravedad          text not null default 'baja'
                    check (gravedad in ('baja','media','alta','critica')),
  titulo            text not null,
  descripcion       text,
  -- Lista de URLs de fotos: ["https://…/1.jpg", "https://…/2.jpg"]
  fotos             jsonb not null default '[]'::jsonb,

  -- Con qué o con quién se relaciona (todos opcionales)
  unidad_id         uuid references public.unidades(id) on delete set null,
  residente_id      uuid references public.usuarios(id) on delete set null,
  patente           text,
  punto_acceso_id   uuid references public.puntos_acceso(id) on delete set null,
  ubicacion_texto   text,

  reportado_por     uuid not null references public.usuarios(id) on delete restrict,
  turno_id          uuid references public.turnos(id) on delete set null,
  ocurrido_en       timestamptz not null default now(),
  creado_en         timestamptz not null default now(),
  sincronizado_offline boolean not null default false,

  estado            text not null default 'abierto'
                    check (estado in ('abierto','en_proceso','cerrado')),
  resuelto_por      uuid references public.usuarios(id) on delete set null,
  resuelto_en       timestamptz,
  nota_resolucion   text,

  check (jsonb_typeof(fotos) = 'array'),
  check (not (estado = 'cerrado' and resuelto_en is null))
);

create index ix_incidentes_condominio on public.incidentes (condominio_id, ocurrido_en desc);
create index ix_incidentes_abiertos   on public.incidentes (condominio_id, gravedad, ocurrido_en)
  where estado <> 'cerrado';
create index ix_incidentes_unidad     on public.incidentes (unidad_id);

-- ============================================================================
-- 14 · NOTIFICACIONES
-- ============================================================================
-- Copia de todo lo que se le mandó a cada persona. Sirve para la campanita
-- dentro de la app y para saber si una notificación llegó o falló.
-- ============================================================================

create table public.notificaciones (
  id             uuid primary key default gen_random_uuid(),
  condominio_id  uuid not null references public.condominios(id) on delete cascade,
  usuario_id     uuid not null references public.usuarios(id) on delete cascade,

  tipo           text not null
                 check (tipo in ('acceso_peatonal','acceso_vehicular_pendiente',
                                 'paquete_recibido','paquete_entregado',
                                 'vehiculo_aprobado','vehiculo_rechazado',
                                 'visita_esperando_aprobacion','visita_ingreso',
                                 'personal_servicio_ingreso','incidente_unidad',
                                 'paquete_sin_retirar','sistema')),
  titulo         text not null,
  mensaje        text not null,
  -- Información extra para que la app sepa a qué pantalla ir al tocarla
  datos          jsonb not null default '{}'::jsonb,
  -- Las urgentes suenan fuerte aunque el teléfono esté en silencio
  urgente        boolean not null default false,

  canal          text not null default 'push'
                 check (canal in ('push','en_app','sms','whatsapp')),
  enviada_en     timestamptz,
  error_envio    text,
  leida          boolean not null default false,
  leida_en       timestamptz,
  creado_en      timestamptz not null default now()
);

create index ix_notif_usuario   on public.notificaciones (usuario_id, creado_en desc);
create index ix_notif_no_leidas on public.notificaciones (usuario_id) where not leida;

-- ============================================================================
-- 15 · BITÁCORA DE AUDITORÍA
-- ============================================================================
-- Registra los cambios importantes: quién aprobó un vehículo, quién desactivó a
-- un residente, quién revocó el celular de un guardia. Si algo raro pasa, acá
-- está el rastro.
-- ============================================================================

create table public.auditoria (
  id            bigint generated always as identity primary key,
  condominio_id uuid references public.condominios(id) on delete cascade,
  usuario_id    uuid references public.usuarios(id) on delete set null,
  accion        text not null,
  tabla         text not null,
  registro_id   text,
  datos_antes   jsonb,
  datos_despues jsonb,
  ip            inet,
  creado_en     timestamptz not null default now()
);

create index ix_auditoria_condominio on public.auditoria (condominio_id, creado_en desc);
create index ix_auditoria_registro   on public.auditoria (tabla, registro_id);

-- ============================================================================
-- FIN DEL ARCHIVO 01
-- Siguiente paso: ejecutar 02-seguridad.sql
-- ============================================================================
