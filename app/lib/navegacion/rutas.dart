// ============================================================================
// Tomass Seguridad — Navegación entre pantallas
// ============================================================================
// Define todas las pantallas y quién puede llegar a cada una.
//
// LAS DOS COSAS IMPORTANTES QUE HACE ESTE ARCHIVO
//
//   1. VIGILA LA SESIÓN. Si no hay sesión iniciada, manda al login. Si la sesión
//      vence mientras alguien usa la app, lo saca solo.
//
//   2. SEPARA POR ROL. Un residente y un guardia usan la MISMA app, pero ven
//      pantallas completamente distintas. Acá se decide cuál le toca a cada uno.
//
//   Las dos cosas están en este archivo y no repartidas por las pantallas a
//   propósito: si estuvieran repartidas, alcanzaría con olvidarse en una sola
//   pantalla para dejar un agujero por donde un residente vea la pantalla del
//   guardia.
//
// Y ADEMÁS: EL GUARDIA NO PASA SIN ABRIR TURNO
//   Sin turno abierto, el guardia no recibe avisos de autos. Así que si entra sin
//   turno, se lo manda a abrirlo antes de dejarlo hacer nada más.
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../estado/proveedores.dart';
import '../estado/proveedores_guardia.dart';
import '../modelos/modelos.dart';
import '../pantallas/acceso/pantalla_codigo.dart';
import '../pantallas/acceso/pantalla_escaner.dart';
import '../pantallas/acceso/pantalla_resultado.dart';
import '../pantallas/guardia/contenedor_guardia.dart';
import '../pantallas/guardia/pantalla_acceso_manual.dart';
import '../pantallas/guardia/pantalla_autos_esperando.dart';
import '../pantallas/guardia/pantalla_escaner_guardia.dart';
import '../pantallas/guardia/pantalla_novedades.dart';
import '../pantallas/guardia/pantalla_panel.dart';
import '../pantallas/guardia/pantalla_rondas.dart';
import '../pantallas/guardia/pantalla_porteria.dart';
import '../pantallas/guardia/pantalla_turno.dart';
import '../pantallas/inicio/contenedor_principal.dart';
import '../pantallas/login/pantalla_login.dart';
import '../pantallas/paquetes/pantalla_paquetes.dart';
import '../pantallas/perfil/pantalla_perfil.dart';
import '../pantallas/vehiculos/pantalla_vehiculos.dart';
import '../pantallas/visitas/pantalla_visitas.dart';
import '../pantallas/admin/pantalla_admin_espacios.dart';
import '../pantallas/admin/pantalla_admin_informes.dart';
import '../pantallas/admin/pantalla_admin_inicio.dart';
import '../pantallas/admin/pantalla_admin_personas.dart';
import '../pantallas/admin/pantalla_admin_vehiculos.dart';

class Rutas {
  const Rutas._();

  // Comunes
  static const login = '/login';
  static const cargando = '/cargando';

  // Residente
  static const codigo = '/codigo';
  static const escaner = '/escaner';
  static const resultado = '/resultado';
  static const vehiculos = '/vehiculos';
  static const paquetes = '/paquetes';
  static const visitas = '/visitas';
  static const perfil = '/perfil';

  // Guardia
  static const turno = '/turno';
  static const panel = '/panel';
  static const autosEsperando = '/autos-esperando';
  static const escanerGuardia = '/escanear';
  static const paquetesGuardia = '/porteria';
  static const incidentes = '/incidentes';
  static const accesoManual = '/anotar-ingreso';
  static const rondas = '/rondas';

  // Administrador
  static const adminInicio = '/administracion';
  static const adminVehiculos = '/administracion/vehiculos';
  static const adminPersonas = '/administracion/personas';
  static const adminEspacios = '/administracion/espacios';
  static const adminInformes = '/administracion/informes';
}

final rutasProvider = Provider<GoRouter>((ref) {
  final vigilante = _Vigilante(ref);

  return GoRouter(
    initialLocation: Rutas.cargando,
    refreshListenable: vigilante,
    debugLogDiagnostics: false,

    redirect: (context, estado) {
      final haySesion = ref.read(haySesionProvider);
      final donde = estado.matchedLocation;

      // ---- Sin sesión: solo el login ----
      if (!haySesion) return donde == Rutas.login ? null : Rutas.login;

      // ---- Con sesión pero sin saber todavía quién es ----
      final perfil = ref.read(perfilProvider);
      if (perfil.isLoading || !perfil.hasValue) {
        return donde == Rutas.cargando ? null : Rutas.cargando;
      }

      final rol = perfil.requireValue.rol;

      // ---- RESIDENTE ----
      if (rol == RolUsuario.residente) {
        // Si está en una pantalla que no le corresponde, va a su inicio
        if (!_deResidente.contains(donde)) return Rutas.codigo;
        return null;
      }

      // ---- ADMINISTRADOR ----
      //
      // Tiene su propio panel y NO se le pide abrir turno: los turnos son de
      // los guardias, que son los que están parados en la puerta. Antes el
      // administrador caía en las pantallas de portería y quedaba obligado a
      // abrir un turno que no le correspondía.
      if (rol == RolUsuario.administrador) {
        if (!_deAdministracion.contains(donde)) return Rutas.adminInicio;
        return null;
      }

      // ---- GUARDIA ----
      final turno = ref.read(miTurnoProvider);

      // Todavía averiguando si tiene turno abierto
      if (turno.isLoading) return donde == Rutas.cargando ? null : Rutas.cargando;

      final tieneTurno = turno.valueOrNull != null;

      // Sin turno abierto, lo único que puede hacer es abrirlo
      if (!tieneTurno) return donde == Rutas.turno ? null : Rutas.turno;

      // Con turno abierto, no tiene sentido dejarlo en la pantalla de abrirlo
      if (donde == Rutas.turno || donde == Rutas.cargando) return Rutas.panel;

      if (!_dePorteria.contains(donde)) return Rutas.panel;
      return null;
    },

    routes: [
      GoRoute(
        path: Rutas.cargando,
        builder: (context, estado) => const _PantallaCargando(),
      ),
      GoRoute(
        path: Rutas.login,
        builder: (context, estado) => const PantallaLogin(),
      ),

      // ======================================================================
      // RESIDENTE
      // ======================================================================

      // Estas dos van POR ENCIMA de todo, sin la barra de abajo: cuando la
      // pantalla se pone verde o roja tiene que ocupar todo.
      GoRoute(
        path: Rutas.escaner,
        builder: (context, estado) => const PantallaEscaner(),
      ),
      GoRoute(
        path: Rutas.resultado,
        builder: (context, estado) => const PantallaResultado(),
      ),

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

      // ======================================================================
      // GUARDIA Y ADMINISTRADOR
      // ======================================================================

      GoRoute(
        path: Rutas.turno,
        builder: (context, estado) => const PantallaTurno(),
      ),

      // ======================================================================
      // ADMINISTRADOR
      // ======================================================================
      // Sin contenedor con menú: son pocas pantallas y se llega a todas desde
      // el inicio. Un menú de cinco opciones para cinco pantallas sería una
      // capa de más.

      GoRoute(
        path: Rutas.adminInicio,
        builder: (context, estado) => const PantallaAdminInicio(),
      ),
      GoRoute(
        path: Rutas.adminVehiculos,
        builder: (context, estado) => const PantallaAdminVehiculos(),
      ),
      GoRoute(
        path: Rutas.adminPersonas,
        builder: (context, estado) => const PantallaAdminPersonas(),
      ),
      GoRoute(
        path: Rutas.adminEspacios,
        builder: (context, estado) => const PantallaAdminEspacios(),
      ),
      GoRoute(
        path: Rutas.adminInformes,
        builder: (context, estado) => const PantallaAdminInformes(),
      ),

      ShellRoute(
        builder: (context, estado, hijo) => ContenedorGuardia(hijo: hijo),
        routes: [
          GoRoute(
            path: Rutas.panel,
            builder: (context, estado) => const PantallaPanel(),
          ),
          GoRoute(
            path: Rutas.autosEsperando,
            builder: (context, estado) => const PantallaAutosEsperando(),
          ),

          GoRoute(
            path: Rutas.escanerGuardia,
            builder: (context, estado) => const PantallaEscanerGuardia(),
          ),
          GoRoute(
            path: Rutas.paquetesGuardia,
            builder: (context, estado) => const PantallaPorteria(),
          ),
          GoRoute(
            path: Rutas.rondas,
            builder: (context, estado) => const PantallaRondas(),
          ),
          GoRoute(
            path: Rutas.accesoManual,
            builder: (context, estado) => const PantallaAccesoManual(),
          ),
          GoRoute(
            path: Rutas.incidentes,
            builder: (context, estado) => const PantallaNovedades(),
          ),
        ],
      ),
    ],

    errorBuilder: (context, estado) => Scaffold(
      appBar: AppBar(title: const Text('Pantalla no encontrada')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(26),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Esa pantalla no existe.',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 18),
              ElevatedButton(
                onPressed: () => context.go(Rutas.cargando),
                child: const Text('Volver al inicio'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
});

/// Las pantallas que puede ver un residente.
const _deResidente = {
  Rutas.codigo,
  Rutas.escaner,
  Rutas.resultado,
  Rutas.vehiculos,
  Rutas.paquetes,
  Rutas.visitas,
  Rutas.perfil,
};

/// Las pantallas del panel de administración.
const _deAdministracion = {
  Rutas.adminInicio,
  Rutas.adminVehiculos,
  Rutas.adminPersonas,
  Rutas.adminEspacios,
  Rutas.adminInformes,
};

/// Las pantallas que puede ver el personal de portería.
const _dePorteria = {
  Rutas.panel,
  Rutas.accesoManual,
  Rutas.rondas,
  Rutas.autosEsperando,
  Rutas.escanerGuardia,
  Rutas.paquetesGuardia,
  Rutas.incidentes,
  Rutas.turno,
};

/// Le avisa a go_router cuando cambia algo que puede obligar a redirigir:
/// la sesión, el perfil o el turno abierto.
class _Vigilante extends ChangeNotifier {
  _Vigilante(Ref ref) {
    ref.listen(haySesionProvider, (_, __) => notifyListeners());
    ref.listen(perfilProvider, (_, __) => notifyListeners());
    ref.listen(miTurnoProvider, (_, __) => notifyListeners());
  }
}

/// Se muestra el instante que tarda en llegar el perfil desde el servidor.
class _PantallaCargando extends StatelessWidget {
  const _PantallaCargando();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFF1C1E24),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 34,
              height: 34,
              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3),
            ),
            SizedBox(height: 20),
            Text(
              'Cargando tus datos…',
              style: TextStyle(color: Colors.white70, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }
}
