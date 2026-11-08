// ============================================================================
// Tomass Seguridad — Ciclo de turno 4x4 del guardia
// ============================================================================
// CÓMO FUNCIONA, EN CRIOLLO
//
//   Cada guardia trabaja en ciclos de 8 días: 4 seguidos de trabajo + 4 de
//   descanso. Para saber si HOY le toca trabajar alcanza con dos datos:
//
//     1. Su turno (día o noche, que es FIJO para cada guardia en Tomass).
//     2. UN día cualquiera en el que sí trabajó. Eso ancla el ciclo.
//
//   A partir de ahí: contás los días que pasaron desde el ancla hasta un día
//   cualquiera, hacés mod 8, y:
//
//        0 1 2 3  → trabajo
//        4 5 6 7  → descanso
//
// POR QUÉ NO SE GUARDAN LOS DÍAS EN UNA PLANILLA EN LA BASE
//
//   Porque no hace falta. Con turno + ancla el ciclo queda determinado para
//   siempre. Si algún día el guardia cambia su configuración (empezó un ciclo
//   nuevo, le cambiaron el turno), actualiza esos dos datos y listo.
// ============================================================================

class CicloDeTurno {
  const CicloDeTurno({
    required this.turno,
    required this.primerDiaTrabajo,
    this.horaAprox,
    this.minutoAprox,
  });

  /// 'dia' o 'noche'. En Tomass cada guardia tiene un turno fijo.
  final String turno;

  /// Un día en el que el guardia sí trabajó. Es el ancla del ciclo.
  final DateTime primerDiaTrabajo;

  /// Hora aproximada a la que empieza su turno (8 si es de día, 20 si es de
  /// noche). Opcional, pensada para futuros recordatorios.
  final int? horaAprox;
  final int? minutoAprox;

  bool get esDeDia => turno == 'dia';
  bool get esDeNoche => turno == 'noche';

  bool get tieneHoraAprox => horaAprox != null;

  /// La hora en formato "08:00", lista para mostrar.
  String get horaFormateada {
    if (horaAprox == null) return '';
    final hh = horaAprox!.toString().padLeft(2, '0');
    final mm = (minutoAprox ?? 0).toString().padLeft(2, '0');
    return '$hh:$mm';
  }

  /// Dado un día cualquiera, dice si ese día le toca trabajar.
  ///
  /// Normaliza ambas fechas a medianoche: lo que importa es el día de
  /// calendario, no la hora.
  bool estaDeTrabajo(DateTime dia) {
    final hoy = DateTime(dia.year, dia.month, dia.day);
    final ancla = DateTime(
      primerDiaTrabajo.year,
      primerDiaTrabajo.month,
      primerDiaTrabajo.day,
    );
    final diffDias = hoy.difference(ancla).inDays;
    // mod 8 "seguro" para fechas anteriores al ancla
    final posicion = ((diffDias % 8) + 8) % 8;
    return posicion < 4;
  }

  /// El próximo día (incluyendo "desde", si le toca) que trabaja.
  DateTime proximoDiaDeTrabajo(DateTime desde) {
    var d = DateTime(desde.year, desde.month, desde.day);
    for (var i = 0; i < 8; i++) {
      if (estaDeTrabajo(d)) return d;
      d = d.add(const Duration(days: 1));
    }
    return d; // inalcanzable para un ciclo 4x4, pero evita el warning
  }

  factory CicloDeTurno.desdeMapa(Map<String, dynamic> m) {
    int? h;
    int? mn;
    final hora = m['hora_inicio_aprox'];
    if (hora is String && hora.isNotEmpty) {
      // Postgres devuelve el time como 'HH:MM:SS'
      final partes = hora.split(':');
      if (partes.length >= 2) {
        h = int.tryParse(partes[0]);
        mn = int.tryParse(partes[1]);
      }
    }
    return CicloDeTurno(
      turno: (m['turno'] ?? 'dia') as String,
      primerDiaTrabajo: DateTime.parse(m['primer_dia_trabajo'] as String),
      horaAprox: h,
      minutoAprox: mn,
    );
  }
}
