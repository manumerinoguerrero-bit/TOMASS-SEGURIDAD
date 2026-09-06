// ============================================================================
// Tomass Seguridad — Panel · El informe de rondas
// ============================================================================
// ES EL INFORME QUE SE LE MUESTRA AL CLIENTE.
//
// Hoy un condominio le paga a una empresa de seguridad por rondas nocturnas y
// no tiene NINGUNA forma de saber si se hicieron. Esta pantalla contesta las
// tres preguntas que importan:
//
//   ¿Cuántas rondas hizo?
//   ¿Se pasó de las 2 horas que exige el contrato de trabajo?
//   ¿Marcó los sectores estando ahí, o desde lejos?
//
// SOBRE "MARCÓ DESDE LEJOS": ES UNA SEÑAL, NO UNA ACUSACIÓN
//
//   El GPS falla bajo techo, entre paredes gruesas o con mala señal. Un guardia
//   honesto puede aparecer marcado. Por eso se muestra en naranja y no en rojo,
//   y dice "conviene mirar" en vez de "hizo trampa".
//
//   La decisión es de una persona, mirando el conjunto: una marca lejana suelta
//   no dice nada; el mismo sector marcado desde lejos seis noches seguidas, sí.
//
//   Acusar a alguien que hizo bien su trabajo es la forma más rápida de que el
//   guardia deje de usar el sistema, y ahí se pierde todo.
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';

import '../../config/tema.dart';
import '../../estado/proveedores.dart';
import '../../estado/proveedores_admin.dart';
import '../../modelos/admin.dart';
import '../../nucleo/errores.dart';
import '../../nucleo/formato.dart';
import '../../servicios/informe_pdf.dart';
import '../comunes/componentes.dart';

class PestanaRondas extends ConsumerStatefulWidget {
  const PestanaRondas({super.key});

  @override
  ConsumerState<PestanaRondas> createState() => _EstadoPestanaRondas();
}

class _EstadoPestanaRondas extends ConsumerState<PestanaRondas> {
  bool _armandoPdf = false;

  /// Rango personalizado elegido con date+time pickers. Si no está null,
  /// pisa al filtro de días. Sirve para responder a carabineros/mandante
  /// con "las rondas de la noche del 15 al 16 de marzo entre 22:00 y 06:00".
  DateTimeRange? _rangoPersonalizado;
  TimeOfDay? _horaDesde;
  TimeOfDay? _horaHasta;

  Future<void> _elegirRango() async {
    final ahora = DateTime.now();
    final rango = await showDateRangePicker(
      context: context,
      firstDate: ahora.subtract(const Duration(days: 365)),
      lastDate: ahora,
      initialDateRange: _rangoPersonalizado ??
          DateTimeRange(
            start: ahora.subtract(const Duration(days: 7)),
            end: ahora,
          ),
      locale: const Locale('es', 'CL'),
      helpText: 'Elegí el rango de días',
      cancelText: 'Cancelar',
      confirmText: 'Siguiente',
      saveText: 'Aplicar',
    );
    if (rango == null || !mounted) return;

    // Después de elegir los días, pedir horas (opcional).
    final desde = await showTimePicker(
      context: context,
      initialTime: _horaDesde ?? const TimeOfDay(hour: 0, minute: 0),
      helpText: 'Desde qué hora del primer día',
      cancelText: 'Cancelar',
      confirmText: 'OK',
    );
    if (!mounted) return;
    final hasta = await showTimePicker(
      context: context,
      initialTime: _horaHasta ?? const TimeOfDay(hour: 23, minute: 59),
      helpText: 'Hasta qué hora del último día',
      cancelText: 'Cancelar',
      confirmText: 'OK',
    );
    if (!mounted) return;

    setState(() {
      _rangoPersonalizado = rango;
      _horaDesde = desde;
      _horaHasta = hasta;
    });
  }

  void _limpiarRango() {
    setState(() {
      _rangoPersonalizado = null;
      _horaDesde = null;
      _horaHasta = null;
    });
  }

  ({DateTime desde, DateTime hasta})? get _rangoResuelto {
    if (_rangoPersonalizado == null) return null;
    final r = _rangoPersonalizado!;
    final hd = _horaDesde ?? const TimeOfDay(hour: 0, minute: 0);
    final hh = _horaHasta ?? const TimeOfDay(hour: 23, minute: 59);
    final desde = DateTime(
        r.start.year, r.start.month, r.start.day, hd.hour, hd.minute);
    final hasta = DateTime(
        r.end.year, r.end.month, r.end.day, hh.hour, hh.minute);
    return (desde: desde, hasta: hasta);
  }

  // ==========================================================================
  // EL INFORME PARA EL CLIENTE
  // ==========================================================================
  // Se arma EN EL TELÉFONO, no en el servidor. Así el administrador lo saca
  // parado en la instalación, aunque la señal sea mala, y lo manda por WhatsApp
  // en el momento.
  // ==========================================================================

  Future<void> _sacarPdf() async {
    setState(() => _armandoPdf = true);
    try {
      final servicio = ref.read(servicioAdminProvider);
      final dias = ref.read(diasDelInformeDeRondasProvider);
      final perfil = ref.read(perfilProvider).valueOrNull;
      final rangoP = _rangoResuelto; // null si no hay rango personalizado

      // Los tres pedidos van a la vez: el informe tarda lo que tarda el más
      // lento, y no la suma de los tres.
      final (rondas, marcas, sectores) = await (
        servicio.informeDeRondas(
          dias: dias,
          desde: rangoP?.desde,
          hasta: rangoP?.hasta,
        ),
        servicio.detalleDeRondas(
          dias: dias,
          desde: rangoP?.desde,
          hasta: rangoP?.hasta,
        ),
        servicio.sectoresParaElPlano(),
      ).wait;

      final pdf = await InformeDeRondasPdf.armar(
        instalacion: perfil?.nombreCondominio ?? 'Instalación',
        dias: dias,
        rondas: rondas,
        marcas: marcas,
        sectores: sectores,
        // Lo que exige el contrato de trabajo: una ronda cada 2 horas.
        minutosEntreRondas: 120,
      );

      if (!mounted) return;
      setState(() => _armandoPdf = false);

      // Nombre de archivo: si hay rango personalizado, se pone la fecha
      // en el archivo para que quede claro qué período contiene.
      final nombreArchivo = rangoP == null
          ? 'rondas-${_nombreDeArchivo(perfil?.nombreCondominio)}-${dias}dias.pdf'
          : 'rondas-${_nombreDeArchivo(perfil?.nombreCondominio)}-'
              '${rangoP.desde.toIso8601String().substring(0, 10)}-a-'
              '${rangoP.hasta.toIso8601String().substring(0, 10)}.pdf';

      // Abre la hoja del teléfono para compartir, imprimir o guardar
      await Printing.sharePdf(
        bytes: pdf,
        filename: nombreArchivo,
      );
    } catch (falla) {
      if (!mounted) return;
      setState(() => _armandoPdf = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(Traductor.traducir(falla).mensaje),
          backgroundColor: Colores.rojo,
        ),
      );
    }
  }

  static String _nombreDeArchivo(String? nombre) {
    if (nombre == null || nombre.isEmpty) return 'instalacion';
    return nombre
        .toLowerCase()
        .replaceAll(RegExp('[áàä]'), 'a')
        .replaceAll(RegExp('[éèë]'), 'e')
        .replaceAll(RegExp('[íìï]'), 'i')
        .replaceAll(RegExp('[óòö]'), 'o')
        .replaceAll(RegExp('[úùü]'), 'u')
        .replaceAll('ñ', 'n')
        .replaceAll(RegExp('[^a-z0-9]+'), '-')
        .replaceAll(RegExp('^-|-\$'), '');
  }

  @override
  Widget build(BuildContext context) {
    final rondas = ref.watch(informeDeRondasProvider);
    final dias = ref.watch(diasDelInformeDeRondasProvider);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(Medidas.margen),
          child: Column(
            children: [
              SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 7, label: Text('Semana')),
                  ButtonSegment(value: 30, label: Text('Mes')),
                  ButtonSegment(value: 90, label: Text('3 meses')),
                ],
                selected: {dias},
                onSelectionChanged: _rangoPersonalizado != null
                    ? null
                    : (s) => ref
                        .read(diasDelInformeDeRondasProvider.notifier)
                        .state = s.first,
                showSelectedIcon: false,
              ),
              const SizedBox(height: 8),

              // Rango personalizado — para responder a carabineros o al
              // mandante cuando piden "las rondas del 15 al 16 de marzo
              // entre 22:00 y 06:00". Ver _elegirRango.
              if (_rangoResuelto == null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: _elegirRango,
                    icon: const Icon(Icons.date_range_rounded, size: 18),
                    label: const Text('Elegir rango de fechas y horas'),
                  ),
                )
              else
                _ChipRango(
                  desde: _rangoResuelto!.desde,
                  hasta: _rangoResuelto!.hasta,
                  alCambiar: _elegirRango,
                  alQuitar: _limpiarRango,
                ),

              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _armandoPdf ? null : _sacarPdf,
                  style: FilledButton.styleFrom(
                    backgroundColor: Colores.grafito,
                    minimumSize: const Size(0, Medidas.altoBoton),
                  ),
                  icon: _armandoPdf
                      ? const SizedBox(
                          width: 19,
                          height: 19,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.picture_as_pdf_rounded, size: 21),
                  label: Text(
                    _armandoPdf
                        ? 'Armando el informe…'
                        : 'Informe en PDF para el cliente',
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: rondas.when(
            loading: () => const Center(
              child: CircularProgressIndicator(color: Colores.grafito),
            ),
            error: (falla, _) => Padding(
              padding: const EdgeInsets.all(Medidas.margen),
              child: AvisoDeError(
                problema: Traductor.traducir(falla),
                alReintentar: () => ref.invalidate(informeDeRondasProvider),
              ),
            ),
            data: (lista) {
              if (lista.isEmpty) {
                return const ListaVacia(
                  icono: Icons.route_outlined,
                  titulo: 'No hay rondas en este período',
                  explicacion:
                      'Las rondas aparecen acá cuando un guardia las hace desde '
                      'la app. Si no hay ninguna, revisá que estén cargados los '
                      'sectores y pegados los carteles.',
                );
              }

              final paraMirar = lista.where((r) => r.hayAlgoQueMirar).length;

              return RefreshIndicator(
                onRefresh: () async => ref.invalidate(informeDeRondasProvider),
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(
                      Medidas.margen, 0, Medidas.margen, Medidas.margen),
                  itemCount: lista.length + 1,
                  itemBuilder: (_, i) {
                    if (i == 0) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text(
                          '${lista.length} '
                          '${lista.length == 1 ? "ronda" : "rondas"}'
                          '${paraMirar > 0 ? " · $paraMirar para mirar" : " · todo en orden"}',
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      );
                    }
                    return _FilaRonda(ronda: lista[i - 1]);
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _FilaRonda extends StatelessWidget {
  const _FilaRonda({required this.ronda});

  final RondaDelInforme ronda;

  @override
  Widget build(BuildContext context) {
    final r = ronda;
    final atencion = r.hayAlgoQueMirar;

    return Card(
      margin: const EdgeInsets.only(bottom: 9),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Medidas.redondeo),
        side: BorderSide(
          color:
              atencion ? Colores.naranja.withValues(alpha: 0.55) : Colores.linea,
          width: atencion ? 1.4 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(13),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  r.completa ? Icons.check_circle_rounded : Icons.route_rounded,
                  size: 20,
                  color: r.completa ? Colores.verdeOscuro : Colores.textoTenue,
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(r.guardia,
                      style: const TextStyle(
                          fontSize: 14.5, fontWeight: FontWeight.w700)),
                ),
                if (r.sigueAbierta)
                  const Etiqueta(texto: 'En curso', tono: TonoEtiqueta.espera)
                else
                  Text('${r.minutos} min',
                      style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: Colores.textoSuave)),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '${Formato.diaYMes(r.inicio)} · ${Formato.hora(r.inicio)}'
              ' · ${r.marcados} de ${r.total} sectores',
              style: const TextStyle(fontSize: 12, color: Colores.textoSuave),
            ),

            if (r.sePasoDelLimite)
              _Alerta(
                icono: Icons.schedule_rounded,
                texto: 'Pasaron ${r.horasDesdeLaAnterior} horas desde la ronda '
                    'anterior. El contrato de trabajo pide una cada 2 horas.',
              ),
            if (r.marcasLejanas > 0)
              _Alerta(
                icono: Icons.location_off_outlined,
                texto: '${r.marcasLejanas} '
                    '${r.marcasLejanas == 1 ? "sector marcado" : "sectores marcados"} '
                    'desde lejos. Puede ser mala señal de GPS: conviene mirar si '
                    'se repite.',
              ),
            if (!r.completa && !r.sigueAbierta)
              _Alerta(
                icono: Icons.remove_circle_outline_rounded,
                texto: 'Quedaron ${r.total - r.marcados} sectores sin marcar.',
              ),

            if (r.notas != null && r.notas!.isNotEmpty) ...[
              const SizedBox(height: 9),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colores.grafito.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(Medidas.redondeoChico),
                ),
                child: Text('Dejó anotado: ${r.notas}',
                    style: const TextStyle(fontSize: 12, height: 1.4)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Alerta extends StatelessWidget {
  const _Alerta({required this.icono, required this.texto});

  final IconData icono;
  final String texto;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icono, size: 16, color: Colores.naranjaOscuro),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              texto,
              style: const TextStyle(
                fontSize: 12,
                height: 1.4,
                fontWeight: FontWeight.w600,
                color: Colores.naranjaOscuro,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// Chip que muestra el rango personalizado elegido, con botones para cambiar
// o quitarlo y volver al filtro de días fijos.
// ============================================================================

class _ChipRango extends StatelessWidget {
  const _ChipRango({
    required this.desde,
    required this.hasta,
    required this.alCambiar,
    required this.alQuitar,
  });

  final DateTime desde;
  final DateTime hasta;
  final VoidCallback alCambiar;
  final VoidCallback alQuitar;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colores.dorado.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: Colores.dorado.withValues(alpha: 0.5), width: 1.2),
      ),
      child: Row(
        children: [
          const Icon(Icons.date_range_rounded,
              size: 17, color: Colores.doradoOscuro),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  "RANGO PERSONALIZADO",
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                    color: Colores.doradoOscuro,
                  ),
                ),
                Text(
                  "${Formato.fecha(desde)} ${Formato.hora(desde)} → "
                  "${Formato.fecha(hasta)} ${Formato.hora(hasta)}",
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: Colores.grafito,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.edit_rounded, size: 18),
            tooltip: "Cambiar",
            onPressed: alCambiar,
            color: Colores.grafito,
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded, size: 18),
            tooltip: "Quitar",
            onPressed: alQuitar,
            color: Colores.rojo,
          ),
        ],
      ),
    );
  }
}
