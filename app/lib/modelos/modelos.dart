// ============================================================================
// Tomass Seguridad — Modelos de datos
// ============================================================================
// QUÉ ES UN MODELO
//
//   El servidor manda la información como texto crudo. Un "modelo" es una
//   plantilla que convierte ese texto en algo ordenado que la app entiende, con
//   nombres claros y tipos correctos.
//
//   Ventaja concreta: si el servidor cambia un nombre de campo, la app falla en
//   UN solo lugar (acá) en vez de en veinte pantallas distintas.
// ============================================================================

import 'formato_patente.dart';

// Los demás modelos viven en sus propios archivos, pero se re-exportan desde acá
// para que las pantallas solo tengan que importar "modelos.dart" y ya tengan todo.
export 'formato_patente.dart';
export 'movimiento.dart';
export 'paquete.dart';
export 'visita.dart';

// ============================================================================
// LA PERSONA QUE USA LA APP
// ============================================================================

enum RolUsuario {
  administrador,
  guardia,
  residente;

  static RolUsuario desdeTexto(String? texto) => switch (texto) {
        'administrador' => RolUsuario.administrador,
        'guardia' => RolUsuario.guardia,
        _ => RolUsuario.residente,
      };

  String get nombreVisible => switch (this) {
        RolUsuario.administrador => 'Administrador',
        RolUsuario.guardia => 'Guardia',
        RolUsuario.residente => 'Residente',
      };
}

class Perfil {
  const Perfil({
    required this.id,
    required this.condominioId,
    required this.nombreCompleto,
    required this.email,
    required this.rol,
    required this.estado,
    this.cedula,
    this.telefono,
    this.fotoUrl,
    this.unidadId,
    this.unidad,
    this.relacionUnidad,
    this.nombreCondominio,
  });

  final String id;
  final String condominioId;
  final String nombreCompleto;
  final String email;
  final RolUsuario rol;
  final String estado;
  final String? cedula;
  final String? telefono;
  final String? fotoUrl;
  final String? unidadId;

  /// Ya armada para mostrar: "101 A".
  final String? unidad;
  final String? relacionUnidad;
  final String? nombreCondominio;

  bool get estaActivo => estado == 'activo';

  /// Las iniciales, para mostrar cuando no hay foto.
  String get iniciales {
    final partes = nombreCompleto.trim().split(RegExp(r'\s+'));
    if (partes.isEmpty) return '?';
    if (partes.length == 1) return partes.first.characters2;
    return '${partes[0][0]}${partes[1][0]}'.toUpperCase();
  }

  factory Perfil.desdeMapa(Map<String, dynamic> m) {
    // La unidad puede venir anidada, según cómo se pidió la consulta
    final unidadCruda = m['unidades'];
    String? unidadArmada;
    if (unidadCruda is Map) {
      final numero = unidadCruda['numero']?.toString();
      final torre = unidadCruda['torre']?.toString();
      unidadArmada = [numero, torre]
          .where((p) => p != null && p.isNotEmpty)
          .join(' ');
      if (unidadArmada.isEmpty) unidadArmada = null;
    } else if (m['unidad'] is String) {
      unidadArmada = m['unidad'] as String;
    }

    final condominioCrudo = m['condominios'];
    String? nombreCondo;
    if (condominioCrudo is Map) {
      nombreCondo = condominioCrudo['nombre']?.toString();
    }

    return Perfil(
      id: m['id'] as String,
      condominioId: m['condominio_id'] as String,
      nombreCompleto: (m['nombre_completo'] ?? '') as String,
      email: (m['email'] ?? '') as String,
      rol: RolUsuario.desdeTexto(m['rol'] as String?),
      estado: (m['estado'] ?? 'activo') as String,
      cedula: m['cedula'] as String?,
      telefono: m['telefono'] as String?,
      fotoUrl: m['foto_url'] as String?,
      unidadId: m['unidad_id'] as String?,
      unidad: unidadArmada,
      relacionUnidad: m['relacion_unidad'] as String?,
      nombreCondominio: nombreCondo,
    );
  }
}

// ============================================================================
// VEHÍCULOS
// ============================================================================

enum EstadoVehiculo {
  pendiente,
  aprobado,
  rechazado;

  static EstadoVehiculo desdeTexto(String? texto) => switch (texto) {
        'aprobado' => EstadoVehiculo.aprobado,
        'rechazado' => EstadoVehiculo.rechazado,
        _ => EstadoVehiculo.pendiente,
      };

  String get nombreVisible => switch (this) {
        EstadoVehiculo.aprobado => 'Aprobado',
        EstadoVehiculo.rechazado => 'Rechazado',
        EstadoVehiculo.pendiente => 'Pendiente',
      };

  /// Solo los aprobados sirven para entrar por la barrera.
  bool get puedeEntrar => this == EstadoVehiculo.aprobado;
}

class Vehiculo {
  const Vehiculo({
    required this.id,
    required this.patente,
    required this.marca,
    required this.modelo,
    required this.color,
    required this.estado,
    required this.creadoEn,
    this.anio,
    this.fotoUrl,
    this.fotoPatenteUrl,
    this.motivoRechazo,
    this.aprobadoEn,
  });

  final String id;
  final String patente;
  final String marca;
  final String modelo;
  final String color;
  final EstadoVehiculo estado;
  final DateTime creadoEn;
  final int? anio;
  final String? fotoUrl;
  final String? fotoPatenteUrl;
  final String? motivoRechazo;
  final DateTime? aprobadoEn;

  /// "Toyota Corolla Blanco"
  String get descripcion => '$marca $modelo $color';

  factory Vehiculo.desdeMapa(Map<String, dynamic> m) => Vehiculo(
        id: m['id'] as String,
        patente: FormatoPatente.normalizar((m['patente'] ?? '') as String),
        marca: (m['marca'] ?? '') as String,
        modelo: (m['modelo'] ?? '') as String,
        color: (m['color'] ?? '') as String,
        estado: EstadoVehiculo.desdeTexto(m['estado'] as String?),
        creadoEn: DateTime.parse(m['creado_en'] as String),
        anio: m['anio'] as int?,
        fotoUrl: m['foto_url'] as String?,
        fotoPatenteUrl: m['foto_patente_url'] as String?,
        motivoRechazo: m['motivo_rechazo'] as String?,
        aprobadoEn: m['aprobado_en'] == null
            ? null
            : DateTime.parse(m['aprobado_en'] as String),
      );
}

// ============================================================================
// EL CÓDIGO QR DEL RESIDENTE
// ============================================================================
// Es lo que devuelve la función generar-qr del servidor.
// ============================================================================

enum TipoAcceso {
  peatonal,
  vehicular;

  static TipoAcceso desdeTexto(String? texto) =>
      texto == 'vehicular' ? TipoAcceso.vehicular : TipoAcceso.peatonal;

  String get comoTexto => name;

  String get nombreVisible => switch (this) {
        TipoAcceso.peatonal => 'PEATONAL',
        TipoAcceso.vehicular => 'VEHICULAR',
      };
}

class CodigoAcceso {
  const CodigoAcceso({
    required this.codigo,
    required this.tipo,
    required this.venceEn,
    required this.segundosDeVida,
    required this.residente,
    this.unidad,
    this.vehiculo,
  });

  /// El texto largo que se dibuja como código QR en la pantalla.
  final String codigo;
  final TipoAcceso tipo;
  final DateTime venceEn;
  final int segundosDeVida;
  final String residente;
  final String? unidad;
  final VehiculoDelCodigo? vehiculo;

  /// Cuántos segundos le quedan de vida. Nunca menos de cero.
  int get segundosRestantes {
    final faltan = venceEn.difference(DateTime.now()).inSeconds;
    return faltan < 0 ? 0 : faltan;
  }

  bool get yaVencio => segundosRestantes <= 0;

  /// De 0 a 1, para el relojito circular.
  double get fraccionRestante {
    if (segundosDeVida <= 0) return 0;
    final f = segundosRestantes / segundosDeVida;
    return f.clamp(0.0, 1.0);
  }

  factory CodigoAcceso.desdeMapa(Map<String, dynamic> m) => CodigoAcceso(
        codigo: m['codigo'] as String,
        tipo: TipoAcceso.desdeTexto(m['tipo'] as String?),
        venceEn: DateTime.parse(m['vence_en'] as String),
        segundosDeVida: (m['segundos_de_vida'] as num?)?.toInt() ?? 60,
        residente: (m['residente'] ?? '') as String,
        unidad: m['unidad'] as String?,
        vehiculo: m['vehiculo'] == null
            ? null
            : VehiculoDelCodigo.desdeMapa(
                Map<String, dynamic>.from(m['vehiculo'] as Map)),
      );
}

/// Los datos del auto que van dentro del código, ya listos para mostrar.
class VehiculoDelCodigo {
  const VehiculoDelCodigo({
    required this.id,
    required this.patente,
    required this.descripcion,
    this.fotoUrl,
  });

  final String id;
  final String patente;
  final String descripcion;
  final String? fotoUrl;

  factory VehiculoDelCodigo.desdeMapa(Map<String, dynamic> m) =>
      VehiculoDelCodigo(
        id: m['id'] as String,
        patente: FormatoPatente.normalizar((m['patente'] ?? '') as String),
        descripcion: (m['descripcion'] ?? '') as String,
        fotoUrl: m['foto_url'] as String?,
      );
}

// ============================================================================
// EL RESULTADO DE ESCANEAR
// ============================================================================
// Es lo que devuelve la función validar-acceso, y es lo que decide si la
// pantalla se pone verde o roja.
// ============================================================================

enum Sentido {
  entrada,
  salida;

  static Sentido desdeTexto(String? texto) =>
      texto == 'salida' ? Sentido.salida : Sentido.entrada;

  String get nombreVisible => switch (this) {
        Sentido.entrada => 'Entrada',
        Sentido.salida => 'Salida',
      };
}

class ResultadoAcceso {
  const ResultadoAcceso({
    required this.aprobado,
    required this.titulo,
    required this.mensaje,
    required this.sentido,
    this.detalle,
    this.residente,
    this.unidad,
    this.puntoAcceso,
    this.patente,
    this.descripcionVehiculo,
    this.esperaGuardia = false,
    this.repetido = false,
    this.puedeReintentar = false,
    this.hora,
  });

  final bool aprobado;
  final String titulo;
  final String mensaje;
  final Sentido sentido;
  final String? detalle;
  final String? residente;
  final String? unidad;
  final String? puntoAcceso;
  final String? patente;
  final String? descripcionVehiculo;

  /// true si el guardia todavía tiene que abrir la barrera.
  final bool esperaGuardia;

  /// true si la persona escaneó dos veces por error.
  final bool repetido;

  /// true si vale la pena ofrecer "intentar de nuevo" (código vencido, por ej.).
  final bool puedeReintentar;

  final DateTime? hora;

  bool get esVehicular => patente != null && patente!.isNotEmpty;

  factory ResultadoAcceso.desdeMapa(Map<String, dynamic> m) {
    final vehiculoCrudo = m['vehiculo'];
    String? patente;
    String? descripcion;
    if (vehiculoCrudo is Map) {
      patente = vehiculoCrudo['patente']?.toString();
      descripcion = vehiculoCrudo['descripcion']?.toString();
    }

    return ResultadoAcceso(
      aprobado: m['aprobado'] == true,
      titulo: (m['titulo'] ?? '') as String,
      mensaje: (m['mensaje'] ?? '') as String,
      sentido: Sentido.desdeTexto(m['sentido'] as String?),
      detalle: m['detalle'] as String?,
      residente: m['residente'] as String?,
      unidad: m['unidad'] as String?,
      puntoAcceso: m['punto_acceso'] as String?,
      patente: patente == null ? null : FormatoPatente.normalizar(patente),
      descripcionVehiculo: descripcion,
      esperaGuardia: m['espera_guardia'] == true,
      repetido: m['repetido'] == true,
      puedeReintentar: m['puede_reintentar'] == true,
      hora: m['hora'] == null ? null : DateTime.tryParse(m['hora'] as String),
    );
  }

  /// Cuando el error viene de una respuesta que no es 200, se arma acá para que
  /// la pantalla roja pueda mostrar los datos igual.
  factory ResultadoAcceso.denegado({
    required String titulo,
    required String mensaje,
    String? detalle,
    bool puedeReintentar = false,
  }) =>
      ResultadoAcceso(
        aprobado: false,
        titulo: titulo,
        mensaje: mensaje,
        sentido: Sentido.entrada,
        detalle: detalle,
        puedeReintentar: puedeReintentar,
      );
}

// ============================================================================
// Ayuda chica para las iniciales
// ============================================================================

extension on String {
  String get characters2 {
    if (length >= 2) return substring(0, 2).toUpperCase();
    return toUpperCase();
  }
}
