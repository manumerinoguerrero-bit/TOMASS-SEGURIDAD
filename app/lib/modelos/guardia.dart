// ============================================================================
// Tomass Seguridad — Modelos de la app del guardia
// ============================================================================

import 'formato_patente.dart';

// ============================================================================
// PUNTO DE ACCESO
// ============================================================================

class PuntoAcceso {
  const PuntoAcceso({
    required this.id,
    required this.nombre,
    required this.tipo,
    required this.modo,
    required this.activo,
    this.ubicacion,
  });

  final String id;
  final String nombre;

  /// 'peatonal', 'vehicular' o 'mixto'.
  ///
  /// "mixto" es una garita que controla las dos cosas desde el mismo lugar, que
  /// es como funcionan las de los colegios.
  final String tipo;

  /// Cómo se controla esta entrada:
  ///
  ///   'qr'     la persona escanea el cartel del muro con su app.
  ///   'manual' el guardia anota el ingreso a mano. Se usa donde hay barrera y
  ///            portón que abre el guardia, como en los colegios.
  ///
  /// De esto depende qué pantalla ve el guardia: el lector de códigos o el
  /// formulario de ingreso.
  final String modo;

  final bool activo;
  final String? ubicacion;

  bool get esVehicular => tipo == 'vehicular';
  bool get esMixto => tipo == 'mixto';
  bool get aceptaVehiculos => tipo == 'vehicular' || tipo == 'mixto';
  bool get aceptaPeatones => tipo == 'peatonal' || tipo == 'mixto';

  /// true si acá el guardia anota a mano en vez de leer códigos.
  bool get seAnotaAMano => modo == 'manual';

  factory PuntoAcceso.desdeMapa(Map<String, dynamic> m) => PuntoAcceso(
        id: m['id'] as String,
        nombre: (m['nombre'] ?? '') as String,
        tipo: (m['tipo'] ?? 'peatonal') as String,
        modo: (m['modo'] ?? 'qr') as String,
        activo: m['activo'] == true,
        ubicacion: m['ubicacion'] as String?,
      );
}

// ============================================================================
// TURNO
// ============================================================================
// Es lo que hace que los avisos de autos le lleguen al guardia de la caseta
// vehicular y no al de la garita peatonal.
// ============================================================================

class Turno {
  const Turno({
    required this.id,
    required this.puntoAccesoNombre,
    required this.inicio,
    this.puntoAccesoId,
    this.esVehicular = false,
    this.codigoDelMuro,
    this.finProgramado,
    this.cerradoEn,
    this.notasEntrega,
  });

  final String id;

  /// El puesto donde está parado el guardia.
  ///
  /// Si está VACÍO, el guardia **cubre todo el condominio** y le llegan los
  /// avisos de todas las entradas. Ese es el caso normal cuando hay un solo
  /// guardia, que es lo que pasa en la mayoría de los condominios: tiene que
  /// atender la entrada peatonal y la vehicular al mismo tiempo.
  final String? puntoAccesoId;

  final String puntoAccesoNombre;
  final bool esVehicular;
  final DateTime inicio;

  /// true = el guardia atiende todas las entradas del condominio.
  bool get cubreTodo => puntoAccesoId == null;

  /// El código que va impreso en el cartel del muro de este puesto.
  ///
  /// El guardia lo necesita para validar el código de un residente sin tener
  /// que ir a escanear el cartel: la app ya sabe en qué puerta está parado,
  /// porque el guardia lo eligió al abrir el turno.
  final String? codigoDelMuro;

  final DateTime? finProgramado;
  final DateTime? cerradoEn;
  final String? notasEntrega;

  bool get estaAbierto => cerradoEn == null;

  Duration get tiempoTrabajado =>
      (cerradoEn ?? DateTime.now()).difference(inicio);

  factory Turno.desdeMapa(Map<String, dynamic> m) {
    final punto = m['puntos_acceso'];
    final puntoId = m['punto_acceso_id'] as String?;

    return Turno(
      id: m['id'] as String,
      puntoAccesoId: puntoId,
      puntoAccesoNombre: puntoId == null
          ? 'Todo el condominio'
          : (punto is Map ? (punto['nombre'] ?? 'Puesto') as String : 'Puesto'),
      esVehicular: punto is Map && punto['tipo'] == 'vehicular',
      codigoDelMuro:
          punto is Map ? punto['codigo_qr_estatico'] as String? : null,
      inicio: DateTime.parse(m['inicio'] as String),
      finProgramado: m['fin_programado'] == null
          ? null
          : DateTime.parse(m['fin_programado'] as String),
      cerradoEn: m['cerrado_en'] == null
          ? null
          : DateTime.parse(m['cerrado_en'] as String),
      notasEntrega: m['notas_entrega'] as String?,
    );
  }
}

// ============================================================================
// AUTO ESPERANDO LA BARRERA
// ============================================================================
// Todo lo que el guardia necesita ver en la tarjeta grande para decidir si abre.
// Viene de la vista v_solicitudes_vehiculares_pendientes, que ya cruza todas las
// tablas por nosotros.
// ============================================================================

class AutoEsperando {
  const AutoEsperando({
    required this.solicitudId,
    required this.residenteId,
    required this.residente,
    required this.patente,
    required this.marca,
    required this.modelo,
    required this.color,
    required this.esEntrada,
    required this.solicitadoEn,
    required this.puntoAcceso,
    this.residenteFotoRuta,
    this.residenteTelefono,
    this.vehiculoFotoRuta,
    this.unidad,
    this.torre,
  });

  final String solicitudId;
  final String residenteId;
  final String residente;
  final String patente;
  final String marca;
  final String modelo;
  final String color;
  final bool esEntrada;
  final DateTime solicitadoEn;
  final String puntoAcceso;
  final String? residenteFotoRuta;
  final String? residenteTelefono;
  final String? vehiculoFotoRuta;
  final String? unidad;
  final String? torre;

  /// "101 A" o null.
  String? get unidadCompleta {
    if (unidad == null) return null;
    return [unidad, torre].where((p) => p != null && p.isNotEmpty).join(' ');
  }

  String get descripcionVehiculo => '$marca $modelo $color';

  /// Cuántos segundos lleva el auto esperando. Se recalcula solo.
  int get segundosEsperando =>
      DateTime.now().difference(solicitadoEn).inSeconds;

  /// A partir de 45 segundos la tarjeta se pone más urgente: hay un auto
  /// detenido frenando la entrada.
  bool get llevaMuchoEsperando => segundosEsperando >= 45;

  factory AutoEsperando.desdeMapa(Map<String, dynamic> m) => AutoEsperando(
        solicitudId: m['solicitud_id'] as String,
        residenteId: m['residente_id'] as String,
        residente: (m['residente'] ?? '') as String,
        patente: FormatoPatente.normalizar((m['patente'] ?? '') as String),
        marca: (m['marca'] ?? '') as String,
        modelo: (m['modelo'] ?? '') as String,
        color: (m['color'] ?? '') as String,
        esEntrada: m['sentido'] != 'salida',
        solicitadoEn: DateTime.parse(m['solicitado_en'] as String),
        puntoAcceso: (m['punto_acceso'] ?? '') as String,
        residenteFotoRuta: m['residente_foto_url'] as String?,
        residenteTelefono: m['residente_telefono'] as String?,
        vehiculoFotoRuta: m['vehiculo_foto_url'] as String?,
        unidad: m['unidad'] as String?,
        torre: m['torre'] as String?,
      );
}

// ============================================================================
// RESUMEN DEL PANEL
// ============================================================================

class ResumenCondominio {
  const ResumenCondominio({
    required this.accesosHoy,
    required this.autosEsperando,
    required this.paquetesEnPorteria,
    required this.paquetesAtrasados,
    required this.vehiculosPorAprobar,
    required this.residentesActivos,
    required this.unidades,
    required this.guardiasEnTurno,
    required this.incidentesAbiertos,
    required this.visitasEsperandoAprobacion,
    required this.personasDentro,
  });

  final int accesosHoy;
  final int autosEsperando;
  final int paquetesEnPorteria;
  final int paquetesAtrasados;
  final int vehiculosPorAprobar;
  final int residentesActivos;
  final int unidades;
  final int guardiasEnTurno;
  final int incidentesAbiertos;
  final int visitasEsperandoAprobacion;
  final int personasDentro;

  static int _n(dynamic v) => (v as num?)?.toInt() ?? 0;

  factory ResumenCondominio.desdeMapa(Map<String, dynamic> m) =>
      ResumenCondominio(
        accesosHoy: _n(m['accesos_hoy']),
        autosEsperando: _n(m['autos_esperando']),
        paquetesEnPorteria: _n(m['paquetes_en_porteria']),
        paquetesAtrasados: _n(m['paquetes_atrasados']),
        vehiculosPorAprobar: _n(m['vehiculos_por_aprobar']),
        residentesActivos: _n(m['residentes_activos']),
        unidades: _n(m['unidades']),
        guardiasEnTurno: _n(m['guardias_en_turno']),
        incidentesAbiertos: _n(m['incidentes_abiertos']),
        visitasEsperandoAprobacion: _n(m['visitas_esperando_aprobacion']),
        personasDentro: _n(m['personas_dentro']),
      );

  static const vacio = ResumenCondominio(
    accesosHoy: 0,
    autosEsperando: 0,
    paquetesEnPorteria: 0,
    paquetesAtrasados: 0,
    vehiculosPorAprobar: 0,
    residentesActivos: 0,
    unidades: 0,
    guardiasEnTurno: 0,
    incidentesAbiertos: 0,
    visitasEsperandoAprobacion: 0,
    personasDentro: 0,
  );
}

// ============================================================================
// INCIDENTE
// ============================================================================
// El cuaderno de novedades del guardia, digital y con fotos.
// ============================================================================

enum TipoIncidente {
  estacionamiento,
  ruido,
  danoPropiedad,
  personaSospechosa,
  mascota,
  basura,
  emergenciaMedica,
  fallaTecnica,
  otro;

  static TipoIncidente desdeTexto(String? t) => switch (t) {
        'estacionamiento' => TipoIncidente.estacionamiento,
        'ruido' => TipoIncidente.ruido,
        'dano_propiedad' => TipoIncidente.danoPropiedad,
        'persona_sospechosa' => TipoIncidente.personaSospechosa,
        'mascota' => TipoIncidente.mascota,
        'basura' => TipoIncidente.basura,
        'emergencia_medica' => TipoIncidente.emergenciaMedica,
        'falla_tecnica' => TipoIncidente.fallaTecnica,
        _ => TipoIncidente.otro,
      };

  String get comoTexto => switch (this) {
        TipoIncidente.danoPropiedad => 'dano_propiedad',
        TipoIncidente.personaSospechosa => 'persona_sospechosa',
        TipoIncidente.emergenciaMedica => 'emergencia_medica',
        TipoIncidente.fallaTecnica => 'falla_tecnica',
        _ => name,
      };

  String get nombreVisible => switch (this) {
        TipoIncidente.estacionamiento => 'Estacionamiento',
        TipoIncidente.ruido => 'Ruidos molestos',
        TipoIncidente.danoPropiedad => 'Daño a la propiedad',
        TipoIncidente.personaSospechosa => 'Persona sospechosa',
        TipoIncidente.mascota => 'Mascota suelta',
        TipoIncidente.basura => 'Basura',
        TipoIncidente.emergenciaMedica => 'Emergencia médica',
        TipoIncidente.fallaTecnica => 'Falla técnica',
        TipoIncidente.otro => 'Otro',
      };
}

enum GravedadIncidente {
  baja,
  media,
  alta,
  critica;

  static GravedadIncidente desdeTexto(String? t) => switch (t) {
        'media' => GravedadIncidente.media,
        'alta' => GravedadIncidente.alta,
        'critica' => GravedadIncidente.critica,
        _ => GravedadIncidente.baja,
      };

  String get nombreVisible => switch (this) {
        GravedadIncidente.baja => 'Baja',
        GravedadIncidente.media => 'Media',
        GravedadIncidente.alta => 'Alta',
        GravedadIncidente.critica => 'Crítica',
      };
}

class Incidente {
  const Incidente({
    required this.id,
    required this.tipo,
    required this.gravedad,
    required this.titulo,
    required this.ocurridoEn,
    required this.estado,
    this.descripcion,
    this.fotos = const [],
    this.unidad,
    this.patente,
    this.reportadoPor,
    this.notaResolucion,
    this.sincronizadoOffline = false,
  });

  final String id;
  final TipoIncidente tipo;
  final GravedadIncidente gravedad;
  final String titulo;
  final DateTime ocurridoEn;
  final String estado;
  final String? descripcion;
  final List<String> fotos;
  final String? unidad;
  final String? patente;
  final String? reportadoPor;
  final String? notaResolucion;
  final bool sincronizadoOffline;

  bool get estaCerrado => estado == 'cerrado';

  factory Incidente.desdeMapa(Map<String, dynamic> m) {
    final fotosCrudas = m['fotos'];
    final fotos = <String>[];
    if (fotosCrudas is List) {
      for (final f in fotosCrudas) {
        if (f is String && f.isNotEmpty) fotos.add(f);
      }
    }

    String? nombreUnidad;
    final u = m['unidades'];
    if (u is Map) {
      nombreUnidad = [u['numero'], u['torre']]
          .where((p) => p != null && p.toString().isNotEmpty)
          .join(' ');
      if (nombreUnidad.isEmpty) nombreUnidad = null;
    }

    String? quien;
    final r = m['reportante'];
    if (r is Map) quien = r['nombre_completo']?.toString();

    return Incidente(
      id: m['id'] as String,
      tipo: TipoIncidente.desdeTexto(m['tipo'] as String?),
      gravedad: GravedadIncidente.desdeTexto(m['gravedad'] as String?),
      titulo: (m['titulo'] ?? '') as String,
      ocurridoEn: DateTime.parse(m['ocurrido_en'] as String),
      estado: (m['estado'] ?? 'abierto') as String,
      descripcion: m['descripcion'] as String?,
      fotos: fotos,
      unidad: nombreUnidad,
      patente: m['patente'] as String?,
      reportadoPor: quien,
      notaResolucion: m['nota_resolucion'] as String?,
      sincronizadoOffline: m['sincronizado_offline'] == true,
    );
  }
}

// ============================================================================
// RONDAS CON PUNTOS DE CONTROL
// ============================================================================
// POR QUÉ EL CÓDIGO ESTÁ PEGADO EN LA PARED Y NO EN EL TELÉFONO
//
//   Porque la única forma de demostrar que alguien ESTUVO en un lugar es que
//   haya tenido que ir hasta ahí. Un botón en la app que diga "ya hice la ronda"
//   se aprieta desde la garita sin moverse. Un cartel pegado en el fondo del
//   condominio, no.
// ============================================================================

/// Un cartel pegado en un sector.
class PuntoControl {
  const PuntoControl({
    required this.id,
    required this.nombre,
    required this.orden,
    this.descripcion,
    this.marcadoEn,
  });

  final String id;
  final String nombre;
  final int orden;
  final String? descripcion;

  /// Cuándo se marcó en la ronda que está abierta, o null si todavía no.
  final DateTime? marcadoEn;

  bool get yaMarcado => marcadoEn != null;

  PuntoControl conMarca(DateTime? cuando) => PuntoControl(
        id: id,
        nombre: nombre,
        orden: orden,
        descripcion: descripcion,
        marcadoEn: cuando,
      );

  factory PuntoControl.desdeMapa(Map<String, dynamic> m) => PuntoControl(
        id: m['id'] as String,
        nombre: (m['nombre'] ?? '') as String,
        orden: (m['orden'] ?? 0) as int,
        descripcion: m['descripcion'] as String?,
      );
}

/// La ronda que el guardia tiene en curso.
class RondaAbierta {
  const RondaAbierta({
    required this.id,
    required this.inicio,
    required this.marcados,
    required this.total,
  });

  final String id;
  final DateTime inicio;
  final int marcados;
  final int total;

  bool get estaCompleta => total > 0 && marcados >= total;

  /// De 0 a 1, para la barra de avance.
  double get avance => total == 0 ? 0 : (marcados / total).clamp(0, 1).toDouble();

  Duration get llevaAndando => DateTime.now().difference(inicio);

  factory RondaAbierta.desdeMapa(Map<String, dynamic> m) => RondaAbierta(
        id: m['ronda_id'] as String,
        inicio: DateTime.parse(m['inicio'] as String),
        marcados: (m['marcados'] ?? 0) as int,
        total: (m['total'] ?? 0) as int,
      );
}

/// Lo que contesta el servidor cuando el guardia escanea un cartel.
class ResultadoDeMarca {
  const ResultadoDeMarca({
    required this.punto,
    required this.marcados,
    required this.total,
    required this.yaEstaba,
    this.metrosDeLejos,
    this.lejos = false,
  });

  /// El nombre del sector, para poder decirle "Patio central, listo".
  final String punto;
  final int marcados;
  final int total;

  /// true si ya había marcado ese mismo punto en esta ronda. No es un error:
  /// se le avisa y no se cuenta dos veces.
  final bool yaEstaba;

  /// A cuántos metros del cartel estaba el teléfono al escanear.
  /// null si el cartel no tiene ubicación guardada, o si el GPS no contestó.
  final double? metrosDeLejos;

  /// true si esa distancia se pasó de lo permitido para ese punto.
  ///
  /// NO se le muestra al guardia como una acusación: el GPS falla bajo techo y
  /// acusar a alguien que hizo bien su trabajo es la forma más rápida de que
  /// deje de usar el sistema. Queda anotado y lo mira el administrador.
  final bool lejos;

  factory ResultadoDeMarca.desdeMapa(Map<String, dynamic> m) => ResultadoDeMarca(
        punto: (m['punto'] ?? '') as String,
        marcados: (m['marcados'] ?? 0) as int,
        total: (m['total'] ?? 0) as int,
        yaEstaba: (m['ya_estaba'] ?? false) as bool,
        metrosDeLejos: (m['metros_de_lejos'] as num?)?.toDouble(),
        lejos: (m['lejos'] ?? false) as bool,
      );
}

// ============================================================================
// UNA VISITA ESPERANDO QUE EL RESIDENTE CONTESTE
// ============================================================================
// El guardia deja esta pantalla abierta con la persona parada adelante. Lo que
// importa acá es una sola cosa: ¿ya contestó o todavía no?
// ============================================================================

class VisitaEsperando {
  const VisitaEsperando({
    required this.id,
    required this.nombreVisitante,
    required this.residente,
    required this.espacio,
    required this.estado,
    required this.llamoPorTelefono,
    required this.creadoEn,
    required this.minutosEsperando,
    this.patente,
    this.motivo,
    this.motivoRechazo,
  });

  final String id;
  final String nombreVisitante;
  final String residente;
  final String espacio;

  /// 'esperando_aprobacion', 'aprobada' o 'rechazada'
  final String estado;

  /// true si el guardia además llamó por teléfono.
  ///
  /// NO vale lo mismo que una aprobación desde la app: una la confirmó el
  /// residente con su propio teléfono, la otra la afirma el guardia. Las dos
  /// sirven, pero el informe las tiene que mostrar distinto.
  final bool llamoPorTelefono;

  final DateTime creadoEn;
  final int minutosEsperando;
  final String? patente;
  final String? motivo;
  final String? motivoRechazo;

  bool get estaEsperando => estado == 'esperando_aprobacion';
  bool get fueAprobada => estado == 'aprobada';
  bool get fueRechazada => estado == 'rechazada';

  /// A los 3 minutos con la persona parada en el portón, conviene que el
  /// guardia levante el teléfono en vez de seguir esperando.
  bool get convieneLlamar => estaEsperando && minutosEsperando >= 3;

  factory VisitaEsperando.desdeMapa(Map<String, dynamic> m) => VisitaEsperando(
        id: m['visita_id'] as String,
        nombreVisitante: (m['nombre_visitante'] ?? '') as String,
        residente: (m['residente'] ?? '') as String,
        espacio: (m['espacio'] ?? '—') as String,
        estado: (m['estado'] ?? 'esperando_aprobacion') as String,
        llamoPorTelefono: (m['llamo_por_telefono'] ?? false) as bool,
        creadoEn: DateTime.parse(m['creado_en'] as String),
        minutosEsperando: (m['minutos_esperando'] ?? 0) as int,
        patente: m['patente'] as String?,
        motivo: m['motivo'] as String?,
        motivoRechazo: m['motivo_rechazo'] as String?,
      );
}
