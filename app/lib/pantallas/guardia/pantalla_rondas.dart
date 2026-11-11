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
import '../../servicios/vigilante_de_ronda.dart';
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

  /// Última posición del guardia leída del rastreador. null hasta que llega la
  /// primera (o si se perdió la señal). La UI la usa para el pin y las
  /// distancias. OJO: el GPS lo maneja el rastreador, NO esta pantalla — así
  /// la auto-marca recibe fixes rápidos y sigue andando aunque el guardia
  /// cambie de pestaña (auditoría G-01, G-02).
  Position? _miPos;

  StreamSubscription<Position>? _subPos;
  StreamSubscription<MarcaAutomatica>? _subMarcas;
  Timer? _relojSenal;
  VigilanteDeRonda? _vigilante;

  /// Cuándo llegó el último fix. Sirve para detectar que el GPS se quedó mudo
  /// (subterráneo, bajo techo) y avisarle al guardia en vez de dejar un pin
  /// viejo como si fuera bueno.
  DateTime? _ultimoFixEn;
  bool _sinSenal = false;

  static const _silencioQueEsSinSenal = Duration(seconds: 25);

  @override
  void initState() {
    super.initState();
    final rastreador = ref.read(rastreadorGuardiaProvider);
    _vigilante = ref.read(vigilanteDeRondaProvider);

    _subPos = rastreador.posiciones.listen((p) {
      if (!mounted) return;
      // Fix salvaje (triangulación celular): no muevas el pin con eso.
      if (p.accuracy > 150) return;
      setState(() {
        _miPos = p;
        _ultimoFixEn = DateTime.now();
        _sinSenal = false;
      });
    });
    _subMarcas = _vigilante!.marcas.listen(_avisarMarca);
    _vigilante!.resueltos.addListener(_repintar);
    _relojSenal =
        Timer.periodic(const Duration(seconds: 5), (_) => _revisarSenal());

    // Para no arrancar con la pantalla vacía mientras llega el primer fix.
    unawaited(
        rastreador.pedirPosicionAhora(precision: LocationAccuracy.high));
  }

  @override
  void dispose() {
    _subPos?.cancel();
    _subMarcas?.cancel();
    _relojSenal?.cancel();
    _vigilante?.resueltos.removeListener(_repintar);
    super.dispose();
  }

  void _repintar() {
    if (mounted) setState(() {});
  }

  /// Sin fix nuevo en 25 s (en ronda llega uno cada 3 s) = no hay señal. Se
  /// borra el pin para no mostrar una posición vieja como si fuera buena.
  void _revisarSenal() {
    if (!mounted) return;
    final ultimo = _ultimoFixEn;
    final mudo = ultimo == null ||
        DateTime.now().difference(ultimo) > _silencioQueEsSinSenal;
    if (mudo != _sinSenal) {
      setState(() {
        _sinSenal = mudo;
        if (mudo) _miPos = null;
      });
    }
  }

  /// Pide un fix nuevo a demanda (botón "Refrescar GPS"). El rastreador es el
  /// único que habla con el GPS; acá solo le pedimos que fuerce una lectura.
  Future<void> _refrescarGps() async {
    final p = await ref.read(rastreadorGuardiaProvider).pedirPosicionAhora();
    if (p != null || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('No llegó una posición nueva. '
            'Si estás bajo techo, marcá el punto a mano.'),
        backgroundColor: Colores.naranjaOscuro,
      ),
    );
  }

  /// El vigilante marcó un punto solo: avisamos con vibración + toast.
  void _avisarMarca(MarcaAutomatica m) {
    if (!mounted) return;
    unawaited(HapticFeedback.heavyImpact());
    refrescarRonda(ref);
    final r = m.resultado;
    if (r.yaEstaba) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              r.enCola ? Icons.cloud_off_rounded : Icons.check_circle_rounded,
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
                    '${m.punto.nombre.toUpperCase()} · COMPLETADO',
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
        backgroundColor: r.enCola ? Colores.naranjaOscuro : Colores.verdeOscuro,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Set<String> _puntosYaMarcados(List<PuntoControl> puntos) {
    // Lo que trae la query como yaMarcado + lo que el vigilante resolvió en
    // esta sesión aunque el servidor todavía no lo refleje.
    final locales = _vigilante?.resueltos.value ?? const <String>{};
    return {
      for (final p in puntos)
        if (p.yaMarcado || locales.contains(p.id)) p.id,
    };
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

    final ronda = ref.read(miRondaAbiertaProvider).valueOrNull;
    if (ronda == null) return;
    final vigilante = ref.read(vigilanteDeRondaProvider);
    try {
      final r = await ref.read(servicioGuardiaProvider).marcarPuntoManual(
            idLocal: vigilante.idLocalDe(pc.id),
            puntoControlId: pc.id,
            motivo: motivo,
            nombrePunto: pc.nombre,
            rondaId: ronda.id,
            // Evidencia opcional: si el teléfono tenía alguna posición, queda
            // guardada con su precisión para que el admin evalúe la marca.
            latitud: _miPos?.latitude,
            longitud: _miPos?.longitude,
            precisionM: _miPos?.accuracy,
            gpsSimulado: _miPos?.isMocked ?? false,
          );
      if (!mounted) return;
      vigilante.anotarResuelto(pc.id);
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

        // Estado del GPS en vivo + botón para refrescar a demanda. Se repinta
        // solo si el teléfono empieza/deja de entregar una ubicación simulada.
        ValueListenableBuilder<bool>(
          valueListenable: ref.read(rastreadorGuardiaProvider).gpsSimulado,
          builder: (_, simulado, __) => _ChipGps(
            posicion: _miPos,
            alRefrescar: _refrescarGps,
            sinSenal: _sinSenal,
            simulado: simulado,
          ),
        ),

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
                  ? metrosEntre(
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
  const _ChipGps({
    required this.posicion,
    required this.alRefrescar,
    this.sinSenal = false,
    this.simulado = false,
  });

  final Position? posicion;
  final VoidCallback alRefrescar;
  final bool sinSenal;
  final bool simulado;

  @override
  Widget build(BuildContext context) {
    final Color color;
    final IconData icono;
    final String texto;

    if (simulado) {
      color = Colores.rojo;
      icono = Icons.gpp_bad_rounded;
      texto = 'Ubicación simulada: cerrá la app de GPS falso. Queda registrado.';
    } else if (posicion == null) {
      color = sinSenal ? Colores.rojo : Colores.textoSuave;
      icono = Icons.gps_off_rounded;
      texto = sinSenal
          ? 'Sin señal GPS. Si ya estás en el punto, marcalo a mano.'
          : 'Esperando señal GPS…';
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
