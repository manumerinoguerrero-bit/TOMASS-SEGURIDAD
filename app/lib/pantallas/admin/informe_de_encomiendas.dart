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

  // ==========================================================================
  // GENERAR EL INFORME
  // ==========================================================================

  Future<void> _generarInforme() async {
    final lista = ref.read(encomiendasDelInformeProvider).valueOrNull;
    if (lista == null || lista.isEmpty) {
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
      final fotos = <String, Uint8List>{};

      // De a 5 fotos a la vez: ni una por una (lento) ni todas juntas
      // (satura la conexión y traba el teléfono).
      const tandasDe = 5;
      var hechas = 0;
      for (var i = 0; i < lista.length; i += tandasDe) {
        final grupo = lista.skip(i).take(tandasDe);
        final resultados = await Future.wait(grupo.map((e) async {
          final bytes = await servicioFotos.bytesParaPdf(
              e.fotoParaElInforme, CajonDeFotos.paquetes);
          return MapEntry(e.id, bytes);
        }));
        for (final r in resultados) {
          if (r.value != null) fotos[r.key] = r.value!;
          hechas++;
        }
        if (!mounted) return;
        setState(() => _progreso = 'Descargando fotos… $hechas de ${lista.length}');
      }

      if (!mounted) return;
      setState(() => _progreso = 'Armando el PDF…');

      final perfil = ref.read(perfilProvider).valueOrNull;
      final dias = ref.read(diasDelInformeDeEncomiendasProvider);

      final pdf = await InformeDeEncomiendasPdf.armar(
        instalacion: perfil?.nombreCondominio ?? 'Instalación',
        dias: dias,
        encomiendas: lista,
        fotos: fotos,
      );

      if (!mounted) return;
      setState(() => _generando = false);

      // Abre la hoja del teléfono para imprimir, compartir o guardar
      await Printing.sharePdf(
        bytes: pdf,
        filename: 'encomiendas-${_nombreDeArchivo(perfil?.nombreCondominio)}-'
            '${dias}dias.pdf',
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
                onSelectionChanged: ocupado
                    ? null
                    : (s) {
                        ref
                            .read(diasDelInformeDeEncomiendasProvider.notifier)
                            .state = s.first;
                        setState(() => _ultimoInforme = null);
                      },
                showSelectedIcon: false,
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
                      'Acá aparecen las encomiendas entregadas en el período '
                      'que todavía tienen alguna foto. Las que ya se '
                      'limpiaron no vuelven a salir.',
                );
              }

              final conFoto = lista.where((e) => e.tieneFoto).length;

              return RefreshIndicator(
                onRefresh: () async => ref.invalidate(encomiendasDelInformeProvider),
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
                          '${lista.length == 1 ? "encomienda" : "encomiendas"} '
                          'con foto · $conFoto lista${conFoto == 1 ? "" : "s"} '
                          'para el informe',
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      );
                    }
                    return _FilaEncomienda(encomienda: lista[i - 1]);
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
