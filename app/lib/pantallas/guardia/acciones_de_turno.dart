// ============================================================================
// Tomass Seguridad — Cerrar turno y cerrar sesión
// ============================================================================
// EL CAMBIO DE GUARDIA ES LA OPERACIÓN MÁS COMÚN DE TODAS
//
//   Todos los días, a la misma hora, el guardia del día le pasa el puesto al de
//   la noche. Son dos pasos:
//
//     1. El que se va CIERRA SU TURNO. Desde ese momento deja de recibir los
//        avisos, y queda registrado hasta qué hora estuvo a cargo.
//     2. El que se va CIERRA SESIÓN, para que el que entra pueda entrar con su
//        propio usuario y los registros queden a su nombre.
//
// POR QUÉ ESTE ARCHIVO EXISTE APARTE
//
//   Estas dos acciones tienen que estar al alcance desde CUALQUIER pantalla del
//   guardia, incluida la de abrir turno. Si vivieran dentro de una sola
//   pantalla, desde las otras no se podría llegar.
//
//   Ya nos pasó: estaban solamente en el menú lateral, que únicamente aparece en
//   tablet. Como los guardias usan su celular personal, en la práctica NINGÚN
//   guardia podía cerrar sesión, y el de la noche no tenía cómo tomar el relevo.
//   Por eso ahora son una pieza suelta que se pone en todas las pantallas.
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/tema.dart';
import '../../estado/proveedores.dart';
import '../../estado/proveedores_guardia.dart';
import '../../modelos/admin.dart';
import '../../nucleo/errores.dart';
import '../../nucleo/formato.dart';

// ============================================================================
// LAS DOS ACCIONES
// ============================================================================

abstract final class AccionesDeTurno {
  /// Cierra el turno del guardia y le deja una nota al que entra.
  ///
  /// No cierra la sesión: son cosas distintas. Un guardia puede cerrar su turno
  /// y seguir con la app abierta hasta que llegue el relevo.
  static Future<void> cerrarTurno(BuildContext context, WidgetRef ref) async {
    final notas = TextEditingController();

    final confirmado = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Cerrar tu turno?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Vas a dejar de recibir los avisos de este puesto. Si querés, '
              'dejale una nota al guardia que entra.',
              style: TextStyle(fontSize: 13.5, height: 1.45),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: notas,
              maxLines: 3,
              maxLength: 200,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Nota para el siguiente turno (opcional)',
                hintText: 'Ej: la barrera está lenta, revisar el 302',
                alignLabelWithHint: true,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colores.grafito),
            child: const Text('Cerrar turno'),
          ),
        ],
      ),
    );

    final texto = notas.text.trim();
    notas.dispose();

    if (confirmado != true || !context.mounted) return;

    try {
      await ref.read(servicioGuardiaProvider).cerrarTurno(
            notasParaElSiguiente: texto.isEmpty ? null : texto,
          );
      ref.invalidate(miTurnoProvider);
      // La navegación a la pantalla de turno la hace sola el vigilante de rutas
    } catch (falla) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(Traductor.traducir(falla).mensaje),
          backgroundColor: Colores.rojo,
        ),
      );
    }
  }

  /// Cierra la sesión, para que entre otro guardia con su propio usuario.
  ///
  /// Si el turno sigue abierto, el aviso lo dice con todas las letras: un turno
  /// que queda abierto sigue mandándole los avisos a alguien que ya se fue a su
  /// casa, y esos avisos no le llegan a nadie más.
  static Future<void> cerrarSesion(BuildContext context, WidgetRef ref) async {
    final hayTurnoAbierto = ref.read(miTurnoProvider).valueOrNull != null;

    final seguro = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Cerrar sesión?'),
        content: Text(
          hayTurnoAbierto
              ? 'Ojo: tu turno sigue ABIERTO. Los avisos van a seguir yendo a '
                  'tu nombre aunque te vayas, y el guardia que entra no los va a '
                  'recibir.\n\nSi terminaste, cancelá y cerrá primero el turno.'
              : 'Vas a volver a la pantalla de inicio para que entre otro '
                  'guardia con su usuario.',
          style: const TextStyle(fontSize: 13.5, height: 1.45),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: hayTurnoAbierto ? Colores.rojo : Colores.grafito,
            ),
            child: const Text('Cerrar sesión'),
          ),
        ],
      ),
    );

    if (seguro != true) return;
    await ref.read(servicioSesionProvider).salir();
    // La vuelta al login la hace sola la app al ver que ya no hay sesión
  }
}

// ============================================================================
// EL BOTÓN DE LOS TRES PUNTITOS
// ============================================================================
// Va arriba a la derecha, en el encabezado de todas las pantallas del guardia.
// Es el lugar donde la gente busca las opciones de una app en el celular.
// ============================================================================

class MenuDelGuardia extends ConsumerWidget {
  const MenuDelGuardia({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final perfil = ref.watch(perfilProvider).valueOrNull;
    final turno = ref.watch(miTurnoProvider).valueOrNull;

    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert_rounded),
      tooltip: 'Turno y sesión',
      position: PopupMenuPosition.under,
      onSelected: (elegido) {
        // El menú se cierra antes de abrir el cartel de confirmación
        switch (elegido) {
          case 'turno':
            AccionesDeTurno.cerrarTurno(context, ref);
          case 'sesion':
            AccionesDeTurno.cerrarSesion(context, ref);
        }
      },
      itemBuilder: (context) => [
        // Quién está usando la app. En un cambio de guardia esto es lo primero
        // que hay que mirar: el que entra tiene que ver que todavía figura el
        // que se fue.
        PopupMenuItem<String>(
          enabled: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                perfil == null ? '…' : Formato.nombreCorto(perfil.nombreCompleto),
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: Colores.texto,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                turno == null
                    ? 'Sin turno abierto'
                    : '${turno.puntoAccesoNombre} · desde '
                        '${Formato.hora(turno.inicio)}',
                style: const TextStyle(fontSize: 11.5, color: Colores.textoSuave),
              ),
            ],
          ),
        ),
        const PopupMenuDivider(),

        if (turno != null)
          const PopupMenuItem<String>(
            value: 'turno',
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              leading: Icon(Icons.logout_rounded, size: 20),
              title: Text('Terminar turno'),
              subtitle: Text('Para entregarle el puesto al que entra'),
            ),
          ),
      ],
    );
  }
}

// ============================================================================
// LA SALIDA DE LA PANTALLA DE ABRIR TURNO
// ============================================================================
// Esa pantalla no tiene encabezado, así que el menú de los tres puntitos no
// entra. Y es justo donde MÁS hace falta poder salir: el guardia que llega se
// encuentra con la sesión del que se fue todavía abierta, y necesita sacarla
// para poder entrar con la suya.
// ============================================================================

class SalirDeLaCuenta extends ConsumerWidget {
  const SalirDeLaCuenta({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final perfil = ref.watch(perfilProvider).valueOrNull;
    final nombre =
        perfil == null ? null : Formato.nombreCorto(perfil.nombreCompleto);

    return Column(
      children: [
        Text(
          nombre == null
              ? 'Estás por abrir turno'
              : 'Estás entrando como $nombre',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12.5,
            color: Colors.white.withValues(alpha: 0.55),
          ),
        ),
        const SizedBox(height: 4),
        TextButton.icon(
          onPressed: () => AccionesDeTurno.cerrarSesion(context, ref),
          icon: const Icon(Icons.swap_horiz_rounded, size: 19),
          label: const Text(
            'No soy yo — cambiar de guardia',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          style: TextButton.styleFrom(
            foregroundColor: Colors.white.withValues(alpha: 0.9),
          ),
        ),
      ],
    );
  }
}

// ============================================================================
// EN QUÉ INSTALACIÓN ESTOY HOY
// ============================================================================
// Casi ningún guardia lo ve: si atiende una sola instalación (el caso normal),
// este widget no dibuja nada. Es solo para los pocos que rotan entre dos, como
// Hector, Ivan o Riends. Va ANTES de elegir el puesto, porque de acá depende
// qué puestos aparecen para elegir.
// ============================================================================

class SelectorDeInstalacionGuardia extends ConsumerWidget {
  const SelectorDeInstalacionGuardia({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(atiendeVariasGuardiaProvider)) return const SizedBox.shrink();

    final instalaciones =
        ref.watch(misInstalacionesGuardiaProvider).valueOrNull ?? const [];
    final activa = instalaciones.where((i) => i.esLaActiva).firstOrNull;

    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Material(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(Medidas.redondeo),
        child: InkWell(
          borderRadius: BorderRadius.circular(Medidas.redondeo),
          onTap: () => _elegir(context, ref, instalaciones),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                const Icon(Icons.apartment_rounded, color: Colors.white, size: 21),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'HOY ESTOY EN',
                        style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.3,
                          color: Colors.white.withValues(alpha: 0.55),
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        activa?.nombreParaMostrar ?? '…',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Cambiar',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: Colors.white)),
                      SizedBox(width: 3),
                      Icon(Icons.unfold_more_rounded, size: 15, color: Colors.white),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _elegir(
    BuildContext context,
    WidgetRef ref,
    List<Instalacion> instalaciones,
  ) async {
    final elegida = await showModalBottomSheet<Instalacion>(
      context: context,
      backgroundColor: Colores.superficie,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.82,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colores.linea,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              const Text('¿En cuál trabajás hoy?',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 30),
                child: Text(
                  'Elegí la instalación donde vas a hacer el turno de hoy. '
                  'Podés cambiar cuando quieras.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 12.5, height: 1.4, color: Colores.textoSuave),
                ),
              ),
              const SizedBox(height: 10),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  padding: EdgeInsets.zero,
                  itemCount: instalaciones.length,
                  itemBuilder: (context, n) {
                    final i = instalaciones[n];
                    return ListTile(
                      key: ValueKey(i.id),
                      onTap: () => Navigator.pop(context, i),
                      leading: Icon(
                        switch (i.tipo) {
                          'colegio' => Icons.school_rounded,
                          'empresa' => Icons.warehouse_rounded,
                          _ => Icons.apartment_rounded,
                        },
                        color: i.esLaActiva ? Colores.verdeOscuro : Colores.textoTenue,
                      ),
                      title: Text(
                        i.nombre,
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: i.esLaActiva ? FontWeight.w800 : FontWeight.w600,
                        ),
                      ),
                      subtitle: i.ciudad == null ? null : Text(i.ciudad!),
                      trailing: i.esLaActiva
                          ? const Icon(Icons.check_circle_rounded, color: Colores.verde)
                          : null,
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );

    if (elegida == null || elegida.esLaActiva || !context.mounted) return;

    try {
      await ref.read(servicioGuardiaProvider).cambiarDeInstalacion(elegida.id);
      if (!context.mounted) return;

      // Sin esto, la lista de puestos seguiría mostrando los de la
      // instalación anterior: puestosDisponibles() no filtra a mano, confía
      // en mi_condominio(), y esa función recién ahora devuelve la nueva.
      ref.invalidate(perfilProvider);
      ref.invalidate(misInstalacionesGuardiaProvider);
      ref.invalidate(puestosDisponiblesProvider);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Ahora estás en ${elegida.nombre}.'),
          backgroundColor: Colores.grafito,
        ),
      );
    } catch (falla) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(Traductor.traducir(falla).mensaje),
          backgroundColor: Colores.rojo,
        ),
      );
    }
  }
}
