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
final diasDelInformeProvider = StateProvider<int>((ref) => 7);

final movimientosAdminProvider = FutureProvider<List<MovimientoAdmin>>((ref) {
  final dias = ref.watch(diasDelInformeProvider);
  return ref.watch(servicioAdminProvider).movimientos(
        desde: DateTime.now().subtract(Duration(days: dias)),
      );
});

final turnosAdminProvider = FutureProvider<List<TurnoAdmin>>((ref) {
  return ref.watch(servicioAdminProvider).turnos();
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
  ref.invalidate(vehiculosPorAprobarProvider);
  ref.invalidate(personasProvider);
  ref.invalidate(espaciosProvider);
  ref.invalidate(movimientosAdminProvider);
  ref.invalidate(turnosAdminProvider);
}
