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
    this.fotoUrl,
    this.geoLat,
    this.geoLng,
    this.actividad,
  });

  /// Devuelve una copia con la actividad agregada (para no romper inmutabilidad).
  TurnoAdmin conActividad(ActividadTurno act) => TurnoAdmin(
        id: id,
        inicio: inicio,
        guardia: guardia,
        cerradoEn: cerradoEn,
        puesto: puesto,
        notas: notas,
        fotoUrl: fotoUrl,
        geoLat: geoLat,
        geoLng: geoLng,
        actividad: act,
      );

  final String id;
  final DateTime inicio;
  final String guardia;
  final DateTime? cerradoEn;
  final String? puesto;
  final String? notas;

  /// Ruta de la selfie tomada al abrir el turno (bucket "guardias"). Se
  /// resuelve a URL firmada al momento de mostrar.
  final String? fotoUrl;

  /// Coordenadas GPS donde se abrió el turno. Pueden ser null si el guardia
  /// tenía el GPS apagado o sin señal.
  final double? geoLat;
  final double? geoLng;

  /// Contadores calculados aparte (14. actividad por turno).
  final ActividadTurno? actividad;

  bool get tieneFoto => fotoUrl != null && fotoUrl!.isNotEmpty;
  bool get tieneUbicacion => geoLat != null && geoLng != null;

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
      fotoUrl: m['foto_url'] as String?,
      geoLat: (m['geo_lat'] as num?)?.toDouble(),
      geoLng: (m['geo_lng'] as num?)?.toDouble(),
    );
  }
}

// ============================================================================
// UNA INSTALACIÓN QUE EL ADMINISTRADOR PUEDE ATENDER
// ============================================================================
// Tomass Seguridad Privada atiende varias. El administrador trabaja en UNA a la
// vez y cambia con el selector de arriba.
//
// Se trabaja de a una a propósito, y no viendo todas mezcladas: así los 38
// candados de la base de datos siguen diciendo exactamente lo mismo que antes,
// y no hubo que reescribirlos. Reescribirlos era el camino más corto a que un
// condominio terminara viendo los datos de otro.
// ============================================================================

class Instalacion {
  const Instalacion({
    required this.id,
    required this.nombre,
    required this.tipo,
    required this.esLaActiva,
    this.nombreCorto,
    this.ciudad,
  });

  final String id;
  final String nombre;
  final String tipo;
  final bool esLaActiva;
  final String? nombreCorto;
  final String? ciudad;

  /// El nombre que entra en la pantalla de un celular.
  String get nombreParaMostrar =>
      (nombreCorto != null && nombreCorto!.isNotEmpty) ? nombreCorto! : nombre;

  factory Instalacion.desdeMapa(Map<String, dynamic> m) => Instalacion(
        id: m['id'] as String,
        nombre: (m['nombre'] ?? '') as String,
        nombreCorto: m['nombre_corto'] as String?,
        tipo: (m['tipo'] ?? 'condominio') as String,
        ciudad: m['ciudad'] as String?,
        esLaActiva: (m['es_la_activa'] ?? false) as bool,
      );
}

// ============================================================================
// UN PUNTO DE CONTROL DE LAS RONDAS
// ============================================================================
// El cartel que se pega en cada sector. Lo crea el administrador PARADO AHÍ,
// para que quede guardada la ubicación real del lugar.
// ============================================================================

class PuntoControlAdmin {
  const PuntoControlAdmin({
    required this.id,
    required this.nombre,
    required this.orden,
    required this.codigoQr,
    required this.metrosDeTolerancia,
    this.descripcion,
    this.latitud,
    this.longitud,
    this.ubicacionTomadaEn,
  });

  final String id;
  final String nombre;
  final int orden;

  /// Lo que va impreso adentro del QR del cartel.
  final String codigoQr;

  /// Cuántos metros de error de GPS se le perdonan a este punto.
  final int metrosDeTolerancia;

  final String? descripcion;
  final double? latitud;
  final double? longitud;
  final DateTime? ubicacionTomadaEn;

  /// Sin ubicación, el sistema solo puede demostrar que alguien tuvo el código
  /// del cartel; con ella demuestra que estuvo ahí.
  bool get tieneUbicacion => latitud != null && longitud != null;

  factory PuntoControlAdmin.desdeMapa(Map<String, dynamic> m) =>
      PuntoControlAdmin(
        id: m['id'] as String,
        nombre: (m['nombre'] ?? '') as String,
        orden: (m['orden'] ?? 0) as int,
        codigoQr: (m['codigo_qr'] ?? '') as String,
        metrosDeTolerancia: (m['metros_de_tolerancia'] ?? 60) as int,
        descripcion: m['descripcion'] as String?,
        latitud: (m['latitud'] as num?)?.toDouble(),
        longitud: (m['longitud'] as num?)?.toDouble(),
        ubicacionTomadaEn: m['ubicacion_tomada_en'] == null
            ? null
            : DateTime.parse(m['ubicacion_tomada_en'] as String),
      );
}

// ============================================================================
// UNA RONDA EN EL INFORME
// ============================================================================

class RondaDelInforme {
  const RondaDelInforme({
    required this.id,
    required this.guardia,
    required this.inicio,
    required this.minutos,
    required this.marcados,
    required this.total,
    required this.completa,
    required this.marcasLejanas,
    required this.sePasoDelLimite,
    this.cerradaEn,
    this.horasDesdeLaAnterior,
    this.notas,
  });

  final String id;
  final String guardia;
  final DateTime inicio;
  final DateTime? cerradaEn;
  final int minutos;
  final int marcados;
  final int total;
  final bool completa;

  /// Cuántos puntos se marcaron desde más lejos de lo permitido.
  ///
  /// No prueba que alguien haya hecho trampa: el GPS falla bajo techo. Es una
  /// señal para mirar, no una acusación.
  final int marcasLejanas;

  /// true si pasaron más de las 2 horas de contrato desde la ronda anterior.
  final bool sePasoDelLimite;

  final double? horasDesdeLaAnterior;
  final String? notas;

  bool get sigueAbierta => cerradaEn == null;
  bool get hayAlgoQueMirar => sePasoDelLimite || marcasLejanas > 0 || !completa;

  factory RondaDelInforme.desdeMapa(Map<String, dynamic> m) => RondaDelInforme(
        id: m['ronda_id'] as String,
        guardia: (m['guardia'] ?? 'Sin nombre') as String,
        inicio: DateTime.parse(m['inicio'] as String),
        cerradaEn: m['cerrada_en'] == null
            ? null
            : DateTime.parse(m['cerrada_en'] as String),
        minutos: (m['minutos'] ?? 0) as int,
        marcados: (m['marcados'] ?? 0) as int,
        total: (m['total'] ?? 0) as int,
        completa: (m['completa'] ?? false) as bool,
        marcasLejanas: (m['marcas_lejanas'] ?? 0) as int,
        sePasoDelLimite: (m['se_paso_del_limite'] ?? false) as bool,
        horasDesdeLaAnterior:
            (m['horas_desde_la_anterior'] as num?)?.toDouble(),
        notas: m['notas'] as String?,
      );
}

// ============================================================================
// EL DETALLE DE UNA MARCACIÓN, PARA EL INFORME EN PDF
// ============================================================================

class MarcaDelInforme {
  const MarcaDelInforme({
    required this.rondaId,
    required this.guardia,
    required this.rondaInicio,
    required this.sector,
    required this.sectorOrden,
    required this.marcadoEn,
    required this.lejos,
    this.rondaCerrada,
    this.rondaNotas,
    this.novedad,
    this.sectorLat,
    this.sectorLng,
    this.marcaLat,
    this.marcaLng,
    this.metrosDeLejos,
    this.tolerancia = 60,
  });

  final String rondaId;
  final String guardia;
  final DateTime rondaInicio;
  final DateTime? rondaCerrada;
  final String? rondaNotas;

  final String sector;
  final int sectorOrden;
  final DateTime marcadoEn;
  final String? novedad;

  /// Dónde está pegado el cartel.
  final double? sectorLat;
  final double? sectorLng;
  final int tolerancia;

  /// Dónde estaba el teléfono al marcar.
  final double? marcaLat;
  final double? marcaLng;

  final double? metrosDeLejos;
  final bool lejos;

  bool get tieneUbicacion =>
      sectorLat != null && marcaLat != null && metrosDeLejos != null;

  factory MarcaDelInforme.desdeMapa(Map<String, dynamic> m) => MarcaDelInforme(
        rondaId: m['ronda_id'] as String,
        guardia: (m['guardia'] ?? '') as String,
        rondaInicio: DateTime.parse(m['ronda_inicio'] as String),
        rondaCerrada: m['ronda_cerrada'] == null
            ? null
            : DateTime.parse(m['ronda_cerrada'] as String),
        rondaNotas: m['ronda_notas'] as String?,
        sector: (m['sector'] ?? '') as String,
        sectorOrden: (m['sector_orden'] ?? 0) as int,
        marcadoEn: DateTime.parse(m['marcado_en'] as String),
        novedad: m['novedad'] as String?,
        sectorLat: (m['sector_lat'] as num?)?.toDouble(),
        sectorLng: (m['sector_lng'] as num?)?.toDouble(),
        tolerancia: (m['tolerancia'] ?? 60) as int,
        marcaLat: (m['marca_lat'] as num?)?.toDouble(),
        marcaLng: (m['marca_lng'] as num?)?.toDouble(),
        metrosDeLejos: (m['metros_de_lejos'] as num?)?.toDouble(),
        lejos: (m['lejos'] ?? false) as bool,
      );
}

/// Un sector con su ubicación, para dibujar el plano del informe.
class SectorDelPlano {
  const SectorDelPlano({
    required this.id,
    required this.nombre,
    required this.orden,
    required this.tolerancia,
    this.latitud,
    this.longitud,
  });

  final String id;
  final String nombre;
  final int orden;
  final int tolerancia;
  final double? latitud;
  final double? longitud;

  bool get tieneUbicacion => latitud != null && longitud != null;

  factory SectorDelPlano.desdeMapa(Map<String, dynamic> m) => SectorDelPlano(
        id: m['id'] as String,
        nombre: (m['nombre'] ?? '') as String,
        orden: (m['orden'] ?? 0) as int,
        tolerancia: (m['tolerancia'] ?? 60) as int,
        latitud: (m['latitud'] as num?)?.toDouble(),
        longitud: (m['longitud'] as num?)?.toDouble(),
      );
}

// ============================================================================
// UNA ENCOMIENDA ENTREGADA, PARA EL INFORME CON FOTOS
// ============================================================================

class EncomiendaDelInforme {
  const EncomiendaDelInforme({
    required this.id,
    required this.entregadoEn,
    this.descripcion,
    this.numeroSeguimiento,
    this.empresaCourier,
    this.residente,
    this.unidad,
    this.retiradoPor,
    this.guardiaEntrega,
    this.fotoUrl,
    this.fotoEntregaUrl,
  });

  final String id;
  final DateTime entregadoEn;
  final String? descripcion;
  final String? numeroSeguimiento;
  final String? empresaCourier;
  final String? residente;
  final String? unidad;

  /// Quien retiró, si no fue el propio residente (por ejemplo, un familiar o
  /// el conserje). Si es null, la retiró el residente en persona.
  final String? retiradoPor;
  final String? guardiaEntrega;

  final String? fotoUrl;
  final String? fotoEntregaUrl;

  bool get tieneFoto => fotoUrl != null || fotoEntregaUrl != null;

  /// Con qué foto se arma la fila del informe.
  ///
  /// Se prefiere la de la ENTREGA porque es la que prueba que el paquete se
  /// fue en buen estado con la persona correcta, que es lo que este informe
  /// necesita demostrar. Si esa no se sacó, se usa la de cuando llegó a
  /// portería: es mejor mostrar esa que dejar la fila vacía.
  String? get fotoParaElInforme => fotoEntregaUrl ?? fotoUrl;

  /// A quién se le entregó, ya armado para mostrar.
  String get quienRetiro => (retiradoPor != null && retiradoPor!.isNotEmpty)
      ? retiradoPor!
      : (residente ?? 'Sin nombre registrado');

  factory EncomiendaDelInforme.desdeMapa(Map<String, dynamic> m) {
    final residenteMapa = m['usuarios'];
    String? residente;
    if (residenteMapa is Map) {
      residente = residenteMapa['nombre_completo'] as String?;
    }

    final unidadMapa = m['unidades'];
    String? unidad;
    if (unidadMapa is Map) {
      unidad = [unidadMapa['numero'], unidadMapa['torre']]
          .where((p) => p != null && p.toString().isNotEmpty)
          .join(' ');
      if (unidad.isEmpty) unidad = null;
    }

    final guardiaMapa = m['guardia'];
    String? guardia;
    if (guardiaMapa is Map) {
      guardia = guardiaMapa['nombre_completo'] as String?;
    }

    return EncomiendaDelInforme(
      id: m['id'] as String,
      entregadoEn: DateTime.parse(m['entregado_en'] as String),
      descripcion: m['descripcion'] as String?,
      numeroSeguimiento: m['numero_seguimiento'] as String?,
      empresaCourier: m['empresa_courier'] as String?,
      residente: residente,
      unidad: unidad,
      retiradoPor: m['retirado_por'] as String?,
      guardiaEntrega: guardia,
      fotoUrl: m['foto_url'] as String?,
      fotoEntregaUrl: m['foto_entrega_url'] as String?,
    );
  }
}

// ============================================================================
// ESTADÍSTICAS PARA EL INFORME DE TURNOS
// ============================================================================
// Todo lo que va en la PORTADA del PDF del informe de turnos, calculado en el
// servidor antes de generar el PDF. Los siete "widgets" del Sprint 1:
//
//   1. KpiCumplimiento         → % con selfie / GPS / rondas completas
//   3. accesosPorHora          → array de 24 (para el gráfico horario)
//   4. alertas                 → lista de anomalías detectadas
//   6. encomiendasPendientes   → paquetes viejos sin entregar
//   10. rankingGuardias        → tabla ordenada por cumplimiento
//   14. actividadPorTurno      → ya viene dentro de cada TurnoAdmin
//   15. notasEntregaTurno      → ya viene dentro de cada TurnoAdmin
// ============================================================================

class EstadisticasTurnos {
  const EstadisticasTurnos({
    required this.desde,
    required this.hasta,
    required this.kpi,
    required this.accesosPorHora,
    required this.alertas,
    required this.encomiendasPendientes,
    required this.ranking,
  });

  final DateTime desde;
  final DateTime hasta;
  final KpiCumplimiento kpi;
  final List<int> accesosPorHora; // 24 valores (0-23)
  final List<AlertaTurno> alertas;
  final List<EncomiendaPendiente> encomiendasPendientes;
  final List<RankingGuardia> ranking;

  int get totalAccesos => accesosPorHora.fold(0, (a, b) => a + b);
  int get horaPico {
    if (accesosPorHora.every((v) => v == 0)) return -1;
    var maxIdx = 0;
    for (var i = 1; i < 24; i++) {
      if (accesosPorHora[i] > accesosPorHora[maxIdx]) maxIdx = i;
    }
    return maxIdx;
  }
}

class KpiCumplimiento {
  const KpiCumplimiento({
    required this.totalTurnos,
    required this.turnosConSelfie,
    required this.turnosConGps,
    required this.totalRondas,
    required this.rondasCompletas,
    required this.horasCubiertas,
  });

  final int totalTurnos;
  final int turnosConSelfie;
  final int turnosConGps;
  final int totalRondas;
  final int rondasCompletas;
  final double horasCubiertas;

  int get pctSelfie =>
      totalTurnos == 0 ? 0 : (turnosConSelfie * 100 ~/ totalTurnos);
  int get pctGps =>
      totalTurnos == 0 ? 0 : (turnosConGps * 100 ~/ totalTurnos);
  int get pctRondasCompletas =>
      totalRondas == 0 ? 0 : (rondasCompletas * 100 ~/ totalRondas);
}

/// Una anomalía detectada en el período.
class AlertaTurno {
  const AlertaTurno({
    required this.tipo,
    required this.descripcion,
    this.cuando,
    this.guardia,
  });

  final TipoAlerta tipo;
  final String descripcion;
  final DateTime? cuando;
  final String? guardia;
}

enum TipoAlerta {
  rondaSospechosa, // menos de 5 minutos
  gapCobertura,    // período sin ningún turno abierto
  turnoSinSelfie,
  turnoSinGps;

  String get etiqueta => switch (this) {
        TipoAlerta.rondaSospechosa => 'Ronda muy rápida',
        TipoAlerta.gapCobertura => 'Sin cobertura',
        TipoAlerta.turnoSinSelfie => 'Turno sin selfie',
        TipoAlerta.turnoSinGps => 'Turno sin GPS',
      };
}

class EncomiendaPendiente {
  const EncomiendaPendiente({
    required this.id,
    required this.recibidoEn,
    required this.descripcion,
    this.residente,
    this.unidad,
    this.empresaCourier,
  });

  final String id;
  final DateTime recibidoEn;
  final String descripcion;
  final String? residente;
  final String? unidad;
  final String? empresaCourier;

  int get diasEsperando => DateTime.now().difference(recibidoEn).inDays;
}

class RankingGuardia {
  const RankingGuardia({
    required this.guardia,
    required this.totalTurnos,
    required this.horasTrabajadas,
    required this.pctSelfie,
    required this.pctGps,
    required this.rondasHechas,
  });

  final String guardia;
  final int totalTurnos;
  final double horasTrabajadas;
  final int pctSelfie;
  final int pctGps;
  final int rondasHechas;

  /// Puntaje 0-100 combinando cumplimiento de selfie + GPS.
  int get puntaje => ((pctSelfie + pctGps) / 2).round();
}

/// Contadores por turno individual (14. actividad por turno).
class ActividadTurno {
  const ActividadTurno({
    required this.accesos,
    required this.encomiendas,
    required this.rondas,
  });

  final int accesos;
  final int encomiendas;
  final int rondas;

  bool get vacio => accesos == 0 && encomiendas == 0 && rondas == 0;
}

// ============================================================================
// UNA MARCA DE RONDA (un sector escaneado durante un turno)
// ============================================================================
// Sirve para dibujar el mini-mapa de ronda por turno y contar cuántos puntos
// marcó el guardia con GPS del propio celular (para detectar escaneos
// hechos lejos del cartel).
// ============================================================================

class MarcaDeRondaAdmin {
  const MarcaDeRondaAdmin({
    required this.id,
    required this.rondaId,
    required this.marcadoEn,
    required this.puntoNombre,
    this.geoLat,
    this.geoLng,
    this.puntoLat,
    this.puntoLng,
    this.novedad,
  });

  final String id;
  final String rondaId;
  final DateTime marcadoEn;
  final String puntoNombre;

  /// Dónde estaba el celular del guardia cuando escaneó.
  final double? geoLat;
  final double? geoLng;

  /// Dónde estaba el cartel (según lo cargó el admin).
  final double? puntoLat;
  final double? puntoLng;

  final String? novedad;

  bool get tieneGpsGuardia => geoLat != null && geoLng != null;
  bool get tieneGpsPunto => puntoLat != null && puntoLng != null;

  factory MarcaDeRondaAdmin.desdeMapa(Map<String, dynamic> m) {
    final p = m['puntos_control'];
    return MarcaDeRondaAdmin(
      id: m['id'] as String,
      rondaId: m['ronda_id'] as String,
      marcadoEn: DateTime.parse(m['marcado_en'] as String),
      puntoNombre:
          (p is Map ? p['nombre'] as String? : null) ?? 'Sector sin nombre',
      geoLat: (m['geo_lat'] as num?)?.toDouble(),
      geoLng: (m['geo_lng'] as num?)?.toDouble(),
      puntoLat: p is Map ? (p['latitud'] as num?)?.toDouble() : null,
      puntoLng: p is Map ? (p['longitud'] as num?)?.toDouble() : null,
      novedad: m['novedad'] as String?,
    );
  }
}

// ============================================================================
// UNA NOVEDAD/INCIDENTE DEL HISTORIAL
// ============================================================================
// En la base de datos la tabla se llama "incidentes"; en la UI le decimos
// "novedades". Este modelo abarca lo que el administrador ve al armar el
// informe: qué pasó, cuándo, quién lo reportó, con qué gravedad y con qué
// fotos si tiene.
// ============================================================================

class IncidenteAdmin {
  const IncidenteAdmin({
    required this.id,
    required this.tipo,
    required this.titulo,
    required this.ocurridoEn,
    required this.estado,
    this.gravedad,
    this.descripcion,
    this.ubicacion,
    this.patente,
    this.unidadTexto,
    this.reportadoPor,
    this.notaResolucion,
    this.resueltoEn,
    this.fotos = const [],
  });

  final String id;
  final String tipo;
  final String titulo;
  final DateTime ocurridoEn;

  /// 'abierta', 'resuelta', etc. — cómo viene en la base.
  final String estado;
  final String? gravedad;
  final String? descripcion;
  final String? ubicacion;
  final String? patente;
  final String? unidadTexto;
  final String? reportadoPor;
  final String? notaResolucion;
  final DateTime? resueltoEn;
  final List<String> fotos;

  bool get abierta => estado != 'resuelta';
  bool get tieneFotos => fotos.isNotEmpty;

  factory IncidenteAdmin.desdeMapa(Map<String, dynamic> m) {
    final u = m['unidades'];
    final r = m['usuarios'];

    List<String> parseFotos(dynamic v) {
      if (v is List) return v.whereType<String>().toList();
      return const [];
    }

    String? unidadTexto;
    if (u is Map) {
      final numero = u['numero']?.toString();
      final torre = u['torre']?.toString();
      unidadTexto = [
        if (torre != null && torre.isNotEmpty) torre,
        if (numero != null && numero.isNotEmpty) numero,
      ].join(' ');
      if (unidadTexto.isEmpty) unidadTexto = null;
    }

    return IncidenteAdmin(
      id: m['id'] as String,
      tipo: (m['tipo'] ?? 'otra') as String,
      titulo: (m['titulo'] ?? 'Sin título') as String,
      ocurridoEn: DateTime.parse(m['ocurrido_en'] as String),
      estado: (m['estado'] ?? 'abierta') as String,
      gravedad: m['gravedad'] as String?,
      descripcion: m['descripcion'] as String?,
      ubicacion: m['ubicacion_texto'] as String?,
      patente: m['patente'] as String?,
      unidadTexto: unidadTexto,
      reportadoPor: r is Map ? r['nombre_completo'] as String? : null,
      notaResolucion: m['nota_resolucion'] as String?,
      resueltoEn: m['resuelto_en'] == null
          ? null
          : DateTime.parse(m['resuelto_en'] as String),
      fotos: parseFotos(m['fotos']),
    );
  }
}
