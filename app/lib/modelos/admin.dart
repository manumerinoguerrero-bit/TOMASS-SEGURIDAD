// ============================================================================
// Tomass Seguridad — Los datos que ve el administrador
// ============================================================================
// Van aparte de modelos.dart a propósito: son cosas que solo mira el panel de
// administración, y mezclarlas haría que la app del residente cargue código
// que nunca va a usar.
//
// NOTA SOBRE LOS NOMBRES DE LAS COLUMNAS
//
//   Los nombres que se leen acá son los REALES de la base de datos, y algunos
//   no son los que uno esperaría: la fecha de un movimiento es "ocurrido_en" y
//   no "creado_en", el nombre de quien pasó es "nombre_snapshot", y la patente
//   es "patente_snapshot".
//
//   Se llaman "snapshot" (foto) porque guardan cómo se llamaba la persona EN
//   ESE MOMENTO. Si mañana cambia de nombre o de unidad, el registro viejo
//   sigue diciendo lo que decía el día que pasó. Eso es lo que hace que el
//   historial sirva como prueba.
// ============================================================================

/// Los números de la pantalla de inicio del administrador.
class ResumenAdmin {
  const ResumenAdmin({
    required this.vehiculosPorAprobar,
    required this.personasActivas,
    required this.paquetesEnPorteria,
    required this.espacios,
    required this.novedadesAbiertas,
    required this.guardiasDeTurno,
  });

  final int vehiculosPorAprobar;
  final int personasActivas;
  final int paquetesEnPorteria;
  final int espacios;
  final int novedadesAbiertas;
  final int guardiasDeTurno;

  /// Si hay algo esperando que el administrador haga.
  bool get hayPendientes => vehiculosPorAprobar > 0 || novedadesAbiertas > 0;
}

// ============================================================================
// UN VEHÍCULO ESPERANDO APROBACIÓN
// ============================================================================

class VehiculoParaAprobar {
  const VehiculoParaAprobar({
    required this.id,
    required this.patente,
    required this.marca,
    required this.modelo,
    required this.color,
    required this.creadoEn,
    required this.duenoNombre,
    this.anio,
    this.fotoUrl,
    this.fotoPatenteUrl,
    this.duenoTelefono,
    this.duenoEspacio,
  });

  final String id;
  final String patente;
  final String marca;
  final String modelo;
  final String color;
  final DateTime creadoEn;
  final String duenoNombre;
  final int? anio;
  final String? fotoUrl;
  final String? fotoPatenteUrl;
  final String? duenoTelefono;

  /// "101 A" o "4°B Enseñanza Básica", ya armado para mostrar.
  final String? duenoEspacio;

  /// Cuántos días lleva esperando. Un auto sin aprobar es un residente que no
  /// puede entrar con su auto, así que la espera importa.
  int get diasEsperando => DateTime.now().difference(creadoEn).inDays;

  String get descripcion => [marca, modelo, if (anio != null) '$anio']
      .where((p) => p.trim().isNotEmpty)
      .join(' ');

  factory VehiculoParaAprobar.desdeMapa(Map<String, dynamic> m) {
    final dueno = m['usuarios'];
    String? espacio;
    String nombre = 'Sin dueño registrado';
    String? telefono;

    if (dueno is Map) {
      nombre = (dueno['nombre_completo'] ?? nombre) as String;
      telefono = dueno['telefono'] as String?;
      final u = dueno['unidades'];
      if (u is Map) {
        espacio = [u['numero'], u['torre']]
            .where((p) => p != null && p.toString().isNotEmpty)
            .join(' ');
        if (espacio.isEmpty) espacio = null;
      }
    }

    return VehiculoParaAprobar(
      id: m['id'] as String,
      patente: ((m['patente'] ?? '') as String).toUpperCase(),
      marca: (m['marca'] ?? '') as String,
      modelo: (m['modelo'] ?? '') as String,
      color: (m['color'] ?? '') as String,
      anio: m['anio'] as int?,
      creadoEn: DateTime.parse(m['creado_en'] as String),
      fotoUrl: m['foto_url'] as String?,
      fotoPatenteUrl: m['foto_patente_url'] as String?,
      duenoNombre: nombre,
      duenoTelefono: telefono,
      duenoEspacio: espacio,
    );
  }
}

// ============================================================================
// UNA PERSONA DE LA INSTALACIÓN
// ============================================================================

class PersonaAdmin {
  const PersonaAdmin({
    required this.id,
    required this.nombreCompleto,
    required this.email,
    required this.rol,
    required this.estado,
    this.telefono,
    this.cedula,
    this.espacioId,
    this.espacio,
    this.relacionEspacio,
  });

  final String id;
  final String nombreCompleto;
  final String email;
  final String rol;
  final String estado;
  final String? telefono;
  final String? cedula;
  final String? espacioId;
  final String? espacio;
  final String? relacionEspacio;

  bool get estaActiva => estado == 'activo';

  String get iniciales {
    final partes = nombreCompleto.trim().split(RegExp(r'\s+'));
    if (partes.isEmpty || partes.first.isEmpty) return '?';
    if (partes.length == 1) return partes.first[0].toUpperCase();
    return '${partes[0][0]}${partes[1][0]}'.toUpperCase();
  }

  factory PersonaAdmin.desdeMapa(Map<String, dynamic> m) {
    final u = m['unidades'];
    String? espacio;
    String? espacioId;
    if (u is Map) {
      espacioId = u['id'] as String?;
      espacio = [u['numero'], u['torre']]
          .where((p) => p != null && p.toString().isNotEmpty)
          .join(' ');
      if (espacio.isEmpty) espacio = null;
    }

    return PersonaAdmin(
      id: m['id'] as String,
      nombreCompleto: (m['nombre_completo'] ?? '') as String,
      email: (m['email'] ?? '') as String,
      rol: (m['rol'] ?? 'residente') as String,
      estado: (m['estado'] ?? 'activo') as String,
      telefono: m['telefono'] as String?,
      cedula: m['cedula'] as String?,
      espacioId: espacioId,
      espacio: espacio,
      relacionEspacio: m['relacion_unidad'] as String?,
    );
  }
}

/// Lo que devuelve el servidor al dar de alta a alguien o cambiarle la clave.
class AltaDePersona {
  const AltaDePersona({required this.mensaje, this.claveProvisoria});

  final String mensaje;

  /// La contraseña con la que la persona entra la primera vez. Se muestra UNA
  /// sola vez: el servidor no la guarda en texto y no se puede volver a ver.
  final String? claveProvisoria;
}

// ============================================================================
// UN ESPACIO: unidad en un condominio, curso en un colegio
// ============================================================================

class EspacioAdmin {
  const EspacioAdmin({
    required this.id,
    required this.numero,
    required this.tipo,
    this.torre,
    this.estacionamientos = 0,
    this.notas,
  });

  final String id;
  final String numero;
  final String tipo;
  final String? torre;
  final int estacionamientos;
  final String? notas;

  /// "101 A" o "4°B Enseñanza Básica"
  String get nombreCompleto =>
      [numero, torre].where((p) => p != null && p.isNotEmpty).join(' ');

  factory EspacioAdmin.desdeMapa(Map<String, dynamic> m) => EspacioAdmin(
        id: m['id'] as String,
        numero: (m['numero'] ?? '') as String,
        torre: m['torre'] as String?,
        tipo: (m['tipo'] ?? 'apartamento') as String,
        estacionamientos: (m['estacionamientos'] ?? 0) as int,
        notas: m['notas'] as String?,
      );
}

// ============================================================================
// UN MOVIMIENTO DEL HISTORIAL
// ============================================================================

class MovimientoAdmin {
  const MovimientoAdmin({
    required this.id,
    required this.tipoAcceso,
    required this.sentido,
    required this.aprobado,
    required this.ocurridoEn,
    this.quien,
    this.espacio,
    this.patente,
    this.entrada,
    this.motivoDenegacion,
  });

  final String id;

  /// 'peatonal' o 'vehicular'
  final String tipoAcceso;

  /// 'entrada' o 'salida'
  final String sentido;

  final bool aprobado;
  final DateTime ocurridoEn;
  final String? quien;
  final String? espacio;
  final String? patente;
  final String? entrada;
  final String? motivoDenegacion;

  bool get esVehicular => tipoAcceso == 'vehicular';
  bool get esEntrada => sentido == 'entrada';

  factory MovimientoAdmin.desdeMapa(Map<String, dynamic> m) {
    // El nombre puede venir de dos lados: de la foto guardada en el momento
    // (nombre_snapshot) o de la ficha del residente. Se prefiere la foto,
    // porque es lo que era verdad el día que pasó.
    String? nombre = m['nombre_snapshot'] as String?;
    if (nombre == null || nombre.isEmpty) {
      final u = m['usuarios'];
      if (u is Map) nombre = u['nombre_completo'] as String?;
    }

    final p = m['puntos_acceso'];

    return MovimientoAdmin(
      id: m['id'] as String,
      tipoAcceso: (m['tipo_acceso'] ?? 'peatonal') as String,
      sentido: (m['sentido'] ?? 'entrada') as String,
      aprobado: m['estado'] == 'aprobado',
      ocurridoEn: DateTime.parse(m['ocurrido_en'] as String),
      quien: nombre,
      espacio: m['unidad_snapshot'] as String?,
      patente: m['patente_snapshot'] as String?,
      entrada: p is Map ? p['nombre'] as String? : null,
      motivoDenegacion: m['motivo_denegacion'] as String?,
    );
  }
}

// ============================================================================
// UN TURNO YA TRABAJADO
// ============================================================================

class TurnoAdmin {
  const TurnoAdmin({
    required this.id,
    required this.inicio,
    required this.guardia,
    this.cerradoEn,
    this.puesto,
    this.notas,
  });

  final String id;
  final DateTime inicio;
  final String guardia;
  final DateTime? cerradoEn;
  final String? puesto;
  final String? notas;

  bool get sigueAbierto => cerradoEn == null;

  Duration get duracion => (cerradoEn ?? DateTime.now()).difference(inicio);

  /// "8 h 30 min", ya armado para mostrar.
  String get duracionEnPalabras {
    final horas = duracion.inHours;
    final minutos = duracion.inMinutes % 60;
    if (horas == 0) return '$minutos min';
    return '$horas h $minutos min';
  }

  factory TurnoAdmin.desdeMapa(Map<String, dynamic> m) {
    final g = m['usuarios'];
    final p = m['puntos_acceso'];
    return TurnoAdmin(
      id: m['id'] as String,
      inicio: DateTime.parse(m['inicio'] as String),
      cerradoEn: m['cerrado_en'] == null
          ? null
          : DateTime.parse(m['cerrado_en'] as String),
      guardia: g is Map
          ? (g['nombre_completo'] ?? 'Sin nombre') as String
          : 'Sin nombre',
      // Vacío significa que ese guardia cubría TODAS las entradas, que es el
      // caso normal cuando hay un solo guardia.
      puesto: p is Map ? p['nombre'] as String? : null,
      notas: m['notas_entrega'] as String?,
    );
  }
}
