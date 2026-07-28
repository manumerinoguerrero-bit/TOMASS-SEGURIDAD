// ============================================================================
// Tomass Seguridad — El código de la visita, para mostrar y compartir
// ============================================================================
// Se abre desde abajo cuando el residente toca una visita activa.
//
// EL BOTÓN DE COMPARTIR ES LO PRINCIPAL
//   El residente no le va a mostrar la pantalla de su celular al visitante: se lo
//   manda por WhatsApp antes de que llegue. Por eso el botón de compartir es el
//   que más pesa, y el QR está para el caso en que el visitante ya esté ahí.
//
// EL TEXTO QUE SE COMPARTE INCLUYE LA EXPLICACIÓN
//   No solo el código. Va con el nombre del condominio, el horario y la
//   aclaración de que sirve una sola vez. Así el visitante entiende qué recibió
//   sin tener que preguntar.
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../config/tema.dart';
import '../../estado/proveedores.dart';
import '../../modelos/modelos.dart';
import '../../nucleo/errores.dart';
import '../../nucleo/formato.dart';

Future<void> mostrarCodigoDeVisita(
  BuildContext context,
  WidgetRef ref,
  Visita visita,
) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colores.superficie,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _HojaDelCodigo(visita: visita),
  );
}

class _HojaDelCodigo extends ConsumerStatefulWidget {
  const _HojaDelCodigo({required this.visita});

  final Visita visita;

  @override
  ConsumerState<_HojaDelCodigo> createState() => _EstadoHoja();
}

class _EstadoHoja extends ConsumerState<_HojaDelCodigo> {
  bool _cancelando = false;

  Future<void> _compartir() async {
    final perfil = ref.read(perfilProvider).valueOrNull;
    final mensaje = widget.visita.mensajeParaCompartir(
      perfil?.nombreCondominio ?? ref.read(palabrasProvider).instalacionSinArticulo,
      perfil?.unidad,
    );

    try {
      await Share.share(mensaje, subject: 'Tu código de acceso');
    } catch (_) {
      if (!mounted) return;
      // Si no se pudo abrir el menú de compartir, al menos se copia el texto
      await Clipboard.setData(ClipboardData(text: mensaje));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Copiamos el mensaje. Pegalo en WhatsApp.'),
        ),
      );
    }
  }

  Future<void> _cancelar() async {
    final seguro = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Dar de baja este código?'),
        content: Text(
          'El código de ${widget.visita.nombreVisitante} deja de servir al '
          'instante. Si después querés que venga, hay que generarle uno nuevo.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('No, dejalo'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colores.rojo),
            child: const Text('Sí, darlo de baja'),
          ),
        ],
      ),
    );

    if (seguro != true || !mounted) return;

    setState(() => _cancelando = true);
    try {
      await ref.read(servicioResidenteProvider).cancelarVisita(widget.visita.id);
      ref.invalidate(misVisitasProvider);
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('El código ya no sirve.')),
      );
    } catch (falla) {
      if (!mounted) return;
      setState(() => _cancelando = false);
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
    final desde = v.validoDesde.toLocal();
    final hasta = v.validoHasta.toLocal();

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(22, 12, 22, 22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Manija de la hoja
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: Colores.linea,
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            Text(
              v.nombreVisitante,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 4),
            Text(
              'Código de acceso · sirve una sola vez',
              style: Theme.of(context).textTheme.bodySmall,
            ),

            const SizedBox(height: 20),

            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(Medidas.redondeo),
                border: Border.all(color: Colores.linea),
              ),
              child: QrImageView(
                data: v.tokenQr,
                version: QrVersions.auto,
                size: 210,
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
            ),

            const SizedBox(height: 18),

            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(
                color: Colores.grafito.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(Medidas.redondeoChico),
              ),
              child: Column(
                children: [
                  _Dato(
                    icono: Icons.event_available_rounded,
                    etiqueta: 'Sirve desde',
                    valor: '${Formato.fecha(desde)} a las ${Formato.hora(desde)}',
                  ),
                  const SizedBox(height: 8),
                  _Dato(
                    icono: Icons.event_busy_rounded,
                    etiqueta: 'Vence',
                    valor: '${Formato.fecha(hasta)} a las ${Formato.hora(hasta)}',
                  ),
                  if (v.patenteVehiculo != null) ...[
                    const SizedBox(height: 8),
                    _Dato(
                      icono: Icons.directions_car_rounded,
                      etiqueta: 'Viene en auto',
                      valor: v.patenteVehiculo!,
                    ),
                  ],
                  if (v.cedulaVisitante != null) ...[
                    const SizedBox(height: 8),
                    _Dato(
                      icono: Icons.badge_outlined,
                      etiqueta: 'Cédula',
                      valor: v.cedulaVisitante!,
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 18),

            ElevatedButton.icon(
              onPressed: _compartir,
              icon: const Icon(Icons.share_rounded, size: 20),
              label: const Text('Compartir por WhatsApp'),
              style: ElevatedButton.styleFrom(backgroundColor: Colores.verde),
            ),

            const SizedBox(height: 9),

            OutlinedButton.icon(
              onPressed: _cancelando ? null : _cancelar,
              icon: _cancelando
                  ? const SizedBox(
                      width: 17,
                      height: 17,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colores.rojo,
                      ),
                    )
                  : const Icon(Icons.block_rounded, size: 19),
              label: const Text('Dar de baja el código'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colores.rojo,
                side: const BorderSide(color: Colores.rojo, width: 1.4),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Dato extends StatelessWidget {
  const _Dato({
    required this.icono,
    required this.etiqueta,
    required this.valor,
  });

  final IconData icono;
  final String etiqueta;
  final String valor;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icono, size: 16, color: Colores.textoSuave),
        const SizedBox(width: 10),
        Text(
          etiqueta,
          style: const TextStyle(fontSize: 12.5, color: Colores.textoSuave),
        ),
        const Spacer(),
        Text(
          valor,
          style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}
