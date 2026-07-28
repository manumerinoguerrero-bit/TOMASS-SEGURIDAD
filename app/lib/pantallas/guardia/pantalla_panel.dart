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

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../config/tema.dart';
import '../../estado/proveedores.dart';
import '../../estado/proveedores_guardia.dart';
import '../../modelos/modelos.dart';
import '../../navegacion/rutas.dart';
import '../../nucleo/errores.dart';
import '../../nucleo/formato.dart';
import '../comunes/componentes.dart';
import 'acciones_de_turno.dart';

class PantallaPanel extends ConsumerWidget {
  const PantallaPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resumen = ref.watch(resumenProvider);
    final turno = ref.watch(miTurnoProvider).valueOrNull;
    final autos = ref.watch(cuantosAutosEsperandoProvider);
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
            // ---- 1. Lo urgente. Solo aparece si hay algo ----
            if (autos > 0) ...[
              _AlertaAutos(cuantos: autos),
              const SizedBox(height: 14),
            ],

            // ---- 2. Los números ----
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
// La alerta de autos esperando
// ============================================================================

class _AlertaAutos extends StatelessWidget {
  const _AlertaAutos({required this.cuantos});

  final int cuantos;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colores.rojo,
      borderRadius: BorderRadius.circular(Medidas.redondeo),
      child: InkWell(
        onTap: () => context.go(Rutas.autosEsperando),
        borderRadius: BorderRadius.circular(Medidas.redondeo),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: const Icon(Icons.directions_car_rounded,
                    size: 27, color: Colors.white),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      cuantos == 1
                          ? 'Hay 1 auto esperando la barrera'
                          : 'Hay $cuantos autos esperando la barrera',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Tocá para verlos y abrir el acceso',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.9),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded,
                  color: Colors.white, size: 30),
            ],
          ),
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
      ),
      _Numero(
        valor: '${resumen.personasDentro}',
        etiqueta: 'Personas dentro',
        icono: Icons.groups_rounded,
      ),
      _Numero(
        valor: '${resumen.paquetesEnPorteria}',
        etiqueta: 'Paquetes',
        icono: Icons.inventory_2_rounded,
        alerta: resumen.paquetesAtrasados > 0,
        nota: resumen.paquetesAtrasados > 0
            ? '${resumen.paquetesAtrasados} atrasados'
            : null,
      ),
      _Numero(
        valor: '${resumen.incidentesAbiertos}',
        etiqueta: 'Novedades',
        icono: Icons.report_rounded,
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
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 1.55,
      children: tarjetas,
    );
  }
}

class _Numero extends StatelessWidget {
  const _Numero({
    required this.valor,
    required this.etiqueta,
    required this.icono,
    this.alerta = false,
    this.nota,
  });

  final String valor;
  final String etiqueta;
  final IconData icono;
  final bool alerta;
  final String? nota;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: Colores.superficie,
        borderRadius: BorderRadius.circular(Medidas.redondeo),
        border: Border.all(
          color: alerta ? Colores.naranja : Colores.linea,
          width: alerta ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Icon(icono, size: 19,
              color: alerta ? Colores.naranjaOscuro : Colores.textoSuave),
          const SizedBox(height: 8),
          Text(
            valor,
            style: TextStyle(
              fontSize: 27,
              fontWeight: FontWeight.w800,
              height: 1,
              letterSpacing: -1,
              color: alerta ? Colores.naranjaOscuro : Colores.texto,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            etiqueta.toUpperCase(),
            style: const TextStyle(
              fontSize: 9.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.7,
              color: Colores.textoSuave,
            ),
          ),
          if (nota != null)
            Text(
              nota!,
              style: const TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                color: Colores.naranjaOscuro,
              ),
            ),
        ],
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

                    if (lista.length > 6) ...[
                      const SizedBox(height: 8),
                      Text(
                        'y ${lista.length - 6} más',
                        style: const TextStyle(
                          fontSize: 12,
                          fontStyle: FontStyle.italic,
                          color: Colores.textoSuave,
                        ),
                      ),
                    ],
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
                Text(
                  m.descripcion,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  [
                    Formato.cuandoRelativo(m.ocurridoEn),
                    if (m.puntoAcceso != null) m.puntoAcceso!,
                  ].join(' · '),
                  style: const TextStyle(
                    fontSize: 11,
                    color: Colores.textoSuave,
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
