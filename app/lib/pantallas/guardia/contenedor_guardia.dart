// ============================================================================
// Tomass Seguridad — El menú del guardia
// ============================================================================
// Envuelve las pantallas de portería y les pone el menú.
//
// SE ADAPTA AL APARATO, Y ESO IMPORTA
//   Los guardias usan su CELULAR PERSONAL, no una tablet del condominio. Pero
//   algún condominio puede poner una tablet en la garita. Así que:
//
//     Celular (angosto)  → menú de pestañas abajo, al alcance del pulgar
//     Tablet (ancho)     → menú lateral, que deja más alto para las tarjetas
//
// EL GLOBITO ROJO DE "AUTOS" ES LO MÁS IMPORTANTE DEL MENÚ
//   Si hay un auto esperando y el guardia está en otra pantalla, ese número es
//   lo único que se lo dice. Por eso se pinta rojo y no naranja.
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../config/tema.dart';
import '../../estado/proveedores.dart';
import '../../estado/proveedores_guardia.dart';
import '../../nucleo/formato.dart';
import '../../navegacion/rutas.dart';
import 'acciones_de_turno.dart';

class ContenedorGuardia extends ConsumerStatefulWidget {
  const ContenedorGuardia({super.key, required this.hijo});

  final Widget hijo;

  @override
  ConsumerState<ContenedorGuardia> createState() => _EstadoContenedorGuardia();
}

class _EstadoContenedorGuardia extends ConsumerState<ContenedorGuardia> {
  @override
  void initState() {
    super.initState();
    // El guardia puede usar tablet en horizontal, así que acá NO se bloquea la
    // orientación. (Las pantallas del residente sí la bloquean en vertical.)
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    // Al armarse el shell del guardia se instancia el rastreador GPS. El
    // rastreador se enciende SOLO cuando hay turno abierto (escucha
    // miTurnoProvider) y se apaga automáticamente cuando se cierra.
    ref.read(rastreadorGuardiaProvider);
  }

  /// El menú del guardia. Cambió al nuevo modelo de empresa de seguridad:
  ///
  ///   Antes había pestañas de "Autos" (cola de barrera), "Escanear" (QR de
  ///   residente) y "Visitas" (esperando autorización del residente), que
  ///   servían al modelo condominio-autogestionado. En el modelo Tomass eso
  ///   no aplica: la administradora del edificio no atiende el sistema en
  ///   vivo, y los guardias registran los ingresos ellos mismos.
  ///
  ///   Por eso el menú actual es más corto y directo: Inicio + Registrar
  ///   ingreso + Rondas + Encomiendas + Novedades.
  ///
  ///   La opción "anota" sigue existiendo pero se muestra como "Registrar":
  ///   es el formulario a mano para dar entrada/salida a personas y
  ///   vehículos (con foto de patente y datos básicos).
  List<_Opcion> _opcionesDe({required bool rondas}) => [
        const _Opcion(
            Rutas.panel, 'Inicio', Icons.home_outlined, Icons.home_rounded),
        const _Opcion(Rutas.accesoManual, 'Registrar',
            Icons.edit_note_outlined, Icons.edit_note_rounded),
        if (rondas)
          const _Opcion(Rutas.rondas, 'Rondas', Icons.route_outlined,
              Icons.route_rounded),
        const _Opcion(Rutas.paquetesGuardia, 'Paquetes',
            Icons.inventory_2_outlined, Icons.inventory_2_rounded),
        const _Opcion(Rutas.incidentes, 'Novedades', Icons.report_outlined,
            Icons.report_rounded),
      ];

  int _indiceActualDe(List<_Opcion> opciones) {
    final donde = GoRouterState.of(context).matchedLocation;
    final i = opciones.indexWhere((o) => o.ruta == donde);
    return i < 0 ? 0 : i;
  }

  void _irA(List<_Opcion> opciones, int indice) {
    final destino = opciones[indice].ruta;
    if (destino != GoRouterState.of(context).matchedLocation) {
      context.go(destino);
    }
  }

  // Las dos acciones viven en acciones_de_turno.dart y no acá, porque tienen
  // que estar disponibles también desde las pantallas sueltas del guardia.
  Future<void> _cerrarTurno() => AccionesDeTurno.cerrarTurno(context, ref);
  Future<void> _salirDeLaApp() => AccionesDeTurno.cerrarSesion(context, ref);

  @override
  Widget build(BuildContext context) {
    final ancho = MediaQuery.sizeOf(context).width;
    final esTablet = ancho >= 720;

    // El menú se arma según lo que necesita ESTE guardia en SU puesto.
    // Solo miramos si hay rondas configuradas: el resto (Registrar,
    // Portería, Novedades) aparece siempre en el nuevo modelo.
    final opciones = _opcionesDe(
      rondas: ref.watch(hayRondasProvider),
    );
    final indiceActual = _indiceActualDe(opciones);

    final paquetes =
        ref.watch(resumenProvider).valueOrNull?.paquetesEnPorteria ?? 0;
    final novedades = ref.watch(incidentesAbiertosProvider);

    final avisos = <String, int>{
      Rutas.paquetesGuardia: paquetes,
      Rutas.incidentes: novedades,
    };

    if (esTablet) {
      return Scaffold(
        body: Row(
          children: [
            _MenuLateral(
              opciones: opciones,
              indiceActual: indiceActual,
              avisos: avisos,
              alElegir: (i) => _irA(opciones, i),
              alCerrarTurno: _cerrarTurno,
              alSalir: _salirDeLaApp,
            ),
            Expanded(child: widget.hijo),
          ],
        ),
      );
    }

    return Scaffold(
      body: widget.hijo,
      bottomNavigationBar: NavigationBar(
        selectedIndex: indiceActual,
        onDestinationSelected: (i) => _irA(opciones, i),
        destinations: [
          for (final o in opciones)
            NavigationDestination(
              icon: _ConGlobito(
                cuantos: avisos[o.ruta] ?? 0,
                urgente: false,
                child: Icon(o.iconoApagado),
              ),
              selectedIcon: _ConGlobito(
                cuantos: avisos[o.ruta] ?? 0,
                urgente: false,
                child: Icon(o.iconoEncendido),
              ),
              label: o.nombre,
            ),
        ],
      ),
    );
  }
}

class _Opcion {
  const _Opcion(this.ruta, this.nombre, this.iconoApagado, this.iconoEncendido);

  final String ruta;
  final String nombre;
  final IconData iconoApagado;
  final IconData iconoEncendido;
}

// ============================================================================
// El menú lateral, para tablet
// ============================================================================

class _MenuLateral extends ConsumerWidget {
  const _MenuLateral({
    required this.opciones,
    required this.indiceActual,
    required this.avisos,
    required this.alElegir,
    required this.alCerrarTurno,
    required this.alSalir,
  });

  final List<_Opcion> opciones;
  final int indiceActual;
  final Map<String, int> avisos;
  final void Function(int) alElegir;
  final VoidCallback alCerrarTurno;
  final VoidCallback alSalir;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final perfil = ref.watch(perfilProvider).valueOrNull;
    final turno = ref.watch(miTurnoProvider).valueOrNull;

    return Container(
      width: 196,
      color: Colores.grafito,
      child: SafeArea(
        child: Column(
          children: [
            // ---- Quién soy y dónde estoy ----
            Padding(
              padding: const EdgeInsets.fromLTRB(15, 18, 15, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Tomass',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    perfil == null
                        ? '…'
                        : Formato.nombreCorto(perfil.nombreCompleto),
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.72),
                      fontSize: 12,
                    ),
                  ),
                  if (turno != null) ...[
                    const SizedBox(height: 9),
                    Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colores.verde.withValues(alpha: 0.22),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.circle,
                              size: 7, color: Colores.verde),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              turno.puntoAccesoNombre,
                              maxLines: 2,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10.5,
                                fontWeight: FontWeight.w700,
                                height: 1.3,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),

            const Divider(color: Colors.white24, height: 1),
            const SizedBox(height: 8),

            // ---- Las opciones ----
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 9),
                children: [
                  for (var i = 0; i < opciones.length; i++)
                    _ItemLateral(
                      opcion: opciones[i],
                      activa: i == indiceActual,
                      cuantos: avisos[opciones[i].ruta] ?? 0,
                      urgente: false,
                      alTocar: () => alElegir(i),
                    ),
                ],
              ),
            ),

            // ---- Pie: cerrar turno y salir ----
            const Divider(color: Colors.white24, height: 1),
            Padding(
              padding: const EdgeInsets.all(9),
              child: Column(
                children: [
                  if (turno != null)
                    _BotonDePie(
                      icono: Icons.logout_rounded,
                      texto: 'Cerrar turno',
                      alTocar: alCerrarTurno,
                    ),
                  _BotonDePie(
                    icono: Icons.power_settings_new_rounded,
                    texto: 'Salir de la app',
                    alTocar: alSalir,
                  ),
                  if (turno != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      'Turno desde ${Formato.hora(turno.inicio)}',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.4),
                        fontSize: 10,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ItemLateral extends StatelessWidget {
  const _ItemLateral({
    required this.opcion,
    required this.activa,
    required this.cuantos,
    required this.urgente,
    required this.alTocar,
  });

  final _Opcion opcion;
  final bool activa;
  final int cuantos;
  final bool urgente;
  final VoidCallback alTocar;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Material(
        color: activa ? Colors.white.withValues(alpha: 0.16) : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: alTocar,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 12),
            child: Row(
              children: [
                Icon(
                  activa ? opcion.iconoEncendido : opcion.iconoApagado,
                  size: 20,
                  color: activa
                      ? Colors.white
                      : Colors.white.withValues(alpha: 0.72),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Text(
                    opcion.nombre,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: activa ? FontWeight.w700 : FontWeight.w500,
                      color: activa
                          ? Colors.white
                          : Colors.white.withValues(alpha: 0.78),
                    ),
                  ),
                ),
                if (cuantos > 0)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    constraints: const BoxConstraints(minWidth: 20),
                    decoration: BoxDecoration(
                      color: urgente ? Colores.rojo : Colores.naranja,
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Text(
                      '$cuantos',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BotonDePie extends StatelessWidget {
  const _BotonDePie({
    required this.icono,
    required this.texto,
    required this.alTocar,
  });

  final IconData icono;
  final String texto;
  final VoidCallback alTocar;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: alTocar,
      borderRadius: BorderRadius.circular(7),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        child: Row(
          children: [
            Icon(icono, size: 17, color: Colors.white.withValues(alpha: 0.7)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                texto,
                style: TextStyle(
                  fontSize: 12.5,
                  color: Colors.white.withValues(alpha: 0.75),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// El globito con el número
// ============================================================================
// El de "Autos" va en ROJO y el resto en naranja, a propósito: si hay un auto
// esperando en la barrera, ese número es lo único que se lo dice al guardia
// cuando está en otra pantalla.
// ============================================================================

class _ConGlobito extends StatelessWidget {
  const _ConGlobito({
    required this.cuantos,
    required this.child,
    this.urgente = false,
  });

  final int cuantos;
  final Widget child;
  final bool urgente;

  @override
  Widget build(BuildContext context) {
    if (cuantos <= 0) return child;

    return Badge.count(
      count: cuantos,
      backgroundColor: urgente ? Colores.rojo : Colores.naranja,
      textColor: Colors.white,
      child: child,
    );
  }
}
