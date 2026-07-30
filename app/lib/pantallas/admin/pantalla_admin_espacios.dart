// ============================================================================
// Tomass Seguridad — Panel de administración · Espacios
// ============================================================================
// Las unidades de un condominio, o los cursos de un colegio. Hay que cargarlos
// antes de dar de alta gente, porque cada persona se cuelga de uno.
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

class PantallaAdminEspacios extends ConsumerWidget {
  const PantallaAdminEspacios({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final espacios = ref.watch(espaciosProvider);
    final palabras = ref.watch(palabrasProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(palabras.losEspaciosConMayuscula),
        actions: const [MenuDelAdmin()],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _abrirFormulario(context),
        backgroundColor: Colores.grafito,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded),
        label: Text('Agregar ${palabras.elEspacio}',
            style: const TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: espacios.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: Colores.grafito),
        ),
        error: (falla, _) => Padding(
          padding: const EdgeInsets.all(Medidas.margen),
          child: AvisoDeError(
            problema: Traductor.traducir(falla),
            alReintentar: () => ref.invalidate(espaciosProvider),
          ),
        ),
        data: (lista) {
          if (lista.isEmpty) {
            return ListaVacia(
              icono: Icons.meeting_room_outlined,
              titulo: 'Todavía no hay ${palabras.losEspacios}',
              explicacion:
                  'Cargá acá ${palabras.losEspacios} antes de dar de alta '
                  'gente: cada persona se asigna a uno.',
              accion: ElevatedButton.icon(
                onPressed: () => _abrirFormulario(context),
                icon: const Icon(Icons.add_rounded, size: 20),
                label: Text('Agregar ${palabras.elEspacio}'),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(0, Medidas.altoBoton),
                  padding: const EdgeInsets.symmetric(horizontal: 22),
                ),
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(espaciosProvider),
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(
                  Medidas.margen, Medidas.margen, Medidas.margen, 92),
              itemCount: lista.length,
              // Llave por si esta fila alguna vez toma estado propio: sin
              // ella, al borrar un espacio la siguiente heredaria su estado.
              itemBuilder: (_, i) =>
                  _Fila(key: ValueKey(lista[i].id), espacio: lista[i]),
            ),
          );
        },
      ),
    );
  }

  static void _abrirFormulario(BuildContext context, {EspacioAdmin? espacio}) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colores.superficie,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _FormularioEspacio(espacio: espacio),
    );
  }
}

class _Fila extends ConsumerWidget {
  const _Fila({super.key, required this.espacio});

  final EspacioAdmin espacio;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        onTap: () =>
            PantallaAdminEspacios._abrirFormulario(context, espacio: espacio),
        leading: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: Colores.grafito.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(11),
          ),
          child: const Icon(Icons.meeting_room_outlined,
              size: 20, color: Colores.grafito),
        ),
        title: Text(espacio.nombreCompleto,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        subtitle: Text(
          espacio.estacionamientos > 0
              ? '${espacio.estacionamientos} '
                  '${espacio.estacionamientos == 1 ? "estacionamiento" : "estacionamientos"}'
              : 'Sin estacionamiento',
          style: const TextStyle(fontSize: 12),
        ),
        trailing: IconButton(
          icon: const Icon(Icons.delete_outline_rounded,
              size: 21, color: Colores.textoTenue),
          tooltip: 'Borrar',
          onPressed: () => _borrar(context, ref),
        ),
      ),
    );
  }

  Future<void> _borrar(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('¿Borrar ${espacio.nombreCompleto}?'),
        content: const Text(
          'Si hay personas asignadas, no se va a poder borrar hasta que las '
          'cambies de lugar.',
          style: TextStyle(fontSize: 13.5, height: 1.45),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colores.rojo),
            child: const Text('Borrar'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;

    try {
      await ref.read(servicioAdminProvider).borrarEspacio(espacio.id);
      if (!context.mounted) return;
      ref.invalidate(espaciosProvider);
      ref.invalidate(resumenAdminProvider);
    } catch (falla) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(Traductor.traducir(falla).mensaje),
          backgroundColor: Colores.rojo,
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }
}

// ============================================================================
// EL FORMULARIO
// ============================================================================

class _FormularioEspacio extends ConsumerStatefulWidget {
  const _FormularioEspacio({this.espacio});

  final EspacioAdmin? espacio;

  @override
  ConsumerState<_FormularioEspacio> createState() => _EstadoEspacio();
}

class _EstadoEspacio extends ConsumerState<_FormularioEspacio> {
  late final _numero = TextEditingController(text: widget.espacio?.numero ?? '');
  late final _torre = TextEditingController(text: widget.espacio?.torre ?? '');
  late final _estacionamientos = TextEditingController(
      text: '${widget.espacio?.estacionamientos ?? 0}');

  bool _guardando = false;
  ErrorAmigable? _problema;

  @override
  void dispose() {
    _numero.dispose();
    _torre.dispose();
    _estacionamientos.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    final perfil = ref.read(perfilProvider).valueOrNull;
    if (perfil == null) return;

    FocusScope.of(context).unfocus();
    setState(() {
      _guardando = true;
      _problema = null;
    });

    try {
      await ref.read(servicioAdminProvider).guardarEspacio(
            id: widget.espacio?.id,
            condominioId: perfil.condominioId,
            numero: _numero.text,
            torre: _torre.text,
            tipo: _tipoSegunLaInstalacion(perfil.tipoInstalacion),
            estacionamientos: int.tryParse(_estacionamientos.text) ?? 0,
          );
      if (!mounted) return;
      ref.invalidate(espaciosProvider);
      ref.invalidate(resumenAdminProvider);
      Navigator.pop(context);
    } catch (falla) {
      if (!mounted) return;
      setState(() {
        _guardando = false;
        _problema = Traductor.traducir(falla);
      });
    }
  }

  /// El tipo se deduce de la instalación en vez de preguntárselo al usuario:
  /// en un colegio todos los espacios son cursos, y preguntarlo en cada alta
  /// sería una pregunta con una sola respuesta posible.
  static String _tipoSegunLaInstalacion(String? tipo) => switch (tipo) {
        'colegio' => 'curso',
        'empresa' => 'oficina',
        'edificio' => 'apartamento',
        _ => 'apartamento',
      };

  @override
  Widget build(BuildContext context) {
    final palabras = ref.watch(palabrasProvider);
    final esColegio = palabras.tipo == 'colegio';

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
              widget.espacio == null
                  ? 'Agregar ${palabras.elEspacio}'
                  : 'Editar ${widget.espacio!.nombreCompleto}',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),

            if (_problema != null) ...[
              AvisoDeError(problema: _problema!),
              const SizedBox(height: 14),
            ],

            TextField(
              controller: _numero,
              autofocus: true,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                labelText: esColegio ? 'Curso' : 'Número',
                hintText: esColegio ? 'Ej: 4°B' : 'Ej: 101',
                prefixIcon: const Icon(Icons.tag_rounded),
              ),
            ),
            const SizedBox(height: 12),

            TextField(
              controller: _torre,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                labelText: esColegio ? 'Nivel (opcional)' : 'Torre (opcional)',
                hintText: esColegio ? 'Ej: Enseñanza Básica' : 'Ej: A',
              ),
            ),

            if (!esColegio) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _estacionamientos,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Estacionamientos',
                  prefixIcon: Icon(Icons.local_parking_outlined),
                ),
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
                    : const Text('Guardar'),
              ),
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }
}
