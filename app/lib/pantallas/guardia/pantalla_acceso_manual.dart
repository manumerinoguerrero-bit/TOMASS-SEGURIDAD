// ============================================================================
// Tomass Seguridad — El guardia anota un ingreso a mano
// ============================================================================
// DÓNDE SE USA
//
//   En los colegios y en Viveros Yapur. Ahí hay barrera y portones de cierre
//   que abre el guardia: nadie va a apuntar un teléfono a un cartel. El guardia
//   mira, abre, y anota.
//
// LO QUE SE ANOTA, Y POR QUÉ ES OBLIGATORIO
//
//   nombre · RUT · a dónde va · quién autoriza · patente (si viene en vehículo)
//
//   Los definió Manuel, que es quien conoce la operación. El más importante de
//   todos es QUIÉN AUTORIZA: es el único que contesta la pregunta que se hace
//   siempre cuando pasa algo, que es "¿y este quién lo dejó entrar?". Sin ese
//   dato, el registro dice que alguien entró pero no de quién fue la decisión,
//   y el guardia queda solo cargando con la responsabilidad.
//
//   La foto es OPCIONAL. En la entrada de un colegio a las 8 de la mañana hay
//   fila de autos, y obligar una foto por cada uno agrega quince segundos a
//   cada ingreso. Se usa cuando el guardia ve algo que conviene respaldar.
//
// CÓMO ESTÁ PENSADA LA PANTALLA
//
//   Para usarse con una mano, parado, de noche y con alguien esperando. Por eso:
//
//     · Entrada/Salida y A pie/En vehículo son botones grandes, no listas.
//     · "Quién autoriza" recuerda los últimos que se escribieron: la primera
//       vez se escribe, las siguientes es un toque.
//     · El botón de guardar es enorme y dice qué va a pasar.
//     · Si algo falta, el aviso dice exactamente qué, sin palabras raras.
// ============================================================================

import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/tema.dart';
import '../../estado/proveedores.dart';
import '../../estado/proveedores_guardia.dart';
import '../../modelos/formato_patente.dart';
import '../../modelos/guardia.dart';
import '../../nucleo/errores.dart';
import '../../servicios/servicio_fotos.dart';
import '../comunes/componentes.dart';
import 'acciones_de_turno.dart';
import 'pantalla_personas_dentro.dart';

class PantallaAccesoManual extends ConsumerStatefulWidget {
  const PantallaAccesoManual({super.key});

  @override
  ConsumerState<PantallaAccesoManual> createState() => _EstadoAccesoManual();
}

class _EstadoAccesoManual extends ConsumerState<PantallaAccesoManual> {
  final _nombre = TextEditingController();
  final _rut = TextEditingController();
  final _patente = TextEditingController();
  final _aDondeVa = TextEditingController();
  final _autoriza = TextEditingController();
  final _observacion = TextEditingController();

  String _sentido = 'entrada';
  String _tipoAcceso = 'peatonal';
  String? _garitaId;
  File? _foto;
  bool _guardando = false;
  ErrorAmigable? _problema;

  /// Hora en la que pasó la persona. null significa "ahora" — es el caso
  /// normal. Si el guardia estaba ocupado con otra cosa y anota el ingreso
  /// después, pone la hora real acá y no la que marca el reloj cuando toca
  /// "Registrar".
  DateTime? _horaManual;

  /// Los últimos "quién autoriza" que se escribieron en este turno.
  ///
  /// En un colegio autoriza casi siempre la misma gente (inspectoría, la
  /// directora, el jefe de mantención). Guardarlos convierte cinco toques de
  /// teclado en uno solo, y es la diferencia entre que el guardia lo complete
  /// siempre o que empiece a poner cualquier cosa para salir del paso.
  final _autorizantesRecientes = <String>[];

  /// El identificador de ESTE ingreso. Se arma una sola vez, a propósito: si se
  /// corta el internet y hay que reintentar, el servidor reconoce que es el
  /// mismo y no anota dos veces a la misma persona.
  String _idDelIngreso = _nuevoId();

  static String _nuevoId() {
    final azar = Random.secure();
    String bloque(int bytes) => List.generate(
          bytes,
          (_) => azar.nextInt(256).toRadixString(16).padLeft(2, '0'),
        ).join();
    return '${bloque(4)}-${bloque(2)}-4${bloque(2).substring(1)}-'
        '${(8 + azar.nextInt(4)).toRadixString(16)}${bloque(2).substring(1)}-'
        '${bloque(6)}';
  }

  @override
  void dispose() {
    _nombre.dispose();
    _rut.dispose();
    _patente.dispose();
    _aDondeVa.dispose();
    _autoriza.dispose();
    _observacion.dispose();
    super.dispose();
  }

  Future<void> _elegirHoraManual() async {
    final ahora = DateTime.now();
    final inicial = _horaManual ?? ahora;

    // Fecha: dejamos ir hasta 24 h atrás como límite práctico. Un turno
    // dura 12 h como máximo, así que ese margen alcanza y sobra.
    final fecha = await showDatePicker(
      context: context,
      initialDate: inicial,
      firstDate: ahora.subtract(const Duration(days: 1)),
      lastDate: ahora,
      locale: const Locale('es', 'CL'),
      helpText: '¿En qué día pasó?',
      cancelText: 'Cancelar',
      confirmText: 'Siguiente',
    );
    if (fecha == null || !mounted) return;

    final hora = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(inicial),
      helpText: '¿A qué hora pasó?',
      cancelText: 'Cancelar',
      confirmText: 'Listo',
    );
    if (hora == null || !mounted) return;

    setState(() {
      _horaManual = DateTime(
          fecha.year, fecha.month, fecha.day, hora.hour, hora.minute);
    });
  }

  Future<void> _sacarFoto() async {
    try {
      final foto = await ref.read(servicioFotosProvider).sacarFoto();
      if (foto != null && mounted) setState(() => _foto = foto);
    } catch (falla) {
      if (mounted) setState(() => _problema = Traductor.traducir(falla));
    }
  }

  Future<void> _guardar(List<PuntoAcceso> garitas) async {
    final garita = _garitaId ?? ref.read(miPuestoProvider);

    if (garita == null) {
      setState(() => _problema = const ErrorAmigable(
            'Falta elegir en qué garita estás.',
            detalle: 'Es lo que dice por dónde pasó la persona.',
            sePuedeReintentar: false,
          ));
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() {
      _guardando = true;
      _problema = null;
    });

    try {
      String? rutaFoto;
      if (_foto != null) {
        final perfil = ref.read(perfilProvider).valueOrNull;
        if (perfil != null) {
          rutaFoto = await ref.read(servicioFotosProvider).subir(
                archivo: _foto!,
                cajon: CajonDeFotos.personas,
                condominioId: perfil.condominioId,
                nombreDescriptivo: 'ingreso-manual',
              );
        }
      }

      final enCola =
          await ref.read(servicioGuardiaProvider).anotarAccesoManual(
                idLocal: _idDelIngreso,
                puntoAccesoId: garita,
                nombre: _nombre.text,
                rut: _rut.text,
                tipoAcceso: _tipoAcceso,
                sentido: _sentido,
                aDondeVa: _aDondeVa.text,
                autorizadoPor: _autoriza.text,
                patente: FormatoPatente.normalizar(_patente.text),
                fotoUrl: rutaFoto,
                observacion: _observacion.text,
                ocurridoEn: _horaManual,
              );

      if (!mounted) return;

      // El golpecito de confirmación no se espera: es una vibración, y esperarla
      // dejaría la pantalla sin poder mostrar el aviso hasta que termine.
      unawaited(HapticFeedback.mediumImpact());

      final quien = _nombre.text.trim();
      final entro = _sentido == 'entrada';

      // Se recuerda quién autorizó, para el próximo
      final autoriza = _autoriza.text.trim();
      if (autoriza.isNotEmpty && !_autorizantesRecientes.contains(autoriza)) {
        _autorizantesRecientes.insert(0, autoriza);
        if (_autorizantesRecientes.length > 4) _autorizantesRecientes.removeLast();
      }

      // Se limpia todo menos "quién autoriza" y la garita: en una entrada de
      // colegio pasan diez personas seguidas autorizadas por la misma persona,
      // y volver a escribirlo cada vez es lo que hace que se deje de completar.
      // La hora manual TAMBIÉN se resetea: si el guardia anotó un ingreso
      // atrasado, el próximo por defecto vuelve a ser "ahora".
      setState(() {
        _nombre.clear();
        _rut.clear();
        _patente.clear();
        _aDondeVa.clear();
        _observacion.clear();
        _foto = null;
        _tipoAcceso = 'peatonal';
        _guardando = false;
        _idDelIngreso = _nuevoId();
        _horaManual = null;
      });

      ref.invalidate(ultimosAccesosProvider);
      ref.invalidate(resumenProvider);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            enCola
                ? '$quien quedo guardado sin conexion. Se enviara cuando '
                    'vuelva la red.'
                : '$quien quedó registrado. '
                    '${entro ? "Entrada" : "Salida"} anotada.',
          ),
          backgroundColor: enCola ? Colores.naranja : Colores.verde,
          duration: const Duration(seconds: 3),
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
    final garitas = ref.watch(puestosDisponiblesProvider).valueOrNull ?? const [];
    final miPuesto = ref.watch(miPuestoProvider);
    final cubroTodo = ref.watch(cubroTodoProvider);
    final palabras = ref.watch(palabrasProvider);

    // Si el guardia está asignado a una garita puntual, esa es y no se pregunta.
    // Solo se pregunta cuando cubre todo y podría estar en cualquiera.
    final garitaFija = miPuesto != null;
    final garitaElegida = garitaFija ? miPuesto : _garitaId;
    final garita = garitas.where((g) => g.id == garitaElegida).firstOrNull;
    final aceptaVehiculos = garita?.aceptaVehiculos ?? true;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Anotar ingreso'),
        actions: [
          // Acceso rápido a "Personas dentro" desde acá: cuando el guardia
          // está anotando un ingreso, muchas veces necesita chequear si la
          // persona ya está adentro (para no anotar dos entradas seguidas),
          // o quién más está de la misma casa. Antes había que ir hasta el
          // panel para verlo.
          IconButton(
            icon: const Icon(Icons.groups_2_outlined),
            tooltip: 'Personas dentro',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const PantallaPersonasDentro(),
              ),
            ),
          ),
          const MenuDelGuardia(),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(Medidas.margen),
        children: [
          if (_problema != null) ...[
            AvisoDeError(problema: _problema!),
            const SizedBox(height: 14),
          ],

          // ---- Dónde ----
          if (cubroTodo && garitas.length > 1) ...[
            Text('EN QUÉ GARITA ESTÁS',
                style: Theme.of(context).textTheme.labelSmall),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: _garitaId,
              isExpanded: true,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.meeting_room_outlined),
                hintText: 'Elegí la garita',
              ),
              items: garitas
                  .map((g) => DropdownMenuItem(value: g.id, child: Text(g.nombre)))
                  .toList(),
              onChanged: (v) => setState(() => _garitaId = v),
            ),
            const SizedBox(height: 18),
          ],

          // ---- Entra o sale ----
          Text('¿ENTRA O SALE?',
              style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(height: 8),
          _DosBotones(
            izquierda: 'Entra',
            derecha: 'Sale',
            iconoIzq: Icons.login_rounded,
            iconoDer: Icons.logout_rounded,
            elegidaIzquierda: _sentido == 'entrada',
            alElegir: (esIzq) =>
                setState(() => _sentido = esIzq ? 'entrada' : 'salida'),
          ),

          const SizedBox(height: 18),

          // ---- A pie o en vehículo ----
          Text('¿CÓMO PASA?', style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(height: 8),
          _DosBotones(
            izquierda: 'A pie',
            derecha: 'En vehículo',
            iconoIzq: Icons.directions_walk_rounded,
            iconoDer: Icons.directions_car_rounded,
            elegidaIzquierda: _tipoAcceso == 'peatonal',
            derechaHabilitada: aceptaVehiculos,
            alElegir: (esIzq) =>
                setState(() => _tipoAcceso = esIzq ? 'peatonal' : 'vehicular'),
          ),
          if (!aceptaVehiculos)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text(
                'Esta garita es solo peatonal.',
                style: TextStyle(fontSize: 11.5, color: Colores.textoSuave),
              ),
            ),

          const SizedBox(height: 20),
          const Divider(),
          const SizedBox(height: 14),

          // ---- Quién es ----
          TextField(
            controller: _nombre,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: 'Nombre completo',
              prefixIcon: Icon(Icons.person_outline_rounded),
            ),
          ),
          const SizedBox(height: 12),

          TextField(
            controller: _rut,
            keyboardType: TextInputType.text,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: 'RUT',
              hintText: '12.345.678-9',
              prefixIcon: Icon(Icons.badge_outlined),
            ),
          ),

          // ---- La patente, solo si viene en vehículo ----
          if (_tipoAcceso == 'vehicular') ...[
            const SizedBox(height: 12),
            TextField(
              controller: _patente,
              textCapitalization: TextCapitalization.characters,
              textInputAction: TextInputAction.next,
              // Solo letras y números: el guion lo pone la app sola al guardar.
              // Así "bcdf12", "BCDF 12" y "BCDF-12" quedan iguales en el
              // registro, y el guardia no tiene que acordarse del formato con
              // el camión esperando adelante.
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp('[a-zA-Z0-9]')),
                LengthLimitingTextInputFormatter(6),
              ],
              decoration: const InputDecoration(
                labelText: 'Patente del vehículo',
                hintText: 'BCDF12',
                helperText: 'Sin guion. La app lo agrega sola.',
                prefixIcon: Icon(Icons.directions_car_outlined),
              ),
            ),
          ],

          const SizedBox(height: 12),
          TextField(
            controller: _aDondeVa,
            textCapitalization: TextCapitalization.sentences,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              labelText: '¿A dónde se dirige?',
              hintText: palabras.tipo == 'colegio'
                  ? 'Ej: 4°B, Inspectoría, Estacionamiento'
                  : 'Ej: ${palabras.elEspacioConMayuscula} 302, Administración',
              prefixIcon: const Icon(Icons.place_outlined),
            ),
          ),

          const SizedBox(height: 12),
          TextField(
            controller: _autoriza,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: '¿Quién autoriza el ingreso?',
              hintText: 'Ej: Inspectoría general',
              prefixIcon: Icon(Icons.how_to_reg_outlined),
              helperText: 'Es lo que contesta después "¿quién lo dejó entrar?"',
              helperMaxLines: 2,
            ),
          ),

          // Los últimos que se escribieron, para no reescribirlos
          if (_autorizantesRecientes.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 7,
              children: [
                for (final a in _autorizantesRecientes)
                  ActionChip(
                    label: Text(a, style: const TextStyle(fontSize: 12)),
                    avatar: const Icon(Icons.history_rounded, size: 15),
                    onPressed: () => setState(() => _autoriza.text = a),
                  ),
              ],
            ),
          ],

          const SizedBox(height: 18),

          // ---- La foto, opcional ----
          _Foto(
            foto: _foto,
            alSacar: _sacarFoto,
            alQuitar: () => setState(() => _foto = null),
          ),

          const SizedBox(height: 12),
          TextField(
            controller: _observacion,
            maxLines: 2,
            maxLength: 200,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Observación (opcional)',
              hintText: 'Algo para dejar anotado',
              alignLabelWithHint: true,
            ),
          ),

          // ---- Hora del ingreso (por defecto = ahora) ----
          // Si el guardia estaba ocupado con otra cosa cuando la persona pasó
          // (fila de autos, teléfono, otro visitante) puede anotar el ingreso
          // después con la hora real de cuando cruzó, no con la hora en que
          // termina de escribir el formulario.
          _CampoHora(
            hora: _horaManual,
            alElegir: _elegirHoraManual,
            alQuitar: () => setState(() => _horaManual = null),
          ),

          const SizedBox(height: 10),

          // ---- Guardar ----
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _guardando ? null : () => _guardar(garitas),
              style: FilledButton.styleFrom(
                backgroundColor:
                    _sentido == 'entrada' ? Colores.verde : Colores.grafito,
                minimumSize: const Size(0, Medidas.altoBotonGigante),
              ),
              icon: _guardando
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.5, color: Colors.white),
                    )
                  : Icon(
                      _sentido == 'entrada'
                          ? Icons.login_rounded
                          : Icons.logout_rounded,
                      size: 26,
                    ),
              label: Text(
                _guardando
                    ? 'Guardando…'
                    : _sentido == 'entrada'
                        ? 'Registrar entrada'
                        : 'Registrar salida',
                style: const TextStyle(
                    fontSize: 17, fontWeight: FontWeight.w800),
              ),
            ),
          ),

          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

// ============================================================================
// DOS BOTONES GRANDES
// ============================================================================
// En vez de una lista desplegable. El guardia usa esto parado, de noche, con
// una mano y con gente esperando: un toque en un botón grande no se falla.
// ============================================================================

class _DosBotones extends StatelessWidget {
  const _DosBotones({
    required this.izquierda,
    required this.derecha,
    required this.iconoIzq,
    required this.iconoDer,
    required this.elegidaIzquierda,
    required this.alElegir,
    this.derechaHabilitada = true,
  });

  final String izquierda;
  final String derecha;
  final IconData iconoIzq;
  final IconData iconoDer;
  final bool elegidaIzquierda;
  final bool derechaHabilitada;
  final void Function(bool esIzquierda) alElegir;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _Boton(
            texto: izquierda,
            icono: iconoIzq,
            elegido: elegidaIzquierda,
            habilitado: true,
            alTocar: () => alElegir(true),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _Boton(
            texto: derecha,
            icono: iconoDer,
            elegido: !elegidaIzquierda,
            habilitado: derechaHabilitada,
            alTocar: () => alElegir(false),
          ),
        ),
      ],
    );
  }
}

class _Boton extends StatelessWidget {
  const _Boton({
    required this.texto,
    required this.icono,
    required this.elegido,
    required this.habilitado,
    required this.alTocar,
  });

  final String texto;
  final IconData icono;
  final bool elegido;
  final bool habilitado;
  final VoidCallback alTocar;

  @override
  Widget build(BuildContext context) {
    final apagado = !habilitado;
    return Material(
      color: elegido && !apagado
          ? Colores.grafito
          : Colores.grafito.withValues(alpha: 0.05),
      borderRadius: BorderRadius.circular(Medidas.redondeo),
      child: InkWell(
        onTap: apagado ? null : alTocar,
        borderRadius: BorderRadius.circular(Medidas.redondeo),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 15),
          child: Column(
            children: [
              Icon(
                icono,
                size: 24,
                color: apagado
                    ? Colores.textoTenue
                    : elegido
                        ? Colors.white
                        : Colores.textoSuave,
              ),
              const SizedBox(height: 5),
              Text(
                texto,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: apagado
                      ? Colores.textoTenue
                      : elegido
                          ? Colors.white
                          : Colores.textoSuave,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// LA FOTO, QUE ES OPCIONAL
// ============================================================================

class _Foto extends StatelessWidget {
  const _Foto({
    required this.foto,
    required this.alSacar,
    required this.alQuitar,
  });

  final File? foto;
  final VoidCallback alSacar;
  final VoidCallback alQuitar;

  @override
  Widget build(BuildContext context) {
    if (foto == null) {
      return OutlinedButton.icon(
        onPressed: alSacar,
        icon: const Icon(Icons.photo_camera_outlined, size: 20),
        label: const Text('Agregar una foto (opcional)'),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(double.infinity, Medidas.altoBoton),
          foregroundColor: Colores.textoSuave,
        ),
      );
    }

    return Row(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(Medidas.redondeoChico),
          child: Image.file(foto!, width: 64, height: 64, fit: BoxFit.cover),
        ),
        const SizedBox(width: 12),
        const Expanded(
          child: Text('Foto agregada',
              style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
        ),
        TextButton(
          onPressed: alQuitar,
          style: TextButton.styleFrom(foregroundColor: Colores.rojo),
          child: const Text('Quitar'),
        ),
      ],
    );
  }
}

// ============================================================================
// CAMPO "HORA DEL INGRESO"
// ============================================================================
// Por defecto la app usa la hora en que se toca "Registrar". Si el guardia
// estaba ocupado y anota la visita más tarde, elige la hora real acá.
// ============================================================================

class _CampoHora extends StatelessWidget {
  const _CampoHora({
    required this.hora,
    required this.alElegir,
    required this.alQuitar,
  });

  final DateTime? hora;
  final Future<void> Function() alElegir;
  final VoidCallback alQuitar;

  static const _dias = ['lun', 'mar', 'mié', 'jue', 'vie', 'sáb', 'dom'];

  @override
  Widget build(BuildContext context) {
    if (hora == null) {
      return Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: alElegir,
            icon: const Icon(Icons.schedule_rounded, size: 18),
            label: const Text('La visita pasó antes — anotar la hora real'),
          ),
        ),
      );
    }

    final h = hora!;
    final hoy = DateTime.now();
    final esHoy = h.year == hoy.year && h.month == hoy.month && h.day == hoy.day;
    final etiquetaDia = esHoy
        ? 'Hoy'
        : '${_dias[h.weekday - 1]} ${h.day.toString().padLeft(2, '0')}/'
            '${h.month.toString().padLeft(2, '0')}';
    final etiquetaHora =
        '${h.hour.toString().padLeft(2, '0')}:${h.minute.toString().padLeft(2, '0')}';

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colores.dorado.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(Medidas.redondeoChico),
        border: Border.all(
            color: Colores.dorado.withValues(alpha: 0.5), width: 1.2),
      ),
      child: Row(
        children: [
          const Icon(Icons.schedule_rounded,
              size: 18, color: Colores.doradoOscuro),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'HORA MANUAL',
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                    color: Colores.doradoOscuro,
                  ),
                ),
                Text(
                  '$etiquetaDia · $etiquetaHora',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Colores.grafito,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.edit_rounded, size: 18),
            tooltip: 'Cambiar',
            onPressed: () => alElegir(),
            color: Colores.grafito,
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded, size: 18),
            tooltip: 'Usar la hora de ahora',
            onPressed: alQuitar,
            color: Colores.rojo,
          ),
        ],
      ),
    );
  }
}
