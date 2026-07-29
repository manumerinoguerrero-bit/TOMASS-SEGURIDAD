// ============================================================================
// Tomass Seguridad — Dar de alta o editar una persona
// ============================================================================
// DOS CAMINOS DISTINTOS, Y LA DIFERENCIA IMPORTA
//
//   DAR DE ALTA pasa por el servidor, porque hay que crearle la cuenta de
//   acceso y eso exige la llave maestra. Al terminar, el servidor devuelve una
//   contraseña provisoria que se muestra UNA sola vez.
//
//   EDITAR va directo a la base de datos, porque solo cambia datos comunes. El
//   correo no se puede editar: es la llave con la que la persona entra, y
//   cambiarlo la dejaría afuera sin aviso.
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/tema.dart';
import '../../estado/proveedores.dart';
import '../../estado/proveedores_admin.dart';
import '../../modelos/admin.dart';
import '../../nucleo/errores.dart';
import '../comunes/componentes.dart';
import 'acciones_admin.dart';

/// Abre la hoja de alta o de edición.
void abrirFormularioDePersona(BuildContext context, {PersonaAdmin? persona}) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colores.superficie,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _Formulario(persona: persona),
  );
}

class _Formulario extends ConsumerStatefulWidget {
  const _Formulario({this.persona});

  final PersonaAdmin? persona;

  @override
  ConsumerState<_Formulario> createState() => _EstadoFormulario();
}

class _EstadoFormulario extends ConsumerState<_Formulario> {
  late final _nombre = TextEditingController(
      text: widget.persona?.nombreCompleto ?? '');
  late final _email = TextEditingController(text: widget.persona?.email ?? '');
  late final _telefono =
      TextEditingController(text: widget.persona?.telefono ?? '');
  late final _cedula = TextEditingController(text: widget.persona?.cedula ?? '');

  late String _rol = widget.persona?.rol ?? 'residente';
  late String? _espacioId = widget.persona?.espacioId;
  late String? _relacion = widget.persona?.relacionEspacio;

  bool _guardando = false;
  ErrorAmigable? _problema;

  bool get _esNueva => widget.persona == null;

  @override
  void dispose() {
    _nombre.dispose();
    _email.dispose();
    _telefono.dispose();
    _cedula.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _guardando = true;
      _problema = null;
    });

    try {
      final servicio = ref.read(servicioAdminProvider);

      if (_esNueva) {
        final r = await servicio.crearPersona(
          nombreCompleto: _nombre.text,
          email: _email.text,
          rol: _rol,
          telefono: _telefono.text,
          cedula: _cedula.text,
          unidadId: _espacioId,
          relacionUnidad: _rol == 'residente' ? _relacion : null,
        );
        if (!mounted) return;
        refrescarPanel(ref);
        Navigator.pop(context);
        await mostrarClaveProvisoria(
          context,
          mensaje: r.mensaje,
          clave: r.claveProvisoria ?? '',
        );
      } else {
        await servicio.editarPersona(
          usuarioId: widget.persona!.id,
          nombreCompleto: _nombre.text,
          telefono: _telefono.text,
          cedula: _cedula.text,
          unidadId: _espacioId,
          relacionUnidad: _rol == 'residente' ? _relacion : null,
        );
        if (!mounted) return;
        refrescarPanel(ref);
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Datos guardados.'),
            backgroundColor: Colores.verde,
          ),
        );
      }
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
    final espacios = ref.watch(espaciosProvider).valueOrNull ?? const [];

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
            Text(
              _esNueva
                  ? 'Dar de alta a alguien'
                  : 'Editar a ${widget.persona!.nombreCompleto}',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),

            if (_problema != null) ...[
              AvisoDeError(problema: _problema!),
              const SizedBox(height: 14),
            ],

            TextField(
              controller: _nombre,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Nombre completo',
                prefixIcon: Icon(Icons.person_outline_rounded),
              ),
            ),
            const SizedBox(height: 12),

            TextField(
              controller: _email,
              enabled: _esNueva,
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              decoration: InputDecoration(
                labelText: 'Correo',
                prefixIcon: const Icon(Icons.mail_outline_rounded),
                helperText: _esNueva
                    ? 'Con este correo va a entrar a la app'
                    : 'El correo no se puede cambiar: es su llave de entrada',
                helperMaxLines: 2,
              ),
            ),
            const SizedBox(height: 12),

            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _telefono,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'Teléfono',
                      prefixIcon: Icon(Icons.phone_outlined),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _cedula,
                    decoration: const InputDecoration(labelText: 'Cédula'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // ---- Qué es dentro de la instalación ----
            Text('QUÉ ES', style: Theme.of(context).textTheme.labelSmall),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: [
                ButtonSegment(
                  value: 'residente',
                  label: Text(palabras.elHabitanteConMayuscula),
                  icon: const Icon(Icons.home_outlined, size: 17),
                ),
                const ButtonSegment(
                  value: 'guardia',
                  label: Text('Guardia'),
                  icon: Icon(Icons.shield_outlined, size: 17),
                ),
                const ButtonSegment(
                  value: 'administrador',
                  label: Text('Admin.'),
                  icon: Icon(Icons.admin_panel_settings_outlined, size: 17),
                ),
              ],
              selected: {_rol},
              onSelectionChanged: _esNueva
                  ? (s) => setState(() => _rol = s.first)
                  : null,
              showSelectedIcon: false,
              style: const ButtonStyle(
                visualDensity: VisualDensity.compact,
              ),
            ),
            if (!_esNueva)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text(
                  'El rol no se puede cambiar acá. Si alguien cambia de puesto, '
                  'conviene desactivarlo y darlo de alta de nuevo, para que el '
                  'historial de cada rol quede separado.',
                  style: TextStyle(
                      fontSize: 11.5, height: 1.4, color: Colores.textoSuave),
                ),
              ),

            // ---- El espacio, solo para residentes/apoderados ----
            if (_rol == 'residente') ...[
              const SizedBox(height: 16),
              Text(palabras.elEspacioConMayuscula.toUpperCase(),
                  style: Theme.of(context).textTheme.labelSmall),
              const SizedBox(height: 8),
              DropdownButtonFormField<String?>(
                initialValue: _espacioId,
                isExpanded: true,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.meeting_room_outlined),
                  helperText: espacios.isEmpty
                      ? 'Todavía no hay ninguno cargado. Se crean en la '
                          'pantalla de ${palabras.losEspacios}.'
                      : null,
                  helperMaxLines: 2,
                ),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('Sin asignar'),
                  ),
                  ...espacios.map((e) => DropdownMenuItem<String?>(
                        value: e.id,
                        child: Text(e.nombreCompleto),
                      )),
                ],
                onChanged: (v) => setState(() => _espacioId = v),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String?>(
                initialValue: _relacion,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Relación'),
                items: _relacionesDe(palabras.tipo)
                    .map((r) => DropdownMenuItem<String?>(
                          value: r.$1,
                          child: Text(r.$2),
                        ))
                    .toList(),
                onChanged: (v) => setState(() => _relacion = v),
              ),
            ],

            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _guardando ? null : _guardar,
                style: FilledButton.styleFrom(
                  backgroundColor: Colores.grafito,
                  minimumSize: const Size(0, Medidas.altoBoton),
                ),
                child: _guardando
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : Text(_esNueva ? 'Dar de alta' : 'Guardar cambios'),
              ),
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  /// Las formas de estar ligado a un espacio, según el tipo de instalación.
  /// En un colegio no hay propietarios ni arrendatarios: hay apoderados.
  static List<(String, String)> _relacionesDe(String tipo) => switch (tipo) {
        'colegio' => const [('apoderado', 'Apoderado')],
        'empresa' => const [('trabajador', 'Trabajador')],
        _ => const [
            ('propietario', 'Propietario'),
            ('arrendatario', 'Arrendatario'),
            ('familiar', 'Familiar'),
          ],
      };
}
