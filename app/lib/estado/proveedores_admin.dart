// ============================================================================
// Tomass Seguridad — Estado del panel de administración
// ============================================================================
// Separado del resto a propósito: un residente nunca abre estas pantallas, así
// que no tiene sentido que su app cargue estos datos.
// ============================================================================

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../modelos/admin.dart';
import '../servicios/servicio_admin.dart';
import 'proveedores.dart';

final servicioAdminProvider = Provider<ServicioAdmin>((ref) {
  return ServicioAdmin(ref.watch(supabaseProvider));
});

// ============================================================================
// LAS INSTALACIONES QUE ATIENDE
// ============================================================================

final misInstalacionesProvider = FutureProvider<List<Instalacion>>((ref) {
  // Si cambia el perfil (por ejemplo al cambiar de instalación), la lista se
  // vuelve a pedir sola para que la marca de "activa" quede al día.
  ref.watch(perfilProvider);
  return ref.watch(servicioAdminProvider).misInstalaciones();
});

/// true si atiende más de una. Con una sola, el selector no se muestra: sería
/// un botón que no hace nada.
final atiendeVariasProvider = Provider<bool>((ref) {
  final lista = ref.watch(misInstalacionesProvider).valueOrNull;
  return (lista?.length ?? 0) > 1;
});

// ============================================================================
// LA PANTALLA DE INICIO
// ============================================================================

final resumenAdminProvider = FutureProvider<ResumenAdmin>((ref) {
  return ref.watch(servicioAdminProvider).resumen();
});

// ============================================================================
// VEHÍCULOS POR APROBAR
// ============================================================================
// Es lo que más se usa: mientras un auto no se apruebe, ese residente no puede
// entrar con él.
// ============================================================================

final vehiculosPorAprobarProvider =
    FutureProvider<List<VehiculoParaAprobar>>((ref) {
  return ref.watch(servicioAdminProvider).vehiculosPorAprobar();
});

final cuantosVehiculosEsperanProvider = Provider<int>((ref) {
  return ref.watch(vehiculosPorAprobarProvider).valueOrNull?.length ?? 0;
});

// ============================================================================
// PERSONAS
// ============================================================================

/// Lo que el administrador escribió en el buscador.
final busquedaPersonasProvider = StateProvider<String>((ref) => '');

/// El filtro de rol, o null para ver a todos.
final filtroRolProvider = StateProvider<String?>((ref) => null);

final personasProvider = FutureProvider<List<PersonaAdmin>>((ref) {
  return ref.watch(servicioAdminProvider).personas(
        busqueda: ref.watch(busquedaPersonasProvider),
        rol: ref.watch(filtroRolProvider),
      );
});

// ============================================================================
// ESPACIOS (unidades o cursos)
// ============================================================================

final espaciosProvider = FutureProvider<List<EspacioAdmin>>((ref) {
  return ref.watch(servicioAdminProvider).espacios();
});

// ============================================================================
// INFORMES
// ============================================================================

/// Cuántos días hacia atrás mira el informe.
/// Cuántos días hacia atrás mira el informe (Accesos/Novedades).
/// Default 30: si es muy corto, novedades viejas ("Auto ajeno" del mes
/// pasado) no aparecen y el admin se confunde porque el badge del panel
/// las cuenta pero la pestaña sale vacía.
final diasDelInformeProvider = StateProvider<int>((ref) => 30);

final movimientosAdminProvider = FutureProvider<List<MovimientoAdmin>>((ref) {
  final dias = ref.watch(diasDelInformeProvider);
  return ref.watch(servicioAdminProvider).movimientos(
        desde: DateTime.now().subtract(Duration(days: dias)),
      );
});

final turnosAdminProvider = FutureProvider<List<TurnoAdmin>>((ref) {
  return ref.watch(servicioAdminProvider).turnos();
});

/// Todas las novedades del período seleccionado (usa diasDelInformeProvider).
final incidentesAdminProvider =
    FutureProvider<List<IncidenteAdmin>>((ref) {
  final dias = ref.watch(diasDelInformeProvider);
  final desde = DateTime.now().subtract(Duration(days: dias));
  return ref.watch(servicioAdminProvider).incidentesDelPeriodo(
        desde: desde,
        hasta: DateTime.now(),
      );
});

// ============================================================================
// REFRESCAR TODO DE UNA
// ============================================================================
// Después de aprobar un vehículo o dar de alta a alguien, varios números
// cambian a la vez. Esto los vuelve a pedir todos juntos, para no tener que
// acordarse de cuál actualizar en cada caso.
// ============================================================================

void refrescarPanel(WidgetRef ref) {
  ref.invalidate(resumenAdminProvider);
  ref.invalidate(puntosDeControlAdminProvider);
  ref.invalidate(informeDeRondasProvider);
  ref.invalidate(misInstalacionesProvider);
  ref.invalidate(vehiculosPorAprobarProvider);
  ref.invalidate(personasProvider);
  ref.invalidate(espaciosProvider);
  ref.invalidate(movimientosAdminProvider);
  ref.invalidate(turnosAdminProvider);
  ref.invalidate(incidentesAdminProvider);
  ref.invalidate(encomiendasDelInformeProvider);
}

// ============================================================================
// LOS PUNTOS DE CONTROL DE LAS RONDAS
// ============================================================================

final puntosDeControlAdminProvider =
    FutureProvider<List<PuntoControlAdmin>>((ref) {
  return ref.watch(servicioAdminProvider).puntosDeControl();
});

/// Cuántos sectores todavía no tienen ubicación tomada.
///
/// Mientras haya alguno sin ubicar, el sistema no puede demostrar que el
/// guardia estuvo ahí: solo que tenía el código del cartel.
final sectoresSinUbicarProvider = Provider<int>((ref) {
  final puntos = ref.watch(puntosDeControlAdminProvider).valueOrNull ?? const [];
  return puntos.where((p) => !p.tieneUbicacion).length;
});

// ============================================================================
// EL INFORME DE RONDAS
// ============================================================================

final diasDelInformeDeRondasProvider = StateProvider<int>((ref) => 7);

final informeDeRondasProvider = FutureProvider<List<RondaDelInforme>>((ref) {
  return ref
      .watch(servicioAdminProvider)
      .informeDeRondas(dias: ref.watch(diasDelInformeDeRondasProvider));
});

// ============================================================================
// EL INFORME DE ENCOMIENDAS, CON FOTO
// ============================================================================

final diasDelInformeDeEncomiendasProvider = StateProvider<int>((ref) => 7);

final encomiendasDelInformeProvider =
    FutureProvider<List<EncomiendaDelInforme>>((ref) {
  final dias = ref.watch(diasDelInformeDeEncomiendasProvider);
  final hasta = DateTime.now();
  final desde = hasta.subtract(Duration(days: dias));
  return ref
      .watch(servicioAdminProvider)
      .encomiendasEntregadas(desde: desde, hasta: hasta);
});
