// ============================================================================
// Tomass Seguridad — Registrar a alguien que llegó sin aviso
// ============================================================================
// El guardia tiene a la persona PARADA ADELANTE. Cada segundo que tarda es la
// visita esperando en el portón y, si es en auto, un auto trabando la entrada.
//
// Por eso el formulario pide lo mínimo indispensable y nada más:
//
//   a quién viene a ver  → obligatorio, es a quien se le pide permiso
//   nombre               → obligatorio, es lo que el residente necesita saber
//   patente              → si viene en auto
//   qué dice que viene a hacer → ayuda al residente a decidir
//
// El RUT queda OPCIONAL acá, al revés que en los colegios. Es a propósito: en un
// condominio la decisión la toma el residente, que conoce a la persona por el
// nombre. Pedirle el carnet a la visita mientras el residente ya contestó que sí
// solo agrega demora.
// ============================================================================

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/tema.dart';
import '../../estado/proveedores.dart';
import '../../estado/proveedores_guardia.dart';
import '../../nucleo/errores.dart';
import '../comunes/componentes.dart';

void abrirFormularioDeVisita(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colores.superficie,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => const _Formulario(),
  );
}

class _Formulario extends ConsumerStatefulWidget {
  const _Formulario();

  @override
  ConsumerState<_Formulario> createState() => _EstadoFormulario();
}

class _EstadoFormulario extends ConsumerState<_Formulario> {
  final _busqueda = TextEditingController();
  final _nombre = TextEditingController();
  final _cedula = TextEditingController();
  final _patente = TextEditingController();
  final _motivo = TextEditingController();

  Map<String, dynamic>? _aQuienVaAVer;
  List<Map<String, dynamic>> _encontrados = const [];
  bool _buscando = false;
  bool _llamoPorTelefono = false;
  bool _guardando = false;
  ErrorAmigable? _problema;
  Timer? _esperaParaBuscar;

  @override
  void dispose() {
    _esperaParaBuscar?.cancel();
    _busqueda.dispose();
    _nombre.dispose();
    _cedula.dispose();
    _patente.dispose();
    _motivo.dispose();
    super.dispose();
  }

  /// Se espera medio segundo antes de buscar.
  ///
  /// Sin esto, escribir "Gonzalez" manda ocho consultas al servidor, una por
  /// letra. Con el guardia apurado escribiendo rápido, eso es lento y gasta
  /// datos del celular al vacío.
  void _alEscribir(String texto) {
    _esperaParaBuscar?.cancel();
    if (texto.trim().length < 2) {
      setState(() => _encontrados = const []);
      return;
    }
    _esperaParaBuscar = Timer(const Duration(milliseconds: 500), () async {
      setState(() => _buscando = true);
      try {
        final r = await ref
            .read(servicioGuardiaProvider)
            .buscarAQuienAvisar(texto);
        if (mounted) setState(() => _encontrados = r);
      } catch (_) {
        // Una búsqueda que falla no vale un cartel de error: se reintenta con
        // la próxima letra.
      } finally {
        if (mounted) setState(() => _buscando = false);
      }
    });
  }

  Future<void> _pedirAutorizacion() async {
    if (_aQuienVaAVer == null) {
      setState(() => _problema = const ErrorAmigable(
            'Falta elegir a quién viene a ver.',
            detalle: 'Es la persona a la que se le va a pedir permiso.',
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
      await ref.read(servicioGuardiaProvider).pedirAutorizacionDeVisita(
            residenteId: _aQuienVaAVer!['id'] as String,
            nombre: _nombre.text,
            cedula: _cedula.text,
            patente: _patente.text,
            motivo: _motivo.text,
            llamoPorTelefono: _llamoPorTelefono,
          );

      if (!mounted) return;
      ref.invalidate(visitasEsperandoProvider);
      Navigator.pop(context);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Aviso enviado a '
              '${_aQuienVaAVer!['nombre_completo']}. Te va a aparecer acá '
              'cuando conteste.'),
          backgroundColor: Colores.verde,
          duration: const Duration(seconds: 4),
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
    final palabras = ref.watch(palabrasProvider);

    return Padding(
      padding: EdgeInsets.only(
        left: Medidas.margen,
        right: Medidas.margen,
        top: Medidas.margen,
        bottom: MediaQuery.viewInsetsOf(context).bottom + Medidas.margen,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colores.linea,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text('Alguien llegó sin aviso',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              'Se le va a pedir permiso al ${palabras.elHabitante} en su '
              'celular. La respuesta queda guardada con la hora.',
              style: const TextStyle(
                  fontSize: 12.5, height: 1.45, color: Colores.textoSuave),
            ),
            const SizedBox(height: 18),

            if (_problema != null) ...[
              AvisoDeError(problema: _problema!),
              const SizedBox(height: 14),
            ],

            // ---- 1. A QUIÉN VIENE A VER ----
            Text('1 · A QUIÉN VIENE A VER',
                style: Theme.of(context).textTheme.labelSmall),
            const SizedBox(height: 8),

            if (_aQuienVaAVer == null) ...[
              TextField(
                controller: _busqueda,
                onChanged: _alEscribir,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  hintText: 'Buscar por nombre…',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _buscando
                      ? const Padding(
                          padding: EdgeInsets.all(13),
                          child: SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : null,
                ),
              ),
              if (_encontrados.isNotEmpty) ...[
                const SizedBox(height: 8),
                for (final r in _encontrados)
                  Card(
                    margin: const EdgeInsets.only(bottom: 5),
                    child: ListTile(
                      dense: true,
                      onTap: () => setState(() {
                        _aQuienVaAVer = r;
                        _encontrados = const [];
                      }),
                      leading: Avatar(
                          iniciales: _iniciales(
                              (r['nombre_completo'] ?? '?') as String),
                          tamano: 34),
                      title: Text(r['nombre_completo'] as String,
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w600)),
                      subtitle: Text(
                        _espacioDe(r) ??
                            'Sin ${palabras.elEspacio} asignada',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ),
              ],
            ] else
              Card(
                margin: EdgeInsets.zero,
                color: Colores.verde.withValues(alpha: 0.07),
                child: ListTile(
                  leading: const Icon(Icons.check_circle_rounded,
                      color: Colores.verdeOscuro),
                  title: Text(_aQuienVaAVer!['nombre_completo'] as String,
                      style: const TextStyle(
                          fontSize: 14.5, fontWeight: FontWeight.w700)),
                  subtitle: Text(_espacioDe(_aQuienVaAVer!) ?? '—',
                      style: const TextStyle(fontSize: 12)),
                  trailing: TextButton(
                    onPressed: () => setState(() {
                      _aQuienVaAVer = null;
                      _busqueda.clear();
                    }),
                    child: const Text('Cambiar'),
                  ),
                ),
              ),

            const SizedBox(height: 18),

            // ---- 2. QUIÉN ES LA VISITA ----
            Text('2 · QUIÉN ES LA VISITA',
                style: Theme.of(context).textTheme.labelSmall),
            const SizedBox(height: 8),

            TextField(
              controller: _nombre,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Nombre',
                prefixIcon: Icon(Icons.person_outline_rounded),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _patente,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(
                      labelText: 'Patente',
                      hintText: 'Si viene en auto',
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _cedula,
                    decoration: const InputDecoration(
                      labelText: 'RUT',
                      hintText: 'Opcional',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _motivo,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: '¿Qué dice que viene a hacer?',
                hintText: 'Ej: viene a dejar un mueble',
                prefixIcon: Icon(Icons.chat_bubble_outline_rounded),
                helperText: 'Ayuda al residente a decidir',
              ),
            ),

            const SizedBox(height: 16),

            // ---- 3. SI ADEMÁS LO LLAMÓ ----
            CheckboxListTile(
              value: _llamoPorTelefono,
              onChanged: (v) => setState(() => _llamoPorTelefono = v ?? false),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text('Además lo llamé por teléfono y me dijo que sí',
                  style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
              subtitle: const Text(
                'Queda anotado. No reemplaza la respuesta desde la app, pero '
                'sirve si el residente no contesta el celular.',
                style: TextStyle(fontSize: 11.5, height: 1.35),
              ),
            ),

            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _guardando ? null : _pedirAutorizacion,
                style: FilledButton.styleFrom(
                  backgroundColor: Colores.grafito,
                  minimumSize: const Size(0, Medidas.altoBotonGigante),
                ),
                icon: _guardando
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                            strokeWidth: 2.5, color: Colors.white))
                    : const Icon(Icons.notifications_active_rounded, size: 24),
                label: Text(
                  _guardando ? 'Enviando…' : 'Pedir autorización',
                  style: const TextStyle(
                      fontSize: 16.5, fontWeight: FontWeight.w800),
                ),
              ),
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  static String? _espacioDe(Map<String, dynamic> r) {
    final u = r['unidades'];
    if (u is! Map) return null;
    final t = [u['numero'], u['torre']]
        .where((p) => p != null && p.toString().isNotEmpty)
        .join(' ');
    return t.isEmpty ? null : t;
  }

  static String _iniciales(String nombre) {
    final partes = nombre.trim().split(RegExp(r'\s+'));
    if (partes.isEmpty || partes.first.isEmpty) return '?';
    if (partes.length == 1) return partes.first[0].toUpperCase();
    return '${partes[0][0]}${partes[1][0]}'.toUpperCase();
  }
}
