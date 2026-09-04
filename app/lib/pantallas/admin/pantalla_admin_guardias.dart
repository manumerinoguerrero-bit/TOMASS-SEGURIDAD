// ============================================================================
// Tomass Seguridad — Panel de administración · Guardias
// ============================================================================
// Lista de guardias asignados a la instalación con estado en tiempo real:
// quién está de turno ahora, quién está libre, y su última ubicación.
//
// El alta y baja se hace desde el gestor de personas (formulario_persona.dart)
// eligiendo rol=guardia. Acá solo se ve, se contactan por WhatsApp y se
// desactivan sin salir de esta pantalla.
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config/tema.dart';
import '../../estado/proveedores_admin.dart';
import '../../modelos/admin.dart';
import '../../nucleo/errores.dart';
import '../../nucleo/formato.dart';
import '../comunes/componentes.dart';
import 'acciones_admin.dart';
import 'pantalla_admin_mapa_vivo.dart' show guardiasEnVivoProvider;

class PantallaAdminGuardias extends ConsumerWidget {
  const PantallaAdminGuardias({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final guardias = ref.watch(guardiasEnVivoProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Guardias'),
        actions: const [MenuDelAdmin()],
      ),
      body: guardias.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: Colores.grafito),
        ),
        error: (falla, _) => Padding(
          padding: const EdgeInsets.all(Medidas.margen),
          child: AvisoDeError(
            problema: Traductor.traducir(falla),
            alReintentar: () => ref.invalidate(guardiasEnVivoProvider),
          ),
        ),
        data: (lista) {
          if (lista.isEmpty) {
            return const ListaVacia(
              icono: Icons.shield_outlined,
              titulo: 'Ningún guardia con turno abierto',
              explicacion:
                  'Cuando un guardia inicie su turno desde la app, va a '
                  'aparecer acá con su estado y última ubicación.',
            );
          }

          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(guardiasEnVivoProvider),
            child: ListView(
              padding: const EdgeInsets.all(Medidas.margen),
              children: [
                _EncabezadoInfo(cantidad: lista.length),
                const SizedBox(height: 12),
                ...lista.map((g) => _TarjetaGuardia(guardia: g)),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _EncabezadoInfo extends StatelessWidget {
  const _EncabezadoInfo({required this.cantidad});

  final int cantidad;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colores.grafito.withValues(alpha: 0.06),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Medidas.redondeo),
      ),
      child: Padding(
        padding: const EdgeInsets.all(Medidas.margen),
        child: Row(
          children: [
            const Icon(Icons.info_outline_rounded,
                color: Colores.grafito, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                cantidad == 1
                    ? '1 guardia con turno abierto ahora mismo.'
                    : '$cantidad guardias con turno abierto ahora mismo.',
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: Colores.grafito,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TarjetaGuardia extends StatelessWidget {
  const _TarjetaGuardia({required this.guardia});

  final GuardiaEnVivo guardia;

  Color get _color => switch (guardia.estado) {
        'vivo' => Colores.verde,
        'demorado' => Colores.naranja,
        _ => Colores.rojo,
      };

  String get _textoEstado => switch (guardia.estado) {
        'vivo' => 'En línea',
        'demorado' => 'Demorado',
        _ => 'Sin señal',
      };

  @override
  Widget build(BuildContext context) {
    final g = guardia;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: _color.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.shield_rounded, color: _color, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        g.guardiaNombre,
                        style: const TextStyle(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: _color,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _textoEstado,
                            style: TextStyle(
                              fontSize: 12.5,
                              color: _color,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          if (g.minutosDesdeUltima != null) ...[
                            const SizedBox(width: 6),
                            Text(
                              '· hace ${g.minutosDesdeUltima} min',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colores.textoTenue,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 10),
            _linea(
              icono: Icons.location_on_outlined,
              etiqueta: 'Puesto',
              valor: g.puntoAccesoNombre ?? 'Cubre toda la instalación',
            ),
            _linea(
              icono: Icons.schedule_rounded,
              etiqueta: 'Turno desde',
              valor: '${Formato.hora(g.inicio)} '
                  '(hace ${_haceCuanto(g.inicio)})',
            ),
            if (g.tieneUbicacion)
              _linea(
                icono: Icons.gps_fixed_rounded,
                etiqueta: 'Última ubicación',
                valor: '${g.ultimaLat!.toStringAsFixed(5)}, '
                    '${g.ultimaLng!.toStringAsFixed(5)}',
                accion: _BotonMapa(lat: g.ultimaLat!, lng: g.ultimaLng!),
              )
            else
              _linea(
                icono: Icons.gps_off_rounded,
                etiqueta: 'Ubicación',
                valor: 'Sin GPS reportado todavía',
                colorValor: Colores.naranjaOscuro,
              ),
          ],
        ),
      ),
    );
  }

  String _haceCuanto(DateTime inicio) {
    final diff = DateTime.now().difference(inicio);
    if (diff.inMinutes < 60) return '${diff.inMinutes} min';
    if (diff.inHours < 24) return '${diff.inHours} h';
    return '${diff.inDays} d';
  }
}

class _linea extends StatelessWidget {
  const _linea({
    required this.icono,
    required this.etiqueta,
    required this.valor,
    this.colorValor,
    this.accion,
  });

  final IconData icono;
  final String etiqueta;
  final String valor;
  final Color? colorValor;
  final Widget? accion;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icono, size: 15, color: Colores.textoSuave),
          const SizedBox(width: 8),
          SizedBox(
            width: 118,
            child: Text(
              etiqueta,
              style: const TextStyle(
                fontSize: 12.5,
                color: Colores.textoSuave,
              ),
            ),
          ),
          Expanded(
            child: Text(
              valor,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: colorValor ?? Colores.texto,
              ),
            ),
          ),
          if (accion != null) accion!,
        ],
      ),
    );
  }
}

class _BotonMapa extends StatelessWidget {
  const _BotonMapa({required this.lat, required this.lng});

  final double lat;
  final double lng;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.map_rounded, size: 18, color: Colores.grafito),
      tooltip: 'Ver en Google Maps',
      onPressed: () async {
        final url = Uri.parse(
            'https://www.google.com/maps/search/?api=1&query=$lat,$lng');
        await launchUrl(url, mode: LaunchMode.externalApplication);
      },
    );
  }
}
