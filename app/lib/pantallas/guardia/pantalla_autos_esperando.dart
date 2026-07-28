// ============================================================================
// Tomass Seguridad — Pantalla 13 · Autos esperando la barrera
// ============================================================================
// LA PANTALLA MÁS IMPORTANTE DE TODO EL SISTEMA.
//
// Si esta pantalla falla, se hace fila de autos en la entrada del condominio y
// el guardia queda con gente tocando bocina. Todo acá está pensado para eso:
//
//   · La tarjeta aparece SOLA, en menos de un segundo. El servidor avisa; la app
//     no anda preguntando cada dos segundos.
//
//   · El botón ABRIR ACCESO es gigante a propósito. El guardia lo tiene que
//     acertar sin mirar, de noche, con guantes y con un auto esperando.
//
//   · El botón verde es tres veces más ancho que el rojo. El caso normal es
//     dejar pasar; denegar es la excepción y conviene que cueste un poco más
//     apretarlo por error.
//
//   · El contador de segundos sube a la vista. Presiona a no dejar autos
//     esperando, y a los 45 segundos la tarjeta se pone más urgente.
//
//   · La foto del residente está grande para poder compararla con el conductor.
// ============================================================================

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/tema.dart';
import '../../estado/proveedores_guardia.dart';
import '../../modelos/modelos.dart';
import '../../nucleo/errores.dart';
import '../../servicios/servicio_fotos.dart';
import '../comunes/componentes.dart';
import 'acciones_de_turno.dart';

class PantallaAutosEsperando extends ConsumerStatefulWidget {
  const PantallaAutosEsperando({super.key});

  @override
  ConsumerState<PantallaAutosEsperando> createState() => _EstadoAutos();
}

class _EstadoAutos extends ConsumerState<PantallaAutosEsperando> {
  Timer? _relojDeSegundos;

  /// Las solicitudes que se están resolviendo ahora, para no permitir dos
  /// toques seguidos sobre la misma tarjeta.
  final Set<String> _resolviendo = {};

  @override
  void initState() {
    super.initState();
    // Redibuja una vez por segundo para que el contador de espera avance
    _relojDeSegundos = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _relojDeSegundos?.cancel();
    super.dispose();
  }

  Future<void> _resolver(AutoEsperando auto, bool abrir) async {
    if (_resolviendo.contains(auto.solicitudId)) return;

    String? motivo;
    if (!abrir) {
      motivo = await _pedirMotivo(auto);
      if (motivo == null) return; // se arrepintió
    }

    setState(() => _resolviendo.add(auto.solicitudId));
    await HapticFeedback.mediumImpact();

    try {
      await ref.read(servicioGuardiaProvider).resolverAuto(
            solicitudId: auto.solicitudId,
            abrir: abrir,
            motivoSiDeniega: motivo,
          );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            abrir
                ? '✓ ${auto.patente} autorizado. Podés levantar la barrera.'
                : '${auto.patente} denegado.',
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          backgroundColor: abrir ? Colores.verde : Colores.rojo,
          duration: const Duration(seconds: 4),
        ),
      );
    } catch (falla) {
      if (!mounted) return;
      final problema = Traductor.traducir(falla);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(problema.mensaje),
          backgroundColor: Colores.rojo,
          duration: const Duration(seconds: 6),
        ),
      );
    } finally {
      if (mounted) setState(() => _resolviendo.remove(auto.solicitudId));
    }
  }

  /// Denegar exige un motivo. Queda guardado y el residente lo ve, así que el
  /// guardia no tiene que dar explicaciones después.
  Future<String?> _pedirMotivo(AutoEsperando auto) async {
    const motivosComunes = [
      'La persona del auto no coincide con la foto',
      'El auto no coincide con la patente registrada',
      'Vienen más personas de las autorizadas',
      'Problema con la barrera',
    ];

    final controlador = TextEditingController();

    final elegido = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('¿Por qué no dejás pasar el ${auto.patente}?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'El motivo queda registrado y el residente lo va a ver.',
              style: TextStyle(fontSize: 13, color: Colores.textoSuave),
            ),
            const SizedBox(height: 14),
            for (final motivo in motivosComunes)
              Padding(
                padding: const EdgeInsets.only(bottom: 7),
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context, motivo),
                  style: OutlinedButton.styleFrom(
                    alignment: Alignment.centerLeft,
                    minimumSize: const Size.fromHeight(48),
                    padding: const EdgeInsets.symmetric(horizontal: 13),
                    side: const BorderSide(color: Colores.linea),
                    foregroundColor: Colores.texto,
                  ),
                  child: Text(
                    motivo,
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 6),
            TextField(
              controller: controlador,
              decoration: const InputDecoration(
                labelText: 'Otro motivo',
                hintText: 'Escribilo acá',
              ),
              maxLength: 120,
              onSubmitted: (texto) {
                if (texto.trim().isNotEmpty) Navigator.pop(context, texto.trim());
              },
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
              final texto = controlador.text.trim();
              if (texto.isNotEmpty) Navigator.pop(context, texto);
            },
            style: FilledButton.styleFrom(backgroundColor: Colores.rojo),
            child: const Text('Denegar'),
          ),
        ],
      ),
    );

    controlador.dispose();
    return elegido;
  }

  @override
  Widget build(BuildContext context) {
    final cola = ref.watch(colaDeAutosProvider);
    final turno = ref.watch(miTurnoProvider).valueOrNull;
    final hayApurado = ref.watch(hayAutoImpacienteProvider);

    return Scaffold(
      backgroundColor: hayApurado
          ? Colores.naranja.withValues(alpha: 0.06)
          : Colores.fondo,
      appBar: AppBar(
        title: const Text('Autos esperando la barrera'),
        backgroundColor: hayApurado ? Colores.naranjaOscuro : Colores.grafito,
        actions: [
          if (turno != null)
            Center(
              child: Row(
                children: [
                  const _PuntoEnVivo(),
                  const SizedBox(width: 7),
                  Text(
                    turno.puntoAccesoNombre,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          const MenuDelGuardia(),
        ],
      ),
      body: cola.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: Colores.grafito),
        ),
        error: (falla, _) => Padding(
          padding: const EdgeInsets.all(Medidas.margen),
          child: AvisoDeError(
            problema: Traductor.traducir(falla),
            alReintentar: () => ref.invalidate(colaDeAutosProvider),
          ),
        ),
        data: (autos) {
          if (turno == null) {
            return const ListaVacia(
              icono: Icons.badge_outlined,
              titulo: 'Todavía no abriste tu turno',
              explicacion:
                  'Abrí tu turno y elegí el puesto donde estás. Sin eso, los '
                  'avisos de autos no te van a llegar.',
            );
          }

          if (autos.isEmpty) {
            return _SinAutos(puesto: turno.puntoAccesoNombre);
          }

          return ListView.separated(
            padding: const EdgeInsets.all(Medidas.margen),
            itemCount: autos.length,
            separatorBuilder: (_, __) => const SizedBox(height: 14),
            itemBuilder: (context, i) {
              final auto = autos[i];
              return _TarjetaAuto(
                auto: auto,
                // El primero de la fila va grande; los demás compactos, para
                // que entren varios en pantalla sin perder el foco del que
                // llegó primero.
                destacada: i == 0,
                resolviendo: _resolviendo.contains(auto.solicitudId),
                alAbrir: () => _resolver(auto, true),
                alDenegar: () => _resolver(auto, false),
              );
            },
          );
        },
      ),
    );
  }
}

// ============================================================================
// La tarjeta grande del auto
// ============================================================================

class _TarjetaAuto extends StatelessWidget {
  const _TarjetaAuto({
    required this.auto,
    required this.destacada,
    required this.resolviendo,
    required this.alAbrir,
    required this.alDenegar,
  });

  final AutoEsperando auto;
  final bool destacada;
  final bool resolviendo;
  final VoidCallback alAbrir;
  final VoidCallback alDenegar;

  @override
  Widget build(BuildContext context) {
    final apurado = auto.llevaMuchoEsperando;
    final color = apurado ? Colores.rojo : Colores.naranja;

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Medidas.redondeo),
        side: BorderSide(color: color, width: destacada ? 2.5 : 1.5),
      ),
      child: Column(
        children: [
          // ---- Franja de arriba: cuánto lleva esperando ----
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(Medidas.redondeo - 1),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  auto.esEntrada
                      ? Icons.login_rounded
                      : Icons.logout_rounded,
                  size: 16,
                  color: apurado ? Colores.rojoOscuro : Colores.naranjaOscuro,
                ),
                const SizedBox(width: 7),
                Text(
                  auto.esEntrada ? 'QUIERE ENTRAR' : 'QUIERE SALIR',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.9,
                    color: apurado ? Colores.rojoOscuro : Colores.naranjaOscuro,
                  ),
                ),
                const Spacer(),
                Text(
                  _cuantoEspera(auto.segundosEsperando),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: apurado ? Colores.rojoOscuro : Colores.naranjaOscuro,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),

          // ---- El cuerpo: quién es y qué auto ----
          Padding(
            padding: EdgeInsets.all(destacada ? 15 : 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Foto del residente: para comparar con el conductor
                if (auto.residenteFotoRuta != null &&
                    auto.residenteFotoRuta!.isNotEmpty)
                  FotoDelServidor(
                    ruta: auto.residenteFotoRuta,
                    cajon: CajonDeFotos.personas,
                    ancho: destacada ? 84 : 56,
                    alto: destacada ? 84 : 56,
                    redondeo: destacada ? 42 : 28,
                    iconoSiFalta: Icons.person_rounded,
                  )
                else
                  Avatar(
                    iniciales: _iniciales(auto.residente),
                    tamano: destacada ? 84 : 56,
                  ),

                SizedBox(width: destacada ? 15 : 12),

                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        auto.residente,
                        style: TextStyle(
                          fontSize: destacada ? 19 : 15.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.3,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        auto.unidadCompleta != null
                            ? 'Unidad ${auto.unidadCompleta}'
                            : auto.puntoAcceso,
                        style: TextStyle(
                          fontSize: destacada ? 14 : 12.5,
                          color: Colores.textoSuave,
                        ),
                      ),
                      SizedBox(height: destacada ? 12 : 8),

                      // La patente, grande: es lo que el guardia compara
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 11,
                        runSpacing: 7,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 11, vertical: 4),
                            decoration: BoxDecoration(
                              border: Border.all(
                                  color: Colores.texto, width: 2.2),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              auto.patente,
                              style: TextStyle(
                                fontSize: destacada ? 24 : 18,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 2,
                                fontFeatures: const [
                                  FontFeature.tabularFigures()
                                ],
                              ),
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${auto.marca} ${auto.modelo}',
                                style: TextStyle(
                                  fontSize: destacada ? 15 : 13,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                'Color ${auto.color.toLowerCase()}',
                                style: TextStyle(
                                  fontSize: destacada ? 13 : 12,
                                  color: Colores.textoSuave,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // Foto del vehículo, solo en la tarjeta destacada
                if (destacada &&
                    auto.vehiculoFotoRuta != null &&
                    auto.vehiculoFotoRuta!.isNotEmpty) ...[
                  const SizedBox(width: 12),
                  FotoDelServidor(
                    ruta: auto.vehiculoFotoRuta,
                    cajon: CajonDeFotos.vehiculos,
                    ancho: 118,
                    alto: 84,
                    iconoSiFalta: Icons.directions_car_outlined,
                  ),
                ],
              ],
            ),
          ),

          // ---- Los botones ----
          Padding(
            padding: EdgeInsets.fromLTRB(
                destacada ? 15 : 12, 0, destacada ? 15 : 12, destacada ? 15 : 12),
            child: resolviendo
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 18),
                    child: Center(
                      child: CircularProgressIndicator(color: Colores.grafito),
                    ),
                  )
                : Row(
                    children: [
                      // Verde tres veces más ancho: el caso normal es dejar pasar
                      Expanded(
                        flex: 3,
                        child: ElevatedButton.icon(
                          onPressed: alAbrir,
                          icon: Icon(Icons.check_rounded,
                              size: destacada ? 26 : 21),
                          label: Text(
                            'ABRIR ACCESO',
                            style: TextStyle(
                              fontSize: destacada ? 18 : 15,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.5,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colores.verde,
                            minimumSize: Size.fromHeight(
                              destacada
                                  ? Medidas.altoBotonGigante
                                  : Medidas.altoBoton,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        flex: 1,
                        child: OutlinedButton(
                          onPressed: alDenegar,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colores.rojo,
                            side: const BorderSide(
                                color: Colores.rojo, width: 1.8),
                            minimumSize: Size.fromHeight(
                              destacada
                                  ? Medidas.altoBotonGigante
                                  : Medidas.altoBoton,
                            ),
                          ),
                          child: Text(
                            'DENEGAR',
                            style: TextStyle(
                              fontSize: destacada ? 15 : 13,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  static String _cuantoEspera(int segundos) {
    if (segundos < 60) return 'hace $segundos s';
    final minutos = segundos ~/ 60;
    final resto = segundos % 60;
    return 'hace $minutos min $resto s';
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

// ============================================================================
// Cuando no hay nadie esperando
// ============================================================================
// Se muestra en verde y con calma, a propósito: el estado normal de esta
// pantalla es estar vacía, y el guardia tiene que poder confirmar de un vistazo
// que está todo tranquilo y que la app está funcionando.
// ============================================================================

class _SinAutos extends StatelessWidget {
  const _SinAutos({required this.puesto});

  final String puesto;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                color: Colores.verde.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_rounded,
                  size: 42, color: Colores.verde),
            ),
            const SizedBox(height: 20),
            const Text(
              'No hay autos esperando',
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w700,
                color: Colores.texto,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Cuando llegue uno a $puesto, va a aparecer acá al instante '
              'y te va a sonar el celular.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13.5,
                height: 1.5,
                color: Colores.textoSuave,
              ),
            ),
            const SizedBox(height: 22),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const _PuntoEnVivo(color: Colores.verde),
                const SizedBox(width: 8),
                Text(
                  'Conectado y escuchando',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: Colores.verde,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// El puntito que late, para que el guardia sepa que la app está conectada.
/// Si esto se apagara, sabría que dejó de recibir avisos.
class _PuntoEnVivo extends StatefulWidget {
  const _PuntoEnVivo({this.color = Colors.white});

  final Color color;

  @override
  State<_PuntoEnVivo> createState() => _EstadoPunto();
}

class _EstadoPunto extends State<_PuntoEnVivo>
    with SingleTickerProviderStateMixin {
  late final AnimationController _control = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _control.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: 0.35, end: 1).animate(_control),
      child: Container(
        width: 9,
        height: 9,
        decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
      ),
    );
  }
}
