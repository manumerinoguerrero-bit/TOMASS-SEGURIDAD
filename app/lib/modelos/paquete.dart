// ============================================================================
// Tomass Seguridad — Paquetes
// ============================================================================

enum EstadoPaquete {
  enPorteria,
  entregado,
  devuelto;

  static EstadoPaquete desdeTexto(String? texto) => switch (texto) {
        'entregado' => EstadoPaquete.entregado,
        'devuelto' => EstadoPaquete.devuelto,
        _ => EstadoPaquete.enPorteria,
      };

  String get nombreVisible => switch (this) {
        EstadoPaquete.enPorteria => 'En portería',
        EstadoPaquete.entregado => 'Entregado',
        EstadoPaquete.devuelto => 'Devuelto',
      };
}

class Paquete {
  const Paquete({
    required this.id,
    required this.estado,
    required this.recibidoEn,
    required this.fotoRuta,
    this.numeroSeguimiento,
    this.empresaCourier,
    this.descripcion,
    this.entregadoEn,
    this.recibidoPor,
    this.entregadoPor,
    this.retiradoPor,
    this.diasAlerta = 7,
  });

  final String id;
  final EstadoPaquete estado;
  final DateTime recibidoEn;

  /// La ruta dentro del cajón de fotos, NO un enlace directo.
  /// El enlace temporal lo arma la app cuando va a mostrar la imagen.
  final String fotoRuta;

  final String? numeroSeguimiento;
  final String? empresaCourier;
  final String? descripcion;
  final DateTime? entregadoEn;

  /// Nombre del guardia que lo recibió.
  final String? recibidoPor;

  /// Nombre del guardia que lo entregó.
  final String? entregadoPor;

  /// Si lo retiró otra persona (un familiar, el conserje).
  final String? retiradoPor;

  /// A partir de cuántos días se considera atrasado. Lo define el condominio.
  final int diasAlerta;

  /// Cuántos días lleva esperando en portería. Si ya se entregó, cuántos días
  /// estuvo guardado.
  int get diasEsperando {
    final hasta = entregadoEn ?? DateTime.now();
    return hasta.difference(recibidoEn).inDays;
  }

  /// true = se pinta en rojo. La portería tiene espacio limitado.
  bool get estaAtrasado =>
      estado == EstadoPaquete.enPorteria && diasEsperando >= diasAlerta;

  /// Qué mostrar como nombre del paquete cuando no hay descripción.
  String get titulo {
    if (descripcion != null && descripcion!.isNotEmpty) return descripcion!;
    if (empresaCourier != null && empresaCourier!.isNotEmpty) {
      return 'Paquete de $empresaCourier';
    }
    return 'Paquete';
  }

  factory Paquete.desdeMapa(Map<String, dynamic> m) {
    // El límite de días viene del condominio, si la consulta lo trajo
    int alerta = 7;
    final condo = m['condominios'];
    if (condo is Map && condo['dias_alerta_paquete'] != null) {
      alerta = (condo['dias_alerta_paquete'] as num).toInt();
    }

    String? nombreDe(dynamic anidado) {
      if (anidado is Map) return anidado['nombre_completo']?.toString();
      return null;
    }

    return Paquete(
      id: m['id'] as String,
      estado: EstadoPaquete.desdeTexto(m['estado'] as String?),
      recibidoEn: DateTime.parse(m['recibido_en'] as String),
      fotoRuta: (m['foto_url'] ?? '') as String,
      numeroSeguimiento: m['numero_seguimiento'] as String?,
      empresaCourier: m['empresa_courier'] as String?,
      descripcion: m['descripcion'] as String?,
      entregadoEn: m['entregado_en'] == null
          ? null
          : DateTime.parse(m['entregado_en'] as String),
      recibidoPor: nombreDe(m['guardia_receptor']),
      entregadoPor: nombreDe(m['guardia_entrega']),
      retiradoPor: m['retirado_por'] as String?,
      diasAlerta: alerta,
    );
  }
}
