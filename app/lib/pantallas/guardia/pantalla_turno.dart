// ============================================================================
// Tomass Seguridad — Pantalla 10 · Inicio de turno del guardia
// ============================================================================
// LA PANTALLA MÁS IMPORTANTE QUE NADIE NOTA
//
//   Es la que hace que los avisos lleguen al guardia correcto. Si Carlos marca
//   "Entrada Vehicular", los autos que llegan a la barrera le suenan a ÉL y no al
//   de la garita peatonal.
//
//   Sin turno abierto, el guardia no recibe ningún aviso. Por eso esta pantalla
//   aparece sola al entrar y no se puede saltear.
//
// TAMBIÉN DEJA EL REGISTRO DE QUIÉN ESTABA A CARGO
//   Si el día de mañana hay que revisar quién dejó pasar a alguien, el turno dice
//   qué guardia estaba en qué puerta y a qué hora.
// ============================================================================

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/tema.dart';
import '../../estado/proveedores.dart';
import '../../estado/proveedores_guardia.dart';
import '../../modelos/modelos.dart';
import '../../nucleo/errores.dart';
import '../../nucleo/formato.dart';
import '../../nucleo/ubicacion.dart';
import '../../servicios/servicio_fotos.dart';
import '../comunes/componentes.dart';
import 'acciones_de_turno.dart';

class PantallaTurno extends ConsumerStatefulWidget {
  const PantallaTurno({super.key});

  @override
  ConsumerState<PantallaTurno> createState() => _EstadoTurno();
}

class _EstadoTurno extends ConsumerState<PantallaTurno> {
  /// null = todavía no eligió. Cadena vacía = eligió "cubro todo".
  /// Cualquier otra cosa = el id del puesto puntual.
  String? _eleccion = _cubroTodo;

  static const _cubroTodo = '';

  bool _trabajando = false;
  ErrorAmigable? _problema;

  Future<void> _empezar() async {
    if (_eleccion == null) return;

    final perfil = ref.read(perfilProvider).valueOrNull;
    if (perfil == null) {
      setState(() => _problema = const ErrorAmigable(
            'Todavía se están cargando tus datos.',
            detalle: 'Esperá un segundo y volvé a intentar.',
          ));
      return;
    }

    // -----------------------------------------------------------------------
    // Selfie del guardia + ubicación GPS del inicio
    // -----------------------------------------------------------------------
    // El admin necesita saber quién estaba a cargo y dónde. La selfie es
    // obligatoria porque es la única prueba real: sin ella cualquiera con
    // usuario y clave abre el turno desde otro lado. El GPS es "el que se
    // pueda": si no responde en unos segundos, se abre igual sin él.
    setState(() {
      _trabajando = true;
      _problema = null;
    });

    File? selfie;
    try {
      selfie = await ref.read(servicioFotosProvider).sacarFoto(
            proposito: PropositoDeLaFoto.elGuardiaEnTurno,
            frontal: true,
          );
    } catch (falla) {
      if (!mounted) return;
      setState(() {
        _trabajando = false;
        _problema = Traductor.traducir(falla);
      });
      return;
    }
    if (selfie == null) {
      // Canceló la cámara — no se abre turno sin selfie
      if (!mounted) return;
      setState(() {
        _trabajando = false;
        _problema = const ErrorAmigable(
          'Necesitás sacarte una selfie para abrir el turno.',
          detalle: 'Es la prueba de que sos vos el que está a cargo. Sin ella '
              'cualquiera con tu usuario y clave podría abrir turno desde otro '
              'lado.',
        );
      });
      return;
    }

    // GPS con timeout corto: no bloqueamos al guardia si no engancha señal.
    final donde = await Localizador.donde(
      esperaMaxima: const Duration(seconds: 8),
    );

    try {
      // Subir la selfie al bucket "guardias" ANTES de crear el turno, así
      // el registro nace con la foto ya guardada y no queda huérfana la
      // referencia si el insert falla.
      final rutaFoto = await ref.read(servicioFotosProvider).subir(
            archivo: selfie,
            cajon: CajonDeFotos.guardias,
            condominioId: perfil.condominioId,
            nombreDescriptivo: 'turno',
          );

      await ref.read(servicioGuardiaProvider).abrirTurno(
            condominioId: perfil.condominioId,
            // Vacío significa "cubro todo el condominio"
            puntoAccesoId: _eleccion == _cubroTodo ? null : _eleccion,
            fotoUrl: rutaFoto,
            geoLat: donde?.latitud,
            geoLng: donde?.longitud,
          );
      ref.invalidate(miTurnoProvider);
      // La navegación la maneja sola la app al detectar que hay turno abierto
    } catch (falla) {
      if (!mounted) return;
      setState(() {
        _trabajando = false;
        _problema = Traductor.traducir(falla);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Si cambia la instalación activa (por el selector de arriba), el puesto
    // que tenía elegido ya no existe en la lista nueva: sin esto, quedaría
    // "elegido" un puesto de la instalación anterior, invisible pero todavía
    // marcado, y el botón de empezar mandaría un id que ya no corresponde.
    ref.listen(perfilProvider, (anterior, actual) {
      final idAnterior = anterior?.valueOrNull?.condominioId;
      final idActual = actual.valueOrNull?.condominioId;
      if (idAnterior != null && idActual != null && idAnterior != idActual) {
        setState(() => _eleccion = _cubroTodo);
      }
    });

    final puestos = ref.watch(puestosDisponiblesProvider);
    final perfil = ref.watch(perfilProvider).valueOrNull;
    final anchoGrande = MediaQuery.sizeOf(context).width > 700;

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colores.azulOscuro,
              Colores.grafito,
              Colores.grafitoClaro,
            ],
            stops: [0.0, 0.5, 1.0],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(26),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                anchoGrande
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: _Bienvenida(perfil: perfil)),
                          const SizedBox(width: 34),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                const SelectorDeInstalacionGuardia(),
                                _Eleccion(
                                  puestos: puestos,
                                  elegido: _eleccion,
                                  trabajando: _trabajando,
                                  problema: _problema,
                                  alElegir: (id) =>
                                      setState(() => _eleccion = id),
                                  alEmpezar: _empezar,
                                  alReintentar: () => ref
                                      .invalidate(puestosDisponiblesProvider),
                                ),
                              ],
                            ),
                          ),
                        ],
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _Bienvenida(perfil: perfil),
                          const SizedBox(height: 26),
                          const SelectorDeInstalacionGuardia(),
                          _Eleccion(
                            puestos: puestos,
                            elegido: _eleccion,
                            trabajando: _trabajando,
                            problema: _problema,
                            alElegir: (id) =>
                                setState(() => _eleccion = id),
                            alEmpezar: _empezar,
                            alReintentar: () =>
                                ref.invalidate(puestosDisponiblesProvider),
                          ),
                        ],
                      ),

                    // La salida. Va acá abajo y no arriba a propósito: arriba
                    // le competiría la atención al botón de empezar el turno,
                    // que es lo que el guardia viene a hacer el 95% de las
                    // veces. Pero tiene que estar, porque el guardia que llega
                    // se encuentra con la sesión del que se fue.
                    const SizedBox(height: 28),
                    const SalirDeLaCuenta(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Bienvenida extends StatelessWidget {
  const _Bienvenida({required this.perfil});

  final Perfil? perfil;

  @override
  Widget build(BuildContext context) {
    final ahora = DateTime.now();
    final saludo = ahora.hour < 12
        ? 'Buenos días'
        : ahora.hour < 20
            ? 'Buenas tardes'
            : 'Buenas noches';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 96,
          height: 96,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colores.dorado.withValues(alpha: 0.32),
                blurRadius: 24,
                spreadRadius: 3,
              ),
            ],
          ),
          child: const LogoTomass(tamano: 96),
        ),
        const SizedBox(height: 20),
        Text(
          'Inicio de turno',
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w800,
            color: Colors.white,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '$saludo, ${perfil == null ? '' : Formato.nombreCorto(perfil!.nombreCompleto)}',
          style: TextStyle(
            fontSize: 15,
            color: Colors.white.withValues(alpha: 0.85),
          ),
        ),
        const SizedBox(height: 14),
        Text(
          'Si sos el único guardia, dejá la primera opción: vas a recibir los '
          'avisos de todas las entradas. Elegí un puesto solo si hay otro '
          'guardia cubriendo la otra puerta.',
          style: TextStyle(
            fontSize: 13.5,
            height: 1.5,
            color: Colors.white.withValues(alpha: 0.6),
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            Formato.diaCompleto(ahora).toUpperCase(),
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
              color: Colors.white.withValues(alpha: 0.8),
            ),
          ),
        ),
      ],
    );
  }
}

class _Eleccion extends ConsumerWidget {
  const _Eleccion({
    required this.puestos,
    required this.elegido,
    required this.trabajando,
    required this.problema,
    required this.alElegir,
    required this.alEmpezar,
    required this.alReintentar,
  });

  final AsyncValue<List<PuntoAcceso>> puestos;
  final String? elegido;
  final bool trabajando;
  final ErrorAmigable? problema;
  final void Function(String) alElegir;
  final VoidCallback alEmpezar;
  final VoidCallback alReintentar;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palabras = ref.watch(palabrasProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'MI PUESTO DE HOY',
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.1,
            color: Colors.white.withValues(alpha: 0.55),
          ),
        ),
        const SizedBox(height: 11),

        if (problema != null) ...[
          AvisoDeError(problema: problema!),
          const SizedBox(height: 14),
        ],

        puestos.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Center(child: CircularProgressIndicator(color: Colors.white)),
          ),
          error: (falla, _) => AvisoDeError(
            problema: Traductor.traducir(falla),
            alReintentar: alReintentar,
          ),
          data: (lista) {
            if (lista.isEmpty) {
              return Container(
                padding: const EdgeInsets.all(Medidas.margen),
                decoration: BoxDecoration(
                  color: Colores.superficie,
                  borderRadius: BorderRadius.circular(Medidas.redondeo),
                ),
                child: Text(
                  '${palabras.instalacionConMayuscula} todavía no tiene puestos de acceso '
                  'configurados. Avisale a la administración.',
                  style: TextStyle(fontSize: 13.5, height: 1.5),
                ),
              );
            }

            return Column(
              children: [
                // La opción normal va primera y destacada: en la mayoría de los
                // condominios hay UN SOLO guardia y tiene que cubrir las dos
                // entradas al mismo tiempo.
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _TarjetaCubroTodo(
                    elegido: elegido == '',
                    cuantasEntradas: lista.length,
                    alTocar: trabajando ? null : () => alElegir(''),
                  ),
                ),

                if (lista.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        Expanded(
                          child: Divider(
                            color: Colors.white.withValues(alpha: 0.2),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          child: Text(
                            'o solo una entrada',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.white.withValues(alpha: 0.5),
                            ),
                          ),
                        ),
                        Expanded(
                          child: Divider(
                            color: Colors.white.withValues(alpha: 0.2),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                for (final puesto in lista)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _TarjetaPuesto(
                      puesto: puesto,
                      elegido: puesto.id == elegido,
                      alTocar: trabajando ? null : () => alElegir(puesto.id),
                    ),
                  ),
              ],
            );
          },
        ),

        const SizedBox(height: 8),

        // Botón grande con gradiente verde y sombra profunda, estilo Merlyn.
        // Cuando no hay puesto elegido queda apagado (blanco semi-transparente).
        DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Medidas.redondeoChico),
            gradient: (elegido == null || trabajando)
                ? null
                : LinearGradient(
                    colors: [Colores.verde, Colores.verdeOscuro],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
            color: (elegido == null || trabajando)
                ? Colors.white.withValues(alpha: 0.15)
                : null,
            boxShadow: (elegido == null || trabajando)
                ? null
                : [
                    BoxShadow(
                      color: Colores.verde.withValues(alpha: 0.42),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
          ),
          child: ElevatedButton(
            onPressed: (elegido == null || trabajando) ? null : alEmpezar,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.transparent,
              shadowColor: Colors.transparent,
              foregroundColor: Colors.white,
              disabledBackgroundColor: Colors.transparent,
              disabledForegroundColor: Colors.white.withValues(alpha: 0.5),
              minimumSize: const Size.fromHeight(Medidas.altoBotonGigante),
              elevation: 0,
              textStyle: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.3,
              ),
            ),
            child: trabajando
                ? const SizedBox(
                    width: 26,
                    height: 26,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.6,
                      color: Colors.white,
                    ),
                  )
                : const Text('COMENZAR TURNO'),
          ),
        ),

        if (elegido == null) ...[
          const SizedBox(height: 10),
          Text(
            'Elegí un puesto para poder empezar',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12.5,
              color: Colors.white.withValues(alpha: 0.5),
            ),
          ),
        ],
      ],
    );
  }
}

// ============================================================================
// "Cubro todo el condominio" — la opción normal
// ============================================================================
// Va primera y destacada porque es lo que pasa en la mayoría de los
// condominios: hay UN SOLO guardia y tiene que atender la entrada peatonal y la
// vehicular al mismo tiempo.
//
// Con la opción de un puesto puntual, ese guardia quedaría ciego a la mitad: si
// elige la vehicular no se entera de los peatones, y si elige la peatonal no ve
// los autos esperando en la barrera.
// ============================================================================

class _TarjetaCubroTodo extends ConsumerWidget {
  const _TarjetaCubroTodo({
    required this.elegido,
    required this.cuantasEntradas,
    required this.alTocar,
  });

  final bool elegido;
  final int cuantasEntradas;
  final VoidCallback? alTocar;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palabras = ref.watch(palabrasProvider);

    return GestureDetector(
      onTap: alTocar,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: Colores.superficie,
          borderRadius: BorderRadius.circular(Medidas.redondeo),
          border: Border.all(
            color: elegido ? Colores.verde : Colors.transparent,
            width: 2.5,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: Colores.verde.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(11),
              ),
              child: const Icon(Icons.shield_rounded,
                  size: 25, color: Colores.verdeOscuro),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          'Todo ${palabras.laInstalacion}',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.2,
                          ),
                        ),
                      ),
                      const SizedBox(width: 7),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colores.verde.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Text(
                          'LO NORMAL',
                          style: TextStyle(
                            fontSize: 8.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.6,
                            color: Colores.verdeOscuro,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    cuantasEntradas <= 1
                        ? 'Recibís los avisos de todas las entradas'
                        : 'Recibís los avisos de las $cuantasEntradas entradas: '
                            'peatones y autos al mismo tiempo',
                    style: const TextStyle(
                      fontSize: 12.5,
                      height: 1.4,
                      color: Colores.textoSuave,
                    ),
                  ),
                ],
              ),
            ),
            AnimatedOpacity(
              duration: const Duration(milliseconds: 140),
              opacity: elegido ? 1 : 0,
              child: const Icon(Icons.check_circle_rounded,
                  color: Colores.verde, size: 26),
            ),
          ],
        ),
      ),
    );
  }
}

class _TarjetaPuesto extends StatelessWidget {
  const _TarjetaPuesto({
    required this.puesto,
    required this.elegido,
    required this.alTocar,
  });

  final PuntoAcceso puesto;
  final bool elegido;
  final VoidCallback? alTocar;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: alTocar,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: elegido
              ? Colores.superficie
              : Colores.superficie.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(Medidas.redondeo),
          border: Border.all(
            color: elegido ? Colores.verde : Colors.transparent,
            width: 2.5,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: Colores.grafito.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                puesto.esVehicular
                    ? Icons.directions_car_rounded
                    : Icons.directions_walk_rounded,
                size: 23,
                color: Colores.grafito,
              ),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    puesto.nombre,
                    style: const TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.1,
                    ),
                  ),
                  if (puesto.ubicacion != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      puesto.ubicacion!,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: Colores.textoSuave,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            AnimatedOpacity(
              duration: const Duration(milliseconds: 140),
              opacity: elegido ? 1 : 0,
              child: const Icon(
                Icons.check_circle_rounded,
                color: Colores.verde,
                size: 26,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
