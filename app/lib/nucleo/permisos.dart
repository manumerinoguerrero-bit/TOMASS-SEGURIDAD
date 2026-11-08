// ============================================================================
// Tomass Seguridad — Pedir todos los permisos de la app de una vez
// ============================================================================
// POR QUÉ ESTE ARCHIVO EXISTE
//
//   Antes cada feature pedía su permiso cuando lo necesitaba: la cámara al
//   sacar una foto, la ubicación al abrir el turno, las notificaciones al
//   abrir turno también. Para un guardia que ya conoce la app funciona OK,
//   pero cuando llega un celular nuevo pasa esto:
//
//     · Instala la app → no pide nada (los permisos se piden "runtime"
//       desde Android 6, no al instalar).
//     · Logueo → nada.
//     · Toca "Anotar ingreso" sin abrir turno → se queja por otra cosa.
//     · Nunca sabe que la app necesita ubicación, cámara ni notifs.
//
//   Pedido por Manuel el 08/11/2026: pedir todos los permisos APENAS el
//   guardia se loguea. Así el que arma el celular por primera vez ya los
//   deja listos y la app anda a la primera.
//
//   CUIDADO con lo que esto NO resuelve: los ajustes específicos de MIUI
//   (Xiaomi) — ahorro de batería "Sin restricciones", autoarranque, candado
//   en memoria — no se pueden pedir desde el código. Esos siguen siendo
//   manuales. El manual de setup los explica.
// ============================================================================

import 'dart:io' show Platform;

import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

abstract final class PermisosDeLaApp {
  /// Pide todos los permisos que usa la app, en el orden en que Android los
  /// deja pedir. Se llama una sola vez, justo después del login. Si el
  /// usuario rechaza alguno la app sigue andando; el feature que lo necesita
  /// va a mostrar un aviso cuando se use (ya era así antes).
  ///
  /// SILENCIOSA: no lanza excepciones ni devuelve nada útil. Es
  /// "best-effort". Si Android ya tiene los permisos otorgados, no muestra
  /// ninguna ventana — esto es seguro llamarla cada login.
  static Future<void> pedirTodos() async {
    // 1) UBICACIÓN
    //
    //   Primero WhileInUse (requerido por Android para después pedir
    //   Always). Geolocator es el que sabe lanzar el diálogo correcto
    //   en cada versión de Android.
    try {
      var p = await Geolocator.checkPermission();
      if (p == LocationPermission.denied) {
        await Geolocator.requestPermission();
      }
    } catch (_) {/* el rastreador va a volver a intentar */}

    if (Platform.isAndroid) {
      // 2) UBICACIÓN EN BACKGROUND (Always)
      //
      //   Tiene que ser un paso separado en Android 10+. Si no está
      //   otorgado permanentemente, lo pedimos — el sistema abre la
      //   ventana de ajustes que lleva a "Permitir siempre".
      try {
        final bg = await Permission.locationAlways.status;
        if (!bg.isGranted && !bg.isPermanentlyDenied) {
          await Permission.locationAlways.request();
        }
      } catch (_) {}

      // 3) NOTIFICACIONES (Android 13+ lo exige explícito)
      //
      //   Sin este permiso el foreground service no muestra la notif
      //   permanente y Android mata el GPS a los 30 s de bloquear pantalla.
      try {
        final notif = await Permission.notification.status;
        if (!notif.isGranted && !notif.isPermanentlyDenied) {
          await Permission.notification.request();
        }
      } catch (_) {}
    }

    // 4) CÁMARA
    //
    //   Para encomiendas, novedades e ingresos manuales con foto. Mejor
    //   pedirla ahora que cuando el guardia esté haciendo entregas con
    //   un residente esperando — así la primera foto sale a la primera.
    try {
      final cam = await Permission.camera.status;
      if (!cam.isGranted && !cam.isPermanentlyDenied) {
        await Permission.camera.request();
      }
    } catch (_) {}
  }
}
