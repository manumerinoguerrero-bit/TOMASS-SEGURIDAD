// ============================================================================
// Tomass Seguridad — Todo lo demás del residente
// ============================================================================
// Vehículos, paquetes, visitas e historial. Están juntos porque son consultas
// simples a la base de datos y separarlos en cuatro archivos casi vacíos haría
// más difícil encontrar las cosas.
//
// La seguridad NO está acá: la ponen los candados de la base de datos. Aunque
// alguien modificara la app para pedir los paquetes de otro residente, la base
// de datos le devolvería una lista vacía.
// ============================================================================

import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/entorno.dart';
import '../modelos/modelos.dart';
import '../nucleo/errores.dart';
import 'servicio_fotos.dart';

class ServicioResidente {
  ServicioResidente(this._supabase, this._fotos);

  final SupabaseClient _supabase;
  final ServicioFotos _fotos;

  String get _miId {
    final usuario = _supabase.auth.currentUser;
    if (usuario == null) {
      throw const ErrorAmigable(
        'Se cerró tu sesión.',
        hayQueIniciarSesion: true,
        sePuedeReintentar: false,
      );
    }
    return usuario.id;
  }

  // ==========================================================================
  // VEHÍCULOS
  // ==========================================================================

  /// Registra un vehículo nuevo. Nace en estado "pendiente": no sirve para
  /// entrar hasta que el administrador lo apruebe.
  Future<void> registrarVehiculo({
    required String condominioId,
    required String patente,
    required String marca,
    required String modelo,
    required String color,
    int? anio,
    File? fotoDeLaPatente,
    File? fotoDelVehiculo,
  }) async {
    String? rutaPatente;
    String? rutaVehiculo;

    try {
      // Las fotos se suben primero. Si algo falla acá, no queda un vehículo a
      // medio registrar en la base de datos.
      if (fotoDeLaPatente != null) {
        rutaPatente = await _fotos.subir(
          archivo: fotoDeLaPatente,
          cajon: CajonDeFotos.vehiculos,
          condominioId: condominioId,
          nombreDescriptivo: 'patente',
        );
      }
      if (fotoDelVehiculo != null) {
        rutaVehiculo = await _fotos.subir(
          archivo: fotoDelVehiculo,
          cajon: CajonDeFotos.vehiculos,
          condominioId: condominioId,
          nombreDescriptivo: 'vehiculo',
        );
      }

      await _supabase.from('vehiculos').insert({
        'condominio_id': condominioId,
        'residente_id': _miId,
        'patente': FormatoPatente.normalizar(patente),
        'marca': marca.trim(),
        'modelo': modelo.trim(),
        'color': color.trim(),
        if (anio != null) 'anio': anio,
        if (rutaPatente != null) 'foto_patente_url': rutaPatente,
        if (rutaVehiculo != null) 'foto_url': rutaVehiculo,
        'estado': 'pendiente',
      }).timeout(Entorno.esperaMaxima);
    } catch (falla) {
      // Si el registro falló, las fotos que ya se subieron quedarían huérfanas.
      // Se limpian para no acumular basura en el servidor.
      await _fotos.borrar(rutaPatente, CajonDeFotos.vehiculos);
      await _fotos.borrar(rutaVehiculo, CajonDeFotos.vehiculos);
      throw Traductor.traducir(falla);
    }
  }

  /// Borra un vehículo propio. Solo tiene sentido con los pendientes o
  /// rechazados: si está aprobado y se borra, deja de poder entrar.
  Future<void> borrarVehiculo(Vehiculo vehiculo) async {
    try {
      await _supabase
          .from('vehiculos')
          .delete()
          .eq('id', vehiculo.id)
          .timeout(Entorno.esperaMaxima);

      await _fotos.borrar(vehiculo.fotoPatenteUrl, CajonDeFotos.vehiculos);
      await _fotos.borrar(vehiculo.fotoUrl, CajonDeFotos.vehiculos);
    } catch (falla) {
      throw Traductor.traducir(falla);
    }
  }

  // ==========================================================================
  // PAQUETES
  // ==========================================================================

  Future<List<Paquete>> misPaquetes() async {
    try {
      final filas = await _supabase
          .from('paquetes')
          .select('''
            id, numero_seguimiento, empresa_courier, descripcion, foto_url,
            estado, recibido_en, entregado_en, retirado_por,
            condominios ( dias_alerta_paquete ),
            guardia_receptor:usuarios!paquetes_guardia_receptor_id_fkey (
              nombre_completo
            ),
            guardia_entrega:usuarios!paquetes_guardia_entrega_id_fkey (
              nombre_completo
            )
          ''')
          .eq('residente_id', _miId)
          .order('recibido_en', ascending: false)
          .timeout(Entorno.esperaMaxima);

      return filas
          .map((f) => Paquete.desdeMapa(Map<String, dynamic>.from(f)))
          .toList();
    } catch (falla) {
      throw Traductor.traducir(falla);
    }
  }

  // ==========================================================================
  // VISITAS
  // ==========================================================================

  Future<List<Visita>> misVisitas() async {
    try {
      final filas = await _supabase
          .from('visitas')
          .select()
          .eq('residente_id', _miId)
          .order('creado_en', ascending: false)
          .limit(50)
          .timeout(Entorno.esperaMaxima);

      return filas
          .map((f) => Visita.desdeMapa(Map<String, dynamic>.from(f)))
          .toList();
    } catch (falla) {
      throw Traductor.traducir(falla);
    }
  }

  /// Crea una visita y devuelve el código para compartir.
  ///
  /// El código lo genera la base de datos sola, no la app: si lo generara la
  /// app, alguien podría fabricar códigos modificándola.
  Future<Visita> invitarVisitante({
    required String condominioId,
    required String? unidadId,
    required String nombreVisitante,
    required DateTime validoDesde,
    required DateTime validoHasta,
    String? cedula,
    String? telefono,
    String? patente,
    String? motivo,
  }) async {
    try {
      final fila = await _supabase
          .from('visitas')
          .insert({
            'condominio_id': condominioId,
            'residente_id': _miId,
            'creada_por': _miId,
            if (unidadId != null) 'unidad_id': unidadId,
            'origen': 'preregistrada',
            'nombre_visitante': nombreVisitante.trim(),
            if (cedula != null && cedula.trim().isNotEmpty)
              'cedula_visitante': cedula.trim(),
            if (telefono != null && telefono.trim().isNotEmpty)
              'telefono_visitante': telefono.trim(),
            if (patente != null && patente.trim().isNotEmpty)
              'patente_vehiculo': FormatoPatente.normalizar(patente),
            if (motivo != null && motivo.trim().isNotEmpty)
              'motivo_visita': motivo.trim(),
            'valido_desde': validoDesde.toUtc().toIso8601String(),
            'valido_hasta': validoHasta.toUtc().toIso8601String(),
            'estado': 'activa',
          })
          .select()
          .single()
          .timeout(Entorno.esperaMaxima);

      return Visita.desdeMapa(Map<String, dynamic>.from(fila));
    } catch (falla) {
      throw Traductor.traducir(falla);
    }
  }

  /// El residente aprueba o rechaza una visita que llegó sin aviso.
  Future<void> responderVisita({
    required String visitaId,
    required bool aprobar,
    String? motivoRechazo,
  }) async {
    try {
      await _supabase
          .from('visitas')
          .update({
            'estado': aprobar ? 'aprobada' : 'rechazada',
            if (aprobar)
              'aprobada_en': DateTime.now().toUtc().toIso8601String()
            else
              'rechazada_en': DateTime.now().toUtc().toIso8601String(),
            if (!aprobar && motivoRechazo != null && motivoRechazo.isNotEmpty)
              'motivo_rechazo': motivoRechazo.trim(),
          })
          .eq('id', visitaId)
          .timeout(Entorno.esperaMaxima);
    } catch (falla) {
      throw Traductor.traducir(falla);
    }
  }

  /// Da de baja un código que el residente ya no quiere que sirva.
  Future<void> cancelarVisita(String visitaId) async {
    try {
      await _supabase
          .from('visitas')
          .update({'estado': 'cancelada'})
          .eq('id', visitaId)
          .timeout(Entorno.esperaMaxima);
    } catch (falla) {
      throw Traductor.traducir(falla);
    }
  }

  // ==========================================================================
  // HISTORIAL DE ACCESOS
  // ==========================================================================

  /// Las entradas y salidas del residente, de la más nueva a la más vieja.
  Future<List<Movimiento>> miHistorial({int cuantos = 60}) async {
    try {
      final filas = await _supabase
          .from('movimientos_acceso')
          .select('''
            id, sentido, tipo_acceso, estado, ocurrido_en, patente_snapshot,
            motivo_denegacion, sincronizado_offline,
            puntos_acceso ( nombre ),
            guardia:usuarios!movimientos_acceso_guardia_id_fkey (
              nombre_completo
            )
          ''')
          .eq('residente_id', _miId)
          .order('ocurrido_en', ascending: false)
          .limit(cuantos)
          .timeout(Entorno.esperaMaxima);

      return filas
          .map((f) => Movimiento.desdeMapa(Map<String, dynamic>.from(f)))
          .toList();
    } catch (falla) {
      throw Traductor.traducir(falla);
    }
  }

  // ==========================================================================
  // MI FICHA
  // ==========================================================================

  /// Cambia la foto de perfil.
  Future<void> cambiarMiFoto({
    required String condominioId,
    required File foto,
    String? rutaAnterior,
  }) async {
    try {
      final ruta = await _fotos.subir(
        archivo: foto,
        cajon: CajonDeFotos.personas,
        condominioId: condominioId,
        nombreDescriptivo: 'perfil',
      );

      await _supabase
          .from('usuarios')
          .update({'foto_url': ruta})
          .eq('id', _miId)
          .timeout(Entorno.esperaMaxima);

      await _fotos.borrar(rutaAnterior, CajonDeFotos.personas);
    } catch (falla) {
      throw Traductor.traducir(falla);
    }
  }

  /// Actualiza el teléfono. El nombre, la cédula y la unidad los cambia solo la
  /// administración: son los datos que identifican a la persona.
  Future<void> cambiarMiTelefono(String telefono) async {
    try {
      await _supabase
          .from('usuarios')
          .update({'telefono': telefono.trim()})
          .eq('id', _miId)
          .timeout(Entorno.esperaMaxima);
    } catch (falla) {
      throw Traductor.traducir(falla);
    }
  }
}
