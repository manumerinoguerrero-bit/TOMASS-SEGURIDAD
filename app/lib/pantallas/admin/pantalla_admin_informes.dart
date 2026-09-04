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
import 'informe_de_encomiendas.dart';
import 'informe_de_rondas.dart';

class PantallaAdminInformes extends ConsumerWidget {
  const PantallaAdminInformes({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 5,
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

class _PestanaAccesos extends ConsumerWidget {
  const _PestanaAccesos();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final movimientos = ref.watch(movimientosAdminProvider);
    final dias = ref.watch(diasDelInformeProvider);

    return Column(
      children: [
        // ---- Cuánto tiempo hacia atrás ----
        Padding(
          padding: const EdgeInsets.all(Medidas.margen),
          child: SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 1, label: Text('Hoy')),
              ButtonSegment(value: 7, label: Text('7 días')),
              ButtonSegment(value: 30, label: Text('30 días')),
            ],
            selected: {dias},
            onSelectionChanged: (s) =>
                ref.read(diasDelInformeProvider.notifier).state = s.first,
            showSelectedIcon: false,
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

              final denegados = lista.where((m) => !m.aprobado).length;

              return RefreshIndicator(
                onRefresh: () async => ref.invalidate(movimientosAdminProvider),
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(
                      Medidas.margen, 0, Medidas.margen, Medidas.margen),
                  itemCount: lista.length + 2,
                  itemBuilder: (_, i) {
                    if (i == 0) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: () =>
                                _descargarPdfIngresos(context, ref, lista, dias),
                            icon: const Icon(
                                Icons.picture_as_pdf_rounded, size: 18),
                            label:
                                const Text('Descargar informe en PDF'),
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
                        padding: const EdgeInsets.only(bottom: 12, top: 4),
                        child: Text(
                          '${lista.length} '
                          '${lista.length == 1 ? "movimiento" : "movimientos"}'
                          '${denegados > 0 ? " · $denegados denegado${denegados == 1 ? "" : "s"}" : ""}',
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      );
                    }
                    return _FilaAcceso(movimiento: lista[i - 2]);
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _descargarPdfIngresos(
    BuildContext context,
    WidgetRef ref,
    List<MovimientoAdmin> lista,
    int dias,
  ) async {
    final perfil = ref.read(perfilProvider).valueOrNull;
    final instalacion = perfil?.nombreCondominio ?? 'Instalación';
    final desde = DateTime.now().subtract(Duration(days: dias));
    try {
      final bytes = await InformeDeIngresosPdf.armar(
        instalacion: instalacion,
        desde: desde,
        hasta: DateTime.now(),
        movimientos: lista,
      );
      await Printing.layoutPdf(
        name: 'ingresos-${desde.toIso8601String().substring(0, 10)}.pdf',
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

// ============================================================================
// PESTAÑA 2 · LOS TURNOS DE LOS GUARDIAS
// ============================================================================

class _PestanaTurnos extends ConsumerWidget {
  const _PestanaTurnos();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final turnos = ref.watch(turnosAdminProvider);

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

        return RefreshIndicator(
          onRefresh: () async => ref.invalidate(turnosAdminProvider),
          child: Column(
            children: [
              // ---- Botón Descargar PDF ----
              Padding(
                padding: const EdgeInsets.fromLTRB(
                    Medidas.margen, Medidas.margen, Medidas.margen, 4),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () => _descargarPdf(context, ref, lista),
                    icon: const Icon(Icons.picture_as_pdf_rounded, size: 18),
                    label: const Text('Descargar informe en PDF'),
                    style: FilledButton.styleFrom(
                      backgroundColor: Colores.grafito,
                      minimumSize: const Size(0, 42),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(
                      Medidas.margen, 4, Medidas.margen, Medidas.margen),
                  itemCount: lista.length,
                  itemBuilder: (_, i) => _FilaTurno(turno: lista[i]),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _descargarPdf(
    BuildContext context,
    WidgetRef ref,
    List<TurnoAdmin> lista,
  ) async {
    // Aviso al usuario que puede tardar (se bajan las fotos una por una)
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Calculando estadísticas y bajando ${lista.length} fotos...',
        ),
        backgroundColor: Colores.grafito,
        duration: const Duration(seconds: 8),
      ),
    );
    try {
      final instalacion = ref.read(perfilProvider).valueOrNull?.nombreCondominio
          ?? 'Instalación';
      final servicioFotos = ref.read(servicioFotosProvider);
      final servicio = ref.read(servicioAdminProvider);

      // Traemos las estadísticas del período (últimos 14 días por defecto)
      final desde = DateTime.now().subtract(const Duration(days: 14));
      final hasta = DateTime.now();
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
      if (!context.mounted) return;
      await Printing.layoutPdf(
        name: 'informe-turnos-${DateTime.now().millisecondsSinceEpoch}.pdf',
        onLayout: (_) async => bytes,
      );
    } catch (falla) {
      if (!context.mounted) return;
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
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final url = Uri.parse(
                      'https://www.google.com/maps/search/?api=1'
                      '&query=${t.geoLat},${t.geoLng}',
                    );
                    // Copiamos por clipboard como fallback simple
                    // (evitamos agregar dependencia url_launcher)
                    await Clipboard.setData(
                        ClipboardData(text: url.toString()));
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Link a Google Maps copiado. Pegalo en el navegador.',
                        ),
                        backgroundColor: Colores.grafito,
                      ),
                    );
                  },
                  icon: const Icon(Icons.map_rounded, size: 18),
                  label: const Text('Copiar link de Google Maps'),
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

class _PestanaNovedades extends ConsumerWidget {
  const _PestanaNovedades();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final incidentes = ref.watch(incidentesAdminProvider);
    final dias = ref.watch(diasDelInformeProvider);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(Medidas.margen),
          child: SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 1, label: Text('Hoy')),
              ButtonSegment(value: 7, label: Text('7 días')),
              ButtonSegment(value: 30, label: Text('30 días')),
            ],
            selected: {dias},
            onSelectionChanged: (s) =>
                ref.read(diasDelInformeProvider.notifier).state = s.first,
            showSelectedIcon: false,
          ),
        ),
        Expanded(
          child: incidentes.when(
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
            data: (lista) {
              if (lista.isEmpty) {
                return const ListaVacia(
                  icono: Icons.report_gmailerrorred_outlined,
                  titulo: 'Sin novedades en este período',
                  explicacion:
                      'Cuando los guardias reporten una novedad, va a aparecer '
                      'acá con foto y detalle.',
                );
              }

              final abiertas = lista.where((i) => i.abierta).length;

              return RefreshIndicator(
                onRefresh: () async =>
                    ref.invalidate(incidentesAdminProvider),
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(
                      Medidas.margen, 0, Medidas.margen, Medidas.margen),
                  itemCount: lista.length + 2,
                  itemBuilder: (_, i) {
                    if (i == 0) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: () =>
                                _descargarPdf(context, ref, lista, dias),
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
                        padding: const EdgeInsets.only(bottom: 12, top: 4),
                        child: Text(
                          '${lista.length} '
                          '${lista.length == 1 ? "novedad" : "novedades"}'
                          '${abiertas > 0 ? " · $abiertas abierta${abiertas == 1 ? "" : "s"}" : ""}',
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      );
                    }
                    return _FilaNovedad(incidente: lista[i - 2]);
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _descargarPdf(
    BuildContext context,
    WidgetRef ref,
    List<IncidenteAdmin> lista,
    int dias,
  ) async {
    final perfil = ref.read(perfilProvider).valueOrNull;
    final instalacion = perfil?.nombreCondominio ?? 'Instalación';
    final servicioFotos = ref.read(servicioFotosProvider);
    final desde = DateTime.now().subtract(Duration(days: dias));

    final cuantasFotos = lista.fold<int>(0, (t, i) => t + i.fotos.length);
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
      final bytes = await InformeDeIncidentesPdf.armar(
        instalacion: instalacion,
        desde: desde,
        hasta: DateTime.now(),
        incidentes: lista,
        servicioFotos: servicioFotos,
      );
      await Printing.layoutPdf(
        name: 'novedades-${desde.toIso8601String().substring(0, 10)}.pdf',
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

class _FilaNovedad extends StatelessWidget {
  const _FilaNovedad({required this.incidente});

  final IncidenteAdmin incidente;

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
    );
  }
}
