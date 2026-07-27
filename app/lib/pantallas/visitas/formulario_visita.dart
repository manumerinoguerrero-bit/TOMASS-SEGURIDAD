// ============================================================================
// Tomass Seguridad — Invitar a un visitante
// ============================================================================
// EL HORARIO VIENE PRELLENADO, A PROPÓSITO
//   Arranca en "hoy, desde ahora, hasta las 23:00". Es lo que pasa el 80% de las
//   veces: alguien avisa que va a venir en un rato. Así el residente toca dos
//   campos y manda el código, en lugar de pelearse con cuatro selectores.
//
// EL CÓDIGO LO GENERA LA BASE DE DATOS, NO LA APP
//   Si lo generara la app, alguien podría modificarla para fabricar códigos
//   válidos. Acá la app manda los datos y el servidor devuelve el código.
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/tema.dart';
import '../../estado/proveedores.dart';
import '../../modelos/modelos.dart';
import '../../nucleo/errores.dart';
import '../../nucleo/formato.dart';
import '../comunes/componentes.dart';
import '../vehiculos/formulario_vehiculo.dart' show UpperCaseTextFormatter;
import 'tarjeta_codigo_visita.dart';

class FormularioVisita extends ConsumerStatefulWidget {
  const FormularioVisita({super.key});

  @override
  ConsumerState<FormularioVisita> createState() => _EstadoFormularioVisita();
}

class _EstadoFormularioVisita extends ConsumerState<FormularioVisita> {
  final _formulario = GlobalKey<FormState>();
  final _nombre = TextEditingController();
  final _cedula = TextEditingController();
  final _telefono = TextEditingController();
  final _patente = TextEditingController();
  final _motivo = TextEditingController();

  late DateTime _desde;
  late DateTime _hasta;

  bool _vieneEnAuto = false;
  bool _guardando = false;
  ErrorAmigable? _problema;

  @override
  void initState() {
    super.initState();
    // Lo más común: viene hoy, en un rato, y se va antes de medianoche
    final ahora = DateTime.now();
    _desde = ahora;
    _hasta = DateTime(ahora.year, ahora.month, ahora.day, 23, 0);
    // Si ya pasaron las 23:00, se extiende hasta las 2 de la mañana
    if (_hasta.isBefore(ahora.add(const Duration(hours: 1)))) {
      _hasta = ahora.add(const Duration(hours: 3));
    }
  }

  @override
  void dispose() {
    _nombre.dispose();
    _cedula.dispose();
    _telefono.dispose();
    _patente.dispose();
    _motivo.dispose();
    super.dispose();
  }

  Future<void> _elegirCuando({required bool esDesde}) async {
    final actual = esDesde ? _desde : _hasta;

    final fecha = await showDatePicker(
      context: context,
      initialDate: actual,
      firstDate: DateTime.now().subtract(const Duration(minutes: 5)),
      lastDate: DateTime.now().add(const Duration(days: 90)),
      helpText: esDesde ? 'Desde qué día sirve' : 'Hasta qué día sirve',
      cancelText: 'Cancelar',
      confirmText: 'Listo',
      locale: const Locale('es'),
    );
    if (fecha == null || !mounted) return;

    final hora = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(actual),
      helpText: esDesde ? 'Desde qué hora' : 'Hasta qué hora',
      cancelText: 'Cancelar',
      confirmText: 'Listo',
    );
    if (hora == null || !mounted) return;

    final elegido = DateTime(
      fecha.year,
      fecha.month,
      fecha.day,
      hora.hour,
      hora.minute,
    );

    setState(() {
      if (esDesde) {
        _desde = elegido;
        // Si el "desde" pasó al "hasta", se corre el hasta 3 horas después
        if (_hasta.isBefore(_desde.add(const Duration(minutes: 15)))) {
          _hasta = _desde.add(const Duration(hours: 3));
        }
      } else {
        _hasta = elegido;
      }
    });
  }

  Future<void> _generar() async {
    if (!_formulario.currentState!.validate()) return;

    if (_hasta.isBefore(_desde.add(const Duration(minutes: 10)))) {
      setState(() => _problema = const ErrorAmigable(
            'El horario no tiene sentido.',
            detalle: 'La visita tiene que durar al menos 10 minutos.',
            sePuedeReintentar: false,
          ));
      return;
    }

    final perfil = ref.read(perfilProvider).valueOrNull;
    if (perfil == null) {
      setState(() => _problema = const ErrorAmigable(
            'Todavía se están cargando tus datos.',
            detalle: 'Esperá un segundo y volvé a intentar.',
          ));
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() {
      _guardando = true;
      _problema = null;
    });

    try {
      final visita = await ref.read(servicioResidenteProvider).invitarVisitante(
            condominioId: perfil.condominioId,
            unidadId: perfil.unidadId,
            nombreVisitante: _nombre.text,
            validoDesde: _desde,
            validoHasta: _hasta,
            cedula: _cedula.text,
            telefono: _telefono.text,
            patente: _vieneEnAuto ? _patente.text : null,
            motivo: _motivo.text,
          );

      ref.invalidate(misVisitasProvider);
      if (!mounted) return;

      Navigator.of(context).pop();
      // Se abre el código de una para que lo comparta ya mismo: es lo que iba
      // a hacer de todas formas.
      await mostrarCodigoDeVisita(context, ref, visita);
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
    return Scaffold(
      appBar: AppBar(title: const Text('Invitar a alguien')),
      body: Form(
        key: _formulario,
        child: ListView(
          padding: const EdgeInsets.all(Medidas.margen),
          children: [
            if (_problema != null) ...[
              AvisoDeError(problema: _problema!),
              const SizedBox(height: 16),
            ],

            Text('QUIÉN VIENE', style: Theme.of(context).textTheme.labelSmall),
            const SizedBox(height: 10),

            TextFormField(
              controller: _nombre,
              enabled: !_guardando,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Nombre completo',
                hintText: 'María González',
                prefixIcon: Icon(Icons.person_outline_rounded),
              ),
              validator: (v) {
                final texto = (v ?? '').trim();
                if (texto.isEmpty) return 'Escribí el nombre de tu visita.';
                if (texto.length < 3) return 'El nombre parece incompleto.';
                return null;
              },
            ),
            const SizedBox(height: 11),
            TextFormField(
              controller: _cedula,
              enabled: !_guardando,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Cédula',
                hintText: '12.345.678-9',
                helperText: 'El guardia la puede pedir en la garita',
                prefixIcon: Icon(Icons.badge_outlined),
              ),
            ),
            const SizedBox(height: 11),
            TextFormField(
              controller: _telefono,
              enabled: !_guardando,
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Teléfono (opcional)',
                hintText: '+56 9 1234 5678',
                prefixIcon: Icon(Icons.phone_outlined),
              ),
            ),

            const SizedBox(height: 22),
            Text('¿VIENE EN AUTO?', style: Theme.of(context).textTheme.labelSmall),
            const SizedBox(height: 6),

            SwitchListTile.adaptive(
              value: _vieneEnAuto,
              onChanged: _guardando
                  ? null
                  : (valor) => setState(() => _vieneEnAuto = valor),
              activeThumbColor: Colores.grafito,
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'Sí, viene en auto',
                style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600),
              ),
              subtitle: const Text(
                'El guardia va a comparar la patente con la del auto',
                style: TextStyle(fontSize: 12.5, color: Colores.textoSuave),
              ),
            ),

            if (_vieneEnAuto) ...[
              const SizedBox(height: 6),
              TextFormField(
                controller: _patente,
                enabled: !_guardando,
                textCapitalization: TextCapitalization.characters,
                textInputAction: TextInputAction.next,
                inputFormatters: [
                  UpperCaseTextFormatter(),
                  LengthLimitingTextInputFormatter(8),
                ],
                decoration: const InputDecoration(
                  labelText: 'Patente del auto',
                  hintText: 'BCDF-12',
                  prefixIcon: Icon(Icons.directions_car_outlined),
                ),
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.4,
                ),
                validator: (v) =>
                    _vieneEnAuto ? FormatoPatente.mensajeSiEstaMal(v) : null,
              ),
            ],

            const SizedBox(height: 22),
            Text('CUÁNDO SIRVE EL CÓDIGO',
                style: Theme.of(context).textTheme.labelSmall),
            const SizedBox(height: 10),

            _SelectorDeCuando(
              etiqueta: 'Desde',
              cuando: _desde,
              alTocar: _guardando ? null : () => _elegirCuando(esDesde: true),
            ),
            const SizedBox(height: 9),
            _SelectorDeCuando(
              etiqueta: 'Hasta',
              cuando: _hasta,
              alTocar: _guardando ? null : () => _elegirCuando(esDesde: false),
            ),

            const SizedBox(height: 22),
            TextFormField(
              controller: _motivo,
              enabled: !_guardando,
              maxLength: 80,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(
                labelText: 'Motivo (opcional)',
                hintText: 'Almuerzo familiar',
                prefixIcon: Icon(Icons.notes_rounded),
              ),
            ),

            const SizedBox(height: 8),

            Container(
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(
                color: Colores.grafito.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(Medidas.redondeoChico),
                border: Border.all(color: Colores.linea),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.lock_outline_rounded,
                      size: 18, color: Colores.grafito),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'El código sirve UNA sola vez y solo en el horario que '
                      'elegiste. Después se apaga solo. Queda registrado que vos '
                      'lo invitaste.',
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.45,
                        color: Colores.textoSuave,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 18),

            ElevatedButton.icon(
              onPressed: _guardando ? null : _generar,
              icon: _guardando
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.qr_code_2_rounded, size: 21),
              label: Text(_guardando ? 'Generando…' : 'Generar el código'),
            ),
            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }
}

class _SelectorDeCuando extends StatelessWidget {
  const _SelectorDeCuando({
    required this.etiqueta,
    required this.cuando,
    required this.alTocar,
  });

  final String etiqueta;
  final DateTime cuando;
  final VoidCallback? alTocar;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: alTocar,
      borderRadius: BorderRadius.circular(Medidas.redondeoChico),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: Colores.superficie,
          borderRadius: BorderRadius.circular(Medidas.redondeoChico),
          border: Border.all(color: Colores.linea),
        ),
        child: Row(
          children: [
            const Icon(Icons.schedule_rounded,
                size: 19, color: Colores.textoSuave),
            const SizedBox(width: 12),
            Text(
              etiqueta,
              style: const TextStyle(
                fontSize: 13.5,
                color: Colores.textoSuave,
              ),
            ),
            const Spacer(),
            Text(
              '${Formato.fecha(cuando)}  ${Formato.hora(cuando)}',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(width: 6),
            const Icon(Icons.edit_rounded, size: 15, color: Colores.textoTenue),
          ],
        ),
      ),
    );
  }
}
