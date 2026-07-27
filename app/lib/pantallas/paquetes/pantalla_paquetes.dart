// ============================================================================
// Tomass Seguridad — Pantalla 07 · Mis paquetes
// ============================================================================
// POR QUÉ SE MUESTRA LA FOTO DEL PAQUETE Y NO SOLO EL NÚMERO
//   Porque el residente reconoce su paquete de un vistazo y sabe si es el que
//   esperaba. Un número de seguimiento de 9 dígitos no le dice nada a nadie.
//
// LOS ATRASADOS SE VEN EN ROJO
//   La portería tiene espacio limitado. Un paquete de 9 días ocupando el mostrador
//   es un problema del condominio, y el residente casi siempre se olvidó, no se
//   negó. Verlo en rojo con los días contados alcanza para que lo vaya a buscar.
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/tema.dart';
import '../../estado/proveedores.dart';
import '../../modelos/modelos.dart';
import '../../nucleo/errores.dart';
import '../../nucleo/formato.dart';
import '../../servicios/servicio_fotos.dart';
import '../comunes/componentes.dart';

class PantallaPaquetes extends ConsumerWidget {
  const PantallaPaquetes({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final paquetes = ref.watch(misPaquetesProvider);

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Mis paquetes'),
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
              Tab(
                text: paquetes.valueOrNull == null
                    ? 'En portería'
                    : 'En portería (${paquetes.value!.where((p) => p.estado == EstadoPaquete.enPorteria).length})',
              ),
              const Tab(text: 'Entregados'),
            ],
          ),
        ),
        body: paquetes.when(
          loading: () => const Center(
            child: CircularProgressIndicator(color: Colores.grafito),
          ),
          error: (falla, _) => Padding(
            padding: const EdgeInsets.all(Medidas.margen),
            child: AvisoDeError(
              problema: Traductor.traducir(falla),
              alReintentar: () => ref.invalidate(misPaquetesProvider),
            ),
          ),
          data: (lista) {
            final enPorteria = lista
                .where((p) => p.estado == EstadoPaquete.enPorteria)
                .toList();
            final cerrados = lista
                .where((p) => p.estado != EstadoPaquete.enPorteria)
                .toList();

            return TabBarView(
              children: [
                _Lista(
                  paquetes: enPorteria,
                  alRecargar: () => ref.invalidate(misPaquetesProvider),
                  vacia: const ListaVacia(
                    icono: Icons.inventory_2_outlined,
                    titulo: 'No tenés paquetes esperando',
                    explicacion:
                        'Cuando llegue uno a portería, te avisamos al celular y '
                        'lo vas a ver acá con su foto.',
                  ),
                  mostrarAvisoDeRetiro: enPorteria.isNotEmpty,
                ),
                _Lista(
                  paquetes: cerrados,
                  alRecargar: () => ref.invalidate(misPaquetesProvider),
                  vacia: const ListaVacia(
                    icono: Icons.check_circle_outline_rounded,
                    titulo: 'Todavía no retiraste ningún paquete',
                    explicacion:
                        'Acá va quedando el registro de cada entrega, con la '
                        'fecha y quién te lo entregó.',
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Lista extends StatelessWidget {
  const _Lista({
    required this.paquetes,
    required this.alRecargar,
    required this.vacia,
    this.mostrarAvisoDeRetiro = false,
  });

  final List<Paquete> paquetes;
  final VoidCallback alRecargar;
  final Widget vacia;
  final bool mostrarAvisoDeRetiro;

  @override
  Widget build(BuildContext context) {
    if (paquetes.isEmpty) {
      return RefreshIndicator(
        onRefresh: () async => alRecargar(),
        child: ListView(children: [SizedBox(height: 400, child: vacia)]),
      );
    }

    return RefreshIndicator(
      onRefresh: () async => alRecargar(),
      child: ListView.separated(
        padding: const EdgeInsets.all(Medidas.margen),
        itemCount: paquetes.length + (mostrarAvisoDeRetiro ? 1 : 0),
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, i) {
          if (i == paquetes.length) return const _ComoRetirar();
          return _TarjetaPaquete(paquete: paquetes[i]);
        },
      ),
    );
  }
}

class _TarjetaPaquete extends StatelessWidget {
  const _TarjetaPaquete({required this.paquete});

  final Paquete paquete;

  @override
  Widget build(BuildContext context) {
    final entregado = paquete.estado == EstadoPaquete.entregado;
    final atrasado = paquete.estaAtrasado;

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Medidas.redondeo),
        side: BorderSide(
          color: atrasado ? Colores.rojo : Colores.linea,
          width: atrasado ? 1.4 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(13),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FotoDelServidor(
                  ruta: paquete.fotoRuta,
                  cajon: CajonDeFotos.paquetes,
                  ancho: 66,
                  alto: 66,
                  iconoSiFalta: Icons.inventory_2_outlined,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        paquete.titulo,
                        style: const TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                          height: 1.25,
                        ),
                      ),
                      if (paquete.numeroSeguimiento != null) ...[
                        const SizedBox(height: 3),
                        Text(
                          'Nº ${paquete.numeroSeguimiento}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colores.textoSuave,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                      const SizedBox(height: 5),
                      Text(
                        entregado
                            ? 'Retirado ${Formato.cuandoRelativo(paquete.entregadoEn!)}'
                            : 'Llegó ${Formato.cuandoRelativo(paquete.recibidoEn)}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colores.textoSuave,
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (entregado)
                        const Etiqueta(
                          texto: 'Entregado',
                          tono: TonoEtiqueta.bueno,
                          icono: Icons.check_rounded,
                        )
                      else
                        Etiqueta(
                          texto: Formato.cantidadDeDias(paquete.diasEsperando),
                          tono: atrasado
                              ? TonoEtiqueta.malo
                              : paquete.diasEsperando >= 3
                                  ? TonoEtiqueta.espera
                                  : TonoEtiqueta.neutro,
                          icono: atrasado ? Icons.schedule_rounded : null,
                        ),
                    ],
                  ),
                ),
              ],
            ),

            if (atrasado) ...[
              const SizedBox(height: 11),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colores.rojo.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(Medidas.redondeoChico),
                ),
                child: Text(
                  'Lleva ${Formato.cantidadDeDias(paquete.diasEsperando)} en '
                  'portería. Pasá a retirarlo: el espacio es limitado.',
                  style: const TextStyle(
                    fontSize: 12.5,
                    height: 1.45,
                    color: Colores.rojoOscuro,
                  ),
                ),
              ),
            ],

            if (entregado) ...[
              const SizedBox(height: 10),
              const Divider(),
              const SizedBox(height: 8),
              _LineaDeDato(
                icono: Icons.person_outline_rounded,
                texto: paquete.retiradoPor != null
                    ? 'Lo retiró ${paquete.retiradoPor}'
                    : 'Lo retiraste vos',
              ),
              if (paquete.entregadoPor != null)
                _LineaDeDato(
                  icono: Icons.shield_outlined,
                  texto: 'Lo entregó ${paquete.entregadoPor}',
                ),
              _LineaDeDato(
                icono: Icons.schedule_rounded,
                texto: 'Estuvo ${Formato.cantidadDeDias(paquete.diasEsperando)} '
                    'en portería',
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _LineaDeDato extends StatelessWidget {
  const _LineaDeDato({required this.icono, required this.texto});

  final IconData icono;
  final String texto;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Icon(icono, size: 14, color: Colores.textoTenue),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              texto,
              style: const TextStyle(fontSize: 12, color: Colores.textoSuave),
            ),
          ),
        ],
      ),
    );
  }
}

class _ComoRetirar extends StatelessWidget {
  const _ComoRetirar();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 4, bottom: 22),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colores.grafito.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(Medidas.redondeo),
        border: Border.all(color: Colores.linea),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.qr_code_2_rounded, size: 20, color: Colores.grafito),
          SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Cómo retirarlo',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: Colores.texto,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Pasá por portería y mostrale tu código de acceso al guardia. '
                  'Vas a firmar con el dedo en su tablet y listo.',
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.45,
                    color: Colores.textoSuave,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
