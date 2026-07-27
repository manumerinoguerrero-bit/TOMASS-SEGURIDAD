// ============================================================================
// Tomass Seguridad — Pantalla 02 y 03 · Mi código de acceso
// ============================================================================
// LA PANTALLA MÁS IMPORTANTE DE LA APP DEL RESIDENTE.
// Es la que se abre al entrar y la única que usa todos los días.
//
// Lo que hace:
//   · Muestra el código QR grande, que se renueva solo cada 60 segundos.
//   · Un interruptor arriba para cambiar entre PEATONAL y VEHICULAR.
//   · Si es vehicular, muestra debajo qué auto va a entrar.
//   · Un botón para abrir la cámara y escanear el código del muro.
//
// DETALLE QUE IMPORTA: cuando la app pasa a segundo plano, deja de pedir
// códigos. Sin eso, pediría uno por minuto toda la noche con el teléfono
// guardado en el bolsillo, gastando batería y datos para nada.
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../config/tema.dart';
import '../../estado/proveedores.dart';
import '../../modelos/modelos.dart';
import '../../navegacion/rutas.dart';
import '../comunes/componentes.dart';

class PantallaCodigo extends ConsumerStatefulWidget {
  const PantallaCodigo({super.key});

  @override
  ConsumerState<PantallaCodigo> createState() => _EstadoCodigoPantalla();
}

class _EstadoCodigoPantalla extends ConsumerState<PantallaCodigo>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState estado) {
    final controlador = ref.read(controladorCodigoProvider.notifier);
    switch (estado) {
      case AppLifecycleState.resumed:
        controlador.reanudar();
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        controlador.pausar();
    }
  }

  @override
  Widget build(BuildContext context) {
    final estado = ref.watch(controladorCodigoProvider);
    final perfil = ref.watch(perfilProvider);
    final aprobados = ref.watch(misVehiculosAprobadosProvider);

    return Scaffold(
      body: Column(
        children: [
          _Encabezado(perfil: perfil, tipoActual: estado.tipo),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async {
                ref.invalidate(misVehiculosProvider);
                await ref.read(controladorCodigoProvider.notifier).renovar();
              },
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(Medidas.margen),
                child: Column(
                  children: [
                    _CuadroDelCodigo(estado: estado),
                    const SizedBox(height: 14),
                    if (estado.tipo == TipoAcceso.vehicular)
                      _TarjetaDelVehiculo(
                        estado: estado,
                        aprobados: aprobados,
                      ),
                    const SizedBox(height: 14),
                    _Instruccion(tipo: estado.tipo),
                    const SizedBox(height: 14),
                    ElevatedButton.icon(
                      onPressed: estado.hayCodigo
                          ? () => context.push(Rutas.escaner)
                          : null,
                      icon: const Icon(Icons.photo_camera_rounded, size: 21),
                      label: Text(
                        estado.tipo == TipoAcceso.vehicular
                            ? 'Escanear QR de la barrera'
                            : 'Escanear QR de la entrada',
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// El encabezado: quién sos, y el interruptor peatonal / vehicular
// ============================================================================

class _Encabezado extends ConsumerWidget {
  const _Encabezado({required this.perfil, required this.tipoActual});

  final AsyncValue<Perfil> perfil;
  final TipoAcceso tipoActual;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final datos = perfil.valueOrNull;

    return Container(
      color: Colores.grafito,
      padding: EdgeInsets.only(
        top: MediaQuery.paddingOf(context).top + 12,
        left: Medidas.margen,
        right: Medidas.margen,
        bottom: 14,
      ),
      child: Column(
        children: [
          Row(
            children: [
              Avatar(
                iniciales: datos?.iniciales ?? '·',
                fotoUrl: datos?.fotoUrl,
                tamano: 42,
                sobreFondoOscuro: true,
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      datos?.nombreCompleto ?? 'Cargando…',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.2,
                      ),
                    ),
                    Text(
                      datos?.unidad != null
                          ? 'Unidad ${datos!.unidad}'
                          : (datos?.nombreCondominio ?? ''),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.7),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _Interruptor(tipoActual: tipoActual),
        ],
      ),
    );
  }
}

class _Interruptor extends ConsumerWidget {
  const _Interruptor({required this.tipoActual});

  final TipoAcceso tipoActual;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Widget mitad(TipoAcceso tipo, IconData icono) {
      final activa = tipo == tipoActual;
      return Expanded(
        child: GestureDetector(
          onTap: activa
              ? null
              : () => ref
                  .read(controladorCodigoProvider.notifier)
                  .cambiarTipo(tipo),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(vertical: 11),
            decoration: BoxDecoration(
              color: activa ? Colors.white : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icono,
                  size: 17,
                  color: activa
                      ? Colores.grafito
                      : Colors.white.withValues(alpha: 0.72),
                ),
                const SizedBox(width: 7),
                Text(
                  tipo.nombreVisible,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                    color: activa
                        ? Colores.grafito
                        : Colors.white.withValues(alpha: 0.72),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(11),
      ),
      child: Row(
        children: [
          mitad(TipoAcceso.peatonal, Icons.directions_walk_rounded),
          mitad(TipoAcceso.vehicular, Icons.directions_car_rounded),
        ],
      ),
    );
  }
}

// ============================================================================
// El cuadro con el código QR y el relojito
// ============================================================================

class _CuadroDelCodigo extends ConsumerWidget {
  const _CuadroDelCodigo({required this.estado});

  final EstadoCodigo estado;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // ---- Hubo un problema al pedir el código ----
    if (estado.error != null && estado.codigo == null) {
      final esperando = estado.segundosDeEspera != null;
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(Medidas.margen),
          child: Column(
            children: [
              Icon(
                esperando
                    ? Icons.hourglass_bottom_rounded
                    : Icons.wifi_off_rounded,
                size: 34,
                color: esperando ? Colores.naranja : Colores.rojo,
              ),
              const SizedBox(height: 12),
              Text(
                estado.error!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: Colores.texto,
                ),
              ),
              if (esperando) ...[
                const SizedBox(height: 6),
                const Text(
                  'El código se renueva solo en cuanto pase la espera.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: Colores.textoSuave),
                ),
              ] else ...[
                const SizedBox(height: 14),
                OutlinedButton.icon(
                  onPressed: () =>
                      ref.read(controladorCodigoProvider.notifier).renovar(),
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('Intentar de nuevo'),
                ),
              ],
            ],
          ),
        ),
      );
    }

    // ---- Todavía no llegó el primer código ----
    if (estado.codigo == null) {
      return Card(
        child: SizedBox(
          height: 300,
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const CircularProgressIndicator(color: Colores.grafito),
                const SizedBox(height: 16),
                Text(
                  'Generando tu código…',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
      );
    }

    // ---- El código, listo para escanear ----
    final codigo = estado.codigo!;
    final apurado = codigo.segundosRestantes <= 10;

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Medidas.redondeo),
        side: BorderSide(
          color: apurado ? Colores.naranja : Colores.linea,
          width: apurado ? 1.6 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          children: [
            // El QR. Nivel de corrección alto para que se lea igual aunque la
            // pantalla esté sucia, rayada o con poco brillo.
            QrImageView(
              data: codigo.codigo,
              version: QrVersions.auto,
              size: 218,
              errorCorrectionLevel: QrErrorCorrectLevel.H,
              backgroundColor: Colors.white,
              eyeStyle: const QrEyeStyle(
                eyeShape: QrEyeShape.square,
                color: Colores.grafito,
              ),
              dataModuleStyle: const QrDataModuleStyle(
                dataModuleShape: QrDataModuleShape.square,
                color: Colores.grafito,
              ),
            ),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                RelojDelCodigo(
                  segundosRestantes: codigo.segundosRestantes,
                  fraccion: codigo.fraccionRestante,
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      codigo.segundosRestantes <= 1
                          ? 'Se está renovando'
                          : 'Expira en ${codigo.segundosRestantes} segundos',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Colores.texto,
                      ),
                    ),
                    const Text(
                      'Se renueva solo',
                      style: TextStyle(fontSize: 12, color: Colores.textoSuave),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// La tarjeta que dice qué auto va a entrar
// ============================================================================

class _TarjetaDelVehiculo extends ConsumerWidget {
  const _TarjetaDelVehiculo({required this.estado, required this.aprobados});

  final EstadoCodigo estado;
  final List<Vehiculo> aprobados;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Si el servidor no dio código vehicular, es porque no tiene auto aprobado.
    // El mensaje del servidor ya explica exactamente por qué, así que se muestra
    // ese en lugar de inventar uno acá.
    if (estado.codigo?.vehiculo == null) {
      if (estado.error != null) return const SizedBox.shrink();
      return const SizedBox.shrink();
    }

    final auto = estado.codigo!.vehiculo!;
    final hayVarios = aprobados.length > 1;

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Medidas.redondeo),
        side: const BorderSide(color: Colores.verde, width: 1.4),
      ),
      child: Padding(
        padding: const EdgeInsets.all(13),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 46,
                  height: 36,
                  decoration: BoxDecoration(
                    color: Colores.verde.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: const Icon(Icons.directions_car_rounded,
                      size: 20, color: Colores.verdeOscuro),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        auto.patente,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.2,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                      Text(
                        auto.descripcion,
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: Colores.textoSuave,
                        ),
                      ),
                    ],
                  ),
                ),
                const Etiqueta(
                  texto: 'Aprobado',
                  tono: TonoEtiqueta.bueno,
                  icono: Icons.check_rounded,
                ),
              ],
            ),
            if (hayVarios) ...[
              const SizedBox(height: 11),
              const Divider(),
              const SizedBox(height: 9),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'ELEGIR OTRO AUTO',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final otro in aprobados)
                    ChoiceChip(
                      label: Text(otro.patente),
                      selected: otro.id == auto.id,
                      onSelected: otro.id == auto.id
                          ? null
                          : (_) => ref
                              .read(controladorCodigoProvider.notifier)
                              .elegirVehiculo(otro.id),
                      selectedColor: Colores.grafito,
                      labelStyle: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: otro.id == auto.id
                            ? Colors.white
                            : Colores.texto,
                      ),
                      side: const BorderSide(color: Colores.linea),
                      showCheckmark: false,
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// La frase que explica qué hacer
// ============================================================================

class _Instruccion extends StatelessWidget {
  const _Instruccion({required this.tipo});

  final TipoAcceso tipo;

  @override
  Widget build(BuildContext context) {
    return Text(
      tipo == TipoAcceso.vehicular
          ? 'Detené el auto antes de la barrera y apuntá la cámara al código '
              'pegado en el poste.'
          : 'Apuntá la cámara al código QR pegado en el muro de la entrada '
              'peatonal.',
      textAlign: TextAlign.center,
      style: const TextStyle(
        fontSize: 13,
        height: 1.45,
        color: Colores.textoSuave,
      ),
    );
  }
}
