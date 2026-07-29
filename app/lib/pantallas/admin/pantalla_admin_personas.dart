// ============================================================================
// Tomass Seguridad — Panel de administración · Personas
// ============================================================================
// Dar de alta residentes, apoderados y guardias; editarlos, desactivarlos y
// cambiarles la contraseña cuando la olvidan.
//
// POR QUÉ "DESACTIVAR" Y NO "BORRAR"
//
//   Porque los registros de acceso apuntan a la persona. Si se borrara, todo el
//   historial quedaría con huecos: "alguien entró el martes a las 22:14" sin
//   saber quién. Y ese historial es justamente lo que sirve de prueba cuando
//   hay un problema.
//
//   Desactivar hace lo que hace falta: la persona deja de poder entrar, sus
//   teléfonos dejan de recibir avisos, y el historial queda intacto.
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/palabras.dart';
import '../../config/tema.dart';
import '../../estado/proveedores.dart';
import '../../estado/proveedores_admin.dart';
import '../../modelos/admin.dart';
import '../../nucleo/errores.dart';
import '../comunes/componentes.dart';
import 'acciones_admin.dart';
import 'formulario_persona.dart';

class PantallaAdminPersonas extends ConsumerWidget {
  const PantallaAdminPersonas({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final personas = ref.watch(personasProvider);
    final palabras = ref.watch(palabrasProvider);
    final filtro = ref.watch(filtroRolProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(palabras.losHabitantesConMayuscula),
        actions: const [MenuDelAdmin()],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => abrirFormularioDePersona(context),
        backgroundColor: Colores.grafito,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.person_add_rounded),
        label: const Text('Dar de alta',
            style: TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: Column(
        children: [
          // ---- Buscador y filtro por rol ----
          Padding(
            padding: const EdgeInsets.fromLTRB(
                Medidas.margen, Medidas.margen, Medidas.margen, 8),
            child: TextField(
              onChanged: (t) =>
                  ref.read(busquedaPersonasProvider.notifier).state = t,
              decoration: InputDecoration(
                hintText: 'Buscar por nombre o correo…',
                prefixIcon: const Icon(Icons.search_rounded),
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(Medidas.redondeo),
                ),
              ),
            ),
          ),
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: Medidas.margen),
              children: [
                _Filtro(
                  texto: 'Todos',
                  activo: filtro == null,
                  alTocar: () =>
                      ref.read(filtroRolProvider.notifier).state = null,
                ),
                _Filtro(
                  texto: palabras.losHabitantesConMayuscula,
                  activo: filtro == 'residente',
                  alTocar: () =>
                      ref.read(filtroRolProvider.notifier).state = 'residente',
                ),
                _Filtro(
                  texto: 'Guardias',
                  activo: filtro == 'guardia',
                  alTocar: () =>
                      ref.read(filtroRolProvider.notifier).state = 'guardia',
                ),
                _Filtro(
                  texto: 'Administración',
                  activo: filtro == 'administrador',
                  alTocar: () => ref.read(filtroRolProvider.notifier).state =
                      'administrador',
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),

          Expanded(
            child: personas.when(
              loading: () => const Center(
                child: CircularProgressIndicator(color: Colores.grafito),
              ),
              error: (falla, _) => Padding(
                padding: const EdgeInsets.all(Medidas.margen),
                child: AvisoDeError(
                  problema: Traductor.traducir(falla),
                  alReintentar: () => ref.invalidate(personasProvider),
                ),
              ),
              data: (lista) {
                if (lista.isEmpty) {
                  return ListaVacia(
                    icono: Icons.person_search_rounded,
                    titulo: 'No hay nadie que coincida',
                    explicacion:
                        'Probá con otro nombre, o dale de alta con el botón '
                        'de abajo.',
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(
                      Medidas.margen, 0, Medidas.margen, 92),
                  itemCount: lista.length,
                  itemBuilder: (_, i) =>
                      _Fila(persona: lista[i], palabras: palabras),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _Filtro extends StatelessWidget {
  const _Filtro({
    required this.texto,
    required this.activo,
    required this.alTocar,
  });

  final String texto;
  final bool activo;
  final VoidCallback alTocar;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(texto),
        selected: activo,
        onSelected: (_) => alTocar(),
        labelStyle: TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w700,
          color: activo ? Colors.white : Colores.textoSuave,
        ),
        selectedColor: Colores.grafito,
        showCheckmark: false,
      ),
    );
  }
}

// ============================================================================
// UNA PERSONA DE LA LISTA
// ============================================================================

class _Fila extends ConsumerWidget {
  const _Fila({required this.persona, required this.palabras});

  final PersonaAdmin persona;
  final Palabras palabras;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = persona;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        onTap: () => abrirFormularioDePersona(context, persona: p),
        leading: Opacity(
          opacity: p.estaActiva ? 1 : 0.4,
          child: Avatar(iniciales: p.iniciales, tamano: 42),
        ),
        title: Text(
          p.nombreCompleto,
          style: TextStyle(
            fontSize: 14.5,
            fontWeight: FontWeight.w700,
            color: p.estaActiva ? Colores.texto : Colores.textoTenue,
          ),
        ),
        subtitle: Text(
          [
            _rolEnPalabras(p.rol, palabras),
            if (p.espacio != null) '${palabras.elEspacioConMayuscula} ${p.espacio}',
          ].join(' · '),
          style: const TextStyle(fontSize: 12),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!p.estaActiva)
              const Etiqueta(texto: 'Inactiva', tono: TonoEtiqueta.malo),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert_rounded, size: 20),
              onSelected: (accion) => _hacer(context, ref, accion),
              itemBuilder: (_) => [
                const PopupMenuItem(
                  value: 'editar',
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    leading: Icon(Icons.edit_outlined, size: 19),
                    title: Text('Editar datos'),
                  ),
                ),
                const PopupMenuItem(
                  value: 'clave',
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    leading: Icon(Icons.key_outlined, size: 19),
                    title: Text('Contraseña nueva'),
                    subtitle: Text('Si la olvidó'),
                  ),
                ),
                PopupMenuItem(
                  value: p.estaActiva ? 'desactivar' : 'activar',
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    leading: Icon(
                      p.estaActiva
                          ? Icons.person_off_outlined
                          : Icons.person_outline_rounded,
                      size: 19,
                      color: p.estaActiva ? Colores.rojo : Colores.verde,
                    ),
                    title: Text(p.estaActiva ? 'Desactivar' : 'Volver a activar'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _rolEnPalabras(String rol, Palabras palabras) => switch (rol) {
        'administrador' => 'Administración',
        'guardia' => 'Guardia',
        _ => palabras.elHabitanteConMayuscula,
      };

  Future<void> _hacer(
      BuildContext context, WidgetRef ref, String accion) async {
    if (accion == 'editar') {
      abrirFormularioDePersona(context, persona: persona);
      return;
    }

    if (accion == 'clave') {
      final ok = await _confirmar(
        context,
        titulo: 'Contraseña nueva',
        texto: 'Se le va a poner una contraseña nueva a '
            '${persona.nombreCompleto}. La anterior deja de servir en el acto.',
        textoDelBoton: 'Generar',
      );
      if (ok != true || !context.mounted) return;

      try {
        final r = await ref
            .read(servicioAdminProvider)
            .restablecerClave(persona.id);
        if (!context.mounted) return;
        await mostrarClaveProvisoria(
          context,
          mensaje: r.mensaje,
          clave: r.claveProvisoria ?? '',
        );
      } catch (falla) {
        if (context.mounted) _avisarError(context, falla);
      }
      return;
    }

    // Activar o desactivar
    final desactivando = accion == 'desactivar';
    final ok = await _confirmar(
      context,
      titulo: desactivando ? '¿Desactivar?' : '¿Volver a activar?',
      texto: desactivando
          ? '${persona.nombreCompleto} no va a poder entrar a la app ni pasar '
              'por la entrada, y sus teléfonos dejan de recibir avisos.\n\n'
              'Su historial de accesos NO se borra: queda como prueba.'
          : '${persona.nombreCompleto} va a poder volver a usar la app y pasar '
              'por la entrada.',
      textoDelBoton: desactivando ? 'Desactivar' : 'Activar',
      peligroso: desactivando,
    );
    if (ok != true || !context.mounted) return;

    try {
      final r = await ref.read(servicioAdminProvider).cambiarEstado(
            persona.id,
            desactivando ? 'inactivo' : 'activo',
          );
      if (!context.mounted) return;
      refrescarPanel(ref);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(r.mensaje),
          backgroundColor: desactivando ? Colores.grafito : Colores.verde,
        ),
      );
    } catch (falla) {
      if (context.mounted) _avisarError(context, falla);
    }
  }

  Future<bool?> _confirmar(
    BuildContext context, {
    required String titulo,
    required String texto,
    required String textoDelBoton,
    bool peligroso = false,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(titulo),
        content: Text(texto,
            style: const TextStyle(fontSize: 13.5, height: 1.45)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: peligroso ? Colores.rojo : Colores.grafito,
            ),
            child: Text(textoDelBoton),
          ),
        ],
      ),
    );
  }

  void _avisarError(BuildContext context, Object falla) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(Traductor.traducir(falla).mensaje),
        backgroundColor: Colores.rojo,
      ),
    );
  }
}
