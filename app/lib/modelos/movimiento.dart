// ============================================================================
// Tomass Seguridad — Movimientos de acceso
// ============================================================================
// Cada entrada y cada salida registrada. Es lo que el guardia ve en su panel
// como "Últimos accesos", y lo que sirve como prueba si hay un reclamo.
//
// Estos registros NO se pueden modificar ni borrar: la base de datos lo bloquea.
// ============================================================================

class Movimiento {
  const Movimiento({
    required this.id,
    required this.esEntrada,
    required this.esVehicular,
    required this.aprobado,
    required this.ocurridoEn,
    this.puntoAcceso,
    this.nombre,
    this.rut,
    this.unidad,
    this.patente,
    this.autorizadoPor,
    this.motivoDenegacion,
    this.nombreGuardia,
    this.sincronizadoOffline = false,
  });

  final String id;

  /// true = entró. false = salió.
  final bool esEntrada;

  /// true = pasó en auto. false = pasó caminando.
  final bool esVehicular;

  final bool aprobado;
  final DateTime ocurridoEn;

  /// Por qué puerta pasó.
  final String? puntoAcceso;

  /// Nombre de la persona que ENTRÓ o SALIÓ (viene de nombre_snapshot).
  final String? nombre;

  /// RUT chileno de la persona que entró/salió (viene de rut_snapshot).
  final String? rut;

  /// Casa/departamento al que iba o del que salía (viene de unidad_snapshot).
  final String? unidad;

  final String? patente;

  /// Quién autorizó el ingreso (residente que dio el OK). Puede ser null
  /// cuando el que entró era el propio residente o no hubo autorización
  /// explícita.
  final String? autorizadoPor;

  /// Si fue denegado, la explicación exacta.
  final String? motivoDenegacion;

  /// Qué guardia lo registró, si hubo uno.
  final String? nombreGuardia;

  /// true si se registró sin internet y se sincronizó después.
  final bool sincronizadoOffline;

  /// "Entrada vehicular", "Salida peatonal".
  String get descripcion {
    final sentido = esEntrada ? 'Entrada' : 'Salida';
    final tipo = esVehicular ? 'vehicular' : 'peatonal';
    return '$sentido $tipo';
  }

  factory Movimiento.desdeMapa(Map<String, dynamic> m) {
    String? nombrePunto;
    final punto = m['puntos_acceso'];
    if (punto is Map) nombrePunto = punto['nombre']?.toString();

    String? nombreGuardia;
    final guardia = m['guardia'];
    if (guardia is Map) nombreGuardia = guardia['nombre_completo']?.toString();

    // Autorizador: preferir el texto libre que el guardia escribió a mano,
    // y si no hay, tomar el nombre del residente registrado en la relación.
    String? autorizador = (m['autorizado_por_texto'] as String?)?.trim();
    if (autorizador == null || autorizador.isEmpty) {
      final u = m['usuarios'];
      if (u is Map) autorizador = u['nombre_completo']?.toString();
    }
    if (autorizador != null && autorizador.isEmpty) autorizador = null;

    return Movimiento(
      id: m['id'] as String,
      esEntrada: m['sentido'] == 'entrada',
      esVehicular: m['tipo_acceso'] == 'vehicular',
      aprobado: m['estado'] == 'aprobado',
      ocurridoEn: DateTime.parse(m['ocurrido_en'] as String),
      puntoAcceso: nombrePunto ?? m['punto_acceso'] as String?,
      nombre: (m['nombre_snapshot'] as String?)?.trim(),
      rut: (m['rut_snapshot'] as String?)?.trim(),
      unidad: (m['unidad_snapshot'] as String?)?.trim(),
      patente: m['patente_snapshot'] as String?,
      autorizadoPor: autorizador,
      motivoDenegacion: m['motivo_denegacion'] as String?,
      nombreGuardia: nombreGuardia,
      sincronizadoOffline: m['sincronizado_offline'] == true,
    );
  }
}
