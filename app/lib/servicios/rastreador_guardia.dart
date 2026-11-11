// ============================================================================
// Tomass Seguridad — Rastreador en vivo del guardia
// ============================================================================
// ES EL ÚNICO DUEÑO DEL STREAM DE GPS DE LA APP
//
//   geolocator mantiene UN solo stream de posiciones por proceso: el segundo
//   getPositionStream() devuelve el primero e ignora sus ajustes. Por eso
//   nadie más debe abrir un stream; las pantallas escuchan `posiciones`.
//   (Antes la pantalla de rondas abría el suyo y por eso la auto-marca recibía
//   el fix de 3 min del turno en vez de uno rápido — auditoría G-01.)
//
// DOS MODOS
//
//   turno  1 fix cada 3 min. Cuida la batería de las 12 horas.
//   ronda  1 fix cada 3 s mientras hay una ronda abierta, para que la
//          geocerca marque al pasar. Vuelve solo a "turno" a las 2 horas
//          por si el guardia se olvida de cerrar la ronda.
//
// QUÉ SE MANDA AL SERVIDOR
//
//   Una muestra cada ~2,5 min en turno y cada 30 s en ronda, con precisión,
//   bandera de GPS simulado y, si se mandó tarde por falta de red, la hora
//   real en que se tomó. Si el envío falla, el estado NO pasa a "activo".
// ============================================================================

import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart' as ph;

import 'servicio_guardia.dart';

/// Estado del rastreador visto desde el UI.
enum EstadoRastreador { apagado, bloqueado, esperandoPrimera, activo, demorado }

/// Ritmo del GPS: lento para el turno, rápido mientras hay una ronda abierta.
enum ModoRastreo { turno, ronda }

/// Muestra que no se pudo mandar por falta de red. Vive en memoria: si
/// Android mata la app se pierde, igual que antes se perdían todas.
class _MuestraPendiente {
  const _MuestraPendiente(
      this.lat, this.lng, this.precisionM, this.simulada, this.tomadaEn);
  final double lat;
  final double lng;
  final double precisionM;
  final bool simulada;
  final DateTime tomadaEn;
}

class RastreadorGuardia {
  RastreadorGuardia(this._servicio);

  final ServicioGuardia _servicio;
  StreamSubscription<Position>? _sub;
  Timer? _watchdog;
  bool _enviando = false;
  bool _pidiendo = false;
  bool _arrancando = false;
  bool _cancelado = false;

  ModoRastreo _modo = ModoRastreo.turno;
  DateTime? _modoRondaDesde;
  DateTime? _suscritoEn;

  DateTime? _ultimoEnvioExitoso;
  DateTime? _ultimoIntentoDeEnvio;
  DateTime? _ultimaPosicionDelStream;

  final _pendientes = <_MuestraPendiente>[];
  static const _maxPendientes = 240; // 12 h a una muestra cada 3 min

  final _posicionesCtrl = StreamController<Position>.broadcast();

  /// Posiciones frescas, ya filtradas por antigüedad. Es lo que escuchan la
  /// pantalla de rondas y el vigilante de geocercas.
  Stream<Position> get posiciones => _posicionesCtrl.stream;

  /// La última posición fresca recibida, o null.
  Position? ultimaPosicion;

  final ValueNotifier<EstadoRastreador> estado =
      ValueNotifier(EstadoRastreador.apagado);
  final ValueNotifier<DateTime?> ultimoEnvio = ValueNotifier(null);

  /// true mientras el teléfono entregue posiciones de una app de GPS falso.
  final ValueNotifier<bool> gpsSimulado = ValueNotifier(false);

  static const _umbralDemorado = Duration(minutes: 6);

  /// Un fix más viejo que esto no se usa para nada.
  static const _edadMaxima = Duration(minutes: 2);

  /// Peor que esto no se guarda en el recorrido (triangulación celular).
  static const _precisionMaximaParaGuardar = 100.0;

  /// Tope de tiempo en modo ronda, por si queda una ronda sin cerrar.
  static const _topeModoRonda = Duration(hours: 2);

  bool get activo => _watchdog != null;
  ModoRastreo get modo => _modo;

  Duration get _intervaloGps => _modo == ModoRastreo.ronda
      ? const Duration(seconds: 3)
      : const Duration(minutes: 3);

  /// Cada cuánto se escribe en la base. Un poco menos que el intervalo del
  /// GPS en modo turno para que ningún fix de 3 min quede frenado.
  Duration get _cadaEnvio => _modo == ModoRastreo.ronda
      ? const Duration(seconds: 30)
      : const Duration(seconds: 150);

  /// Silencio del stream a partir del cual el watchdog pide un fix propio.
  Duration get _umbralWatchdog => _modo == ModoRastreo.ronda
      ? const Duration(seconds: 45)
      : const Duration(minutes: 6);

  Duration? get haceQueMandeUltimo => _ultimoEnvioExitoso == null
      ? null
      : DateTime.now().difference(_ultimoEnvioExitoso!);

  Future<void> iniciar() async {
    if (activo || _arrancando) return;
    _arrancando = true;
    _cancelado = false;
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        estado.value = EstadoRastreador.bloqueado;
        return;
      }

      var permiso = await Geolocator.checkPermission();
      if (permiso == LocationPermission.denied) {
        permiso = await Geolocator.requestPermission();
      }
      if (permiso == LocationPermission.denied ||
          permiso == LocationPermission.deniedForever) {
        estado.value = EstadoRastreador.bloqueado;
        return;
      }

      if (Platform.isAndroid) {
        final estadoNotif = await ph.Permission.notification.status;
        if (!estadoNotif.isGranted) {
          await ph.Permission.notification.request();
        }
        final estadoBg = await ph.Permission.locationAlways.status;
        if (!estadoBg.isGranted && !estadoBg.isPermanentlyDenied) {
          await ph.Permission.locationAlways.request();
        }
      }

      // Si cerraron el turno mientras se contestaban los permisos, no
      // arrancamos: quedaría el GPS prendido sin turno.
      if (_cancelado) return;

      estado.value = EstadoRastreador.esperandoPrimera;
      await _suscribir();
      if (_cancelado) {
        detener();
        return;
      }
      _watchdog =
          Timer.periodic(const Duration(seconds: 30), (_) => _tickWatchdog());
      unawaited(_tickWatchdog());
    } finally {
      _arrancando = false;
    }
  }

  /// Cambia entre el ritmo de turno y el de ronda. Vuelve a abrir el stream
  /// porque geolocator no deja cambiar los ajustes de uno ya abierto.
  Future<void> cambiarModo(ModoRastreo nuevo) async {
    if (_modo == nuevo) return;
    _modo = nuevo;
    _modoRondaDesde = nuevo == ModoRastreo.ronda ? DateTime.now() : null;
    if (!activo || _cancelado) return;
    await _suscribir();
  }

  Future<void> _suscribir() async {
    // Hay que ESPERAR la cancelación: recién ahí geolocator suelta el stream
    // viejo. Sin el await, el listen de abajo se colgaría del stream que se
    // está cerrando.
    final viejo = _sub;
    _sub = null;
    await viejo?.cancel();
    if (_cancelado) return;

    final LocationSettings ajustes;
    if (Platform.isAndroid) {
      ajustes = AndroidSettings(
        accuracy: LocationAccuracy.high,
        intervalDuration: _intervaloGps,
        distanceFilter: 0,
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: 'Tomass Seguridad',
          notificationText: 'Turno abierto',
          notificationChannelName: 'Rastreo del turno',
          setOngoing: true,
          enableWakeLock: true,
          notificationIcon: AndroidResource(
            name: 'ic_launcher',
            defType: 'mipmap',
          ),
        ),
      );
    } else if (Platform.isIOS) {
      // OJO: allowBackgroundLocationUpdates exige UIBackgroundModes=location
      // en Info.plist. Sin eso iOS cierra la app.
      ajustes = AppleSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: _modo == ModoRastreo.ronda ? 0 : 20,
        activityType: ActivityType.fitness,
        pauseLocationUpdatesAutomatically: false,
        allowBackgroundLocationUpdates: true,
        showBackgroundLocationIndicator: true,
      );
    } else {
      ajustes = const LocationSettings(accuracy: LocationAccuracy.high);
    }

    _suscritoEn = DateTime.now();
    _sub = Geolocator.getPositionStream(locationSettings: ajustes).listen(
      (p) {
        _ultimaPosicionDelStream = DateTime.now();
        _alRecibir(p);
      },
      // Si el stream se cae o termina, soltamos la suscripción: el próximo
      // tick del watchdog la vuelve a abrir.
      onError: (_) => _sub = null,
      onDone: () => _sub = null,
      cancelOnError: true,
    );
  }

  Future<void> _tickWatchdog() async {
    if (_cancelado) return;
    final ahora = DateTime.now();

    // Freno de batería: una ronda olvidada no puede dejar el GPS a 3 s.
    final desde = _modoRondaDesde;
    if (_modo == ModoRastreo.ronda &&
        desde != null &&
        ahora.difference(desde) > _topeModoRonda) {
      await cambiarModo(ModoRastreo.turno);
    }

    if (_sub == null) await _suscribir();

    final referencia = _ultimaPosicionDelStream ?? _suscritoEn;
    final silencio =
        referencia == null ? _umbralWatchdog : ahora.difference(referencia);
    // Si ya tenemos alguna posición y el stream no lleva tanto callado, no
    // hay nada que hacer. Sin ninguna posición todavía (arranque del turno)
    // seguimos de largo para pedir la primera ya.
    if (ultimaPosicion != null && silencio < _umbralWatchdog) return;

    // El stream está mudo (o todavía no dio la primera): pedimos un fix.
    await pedirPosicionAhora(
      precision: _modo == ModoRastreo.ronda
          ? LocationAccuracy.high
          : LocationAccuracy.medium,
      espera: const Duration(seconds: 25),
    );

    // Mudo hace demasiado: lo damos por muerto y lo abrimos de nuevo.
    if (silencio > const Duration(minutes: 10)) await _suscribir();
  }

  /// Pide un fix a demanda (botón "Refrescar GPS" y watchdog). Devuelve
  /// null si no llegó. Nunca lanza.
  Future<Position?> pedirPosicionAhora({
    LocationAccuracy precision = LocationAccuracy.best,
    Duration espera = const Duration(seconds: 15),
  }) async {
    if (_pidiendo) return null;
    _pidiendo = true;
    try {
      final p = await Geolocator.getCurrentPosition(
        locationSettings:
            LocationSettings(accuracy: precision, timeLimit: espera),
      );
      await _alRecibir(p);
      return p;
    } catch (_) {
      return null;
    } finally {
      _pidiendo = false;
    }
  }

  void detener() {
    _cancelado = true;
    _sub?.cancel();
    _sub = null;
    _watchdog?.cancel();
    _watchdog = null;
    _modo = ModoRastreo.turno;
    _modoRondaDesde = null;
    _suscritoEn = null;
    _ultimoEnvioExitoso = null;
    _ultimoIntentoDeEnvio = null;
    _ultimaPosicionDelStream = null;
    _pendientes.clear();
    ultimaPosicion = null;
    ultimoEnvio.value = null;
    gpsSimulado.value = false;
    estado.value = EstadoRastreador.apagado;
  }

  Future<void> _alRecibir(Position p) async {
    if (_cancelado) return;

    // Fix viejo (caché del sistema): no sirve ni para el mapa ni para marcar.
    if (DateTime.now().difference(p.timestamp).abs() > _edadMaxima) return;

    if (gpsSimulado.value != p.isMocked) gpsSimulado.value = p.isMocked;

    ultimaPosicion = p;
    if (!_posicionesCtrl.isClosed) _posicionesCtrl.add(p);

    // De acá para abajo es el guardado en la base.
    if (p.accuracy > _precisionMaximaParaGuardar) return;

    final ahora = DateTime.now();
    final ultimoIntento = _ultimoIntentoDeEnvio;
    if (ultimoIntento != null && ahora.difference(ultimoIntento) < _cadaEnvio) {
      return;
    }
    if (_enviando) return;
    _enviando = true;
    _ultimoIntentoDeEnvio = ahora;
    try {
      final llego = await _servicio.actualizarMiUbicacion(
        lat: p.latitude,
        lng: p.longitude,
        precisionM: p.accuracy,
        simulada: p.isMocked,
      );
      if (_cancelado) return;
      if (llego) {
        final cuando = DateTime.now();
        _ultimoEnvioExitoso = cuando;
        ultimoEnvio.value = cuando;
        estado.value = EstadoRastreador.activo;
        await _vaciarPendientes();
      } else {
        // Sin red: la guardamos con su hora para mandarla después. El estado
        // NO pasa a activo; evaluarDemora() lo llevará a "demorado".
        if (_pendientes.length >= _maxPendientes) _pendientes.removeAt(0);
        _pendientes.add(_MuestraPendiente(
            p.latitude, p.longitude, p.accuracy, p.isMocked, p.timestamp));
      }
    } finally {
      _enviando = false;
    }
  }

  /// Manda las muestras que quedaron sin red, en orden, con su hora real.
  /// Si una falla corta: la red volvió a caerse.
  Future<void> _vaciarPendientes() async {
    var enviadas = 0;
    while (_pendientes.isNotEmpty && enviadas < 30 && !_cancelado) {
      final m = _pendientes.first;
      final llego = await _servicio.actualizarMiUbicacion(
        lat: m.lat,
        lng: m.lng,
        precisionM: m.precisionM,
        simulada: m.simulada,
        tomadaEn: m.tomadaEn,
      );
      if (!llego) return;
      _pendientes.removeAt(0);
      enviadas++;
    }
  }

  /// La pantalla la llama en un timer local para que el banner pase a
  /// "demorado" si hace rato que no se manda nada.
  void evaluarDemora() {
    if (estado.value == EstadoRastreador.apagado ||
        estado.value == EstadoRastreador.bloqueado) {
      return;
    }
    final ultimo = _ultimoEnvioExitoso;
    if (ultimo == null) return;
    if (DateTime.now().difference(ultimo) >= _umbralDemorado) {
      estado.value = EstadoRastreador.demorado;
    }
  }
}
