// ============================================================================
// Tomass Seguridad — Panel · El informe de encomiendas, con foto
// ============================================================================
// PARA QUÉ SIRVE
//
//   Manuel pidió esto para no depender de la limpieza automática de 6 meses:
//   una vez a la semana (o cuando quiera), el administrador saca este informe
//   con la foto de cada encomienda entregada, y con el botón de al lado borra
//   esas fotos de la aplicación apenas queda guardado o impreso el papel.
//
//   El texto de cada entrega (quién la retiró, cuándo, quién la entregó) y la
//   firma del residente NUNCA se borran acá: eso vive en la base de datos
//   para siempre, sin importar qué se haga con las fotos.
//
// POR QUÉ SE BAJAN LAS FOTOS DE A TANDAS
//
//   Bajar y achicar 40 o 50 fotos de una sola vez, todas a la vez, satura una
//   conexión de celular. De a 5 en 5, el teléfono no se traba y además se
//   puede mostrar cuántas van, para que no parezca que la app se colgó.
// ============================================================================

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';

import '../../config/tema.dart';
import '../../estado/proveedores.dart';
import '../../estado/proveedores_admin.dart';
import '../../modelos/admin.dart';
import '../../nucleo/errores.dart';
import '../../nucleo/formato.dart';
import '../../servicios/informe_encomiendas_pdf.dart';
import '../../servicios/servicio_fotos.dart';
import '../comunes/componentes.dart';

class PestanaEncomiendas extends ConsumerStatefulWidget {
  const PestanaEncomiendas({super.key});

  @override
  ConsumerState<PestanaEncomiendas> createState() => _EstadoPestanaEncomiendas();
}

class _EstadoPestanaEncomiendas extends ConsumerState<PestanaEncomiendas> {
  bool _generando = false;
  bool _borrando = false;
  String _progreso = '';

  /// Las encomiendas que quedaron en el ÚLTIMO PDF generado. Se guarda la
  /// lista exacta (no se vuelve a pedir) para que el botón de borrar borre
  /// justo lo que quedó impreso, ni una encomienda más ni una menos.
  List<EncomiendaDelInforme>? _ultimoInforme;

  /// Rango personalizado (día + hora) para el PDF. Si es null, el PDF sale
  /// con los últimos N días del segmented button.
  ({DateTime desde, DateTime hasta})? _rango;

  /// Filtro de la lista visible en la pantalla (no afecta el PDF).
  ///
  /// Se abre por defecto en "pendientes" porque es lo que el admin quiere
  /// ver de un vistazo al entrar acá: cuántos paquetes quedaron en portería
  /// esperando ser retirados. El PDF sigue tomando la lista completa del
  /// período para el archivo histórico.
  _FiltroEncomienda _filtro = _FiltroEncomienda.pendientes;

  // ==========================================================================
  // GENERAR EL INFORME
  // ==========================================================================

  Future<void> _generarInforme() async {
    // Si hay rango personalizado, la lista sale del servicio con esos límites
    // exactos. Si no, sale del provider (últimos N días).
    List<EncomiendaDelInforme> lista;
    if (_rango != null) {
      setState(() {
        _generando = true;
        _ultimoInforme = null;
        _progreso = 'Buscando encomiendas del período…';
      });
      try {
        lista = await ref.read(servicioAdminProvider).encomiendasEntregadas(
              desde: _rango!.desde,
              hasta: _rango!.hasta,
            );
      } catch (falla) {
        if (!mounted) return;
        setState(() => _generando = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(Traductor.traducir(falla).mensaje),
            backgroundColor: Colores.rojo,
          ),
        );
        return;
      }
    } else {
      final delProvider = ref.read(encomiendasDelInformeProvider).valueOrNull;
      if (delProvider == null) return;
      lista = delProvider;
    }

    if (lista.isEmpty) {
      if (!mounted) return;
      setState(() => _generando = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No hay encomiendas entregadas con foto en este período.'),
          backgroundColor: Colores.grafito,
        ),
      );
      return;
    }

    setState(() {
      _generando = true;
      _ultimoInforme = null;
      _progreso = 'Descargando fotos… 0 de ${lista.length}';
    });

    try {
      final servicioFotos = ref.read(servicioFotosProvider);
      final fotosRecepcion = <String, Uint8List>{};
      final fotosEntrega = <String, Uint8List>{};
      final firmas = <String, Uint8List>{};

      // De a 5 encomiendas a la vez: ni una por una (lento) ni todas juntas
      // (satura la conexión y traba el teléfono). Por cada encomienda
      // bajamos en paralelo las TRES pruebas visuales que existan:
      // foto de recepción, foto de entrega y firma del residente. Las dos
      // fotos viven en el bucket 'paquetes', la firma en 'firmas'.
      const tandasDe = 5;
      var hechas = 0;
      for (var i = 0; i < lista.length; i += tandasDe) {
        final grupo = lista.skip(i).take(tandasDe).toList();
        final resultados = await Future.wait(grupo.map((e) async {
          final recepcion = servicioFotos.bytesParaPdf(
              e.fotoUrl, CajonDeFotos.paquetes);
          final entrega = e.fotoEntregaUrl != null
              ? servicioFotos.bytesParaPdf(
                  e.fotoEntregaUrl, CajonDeFotos.paquetes)
              : Future<Uint8List?>.value(null);
          final firma = e.tieneFirma
              ? servicioFotos.bytesParaPdf(e.firmaUrl, CajonDeFotos.firmas)
              : Future<Uint8List?>.value(null);
          final (rb, eb, sb) = await (recepcion, entrega, firma).wait;
          return (id: e.id, recepcion: rb, entrega: eb, firmaBytes: sb);
        }));
        for (final r in resultados) {
          if (r.recepcion != null) fotosRecepcion[r.id] = r.recepcion!;
          if (r.entrega != null) fotosEntrega[r.id] = r.entrega!;
          if (r.firmaBytes != null) firmas[r.id] = r.firmaBytes!;
          hechas++;
        }
        if (!mounted) return;
        setState(() => _progreso = 'Descargando fotos y firmas… '
            '$hechas de ${lista.length}');
      }

      if (!mounted) return;
      setState(() => _progreso = 'Armando el PDF…');

      final perfil = ref.read(perfilProvider).valueOrNull;
      final dias = ref.read(diasDelInformeDeEncomiendasProvider);

      final pdf = await InformeDeEncomiendasPdf.armar(
        instalacion: perfil?.nombreCondominio ?? 'Instalación',
        dias: dias,
        encomiendas: lista,
        fotosRecepcion: fotosRecepcion,
        fotosEntrega: fotosEntrega,
        firmas: firmas,
      );

      if (!mounted) return;
      setState(() => _generando = false);

      // Abre la hoja del teléfono para imprimir, compartir o guardar.
      // Si hubo rango personalizado, el filename lo lleva; si no, "Ndias".
      final rango = _rango;
      final nombre = rango == null
          ? 'encomiendas-${_nombreDeArchivo(perfil?.nombreCondominio)}-'
              '${dias}dias.pdf'
          : 'encomiendas-${_nombreDeArchivo(perfil?.nombreCondominio)}-'
              '${rango.desde.toIso8601String().substring(0, 10)}-a-'
              '${rango.hasta.toIso8601String().substring(0, 10)}.pdf';

      await Printing.sharePdf(
        bytes: pdf,
        filename: nombre,
      );

      if (!mounted) return;
      // Recién ahora aparece el botón de borrar: no antes de que el informe
      // exista de verdad.
      setState(() => _ultimoInforme = lista);
    } catch (falla) {
      if (!mounted) return;
      setState(() => _generando = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(Traductor.traducir(falla).mensaje),
          backgroundColor: Colores.rojo,
        ),
      );
    }
  }

  // ==========================================================================
  // BORRAR LAS FOTOS YA IMPRESAS
  // ==========================================================================

  Future<void> _borrarFotos() async {
    final lista = _ultimoInforme;
    if (lista == null) return;

    final conFoto = lista.where((e) => e.tieneFoto).length;

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Borrar las fotos de este informe?'),
        content: Text(
          'Se van a borrar PARA SIEMPRE las fotos de $conFoto '
          '${conFoto == 1 ? "encomienda" : "encomiendas"}: las mismas que '
          'quedaron en el PDF que acabás de generar.\n\n'
          'El texto de cada entrega (quién retiró, cuándo, quién entregó) no '
          'se toca: eso queda igual para siempre.\n\n'
          'Asegurate de haber guardado o impreso el informe antes de '
          'continuar.',
          style: const TextStyle(fontSize: 13.5, height: 1.45),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colores.rojo),
            child: Text('Borrar $conFoto ${conFoto == 1 ? "foto" : "fotos"}'),
          ),
        ],
      ),
    );

    if (ok != true || !mounted) return;

    setState(() => _borrando = true);
    try {
      await ref.read(servicioAdminProvider).borrarFotosDeEncomiendas(lista);
      if (!mounted) return;
      setState(() {
        _borrando = false;
        _ultimoInforme = null;
      });
      ref.invalidate(encomiendasDelInformeProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Fotos borradas. El texto del registro sigue intacto.'),
          backgroundColor: Colores.verde,
        ),
      );
    } catch (falla) {
      if (!mounted) return;
      setState(() => _borrando = false);
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

  // ==========================================================================

  @override
  Widget build(BuildContext context) {
    final encomiendas = ref.watch(encomiendasDelInformeProvider);
    final dias = ref.watch(diasDelInformeDeEncomiendasProvider);
    final ocupado = _generando || _borrando;

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
                ],
                selected: {dias},
                onSelectionChanged: (ocupado || _rango != null)
                    ? null
                    : (s) {
                        ref
                            .read(diasDelInformeDeEncomiendasProvider.notifier)
                            .state = s.first;
                        setState(() => _ultimoInforme = null);
                      },
                showSelectedIcon: false,
              ),
              const SizedBox(height: 8),
              SelectorRangoPersonalizado(
                rango: _rango,
                deshabilitado: ocupado,
                alElegir: (r) => setState(() {
                  _rango = r;
                  _ultimoInforme = null;
                }),
                alQuitar: () => setState(() {
                  _rango = null;
                  _ultimoInforme = null;
                }),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: ocupado ? null : _generarInforme,
                  style: FilledButton.styleFrom(
                    backgroundColor: Colores.grafito,
                    minimumSize: const Size(0, Medidas.altoBoton),
                  ),
                  icon: _generando
                      ? const SizedBox(
                          width: 19,
                          height: 19,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.picture_as_pdf_rounded, size: 21),
                  label: Text(
                    _generando ? _progreso : 'Informe con fotos para imprimir',
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                  ),
                ),
              ),
              if (_ultimoInforme != null) ...[
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _borrando ? null : _borrarFotos,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colores.rojo,
                      side: const BorderSide(color: Colores.rojo),
                      minimumSize: const Size(0, Medidas.altoBoton),
                    ),
                    icon: _borrando
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colores.rojo))
                        : const Icon(Icons.delete_outline_rounded, size: 20),
                    label: Text(
                      _borrando
                          ? 'Borrando fotos…'
                          : 'Ya lo imprimí — borrar esas fotos',
                      style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        Expanded(
          child: encomiendas.when(
            loading: () => const Center(
              child: CircularProgressIndicator(color: Colores.grafito),
            ),
            error: (falla, _) => Padding(
              padding: const EdgeInsets.all(Medidas.margen),
              child: AvisoDeError(
                problema: Traductor.traducir(falla),
                alReintentar: () => ref.invalidate(encomiendasDelInformeProvider),
              ),
            ),
            data: (lista) {
              if (lista.isEmpty) {
                return const ListaVacia(
                  icono: Icons.inventory_2_outlined,
                  titulo: 'No hay encomiendas para informar',
                  explicacion:
                      'Acá aparecen las encomiendas del período. Las '
                      'entregadas y las que quedaron pendientes en portería.',
                );
              }

              // Conteo por estado — la fuente para los chips y el contador.
              final pendientes = lista.where((e) => !e.fueEntregado).toList();
              final entregadas = lista.where((e) => e.fueEntregado).toList();

              final visibles = switch (_filtro) {
                _FiltroEncomienda.pendientes => pendientes,
                _FiltroEncomienda.entregadas => entregadas,
                _FiltroEncomienda.todas => lista,
              };

              return RefreshIndicator(
                onRefresh: () async =>
                    ref.invalidate(encomiendasDelInformeProvider),
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(
                      Medidas.margen, 0, Medidas.margen, Medidas.margen),
                  itemCount: visibles.length + 1,
                  itemBuilder: (_, i) {
                    if (i == 0) {
                      return _CabeceraEncomiendas(
                        pendientes: pendientes.length,
                        entregadas: entregadas.length,
                        filtro: _filtro,
                        alCambiarFiltro: (f) => setState(() => _filtro = f),
                      );
                    }
                    return _FilaEncomienda(encomienda: visibles[i - 1]);
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

// ============================================================================
// UNA FILA DE LA LISTA
// ============================================================================

class _FilaEncomienda extends StatelessWidget {
  const _FilaEncomienda({required this.encomienda});

  final EncomiendaDelInforme encomienda;

  @override
  Widget build(BuildContext context) {
    final e = encomienda;

    return Card(
      margin: const EdgeInsets.only(bottom: 7),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: Colores.verde.withValues(alpha: 0.11),
                borderRadius: BorderRadius.circular(9),
              ),
              child: const Icon(Icons.inventory_2_outlined,
                  size: 18, color: Colores.verdeOscuro),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    (e.descripcion?.isNotEmpty ?? false)
                        ? e.descripcion!
                        : 'Encomienda',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 13.5, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    [
                      'Retiró: ${e.quienRetiro}',
                      if (e.unidad != null) e.unidad!,
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 11.5, color: Colores.textoSuave),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // Muestra la fecha del ENTREGA si ya fue entregado,
                // si no, la fecha en la que llegó a portería. Antes
                // usaba entregadoEn sin null-check, y con paquetes
                // pendientes crasheaba.
                Text(Formato.hora(e.entregadoEn ?? e.recibidoEn),
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w700)),
                Text(Formato.diaYMes(e.entregadoEn ?? e.recibidoEn),
                    style: const TextStyle(
                        fontSize: 10.5, color: Colores.textoTenue)),
                if (!e.fueEntregado)
                  Container(
                    margin: const EdgeInsets.only(top: 4),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colores.naranja.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text(
                      'EN PORTERÍA',
                      style: TextStyle(
                        fontSize: 8.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.6,
                        color: Colores.naranjaOscuro,
                      ),
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

// ============================================================================
// CABECERA CON CONTADORES Y CHIPS DE FILTRO
// ============================================================================
// Se agrego porque el admin necesitaba ver, de un vistazo, cuantas encomiendas
// habia PENDIENTES en porteria (sin retirar todavia). Antes se mezclaban con
// las entregadas en una sola lista larga ordenada por fecha, y las pendientes
// se perdian entre las demas. Ahora:
//
//   * El chip de "Pendientes" muestra el numero en el titulo y arranca
//     seleccionado por defecto, asi se ven de una.
//   * Cuando hay pendientes, la barra se pinta naranja para llamar la
//     atencion. Cuando no hay, verde.
//   * Los chips filtran solo la lista visible; el PDF sigue trayendo todo
//     el periodo.
// ============================================================================

enum _FiltroEncomienda { pendientes, entregadas, todas }

class _CabeceraEncomiendas extends StatelessWidget {
  const _CabeceraEncomiendas({
    required this.pendientes,
    required this.entregadas,
    required this.filtro,
    required this.alCambiarFiltro,
  });

  final int pendientes;
  final int entregadas;
  final _FiltroEncomienda filtro;
  final void Function(_FiltroEncomienda) alCambiarFiltro;

  @override
  Widget build(BuildContext context) {
    final hayPendientes = pendientes > 0;
    final colorAcento = hayPendientes ? Colores.naranjaOscuro : Colores.verdeOscuro;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ---- Estado destacado ----
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
            decoration: BoxDecoration(
              color: colorAcento.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(Medidas.redondeoChico),
              border: Border.all(
                color: colorAcento.withValues(alpha: 0.35),
                width: 0.8,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  hayPendientes
                      ? Icons.pending_actions_rounded
                      : Icons.task_alt_rounded,
                  size: 22,
                  color: colorAcento,
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        hayPendientes
                            ? '$pendientes '
                                '${pendientes == 1 ? "encomienda pendiente" : "encomiendas pendientes"} '
                                'en portería'
                            : 'No hay encomiendas pendientes',
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                          color: colorAcento,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        hayPendientes
                            ? 'Estas encomiendas ya llegaron pero todavía '
                                'no las retiran los residentes.'
                            : 'Todas las encomiendas del período ya fueron '
                                'retiradas.',
                        style: const TextStyle(
                          fontSize: 11.5,
                          height: 1.35,
                          color: Colores.texto,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 10),

          // ---- Chips de filtro ----
          Wrap(
            spacing: 6,
            runSpacing: -4,
            children: [
              _chip(
                context,
                etiqueta: 'Pendientes ($pendientes)',
                seleccionado: filtro == _FiltroEncomienda.pendientes,
                color: Colores.naranjaOscuro,
                alTocar: () => alCambiarFiltro(_FiltroEncomienda.pendientes),
              ),
              _chip(
                context,
                etiqueta: 'Entregadas ($entregadas)',
                seleccionado: filtro == _FiltroEncomienda.entregadas,
                color: Colores.verdeOscuro,
                alTocar: () => alCambiarFiltro(_FiltroEncomienda.entregadas),
              ),
              _chip(
                context,
                etiqueta: 'Todas (${pendientes + entregadas})',
                seleccionado: filtro == _FiltroEncomienda.todas,
                color: Colores.grafito,
                alTocar: () => alCambiarFiltro(_FiltroEncomienda.todas),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _chip(
    BuildContext context, {
    required String etiqueta,
    required bool seleccionado,
    required Color color,
    required VoidCallback alTocar,
  }) {
    return FilterChip(
      label: Text(
        etiqueta,
        style: TextStyle(
          fontSize: 12,
          fontWeight: seleccionado ? FontWeight.w800 : FontWeight.w600,
          color: seleccionado ? Colors.white : color,
        ),
      ),
      selected: seleccionado,
      onSelected: (_) => alTocar(),
      backgroundColor: color.withValues(alpha: 0.08),
      selectedColor: color,
      showCheckmark: false,
      side: BorderSide(
        color: color.withValues(alpha: seleccionado ? 1 : 0.4),
      ),
      visualDensity: VisualDensity.compact,
    );
  }
}
