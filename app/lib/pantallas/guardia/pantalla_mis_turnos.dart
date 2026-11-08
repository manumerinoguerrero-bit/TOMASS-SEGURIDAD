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

        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('PRÓXIMOS 30 DÍAS',
                style: Theme.of(context).textTheme.labelSmall),
            _ChipLeyenda(ciclo: ciclo),
          ],
        ),
        const SizedBox(height: 10),
        _Lista30Dias(ciclo: ciclo),
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

class _ChipLeyenda extends StatelessWidget {
  const _ChipLeyenda({required this.ciclo});

  final CicloDeTurno ciclo;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _puntito(Colores.verde),
        const SizedBox(width: 4),
        const Text('trabajo',
            style: TextStyle(fontSize: 11, color: Colores.textoSuave)),
        const SizedBox(width: 10),
        _puntito(Colores.textoTenue),
        const SizedBox(width: 4),
        const Text('descanso',
            style: TextStyle(fontSize: 11, color: Colores.textoSuave)),
      ],
    );
  }

  Widget _puntito(Color color) => Container(
        width: 9,
        height: 9,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      );
}

class _Lista30Dias extends StatelessWidget {
  const _Lista30Dias({required this.ciclo});

  final CicloDeTurno ciclo;

  @override
  Widget build(BuildContext context) {
    final hoy = DateTime.now();
    final base = DateTime(hoy.year, hoy.month, hoy.day);

    return Container(
      decoration: BoxDecoration(
        color: Colores.superficie,
        borderRadius: BorderRadius.circular(Medidas.redondeo),
        border: Border.all(color: Colores.linea),
      ),
      child: Column(
        children: [
          for (var i = 0; i < 30; i++)
            _FilaDia(
              dia: base.add(Duration(days: i)),
              esTrabajo: ciclo.estaDeTrabajo(base.add(Duration(days: i))),
              esHoy: i == 0,
              esUltima: i == 29,
            ),
        ],
      ),
    );
  }
}

class _FilaDia extends StatelessWidget {
  const _FilaDia({
    required this.dia,
    required this.esTrabajo,
    required this.esHoy,
    required this.esUltima,
  });

  final DateTime dia;
  final bool esTrabajo;
  final bool esHoy;
  final bool esUltima;

  @override
  Widget build(BuildContext context) {
    final color = esTrabajo ? Colores.verde : Colores.textoTenue;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        border: esUltima
            ? null
            : const Border(
                bottom: BorderSide(color: Colores.linea, width: 1),
              ),
      ),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              esHoy
                  ? 'HOY · ${Formato.diaCompleto(dia)}'
                  : Formato.diaCompleto(dia),
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: esHoy ? FontWeight.w800 : FontWeight.w600,
                color: Colores.texto,
              ),
            ),
          ),
          Text(
            esTrabajo ? 'Trabajo' : 'Descanso',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: color,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
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
