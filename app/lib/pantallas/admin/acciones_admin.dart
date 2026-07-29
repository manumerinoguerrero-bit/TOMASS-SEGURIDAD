// ============================================================================
// Tomass Seguridad — El menú del administrador
// ============================================================================
// El botón de los tres puntitos, arriba a la derecha de todas las pantallas del
// panel. Muestra quién está usando la app y deja cerrar sesión.
//
// Va en TODAS las pantallas del panel por la misma razón que en las del
// guardia: si vive en una sola, desde las otras no se puede salir. Ya nos pasó.
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/tema.dart';
import '../../estado/proveedores.dart';
import '../../nucleo/formato.dart';

class MenuDelAdmin extends ConsumerWidget {
  const MenuDelAdmin({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final perfil = ref.watch(perfilProvider).valueOrNull;

    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert_rounded),
      tooltip: 'Mi sesión',
      position: PopupMenuPosition.under,
      onSelected: (elegido) {
        if (elegido == 'salir') _cerrarSesion(context, ref);
      },
      itemBuilder: (context) => [
        PopupMenuItem<String>(
          enabled: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                perfil == null
                    ? '…'
                    : Formato.nombreCorto(perfil.nombreCompleto),
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: Colores.texto,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                perfil?.nombreCondominio ?? 'Administración',
                style: const TextStyle(fontSize: 11.5, color: Colores.textoSuave),
              ),
            ],
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem<String>(
          value: 'salir',
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            leading: Icon(Icons.power_settings_new_rounded, size: 20),
            title: Text('Cerrar sesión'),
          ),
        ),
      ],
    );
  }

  Future<void> _cerrarSesion(BuildContext context, WidgetRef ref) async {
    final seguro = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Cerrar sesión?'),
        content: const Text(
          'Vas a volver a la pantalla de inicio.',
          style: TextStyle(fontSize: 13.5, height: 1.45),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colores.grafito),
            child: const Text('Cerrar sesión'),
          ),
        ],
      ),
    );

    if (seguro != true) return;
    await ref.read(servicioSesionProvider).salir();
  }
}

// ============================================================================
// EL CARTEL DE LA CONTRASEÑA PROVISORIA
// ============================================================================
// Se muestra al dar de alta a alguien o al cambiarle la clave.
//
// ⚠️ ESTA ES LA ÚNICA VEZ QUE ESA CONTRASEÑA SE PUEDE VER.
//
//    El servidor no la guarda en texto plano, a propósito: si la guardara,
//    cualquiera con acceso a la base podría entrar como esa persona. O sea que
//    si el administrador cierra este cartel sin anotarla, no hay forma de
//    recuperarla; hay que generar otra.
//
//    Por eso el cartel es grande, la contraseña se ve enorme, y hay un botón
//    para copiarla. No se puede cerrar tocando afuera sin querer.
// ============================================================================

Future<void> mostrarClaveProvisoria(
  BuildContext context, {
  required String mensaje,
  required String clave,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.key_rounded, color: Colores.verdeOscuro),
          SizedBox(width: 9),
          Expanded(child: Text('Anotá esta contraseña')),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(mensaje, style: const TextStyle(fontSize: 13.5, height: 1.45)),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 16),
            decoration: BoxDecoration(
              color: Colores.grafito.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(Medidas.redondeoChico),
              border: Border.all(color: Colores.linea),
            ),
            child: Text(
              clave,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w800,
                letterSpacing: 3,
                fontFamily: 'monospace',
              ),
            ),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
              color: Colores.naranja.withValues(alpha: 0.09),
              borderRadius: BorderRadius.circular(Medidas.redondeoChico),
            ),
            child: const Text(
              'Esta es la única vez que se puede ver. Si cerrás sin anotarla, '
              'hay que generar otra.',
              style: TextStyle(
                fontSize: 12.5,
                height: 1.45,
                fontWeight: FontWeight.w600,
                color: Colores.naranjaOscuro,
              ),
            ),
          ),
        ],
      ),
      actions: [
        FilledButton.icon(
          onPressed: () => Navigator.pop(context),
          style: FilledButton.styleFrom(backgroundColor: Colores.grafito),
          icon: const Icon(Icons.check_rounded, size: 19),
          label: const Text('Ya la anoté'),
        ),
      ],
    ),
  );
}
