// ============================================================================
// Tomass Seguridad — Detalle de novedad (rol admin)
// ============================================================================
// La pantalla que el administrador abre al tocar una fila del listado de
// novedades. Sirve para:
//
//   * Leer la novedad completa que dejó el guardia (descripción + fotos).
//   * Dejar constancia de qué se hizo o qué pasos se sugirieron.
//   * Marcarla como resuelta.
//
// Una vez resuelta, la nota y quién la cerró quedan para siempre — igual que
// el registro original. Es lo mismo que exige el mandante cuando pregunta
// "¿qué hicieron con la novedad del 4 de septiembre?".
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/tema.dart';
import '../../estado/proveedores.dart';
import '../../estado/proveedores_admin.dart';
import '../../modelos/admin.dart';
import '../../nucleo/errores.dart';
import '../../nucleo/formato.dart';
import '../../servicios/servicio_fotos.dart';

class PantallaDetalleNovedad extends ConsumerStatefulWidget {
  const PantallaDetalleNovedad({super.key, required this.incidente});

  final IncidenteAdmin incidente;

  @override
  ConsumerState<PantallaDetalleNovedad> createState() =>
      _EstadoDetalleNovedad();
}

class _EstadoDetalleNovedad extends ConsumerState<PantallaDetalleNovedad> {
  final _controladorNota = TextEditingController();
  bool _resolviendo = false;

  @override
  void dispose() {
    _controladorNota.dispose();
    super.dispose();
  }

  Future<void> _marcarResuelta() async {
    final nota = _controladorNota.text.trim();
    if (nota.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Dejá escrito qué se hizo o qué pasos se sugirieron '
              'antes de marcar como resuelta.'),
          backgroundColor: Colores.naranja,
        ),
      );
      return;
    }

    setState(() => _resolviendo = true);
    try {
      await ref
          .read(servicioAdminProvider)
          .resolverIncidente(id: widget.incidente.id, nota: nota);

      if (!mounted) return;
      // Al refrescar el provider de incidentes, la lista de arriba se recarga
      // y el badge de "novedades abiertas" baja de una.
      ref.invalidate(incidentesAdminProvider);
      ref.invalidate(resumenAdminProvider);

      // Capturamos el ScaffoldMessenger ANTES de pop — después del pop el
      // widget queda desmontado y ScaffoldMessenger.of(context) buscaría en
      // un árbol que ya no existe. Con la referencia capturada, el snack
      // se muestra correctamente en la pantalla anterior (la lista de
      // novedades) al volver.
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).pop(true);
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Novedad marcada como resuelta.'),
          backgroundColor: Colores.verde,
        ),
      );
    } catch (falla) {
      if (!mounted) return;
      setState(() => _resolviendo = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(Traductor.traducir(falla).mensaje),
          backgroundColor: Colores.rojo,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final i = widget.incidente;
    final gravedadColor = switch ((i.gravedad ?? 'baja').toLowerCase()) {
      'critica' || 'critico' || 'alta' => Colores.rojo,
      'media' => Colores.naranja,
      _ => Colores.verde,
    };

    return Scaffold(
      appBar: AppBar(
        title: const Text('Novedad'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(Medidas.margen),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ---- Badges: gravedad + tipo + estado ----
            Row(
              children: [
                _Insignia(texto: (i.gravedad ?? 'baja').toUpperCase(),
                    fondo: gravedadColor, tinta: Colors.white),
                const SizedBox(width: 8),
                Text(
                  i.tipo.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    color: Colores.textoSuave,
                    letterSpacing: 0.7,
                  ),
                ),
                const Spacer(),
                _Insignia(
                  texto: i.abierta ? 'ABIERTA' : 'RESUELTA',
                  fondo: (i.abierta ? Colores.naranja : Colores.verde)
                      .withValues(alpha: 0.15),
                  tinta: i.abierta
                      ? Colores.naranjaOscuro
                      : Colores.verdeOscuro,
                ),
              ],
            ),
            const SizedBox(height: 12),

            // ---- Título de la novedad ----
            Text(
              i.titulo,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                height: 1.25,
              ),
            ),
            const SizedBox(height: 12),

            // ---- Descripción ----
            if (i.descripcion != null && i.descripcion!.isNotEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colores.grafito.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(Medidas.redondeoChico),
                ),
                child: Text(
                  i.descripcion!,
                  style: const TextStyle(fontSize: 14, height: 1.45),
                ),
              ),
            const SizedBox(height: 14),

            // ---- Metadatos ----
            _Fila('Cuándo', Formato.fechaYHora(i.ocurridoEn)),
            if (i.reportadoPor != null)
              _Fila('Reportado por', i.reportadoPor!),
            if (i.ubicacion != null) _Fila('Dónde', i.ubicacion!),
            if (i.unidadTexto != null) _Fila('Unidad', i.unidadTexto!),
            if (i.patente != null) _Fila('Patente', i.patente!),
            const SizedBox(height: 16),

            // ---- Fotos ----
            if (i.tieneFotos) ...[
              const Text(
                'FOTOS',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: Colores.textoSuave,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 140,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: i.fotos.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (_, idx) => _MiniaturaFoto(
                    ruta: i.fotos[idx],
                    alTocar: () => _abrirFotoFullscreen(i.fotos[idx]),
                  ),
                ),
              ),
              const SizedBox(height: 20),
            ],

            const Divider(),
            const SizedBox(height: 8),

            // ---- Sección de resolución ----
            if (!i.abierta) ...[
              // Ya está resuelta: mostrar la nota + cuándo
              const Text(
                'CÓMO SE RESOLVIÓ',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: Colores.verdeOscuro,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colores.verde.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(Medidas.redondeoChico),
                  border: Border.all(
                      color: Colores.verde.withValues(alpha: 0.35)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      i.notaResolucion?.isNotEmpty == true
                          ? i.notaResolucion!
                          : '(Sin nota registrada)',
                      style: const TextStyle(fontSize: 14, height: 1.5),
                    ),
                    if (i.resueltoEn != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Resuelta el ${Formato.fechaYHora(i.resueltoEn!)}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colores.textoSuave,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ] else ...[
              // Todavía abierta: input + botón
              const Text(
                'QUÉ SE HIZO O QUÉ PASOS SE SUGIRIERON',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: Colores.grafito,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _controladorNota,
                minLines: 3,
                maxLines: 8,
                textCapitalization: TextCapitalization.sentences,
                enabled: !_resolviendo,
                decoration: InputDecoration(
                  hintText: 'Ej.: Se le aviso al supervisor. Se pidió al '
                      'residente que sacara la basura en el horario '
                      'correspondiente.',
                  hintStyle: const TextStyle(
                    color: Colores.textoTenue,
                    fontStyle: FontStyle.italic,
                    fontSize: 13,
                  ),
                  border: OutlineInputBorder(
                    borderRadius:
                        BorderRadius.circular(Medidas.redondeoChico),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _resolviendo ? null : _marcarResuelta,
                  icon: _resolviendo
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.check_circle_rounded, size: 20),
                  label: Text(
                    _resolviendo ? 'Guardando…' : 'Marcar como resuelta',
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w800),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colores.verde,
                    minimumSize: const Size(0, Medidas.altoBoton),
                  ),
                ),
              ),
            ],

            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  void _abrirFotoFullscreen(String ruta) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => _VisorFotoFullscreen(ruta: ruta),
      fullscreenDialog: true,
    ));
  }
}

// ============================================================================
// Badge de gravedad / tipo / estado
// ============================================================================

class _Insignia extends StatelessWidget {
  const _Insignia({required this.texto, required this.fondo, required this.tinta});
  final String texto;
  final Color fondo;
  final Color tinta;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: fondo,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        texto,
        style: TextStyle(
          color: tinta,
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

// ============================================================================
// Fila etiqueta ─ valor
// ============================================================================

class _Fila extends StatelessWidget {
  const _Fila(this.etiqueta, this.valor);
  final String etiqueta;
  final String valor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              etiqueta,
              style: const TextStyle(fontSize: 12, color: Colores.textoSuave),
            ),
          ),
          Expanded(
            child: Text(
              valor,
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// Miniatura de foto en la lista horizontal
// ============================================================================

class _MiniaturaFoto extends ConsumerWidget {
  const _MiniaturaFoto({required this.ruta, required this.alTocar});
  final String ruta;
  final VoidCallback alTocar;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final futuro = ref.watch(_enlaceIncidenteProvider(ruta));
    return futuro.when(
      loading: () => _placeholder(cargando: true),
      error: (_, __) => _placeholder(),
      data: (enlace) {
        if (enlace == null) return _placeholder();
        return InkWell(
          onTap: alTocar,
          borderRadius: BorderRadius.circular(10),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.network(
              enlace,
              width: 140,
              height: 140,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _placeholder(),
            ),
          ),
        );
      },
    );
  }

  Widget _placeholder({bool cargando = false}) => Container(
        width: 140,
        height: 140,
        decoration: BoxDecoration(
          color: Colores.grafito.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(10),
        ),
        alignment: Alignment.center,
        child: cargando
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.broken_image_outlined,
                size: 32, color: Colores.textoTenue),
      );
}

/// Cache de enlaces temporales de fotos de incidentes (mismo bucket que
/// paquetes — los guardias fotografían la novedad con la misma cámara).
final _enlaceIncidenteProvider =
    FutureProvider.family<String?, String>((ref, ruta) {
  return ref
      .watch(servicioFotosProvider)
      .enlaceTemporal(ruta, CajonDeFotos.paquetes);
});

// ============================================================================
// Visor de foto a pantalla completa
// ============================================================================

class _VisorFotoFullscreen extends ConsumerWidget {
  const _VisorFotoFullscreen({required this.ruta});
  final String ruta;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final futuro = ref.watch(_enlaceIncidenteProvider(ruta));
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Center(
        child: futuro.when(
          loading: () => const CircularProgressIndicator(color: Colors.white),
          error: (_, __) => const Icon(Icons.broken_image_outlined,
              color: Colors.white54, size: 80),
          data: (enlace) => enlace == null
              ? const Icon(Icons.broken_image_outlined,
                  color: Colors.white54, size: 80)
              : InteractiveViewer(
                  child: Image.network(enlace, fit: BoxFit.contain),
                ),
        ),
      ),
    );
  }
}
