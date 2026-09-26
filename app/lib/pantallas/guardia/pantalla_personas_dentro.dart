// ============================================================================
// Tomass Seguridad — Guardia · Personas dentro
// ============================================================================
// LO QUE HACE
//
//   Le muestra al guardia la lista COMPLETA de quiénes están adentro ahora
//   mismo: cada persona que registró entrada y no marcó salida todavía.
//
//   El panel principal ya trae un resumen con los primeros 6 y dice "y N más".
//   Esta pantalla es para cuando el guardia necesita buscar a alguien puntual,
//   verificar que nadie quedó adentro al fin del turno, o pasarle a Manuel
//   la lista para el conteo.
//
//   Se puede filtrar por nombre, unidad o patente. La búsqueda no toca el
//   servidor: se hace en memoria sobre la lista que ya tiene el provider.
// ============================================================================

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/tema.dart';
import '../../estado/proveedores_guardia.dart';
import '../../nucleo/errores.dart';
import '../../nucleo/formato.dart';
import '../comunes/componentes.dart';

class PantallaPersonasDentro extends ConsumerStatefulWidget {
  const PantallaPersonasDentro({super.key});

  @override
  ConsumerState<PantallaPersonasDentro> createState() =>
      _EstadoPersonasDentro();
}

class _EstadoPersonasDentro extends ConsumerState<PantallaPersonasDentro> {
  final _busqueda = TextEditingController();

  @override
  void dispose() {
    _busqueda.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final personas = ref.watch(personasDentroProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Personas dentro'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Actualizar',
            onPressed: () => ref.invalidate(personasDentroProvider),
          ),
        ],
      ),
      body: personas.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: Colores.grafito),
        ),
        error: (falla, _) => Padding(
          padding: const EdgeInsets.all(Medidas.margen),
          child: AvisoDeError(
            problema: Traductor.traducir(falla),
            alReintentar: () => ref.invalidate(personasDentroProvider),
          ),
        ),
        data: (lista) {
          final filtrada = _filtrar(lista, _busqueda.text);
          final raras = filtrada.where((p) => p['estadia_inusual'] == true).length;

          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(personasDentroProvider),
            child: Column(
              children: [
                // ---- Contador arriba ----
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                      Medidas.margen, Medidas.margen, Medidas.margen, 4),
                  child: Row(
                    children: [
                      Icon(Icons.people_rounded,
                          size: 20, color: Colores.grafito),
                      const SizedBox(width: 8),
                      Text(
                        _busqueda.text.isEmpty
                            ? '${lista.length} personas adentro ahora'
                            : '${filtrada.length} de ${lista.length}',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Colores.grafito,
                        ),
                      ),
                      const Spacer(),
                      if (raras > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colores.naranja.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.schedule_rounded,
                                  size: 13, color: Colores.naranjaOscuro),
                              const SizedBox(width: 4),
                              Text(
                                '$raras hace mucho',
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700,
                                  color: Colores.naranjaOscuro,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),

                // ---- Buscador ----
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: Medidas.margen, vertical: 8),
                  child: TextField(
                    controller: _busqueda,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      hintText: 'Buscar por nombre, unidad o patente',
                      prefixIcon: const Icon(Icons.search_rounded),
                      suffixIcon: _busqueda.text.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.close_rounded),
                              onPressed: () => setState(() {
                                _busqueda.clear();
                              }),
                            ),
                      border: OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(Medidas.redondeoChico),
                      ),
                      isDense: true,
                    ),
                  ),
                ),

                // ---- Lista ----
                Expanded(
                  child: filtrada.isEmpty
                      ? _vacio(lista.isEmpty)
                      : ListView.separated(
                          padding: const EdgeInsets.symmetric(
                              horizontal: Medidas.margen, vertical: 8),
                          itemCount: filtrada.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 6),
                          itemBuilder: (_, i) =>
                              _TarjetaPersona(persona: filtrada[i]),
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _vacio(bool listaVaciaTotal) {
    if (listaVaciaTotal) {
      return const ListaVacia(
        icono: Icons.people_outline_rounded,
        titulo: 'No hay nadie registrado adentro',
        explicacion:
            'Cuando alguien pase y registre entrada, va a aparecer acá con '
            'nombre, unidad y hora.',
      );
    }
    return const ListaVacia(
      icono: Icons.search_off_rounded,
      titulo: 'Ninguna persona coincide',
      explicacion:
          'Probá con menos texto o revisá cómo lo escribiste. La búsqueda '
          'no distingue mayúsculas ni tildes.',
    );
  }

  static List<Map<String, dynamic>> _filtrar(
      List<Map<String, dynamic>> lista, String busqueda) {
    final q = _normalizar(busqueda);
    if (q.isEmpty) return lista;
    return lista.where((p) {
      final nombre = _normalizar(p['nombre']?.toString() ?? '');
      final unidad = _normalizar(p['unidad']?.toString() ?? '');
      final patente = _normalizar(p['patente']?.toString() ?? '');
      return nombre.contains(q) ||
          unidad.contains(q) ||
          patente.contains(q);
    }).toList();
  }

  /// Normaliza para buscar: baja, saca tildes, elimina separadores.
  /// Así "Peréz", "PEREZ" y "perez" son la misma cosa para el buscador.
  static String _normalizar(String s) {
    return s
        .toLowerCase()
        .replaceAll(RegExp('[áàä]'), 'a')
        .replaceAll(RegExp('[éèë]'), 'e')
        .replaceAll(RegExp('[íìï]'), 'i')
        .replaceAll(RegExp('[óòö]'), 'o')
        .replaceAll(RegExp('[úùü]'), 'u')
        .replaceAll('ñ', 'n')
        .replaceAll(RegExp('[^a-z0-9]+'), '');
  }
}

// ============================================================================
// Tarjeta de una persona
// ============================================================================

class _TarjetaPersona extends ConsumerStatefulWidget {
  const _TarjetaPersona({required this.persona});

  final Map<String, dynamic> persona;

  @override
  ConsumerState<_TarjetaPersona> createState() => _EstadoTarjetaPersona();
}

class _EstadoTarjetaPersona extends ConsumerState<_TarjetaPersona> {
  bool _cerrando = false;

  Future<void> _marcarSalida() async {
    final persona = widget.persona;
    final tipo = persona['persona_tipo']?.toString();
    final id = persona['persona_id']?.toString();
    if (tipo == null || id == null) return;

    final nombre = persona['nombre']?.toString() ?? 'esta persona';

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('¿Marcar salida?'),
        content: Text(
          'Se va a registrar la salida de $nombre con la hora de ahora. '
          'Los datos (unidad, patente, quién autorizó) se copian del último '
          'ingreso.',
          style: const TextStyle(fontSize: 13.5, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colores.grafito),
            child: const Text('Sí, marcar salida'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _cerrando = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(servicioGuardiaProvider).registrarSalidaRapida(
            personaTipo: tipo,
            personaId: id,
            idLocal: _nuevoUuidV4(),
          );
      ref.invalidate(personasDentroProvider);
      ref.invalidate(ultimosAccesosProvider);
      ref.invalidate(resumenProvider);
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text('Salida marcada: $nombre.'),
          backgroundColor: Colores.verde,
        ),
      );
    } catch (falla) {
      if (!mounted) return;
      setState(() => _cerrando = false);
      messenger.showSnackBar(
        SnackBar(
          content: Text(Traductor.traducir(falla).mensaje),
          backgroundColor: Colores.rojo,
        ),
      );
    }
  }

  /// UUID v4 idempotency key para que si el guardia toca dos veces por
  /// lag, la salida se registre una sola vez en el servidor.
  static String _nuevoUuidV4() {
    final azar = Random.secure();
    String b(int n) => List.generate(
          n,
          (_) => azar.nextInt(256).toRadixString(16).padLeft(2, '0'),
        ).join();
    return '${b(4)}-${b(2)}-4${b(2).substring(1)}-'
        '${(8 + azar.nextInt(4)).toRadixString(16)}${b(2).substring(1)}-'
        '${b(6)}';
  }

  @override
  Widget build(BuildContext context) {
    final persona = widget.persona;
    final tipo = persona['persona_tipo']?.toString() ?? 'residente';
    final raro = persona['estadia_inusual'] == true;
    final entro = DateTime.tryParse(persona['entro_en']?.toString() ?? '');

    final (icono, nombreTipo, colorIcono) = switch (tipo) {
      'visita' => (
          Icons.person_add_alt_rounded,
          'Visita',
          Colores.dorado
        ),
      'personal_servicio' => (
          Icons.handyman_rounded,
          'Personal',
          Colores.grafito
        ),
      _ => (Icons.home_rounded, 'Residente', Colores.verdeOscuro),
    };

    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Medidas.redondeoChico),
        side: BorderSide(
          color: raro
              ? Colores.naranja.withValues(alpha: 0.6)
              : Colores.linea,
          width: raro ? 1.2 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: colorIcono.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icono, size: 20, color: colorIcono),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    persona['nombre']?.toString() ?? '—',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    [
                      nombreTipo,
                      if (persona['unidad'] != null)
                        'Unidad ${persona['unidad']}',
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colores.textoSuave,
                    ),
                  ),
                  if (entro != null)
                    Text(
                      'Entró ${Formato.haceCuanto(entro)}',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color:
                            raro ? Colores.naranjaOscuro : Colores.textoTenue,
                      ),
                    ),
                ],
              ),
            ),
            if (persona['patente'] != null) ...[
              const SizedBox(width: 6),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Icon(Icons.directions_car_rounded,
                      size: 14, color: Colores.textoTenue),
                  const SizedBox(height: 2),
                  Text(
                    persona['patente'].toString(),
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Colores.grafito,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(width: 4),
            // Botón "Marcar salida" — el flujo más frecuente al final del
            // turno. Antes había que ir a Registrar y reescribir todo.
            IconButton(
              tooltip: 'Marcar salida',
              icon: _cerrando
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colores.grafito,
                      ),
                    )
                  : const Icon(Icons.logout_rounded, size: 20),
              color: Colores.grafito,
              onPressed: _cerrando ? null : _marcarSalida,
            ),
          ],
        ),
      ),
    );
  }
}
