// ============================================================================
// Tomass Seguridad — Mapa en vivo de guardias activos
// ============================================================================
// LO QUE MUESTRA
//
//   Un mapa con la última ubicación conocida de cada guardia con turno
//   abierto en la instalación. Se refresca solo cada 30 segundos.
//
//   Cada guardia aparece con un pin de color:
//     Verde  → mandó su GPS hace menos de 10 min  (VIVO)
//     Amarillo → hace 10 a 30 min                 (DEMORADO)
//     Rojo   → hace más de 30 min o nunca         (FRÍO)
//
// POR QUÉ CADA 30 SEGUNDOS Y NO EN VIVO REAL
//
//   El guardia manda su posición cada 3 minutos: no tiene sentido pedirla
//   más seguido que eso. Refrescar cada 30s es un compromiso entre
//   sensación de "en vivo" y no cargar el celular del admin con red.
//
// USA FLUTTER_MAP + OPENSTREETMAP
//
//   No requiere API key ni facturación (Google Maps sí). Los tiles vienen
//   directo de tile.openstreetmap.org, gratis para uso moderado.
// ============================================================================

import 'dart:async';

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

/// Guardias con turno abierto y última ubicación conocida. Se refresca solo.
final guardiasEnVivoProvider = FutureProvider<List<GuardiaEnVivo>>((ref) {
  return ref.watch(servicioAdminProvider).guardiasActivosEnVivo();
});

class PantallaAdminMapaVivo extends ConsumerStatefulWidget {
  const PantallaAdminMapaVivo({super.key});

  @override
  ConsumerState<PantallaAdminMapaVivo> createState() => _EstadoMapaVivo();
}

class _EstadoMapaVivo extends ConsumerState<PantallaAdminMapaVivo> {
  final _mapa = MapController();
  Timer? _refresco;

  @override
  void initState() {
    super.initState();
    // Auto-refresh cada 30s.
    _refresco = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) ref.invalidate(guardiasEnVivoProvider);
    });
  }

  @override
  void dispose() {
    _refresco?.cancel();
    _mapa.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final guardias = ref.watch(guardiasEnVivoProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mapa en vivo'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Actualizar ahora',
            onPressed: () => ref.invalidate(guardiasEnVivoProvider),
          ),
          const MenuDelAdmin(),
        ],
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
          final conUbicacion =
              lista.where((g) => g.tieneUbicacion).toList();

          if (lista.isEmpty) {
            return const ListaVacia(
              icono: Icons.location_off_outlined,
              titulo: 'Ningún guardia activo ahora',
              explicacion:
                  'Cuando un guardia abra su turno, va a aparecer acá con '
                  'su última posición.',
            );
          }

          if (conUbicacion.isEmpty) {
            return _SinUbicaciones(guardias: lista);
          }

          final centro = _centro(conUbicacion);

          return Column(
            children: [
              Expanded(
                child: FlutterMap(
                  mapController: _mapa,
                  options: MapOptions(
                    initialCenter: centro,
                    initialZoom: 17,
                    minZoom: 3,
                    maxZoom: 19,
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'cl.tomass.tomass_seguridad',
                      maxNativeZoom: 19,
                    ),
                    MarkerLayer(
                      markers: [
                        for (final g in conUbicacion)
                          Marker(
                            point: LatLng(g.ultimaLat!, g.ultimaLng!),
                            width: 46,
                            height: 60,
                            alignment: Alignment.bottomCenter,
                            child: _PinGuardia(
                              guardia: g,
                              alTocar: () => _abrirDetalle(g),
                            ),
                          ),
                      ],
                    ),
                    // Atribución obligatoria de OpenStreetMap
                    const RichAttributionWidget(
                      attributions: [
                        TextSourceAttribution('© OpenStreetMap'),
                      ],
                    ),
                  ],
                ),
              ),

              // Barra inferior: lista compacta scrollable de guardias
              Container(
                decoration: const BoxDecoration(
                  color: Colores.superficie,
                  border: Border(
                    top: BorderSide(color: Colores.linea),
                  ),
                ),
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: SizedBox(
                  height: 92,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    itemCount: lista.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 10),
                    itemBuilder: (_, i) => _TarjetaGuardia(
                      guardia: lista[i],
                      alTocar: () {
                        if (lista[i].tieneUbicacion) {
                          _mapa.move(
                            LatLng(
                                lista[i].ultimaLat!, lista[i].ultimaLng!),
                            18,
                          );
                        }
                        _abrirDetalle(lista[i]);
                      },
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  LatLng _centro(List<GuardiaEnVivo> guardias) {
    var lat = 0.0, lng = 0.0;
    for (final g in guardias) {
      lat += g.ultimaLat!;
      lng += g.ultimaLng!;
    }
    return LatLng(lat / guardias.length, lng / guardias.length);
  }

  void _abrirDetalle(GuardiaEnVivo g) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colores.superficie,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _DetalleGuardia(guardia: g),
    );
  }
}

// ============================================================================
// EL PIN QUE VA EN EL MAPA
// ============================================================================

class _PinGuardia extends StatelessWidget {
  const _PinGuardia({required this.guardia, required this.alTocar});

  final GuardiaEnVivo guardia;
  final VoidCallback alTocar;

  Color get _color => switch (guardia.estado) {
        'vivo' => Colores.verde,
        'demorado' => Colores.naranja,
        _ => Colores.rojo,
      };

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: alTocar,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: _color,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 3),
              boxShadow: [
                BoxShadow(
                  color: _color.withValues(alpha: 0.45),
                  blurRadius: 10,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: const Icon(
              Icons.shield_rounded,
              color: Colors.white,
              size: 20,
            ),
          ),
          Container(
            width: 3,
            height: 8,
            color: _color,
          ),
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: _color,
              shape: BoxShape.circle,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// TARJETA CHICA DE UN GUARDIA (barra inferior)
// ============================================================================

class _TarjetaGuardia extends StatelessWidget {
  const _TarjetaGuardia({required this.guardia, required this.alTocar});

  final GuardiaEnVivo guardia;
  final VoidCallback alTocar;

  @override
  Widget build(BuildContext context) {
    final color = switch (guardia.estado) {
      'vivo' => Colores.verde,
      'demorado' => Colores.naranja,
      _ => Colores.rojo,
    };

    return GestureDetector(
      onTap: alTocar,
      child: Container(
        width: 210,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: Colores.fondo,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.4), width: 1.2),
        ),
        child: Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    guardia.guardiaNombre,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _subtitulo(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      color: color,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    guardia.puntoAccesoNombre ?? 'Todo el condominio',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 10.5,
                      color: Colores.textoSuave,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _subtitulo() {
    if (guardia.minutosDesdeUltima == null) return 'Sin GPS';
    final m = guardia.minutosDesdeUltima!;
    if (m < 1) return 'Hace instantes';
    if (m == 1) return 'Hace 1 min';
    return 'Hace $m min';
  }
}

// ============================================================================
// DETALLE DEL GUARDIA (bottom sheet)
// ============================================================================

class _DetalleGuardia extends StatelessWidget {
  const _DetalleGuardia({required this.guardia});

  final GuardiaEnVivo guardia;

  @override
  Widget build(BuildContext context) {
    final g = guardia;
    final color = switch (g.estado) {
      'vivo' => Colores.verde,
      'demorado' => Colores.naranja,
      _ => Colores.rojo,
    };
    final estadoTexto = switch (g.estado) {
      'vivo' => 'En línea',
      'demorado' => 'Demorado',
      _ => 'Sin señal',
    };

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(Medidas.margen),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.shield_rounded, color: color, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        g.guardiaNombre,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        estadoTexto,
                        style: TextStyle(
                          fontSize: 13,
                          color: color,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _fila('Puesto', g.puntoAccesoNombre ?? 'Todo el condominio'),
            _fila('Comenzó', Formato.fechaYHora(g.inicio)),
            _fila(
                'Última ubicación',
                g.ultimaUbicacionEn == null
                    ? 'Nunca reportó posición'
                    : '${Formato.hora(g.ultimaUbicacionEn!)} '
                        '(hace ${g.minutosDesdeUltima} min)'),
            if (g.tieneUbicacion)
              _fila(
                'Coordenadas',
                '${g.ultimaLat!.toStringAsFixed(6)}, '
                    '${g.ultimaLng!.toStringAsFixed(6)}',
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _fila(String etiqueta, String valor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              etiqueta,
              style: const TextStyle(
                fontSize: 12,
                color: Colores.textoSuave,
              ),
            ),
          ),
          Expanded(
            child: Text(
              valor,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// CASO SIN UBICACIONES: hay guardias activos pero ninguno reportó todavía
// ============================================================================

class _SinUbicaciones extends StatelessWidget {
  const _SinUbicaciones({required this.guardias});

  final List<GuardiaEnVivo> guardias;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(Medidas.margen),
      child: Column(
        children: [
          Card(
            color: Colores.naranja.withValues(alpha: 0.08),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(Medidas.redondeo),
              side: BorderSide(color: Colores.naranja.withValues(alpha: 0.4)),
            ),
            child: const Padding(
              padding: EdgeInsets.all(Medidas.margen),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline_rounded,
                      color: Colores.naranjaOscuro, size: 22),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Hay guardias con turno abierto, pero ninguno reportó '
                      'su ubicación todavía. Puede tardar hasta 3 min desde '
                      'que abren el turno.',
                      style: TextStyle(fontSize: 13, height: 1.5),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          ...guardias.map((g) => Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: const Icon(Icons.shield_rounded,
                      color: Colores.textoSuave),
                  title: Text(g.guardiaNombre),
                  subtitle: Text(
                    'Desde ${Formato.hora(g.inicio)} · '
                    '${g.puntoAccesoNombre ?? "Todo el condominio"}',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              )),
        ],
      ),
    );
  }
}
