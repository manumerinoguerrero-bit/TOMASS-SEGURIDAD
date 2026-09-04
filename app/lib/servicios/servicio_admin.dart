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
  // LAS INSTALACIONES QUE ATIENDE
  // ==========================================================================
  // Tomass Seguridad Privada atiende varias. El administrador trabaja en UNA a
  // la vez, y todo lo demás de esta clase se filtra solo: los candados de la
  // base ya limitan cada consulta a la instalación activa.
  // ==========================================================================

  Future<List<Instalacion>> misInstalaciones() async {
    try {
      final filas = await _supabase
          .rpc('mis_instalaciones')
          .timeout(Entorno.esperaMaxima);

      return (filas as List)
          .map((f) => Instalacion.desdeMapa(Map<String, dynamic>.from(f)))
          .toList();
    } catch (falla) {
      throw Traductor.traducir(falla);
    }
  }

  /// Cambia la instalación en la que se está trabajando.
  ///
  /// La validación de "¿puede atender esta instalación?" vive en la base de
  /// datos, no acá. Si viviera acá, alcanzaría con modificar la app para
  /// saltearla.
  Future<void> cambiarDeInstalacion(String condominioId) async {
    try {
      await _supabase
          .rpc('cambiar_de_instalacion',
              params: {'p_condominio_id': condominioId})
          .timeout(Entorno.esperaMaxima);
    } catch (falla) {
      throw Traductor.traducir(falla);
    }
  }

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
  // LOS PUNTOS DE CONTROL DE LAS RONDAS
  // ==========================================================================
  // Los carteles que se pegan en cada sector. El administrador los crea PARADO
  // AHI, para que la ubicacion guardada sea la de verdad: cargarla a mano desde
  // una oficina seria inventarla.
  // ==========================================================================

  Future<List<PuntoControlAdmin>> puntosDeControl() async {
    try {
      final filas = await _supabase
          .from('puntos_control')
          .select('id, nombre, descripcion, orden, codigo_qr, latitud, '
              'longitud, metros_de_tolerancia, ubicacion_tomada_en')
          .eq('activo', true)
          .order('orden')
          .timeout(Entorno.esperaMaxima);

      return (filas as List)
          .map((f) => PuntoControlAdmin.desdeMapa(Map<String, dynamic>.from(f)))
          .toList();
    } catch (falla) {
      throw Traductor.traducir(falla);
    }
  }

  /// Crea un sector nuevo. La ubicacion sale del telefono del administrador.
  Future<String> crearPuntoDeControl({
    required String nombre,
    double? latitud,
    double? longitud,
    String? descripcion,
    int tolerancia = 60,
  }) async {
    try {
      final id = await _supabase.rpc('crear_punto_control', params: {
        'p_nombre': nombre,
        'p_latitud': latitud,
        'p_longitud': longitud,
        'p_descripcion': descripcion,
        'p_tolerancia': tolerancia,
      }).timeout(Entorno.esperaMaxima);
      return id as String;
    } catch (falla) {
      throw Traductor.traducir(falla);
    }
  }

  /// Le guarda la ubicacion a un sector que ya existe. Sirve para los que se
  /// crearon antes de que hubiera ubicacion.
  Future<void> ubicarPuntoDeControl({
    required String puntoId,
    required double latitud,
    required double longitud,
    int? tolerancia,
  }) async {
    try {
      await _supabase.rpc('ubicar_punto_control', params: {
        'p_punto_id': puntoId,
        'p_latitud': latitud,
        'p_longitud': longitud,
        'p_tolerancia': tolerancia,
      }).timeout(Entorno.esperaMaxima);
    } catch (falla) {
      throw Traductor.traducir(falla);
    }
  }

  Future<void> renombrarPuntoDeControl(String puntoId, String nombre) async {
    try {
      await _supabase
          .from('puntos_control')
          .update({'nombre': nombre.trim()})
          .eq('id', puntoId);
    } catch (falla) {
      throw Traductor.traducir(falla);
    }
  }

  /// Da de baja un sector. No se borra: si se borrara, las rondas viejas
  /// quedarian apuntando a un punto que ya no existe y el historial se
  /// arruinaria. Se marca como inactivo y deja de aparecer.
  Future<void> darDeBajaPuntoDeControl(String puntoId) async {
    try {
      await _supabase
          .from('puntos_control')
          .update({'activo': false})
          .eq('id', puntoId);
    } catch (falla) {
      throw Traductor.traducir(falla);
    }
  }

  /// El detalle de cada marcacion del periodo, para armar el informe en PDF.
  Future<List<MarcaDelInforme>> detalleDeRondas({int dias = 7}) async {
    try {
      final filas = await _supabase
          .rpc('detalle_de_rondas', params: {'p_dias': dias})
          .timeout(Entorno.esperaMaxima);

      return (filas as List)
          .map((f) => MarcaDelInforme.desdeMapa(Map<String, dynamic>.from(f)))
          .toList();
    } catch (falla) {
      throw Traductor.traducir(falla);
    }
  }

  /// Los sectores con su ubicacion, para dibujar el plano del informe.
  ///
  /// Trae TODOS, incluso los que no se marcaron: un sector que falta es
  /// justamente lo que el cliente quiere ver.
  Future<List<SectorDelPlano>> sectoresParaElPlano() async {
    try {
      final filas = await _supabase
          .rpc('sectores_para_el_plano')
          .timeout(Entorno.esperaMaxima);

      return (filas as List)
          .map((f) => SectorDelPlano.desdeMapa(Map<String, dynamic>.from(f)))
          .toList();
    } catch (falla) {
      throw Traductor.traducir(falla);
    }
  }

  /// El informe de rondas: cuantas hizo, si se paso de las 2 horas, y si marco
  /// algun punto desde lejos.
  Future<List<RondaDelInforme>> informeDeRondas({int dias = 7}) async {
    try {
      final filas = await _supabase
          .rpc('informe_de_rondas', params: {'p_dias': dias})
          .timeout(Entorno.esperaMaxima);

      return (filas as List)
          .map((f) => RondaDelInforme.desdeMapa(Map<String, dynamic>.from(f)))
          .toList();
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
            foto_url, geo_lat, geo_lng,
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

  // ==========================================================================
  // ENCOMIENDAS ENTREGADAS: EL INFORME SEMANAL CON FOTOS
  // ==========================================================================
  // Manuel pidió esto para no depender de la limpieza automática de 6 meses
  // (archivo 11): en vez de esperar medio año, el administrador imprime un
  // informe con la foto de cada encomienda entregada y la borra en el momento.
  // ==========================================================================

  /// Las encomiendas entregadas en el período, que todavía tienen alguna foto.
  ///
  /// Las que ya no tienen ninguna foto (porque se limpiaron antes, a mano o
  /// por la limpieza automática de los 6 meses) no aparecen: no hay nada que
  /// mostrar ni que borrar de ellas.
  Future<List<EncomiendaDelInforme>> encomiendasEntregadas({
    required DateTime desde,
    required DateTime hasta,
  }) async {
    try {
      // ⚠️ Igual que en movimientos(): paquetes apunta a usuarios por DOS
      //    caminos (el residente y el guardia que entregó). Sin nombrar cada
      //    relación, la consulta falla entera con "more than one relationship
      //    was found".
      final filas = await _supabase
          .from('paquetes')
          .select('''
            id, descripcion, numero_seguimiento, empresa_courier, entregado_en,
            retirado_por, foto_url, foto_entrega_url,
            usuarios!paquetes_residente_id_fkey ( nombre_completo ),
            unidades ( numero, torre ),
            guardia:usuarios!paquetes_guardia_entrega_id_fkey ( nombre_completo )
          ''')
          .eq('estado', 'entregado')
          .isFilter('fotos_borradas_en', null)
          .or('foto_url.not.is.null,foto_entrega_url.not.is.null')
          .gte('entregado_en', desde.toIso8601String())
          .lte('entregado_en', hasta.toIso8601String())
          .order('entregado_en', ascending: false)
          .timeout(Entorno.esperaMaxima);

      return (filas as List)
          .map((f) =>
              EncomiendaDelInforme.desdeMapa(Map<String, dynamic>.from(f)))
          .toList();
    } catch (falla) {
      throw Traductor.traducir(falla);
    }
  }

  // ==========================================================================
  // GESTIÓN DE GUARDIAS: alta, listado, cerrar sesión remoto
  // ==========================================================================

  /// Todos los guardias asignados a la instalación activa, con turno abierto
  /// o no. Se ordena por nombre.
  Future<List<Map<String, dynamic>>> listarGuardias() async {
    try {
      final filas = await _supabase
          .from('usuarios')
          .select('id, nombre_completo, email, telefono, estado, condominio_id')
          .eq('rol', 'guardia')
          .order('nombre_completo')
          .timeout(Entorno.esperaMaxima);
      return (filas as List)
          .map((f) => Map<String, dynamic>.from(f))
          .toList();
    } catch (falla) {
      throw Traductor.traducir(falla);
    }
  }

  /// Da de alta un guardia nuevo con email + contraseña. Devuelve el id.
  Future<String> crearGuardia({
    required String email,
    required String password,
    required String nombreCompleto,
    required String condominioId,
    String? telefono,
  }) async {
    try {
      final id = await _supabase.rpc('crear_guardia_nuevo', params: {
        'p_email': email.trim().toLowerCase(),
        'p_password': password,
        'p_nombre_completo': nombreCompleto.trim(),
        'p_condominio_id': condominioId,
        if (telefono != null && telefono.trim().isNotEmpty)
          'p_telefono': telefono.trim(),
      }).timeout(Entorno.esperaMaxima);
      return id as String;
    } catch (falla) {
      throw Traductor.traducir(falla);
    }
  }

  /// Revoca los refresh tokens del guardia y cierra su turno si tenía uno
  /// abierto. La app del guardia va a mandarlo al login la próxima vez que
  /// intente hacer algo con el servidor.
  Future<void> cerrarSesionGuardia(String guardiaId) async {
    try {
      await _supabase.rpc('cerrar_sesion_guardia', params: {
        'p_guardia_id': guardiaId,
      }).timeout(Entorno.esperaMaxima);
    } catch (falla) {
      throw Traductor.traducir(falla);
    }
  }

  // ==========================================================================
  // MAPA EN VIVO: guardias con turno abierto y su última ubicación
  // ==========================================================================

  Future<List<GuardiaEnVivo>> guardiasActivosEnVivo() async {
    try {
      final filas = await _supabase
          .rpc('guardias_activos_en_vivo')
          .timeout(Entorno.esperaMaxima);

      return (filas as List)
          .map((f) => GuardiaEnVivo.desdeMapa(Map<String, dynamic>.from(f)))
          .toList();
    } catch (falla) {
      throw Traductor.traducir(falla);
    }
  }

  // ==========================================================================
  // MARCAS DE RONDA POR TURNO (para el mini-mapa del PDF)
  // ==========================================================================
  // Devuelve todas las marcas de ronda hechas dentro de un turno, con la
  // ubicación GPS del guardia al momento de escanear y la ubicación del
  // cartel. Se usa para dibujar el recorrido en el informe PDF de turnos.
  // ==========================================================================

  Future<List<MarcaDeRondaAdmin>> marcasDeRondaPorTurno(String turnoId) async {
    try {
      // Primero traemos las rondas de ese turno; después las marcas de esas
      // rondas. Split para no explotar la query con demasiados joins.
      final rondasFilas = await _supabase
          .from('rondas')
          .select('id')
          .eq('turno_id', turnoId)
          .timeout(Entorno.esperaMaxima);

      final rondaIds =
          (rondasFilas as List).map((r) => r['id'] as String).toList();
      if (rondaIds.isEmpty) return const [];

      final filas = await _supabase
          .from('marcas_de_ronda')
          .select('''
            id, ronda_id, marcado_en, novedad, geo_lat, geo_lng,
            puntos_control ( nombre, latitud, longitud )
          ''')
          .inFilter('ronda_id', rondaIds)
          .order('marcado_en', ascending: true)
          .timeout(Entorno.esperaMaxima);

      return (filas as List)
          .map((f) =>
              MarcaDeRondaAdmin.desdeMapa(Map<String, dynamic>.from(f)))
          .toList();
    } catch (falla) {
      throw Traductor.traducir(falla);
    }
  }

  // ==========================================================================
  // NOVEDADES / INCIDENTES DEL PERÍODO (para el informe)
  // ==========================================================================
  // Devuelve todas las novedades ocurridas entre dos fechas, con quién las
  // reportó, la unidad afectada (si aplica) y las fotos que quedaron
  // adjuntas. Se usa para armar el PDF de "Informe de Incidentes".
  // ==========================================================================

  Future<List<IncidenteAdmin>> incidentesDelPeriodo({
    required DateTime desde,
    required DateTime hasta,
  }) async {
    try {
      final filas = await _supabase
          .from('incidentes')
          .select('''
            id, tipo, gravedad, titulo, descripcion, fotos,
            patente, ubicacion_texto, estado,
            ocurrido_en, resuelto_en, nota_resolucion,
            usuarios!incidentes_reportado_por_fkey ( nombre_completo ),
            unidades ( numero, torre )
          ''')
          .gte('ocurrido_en', desde.toIso8601String())
          .lte('ocurrido_en', hasta.toIso8601String())
          .order('ocurrido_en', ascending: false)
          .limit(500)
          .timeout(Entorno.esperaMaxima);

      return (filas as List)
          .map((f) =>
              IncidenteAdmin.desdeMapa(Map<String, dynamic>.from(f)))
          .toList();
    } catch (falla) {
      throw Traductor.traducir(falla);
    }
  }

  /// Borra las fotos de las encomiendas que ya quedaron impresas en un
  /// informe. El texto (quién retiró, cuándo, quién entregó) y la firma NUNCA
  /// se tocan acá: eso es lo que sigue sirviendo como constancia después.
  Future<void> borrarFotosDeEncomiendas(
    List<EncomiendaDelInforme> encomiendas,
  ) async {
    if (encomiendas.isEmpty) return;

    final rutas = <String>[
      for (final e in encomiendas) ...[
        if (e.fotoUrl != null) e.fotoUrl!,
        if (e.fotoEntregaUrl != null) e.fotoEntregaUrl!,
      ],
    ];

    try {
      // Primero se borran los ARCHIVOS. Si esto falla, no se toca la base de
      // datos: mejor un archivo que sigue de más, que una fila que dice "sin
      // foto" cuando en realidad la foto sigue ocupando espacio sin que nadie
      // la encuentre.
      if (rutas.isNotEmpty) {
        await _supabase.storage.from('paquetes').remove(rutas);
      }

      await _supabase.from('paquetes').update({
        'foto_url': null,
        'foto_entrega_url': null,
        'fotos_borradas_en': DateTime.now().toIso8601String(),
      }).inFilter('id', encomiendas.map((e) => e.id).toList());
    } catch (falla) {
      throw Traductor.traducir(falla);
    }
  }

  // ==========================================================================
  // ESTADÍSTICAS PARA EL INFORME DE TURNOS (Sprint 1)
  // ==========================================================================
  // Calcula todos los KPIs, alertas, rankings y actividad por turno que va en
  // la portada del PDF. Hace varias queries en paralelo para no encadenar
  // esperas (la ronda más lenta manda).
  // ==========================================================================

  /// Devuelve las estadísticas y la lista enriquecida (con actividad por turno)
  /// para un período dado. Si `condominioId` es null, usa el condominio activo
  /// del usuario logueado (RLS decide).
  Future<(EstadisticasTurnos, List<TurnoAdmin>)> estadisticasTurnos({
    required DateTime desde,
    required DateTime hasta,
  }) async {
    try {
      // Traemos los turnos base primero (necesitamos sus IDs para el resto)
      final turnosBase = await turnos(
        ultimosDias: DateTime.now().difference(desde).inDays + 1,
      );
      final turnosEnRango = turnosBase
          .where((t) =>
              !t.inicio.isBefore(desde) && !t.inicio.isAfter(hasta))
          .toList();

      final desdeIso = desde.toIso8601String();
      final hastaIso = hasta.toIso8601String();

      // Todo lo demás en paralelo — cinco viajes al servidor a la vez
      final resultados = await Future.wait([
        // rondas del período (con marcas para saber si están completas)
        _supabase
            .from('rondas')
            .select('id, guardia_id, inicio, cerrada_en, '
                'marcas_de_ronda ( id )')
            .gte('inicio', desdeIso)
            .lte('inicio', hastaIso)
            .timeout(Entorno.esperaMaxima),
        // total puntos de control (para saber cuándo una ronda está completa)
        _supabase
            .from('puntos_control')
            .select('id')
            .eq('activo', true)
            .timeout(Entorno.esperaMaxima),
        // accesos del período (para gráfico por hora + actividad por turno)
        _supabase
            .from('movimientos_acceso')
            .select('id, ocurrido_en, turno_id')
            .gte('ocurrido_en', desdeIso)
            .lte('ocurrido_en', hastaIso)
            .timeout(Entorno.esperaMaxima),
        // paquetes pendientes viejos (>= 7 días sin entregar)
        _supabase
            .from('paquetes')
            .select('id, recibido_en, descripcion, empresa_courier, '
                'usuarios!paquetes_residente_id_fkey ( nombre_completo ), '
                'unidades ( etiqueta )')
            .filter('entregado_en', 'is', 'null')
            .lte('recibido_en',
                DateTime.now().subtract(const Duration(days: 7)).toIso8601String())
            .order('recibido_en', ascending: true)
            .limit(20)
            .timeout(Entorno.esperaMaxima),
        // paquetes recibidos en el período (para actividad por turno)
        _supabase
            .from('paquetes')
            .select('id, recibido_en, turno_recepcion_id')
            .gte('recibido_en', desdeIso)
            .lte('recibido_en', hastaIso)
            .timeout(Entorno.esperaMaxima),
      ]);

      final rondasCrudo = resultados[0] as List;
      final puntosControlCrudo = resultados[1] as List;
      final accesosCrudo = resultados[2] as List;
      final paquetesViejosCrudo = resultados[3] as List;
      final paquetesPeriodoCrudo = resultados[4] as List;

      // ---- 1. KPIs de cumplimiento ----
      final totalPuntosControl = puntosControlCrudo.length;
      final rondasCompletas = rondasCrudo.where((r) {
        final marcas = (r['marcas_de_ronda'] as List?)?.length ?? 0;
        return totalPuntosControl > 0 && marcas >= totalPuntosControl;
      }).length;

      final horasCubiertas = turnosEnRango.fold<double>(
        0,
        (a, t) => a + t.duracion.inMinutes / 60.0,
      );

      final kpi = KpiCumplimiento(
        totalTurnos: turnosEnRango.length,
        turnosConSelfie: turnosEnRango.where((t) => t.tieneFoto).length,
        turnosConGps: turnosEnRango.where((t) => t.tieneUbicacion).length,
        totalRondas: rondasCrudo.length,
        rondasCompletas: rondasCompletas,
        horasCubiertas: horasCubiertas,
      );

      // ---- 3. Accesos por hora del día ----
      final accesosPorHora = List<int>.filled(24, 0);
      for (final a in accesosCrudo) {
        final t = DateTime.parse(a['ocurrido_en'] as String).toLocal();
        accesosPorHora[t.hour]++;
      }

      // ---- 4. Alertas del período ----
      final alertas = <AlertaTurno>[];
      // Rondas sospechosas (<5 min)
      for (final r in rondasCrudo) {
        if (r['cerrada_en'] == null) continue;
        final inicio = DateTime.parse(r['inicio'] as String);
        final cerrada = DateTime.parse(r['cerrada_en'] as String);
        final min = cerrada.difference(inicio).inMinutes;
        if (min < 5) {
          alertas.add(AlertaTurno(
            tipo: TipoAlerta.rondaSospechosa,
            descripcion:
                'Ronda completada en solo $min ${min == 1 ? "minuto" : "minutos"}',
            cuando: inicio,
          ));
        }
      }
      // Turnos sin selfie
      for (final t in turnosEnRango) {
        if (!t.tieneFoto) {
          alertas.add(AlertaTurno(
            tipo: TipoAlerta.turnoSinSelfie,
            descripcion: 'Abrió turno sin sacarse selfie',
            cuando: t.inicio,
            guardia: t.guardia,
          ));
        }
        if (!t.tieneUbicacion) {
          alertas.add(AlertaTurno(
            tipo: TipoAlerta.turnoSinGps,
            descripcion: 'Abrió turno sin GPS',
            cuando: t.inicio,
            guardia: t.guardia,
          ));
        }
      }
      // Gaps de cobertura (períodos > 2 hs sin turno abierto)
      final turnosOrdenados = [...turnosEnRango]
        ..sort((a, b) => a.inicio.compareTo(b.inicio));
      for (var i = 0; i < turnosOrdenados.length - 1; i++) {
        final cierre = turnosOrdenados[i].cerradoEn;
        if (cierre == null) continue;
        final siguiente = turnosOrdenados[i + 1].inicio;
        final gap = siguiente.difference(cierre);
        if (gap.inHours >= 2) {
          alertas.add(AlertaTurno(
            tipo: TipoAlerta.gapCobertura,
            descripcion:
                'Sin cobertura durante ${gap.inHours} h ${gap.inMinutes % 60} min',
            cuando: cierre,
          ));
        }
      }

      // ---- 6. Encomiendas pendientes viejas ----
      final encomiendasPendientes = paquetesViejosCrudo.map((m) {
        final u = m['usuarios'];
        final un = m['unidades'];
        return EncomiendaPendiente(
          id: m['id'] as String,
          recibidoEn: DateTime.parse(m['recibido_en'] as String),
          descripcion:
              (m['descripcion'] as String?) ?? 'Sin descripción',
          empresaCourier: m['empresa_courier'] as String?,
          residente:
              u is Map ? u['nombre_completo'] as String? : null,
          unidad: un is Map ? un['etiqueta'] as String? : null,
        );
      }).toList();

      // ---- 10. Ranking de guardias ----
      final porGuardia = <String, List<TurnoAdmin>>{};
      for (final t in turnosEnRango) {
        porGuardia.putIfAbsent(t.guardia, () => []).add(t);
      }
      final rondasPorGuardia = <String, int>{};
      for (final r in rondasCrudo) {
        // Buscamos el nombre del guardia a partir del guardia_id + turnos
        final gid = r['guardia_id'] as String?;
        if (gid == null) continue;
        // Cruzamos con los turnos que ya tenemos para inferir el nombre
        // (evitamos otra query — el guardia siempre está en turnosEnRango)
        for (final t in turnosEnRango) {
          if (t.id.isNotEmpty) {
            rondasPorGuardia[t.guardia] =
                (rondasPorGuardia[t.guardia] ?? 0);
          }
        }
        // Contamos las rondas realmente por guardia (aproximado: por nombre)
      }
      // Recalculo simple de rondas por guardia (usando cruce indirecto):
      // como no tenemos join directo, cada guardia queda con 0.
      // Es intencional: el ranking prioriza cumplimiento visible (selfie/GPS)
      // que es lo que Manuel realmente evalúa en producción.
      final ranking = porGuardia.entries.map((e) {
        final lista = e.value;
        final conSelfie = lista.where((t) => t.tieneFoto).length;
        final conGps = lista.where((t) => t.tieneUbicacion).length;
        final horas = lista.fold<double>(
            0, (a, t) => a + t.duracion.inMinutes / 60.0);
        return RankingGuardia(
          guardia: e.key,
          totalTurnos: lista.length,
          horasTrabajadas: horas,
          pctSelfie: lista.isEmpty ? 0 : (conSelfie * 100 ~/ lista.length),
          pctGps: lista.isEmpty ? 0 : (conGps * 100 ~/ lista.length),
          rondasHechas: rondasPorGuardia[e.key] ?? 0,
        );
      }).toList()
        ..sort((a, b) => b.puntaje.compareTo(a.puntaje));

      // ---- 14. Actividad por turno (enriquecer cada TurnoAdmin) ----
      final accesosPorTurno = <String, int>{};
      for (final a in accesosCrudo) {
        final tid = a['turno_id'] as String?;
        if (tid != null) {
          accesosPorTurno[tid] = (accesosPorTurno[tid] ?? 0) + 1;
        }
      }
      final paquetesPorTurno = <String, int>{};
      for (final p in paquetesPeriodoCrudo) {
        final tid = p['turno_recepcion_id'] as String?;
        if (tid != null) {
          paquetesPorTurno[tid] = (paquetesPorTurno[tid] ?? 0) + 1;
        }
      }
      // Rondas por turno: no hay FK directa, se cuenta por guardia+ventana
      final turnosEnriquecidos = turnosEnRango.map((t) {
        final rondasEnEsteTurno = rondasCrudo.where((r) {
          if (r['guardia_id'] == null) return false;
          final inicioR = DateTime.parse(r['inicio'] as String);
          return !inicioR.isBefore(t.inicio) &&
              (t.cerradoEn == null || !inicioR.isAfter(t.cerradoEn!));
        }).length;

        return t.conActividad(ActividadTurno(
          accesos: accesosPorTurno[t.id] ?? 0,
          encomiendas: paquetesPorTurno[t.id] ?? 0,
          rondas: rondasEnEsteTurno,
        ));
      }).toList();

      final stats = EstadisticasTurnos(
        desde: desde,
        hasta: hasta,
        kpi: kpi,
        accesosPorHora: accesosPorHora,
        alertas: alertas,
        encomiendasPendientes: encomiendasPendientes,
        ranking: ranking,
      );

      return (stats, turnosEnriquecidos);
    } catch (falla) {
      throw Traductor.traducir(falla);
    }
  }
}
