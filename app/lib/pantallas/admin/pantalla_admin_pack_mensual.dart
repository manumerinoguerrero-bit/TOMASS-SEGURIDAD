// ============================================================================
// Tomass Seguridad — Pack mensual del mandante
// ============================================================================
// Pantalla sencilla: el admin elige qué mes quiere y toca "Generar". La
// generación tarda varios minutos (bajar selfies de turnos + fotos de
// novedades), así que el UI muestra en vivo qué está haciendo:
//
//    [●     ] Generando 2 de 6: Turnos (bajando selfies)
//
// Al terminar comparte el ZIP via share_plus (WhatsApp, Gmail, Drive).
// Un pack típico de un condominio de ~30 unidades para un mes son 2-5 MB.
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../config/tema.dart';
import '../../estado/proveedores.dart';
import '../../estado/proveedores_admin.dart';
import '../../nucleo/errores.dart';
import '../../servicios/pack_mensual_pdf.dart';
import 'acciones_admin.dart';

class PantallaAdminPackMensual extends ConsumerStatefulWidget {
  const PantallaAdminPackMensual({super.key});

  @override
  ConsumerState<PantallaAdminPackMensual> createState() =>
      _EstadoPackMensual();
}

class _EstadoPackMensual extends ConsumerState<PantallaAdminPackMensual> {
  late int _anio;
  late int _mes;
  bool _generando = false;
  String _estado = '';

  @override
  void initState() {
    super.initState();
    // Default: mes anterior. Es el caso más común — a principio de mes el
    // admin le pasa al mandante el pack del mes recién terminado.
    final hoy = DateTime.now();
    final anterior = DateTime(hoy.year, hoy.month - 1, 1);
    _anio = anterior.year;
    _mes = anterior.month;
  }

  void _mesActual() {
    final hoy = DateTime.now();
    setState(() {
      _anio = hoy.year;
      _mes = hoy.month;
    });
  }

  void _mesAnterior() {
    final hoy = DateTime.now();
    final anterior = DateTime(hoy.year, hoy.month - 1, 1);
    setState(() {
      _anio = anterior.year;
      _mes = anterior.month;
    });
  }

  Future<void> _elegirCustom() async {
    final ahora = DateTime.now();
    final elegido = await showDatePicker(
      context: context,
      initialDate: DateTime(_anio, _mes, 1),
      firstDate: DateTime(ahora.year - 2, 1, 1),
      lastDate: ahora,
      locale: const Locale('es', 'CL'),
      helpText: 'Elegí el mes del informe',
      cancelText: 'Cancelar',
      confirmText: 'Elegir',
    );
    if (elegido == null || !mounted) return;
    setState(() {
      _anio = elegido.year;
      _mes = elegido.month;
    });
  }

  Future<void> _generar() async {
    final perfil = ref.read(perfilProvider).valueOrNull;
    final instalacion = perfil?.nombreCondominio ?? 'Instalación';
    final admin = ref.read(servicioAdminProvider);
    final fotos = ref.read(servicioFotosProvider);

    setState(() {
      _generando = true;
      _estado = 'Preparando…';
    });

    try {
      final zip = await PackMensualPdf.armar(
        anio: _anio,
        mes: _mes,
        instalacion: instalacion,
        admin: admin,
        servicioFotos: fotos,
        alProgresar: (seccion) {
          if (!mounted) return;
          setState(() => _estado = seccion);
        },
      );

      if (!mounted) return;
      final sufijo =
          '${_anio.toString().padLeft(4, '0')}-${_mes.toString().padLeft(2, '0')}';
      final nombre =
          'pack-${_normalizar(instalacion)}-$sufijo.zip';

      await Share.shareXFiles(
        [
          XFile.fromData(
            zip,
            mimeType: 'application/zip',
            name: nombre,
          ),
        ],
        subject: 'Informe mensual Tomass Seguridad — '
            '${_nombreMes(_mes)} $_anio',
      );
    } catch (falla) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo armar el pack: '
              '${Traductor.traducir(falla).mensaje}'),
          backgroundColor: Colores.rojo,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _generando = false;
          _estado = '';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final hoy = DateTime.now();
    final mesAnterior = DateTime(hoy.year, hoy.month - 1, 1);
    final esActual = _anio == hoy.year && _mes == hoy.month;
    final esAnterior =
        _anio == mesAnterior.year && _mes == mesAnterior.month;
    final esCustom = !esActual && !esAnterior;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Informe mensual del mandante'),
        actions: const [MenuDelAdmin()],
      ),
      body: Padding(
        padding: const EdgeInsets.all(Medidas.margen),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Genera un archivo ZIP con los 5 informes del mes '
              '(accesos, turnos, rondas, novedades, encomiendas) listo '
              'para pasarle al mandante.',
              style: TextStyle(
                fontSize: 13.5,
                height: 1.45,
                color: Colores.textoSuave,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'MES A INCLUIR',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.1,
                color: Colores.textoSuave,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                ChoiceChip(
                  label: Text('${_nombreMes(mesAnterior.month)} '
                      '${mesAnterior.year}'),
                  selected: esAnterior,
                  onSelected:
                      _generando ? null : (_) => _mesAnterior(),
                ),
                ChoiceChip(
                  label: Text(
                      '${_nombreMes(hoy.month)} ${hoy.year}'),
                  selected: esActual,
                  onSelected: _generando ? null : (_) => _mesActual(),
                ),
                ChoiceChip(
                  label: const Text('Otro mes…'),
                  selected: esCustom,
                  onSelected:
                      _generando ? null : (_) => _elegirCustom(),
                ),
              ],
            ),
            if (esCustom) ...[
              const SizedBox(height: 10),
              Text(
                'Seleccionado: ${_nombreMes(_mes)} $_anio',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Colores.grafito,
                ),
              ),
            ],
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _generando ? null : _generar,
                icon: _generando
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.file_download_rounded, size: 18),
                label: Text(
                  _generando ? 'Generando…' : 'Generar y compartir',
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: Colores.grafito,
                  minimumSize: const Size(0, 46),
                ),
              ),
            ),
            if (_generando && _estado.isNotEmpty) ...[
              const SizedBox(height: 16),
              Card(
                color: Colores.grafito.withValues(alpha: 0.06),
                elevation: 0,
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colores.grafito,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _estado,
                          style: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                            color: Colores.grafito,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Puede tardar varios minutos — el PDF de turnos baja '
                'una selfie por cada guardia, y el de novedades baja '
                'las fotos de cada incidente. No cierres esta pantalla.',
                style: TextStyle(
                  fontSize: 11.5,
                  height: 1.4,
                  color: Colores.textoSuave,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static String _normalizar(String txt) {
    return txt
        .toLowerCase()
        .replaceAll(RegExp(r'[áà]'), 'a')
        .replaceAll(RegExp(r'[éè]'), 'e')
        .replaceAll(RegExp(r'[íì]'), 'i')
        .replaceAll(RegExp(r'[óò]'), 'o')
        .replaceAll(RegExp(r'[úù]'), 'u')
        .replaceAll('ñ', 'n')
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
  }

  static String _nombreMes(int mes) {
    const nombres = [
      'enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio',
      'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre',
    ];
    if (mes < 1 || mes > 12) return 'mes';
    return nombres[mes - 1];
  }
}
