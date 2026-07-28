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
    required this.esVehicular,
    required this.activo,
    this.ubicacion,
  });

  final String id;
  final String nombre;
  final bool esVehicular;
  final bool activo;
  final String? ubicacion;

  factory PuntoAcceso.desdeMapa(Map<String, dynamic> m) => PuntoAcceso(
        id: m['id'] as String,
        nombre: (m['nombre'] ?? '') as String,
        esVehicular: m['tipo'] == 'vehicular',
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
    required this.puntoAccesoId,
    required this.puntoAccesoNombre,
    required this.esVehicular,
    required this.inicio,
    this.codigoDelMuro,
    this.finProgramado,
    this.cerradoEn,
    this.notasEntrega,
  });

  final String id;
  final String puntoAccesoId;
  final String puntoAccesoNombre;
  final bool esVehicular;
  final DateTime inicio;

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
    return Turno(
      id: m['id'] as String,
      puntoAccesoId: m['punto_acceso_id'] as String,
      puntoAccesoNombre:
          punto is Map ? (punto['nombre'] ?? '') as String : 'Puesto',
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
