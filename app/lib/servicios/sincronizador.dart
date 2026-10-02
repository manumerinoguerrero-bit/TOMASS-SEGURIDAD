// ============================================================================
// Tomass Seguridad — Vaciado automático de la cola offline
// ============================================================================
// Escucha dos cosas:
//
//   1. El stream de connectivity_plus: cuando pasa de "sin conexión" a
//      "con conexión", intenta vaciar la cola.
//   2. Un timer de respaldo cada 60s: por si connectivity_plus no detecta
//      bien un cambio puntual (pasa en algunos routers caseros al reconectar).
//
// La sincronización es serial — una op a la vez — para que si el backend
// está empezando a responder después de un corte, no lo saturemos con un
// paquete de 20 requests. Si una op falla por red se corta el loop y se
// reintenta en el próximo tick. Si falla por validación, se descarta tras
// 3 intentos y se guarda el último error para que el admin pueda mirar.
// ============================================================================

import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'cola_offline.dart';

class Sincronizador {
  Sincronizador(this._cola, this._supabase);

  final ColaOffline _cola;
  final SupabaseClient _supabase;

  StreamSubscription<List<ConnectivityResult>>? _subConectividad;
  Timer? _reloj;
  bool _sincronizando = false;

  void arrancar() {
    final c = Connectivity();
    _subConectividad = c.onConnectivityChanged.listen((rs) {
      final hayConexion = rs.any((r) => r != ConnectivityResult.none);
      if (hayConexion) {
        // Pequeño delay para dejar que el stack TCP termine de levantar;
        // sincronizar en el instante del evento a veces falla con
        // "Network is unreachable" aunque el estado ya diga wifi.
        Future<void>.delayed(const Duration(seconds: 2), sincronizarAhora);
      }
    });

    // Latido de respaldo: cada minuto intentamos. Si hay cola llena vacía
    // rápido, si no es un no-op.
    _reloj = Timer.periodic(const Duration(seconds: 60), (_) {
      sincronizarAhora();
    });

    // Un primer intento al arrancar (cubre el caso de que la app abra con
    // red disponible y cola pendiente de un cierre anterior).
    sincronizarAhora();
  }

  Future<void> detener() async {
    await _subConectividad?.cancel();
    _reloj?.cancel();
  }

  /// Vacía la cola, respetando el orden FIFO. Devuelve cuántas ops logró
  /// enviar en esta pasada.
  Future<int> sincronizarAhora() async {
    if (_sincronizando) return 0;
    _sincronizando = true;
    var enviadas = 0;
    try {
      while (true) {
        final lote = await _cola.pendientes(limite: 20);
        if (lote.isEmpty) break;
        for (final op in lote) {
          try {
            await _supabase.rpc(op.tipo, params: op.params);
            await _cola.marcarEnviada(op.idDb);
            enviadas++;
          } catch (falla) {
            if (esErrorDeRed(falla)) {
              // Red cortada otra vez: no insistir, dejar en cola y salir.
              return enviadas;
            }
            // Error no-de-red: el backend rechazó algo (RLS, validación,
            // etc). Registramos el intento. Después de 3 intentos lo
            // descartamos para que la cola no quede atascada por una op
            // tóxica (ej: un QR que ya no existe porque el admin lo borró).
            await _cola.marcarIntentoFallido(op.idDb, falla.toString());
            if (op.intentos + 1 >= 3) {
              await _cola.marcarEnviada(op.idDb);
            }
          }
        }
      }
    } finally {
      _sincronizando = false;
    }
    return enviadas;
  }
}
