// ============================================================================
// Tomass Seguridad — La barra de pestañas de abajo
// ============================================================================
// Envuelve las cinco pantallas del residente y les pone la barra de navegación
// abajo. La pantalla de resultado (verde o roja) NO pasa por acá a propósito:
// tiene que ocupar la pantalla completa, sin barra.
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../estado/proveedores.dart';
import '../../navegacion/rutas.dart';

class ContenedorPrincipal extends ConsumerStatefulWidget {
  const ContenedorPrincipal({super.key, required this.hijo});

  final Widget hijo;

  @override
  ConsumerState<ContenedorPrincipal> createState() => _EstadoContenedor();
}

class _EstadoContenedor extends ConsumerState<ContenedorPrincipal> {
  // Las pantallas del residente se usan SOLO en vertical: las mira de pie en la
  // entrada o sentado en el auto, y una pantalla que gira sola sería un estorbo.
  //
  // El bloqueo se pone acá y no en main.dart porque el guardia usa la misma app
  // en una tablet horizontal (Fase 4). Al salir de estas pantallas se libera.
  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
  }

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    super.dispose();
  }

  static const _pestanas = <(String, String, IconData, IconData)>[
    (Rutas.codigo, 'Acceso', Icons.qr_code_2_outlined, Icons.qr_code_2_rounded),
    (Rutas.vehiculos, 'Vehículos', Icons.directions_car_outlined,
        Icons.directions_car_rounded),
    (Rutas.paquetes, 'Paquetes', Icons.inventory_2_outlined,
        Icons.inventory_2_rounded),
    (Rutas.visitas, 'Visitas', Icons.group_outlined, Icons.group_rounded),
    (Rutas.perfil, 'Perfil', Icons.person_outline_rounded, Icons.person_rounded),
  ];

  int _pestanaActual(BuildContext context) {
    final donde = GoRouterState.of(context).matchedLocation;
    final indice = _pestanas.indexWhere((p) => p.$1 == donde);
    return indice < 0 ? 0 : indice;
  }

  @override
  Widget build(BuildContext context) {
    final actual = _pestanaActual(context);

    // Los globitos rojos: cuántas cosas esperan que el residente haga algo.
    // Sin esto, una visita parada en la garita esperando su respuesta pasaría
    // desapercibida hasta que él abriera esa pestaña por casualidad.
    final avisos = <String, int>{
      Rutas.vehiculos: ref.watch(vehiculosPendientesProvider),
      Rutas.paquetes: ref.watch(paquetesEsperandoProvider),
      Rutas.visitas: ref.watch(visitasPorResponderProvider),
    };

    return Scaffold(
      body: widget.hijo,
      bottomNavigationBar: NavigationBar(
        selectedIndex: actual,
        onDestinationSelected: (indice) {
          final destino = _pestanas[indice].$1;
          if (destino != GoRouterState.of(context).matchedLocation) {
            context.go(destino);
          }
        },
        destinations: [
          for (final (ruta, nombre, iconoApagado, iconoEncendido) in _pestanas)
            NavigationDestination(
              icon: _ConGlobito(
                cuantos: avisos[ruta] ?? 0,
                child: Icon(iconoApagado),
              ),
              selectedIcon: _ConGlobito(
                cuantos: avisos[ruta] ?? 0,
                child: Icon(iconoEncendido),
              ),
              label: nombre,
            ),
        ],
      ),
    );
  }
}

/// Le pone el globito rojo con el número arriba a la derecha de un ícono.
class _ConGlobito extends StatelessWidget {
  const _ConGlobito({required this.cuantos, required this.child});

  final int cuantos;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (cuantos <= 0) return child;

    return Badge.count(
      count: cuantos,
      backgroundColor: const Color(0xFFD32F2F),
      textColor: Colors.white,
      child: child,
    );
  }
}
