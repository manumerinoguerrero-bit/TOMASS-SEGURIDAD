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
// POR QUÉ ESTÁ EN LA APP Y NO ES UN SERVICIO EN SEGUNDO PLANO DE ANDROID
//
//   Para MVP alcanza con esto. Cuando la app está minimizada, Flutter la
//   pausa y el Timer se detiene: si el guardia bloquea el teléfono el
//   admin va a ver "sin actualizar hace 20 min". Es suficiente para saber
//   que hay que llamarlo.
//
//   La versión con servicio nativo Android (foreground service con
//   notificación permanente) queda para más adelante — implica pedir
//   permisos "always" al usuario y hay que darle vuelta al Play Store.
// ============================================================================

import 'dart:async';

import '../nucleo/ubicacion.dart';
import 'servicio_guardia.dart';

class RastreadorGuardia {
  RastreadorGuardia(this._servicio);

  final ServicioGuardia _servicio;
  Timer? _timer;
  bool _enviando = false;

  bool get activo => _timer != null && _timer!.isActive;

  /// Empezar a mandar la posición cada [cada]. Si ya está andando, no hace
  /// nada. Manda una posición al toque para que el admin vea al guardia
  /// aparecer en el mapa sin esperar el primer intervalo.
  void iniciar({Duration cada = const Duration(minutes: 3)}) {
    if (activo) return;
    _enviarUnaVez();
    _timer = Timer.periodic(cada, (_) => _enviarUnaVez());
  }

  /// Detener el envío periódico. Se llama al cerrar turno o al cerrar sesión.
  void detener() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _enviarUnaVez() async {
    // Evita apilar envíos si el anterior todavía no volvió (mala señal).
    if (_enviando) return;
    _enviando = true;
    try {
      final donde = await Localizador.donde(
        esperaMaxima: const Duration(seconds: 15),
      );
      if (donde == null) return; // sin señal, se intentará en el próximo tick
      await _servicio.actualizarMiUbicacion(
        lat: donde.latitud,
        lng: donde.longitud,
      );
    } catch (_) {
      // Cualquier falla queda silenciada: el próximo tick vuelve a intentar.
    } finally {
      _enviando = false;
    }
  }
}
