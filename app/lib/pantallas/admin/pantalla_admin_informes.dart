// ============================================================================
// Tomass Seguridad — Panel de administración · Informes
// ============================================================================
// Tres cosas en tres pestañas:
//
//   ACCESOS → quién entró y salió, con fecha y hora. Es lo que se revisa cuando
//             hay un problema, y lo que el administrador lleva a la reunión de
//             copropietarios.
//
//   TURNOS  → qué guardia estuvo a cargo y en qué horario. Sirve para el pago
//             de horas y para saber a quién preguntarle por algo que pasó.
//
//   RONDAS  → si se hicieron los recorridos, cada cuánto, y si se marcaron los
//             sectores estando ahí. Vive en informe_de_rondas.dart. Es el que
//             se le muestra al cliente.
//
// Los registros de acceso no se pueden modificar ni borrar: la base de datos lo
// impide. Por eso sirven como prueba.
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';

import '../../config/tema.dart';
import '../../estado/proveedores.dart';
import '../../estado/proveedores_admin.dart';
import '../../modelos/admin.dart';
import '../../nucleo/errores.dart';
import '../../nucleo/formato.dart';
import '../../servicios/servicio_fotos.dart';
import '../comunes/componentes.dart';
import '../../servicios/informe_incidentes_pdf.dart';
import '../../servicios/informe_ingresos_pdf.dart';
import '../../servicios/informe_turnos_pdf.dart';
import 'acciones_admin.dart';
import 'detalle_novedad.dart';
import 'informe_de_encomiendas.dart';
import 'informe_de_rondas.dart';

class PantallaAdminInformes extends ConsumerWidget {
  const PantallaAdminInformes({super.key, this.tabInicial = 0});

  /// Índice de pestaña con la que abre. 0=Accesos, 1=Turnos, 2=Novedades,
  /// 3=Rondas, 4=Encomiendas. Sirve para que los accesos rápidos del panel
  /// (Ingresos, Encomiendas, Novedades) abran directo la pestaña correcta.
  final int tabInicial;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 5,
      initialIndex: tabInicial.clamp(0, 4),
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Informes'),
          actions: const [MenuDelAdmin()],
          bottom: const TabBar(
            isScrollable: true,
            indicatorColor: Colors.white,
            indicatorWeight: 3,
            labelColor: Colors.white,
            labelStyle: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
            tabs: [
              Tab(text: 'Accesos'),
              Tab(text: 'Turnos'),
              Tab(text: 'Novedades'),
              Tab(text: 'Rondas'),
              Tab(text: 'Encomiendas'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _PestanaAccesos(),
            _PestanaTurnos(),
            _PestanaNovedades(),
            PestanaRondas(),
            PestanaEncomiendas(),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// PESTAÑA 1 · QUIÉN ENTRÓ Y SALIÓ
// ============================================================================

class _PestanaAccesos extends ConsumerStatefulWidget {
  const _PestanaAccesos();

  @override
  ConsumerState<_PestanaAccesos> createState() => _EstadoPestanaAccesos();
}

class _EstadoPestanaAccesos extends ConsumerState<_PestanaAccesos> {
  /// Rango personalizado (día + hora). Cuando está seteado, el PDF sale con
  /// este rango exacto en vez de "últimos N días". La lista sigue mostrando
  /// por días — el rango es para el PDF que se manda a Carabineros/mandante.
  ({DateTime desde, DateTime hasta})? _rango;

  @override
  Widget build(BuildContext context) {
    final movimientos = ref.watch(movimientosAdminProvider);
    final dias = ref.watch(diasAccesosProvider);
    final filtro = ref.watch(filtroAccesosProvider);
    final guardiaFiltrado = ref.watch(filtroGuardiaAccesosProvider);

    return Column(
      children: [
        // ---- Cuánto tiempo hacia atrás ----
        Padding(
          padding: const EdgeInsets.all(Medidas.margen),
          child: Column(
            children: [
              SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 1, label: Text('Hoy')),
                  ButtonSegment(value: 7, label: Text('7 días')),
                  ButtonSegment(value: 30, label: Text('30 días')),
                  ButtonSegment(value: 90, label: Text('3 meses')),
                ],
                selected: {dias},
                // Cuando hay rango personalizado, el segmento queda anulado:
                // sería raro elegir "7 días" y que igual el PDF muestre otro
                // rango. Se ve deshabilitado hasta quitar el rango.
                onSelectionChanged: _rango != null
                    ? null
                    : (s) => ref
                        .read(diasAccesosProvider.notifier)
                        .state = s.first,
                showSelectedIcon: false,
              ),
              const SizedBox(height: 8),
              SelectorRangoPersonalizado(
                rango: _rango,
                alElegir: (r) => setState(() => _rango = r),
                alQuitar: () => setState(() => _rango = null),
              ),
            ],
          ),
        ),

        Expanded(
          child: movimientos.when(
            loading: () => const Center(
              child: CircularProgressIndicator(color: Colores.grafito),
            ),
            error: (falla, _) => Padding(
              padding: const EdgeInsets.all(Medidas.margen),
              child: AvisoDeError(
                problema: Traductor.traducir(falla),
                alReintentar: () => ref.invalidate(movimientosAdminProvider),
              ),
            ),
            data: (lista) {
              if (lista.isEmpty) {
                return const ListaVacia(
                  icono: Icons.history_rounded,
                  titulo: 'No hay accesos en este período',
                  explicacion:
                      'Probá con un período más largo, o esperá a que empiece '
                      'a usarse el sistema.',
                );
              }

              // Aplicar los filtros en memoria. La lista YA viene recortada
              // por días desde el provider; los chips y el dropdown son
              // refinamiento visual (más rápido que ir a la BD).
              Iterable<MovimientoAdmin> filtrada = lista;
              switch (filtro) {
                case FiltroAcceso.todos:
                  break;
                case FiltroAcceso.denegados:
                  filtrada = filtrada.where((m) => !m.aprobado);
                  break;
                case FiltroAcceso.peatonales:
                  filtrada = filtrada.where((m) => !m.esVehicular);
                  break;
                case FiltroAcceso.vehiculares:
                  filtrada = filtrada.where((m) => m.esVehicular);
                  break;
              }
              if (guardiaFiltrado != null) {
                filtrada = filtrada.where((m) => m.guardia == guardiaFiltrado);
              }
              final filtradaList = filtrada.toList();
              final denegados = filtradaList.where((m) => !m.aprobado).length;

              // Guardias distintos que aparecen en el período original (NO
              // filtrados por chip), ordenados alfabéticamente. Si no hay
              // ningún movimiento con guardia asignado, el dropdown no se
              // dibuja.
              final guardias = _guardiasDistintos(lista);

              return RefreshIndicator(
                onRefresh: () async => ref.invalidate(movimientosAdminProvider),
                child: Column(
                  children: [
                    _BarraFiltrosAccesos(guardias: guardias),
                    Expanded(
                      child: filtradaList.isEmpty
                          ? const ListaVacia(
                              icono: Icons.filter_alt_off_rounded,
                              titulo: 'No hay accesos con esos filtros',
                              explicacion:
                                  'Probá quitar el filtro de guardia o el chip '
                                  'de tipo para ver más resultados.',
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.fromLTRB(
                                  Medidas.margen, 0,
                                  Medidas.margen, Medidas.margen),
                              itemCount: filtradaList.length + 2,
                              itemBuilder: (_, i) {
                                if (i == 0) {
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 8),
                                    child: SizedBox(
                                      width: double.infinity,
                                      child: FilledButton.icon(
                                        onPressed: () => _descargarPdfIngresos(
                                            filtradaList, dias),
                                        icon: const Icon(
                                            Icons.picture_as_pdf_rounded,
                                            size: 18),
                                        label: const Text(
                                            'Descargar informe en PDF'),
                                        style: FilledButton.styleFrom(
                                          backgroundColor: Colores.grafito,
                                          minimumSize: const Size(0, 42),
                                        ),
                                      ),
                                    ),
                                  );
                                }
                                if (i == 1) {
                                  return Padding(
                                    padding: const EdgeInsets.only(
                                        bottom: 12, top: 4),
                                    child: Text(
                                      '${filtradaList.length} '
                                      '${filtradaList.length == 1 ? "movimiento" : "movimientos"}'
                                      '${denegados > 0 ? " · $denegados denegado${denegados == 1 ? "" : "s"}" : ""}',
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelSmall,
                                    ),
                                  );
                                }
                                return _FilaAcceso(
                                    movimiento: filtradaList[i - 2]);
                              },
                            ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  /// Lista ordenada alfabéticamente de nombres de guardias que aparecen en
  /// la lista. Null se descarta (movimientos viejos sin guardia asignado).
  List<String> _guardiasDistintos(List<MovimientoAdmin> lista) {
    final s = <String>{};
    for (final m in lista) {
      final g = m.guardia;
      if (g != null && g.isNotEmpty) s.add(g);
    }
    final r = s.toList()..sort();
    return r;
  }

  Future<void> _descargarPdfIngresos(
    List<MovimientoAdmin> lista,
    int dias,
  ) async {
    final perfil = ref.read(perfilProvider).valueOrNull;
    final instalacion = perfil?.nombreCondominio ?? 'Instalación';

    // Si hay rango personalizado, el PDF sale con EXACTAMENTE ese período
    // (día + hora inicio a día + hora fin). Si no, sale con "últimos N días".
    final rango = _rango;
    final desde =
        rango?.desde ?? DateTime.now().subtract(Duration(days: dias));
    final hasta = rango?.hasta ?? DateTime.now();

    try {
      // Con rango personalizado hay que pedir la lista de nuevo al servicio,
      // porque la lista del provider está filtrada por días — puede no cubrir
      // el rango elegido, o traer días de más.
      final movimientos = rango == null
          ? lista
          : await ref
              .read(servicioAdminProvider)
              .movimientos(desde: desde, hasta: hasta);

      final bytes = await InformeDeIngresosPdf.armar(
        instalacion: instalacion,
        desde: desde,
        hasta: hasta,
        movimientos: movimientos,
      );

      final nombre = rango == null
          ? 'ingresos-${desde.toIso8601String().substring(0, 10)}.pdf'
          : 'ingresos-${desde.toIso8601String().substring(0, 10)}-a-'
              '${hasta.toIso8601String().substring(0, 10)}.pdf';

      await Printing.layoutPdf(
        name: nombre,
        onLayout: (_) => bytes,
      );
    } catch (falla) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(Traductor.traducir(falla).mensaje),
          backgroundColor: Colores.rojo,
        ),
      );
    }
  }
}

class _FilaAcceso extends StatelessWidget {
  const _FilaAcceso({required this.movimiento});

  final MovimientoAdmin movimiento;

  @override
  Widget build(BuildContext context) {
    final m = movimiento;
    final color = m.aprobado ? Colores.verde : Colores.rojo;

    return Card(
      margin: const EdgeInsets.only(bottom: 7),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
        child: Row(
          children: [
            // La flecha dice de un vistazo si entró o salió
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.11),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(
                m.esEntrada ? Icons.login_rounded : Icons.logout_rounded,
                size: 18,
                color: color,
              ),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    m.quien ?? 'Sin nombre registrado',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 13.5, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    [
                      m.esEntrada ? 'Entrada' : 'Salida',
                      if (m.esVehicular && m.patente != null) m.patente!,
                      if (m.espacio != null) m.espacio!,
                      if (m.entrada != null) m.entrada!,
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 11.5, color: Colores.textoSuave),
                  ),
                  if (m.autorizadoPor != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Row(
                        children: [
                          const Icon(Icons.verified_user_outlined,
                              size: 12, color: Colores.textoTenue),
                          const SizedBox(width: 3),
                          Flexible(
                            child: Text(
                              'Autorizó: ${m.autorizadoPor}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 11,
                                color: Colores.textoTenue,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (!m.aprobado && m.motivoDenegacion != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(
                        m.motivoDenegacion!,
                        style: const TextStyle(
                            fontSize: 11.5,
                            height: 1.35,
                            fontWeight: FontWeight.w600,
                            color: Colores.rojoOscuro),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(Formato.hora(m.ocurridoEn),
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w700)),
                Text(Formato.diaYMes(m.ocurridoEn),
                    style: const TextStyle(
                        fontSize: 10.5, color: Colores.textoTenue)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ----------------------------------------------------------------------------
// BARRA DE FILTROS DE ACCESOS (chips + dropdown de guardia)
// ----------------------------------------------------------------------------

class _BarraFiltrosAccesos extends ConsumerWidget {
  const _BarraFiltrosAccesos({required this.guardias});

  final List<String> guardias;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filtro = ref.watch(filtroAccesosProvider);
    final guardiaFiltrado = ref.watch(filtroGuardiaAccesosProvider);

    FilterChip chip(FiltroAcceso f, String texto) => FilterChip(
          label: Text(texto),
          selected: filtro == f,
          onSelected: (_) =>
              ref.read(filtroAccesosProvider.notifier).state = f,
          visualDensity: VisualDensity.compact,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        );

    return Padding(
      padding: const EdgeInsets.fromLTRB(
          Medidas.margen, 0, Medidas.margen, 8),
      child: Column(
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              chip(FiltroAcceso.todos, 'Todos'),
              chip(FiltroAcceso.denegados, 'Denegados'),
              chip(FiltroAcceso.peatonales, 'Peatonales'),
              chip(FiltroAcceso.vehiculares, 'Vehiculares'),
            ],
          ),
          if (guardias.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: _DropdownGuardia(
                guardias: guardias,
                valor: guardiaFiltrado,
                alCambiar: (v) =>
                    ref.read(filtroGuardiaAccesosProvider.notifier).state = v,
              ),
            ),
        ],
      ),
    );
  }
}

/// Dropdown compacto para elegir "ver solo lo de este guardia". Null = todos.
/// Se usa en las 3 pestañas con providers distintos.
class _DropdownGuardia extends StatelessWidget {
  const _DropdownGuardia({
    required this.guardias,
    required this.valor,
    required this.alCambiar,
  });

  final List<String> guardias;
  final String? valor;
  final ValueChanged<String?> alCambiar;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String?>(
      initialValue: valor,
      isDense: true,
      decoration: const InputDecoration(
        labelText: 'Guardia',
        prefixIcon: Icon(Icons.shield_outlined, size: 20),
        border: OutlineInputBorder(),
        contentPadding:
            EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      ),
      items: [
        const DropdownMenuItem<String?>(
          value: null,
          child: Text('Todos los guardias'),
        ),
        ...guardias.map((g) => DropdownMenuItem<String?>(
              value: g,
              child: Text(g, overflow: TextOverflow.ellipsis),
            )),
      ],
      onChanged: alCambiar,
    );
  }
}

// ============================================================================
// PESTAÑA 2 · LOS TURNOS DE LOS GUARDIAS
// ============================================================================

class _PestanaTurnos extends ConsumerStatefulWidget {
  const _PestanaTurnos();

  @override
  ConsumerState<_PestanaTurnos> createState() => _EstadoPestanaTurnos();
}

class _EstadoPestanaTurnos extends ConsumerState<_PestanaTurnos> {
  /// Rango personalizado (día + hora) para el PDF. Si es null, el PDF sale
  /// con los últimos 14 días. La lista de la pantalla no depende del rango
  /// — sigue mostrando los últimos 14 días como siempre.
  ({DateTime desde, DateTime hasta})? _rango;

  @override
  Widget build(BuildContext context) {
    final turnos = ref.watch(turnosAdminProvider);
    final guardiaFiltrado = ref.watch(filtroGuardiaTurnosProvider);

    return turnos.when(
      loading: () => const Center(
        child: CircularProgressIndicator(color: Colores.grafito),
      ),
      error: (falla, _) => Padding(
        padding: const EdgeInsets.all(Medidas.margen),
        child: AvisoDeError(
          problema: Traductor.traducir(falla),
          alReintentar: () => ref.invalidate(turnosAdminProvider),
        ),
      ),
      data: (lista) {
        if (lista.isEmpty) {
          return const ListaVacia(
            icono: Icons.schedule_rounded,
            titulo: 'No hay turnos en las últimas dos semanas',
            explicacion:
                'Los turnos aparecen acá cuando un guardia abre el suyo en la app.',
          );
        }

        // Guardias que trabajaron en el período, ordenados.
        final guardias = <String>{for (final t in lista) t.guardia}
            .where((g) => g.isNotEmpty)
            .toList()
          ..sort();

        final filtrada = guardiaFiltrado == null
            ? lista
            : lista.where((t) => t.guardia == guardiaFiltrado).toList();

        return RefreshIndicator(
          onRefresh: () async => ref.invalidate(turnosAdminProvider),
          child: Column(
            children: [
              // ---- Selector de rango + botón Descargar PDF ----
              Padding(
                padding: const EdgeInsets.fromLTRB(
                    Medidas.margen, Medidas.margen, Medidas.margen, 4),
                child: Column(
                  children: [
                    SelectorRangoPersonalizado(
                      rango: _rango,
                      alElegir: (r) => setState(() => _rango = r),
                      alQuitar: () => setState(() => _rango = null),
                    ),
                    const SizedBox(height: 8),
                    if (guardias.length > 1)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _DropdownGuardia(
                          guardias: guardias,
                          valor: guardiaFiltrado,
                          alCambiar: (v) => ref
                              .read(filtroGuardiaTurnosProvider.notifier)
                              .state = v,
                        ),
                      ),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: () => _descargarPdf(),
                        icon: const Icon(Icons.picture_as_pdf_rounded, size: 18),
                        label: const Text('Descargar informe en PDF'),
                        style: FilledButton.styleFrom(
                          backgroundColor: Colores.grafito,
                          minimumSize: const Size(0, 42),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: filtrada.isEmpty
                    ? const ListaVacia(
                        icono: Icons.filter_alt_off_rounded,
                        titulo: 'No hay turnos de ese guardia',
                        explicacion:
                            'Elegí "Todos los guardias" para ver todos los '
                            'turnos del período.',
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(
                            Medidas.margen, 4, Medidas.margen, Medidas.margen),
                        itemCount: filtrada.length,
                        itemBuilder: (_, i) =>
                            _FilaTurno(turno: filtrada[i]),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _descargarPdf() async {
    // Aviso al usuario que puede tardar (se bajan las fotos una por una)
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Calculando estadísticas y bajando fotos…',
        ),
        backgroundColor: Colores.grafito,
        duration: Duration(seconds: 8),
      ),
    );
    try {
      final instalacion = ref.read(perfilProvider).valueOrNull?.nombreCondominio
          ?? 'Instalación';
      final servicioFotos = ref.read(servicioFotosProvider);
      final servicio = ref.read(servicioAdminProvider);

      // Rango del PDF: personalizado si el admin lo eligió; si no, los
      // últimos 14 días como siempre.
      final rango = _rango;
      final desde = rango?.desde ??
          DateTime.now().subtract(const Duration(days: 14));
      final hasta = rango?.hasta ?? DateTime.now();

      final (stats, turnosEnriquecidos) =
          await servicio.estadisticasTurnos(desde: desde, hasta: hasta);

      // Marcas de ronda por turno — se usa para dibujar el mini-mapa OSM
      // y el timeline dentro de cada tarjeta del PDF. Se pide de a 4
      // turnos en paralelo para no saturar la red.
      final rondasPorTurno = <String, List<MarcaDeRondaAdmin>>{};
      for (var i = 0; i < turnosEnriquecidos.length; i += 4) {
        final tanda = turnosEnriquecidos.skip(i).take(4);
        final resultados = await Future.wait(
          tanda.map((t) => servicio.marcasDeRondaPorTurno(t.id)),
        );
        var j = 0;
        for (final t in tanda) {
          rondasPorTurno[t.id] = resultados[j++];
        }
      }

      final bytes = await InformeDeTurnosPdf.armar(
        instalacion: instalacion,
        turnos: turnosEnriquecidos,
        servicioFotos: servicioFotos,
        stats: stats,
        rondasPorTurno: rondasPorTurno,
      );
      if (!mounted) return;

      final nombre = rango == null
          ? 'informe-turnos-${DateTime.now().millisecondsSinceEpoch}.pdf'
          : 'turnos-${desde.toIso8601String().substring(0, 10)}-a-'
              '${hasta.toIso8601String().substring(0, 10)}.pdf';

      await Printing.layoutPdf(
        name: nombre,
        onLayout: (_) async => bytes,
      );
    } catch (falla) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo generar el PDF: '
              '${Traductor.traducir(falla).mensaje}'),
          backgroundColor: Colores.rojo,
        ),
      );
    }
  }
}

class _FilaTurno extends ConsumerWidget {
  const _FilaTurno({required this.turno});

  final TurnoAdmin turno;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = turno;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () => _abrirDetalle(context, ref),
        borderRadius: BorderRadius.circular(Medidas.redondeo),
        child: Padding(
          padding: const EdgeInsets.all(13),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ---- Selfie del guardia al iniciar el turno ----
              _MiniSelfie(rutaFoto: t.fotoUrl),
              const SizedBox(width: 12),

              // ---- Datos del turno ----
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(t.guardia,
                              style: const TextStyle(
                                  fontSize: 14.5, fontWeight: FontWeight.w700)),
                        ),
                        if (t.sigueAbierto)
                          const Etiqueta(
                              texto: 'De turno', tono: TonoEtiqueta.bueno)
                        else
                          Text(t.duracionEnPalabras,
                              style: const TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                  color: Colores.textoSuave)),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      [
                        // Sin puesto significa que cubría TODAS las entradas.
                        t.puesto ?? 'Cubría todas las entradas',
                        '${Formato.diaYMes(t.inicio)} · ${Formato.hora(t.inicio)}'
                            '${t.cerradoEn == null ? "" : " a ${Formato.hora(t.cerradoEn!)}"}',
                      ].join(' · '),
                      style: const TextStyle(
                          fontSize: 12, color: Colores.textoSuave),
                    ),
                    const SizedBox(height: 5),
                    // Icono de GPS: verde si tiene, gris si no.
                    Row(
                      children: [
                        Icon(
                          t.tieneUbicacion
                              ? Icons.location_on_rounded
                              : Icons.location_off_outlined,
                          size: 14,
                          color: t.tieneUbicacion
                              ? Colores.verdeOscuro
                              : Colores.textoTenue,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          t.tieneUbicacion
                              ? 'Ubicación registrada'
                              : 'Sin ubicación',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: t.tieneUbicacion
                                ? Colores.verdeOscuro
                                : Colores.textoTenue,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    if (t.notas != null && t.notas!.isNotEmpty) ...[
                      const SizedBox(height: 9),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colores.grafito.withValues(alpha: 0.05),
                          borderRadius:
                              BorderRadius.circular(Medidas.redondeoChico),
                        ),
                        child: Text(
                          'Dejó anotado: ${t.notas}',
                          style: const TextStyle(
                              fontSize: 12, height: 1.4, color: Colores.texto),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _abrirDetalle(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colores.superficie,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _DetalleTurno(turno: turno),
    );
  }
}

// ============================================================================
// SELFIE EN MINIATURA (60x60)
// ============================================================================
// Pide el enlace temporal al servidor y lo cachea. Si la foto no existe (o
// el turno se abrió sin selfie), muestra el marcador gris con un icono.
// ============================================================================

class _MiniSelfie extends ConsumerWidget {
  const _MiniSelfie({required this.rutaFoto});

  final String? rutaFoto;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (rutaFoto == null || rutaFoto!.isEmpty) {
      return _placeholder();
    }
    final futuro = ref.watch(
      _enlaceGuardiaProvider(rutaFoto!),
    );
    return futuro.when(
      loading: () => _placeholder(cargando: true),
      error: (_, __) => _placeholder(),
      data: (enlace) => enlace == null
          ? _placeholder()
          : ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(
                enlace,
                width: 60,
                height: 60,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _placeholder(),
              ),
            ),
    );
  }

  Widget _placeholder({bool cargando = false}) => Container(
        width: 60,
        height: 60,
        decoration: BoxDecoration(
          color: Colores.grafito.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
        ),
        alignment: Alignment.center,
        child: cargando
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.person_outline_rounded,
                size: 26, color: Colores.textoTenue),
      );
}

/// Cache de enlaces temporales de fotos de guardia (dura 1 hora)
final _enlaceGuardiaProvider =
    FutureProvider.family<String?, String>((ref, ruta) {
  return ref
      .watch(servicioFotosProvider)
      .enlaceTemporal(ruta, CajonDeFotos.guardias);
});

// ============================================================================
// DETALLE DEL TURNO (modal)
// ============================================================================
// Muestra la selfie grande + coordenadas + botón "Ver en Google Maps".
// ============================================================================

class _DetalleTurno extends ConsumerWidget {
  const _DetalleTurno({required this.turno});

  final TurnoAdmin turno;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = turno;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(Medidas.margen),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // agarradera visual
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colores.linea,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Text(t.guardia,
                style: const TextStyle(
                    fontSize: 20, fontWeight: FontWeight.w800)),
            Text(
              '${Formato.diaCompleto(t.inicio)} · ${Formato.hora(t.inicio)}'
              '${t.cerradoEn == null ? " · sigue abierto" : " a ${Formato.hora(t.cerradoEn!)}"}',
              style:
                  const TextStyle(fontSize: 13, color: Colores.textoSuave),
            ),
            const SizedBox(height: 18),

            // Foto grande
            if (t.tieneFoto)
              ClipRRect(
                borderRadius: BorderRadius.circular(Medidas.redondeo),
                child: AspectRatio(
                  aspectRatio: 1,
                  child: _SelfieGrande(rutaFoto: t.fotoUrl!),
                ),
              )
            else
              Container(
                width: double.infinity,
                height: 200,
                decoration: BoxDecoration(
                  color: Colores.grafito.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(Medidas.redondeo),
                ),
                alignment: Alignment.center,
                child: const Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.no_photography_outlined,
                        size: 40, color: Colores.textoTenue),
                    SizedBox(height: 8),
                    Text('Este turno se abrió sin selfie',
                        style: TextStyle(
                            fontSize: 13, color: Colores.textoSuave)),
                  ],
                ),
              ),
            const SizedBox(height: 14),

            // Ubicación GPS
            if (t.tieneUbicacion) ...[
              Row(
                children: [
                  const Icon(Icons.location_on_rounded,
                      size: 18, color: Colores.verdeOscuro),
                  const SizedBox(width: 6),
                  Text(
                    '${t.geoLat!.toStringAsFixed(6)}, ${t.geoLng!.toStringAsFixed(6)}',
                    style: const TextStyle(
                        fontSize: 12.5,
                        fontFamily: 'monospace',
                        color: Colores.textoSuave),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  // Abre Google Maps en el navegador o en la app nativa
                  // (Android decide qué usar). Antes se copiaba al
                  // portapapeles y el admin tenía que pegar la URL a mano
                  // en el navegador. Ahora un tap y aparece el mapa.
                  onPressed: () async {
                    final url = Uri.parse(
                      'https://www.google.com/maps/search/?api=1'
                      '&query=${t.geoLat},${t.geoLng}',
                    );
                    try {
                      await launchUrl(url,
                          mode: LaunchMode.externalApplication);
                    } catch (_) {
                      // Fallback: copiar al portapapeles si el sistema no
                      // puede abrir un browser.
                      await Clipboard.setData(
                          ClipboardData(text: url.toString()));
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Link copiado al portapapeles.'),
                          backgroundColor: Colores.grafito,
                        ),
                      );
                    }
                  },
                  icon: const Icon(Icons.map_rounded, size: 18),
                  label: const Text('Ver en Google Maps'),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colores.grafito,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ] else
              Row(
                children: const [
                  Icon(Icons.location_off_outlined,
                      size: 18, color: Colores.textoTenue),
                  SizedBox(width: 6),
                  Text('Sin ubicación registrada',
                      style: TextStyle(
                          fontSize: 12.5,
                          color: Colores.textoTenue,
                          fontStyle: FontStyle.italic)),
                ],
              ),

            if (t.puesto != null) ...[
              const SizedBox(height: 14),
              Text('Puesto: ${t.puesto}',
                  style: const TextStyle(fontSize: 13)),
            ],

            if (t.notas != null && t.notas!.isNotEmpty) ...[
              const SizedBox(height: 14),
              const Text('Nota dejada al siguiente turno:',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Colores.textoSuave)),
              const SizedBox(height: 6),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colores.grafito.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(Medidas.redondeoChico),
                ),
                child: Text(t.notas!,
                    style:
                        const TextStyle(fontSize: 13, height: 1.45)),
              ),
            ],

            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }
}

class _SelfieGrande extends ConsumerWidget {
  const _SelfieGrande({required this.rutaFoto});
  final String rutaFoto;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final futuro = ref.watch(_enlaceGuardiaProvider(rutaFoto));
    return futuro.when(
      loading: () => Container(
        color: Colores.grafito.withValues(alpha: 0.04),
        alignment: Alignment.center,
        child: const CircularProgressIndicator(),
      ),
      error: (_, __) => Container(
        color: Colores.grafito.withValues(alpha: 0.04),
        alignment: Alignment.center,
        child: const Icon(Icons.broken_image_outlined,
            size: 60, color: Colores.textoTenue),
      ),
      data: (enlace) => enlace == null
          ? Container(
              color: Colores.grafito.withValues(alpha: 0.04),
              alignment: Alignment.center,
              child: const Icon(Icons.broken_image_outlined,
                  size: 60, color: Colores.textoTenue),
            )
          : Image.network(enlace, fit: BoxFit.cover),
    );
  }
}

// ============================================================================
// PESTAÑA 3 · NOVEDADES DEL PERÍODO
// ============================================================================
// Lista las novedades (incidentes) que reportaron los guardias durante el
// período seleccionado. Se puede filtrar por 1/7/30 días con el mismo
// selector que Accesos y bajar un PDF con todo el detalle.
// ============================================================================

class _PestanaNovedades extends ConsumerStatefulWidget {
  const _PestanaNovedades();

  @override
  ConsumerState<_PestanaNovedades> createState() => _EstadoPestanaNovedades();
}

class _EstadoPestanaNovedades extends ConsumerState<_PestanaNovedades> {
  /// Rango personalizado (día + hora). Cuando está seteado, la lista y el PDF
  /// salen con ese rango exacto en vez de "últimos N días".
  ({DateTime desde, DateTime hasta})? _rango;

  Future<List<IncidenteAdmin>>? _futuroRango;

  void _cargarRango() {
    final r = _rango;
    if (r == null) {
      _futuroRango = null;
      return;
    }
    _futuroRango = ref
        .read(servicioAdminProvider)
        .incidentesDelPeriodo(desde: r.desde, hasta: r.hasta);
  }

  @override
  Widget build(BuildContext context) {
    final dias = ref.watch(diasNovedadesProvider);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(Medidas.margen),
          child: Column(
            children: [
              SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 1, label: Text('Hoy')),
                  ButtonSegment(value: 7, label: Text('7 días')),
                  ButtonSegment(value: 30, label: Text('30 días')),
                  ButtonSegment(value: 90, label: Text('3 meses')),
                ],
                selected: {dias},
                onSelectionChanged: _rango != null
                    ? null
                    : (s) => ref
                        .read(diasNovedadesProvider.notifier)
                        .state = s.first,
                showSelectedIcon: false,
              ),
              const SizedBox(height: 8),
              SelectorRangoPersonalizado(
                rango: _rango,
                alElegir: (r) => setState(() {
                  _rango = r;
                  _cargarRango();
                }),
                alQuitar: () => setState(() {
                  _rango = null;
                  _futuroRango = null;
                }),
              ),
            ],
          ),
        ),
        Expanded(
          child: _rango != null
              ? _ListaNovedadesConRango(
                  futuro: _futuroRango!,
                  desde: _rango!.desde,
                  hasta: _rango!.hasta,
                  alRecargar: () => setState(() => _cargarRango()),
                )
              : _ListaNovedades(dias: dias),
        ),
      ],
    );
  }
}

class _ListaNovedades extends ConsumerWidget {
  const _ListaNovedades({required this.dias});
  final int dias;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final incidentes = ref.watch(incidentesAdminProvider);
    return incidentes.when(
      loading: () => const Center(
        child: CircularProgressIndicator(color: Colores.grafito),
      ),
      error: (falla, _) => Padding(
        padding: const EdgeInsets.all(Medidas.margen),
        child: AvisoDeError(
          problema: Traductor.traducir(falla),
          alReintentar: () => ref.invalidate(incidentesAdminProvider),
        ),
      ),
      data: (lista) => _CuerpoNovedades(
        lista: lista,
        desde: DateTime.now().subtract(Duration(days: dias)),
        hasta: DateTime.now(),
        alRecargar: () => ref.invalidate(incidentesAdminProvider),
      ),
    );
  }
}

class _ListaNovedadesConRango extends ConsumerWidget {
  const _ListaNovedadesConRango({
    required this.futuro,
    required this.desde,
    required this.hasta,
    required this.alRecargar,
  });

  final Future<List<IncidenteAdmin>> futuro;
  final DateTime desde;
  final DateTime hasta;
  final VoidCallback alRecargar;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FutureBuilder<List<IncidenteAdmin>>(
      future: futuro,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: Colores.grafito),
          );
        }
        if (snap.hasError) {
          return Padding(
            padding: const EdgeInsets.all(Medidas.margen),
            child: AvisoDeError(
              problema: Traductor.traducir(snap.error!),
              alReintentar: alRecargar,
            ),
          );
        }
        return _CuerpoNovedades(
          lista: snap.data ?? const [],
          desde: desde,
          hasta: hasta,
          alRecargar: alRecargar,
        );
      },
    );
  }
}

class _CuerpoNovedades extends ConsumerWidget {
  const _CuerpoNovedades({
    required this.lista,
    required this.desde,
    required this.hasta,
    required this.alRecargar,
  });

  final List<IncidenteAdmin> lista;
  final DateTime desde;
  final DateTime hasta;
  final VoidCallback alRecargar;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filtro = ref.watch(filtroNovedadesProvider);
    final guardiaFiltrado = ref.watch(filtroGuardiaNovedadesProvider);

    // Guardias (quien reportó) que aparecen en la lista original — para
    // armar el dropdown. Se calculan ANTES de aplicar el filtro de guardia
    // para que el admin pueda volver a elegir otro.
    final guardias = <String>{
      for (final i in lista)
        if (i.reportadoPor != null && i.reportadoPor!.isNotEmpty)
          i.reportadoPor!,
    }.toList()
      ..sort();

    Iterable<IncidenteAdmin> filtrada = lista;
    switch (filtro) {
      case FiltroNovedad.todas:
        break;
      case FiltroNovedad.abiertas:
        filtrada = filtrada.where((i) => i.abierta);
        break;
      case FiltroNovedad.criticas:
        // "Crítica" = abierta Y gravedad alta/crítica. Resuelve el reclamo
        // del admin de "quiero ver solo las urgentes".
        filtrada = filtrada.where((i) =>
            i.abierta &&
            (i.gravedad == 'critica' || i.gravedad == 'alta'));
        break;
      case FiltroNovedad.resueltas:
        filtrada = filtrada.where((i) => !i.abierta);
        break;
    }
    if (guardiaFiltrado != null) {
      filtrada = filtrada.where((i) => i.reportadoPor == guardiaFiltrado);
    }
    final filtradaList = filtrada.toList();
    final abiertas = filtradaList.where((i) => i.abierta).length;

    final barra = _BarraFiltrosNovedades(guardias: guardias);

    if (lista.isEmpty) {
      // El rango no trajo nada: ni siquiera tiene sentido mostrar los chips.
      return const ListaVacia(
        icono: Icons.report_gmailerrorred_outlined,
        titulo: 'Sin novedades en este período',
        explicacion:
            'Cuando los guardias reporten una novedad, va a aparecer '
            'acá con foto y detalle.',
      );
    }

    return RefreshIndicator(
      onRefresh: () async => alRecargar(),
      child: Column(
        children: [
          barra,
          Expanded(
            child: filtradaList.isEmpty
                ? const ListaVacia(
                    icono: Icons.filter_alt_off_rounded,
                    titulo: 'Ninguna novedad coincide con el filtro',
                    explicacion:
                        'Probá "Todas" o quitar el filtro de guardia para '
                        'volver a ver todo lo del período.',
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(
                        Medidas.margen, 0, Medidas.margen, Medidas.margen),
                    itemCount: filtradaList.length + 2,
                    itemBuilder: (_, i) {
                      if (i == 0) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              onPressed: () =>
                                  _descargarPdf(context, ref, filtradaList),
                              icon: const Icon(
                                  Icons.picture_as_pdf_rounded, size: 18),
                              label: const Text(
                                  'Descargar informe de novedades en PDF'),
                              style: FilledButton.styleFrom(
                                backgroundColor: Colores.grafito,
                                minimumSize: const Size(0, 42),
                              ),
                            ),
                          ),
                        );
                      }
                      if (i == 1) {
                        return Padding(
                          padding:
                              const EdgeInsets.only(bottom: 12, top: 4),
                          child: Text(
                            '${filtradaList.length} '
                            '${filtradaList.length == 1 ? "novedad" : "novedades"}'
                            '${abiertas > 0 ? " · $abiertas abierta${abiertas == 1 ? "" : "s"}" : ""}',
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                        );
                      }
                      return _FilaNovedad(
                        incidente: filtradaList[i - 2],
                        alRecargar: alRecargar,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _descargarPdf(
    BuildContext context,
    WidgetRef ref,
    List<IncidenteAdmin> listaParaPdf,
  ) async {
    final perfil = ref.read(perfilProvider).valueOrNull;
    final instalacion = perfil?.nombreCondominio ?? 'Instalación';
    final servicioFotos = ref.read(servicioFotosProvider);

    final cuantasFotos =
        listaParaPdf.fold<int>(0, (t, i) => t + i.fotos.length);
    if (cuantasFotos > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Armando informe y bajando $cuantasFotos '
              '${cuantasFotos == 1 ? "foto" : "fotos"}…'),
          duration: const Duration(seconds: 3),
        ),
      );
    }

    try {
      // El PDF sale con la lista FILTRADA (lo que el admin ve en pantalla),
      // no con todo el período. Si tiene activo "solo críticas abiertas", el
      // PDF que entrega al mandante también va con eso solo.
      final bytes = await InformeDeIncidentesPdf.armar(
        instalacion: instalacion,
        desde: desde,
        hasta: hasta,
        incidentes: listaParaPdf,
        servicioFotos: servicioFotos,
      );
      await Printing.layoutPdf(
        name: 'novedades-${desde.toIso8601String().substring(0, 10)}-a-'
            '${hasta.toIso8601String().substring(0, 10)}.pdf',
        onLayout: (_) => bytes,
      );
    } catch (falla) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(Traductor.traducir(falla).mensaje),
          backgroundColor: Colores.rojo,
        ),
      );
    }
  }
}

// ----------------------------------------------------------------------------
// BARRA DE FILTROS DE NOVEDADES (chips + dropdown de guardia)
// ----------------------------------------------------------------------------

class _BarraFiltrosNovedades extends ConsumerWidget {
  const _BarraFiltrosNovedades({required this.guardias});

  final List<String> guardias;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filtro = ref.watch(filtroNovedadesProvider);
    final guardiaFiltrado = ref.watch(filtroGuardiaNovedadesProvider);

    FilterChip chip(FiltroNovedad f, String texto) => FilterChip(
          label: Text(texto),
          selected: filtro == f,
          onSelected: (_) =>
              ref.read(filtroNovedadesProvider.notifier).state = f,
          visualDensity: VisualDensity.compact,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        );

    return Padding(
      padding: const EdgeInsets.fromLTRB(
          Medidas.margen, 0, Medidas.margen, 8),
      child: Column(
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              chip(FiltroNovedad.todas, 'Todas'),
              chip(FiltroNovedad.abiertas, 'Abiertas'),
              chip(FiltroNovedad.criticas, 'Críticas'),
              chip(FiltroNovedad.resueltas, 'Resueltas'),
            ],
          ),
          if (guardias.length > 1)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: _DropdownGuardia(
                guardias: guardias,
                valor: guardiaFiltrado,
                alCambiar: (v) => ref
                    .read(filtroGuardiaNovedadesProvider.notifier)
                    .state = v,
              ),
            ),
        ],
      ),
    );
  }
}

class _FilaNovedad extends StatelessWidget {
  const _FilaNovedad({required this.incidente, required this.alRecargar});

  final IncidenteAdmin incidente;
  final VoidCallback alRecargar;

  @override
  Widget build(BuildContext context) {
    final i = incidente;
    final color = switch ((i.gravedad ?? 'baja').toLowerCase()) {
      'critica' || 'critico' || 'alta' => Colores.rojo,
      'media' => Colores.naranja,
      _ => Colores.verde,
    };

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () async {
          final huboResolucion = await Navigator.of(context).push<bool>(
            MaterialPageRoute(
              builder: (_) => PantallaDetalleNovedad(incidente: i),
            ),
          );
          // Si volvió con "true" es porque se marcó como resuelta: pedimos
          // a la lista de arriba que refresque.
          if (huboResolucion == true) alRecargar();
        },
        borderRadius: BorderRadius.circular(Medidas.redondeo),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    (i.gravedad ?? 'baja').toUpperCase(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  i.tipo.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: Colores.textoSuave,
                    letterSpacing: 0.6,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: (i.abierta ? Colores.naranja : Colores.verde)
                        .withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    i.abierta ? 'ABIERTA' : 'RESUELTA',
                    style: TextStyle(
                      color: i.abierta
                          ? Colores.naranjaOscuro
                          : Colores.verdeOscuro,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              i.titulo,
              style: const TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w700,
                color: Colores.texto,
              ),
            ),
            if (i.descripcion != null && i.descripcion!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                i.descripcion!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12.5,
                  color: Colores.textoSuave,
                  height: 1.4,
                ),
              ),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.schedule_rounded,
                    size: 13, color: Colores.textoTenue),
                const SizedBox(width: 4),
                Text(
                  Formato.fechaYHora(i.ocurridoEn),
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: Colores.textoTenue,
                  ),
                ),
                if (i.reportadoPor != null) ...[
                  const SizedBox(width: 12),
                  Icon(Icons.person_outline_rounded,
                      size: 13, color: Colores.textoTenue),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      i.reportadoPor!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: Colores.textoTenue,
                      ),
                    ),
                  ),
                ],
                if (i.tieneFotos) ...[
                  const Spacer(),
                  Icon(Icons.photo_library_outlined,
                      size: 14, color: Colores.dorado),
                  const SizedBox(width: 3),
                  Text(
                    '${i.fotos.length}',
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: Colores.dorado,
                    ),
                  ),
                ],
              ],
            ),
          ],
          ),
        ),
      ),
    );
  }
}
