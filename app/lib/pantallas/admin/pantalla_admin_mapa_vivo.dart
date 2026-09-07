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
import '../../estado/proveedores.dart';
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

          // Layout estilo Merlyn: mapa a pantalla completa con overlays
          // flotantes. Antes teníamos una barra inferior fija que le
          // comía altura al mapa; con overlays el mapa es más grande y
          // el resto se apoya arriba como Cards con sombra.
          return Stack(
            children: [
              // ---- El mapa ocupa TODO ----
              FlutterMap(
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
                          width: 130,
                          height: 74,
                          alignment: Alignment.bottomCenter,
                          child: _PinGuardia(
                            guardia: g,
                            alTocar: () => _abrirDetalle(g),
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

              // ---- Banner "EN VIVO" arriba ----
              Positioned(
                top: 12,
                left: 12,
                right: 12,
                child: SafeArea(child: _BannerVivo(cantidad: lista.length)),
              ),

              // ---- Botones flotantes: zoom + refresh ----
              Positioned(
                right: 12,
                bottom: 128,
                child: Column(
                  children: [
                    _FabRedondo(
                      icono: Icons.add_rounded,
                      alTocar: () => _mapa.move(
                        _mapa.camera.center,
                        (_mapa.camera.zoom + 1).clamp(3, 19),
                      ),
                    ),
                    const SizedBox(height: 8),
                    _FabRedondo(
                      icono: Icons.remove_rounded,
                      alTocar: () => _mapa.move(
                        _mapa.camera.center,
                        (_mapa.camera.zoom - 1).clamp(3, 19),
                      ),
                    ),
                    const SizedBox(height: 8),
                    _FabRedondo(
                      icono: Icons.refresh_rounded,
                      fondo: Colores.grafito,
                      tinta: Colors.white,
                      alTocar: () => ref.invalidate(guardiasEnVivoProvider),
                    ),
                  ],
                ),
              ),

              // ---- Panel inferior flotante con las tarjetas ----
              Positioned(
                left: 12,
                right: 12,
                bottom: 12,
                child: SafeArea(
                  child: _PanelDeTarjetas(
                    guardias: lista,
                    alTocar: (g) {
                      if (g.tieneUbicacion) {
                        _mapa.move(
                          LatLng(g.ultimaLat!, g.ultimaLng!),
                          18,
                        );
                      }
                      _abrirDetalle(g);
                    },
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
        'esperando' => Colores.textoSuave,
        _ => Colores.rojo,
      };

  @override
  Widget build(BuildContext context) {
    // Primer nombre para el chip: si tiene varios, con el primero alcanza.
    // Preferimos algo corto porque el chip queda encima del mapa.
    final primerNombre = guardia.guardiaNombre.trim().split(RegExp(r'\s+')).first;

    return GestureDetector(
      onTap: alTocar,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ---- Chip con el primer nombre (estilo Merlyn) ----
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: _color,
              borderRadius: BorderRadius.circular(5),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.2),
                  blurRadius: 4,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            child: Text(
              primerNombre,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.2,
              ),
            ),
          ),
          const SizedBox(height: 4),
          // ---- El círculo con el escudo ----
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
        ],
      ),
    );
  }
}

// ============================================================================
// TARJETA CHICA DE UN GUARDIA (barra inferior)
// ============================================================================

class _TarjetaGuardia extends ConsumerWidget {
  const _TarjetaGuardia({required this.guardia, required this.alTocar});

  final GuardiaEnVivo guardia;
  final VoidCallback alTocar;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final instalacion =
        ref.watch(perfilProvider).valueOrNull?.nombreCondominio;
    final color = switch (guardia.estado) {
      'vivo' => Colores.verde,
      'demorado' => Colores.naranja,
      'esperando' => Colores.textoSuave,
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
                    [
                      if (instalacion != null) instalacion,
                      guardia.puntoAccesoNombre ?? 'Todo el condominio',
                    ].join(' · '),
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
    if (guardia.minutosDesdeUltima == null) {
      return guardia.estado == 'esperando' ? 'Buscando GPS…' : 'Sin GPS';
    }
    final m = guardia.minutosDesdeUltima!;
    if (m < 1) return 'Hace instantes';
    if (m == 1) return 'Hace 1 min';
    return 'Hace $m min';
  }
}

// ============================================================================
// DETALLE DEL GUARDIA (bottom sheet)
// ============================================================================

class _DetalleGuardia extends ConsumerWidget {
  const _DetalleGuardia({required this.guardia});

  final GuardiaEnVivo guardia;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final g = guardia;
    final instalacion =
        ref.watch(perfilProvider).valueOrNull?.nombreCondominio;
    final color = switch (g.estado) {
      'vivo' => Colores.verde,
      'demorado' => Colores.naranja,
      'esperando' => Colores.textoSuave,
      _ => Colores.rojo,
    };
    final estadoTexto = switch (g.estado) {
      'vivo' => 'En línea',
      'demorado' => 'Demorado',
      'esperando' => 'Buscando GPS…',
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
            if (instalacion != null) _fila('Instalación', instalacion),
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

class _SinUbicaciones extends ConsumerWidget {
  const _SinUbicaciones({required this.guardias});

  final List<GuardiaEnVivo> guardias;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final instalacion =
        ref.watch(perfilProvider).valueOrNull?.nombreCondominio;
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
                    [
                      'Desde ${Formato.hora(g.inicio)}',
                      if (instalacion != null) instalacion,
                      g.puntoAccesoNombre ?? 'Todo el condominio',
                    ].join(' · '),
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              )),
        ],
      ),
    );
  }
}

// ============================================================================
// BANNER "EN VIVO" (arriba del mapa)
// ============================================================================
// Un chip flotante con LED verde parpadeando + contador de guardias activos.
// Mismo lenguaje visual del dashboard Merlyn, para que ambas apps se sientan
// hermanas.
// ============================================================================

class _BannerVivo extends StatelessWidget {
  const _BannerVivo({required this.cantidad});

  final int cantidad;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: const BoxDecoration(
                color: Colores.verde,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            const Text(
              'EN VIVO',
              style: TextStyle(
                color: Colores.verdeOscuro,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                '$cantidad guardia${cantidad == 1 ? "" : "s"} '
                'activo${cantidad == 1 ? "" : "s"}',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Colores.grafito,
                ),
              ),
            ),
            const Text(
              'Actualiza c/30 s',
              style: TextStyle(fontSize: 10.5, color: Colores.textoTenue),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// FAB REDONDO (zoom +, zoom -, refresh)
// ============================================================================

class _FabRedondo extends StatelessWidget {
  const _FabRedondo({
    required this.icono,
    required this.alTocar,
    this.fondo = Colors.white,
    this.tinta = Colores.grafito,
  });

  final IconData icono;
  final VoidCallback alTocar;
  final Color fondo;
  final Color tinta;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: fondo,
      elevation: 4,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: alTocar,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 44,
          height: 44,
          child: Icon(icono, color: tinta, size: 22),
        ),
      ),
    );
  }
}

// ============================================================================
// PANEL DE TARJETAS (flota abajo, scroll horizontal)
// ============================================================================
// Reemplaza la barra fija que teníamos antes por un panel flotante estilo
// Merlyn. Al tocar una tarjeta, el mapa hace zoom hasta ese guardia y abre
// el detalle en un bottom sheet.
// ============================================================================

class _PanelDeTarjetas extends StatelessWidget {
  const _PanelDeTarjetas({required this.guardias, required this.alTocar});

  final List<GuardiaEnVivo> guardias;
  final void Function(GuardiaEnVivo) alTocar;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
      ),
      child: SizedBox(
        height: 98,
        child: ListView.separated(
          padding: const EdgeInsets.all(8),
          scrollDirection: Axis.horizontal,
          itemCount: guardias.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (_, i) => _TarjetaGuardia(
            guardia: guardias[i],
            alTocar: () => alTocar(guardias[i]),
          ),
        ),
      ),
    );
  }
}
