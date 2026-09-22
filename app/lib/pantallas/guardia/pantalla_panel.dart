// ============================================================================
// Tomass Seguridad — Pantalla 11 · Panel del guardia
// ============================================================================
// La primera pantalla del turno. Tiene que contestar de un vistazo, sin tocar
// nada: ¿hay algo que necesite mi atención ahora mismo?
//
// EL ORDEN NO ES CASUAL
//   1. Lo urgente primero (autos esperando), en rojo y grande.
//   2. Los números del día.
//   3. Quién está adentro del condominio  ← el dato que piden los bomberos.
//   4. Los últimos movimientos, que se actualizan solos.
//
// SI NO HAY NADA URGENTE, LA PRIMERA TARJETA DESAPARECE.
//   Un panel que siempre muestra una alerta enseña al guardia a ignorarlas.
// ============================================================================

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/tema.dart';
import '../../estado/proveedores.dart';
import '../../estado/proveedores_guardia.dart';
import '../../modelos/modelos.dart';
import '../../nucleo/errores.dart';
import '../../nucleo/formato.dart';
import '../../servicios/rastreador_guardia.dart';
import '../comunes/componentes.dart';
import 'acciones_de_turno.dart';
import 'pantalla_personas_dentro.dart';

class PantallaPanel extends ConsumerWidget {
  const PantallaPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resumen = ref.watch(resumenProvider);
    final turno = ref.watch(miTurnoProvider).valueOrNull;
    final esAncho = MediaQuery.sizeOf(context).width >= 720;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Portería'),
            if (turno != null)
              Text(
                '${turno.puntoAccesoNombre} · desde ${Formato.hora(turno.inicio)}',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w400,
                  color: Colors.white.withValues(alpha: 0.7),
                ),
              ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Actualizar',
            onPressed: () {
              ref.invalidate(resumenProvider);
              ref.invalidate(ultimosAccesosProvider);
              ref.invalidate(personasDentroProvider);
            },
          ),
          const MenuDelGuardia(),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(resumenProvider);
          ref.invalidate(ultimosAccesosProvider);
          ref.invalidate(personasDentroProvider);
          ref.invalidate(incidentesProvider);
        },
        child: ListView(
          padding: const EdgeInsets.all(Medidas.margen),
          children: [
            // ---- Estado del GPS ----
            // Aviso visible al guardia si el rastreador esta activo,
            // demorado o bloqueado. Antes esto era invisible: si Android
            // mataba el foreground service, ni el guardia ni el admin se
            // enteraban hasta que el mapa en vivo mostraba "Sin senal"
            // muchas horas despues.
            if (turno != null) ...[
              const _BannerEstadoGps(),
              const SizedBox(height: 14),
            ],

            // ---- Los números ----
            //
            // La alerta de autos esperando se quitó del panel a pedido:
            // los autos se atienden desde la pestaña dedicada y no hace
            // falta que el panel llame la atención sobre eso.
            resumen.when(
              loading: () => const SizedBox(
                height: 120,
                child: Center(
                  child: CircularProgressIndicator(color: Colores.grafito),
                ),
              ),
              error: (falla, _) => AvisoDeError(
                problema: Traductor.traducir(falla),
                alReintentar: () => ref.invalidate(resumenProvider),
              ),
              data: (r) => _Numeros(resumen: r, enFila: esAncho),
            ),

            const SizedBox(height: 22),

            // ---- 3. Quién está adentro ----
            const _QuienEstaAdentro(),

            const SizedBox(height: 22),

            // ---- 4. Los últimos movimientos ----
            Row(
              children: [
                Text('ÚLTIMOS ACCESOS',
                    style: Theme.of(context).textTheme.labelSmall),
                const Spacer(),
                const Etiqueta(texto: 'En vivo', tono: TonoEtiqueta.bueno),
              ],
            ),
            const SizedBox(height: 9),
            const _UltimosAccesos(),

            const SizedBox(height: 26),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// Los números del día
// ============================================================================

class _Numeros extends StatelessWidget {
  const _Numeros({required this.resumen, required this.enFila});

  final ResumenCondominio resumen;
  final bool enFila;

  @override
  Widget build(BuildContext context) {
    final tarjetas = <Widget>[
      _Numero(
        valor: '${resumen.accesosHoy}',
        etiqueta: 'Accesos hoy',
        icono: Icons.login_rounded,
        color: Colores.grafito,
      ),
      _Numero(
        valor: '${resumen.personasDentro}',
        etiqueta: 'Personas dentro',
        icono: Icons.groups_rounded,
        color: Colores.verde,
      ),
      _Numero(
        valor: '${resumen.paquetesEnPorteria}',
        etiqueta: 'Paquetes',
        icono: Icons.inventory_2_rounded,
        color: Colores.naranja,
        alerta: resumen.paquetesAtrasados > 0,
        nota: resumen.paquetesAtrasados > 0
            ? '${resumen.paquetesAtrasados} atrasados'
            : null,
      ),
      _Numero(
        valor: '${resumen.incidentesAbiertos}',
        etiqueta: 'Novedades',
        icono: Icons.report_rounded,
        color: resumen.incidentesAbiertos > 0 ? Colores.rojo : Colores.dorado,
        alerta: resumen.incidentesAbiertos > 0,
      ),
    ];

    if (enFila) {
      return Row(
        children: [
          for (var i = 0; i < tarjetas.length; i++) ...[
            if (i > 0) const SizedBox(width: 10),
            Expanded(child: tarjetas[i]),
          ],
        ],
      );
    }

    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.4,
      children: tarjetas,
    );
  }
}

class _Numero extends StatelessWidget {
  const _Numero({
    required this.valor,
    required this.etiqueta,
    required this.icono,
    required this.color,
    this.alerta = false,
    this.nota,
  });

  final String valor;
  final String etiqueta;
  final IconData icono;
  final Color color;
  final bool alerta;
  final String? nota;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Medidas.redondeo),
        side: BorderSide(
          color: alerta
              ? color.withValues(alpha: 0.5)
              : Colors.black.withValues(alpha: 0.04),
          width: alerta ? 1.5 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Icon(icono, size: 24, color: color),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  valor,
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    height: 1.1,
                    letterSpacing: -0.5,
                    color: color,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  etiqueta,
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: Colores.textoSuave,
                    height: 1.25,
                  ),
                ),
                if (nota != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      nota!,
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: color,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// Quiénes están adentro del condominio
// ============================================================================
// PARA QUÉ SIRVE DE VERDAD: si hay un incendio y los bomberos preguntan cuánta
// gente queda adentro, esta lista es la respuesta.
//
// También marca las estadías raras: una visita que entró hace 14 horas y nunca
// salió es algo que conviene revisar.
// ============================================================================

class _QuienEstaAdentro extends ConsumerWidget {
  const _QuienEstaAdentro();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dentro = ref.watch(personasDentroProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('QUIÉNES ESTÁN ADENTRO',
                style: Theme.of(context).textTheme.labelSmall),
            const Spacer(),
            Text(
              '${dentro.valueOrNull?.length ?? 0} personas',
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: Colores.textoSuave,
              ),
            ),
          ],
        ),
        const SizedBox(height: 9),
        dentro.when(
          loading: () => const Card(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 28),
              child: Center(
                child: CircularProgressIndicator(color: Colores.grafito),
              ),
            ),
          ),
          error: (falla, _) => AvisoDeError(
            problema: Traductor.traducir(falla),
            alReintentar: () => ref.invalidate(personasDentroProvider),
            compacto: true,
          ),
          data: (lista) {
            if (lista.isEmpty) {
              return Card(
                child: Padding(
                  padding: EdgeInsets.all(Medidas.margen),
                  child: Text(
                    'No hay nadie registrado dentro de ${ref.watch(palabrasProvider).laInstalacion} ahora mismo.',
                    style: TextStyle(fontSize: 13, color: Colores.textoSuave),
                  ),
                ),
              );
            }

            final raros = lista.where((p) => p['estadia_inusual'] == true).toList();

            return Card(
              child: Padding(
                padding: const EdgeInsets.all(13),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (raros.isNotEmpty) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colores.naranja.withValues(alpha: 0.1),
                          borderRadius:
                              BorderRadius.circular(Medidas.redondeoChico),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.schedule_rounded,
                                size: 17, color: Colores.naranjaOscuro),
                            const SizedBox(width: 9),
                            Expanded(
                              child: Text(
                                raros.length == 1
                                    ? '1 persona lleva mucho tiempo adentro. Conviene revisar.'
                                    : '${raros.length} personas llevan mucho tiempo adentro.',
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  height: 1.4,
                                  color: Colores.naranjaOscuro,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 11),
                    ],

                    // Se muestran los primeros; el resto se resume
                    for (final p in lista.take(6))
                      _FilaPersona(persona: p),

                    // Botón para ver la lista completa con búsqueda.
                    // Aparece siempre — no solo cuando hay más de 6 — porque
                    // en la pantalla completa el guardia puede filtrar por
                    // patente o unidad, que en el resumen no se puede.
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: SizedBox(
                        width: double.infinity,
                        child: TextButton.icon(
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const PantallaPersonasDentro(),
                            ),
                          ),
                          icon: const Icon(Icons.list_alt_rounded, size: 18),
                          label: Text(lista.length > 6
                              ? 'Ver los ${lista.length} — buscar por nombre, unidad o patente'
                              : 'Ver todos con búsqueda'),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

class _FilaPersona extends StatelessWidget {
  const _FilaPersona({required this.persona});

  final Map<String, dynamic> persona;

  @override
  Widget build(BuildContext context) {
    final tipo = persona['persona_tipo']?.toString() ?? 'residente';
    final raro = persona['estadia_inusual'] == true;
    final entro = DateTime.tryParse(persona['entro_en']?.toString() ?? '');

    final (icono, nombreTipo) = switch (tipo) {
      'visita' => (Icons.person_add_alt_rounded, 'Visita'),
      'personal_servicio' => (Icons.handyman_rounded, 'Personal'),
      _ => (Icons.home_rounded, 'Residente'),
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(
        children: [
          Icon(icono, size: 16,
              color: raro ? Colores.naranjaOscuro : Colores.textoSuave),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  persona['nombre']?.toString() ?? '—',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  [
                    nombreTipo,
                    if (persona['unidad'] != null) 'unidad ${persona['unidad']}',
                    if (entro != null) 'entró ${Formato.haceCuanto(entro)}',
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    color: raro ? Colores.naranjaOscuro : Colores.textoSuave,
                  ),
                ),
              ],
            ),
          ),
          if (persona['patente'] != null)
            Text(
              persona['patente'].toString(),
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: Colores.textoSuave,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
        ],
      ),
    );
  }
}

// ============================================================================
// Los últimos accesos
// ============================================================================

class _UltimosAccesos extends ConsumerWidget {
  const _UltimosAccesos();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accesos = ref.watch(ultimosAccesosProvider);

    return accesos.when(
      loading: () => const Card(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 30),
          child: Center(child: CircularProgressIndicator(color: Colores.grafito)),
        ),
      ),
      error: (falla, _) => AvisoDeError(
        problema: Traductor.traducir(falla),
        alReintentar: () => ref.invalidate(ultimosAccesosProvider),
        compacto: true,
      ),
      data: (lista) {
        if (lista.isEmpty) {
          return const Card(
            child: Padding(
              padding: EdgeInsets.all(Medidas.margen),
              child: Text(
                'Todavía no hay movimientos registrados hoy.',
                style: TextStyle(fontSize: 13, color: Colores.textoSuave),
              ),
            ),
          );
        }

        return Card(
          child: Column(
            children: [
              for (var i = 0; i < lista.length; i++) ...[
                if (i > 0) const Divider(height: 1),
                _FilaAcceso(movimiento: lista[i]),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _FilaAcceso extends StatelessWidget {
  const _FilaAcceso({required this.movimiento});

  final Movimiento movimiento;

  @override
  Widget build(BuildContext context) {
    final m = movimiento;
    final color = m.aprobado
        ? (m.esEntrada ? Colores.verde : Colores.grafito)
        : Colores.rojo;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.11),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              m.esVehicular
                  ? Icons.directions_car_rounded
                  : Icons.directions_walk_rounded,
              size: 16,
              color: color,
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Primera línea: nombre de la persona (o el tipo genérico si
                // no se registró nombre). Es lo primero que el guardia quiere
                // ver — reemplaza al texto genérico "Entrada peatonal" que
                // había antes y que no ayudaba a saber quién había pasado.
                Text(
                  (m.nombre != null && m.nombre!.isNotEmpty)
                      ? m.nombre!
                      : m.descripcion,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                // Segunda línea: RUT + unidad + autorizador cuando existen.
                // Todo con separador " · " para no repetir labels; el guardia
                // ya sabe qué es cada cosa a primera vista.
                if (m.rut != null && m.rut!.isNotEmpty ||
                    m.unidad != null && m.unidad!.isNotEmpty ||
                    m.autorizadoPor != null && m.autorizadoPor!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: Text(
                      [
                        if (m.rut != null && m.rut!.isNotEmpty)
                          Formato.rut(m.rut),
                        if (m.unidad != null && m.unidad!.isNotEmpty) m.unidad!,
                        if (m.autorizadoPor != null &&
                            m.autorizadoPor!.isNotEmpty)
                          'autorizó ${m.autorizadoPor}',
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: Colores.texto,
                      ),
                    ),
                  ),
                // Tercera línea: cuándo, tipo de acceso, punto de acceso.
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    [
                      Formato.cuandoRelativo(m.ocurridoEn),
                      m.descripcion.toLowerCase(),
                      if (m.puntoAcceso != null) m.puntoAcceso!,
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Colores.textoSuave,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (m.patente != null)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Text(
                m.patente!,
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: Colores.textoSuave,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ),
          if (!m.aprobado)
            const Etiqueta(texto: 'Denegado', tono: TonoEtiqueta.malo),
        ],
      ),
    );
  }
}

// ============================================================================
// BANNER DE ESTADO DEL GPS
// ============================================================================
// Le dice al guardia — y de rebote al admin que le pregunte — si el rastreador
// esta mandando la posicion o si algo esta roto. Antes eso era invisible:
// solo el admin lo notaba dias despues mirando el mapa en vivo. Ahora si
// falta un permiso, el guardia lo ve en la primera pantalla del turno.
//
// Se refresca cada 30 s con un Timer local para que el "hace X min" quede
// al dia y para que el estado pase a demorado sin necesidad de que llegue
// una posicion nueva.
// ============================================================================

class _BannerEstadoGps extends ConsumerStatefulWidget {
  const _BannerEstadoGps();

  @override
  ConsumerState<_BannerEstadoGps> createState() => _EstadoBannerGps();
}

class _EstadoBannerGps extends ConsumerState<_BannerEstadoGps> {
  Timer? _refresco;

  @override
  void initState() {
    super.initState();
    // Timer solo para forzar rebuild y para que el rastreador evalue si
    // ya paso al estado "demorado". No dispara ningun GPS.
    _refresco = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!mounted) return;
      ref.read(rastreadorGuardiaProvider).evaluarDemora();
      setState(() {});
    });
  }

  @override
  void dispose() {
    _refresco?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rastreador = ref.watch(rastreadorGuardiaProvider);

    return ValueListenableBuilder<EstadoRastreador>(
      valueListenable: rastreador.estado,
      builder: (context, estado, _) {
        return ValueListenableBuilder<DateTime?>(
          valueListenable: rastreador.ultimoEnvio,
          builder: (context, ultimo, __) => _pintar(context, estado, ultimo),
        );
      },
    );
  }

  Widget _pintar(BuildContext context, EstadoRastreador estado, DateTime? ultimo) {
    final (color, icono, titulo, detalle) = switch (estado) {
      EstadoRastreador.apagado => (
          Colores.textoSuave,
          Icons.gps_off_outlined,
          'GPS apagado',
          'El rastreador no está corriendo.',
        ),
      EstadoRastreador.bloqueado => (
          Colores.rojo,
          Icons.location_disabled_rounded,
          'GPS bloqueado',
          'Faltan permisos. Ajustes → Apps → Tomass → Ubicación → '
              'Permitir todo el tiempo.',
        ),
      EstadoRastreador.esperandoPrimera => (
          Colores.naranjaOscuro,
          Icons.gps_not_fixed_rounded,
          'Buscando señal',
          'Puede tardar hasta 1 minuto en dar la primera posición.',
        ),
      EstadoRastreador.activo => (
          Colores.verde,
          Icons.gps_fixed_rounded,
          'GPS activo',
          ultimo == null
              ? 'Enviando ubicación al panel del admin.'
              : 'Última posición ${_haceCuanto(ultimo)}.',
        ),
      EstadoRastreador.demorado => (
          Colores.naranjaOscuro,
          Icons.gps_not_fixed_rounded,
          'GPS demorado',
          ultimo == null
              ? 'No mandaste posición todavía. Revisá permisos y señal.'
              : 'Última posición ${_haceCuanto(ultimo)}. '
                  'Puede ser mala señal o Android matando la app.',
        ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(Medidas.redondeoChico),
        border: Border.all(color: color.withValues(alpha: 0.35), width: 0.8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icono, size: 22, color: color),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titulo,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  detalle,
                  style: const TextStyle(
                    fontSize: 11.5,
                    height: 1.35,
                    color: Colores.texto,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// "hace 15 s", "hace 2 min", "hace 1 h 20 min".
  static String _haceCuanto(DateTime cuando) {
    final delta = DateTime.now().difference(cuando);
    if (delta.inSeconds < 60) return 'hace ${delta.inSeconds} s';
    if (delta.inMinutes < 60) return 'hace ${delta.inMinutes} min';
    final horas = delta.inHours;
    final min = delta.inMinutes % 60;
    return min == 0 ? 'hace $horas h' : 'hace $horas h $min min';
  }
}
