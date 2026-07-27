// ============================================================================
// Tomass Seguridad — Visitas
// ============================================================================
// Cubre los dos casos:
//
//   preregistrada → el residente la crea antes y le manda el código por WhatsApp.
//   espontanea    → llegó alguien sin avisar, el guardia lo registró, y el
//                   residente tiene que aprobar o rechazar desde su celular.
// ============================================================================

enum OrigenVisita {
  preregistrada,
  espontanea;

  static OrigenVisita desdeTexto(String? texto) =>
      texto == 'espontanea' ? OrigenVisita.espontanea : OrigenVisita.preregistrada;

  String get comoTexto => name;
}

enum EstadoVisita {
  activa,
  esperandoAprobacion,
  aprobada,
  rechazada,
  usada,
  expirada,
  cancelada;

  static EstadoVisita desdeTexto(String? texto) => switch (texto) {
        'esperando_aprobacion' => EstadoVisita.esperandoAprobacion,
        'aprobada' => EstadoVisita.aprobada,
        'rechazada' => EstadoVisita.rechazada,
        'usada' => EstadoVisita.usada,
        'expirada' => EstadoVisita.expirada,
        'cancelada' => EstadoVisita.cancelada,
        _ => EstadoVisita.activa,
      };

  String get comoTexto => switch (this) {
        EstadoVisita.esperandoAprobacion => 'esperando_aprobacion',
        _ => name,
      };

  String get nombreVisible => switch (this) {
        EstadoVisita.activa => 'Código activo',
        EstadoVisita.esperandoAprobacion => 'Esperando tu respuesta',
        EstadoVisita.aprobada => 'Aprobada',
        EstadoVisita.rechazada => 'Rechazada',
        EstadoVisita.usada => 'Ya ingresó',
        EstadoVisita.expirada => 'Venció',
        EstadoVisita.cancelada => 'Cancelada',
      };

  /// ¿El código todavía le sirve al visitante para entrar?
  bool get sirveParaEntrar =>
      this == EstadoVisita.activa || this == EstadoVisita.aprobada;

  /// ¿Necesita que el residente haga algo ahora?
  bool get necesitaTuRespuesta => this == EstadoVisita.esperandoAprobacion;
}

class Visita {
  const Visita({
    required this.id,
    required this.nombreVisitante,
    required this.origen,
    required this.estado,
    required this.tokenQr,
    required this.validoDesde,
    required this.validoHasta,
    required this.creadoEn,
    this.cedulaVisitante,
    this.telefonoVisitante,
    this.patenteVehiculo,
    this.motivoVisita,
    this.notaGuardia,
    this.autorizadaPorTelefono = false,
    this.usadaEn,
    this.motivoRechazo,
  });

  final String id;
  final String nombreVisitante;
  final OrigenVisita origen;
  final EstadoVisita estado;

  /// El código que el visitante muestra en la garita.
  final String tokenQr;

  final DateTime validoDesde;
  final DateTime validoHasta;
  final DateTime creadoEn;
  final String? cedulaVisitante;
  final String? telefonoVisitante;
  final String? patenteVehiculo;
  final String? motivoVisita;

  /// Lo que anotó el guardia si la visita llegó sin aviso.
  final String? notaGuardia;

  /// El guardia marcó que llamó por teléfono al residente.
  final bool autorizadaPorTelefono;

  final DateTime? usadaEn;
  final String? motivoRechazo;

  bool get yaVencio => DateTime.now().isAfter(validoHasta);

  /// ¿Se puede mostrar el código QR para compartir?
  bool get sePuedeCompartir => estado.sirveParaEntrar && !yaVencio;

  /// El texto que se manda por WhatsApp junto con el código.
  String mensajeParaCompartir(String nombreCondominio, String? unidad) {
    final desde = validoDesde;
    final hasta = validoHasta;
    final mismoDia = desde.day == hasta.day && desde.month == hasta.month;

    final cuando = mismoDia
        ? 'el ${_fecha(desde)} entre las ${_hora(desde)} y las ${_hora(hasta)}'
        : 'desde el ${_fecha(desde)} ${_hora(desde)} hasta el '
            '${_fecha(hasta)} ${_hora(hasta)}';

    return 'Hola $nombreVisitante, te dejo tu código de acceso a '
        '$nombreCondominio${unidad != null ? ' (unidad $unidad)' : ''}.\n\n'
        'Mostrale este código al guardia en la entrada. Sirve $cuando, '
        'y solo una vez.\n\n'
        'Código: $tokenQr';
  }

  static String _fecha(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';

  static String _hora(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  factory Visita.desdeMapa(Map<String, dynamic> m) => Visita(
        id: m['id'] as String,
        nombreVisitante: (m['nombre_visitante'] ?? '') as String,
        origen: OrigenVisita.desdeTexto(m['origen'] as String?),
        estado: EstadoVisita.desdeTexto(m['estado'] as String?),
        tokenQr: (m['token_qr'] ?? '') as String,
        validoDesde: DateTime.parse(m['valido_desde'] as String),
        validoHasta: DateTime.parse(m['valido_hasta'] as String),
        creadoEn: DateTime.parse(m['creado_en'] as String),
        cedulaVisitante: m['cedula_visitante'] as String?,
        telefonoVisitante: m['telefono_visitante'] as String?,
        patenteVehiculo: m['patente_vehiculo'] as String?,
        motivoVisita: m['motivo_visita'] as String?,
        notaGuardia: m['nota_guardia'] as String?,
        autorizadaPorTelefono: m['autorizada_por_telefono'] == true,
        usadaEn: m['usada_en'] == null
            ? null
            : DateTime.parse(m['usada_en'] as String),
        motivoRechazo: m['motivo_rechazo'] as String?,
      );
}
