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

/// El puesto donde está parado el guardia ahora, o null si no abrió turno.
final miPuestoProvider = Provider<String?>((ref) {
  return ref.watch(miTurnoProvider).valueOrNull?.puntoAccesoId;
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
  final puesto = ref.watch(miPuestoProvider);

  // Sin turno abierto no hay cola que mostrar
  if (puesto == null) return Stream.value(const <AutoEsperando>[]);

  return ref.watch(servicioGuardiaProvider).colaDeAutosEnVivo(puesto);
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
