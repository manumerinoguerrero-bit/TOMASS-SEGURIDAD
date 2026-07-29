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
import '../../estado/proveedores_admin.dart';
import '../../modelos/admin.dart';
import '../../nucleo/errores.dart';
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

// ============================================================================
// EL SELECTOR DE INSTALACIÓN
// ============================================================================
// Tomass Seguridad Privada atiende varias instalaciones. El administrador
// trabaja en UNA a la vez y cambia con esto.
//
// POR QUÉ DE A UNA Y NO TODAS JUNTAS
//
//   Porque los 38 candados de la base de datos dicen "solo lo de mi
//   instalación". Para mostrar todas mezcladas habría que reescribirlos, y un
//   renglón mal copiado ahí hace que un condominio vea los datos de otro, sin
//   ningún aviso.
//
//   Trabajando de a una, los candados no se tocan y siguen protegiendo igual.
//   Y encima el panel se lee mejor: los números de un condominio no se suman
//   con los de otro.
//
// Si atiende una sola instalación, esto no aparece: sería un botón inútil.
// ============================================================================

class SelectorDeInstalacion extends ConsumerWidget {
  const SelectorDeInstalacion({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(atiendeVariasProvider)) return const SizedBox.shrink();

    final instalaciones =
        ref.watch(misInstalacionesProvider).valueOrNull ?? const [];
    final activa = instalaciones.where((i) => i.esLaActiva).firstOrNull;

    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      color: Colores.grafito,
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
                      'ESTÁS ADMINISTRANDO',
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
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
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
                    Icon(Icons.unfold_more_rounded,
                        size: 15, color: Colors.white),
                  ],
                ),
              ),
            ],
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
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
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
            const Text('¿Cuál querés administrar?',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 30),
              child: Text(
                'Vas a ver y modificar solo la que elijas. Podés cambiar '
                'cuando quieras.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 12.5, height: 1.4, color: Colores.textoSuave),
              ),
            ),
            const SizedBox(height: 14),
            for (final i in instalaciones)
              ListTile(
                onTap: () => Navigator.pop(context, i),
                leading: Icon(
                  i.tipo == 'colegio'
                      ? Icons.school_rounded
                      : Icons.apartment_rounded,
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
                    ? const Icon(Icons.check_circle_rounded,
                        color: Colores.verde)
                    : null,
              ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );

    if (elegida == null || elegida.esLaActiva || !context.mounted) return;

    try {
      await ref.read(servicioAdminProvider).cambiarDeInstalacion(elegida.id);
      if (!context.mounted) return;

      // El perfil también se vuelve a pedir: de ahí salen las palabras de la
      // app. Si se pasa de un condominio a un colegio y el perfil no se
      // recarga, las pantallas seguirían diciendo "residente" y "unidad".
      ref.invalidate(perfilProvider);
      refrescarPanel(ref);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Ahora estás administrando ${elegida.nombre}.'),
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
