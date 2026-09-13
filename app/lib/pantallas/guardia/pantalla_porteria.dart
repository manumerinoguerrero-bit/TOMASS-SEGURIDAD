// ============================================================================
// Tomass Seguridad — Pantallas 14, 15 y 16 · Portería
// ============================================================================
// Las tres cosas que el guardia hace con los paquetes, en una sola pantalla con
// tres pestañas: recibir, ver el inventario, y entregar.
//
// POR QUÉ LAS TRES JUNTAS Y NO EN TRES PANTALLAS SEPARADAS
//   Porque son el mismo trabajo visto en tres momentos. El guardia pasa de una a
//   otra todo el día, y tenerlas en pestañas le ahorra volver a un menú cada vez.
//
// LA FOTO DEL PAQUETE ES OBLIGATORIA
//   No es burocracia: es el respaldo del condominio si el residente después dice
//   que llegó dañado o que nunca llegó. Sin foto no se puede guardar.
// ============================================================================

import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:signature/signature.dart';

import '../../config/palabras.dart';
import '../../config/tema.dart';
import '../../estado/proveedores.dart';
import '../../estado/proveedores_guardia.dart';
import '../../nucleo/errores.dart';
import '../../nucleo/formato.dart';
import '../../servicios/servicio_fotos.dart';
import '../comunes/componentes.dart';
import 'acciones_de_turno.dart';

/// Genera un UUID v4 válido (formato 8-4-4-4-12 con guiones y los bits
/// de versión/variant fijos). Se usa para el id_local de paquetes y
/// novedades, que Postgres exige de tipo uuid.
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

class PantallaPorteria extends ConsumerWidget {
  const PantallaPorteria({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final inventario = ref.watch(inventarioPaquetesProvider);
    final cuantos = inventario.valueOrNull?.length ?? 0;

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Portería'),
          actions: const [MenuDelGuardia()],
          bottom: TabBar(
            indicatorColor: Colors.white,
            indicatorWeight: 3,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white.withValues(alpha: 0.6),
            labelStyle: const TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
            ),
            tabs: [
              const Tab(text: 'Recibir'),
              Tab(text: cuantos == 0 ? 'Inventario' : 'Inventario ($cuantos)'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _PestanaRecibir(),
            _PestanaInventario(),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// PESTAÑA 1 · RECIBIR UN PAQUETE
// ============================================================================
// Tres pasos en una sola pantalla, sin cambiar de página. Toma menos de 30
// segundos con el repartidor esperando adelante.
// ============================================================================

class _PestanaRecibir extends ConsumerStatefulWidget {
  const _PestanaRecibir();

  @override
  ConsumerState<_PestanaRecibir> createState() => _EstadoRecibir();
}

class _EstadoRecibir extends ConsumerState<_PestanaRecibir> {
  final _seguimiento = TextEditingController();
  final _courier = TextEditingController();
  final _descripcion = TextEditingController();
  final _busqueda = TextEditingController();
  // Campos para escribir el destinatario a mano cuando no está registrado
  // en el sistema (por ejemplo la primera semana de uso o alguien que se
  // muda hoy). Si el modo a mano está activo, se usan estos en lugar del
  // residente elegido de la lista.
  final _nombreAMano = TextEditingController();
  final _unidadAMano = TextEditingController();
  bool _aMano = false;
  List<Map<String, dynamic>> _sugerenciasAMano = const [];

  File? _foto;
  Map<String, dynamic>? _residente;
  List<Map<String, dynamic>> _encontrados = const [];
  bool _buscando = false;
  bool _guardando = false;
  ErrorAmigable? _problema;

  @override
  void dispose() {
    _seguimiento.dispose();
    _courier.dispose();
    _descripcion.dispose();
    _busqueda.dispose();
    _nombreAMano.dispose();
    _unidadAMano.dispose();
    super.dispose();
  }

  Future<void> _fotografiar() async {
    try {
      // La que más se saca de todas: 90 por día en un condominio de 300
      // departamentos. Se comprime más que las otras, y por eso baja a la mitad
      // el espacio que ocupa el sistema entero.
      final foto = await ref.read(servicioFotosProvider).sacarFoto(
            proposito: PropositoDeLaFoto.elPaquete,
          );
      if (foto != null && mounted) setState(() => _foto = foto);
    } catch (falla) {
      if (mounted) setState(() => _problema = Traductor.traducir(falla));
    }
  }

  Future<void> _buscar(String texto) async {
    if (texto.trim().length < 2) {
      setState(() => _encontrados = const []);
      return;
    }
    setState(() => _buscando = true);
    try {
      // Se buscan las dos cosas en paralelo:
      //   1) residentes formales dados de alta en el sistema
      //   2) destinatarios que el guardia (o el anterior) ya escribió
      //      a mano en paquetes previos — quedaron en paquetes.destinatario_texto
      // Los resultados se mezclan en una sola lista. Los de a mano quedan al
      // final y se marcan con la bandera `es_a_mano` para pintarlos distinto.
      final servicio = ref.read(servicioGuardiaProvider);
      final resultados = await Future.wait([
        servicio.buscarResidentes(texto),
        servicio.sugerenciasDestinatariosAMano(empezandoCon: texto),
      ]);
      final registrados = resultados[0]
          .map((r) => {...r, 'es_a_mano': false})
          .toList();
      final aMano = resultados[1]
          .map((s) => {
                'nombre_completo': s['nombre'],
                'unidad_texto': s['unidad'],
                'es_a_mano': true,
              })
          .toList();
      if (mounted) setState(() => _encontrados = [...registrados, ...aMano]);
    } catch (_) {
      // Una búsqueda que falla no vale un cartel de error: se reintenta al
      // escribir la próxima letra.
    } finally {
      if (mounted) setState(() => _buscando = false);
    }
  }

  /// Busca destinatarios que ya se escribieron a mano en paquetes anteriores.
  /// Se dispara cuando el guardia está en modo "a mano" y escribe algo.
  Future<void> _buscarSugerenciasAMano(String texto) async {
    try {
      final r = await ref
          .read(servicioGuardiaProvider)
          .sugerenciasDestinatariosAMano(empezandoCon: texto);
      if (mounted) setState(() => _sugerenciasAMano = r);
    } catch (_) {
      // Silencioso: si no hay sugerencias, se escribe a mano y ya.
    }
  }

  Future<void> _guardar() async {
    if (_foto == null) {
      setState(() => _problema = const ErrorAmigable(
            'Falta la foto del paquete.',
            detalle: 'Es obligatoria: es tu respaldo si después reclaman que '
                'llegó dañado.',
            sePuedeReintentar: false,
          ));
      return;
    }
    if (_aMano) {
      if (_nombreAMano.text.trim().length < 2) {
        setState(() => _problema = const ErrorAmigable(
              'Falta el nombre del destinatario.',
              detalle: 'Escribí al menos 2 letras.',
              sePuedeReintentar: false,
            ));
        return;
      }
    } else if (_residente == null) {
      setState(() => _problema = ErrorAmigable(
            'Falta elegir a quién va el paquete.',
            detalle:
                'Buscalo por nombre o por número de ${ref.read(palabrasProvider).elEspacio}, '
                'o tocá "Escribir a mano" si todavía no está registrado.',
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
      await ref.read(servicioGuardiaProvider).recibirPaquete(
            condominioId: perfil.condominioId,
            residenteId: _aMano ? null : _residente!['id'] as String,
            unidadId: _aMano ? null : _residente!['unidad_id'] as String?,
            destinatarioTexto: _aMano ? _nombreAMano.text.trim() : null,
            unidadTexto: _aMano && _unidadAMano.text.trim().isNotEmpty
                ? _unidadAMano.text.trim()
                : null,
            foto: _foto!,
            // Antes se armaba un hex a mano concatenando hashCode +
            // microseconds. El campo id_local en la tabla paquetes es de
            // tipo uuid, así que Postgres lo rechazaba con
            // "invalid input for type uuid". Ahora se genera un UUID v4
            // real (formato 8-4-4-4-12 con guiones y bits fijos).
            idLocal: _nuevoUuidV4(),
            numeroSeguimiento: _seguimiento.text,
            empresaCourier: _courier.text,
            descripcion: _descripcion.text,
            turnoId: turno?.id,
          );

      ref.invalidate(inventarioPaquetesProvider);
      ref.invalidate(resumenProvider);

      if (!mounted) return;
      final nombre = _aMano
          ? _nombreAMano.text.trim()
          : _residente!['nombre_completo'];
      setState(() {
        _foto = null;
        _residente = null;
        _encontrados = const [];
        _seguimiento.clear();
        _courier.clear();
        _descripcion.clear();
        _busqueda.clear();
        _nombreAMano.clear();
        _unidadAMano.clear();
        _aMano = false;
        _guardando = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'Paquete guardado para $nombre. Queda en el inventario '
              'de portería hasta que lo retire.'),
          backgroundColor: Colores.verde,
          duration: const Duration(seconds: 4),
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
    return ListView(
      padding: const EdgeInsets.all(Medidas.margen),
      children: [
        if (_problema != null) ...[
          AvisoDeError(problema: _problema!),
          const SizedBox(height: 14),
        ],

        // ---- Paso 1: la foto ----
        Row(
          children: [
            Text('1 · FOTO DEL PAQUETE',
                style: Theme.of(context).textTheme.labelSmall),
            const SizedBox(width: 7),
            const Text(
              'OBLIGATORIA',
              style: TextStyle(
                fontSize: 9.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.6,
                color: Colores.rojo,
              ),
            ),
          ],
        ),
        const SizedBox(height: 9),
        GestureDetector(
          onTap: _guardando ? null : _fotografiar,
          child: Container(
            height: 150,
            decoration: BoxDecoration(
              color: Colores.grafito.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(Medidas.redondeo),
              border: Border.all(
                color: _foto == null ? Colores.rojo : Colores.verde,
                width: 1.6,
              ),
            ),
            child: _foto == null
                ? const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.photo_camera_rounded,
                          size: 30, color: Colores.textoSuave),
                      SizedBox(height: 9),
                      Text(
                        'Tocá para fotografiar el paquete',
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: Colores.textoSuave,
                        ),
                      ),
                    ],
                  )
                : ClipRRect(
                    borderRadius: BorderRadius.circular(Medidas.redondeo - 1),
                    child: Image.file(_foto!, fit: BoxFit.cover,
                        width: double.infinity),
                  ),
          ),
        ),

        const SizedBox(height: 20),

        // ---- Paso 2: los datos ----
        Text('2 · DATOS DEL PAQUETE',
            style: Theme.of(context).textTheme.labelSmall),
        const SizedBox(height: 9),
        Row(
          children: [
            Expanded(
              flex: 3,
              child: TextField(
                controller: _seguimiento,
                enabled: !_guardando,
                decoration: const InputDecoration(
                  labelText: 'Nº de seguimiento',
                  hintText: '998877665',
                  prefixIcon: Icon(Icons.numbers_rounded),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: TextField(
                controller: _courier,
                enabled: !_guardando,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Courier',
                  hintText: 'Starken',
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _descripcion,
          enabled: !_guardando,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            labelText: 'Descripción (opcional)',
            hintText: 'Caja grande, sobre, bolsa…',
            helperText: 'Ayuda al ${ref.read(palabrasProvider).elHabitante} a reconocerlo',
          ),
        ),

        const SizedBox(height: 20),

        // ---- Paso 3: para quién ----
        Text('3 · ¿PARA QUIÉN ES?',
            style: Theme.of(context).textTheme.labelSmall),
        const SizedBox(height: 9),

        if (_residente != null)
          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(Medidas.redondeo),
              side: const BorderSide(color: Colores.verde, width: 1.8),
            ),
            child: ListTile(
              leading: Avatar(
                iniciales: _iniciales(
                    _residente!['nombre_completo']?.toString() ?? '?'),
                tamano: 42,
              ),
              title: Text(
                _residente!['nombre_completo']?.toString() ?? '',
                style: const TextStyle(
                    fontSize: 14.5, fontWeight: FontWeight.w700),
              ),
              subtitle: Text(_unidadDe(_residente!, ref.read(palabrasProvider)) ??
                  'Sin ${ref.read(palabrasProvider).elEspacio} asignada'),
              trailing: IconButton(
                icon: const Icon(Icons.close_rounded),
                tooltip: 'Elegir otro',
                onPressed: _guardando
                    ? null
                    : () => setState(() {
                          _residente = null;
                          _busqueda.clear();
                          _encontrados = const [];
                        }),
              ),
            ),
          )
        else if (_aMano) ...[
          // Modo "a mano": campos abiertos + sugerencias de nombres ya usados
          // + botón para volver a la lista.
          //
          // Ojo con los labels: acá NO se usa el vocabulario de la
          // instalación (habitante/espacio, que en colegio dan "apoderado"
          // y "curso"). Para las encomiendas siempre hablamos de "residente"
          // y "casa/departamento/sitio", que es como el guardia escribe.
          TextField(
            controller: _nombreAMano,
            enabled: !_guardando,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            onChanged: _buscarSugerenciasAMano,
            decoration: const InputDecoration(
              labelText: 'Nombre del residente',
              hintText: 'Ej: María Fernández',
              prefixIcon: Icon(Icons.person_outline_rounded),
            ),
          ),
          // Sugerencias basadas en nombres que este mismo guardia (o el
          // anterior) ya escribió a mano en paquetes previos. Al tocar una
          // se completan nombre + unidad de una sola vez.
          if (_sugerenciasAMano.isNotEmpty) ...[
            const SizedBox(height: 8),
            Card(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 8),
                    child: Row(
                      children: [
                        const Icon(Icons.history_rounded,
                            size: 15, color: Colores.textoSuave),
                        const SizedBox(width: 6),
                        Text(
                          'Escritos antes',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.8,
                            color: Colores.textoSuave,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  for (var i = 0; i < _sugerenciasAMano.length; i++) ...[
                    if (i > 0) const Divider(height: 1),
                    ListTile(
                      dense: true,
                      leading: Avatar(
                        iniciales: _iniciales(
                            _sugerenciasAMano[i]['nombre'] as String),
                        tamano: 32,
                      ),
                      title: Text(
                        _sugerenciasAMano[i]['nombre'] as String,
                        style: const TextStyle(
                            fontSize: 13.5, fontWeight: FontWeight.w600),
                      ),
                      subtitle: (_sugerenciasAMano[i]['unidad'] as String)
                              .isEmpty
                          ? null
                          : Text(
                              _sugerenciasAMano[i]['unidad'] as String,
                              style: const TextStyle(fontSize: 12),
                            ),
                      onTap: () => setState(() {
                        _nombreAMano.text =
                            _sugerenciasAMano[i]['nombre'] as String;
                        _unidadAMano.text =
                            _sugerenciasAMano[i]['unidad'] as String;
                        _sugerenciasAMano = const [];
                      }),
                    ),
                  ],
                ],
              ),
            ),
          ],
          const SizedBox(height: 10),
          TextField(
            controller: _unidadAMano,
            enabled: !_guardando,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Casa, departamento o sitio (opcional)',
              hintText: 'Ej: Casa 12 · Depto 401 · Sitio 8',
              prefixIcon: Icon(Icons.location_on_outlined),
            ),
          ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _guardando
                  ? null
                  : () => setState(() {
                        _aMano = false;
                        _nombreAMano.clear();
                        _unidadAMano.clear();
                        _sugerenciasAMano = const [];
                      }),
              icon: const Icon(Icons.search_rounded, size: 18),
              label: const Text('Buscar de la lista'),
            ),
          ),
        ] else ...[
          TextField(
            controller: _busqueda,
            enabled: !_guardando,
            textCapitalization: TextCapitalization.words,
            onChanged: _buscar,
            decoration: InputDecoration(
              labelText: 'Buscar ${ref.read(palabrasProvider).elHabitante}',
              hintText: 'Nombre o cédula',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _buscando
                  ? const Padding(
                      padding: EdgeInsets.all(13),
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : null,
            ),
          ),
          if (_encontrados.isNotEmpty) ...[
            const SizedBox(height: 9),
            Card(
              child: Column(
                children: [
                  for (var i = 0; i < _encontrados.length; i++) ...[
                    if (i > 0) const Divider(height: 1),
                    Builder(builder: (_) {
                      final r = _encontrados[i];
                      final esAMano = r['es_a_mano'] == true;
                      final nombre =
                          r['nombre_completo']?.toString() ?? '';
                      // Subtítulo: si es "a mano" mostramos la unidad
                      // escrita a mano; si es residente formal, la unidad
                      // del sistema.
                      final subtitulo = esAMano
                          ? ((r['unidad_texto'] as String?)?.isEmpty ?? true
                              ? 'Escrito antes'
                              : 'Escrito antes · ${r['unidad_texto']}')
                          : (_unidadDe(r, ref.read(palabrasProvider)) ??
                              'Sin ${ref.read(palabrasProvider).elEspacio}');
                      return ListTile(
                        dense: true,
                        leading: Avatar(
                          iniciales: _iniciales(nombre.isEmpty ? '?' : nombre),
                          tamano: 34,
                        ),
                        title: Row(
                          children: [
                            Flexible(
                              child: Text(
                                nombre,
                                style: const TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w600),
                              ),
                            ),
                            if (esAMano) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 1),
                                decoration: BoxDecoration(
                                  color: Colores.dorado
                                      .withValues(alpha: 0.18),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Text(
                                  'A MANO',
                                  style: TextStyle(
                                    fontSize: 8.5,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.6,
                                    color: Colores.doradoOscuro,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        subtitle: Text(
                          subtitulo,
                          style: const TextStyle(fontSize: 12),
                        ),
                        onTap: () => setState(() {
                          if (esAMano) {
                            // Se activa el modo a mano y se precargan
                            // los datos, así el guardia solo confirma
                            // y guarda.
                            _aMano = true;
                            _nombreAMano.text = nombre;
                            _unidadAMano.text =
                                r['unidad_texto']?.toString() ?? '';
                            _busqueda.clear();
                            _encontrados = const [];
                            _sugerenciasAMano = const [];
                          } else {
                            _residente = r;
                            _encontrados = const [];
                          }
                        }),
                      );
                    }),
                  ],
                ],
              ),
            ),
          ],
          const SizedBox(height: 6),
          // Botón "Escribir a mano": indispensable cuando el destinatario
          // todavía no está registrado en el sistema.
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _guardando
                  ? null
                  : () {
                      setState(() {
                        _aMano = true;
                        _busqueda.clear();
                        _encontrados = const [];
                      });
                      // Cargar los últimos destinatarios ya escritos a mano,
                      // sin filtro: así el guardia ve los frecuentes al toque
                      // sin tener que empezar a escribir.
                      _buscarSugerenciasAMano('');
                    },
              icon: const Icon(Icons.edit_outlined, size: 18),
              label: const Text('Escribir el destinatario a mano'),
            ),
          ),
        ],

        const SizedBox(height: 20),

        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colores.grafito.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(Medidas.redondeoChico),
          ),
          child: const Row(
            children: [
              Icon(Icons.inventory_2_outlined,
                  size: 17, color: Colores.grafito),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Al guardar, el paquete queda en el inventario de portería. '
                  'Se entrega en persona cuando el residente lo retira.',
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.4,
                    color: Colores.textoSuave,
                  ),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

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
          label: Text(_guardando ? 'Guardando…' : 'Guardar paquete'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colores.verde,
            minimumSize: const Size.fromHeight(Medidas.altoBotonGigante),
            textStyle: const TextStyle(
                fontSize: 17, fontWeight: FontWeight.w800),
          ),
        ),
        const SizedBox(height: 26),
      ],
    );
  }
}

// ============================================================================
// PESTAÑA 2 · INVENTARIO Y ENTREGA
// ============================================================================

class _PestanaInventario extends ConsumerStatefulWidget {
  const _PestanaInventario();

  @override
  ConsumerState<_PestanaInventario> createState() => _EstadoInventario();
}

class _EstadoInventario extends ConsumerState<_PestanaInventario> {
  String _filtro = '';

  @override
  Widget build(BuildContext context) {
    final inventario = ref.watch(inventarioPaquetesProvider);

    return inventario.when(
      loading: () => const Center(
        child: CircularProgressIndicator(color: Colores.grafito),
      ),
      error: (falla, _) => Padding(
        padding: const EdgeInsets.all(Medidas.margen),
        child: AvisoDeError(
          problema: Traductor.traducir(falla),
          alReintentar: () => ref.invalidate(inventarioPaquetesProvider),
        ),
      ),
      data: (todos) {
        final texto = _filtro.trim().toLowerCase();
        final lista = texto.isEmpty
            ? todos
            : todos.where((p) {
                final campos = [
                  p['residente'],
                  p['unidad'],
                  p['numero_seguimiento'],
                  p['empresa_courier'],
                ].map((c) => c?.toString().toLowerCase() ?? '');
                return campos.any((c) => c.contains(texto));
              }).toList();

        final atrasados =
            todos.where((p) => p['alerta_antiguedad'] == true).length;

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  Medidas.margen, Medidas.margen, Medidas.margen, 8),
              child: TextField(
                onChanged: (t) => setState(() => _filtro = t),
                decoration: InputDecoration(
                  hintText: 'Buscar por nombre, ${ref.read(palabrasProvider).elEspacio} o número…',
                  prefixIcon: Icon(Icons.search_rounded),
                  isDense: true,
                ),
              ),
            ),

            if (atrasados > 0)
              Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: Medidas.margen, vertical: 4),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(11),
                  decoration: BoxDecoration(
                    color: Colores.rojo.withValues(alpha: 0.09),
                    borderRadius: BorderRadius.circular(Medidas.redondeoChico),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.schedule_rounded,
                          size: 17, color: Colores.rojoOscuro),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Text(
                          atrasados == 1
                              ? '1 paquete lleva más de una semana en portería.'
                              : '$atrasados paquetes llevan más de una semana en portería.',
                          style: const TextStyle(
                            fontSize: 12.5,
                            color: Colores.rojoOscuro,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            Expanded(
              child: lista.isEmpty
                  ? ListaVacia(
                      icono: Icons.inventory_2_outlined,
                      titulo: texto.isEmpty
                          ? 'No hay paquetes en portería'
                          : 'Ningún paquete coincide',
                      explicacion: texto.isEmpty
                          ? 'Cuando recibas uno, va a aparecer acá con su foto.'
                          : 'Probá con otro nombre, ${ref.read(palabrasProvider).elEspacio} o número.',
                    )
                  : RefreshIndicator(
                      onRefresh: () async =>
                          ref.invalidate(inventarioPaquetesProvider),
                      child: ListView.separated(
                        padding: const EdgeInsets.all(Medidas.margen),
                        itemCount: lista.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 11),
                        itemBuilder: (context, i) =>
                            _TarjetaInventario(paquete: lista[i]),
                      ),
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _TarjetaInventario extends ConsumerWidget {
  const _TarjetaInventario({required this.paquete});

  final Map<String, dynamic> paquete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final atrasado = paquete['alerta_antiguedad'] == true;
    final dias = (paquete['dias_en_porteria'] as num?)?.toInt() ?? 0;
    final recibido = DateTime.tryParse(paquete['recibido_en']?.toString() ?? '');

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Medidas.redondeo),
        side: BorderSide(
          color: atrasado ? Colores.rojo : Colores.linea,
          width: atrasado ? 1.5 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            FotoDelServidor(
              ruta: paquete['foto_url']?.toString(),
              cajon: CajonDeFotos.paquetes,
              ancho: 58,
              alto: 58,
              iconoSiFalta: Icons.inventory_2_outlined,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    paquete['residente']?.toString() ?? '—',
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w700),
                  ),
                  Text(
                    [
                      if (paquete['unidad'] != null)
                        '${ref.read(palabrasProvider).elEspacioConMayuscula} '
                        '${paquete['unidad']}',
                      if (paquete['numero_seguimiento'] != null)
                        'Nº ${paquete['numero_seguimiento']}',
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 12, color: Colores.textoSuave),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Etiqueta(
                        texto: Formato.cantidadDeDias(dias),
                        tono: atrasado
                            ? TonoEtiqueta.malo
                            : dias >= 3
                                ? TonoEtiqueta.espera
                                : TonoEtiqueta.neutro,
                      ),
                      if (recibido != null) ...[
                        const SizedBox(width: 7),
                        Text(
                          Formato.cuandoRelativo(recibido),
                          style: const TextStyle(
                              fontSize: 11, color: Colores.textoTenue),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: () => _abrirEntrega(context, ref, paquete),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colores.verde,
                minimumSize: const Size(0, 44),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                textStyle: const TextStyle(
                    fontSize: 13.5, fontWeight: FontWeight.w800),
              ),
              child: const Text('Entregar'),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// ENTREGAR: la firma del residente
// ============================================================================
// El residente firma con el dedo. Eso, con la hora exacta y quién lo entregó,
// es el respaldo completo de que el paquete salió de portería.
// ============================================================================

Future<void> _abrirEntrega(
  BuildContext context,
  WidgetRef ref,
  Map<String, dynamic> paquete,
) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colores.superficie,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _HojaDeEntrega(paquete: paquete),
  );
}

class _HojaDeEntrega extends ConsumerStatefulWidget {
  const _HojaDeEntrega({required this.paquete});

  final Map<String, dynamic> paquete;

  @override
  ConsumerState<_HojaDeEntrega> createState() => _EstadoEntrega();
}

class _EstadoEntrega extends ConsumerState<_HojaDeEntrega> {
  late final SignatureController _firma = SignatureController(
    penStrokeWidth: 3.2,
    penColor: Colores.texto,
    exportBackgroundColor: Colors.white,
  );

  final _retiradoPor = TextEditingController();
  bool _loRetiraOtro = false;
  bool _guardando = false;
  ErrorAmigable? _problema;
  // Nombres que ya retiraron paquetes de este residente en el pasado,
  // ordenados por frecuencia. Se cargan al abrir la hoja y sirven de chips
  // para que el guardia no reescriba el mismo nombre cada vez.
  List<String> _sugerenciasRetiro = const [];

  @override
  void initState() {
    super.initState();
    _cargarSugerencias();
  }

  Future<void> _cargarSugerencias() async {
    final residenteId = widget.paquete['residente_id'] as String?;
    if (residenteId == null || residenteId.isEmpty) return;
    try {
      final nombres = await ref
          .read(servicioGuardiaProvider)
          .quienSueleRetirar(residenteId: residenteId);
      if (mounted) setState(() => _sugerenciasRetiro = nombres);
    } catch (_) {
      // Silencioso: sin sugerencias el guardia escribe a mano.
    }
  }

  @override
  void dispose() {
    _firma.dispose();
    _retiradoPor.dispose();
    super.dispose();
  }

  Future<void> _confirmar() async {
    if (_firma.isEmpty) {
      setState(() => _problema = ErrorAmigable(
            'Falta la firma.',
            detalle: 'Pedile al ${ref.read(palabrasProvider).elHabitante} que firme con el dedo en el recuadro.',
            sePuedeReintentar: false,
          ));
      return;
    }

    final perfil = ref.read(perfilProvider).valueOrNull;
    final turno = ref.read(miTurnoProvider).valueOrNull;
    if (perfil == null) return;

    setState(() {
      _guardando = true;
      _problema = null;
    });

    try {
      final imagen = await _firma.toPngBytes();
      if (imagen == null) throw const ErrorAmigable('No se pudo guardar la firma.');

      // Se escribe a un archivo temporal para poder subirla
      final temporal = File(
        '${Directory.systemTemp.path}/firma_${DateTime.now().millisecondsSinceEpoch}.png',
      );
      await temporal.writeAsBytes(imagen);

      await ref.read(servicioGuardiaProvider).entregarPaquete(
            paqueteId: widget.paquete['id'] as String,
            condominioId: perfil.condominioId,
            firma: temporal,
            identidadValidada: !_loRetiraOtro,
            retiradoPor: _loRetiraOtro ? _retiradoPor.text : null,
            turnoId: turno?.id,
          );

      ref.invalidate(inventarioPaquetesProvider);
      ref.invalidate(resumenProvider);

      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Paquete entregado a ${widget.paquete['residente']}.',
          ),
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
    final p = widget.paquete;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom,
      ),
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

              Text('Entregar paquete',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 3),
              Text(
                '${p['residente']} · '
                '${p['unidad'] != null ? '${ref.read(palabrasProvider).elEspacio} ${p['unidad']}' : 'sin ${ref.read(palabrasProvider).elEspacio}'}',
                style: Theme.of(context).textTheme.bodySmall,
              ),

              const SizedBox(height: 16),

              if (_problema != null) ...[
                AvisoDeError(problema: _problema!),
                const SizedBox(height: 14),
              ],

              // ---- ¿Lo retira el residente u otra persona? ----
              SwitchListTile.adaptive(
                value: _loRetiraOtro,
                onChanged: _guardando
                    ? null
                    : (v) => setState(() => _loRetiraOtro = v),
                activeThumbColor: Colores.naranja,
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  'Lo retira otra persona',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
                subtitle: const Text(
                  'Un familiar, la nana, el conserje',
                  style: TextStyle(fontSize: 12, color: Colores.textoSuave),
                ),
              ),

              if (_loRetiraOtro) ...[
                const SizedBox(height: 4),
                if (_sugerenciasRetiro.isNotEmpty) ...[
                  const Padding(
                    padding: EdgeInsets.only(bottom: 6, top: 2),
                    child: Text(
                      'YA RETIRARON ANTES ACÁ',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2,
                        color: Colores.textoSuave,
                      ),
                    ),
                  ),
                  Wrap(
                    spacing: 6,
                    runSpacing: -4,
                    children: [
                      for (final nombre in _sugerenciasRetiro)
                        ActionChip(
                          label: Text(
                            nombre,
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          avatar: const Icon(Icons.history_rounded, size: 16),
                          onPressed: _guardando
                              ? null
                              : () {
                                  _retiradoPor.text = nombre;
                                  _retiradoPor.selection =
                                      TextSelection.collapsed(
                                          offset: nombre.length);
                                },
                          backgroundColor:
                              Colores.naranja.withValues(alpha: 0.08),
                          side: BorderSide(
                            color: Colores.naranja.withValues(alpha: 0.35),
                          ),
                          visualDensity: VisualDensity.compact,
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                ],
                TextField(
                  controller: _retiradoPor,
                  enabled: !_guardando,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: '¿Quién lo retira?',
                    hintText: 'Nombre y cédula si podés',
                    prefixIcon: Icon(Icons.person_outline_rounded),
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colores.naranja.withValues(alpha: 0.09),
                    borderRadius: BorderRadius.circular(Medidas.redondeoChico),
                  ),
                  child: Text(
                    'Queda registrado que la entrega la recibió otra persona, '
                    'con su nombre. Sirve como respaldo si después el '
                    '${ref.read(palabrasProvider).elHabitante} reclama.',
                    style: const TextStyle(
                      fontSize: 12,
                      height: 1.4,
                      color: Colores.naranjaOscuro,
                    ),
                  ),
                ),
              ],

              const SizedBox(height: 16),

              // ---- La firma ----
              Text('FIRMA DE QUIEN RETIRA',
                  style: Theme.of(context).textTheme.labelSmall),
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(Medidas.redondeo),
                  border: Border.all(color: Colores.grafito, width: 1.5),
                ),
                child: Column(
                  children: [
                    ClipRRect(
                      borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(Medidas.redondeo - 1)),
                      child: Signature(
                        controller: _firma,
                        height: 165,
                        backgroundColor: Colors.white,
                      ),
                    ),
                    Container(
                      decoration: const BoxDecoration(
                        border: Border(
                            top: BorderSide(color: Colores.linea)),
                      ),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 7),
                      child: Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Firmá con el dedo sobre el recuadro',
                              style: TextStyle(
                                fontSize: 11.5,
                                color: Colores.textoSuave,
                              ),
                            ),
                          ),
                          TextButton.icon(
                            onPressed: _guardando
                                ? null
                                : () => setState(() => _firma.clear()),
                            icon: const Icon(Icons.refresh_rounded, size: 16),
                            label: const Text('Borrar'),
                            style: TextButton.styleFrom(
                              foregroundColor: Colores.textoSuave,
                              textStyle: const TextStyle(fontSize: 12.5),
                              minimumSize: const Size(0, 32),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 18),

              ElevatedButton.icon(
                onPressed: _guardando ? null : _confirmar,
                icon: _guardando
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2.4, color: Colors.white),
                      )
                    : const Icon(Icons.check_rounded, size: 22),
                label: Text(_guardando ? 'Guardando…' : 'CONFIRMAR ENTREGA'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colores.verde,
                  minimumSize: const Size.fromHeight(Medidas.altoBotonGigante),
                  textStyle: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w800),
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
// Ayudas
// ============================================================================

String _iniciales(String nombre) {
  final partes = nombre.trim().split(RegExp(r'\s+'));
  if (partes.isEmpty) return '?';
  if (partes.length == 1) {
    return partes.first
        .substring(0, partes.first.length >= 2 ? 2 : 1)
        .toUpperCase();
  }
  return '${partes[0][0]}${partes[1][0]}'.toUpperCase();
}

/// Arma el texto del espacio de una persona: "Unidad 302" o "Curso 4B".
///
/// La palabra llega de afuera porque esta funcion esta suelta, fuera de
/// cualquier pantalla, y desde aca no se puede preguntar de que tipo es la
/// instalacion.
String? _unidadDe(Map<String, dynamic> residente, Palabras palabras) {
  final u = residente['unidades'];
  if (u is Map) {
    final texto = [u['numero'], u['torre']]
        .where((p) => p != null && p.toString().isNotEmpty)
        .join(' ');
    return texto.isEmpty ? null : '${palabras.elEspacioConMayuscula} $texto';
  }
  return null;
}
