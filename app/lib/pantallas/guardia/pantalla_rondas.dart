// ============================================================================
// Tomass Seguridad — Rondas por geocerca GPS
// ============================================================================
// EL CAMBIO QUE VALE ORO PARA EL SERVICIO
//
//   Hasta acá había que pegar carteles con código QR en cada punto y el
//   guardia los escaneaba. Funciona pero los carteles se tapan, se arrancan,
//   se despegan con la humedad. La competencia (Itácora/Bitácora) se movió a
//   geocerca GPS y Manuel confirmó que es el camino.
//
//   Ahora la app sabe dónde están los puntos (lat/lng cargados desde el panel
//   del admin) y qué radio tiene cada uno. Mientras la ronda está abierta la
//   pantalla sigue el GPS del teléfono con stream propio de alta frecuencia y,
//   cuando detecta que el guardia entró al radio de un punto pendiente, lo
//   marca sola. Vibración fuerte + toast = el guardia sabe que quedó
//   registrado y sigue caminando.
//
// EL GPS DE ALTA FRECUENCIA LO MANTIENE SOLO ESTA PANTALLA
//
//   El rastreador general del turno sigue a 3 min para no quemar batería en
//   las 12 horas del turno. Acá, SOLO mientras la pantalla está viva, se abre
//   un stream propio con precisión alta y distanceFilter chico. Al salir de
//   la pantalla el stream se cierra y la batería vuelve a ir despacio.
//
// SIEMPRE HAY UN BOTÓN "MARCAR MANUAL"
//
//   Si el guardia está en el sótano, atrás de una pared gruesa o el GPS
//   simplemente no toma — la app no debe ser una traba. Toca "Marcar manual",
//   escribe el motivo (mín 10 letras) y la marca queda registrada con bandera
//   "manual" en el informe. El admin ve en el PDF cuáles fueron auto y cuáles
//   a mano.
// ============================================================================

import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../../config/tema.dart';
import '../../estado/proveedores_guardia.dart';
import '../../nucleo/capas_mapa.dart';
import '../../modelos/guardia.dart';
import '../../nucleo/errores.dart';
import '../../nucleo/formato.dart';
import '../comunes/componentes.dart';
import 'acciones_de_turno.dart';

class PantallaRondas extends ConsumerStatefulWidget {
  const PantallaRondas({super.key});

  @override
  ConsumerState<PantallaRondas> createState() => _EstadoRondas();
}

class _EstadoRondas extends ConsumerState<PantallaRondas> {
  bool _trabajando = false;
  ErrorAmigable? _problema;

  /// Última posición del guardia leída del stream. null hasta que llega la
  /// primera. La UI la usa para pintar el pin azul y calcular distancias.
  Position? _miPos;

  /// Stream propio de geolocator — solo vive mientras esta pantalla existe.
  /// Al salir o cerrar ronda se cancela y el GPS del teléfono vuelve a su
  /// ritmo normal.
  StreamSubscription<Position>? _subGps;

  /// IDs de los puntos que estamos intentando marcar AHORA — evita que el
  /// mismo update del stream dispare varias RPCs mientras la primera viaja.
  final _marcandoAhora = <String>{};

  /// Formato de la hora del servidor para los toasts. Se reutiliza.
  static final _rng = Random.secure();

  @override
  void initState() {
    super.initState();
    _arrancarGps();
  }

  @override
  void dispose() {
    _subGps?.cancel();
    super.dispose();
  }

  /// Arranca el stream de GPS con alta precisión y distanceFilter chico.
  /// Importante: NO prende foregroundNotificationConfig — ese lo lleva el
  /// rastreador del turno; si lo prendiéramos acá también chocarían.
  ///
  /// Dos cosas para que la posición no quede desfasada 100+ metros como le
  /// pasó a Manuel la primera vez:
  ///
  ///   1) Pedimos UNA posición al arranque con getCurrentPosition. Fuerza
  ///      al Fused Location Provider a darnos una fresca, en vez de que la
  ///      pantalla espere el primer evento del stream (que puede tardar
  ///      30+ s en Android cuando el chip GPS estaba dormido).
  ///
  ///   2) Rechazamos posiciones con precision peor que 50 m: son el GPS
  ///      diciendo "estoy perdido". Si entrara al pin del mapa, el guardia
  ///      vería su punto azul 100 m fuera del lugar real y se confundiría
  ///      — mejor no mostrar nada y que vea "esperando señal".
  Future<void> _arrancarGps() async {
    final permiso = await Geolocator.checkPermission();
    if (permiso == LocationPermission.denied ||
        permiso == LocationPermission.deniedForever) {
      return; // el rastreador del turno ya se encarga de pedir el permiso
    }

    // 1) Fallback INSTANTÁNEO: la última posición conocida del celular, aunque
    //    sea vieja. Es mejor que mostrar nada mientras esperamos el GPS
    //    fresco; el chip arriba va a decir claramente que es imprecisa.
    try {
      final previa = await Geolocator.getLastKnownPosition();
      if (previa != null && mounted) {
        setState(() => _miPos = previa);
      }
    } catch (_) {/* seguimos */}

    // 2) Primera lectura "fresca": pedimos al Fused Location Provider la
    //    mejor que pueda darnos ahora. `accuracy: high` arranca más rápido
    //    que `best` (no exige GPS satelital puro, acepta WiFi/cell).
    try {
      final p = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
      if (mounted) {
        setState(() => _miPos = p);
        if (_esPosicionBuenaParaMarcar(p)) _revisarGeocercas(p);
      }
    } catch (_) {/* seguimos al stream */}

    // 3) Stream permanente: cada ~3 m que camine el guardia llega un update.
    _subGps = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 3,
      ),
    ).listen((p) {
      if (!mounted) return;
      // Descartamos fixes EXTREMADAMENTE malos (precisión > 150 m): esos son
      // el GPS tirando posiciones salvajes de triangulación celular que
      // saltan el pin a 300 m del lugar real y confunden al guardia. Las
      // lecturas razonables (±5 a ±100 m) se muestran igual: el chip de
      // arriba avisa cuánto está errando. Antes de este filtro, Manuel
      // reportaba que el pin "saltaba" mientras él no se movía — este bug
      // se veía en terreno el 08/11/2026 con fixes de hasta 350 m.
      if (p.accuracy > 150) return;
      setState(() => _miPos = p);
      if (_esPosicionBuenaParaMarcar(p)) _revisarGeocercas(p);
    }, onError: (_) {/* el chip pasa a "sin señal" solo */});
  }

  /// Pide al sistema operativo una posición nueva a demanda. Se llama cuando
  /// el guardia toca el botón "Refrescar GPS" de la pantalla: sirve si llegó
  /// al punto y la app todavía no actualizó la posición.
  Future<void> _refrescarGps() async {
    try {
      final p = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.best,
          timeLimit: Duration(seconds: 15),
        ),
      );
      if (mounted) {
        setState(() => _miPos = p);
        if (_esPosicionBuenaParaMarcar(p)) _revisarGeocercas(p);
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No llegó una posición nueva. '
              'Esperá unos segundos y probá otra vez.'),
          backgroundColor: Colores.naranjaOscuro,
        ),
      );
    }
  }

  /// Umbral para la auto-marca: si la precisión del GPS es peor que el radio
  /// de tolerancia del punto, no dispares la RPC — serían marcas falsas. El
  /// pin se sigue mostrando en el mapa; lo que se bloquea es el intento de
  /// marcar automático. Para marcar sí o sí está el botón manual.
  static bool _esPosicionBuenaParaMarcar(Position p) => p.accuracy <= 30;

  // ==========================================================================
  // EL CORAZÓN: cada posición del stream dispara esta función. Revisa si el
  // guardia entró al radio de algún punto todavía pendiente, y si sí, lo
  // marca con la RPC automática.
  // ==========================================================================

  Future<void> _revisarGeocercas(Position p) async {
    final ronda = ref.read(miRondaAbiertaProvider).valueOrNull;
    if (ronda == null) return;

    final puntos = ref.read(puntosDeControlProvider).valueOrNull;
    if (puntos == null || puntos.isEmpty) return;

    final marcados = _puntosYaMarcados(puntos);

    for (final pc in puntos) {
      if (marcados.contains(pc.id)) continue;
      if (_marcandoAhora.contains(pc.id)) continue;
      if (!pc.tieneUbicacion) continue;

      final metros = _distanciaMetros(
        p.latitude,
        p.longitude,
        pc.latitud!,
        pc.longitud!,
      );

      if (metros <= pc.metrosDeTolerancia) {
        _marcandoAhora.add(pc.id);
        unawaited(_marcarPorGps(pc, p));
      }
    }
  }

  Future<void> _marcarPorGps(PuntoControl pc, Position donde) async {
    try {
      final r = await ref.read(servicioGuardiaProvider).marcarPuntoPorGps(
            idLocal: _nuevoId(),
            puntoControlId: pc.id,
            latitud: donde.latitude,
            longitud: donde.longitude,
            nombrePunto: pc.nombre,
          );
      if (!mounted) return;

      unawaited(HapticFeedback.heavyImpact());
      refrescarRonda(ref);

      if (!r.yaEstaba) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(
                  r.enCola
                      ? Icons.cloud_off_rounded
                      : Icons.check_circle_rounded,
                  color: Colors.white,
                  size: 24,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${pc.nombre.toUpperCase()} · COMPLETADO',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.1,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        r.enCola
                            ? 'Se enviará cuando vuelva la señal'
                            : '${r.marcados} de ${r.total}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            backgroundColor:
                r.enCola ? Colores.naranjaOscuro : Colores.verdeOscuro,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (_) {
      // La próxima posición vuelve a intentar: no mostramos error — podría ser
      // una desconexión momentánea o que el guardia salió del radio justo
      // cuando la llamada arrancaba. Mejor silencioso que un toast falso.
    } finally {
      _marcandoAhora.remove(pc.id);
    }
  }

  Set<String> _puntosYaMarcados(List<PuntoControl> puntos) {
    // La lista de puntos del provider trae un flag yaMarcado por cada uno,
    // calculado por la query. Si no viniera, caería al else.
    return {for (final p in puntos) if (p.yaMarcado) p.id};
  }

  // ==========================================================================
  // EMPEZAR y CERRAR ronda
  // ==========================================================================

  Future<void> _empezar() async {
    setState(() {
      _trabajando = true;
      _problema = null;
    });
    try {
      await ref.read(servicioGuardiaProvider).empezarRonda();
      if (!mounted) return;
      refrescarRonda(ref);
      setState(() => _trabajando = false);
    } catch (falla) {
      if (!mounted) return;
      setState(() {
        _trabajando = false;
        _problema = Traductor.traducir(falla);
      });
    }
  }

  Future<void> _cerrar() async {
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Cerrar la ronda?'),
        content: const Text(
          'Vas a dar la ronda por terminada. Se guarda el detalle para el '
          'administrador y después queda armada para la próxima.',
          style: TextStyle(fontSize: 13.5, height: 1.45),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Seguir caminando'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colores.verdeOscuro),
            child: const Text('Cerrar ronda'),
          ),
        ],
      ),
    );
    if (confirmado != true || !mounted) return;

    try {
      final (marcados, total, minutos) =
          await ref.read(servicioGuardiaProvider).cerrarRonda();
      if (!mounted) return;
      refrescarRonda(ref);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Ronda cerrada: $marcados de $total puntos en $minutos min.',
          ),
          backgroundColor: Colores.grafito,
          duration: const Duration(seconds: 4),
        ),
      );
    } catch (falla) {
      if (!mounted) return;
      setState(() => _problema = Traductor.traducir(falla));
    }
  }

  // ==========================================================================
  // MARCAR MANUAL: botón de emergencia por si el GPS no responde
  // ==========================================================================

  Future<void> _marcarManual(PuntoControl pc) async {
    final motivoCtrl = TextEditingController();
    final motivo = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Marcar ${pc.nombre} a mano'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'La marca automática usa tu GPS. Si no te está marcando sola, '
              'podés dejar constancia escrita de que sí pasaste por acá. Queda '
              'registrada como marca manual en el informe.',
              style: TextStyle(fontSize: 13, height: 1.45),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: motivoCtrl,
              autofocus: true,
              maxLines: 3,
              minLines: 2,
              maxLength: 200,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Motivo (obligatorio)',
                hintText: 'Ej: sin señal GPS en el subsuelo',
                alignLabelWithHint: true,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              if (motivoCtrl.text.trim().length < 10) return;
              Navigator.pop(context, motivoCtrl.text.trim());
            },
            style: FilledButton.styleFrom(backgroundColor: Colores.grafito),
            child: const Text('Marcar a mano'),
          ),
        ],
      ),
    );
    motivoCtrl.dispose();
    if (motivo == null || !mounted) return;

    try {
      final r = await ref.read(servicioGuardiaProvider).marcarPuntoManual(
            idLocal: _nuevoId(),
            puntoControlId: pc.id,
            motivo: motivo,
            nombrePunto: pc.nombre,
          );
      if (!mounted) return;
      unawaited(HapticFeedback.mediumImpact());
      refrescarRonda(ref);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            r.enCola
                ? '${pc.nombre} quedó registrado sin conexión. '
                    'Se enviará cuando vuelva la señal.'
                : '${pc.nombre}: marcado a mano. ${r.marcados} de ${r.total}.',
          ),
          backgroundColor:
              r.enCola ? Colores.naranjaOscuro : Colores.verdeOscuro,
        ),
      );
    } catch (falla) {
      if (!mounted) return;
      setState(() => _problema = Traductor.traducir(falla));
    }
  }

  // ==========================================================================
  // BUILD
  // ==========================================================================

  @override
  Widget build(BuildContext context) {
    final ronda = ref.watch(miRondaAbiertaProvider).valueOrNull;
    final puntos = ref.watch(puntosDeControlProvider).valueOrNull ?? const [];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Rondas'),
        actions: const [MenuDelGuardia()],
      ),
      body: ronda == null
          ? _vistaEmpezar(puntos.length)
          : _vistaRondaAbierta(ronda, puntos),
    );
  }

  Widget _vistaEmpezar(int cantidadPuntos) {
    return Padding(
      padding: const EdgeInsets.all(Medidas.margen),
      child: Column(
        children: [
          if (_problema != null) ...[
            AvisoDeError(problema: _problema!),
            const SizedBox(height: 14),
          ],
          const Spacer(),
          const Icon(Icons.route_rounded,
              size: 72, color: Colores.textoTenue),
          const SizedBox(height: 16),
          const Text(
            'Lista para empezar una ronda',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          Text(
            cantidadPuntos == 0
                ? 'Todavía no hay puntos de control configurados en esta '
                    'instalación. Avisale a la administración.'
                : 'Tocá para arrancar. Al pasar cerca de cada uno de los '
                    '$cantidadPuntos puntos, la app los marca sola por GPS.',
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontSize: 13.5, color: Colores.textoSuave, height: 1.5),
          ),
          const SizedBox(height: 32),
          if (cantidadPuntos > 0)
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _trabajando ? null : _empezar,
                style: FilledButton.styleFrom(
                  backgroundColor: Colores.verdeOscuro,
                  minimumSize: const Size(0, Medidas.altoBotonGigante),
                ),
                icon: _trabajando
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.play_arrow_rounded, size: 28),
                label: Text(
                  _trabajando ? 'Abriendo…' : 'Empezar ronda',
                  style:
                      const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
              ),
            ),
          const Spacer(flex: 2),
        ],
      ),
    );
  }

  Widget _vistaRondaAbierta(RondaAbierta ronda, List<PuntoControl> puntos) {
    final marcados = _puntosYaMarcados(puntos);
    final conGps = puntos.where((p) => p.tieneUbicacion).toList();
    final completos = marcados.length;
    final faltan = puntos.length - completos;

    return Column(
      children: [
        // Encabezado con cuenta y tiempo
        Container(
          padding: const EdgeInsets.all(14),
          decoration: const BoxDecoration(
            color: Colores.grafito,
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'RONDA EN CURSO · DESDE ${Formato.hora(ronda.inicio)}',
                      style: TextStyle(
                        fontSize: 11,
                        letterSpacing: 1.1,
                        fontWeight: FontWeight.w700,
                        color: Colors.white.withValues(alpha: 0.75),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$completos de ${puntos.length} puntos · faltan $faltan',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
              TextButton.icon(
                onPressed: _cerrar,
                icon: const Icon(Icons.stop_circle_rounded,
                    color: Colors.white, size: 20),
                label: const Text(
                  'Cerrar ronda',
                  style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
        ),

        // Mapa
        SizedBox(
          height: 260,
          child: _Mapa(
            miPos: _miPos,
            puntos: conGps,
            marcados: marcados,
          ),
        ),

        // Estado del GPS en vivo + botón para refrescar a demanda.
        _ChipGps(posicion: _miPos, alRefrescar: _refrescarGps),

        if (_problema != null) ...[
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: AvisoDeError(problema: _problema!),
          ),
        ],

        // Lista
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.all(14),
            itemCount: puntos.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, i) {
              final pc = puntos[i];
              final marcado = marcados.contains(pc.id);
              final metros = _miPos != null && pc.tieneUbicacion
                  ? _distanciaMetros(
                      _miPos!.latitude,
                      _miPos!.longitude,
                      pc.latitud!,
                      pc.longitud!,
                    )
                  : null;
              return _FilaPunto(
                punto: pc,
                marcado: marcado,
                metros: metros,
                alMarcarManual: () => _marcarManual(pc),
              );
            },
          ),
        ),
      ],
    );
  }

  // ==========================================================================
  // Util: UUID v4 "casero" para el id_local (sin dependencia nueva)
  // ==========================================================================

  static String _nuevoId() {
    String bloque(int bytes) => List.generate(
          bytes,
          (_) => _rng.nextInt(256).toRadixString(16).padLeft(2, '0'),
        ).join();
    return '${bloque(4)}-${bloque(2)}-4${bloque(2).substring(1)}-'
        '${(8 + _rng.nextInt(4)).toRadixString(16)}${bloque(2).substring(1)}-'
        '${bloque(6)}';
  }

  /// Haversine en metros (es lo mismo que usa el backend con metros_entre).
  static double _distanciaMetros(
      double lat1, double lng1, double lat2, double lng2) {
    const r = 6371000.0;
    final dLat = _rad(lat2 - lat1);
    final dLng = _rad(lng2 - lng1);
    final a = pow(sin(dLat / 2), 2) +
        cos(_rad(lat1)) * cos(_rad(lat2)) * pow(sin(dLng / 2), 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return r * c;
  }

  static double _rad(double grados) => grados * pi / 180;
}

// ============================================================================
// EL MAPA: puntos de control dibujados como círculos (verde = marcado, azul
// claro = pendiente) y el guardia como pin azul oscuro.
// ============================================================================

class _Mapa extends StatefulWidget {
  const _Mapa({
    required this.miPos,
    required this.puntos,
    required this.marcados,
  });

  final Position? miPos;
  final List<PuntoControl> puntos;
  final Set<String> marcados;

  @override
  State<_Mapa> createState() => _EstadoMapa();
}

class _EstadoMapa extends State<_Mapa> {
  final _ctl = MapController();
  bool _primerCentrado = false;
  bool _satelital = true; // arranca en satelital — Manuel lo pidió
  bool _siguiendo = true; // modo seguimiento auto del pin del guardia

  @override
  void didUpdateWidget(covariant _Mapa old) {
    super.didUpdateWidget(old);
    if (widget.miPos == null) return;

    // Primera posición: centrar con zoom cómodo para ver el predio.
    if (!_primerCentrado) {
      _primerCentrado = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _ctl.move(
          LatLng(widget.miPos!.latitude, widget.miPos!.longitude),
          17,
        );
      });
      return;
    }

    // Siguientes posiciones: si está en modo seguimiento, el mapa viaja con
    // el guardia (manteniendo el zoom que él tenga ahora). Si el guardia
    // tocó el mapa para mover a mano, _siguiendo se apagó y el mapa se
    // queda quieto hasta que vuelva a tocar el botón de "centrar en mí".
    if (_siguiendo) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _ctl.move(
          LatLng(widget.miPos!.latitude, widget.miPos!.longitude),
          _ctl.camera.zoom,
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Centro por defecto: si no hay posición, usar el primer punto con GPS.
    final LatLng centro = widget.miPos != null
        ? LatLng(widget.miPos!.latitude, widget.miPos!.longitude)
        : widget.puntos.isNotEmpty
            ? LatLng(widget.puntos.first.latitud!, widget.puntos.first.longitud!)
            : const LatLng(-29.95, -71.22); // La Serena por si no hay nada

    return Stack(
      children: [
        FlutterMap(
          mapController: _ctl,
          options: MapOptions(
            initialCenter: centro,
            initialZoom: 17,
            minZoom: 12,
            maxZoom: 19,
            // Si el guardia arrastra o hace pinch-zoom (hasGesture = true),
            // apagamos el seguimiento para no pelearnos con él. Vuelve a
            // activarse cuando toque el botón "centrar en mí" de abajo.
            onPositionChanged: (pos, hasGesture) {
              if (hasGesture && _siguiendo) {
                setState(() => _siguiendo = false);
              }
            },
          ),
          children: [
            ..._tileLayer(),
            ..._capas(),
          ],
        ),
        // Botón toggle para cambiar entre satelital y calles. Arriba a la
        // derecha, estilo "layers" de Google Maps.
        Positioned(
          top: 8,
          right: 8,
          child: Material(
            color: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: const BorderSide(color: Colores.linea),
            ),
            elevation: 2,
            child: InkWell(
              onTap: () => setState(() => _satelital = !_satelital),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _satelital ? Icons.map_outlined : Icons.satellite_alt_rounded,
                      size: 18,
                      color: Colores.grafito,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _satelital ? 'Calles' : 'Satélite',
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        color: Colores.grafito,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        // Botón "centrar en mí" abajo a la derecha. Aparece cuando el guardia
        // movió el mapa a mano y perdió su posición. Mientras está en modo
        // seguimiento (default) no se muestra para no ocupar espacio al dope.
        if (!_siguiendo && widget.miPos != null)
          Positioned(
            bottom: 8,
            right: 8,
            child: Material(
              color: Colores.grafito,
              shape: const CircleBorder(),
              elevation: 3,
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: () {
                  setState(() => _siguiendo = true);
                  _ctl.move(
                    LatLng(widget.miPos!.latitude, widget.miPos!.longitude),
                    _ctl.camera.zoom,
                  );
                },
                child: const Padding(
                  padding: EdgeInsets.all(12),
                  child: Icon(
                    Icons.my_location_rounded,
                    color: Colors.white,
                    size: 22,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// Capas de mosaicos del mapa. Dos variantes, elegibles con el toggle
  /// arriba a la derecha:
  ///
  ///   · Satélite (default): imagen aérea de Esri World Imagery + capas
  ///     de calles y nombres encima. Se ven los techos de los edificios y
  ///     al mismo tiempo los nombres de las calles — como la vista
  ///     "Hybrid" de Google Maps.
  ///
  ///   · Calles: OpenStreetMap, el mapa cartográfico tradicional.
  List<Widget> _tileLayer() => _satelital
      ? CapasMapa.satelitalConCalles()
      : [CapasMapa.calles()];

  /// Marcadores y círculos, extraídos para que _tileLayer() cambie sin
  /// tocar el resto del árbol del mapa.
  List<Widget> _capas() => [
        CircleLayer(
          circles: [
            for (final p in widget.puntos)
              CircleMarker(
                point: LatLng(p.latitud!, p.longitud!),
                radius: p.metrosDeTolerancia.toDouble(),
                useRadiusInMeter: true,
                color: (widget.marcados.contains(p.id)
                        ? Colores.verde
                        : Colores.doradoClaro)
                    .withValues(alpha: 0.30),
                borderColor: widget.marcados.contains(p.id)
                    ? Colores.verdeOscuro
                    : Colores.dorado,
                borderStrokeWidth: 2,
              ),
          ],
        ),
        MarkerLayer(
          markers: [
            if (widget.miPos != null)
              Marker(
                point:
                    LatLng(widget.miPos!.latitude, widget.miPos!.longitude),
                width: 24,
                height: 24,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colores.grafito,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 3),
                    boxShadow: [
                      BoxShadow(
                        color: Colores.grafito.withValues(alpha: 0.5),
                        blurRadius: 10,
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ];
}

// ============================================================================
// CHIP DE ESTADO DEL GPS
// ============================================================================
// Muestra en vivo cuánto está errando el GPS en metros. Verde si < 15 m (el
// guardia puede confiar), naranja si 15-30 m (uso con cuidado), rojo si está
// peor que 30 m. "Esperando señal" si todavía no agarró ninguna lectura.
// ============================================================================

class _ChipGps extends StatelessWidget {
  const _ChipGps({required this.posicion, required this.alRefrescar});

  final Position? posicion;
  final VoidCallback alRefrescar;

  @override
  Widget build(BuildContext context) {
    final Color color;
    final IconData icono;
    final String texto;

    if (posicion == null) {
      color = Colores.textoSuave;
      icono = Icons.gps_off_rounded;
      texto = 'Esperando señal GPS…';
    } else {
      final metros = posicion!.accuracy.round();
      if (metros <= 15) {
        color = Colores.verde;
        icono = Icons.gps_fixed_rounded;
        texto = 'GPS preciso · ±$metros m';
      } else if (metros <= 30) {
        color = Colores.naranjaOscuro;
        icono = Icons.gps_not_fixed_rounded;
        texto = 'GPS medio · ±$metros m';
      } else {
        color = Colores.rojo;
        icono = Icons.gps_off_rounded;
        texto = 'GPS pobre · ±$metros m';
      }
    }

    return Container(
      padding: const EdgeInsets.only(left: 14, right: 6, top: 2, bottom: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        border: Border(
          bottom: BorderSide(color: color.withValues(alpha: 0.3)),
        ),
      ),
      child: Row(
        children: [
          Icon(icono, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              texto,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ),
          IconButton(
            onPressed: alRefrescar,
            icon: const Icon(Icons.refresh_rounded, size: 20),
            color: color,
            tooltip: 'Forzar nueva lectura del GPS',
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// Una fila de la lista
// ============================================================================

class _FilaPunto extends StatelessWidget {
  const _FilaPunto({
    required this.punto,
    required this.marcado,
    required this.metros,
    required this.alMarcarManual,
  });

  final PuntoControl punto;
  final bool marcado;
  final double? metros;
  final VoidCallback alMarcarManual;

  @override
  Widget build(BuildContext context) {
    final color = marcado ? Colores.verde : Colores.dorado;
    return Material(
      color: Colores.superficie,
      borderRadius: BorderRadius.circular(Medidas.redondeo),
      elevation: 0,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(Medidas.redondeo),
          border: Border.all(color: Colores.linea),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(
                marcado
                    ? Icons.check_circle_rounded
                    : Icons.location_on_rounded,
                color: color,
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    punto.nombre,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    marcado
                        ? 'Marcado ✓'
                        : metros == null
                            ? !punto.tieneUbicacion
                                ? 'Sin coordenadas cargadas'
                                : 'Esperando señal GPS…'
                            : 'A ${metros!.round()} m · '
                                'tope ${punto.metrosDeTolerancia} m',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: marcado ? Colores.verdeOscuro : Colores.textoSuave,
                      fontWeight: marcado ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            if (!marcado)
              IconButton(
                tooltip: 'Marcar a mano',
                onPressed: alMarcarManual,
                icon: const Icon(Icons.edit_note_rounded),
                color: Colores.grafito,
              ),
          ],
        ),
      ),
    );
  }
}
