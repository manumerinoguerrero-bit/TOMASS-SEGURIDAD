// ============================================================================
// Tomass Seguridad — Pantalla 06 · Mis vehículos
// ============================================================================
// El residente registra sus propios autos y el administrador los aprueba.
//
// POR QUÉ ES EL RESIDENTE Y NO LA ADMINISTRACIÓN QUIEN LOS CARGA
//   Porque son 150 unidades y muchas con dos autos. Si los cargara la
//   administración, alguien tendría que tipear 200 patentes y perseguir a la
//   gente por los datos. Así cada uno carga el suyo con una foto, y a la
//   administración solo le queda mirar y aprobar.
//
// UN AUTO PENDIENTE SE VE CLARAMENTE DISTINTO DE UNO APROBADO
//   Es la causa número uno de discusiones en la barrera: el residente cree que
//   su auto está listo y el guardia no lo deja pasar. Acá el estado se ve de
//   lejos, con color y con el texto de qué falta.
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/tema.dart';
import '../../estado/proveedores.dart';
import '../../modelos/modelos.dart';
import '../../nucleo/errores.dart';
import '../../nucleo/formato.dart';
import '../../servicios/servicio_fotos.dart';
import '../comunes/componentes.dart';
import 'formulario_vehiculo.dart';

class PantallaVehiculos extends ConsumerWidget {
  const PantallaVehiculos({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vehiculos = ref.watch(misVehiculosProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mis vehículos'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_rounded),
            tooltip: 'Agregar un vehículo',
            onPressed: () => _abrirFormulario(context),
          ),
        ],
      ),
      body: vehiculos.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: Colores.grafito),
        ),
        error: (falla, _) => Padding(
          padding: const EdgeInsets.all(Medidas.margen),
          child: AvisoDeError(
            problema: Traductor.traducir(falla),
            alReintentar: () => ref.invalidate(misVehiculosProvider),
          ),
        ),
        data: (lista) {
          if (lista.isEmpty) {
            return ListaVacia(
              icono: Icons.directions_car_outlined,
              titulo: 'Todavía no registraste ningún vehículo',
              explicacion:
                  'Registrá tu auto para poder entrar por la barrera sin bajarte. '
                  'Le sacás una foto a la patente y la app la lee sola.',
              accion: ElevatedButton.icon(
                onPressed: () => _abrirFormulario(context),
                icon: const Icon(Icons.add_rounded, size: 20),
                label: const Text('Agregar mi primer vehículo'),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(0, Medidas.altoBoton),
                  padding: const EdgeInsets.symmetric(horizontal: 22),
                ),
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(misVehiculosProvider),
            child: ListView.separated(
              padding: const EdgeInsets.all(Medidas.margen),
              itemCount: lista.length + 1,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, i) {
                if (i == lista.length) {
                  return Padding(
                    padding: const EdgeInsets.only(top: 6, bottom: 20),
                    child: OutlinedButton.icon(
                      onPressed: () => _abrirFormulario(context),
                      icon: const Icon(Icons.add_rounded, size: 20),
                      label: const Text('Agregar otro vehículo'),
                    ),
                  );
                }
                return _TarjetaVehiculo(vehiculo: lista[i]);
              },
            ),
          );
        },
      ),
    );
  }

  void _abrirFormulario(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const FormularioVehiculo()),
    );
  }
}

class _TarjetaVehiculo extends ConsumerWidget {
  const _TarjetaVehiculo({required this.vehiculo});

  final Vehiculo vehiculo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (color, tono, mensaje) = switch (vehiculo.estado) {
      EstadoVehiculo.aprobado => (
          Colores.verde,
          TonoEtiqueta.bueno,
          null,
        ),
      EstadoVehiculo.pendiente => (
          Colores.naranja,
          TonoEtiqueta.espera,
          'Esperando la aprobación de la administración desde '
              '${Formato.haceCuanto(vehiculo.creadoEn)}. Todavía no sirve para '
              'entrar por la barrera.',
        ),
      EstadoVehiculo.rechazado => (
          Colores.rojo,
          TonoEtiqueta.malo,
          vehiculo.motivoRechazo == null
              ? 'La administración lo rechazó. Consultá el motivo en la portería.'
              : 'La administración lo rechazó: ${vehiculo.motivoRechazo}',
        ),
    };

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Medidas.redondeo),
        side: BorderSide(
          color: vehiculo.estado == EstadoVehiculo.aprobado
              ? Colores.linea
              : color,
          width: vehiculo.estado == EstadoVehiculo.aprobado ? 1 : 1.4,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(13),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FotoDelServidor(
                  ruta: vehiculo.fotoUrl,
                  cajon: CajonDeFotos.vehiculos,
                  ancho: 84,
                  alto: 62,
                  iconoSiFalta: Icons.directions_car_outlined,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        vehiculo.patente,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.4,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        vehiculo.descripcion,
                        style: const TextStyle(
                          fontSize: 13,
                          color: Colores.textoSuave,
                        ),
                      ),
                      if (vehiculo.anio != null)
                        Text(
                          'Año ${vehiculo.anio}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colores.textoTenue,
                          ),
                        ),
                      const SizedBox(height: 8),
                      Etiqueta(
                        texto: vehiculo.estado.nombreVisible,
                        tono: tono,
                        icono: switch (vehiculo.estado) {
                          EstadoVehiculo.aprobado => Icons.check_rounded,
                          EstadoVehiculo.pendiente => Icons.schedule_rounded,
                          EstadoVehiculo.rechazado => Icons.close_rounded,
                        },
                      ),
                    ],
                  ),
                ),
                if (vehiculo.estado != EstadoVehiculo.aprobado)
                  IconButton(
                    icon: const Icon(Icons.delete_outline_rounded, size: 21),
                    color: Colores.textoSuave,
                    tooltip: 'Quitar este vehículo',
                    onPressed: () => _confirmarBorrado(context, ref),
                  ),
              ],
            ),
            if (mensaje != null) ...[
              const SizedBox(height: 11),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(Medidas.redondeoChico),
                ),
                child: Text(
                  mensaje,
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.45,
                    color: vehiculo.estado == EstadoVehiculo.pendiente
                        ? Colores.naranjaOscuro
                        : Colores.rojoOscuro,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _confirmarBorrado(BuildContext context, WidgetRef ref) async {
    final seguro = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('¿Quitar el ${vehiculo.patente}?'),
        content: const Text(
          'Se borra de tu lista junto con sus fotos. Si después lo querés de '
          'vuelta, hay que registrarlo de nuevo y esperar la aprobación otra vez.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colores.rojo),
            child: const Text('Sí, quitarlo'),
          ),
        ],
      ),
    );

    if (seguro != true || !context.mounted) return;

    try {
      await ref.read(servicioResidenteProvider).borrarVehiculo(vehiculo);
      ref.invalidate(misVehiculosProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Se quitó el ${vehiculo.patente}.')),
        );
      }
    } catch (falla) {
      if (!context.mounted) return;
      final problema = Traductor.traducir(falla);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(problema.mensaje),
          backgroundColor: Colores.rojo,
        ),
      );
    }
  }
}
