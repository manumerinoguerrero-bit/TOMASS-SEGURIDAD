// ============================================================================
// Tomass Seguridad — Pantalla 17 · Novedades del turno
// ============================================================================
// El cuaderno de novedades del guardia, pero digital y con fotos.
// "Auto mal estacionado en el 302", "portón dañado", "ruido a las 2 AM".
//
// ES LA PANTALLA MÁS SIMPLE Y LA QUE MÁS SE USA
//   Un guardia anota varias novedades por turno. Si anotar cuesta trabajo, deja
//   de hacerlo y el condominio pierde el registro. Por eso: tres toques y listo.
//   El tipo, el título y guardar. Todo lo demás es opcional.
//
// Y ES LA QUE MÁS VALOR TIENE PARA VENDER EL SISTEMA
//   Es el informe que el administrador lleva a la reunión de copropietarios:
//   con fecha, hora, foto y nombre de quién lo reportó.
// ============================================================================

import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/tema.dart';
import '../../estado/proveedores.dart';
import '../../estado/proveedores_guardia.dart';
import '../../modelos/modelos.dart';
import '../../nucleo/errores.dart';
import '../../nucleo/formato.dart';
import '../../servicios/servicio_fotos.dart';
import '../comunes/componentes.dart';
import 'acciones_de_turno.dart';

/// Genera un UUID v4 válido (formato 8-4-4-4-12 con guiones y los bits
/// de versión/variant fijos). El campo id_local en la tabla incidentes
/// es de tipo uuid, así que necesita este formato.
String _nuevoUuidV4() {
  final azar = Random.secure();
  String b(int n) => List.generate(
        n,
        (_) => azar.nextInt(256).toRadixString(16).padLeft(2, '0'),
      ).join();
  return '${b(4)}-${b(2)}-4${b(2).substring(1)}-'
      '${(8 + azar.nextInt(4)).toRadixString(16)}${b(2).substring(1)}-'
      '${b(6)}';
}

class PantallaNovedades extends ConsumerWidget {
  const PantallaNovedades({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final incidentes = ref.watch(incidentesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Novedades'),
        actions: const [MenuDelGuardia()],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _abrirFormulario(context),
        backgroundColor: Colores.grafito,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded),
        label: const Text(
          'Anotar novedad',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      body: incidentes.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: Colores.grafito),
        ),
        error: (falla, _) => Padding(
          padding: const EdgeInsets.all(Medidas.margen),
          child: AvisoDeError(
            problema: Traductor.traducir(falla),
            alReintentar: () => ref.invalidate(incidentesProvider),
          ),
        ),
        data: (lista) {
          if (lista.isEmpty) {
            // Antes había un botón "Anotar la primera" acá adentro que
            // duplicaba al FAB flotante. Se quitó a pedido: alcanza con
            // el FAB que ya está siempre visible abajo a la derecha.
            return const ListaVacia(
              icono: Icons.event_note_outlined,
              titulo: 'No hay novedades anotadas',
              explicacion:
                  'Anotá lo que pasa en tu turno: autos mal estacionados, '
                  'ruidos, daños, cualquier cosa que convenga dejar '
                  'registrada. Tocá el botón "+ Anotar novedad" abajo.',
            );
          }

          final abiertas = lista.where((i) => !i.estaCerrado).toList();
          final cerradas = lista.where((i) => i.estaCerrado).toList();

          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(incidentesProvider),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                  Medidas.margen, Medidas.margen, Medidas.margen, 90),
              children: [
                if (abiertas.isNotEmpty) ...[
                  Text('SIN RESOLVER · ${abiertas.length}',
                      style: Theme.of(context).textTheme.labelSmall),
                  const SizedBox(height: 9),
                  for (final i in abiertas)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 11),
                      child: _Tarjeta(incidente: i),
                    ),
                  const SizedBox(height: 14),
                ],
                if (cerradas.isNotEmpty) ...[
                  Text('YA RESUELTAS',
                      style: Theme.of(context).textTheme.labelSmall),
                  const SizedBox(height: 9),
                  for (final i in cerradas)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 11),
                      child: _Tarjeta(incidente: i),
                    ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  void _abrirFormulario(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colores.superficie,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const _FormularioNovedad(),
    );
  }
}

// ============================================================================
// La tarjeta de una novedad
// ============================================================================

class _Tarjeta extends StatelessWidget {
  const _Tarjeta({required this.incidente});

  final Incidente incidente;

  @override
  Widget build(BuildContext context) {
    final i = incidente;
    final (color, tono) = switch (i.gravedad) {
      GravedadIncidente.critica => (Colores.rojo, TonoEtiqueta.malo),
      GravedadIncidente.alta => (Colores.rojo, TonoEtiqueta.malo),
      GravedadIncidente.media => (Colores.naranja, TonoEtiqueta.espera),
      GravedadIncidente.baja => (Colores.textoSuave, TonoEtiqueta.neutro),
    };

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Medidas.redondeo),
        side: BorderSide(
          color: i.estaCerrado ? Colores.linea : color.withValues(alpha: 0.55),
          width: i.estaCerrado ? 1 : 1.4,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(13),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.11),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Icon(_icono(i.tipo), size: 18, color: color),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        i.titulo,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          height: 1.25,
                          decoration: i.estaCerrado
                              ? TextDecoration.lineThrough
                              : null,
                          color: i.estaCerrado
                              ? Colores.textoSuave
                              : Colores.texto,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        [
                          i.tipo.nombreVisible,
                          Formato.cuandoRelativo(i.ocurridoEn),
                          if (i.unidad != null) 'unidad ${i.unidad}',
                        ].join(' · '),
                        style: const TextStyle(
                            fontSize: 11.5, color: Colores.textoSuave),
                      ),
                    ],
                  ),
                ),
                if (i.estaCerrado)
                  const Etiqueta(texto: 'Resuelta', tono: TonoEtiqueta.bueno)
                else
                  Etiqueta(texto: i.gravedad.nombreVisible, tono: tono),
              ],
            ),

            if (i.descripcion != null && i.descripcion!.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                i.descripcion!,
                style: const TextStyle(
                    fontSize: 12.5, height: 1.45, color: Colores.textoSuave),
              ),
            ],

            if (i.fotos.isNotEmpty) ...[
              const SizedBox(height: 10),
              SizedBox(
                height: 62,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: i.fotos.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, n) => FotoDelServidor(
                    ruta: i.fotos[n],
                    cajon: CajonDeFotos.paquetes,
                    ancho: 84,
                    alto: 62,
                    iconoSiFalta: Icons.image_outlined,
                  ),
                ),
              ),
            ],

            if (i.patente != null || i.reportadoPor != null) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  if (i.patente != null) ...[
                    const Icon(Icons.directions_car_outlined,
                        size: 14, color: Colores.textoTenue),
                    const SizedBox(width: 5),
                    Text(
                      i.patente!,
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: Colores.textoSuave,
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                  if (i.reportadoPor != null)
                    Expanded(
                      child: Text(
                        'Anotó ${Formato.nombreCorto(i.reportadoPor!)}',
                        style: const TextStyle(
                            fontSize: 11, color: Colores.textoTenue),
                      ),
                    ),
                ],
              ),
            ],

            if (i.estaCerrado && i.notaResolucion != null) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colores.verde.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(Medidas.redondeoChico),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.check_circle_outline_rounded,
                        size: 15, color: Colores.verdeOscuro),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        i.notaResolucion!,
                        style: const TextStyle(
                            fontSize: 12, height: 1.4, color: Colores.verdeOscuro),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static IconData _icono(TipoIncidente tipo) => switch (tipo) {
        TipoIncidente.estacionamiento => Icons.local_parking_rounded,
        TipoIncidente.ruido => Icons.volume_up_rounded,
        TipoIncidente.danoPropiedad => Icons.broken_image_rounded,
        TipoIncidente.personaSospechosa => Icons.person_search_rounded,
        TipoIncidente.mascota => Icons.pets_rounded,
        TipoIncidente.basura => Icons.delete_outline_rounded,
        TipoIncidente.emergenciaMedica => Icons.medical_services_rounded,
        TipoIncidente.fallaTecnica => Icons.build_rounded,
        TipoIncidente.otro => Icons.more_horiz_rounded,
      };
}

// ============================================================================
// Anotar una novedad
// ============================================================================

class _FormularioNovedad extends ConsumerStatefulWidget {
  const _FormularioNovedad();

  @override
  ConsumerState<_FormularioNovedad> createState() => _EstadoFormulario();
}

class _EstadoFormulario extends ConsumerState<_FormularioNovedad> {
  final _titulo = TextEditingController();
  final _descripcion = TextEditingController();
  final _patente = TextEditingController();

  TipoIncidente _tipo = TipoIncidente.estacionamiento;
  GravedadIncidente _gravedad = GravedadIncidente.baja;
  final List<File> _fotos = [];
  bool _guardando = false;
  ErrorAmigable? _problema;

  @override
  void dispose() {
    _titulo.dispose();
    _descripcion.dispose();
    _patente.dispose();
    super.dispose();
  }

  Future<void> _agregarFoto() async {
    if (_fotos.length >= 3) return;
    try {
      final foto = await ref.read(servicioFotosProvider).sacarFoto();
      if (foto != null && mounted) setState(() => _fotos.add(foto));
    } catch (falla) {
      if (mounted) setState(() => _problema = Traductor.traducir(falla));
    }
  }

  Future<void> _guardar() async {
    if (_titulo.text.trim().length < 4) {
      setState(() => _problema = const ErrorAmigable(
            'Escribí de qué se trata.',
            detalle: 'Una frase corta alcanza: "Auto ajeno en el 302".',
            sePuedeReintentar: false,
          ));
      return;
    }

    final perfil = ref.read(perfilProvider).valueOrNull;
    final turno = ref.read(miTurnoProvider).valueOrNull;
    if (perfil == null) return;

    FocusScope.of(context).unfocus();
    setState(() {
      _guardando = true;
      _problema = null;
    });

    try {
      await ref.read(servicioGuardiaProvider).reportarIncidente(
            condominioId: perfil.condominioId,
            // El campo id_local en incidentes es de tipo uuid; antes se
            // armaba a mano concatenando hex, y Postgres rechazaba con
            // "invalid input for type uuid". Ahora es UUID v4 real.
            idLocal: _nuevoUuidV4(),
            tipo: _tipo,
            gravedad: _gravedad,
            titulo: _titulo.text,
            descripcion: _descripcion.text,
            fotos: _fotos,
            patente: _patente.text,
            turnoId: turno?.id,
            puntoAccesoId: turno?.puntoAccesoId,
          );

      ref.invalidate(incidentesProvider);
      ref.invalidate(resumenProvider);

      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Novedad anotada.'),
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
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 18),
                  decoration: BoxDecoration(
                    color: Colores.linea,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              Text('Anotar una novedad',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 3),
              const Text(
                'Queda con la fecha, la hora y tu nombre.',
                style: TextStyle(fontSize: 13, color: Colores.textoSuave),
              ),

              const SizedBox(height: 16),

              if (_problema != null) ...[
                AvisoDeError(problema: _problema!),
                const SizedBox(height: 14),
              ],

              // ---- Tipo ----
              Text('¿DE QUÉ SE TRATA?',
                  style: Theme.of(context).textTheme.labelSmall),
              const SizedBox(height: 9),
              Wrap(
                spacing: 7,
                runSpacing: 7,
                children: [
                  for (final t in TipoIncidente.values)
                    ChoiceChip(
                      label: Text(t.nombreVisible),
                      selected: _tipo == t,
                      onSelected: _guardando
                          ? null
                          : (_) => setState(() => _tipo = t),
                      selectedColor: Colores.grafito,
                      labelStyle: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: _tipo == t ? Colors.white : Colores.texto,
                      ),
                      side: const BorderSide(color: Colores.linea),
                      showCheckmark: false,
                    ),
                ],
              ),

              const SizedBox(height: 18),

              // ---- Título ----
              TextField(
                controller: _titulo,
                enabled: !_guardando,
                textCapitalization: TextCapitalization.sentences,
                maxLength: 90,
                decoration: const InputDecoration(
                  labelText: 'En pocas palabras',
                  hintText: 'Auto ajeno en el estacionamiento del 302',
                ),
              ),

              // ---- Gravedad ----
              Text('¿QUÉ TAN GRAVE ES?',
                  style: Theme.of(context).textTheme.labelSmall),
              const SizedBox(height: 9),
              Row(
                children: [
                  for (final g in GravedadIncidente.values) ...[
                    Expanded(
                      child: GestureDetector(
                        onTap: _guardando
                            ? null
                            : () => setState(() => _gravedad = g),
                        child: Container(
                          margin: const EdgeInsets.only(right: 6),
                          padding: const EdgeInsets.symmetric(vertical: 11),
                          decoration: BoxDecoration(
                            color: _gravedad == g
                                ? _colorGravedad(g)
                                : Colores.superficie,
                            borderRadius:
                                BorderRadius.circular(Medidas.redondeoChico),
                            border: Border.all(
                              color: _gravedad == g
                                  ? _colorGravedad(g)
                                  : Colores.linea,
                              width: 1.4,
                            ),
                          ),
                          child: Text(
                            g.nombreVisible,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: _gravedad == g
                                  ? Colors.white
                                  : Colores.textoSuave,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),

              const SizedBox(height: 18),

              // ---- Detalle y patente ----
              TextField(
                controller: _descripcion,
                enabled: !_guardando,
                maxLines: 3,
                maxLength: 400,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Detalle (opcional)',
                  hintText: 'Contá qué pasó, a qué hora, quién estaba…',
                  alignLabelWithHint: true,
                ),
              ),
              TextField(
                controller: _patente,
                enabled: !_guardando,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  labelText: 'Patente involucrada (opcional)',
                  hintText: 'BCDF-12',
                  prefixIcon: Icon(Icons.directions_car_outlined),
                ),
              ),

              const SizedBox(height: 16),

              // ---- Fotos ----
              Text('FOTOS (OPCIONAL, HASTA 3)',
                  style: Theme.of(context).textTheme.labelSmall),
              const SizedBox(height: 9),
              Row(
                children: [
                  for (final foto in _fotos)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Stack(
                        children: [
                          ClipRRect(
                            borderRadius:
                                BorderRadius.circular(Medidas.redondeoChico),
                            child: Image.file(foto,
                                width: 74, height: 74, fit: BoxFit.cover),
                          ),
                          Positioned(
                            right: 2,
                            top: 2,
                            child: GestureDetector(
                              onTap: () => setState(() => _fotos.remove(foto)),
                              child: Container(
                                padding: const EdgeInsets.all(3),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.65),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.close_rounded,
                                    size: 13, color: Colors.white),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (_fotos.length < 3)
                    GestureDetector(
                      onTap: _guardando ? null : _agregarFoto,
                      child: Container(
                        width: 74,
                        height: 74,
                        decoration: BoxDecoration(
                          color: Colores.grafito.withValues(alpha: 0.04),
                          borderRadius:
                              BorderRadius.circular(Medidas.redondeoChico),
                          border: Border.all(
                            color: Colores.grafito.withValues(alpha: 0.28),
                          ),
                        ),
                        child: const Icon(Icons.add_a_photo_outlined,
                            size: 22, color: Colores.textoSuave),
                      ),
                    ),
                ],
              ),

              const SizedBox(height: 20),

              ElevatedButton.icon(
                onPressed: _guardando ? null : _guardar,
                icon: _guardando
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2.4, color: Colors.white),
                      )
                    : const Icon(Icons.save_rounded, size: 21),
                label: Text(_guardando ? 'Guardando…' : 'Guardar novedad'),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size.fromHeight(Medidas.altoBoton),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Color _colorGravedad(GravedadIncidente g) => switch (g) {
        GravedadIncidente.baja => Colores.textoSuave,
        GravedadIncidente.media => Colores.naranja,
        GravedadIncidente.alta => Colores.rojo,
        GravedadIncidente.critica => Colores.rojoOscuro,
      };
}
