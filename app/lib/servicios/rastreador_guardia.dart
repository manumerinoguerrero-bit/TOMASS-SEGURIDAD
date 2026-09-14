// ============================================================================
// Tomass Seguridad — Rastreador en vivo del guardia
// ============================================================================
// LO QUE HACE
//
//   Mientras el guardia tenga un turno abierto, cada 3 minutos manda su
//   ubicación GPS al servidor. Con eso el admin ve un mapa en vivo con la
//   última posición de cada guardia activo.
//
// POR QUÉ 3 MINUTOS Y NO 30 SEGUNDOS
//
//   Un GPS activo con alta precisión chupa batería como aspiradora. Con
//   30 segundos, un celular común no llega al fin de un turno de 12 horas.
//   Con 3 minutos es imperceptible. Para "dónde está el guardia AHORA"
//   3 minutos es preciso de sobra.
//
// POR QUÉ HAY DOS FUENTES DE POSICIÓN (stream + timer)
//
//   El diseño anterior tenía solo `getPositionStream()`. En la práctica,
//   cuando el foreground service NO arrancaba bien (por permiso de
//   notificaciones no aceptado, o por el fabricante Xiaomi/Realme matando
//   procesos), el stream emitía UNA sola vez y se moría. Lo veíamos en la
//   base: el guardia abría turno a las 10:57:15 y la última ubicación
//   quedaba a las 10:57:17. Nada más en 5 horas.
//
//   Ahora tenemos DOS caminos hacia la BD:
//
//     1. Stream de geolocator (rápido, ~cada 3 min si el service anda).
//     2. Timer.periodic en Dart que cada 3 min pide getCurrentPosition().
//
//   Si el foreground service anda, el timer es redundante pero no molesta.
//   Si NO anda (proceso Dart pausado por sistema), el timer no va a
//   ejecutar tampoco. Pero al menos mientras el guardia tenga la app
//   abierta o volver a ella, el timer arma la sesión de nuevo y manda.
//
// PERMISOS QUE PEDIMOS AL ARRANCAR
//
//   * Location (ACCESS_FINE_LOCATION): sin esto no hay GPS.
//   * LocationAlways (ACCESS_BACKGROUND_LOCATION): sin esto el service
//     muere cuando la app pasa a background.
//   * Notification (POST_NOTIFICATIONS, Android 13+): sin esto la notif
//     permanente del foreground service NO aparece, y sin ella Android
//     mata el proceso a los ~30 s de bloquear pantalla. Este era el bug.
//
//   Los permisos se piden UNA sola vez al abrir el primer turno; después
//   Android los recuerda. Si el guardia rechaza alguno, el rastreador
//   arranca igual (mejor tener algo que nada), pero el admin va a ver
//   "Sin señal" cuando el guardia bloquee la pantalla.
// ============================================================================

import 'dart:async';
import 'dart:io' show Platform;

import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart' as ph;

import 'servicio_guardia.dart';

class RastreadorGuardia {
  RastreadorGuardia(this._servicio);

  final ServicioGuardia _servicio;
  StreamSubscription<Position>? _sub;
  Timer? _watchdog;
  bool _enviando = false;
  DateTime? _ultimoEnvioExitoso;

  bool get activo => _sub != null || _watchdog != null;

  /// Cuánto hace que se mandó la última posición al servidor (útil para
  /// diagnóstico en pantalla si algún día se quiere).
  Duration? get haceQueMandeUltimo => _ultimoEnvioExitoso == null
      ? null
      : DateTime.now().difference(_ultimoEnvioExitoso!);

  /// Arranca el rastreador si no está activo. Si el usuario no dio permiso de
  /// ubicación, sale sin hacer nada — el mapa en vivo va a mostrar "Sin
  /// señal" y ya está.
  Future<void> iniciar({Duration cada = const Duration(minutes: 3)}) async {
    if (activo) return;

    // 1) Servicio de ubicación prendido en el celular
    if (!await Geolocator.isLocationServiceEnabled()) return;

    // 2) Permiso de ubicación: pedimos "Always" a propósito, porque
    //    "WhileInUse" no alcanza para el foreground service en background.
    //    Si el usuario da solo "WhileInUse", igual arrancamos: el stream
    //    va a andar mientras la app esté en primer plano.
    var permiso = await Geolocator.checkPermission();
    if (permiso == LocationPermission.denied) {
      permiso = await Geolocator.requestPermission();
    }
    if (permiso == LocationPermission.denied ||
        permiso == LocationPermission.deniedForever) {
      return;
    }

    // 3) Permiso de notificaciones (Android 13+). Sin esto, la notificación
    //    permanente del foreground service no aparece, y sin ella Android
    //    trata la app como si no estuviera en foreground y mata el GPS a
    //    los ~30 segundos de bloquear la pantalla. Este era el bug real.
    //    En Android <13 y en iOS, request() responde granted directamente.
    if (Platform.isAndroid) {
      final estadoNotif = await ph.Permission.notification.status;
      if (!estadoNotif.isGranted) {
        await ph.Permission.notification.request();
      }

      // Además pedimos LocationAlways de forma explícita: geolocator no
      // siempre lo pide en la misma sesión que WhileInUse (Android exige
      // dos pasos separados), así que forzamos el segundo.
      final estadoBg = await ph.Permission.locationAlways.status;
      if (!estadoBg.isGranted && !estadoBg.isPermanentlyDenied) {
        await ph.Permission.locationAlways.request();
      }
    }

    // 4) Stream de geolocator con foreground service (rápido, cerca de la
    //    frecuencia real del GPS del teléfono).
    final settings = Platform.isAndroid
        ? AndroidSettings(
            accuracy: LocationAccuracy.high,
            intervalDuration: cada,
            // 0 = mandar cada intervalDuration sin importar si se movió.
            distanceFilter: 0,
            foregroundNotificationConfig: const ForegroundNotificationConfig(
              notificationTitle: 'Tomass Seguridad',
              notificationText:
                  'Turno abierto · enviando tu ubicación al panel del admin',
              notificationChannelName: 'Rastreo del turno',
              setOngoing: true,
              enableWakeLock: true,
              notificationIcon: AndroidResource(
                name: 'ic_launcher',
                defType: 'mipmap',
              ),
            ),
          )
        : LocationSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 0,
            timeLimit: cada + const Duration(seconds: 30),
          );

    _sub = Geolocator.getPositionStream(locationSettings: settings)
        .listen(_alRecibir, onError: (_) {
      // Silencioso: el watchdog abajo vuelve a intentar cada `cada`.
    });

    // 5) WATCHDOG: Timer.periodic redundante. Cada `cada` pide la posición
    //    actual de forma directa. Sirve para:
    //      * Si el stream murió sin avisar (fabricantes agresivos), este
    //        toma la posta mientras la app siga viva.
    //      * Al arrancar, dispara un envío inmediato para no esperar el
    //        primer tick del intervalo del stream.
    //    getCurrentPosition() con desiredAccuracy medium es más liviano
    //    para la batería que el stream de alta precisión, y como esto es
    //    un fallback no necesita la máxima precisión.
    _watchdog = Timer.periodic(cada, (_) => _tickWatchdog());
    // Disparo inmediato para tener una posición apenas se abre el turno.
    unawaited(_tickWatchdog());
  }

  Future<void> _tickWatchdog() async {
    if (_enviando) return;
    try {
      final p = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 25),
        ),
      );
      await _alRecibir(p);
    } catch (_) {
      // Silencioso: el próximo tick vuelve a probar.
    }
  }

  void detener() {
    _sub?.cancel();
    _sub = null;
    _watchdog?.cancel();
    _watchdog = null;
    _ultimoEnvioExitoso = null;
  }

  Future<void> _alRecibir(Position p) async {
    // Evita apilar envíos si el anterior todavía no volvió (mala señal).
    if (_enviando) return;
    _enviando = true;
    try {
      await _servicio.actualizarMiUbicacion(
        lat: p.latitude,
        lng: p.longitude,
      );
      _ultimoEnvioExitoso = DateTime.now();
    } catch (_) {
      // Cualquier falla queda silenciada: la próxima posición vuelve a probar.
    } finally {
      _enviando = false;
    }
  }
}
