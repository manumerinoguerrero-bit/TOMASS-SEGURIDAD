// ============================================================================
// Tomass Seguridad — Pantalla 12 · Escáner del guardia
// ============================================================================
// El guardia apunta la cámara a CUALQUIER código y la app se encarga del resto.
//
// UN SOLO ESCÁNER PARA LOS TRES TIPOS DE CÓDIGO
//   El guardia no tiene que elegir "voy a escanear un residente" o "voy a
//   escanear una visita". Apunta y listo. La app distingue sola:
//
//     Código de residente  → es un mensaje firmado, tiene dos puntos adentro
//     Visita o credencial  → es un código simple, sin puntos
//
//   Parece un detalle, pero con gente esperando en la garita, un menú de
//   "¿qué tipo de código vas a escanear?" es un paso de más que nadie quiere dar.
//
// NO HACE FALTA ESCANEAR EL CARTEL DEL MURO
//   La app ya sabe en qué puerta está parado el guardia, porque él la eligió al
//   abrir su turno. Ese dato viaja solo.
// ============================================================================

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../config/tema.dart';
import '../../estado/proveedores.dart';
import '../../estado/proveedores_guardia.dart';
import '../../nucleo/errores.dart';
import '../../servicios/servicio_fotos.dart';
import '../comunes/componentes.dart';

class PantallaEscanerGuardia extends ConsumerStatefulWidget {
  const PantallaEscanerGuardia({super.key});

  @override
  ConsumerState<PantallaEscanerGuardia> createState() => _EstadoEscanerGuardia();
}

class _EstadoEscanerGuardia extends ConsumerState<PantallaEscanerGuardia> {
  final _camara = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    facing: CameraFacing.back,
  );

  bool _procesando = false;
  bool _linterna = false;
  _Veredicto? _resultado;
  ErrorAmigable? _problema;

  @override
  void dispose() {
    _camara.dispose();
    super.dispose();
  }

  /// Un identificador único por escaneo. Si hay que reintentar por mala señal,
  /// el servidor reconoce que es el mismo intento y no lo cuenta dos veces.
  String _nuevoId() {
    final azar = Random.secure();
    String b(int n) => List.generate(
          n,
          (_) => azar.nextInt(256).toRadixString(16).padLeft(2, '0'),
        ).join();
    return '${b(4)}-${b(2)}-4${b(2).substring(1)}-'
        '${(8 + azar.nextInt(4)).toRadixString(16)}${b(2).substring(1)}-${b(6)}';
  }

  Future<void> _alDetectar(BarcodeCapture lectura) async {
    if (_procesando || _resultado != null) return;

    final texto = lectura.barcodes
        .map((b) => b.rawValue)
        .firstWhere((v) => v != null && v.isNotEmpty, orElse: () => null);
    if (texto == null) return;

    setState(() {
      _procesando = true;
      _problema = null;
    });

    await _camara.stop();
    await HapticFeedback.selectionClick();
    await _validar(texto);
  }

  Future<void> _validar(String codigo) async {
    final turno = ref.read(miTurnoProvider).valueOrNull;
    final idLocal = _nuevoId();

    try {
      // Un código de residente es un mensaje firmado: tiene dos puntos adentro.
      // Los de visita y personal de servicio son códigos simples.
      final esDeResidente = '.'.allMatches(codigo).length == 2;

      if (esDeResidente) {
        if (turno?.codigoDelMuro == null) {
          setState(() {
            _problema = const ErrorAmigable(
              'No sabemos en qué puerta estás parado.',
              detalle: 'Cerrá el turno y volvé a abrirlo eligiendo tu puesto.',
              sePuedeReintentar: false,
            );
            _procesando = false;
          });
          return;
        }

        final r = await ref.read(servicioAccesoProvider).validar(
              codigoDelResidente: codigo,
              codigoDelMuro: turno!.codigoDelMuro!,
              idLocal: idLocal,
            );

        if (!mounted) return;
        setState(() {
          _resultado = _Veredicto(
            aprobado: r.aprobado,
            esperando: r.esperaGuardia,
            titulo: r.titulo,
            mensaje: r.mensaje,
            detalle: r.detalle,
            nombre: r.residente,
            unidad: r.unidad,
            patente: r.patente,
            extra: r.descripcionVehiculo,
            tipoPersona: 'Residente',
          );
          _procesando = false;
        });
      } else {
        final m = await ref.read(servicioGuardiaProvider).validarCredencial(
              codigo: codigo,
              idLocal: idLocal,
            );

        if (!mounted) return;
        setState(() {
          _resultado = _Veredicto.desdeCredencial(m);
          _procesando = false;
        });
      }

      await HapticFeedback.heavyImpact();
    } catch (falla) {
      if (!mounted) return;
      setState(() {
        _problema = Traductor.traducir(falla);
        _procesando = false;
      });
    }
  }

  Future<void> _escanearOtro() async {
    setState(() {
      _resultado = null;
      _problema = null;
      _procesando = false;
    });
    await _camara.start();
  }

  @override
  Widget build(BuildContext context) {
    final turno = ref.watch(miTurnoProvider).valueOrNull;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _camara,
            onDetect: _alDetectar,
            errorBuilder: (context, error, _) => _SinCamara(error: error),
          ),

          Container(color: Colors.black.withValues(alpha: 0.45)),

          // ---- El marco y la instrucción ----
          if (_resultado == null)
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
                        const SizedBox(height: 13),
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
                      padding: const EdgeInsets.symmetric(horizontal: 34),
                      child: Column(
                        children: [
                          const Text(
                            'Apuntá a cualquier código',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Residente, visita o credencial de personal. La app '
                            'reconoce sola cuál es.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.6),
                              fontSize: 13,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),

          // ---- Encabezado ----
          Positioned(
            top: MediaQuery.paddingOf(context).top + 8,
            left: 12,
            right: 12,
            child: Row(
              children: [
                if (turno != null)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      turno.puntoAccesoNombre,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                const Spacer(),
                Material(
                  color: _linterna
                      ? Colors.white
                      : Colors.black.withValues(alpha: 0.6),
                  shape: const CircleBorder(),
                  child: IconButton(
                    tooltip: _linterna ? 'Apagar la linterna' : 'Prender la linterna',
                    onPressed: () async {
                      await _camara.toggleTorch();
                      setState(() => _linterna = !_linterna);
                    },
                    icon: Icon(
                      _linterna
                          ? Icons.flashlight_on_rounded
                          : Icons.flashlight_off_rounded,
                      color: _linterna ? Colores.grafito : Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ---- El resultado ----
          if (_resultado != null)
            _PanelVeredicto(
              veredicto: _resultado!,
              alEscanearOtro: _escanearOtro,
            ),

          // ---- Un error ----
          if (_problema != null)
            Positioned(
              left: Medidas.margen,
              right: Medidas.margen,
              bottom: MediaQuery.paddingOf(context).bottom + 20,
              child: AvisoDeError(
                problema: _problema!,
                alReintentar: _escanearOtro,
              ),
            ),
        ],
      ),
    );
  }
}

// ============================================================================
// El veredicto, normalizado
// ============================================================================
// Los residentes y las credenciales vienen del servidor con formatos distintos.
// Acá se los unifica para que la pantalla los muestre igual.
// ============================================================================

class _Veredicto {
  const _Veredicto({
    required this.aprobado,
    required this.titulo,
    required this.mensaje,
    this.esperando = false,
    this.esperandoResidente = false,
    this.detalle,
    this.nombre,
    this.unidad,
    this.patente,
    this.extra,
    this.fotoRuta,
    this.tipoPersona,
    this.telefono,
  });

  final bool aprobado;
  final String titulo;
  final String mensaje;

  /// El auto quedó en la cola esperando que el guardia abra la barrera.
  final bool esperando;

  /// La visita llegó sin aviso y el residente todavía no respondió.
  final bool esperandoResidente;

  final String? detalle;
  final String? nombre;
  final String? unidad;
  final String? patente;
  final String? extra;
  final String? fotoRuta;
  final String? tipoPersona;
  final String? telefono;

  factory _Veredicto.desdeCredencial(Map<String, dynamic> m) {
    final tipo = m['tipo_persona']?.toString();
    return _Veredicto(
      aprobado: m['aprobado'] == true,
      esperandoResidente: m['esperando_residente'] == true,
      titulo: (m['titulo'] ?? (m['aprobado'] == true ? 'AUTORIZADO' : 'DENEGADO'))
          .toString(),
      mensaje: (m['mensaje'] ?? '').toString(),
      detalle: m['detalle']?.toString(),
      nombre: m['nombre']?.toString(),
      unidad: m['unidad']?.toString(),
      patente: m['patente']?.toString(),
      extra: m['oficio']?.toString() ??
          m['motivo']?.toString() ??
          (m['invita'] != null ? 'Visita de ${m['invita']}' : null),
      fotoRuta: m['foto_url']?.toString(),
      telefono: m['telefono']?.toString(),
      tipoPersona: switch (tipo) {
        'visita' => 'Visita',
        'personal_servicio' => 'Personal de servicio',
        _ => null,
      },
    );
  }
}

// ============================================================================
// El panel del resultado
// ============================================================================

class _PanelVeredicto extends StatelessWidget {
  const _PanelVeredicto({
    required this.veredicto,
    required this.alEscanearOtro,
  });

  final _Veredicto veredicto;
  final VoidCallback alEscanearOtro;

  @override
  Widget build(BuildContext context) {
    final v = veredicto;

    // Tres estados posibles, no dos: verde pasa, rojo no pasa, y gris cuando
    // hay que esperar al residente. Mezclar "esperá" con "denegado" haría que
    // el guardia le diga a alguien que no puede entrar cuando en realidad sí.
    final (fondo, icono) = v.esperandoResidente
        ? (Colores.grafito, Icons.hourglass_top_rounded)
        : v.aprobado
            ? (Colores.verde, Icons.check_rounded)
            : (Colores.rojo, Icons.close_rounded);

    return Container(
      color: Colors.black.withValues(alpha: 0.55),
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(18),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Card(
                clipBehavior: Clip.antiAlias,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // ---- Franja de color con el veredicto ----
                    Container(
                      width: double.infinity,
                      color: fondo,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 18, vertical: 20),
                      child: Column(
                        children: [
                          Icon(icono, size: 46, color: Colors.white),
                          const SizedBox(height: 10),
                          Text(
                            v.titulo,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              height: 1.15,
                              letterSpacing: -0.3,
                            ),
                          ),
                        ],
                      ),
                    ),

                    // ---- Quién es ----
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          if (v.nombre != null) ...[
                            Row(
                              children: [
                                if (v.fotoRuta != null && v.fotoRuta!.isNotEmpty)
                                  FotoDelServidor(
                                    ruta: v.fotoRuta,
                                    cajon: CajonDeFotos.personas,
                                    ancho: 64,
                                    alto: 64,
                                    redondeo: 32,
                                    iconoSiFalta: Icons.person_rounded,
                                  )
                                else
                                  Avatar(
                                    iniciales: _iniciales(v.nombre!),
                                    tamano: 64,
                                  ),
                                const SizedBox(width: 13),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        v.nombre!,
                                        style: const TextStyle(
                                          fontSize: 17,
                                          fontWeight: FontWeight.w800,
                                          height: 1.2,
                                        ),
                                      ),
                                      if (v.tipoPersona != null ||
                                          v.unidad != null) ...[
                                        const SizedBox(height: 3),
                                        Text(
                                          [
                                            if (v.tipoPersona != null)
                                              v.tipoPersona!,
                                            if (v.unidad != null)
                                              'unidad ${v.unidad}',
                                          ].join(' · '),
                                          style: const TextStyle(
                                            fontSize: 13,
                                            color: Colores.textoSuave,
                                          ),
                                        ),
                                      ],
                                      if (v.extra != null) ...[
                                        const SizedBox(height: 2),
                                        Text(
                                          v.extra!,
                                          style: const TextStyle(
                                            fontSize: 12.5,
                                            color: Colores.textoSuave,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 13),
                          ],

                          if (v.patente != null) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 13, vertical: 6),
                              decoration: BoxDecoration(
                                border:
                                    Border.all(color: Colores.texto, width: 2),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                v.patente!,
                                style: const TextStyle(
                                  fontSize: 21,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 2,
                                  fontFeatures: [FontFeature.tabularFigures()],
                                ),
                              ),
                            ),
                            const SizedBox(height: 13),
                          ],

                          Text(
                            v.mensaje,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 14.5,
                              height: 1.45,
                              fontWeight: FontWeight.w600,
                            ),
                          ),

                          if (v.detalle != null) ...[
                            const SizedBox(height: 11),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(11),
                              decoration: BoxDecoration(
                                color: fondo.withValues(alpha: 0.08),
                                borderRadius:
                                    BorderRadius.circular(Medidas.redondeoChico),
                              ),
                              child: Text(
                                v.detalle!,
                                style: const TextStyle(
                                  fontSize: 13,
                                  height: 1.45,
                                  color: Colores.texto,
                                ),
                              ),
                            ),
                          ],

                          // Si hay que esperar al residente, el guardia puede
                          // llamarlo por teléfono en el momento.
                          if (v.esperandoResidente && v.telefono != null) ...[
                            const SizedBox(height: 11),
                            Row(
                              children: [
                                const Icon(Icons.phone_rounded,
                                    size: 17, color: Colores.textoSuave),
                                const SizedBox(width: 8),
                                Text(
                                  v.telefono!,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ],

                          const SizedBox(height: 18),

                          ElevatedButton.icon(
                            onPressed: alEscanearOtro,
                            icon: const Icon(Icons.qr_code_scanner_rounded,
                                size: 20),
                            label: const Text('Escanear otro'),
                            style: ElevatedButton.styleFrom(
                              minimumSize:
                                  const Size.fromHeight(Medidas.altoBoton),
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
      ),
    );
  }

  static String _iniciales(String nombre) {
    final partes = nombre.trim().split(RegExp(r'\s+'));
    if (partes.isEmpty) return '?';
    if (partes.length == 1) {
      return partes.first
          .substring(0, partes.first.length >= 2 ? 2 : 1)
          .toUpperCase();
    }
    return '${partes[0][0]}${partes[1][0]}'.toUpperCase();
  }
}

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
                sinPermiso
                    ? Icons.no_photography_rounded
                    : Icons.videocam_off_rounded,
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
                    ? 'Sin la cámara no podés escanear códigos. Andá a los '
                        'ajustes del teléfono, buscá Tomass Seguridad y activá '
                        'el permiso de cámara.'
                    : 'Cerrá la app y volvé a abrirla. Si sigue pasando, '
                        'reiniciá el teléfono.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
