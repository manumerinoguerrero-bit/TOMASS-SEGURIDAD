// ============================================================================
// Tomass Seguridad — ¿De quién es este auto?
// ============================================================================
// EL CASO QUE LA MOTIVA, TAL COMO LO CONTÓ MANUEL
//
//   Un auto se estaciona en el lugar de otro. El guardia necesita saber de quién
//   es para llamarlo, y hoy eso significa buscar a alguien que lo reconozca o
//   dejar una nota en el parabrisas.
//
//   Con esto: escribe tres letras de la patente y tiene el nombre, la unidad y
//   el teléfono, con un botón para llamar directo.
//
// LAS TRES COSAS QUE CONTESTA, EN ESTE ORDEN
//
//   1. ¿De quién es?          → nombre y unidad, bien grandes
//   2. ¿Cómo lo ubico?        → el botón de llamar, que es la acción real
//   3. ¿Puede estar acá?      → si el vehículo está aprobado o no
//
//   El punto 3 importa más de lo que parece: un auto PENDIENTE está registrado
//   pero todavía no aprobado, y el guardia tiene que poder distinguirlo de uno
//   que sí puede entrar.
//
// SI LA PATENTE NO APARECE, ESO TAMBIÉN ES UNA RESPUESTA
//
//   Significa que es un auto no registrado. La pantalla lo dice con todas las
//   letras en vez de mostrar una lista vacía, porque para el guardia es un dato
//   que cambia lo que hace después.
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config/tema.dart';
import '../../estado/proveedores.dart';
import '../../estado/proveedores_guardia.dart';
import '../../modelos/guardia.dart';
import '../../nucleo/errores.dart';
import '../comunes/componentes.dart';
import 'acciones_de_turno.dart';

class PantallaBuscarPatente extends ConsumerStatefulWidget {
  const PantallaBuscarPatente({super.key});

  @override
  ConsumerState<PantallaBuscarPatente> createState() => _EstadoBuscarPatente();
}

class _EstadoBuscarPatente extends ConsumerState<PantallaBuscarPatente> {
  final _campo = TextEditingController();

  @override
  void dispose() {
    _campo.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final texto = ref.watch(busquedaDePatenteProvider);
    final resultados = ref.watch(vehiculosEncontradosProvider);
    final palabras = ref.watch(palabrasProvider);

    // Cuántas letras escribió, sin contar guiones ni espacios
    final letras = texto.replaceAll(RegExp('[^A-Za-z0-9]'), '').length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('¿De quién es este auto?'),
        actions: const [MenuDelGuardia()],
      ),
      body: Column(
        children: [
          // ---- El buscador ----
          Padding(
            padding: const EdgeInsets.all(Medidas.margen),
            child: TextField(
              controller: _campo,
              autofocus: true,
              textCapitalization: TextCapitalization.characters,
              // Solo letras y números: así el guardia escribe rápido sin
              // preocuparse por el guion.
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp('[a-zA-Z0-9]')),
                // 6 es el máximo real: la patente chilena más larga tiene 4
                // letras y 2 números (BBBB99), o 2 letras y 4 números (AA9999).
                LengthLimitingTextInputFormatter(6),
              ],
              style: const TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w800,
                letterSpacing: 4,
              ),
              textAlign: TextAlign.center,
              onChanged: (t) =>
                  ref.read(busquedaDePatenteProvider.notifier).state = t,
              decoration: InputDecoration(
                hintText: 'BCDF12',
                hintStyle: TextStyle(
                  fontSize: 26,
                  letterSpacing: 4,
                  color: Colores.textoTenue.withValues(alpha: 0.5),
                ),
                helperText: 'Escribí al menos 3 letras o números. '
                    'No hace falta el guion.',
                helperMaxLines: 2,
                suffixIcon: texto.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close_rounded),
                        tooltip: 'Borrar',
                        onPressed: () {
                          _campo.clear();
                          ref.read(busquedaDePatenteProvider.notifier).state = '';
                        },
                      ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(Medidas.redondeo),
                ),
              ),
            ),
          ),

          Expanded(
            child: letras < 3
                ? const ListaVacia(
                    icono: Icons.pin_rounded,
                    titulo: 'Escribí la patente',
                    explicacion:
                        'Con tres letras o números alcanza. Sirve para saber de '
                        'quién es un auto que está estacionado donde no '
                        'corresponde, o uno que no reconocés.',
                  )
                : resultados.when(
                    loading: () => const Center(
                      child: CircularProgressIndicator(color: Colores.grafito),
                    ),
                    error: (falla, _) => Padding(
                      padding: const EdgeInsets.all(Medidas.margen),
                      child: AvisoDeError(
                        problema: Traductor.traducir(falla),
                        alReintentar: () =>
                            ref.invalidate(vehiculosEncontradosProvider),
                      ),
                    ),
                    data: (lista) {
                      if (lista.isEmpty) return const _NoEstaRegistrado();

                      return ListView.builder(
                        padding: const EdgeInsets.fromLTRB(
                            Medidas.margen, 0, Medidas.margen, Medidas.margen),
                        itemCount: lista.length,
                        itemBuilder: (_, i) => _Tarjeta(
                          key: ValueKey(lista[i].id),
                          vehiculo: lista[i],
                          palabras: palabras,
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// CUANDO LA PATENTE NO APARECE
// ============================================================================
// No es una lista vacía: es una respuesta. Para el guardia cambia lo que hace
// después, así que se dice con todas las letras.
// ============================================================================

class _NoEstaRegistrado extends StatelessWidget {
  const _NoEstaRegistrado();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(Medidas.margen),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(Medidas.margen),
            decoration: BoxDecoration(
              color: Colores.naranja.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(Medidas.redondeo),
              border: Border.all(color: Colores.naranja.withValues(alpha: 0.5)),
            ),
            child: Column(
              children: [
                const Icon(Icons.help_outline_rounded,
                    size: 38, color: Colores.naranjaOscuro),
                const SizedBox(height: 12),
                const Text(
                  'Ese auto NO está registrado',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: Colores.naranjaOscuro,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'No pertenece a ningún residente de esta instalación, o la '
                  'patente está escrita distinta. Probá con menos letras por si '
                  'leíste alguna mal.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, height: 1.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// UN AUTO ENCONTRADO
// ============================================================================

class _Tarjeta extends StatelessWidget {
  const _Tarjeta({super.key, required this.vehiculo, required this.palabras});

  final VehiculoBuscado vehiculo;
  final dynamic palabras;

  @override
  Widget build(BuildContext context) {
    final v = vehiculo;

    final (color, tono, etiqueta) = switch (v.estado) {
      'aprobado' => (Colores.verde, Colores.verdeOscuro, 'PUEDE ENTRAR'),
      'rechazado' => (Colores.rojo, Colores.rojoOscuro, 'RECHAZADO'),
      _ => (Colores.naranja, Colores.naranjaOscuro, 'TODAVÍA NO APROBADO'),
    };

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Medidas.redondeo),
        side: BorderSide(color: color.withValues(alpha: 0.5), width: 1.4),
      ),
      child: Padding(
        padding: const EdgeInsets.all(Medidas.margen),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ---- La patente y si puede entrar ----
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: Colores.grafito,
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Text(
                    v.patente,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 2.5,
                    ),
                  ),
                ),
                const Spacer(),
                Flexible(
                  child: Text(
                    etiqueta,
                    textAlign: TextAlign.end,
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                      color: tono,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 10),
            Text(v.descripcion,
                style: const TextStyle(
                    fontSize: 13.5, color: Colores.textoSuave)),

            const SizedBox(height: 13),
            const Divider(height: 1),
            const SizedBox(height: 13),

            // ---- De quién es: lo que el guardia vino a buscar ----
            Text(v.dueno,
                style: const TextStyle(
                    fontSize: 17, fontWeight: FontWeight.w800, height: 1.2)),
            if (v.espacio != null) ...[
              const SizedBox(height: 3),
              Text('${palabras.elEspacioConMayuscula} ${v.espacio}',
                  style: const TextStyle(
                      fontSize: 14, color: Colores.textoSuave)),
            ],

            // ---- Llamarlo: la acción real ----
            if (v.telefono != null && v.telefono!.isNotEmpty) ...[
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => _llamar(context, v.telefono!),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colores.grafito,
                    minimumSize: const Size(0, Medidas.altoBoton),
                  ),
                  icon: const Icon(Icons.phone_rounded, size: 21),
                  label: Text('Llamar a ${v.telefono}',
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w700)),
                ),
              ),
            ] else ...[
              const SizedBox(height: 12),
              const Text(
                'No tiene teléfono registrado. Avisale a la administración '
                'para que lo cargue.',
                style: TextStyle(
                    fontSize: 12.5, height: 1.4, color: Colores.textoSuave),
              ),
            ],

            // ---- El aviso, solo si NO puede entrar ----
            if (!v.puedeEntrar) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(11),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.09),
                  borderRadius: BorderRadius.circular(Medidas.redondeoChico),
                ),
                child: Text(
                  v.estaEsperandoAprobacion
                      ? 'Este auto está registrado pero la administración '
                          'todavía no lo aprobó. No debería estar adentro.'
                      : 'La administración rechazó este auto. No puede entrar.',
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.45,
                    fontWeight: FontWeight.w600,
                    color: tono,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Abre el teléfono con el número puesto. El guardia solo aprieta llamar.
  ///
  /// Si el teléfono no puede abrirlo (pasa en algunas tablets sin línea), se le
  /// copia el número al portapapeles en vez de dejarlo sin nada.
  static Future<void> _llamar(BuildContext context, String telefono) async {
    final limpio = telefono.replaceAll(RegExp(r'[^\d+]'), '');
    final destino = Uri.parse('tel:$limpio');

    try {
      final pudo = await launchUrl(destino);
      if (pudo || !context.mounted) return;
    } catch (_) {
      if (!context.mounted) return;
    }

    await Clipboard.setData(ClipboardData(text: telefono));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Este aparato no puede llamar. Copiamos el número: '
            '$telefono'),
        backgroundColor: Colores.grafito,
        duration: const Duration(seconds: 5),
      ),
    );
  }
}
