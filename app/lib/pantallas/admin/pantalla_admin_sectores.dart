// ============================================================================
// Tomass Seguridad — Panel · Los sectores de la ronda
// ============================================================================
// QUÉ HACE EL ADMINISTRADOR ACÁ
//
//   Camina por la instalación y, parado en cada sector, toca "Agregar sector
//   acá". El teléfono guarda la ubicación de ese lugar. Después toca el sector
//   y ve el código QR para imprimirlo y pegarlo ahí mismo.
//
// POR QUÉ LA UBICACIÓN SE TOMA PARADO AHÍ Y NO SE ESCRIBE A MANO
//
//   Porque escribirla desde una oficina sería inventarla, y entonces no
//   probaría nada. La gracia de este sistema es que la ubicación del cartel es
//   REAL, tomada en el lugar.
//
// QUÉ DEFIENDE ESTO
//
//   Sin ubicación, el sistema demuestra que el guardia TUVO el código del
//   cartel. Con ubicación, demuestra que ESTUVO AHÍ.
//
//   La diferencia es concreta: sin ella, un guardia puede sacarle una foto a
//   los seis carteles el primer día y después escanear las fotos desde la
//   garita sin moverse en toda la noche. Es el primer truco que se le ocurre a
//   cualquiera, y es exactamente lo que el cliente está pagando por evitar.
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../config/tema.dart';
import '../../estado/proveedores.dart';
import '../../estado/proveedores_admin.dart';
import '../../modelos/admin.dart';
import '../../nucleo/errores.dart';
import '../../nucleo/formato.dart';
import '../../nucleo/ubicacion.dart';
import '../../servicios/cartel_de_sector_pdf.dart';
import '../comunes/componentes.dart';
import 'acciones_admin.dart';

class PantallaAdminSectores extends ConsumerStatefulWidget {
  const PantallaAdminSectores({super.key});

  @override
  ConsumerState<PantallaAdminSectores> createState() => _EstadoSectores();
}

class _EstadoSectores extends ConsumerState<PantallaAdminSectores> {
  bool _trabajando = false;

  // ==========================================================================
  // AGREGAR UN SECTOR, PARADO AHÍ
  // ==========================================================================

  Future<void> _agregarAca() async {
    setState(() => _trabajando = true);

    // ⚠️ TODO EL TRABAJO CON EL GPS VA ACÁ, ANTES DE ABRIR NINGÚN CARTEL.
    //
    //    No alcanzaba con resolver el permiso antes: el propio pedido de
    //    ubicación (Geolocator.getCurrentPosition) puede disparar OTRO aviso
    //    del sistema operativo, por ejemplo el de "activar ubicación de alta
    //    precisión". Si cualquiera de esos avisos aparece mientras se está
    //    cerrando un cartel de la app (el de "nombre del sector", por
    //    ejemplo), la interrupción deja la animación a medio camino y la app
    //    se cae con la pantalla roja. Nos volvió a pasar con el arreglo
    //    anterior, que solo cubría el permiso y no el pedido en sí.
    //
    //    Acá no hay ningún cartel de la app abierto todavía, así que
    //    cualquier aviso de Android aparece con la pantalla tranquila.
    final donde = await Localizador.donde();
    final porque = donde == null ? await Localizador.porQueNoSePudo() : null;

    if (!mounted) return;
    setState(() => _trabajando = false);

    final elegido = await _pedirNombre();
    if (elegido == null || !mounted) return;

    if (donde == null) {
      final igual = await _preguntar(
        titulo: 'No se pudo tomar la ubicación',
        texto: '${porque ?? ""}\n\nPodés crear el sector igual, pero sin '
            'ubicación el sistema no va a poder demostrar que el guardia '
            'estuvo ahí: solo que tenía el código del cartel.\n\n'
            'Después podés volver parado en el sector y tocar "Tomar '
            'ubicación acá".',
        siText: 'Crear sin ubicación',
      );
      if (igual != true || !mounted) return;

      setState(() => _trabajando = true);
      await _crear(elegido.nombre, null, elegido.puntoAccesoId);
      return;
    }

    // El GPS a veces contesta con un error enorme. Conviene decirlo antes de
    // guardar una ubicación que después va a dar falsas alarmas.
    if (!donde.esConfiable) {
      final igual = await _preguntar(
        titulo: 'La ubicación no es precisa',
        texto: 'El teléfono dice que puede errarle hasta ${donde.errorEnPalabras}. '
            'Bajo techo o entre paredes gruesas el GPS pierde precisión.\n\n'
            'Conviene salir un poco al aire libre y volver a intentar. Si la '
            'guardás así, el sistema podría marcar como sospechosas rondas que '
            'están bien.',
        siText: 'Guardar igual',
      );
      if (igual != true || !mounted) return;
    }

    setState(() => _trabajando = true);
    await _crear(elegido.nombre, donde, elegido.puntoAccesoId);
  }

  Future<void> _crear(String nombre, Ubicacion? donde, String? puntoAccesoId) async {
    try {
      await ref.read(servicioAdminProvider).crearPuntoDeControl(
            nombre: nombre,
            latitud: donde?.latitud,
            longitud: donde?.longitud,
            // Tolerancia FIJA en 20 metros: con 5m los guardias no podían
            // escanear ni parados al lado del cartel porque el GPS urbano
            // tiene error típico de 6 a 12m. 20m es el margen pedido por
            // el usuario el 01/10/2026.
            tolerancia: 20,
            puntoAccesoId: puntoAccesoId,
          );
      if (!mounted) return;
      ref.invalidate(puntosDeControlAdminProvider);
      setState(() => _trabajando = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(donde == null
              ? '$nombre creado, sin ubicación.'
              : '$nombre creado acá, con ${donde.errorEnPalabras} de precisión.'),
          backgroundColor: donde == null ? Colores.naranjaOscuro : Colores.verde,
        ),
      );
    } catch (falla) {
      if (!mounted) return;
      setState(() => _trabajando = false);
      _avisar(Traductor.traducir(falla).mensaje, malo: true);
    }
  }

  // ==========================================================================
  // TOMARLE LA UBICACIÓN A UNO QUE YA EXISTE
  // ==========================================================================

  Future<void> _ubicarAca(PuntoControlAdmin punto) async {
    setState(() => _trabajando = true);

    // Mismo motivo que en _agregarAca: TODO el trabajo con el GPS va antes
    // de abrir el cartel de confirmación, para que ningún aviso de Android
    // pueda interrumpir una animación de la app a medio camino.
    final donde = await Localizador.donde();
    final porque = donde == null ? await Localizador.porQueNoSePudo() : null;

    if (!mounted) return;
    setState(() => _trabajando = false);

    if (donde == null) {
      _avisar(porque ?? 'No se pudo.', malo: true);
      return;
    }

    final ok = await _preguntar(
      titulo: '¿Estás parado en ${punto.nombre}?',
      texto: 'La ubicación se toma DONDE ESTÁS AHORA. Si la tomás desde otro '
          'lado, todas las rondas de este sector van a aparecer marcadas como '
          'hechas desde lejos.',
      siText: 'Sí, estoy acá',
    );
    if (ok != true || !mounted) return;

    setState(() => _trabajando = true);

    try {
      await ref.read(servicioAdminProvider).ubicarPuntoDeControl(
            puntoId: punto.id,
            latitud: donde.latitud,
            longitud: donde.longitud,
            // Tolerancia FIJA: mismo valor que _crear(). 20m: con 5m los
            // guardias no podían escanear ni al lado del cartel porque el
            // GPS urbano tiene error típico de 6 a 12m.
            tolerancia: 20,
          );
      if (!mounted) return;
      ref.invalidate(puntosDeControlAdminProvider);
      setState(() => _trabajando = false);
      _avisar('${punto.nombre} quedó ubicado, con '
          '${donde.errorEnPalabras} de precisión.');
    } catch (falla) {
      if (!mounted) return;
      setState(() => _trabajando = false);
      _avisar(Traductor.traducir(falla).mensaje, malo: true);
    }
  }

  // ==========================================================================
  // AYUDANTES DE PANTALLA
  // ==========================================================================

  /// Pide nombre + garita para un sector NUEVO.
  ///
  /// El dropdown de garita solo aparece si el condominio tiene más de una
  /// (colegios con Garita 1 / Garita 2 / etc). En condominios chicos con una
  /// sola garita, no tiene sentido preguntar y se salta el paso.
  Future<({String nombre, String? puntoAccesoId})?>
      _pedirNombre() async {
    return showDialog<({String nombre, String? puntoAccesoId})>(
      context: context,
      builder: (_) => const _DialogoNombreYGarita(),
    );
  }

  /// Pide solo un nombre nuevo. Se usa al RENOMBRAR un sector existente:
  /// el punto ya tiene su garita, no queremos cambiarla acá por accidente.
  Future<String?> _pedirRenombrar({required String actual}) async {
    return showDialog<String>(
      context: context,
      builder: (_) => _DialogoNombre(actual: actual),
    );
  }

  Future<bool?> _preguntar({
    required String titulo,
    required String texto,
    required String siText,
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
            style: FilledButton.styleFrom(backgroundColor: Colores.grafito),
            child: Text(siText),
          ),
        ],
      ),
    );
  }

  void _avisar(String texto, {bool malo = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(texto),
        backgroundColor: malo ? Colores.rojo : Colores.verde,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  // ==========================================================================

  @override
  Widget build(BuildContext context) {
    final puntos = ref.watch(puntosDeControlAdminProvider);
    final sinUbicar = ref.watch(sectoresSinUbicarProvider);
    final instalacion =
        ref.watch(perfilProvider).valueOrNull?.nombreCondominio ?? 'Instalación';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sectores de la ronda'),
        actions: const [MenuDelAdmin()],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _trabajando ? null : _agregarAca,
        backgroundColor: Colores.grafito,
        foregroundColor: Colors.white,
        icon: _trabajando
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white))
            : const Icon(Icons.add_location_alt_rounded),
        label: Text(_trabajando ? 'Tomando ubicación…' : 'Agregar sector acá',
            style: const TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: puntos.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: Colores.grafito),
        ),
        error: (falla, _) => Padding(
          padding: const EdgeInsets.all(Medidas.margen),
          child: AvisoDeError(
            problema: Traductor.traducir(falla),
            alReintentar: () => ref.invalidate(puntosDeControlAdminProvider),
          ),
        ),
        data: (lista) {
          if (lista.isEmpty) {
            return const ListaVacia(
              icono: Icons.add_location_alt_outlined,
              titulo: 'Todavía no hay sectores',
              explicacion:
                  'Caminá por la instalación y, parado en cada sector, tocá '
                  '"Agregar sector acá". El teléfono guarda la ubicación del '
                  'lugar y después imprimís el cartel para pegarlo ahí.',
            );
          }

          return ListView(
            padding: const EdgeInsets.fromLTRB(
                Medidas.margen, Medidas.margen, Medidas.margen, 96),
            children: [
              if (sinUbicar > 0) _FaltanUbicar(cuantos: sinUbicar),
              for (var i = 0; i < lista.length; i++)
                _Sector(
                  punto: lista[i],
                  numero: i + 1,
                  instalacion: instalacion,
                  alUbicar: () => _ubicarAca(lista[i]),
                  alRenombrar: () async {
                    final n = await _pedirRenombrar(actual: lista[i].nombre);
                    if (n == null || !mounted) return;
                    try {
                      await ref
                          .read(servicioAdminProvider)
                          .renombrarPuntoDeControl(lista[i].id, n);
                      if (!mounted) return;
                      ref.invalidate(puntosDeControlAdminProvider);
                    } catch (falla) {
                      if (mounted) {
                        _avisar(Traductor.traducir(falla).mensaje, malo: true);
                      }
                    }
                  },
                  alDarDeBaja: () async {
                    final ok = await _preguntar(
                      titulo: '¿Sacar ${lista[i].nombre}?',
                      texto: 'Deja de aparecer en las rondas nuevas. Las rondas '
                          'viejas NO se tocan: el historial queda intacto.\n\n'
                          'Si el cartel sigue pegado, sacalo de la pared: ya no '
                          'va a funcionar.',
                      siText: 'Sacar',
                    );
                    if (ok != true || !mounted) return;
                    try {
                      await ref
                          .read(servicioAdminProvider)
                          .darDeBajaPuntoDeControl(lista[i].id);
                      if (!mounted) return;
                      ref.invalidate(puntosDeControlAdminProvider);
                    } catch (falla) {
                      if (mounted) {
                        _avisar(Traductor.traducir(falla).mensaje, malo: true);
                      }
                    }
                  },
                  alCambiarGarita: () async {
                    final nueva = await showDialog<({String? id})?>(
                      context: context,
                      builder: (_) => _DialogoCambiarGarita(
                        actualId: lista[i].puntoAccesoId,
                      ),
                    );
                    if (nueva == null || !mounted) return;
                    try {
                      await ref
                          .read(servicioAdminProvider)
                          .asignarPuntoAGarita(
                            puntoId: lista[i].id,
                            puntoAccesoId: nueva.id,
                          );
                      if (!mounted) return;
                      ref.invalidate(puntosDeControlAdminProvider);
                      _avisar('Sector reasignado.');
                    } catch (falla) {
                      if (mounted) {
                        _avisar(Traductor.traducir(falla).mensaje, malo: true);
                      }
                    }
                  },
                ),
            ],
          );
        },
      ),
    );
  }
}

// ============================================================================
// EL DIÁLOGO DEL NOMBRE
// ============================================================================
// Es un StatefulWidget solo para que el TextEditingController viva junto al
// TextField, y se disponga cuando el propio diálogo se desmonta. Cualquier
// otra forma (crear el controller afuera y disponerlo después del await)
// hace que Flutter estalle con "_dependents.isEmpty is not true", porque el
// controller queda muerto mientras el TextField todavía se está animando fuera
// del árbol.
// ============================================================================

// ============================================================================
// DIÁLOGO "SECTOR NUEVO" — con nombre + a qué garita pertenece
// ============================================================================
// Se usa solo para CREAR. Al renombrar un sector existente se usa el otro
// diálogo más simple, para no cambiar por accidente la asignación de garita.
// ============================================================================

class _DialogoNombreYGarita extends ConsumerStatefulWidget {
  const _DialogoNombreYGarita();

  @override
  ConsumerState<_DialogoNombreYGarita> createState() =>
      _EstadoDialogoNombreYGarita();
}

class _EstadoDialogoNombreYGarita extends ConsumerState<_DialogoNombreYGarita> {
  final _campo = TextEditingController();
  String? _garitaId;
  late Future<List<Map<String, dynamic>>> _garitas;

  @override
  void initState() {
    super.initState();
    _garitas = ref.read(servicioAdminProvider).garitasActivas();
  }

  @override
  void dispose() {
    _campo.dispose();
    super.dispose();
  }

  void _aceptar() {
    final texto = _campo.text.trim();
    if (texto.length < 3) return;
    Navigator.pop(context, (nombre: texto, puntoAccesoId: _garitaId));
  }

  @override
  Widget build(BuildContext context) {
    final palabras = ref.watch(palabrasProvider);
    return AlertDialog(
      title: const Text('Sector nuevo'),
      content: FutureBuilder<List<Map<String, dynamic>>>(
        future: _garitas,
        builder: (context, snap) {
          final garitas = snap.data ?? const [];
          // Si hay una sola garita en el condominio, no tiene sentido preguntar
          // — todos los puntos son de esa. Se salta el dropdown.
          final mostrarDropdown = garitas.length > 1;

          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Ponele un nombre que el guardia reconozca de noche, '
                'caminando. "Portón del fondo" sirve; "Punto 3" no.',
                style: const TextStyle(fontSize: 13, height: 1.45),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _campo,
                autofocus: true,
                textCapitalization: TextCapitalization.sentences,
                onSubmitted: (_) => _aceptar(),
                decoration: InputDecoration(
                  labelText: 'Nombre del sector',
                  hintText: palabras.tipo == 'colegio'
                      ? 'Ej: Patio de básica'
                      : 'Ej: Portón del fondo',
                ),
              ),
              if (mostrarDropdown) ...[
                const SizedBox(height: 16),
                const Text('¿A QUÉ GARITA CORRESPONDE?',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      color: Colores.textoSuave,
                      letterSpacing: 0.7,
                    )),
                const SizedBox(height: 6),
                DropdownButtonFormField<String?>(
                  initialValue: _garitaId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.meeting_room_outlined),
                    isDense: true,
                  ),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('Común a todas las garitas'),
                    ),
                    for (final g in garitas)
                      DropdownMenuItem<String?>(
                        value: g['id'] as String,
                        child: Text(g['nombre'] as String,
                            overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: (v) => setState(() => _garitaId = v),
                ),
                const SizedBox(height: 4),
                const Text(
                  'El sector solo lo va a hacer el guardia que abra turno '
                  'en esa garita. Elegí "común" si cualquier guardia lo puede '
                  'incluir en su recorrido.',
                  style: TextStyle(
                      fontSize: 11, color: Colores.textoSuave, height: 1.35),
                ),
              ],
            ],
          );
        },
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _aceptar,
          style: FilledButton.styleFrom(backgroundColor: Colores.grafito),
          child: const Text('Siguiente'),
        ),
      ],
    );
  }
}

// ============================================================================
// DIÁLOGO "CAMBIAR DE GARITA"
// ============================================================================
// Reasigna un sector existente a otra garita, o lo pasa a común. Al confirmar
// devuelve el nuevo id (o null si eligió "común").
// ============================================================================

class _DialogoCambiarGarita extends ConsumerStatefulWidget {
  const _DialogoCambiarGarita({this.actualId});
  final String? actualId;

  @override
  ConsumerState<_DialogoCambiarGarita> createState() =>
      _EstadoDialogoCambiarGarita();
}

class _EstadoDialogoCambiarGarita
    extends ConsumerState<_DialogoCambiarGarita> {
  late String? _eleccion = widget.actualId;
  late Future<List<Map<String, dynamic>>> _garitas;

  @override
  void initState() {
    super.initState();
    _garitas = ref.read(servicioAdminProvider).garitasActivas();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Cambiar de garita'),
      content: FutureBuilder<List<Map<String, dynamic>>>(
        future: _garitas,
        builder: (context, snap) {
          if (!snap.hasData) {
            return const SizedBox(
              height: 60,
              child: Center(child: CircularProgressIndicator()),
            );
          }
          final garitas = snap.data!;
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'El sector solo lo va a hacer el guardia que abra turno '
                'en esa garita. Común quiere decir que cualquier guardia '
                'lo puede incluir en su recorrido.',
                style: TextStyle(fontSize: 12.5, height: 1.4),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String?>(
                initialValue: _eleccion,
                isExpanded: true,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.meeting_room_outlined),
                  isDense: true,
                ),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('Común a todas las garitas'),
                  ),
                  for (final g in garitas)
                    DropdownMenuItem<String?>(
                      value: g['id'] as String,
                      child: Text(g['nombre'] as String,
                          overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (v) => setState(() => _eleccion = v),
              ),
            ],
          );
        },
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, (id: _eleccion)),
          style: FilledButton.styleFrom(backgroundColor: Colores.grafito),
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}

class _DialogoNombre extends ConsumerStatefulWidget {
  const _DialogoNombre({this.actual});

  final String? actual;

  @override
  ConsumerState<_DialogoNombre> createState() => _EstadoDialogoNombre();
}

class _EstadoDialogoNombre extends ConsumerState<_DialogoNombre> {
  late final TextEditingController _campo =
      TextEditingController(text: widget.actual ?? '');

  @override
  void dispose() {
    _campo.dispose();
    super.dispose();
  }

  void _aceptar() {
    final texto = _campo.text.trim();
    if (texto.length < 3) return;
    Navigator.pop(context, texto);
  }

  @override
  Widget build(BuildContext context) {
    final actual = widget.actual;
    final palabras = ref.watch(palabrasProvider);

    return AlertDialog(
      title: Text(actual == null ? 'Sector nuevo' : 'Cambiar el nombre'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            actual == null
                ? 'Ponele un nombre que el guardia reconozca de noche, '
                    'caminando. "Portón del fondo" sirve; "Punto 3" no.'
                : 'El código del cartel no cambia: si ya está impreso y '
                    'pegado, sigue funcionando igual.',
            style: const TextStyle(fontSize: 13, height: 1.45),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _campo,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            onSubmitted: (_) => _aceptar(),
            decoration: InputDecoration(
              labelText: 'Nombre del sector',
              hintText: palabras.tipo == 'colegio'
                  ? 'Ej: Patio de básica'
                  : 'Ej: Portón del fondo',
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
          onPressed: _aceptar,
          style: FilledButton.styleFrom(backgroundColor: Colores.grafito),
          child: Text(actual == null ? 'Siguiente' : 'Guardar'),
        ),
      ],
    );
  }
}

// ============================================================================
// EL AVISO DE LOS QUE FALTAN UBICAR
// ============================================================================

class _FaltanUbicar extends StatelessWidget {
  const _FaltanUbicar({required this.cuantos});

  final int cuantos;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      color: Colores.naranja.withValues(alpha: 0.08),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Medidas.redondeo),
        side: BorderSide(color: Colores.naranja.withValues(alpha: 0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(Medidas.margen),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.location_off_outlined,
                color: Colores.naranjaOscuro, size: 22),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$cuantos ${cuantos == 1 ? "sector" : "sectores"} sin ubicación',
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: Colores.naranjaOscuro),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Mientras no tengan ubicación, el sistema solo puede '
                    'demostrar que el guardia tenía el código del cartel, no '
                    'que estuvo ahí. Andá hasta cada uno y tocá "Tomar '
                    'ubicación acá".',
                    style: TextStyle(fontSize: 12.5, height: 1.45),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// UN SECTOR
// ============================================================================

class _Sector extends StatelessWidget {
  const _Sector({
    required this.punto,
    required this.numero,
    required this.instalacion,
    required this.alUbicar,
    required this.alRenombrar,
    required this.alDarDeBaja,
    required this.alCambiarGarita,
  });

  final PuntoControlAdmin punto;
  final int numero;
  final String instalacion;
  final VoidCallback alUbicar;
  final VoidCallback alRenombrar;
  final VoidCallback alDarDeBaja;
  final VoidCallback alCambiarGarita;

  @override
  Widget build(BuildContext context) {
    final ubicado = punto.tieneUbicacion;

    return Card(
      margin: const EdgeInsets.only(bottom: 9),
      child: ListTile(
        onTap: () => _mostrarCartel(context, punto, instalacion),
        leading: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: (ubicado ? Colores.verde : Colores.naranja)
                .withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(11),
          ),
          child: Icon(
            ubicado ? Icons.location_on_rounded : Icons.location_off_outlined,
            size: 20,
            color: ubicado ? Colores.verdeOscuro : Colores.naranjaOscuro,
          ),
        ),
        title: Text('$numero · ${punto.nombre}',
            style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              ubicado
                  ? 'Ubicado · tolerancia ${punto.metrosDeTolerancia} m'
                  : 'Sin ubicación',
              style: TextStyle(
                fontSize: 12,
                color: ubicado ? Colores.textoSuave : Colores.naranjaOscuro,
                fontWeight: ubicado ? FontWeight.normal : FontWeight.w600,
              ),
            ),
            // Garita a la que pertenece — clave para saber quién lo hace en
            // los colegios con varias garitas. Si es común a todas, no se
            // muestra chip: en condominios chicos con una sola garita, no
            // agrega información.
            if (punto.puntoAccesoNombre != null) ...[
              const SizedBox(height: 3),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colores.grafito.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  punto.puntoAccesoNombre!,
                  style: const TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: Colores.grafito,
                  ),
                ),
              ),
            ],
          ],
        ),
        trailing: PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert_rounded, size: 20),
          onSelected: (a) {
            switch (a) {
              case 'cartel':
                _mostrarCartel(context, punto, instalacion);
              case 'ubicar':
                alUbicar();
              case 'nombre':
                alRenombrar();
              case 'garita':
                alCambiarGarita();
              case 'baja':
                alDarDeBaja();
            }
          },
          itemBuilder: (_) => const [
            PopupMenuItem(
              value: 'cartel',
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                leading: Icon(Icons.qr_code_2_rounded, size: 19),
                title: Text('Ver el cartel'),
              ),
            ),
            PopupMenuItem(
              value: 'ubicar',
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                leading: Icon(Icons.my_location_rounded, size: 19),
                title: Text('Tomar ubicación acá'),
              ),
            ),
            PopupMenuItem(
              value: 'nombre',
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                leading: Icon(Icons.edit_outlined, size: 19),
                title: Text('Cambiar el nombre'),
              ),
            ),
            PopupMenuItem(
              value: 'garita',
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                leading: Icon(Icons.meeting_room_outlined, size: 19),
                title: Text('Cambiar de garita'),
              ),
            ),
            PopupMenuItem(
              value: 'baja',
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                leading: Icon(Icons.delete_outline_rounded,
                    size: 19, color: Colores.rojo),
                title: Text('Sacar este sector'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================================================
  // EL CARTEL PARA IMPRIMIR
  // ==========================================================================

  static void _mostrarCartel(
    BuildContext context,
    PuntoControlAdmin punto,
    String instalacion,
  ) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colores.superficie,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(Medidas.margen),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colores.linea,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 18),
              Text(punto.nombre,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 4),
              const Text('Cartel del sector',
                  style: TextStyle(fontSize: 12.5, color: Colores.textoSuave)),
              const SizedBox(height: 18),

              // El código, bien grande y sobre blanco: así se puede fotografiar
              // desde otra pantalla si hace falta imprimirlo de apuro.
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(Medidas.redondeo),
                  border: Border.all(color: Colores.linea),
                ),
                child: QrImageView(
                  data: punto.codigoQr,
                  size: 220,
                  // El nivel más alto de resistencia a la suciedad: estos
                  // carteles viven a la intemperie.
                  errorCorrectionLevel: QrErrorCorrectLevel.H,
                  backgroundColor: Colors.white,
                ),
              ),

              const SizedBox(height: 14),
              if (punto.tieneUbicacion)
                Text(
                  'Ubicación tomada'
                  '${punto.ubicacionTomadaEn == null ? "" : " el ${Formato.fecha(punto.ubicacionTomadaEn!)}"}'
                  ' · tolerancia ${punto.metrosDeTolerancia} m',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 12, color: Colores.verdeOscuro),
                )
              else
                const Text(
                  'Este sector NO tiene ubicación. El sistema no va a poder '
                  'demostrar que el guardia estuvo acá.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 12,
                      height: 1.4,
                      fontWeight: FontWeight.w600,
                      color: Colores.naranjaOscuro),
                ),

              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () async {
                    try {
                      await Printing.layoutPdf(
                        name: 'cartel-${punto.nombre}.pdf',
                        onLayout: (_) => CartelDeSectorPdf.armar(
                          instalacion: instalacion,
                          sector: punto.nombre,
                          codigoQr: punto.codigoQr,
                          tieneUbicacion: punto.tieneUbicacion,
                        ),
                      );
                    } catch (_) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('No se pudo abrir el diálogo de impresión.'),
                            backgroundColor: Colores.rojo,
                          ),
                        );
                      }
                    }
                  },
                  icon: const Icon(Icons.print_rounded, size: 19),
                  label: const Text('Imprimir o guardar PDF'),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colores.grafito,
                    minimumSize: const Size(0, Medidas.altoBoton),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: punto.codigoQr));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Código copiado.'),
                        backgroundColor: Colores.grafito,
                      ),
                    );
                  },
                  icon: const Icon(Icons.copy_rounded, size: 18),
                  label: const Text('Copiar código'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, Medidas.altoBoton),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'El diálogo que se abre deja elegir impresora, guardar como '
                'PDF o compartirlo por WhatsApp para imprimirlo más tarde.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 11.5, height: 1.4, color: Colores.textoTenue),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}
