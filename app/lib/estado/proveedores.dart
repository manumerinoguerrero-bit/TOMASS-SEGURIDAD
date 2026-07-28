// ============================================================================
// Tomass Seguridad — Estado de la app
// ============================================================================
// QUÉ ES ESTO, EN SIMPLE
//
//   Las pantallas no van a buscar los datos por su cuenta. Le preguntan a un
//   "proveedor", que es el único que sabe cómo conseguirlos y que se encarga de
//   avisarle a todas las pantallas cuando cambian.
//
//   Ventaja concreta: si el residente aprueba un vehículo nuevo, la pantalla del
//   código y la de Mis Vehículos se enteran las dos solas, sin que haya que
//   acordarse de actualizar cada una.
// ============================================================================

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/entorno.dart';
import '../config/palabras.dart';
import '../modelos/modelos.dart';
import '../nucleo/errores.dart';
import '../servicios/lector_de_patentes.dart';
import '../servicios/servicio_acceso.dart';
import '../servicios/servicio_fotos.dart';
import '../servicios/servicio_residente.dart';
import '../servicios/servicio_sesion.dart';

// ============================================================================
// LAS PIEZAS BÁSICAS
// ============================================================================

/// La conexión al servidor.
final supabaseProvider = Provider<SupabaseClient>((ref) {
  return Supabase.instance.client;
});

final servicioSesionProvider = Provider<ServicioSesion>((ref) {
  return ServicioSesion(ref.watch(supabaseProvider));
});

final servicioAccesoProvider = Provider<ServicioAcceso>((ref) {
  return ServicioAcceso(ref.watch(supabaseProvider));
});

final servicioFotosProvider = Provider<ServicioFotos>((ref) {
  return ServicioFotos(ref.watch(supabaseProvider));
});

final servicioResidenteProvider = Provider<ServicioResidente>((ref) {
  return ServicioResidente(
    ref.watch(supabaseProvider),
    ref.watch(servicioFotosProvider),
  );
});

final lectorDePatentesProvider = Provider<LectorDePatentes>((ref) {
  final lector = LectorDePatentes();
  // La lectura automática usa memoria del sistema que hay que devolver
  ref.onDispose(lector.cerrar);
  return lector;
});

// ============================================================================
// ¿HAY ALGUIEN CON LA SESIÓN ABIERTA?
// ============================================================================
// Esto es lo que hace que la app mande sola al login cuando la sesión vence, y
// a la pantalla principal cuando alguien entra.
// ============================================================================

final cambiosDeSesionProvider = StreamProvider<AuthState>((ref) {
  return ref.watch(servicioSesionProvider).cambiosDeSesion;
});

final haySesionProvider = Provider<bool>((ref) {
  // Se escucha el flujo de cambios para que esto se recalcule solo
  ref.watch(cambiosDeSesionProvider);
  return ref.watch(servicioSesionProvider).haySesion;
});

// ============================================================================
// LA FICHA DEL RESIDENTE
// ============================================================================

final perfilProvider = FutureProvider<Perfil>((ref) async {
  // Si cambia la sesión, la ficha se vuelve a pedir sola
  ref.watch(cambiosDeSesionProvider);
  return ref.watch(servicioSesionProvider).traerPerfil();
});

// ============================================================================
// LOS VEHÍCULOS DEL RESIDENTE
// ============================================================================

final misVehiculosProvider = FutureProvider<List<Vehiculo>>((ref) async {
  return ref.watch(servicioAccesoProvider).misVehiculos();
});

final misVehiculosAprobadosProvider = Provider<List<Vehiculo>>((ref) {
  final todos = ref.watch(misVehiculosProvider).valueOrNull ?? const <Vehiculo>[];
  return todos.where((v) => v.estado.puedeEntrar).toList();
});

// ============================================================================
// PAQUETES, VISITAS E HISTORIAL
// ============================================================================

final misPaquetesProvider = FutureProvider<List<Paquete>>((ref) async {
  return ref.watch(servicioResidenteProvider).misPaquetes();
});

final misVisitasProvider = FutureProvider<List<Visita>>((ref) async {
  return ref.watch(servicioResidenteProvider).misVisitas();
});

final miHistorialProvider = FutureProvider<List<Movimiento>>((ref) async {
  return ref.watch(servicioResidenteProvider).miHistorial();
});

/// Cuántas visitas están esperando que el residente responda.
/// Es lo que pinta el globito rojo en la pestaña de Visitas.
final visitasPorResponderProvider = Provider<int>((ref) {
  final visitas = ref.watch(misVisitasProvider).valueOrNull ?? const <Visita>[];
  return visitas.where((v) => v.estado.necesitaTuRespuesta).length;
});

/// Cuántos paquetes lo están esperando en portería.
final paquetesEsperandoProvider = Provider<int>((ref) {
  final paquetes = ref.watch(misPaquetesProvider).valueOrNull ?? const <Paquete>[];
  return paquetes.where((p) => p.estado == EstadoPaquete.enPorteria).length;
});

/// Cuántos vehículos están esperando la aprobación del administrador.
final vehiculosPendientesProvider = Provider<int>((ref) {
  final todos = ref.watch(misVehiculosProvider).valueOrNull ?? const <Vehiculo>[];
  return todos.where((v) => v.estado == EstadoVehiculo.pendiente).length;
});

// ============================================================================
// EL CÓDIGO QR QUE SE RENUEVA SOLO
// ============================================================================
// ESTA ES LA PIEZA MÁS DELICADA DE LA APP DEL RESIDENTE.
//
// Lo que hace:
//   1. Pide un código al servidor.
//   2. Cuenta los segundos hacia atrás, una vez por segundo, para el relojito.
//   3. Cinco segundos antes de que venza, pide el siguiente. Así el residente
//      nunca ve un código muerto en la pantalla.
//   4. Cuando la app pasa a segundo plano, DEJA de pedir códigos: no tiene
//      sentido gastar batería y datos generando códigos que nadie está mirando.
//   5. Al volver, si el código venció, pide uno nuevo de inmediato.
//
// El punto 4 importa más de lo que parece: sin eso, la app pediría un código por
// minuto para siempre, incluso guardada en el bolsillo toda la noche.
// ============================================================================

/// Lo que la pantalla del código necesita saber en cada momento.
class EstadoCodigo {
  const EstadoCodigo({
    this.codigo,
    this.cargando = false,
    this.error,
    this.tipo = TipoAcceso.peatonal,
    this.vehiculoElegidoId,
    this.segundosDeEspera,
  });

  final CodigoAcceso? codigo;
  final bool cargando;
  final String? error;
  final TipoAcceso tipo;
  final String? vehiculoElegidoId;

  /// Si el servidor pidió esperar (límite de 1 código cada 30 segundos).
  final int? segundosDeEspera;

  bool get hayCodigo => codigo != null && !codigo!.yaVencio;

  EstadoCodigo copiarCon({
    CodigoAcceso? codigo,
    bool? cargando,
    String? error,
    TipoAcceso? tipo,
    String? vehiculoElegidoId,
    int? segundosDeEspera,
    bool limpiarError = false,
    bool limpiarCodigo = false,
    bool limpiarEspera = false,
  }) {
    return EstadoCodigo(
      codigo: limpiarCodigo ? null : (codigo ?? this.codigo),
      cargando: cargando ?? this.cargando,
      error: limpiarError ? null : (error ?? this.error),
      tipo: tipo ?? this.tipo,
      vehiculoElegidoId: vehiculoElegidoId ?? this.vehiculoElegidoId,
      segundosDeEspera:
          limpiarEspera ? null : (segundosDeEspera ?? this.segundosDeEspera),
    );
  }
}

class ControladorCodigo extends StateNotifier<EstadoCodigo> {
  ControladorCodigo(this._servicio) : super(const EstadoCodigo()) {
    renovar();
  }

  final ServicioAcceso _servicio;

  Timer? _reloj;
  bool _enPausa = false;

  /// La app pasó a segundo plano: se deja de pedir códigos.
  void pausar() {
    _enPausa = true;
    _reloj?.cancel();
    _reloj = null;
  }

  /// La app volvió al frente: si el código venció, se pide uno nuevo.
  void reanudar() {
    if (!_enPausa) return;
    _enPausa = false;
    if (state.codigo == null || state.codigo!.yaVencio) {
      renovar();
    } else {
      _arrancarReloj();
    }
  }

  /// Cambia entre el código peatonal y el vehicular.
  Future<void> cambiarTipo(TipoAcceso nuevo) async {
    if (state.tipo == nuevo) return;
    state = state.copiarCon(
      tipo: nuevo,
      limpiarCodigo: true,
      limpiarError: true,
      limpiarEspera: true,
    );
    await renovar();
  }

  /// El residente eligió otro de sus autos aprobados.
  Future<void> elegirVehiculo(String vehiculoId) async {
    if (state.vehiculoElegidoId == vehiculoId) return;
    state = state.copiarCon(
      vehiculoElegidoId: vehiculoId,
      limpiarCodigo: true,
      limpiarError: true,
    );
    await renovar();
  }

  /// Pide un código nuevo al servidor.
  Future<void> renovar() async {
    if (state.cargando) return;

    state = state.copiarCon(cargando: true, limpiarError: true, limpiarEspera: true);

    try {
      final codigo = await _servicio.pedirCodigo(
        tipo: state.tipo,
        vehiculoId: state.tipo == TipoAcceso.vehicular
            ? state.vehiculoElegidoId
            : null,
      );

      state = state.copiarCon(codigo: codigo, cargando: false, limpiarError: true);
      _arrancarReloj();
    } catch (falla) {
      final problema = Traductor.traducir(falla);

      // Si el servidor pidió esperar (límite de 1 código cada 30 segundos), se
      // guarda cuántos segundos para mostrar la cuenta regresiva en lugar de un
      // error a secas.
      int? espera;
      final coincidencia =
          RegExp(r'(\d+)\s+segundo').firstMatch(problema.mensaje);
      if (coincidencia != null) {
        espera = int.tryParse(coincidencia.group(1)!);
      }

      state = state.copiarCon(
        cargando: false,
        error: problema.mensaje,
        segundosDeEspera: espera,
      );

      // Si fue el límite de códigos, se reintenta solo cuando pase la espera
      if (espera != null && espera > 0) {
        _reloj?.cancel();
        _reloj = Timer(Duration(seconds: espera + 1), () {
          if (!_enPausa) renovar();
        });
      }
    }
  }

  /// El reloj que hace bajar el contador y dispara la renovación.
  void _arrancarReloj() {
    _reloj?.cancel();
    _reloj = Timer.periodic(const Duration(seconds: 1), (_) {
      final codigo = state.codigo;
      if (codigo == null) return;

      // Se avisa a la pantalla para que redibuje el contador
      state = state.copiarCon();

      final restantes = codigo.segundosRestantes;
      if (restantes <= Entorno.margenRenovacionSegundos) {
        renovar();
      }
    });
  }

  @override
  void dispose() {
    _reloj?.cancel();
    super.dispose();
  }
}

final controladorCodigoProvider =
    StateNotifierProvider<ControladorCodigo, EstadoCodigo>((ref) {
  return ControladorCodigo(ref.watch(servicioAccesoProvider));
});

// ============================================================================
// EL RESULTADO DEL ÚLTIMO ESCANEO
// ============================================================================
// La pantalla verde o roja lee de acá.
// ============================================================================

final ultimoResultadoProvider = StateProvider<ResultadoAcceso?>((ref) => null);

// ============================================================================
// LAS PALABRAS DE ESTA INSTALACIÓN
// ============================================================================
// De acá salen las palabras que cambian según dónde esté instalado el sistema:
// en un condominio "residente" y "unidad", en un colegio "apoderado" y "curso".
//
// Las pantallas piden la palabra en vez de tenerla escrita a mano. Así el mismo
// código sirve para el Condominio Cerro Grande y para el Colegio Alemán, sin
// tener dos versiones de la app.
//
// Mientras el perfil se está cargando devuelve las de condominio, que son las
// más comunes: es preferible a dejar la pantalla en blanco esperando.
// ============================================================================

final palabrasProvider = Provider<Palabras>((ref) {
  final perfil = ref.watch(perfilProvider).valueOrNull;
  return Palabras.deTipo(perfil?.tipoInstalacion);
});
