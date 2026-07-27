// ============================================================================
// Tomass Seguridad — Códigos de acceso
// ============================================================================
// Habla con las dos funciones del servidor que ya están andando:
//
//   generar-qr      → pide un código nuevo, que vive 60 segundos
//   validar-acceso  → manda el código escaneado y recibe aprobado o denegado
//
// Este archivo NO decide nada por su cuenta. Todas las reglas de seguridad
// viven en el servidor, a propósito: si estuvieran acá, alguien podría
// modificar la app y saltearlas.
// ============================================================================

import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/entorno.dart';
import '../modelos/modelos.dart';
import '../nucleo/errores.dart';

class ServicioAcceso {
  ServicioAcceso(this._supabase);

  final SupabaseClient _supabase;

  // --------------------------------------------------------------------------
  // Pedir un código nuevo
  // --------------------------------------------------------------------------
  /// [tipo] decide si el código sirve para la entrada peatonal o la vehicular.
  /// [vehiculoId] es opcional: si el residente tiene dos autos aprobados y
  /// eligió uno en particular.
  Future<CodigoAcceso> pedirCodigo({
    required TipoAcceso tipo,
    String? vehiculoId,
  }) async {
    try {
      final respuesta = await _supabase.functions
          .invoke(
            Entorno.funcionGenerarCodigo,
            body: {
              'tipo': tipo.comoTexto,
              if (vehiculoId != null) 'vehiculo_id': vehiculoId,
            },
          )
          .timeout(Entorno.esperaMaxima);

      final datos = respuesta.data;
      if (datos is! Map) {
        throw const ErrorAmigable(
          'El servidor devolvió una respuesta que no entendemos.',
          detalle: 'Intentá de nuevo. Si sigue pasando, avisale a la administración.',
        );
      }

      return CodigoAcceso.desdeMapa(Map<String, dynamic>.from(datos));
    } catch (falla) {
      throw Traductor.traducir(falla);
    }
  }

  // --------------------------------------------------------------------------
  // Validar el código escaneado del muro
  // --------------------------------------------------------------------------
  /// [codigoDelResidente] es el código QR que la app está mostrando.
  /// [codigoDelMuro] es lo que la cámara leyó del cartel pegado en la entrada.
  ///
  /// [idLocal] es un identificador que genera el teléfono. Si se corta el
  /// internet y la app reintenta, el servidor reconoce que es el mismo intento y
  /// no lo cuenta dos veces. Hay que mandar SIEMPRE el mismo id en los
  /// reintentos del mismo escaneo, y uno nuevo cuando es un escaneo distinto.
  Future<ResultadoAcceso> validar({
    required String codigoDelResidente,
    required String codigoDelMuro,
    required String idLocal,
    double? latitud,
    double? longitud,
  }) async {
    try {
      final respuesta = await _supabase.functions
          .invoke(
            Entorno.funcionValidarAcceso,
            body: {
              'token_qr': codigoDelResidente,
              'codigo_estatico': codigoDelMuro,
              'id_local': idLocal,
              if (latitud != null) 'geo_lat': latitud,
              if (longitud != null) 'geo_lng': longitud,
            },
          )
          .timeout(Entorno.esperaMaxima);

      final datos = respuesta.data;
      if (datos is! Map) {
        throw const ErrorAmigable(
          'El servidor devolvió una respuesta que no entendemos.',
        );
      }

      return ResultadoAcceso.desdeMapa(Map<String, dynamic>.from(datos));
    } on FunctionException catch (falla) {
      // Un acceso denegado NO es un error del programa: es una respuesta válida
      // del sistema, y hay que mostrarla en la pantalla roja con su motivo.
      // Por eso se convierte en un resultado en lugar de lanzarse como falla.
      final cuerpo = falla.details;
      if (cuerpo is Map) {
        final mapa = Map<String, dynamic>.from(cuerpo);
        final mensaje = mapa['mensaje'];
        if (mensaje is String && mensaje.isNotEmpty) {
          return ResultadoAcceso(
            aprobado: false,
            titulo: (mapa['titulo'] as String?) ?? 'ACCESO DENEGADO',
            mensaje: mensaje,
            sentido: Sentido.desdeTexto(mapa['sentido'] as String?),
            detalle: mapa['detalle'] as String?,
            residente: mapa['residente'] as String?,
            unidad: mapa['unidad'] as String?,
            puntoAcceso: mapa['punto_acceso'] as String?,
            puedeReintentar: mapa['puede_reintentar'] == true,
          );
        }
      }

      // Si no vino un mensaje entendible, sí es un problema real
      throw Traductor.traducir(falla);
    } catch (falla) {
      throw Traductor.traducir(falla);
    }
  }

  // --------------------------------------------------------------------------
  // Los vehículos aprobados del residente
  // --------------------------------------------------------------------------
  /// Se usa en la pantalla del código para mostrar qué auto va a entrar, y para
  /// dejarlo elegir si tiene más de uno.
  Future<List<Vehiculo>> misVehiculosAprobados() async {
    final usuario = _supabase.auth.currentUser;
    if (usuario == null) return const [];

    try {
      final filas = await _supabase
          .from('vehiculos')
          .select()
          .eq('residente_id', usuario.id)
          .eq('estado', 'aprobado')
          .order('creado_en')
          .timeout(Entorno.esperaMaxima);

      return filas
          .map((f) => Vehiculo.desdeMapa(Map<String, dynamic>.from(f)))
          .toList();
    } catch (falla) {
      throw Traductor.traducir(falla);
    }
  }

  /// Todos los vehículos, en cualquier estado. Para la pantalla Mis Vehículos y
  /// para poder explicarle al residente por qué no puede usar el acceso
  /// vehicular todavía.
  Future<List<Vehiculo>> misVehiculos() async {
    final usuario = _supabase.auth.currentUser;
    if (usuario == null) return const [];

    try {
      final filas = await _supabase
          .from('vehiculos')
          .select()
          .eq('residente_id', usuario.id)
          .order('creado_en', ascending: false)
          .timeout(Entorno.esperaMaxima);

      return filas
          .map((f) => Vehiculo.desdeMapa(Map<String, dynamic>.from(f)))
          .toList();
    } catch (falla) {
      throw Traductor.traducir(falla);
    }
  }
}
