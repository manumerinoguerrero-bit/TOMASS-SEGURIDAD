// ============================================================================
// Tomass Seguridad — Movimientos de acceso
// ============================================================================
// Cada entrada y cada salida registrada. Es lo que el residente ve en su
// historial, y lo que sirve como prueba si hay un reclamo.
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
    this.patente,
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

  final String? patente;

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

    return Movimiento(
      id: m['id'] as String,
      esEntrada: m['sentido'] == 'entrada',
      esVehicular: m['tipo_acceso'] == 'vehicular',
      aprobado: m['estado'] == 'aprobado',
      ocurridoEn: DateTime.parse(m['ocurrido_en'] as String),
      puntoAcceso: nombrePunto ?? m['punto_acceso'] as String?,
      patente: m['patente_snapshot'] as String?,
      motivoDenegacion: m['motivo_denegacion'] as String?,
      nombreGuardia: nombreGuardia,
      sincronizadoOffline: m['sincronizado_offline'] == true,
    );
  }
}
