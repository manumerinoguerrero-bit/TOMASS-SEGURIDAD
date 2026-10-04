// ============================================================================
// Tomass Seguridad — Recorrido de actividad del turno
// ============================================================================
// Dibuja sobre un mapa de calles los puntos donde el guardia hizo algo
// durante el turno: dónde abrió el turno, dónde escaneó cada cartel de
// ronda, dónde registró cada ingreso/salida, y dónde fue visto por última
// vez por el rastreador GPS.
//
// Los puntos se conectan con una polyline cronológica para que se vea el
// orden en que anduvo. Al tocar un punto se muestra qué pasó en ese lugar
// y a qué hora.
//
// NO ES UN GPS CONTINUO
//
//   El rastreador GPS sobrescribe la última ubicación en vez de guardar
//   una muestra cada 3 minutos (eso requeriría una tabla aparte, se puede
//   agregar más adelante). Lo que se ve acá son las ACCIONES del turno —
//   no cada paso. Para el 90% de los casos (demostrarle al mandante que
//   el guardia recorrió el condominio) alcanza y sobra.
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../config/tema.dart';
import '../../estado/proveedores_admin.dart';
import '../../modelos/admin.dart';
import '../../nucleo/errores.dart';
import '../../nucleo/formato.dart';
import '../comunes/componentes.dart';
import 'acciones_admin.dart';

final _recorridoProvider = FutureProvider.autoDispose
    .family<List<PuntoDelRecorrido>, String>((ref, turnoId) {
  return ref.watch(servicioAdminProvider).recorridoDelTurno(turnoId);
});

class PantallaAdminRecorridoTurno extends ConsumerStatefulWidget {
  const PantallaAdminRecorridoTurno({
    super.key,
    required this.turnoId,
    required this.guardia,
    required this.inicio,
  });

  final String turnoId;
  final String guardia;
  final DateTime inicio;

  @override
  ConsumerState<PantallaAdminRecorridoTurno> createState() =>
      _EstadoRecorrido();
}

class _EstadoRecorrido
    extends ConsumerState<PantallaAdminRecorridoTurno> {
  final _mapaCtrl = MapController();
  int? _puntoSeleccionado;

  @override
  Widget build(BuildContext context) {
    final datos = ref.watch(_recorridoProvider(widget.turnoId));

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Recorrido del turno'),
            Text(
              '${Formato.nombreCorto(widget.guardia)} · '
              '${Formato.fechaYHora(widget.inicio.toLocal())}',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w400,
                color: Colors.white.withValues(alpha: 0.75),
              ),
            ),
          ],
        ),
        actions: const [MenuDelAdmin()],
      ),
      body: datos.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: Colores.grafito),
        ),
        error: (falla, _) => Padding(
          padding: const EdgeInsets.all(Medidas.margen),
          child: AvisoDeError(
            problema: Traductor.traducir(falla),
            alReintentar: () =>
                ref.invalidate(_recorridoProvider(widget.turnoId)),
          ),
        ),
        data: (puntos) {
          if (puntos.isEmpty) {
            return const ListaVacia(
              icono: Icons.location_off_rounded,
              titulo: 'No hay puntos con GPS en este turno',
              explicacion:
                  'El guardia no abrió el turno con ubicación activada, no '
                  'escaneó carteles de ronda ni se registraron accesos con '
                  'coordenadas. No se puede dibujar el recorrido.',
            );
          }
          return _MapaConRecorrido(
            puntos: puntos,
            mapaCtrl: _mapaCtrl,
            puntoSeleccionado: _puntoSeleccionado,
            alElegir: (i) => setState(() => _puntoSeleccionado = i),
          );
        },
      ),
    );
  }
}

// ============================================================================

class _MapaConRecorrido extends StatelessWidget {
  const _MapaConRecorrido({
    required this.puntos,
    required this.mapaCtrl,
    required this.puntoSeleccionado,
    required this.alElegir,
  });

  final List<PuntoDelRecorrido> puntos;
  final MapController mapaCtrl;
  final int? puntoSeleccionado;
  final ValueChanged<int?> alElegir;

  @override
  Widget build(BuildContext context) {
    // Centro = promedio de todos los puntos
    double sumaLat = 0, sumaLng = 0;
    for (final p in puntos) {
      sumaLat += p.latitud;
      sumaLng += p.longitud;
    }
    final centro = LatLng(sumaLat / puntos.length, sumaLng / puntos.length);

    final polyline = Polyline(
      points: puntos.map((p) => LatLng(p.latitud, p.longitud)).toList(),
      color: Colores.grafito.withValues(alpha: 0.75),
      strokeWidth: 3.5,
      pattern: StrokePattern.dashed(segments: const [10, 6]),
    );

    final elegido = puntoSeleccionado;

    return Column(
      children: [
        Expanded(
          flex: 3,
          child: FlutterMap(
            mapController: mapaCtrl,
            options: MapOptions(
              initialCenter: centro,
              initialZoom: _zoomInicial(puntos),
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.pinchZoom |
                    InteractiveFlag.drag |
                    InteractiveFlag.doubleTapZoom,
              ),
            ),
            children: [
              TileLayer(
                urlTemplate:
                    'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'cl.tomass.tomass_seguridad',
                maxNativeZoom: 19,
              ),
              PolylineLayer(polylines: [polyline]),
              MarkerLayer(
                markers: [
                  for (var i = 0; i < puntos.length; i++)
                    Marker(
                      point:
                          LatLng(puntos[i].latitud, puntos[i].longitud),
                      width: 36,
                      height: 36,
                      child: GestureDetector(
                        onTap: () => alElegir(i),
                        child: _IconoPunto(
                          numero: i + 1,
                          tipo: puntos[i].tipo,
                          resaltado: elegido == i,
                        ),
                      ),
                    ),
                ],
              ),
              const RichAttributionWidget(
                attributions: [
                  TextSourceAttribution('© OpenStreetMap'),
                ],
              ),
            ],
          ),
        ),
        _Timeline(
          puntos: puntos,
          seleccionado: elegido,
          alElegir: (i) {
            alElegir(i);
            mapaCtrl.move(
              LatLng(puntos[i].latitud, puntos[i].longitud),
              18,
            );
          },
        ),
      ],
    );
  }

  static double _zoomInicial(List<PuntoDelRecorrido> p) {
    if (p.length == 1) return 17;
    double minLat = 90, maxLat = -90, minLng = 180, maxLng = -180;
    for (final x in p) {
      if (x.latitud < minLat) minLat = x.latitud;
      if (x.latitud > maxLat) maxLat = x.latitud;
      if (x.longitud < minLng) minLng = x.longitud;
      if (x.longitud > maxLng) maxLng = x.longitud;
    }
    final rango = (maxLat - minLat).abs() > (maxLng - minLng).abs()
        ? (maxLat - minLat).abs()
        : (maxLng - minLng).abs();
    if (rango < 0.001) return 18;
    if (rango < 0.003) return 17;
    if (rango < 0.008) return 16;
    if (rango < 0.02) return 15;
    if (rango < 0.05) return 14;
    return 13;
  }
}

// ============================================================================
// Icono del marker en el mapa — color por tipo
// ============================================================================

class _IconoPunto extends StatelessWidget {
  const _IconoPunto({
    required this.numero,
    required this.tipo,
    required this.resaltado,
  });

  final int numero;
  final String tipo;
  final bool resaltado;

  @override
  Widget build(BuildContext context) {
    final color = _color(tipo);
    final size = resaltado ? 36.0 : 28.0;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: Text(
        '$numero',
        style: TextStyle(
          color: Colors.white,
          fontSize: resaltado ? 13 : 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  static Color _color(String tipo) {
    switch (tipo) {
      case 'apertura':
        return Colores.verdeOscuro;
      case 'marca_ronda':
        return Colores.grafito;
      case 'acceso':
        return Colores.dorado;
      case 'ultima_vista':
        return Colores.rojo;
      default:
        return Colores.textoSuave;
    }
  }
}

// ============================================================================
// Timeline cronológico abajo del mapa — scroll horizontal con los puntos
// ============================================================================

class _Timeline extends StatelessWidget {
  const _Timeline({
    required this.puntos,
    required this.seleccionado,
    required this.alElegir,
  });

  final List<PuntoDelRecorrido> puntos;
  final int? seleccionado;
  final ValueChanged<int> alElegir;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 160,
      color: Colores.superficie,
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding:
                EdgeInsets.symmetric(horizontal: Medidas.margen),
            child: Text(
              'LÍNEA DE TIEMPO',
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.1,
                color: Colores.textoSuave,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(
                  horizontal: Medidas.margen),
              itemCount: puntos.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final p = puntos[i];
                final resaltado = seleccionado == i;
                return SizedBox(
                  width: 180,
                  child: Card(
                    elevation: 0,
                    color: resaltado
                        ? Colores.grafito.withValues(alpha: 0.14)
                        : Colores.grafito.withValues(alpha: 0.05),
                    shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(Medidas.redondeo),
                      side: BorderSide(
                        color: resaltado
                            ? Colores.grafito
                            : Colors.transparent,
                        width: 1.5,
                      ),
                    ),
                    child: InkWell(
                      onTap: () => alElegir(i),
                      borderRadius:
                          BorderRadius.circular(Medidas.redondeo),
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              children: [
                                _ChipTipo(tipo: p.tipo, numero: i + 1),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    Formato.hora(p.cuando.toLocal()),
                                    style: const TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              p.descripcion,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 11.5,
                                height: 1.3,
                                color: Colores.texto,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ChipTipo extends StatelessWidget {
  const _ChipTipo({required this.tipo, required this.numero});
  final String tipo;
  final int numero;

  @override
  Widget build(BuildContext context) {
    final color = _IconoPunto._color(tipo);
    return Container(
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        '$numero',
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          color: Colors.white,
        ),
      ),
    );
  }
}
