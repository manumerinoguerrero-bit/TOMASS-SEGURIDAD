-- ============================================================================
-- Tomass Seguridad — 11 · La limpieza automática de fotos
-- ============================================================================
-- ⚠️ ESTE ARCHIVO YA ESTÁ APLICADO EN EL SERVIDOR. Queda para el historial.
--
-- LA DECISIÓN, Y POR QUÉ
--
--   La foto de una encomienda es el respaldo del condominio mientras el paquete
--   está en portería o recién entregado: si el residente reclama que llegó
--   dañado, ahí está la prueba. Pero una vez que firmó y se lo llevó, esa foto
--   va perdiendo sentido, y a los 6 meses ya no le queda ninguno.
--
--   Los números que llevaron a esto: con las tres instalaciones funcionando son
--   unas 90 encomiendas por día. A ~170 KB cada foto (después de la compresión
--   por propósito), eso es más de medio GB por mes, PARA SIEMPRE. En cinco años
--   se estaría pagando por decenas de GB de fotos de cajas de 2026.
--
--   Con esta limpieza el espacio se estabiliza en unos pocos GB y deja de
--   crecer.
--
-- QUÉ SE BORRA Y QUÉ NO
--
--   SE BORRA:  la foto de cuando llegó el paquete y la de cuando se entregó.
--   NO SE TOCA: la firma del residente, ni una sola letra del registro escrito.
--
--   Eso es lo importante: lo que vale como constancia es la firma y el registro
--   (quién lo recibió, quién lo retiró, a qué hora), y eso pesa casi nada.
--
-- CÓMO FUNCIONA
--
--   Todas las madrugadas a las 4:30 (hora de Chile), la base de datos llama
--   sola a la función limpiar-fotos del servidor. Manuel no hace nada, nunca.
--
--   Va de a tandas de 200 encomiendas por noche. Si algún día se acumularan
--   años de fotos, borrar todo de una podría cortarse a la mitad; de a 200 se
--   pone al día en pocos días y después mantiene el ritmo sin esfuerzo.
--
--   Si la limpieza falla una noche (se cayó internet, lo que sea), no marca
--   nada y reintenta sola a la madrugada siguiente. El orden importa: primero
--   se borran los ARCHIVOS y recién después se marca la fila. Al revés
--   quedarían archivos huérfanos ocupando espacio sin que nadie los encuentre.
-- ============================================================================


-- ============================================================================
-- 1 · LA MARCA DE "FOTO BORRADA POR ANTIGÜEDAD"
-- ============================================================================
-- Distingue "nunca tuvo foto" de "la tuvo y se borró por vieja". Sin esto, la
-- app mostraría el ícono de imagen rota donde corresponde una explicación.
-- ============================================================================

alter table public.paquetes
  add column if not exists fotos_borradas_en timestamptz;


-- ============================================================================
-- 2 · EL RELOJ DESPERTADOR
-- ============================================================================
-- pg_cron ejecuta tareas a horario, como una alarma.
-- pg_net le permite llamar a la función del servidor.
-- ============================================================================

create extension if not exists pg_cron;
create extension if not exists pg_net;


-- ============================================================================
-- 3 · LA CITA DE TODAS LAS MADRUGADAS
-- ============================================================================
-- 8:30 UTC = 4:30 de la madrugada en Chile. Se elige esa hora porque es cuando
-- nadie está usando el sistema.
--
-- La llave que viaja en la llamada es la PÚBLICA, la misma que lleva la app en
-- cada teléfono. Alcanza y sobra: la función no recibe instrucciones (hace
-- siempre lo mismo, con la regla fija de los 6 meses) y no devuelve datos de
-- nadie, solo cuántas fotos borró. Lo peor que podría hacer un extraño llamándola
-- es adelantar unas horas una limpieza que iba a pasar igual esa madrugada.
--
-- Ver el texto completo de la cita en el panel de Supabase, migración
-- limpieza_automatica_de_fotos_de_encomiendas.
-- ============================================================================

-- select cron.schedule('borrar-fotos-de-encomiendas-viejas', '30 8 * * *', ...);

-- Para revisar que sigue activa:
--   select jobname, schedule, active from cron.job;

-- Para ver si corrió bien anoche:
--   select status, start_time, return_message
--     from cron.job_run_details
--    order by start_time desc limit 5;


-- ============================================================================
-- FIN DEL ARCHIVO 11
-- ============================================================================
