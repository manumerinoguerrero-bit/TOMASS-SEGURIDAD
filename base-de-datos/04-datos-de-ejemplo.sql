-- ============================================================================
-- Tomass Seguridad — 04 · DATOS DE EJEMPLO
-- ============================================================================
-- Qué hace este archivo:
--   Llena la base de datos con un condominio inventado para que puedas probar la
--   app de inmediato, sin tener que cargar 150 unidades a mano.
--
--   Crea: 1 condominio, 6 unidades, 7 personas (1 administrador, 2 guardias,
--   4 residentes), 4 vehículos, 2 entradas, 3 paquetes, 8 movimientos con
--   entradas Y salidas, 1 auto esperando la barrera, 2 visitas, 2 personas de
--   servicio y 2 incidentes.
--
-- ⚠️  ESTO ES SOLO PARA PRUEBAS.
--     Todas las cuentas usan la misma contraseña: Demo1234!
--     NO ejecutes este archivo en la base de datos real del condominio.
--
-- Cómo se usa:
--   Pegá TODO este archivo en el editor SQL de Supabase y presioná "Run".
--   Ejecutar DESPUÉS de 03-funciones-y-vistas.sql.
--
-- Para entrar a probar la app:
--   Administrador  admin@losaromos.cl      Demo1234!
--   Guardia        carlos@losaromos.cl     Demo1234!   (caseta vehicular)
--   Guardia        luis@losaromos.cl       Demo1234!   (garita peatonal)
--   Residente      juan@gmail.com          Demo1234!   (unidad 101, 1 auto ok)
--   Residente      ana@gmail.com           Demo1234!   (unidad 102)
--
-- Nota sobre los identificadores: son códigos de 32 caracteres que solo pueden
-- usar números y las letras A a la F. Por eso se ven raros. Los fijamos a mano
-- solo en este archivo de pruebas; en la app real se generan solos.
--   cc… = condominio    dd… = unidades      ee… = puntos de acceso
--   bb… = vehículos     77… = turnos        55… = solicitudes
-- ============================================================================


-- ============================================================================
-- PASO 1 · CUENTAS DE LOGIN
-- ============================================================================
-- Las contraseñas las guarda Supabase en su propia tabla, encriptadas.
-- Este bloque crea las cuentas de acceso; los datos de cada persona se cargan
-- en el paso 3.
-- ============================================================================

do $$
declare
  r        record;
  v_clave  text := extensions.crypt('Demo1234!', extensions.gen_salt('bf'));
begin
  for r in
    select * from (values
      ('11111111-1111-1111-1111-111111111111'::uuid, 'admin@losaromos.cl'),
      ('22222222-2222-2222-2222-222222222222'::uuid, 'carlos@losaromos.cl'),
      ('33333333-3333-3333-3333-333333333333'::uuid, 'luis@losaromos.cl'),
      ('44444444-4444-4444-4444-444444444444'::uuid, 'juan@gmail.com'),
      ('55555555-5555-5555-5555-555555555555'::uuid, 'ana@gmail.com'),
      ('66666666-6666-6666-6666-666666666666'::uuid, 'pedro@gmail.com'),
      ('77777777-7777-7777-7777-777777777777'::uuid, 'sofia@gmail.com')
    ) as t(id, email)
  loop
    insert into auth.users (
      instance_id, id, aud, role, email, encrypted_password,
      email_confirmed_at, created_at, updated_at,
      raw_app_meta_data, raw_user_meta_data,
      -- ⚠️ ESTAS OCHO COLUMNAS SON OBLIGATORIAS Y VAN EN BLANCO, NO EN NULO.
      --
      -- Si se las deja sin poner, quedan en "nulo" y el sistema de login de
      -- Supabase se cae con el error "Database error querying schema" al intentar
      -- entrar. Es un detalle conocido y muy difícil de adivinar: el error no
      -- menciona en ningún momento a estas columnas.
      --
      -- (Me pasó al probar la Fase 2 y perdí un rato averiguándolo. Queda anotado
      -- acá para que no le pase a nadie más.)
      confirmation_token, recovery_token, email_change,
      email_change_token_new, email_change_token_current,
      phone_change, phone_change_token, reauthentication_token
    ) values (
      '00000000-0000-0000-0000-000000000000',
      r.id, 'authenticated', 'authenticated', r.email, v_clave,
      now(), now(), now(),
      '{"provider":"email","providers":["email"]}'::jsonb,
      '{}'::jsonb,
      '', '', '', '', '', '', '', ''
    )
    on conflict (id) do nothing;

    insert into auth.identities (
      id, user_id, provider_id, identity_data, provider,
      last_sign_in_at, created_at, updated_at
    ) values (
      gen_random_uuid(), r.id, r.id::text,
      jsonb_build_object('sub', r.id::text, 'email', r.email,
                         'email_verified', true, 'phone_verified', false),
      'email', now(), now(), now()
    )
    on conflict do nothing;
  end loop;
end $$;


-- ============================================================================
-- PASO 2 · EL CONDOMINIO Y SUS UNIDADES
-- ============================================================================

insert into public.condominios (
  id, nombre, direccion, comuna, ciudad, telefono, email_contacto,
  plan, dias_alerta_paquete, segundos_vida_qr
) values (
  'cc000000-0000-0000-0000-000000000001',
  'Condominio Los Aromos',
  'Av. Los Aromos 1450', 'Las Condes', 'Santiago',
  '+56 2 2345 6789', 'administracion@losaromos.cl',
  'profesional', 7, 60
);

insert into public.unidades (id, condominio_id, numero, torre, tipo, estacionamientos) values
  ('dd000000-0000-0000-0000-000000000101', 'cc000000-0000-0000-0000-000000000001', '101', 'A', 'apartamento', 1),
  ('dd000000-0000-0000-0000-000000000102', 'cc000000-0000-0000-0000-000000000001', '102', 'A', 'apartamento', 1),
  ('dd000000-0000-0000-0000-000000000204', 'cc000000-0000-0000-0000-000000000001', '204', 'B', 'apartamento', 1),
  ('dd000000-0000-0000-0000-000000000301', 'cc000000-0000-0000-0000-000000000001', '301', 'B', 'apartamento', 2),
  ('dd000000-0000-0000-0000-000000000302', 'cc000000-0000-0000-0000-000000000001', '302', 'B', 'apartamento', 1),
  ('dd000000-0000-0000-0000-000000000401', 'cc000000-0000-0000-0000-000000000001', '401', 'C', 'casa', 2);


-- ============================================================================
-- PASO 3 · LAS PERSONAS
-- ============================================================================

insert into public.usuarios (
  id, condominio_id, nombre_completo, cedula, telefono, email,
  unidad_id, relacion_unidad, rol, estado, motivo_inactivo, inactivo_desde
) values
  -- Administrador
  ('11111111-1111-1111-1111-111111111111', 'cc000000-0000-0000-0000-000000000001',
   'Manuel Merino Gálvez', '10.111.222-3', '+56 9 9111 2223', 'admin@losaromos.cl',
   null, null, 'administrador', 'activo', null, null),

  -- Guardias
  ('22222222-2222-2222-2222-222222222222', 'cc000000-0000-0000-0000-000000000001',
   'Carlos Soto Núñez', '14.555.666-7', '+56 9 9222 3334', 'carlos@losaromos.cl',
   null, null, 'guardia', 'activo', null, null),
  ('33333333-3333-3333-3333-333333333333', 'cc000000-0000-0000-0000-000000000001',
   'Luis Fuentes Rojas', '16.777.888-9', '+56 9 9333 4445', 'luis@losaromos.cl',
   null, null, 'guardia', 'activo', null, null),

  -- Residentes
  ('44444444-4444-4444-4444-444444444444', 'cc000000-0000-0000-0000-000000000001',
   'Juan Pérez Soto', '12.345.678-9', '+56 9 8765 4321', 'juan@gmail.com',
   'dd000000-0000-0000-0000-000000000101', 'propietario', 'residente', 'activo', null, null),
  ('55555555-5555-5555-5555-555555555555', 'cc000000-0000-0000-0000-000000000001',
   'Ana Rojas Vera', '9.876.543-2', '+56 9 1234 5678', 'ana@gmail.com',
   'dd000000-0000-0000-0000-000000000102', 'propietario', 'residente', 'activo', null, null),
  ('66666666-6666-6666-6666-666666666666', 'cc000000-0000-0000-0000-000000000001',
   'Pedro Lagos Díaz', '15.222.333-4', '+56 9 5555 1111', 'pedro@gmail.com',
   'dd000000-0000-0000-0000-000000000204', 'arrendatario', 'residente', 'activo', null, null),

  -- Residente que se mudó: queda INACTIVO, no se borra, para conservar su historial
  ('77777777-7777-7777-7777-777777777777', 'cc000000-0000-0000-0000-000000000001',
   'Sofía Muñoz Lara', '18.444.555-6', '+56 9 7777 2222', 'sofia@gmail.com',
   'dd000000-0000-0000-0000-000000000301', 'arrendatario', 'residente', 'inactivo',
   'Se mudó del condominio', now() - interval '26 days');

-- Ahora sí se pueden asignar los propietarios de cada unidad
update public.unidades set propietario_id = '44444444-4444-4444-4444-444444444444'
  where id = 'dd000000-0000-0000-0000-000000000101';
update public.unidades set propietario_id = '55555555-5555-5555-5555-555555555555'
  where id = 'dd000000-0000-0000-0000-000000000102';
update public.unidades set propietario_id = '66666666-6666-6666-6666-666666666666'
  where id = 'dd000000-0000-0000-0000-000000000204';


-- ============================================================================
-- PASO 4 · LAS ENTRADAS DEL CONDOMINIO
-- ============================================================================
-- El campo codigo_qr_estatico es el valor que va impreso dentro del QR pegado
-- en el muro. En producción se genera solo y es secreto; acá los fijamos para
-- poder hacer pruebas.
-- ============================================================================

insert into public.puntos_acceso (
  id, condominio_id, nombre, tipo, ubicacion, codigo_qr_estatico, requiere_guardia
) values
  ('ee000000-0000-0000-0000-000000000001', 'cc000000-0000-0000-0000-000000000001',
   'Entrada Peatonal', 'peatonal',
   'Portón chico, calle Los Aromos', 'demo_peatonal_no_usar_en_produccion', true),
  ('ee000000-0000-0000-0000-000000000002', 'cc000000-0000-0000-0000-000000000001',
   'Entrada Vehicular', 'vehicular',
   'Barrera del estacionamiento, junto a la caseta', 'demo_vehicular_no_usar_en_produccion', true);


-- ============================================================================
-- PASO 5 · TURNOS ABIERTOS
-- ============================================================================
-- Carlos está en la caseta vehicular, Luis en la garita peatonal. Con esto ya se
-- puede probar que las notificaciones de autos le lleguen a Carlos y no a Luis.
-- ============================================================================

insert into public.turnos (
  id, condominio_id, guardia_id, punto_acceso_id, inicio, fin_programado
) values
  ('77000000-0000-0000-0000-000000000001', 'cc000000-0000-0000-0000-000000000001',
   '22222222-2222-2222-2222-222222222222', 'ee000000-0000-0000-0000-000000000002',
   now() - interval '3 hours', now() + interval '9 hours'),
  ('77000000-0000-0000-0000-000000000002', 'cc000000-0000-0000-0000-000000000001',
   '33333333-3333-3333-3333-333333333333', 'ee000000-0000-0000-0000-000000000001',
   now() - interval '3 hours', now() + interval '9 hours');


-- ============================================================================
-- PASO 6 · VEHÍCULOS
-- ============================================================================

-- ⚠️ LAS PATENTES DE ESTE ARCHIVO SIGUEN EL FORMATO CHILENO REAL.
--
--    Desde 2007 son 4 CONSONANTES y 2 NÚMEROS (BCDF-12). Las viejas son 2
--    letras y 4 números (AB-1234), y las motos 3 letras y 2 números.
--
--    NO se usan vocales: no existe ninguna patente nueva con A, E, I, O ni U.
--
--    Antes acá había "ABC-123", que es 3 letras y 3 números: un formato que no
--    existe en Chile. Quedaba mal al mostrarle el sistema a un cliente, y peor:
--    hacía creer que el validador de la app estaba roto cuando en realidad
--    estaba bien y los datos de prueba estaban mal.

insert into public.vehiculos (
  id, condominio_id, residente_id, patente, marca, modelo, color, anio,
  estado, aprobado_por, aprobado_en, creado_en
) values
  -- Aprobado: este SÍ puede usar la barrera
  ('bb000000-0000-0000-0000-000000000001', 'cc000000-0000-0000-0000-000000000001',
   '44444444-4444-4444-4444-444444444444', 'BCDF-12', 'Toyota', 'Corolla', 'Blanco', 2021,
   'aprobado', '11111111-1111-1111-1111-111111111111',
   now() - interval '40 days', now() - interval '41 days'),

  -- Pendiente: el residente lo registró pero el administrador no lo ha revisado
  ('bb000000-0000-0000-0000-000000000002', 'cc000000-0000-0000-0000-000000000001',
   '44444444-4444-4444-4444-444444444444', 'TVWX-78', 'Nissan', 'Versa', 'Gris', 2019,
   'pendiente', null, null, now() - interval '2 days'),

  ('bb000000-0000-0000-0000-000000000003', 'cc000000-0000-0000-0000-000000000001',
   '55555555-5555-5555-5555-555555555555', 'GHJK-34', 'Kia', 'Rio', 'Rojo', 2022,
   'aprobado', '11111111-1111-1111-1111-111111111111',
   now() - interval '30 days', now() - interval '31 days'),

  ('bb000000-0000-0000-0000-000000000004', 'cc000000-0000-0000-0000-000000000001',
   '66666666-6666-6666-6666-666666666666', 'LPRS-65', 'Suzuki', 'Swift', 'Azul', 2020,
   'pendiente', null, null, now() - interval '4 hours');


-- ============================================================================
-- PASO 7 · MOVIMIENTOS DE ACCESO (entradas Y salidas)
-- ============================================================================
-- Después de cargar esto, consultá la vista v_personas_dentro: Juan y Pedro
-- quedan adentro (entraron y no salieron), Ana ya salió.
-- ============================================================================

insert into public.movimientos_acceso (
  condominio_id, id_local, persona_tipo, residente_id,
  nombre_snapshot, unidad_snapshot, punto_acceso_id, tipo_acceso, sentido,
  vehiculo_id, patente_snapshot, estado, motivo_denegacion,
  guardia_id, turno_id, ocurrido_en
) values
  -- Juan sale en auto por la mañana
  ('cc000000-0000-0000-0000-000000000001', gen_random_uuid(), 'residente',
   '44444444-4444-4444-4444-444444444444', 'Juan Pérez Soto', '101 A',
   'ee000000-0000-0000-0000-000000000002', 'vehicular', 'salida',
   'bb000000-0000-0000-0000-000000000001', 'BCDF-12', 'aprobado', null,
   '22222222-2222-2222-2222-222222222222', '77000000-0000-0000-0000-000000000001',
   now() - interval '11 hours'),

  -- Y vuelve en la tarde: ahora está ADENTRO
  ('cc000000-0000-0000-0000-000000000001', gen_random_uuid(), 'residente',
   '44444444-4444-4444-4444-444444444444', 'Juan Pérez Soto', '101 A',
   'ee000000-0000-0000-0000-000000000002', 'vehicular', 'entrada',
   'bb000000-0000-0000-0000-000000000001', 'BCDF-12', 'aprobado', null,
   '22222222-2222-2222-2222-222222222222', '77000000-0000-0000-0000-000000000001',
   now() - interval '2 hours'),

  -- Ana entró caminando y después salió: está AFUERA
  ('cc000000-0000-0000-0000-000000000001', gen_random_uuid(), 'residente',
   '55555555-5555-5555-5555-555555555555', 'Ana Rojas Vera', '102 A',
   'ee000000-0000-0000-0000-000000000001', 'peatonal', 'entrada',
   null, null, 'aprobado', null,
   '33333333-3333-3333-3333-333333333333', '77000000-0000-0000-0000-000000000002',
   now() - interval '5 hours'),
  ('cc000000-0000-0000-0000-000000000001', gen_random_uuid(), 'residente',
   '55555555-5555-5555-5555-555555555555', 'Ana Rojas Vera', '102 A',
   'ee000000-0000-0000-0000-000000000001', 'peatonal', 'salida',
   null, null, 'aprobado', null,
   '33333333-3333-3333-3333-333333333333', '77000000-0000-0000-0000-000000000002',
   now() - interval '1 hour'),

  -- Pedro intentó entrar en auto: DENEGADO, su vehículo aún no está aprobado
  ('cc000000-0000-0000-0000-000000000001', gen_random_uuid(), 'residente',
   '66666666-6666-6666-6666-666666666666', 'Pedro Lagos Díaz', '204 B',
   'ee000000-0000-0000-0000-000000000002', 'vehicular', 'entrada',
   null, 'LPRS-65', 'denegado',
   'El vehículo LPRS-65 está pendiente de aprobación de la administración.',
   '22222222-2222-2222-2222-222222222222', '77000000-0000-0000-0000-000000000001',
   now() - interval '3 hours'),

  -- Y entonces entró caminando
  ('cc000000-0000-0000-0000-000000000001', gen_random_uuid(), 'residente',
   '66666666-6666-6666-6666-666666666666', 'Pedro Lagos Díaz', '204 B',
   'ee000000-0000-0000-0000-000000000001', 'peatonal', 'entrada',
   null, null, 'aprobado', null,
   '33333333-3333-3333-3333-333333333333', '77000000-0000-0000-0000-000000000002',
   now() - interval '2 hours' - interval '50 minutes');

-- Un movimiento registrado SIN INTERNET y sincronizado después.
--
-- Fijate en la diferencia entre ocurrido_en (cuando pasó de verdad, hace 30 horas)
-- y creado_en (cuando llegó al servidor, que es ahora): así se ve el modo sin
-- conexión funcionando.
--
-- OJO: el campo sincronizado_offline va acá, dentro del insert. NO se puede
-- poner con un update después, porque esta tabla es de solo agregar y el
-- candado del archivo 02 lo bloquea. Es a propósito.
insert into public.movimientos_acceso (
  condominio_id, id_local, persona_tipo, residente_id,
  nombre_snapshot, unidad_snapshot, punto_acceso_id, tipo_acceso, sentido,
  estado, guardia_id, turno_id, ocurrido_en, sincronizado_offline
) values (
  'cc000000-0000-0000-0000-000000000001', gen_random_uuid(), 'residente',
  '44444444-4444-4444-4444-444444444444', 'Juan Pérez Soto', '101 A',
  'ee000000-0000-0000-0000-000000000001', 'peatonal', 'salida',
  'aprobado', '33333333-3333-3333-3333-333333333333',
  '77000000-0000-0000-0000-000000000002',
  now() - interval '30 hours', true
);


-- ============================================================================
-- PASO 8 · UN AUTO ESPERANDO LA BARRERA AHORA MISMO
-- ============================================================================
-- Al abrir la app como Carlos (el guardia vehicular), esta solicitud tiene que
-- aparecer en la pantalla "Autos esperando la barrera".
-- ============================================================================

insert into public.solicitudes_vehiculares (
  id, condominio_id, id_local, residente_id, vehiculo_id, punto_acceso_id,
  sentido, estado, solicitado_en, expira_en
) values
  ('55000000-0000-0000-0000-000000000001', 'cc000000-0000-0000-0000-000000000001',
   gen_random_uuid(), '55555555-5555-5555-5555-555555555555',
   'bb000000-0000-0000-0000-000000000003', 'ee000000-0000-0000-0000-000000000002',
   'entrada', 'pendiente', now() - interval '25 seconds', now() + interval '10 minutes');

-- Y una que Carlos ya resolvió hace rato
insert into public.solicitudes_vehiculares (
  condominio_id, id_local, residente_id, vehiculo_id, punto_acceso_id,
  sentido, estado, solicitado_en, expira_en, resuelto_en, guardia_id, turno_id
) values
  ('cc000000-0000-0000-0000-000000000001', gen_random_uuid(),
   '44444444-4444-4444-4444-444444444444',
   'bb000000-0000-0000-0000-000000000001', 'ee000000-0000-0000-0000-000000000002',
   'entrada', 'aprobada', now() - interval '2 hours' - interval '20 seconds',
   now() - interval '1 hour' - interval '50 minutes',
   now() - interval '2 hours', '22222222-2222-2222-2222-222222222222',
   '77000000-0000-0000-0000-000000000001');


-- ============================================================================
-- PASO 9 · PAQUETES
-- ============================================================================

insert into public.paquetes (
  condominio_id, id_local, numero_seguimiento, empresa_courier, descripcion,
  foto_url, residente_id, unidad_id, estado,
  recibido_en, guardia_receptor_id, turno_recepcion_id,
  entregado_en, guardia_entrega_id, firma_url, identidad_validada
) values
  -- En portería hace 9 días: se pinta ROJO porque pasó el límite de 7
  ('cc000000-0000-0000-0000-000000000001', gen_random_uuid(),
   '112233445', 'Starken', 'Caja grande, aprox. 40x30x25 cm',
   'https://ejemplo.local/paquetes/112233445.jpg',
   '44444444-4444-4444-4444-444444444444', 'dd000000-0000-0000-0000-000000000101',
   'en_porteria', now() - interval '9 days',
   '22222222-2222-2222-2222-222222222222', null, null, null, null, false),

  -- En portería hace 1 día
  ('cc000000-0000-0000-0000-000000000001', gen_random_uuid(),
   '998877665', 'Chilexpress', 'Sobre mediano',
   'https://ejemplo.local/paquetes/998877665.jpg',
   '44444444-4444-4444-4444-444444444444', 'dd000000-0000-0000-0000-000000000101',
   'en_porteria', now() - interval '1 day',
   '22222222-2222-2222-2222-222222222222', null, null, null, null, false),

  -- Ya entregado, con firma del residente
  ('cc000000-0000-0000-0000-000000000001', gen_random_uuid(),
   '334455667', 'Blue Express', 'Caja chica',
   'https://ejemplo.local/paquetes/334455667.jpg',
   '55555555-5555-5555-5555-555555555555', 'dd000000-0000-0000-0000-000000000102',
   'entregado', now() - interval '5 days',
   '22222222-2222-2222-2222-222222222222', null,
   now() - interval '3 days', '33333333-3333-3333-3333-333333333333',
   'https://ejemplo.local/firmas/334455667.png', true);


-- ============================================================================
-- PASO 10 · VISITAS
-- ============================================================================

-- Caso A: pre-registrada por Ana, ya usó su código y está adentro
insert into public.visitas (
  id, condominio_id, residente_id, unidad_id, origen,
  nombre_visitante, cedula_visitante, telefono_visitante, patente_vehiculo,
  motivo_visita, valido_desde, valido_hasta, estado, creada_por, usada_en
) values (
  '99000000-0000-0000-0000-000000000001', 'cc000000-0000-0000-0000-000000000001',
  '55555555-5555-5555-5555-555555555555', 'dd000000-0000-0000-0000-000000000102',
  'preregistrada', 'María González Pinto', '12.345.678-9', '+56 9 4444 5555', 'DEF-456',
  'Almuerzo familiar', now() - interval '6 hours', now() + interval '6 hours',
  'usada', '55555555-5555-5555-5555-555555555555', now() - interval '4 hours'
);

-- María entró y no ha salido: tiene que aparecer en v_personas_dentro
insert into public.movimientos_acceso (
  condominio_id, id_local, persona_tipo, visita_id,
  nombre_snapshot, unidad_snapshot, punto_acceso_id, tipo_acceso, sentido,
  patente_snapshot, estado, guardia_id, turno_id, ocurrido_en
) values (
  'cc000000-0000-0000-0000-000000000001', gen_random_uuid(), 'visita',
  '99000000-0000-0000-0000-000000000001',
  'María González Pinto', '102 A', 'ee000000-0000-0000-0000-000000000001',
  'peatonal', 'entrada', 'DEF-456', 'aprobado',
  '33333333-3333-3333-3333-333333333333', '77000000-0000-0000-0000-000000000002',
  now() - interval '4 hours'
);

-- Caso B: llegó alguien SIN AVISO. El guardia Luis lo registró y Juan tiene una
-- notificación esperando en su celular para aprobar o rechazar.
insert into public.visitas (
  condominio_id, residente_id, unidad_id, origen,
  nombre_visitante, cedula_visitante, telefono_visitante,
  motivo_visita, valido_desde, valido_hasta, estado,
  creada_por, turno_id, autorizada_por_telefono, nota_guardia
) values (
  'cc000000-0000-0000-0000-000000000001',
  '44444444-4444-4444-4444-444444444444', 'dd000000-0000-0000-0000-000000000101',
  'espontanea', 'Roberto Silva Muñoz', '13.987.654-3', '+56 9 6666 7777',
  'Dice ser el técnico del calefont', now(), now() + interval '3 hours',
  'esperando_aprobacion', '33333333-3333-3333-3333-333333333333',
  '77000000-0000-0000-0000-000000000002',
  true, 'Llamé al 101 por teléfono, no contestaron. Espera en la garita.'
);


-- ============================================================================
-- PASO 11 · PERSONAL DE SERVICIO
-- ============================================================================
-- Días: 1 = lunes, 2 = martes, 3 = miércoles, 4 = jueves, 5 = viernes,
--       6 = sábado, 7 = domingo
-- ============================================================================

insert into public.personal_servicio (
  condominio_id, residente_id, unidad_id, nombre_completo, cedula, telefono,
  tipo, dias_autorizados, hora_desde, hora_hasta, estado,
  aprobado_por, aprobado_en, valido_hasta
) values
  -- Activa: lunes, miércoles y viernes de 08:00 a 18:00
  ('cc000000-0000-0000-0000-000000000001',
   '44444444-4444-4444-4444-444444444444', 'dd000000-0000-0000-0000-000000000101',
   'Rosa Contreras Vidal', '11.222.333-4', '+56 9 3333 4444',
   'asesora_hogar', array[1,3,5]::smallint[], '08:00', '18:00', 'activo',
   '11111111-1111-1111-1111-111111111111', now() - interval '60 days',
   (now() + interval '1 year')::date),

  -- Pendiente de aprobación: sábados de 09:00 a 14:00
  ('cc000000-0000-0000-0000-000000000001',
   '55555555-5555-5555-5555-555555555555', 'dd000000-0000-0000-0000-000000000102',
   'Miguel Ávila Torres', '17.888.999-0', '+56 9 2222 3333',
   'jardinero', array[6]::smallint[], '09:00', '14:00', 'pendiente',
   null, null, null);


-- ============================================================================
-- PASO 12 · INCIDENTES
-- ============================================================================

insert into public.incidentes (
  condominio_id, id_local, tipo, gravedad, titulo, descripcion,
  unidad_id, patente, reportado_por, turno_id, ocurrido_en, estado,
  resuelto_por, resuelto_en, nota_resolucion
) values
  -- Abierto
  ('cc000000-0000-0000-0000-000000000001', gen_random_uuid(),
   'estacionamiento', 'media',
   'Auto ajeno en estacionamiento del 302',
   'Camioneta gris sin patente visible ocupando el estacionamiento asignado a la unidad 302. El residente reclamó a las 21:40.',
   'dd000000-0000-0000-0000-000000000302', null,
   '22222222-2222-2222-2222-222222222222', '77000000-0000-0000-0000-000000000001',
   now() - interval '2 hours', 'abierto', null, null, null),

  -- Ya cerrado por el administrador
  ('cc000000-0000-0000-0000-000000000001', gen_random_uuid(),
   'dano_propiedad', 'alta',
   'Barrera vehicular golpeada',
   'Un vehículo que salía golpeó el brazo de la barrera. El brazo quedó torcido pero sigue funcionando.',
   null, 'LPRS-65',
   '22222222-2222-2222-2222-222222222222', '77000000-0000-0000-0000-000000000001',
   now() - interval '8 days', 'cerrado',
   '11111111-1111-1111-1111-111111111111', now() - interval '5 days',
   'Se cambió el brazo. El costo se cargó a la unidad 204.');


-- ============================================================================
-- PASO 13 · REVISIÓN FINAL
-- ============================================================================
-- Estas consultas comprueban que todo quedó bien cargado. Ejecutalas y comparalas
-- con lo que dice el comentario de cada una. Si los números coinciden, la base de
-- datos está funcionando perfecto.
-- ============================================================================

-- Esperado: autos_esperando = 1 · paquetes_en_porteria = 2 · paquetes_atrasados = 1
--           vehiculos_por_aprobar = 2 · residentes_activos = 3 · unidades = 6
--           guardias_en_turno = 2 · incidentes_abiertos = 1
--           visitas_esperando_aprobacion = 1 · personas_dentro = 3
select * from public.v_resumen_condominio;

-- Esperado: 3 filas — Juan Pérez (entró en auto), Pedro Lagos (entró caminando)
-- y la visita María González. Ana NO debe aparecer porque ya salió.
select nombre, unidad, persona_tipo, tipo_acceso, entro_por, entro_en
  from public.v_personas_dentro
 order by entro_en desc;

-- Esperado: 1 fila — Ana Rojas con su Kia Rio rojo esperando la barrera
select residente, unidad, patente, marca, modelo, color, segundos_esperando
  from public.v_solicitudes_vehiculares_pendientes;

-- Esperado: 2 filas, y el paquete de 9 días con alerta_antiguedad = true
select residente, unidad, numero_seguimiento, dias_en_porteria, alerta_antiguedad
  from public.v_paquetes_porteria;

-- Esperado: 2 filas — TVWX-78 (Juan) y LPRS-65 (Pedro)
select residente, unidad, patente, marca, modelo, color, dias_esperando
  from public.v_vehiculos_por_aprobar;

-- Comprobación del candado más importante: esto TIENE que fallar con el mensaje
-- "La tabla movimientos_acceso es de solo agregar…". Si no falla, algo está mal.
-- Quitá los guiones del principio para probarlo:
-- update public.movimientos_acceso set estado = 'denegado' where true;


-- ============================================================================
-- FIN DEL ARCHIVO 04 — la base de datos está lista y con datos de prueba
-- ============================================================================
