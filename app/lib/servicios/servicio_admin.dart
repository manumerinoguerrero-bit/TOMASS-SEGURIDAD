// ============================================================================
// Tomass Seguridad — Todo lo que hace el administrador
// ============================================================================
// QUÉ RESUELVE
//
//   Hasta ahora, para aprobar un vehículo o dar de alta a un residente había
//   que entrar a la base de datos por atrás. Eso funciona para una instalación
//   de prueba; con cinco instalaciones reales es insostenible, y además obliga
//   a pedírselo a alguien que sepa de bases de datos.
//
// LA REGLA DE SEGURIDAD, EN SIMPLE
//
//   Casi todo lo de acá se hace directo contra la base de datos, sin pasar por
//   el servidor, y eso es seguro por una razón: la base tiene candados propios
//   (las políticas de seguridad). Aunque alguien modificara la app para pedir
//   los datos de otro condominio, la base se los negaría.
//
//   La ÚNICA excepción es dar de alta a una persona, porque eso exige crear su
//   cuenta de acceso y para eso hace falta la llave maestra. Eso va por el
//   servidor, en la función administrar-personas.
// ============================================================================

import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/entorno.dart';
import '../modelos/admin.dart';
import '../nucleo/errores.dart';

class ServicioAdmin {
  ServicioAdmin(this._supabase);

  final SupabaseClient _supabase;

  // ==========================================================================
  // EL RESUMEN DE LA PANTALLA DE INICIO
  // ==========================================================================

  Future<ResumenAdmin> resumen() async {
    try {
      // Se piden todos los números a la vez y no uno tras otro: así la pantalla
      // tarda lo que tarda el más lento, y no la suma de todos.
      final n = await Future.wait([
        _contarIgual('vehiculos', 'estado', 'pendiente'),
        _contarIgual('usuarios', 'estado', 'activo'),
        _contarIgual('paquetes', 'estado', 'en_porteria'),
        _contarTodo('unidades'),
        _contarVacio('incidentes', 'resuelto_en'),
        _contarVacio('turnos', 'cerrado_en'),
      ]);

      return ResumenAdmin(
        vehiculosPorAprobar: n[0],
        personasActivas: n[1],
        paquetesEnPorteria: n[2],
        espacios: n[3],
        novedadesAbiertas: n[4],
        guardiasDeTurno: n[5],
      );
    } catch (falla) {
      throw Traductor.traducir(falla);
    }
  }

  Future<int> _contarTodo(String tabla) async {
    final r = await _supabase.from(tabla).select('id').count(CountOption.exact);
    return r.count;
  }

  Future<int> _contarIgual(String tabla, String campo, String valor) async {
    final r = await _supabase
        .from(tabla)
        .select('id')
        .eq(campo, valor)
        .count(CountOption.exact);
    return r.count;
  }

  /// Cuenta las filas donde ese campo está vacío. Sirve para "sin resolver"
  /// (resuelto_en vacío) y "de turno ahora" (cerrado_en vacío).
  Future<int> _contarVacio(String tabla, String campo) async {
    final r = await _supabase
        .from(tabla)
        .select('id')
        .isFilter(campo, null)
        .count(CountOption.exact);
    return r.count;
  }

  // ==========================================================================
  // VEHÍCULOS: APROBAR Y RECHAZAR
  // ==========================================================================
  // Es lo que más se usa del panel. Un residente registra su auto y no puede
  // entrar hasta que alguien lo apruebe.
  // ==========================================================================

  Future<List<VehiculoParaAprobar>> vehiculosPorAprobar() async {
    try {
      final filas = await _supabase
          .from('vehiculos')
          .select('''
            id, patente, marca, modelo, color, anio, estado, creado_en,
            foto_url, foto_patente_url, motivo_rechazo,
            usuarios!vehiculos_residente_id_fkey (
              id, nombre_completo, telefono,
              unidades!usuarios_unidad_id_fkey ( numero, torre )
            )
          ''')
          .eq('estado', 'pendiente')
          .order('creado_en', ascending: true)
          .timeout(Entorno.esperaMaxima);

      return (filas as List)
          .map((f) => VehiculoParaAprobar.desdeMapa(Map<String, dynamic>.from(f)))
          .toList();
    } catch (falla) {
      throw Traductor.traducir(falla);
    }
  }

  Future<void> aprobarVehiculo(String vehiculoId) async {
    try {
      await _supabase.from('vehiculos').update({
        'estado': 'aprobado',
        'aprobado_en': DateTime.now().toIso8601String(),
        'aprobado_por': _supabase.auth.currentUser?.id,
        'motivo_rechazo': null,
      }).eq('id', vehiculoId);
    } catch (falla) {
      throw Traductor.traducir(falla);
    }
  }

  /// El motivo es obligatorio a propósito: el residente lo va a leer, y
  /// "rechazado" a secas no le dice qué corregir.
  Future<void> rechazarVehiculo(String vehiculoId, String motivo) async {
    if (motivo.trim().length < 5) {
      throw const ErrorAmigable(
        'Falta explicar por qué se rechaza.',
        detalle: 'El residente va a leer este motivo. Con "no" no sabe qué '
            'corregir para volver a intentar.',
        sePuedeReintentar: false,
      );
    }
    try {
      await _supabase.from('vehiculos').update({
        'estado': 'rechazado',
        'motivo_rechazo': motivo.trim(),
        'aprobado_en': null,
        'aprobado_por': _supabase.auth.currentUser?.id,
      }).eq('id', vehiculoId);
    } catch (falla) {
      throw Traductor.traducir(falla);
    }
  }

  // ==========================================================================
  // PERSONAS
  // ==========================================================================

  Future<List<PersonaAdmin>> personas({String? busqueda, String? rol}) async {
    try {
      var consulta = _supabase.from('usuarios').select('''
            id, nombre_completo, email, telefono, cedula, rol, estado,
            relacion_unidad, creado_en,
            unidades!usuarios_unidad_id_fkey ( id, numero, torre )
          ''');

      if (rol != null) consulta = consulta.eq('rol', rol);
      if (busqueda != null && busqueda.trim().length >= 2) {
        final t = busqueda.trim();
        consulta = consulta.or('nombre_completo.ilike.%$t%,email.ilike.%$t%');
      }

      final filas = await consulta
          .order('nombre_completo')
          .timeout(Entorno.esperaMaxima);

      return (filas as List)
          .map((f) => PersonaAdmin.desdeMapa(Map<String, dynamic>.from(f)))
          .toList();
    } catch (falla) {
      throw Traductor.traducir(falla);
    }
  }

  /// Da de alta a una persona nueva y devuelve su contraseña provisoria.
  ///
  /// Pasa por el servidor porque crear la cuenta de acceso exige la llave
  /// maestra, que no puede vivir dentro de la app.
  Future<AltaDePersona> crearPersona({
    required String nombreCompleto,
    required String email,
    required String rol,
    String? telefono,
    String? cedula,
    String? unidadId,
    String? relacionUnidad,
  }) async {
    return _pedirleAlServidor({
      'accion': 'crear',
      'nombre_completo': nombreCompleto,
      'email': email,
      'rol': rol,
      if (telefono != null && telefono.isNotEmpty) 'telefono': telefono,
      if (cedula != null && cedula.isNotEmpty) 'cedula': cedula,
      if (unidadId != null) 'unidad_id': unidadId,
      if (relacionUnidad != null) 'relacion_unidad': relacionUnidad,
    });
  }

  Future<AltaDePersona> cambiarEstado(String usuarioId, String estado) {
    return _pedirleAlServidor({
      'accion': 'cambiar_estado',
      'usuario_id': usuarioId,
      'estado': estado,
    });
  }

  Future<AltaDePersona> restablecerClave(String usuarioId) {
    return _pedirleAlServidor({
      'accion': 'restablecer_clave',
      'usuario_id': usuarioId,
    });
  }

  /// Cambia los datos que NO son la cuenta de acceso. Esto sí va directo a la
  /// base: los candados de la base ya impiden tocar gente de otra instalación.
  Future<void> editarPersona({
    required String usuarioId,
    required String nombreCompleto,
    String? telefono,
    String? cedula,
    String? unidadId,
    String? relacionUnidad,
  }) async {
    try {
      await _supabase.from('usuarios').update({
        'nombre_completo': nombreCompleto.trim(),
        'telefono': telefono?.trim(),
        'cedula': cedula?.trim(),
        'unidad_id': unidadId,
        'relacion_unidad': relacionUnidad,
      }).eq('id', usuarioId);
    } catch (falla) {
      throw Traductor.traducir(falla);
    }
  }

  Future<AltaDePersona> _pedirleAlServidor(Map<String, dynamic> cuerpo) async {
    try {
      final respuesta = await _supabase.functions
          .invoke(Entorno.funcionAdministrarPersonas, body: cuerpo)
          .timeout(Entorno.esperaMaxima);

      final datos = respuesta.data;
      if (datos is! Map) {
        throw const ErrorAmigable(
          'El servidor devolvió una respuesta que no entendemos.',
        );
      }

      final mapa = Map<String, dynamic>.from(datos);
      if (mapa['aprobado'] == false) {
        throw ErrorAmigable(
          (mapa['mensaje'] ?? 'No se pudo completar.') as String,
          sePuedeReintentar: false,
        );
      }

      return AltaDePersona(
        mensaje: (mapa['mensaje'] ?? '') as String,
        claveProvisoria: mapa['clave_provisoria'] as String?,
      );
    } catch (falla) {
      throw Traductor.traducir(falla);
    }
  }

  // ==========================================================================
  // ESPACIOS (unidades en un condominio, cursos en un colegio)
  // ==========================================================================

  Future<List<EspacioAdmin>> espacios() async {
    try {
      final filas = await _supabase
          .from('unidades')
          .select('id, numero, torre, tipo, estacionamientos, notas')
          .order('numero')
          .timeout(Entorno.esperaMaxima);

      return (filas as List)
          .map((f) => EspacioAdmin.desdeMapa(Map<String, dynamic>.from(f)))
          .toList();
    } catch (falla) {
      throw Traductor.traducir(falla);
    }
  }

  Future<void> guardarEspacio({
    String? id,
    required String condominioId,
    required String numero,
    String? torre,
    required String tipo,
    int estacionamientos = 0,
  }) async {
    try {
      final datos = {
        'condominio_id': condominioId,
        'numero': numero.trim(),
        'torre': torre?.trim().isEmpty ?? true ? null : torre!.trim(),
        'tipo': tipo,
        'estacionamientos': estacionamientos,
      };

      if (id == null) {
        await _supabase.from('unidades').insert(datos);
      } else {
        await _supabase.from('unidades').update(datos).eq('id', id);
      }
    } catch (falla) {
      throw Traductor.traducir(falla);
    }
  }

  Future<void> borrarEspacio(String id) async {
    try {
      await _supabase.from('unidades').delete().eq('id', id);
    } catch (falla) {
      // El error más común acá es que el espacio tenga gente colgando. Se
      // explica en criollo en vez de mostrar el error de la base de datos.
      final texto = falla.toString();
      if (texto.contains('foreign key') || texto.contains('violates')) {
        throw const ErrorAmigable(
          'No se puede borrar: todavía hay personas asignadas.',
          detalle: 'Primero cambiales el espacio a esas personas, o desactivalas.',
          sePuedeReintentar: false,
        );
      }
      throw Traductor.traducir(falla);
    }
  }

  // ==========================================================================
  // INFORMES: QUIÉN ENTRÓ Y SALIÓ
  // ==========================================================================
  // Es lo que el administrador lleva a la reunión de copropietarios, y lo que
  // se revisa cuando hay un problema.
  // ==========================================================================

  Future<List<MovimientoAdmin>> movimientos({
    DateTime? desde,
    DateTime? hasta,
    String? tipo,
  }) async {
    try {
      // ⚠️ La relación con usuarios va nombrada a mano y NO se puede abreviar.
      //    movimientos_acceso apunta a usuarios por DOS caminos (el residente y
      //    el guardia). Si no se dice cuál, la consulta falla entera con
      //    "more than one relationship was found". Ya nos rompió el login una
      //    vez por este mismo motivo.
      var consulta = _supabase.from('movimientos_acceso').select('''
            id, tipo_acceso, sentido, estado, patente_snapshot,
            nombre_snapshot, unidad_snapshot, ocurrido_en, motivo_denegacion,
            usuarios!movimientos_acceso_residente_id_fkey ( nombre_completo ),
            puntos_acceso ( nombre )
          ''');

      if (desde != null) {
        consulta = consulta.gte('ocurrido_en', desde.toIso8601String());
      }
      if (hasta != null) {
        consulta = consulta.lte('ocurrido_en', hasta.toIso8601String());
      }
      if (tipo != null) consulta = consulta.eq('tipo_acceso', tipo);

      final filas = await consulta
          .order('ocurrido_en', ascending: false)
          .limit(500)
          .timeout(Entorno.esperaMaxima);

      return (filas as List)
          .map((f) => MovimientoAdmin.desdeMapa(Map<String, dynamic>.from(f)))
          .toList();
    } catch (falla) {
      throw Traductor.traducir(falla);
    }
  }

  // ==========================================================================
  // TURNOS: QUIÉN ESTUVO A CARGO
  // ==========================================================================

  Future<List<TurnoAdmin>> turnos({int ultimosDias = 14}) async {
    try {
      final desde = DateTime.now().subtract(Duration(days: ultimosDias));
      final filas = await _supabase
          .from('turnos')
          .select('''
            id, inicio, cerrado_en, notas_entrega,
            usuarios!turnos_guardia_id_fkey ( nombre_completo ),
            puntos_acceso ( nombre )
          ''')
          .gte('inicio', desde.toIso8601String())
          .order('inicio', ascending: false)
          .timeout(Entorno.esperaMaxima);

      return (filas as List)
          .map((f) => TurnoAdmin.desdeMapa(Map<String, dynamic>.from(f)))
          .toList();
    } catch (falla) {
      throw Traductor.traducir(falla);
    }
  }
}
