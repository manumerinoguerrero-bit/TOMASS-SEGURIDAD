// ============================================================================
// Tomass Seguridad — Mi calendario 4x4
// ============================================================================
// QUÉ RESUELVE
//
//   Los guardias de Tomass trabajan ciclos fijos 4x4 (cuatro días y cuatro
//   descanso). Hasta ahora, para saber qué les tocaba el próximo lunes tenían
//   que llamar al administrador o mirar una planilla en la oficina. Esta
//   pantalla le deja al guardia su propio calendario en el bolsillo.
//
// CÓMO FUNCIONA
//
//   Primera vez que entra: formulario corto. Elige si es de DÍA o de NOCHE,
//   toca una fecha en la que sí trabajó, y opcionalmente la hora de inicio.
//   Con esos dos datos la app calcula todo el ciclo para siempre.
//
//   Siguientes veces: ve una tarjeta con su PRÓXIMO turno destacado, y una
//   lista de los próximos treinta días con el día del calendario en verde si
//   trabaja, en gris si descansa. Puede editar su configuración cuando quiera.
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/tema.dart';
import '../../estado/proveedores_guardia.dart';
import '../../modelos/ciclo_turno.dart';
import '../../nucleo/errores.dart';
import '../../nucleo/formato.dart';
import '../comunes/componentes.dart';

class PantallaMisTurnos extends ConsumerWidget {
  const PantallaMisTurnos({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ciclo = ref.watch(miCicloDeTurnoProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Mis turnos')),
      body: ciclo.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (falla, _) => _ErrorDeCarga(falla: Traductor.traducir(falla)),
        data: (c) => c == null
            ? const _Formulario()
            : _VistaCalendario(ciclo: c),
      ),
    );
  }
}

// ============================================================================
// FORMULARIO: LA PRIMERA VEZ
// ============================================================================
// Se usa cuando el guardia todavía no cargó su ciclo, o cuando toca "Editar".
// Tres campos: día/noche, la fecha, y la hora (opcional).
// ============================================================================

class _Formulario extends ConsumerStatefulWidget {
  const _Formulario({this.inicial});

  final CicloDeTurno? inicial;

  @override
  ConsumerState<_Formulario> createState() => _EstadoFormulario();
}

class _EstadoFormulario extends ConsumerState<_Formulario> {
  String? _turno; // 'dia' | 'noche'
  DateTime? _dia;
  TimeOfDay? _hora;
  bool _guardando = false;
  ErrorAmigable? _problema;

  @override
  void initState() {
    super.initState();
    final i = widget.inicial;
    if (i != null) {
      _turno = i.turno;
      _dia = i.primerDiaTrabajo;
      if (i.horaAprox != null) {
        _hora = TimeOfDay(hour: i.horaAprox!, minute: i.minutoAprox ?? 0);
      }
    }
  }

  Future<void> _elegirDia() async {
    final hoy = DateTime.now();
    final fecha = await showDatePicker(
      context: context,
      initialDate: _dia ?? hoy,
      firstDate: hoy.subtract(const Duration(days: 365)),
      lastDate: hoy.add(const Duration(days: 365)),
      locale: const Locale('es', 'CL'),
      helpText: '¿Qué día trabajaste (o vas a trabajar)?',
      cancelText: 'Cancelar',
      confirmText: 'Listo',
    );
    if (fecha == null) return;
    setState(() => _dia = fecha);
  }

  Future<void> _elegirHora() async {
    final hora = await showTimePicker(
      context: context,
      initialTime: _hora ?? const TimeOfDay(hour: 8, minute: 0),
      helpText: '¿A qué hora empieza tu turno?',
      cancelText: 'Cancelar',
      confirmText: 'Listo',
    );
    if (hora == null) return;
    setState(() => _hora = hora);
  }

  Future<void> _guardar() async {
    if (_turno == null || _dia == null) {
      setState(() => _problema = const ErrorAmigable(
            'Elegí si sos de día o de noche, y una fecha.',
            sePuedeReintentar: false,
          ));
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() {
      _guardando = true;
      _problema = null;
    });

    try {
      await ref.read(servicioGuardiaProvider).guardarMiCiclo(
            turno: _turno!,
            primerDiaTrabajo: _dia!,
            horaAprox: _hora?.hour,
            minutoAprox: _hora?.minute,
          );
      ref.invalidate(miCicloDeTurnoProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Calendario guardado.'),
          backgroundColor: Colores.verde,
        ),
      );
    } catch (falla) {
      if (!mounted) return;
      setState(() {
        _guardando = false;
        _problema = Traductor.traducir(falla);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final editando = widget.inicial != null;

    return ListView(
      padding: const EdgeInsets.all(Medidas.margen),
      children: [
        if (!editando) ...[
          const SizedBox(height: 8),
          const Text(
            'Armá tu calendario 4x4',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          const Text(
            'Cargá tu turno y una fecha en la que trabajás. Con eso la app '
            'sabe qué días te tocan y cuáles descansás.',
            style:
                TextStyle(fontSize: 13.5, color: Colores.textoSuave, height: 1.4),
          ),
          const SizedBox(height: 24),
        ],

        if (_problema != null) ...[
          AvisoDeError(problema: _problema!),
          const SizedBox(height: 14),
        ],

        Text('¿DE DÍA O DE NOCHE?',
            style: Theme.of(context).textTheme.labelSmall),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _BotonTurno(
                texto: 'De día',
                icono: Icons.wb_sunny_rounded,
                elegido: _turno == 'dia',
                alTocar: () => setState(() => _turno = 'dia'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _BotonTurno(
                texto: 'De noche',
                icono: Icons.nightlight_round,
                elegido: _turno == 'noche',
                alTocar: () => setState(() => _turno = 'noche'),
              ),
            ),
          ],
        ),

        const SizedBox(height: 24),
        Text('UNA FECHA EN LA QUE TRABAJÁS',
            style: Theme.of(context).textTheme.labelSmall),
        const SizedBox(height: 4),
        const Text(
          'Puede ser la próxima vez que vas al puesto, o una pasada. Sirve '
          'para contar los demás días.',
          style: TextStyle(fontSize: 12, color: Colores.textoSuave, height: 1.4),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: _elegirDia,
          icon: const Icon(Icons.calendar_today_rounded, size: 19),
          label: Text(
            _dia == null ? 'Elegir fecha' : Formato.diaCompleto(_dia!),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(double.infinity, Medidas.altoBoton),
            foregroundColor: Colores.grafito,
          ),
        ),

        const SizedBox(height: 24),
        Text('HORA DE INICIO (OPCIONAL)',
            style: Theme.of(context).textTheme.labelSmall),
        const SizedBox(height: 4),
        const Text(
          'Si la dejás en blanco no pasa nada. Sirve para recordatorios más '
          'adelante.',
          style: TextStyle(fontSize: 12, color: Colores.textoSuave, height: 1.4),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: _elegirHora,
          icon: const Icon(Icons.schedule_rounded, size: 19),
          label: Text(
            _hora == null
                ? 'Agregar hora'
                : '${_hora!.hour.toString().padLeft(2, '0')}:'
                    '${_hora!.minute.toString().padLeft(2, '0')}',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(double.infinity, Medidas.altoBoton),
            foregroundColor: Colores.grafito,
          ),
        ),
        if (_hora != null)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () => setState(() => _hora = null),
              icon: const Icon(Icons.close_rounded, size: 16),
              label: const Text('Sin hora'),
              style: TextButton.styleFrom(foregroundColor: Colores.textoSuave),
            ),
          ),

        const SizedBox(height: 28),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _guardando ? null : _guardar,
            style: FilledButton.styleFrom(
              backgroundColor: Colores.verdeOscuro,
              minimumSize: const Size(0, Medidas.altoBotonGigante),
            ),
            icon: _guardando
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.check_rounded, size: 24),
            label: Text(
              _guardando ? 'Guardando…' : 'Guardar',
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}

// ============================================================================
// VISTA: TARJETA DEL PRÓXIMO TURNO + LISTA DE DÍAS
// ============================================================================

class _VistaCalendario extends ConsumerWidget {
  const _VistaCalendario({required this.ciclo});

  final CicloDeTurno ciclo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hoy = DateTime.now();
    final proximoDia = ciclo.proximoDiaDeTrabajo(hoy);
    final esHoy = ciclo.estaDeTrabajo(hoy);

    return ListView(
      padding: const EdgeInsets.all(Medidas.margen),
      children: [
        _TarjetaProximoTurno(
          ciclo: ciclo,
          proximoDia: proximoDia,
          esHoy: esHoy,
        ),
        const SizedBox(height: 22),

        _CalendarioMensual(ciclo: ciclo),
        const SizedBox(height: 12),
        _Leyenda(ciclo: ciclo),
        const SizedBox(height: 18),

        OutlinedButton.icon(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => Scaffold(
                appBar: AppBar(title: const Text('Editar mis turnos')),
                body: _Formulario(inicial: ciclo),
              ),
            ),
          ),
          icon: const Icon(Icons.edit_rounded, size: 19),
          label: const Text('Editar mi calendario'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(double.infinity, Medidas.altoBoton),
            foregroundColor: Colores.grafito,
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          'Si tu ciclo cambió (te tocó día en vez de noche, o empezaste un '
          'ciclo nuevo), editalo acá.',
          style: TextStyle(fontSize: 12, color: Colores.textoSuave, height: 1.4),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}

class _TarjetaProximoTurno extends StatelessWidget {
  const _TarjetaProximoTurno({
    required this.ciclo,
    required this.proximoDia,
    required this.esHoy,
  });

  final CicloDeTurno ciclo;
  final DateTime proximoDia;
  final bool esHoy;

  @override
  Widget build(BuildContext context) {
    final hoy = DateTime.now();
    final diaSiguiente = DateTime(hoy.year, hoy.month, hoy.day + 1);
    final esDiaSiguiente = proximoDia.year == diaSiguiente.year &&
        proximoDia.month == diaSiguiente.month &&
        proximoDia.day == diaSiguiente.day;

    final etiquetaCuando = esHoy
        ? 'HOY TE TOCA'
        : esDiaSiguiente
            ? 'MAÑANA TE TOCA'
            : 'TU PRÓXIMO TURNO';

    final hora = ciclo.tieneHoraAprox ? ' · ${ciclo.horaFormateada}' : '';

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: ciclo.esDeDia
              ? [Colores.dorado, Colores.doradoOscuro]
              : [Colores.grafito, Colores.azulOscuro],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(Medidas.redondeo),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                ciclo.esDeDia ? Icons.wb_sunny_rounded : Icons.nightlight_round,
                color: Colors.white,
                size: 22,
              ),
              const SizedBox(width: 10),
              Text(
                etiquetaCuando,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.3,
                  color: Colors.white.withValues(alpha: 0.85),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            Formato.diaCompleto(proximoDia),
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Turno ${ciclo.esDeDia ? 'de día' : 'de noche'}$hora',
            style: TextStyle(
              fontSize: 13.5,
              color: Colors.white.withValues(alpha: 0.85),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// CALENDARIO MENSUAL (cuadrícula Lun-Dom tipo planilla de guardia)
// ============================================================================
// Los guardias ya están acostumbrados a ver su mes así: cuadrícula con las
// semanas en filas y los días de la semana en columnas, con los días de
// trabajo pintados. Pueden ir mes para adelante o para atrás.
// ============================================================================

class _CalendarioMensual extends StatefulWidget {
  const _CalendarioMensual({required this.ciclo});

  final CicloDeTurno ciclo;

  @override
  State<_CalendarioMensual> createState() => _EstadoCalendarioMensual();
}

class _EstadoCalendarioMensual extends State<_CalendarioMensual> {
  late DateTime _mesMostrado;

  // Los meses en español, como los dicen todos. Se evita cargar el formatter
  // con locale porque acá alcanza con esta lista fija.
  static const _nombresDeMeses = [
    'ENERO', 'FEBRERO', 'MARZO', 'ABRIL', 'MAYO', 'JUNIO',
    'JULIO', 'AGOSTO', 'SEPTIEMBRE', 'OCTUBRE', 'NOVIEMBRE', 'DICIEMBRE',
  ];

  @override
  void initState() {
    super.initState();
    final hoy = DateTime.now();
    _mesMostrado = DateTime(hoy.year, hoy.month, 1);
  }

  void _mesAnterior() {
    setState(() {
      _mesMostrado = DateTime(_mesMostrado.year, _mesMostrado.month - 1, 1);
    });
  }

  void _mesSiguiente() {
    setState(() {
      _mesMostrado = DateTime(_mesMostrado.year, _mesMostrado.month + 1, 1);
    });
  }

  @override
  Widget build(BuildContext context) {
    // Lunes es 1 en DateTime.weekday, entonces para que la columna 0 sea
    // lunes restamos (weekday - 1) días al primer día del mes.
    final primerDiaMes = DateTime(_mesMostrado.year, _mesMostrado.month, 1);
    final primerDiaCuadricula =
        primerDiaMes.subtract(Duration(days: primerDiaMes.weekday - 1));

    final hoy = DateTime.now();
    final hoySimple = DateTime(hoy.year, hoy.month, hoy.day);

    final colorTrabajo =
        widget.ciclo.esDeDia ? Colores.dorado : Colores.azulOscuro;

    return Container(
      decoration: BoxDecoration(
        color: Colores.superficie,
        borderRadius: BorderRadius.circular(Medidas.redondeo),
        border: Border.all(color: Colores.linea),
      ),
      child: Column(
        children: [
          // Encabezado con el nombre del mes y las flechas para navegar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: Row(
              children: [
                IconButton(
                  onPressed: _mesAnterior,
                  icon: const Icon(Icons.chevron_left_rounded),
                  tooltip: 'Mes anterior',
                ),
                Expanded(
                  child: Center(
                    child: Text(
                      '${_nombresDeMeses[_mesMostrado.month - 1]} '
                      '${_mesMostrado.year}',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8,
                        color: Colores.texto,
                      ),
                    ),
                  ),
                ),
                IconButton(
                  onPressed: _mesSiguiente,
                  icon: const Icon(Icons.chevron_right_rounded),
                  tooltip: 'Mes siguiente',
                ),
              ],
            ),
          ),

          // Fila con los días de la semana
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: const BoxDecoration(
              border: Border(
                top: BorderSide(color: Colores.linea),
                bottom: BorderSide(color: Colores.linea),
              ),
            ),
            child: const Row(
              children: [
                _HeaderDiaSemana('Lun'),
                _HeaderDiaSemana('Mar'),
                _HeaderDiaSemana('Mié'),
                _HeaderDiaSemana('Jue'),
                _HeaderDiaSemana('Vie'),
                _HeaderDiaSemana('Sáb'),
                _HeaderDiaSemana('Dom'),
              ],
            ),
          ),

          // Las seis filas de la cuadrícula (42 celdas fijas: así el calendario
          // no cambia de alto al pasar de mes, que si no da un saltito feo).
          for (var semana = 0; semana < 6; semana++)
            Row(
              children: [
                for (var dia = 0; dia < 7; dia++)
                  _CeldaDelDia(
                    fecha: primerDiaCuadricula
                        .add(Duration(days: semana * 7 + dia)),
                    mesMostrado: _mesMostrado.month,
                    ciclo: widget.ciclo,
                    colorTrabajo: colorTrabajo,
                    esHoy: _esMismoDia(
                      primerDiaCuadricula
                          .add(Duration(days: semana * 7 + dia)),
                      hoySimple,
                    ),
                  ),
              ],
            ),
          const SizedBox(height: 6),
        ],
      ),
    );
  }

  static bool _esMismoDia(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

class _HeaderDiaSemana extends StatelessWidget {
  const _HeaderDiaSemana(this.texto);
  final String texto;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Center(
        child: Text(
          texto,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            color: Colores.textoSuave,
            letterSpacing: 0.7,
          ),
        ),
      ),
    );
  }
}

class _CeldaDelDia extends StatelessWidget {
  const _CeldaDelDia({
    required this.fecha,
    required this.mesMostrado,
    required this.ciclo,
    required this.colorTrabajo,
    required this.esHoy,
  });

  final DateTime fecha;
  final int mesMostrado;
  final CicloDeTurno ciclo;
  final Color colorTrabajo;
  final bool esHoy;

  @override
  Widget build(BuildContext context) {
    final esDelMes = fecha.month == mesMostrado;
    final trabaja = ciclo.estaDeTrabajo(fecha);

    // Los días que son del mes de al lado (para rellenar la cuadrícula) se
    // muestran más apagados: están, pero son del mes vecino.
    final Color colorFondo;
    final Color colorTexto;

    if (!esDelMes) {
      colorFondo = Colores.fondo;
      colorTexto = Colores.textoTenue;
    } else if (trabaja) {
      colorFondo = colorTrabajo;
      colorTexto = Colors.white;
    } else {
      colorFondo = Colores.superficie;
      colorTexto = Colores.texto;
    }

    return Expanded(
      child: Container(
        height: 46,
        margin: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: colorFondo,
          borderRadius: BorderRadius.circular(8),
          border: esHoy ? Border.all(color: Colores.rojo, width: 2) : null,
        ),
        child: Center(
          child: Text(
            '${fecha.day}',
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: esHoy || trabaja ? FontWeight.w800 : FontWeight.w600,
              color: colorTexto,
            ),
          ),
        ),
      ),
    );
  }
}

class _Leyenda extends StatelessWidget {
  const _Leyenda({required this.ciclo});

  final CicloDeTurno ciclo;

  @override
  Widget build(BuildContext context) {
    final colorTrabajo =
        ciclo.esDeDia ? Colores.dorado : Colores.azulOscuro;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _ItemLeyenda(color: colorTrabajo, texto: 'Trabajás'),
        const SizedBox(width: 18),
        _ItemLeyenda(color: Colores.superficie, texto: 'Descansás', borde: true),
        const SizedBox(width: 18),
        _ItemLeyenda(color: Colores.superficie, texto: 'Hoy', bordeRojo: true),
      ],
    );
  }
}

class _ItemLeyenda extends StatelessWidget {
  const _ItemLeyenda({
    required this.color,
    required this.texto,
    this.borde = false,
    this.bordeRojo = false,
  });

  final Color color;
  final String texto;
  final bool borde;
  final bool bordeRojo;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(5),
            border: bordeRojo
                ? Border.all(color: Colores.rojo, width: 2)
                : borde
                    ? Border.all(color: Colores.linea)
                    : null,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          texto,
          style: const TextStyle(
            fontSize: 12,
            color: Colores.textoSuave,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

// ============================================================================
// WIDGETS AUXILIARES
// ============================================================================

class _BotonTurno extends StatelessWidget {
  const _BotonTurno({
    required this.texto,
    required this.icono,
    required this.elegido,
    required this.alTocar,
  });

  final String texto;
  final IconData icono;
  final bool elegido;
  final VoidCallback alTocar;

  @override
  Widget build(BuildContext context) {
    return Material(
      color:
          elegido ? Colores.grafito : Colores.grafito.withValues(alpha: 0.05),
      borderRadius: BorderRadius.circular(Medidas.redondeo),
      child: InkWell(
        onTap: alTocar,
        borderRadius: BorderRadius.circular(Medidas.redondeo),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 18),
          child: Column(
            children: [
              Icon(
                icono,
                size: 26,
                color: elegido ? Colors.white : Colores.textoSuave,
              ),
              const SizedBox(height: 6),
              Text(
                texto,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: elegido ? Colors.white : Colores.textoSuave,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ErrorDeCarga extends StatelessWidget {
  const _ErrorDeCarga({required this.falla});

  final ErrorAmigable falla;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(Medidas.margen),
      child: AvisoDeError(problema: falla),
    );
  }
}
