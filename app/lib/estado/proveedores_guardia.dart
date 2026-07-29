// ============================================================================
// Tomass Seguridad — Estado de la app del guardia
// ============================================================================
// Separado del estado del residente a propósito: son dos apps distintas que
// comparten el mismo programa, y mezclarlas haría que cada pantalla cargue
// datos que no usa.
// ============================================================================

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../modelos/modelos.dart';
import '../servicios/servicio_guardia.dart';
import 'proveedores.dart';

final servicioGuardiaProvider = Provider<ServicioGuardia>((ref) {
  return ServicioGuardia(
    ref.watch(supabaseProvider),
    ref.watch(servicioFotosProvider),
  );
});

// ============================================================================
// EL TURNO
// ============================================================================
// De acá cuelga todo lo demás: sin turno abierto, el guardia no sabe en qué
// puesto está y los avisos no le llegan.
// ============================================================================

final puestosDisponiblesProvider = FutureProvider<List<PuntoAcceso>>((ref) {
  return ref.watch(servicioGuardiaProvider).puestosDisponibles();
});

final miTurnoProvider = FutureProvider<Turno?>((ref) {
  return ref.watch(servicioGuardiaProvider).miTurnoAbierto();
});

/// El puesto donde está parado el guardia, o null si cubre todo el condominio
/// (o si todavía no abrió turno).
final miPuestoProvider = Provider<String?>((ref) {
  return ref.watch(miTurnoProvider).valueOrNull?.puntoAccesoId;
});

/// ¿El guardia atiende TODAS las entradas del condominio?
/// Es el caso normal: la mayoría de los condominios tiene un solo guardia y
/// tiene que cubrir la entrada peatonal y la vehicular al mismo tiempo.
final cubroTodoProvider = Provider<bool>((ref) {
  return ref.watch(miTurnoProvider).valueOrNull?.cubreTodo ?? false;
});

// ============================================================================
// LA COLA DE AUTOS — EN VIVO
// ============================================================================
// Esta es la pieza crítica de toda la app del guardia.
//
// No pregunta al servidor cada dos segundos: el servidor le AVISA cuando llega
// un auto. Por eso la tarjeta aparece en menos de un segundo sin gastar batería
// ni datos preguntando al vacío.
// ============================================================================

final colaDeAutosProvider = StreamProvider<List<AutoEsperando>>((ref) {
  final turno = ref.watch(miTurnoProvider).valueOrNull;

  // Sin turno abierto no hay cola que mostrar
  if (turno == null) return Stream.value(const <AutoEsperando>[]);

  // Si cubre todo el condominio, escucha los autos de TODAS las entradas.
  // Si está asignado a un puesto, solo los de ese puesto.
  return ref
      .watch(servicioGuardiaProvider)
      .colaDeAutosEnVivo(turno.puntoAccesoId);
});

/// Cuántos autos están esperando. Es el globito rojo del menú.
final cuantosAutosEsperandoProvider = Provider<int>((ref) {
  return ref.watch(colaDeAutosProvider).valueOrNull?.length ?? 0;
});

/// true si hay algún auto esperando hace más de 45 segundos.
/// Sirve para que la pantalla se ponga más urgente: hay un auto detenido
/// frenando la entrada del condominio.
final hayAutoImpacienteProvider = Provider<bool>((ref) {
  final cola = ref.watch(colaDeAutosProvider).valueOrNull ?? const [];
  return cola.any((a) => a.llevaMuchoEsperando);
});

// ============================================================================
// PANEL
// ============================================================================

final resumenProvider = FutureProvider<ResumenCondominio>((ref) {
  return ref.watch(servicioGuardiaProvider).resumen();
});

final ultimosAccesosProvider = FutureProvider<List<Movimiento>>((ref) {
  return ref.watch(servicioGuardiaProvider).ultimosAccesos();
});

final personasDentroProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) {
  return ref.watch(servicioGuardiaProvider).personasDentro();
});

// ============================================================================
// PAQUETES E INCIDENTES
// ============================================================================

final inventarioPaquetesProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) {
  return ref.watch(servicioGuardiaProvider).inventarioDePaquetes();
});

final incidentesProvider = FutureProvider<List<Incidente>>((ref) {
  return ref.watch(servicioGuardiaProvider).incidentes();
});

final incidentesAbiertosProvider = Provider<int>((ref) {
  final lista = ref.watch(incidentesProvider).valueOrNull ?? const <Incidente>[];
  return lista.where((i) => !i.estaCerrado).length;
});

// ============================================================================
// ¿ACÁ SE ESCANEA O SE ANOTA A MANO?
// ============================================================================
// De esto depende qué pestaña ve el guardia: el lector de códigos o el
// formulario de ingreso.
//
// En los colegios y en Viveros Yapur hay barrera y portones que abre el
// guardia, así que no hay nada que escanear. Mostrarle igual el lector sería
// darle un botón que no sirve para nada en su puesto.
//
// Si el guardia cubre TODAS las entradas, alcanza con que una sola sea manual
// para que necesite el formulario.
// ============================================================================

final anotaAManoProvider = Provider<bool>((ref) {
  final garitas = ref.watch(puestosDisponiblesProvider).valueOrNull;
  if (garitas == null || garitas.isEmpty) return false;

  final miPuesto = ref.watch(miPuestoProvider);

  // Sin puesto fijo cubre todo: le hace falta si CUALQUIERA es manual.
  if (miPuesto == null) {
    return garitas.any((g) => g.seAnotaAMano);
  }

  return garitas.where((g) => g.id == miPuesto).any((g) => g.seAnotaAMano);
});

/// true si en su puesto TAMBIÉN se usan códigos QR.
/// Con las dos cosas en true, el guardia ve las dos pestañas.
final escaneaCodigosProvider = Provider<bool>((ref) {
  final garitas = ref.watch(puestosDisponiblesProvider).valueOrNull;
  if (garitas == null || garitas.isEmpty) return true;

  final miPuesto = ref.watch(miPuestoProvider);
  if (miPuesto == null) return garitas.any((g) => !g.seAnotaAMano);
  return garitas.where((g) => g.id == miPuesto).any((g) => !g.seAnotaAMano);
});
