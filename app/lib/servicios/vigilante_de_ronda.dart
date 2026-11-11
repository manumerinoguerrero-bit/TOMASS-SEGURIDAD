// ============================================================================
// Tomass Seguridad — Vigilante de geocercas de la ronda
// ============================================================================
// Escucha las posiciones del rastreador y, mientras haya una ronda abierta,
// marca solo cada punto al que el guardia entra. Vive a nivel de provider:
// sigue marcando aunque el guardia cambie de pestaña o apague la pantalla
// (antes la geocerca vivía en el State de la pantalla y moría al salir — G-02).
//
// REGLAS PARA MARCAR
//
//   · El fix tiene menos de 20 segundos.
//   · No viene de una app de GPS falso.
//   · Su precisión es aceptable para el radio de ese punto.
//   · El guardia está dentro del radio Y ese es el punto más cercano de su
//     lista (dos radios solapados no se marcan desde el mismo lugar).
//   · Cada punto se marca una sola vez por ronda (no una por cada fix — G-06).
// ============================================================================

import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../modelos/guardia.dart';
import 'rastreador_guardia.dart';
import 'servicio_guardia.dart';

/// Lo que la pantalla necesita para avisar "COMPLETADO".
class MarcaAutomatica {
  const MarcaAutomatica(this.punto, this.resultado);
  final PuntoControl punto;
  final ResultadoDeMarca resultado;
}

final _rng = Random.secure();

/// UUID v4 para el id_local (mismo generador que tenía pantalla_rondas).
String nuevoIdLocal() {
  String bloque(int bytes) => List.generate(
        bytes,
        (_) => _rng.nextInt(256).toRadixString(16).padLeft(2, '0'),
      ).join();
  return '${bloque(4)}-${bloque(2)}-4${bloque(2).substring(1)}-'
      '${(8 + _rng.nextInt(4)).toRadixString(16)}${bloque(2).substring(1)}-'
      '${bloque(6)}';
}

/// Haversine en metros. Misma fórmula y radio que metros_entre del servidor.
double metrosEntre(double lat1, double lng1, double lat2, double lng2) {
  const r = 6371000.0;
  double rad(double grados) => grados * pi / 180;
  final dLat = rad(lat2 - lat1);
  final dLng = rad(lng2 - lng1);
  final a = pow(sin(dLat / 2), 2) +
      cos(rad(lat1)) * cos(rad(lat2)) * pow(sin(dLng / 2), 2);
  return r * 2 * atan2(sqrt(a), sqrt(1 - a));
}

class VigilanteDeRonda {
  VigilanteDeRonda(this._servicio, this._rastreador);

  final ServicioGuardia _servicio;
  final RastreadorGuardia _rastreador;

  StreamSubscription<Position>? _sub;
  String? _rondaId;
  List<PuntoControl> _puntos = const [];

  final _marcandoAhora = <String>{};
  final _idsLocales = <String, String>{};
  final _noAntesDe = <String, DateTime>{};

  /// Puntos que ya quedaron marcados o guardados en la cola en ESTA ronda,
  /// aunque el servidor todavía no lo refleje. La pantalla los pinta hechos.
  final ValueNotifier<Set<String>> resueltos = ValueNotifier(const {});

  final _marcasCtrl = StreamController<MarcaAutomatica>.broadcast();
  Stream<MarcaAutomatica> get marcas => _marcasCtrl.stream;

  static const _edadMaximaDelFix = Duration(seconds: 20);

  /// Precisión máxima aceptada para auto-marcar ese punto. Entre 20 y 30 m
  /// según su radio.
  static double precisionMaximaPara(PuntoControl pc) =>
      min(30, max(20, pc.metrosDeTolerancia)).toDouble();

  /// El mismo id_local para todos los reintentos de un punto en una ronda:
  /// así ni la cola ni el servidor lo cuentan dos veces.
  String idLocalDe(String puntoId) =>
      _idsLocales.putIfAbsent(puntoId, nuevoIdLocal);

  /// Lo llama el provider cada vez que cambian la ronda o la lista de puntos.
  void actualizar(
      {required String? rondaId, required List<PuntoControl> puntos}) {
    if (rondaId != _rondaId) {
      _rondaId = rondaId;
      _marcandoAhora.clear();
      _idsLocales.clear();
      _noAntesDe.clear();
      resueltos.value = const {};
    }
    _puntos = puntos;

    if (rondaId == null) {
      _sub?.cancel();
      _sub = null;
      return;
    }
    _sub ??= _rastreador.posiciones.listen(_alMoverse);
    final ultima = _rastreador.ultimaPosicion;
    if (ultima != null) _alMoverse(ultima);
  }

  /// La pantalla avisa que marcó un punto a mano (o que quedó en cola).
  void anotarResuelto(String puntoId) {
    resueltos.value = {...resueltos.value, puntoId};
  }

  void detener() {
    _sub?.cancel();
    _sub = null;
    _rondaId = null;
  }

  void _alMoverse(Position p) {
    final rondaId = _rondaId;
    if (rondaId == null || _puntos.isEmpty) return;
    if (p.isMocked) return;
    if (DateTime.now().difference(p.timestamp).abs() > _edadMaximaDelFix) return;

    // El punto más cercano de toda la lista, esté marcado o no.
    PuntoControl? cercano;
    var metrosAlCercano = double.infinity;
    for (final pc in _puntos) {
      if (!pc.tieneUbicacion) continue;
      final m = metrosEntre(p.latitude, p.longitude, pc.latitud!, pc.longitud!);
      if (m < metrosAlCercano) {
        metrosAlCercano = m;
        cercano = pc;
      }
    }
    final pc = cercano;
    if (pc == null) return;
    if (pc.yaMarcado || resueltos.value.contains(pc.id)) return;
    if (_marcandoAhora.contains(pc.id)) return;
    if (metrosAlCercano > pc.metrosDeTolerancia) return;
    if (p.accuracy > precisionMaximaPara(pc)) return;

    final espera = _noAntesDe[pc.id];
    if (espera != null && DateTime.now().isBefore(espera)) return;

    _marcandoAhora.add(pc.id);
    unawaited(_marcar(pc, p, rondaId));
  }

  Future<void> _marcar(PuntoControl pc, Position p, String rondaId) async {
    try {
      final r = await _servicio.marcarPuntoPorGps(
        idLocal: idLocalDe(pc.id),
        puntoControlId: pc.id,
        latitud: p.latitude,
        longitud: p.longitude,
        nombrePunto: pc.nombre,
        rondaId: rondaId,
        precisionM: p.accuracy,
        gpsSimulado: p.isMocked,
        fixTomadoEn: p.timestamp,
      );
      // Si mientras tanto cambió la ronda, este resultado ya no aplica.
      if (_rondaId != rondaId) return;
      anotarResuelto(pc.id);
      if (!r.yaEstaba && !_marcasCtrl.isClosed) {
        _marcasCtrl.add(MarcaAutomatica(pc, r));
      }
    } catch (_) {
      // El servidor la rechazó (lejos, ronda cerrada…). No insistimos con
      // cada fix: esperamos 15 s antes de volver a probar ese punto.
      _noAntesDe[pc.id] = DateTime.now().add(const Duration(seconds: 15));
    } finally {
      _marcandoAhora.remove(pc.id);
    }
  }
}
