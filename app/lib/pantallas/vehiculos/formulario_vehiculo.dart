// ============================================================================
// Tomass Seguridad — Registrar un vehículo
// ============================================================================
// EL ORDEN DE LOS PASOS ESTÁ PENSADO
//
//   Primero la foto de la patente, porque de ahí la app saca la patente sola. Si
//   se pidiera escribirla primero, el residente ya habría hecho el trabajo que la
//   cámara podía hacer por él.
//
// SIEMPRE SE LE PIDE CONFIRMAR LO QUE SE LEYÓ
//   Ninguna lectura automática acierta el 100% de las veces, y una patente mal
//   cargada significa que el auto no entra y que el residente discute con el
//   guardia sin entender por qué. Confirmar 6 caracteres cuesta dos segundos.
// ============================================================================

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/tema.dart';
import '../../estado/proveedores.dart';
import '../../modelos/modelos.dart';
import '../../nucleo/errores.dart';
import '../../servicios/servicio_fotos.dart';
import '../comunes/componentes.dart';

class FormularioVehiculo extends ConsumerStatefulWidget {
  const FormularioVehiculo({super.key});

  @override
  ConsumerState<FormularioVehiculo> createState() => _EstadoFormulario();
}

class _EstadoFormulario extends ConsumerState<FormularioVehiculo> {
  final _formulario = GlobalKey<FormState>();
  final _patente = TextEditingController();
  final _marca = TextEditingController();
  final _modelo = TextEditingController();
  final _color = TextEditingController();
  final _anio = TextEditingController();

  File? _fotoPatente;
  File? _fotoVehiculo;

  bool _leyendoPatente = false;
  bool _guardando = false;
  ErrorAmigable? _problema;

  /// Qué avisar sobre la lectura automática: si acertó, si conviene revisar, o
  /// si no encontró nada.
  String? _avisoDeLectura;
  bool _lecturaConfiable = false;

  @override
  void dispose() {
    _patente.dispose();
    _marca.dispose();
    _modelo.dispose();
    _color.dispose();
    _anio.dispose();
    super.dispose();
  }

  // --------------------------------------------------------------------------
  // Paso 1: la foto de la patente, y la lectura automática
  // --------------------------------------------------------------------------
  Future<void> _fotografiarPatente() async {
    setState(() => _problema = null);

    try {
      // Con la mejor calidad: de esta foto el lector saca la patente sola.
      final foto = await ref.read(servicioFotosProvider).sacarFoto(
            proposito: PropositoDeLaFoto.leerLaPatente,
          );
      if (foto == null) return;

      setState(() {
        _fotoPatente = foto;
        _leyendoPatente = true;
        _avisoDeLectura = null;
      });

      final leida = await ref.read(lectorDePatentesProvider).leer(foto);
      if (!mounted) return;

      setState(() {
        _leyendoPatente = false;
        if (leida == null) {
          _avisoDeLectura =
              'No pudimos leer la patente de esa foto. Escribila a mano abajo.';
          _lecturaConfiable = false;
        } else {
          _patente.text = leida.patente;
          _lecturaConfiable = leida.esConfiable;
          _avisoDeLectura = leida.esConfiable
              ? 'Leímos ${leida.patente}. Revisá que esté bien.'
              : 'Creemos que dice ${leida.patente}, pero no estamos seguros. '
                  'Revisala con cuidado.';
        }
      });
    } catch (falla) {
      if (!mounted) return;
      setState(() {
        _leyendoPatente = false;
        _problema = Traductor.traducir(falla);
      });
    }
  }

  Future<void> _fotografiarVehiculo() async {
    setState(() => _problema = null);
    try {
      final foto = await ref.read(servicioFotosProvider).sacarFoto(
            proposito: PropositoDeLaFoto.elVehiculo,
          );
      if (foto != null && mounted) setState(() => _fotoVehiculo = foto);
    } catch (falla) {
      if (mounted) setState(() => _problema = Traductor.traducir(falla));
    }
  }

  // --------------------------------------------------------------------------
  // Guardar
  // --------------------------------------------------------------------------
  Future<void> _guardar() async {
    if (!_formulario.currentState!.validate()) return;

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
      await ref.read(servicioResidenteProvider).registrarVehiculo(
            condominioId: perfil.condominioId,
            patente: _patente.text,
            marca: _marca.text,
            modelo: _modelo.text,
            color: _color.text,
            anio: int.tryParse(_anio.text.trim()),
            fotoDeLaPatente: _fotoPatente,
            fotoDelVehiculo: _fotoVehiculo,
          );

      ref.invalidate(misVehiculosProvider);
      if (!mounted) return;

      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Registramos el ${FormatoPatente.normalizar(_patente.text)}. '
            'La administración lo va a revisar.',
          ),
          duration: const Duration(seconds: 5),
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
    return Scaffold(
      appBar: AppBar(title: const Text('Agregar un vehículo')),
      body: Form(
        key: _formulario,
        child: ListView(
          padding: const EdgeInsets.all(Medidas.margen),
          children: [
            if (_problema != null) ...[
              AvisoDeError(problema: _problema!),
              const SizedBox(height: 16),
            ],

            // ---- Paso 1 ----
            const _Paso(
              numero: '1',
              titulo: 'Foto de la patente',
              explicacion: 'La app la lee sola de la foto.',
            ),
            const SizedBox(height: 10),
            _RecuadroDeFoto(
              archivo: _fotoPatente,
              cargando: _leyendoPatente,
              textoVacio: 'Tocá para fotografiar la patente',
              textoCargando: 'Leyendo la patente…',
              icono: Icons.pin_rounded,
              alto: 128,
              alTocar: _guardando ? null : _fotografiarPatente,
            ),
            if (_avisoDeLectura != null) ...[
              const SizedBox(height: 10),
              _AvisoDeLectura(
                texto: _avisoDeLectura!,
                confiable: _lecturaConfiable,
              ),
            ],

            const SizedBox(height: 22),

            // ---- Paso 2 ----
            const _Paso(
              numero: '2',
              titulo: 'Datos del vehículo',
              explicacion: 'Revisá la patente y completá el resto.',
            ),
            const SizedBox(height: 10),
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
                labelText: 'Patente',
                hintText: 'BCDF-12',
                prefixIcon: Icon(Icons.confirmation_number_outlined),
              ),
              style: const TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.6,
              ),
              validator: FormatoPatente.mensajeSiEstaMal,
            ),
            const SizedBox(height: 11),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _marca,
                    enabled: !_guardando,
                    textCapitalization: TextCapitalization.words,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Marca',
                      hintText: 'Toyota',
                    ),
                    validator: (v) =>
                        (v ?? '').trim().isEmpty ? 'Escribí la marca.' : null,
                  ),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: TextFormField(
                    controller: _modelo,
                    enabled: !_guardando,
                    textCapitalization: TextCapitalization.words,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Modelo',
                      hintText: 'Corolla',
                    ),
                    validator: (v) =>
                        (v ?? '').trim().isEmpty ? 'Escribí el modelo.' : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 11),
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: TextFormField(
                    controller: _color,
                    enabled: !_guardando,
                    textCapitalization: TextCapitalization.words,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Color',
                      hintText: 'Blanco',
                    ),
                    validator: (v) =>
                        (v ?? '').trim().isEmpty ? 'Escribí el color.' : null,
                  ),
                ),
                const SizedBox(width: 11),
                Expanded(
                  flex: 2,
                  child: TextFormField(
                    controller: _anio,
                    enabled: !_guardando,
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.done,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(4),
                    ],
                    decoration: const InputDecoration(
                      labelText: 'Año',
                      hintText: '2021',
                    ),
                    validator: (v) {
                      final texto = (v ?? '').trim();
                      if (texto.isEmpty) return null; // es opcional
                      final anio = int.tryParse(texto);
                      final ahora = DateTime.now().year;
                      if (anio == null || anio < 1950 || anio > ahora + 1) {
                        return 'Año inválido.';
                      }
                      return null;
                    },
                  ),
                ),
              ],
            ),

            const SizedBox(height: 22),

            // ---- Paso 3 ----
            const _Paso(
              numero: '3',
              titulo: 'Foto del vehículo',
              explicacion: 'Opcional, pero le sirve al guardia para reconocerlo '
                  'de lejos.',
            ),
            const SizedBox(height: 10),
            _RecuadroDeFoto(
              archivo: _fotoVehiculo,
              textoVacio: 'Tocá para fotografiar el vehículo',
              icono: Icons.directions_car_outlined,
              alto: 148,
              alTocar: _guardando ? null : _fotografiarVehiculo,
            ),

            const SizedBox(height: 26),

            Container(
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(
                color: Colores.naranja.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(Medidas.redondeoChico),
                border: Border.all(
                  color: Colores.naranja.withValues(alpha: 0.35),
                ),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline_rounded,
                      size: 19, color: Colores.naranjaOscuro),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'El vehículo queda pendiente hasta que la administración lo '
                      'apruebe. Recién entonces sirve para entrar por la barrera.',
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.45,
                        color: Colores.naranjaOscuro,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 18),

            ElevatedButton(
              onPressed: _guardando ? null : _guardar,
              child: _guardando
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Enviar para aprobación'),
            ),
            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// Piezas de este formulario
// ============================================================================

class _Paso extends StatelessWidget {
  const _Paso({
    required this.numero,
    required this.titulo,
    required this.explicacion,
  });

  final String numero;
  final String titulo;
  final String explicacion;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 24,
          height: 24,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            color: Colores.grafito,
            shape: BoxShape.circle,
          ),
          child: Text(
            numero,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(titulo, style: Theme.of(context).textTheme.titleMedium),
              Text(
                explicacion,
                style: const TextStyle(
                  fontSize: 12.5,
                  color: Colores.textoSuave,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _RecuadroDeFoto extends StatelessWidget {
  const _RecuadroDeFoto({
    required this.archivo,
    required this.textoVacio,
    required this.icono,
    required this.alto,
    required this.alTocar,
    this.cargando = false,
    this.textoCargando,
  });

  final File? archivo;
  final String textoVacio;
  final IconData icono;
  final double alto;
  final VoidCallback? alTocar;
  final bool cargando;
  final String? textoCargando;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: alTocar,
      child: Container(
        height: alto,
        width: double.infinity,
        decoration: BoxDecoration(
          color: Colores.grafito.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(Medidas.redondeo),
          border: Border.all(
            color: archivo == null
                ? Colores.grafito.withValues(alpha: 0.28)
                : Colores.verde,
            width: archivo == null ? 1 : 1.5,
            strokeAlign: BorderSide.strokeAlignInside,
          ),
        ),
        child: cargando
            ? Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(color: Colores.grafito),
                  const SizedBox(height: 12),
                  Text(
                    textoCargando ?? 'Cargando…',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colores.textoSuave,
                    ),
                  ),
                ],
              )
            : archivo == null
                ? Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(icono, size: 28, color: Colores.textoSuave),
                      const SizedBox(height: 9),
                      Text(
                        textoVacio,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colores.textoSuave,
                        ),
                      ),
                    ],
                  )
                : Stack(
                    fit: StackFit.expand,
                    children: [
                      ClipRRect(
                        borderRadius:
                            BorderRadius.circular(Medidas.redondeo - 1),
                        child: Image.file(archivo!, fit: BoxFit.cover),
                      ),
                      Positioned(
                        right: 8,
                        bottom: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 11, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.65),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Row(
                            children: [
                              Icon(Icons.refresh_rounded,
                                  size: 14, color: Colors.white),
                              SizedBox(width: 5),
                              Text(
                                'Cambiar',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
      ),
    );
  }
}

class _AvisoDeLectura extends StatelessWidget {
  const _AvisoDeLectura({required this.texto, required this.confiable});

  final String texto;
  final bool confiable;

  @override
  Widget build(BuildContext context) {
    final color = confiable ? Colores.verde : Colores.naranja;
    final letra = confiable ? Colores.verdeOscuro : Colores.naranjaOscuro;

    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(Medidas.redondeoChico),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(
            confiable ? Icons.auto_awesome_rounded : Icons.warning_amber_rounded,
            size: 18,
            color: letra,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              texto,
              style: TextStyle(fontSize: 12.5, height: 1.4, color: letra),
            ),
          ),
        ],
      ),
    );
  }
}

/// Convierte a mayúsculas lo que se escribe en el campo de la patente.
class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue anterior,
    TextEditingValue nuevo,
  ) {
    return TextEditingValue(
      text: nuevo.text.toUpperCase(),
      selection: nuevo.selection,
    );
  }
}
