// ============================================================================
// Tomass Seguridad — Panel de administración · Guardias
// ============================================================================
// Dos secciones:
//   · Los que están en turno AHORA con su ubicación y hora de inicio.
//   · Todos los guardias del condominio, para editar/cerrar sesión/dar de alta.
//
// Acciones del administrador desde acá:
//   · Dar de alta un guardia nuevo con email + contraseña (FAB "+")
//   · Cerrar la sesión de un guardia forzadamente (revoca sus tokens y le
//     cierra el turno abierto si lo tuviera)
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config/tema.dart';
import '../../estado/proveedores.dart';
import '../../estado/proveedores_admin.dart';
import '../../modelos/admin.dart';
import '../../nucleo/errores.dart';
import '../../nucleo/formato.dart';
import '../../servicios/informe_guardia_pdf.dart';
import '../comunes/componentes.dart';
import 'acciones_admin.dart';
import 'pantalla_admin_mapa_vivo.dart' show guardiasEnVivoProvider;

/// Lista completa de guardias del condominio (en turno o no).
final listaGuardiasProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) {
  return ref.watch(servicioAdminProvider).listarGuardias();
});

class PantallaAdminGuardias extends ConsumerWidget {
  const PantallaAdminGuardias({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enVivo = ref.watch(guardiasEnVivoProvider);
    final todos = ref.watch(listaGuardiasProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Guardias'),
        actions: const [MenuDelAdmin()],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _abrirCrearGuardia(context, ref),
        icon: const Icon(Icons.person_add_alt_1_rounded),
        label: const Text('Agregar guardia'),
        backgroundColor: Colores.grafito,
        foregroundColor: Colors.white,
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(guardiasEnVivoProvider);
          ref.invalidate(listaGuardiasProvider);
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
              Medidas.margen, Medidas.margen, Medidas.margen, 92),
          children: [
            const _TituloSeccion('EN TURNO AHORA'),
            const SizedBox(height: 8),
            _SeccionEnTurno(enVivo: enVivo),
            const SizedBox(height: 24),
            const _TituloSeccion('TODOS LOS GUARDIAS'),
            const SizedBox(height: 8),
            _SeccionTodos(todos: todos, ref: ref),
          ],
        ),
      ),
    );
  }

  Future<void> _abrirCrearGuardia(BuildContext context, WidgetRef ref) async {
    final creado = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colores.superficie,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: const _FormularioGuardia(),
      ),
    );
    if (creado == true) {
      ref.invalidate(listaGuardiasProvider);
      ref.invalidate(guardiasEnVivoProvider);
    }
  }
}

class _TituloSeccion extends StatelessWidget {
  const _TituloSeccion(this.texto);
  final String texto;
  @override
  Widget build(BuildContext context) {
    return Text(
      texto,
      style: const TextStyle(
        fontSize: 11.5,
        fontWeight: FontWeight.w800,
        color: Colores.grafito,
        letterSpacing: 1.2,
      ),
    );
  }
}

// ============================================================================
// SECCIÓN 1: GUARDIAS EN TURNO AHORA
// ============================================================================

class _SeccionEnTurno extends StatelessWidget {
  const _SeccionEnTurno({required this.enVivo});
  final AsyncValue<List<GuardiaEnVivo>> enVivo;

  @override
  Widget build(BuildContext context) {
    return enVivo.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: CircularProgressIndicator(color: Colores.grafito),
        ),
      ),
      error: (falla, _) => AvisoDeError(
        problema: Traductor.traducir(falla),
        compacto: true,
      ),
      data: (lista) {
        if (lista.isEmpty) {
          return Card(
            color: Colores.grafito.withValues(alpha: 0.05),
            child: const Padding(
              padding: EdgeInsets.all(Medidas.margen),
              child: Row(
                children: [
                  Icon(Icons.info_outline_rounded,
                      size: 20, color: Colores.textoSuave),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Ningún guardia con turno abierto ahora mismo.',
                      style: TextStyle(
                          fontSize: 13, color: Colores.textoSuave),
                    ),
                  ),
                ],
              ),
            ),
          );
        }
        return Column(
          children: [
            for (final g in lista) _TarjetaEnTurno(guardia: g),
          ],
        );
      },
    );
  }
}

class _TarjetaEnTurno extends StatelessWidget {
  const _TarjetaEnTurno({required this.guardia});
  final GuardiaEnVivo guardia;

  Color get _color => switch (guardia.estado) {
        'vivo' => Colores.verde,
        'demorado' => Colores.naranja,
        'esperando' => Colores.textoSuave,
        _ => Colores.rojo,
      };
  String get _texto => switch (guardia.estado) {
        'vivo' => 'En línea',
        'demorado' => 'Demorado',
        'esperando' => 'Buscando GPS…',
        _ => 'Sin señal',
      };

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: _color.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.shield_rounded, color: _color, size: 21),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    guardia.guardiaNombre,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$_texto · desde ${Formato.hora(guardia.inicio)} · '
                    '${guardia.puntoAccesoNombre ?? "Todo el condominio"}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: _color,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            if (guardia.tieneUbicacion)
              IconButton(
                icon: const Icon(Icons.map_outlined),
                iconSize: 20,
                color: Colores.grafito,
                tooltip: 'Ver en Google Maps',
                onPressed: () async {
                  final url = Uri.parse(
                      'https://www.google.com/maps/search/?api=1'
                      '&query=${guardia.ultimaLat},${guardia.ultimaLng}');
                  await launchUrl(url,
                      mode: LaunchMode.externalApplication);
                },
              ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// SECCIÓN 2: TODOS LOS GUARDIAS
// ============================================================================

class _SeccionTodos extends StatelessWidget {
  const _SeccionTodos({required this.todos, required this.ref});
  final AsyncValue<List<Map<String, dynamic>>> todos;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    return todos.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(
            child: CircularProgressIndicator(color: Colores.grafito)),
      ),
      error: (falla, _) => AvisoDeError(
        problema: Traductor.traducir(falla),
        compacto: true,
      ),
      data: (lista) {
        if (lista.isEmpty) {
          return const Card(
            child: Padding(
              padding: EdgeInsets.all(Medidas.margen),
              child: Text(
                'Todavía no hay guardias registrados. Tocá "Agregar guardia" '
                'para dar de alta al primero.',
                style: TextStyle(fontSize: 13, color: Colores.textoSuave),
              ),
            ),
          );
        }
        return Column(
          children: [
            for (final g in lista) _TarjetaGuardia(guardia: g, ref: ref),
          ],
        );
      },
    );
  }
}

class _TarjetaGuardia extends StatelessWidget {
  const _TarjetaGuardia({required this.guardia, required this.ref});
  final Map<String, dynamic> guardia;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    final nombre = guardia['nombre_completo'] as String? ?? 'Sin nombre';
    final email = guardia['email'] as String? ?? '';
    final telefono = guardia['telefono'] as String?;
    final activo = guardia['estado'] == 'activo';

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Avatar(
          iniciales: _iniciales(nombre),
          tamano: 40,
        ),
        title: Text(
          nombre,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          email + (telefono != null ? ' · $telefono' : '') +
              (activo ? '' : ' · inactivo'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 11.5,
            color: activo ? Colores.textoSuave : Colores.rojo,
          ),
        ),
        trailing: PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert_rounded),
          onSelected: (accion) => _hacer(context, accion),
          itemBuilder: (_) => [
            const PopupMenuItem(
              value: 'informe',
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                leading: Icon(Icons.picture_as_pdf_rounded, size: 19),
                title: Text('Descargar informe (30 días)'),
              ),
            ),
            const PopupMenuDivider(),
            const PopupMenuItem(
              value: 'cambiar_clave',
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                leading: Icon(Icons.key_rounded, size: 19),
                title: Text('Cambiar clave'),
              ),
            ),
            const PopupMenuItem(
              value: 'cerrar_sesion',
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                leading: Icon(Icons.logout_rounded, size: 19),
                title: Text('Cerrar sesión'),
              ),
            ),
            const PopupMenuDivider(),
            if (activo)
              const PopupMenuItem(
                value: 'dar_de_baja',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  leading: Icon(Icons.person_off_rounded,
                      size: 19, color: Colores.naranja),
                  title: Text('Dar de baja',
                      style: TextStyle(color: Colores.naranja)),
                ),
              )
            else
              const PopupMenuItem(
                value: 'reactivar',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  leading: Icon(Icons.restart_alt_rounded,
                      size: 19, color: Colores.verdeOscuro),
                  title: Text('Reactivar',
                      style: TextStyle(color: Colores.verdeOscuro)),
                ),
              ),
            const PopupMenuItem(
              value: 'borrar',
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                leading: Icon(Icons.delete_forever_rounded,
                    size: 19, color: Colores.rojo),
                title: Text('Borrar definitivamente',
                    style: TextStyle(color: Colores.rojo)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _hacer(BuildContext context, String accion) async {
    switch (accion) {
      case 'informe':
        await _descargarInforme(context);
      case 'cerrar_sesion':
        await _cerrarSesion(context);
      case 'cambiar_clave':
        await _cambiarClave(context);
      case 'dar_de_baja':
        await _darDeBaja(context);
      case 'reactivar':
        await _reactivar(context);
      case 'borrar':
        await _borrarDefinitivo(context);
    }
  }

  Future<void> _cerrarSesion(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Cerrar sesión del guardia'),
        content: Text(
          '¿Cerrar la sesión de ${guardia['nombre_completo']}?\n\n'
          'Si tiene turno abierto, se cierra también. La próxima vez que abra '
          'la app le va a pedir el email y la contraseña.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colores.rojo),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Cerrar sesión'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    await _ejecutar(context,
        tarea: () => ref
            .read(servicioAdminProvider)
            .cerrarSesionGuardia(guardia['id'] as String),
        exito: 'Sesión de ${guardia['nombre_completo']} cerrada.');
  }

  Future<void> _cambiarClave(BuildContext context) async {
    final nuevaClave = await showDialog<String>(
      context: context,
      builder: (_) => const _DialogoCambiarClave(),
    );
    if (nuevaClave == null || nuevaClave.isEmpty || !context.mounted) return;
    await _ejecutar(context,
        tarea: () => ref.read(servicioAdminProvider).cambiarClaveDeGuardia(
              guardiaId: guardia['id'] as String,
              nuevaClave: nuevaClave,
            ),
        exito:
            'Clave de ${guardia['nombre_completo']} actualizada. Ya puede entrar con la nueva clave.');
  }

  Future<void> _darDeBaja(BuildContext context) async {
    final motivo = await showDialog<String>(
      context: context,
      builder: (_) => _DialogoDarDeBaja(nombre: guardia['nombre_completo'] as String),
    );
    if (motivo == null || !context.mounted) return;
    await _ejecutar(context,
        tarea: () => ref.read(servicioAdminProvider).darDeBajaGuardia(
              guardiaId: guardia['id'] as String,
              motivo: motivo,
            ),
        exito: '${guardia['nombre_completo']} dado de baja. El historial se conserva.');
  }

  Future<void> _reactivar(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Reactivar guardia'),
        content: Text(
          '¿Reactivar a ${guardia['nombre_completo']}?\n\n'
          'Vuelve a estar activo y con acceso a todas las instalaciones. '
          'Si olvidó la clave, usá "Cambiar clave" después.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Reactivar'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    await _ejecutar(context,
        tarea: () => ref
            .read(servicioAdminProvider)
            .reactivarGuardia(guardia['id'] as String),
        exito: '${guardia['nombre_completo']} reactivado.');
  }

  Future<void> _borrarDefinitivo(BuildContext context) async {
    final nombreReal = guardia['nombre_completo'] as String? ?? '';
    final confirmado = await showDialog<String>(
      context: context,
      builder: (_) => _DialogoBorrarDefinitivo(nombreReal: nombreReal),
    );
    if (confirmado == null || confirmado.isEmpty || !context.mounted) return;
    await _ejecutar(context,
        tarea: () => ref.read(servicioAdminProvider).borrarGuardiaDefinitivo(
              guardiaId: guardia['id'] as String,
              confirmacionNombre: confirmado,
            ),
        exito: '$nombreReal borrado del sistema.');
  }

  Future<void> _ejecutar(BuildContext context,
      {required Future<void> Function() tarea, required String exito}) async {
    try {
      await tarea();
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(exito), backgroundColor: Colores.verde),
      );
      ref.invalidate(guardiasEnVivoProvider);
      ref.invalidate(listaGuardiasProvider);
    } catch (falla) {
      if (!context.mounted) return;
      final e = Traductor.traducir(falla);
      final texto = e.detalle != null && e.detalle!.isNotEmpty
          ? '${e.mensaje}\n${e.detalle}'
          : e.mensaje;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(texto),
          backgroundColor: Colores.rojo,
          duration: const Duration(seconds: 7),
        ),
      );
    }
  }

  Future<void> _descargarInforme(BuildContext context) async {
    final servicio = ref.read(servicioAdminProvider);
    final servicioFotos = ref.read(servicioFotosProvider);
    final instalacion =
        ref.read(perfilProvider).valueOrNull?.nombreCondominio ?? 'Instalación';
    final desde = DateTime.now().subtract(const Duration(days: 30));
    final hasta = DateTime.now();
    final nombre = guardia['nombre_completo'] as String? ?? 'guardia';

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Armando informe de $nombre…'),
        backgroundColor: Colores.grafito,
        duration: const Duration(seconds: 3),
      ),
    );
    try {
      final data = await servicio.dataInformeGuardia(
        guardiaId: guardia['id'] as String,
        desde: desde,
        hasta: hasta,
      );
      final bytes = await InformeDeGuardiaPdf.armar(
        instalacion: instalacion,
        data: data,
        servicioFotos: servicioFotos,
      );
      if (!context.mounted) return;
      final apellido = nombre
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
          .replaceAll(RegExp(r'^-|-$'), '');
      await Printing.layoutPdf(
        name: 'informe-$apellido-${DateTime.now().millisecondsSinceEpoch}.pdf',
        onLayout: (_) async => bytes,
      );
    } catch (falla) {
      if (!context.mounted) return;
      final e = Traductor.traducir(falla);
      // Mostramos también el detalle: cuando la causa es una query específica
      // o un dato inconsistente, el detalle trae el mensaje real del servidor
      // en vez de solo "La base de datos rechazó la operación", que no dice
      // por dónde arrancar a buscar.
      final texto = e.detalle != null && e.detalle!.isNotEmpty
          ? '${e.mensaje}\n${e.detalle}'
          : e.mensaje;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(texto),
          backgroundColor: Colores.rojo,
          duration: const Duration(seconds: 8),
        ),
      );
    }
  }

  static String _iniciales(String nombre) {
    final partes = nombre.trim().split(RegExp(r'\s+'));
    if (partes.isEmpty || partes.first.isEmpty) return '?';
    if (partes.length == 1) {
      return partes.first
          .substring(0, partes.first.length >= 2 ? 2 : 1)
          .toUpperCase();
    }
    return '${partes[0][0]}${partes[1][0]}'.toUpperCase();
  }
}

// ============================================================================
// FORMULARIO DE ALTA DE GUARDIA
// ============================================================================

class _FormularioGuardia extends ConsumerStatefulWidget {
  const _FormularioGuardia();

  @override
  ConsumerState<_FormularioGuardia> createState() => _EstadoFormulario();
}

class _EstadoFormulario extends ConsumerState<_FormularioGuardia> {
  final _form = GlobalKey<FormState>();
  final _nombre = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _telefono = TextEditingController();
  bool _guardando = false;
  bool _verPassword = false;
  ErrorAmigable? _problema;

  @override
  void dispose() {
    _nombre.dispose();
    _email.dispose();
    _password.dispose();
    _telefono.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    if (!_form.currentState!.validate()) return;
    final perfil = ref.read(perfilProvider).valueOrNull;
    if (perfil == null) return;

    FocusScope.of(context).unfocus();
    setState(() {
      _guardando = true;
      _problema = null;
    });
    try {
      await ref.read(servicioAdminProvider).crearGuardia(
            email: _email.text,
            password: _password.text,
            nombreCompleto: _nombre.text,
            condominioId: perfil.condominioId,
            telefono: _telefono.text,
          );
      if (!mounted) return;
      // Capturamos el messenger ANTES del pop para que el snack aparezca
      // en la pantalla de arriba (la lista de guardias) y no en el diálogo
      // que se está cerrando.
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).pop(true);
      messenger.showSnackBar(
        SnackBar(
          content: Text('Guardia ${_nombre.text} dado de alta.'),
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
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(Medidas.margen),
        child: Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
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
              const SizedBox(height: 18),
              Text(
                'Nuevo guardia',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 4),
              const Text(
                'Da de alta al guardia con email y contraseña. Después va a '
                'poder entrar solo desde la app.',
                style: TextStyle(fontSize: 12.5, color: Colores.textoSuave),
              ),
              const SizedBox(height: 18),
              if (_problema != null) ...[
                Container(
                  padding: const EdgeInsets.all(11),
                  decoration: BoxDecoration(
                    color: Colores.rojo.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.error_outline_rounded,
                          color: Colores.rojo, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _problema!.mensaje,
                          style: const TextStyle(
                              color: Colores.rojo,
                              fontSize: 13,
                              fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],
              TextFormField(
                controller: _nombre,
                enabled: !_guardando,
                textCapitalization: TextCapitalization.words,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Nombre completo',
                  hintText: 'Juan Pérez González',
                  prefixIcon: Icon(Icons.person_outline_rounded),
                ),
                validator: (v) =>
                    (v ?? '').trim().length < 3 ? 'Falta el nombre.' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _email,
                enabled: !_guardando,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'Correo electrónico',
                  hintText: 'juan.perez@empresa.cl',
                  prefixIcon: Icon(Icons.mail_outline_rounded),
                ),
                validator: (v) {
                  final t = (v ?? '').trim();
                  if (t.isEmpty) return 'Escribí el email.';
                  if (!t.contains('@') || !t.contains('.')) {
                    return 'Ese email no parece completo.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _password,
                enabled: !_guardando,
                obscureText: !_verPassword,
                decoration: InputDecoration(
                  labelText: 'Contraseña',
                  hintText: 'Mínimo 6 caracteres',
                  prefixIcon: const Icon(Icons.lock_outline_rounded),
                  suffixIcon: IconButton(
                    icon: Icon(_verPassword
                        ? Icons.visibility_off_rounded
                        : Icons.visibility_rounded),
                    onPressed: () =>
                        setState(() => _verPassword = !_verPassword),
                  ),
                ),
                validator: (v) =>
                    (v ?? '').length < 6 ? 'Mínimo 6 caracteres.' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _telefono,
                enabled: !_guardando,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Teléfono (opcional)',
                  hintText: '+56 9 1234 5678',
                  prefixIcon: Icon(Icons.phone_outlined),
                ),
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: _guardando ? null : _guardar,
                icon: _guardando
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.person_add_alt_1_rounded, size: 20),
                label: Text(_guardando ? 'Guardando…' : 'Dar de alta'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colores.grafito,
                  minimumSize: const Size.fromHeight(Medidas.altoBoton),
                ),
              ),
              const SizedBox(height: 10),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// DIÁLOGO: cambiar la clave de un guardia
// ============================================================================
// El admin tipea una clave nueva. Si tiene al menos 6 caracteres, confirma;
// después el guardia va a tener que entrar con esa clave. Útil cuando un
// guardia pierde su clave y no puede recuperarla por email.
// ============================================================================

class _DialogoCambiarClave extends StatefulWidget {
  const _DialogoCambiarClave();

  @override
  State<_DialogoCambiarClave> createState() => _EstadoDialogoCambiarClave();
}

class _EstadoDialogoCambiarClave extends State<_DialogoCambiarClave> {
  final _controlador = TextEditingController();
  bool _mostrar = false;
  String? _error;

  @override
  void dispose() {
    _controlador.dispose();
    super.dispose();
  }

  void _confirmar() {
    final valor = _controlador.text.trim();
    if (valor.length < 6) {
      setState(() => _error = 'Al menos 6 caracteres.');
      return;
    }
    Navigator.pop(context, valor);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Cambiar clave del guardia'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'La nueva clave reemplaza a la actual. Se cierra la sesión y el '
            'guardia va a tener que entrar con esta nueva clave.',
            style: TextStyle(fontSize: 12.5, color: Colores.textoSuave),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _controlador,
            obscureText: !_mostrar,
            autofocus: true,
            decoration: InputDecoration(
              labelText: 'Clave nueva',
              errorText: _error,
              suffixIcon: IconButton(
                icon: Icon(_mostrar
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined),
                onPressed: () => setState(() => _mostrar = !_mostrar),
              ),
            ),
            onSubmitted: (_) => _confirmar(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _confirmar,
          child: const Text('Cambiar clave'),
        ),
      ],
    );
  }
}

// ============================================================================
// DIÁLOGO: dar de baja (soft delete)
// ============================================================================
// El admin anota un motivo (opcional). El guardia queda inactivo pero su
// historial se conserva, y puede reactivarse después.
// ============================================================================

class _DialogoDarDeBaja extends StatefulWidget {
  const _DialogoDarDeBaja({required this.nombre});
  final String nombre;

  @override
  State<_DialogoDarDeBaja> createState() => _EstadoDialogoDarDeBaja();
}

class _EstadoDialogoDarDeBaja extends State<_DialogoDarDeBaja> {
  final _controlador = TextEditingController();
  String? _motivoElegido;

  @override
  void dispose() {
    _controlador.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Dar de baja a ${widget.nombre}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'El guardia queda inactivo y no puede abrir turnos. Se conservan '
            'sus turnos, novedades y rondas para informes futuros. Se puede '
            'reactivar más adelante.',
            style: TextStyle(fontSize: 12.5, color: Colores.textoSuave),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              for (final m in const ['Renuncia', 'Despido', 'Fin de contrato'])
                ChoiceChip(
                  label: Text(m),
                  selected: _motivoElegido == m,
                  onSelected: (_) {
                    setState(() {
                      _motivoElegido = m;
                      _controlador.text = m;
                    });
                  },
                ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _controlador,
            decoration: const InputDecoration(
              labelText: 'Motivo (opcional)',
              hintText: 'Ej: Renuncia voluntaria',
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Colores.naranja),
          onPressed: () => Navigator.pop(context, _controlador.text.trim()),
          child: const Text('Dar de baja'),
        ),
      ],
    );
  }
}

// ============================================================================
// DIÁLOGO: borrar definitivamente (destructivo)
// ============================================================================
// Exige que el admin escriba el nombre COMPLETO del guardia tal como aparece
// en la ficha. El servidor además valida que no tenga historial — si tiene
// aunque sea 1 turno, rechaza el borrado y sugiere "Dar de baja". El admin
// recibe ese error como un snackbar rojo si lo intenta.
// ============================================================================

class _DialogoBorrarDefinitivo extends StatefulWidget {
  const _DialogoBorrarDefinitivo({required this.nombreReal});
  final String nombreReal;

  @override
  State<_DialogoBorrarDefinitivo> createState() =>
      _EstadoDialogoBorrarDefinitivo();
}

class _EstadoDialogoBorrarDefinitivo
    extends State<_DialogoBorrarDefinitivo> {
  final _controlador = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controlador.dispose();
    super.dispose();
  }

  void _confirmar() {
    final tipeado = _controlador.text.trim();
    if (tipeado.toLowerCase() != widget.nombreReal.trim().toLowerCase()) {
      setState(() => _error = 'El nombre no coincide.');
      return;
    }
    Navigator.pop(context, tipeado);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Borrar definitivamente'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colores.rojo.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colores.rojo.withValues(alpha: 0.3)),
            ),
            child: const Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: Colores.rojo, size: 20),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Esto borra la cuenta y la vuelve inaccesible. Solo se '
                    'permite si el guardia NO tiene historial (turnos, rondas, '
                    'paquetes). En otro caso, usá "Dar de baja".',
                    style: TextStyle(fontSize: 12, color: Colores.rojo),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'Para confirmar, escribí el nombre completo del guardia:',
            style: TextStyle(fontSize: 12.5, color: Colores.textoSuave),
          ),
          const SizedBox(height: 4),
          Text(
            widget.nombreReal,
            style: const TextStyle(
                fontSize: 13.5, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _controlador,
            autofocus: true,
            decoration: InputDecoration(
              labelText: 'Nombre completo',
              errorText: _error,
            ),
            onSubmitted: (_) => _confirmar(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Colores.rojo),
          onPressed: _confirmar,
          child: const Text('Borrar para siempre'),
        ),
      ],
    );
  }
}
