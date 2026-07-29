// ============================================================================
// Tomass Seguridad — Panel de administración · Vehículos por aprobar
// ============================================================================
// LA PANTALLA MÁS IMPORTANTE DEL PANEL
//
//   Un residente registra su auto y NO PUEDE ENTRAR CON ÉL hasta que alguien lo
//   apruebe. Cada día que un auto queda esperando es un residente que tiene que
//   bajarse en la barrera y explicarle al guardia.
//
//   Por eso la tarjeta muestra hace cuántos días espera, y a partir de tres
//   días se pone naranja.
//
// POR QUÉ EL RECHAZO PIDE UN MOTIVO OBLIGATORIO
//
//   Porque el residente lo va a leer. "Rechazado" a secas no le dice qué
//   corregir, y va a volver a registrar el mismo auto igual.
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/tema.dart';
import '../../estado/proveedores.dart';
import '../../estado/proveedores_admin.dart';
import '../../modelos/admin.dart';
import '../../nucleo/errores.dart';
import '../../nucleo/formato.dart';
import '../../servicios/servicio_fotos.dart';
import '../comunes/componentes.dart';
import 'acciones_admin.dart';

class PantallaAdminVehiculos extends ConsumerWidget {
  const PantallaAdminVehiculos({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vehiculos = ref.watch(vehiculosPorAprobarProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Vehículos por aprobar'),
        actions: const [MenuDelAdmin()],
      ),
      body: vehiculos.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: Colores.grafito),
        ),
        error: (falla, _) => Padding(
          padding: const EdgeInsets.all(Medidas.margen),
          child: AvisoDeError(
            problema: Traductor.traducir(falla),
            alReintentar: () => ref.invalidate(vehiculosPorAprobarProvider),
          ),
        ),
        data: (lista) {
          if (lista.isEmpty) {
            return const ListaVacia(
              icono: Icons.check_circle_outline_rounded,
              titulo: 'No hay vehículos esperando',
              explicacion:
                  'Cuando alguien registre un auto nuevo, va a aparecer acá '
                  'para que lo apruebes.',
            );
          }

          return RefreshIndicator(
            onRefresh: () async => refrescarPanel(ref),
            child: ListView.builder(
              padding: const EdgeInsets.all(Medidas.margen),
              itemCount: lista.length,
              itemBuilder: (_, i) => _Tarjeta(vehiculo: lista[i]),
            ),
          );
        },
      ),
    );
  }
}

class _Tarjeta extends ConsumerStatefulWidget {
  const _Tarjeta({required this.vehiculo});

  final VehiculoParaAprobar vehiculo;

  @override
  ConsumerState<_Tarjeta> createState() => _EstadoTarjeta();
}

class _EstadoTarjeta extends ConsumerState<_Tarjeta> {
  bool _trabajando = false;

  Future<void> _aprobar() async {
    setState(() => _trabajando = true);
    try {
      await ref.read(servicioAdminProvider).aprobarVehiculo(widget.vehiculo.id);
      if (!mounted) return;
      refrescarPanel(ref);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${widget.vehiculo.patente} aprobado. '
              '${widget.vehiculo.duenoNombre} ya puede entrar con él.'),
          backgroundColor: Colores.verde,
        ),
      );
    } catch (falla) {
      if (!mounted) return;
      setState(() => _trabajando = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(Traductor.traducir(falla).mensaje),
          backgroundColor: Colores.rojo,
        ),
      );
    }
  }

  Future<void> _rechazar() async {
    final motivo = TextEditingController();

    final confirmado = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Rechazar ${widget.vehiculo.patente}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Escribí por qué. El residente va a leer este texto, así que '
              'conviene decirle qué tiene que corregir.',
              style: TextStyle(fontSize: 13.5, height: 1.45),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: motivo,
              maxLines: 3,
              maxLength: 200,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Motivo del rechazo',
                hintText: 'Ej: la foto de la patente está borrosa, sacala de nuevo',
                alignLabelWithHint: true,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colores.rojo),
            child: const Text('Rechazar'),
          ),
        ],
      ),
    );

    final texto = motivo.text;
    motivo.dispose();
    if (confirmado != true || !mounted) return;

    setState(() => _trabajando = true);
    try {
      await ref
          .read(servicioAdminProvider)
          .rechazarVehiculo(widget.vehiculo.id, texto);
      if (!mounted) return;
      refrescarPanel(ref);
    } catch (falla) {
      if (!mounted) return;
      setState(() => _trabajando = false);
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
    final v = widget.vehiculo;
    final palabras = ref.watch(palabrasProvider);
    final llevaMucho = v.diasEsperando >= 3;

    return Card(
      margin: const EdgeInsets.only(bottom: 13),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Medidas.redondeo),
        side: BorderSide(
          color: llevaMucho ? Colores.naranja.withValues(alpha: 0.6) : Colores.linea,
          width: llevaMucho ? 1.5 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(Medidas.margen),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ---- La patente, bien grande ----
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: Colores.grafito,
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Text(
                    v.patente,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 2.5,
                    ),
                  ),
                ),
                const Spacer(),
                Etiqueta(
                  texto: v.diasEsperando == 0
                      ? 'Hoy'
                      : 'Hace ${v.diasEsperando} '
                          '${v.diasEsperando == 1 ? "día" : "días"}',
                  tono: llevaMucho ? TonoEtiqueta.espera : TonoEtiqueta.neutro,
                ),
              ],
            ),
            const SizedBox(height: 11),

            Text(
              [v.descripcion, v.color].where((t) => t.isNotEmpty).join(' · '),
              style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600),
            ),

            const SizedBox(height: 13),
            const Divider(height: 1),
            const SizedBox(height: 13),

            // ---- De quién es ----
            Row(
              children: [
                const Icon(Icons.person_outline_rounded,
                    size: 19, color: Colores.textoTenue),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(v.duenoNombre,
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w700)),
                      Text(
                        [
                          if (v.duenoEspacio != null)
                            '${palabras.elEspacioConMayuscula} ${v.duenoEspacio}',
                          if (v.duenoTelefono != null) v.duenoTelefono!,
                        ].join(' · '),
                        style: const TextStyle(
                            fontSize: 12, color: Colores.textoSuave),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            // ---- Las fotos ----
            if (v.fotoUrl != null || v.fotoPatenteUrl != null) ...[
              const SizedBox(height: 13),
              SizedBox(
                height: 96,
                child: Row(
                  children: [
                    if (v.fotoUrl != null)
                      Expanded(
                        child: _Foto(ruta: v.fotoUrl!, etiqueta: 'El auto'),
                      ),
                    if (v.fotoUrl != null && v.fotoPatenteUrl != null)
                      const SizedBox(width: 9),
                    if (v.fotoPatenteUrl != null)
                      Expanded(
                        child:
                            _Foto(ruta: v.fotoPatenteUrl!, etiqueta: 'La patente'),
                      ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 15),

            // ---- Los dos botones ----
            if (_trabajando)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(8),
                  child: CircularProgressIndicator(color: Colores.grafito),
                ),
              )
            else
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _rechazar,
                      icon: const Icon(Icons.close_rounded, size: 19),
                      label: const Text('Rechazar'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colores.rojo,
                        side: const BorderSide(color: Colores.rojo),
                        minimumSize: const Size(0, Medidas.altoBoton),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: FilledButton.icon(
                      onPressed: _aprobar,
                      icon: const Icon(Icons.check_rounded, size: 20),
                      label: const Text('Aprobar'),
                      style: FilledButton.styleFrom(
                        backgroundColor: Colores.verde,
                        minimumSize: const Size(0, Medidas.altoBoton),
                      ),
                    ),
                  ),
                ],
              ),

            const SizedBox(height: 4),
            Text(
              'Registrado el ${Formato.fecha(v.creadoEn)}',
              style: const TextStyle(fontSize: 11, color: Colores.textoTenue),
            ),
          ],
        ),
      ),
    );
  }
}

class _Foto extends StatelessWidget {
  const _Foto({required this.ruta, required this.etiqueta});

  final String ruta;
  final String etiqueta;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(etiqueta,
            style: const TextStyle(fontSize: 10.5, color: Colores.textoTenue)),
        const SizedBox(height: 4),
        Expanded(
          child: FotoDelServidor(
            ruta: ruta,
            cajon: CajonDeFotos.vehiculos,
            ancho: double.infinity,
            alto: double.infinity,
            redondeo: Medidas.redondeoChico,
            iconoSiFalta: Icons.directions_car_rounded,
          ),
        ),
      ],
    );
  }
}
