// ============================================================================
// Tomass Seguridad — Cambiar la contraseña
// ============================================================================
// Pantalla única para guardias y admin: pide la contraseña actual (para
// evitar que alguien que agarró el celular desbloqueado la cambie) y la
// nueva por duplicado.
//
// Al guardar bien, vuelve a la pantalla anterior con un snackbar de
// confirmación.
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../config/tema.dart';
import '../../estado/proveedores.dart';
import '../../nucleo/errores.dart';
import 'componentes.dart';

class PantallaCambiarClave extends ConsumerStatefulWidget {
  const PantallaCambiarClave({super.key});

  @override
  ConsumerState<PantallaCambiarClave> createState() =>
      _EstadoCambiarClave();
}

class _EstadoCambiarClave extends ConsumerState<PantallaCambiarClave> {
  final _formKey = GlobalKey<FormState>();
  final _actual = TextEditingController();
  final _nueva = TextEditingController();
  final _confirmar = TextEditingController();

  bool _verActual = false;
  bool _verNueva = false;
  bool _trabajando = false;
  ErrorAmigable? _problema;

  @override
  void dispose() {
    _actual.dispose();
    _nueva.dispose();
    _confirmar.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    setState(() => _problema = null);
    if (!_formKey.currentState!.validate()) return;

    setState(() => _trabajando = true);

    try {
      await ref.read(servicioSesionProvider).cambiarContrasena(
            actual: _actual.text,
            nueva: _nueva.text,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Listo. Tu contraseña fue cambiada.'),
          backgroundColor: Colores.verde,
        ),
      );
      context.pop();
    } catch (falla) {
      if (!mounted) return;
      setState(() {
        _trabajando = false;
        _problema = Traductor.traducir(falla);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cambiar mi contraseña'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(Medidas.margen),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Elegí una contraseña propia. Hace falta la actual para '
                'confirmar que sos vos.',
                style: TextStyle(
                  fontSize: 13.5,
                  height: 1.45,
                  color: Colores.textoSuave,
                ),
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: _actual,
                obscureText: !_verActual,
                autofillHints: const [AutofillHints.password],
                decoration: InputDecoration(
                  labelText: 'Contraseña actual',
                  prefixIcon: const Icon(Icons.lock_outline_rounded),
                  suffixIcon: IconButton(
                    icon: Icon(_verActual
                        ? Icons.visibility_off_rounded
                        : Icons.visibility_rounded),
                    onPressed: () =>
                        setState(() => _verActual = !_verActual),
                  ),
                  border: const OutlineInputBorder(),
                ),
                validator: (v) => (v == null || v.isEmpty)
                    ? 'Escribí tu contraseña actual.'
                    : null,
                enabled: !_trabajando,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _nueva,
                obscureText: !_verNueva,
                autofillHints: const [AutofillHints.newPassword],
                decoration: InputDecoration(
                  labelText: 'Contraseña nueva',
                  prefixIcon: const Icon(Icons.lock_rounded),
                  helperText: 'Al menos 8 caracteres.',
                  suffixIcon: IconButton(
                    icon: Icon(_verNueva
                        ? Icons.visibility_off_rounded
                        : Icons.visibility_rounded),
                    onPressed: () =>
                        setState(() => _verNueva = !_verNueva),
                  ),
                  border: const OutlineInputBorder(),
                ),
                validator: (v) {
                  if (v == null || v.isEmpty) {
                    return 'Elegí una contraseña nueva.';
                  }
                  if (v.length < 8) {
                    return 'Mínimo 8 caracteres.';
                  }
                  if (v == _actual.text) {
                    return 'Elegí una distinta a la actual.';
                  }
                  return null;
                },
                enabled: !_trabajando,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _confirmar,
                obscureText: !_verNueva,
                autofillHints: const [AutofillHints.newPassword],
                decoration: const InputDecoration(
                  labelText: 'Repetir contraseña nueva',
                  prefixIcon: Icon(Icons.lock_rounded),
                  border: OutlineInputBorder(),
                ),
                validator: (v) => (v != _nueva.text)
                    ? 'Las dos contraseñas no coinciden.'
                    : null,
                enabled: !_trabajando,
              ),
              if (_problema != null) ...[
                const SizedBox(height: 16),
                AvisoDeError(problema: _problema!),
              ],
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _trabajando ? null : _guardar,
                icon: _trabajando
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.check_rounded),
                label: Text(_trabajando ? 'Guardando…' : 'Guardar'),
                style: FilledButton.styleFrom(
                  backgroundColor: Colores.grafito,
                  minimumSize: const Size(0, 46),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
