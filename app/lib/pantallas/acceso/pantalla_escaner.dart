// ============================================================================
// Tomass Seguridad — Escanear el código del muro
// ============================================================================
// La cámara ocupa toda la pantalla y lee el código sola, sin que el residente
// tenga que apretar nada.
//
// TRES DECISIONES QUE PARECEN CHICAS Y EVITAN PROBLEMAS REALES
//
//   1. Se apaga el lector en cuanto lee un código. Sin eso, la cámara sigue
//      leyendo el mismo cartel diez veces por segundo y mandaría diez pedidos
//      al servidor por un solo escaneo.
//
//   2. El identificador del intento (id_local) se genera UNA vez por escaneo, no
//      por pedido. Así, si se corta el internet y hay que reintentar, el servidor
//      reconoce que es el mismo intento y no lo registra dos veces.
//
//   3. La linterna se puede prender a mano. La entrada vehicular de noche está
//      oscura y el cartel puede no verse.
// ============================================================================

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../config/tema.dart';
import '../../estado/proveedores.dart';
import '../../modelos/modelos.dart';
import '../../navegacion/rutas.dart';
import '../../nucleo/errores.dart';
import '../comunes/componentes.dart';

class PantallaEscaner extends ConsumerStatefulWidget {
  const PantallaEscaner({super.key});

  @override
  ConsumerState<PantallaEscaner> createState() => _EstadoEscaner();
}

class _EstadoEscaner extends ConsumerState<PantallaEscaner> {
  final _camara = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    facing: CameraFacing.back,
  );

  bool _procesando = false;
  bool _linternaPrendida = false;
  ErrorAmigable? _problema;

  /// El identificador de ESTE escaneo. Se genera una sola vez, a propósito.
  late final String _idDelIntento = _generarId();

  static String _generarId() {
    // Un identificador único con formato UUID v4, armado sin dependencias extra
    final azar = Random.secure();
    String bloque(int bytes) => List.generate(
          bytes,
          (_) => azar.nextInt(256).toRadixString(16).padLeft(2, '0'),
        ).join();
    return '${bloque(4)}-${bloque(2)}-4${bloque(2).substring(1)}-'
        '${(8 + azar.nextInt(4)).toRadixString(16)}${bloque(2).substring(1)}-'
        '${bloque(6)}';
  }

  @override
  void dispose() {
    _camara.dispose();
    super.dispose();
  }

  Future<void> _alDetectar(BarcodeCapture lectura) async {
    if (_procesando) return;

    final texto = lectura.barcodes
        .map((b) => b.rawValue)
        .firstWhere((v) => v != null && v.isNotEmpty, orElse: () => null);

    if (texto == null) return;

    setState(() {
      _procesando = true;
      _problema = null;
    });

    // Se apaga el lector: ya tenemos lo que necesitábamos
    await _camara.stop();
    await HapticFeedback.selectionClick();

    await _validar(texto);
  }

  Future<void> _validar(String codigoDelMuro) async {
    final estadoCodigo = ref.read(controladorCodigoProvider);
    final miCodigo = estadoCodigo.codigo;

    if (miCodigo == null || miCodigo.yaVencio) {
      setState(() {
        _problema = const ErrorAmigable(
          'Tu código se venció mientras escaneabas.',
          detalle: 'Volvé atrás, esperá el código nuevo y escaneá otra vez.',
          sePuedeReintentar: false,
        );
        _procesando = false;
      });
      return;
    }

    try {
      final resultado = await ref.read(servicioAccesoProvider).validar(
            codigoDelResidente: miCodigo.codigo,
            codigoDelMuro: codigoDelMuro,
            idLocal: _idDelIntento,
          );

      if (!mounted) return;

      // El resultado se guarda y la pantalla verde o roja lo lee de ahí
      ref.read(ultimoResultadoProvider.notifier).state = resultado;
      context.pushReplacement(Rutas.resultado);
    } catch (falla) {
      if (!mounted) return;
      setState(() {
        _problema = Traductor.traducir(falla);
        _procesando = false;
      });
    }
  }

  Future<void> _reintentar() async {
    setState(() {
      _problema = null;
      _procesando = false;
    });
    await _camara.start();
  }

  @override
  Widget build(BuildContext context) {
    final tipo = ref.watch(controladorCodigoProvider).tipo;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          fit: StackFit.expand,
          children: [
            MobileScanner(
              controller: _camara,
              onDetect: _alDetectar,
              errorBuilder: (context, error, _) => _SinCamara(error: error),
            ),

            // Oscurece todo menos el centro
            Container(color: Colors.black.withValues(alpha: 0.45)),

            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const MarcoDeEscaneo(lado: 250),
                  const SizedBox(height: 26),
                  if (_procesando)
                    Column(
                      children: [
                        const CircularProgressIndicator(color: Colors.white),
                        const SizedBox(height: 14),
                        Text(
                          'Validando…',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.9),
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    )
                  else
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 36),
                      child: Column(
                        children: [
                          Text(
                            tipo == TipoAcceso.vehicular
                                ? 'Apuntá al código del poste de la barrera'
                                : 'Apuntá al código pegado en el muro',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Se lee solo, no hace falta tocar nada',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.6),
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),

            // Encabezado: volver y linterna
            Positioned(
              top: MediaQuery.paddingOf(context).top + 8,
              left: 10,
              right: 10,
              child: Row(
                children: [
                  _BotonRedondo(
                    icono: Icons.arrow_back_rounded,
                    etiqueta: 'Volver',
                    alTocar: () => context.pop(),
                  ),
                  const Spacer(),
                  _BotonRedondo(
                    icono: _linternaPrendida
                        ? Icons.flashlight_on_rounded
                        : Icons.flashlight_off_rounded,
                    etiqueta: _linternaPrendida
                        ? 'Apagar la linterna'
                        : 'Prender la linterna',
                    activo: _linternaPrendida,
                    alTocar: () async {
                      await _camara.toggleTorch();
                      setState(() => _linternaPrendida = !_linternaPrendida);
                    },
                  ),
                ],
              ),
            ),

            // Si algo falló, el aviso va abajo con el botón de reintentar
            if (_problema != null)
              Positioned(
                left: Medidas.margen,
                right: Medidas.margen,
                bottom: MediaQuery.paddingOf(context).bottom + 20,
                child: AvisoDeError(
                  problema: _problema!,
                  alReintentar: _reintentar,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _BotonRedondo extends StatelessWidget {
  const _BotonRedondo({
    required this.icono,
    required this.etiqueta,
    required this.alTocar,
    this.activo = false,
  });

  final IconData icono;
  final String etiqueta;
  final VoidCallback alTocar;
  final bool activo;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: activo ? Colors.white : Colors.black.withValues(alpha: 0.55),
      shape: const CircleBorder(),
      child: IconButton(
        onPressed: alTocar,
        tooltip: etiqueta,
        iconSize: 24,
        padding: const EdgeInsets.all(12),
        icon: Icon(icono, color: activo ? Colores.grafito : Colors.white),
      ),
    );
  }
}

/// Qué mostrar si no se puede usar la cámara. Casi siempre es porque el
/// residente no dio permiso, así que se le explica cómo darlo.
class _SinCamara extends StatelessWidget {
  const _SinCamara({required this.error});

  final MobileScannerException error;

  @override
  Widget build(BuildContext context) {
    final sinPermiso =
        error.errorCode == MobileScannerErrorCode.permissionDenied;

    return ColoredBox(
      color: Colores.grafito,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(30),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                sinPermiso ? Icons.no_photography_rounded : Icons.videocam_off_rounded,
                size: 44,
                color: Colors.white.withValues(alpha: 0.8),
              ),
              const SizedBox(height: 18),
              Text(
                sinPermiso
                    ? 'La app necesita permiso para usar la cámara'
                    : 'No se pudo abrir la cámara',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                sinPermiso
                    ? 'Sin la cámara no se puede escanear el código de la '
                        'entrada. Andá a los ajustes del teléfono, buscá Tomass '
                        'Seguridad y activá el permiso de cámara.'
                    : 'Cerrá la app y volvé a abrirla. Si sigue pasando, '
                        'reiniciá el teléfono.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 26),
              OutlinedButton(
                onPressed: () => Navigator.of(context).maybePop(),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: BorderSide(color: Colors.white.withValues(alpha: 0.5)),
                ),
                child: const Text('Volver'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
