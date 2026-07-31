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
    // Se resuelve el permiso de ubicación ANTES de abrir el cartel de
    // "nombre del sector". Ver la explicación larga en Localizador.resolverPermiso.
    await Localizador.resolverPermiso();
    if (!mounted) return;

    final nombre = await _pedirNombre();
    if (nombre == null || !mounted) return;

    setState(() => _trabajando = true);

    // Se toma la ubicación ANTES de crear nada: si el GPS no anda, conviene
    // avisarle ahora y no dejarlo con un sector a medio hacer.
    final donde = await Localizador.donde();

    if (!mounted) return;

    if (donde == null) {
      final porque = await Localizador.porQueNoSePudo();
      if (!mounted) return;
      setState(() => _trabajando = false);

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
      await _crear(nombre, null);
      return;
    }

    // El GPS a veces contesta con un error enorme. Conviene decirlo antes de
    // guardar una ubicación que después va a dar falsas alarmas.
    if (!donde.esConfiable) {
      setState(() => _trabajando = false);
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
      setState(() => _trabajando = true);
    }

    await _crear(nombre, donde);
  }

  Future<void> _crear(String nombre, Ubicacion? donde) async {
    try {
      await ref.read(servicioAdminProvider).crearPuntoDeControl(
            nombre: nombre,
            latitud: donde?.latitud,
            longitud: donde?.longitud,
            // Se le da margen al error que declaró el propio teléfono, con un
            // mínimo de 60 metros: menos que eso da falsas alarmas.
            tolerancia: donde == null
                ? 60
                : (donde.metrosDeError * 2).clamp(60, 200).round(),
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
    // Mismo motivo que en _agregarAca: resolver el permiso ANTES de abrir el
    // cartel de confirmación, para que el aviso de Android (si hace falta)
    // nunca interrumpa una animación de la app a medio camino.
    await Localizador.resolverPermiso();
    if (!mounted) return;

    final ok = await _preguntar(
      titulo: '¿Estás parado en ${punto.nombre}?',
      texto: 'La ubicación se toma DONDE ESTÁS AHORA. Si la tomás desde otro '
          'lado, todas las rondas de este sector van a aparecer marcadas como '
          'hechas desde lejos.',
      siText: 'Sí, estoy acá',
    );
    if (ok != true || !mounted) return;

    setState(() => _trabajando = true);
    final donde = await Localizador.donde();
    if (!mounted) return;

    if (donde == null) {
      setState(() => _trabajando = false);
      _avisar(await Localizador.porQueNoSePudo() ?? 'No se pudo.', malo: true);
      return;
    }

    try {
      await ref.read(servicioAdminProvider).ubicarPuntoDeControl(
            puntoId: punto.id,
            latitud: donde.latitud,
            longitud: donde.longitud,
            tolerancia: (donde.metrosDeError * 2).clamp(60, 200).round(),
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

  Future<String?> _pedirNombre({String? actual}) async {
    final campo = TextEditingController(text: actual ?? '');
    final palabras = ref.read(palabrasProvider);

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
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
              controller: campo,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
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
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colores.grafito),
            child: Text(actual == null ? 'Siguiente' : 'Guardar'),
          ),
        ],
      ),
    );

    final texto = campo.text.trim();
    campo.dispose();
    return (ok == true && texto.length >= 3) ? texto : null;
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
                    final n = await _pedirNombre(actual: lista[i].nombre);
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
                ),
            ],
          );
        },
      ),
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
  });

  final PuntoControlAdmin punto;
  final int numero;
  final String instalacion;
  final VoidCallback alUbicar;
  final VoidCallback alRenombrar;
  final VoidCallback alDarDeBaja;

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
        subtitle: Text(
          ubicado
              ? 'Ubicado · tolerancia ${punto.metrosDeTolerancia} m'
              : 'Sin ubicación',
          style: TextStyle(
            fontSize: 12,
            color: ubicado ? Colores.textoSuave : Colores.naranjaOscuro,
            fontWeight: ubicado ? FontWeight.normal : FontWeight.w600,
          ),
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
