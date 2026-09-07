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
//   3 minutos es preciso de sobra: si un guardia está corriendo, la
//   posición nunca es "aquí y solo aquí", es un radio de la instalación.
//
// FOREGROUND SERVICE (por qué el GPS sigue mandando con la pantalla apagada)
//
//   Antes usábamos un Timer.periodic dentro del proceso Dart. En cuanto el
//   guardia bloqueaba el celular, Flutter pausaba el timer y el admin veía
//   "Sin señal" a los 3 minutos. Es lo que le pasó a Juan Martínez el
//   06/09/2026.
//
//   Ahora usamos Geolocator.getPositionStream() con
//   AndroidSettings.foregroundNotificationConfig. Esto le pide al sistema
//   Android que arranque un servicio nativo con una notificación permanente,
//   que sigue mandando la posición aunque:
//
//     * el guardia bloquee la pantalla
//     * la app quede en background
//     * el celular se meta en modo ahorro de batería
//
//   La notificación es OBLIGATORIA por Android: es lo que le muestra al
//   guardia que la app está usando el GPS. No se puede ocultar.
//
// PERMISO "PERMITIR TODO EL TIEMPO"
//
//   El foreground service arranca igual con permiso "solo mientras uso la
//   app", pero Android en algunos fabricantes (Xiaomi, Huawei) igual mata
//   el proceso si la app pasa mucho a background. Con "Permitir todo el
//   tiempo" queda claro que el sistema no debe pausar el GPS.
//
//   El guardia lo acepta una sola vez la primera vez que abre un turno.
//   Si el permiso no está, el rastreador arranca igual (mejor tener GPS
//   con la app abierta que no tener nada), pero el admin va a ver "Sin
//   señal" cuando el guardia bloquee la pantalla.
// ============================================================================

import 'dart:async';
import 'dart:io' show Platform;

import 'package:geolocator/geolocator.dart';

import 'servicio_guardia.dart';

class RastreadorGuardia {
  RastreadorGuardia(this._servicio);

  final ServicioGuardia _servicio;
  StreamSubscription<Position>? _sub;
  bool _enviando = false;

  bool get activo => _sub != null;

  /// Arranca el rastreador si no está activo. Si el usuario no dio permiso de
  /// ubicación, sale sin hacer nada — el mapa en vivo va a mostrar "Sin
  /// señal" y ya está.
  Future<void> iniciar({Duration cada = const Duration(minutes: 3)}) async {
    if (activo) return;

    // Chequeo mínimo: si el usuario apagó el GPS del teléfono o negó el
    // permiso, no tiene sentido intentar. Pedimos el permiso de "en uso"
    // — al iniciar el turno la pantalla de turno pide el "always" arriba.
    if (!await Geolocator.isLocationServiceEnabled()) return;
    var permiso = await Geolocator.checkPermission();
    if (permiso == LocationPermission.denied) {
      permiso = await Geolocator.requestPermission();
    }
    if (permiso == LocationPermission.denied ||
        permiso == LocationPermission.deniedForever) {
      return;
    }

    // Configuración del stream. En Android usamos AndroidSettings con el
    // foreground service embebido de geolocator; en cualquier otra
    // plataforma (iOS, web) caemos al LocationSettings genérico.
    final settings = Platform.isAndroid
        ? AndroidSettings(
            accuracy: LocationAccuracy.high,
            // Intervalo mínimo entre actualizaciones. Al pasar por acá
            // el sistema puede darnos MÁS actualizaciones si hay
            // suficiente movimiento; nunca menos.
            intervalDuration: cada,
            // 0 = mandar la posición cada `intervalDuration` sin importar
            // si el guardia se movió o no. Con cualquier valor mayor,
            // un guardia parado en la garita nunca aparecería en el mapa.
            distanceFilter: 0,
            foregroundNotificationConfig: const ForegroundNotificationConfig(
              notificationTitle: 'Tomass Seguridad',
              notificationText:
                  'Turno abierto · enviando tu ubicación al panel del admin',
              notificationChannelName: 'Rastreo del turno',
              // No mostrar el ícono como notification badge en el launcher:
              // ya está el ícono de la app abierta con otros datos.
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
      // Silencioso a propósito: el próximo tick vuelve a probar. Si el
      // stream muere del todo, el admin lo va a ver como "Sin señal" y
      // el guardia va a reabrir la app.
    });
  }

  void detener() {
    _sub?.cancel();
    _sub = null;
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
    } catch (_) {
      // Cualquier falla queda silenciada: la próxima posición vuelve a probar.
    } finally {
      _enviando = false;
    }
  }
}
