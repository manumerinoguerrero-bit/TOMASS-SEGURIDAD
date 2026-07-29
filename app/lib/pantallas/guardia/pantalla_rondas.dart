// ============================================================================
// Tomass Seguridad — Las rondas del guardia
// ============================================================================
// LO QUE MÁS VALOR TIENE PARA VENDER EL SERVICIO
//
//   Un condominio le paga a una empresa de seguridad por rondas nocturnas y no
//   tiene NINGUNA forma de saber si se hicieron. El guardia dice que sí, y
//   listo. Es la queja más vieja del rubro.
//
//   Con esto el administrador ve al otro día: "recorrió los 6 sectores a las
//   23:15, 01:40 y 04:20". Eso es lo que el cliente quiere saber y hoy nadie le
//   puede demostrar.
//
// POR QUÉ SE ESCANEA UN CARTEL Y NO SE APRIETA UN BOTÓN
//
//   Porque la única forma de demostrar que alguien ESTUVO en un lugar es que
//   haya tenido que ir hasta ahí. Un botón que diga "ya hice la ronda" se
//   aprieta desde la garita sin moverse. Un cartel pegado en el fondo del
//   condominio, no.
//
// CÓMO ESTÁ PENSADA
//
//   Para usarse de noche, caminando, con una mano. Por eso la lista de sectores
//   se ve completa de un vistazo, con un tilde verde en los que ya pasó, y el
//   botón de escanear es enorme y está siempre abajo, al alcance del pulgar.
// ============================================================================

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../config/tema.dart';
import '../../estado/proveedores_guardia.dart';
import '../../modelos/guardia.dart';
import '../../nucleo/errores.dart';
import '../../nucleo/formato.dart';
import '../../nucleo/ubicacion.dart';
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

  Future<void> _escanear() async {
    final codigo = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const _LectorDeCartel()),
    );
    if (codigo == null || !mounted) return;

    setState(() {
      _trabajando = true;
      _problema = null;
    });

    try {
      // Se pide la ubicación pero NO se espera para siempre: si el GPS no
      // contesta en unos segundos, la marca se anota igual sin ella. Un guardia
      // que no puede registrar una ronda que sí hizo deja de usar la app.
      final donde = await Localizador.donde(
        esperaMaxima: const Duration(seconds: 8),
      );

      final r = await ref.read(servicioGuardiaProvider).marcarPuntoDeControl(
            idLocal: _nuevoId(),
            codigoDelCartel: codigo,
            latitud: donde?.latitud,
            longitud: donde?.longitud,
          );
      if (!mounted) return;

      refrescarRonda(ref);
      setState(() => _trabajando = false);

      await HapticFeedback.mediumImpact();
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            r.yaEstaba
                ? '${r.punto} ya lo habías marcado en esta ronda.'
                : '${r.punto} · ${r.marcados} de ${r.total}',
          ),
          backgroundColor: r.yaEstaba ? Colores.naranjaOscuro : Colores.verde,
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (falla) {
      if (!mounted) return;
      setState(() {
        _trabajando = false;
        _problema = Traductor.traducir(falla);
      });
    }
  }

  Future<void> _cerrar(RondaAbierta ronda) async {
    final notas = TextEditingController();
    final faltan = ronda.total - ronda.marcados;

    final confirmado = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Terminar la ronda?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              faltan > 0
                  ? 'Marcaste ${ronda.marcados} de ${ronda.total} sectores. '
                      'Van a quedar $faltan sin marcar, y así va a figurar en el '
                      'informe.'
                  : 'Marcaste los ${ronda.total} sectores. Ronda completa.',
              style: TextStyle(
                fontSize: 13.5,
                height: 1.45,
                fontWeight: faltan > 0 ? FontWeight.w600 : FontWeight.normal,
                color: faltan > 0 ? Colores.naranjaOscuro : Colores.texto,
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: notas,
              maxLines: 3,
              maxLength: 200,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Novedades del recorrido (opcional)',
                hintText: 'Ej: portón del fondo con la luz quemada',
                alignLabelWithHint: true,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Seguir'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colores.grafito),
            child: const Text('Terminar'),
          ),
        ],
      ),
    );

    final texto = notas.text.trim();
    notas.dispose();
    if (confirmado != true || !mounted) return;

    setState(() => _trabajando = true);
    try {
      final (marcados, total, minutos) = await ref
          .read(servicioGuardiaProvider)
          .cerrarRonda(notas: texto.isEmpty ? null : texto);
      if (!mounted) return;

      refrescarRonda(ref);
      setState(() => _trabajando = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Ronda terminada: $marcados de $total sectores '
              'en $minutos ${minutos == 1 ? "minuto" : "minutos"}.'),
          backgroundColor: Colores.grafito,
          duration: const Duration(seconds: 4),
        ),
      );
    } catch (falla) {
      if (!mounted) return;
      setState(() {
        _trabajando = false;
        _problema = Traductor.traducir(falla);
      });
    }
  }

  static String _nuevoId() {
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
  Widget build(BuildContext context) {
    final ronda = ref.watch(miRondaAbiertaProvider).valueOrNull;
    final puntos = ref.watch(puntosDeControlProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Rondas'),
        actions: const [MenuDelGuardia()],
      ),
      body: puntos.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: Colores.grafito),
        ),
        error: (falla, _) => Padding(
          padding: const EdgeInsets.all(Medidas.margen),
          child: AvisoDeError(
            problema: Traductor.traducir(falla),
            alReintentar: () => refrescarRonda(ref),
          ),
        ),
        data: (lista) {
          if (lista.isEmpty) {
            return const ListaVacia(
              icono: Icons.route_outlined,
              titulo: 'Todavía no hay sectores cargados',
              explicacion:
                  'La administración tiene que cargar los sectores del recorrido '
                  'y pegar un cartel en cada uno. Sin eso no se pueden hacer '
                  'rondas registradas.',
            );
          }

          return Column(
            children: [
              if (_problema != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                      Medidas.margen, Medidas.margen, Medidas.margen, 0),
                  child: AvisoDeError(problema: _problema!),
                ),

              // ---- El estado de la ronda ----
              Padding(
                padding: const EdgeInsets.all(Medidas.margen),
                child: ronda == null
                    ? const _SinRonda()
                    : _EnCurso(ronda: ronda),
              ),

              // ---- Los sectores ----
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(
                      Medidas.margen, 0, Medidas.margen, 100),
                  itemCount: lista.length,
                  itemBuilder: (_, i) => _Sector(
                    punto: lista[i],
                    numero: i + 1,
                    hayRonda: ronda != null,
                  ),
                ),
              ),
            ],
          );
        },
      ),

      // ---- El botón grande, siempre al alcance del pulgar ----
      bottomNavigationBar: puntos.valueOrNull == null ||
              puntos.valueOrNull!.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(Medidas.margen),
                child: ronda == null
                    ? FilledButton.icon(
                        onPressed: _trabajando ? null : _empezar,
                        style: FilledButton.styleFrom(
                          backgroundColor: Colores.verde,
                          minimumSize:
                              const Size(double.infinity, Medidas.altoBotonGigante),
                        ),
                        icon: const Icon(Icons.play_arrow_rounded, size: 28),
                        label: const Text('Empezar ronda',
                            style: TextStyle(
                                fontSize: 18, fontWeight: FontWeight.w800)),
                      )
                    : Row(
                        children: [
                          Expanded(
                            flex: 2,
                            child: FilledButton.icon(
                              onPressed: _trabajando ? null : _escanear,
                              style: FilledButton.styleFrom(
                                backgroundColor: Colores.grafito,
                                minimumSize: const Size(0, Medidas.altoBotonGigante),
                              ),
                              icon: const Icon(Icons.qr_code_scanner_rounded,
                                  size: 26),
                              label: const Text('Marcar sector',
                                  style: TextStyle(
                                      fontSize: 16.5,
                                      fontWeight: FontWeight.w800)),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: OutlinedButton(
                              onPressed:
                                  _trabajando ? null : () => _cerrar(ronda),
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size(0, Medidas.altoBotonGigante),
                                foregroundColor: Colores.grafito,
                              ),
                              child: const Text('Terminar',
                                  style: TextStyle(
                                      fontSize: 14.5,
                                      fontWeight: FontWeight.w700)),
                            ),
                          ),
                        ],
                      ),
              ),
            ),
    );
  }
}

// ============================================================================
// EL ESTADO DE LA RONDA
// ============================================================================

class _SinRonda extends StatelessWidget {
  const _SinRonda();

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(Medidas.margen),
        child: Row(
          children: [
            const Icon(Icons.route_outlined, size: 26, color: Colores.textoTenue),
            const SizedBox(width: 13),
            const Expanded(
              child: Text(
                'No tenés ninguna ronda en curso. Tocá "Empezar ronda" y andá '
                'marcando los carteles de cada sector al pasar.',
                style: TextStyle(fontSize: 13, height: 1.45),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EnCurso extends StatelessWidget {
  const _EnCurso({required this.ronda});

  final RondaAbierta ronda;

  @override
  Widget build(BuildContext context) {
    final completa = ronda.estaCompleta;

    return Card(
      margin: EdgeInsets.zero,
      color: (completa ? Colores.verde : Colores.grafito).withValues(alpha: 0.06),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Medidas.redondeo),
        side: BorderSide(
          color: (completa ? Colores.verde : Colores.grafito)
              .withValues(alpha: 0.45),
          width: 1.4,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(Medidas.margen),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  completa
                      ? Icons.check_circle_rounded
                      : Icons.directions_walk_rounded,
                  size: 22,
                  color: completa ? Colores.verdeOscuro : Colores.grafito,
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    completa ? 'Recorrido completo' : 'Ronda en curso',
                    style: TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w800,
                      color: completa ? Colores.verdeOscuro : Colores.grafito,
                    ),
                  ),
                ),
                Text(
                  'Desde ${Formato.hora(ronda.inicio)}',
                  style: const TextStyle(
                      fontSize: 12, color: Colores.textoSuave),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: ronda.avance,
                minHeight: 9,
                backgroundColor: Colores.linea,
                valueColor: AlwaysStoppedAnimation(
                    completa ? Colores.verde : Colores.grafito),
              ),
            ),
            const SizedBox(height: 7),
            Text(
              '${ronda.marcados} de ${ronda.total} sectores marcados',
              style: const TextStyle(
                  fontSize: 12.5, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// UN SECTOR DE LA LISTA
// ============================================================================

class _Sector extends StatelessWidget {
  const _Sector({
    required this.punto,
    required this.numero,
    required this.hayRonda,
  });

  final PuntoControl punto;
  final int numero;
  final bool hayRonda;

  @override
  Widget build(BuildContext context) {
    final listo = punto.yaMarcado;

    return Card(
      margin: const EdgeInsets.only(bottom: 7),
      child: ListTile(
        leading: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: listo
                ? Colores.verde.withValues(alpha: 0.14)
                : Colores.grafito.withValues(alpha: 0.06),
            shape: BoxShape.circle,
          ),
          child: listo
              ? const Icon(Icons.check_rounded,
                  size: 21, color: Colores.verdeOscuro)
              : Center(
                  child: Text(
                    '$numero',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: Colores.textoTenue,
                    ),
                  ),
                ),
        ),
        title: Text(
          punto.nombre,
          style: TextStyle(
            fontSize: 14.5,
            fontWeight: FontWeight.w700,
            color: listo ? Colores.texto : Colores.textoSuave,
          ),
        ),
        subtitle: listo
            ? Text('Marcado a las ${Formato.hora(punto.marcadoEn!)}',
                style: const TextStyle(
                    fontSize: 12, color: Colores.verdeOscuro))
            : Text(
                hayRonda ? 'Falta pasar' : 'Sin marcar',
                style: const TextStyle(fontSize: 12),
              ),
      ),
    );
  }
}

// ============================================================================
// EL LECTOR DEL CARTEL
// ============================================================================
// La cámara a pantalla completa. Lee solo y se apaga en cuanto lee: si no,
// seguiría leyendo el mismo cartel diez veces por segundo.
// ============================================================================

class _LectorDeCartel extends StatefulWidget {
  const _LectorDeCartel();

  @override
  State<_LectorDeCartel> createState() => _EstadoLector();
}

class _EstadoLector extends State<_LectorDeCartel> {
  final _camara = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    facing: CameraFacing.back,
  );

  bool _yaLeyo = false;
  bool _linterna = false;

  @override
  void dispose() {
    _camara.dispose();
    super.dispose();
  }

  void _alDetectar(BarcodeCapture lectura) {
    if (_yaLeyo) return;
    final texto = lectura.barcodes
        .map((b) => b.rawValue)
        .firstWhere((v) => v != null && v.isNotEmpty, orElse: () => null);
    if (texto == null) return;

    _yaLeyo = true;
    _camara.stop();
    HapticFeedback.selectionClick();
    Navigator.of(context).pop(texto);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _camara,
            onDetect: _alDetectar,
            errorBuilder: (context, error, _) => const Center(
              child: Padding(
                padding: EdgeInsets.all(30),
                child: Text(
                  'No se pudo abrir la cámara. Cerrá la app y volvé a abrirla.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white, fontSize: 15),
                ),
              ),
            ),
          ),
          Container(color: Colors.black.withValues(alpha: 0.45)),
          const Center(child: MarcoDeEscaneo(lado: 250)),
          Positioned(
            left: 0,
            right: 0,
            bottom: 60,
            child: Text(
              'Apuntá al cartel del sector',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.92),
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Positioned(
            top: MediaQuery.paddingOf(context).top + 8,
            left: 10,
            right: 10,
            child: Row(
              children: [
                _Redondo(
                  icono: Icons.arrow_back_rounded,
                  alTocar: () => Navigator.of(context).pop(),
                ),
                const Spacer(),
                _Redondo(
                  icono: _linterna
                      ? Icons.flashlight_on_rounded
                      : Icons.flashlight_off_rounded,
                  activo: _linterna,
                  alTocar: () async {
                    await _camara.toggleTorch();
                    setState(() => _linterna = !_linterna);
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Redondo extends StatelessWidget {
  const _Redondo({
    required this.icono,
    required this.alTocar,
    this.activo = false,
  });

  final IconData icono;
  final VoidCallback alTocar;
  final bool activo;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: activo ? Colors.white : Colors.black.withValues(alpha: 0.55),
      shape: const CircleBorder(),
      child: IconButton(
        onPressed: alTocar,
        iconSize: 24,
        padding: const EdgeInsets.all(12),
        icon: Icon(icono, color: activo ? Colores.grafito : Colors.white),
      ),
    );
  }
}
