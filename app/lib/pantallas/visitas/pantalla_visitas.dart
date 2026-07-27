// ============================================================================
// Tomass Seguridad — Pantalla 08 · Visitas
// ============================================================================
// Cubre las dos cosas que el residente necesita hacer con sus visitas:
//
//   1. INVITAR a alguien: llena los datos, la app genera un código de un solo
//      uso, y lo manda por WhatsApp.
//
//   2. RESPONDER a alguien que llegó SIN AVISO: el guardia lo registró y acá
//      aparece arriba, en naranja, esperando que el residente diga sí o no.
//
// LO QUE ESPERA RESPUESTA VA PRIMERO Y RESALTADO
//   Porque hay una persona parada en la garita esperando. Si estuviera mezclado
//   con el historial, el residente lo vería veinte minutos después.
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/tema.dart';
import '../../estado/proveedores.dart';
import '../../modelos/modelos.dart';
import '../../nucleo/errores.dart';
import '../../nucleo/formato.dart';
import '../comunes/componentes.dart';
import 'formulario_visita.dart';
import 'tarjeta_codigo_visita.dart';

class PantallaVisitas extends ConsumerWidget {
  const PantallaVisitas({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final visitas = ref.watch(misVisitasProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Visitas'),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_add_alt_rounded),
            tooltip: 'Invitar a alguien',
            onPressed: () => _abrirFormulario(context),
          ),
        ],
      ),
      body: visitas.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: Colores.grafito),
        ),
        error: (falla, _) => Padding(
          padding: const EdgeInsets.all(Medidas.margen),
          child: AvisoDeError(
            problema: Traductor.traducir(falla),
            alReintentar: () => ref.invalidate(misVisitasProvider),
          ),
        ),
        data: (lista) {
          final esperando =
              lista.where((v) => v.estado.necesitaTuRespuesta).toList();
          final activas = lista.where((v) => v.sePuedeCompartir).toList();
          final pasadas = lista
              .where((v) => !v.estado.necesitaTuRespuesta && !v.sePuedeCompartir)
              .toList();

          if (lista.isEmpty) {
            return ListaVacia(
              icono: Icons.group_outlined,
              titulo: 'Todavía no invitaste a nadie',
              explicacion:
                  'Generá un código para tu visita y mandáselo por WhatsApp. '
                  'Le sirve una sola vez y solo en el horario que elijas.',
              accion: ElevatedButton.icon(
                onPressed: () => _abrirFormulario(context),
                icon: const Icon(Icons.person_add_alt_rounded, size: 20),
                label: const Text('Invitar a alguien'),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(0, Medidas.altoBoton),
                  padding: const EdgeInsets.symmetric(horizontal: 22),
                ),
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(misVisitasProvider),
            child: ListView(
              padding: const EdgeInsets.all(Medidas.margen),
              children: [
                if (esperando.isNotEmpty) ...[
                  const _Titulo(
                    texto: 'Esperando tu respuesta',
                    urgente: true,
                  ),
                  for (final v in esperando)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _TarjetaPorResponder(visita: v),
                    ),
                  const SizedBox(height: 10),
                ],

                if (activas.isNotEmpty) ...[
                  const _Titulo(texto: 'Códigos activos'),
                  for (final v in activas)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _TarjetaActiva(visita: v),
                    ),
                  const SizedBox(height: 10),
                ],

                OutlinedButton.icon(
                  onPressed: () => _abrirFormulario(context),
                  icon: const Icon(Icons.person_add_alt_rounded, size: 20),
                  label: const Text('Invitar a alguien más'),
                ),

                if (pasadas.isNotEmpty) ...[
                  const SizedBox(height: 22),
                  const _Titulo(texto: 'Visitas anteriores'),
                  for (final v in pasadas)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 9),
                      child: _TarjetaPasada(visita: v),
                    ),
                ],
                const SizedBox(height: 24),
              ],
            ),
          );
        },
      ),
    );
  }

  void _abrirFormulario(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const FormularioVisita()),
    );
  }
}

class _Titulo extends StatelessWidget {
  const _Titulo({required this.texto, this.urgente = false});

  final String texto;
  final bool urgente;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        texto.toUpperCase(),
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.1,
          color: urgente ? Colores.naranjaOscuro : Colores.textoSuave,
        ),
      ),
    );
  }
}

// ============================================================================
// Alguien llegó sin aviso: hay que decir sí o no
// ============================================================================

class _TarjetaPorResponder extends ConsumerStatefulWidget {
  const _TarjetaPorResponder({required this.visita});

  final Visita visita;

  @override
  ConsumerState<_TarjetaPorResponder> createState() => _EstadoPorResponder();
}

class _EstadoPorResponder extends ConsumerState<_TarjetaPorResponder> {
  bool _respondiendo = false;

  Future<void> _responder(bool aprobar) async {
    setState(() => _respondiendo = true);
    try {
      await ref.read(servicioResidenteProvider).responderVisita(
            visitaId: widget.visita.id,
            aprobar: aprobar,
          );
      ref.invalidate(misVisitasProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(aprobar
              ? '${widget.visita.nombreVisitante} puede pasar. Ya le avisamos al guardia.'
              : 'Rechazaste la visita. Ya le avisamos al guardia.'),
          backgroundColor: aprobar ? Colores.verde : Colores.grafito,
        ),
      );
    } catch (falla) {
      if (!mounted) return;
      setState(() => _respondiendo = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(Traductor.traducir(falla).mensaje),
          backgroundColor: Colores.rojo,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final v = widget.visita;

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Medidas.redondeo),
        side: const BorderSide(color: Colores.naranja, width: 1.8),
      ),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
            decoration: BoxDecoration(
              color: Colores.naranja.withValues(alpha: 0.13),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(Medidas.redondeo - 1),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.notifications_active_rounded,
                    size: 15, color: Colores.naranjaOscuro),
                const SizedBox(width: 7),
                const Expanded(
                  child: Text(
                    'ALGUIEN TE ESPERA EN LA GARITA',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                      color: Colores.naranjaOscuro,
                    ),
                  ),
                ),
                Text(
                  Formato.haceCuanto(v.creadoEn),
                  style: const TextStyle(
                    fontSize: 11,
                    color: Colores.naranjaOscuro,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(13),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Avatar(iniciales: _iniciales(v.nombreVisitante), tamano: 46),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            v.nombreVisitante,
                            style: const TextStyle(
                              fontSize: 15.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          if (v.cedulaVisitante != null)
                            Text(
                              'Cédula ${v.cedulaVisitante}',
                              style: const TextStyle(
                                fontSize: 12.5,
                                color: Colores.textoSuave,
                              ),
                            ),
                          if (v.patenteVehiculo != null)
                            Text(
                              'Patente ${v.patenteVehiculo}',
                              style: const TextStyle(
                                fontSize: 12.5,
                                color: Colores.textoSuave,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),

                if (v.motivoVisita != null) ...[
                  const SizedBox(height: 11),
                  Text(
                    'Dice que viene por: ${v.motivoVisita}',
                    style: const TextStyle(fontSize: 13, height: 1.4),
                  ),
                ],

                if (v.notaGuardia != null) ...[
                  const SizedBox(height: 11),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colores.grafito.withValues(alpha: 0.05),
                      borderRadius:
                          BorderRadius.circular(Medidas.redondeoChico),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'NOTA DEL GUARDIA',
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          v.notaGuardia!,
                          style: const TextStyle(fontSize: 12.5, height: 1.45),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 14),

                if (_respondiendo)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: CircularProgressIndicator(color: Colores.grafito),
                    ),
                  )
                else
                  Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: ElevatedButton.icon(
                          onPressed: () => _responder(true),
                          icon: const Icon(Icons.check_rounded, size: 20),
                          label: const Text('Dejalo pasar'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colores.verde,
                          ),
                        ),
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        flex: 2,
                        child: OutlinedButton(
                          onPressed: () => _responder(false),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colores.rojo,
                            side: const BorderSide(
                              color: Colores.rojo,
                              width: 1.5,
                            ),
                          ),
                          child: const Text('No pasa'),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// Un código que todavía sirve: se puede ver y compartir
// ============================================================================

class _TarjetaActiva extends ConsumerWidget {
  const _TarjetaActiva({required this.visita});

  final Visita visita;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Medidas.redondeo),
        side: const BorderSide(color: Colores.verde, width: 1.3),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(Medidas.redondeo),
        onTap: () => mostrarCodigoDeVisita(context, ref, visita),
        child: Padding(
          padding: const EdgeInsets.all(13),
          child: Row(
            children: [
              Avatar(iniciales: _iniciales(visita.nombreVisitante), tamano: 44),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      visita.nombreVisitante,
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _cuandoSirve(visita),
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colores.textoSuave,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Etiqueta(
                      texto: visita.estado.nombreVisible,
                      tono: TonoEtiqueta.bueno,
                      icono: Icons.qr_code_2_rounded,
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded,
                  color: Colores.textoTenue),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// Historial
// ============================================================================

class _TarjetaPasada extends StatelessWidget {
  const _TarjetaPasada({required this.visita});

  final Visita visita;

  @override
  Widget build(BuildContext context) {
    final (tono, icono) = switch (visita.estado) {
      EstadoVisita.usada => (TonoEtiqueta.bueno, Icons.login_rounded),
      EstadoVisita.rechazada => (TonoEtiqueta.malo, Icons.block_rounded),
      EstadoVisita.cancelada => (TonoEtiqueta.neutro, Icons.close_rounded),
      _ => (TonoEtiqueta.neutro, Icons.schedule_rounded),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
      decoration: BoxDecoration(
        color: Colores.superficie,
        borderRadius: BorderRadius.circular(Medidas.redondeoChico),
        border: Border.all(color: Colores.linea),
      ),
      child: Row(
        children: [
          Icon(icono, size: 17, color: Colores.textoTenue),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  visita.nombreVisitante,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  visita.usadaEn != null
                      ? 'Ingresó ${Formato.cuandoRelativo(visita.usadaEn!)}'
                      : Formato.cuandoRelativo(visita.creadoEn),
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: Colores.textoSuave,
                  ),
                ),
              ],
            ),
          ),
          Etiqueta(texto: visita.estado.nombreVisible, tono: tono),
        ],
      ),
    );
  }
}

// ============================================================================
// Ayudas
// ============================================================================

String _iniciales(String nombre) {
  final partes = nombre.trim().split(RegExp(r'\s+'));
  if (partes.isEmpty) return '?';
  if (partes.length == 1) {
    return partes.first.substring(0, partes.first.length >= 2 ? 2 : 1).toUpperCase();
  }
  return '${partes[0][0]}${partes[1][0]}'.toUpperCase();
}

String _cuandoSirve(Visita v) {
  final desde = v.validoDesde.toLocal();
  final hasta = v.validoHasta.toLocal();
  final mismoDia = desde.day == hasta.day && desde.month == hasta.month;

  if (mismoDia) {
    return '${Formato.fecha(desde)} de ${Formato.hora(desde)} '
        'a ${Formato.hora(hasta)}';
  }
  return 'Del ${Formato.fecha(desde)} al ${Formato.fecha(hasta)}';
}
