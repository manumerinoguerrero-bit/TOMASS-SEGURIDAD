// ============================================================================
// Tomass Seguridad — Lo que hace el guardia
// ============================================================================
// Turnos, la cola de autos esperando la barrera, paquetes e incidentes.
//
// LA PIEZA MÁS IMPORTANTE ES LA COLA DE AUTOS EN VIVO
//
//   La pantalla del guardia NO le pregunta al servidor cada dos segundos si
//   llegó un auto. El servidor le AVISA en el momento en que llega. Eso es lo
//   que hace que la tarjeta aparezca en menos de un segundo sin gastar batería
//   ni datos preguntando al vacío.
//
//   Técnicamente: la base de datos publica los cambios de la tabla de
//   solicitudes, y la app está suscrita a esa publicación.
// ============================================================================

import 'dart:async';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/entorno.dart';
import '../modelos/admin.dart';
import '../modelos/modelos.dart';
import '../nucleo/errores.dart';
import 'cola_offline.dart';
import 'servicio_fotos.dart';

class ServicioGuardia {
  ServicioGuardia(this._supabase, this._fotos, {this.cola});

  final SupabaseClient _supabase;
  final ServicioFotos _fotos;

  /// Cola para operaciones del guardia que se pueden retrasar si no hay
  /// internet (marcar punto, registrar acceso manual, entregar paquete,
  /// crear incidente). Si es null (ej: BD corrupta al arrancar), los RPCs
  /// se comportan como siempre: fallan con el error de red.
  final ColaOffline? cola;

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

  /// ID del condominio activo del guardia. Se llama a la RPC mi_condominio
  /// (la misma que usan las policies RLS) para filtrar explícitamente en
  /// las queries que no van via RPC.
  ///
  /// Reportado el 27/09/2026: Miguel Sotelo (guardia de Encomenderos) veía
  /// en Encomiendas e Inventario paquetes del Condominio Milagros. Fue el
  /// mismo bug que ya se había arreglado en ultimosAccesos y personasDentro
  /// pero varias queries de paquetes y de búsqueda de residentes seguían
  /// sin filtro por condominio_id — dependían solo de RLS, y con admin de
  /// múltiples instalaciones (o cambio de instalación mid-session) se
  /// mezclaban datos.
  Future<String?> _condominioActivo() async {
    final id = await _supabase
        .rpc('mi_condominio')
        .timeout(Entorno.esperaMaxima);
    return id as String?;
  }

  // ==========================================================================
  // LAS INSTALACIONES QUE ATIENDE
  // ==========================================================================
  // Casi todos los guardias trabajan en una sola. Los que rotan entre dos
  // (turnos compartidos entre instalaciones) usan esto para elegir en cuál
  // están parados hoy, antes de abrir turno.
  //
  // Son las mismas dos funciones que ya usaba el panel del administrador para
  // lo mismo: no es un mecanismo aparte, es el mismo permiso extendido.
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
  // TURNOS
  // ==========================================================================

  /// Los puestos donde el guardia puede abrir turno EN EL CONDOMINIO ACTIVO.
  ///
  /// El filtro por condominio_id es explícito: sin él, un guardia que
  /// atiende varias instalaciones veía puestos de todas mezclados.
  Future<List<PuntoAcceso>> puestosDisponibles() async {
    try {
      final condominioId = await _condominioActivo();
      if (condominioId == null) return const [];

      final filas = await _supabase
          .from('puntos_acceso')
          .select('id, nombre, tipo, modo, ubicacion, activo')
          .eq('condominio_id', condominioId)
          .eq('activo', true)
          .order('tipo')
          .timeout(Entorno.esperaMaxima);

      return filas
          .map((f) => PuntoAcceso.desdeMapa(Map<String, dynamic>.from(f)))
          .toList();
    } catch (falla) {
      throw Traductor.traducir(falla);
    }
  }

  // ==========================================================================
  // EL INGRESO ANOTADO A MANO
  // ==========================================================================
  // Se usa donde NO hay codigo QR: los colegios y Viveros Yapur tienen barrera
  // y portones que abre el guardia, asi que no hay nadie apuntando un telefono
  // a un cartel. El guardia mira, abre, y anota.
  //
  // TODAS LAS REVISIONES VIVEN EN LA BASE DE DATOS, NO ACA
  //
  //   Que el guardia tenga turno abierto, que la garita sea de su instalacion,
  //   y que no falte ningun dato obligatorio lo revisa la funcion
  //   registrar_acceso_manual del servidor.
  //
  //   Si viviera en la app, alcanzaria con modificar la app para saltearlo.
  //   Aca solo se arman los datos y se traducen los errores al castellano.
  // ==========================================================================

  /// Anota una entrada o salida a mano.
  ///
  /// [idLocal] tiene que ser el MISMO si se reintenta el mismo ingreso (por
  /// ejemplo si se corto el internet), y uno nuevo para cada ingreso distinto.
  /// Asi el servidor reconoce el reintento y no anota dos veces a la misma
  /// persona.
  // ==========================================================================
  // VISITAS QUE LLEGAN SIN AVISO
  // ==========================================================================
  // EL CASO REAL DE LA GARITA DE UN CONDOMINIO
  //
  //   Llega alguien al porton y no esta en ninguna lista. El guardia no puede
  //   decidir por su cuenta: tiene que preguntarle al residente.
  //
  //   Hoy eso se hace por telefono y no queda registro de nada. Si manana el
  //   residente dice "yo nunca autorice a esa persona", el guardia no tiene con
  //   que defenderse.
  //
  //   Con esto el residente contesta desde su celular y la respuesta queda
  //   guardada con la hora.
  // ==========================================================================

  /// Busca residentes por nombre o por unidad, para elegir a quien avisarle.
  Future<List<Map<String, dynamic>>> buscarAQuienAvisar(String texto) async {
    if (texto.trim().length < 2) return const [];
    try {
      final t = texto.trim();
      final filas = await _supabase
          .from('usuarios')
          .select('id, nombre_completo, telefono, '
              'unidades!usuarios_unidad_id_fkey ( numero, torre )')
          .eq('rol', 'residente')
          .eq('estado', 'activo')
          .or('nombre_completo.ilike.%$t%,email.ilike.%$t%')
          .limit(15)
          .timeout(Entorno.esperaMaxima);

      return (filas as List).map((f) => Map<String, dynamic>.from(f)).toList();
    } catch (falla) {
      throw Traductor.traducir(falla);
    }
  }

  /// Registra la visita y le manda el aviso al residente.
  Future<String> pedirAutorizacionDeVisita({
    required String residenteId,
    required String nombre,
    String? cedula,
    String? patente,
    String? motivo,
    String? telefono,
    String? fotoUrl,
    int horasDeValidez = 4,
    bool llamoPorTelefono = false,
    String? notaGuardia,
  }) async {
    try {
      final id = await _supabase.rpc('registrar_visita_espontanea', params: {
        'p_residente_id': residenteId,
        'p_nombre': nombre,
        'p_cedula': cedula,
        'p_patente': patente,
        'p_motivo': motivo,
        'p_telefono': telefono,
        'p_foto_url': fotoUrl,
        'p_horas_de_validez': horasDeValidez,
        'p_llamo_por_telefono': llamoPorTelefono,
        'p_nota_guardia': notaGuardia,
      }).timeout(Entorno.esperaMaxima);
      return id as String;
    } catch (falla) {
      throw Traductor.traducir(falla);
    }
  }

  /// Las visitas de las ultimas 2 horas y en que quedaron.
  ///
  /// Se limita a 2 horas a proposito: una visita de ayer ya no esta parada en el
  /// porton, y llenaria la pantalla de ruido justo cuando el guardia necesita
  /// ver la de ahora.
  Future<List<VisitaEsperando>> visitasEsperandoRespuesta() async {
    try {
      final filas = await _supabase
          .rpc('visitas_esperando_respuesta')
          .timeout(Entorno.esperaMaxima);

      return (filas as List)
          .map((f) => VisitaEsperando.desdeMapa(Map<String, dynamic>.from(f)))
          .toList();
    } catch (falla) {
      throw Traductor.traducir(falla);
    }
  }

  // ==========================================================================
  // RONDAS CON PUNTOS DE CONTROL
  // ==========================================================================
  // Es lo que le permite al condominio SABER que la ronda se hizo, en vez de
  // creerle al guardia. Los carteles estan pegados en cada sector: para
  // marcarlos hay que ir hasta ahi.
  //
  // Todas las revisiones (que haya turno abierto, que el cartel sea de esta
  // instalacion, que no se cuente dos veces el mismo punto) viven en la base de
  // datos. Aca solo se piden los datos y se traducen los errores.
  // ==========================================================================

  /// Los carteles de esta instalacion, con la marca de cuales ya se pasaron en
  /// la ronda que esta abierta.
  ///
  /// Filtro por garita: si el guardia esta cubriendo una garita puntual
  /// ([puntoAccesoId] no null), solo trae los sectores asignados a esa
  /// garita mas los COMUNES (punto_acceso_id = NULL). En los colegios cada
  /// garita hace su lado del recorrido; en condominios chicos con una sola
  /// garita, todos los puntos son comunes y se ven igual.
  Future<List<PuntoControl>> puntosDeControl({
    String? rondaId,
    String? puntoAccesoId,
  }) async {
    try {
      // Filtro explícito por condominio activo — sin esto un guardia de
      // Encomenderos vería puntos QR de Milagros y podría escanearlos.
      final condominioId = await _condominioActivo();
      if (condominioId == null) return const [];

      var consulta = _supabase
          .from('puntos_control')
          .select('id, nombre, orden, descripcion, codigo_qr, '
              'latitud, longitud, metros_de_tolerancia')
          .eq('condominio_id', condominioId)
          .eq('activo', true);
      if (puntoAccesoId != null) {
        // Filtro OR: asignados a esa garita O sin garita (comunes).
        consulta = consulta.or(
          'punto_acceso_id.eq.$puntoAccesoId,punto_acceso_id.is.null',
        );
      }
      final filas =
          await consulta.order('orden').timeout(Entorno.esperaMaxima);

      final puntos = (filas as List)
          .map((f) => PuntoControl.desdeMapa(Map<String, dynamic>.from(f)))
          .toList();

      if (rondaId == null) return puntos;

      // Cuales ya marco en esta ronda
      final marcas = await _supabase
          .from('marcas_de_ronda')
          .select('punto_control_id, marcado_en')
          .eq('ronda_id', rondaId)
          .timeout(Entorno.esperaMaxima);

      final cuando = <String, DateTime>{};
      for (final m in (marcas as List)) {
        cuando[m['punto_control_id'] as String] =
            DateTime.parse(m['marcado_en'] as String);
      }

      return puntos.map((p) => p.conMarca(cuando[p.id])).toList();
    } catch (falla) {
      throw Traductor.traducir(falla);
    }
  }

  /// La ronda en curso, o null si no arranco ninguna.
  Future<RondaAbierta?> miRondaAbierta() async {
    try {
      final filas = await _supabase
          .rpc('mi_ronda_abierta')
          .timeout(Entorno.esperaMaxima);
      final lista = filas as List;
      if (lista.isEmpty) return null;
      return RondaAbierta.desdeMapa(Map<String, dynamic>.from(lista.first));
    } catch (falla) {
      throw Traductor.traducir(falla);
    }
  }

  /// Arranca el recorrido. Si ya habia uno abierto, devuelve ese: pasa seguido
  /// que el guardia cierre la app en medio de la ronda y la vuelva a abrir.
  Future<String> empezarRonda() async {
    try {
      final id = await _supabase.rpc('empezar_ronda').timeout(Entorno.esperaMaxima);
      return id as String;
    } catch (falla) {
      throw Traductor.traducir(falla);
    }
  }

  /// Marca un punto al pasar por el.
  ///
  /// [idLocal] tiene que ser el MISMO si se reintenta la misma marca, para que
  /// un corte de internet no la anote dos veces.
  ///
  /// Modo offline: si al mandar la marca no hay señal, se encola para que la
  /// mande el sincronizador cuando vuelva internet y se devuelve un
  /// ResultadoDeMarca.enCola. La UI muestra un toast distinto para que el
  /// guardia sepa que la marca quedó guardada pero todavía no llegó.
  Future<ResultadoDeMarca> marcarPuntoDeControl({
    required String idLocal,
    required String codigoDelCartel,
    String? novedad,
    String? fotoUrl,
    double? latitud,
    double? longitud,
  }) async {
    final params = <String, dynamic>{
      'p_id_local': idLocal,
      'p_codigo_qr': codigoDelCartel,
      'p_novedad': novedad,
      'p_foto_url': fotoUrl,
      'p_geo_lat': latitud,
      'p_geo_lng': longitud,
    };
    try {
      final filas = await _supabase
          .rpc('marcar_punto_control', params: params)
          .timeout(Entorno.esperaMaxima);

      final lista = filas as List;
      if (lista.isEmpty) {
        throw const ErrorAmigable('El servidor no contesto lo que esperabamos.');
      }
      return ResultadoDeMarca.desdeMapa(Map<String, dynamic>.from(lista.first));
    } catch (falla) {
      // Si el error es de red Y tenemos cola, encolamos y le decimos a la
      // UI "guardado, se mandará cuando vuelva internet". Cualquier otro
      // error (QR no reconocido, no hay turno abierto, etc.) se propaga
      // como siempre — no tiene sentido encolar algo que el backend ya
      // rechazó por motivos de datos.
      if (cola != null && esErrorDeRed(falla)) {
        await cola!.encolar(
          idLocal: idLocal,
          tipo: 'marcar_punto_control',
          params: params,
        );
        return ResultadoDeMarca.enCola(nombrePunto: codigoDelCartel);
      }
      throw Traductor.traducir(falla);
    }
  }

  /// Cierra el recorrido. Devuelve cuantos puntos marco de cuantos, y cuanto
  /// tardo en minutos.
  Future<(int marcados, int total, int minutos)> cerrarRonda({String? notas}) async {
    try {
      final filas = await _supabase
          .rpc('cerrar_ronda', params: {'p_notas': notas})
          .timeout(Entorno.esperaMaxima);

      final lista = filas as List;
      if (lista.isEmpty) return (0, 0, 0);
      final r = Map<String, dynamic>.from(lista.first);
      return (
        (r['marcados'] ?? 0) as int,
        (r['total'] ?? 0) as int,
        (r['minutos'] ?? 0) as int,
      );
    } catch (falla) {
      throw Traductor.traducir(falla);
    }
  }

  Future<void> anotarAccesoManual({
    required String idLocal,
    required String puntoAccesoId,
    required String nombre,
    required String rut,
    required String tipoAcceso, // 'peatonal' o 'vehicular'
    required String sentido, // 'entrada' o 'salida'
    required String aDondeVa,
    required String autorizadoPor,
    String? patente,
    String? fotoUrl,
    String? observacion,
    String? residenteId,
    DateTime? ocurridoEn,
  }) async {
    try {
      await _supabase.rpc('registrar_acceso_manual', params: {
        'p_id_local': idLocal,
        'p_punto_acceso_id': puntoAccesoId,
        'p_nombre': nombre,
        'p_tipo_acceso': tipoAcceso,
        'p_sentido': sentido,
        'p_rut': rut,
        'p_a_donde_va': aDondeVa,
        'p_autorizado_por': autorizadoPor,
        'p_patente': patente,
        'p_foto_url': fotoUrl,
        'p_observacion': observacion,
        'p_residente_id': residenteId,
        // Hora del ingreso. Si el guardia dejó null, el servidor usa now().
        // Sirve para cuando el guardia estaba ocupado y anota la visita
        // 20 minutos después de que pasó, con la hora real de ingreso.
        if (ocurridoEn != null) 'p_ocurrido_en': ocurridoEn.toUtc().toIso8601String(),
      }).timeout(Entorno.esperaMaxima);
    } catch (falla) {
      throw Traductor.traducir(falla);
    }
  }

  /// El turno abierto del guardia, o null si no empezó.
  Future<Turno?> miTurnoAbierto() async {
    try {
      final fila = await _supabase
          .from('turnos')
          .select('''
            id, punto_acceso_id, inicio, fin_programado, cerrado_en,
            notas_entrega,
            puntos_acceso ( nombre, tipo, codigo_qr_estatico )
          ''')
          .eq('guardia_id', _miId)
          .isFilter('cerrado_en', null)
          .order('inicio', ascending: false)
          .limit(1)
          .maybeSingle()
          .timeout(Entorno.esperaMaxima);

      if (fila == null) return null;
      return Turno.desdeMapa(Map<String, dynamic>.from(fila));
    } catch (falla) {
      throw Traductor.traducir(falla);
    }
  }

  /// Abre el turno del guardia.
  ///
  /// Si [puntoAccesoId] va vacío, el guardia **cubre todo el condominio** y le
  /// llegan los avisos de todas las entradas. Ese es el caso normal: en la
  /// mayoría de los condominios hay un solo guardia y tiene que atender la
  /// entrada peatonal y la vehicular al mismo tiempo.
  // ==========================================================================
  // MAPA EN VIVO: el guardia manda su posición cada 2-3 minutos
  // ==========================================================================
  // Se llama desde un Timer periódico mientras haya turno abierto. El RPC
  // del backend actualiza SOLO el turno abierto del guardia; si no tiene
  // ninguno, no hace nada (para no molestar entre cerrar y abrir).
  // ==========================================================================

  Future<void> actualizarMiUbicacion({
    required double lat,
    required double lng,
  }) async {
    try {
      await _supabase.rpc('actualizar_mi_ubicacion', params: {
        'p_lat': lat,
        'p_lng': lng,
      }).timeout(const Duration(seconds: 8));
    } catch (_) {
      // A propósito: NO propagamos el error. El envío periódico de GPS es
      // un "best effort": si falla porque el guardia perdió señal, no
      // conviene interrumpirle nada; en el próximo tick vuelve a intentar.
    }
  }

  /// Registra la salida de una persona que está dentro, clonando los datos
  /// (nombre, RUT, unidad, patente, garita, vehículo) de su último ingreso.
  ///
  /// El guardia lo dispara con un botón desde "Personas dentro" — evita
  /// tener que reescribir todo el formulario para cerrar una persona que
  /// ya está en la lista. La RPC en el servidor rechaza si ya se marcó
  /// salida o si no hay entrada previa.
  Future<void> registrarSalidaRapida({
    required String personaTipo,
    required String personaId,
    required String idLocal,
    double? latitud,
    double? longitud,
  }) async {
    try {
      await _supabase.rpc('registrar_salida_rapida', params: {
        'p_persona_tipo': personaTipo,
        'p_persona_id': personaId,
        'p_id_local': idLocal,
        'p_geo_lat': latitud,
        'p_geo_lng': longitud,
      }).timeout(Entorno.esperaMaxima);
    } catch (falla) {
      throw Traductor.traducir(falla);
    }
  }

  Future<Turno> abrirTurno({
    required String condominioId,
    String? puntoAccesoId,
    DateTime? finProgramado,
    // Selfie + GPS del inicio: el admin necesita ver quién estaba a cargo y
    // dónde. Son opcionales para no romper si el teléfono no puede darlos
    // (permiso de cámara denegado, GPS sin señal): se abre el turno igual.
    String? fotoUrl,
    double? geoLat,
    double? geoLng,
  }) async {
    try {
      final fila = await _supabase
          .from('turnos')
          .insert({
            'condominio_id': condominioId,
            'guardia_id': _miId,
            // Vacío = cubre todo el condominio
            'punto_acceso_id': puntoAccesoId,
            if (finProgramado != null)
              'fin_programado': finProgramado.toUtc().toIso8601String(),
            if (fotoUrl != null) 'foto_url': fotoUrl,
            if (geoLat != null) 'geo_lat': geoLat,
            if (geoLng != null) 'geo_lng': geoLng,
          })
          .select('''
            id, punto_acceso_id, inicio, fin_programado, cerrado_en,
            notas_entrega,
            puntos_acceso ( nombre, tipo, codigo_qr_estatico )
          ''')
          .single()
          .timeout(Entorno.esperaMaxima);

      return Turno.desdeMapa(Map<String, dynamic>.from(fila));
    } on PostgrestException catch (falla) {
      // La base de datos impide dos turnos abiertos a la vez para el mismo
      // guardia. Si pasa, es que quedó uno sin cerrar de la vez anterior.
      if (falla.code == '23505') {
        throw const ErrorAmigable(
          'Ya tenés un turno abierto.',
          detalle: 'Cerralo antes de empezar uno nuevo.',
          sePuedeReintentar: false,
        );
      }
      throw Traductor.traducir(falla);
    } catch (falla) {
      throw Traductor.traducir(falla);
    }
  }

  /// Cierra el turno. El guardia deja de recibir avisos de ese puesto.
  Future<void> cerrarTurno({String? notasParaElSiguiente}) async {
    try {
      await _supabase
          .rpc('cerrar_turno', params: {'p_notas': notasParaElSiguiente})
          .timeout(Entorno.esperaMaxima);
    } catch (falla) {
      throw Traductor.traducir(falla);
    }
  }

  // ==========================================================================
  // LA COLA DE AUTOS — EN VIVO
  // ==========================================================================

  /// Los autos esperando la barrera ahora mismo.
  ///
  /// Si [puntoAccesoId] va vacío, trae los de TODAS las entradas del
  /// condominio: es lo que corresponde cuando el guardia cubre todo.
  Future<List<AutoEsperando>> autosEsperando([String? puntoAccesoId]) async {
    try {
      final condominioId = await _condominioActivo();
      if (condominioId == null) return const [];

      var consulta = _supabase
          .from('v_solicitudes_vehiculares_pendientes')
          .select()
          .eq('condominio_id', condominioId);

      if (puntoAccesoId != null) {
        consulta = consulta.eq('punto_acceso_id', puntoAccesoId);
      }

      final filas = await consulta
          .order('solicitado_en')
          .timeout(Entorno.esperaMaxima);

      return filas
          .map((f) => AutoEsperando.desdeMapa(Map<String, dynamic>.from(f)))
          .toList();
    } catch (falla) {
      throw Traductor.traducir(falla);
    }
  }

  /// Avisa cada vez que la cola de autos cambia.
  ///
  /// No se suscribe directo a la vista (las vistas no publican cambios): se
  /// suscribe a la tabla de solicitudes y, cuando algo cambia, vuelve a pedir la
  /// lista completa. Es una consulta chica y así los datos llegan siempre
  /// completos, con la foto y los datos del auto ya cruzados.
  /// Si [puntoAccesoId] va vacío, escucha los autos de TODAS las entradas.
  Stream<List<AutoEsperando>> colaDeAutosEnVivo([String? puntoAccesoId]) {
    final control = StreamController<List<AutoEsperando>>.broadcast();
    RealtimeChannel? canal;
    Timer? respaldo;

    Future<void> refrescar() async {
      try {
        final lista = await autosEsperando(puntoAccesoId);
        if (!control.isClosed) control.add(lista);
      } catch (_) {
        // Un error puntual no debe cortar el flujo: el próximo aviso reintenta.
      }
    }

    control.onListen = () {
      refrescar();

      canal = _supabase
          .channel('cola_autos_${puntoAccesoId ?? 'todo'}')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'solicitudes_vehiculares',
            callback: (_) => refrescar(),
          )
          .subscribe();

      // Red de seguridad: si la conexión en vivo se cae sin avisar, esto
      // refresca igual cada 20 segundos. Un auto esperando sin que nadie se
      // entere es el peor escenario posible de esta pantalla.
      respaldo = Timer.periodic(const Duration(seconds: 20), (_) => refrescar());
    };

    control.onCancel = () async {
      respaldo?.cancel();
      if (canal != null) await _supabase.removeChannel(canal!);
      await control.close();
    };

    return control.stream;
  }

  /// El guardia aprieta ABRIR ACCESO (o DENEGAR).
  ///
  /// Todo lo que pasa —registrar la entrada, dejar anotado qué guardia autorizó,
  /// sacar la tarjeta de la cola— ocurre en una sola operación del servidor. Si
  /// algo fallara a mitad de camino, no queda nada a medias.
  Future<void> resolverAuto({
    required String solicitudId,
    required bool abrir,
    String? motivoSiDeniega,
  }) async {
    try {
      await _supabase.rpc('resolver_solicitud_vehicular', params: {
        'p_solicitud_id': solicitudId,
        'p_aprobar': abrir,
        'p_motivo': motivoSiDeniega,
      }).timeout(Entorno.esperaMaxima);
    } catch (falla) {
      throw Traductor.traducir(falla);
    }
  }

  // ==========================================================================
  // PANEL
  // ==========================================================================

  Future<ResumenCondominio> resumen() async {
    try {
      final fila = await _supabase
          .from('v_resumen_condominio')
          .select()
          .maybeSingle()
          .timeout(Entorno.esperaMaxima);

      if (fila == null) return ResumenCondominio.vacio;
      return ResumenCondominio.desdeMapa(Map<String, dynamic>.from(fila));
    } catch (falla) {
      throw Traductor.traducir(falla);
    }
  }

  /// Los últimos movimientos DEL CONDOMINIO ACTIVO del guardia.
  ///
  /// El filtro por `condominio_id` es explícito a propósito. Cuando el mismo
  /// usuario administra varias instalaciones (Manuel es admin de todas) y
  /// entra como guardia a una, sin este filtro la lista mezclaba accesos de
  /// otros condominios donde también tiene permisos. Reportado el 14/09/2026
  /// al ver "ingreso de apoderados y profesores" en Milagros del Cerro Grande.
  ///
  /// El id se pide con la RPC `mi_condominio()` — misma que usan las políticas
  /// RLS del servidor, así el filtro del cliente y el del servidor coinciden.
  Future<List<Movimiento>> ultimosAccesos({int cuantos = 25}) async {
    try {
      final condominioId = await _supabase
          .rpc('mi_condominio')
          .timeout(Entorno.esperaMaxima) as String?;
      if (condominioId == null) return const [];

      final filas = await _supabase
          .from('movimientos_acceso')
          .select('''
            id, sentido, tipo_acceso, estado, ocurrido_en, patente_snapshot,
            motivo_denegacion, sincronizado_offline,
            nombre_snapshot, rut_snapshot, unidad_snapshot,
            autorizado_por_texto,
            usuarios!movimientos_acceso_residente_id_fkey ( nombre_completo ),
            puntos_acceso ( nombre )
          ''')
          .eq('condominio_id', condominioId)
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

  /// Quiénes están dentro del CONDOMINIO ACTIVO ahora.
  /// Es el dato que hay que dar si vienen los bomberos.
  ///
  /// Igual que en ultimosAccesos(), se filtra por condominio_id explícito
  /// contra `mi_condominio()`. La vista `v_personas_dentro` expone la
  /// columna pero no filtra por sí sola, así que un usuario que administra
  /// varias instalaciones vería personas mezcladas de todas ellas.
  Future<List<Map<String, dynamic>>> personasDentro() async {
    try {
      final condominioId = await _supabase
          .rpc('mi_condominio')
          .timeout(Entorno.esperaMaxima) as String?;
      if (condominioId == null) return const [];

      final filas = await _supabase
          .from('v_personas_dentro')
          .select()
          .eq('condominio_id', condominioId)
          .order('entro_en', ascending: false)
          .timeout(Entorno.esperaMaxima);

      return filas.map((f) => Map<String, dynamic>.from(f)).toList();
    } catch (falla) {
      throw Traductor.traducir(falla);
    }
  }

  // ==========================================================================
  // PAQUETES
  // ==========================================================================

  /// Sugerencias de destinatarios escritos a mano en paquetes anteriores.
  ///
  /// Cuando el guardia escribe el nombre a mano, se le van sugiriendo los
  /// nombres que ya usó antes en otros paquetes. Así, la próxima vez que
  /// venga un paquete para "María de la Casa 12" no tiene que reescribirlo:
  /// alcanza con tocar la sugerencia.
  ///
  /// Devuelve una lista de {nombre, unidad, usos} ordenada por más usados.
  Future<List<Map<String, dynamic>>> sugerenciasDestinatariosAMano({
    String? empezandoCon,
  }) async {
    try {
      // Filtro por condominio activo: antes las sugerencias mezclaban
      // destinatarios escritos a mano de todos los condominios donde el
      // usuario tenía permiso. Miguel Sotelo (Encomenderos) veía nombres
      // de residentes de Milagros que había escrito otro guardia.
      final condominioId = await _condominioActivo();
      if (condominioId == null) return const [];

      var consulta = _supabase
          .from('paquetes')
          .select('destinatario_texto, unidad_texto')
          .eq('condominio_id', condominioId)
          .not('destinatario_texto', 'is', null);

      if (empezandoCon != null && empezandoCon.trim().isNotEmpty) {
        consulta = consulta.ilike('destinatario_texto',
            '${empezandoCon.trim()}%');
      }

      final filas = await consulta.limit(80).timeout(Entorno.esperaMaxima);

      // Agrupar por nombre+unidad para contar los usos y quedarnos con los
      // más frecuentes. Se hace en el cliente porque son pocas filas.
      final agrupado = <String, Map<String, dynamic>>{};
      for (final f in (filas as List)) {
        final nombre = (f['destinatario_texto'] as String?)?.trim() ?? '';
        final unidad = (f['unidad_texto'] as String?)?.trim() ?? '';
        if (nombre.isEmpty) continue;
        final clave = '$nombre|$unidad';
        agrupado.update(
          clave,
          (v) => {...v, 'usos': (v['usos'] as int) + 1},
          ifAbsent: () => {'nombre': nombre, 'unidad': unidad, 'usos': 1},
        );
      }

      final ordenado = agrupado.values.toList()
        ..sort((a, b) => (b['usos'] as int).compareTo(a['usos'] as int));
      return ordenado.take(10).toList();
    } catch (_) {
      // Una sugerencia que falla no vale un cartel de error: el guardia
      // igual puede escribir el nombre completo a mano.
      return const [];
    }
  }

  /// Quién suele retirar los paquetes de este residente, basado en el
  /// historial de entregas anteriores.
  ///
  /// Cuando el guardia va a entregar un paquete y activa "lo retira otra
  /// persona", en vez de escribir el nombre desde cero le aparecen las
  /// personas que ya retiraron antes en esta misma casa, ordenadas por
  /// frecuencia. En un condominio, después de dos o tres entregas ya se
  /// forma el patrón (la nana los martes, la señora en la tarde).
  Future<List<String>> quienSueleRetirar({required String residenteId}) async {
    try {
      // Defensa en profundidad: el filtro por residente_id ya limita a un
      // residente puntual, pero además restringimos al condominio activo
      // para el caso improbable de residentes homónimos en distintos
      // condominios que administra el mismo usuario.
      final condominioId = await _condominioActivo();
      if (condominioId == null) return const [];

      final filas = await _supabase
          .from('paquetes')
          .select('retirado_por')
          .eq('condominio_id', condominioId)
          .eq('residente_id', residenteId)
          .eq('estado', 'entregado')
          .not('retirado_por', 'is', null)
          .order('entregado_en', ascending: false)
          .limit(30)
          .timeout(Entorno.esperaMaxima);

      // Se agrupa por nombre y se cuentan las apariciones en el cliente:
      // son pocas filas por residente y no vale la pena una función en el
      // servidor.
      final conteos = <String, int>{};
      for (final f in (filas as List)) {
        final nombre = ((f['retirado_por'] as String?) ?? '').trim();
        if (nombre.isEmpty) continue;
        conteos.update(nombre, (v) => v + 1, ifAbsent: () => 1);
      }

      final ordenado = conteos.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      return ordenado.take(5).map((e) => e.key).toList();
    } catch (_) {
      // Una sugerencia que falla no vale un cartel de error: el guardia
      // igual puede escribir el nombre a mano.
      return const [];
    }
  }

  /// Recibe un paquete. La foto es obligatoria: es el respaldo si después
  /// alguien reclama que llegó dañado.
  ///
  /// Hay dos formas de decir para quién es:
  ///   - [residenteId] si es alguien registrado en el sistema (lo normal)
  ///   - [destinatarioTexto] si es alguien que todavía no está registrado,
  ///     con [unidadTexto] opcional (por ejemplo "Casa 12" o "Torre B 401")
  ///
  /// Al menos uno de los dos tiene que venir; si vienen los dos, se guardan
  /// los dos y prevalece el registrado.
  Future<void> recibirPaquete({
    required String condominioId,
    String? residenteId,
    String? unidadId,
    String? destinatarioTexto,
    String? unidadTexto,
    required File foto,
    required String idLocal,
    String? numeroSeguimiento,
    String? empresaCourier,
    String? descripcion,
    String? turnoId,
  }) async {
    if ((residenteId == null || residenteId.isEmpty) &&
        (destinatarioTexto == null ||
            destinatarioTexto.trim().length < 2)) {
      throw const ErrorAmigable(
        'Falta el destinatario del paquete.',
        detalle: 'Elegí un residente de la lista o escribí el nombre a mano.',
        sePuedeReintentar: false,
      );
    }

    String? rutaFoto;
    try {
      rutaFoto = await _fotos.subir(
        archivo: foto,
        cajon: CajonDeFotos.paquetes,
        condominioId: condominioId,
        nombreDescriptivo: 'paquete',
      );

      await _supabase.from('paquetes').insert({
        'condominio_id': condominioId,
        'id_local': idLocal,
        if (residenteId != null && residenteId.isNotEmpty)
          'residente_id': residenteId,
        if (unidadId != null) 'unidad_id': unidadId,
        if (destinatarioTexto != null && destinatarioTexto.trim().isNotEmpty)
          'destinatario_texto': destinatarioTexto.trim(),
        if (unidadTexto != null && unidadTexto.trim().isNotEmpty)
          'unidad_texto': unidadTexto.trim(),
        'foto_url': rutaFoto,
        if (numeroSeguimiento != null && numeroSeguimiento.trim().isNotEmpty)
          'numero_seguimiento': numeroSeguimiento.trim(),
        if (empresaCourier != null && empresaCourier.trim().isNotEmpty)
          'empresa_courier': empresaCourier.trim(),
        if (descripcion != null && descripcion.trim().isNotEmpty)
          'descripcion': descripcion.trim(),
        'estado': 'en_porteria',
        'guardia_receptor_id': _miId,
        if (turnoId != null) 'turno_recepcion_id': turnoId,
      }).timeout(Entorno.esperaMaxima);
    } catch (falla) {
      await _fotos.borrar(rutaFoto, CajonDeFotos.paquetes);
      throw Traductor.traducir(falla);
    }
  }

  /// El inventario de portería del CONDOMINIO ACTIVO, ordenado por antigüedad.
  ///
  /// Filtro explícito por condominio_id — reportado el 27/09/2026 por Miguel
  /// Sotelo: veía paquetes de otro condominio al abrir el inventario. La
  /// vista v_paquetes_porteria expone la columna pero no filtra por sí sola.
  Future<List<Map<String, dynamic>>> inventarioDePaquetes() async {
    try {
      final condominioId = await _condominioActivo();
      if (condominioId == null) return const [];

      final filas = await _supabase
          .from('v_paquetes_porteria')
          .select()
          .eq('condominio_id', condominioId)
          .order('recibido_en')
          .timeout(Entorno.esperaMaxima);

      return filas.map((f) => Map<String, dynamic>.from(f)).toList();
    } catch (falla) {
      throw Traductor.traducir(falla);
    }
  }

  /// Entrega un paquete con la firma del residente.
  Future<void> entregarPaquete({
    required String paqueteId,
    required String condominioId,
    required File firma,
    required bool identidadValidada,
    File? fotoDeLaEntrega,
    String? retiradoPor,
    String? turnoId,
  }) async {
    String? rutaFirma;
    String? rutaFoto;
    try {
      rutaFirma = await _fotos.subir(
        archivo: firma,
        cajon: CajonDeFotos.firmas,
        condominioId: condominioId,
        nombreDescriptivo: 'firma',
      );

      if (fotoDeLaEntrega != null) {
        rutaFoto = await _fotos.subir(
          archivo: fotoDeLaEntrega,
          cajon: CajonDeFotos.paquetes,
          condominioId: condominioId,
          nombreDescriptivo: 'entrega',
        );
      }

      await _supabase
          .from('paquetes')
          .update({
            'estado': 'entregado',
            'entregado_en': DateTime.now().toUtc().toIso8601String(),
            'guardia_entrega_id': _miId,
            if (turnoId != null) 'turno_entrega_id': turnoId,
            'firma_url': rutaFirma,
            if (rutaFoto != null) 'foto_entrega_url': rutaFoto,
            'identidad_validada': identidadValidada,
            if (retiradoPor != null && retiradoPor.trim().isNotEmpty)
              'retirado_por': retiradoPor.trim(),
          })
          .eq('id', paqueteId)
          .timeout(Entorno.esperaMaxima);
    } catch (falla) {
      await _fotos.borrar(rutaFirma, CajonDeFotos.firmas);
      await _fotos.borrar(rutaFoto, CajonDeFotos.paquetes);
      throw Traductor.traducir(falla);
    }
  }

  /// Busca residentes por nombre, cédula o número de unidad, para asignarles
  /// un paquete.
  ///
  /// Casi siempre el repartidor le dice al guardia la unidad, no el nombre:
  /// "es para la casa 12", "torre B departamento 401". Por eso además de
  /// buscar por nombre y cédula, también busca por número y torre de la
  /// unidad. Si en la unidad hay varios residentes (papá, mamá, hijos)
  /// aparecen todos para que el guardia elija a cuál le va el paquete.
  Future<List<Map<String, dynamic>>> buscarResidentes(String texto) async {
    final busqueda = texto.trim();
    if (busqueda.length < 2) return const [];

    // Se hace la selección con una constante porque se usa dos veces (la
    // búsqueda por nombre y la búsqueda por unidad). Así no se puede
    // desincronizar entre ambas ramas.
    const seleccion = '''
      id, nombre_completo, telefono, foto_url, unidad_id,
      unidades!usuarios_unidad_id_fkey ( numero, torre )
    ''';

    try {
      // Filtro por condominio activo — sin esto un guardia de Encomenderos
      // podía ver residentes de Milagros al buscar destinatario del paquete.
      final condominioId = await _condominioActivo();
      if (condominioId == null) return const [];

      // 1) Por nombre o cédula del residente.
      final porNombre = await _supabase
          .from('usuarios')
          .select(seleccion)
          .eq('condominio_id', condominioId)
          .eq('rol', 'residente')
          .eq('estado', 'activo')
          .or('nombre_completo.ilike.%$busqueda%,cedula.ilike.%$busqueda%')
          .limit(20)
          .timeout(Entorno.esperaMaxima);

      // 2) Por número o torre de la unidad. Primero se buscan las unidades
      //    que matchean, y después se traen TODOS los residentes de esas
      //    unidades: si el guardia escribe "12" y en la casa 12 hay papá,
      //    mamá y dos hijos, aparecen los cuatro.
      final unidadesMatch = await _supabase
          .from('unidades')
          .select('id')
          .eq('condominio_id', condominioId)
          .or('numero.ilike.%$busqueda%,torre.ilike.%$busqueda%')
          .limit(20)
          .timeout(Entorno.esperaMaxima);

      final idsUnidades = (unidadesMatch as List)
          .map((u) => u['id'] as String)
          .toList();

      List porUnidad = const [];
      if (idsUnidades.isNotEmpty) {
        porUnidad = await _supabase
            .from('usuarios')
            .select(seleccion)
            .eq('condominio_id', condominioId)
            .eq('rol', 'residente')
            .eq('estado', 'activo')
            .inFilter('unidad_id', idsUnidades)
            .limit(30)
            .timeout(Entorno.esperaMaxima);
      }

      // Unir los dos resultados y deduplicar por id: un residente puede
      // matchear tanto por nombre como por número de unidad.
      final vistos = <String>{};
      final resultado = <Map<String, dynamic>>[];
      for (final f in [...(porNombre as List), ...porUnidad]) {
        final id = f['id'] as String;
        if (vistos.add(id)) resultado.add(Map<String, dynamic>.from(f));
      }
      return resultado;
    } catch (falla) {
      throw Traductor.traducir(falla);
    }
  }

  // ==========================================================================
  // INCIDENTES
  // ==========================================================================

  Future<List<Incidente>> incidentes({bool soloAbiertos = false}) async {
    try {
      // Filtro explícito por condominio_id — misma clase de bug que se
      // reportó el 27/09/2026 en paquetes: un guardia veía novedades de
      // otro condominio.
      final condominioId = await _condominioActivo();
      if (condominioId == null) return const [];

      var consulta = _supabase.from('incidentes').select('''
            id, tipo, gravedad, titulo, descripcion, fotos, patente,
            ocurrido_en, estado, nota_resolucion, sincronizado_offline,
            unidades ( numero, torre ),
            reportante:usuarios!incidentes_reportado_por_fkey ( nombre_completo )
          ''').eq('condominio_id', condominioId);

      if (soloAbiertos) consulta = consulta.neq('estado', 'cerrado');

      final filas = await consulta
          .order('ocurrido_en', ascending: false)
          .limit(60)
          .timeout(Entorno.esperaMaxima);

      return filas
          .map((f) => Incidente.desdeMapa(Map<String, dynamic>.from(f)))
          .toList();
    } catch (falla) {
      throw Traductor.traducir(falla);
    }
  }

  /// Anota una novedad. Es lo más simple del sistema y lo que más se usa.
  Future<void> reportarIncidente({
    required String condominioId,
    required String idLocal,
    required TipoIncidente tipo,
    required GravedadIncidente gravedad,
    required String titulo,
    String? descripcion,
    List<File> fotos = const [],
    String? unidadId,
    String? patente,
    String? turnoId,
    String? puntoAccesoId,
  }) async {
    final rutas = <String>[];
    try {
      for (final foto in fotos) {
        rutas.add(await _fotos.subir(
          archivo: foto,
          cajon: CajonDeFotos.paquetes,
          condominioId: condominioId,
          nombreDescriptivo: 'incidente',
        ));
      }

      await _supabase.from('incidentes').insert({
        'condominio_id': condominioId,
        'id_local': idLocal,
        'tipo': tipo.comoTexto,
        'gravedad': gravedad.name,
        'titulo': titulo.trim(),
        if (descripcion != null && descripcion.trim().isNotEmpty)
          'descripcion': descripcion.trim(),
        'fotos': rutas,
        if (unidadId != null) 'unidad_id': unidadId,
        if (patente != null && patente.trim().isNotEmpty)
          'patente': FormatoPatente.normalizar(patente),
        if (puntoAccesoId != null) 'punto_acceso_id': puntoAccesoId,
        'reportado_por': _miId,
        if (turnoId != null) 'turno_id': turnoId,
        'estado': 'abierto',
      }).timeout(Entorno.esperaMaxima);
    } catch (falla) {
      for (final ruta in rutas) {
        await _fotos.borrar(ruta, CajonDeFotos.paquetes);
      }
      throw Traductor.traducir(falla);
    }
  }

  // ==========================================================================
  // VALIDAR CREDENCIALES (visitantes y personal de servicio)
  // ==========================================================================

  /// El guardia escanea un código. El servidor descubre solo si es una visita,
  /// una credencial de personal de servicio o un residente.
  Future<Map<String, dynamic>> validarCredencial({
    required String codigo,
    String? codigoDelMuro,
    String? idLocal,
  }) async {
    try {
      final respuesta = await _supabase.functions
          .invoke(
            Entorno.funcionValidarCredencial,
            body: {
              'codigo': codigo,
              if (codigoDelMuro != null) 'codigo_estatico': codigoDelMuro,
              if (idLocal != null) 'id_local': idLocal,
            },
          )
          .timeout(Entorno.esperaMaxima);

      final datos = respuesta.data;
      if (datos is! Map) {
        throw const ErrorAmigable('El servidor devolvió algo que no entendemos.');
      }
      return Map<String, dynamic>.from(datos);
    } on FunctionException catch (falla) {
      // Un acceso denegado es una respuesta válida, no un error del programa:
      // el guardia tiene que verla en pantalla con su motivo.
      final cuerpo = falla.details;
      if (cuerpo is Map && cuerpo['mensaje'] is String) {
        return Map<String, dynamic>.from(cuerpo);
      }
      throw Traductor.traducir(falla);
    } catch (falla) {
      throw Traductor.traducir(falla);
    }
  }
}

