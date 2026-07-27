// ============================================================================
// Tomass Seguridad — Navegación entre pantallas
// ============================================================================
// Define todas las pantallas de la app y cómo se llega a cada una.
//
// LO MÁS IMPORTANTE QUE HACE ESTE ARCHIVO
//
//   Vigila la sesión. Si el residente no inició sesión y trata de entrar a
//   cualquier pantalla, lo manda al login. Y si la sesión vence mientras usa la
//   app, lo saca solo.
//
//   Eso está acá y no en cada pantalla a propósito: si estuviera repartido,
//   alcanzaría con olvidarse en una sola pantalla para dejar un agujero.
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../estado/proveedores.dart';
import '../pantallas/acceso/pantalla_codigo.dart';
import '../pantallas/acceso/pantalla_escaner.dart';
import '../pantallas/acceso/pantalla_resultado.dart';
import '../pantallas/inicio/contenedor_principal.dart';
import '../pantallas/login/pantalla_login.dart';
import '../pantallas/paquetes/pantalla_paquetes.dart';
import '../pantallas/perfil/pantalla_perfil.dart';
import '../pantallas/vehiculos/pantalla_vehiculos.dart';
import '../pantallas/visitas/pantalla_visitas.dart';

class Rutas {
  const Rutas._();

  static const login = '/login';
  static const codigo = '/codigo';
  static const escaner = '/escaner';
  static const resultado = '/resultado';
  static const vehiculos = '/vehiculos';
  static const paquetes = '/paquetes';
  static const visitas = '/visitas';
  static const perfil = '/perfil';
}

final rutasProvider = Provider<GoRouter>((ref) {
  // Al cambiar la sesión, go_router revisa de nuevo si hay que redirigir
  final vigilante = _VigilanteDeSesion(ref);

  return GoRouter(
    initialLocation: Rutas.codigo,
    refreshListenable: vigilante,
    debugLogDiagnostics: false,

    redirect: (context, estado) {
      final haySesion = ref.read(haySesionProvider);
      final vaAlLogin = estado.matchedLocation == Rutas.login;

      // Sin sesión, solo se puede estar en el login
      if (!haySesion) return vaAlLogin ? null : Rutas.login;

      // Con sesión, no tiene sentido quedarse en el login
      if (vaAlLogin) return Rutas.codigo;

      return null;
    },

    routes: [
      GoRoute(
        path: Rutas.login,
        builder: (context, estado) => const PantallaLogin(),
      ),

      // La pantalla de resultado va POR ENCIMA de todo, sin la barra de abajo:
      // cuando se pone verde o roja tiene que ocupar la pantalla completa.
      GoRoute(
        path: Rutas.escaner,
        builder: (context, estado) => const PantallaEscaner(),
      ),
      GoRoute(
        path: Rutas.resultado,
        builder: (context, estado) => const PantallaResultado(),
      ),

      // Las cinco pestañas comparten la barra de abajo
      ShellRoute(
        builder: (context, estado, hijo) => ContenedorPrincipal(hijo: hijo),
        routes: [
          GoRoute(
            path: Rutas.codigo,
            builder: (context, estado) => const PantallaCodigo(),
          ),
          GoRoute(
            path: Rutas.vehiculos,
            builder: (context, estado) => const PantallaVehiculos(),
          ),
          GoRoute(
            path: Rutas.paquetes,
            builder: (context, estado) => const PantallaPaquetes(),
          ),
          GoRoute(
            path: Rutas.visitas,
            builder: (context, estado) => const PantallaVisitas(),
          ),
          GoRoute(
            path: Rutas.perfil,
            builder: (context, estado) => const PantallaPerfil(),
          ),
        ],
      ),
    ],

    errorBuilder: (context, estado) => Scaffold(
      appBar: AppBar(title: const Text('Pantalla no encontrada')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Esa pantalla no existe.',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 18),
              ElevatedButton(
                onPressed: () => context.go(Rutas.codigo),
                child: const Text('Volver al inicio'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
});

/// Le avisa a go_router cada vez que la sesión cambia, para que vuelva a
/// evaluar si hay que redirigir al login.
class _VigilanteDeSesion extends ChangeNotifier {
  _VigilanteDeSesion(this._ref) {
    _ref.listen(haySesionProvider, (_, __) => notifyListeners());
  }

  // ignore: unused_field
  final Ref _ref;
}
