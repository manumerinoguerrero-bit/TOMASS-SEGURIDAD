// ============================================================================
// Tomass Seguridad — Pantallas 04 y 05 · Aprobado y denegado
// ============================================================================
// La pantalla completa se pone VERDE o ROJA y el celular vibra.
//
// POR QUÉ OCUPA TODA LA PANTALLA Y CON LETRAS TAN GRANDES
//   El guardia de la caseta tiene que poder confirmar el resultado desde dos
//   metros, de noche, sin bajarse de su silla y sin pedirle el teléfono al
//   residente. Una tarjetita chica no serviría para eso.
//
// LA VIBRACIÓN ES DISTINTA A PROPÓSITO
//   Aprobado  → un toque corto.
//   Denegado  → tres pulsos largos.
//   Así el residente sabe el resultado incluso antes de mirar la pantalla, con
//   el teléfono en la mano y la vista en la barrera.
//
// VUELVE SOLA
//   A los 10 segundos regresa a la pantalla del código. Nadie tiene que
//   acordarse de tocar "volver" con un auto detenido atrás.
// ============================================================================

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:vibration/vibration.dart';

import '../../config/tema.dart';
import '../../estado/proveedores.dart';
import '../../modelos/modelos.dart';
import '../../navegacion/rutas.dart';
import '../../nucleo/formato.dart';

class PantallaResultado extends ConsumerStatefulWidget {
  const PantallaResultado({super.key});

  @override
  ConsumerState<PantallaResultado> createState() => _EstadoResultado();
}

class _EstadoResultado extends ConsumerState<PantallaResultado> {
  static const _segundosParaVolver = 10;

  Timer? _cuentaAtras;
  int _restantes = _segundosParaVolver;

  @override
  void initState() {
    super.initState();
    _vibrar();
    _arrancarCuentaAtras();
  }

  @override
  void dispose() {
    _cuentaAtras?.cancel();
    super.dispose();
  }

  Future<void> _vibrar() async {
    final resultado = ref.read(ultimoResultadoProvider);
    if (resultado == null) return;

    try {
      // En la versión 3 de la librería esto devuelve un sí o no directo,
      // sin el "no sé" que devolvía la versión anterior.
      final puede = await Vibration.hasVibrator();
      if (!puede) {
        // Sin motor de vibración se usa el golpecito del sistema
        await HapticFeedback.heavyImpact();
        return;
      }

      if (resultado.aprobado) {
        await Vibration.vibrate(duration: 180);
      } else {
        // Tres pulsos largos: inconfundible con el de aprobado
        await Vibration.vibrate(pattern: [0, 400, 200, 400, 200, 400]);
      }
    } catch (_) {
      // Si la vibración falla, la pantalla de color alcanza. No es crítico.
    }
  }

  void _arrancarCuentaAtras() {
    _cuentaAtras = Timer.periodic(const Duration(seconds: 1), (reloj) {
      if (!mounted) {
        reloj.cancel();
        return;
      }
      setState(() => _restantes--);
      if (_restantes <= 0) {
        reloj.cancel();
        _volver();
      }
    });
  }

  void _volver() {
    ref.read(ultimoResultadoProvider.notifier).state = null;
    if (mounted) context.go(Rutas.codigo);
  }

  @override
  Widget build(BuildContext context) {
    final resultado = ref.watch(ultimoResultadoProvider);

    // Si se llegó acá sin resultado (por ejemplo al recargar en desarrollo),
    // se vuelve al código en lugar de mostrar una pantalla vacía.
    if (resultado == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.go(Rutas.codigo);
      });
      return const Scaffold(
        backgroundColor: Colores.grafito,
        body: Center(child: CircularProgressIndicator(color: Colors.white)),
      );
    }

    final aprobado = resultado.aprobado;
    final repetido = resultado.repetido;

    // Un escaneo repetido no es un error ni un éxito nuevo: se muestra en
    // grafito para que no se confunda con ninguno de los dos.
    final colores = repetido
        ? [Colores.grafito, Colores.grafitoClaro]
        : aprobado
            ? [Colores.verde, Colores.verdeOscuro]
            : [Colores.rojo, Colores.rojoOscuro];

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: colores.first,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      ),
      child: PopScope(
        // Al apretar "atrás" se limpia el resultado antes de salir
        canPop: false,
        onPopInvokedWithResult: (yaSalio, _) {
          if (!yaSalio) _volver();
        },
        child: Scaffold(
          body: Container(
            width: double.infinity,
            height: double.infinity,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: colores,
              ),
            ),
            child: SafeArea(
              child: Column(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 26, vertical: 20),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const SizedBox(height: 20),
                          _Marca(aprobado: aprobado, repetido: repetido),
                          const SizedBox(height: 22),

                          Text(
                            resultado.titulo,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 30,
                              fontWeight: FontWeight.w800,
                              height: 1.1,
                              letterSpacing: -0.8,
                            ),
                          ),

                          // La patente, grande y en blanco: es el dato que el
                          // guardia compara con el auto que tiene adelante.
                          if (resultado.patente != null) ...[
                            const SizedBox(height: 20),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 20, vertical: 9),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                resultado.patente!,
                                style: const TextStyle(
                                  color: Colores.texto,
                                  fontSize: 30,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 3,
                                  fontFeatures: [FontFeature.tabularFigures()],
                                ),
                              ),
                            ),
                            if (resultado.descripcionVehiculo != null) ...[
                              const SizedBox(height: 8),
                              Text(
                                resultado.descripcionVehiculo!,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ],

                          const SizedBox(height: 20),
                          Text(
                            resultado.mensaje,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.95),
                              fontSize: 15.5,
                              height: 1.45,
                              fontWeight: FontWeight.w600,
                            ),
                          ),

                          if (resultado.detalle != null) ...[
                            const SizedBox(height: 18),
                            Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.16),
                                borderRadius:
                                    BorderRadius.circular(Medidas.redondeo),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.3),
                                ),
                              ),
                              child: Text(
                                resultado.detalle!,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  height: 1.5,
                                ),
                              ),
                            ),
                          ],

                          const SizedBox(height: 24),
                          _Datos(resultado: resultado),
                          const SizedBox(height: 20),
                        ],
                      ),
                    ),
                  ),

                  // Abajo: volver ahora, o esperar a que vuelva sola
                  Padding(
                    padding: const EdgeInsets.fromLTRB(26, 0, 26, 20),
                    child: Column(
                      children: [
                        if (resultado.puedeReintentar)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: OutlinedButton.icon(
                              onPressed: () {
                                ref
                                    .read(ultimoResultadoProvider.notifier)
                                    .state = null;
                                context.go(Rutas.codigo);
                              },
                              icon: const Icon(Icons.refresh_rounded, size: 19),
                              label: const Text('Volver y probar con el código nuevo'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.white,
                                side: BorderSide(
                                  color: Colors.white.withValues(alpha: 0.6),
                                  width: 1.5,
                                ),
                              ),
                            ),
                          ),
                        TextButton(
                          onPressed: _volver,
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.white.withValues(alpha: 0.85),
                            minimumSize: const Size.fromHeight(46),
                          ),
                          child: Text(
                            _restantes > 0
                                ? 'Volver ahora  ·  se cierra en $_restantes'
                                : 'Volver ahora',
                            style: const TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// El círculo grande con el visto o la cruz.
class _Marca extends StatelessWidget {
  const _Marca({required this.aprobado, required this.repetido});

  final bool aprobado;
  final bool repetido;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 116,
      height: 116,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withValues(alpha: 0.2),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.55),
          width: 3,
        ),
      ),
      child: Icon(
        repetido
            ? Icons.done_all_rounded
            : aprobado
                ? Icons.check_rounded
                : Icons.close_rounded,
        size: 64,
        color: Colors.white,
      ),
    );
  }
}

/// Nombre, unidad, puerta y hora. En letra chica: son datos de respaldo, no lo
/// primero que hay que leer.
class _Datos extends StatelessWidget {
  const _Datos({required this.resultado});

  final ResultadoAcceso resultado;

  @override
  Widget build(BuildContext context) {
    final lineas = <String>[
      if (resultado.residente != null) resultado.residente!,
      if (resultado.unidad != null) 'Unidad ${resultado.unidad}',
      if (resultado.puntoAcceso != null) resultado.puntoAcceso!,
      if (resultado.hora != null) Formato.horaConSegundos(resultado.hora!),
    ];

    if (lineas.isEmpty) return const SizedBox.shrink();

    return Column(
      children: [
        Container(
          height: 1,
          margin: const EdgeInsets.only(bottom: 14),
          color: Colors.white.withValues(alpha: 0.22),
        ),
        Text(
          lineas.join('  ·  '),
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.85),
            fontSize: 12.5,
            height: 1.6,
            letterSpacing: 0.2,
          ),
        ),
      ],
    );
  }
}
