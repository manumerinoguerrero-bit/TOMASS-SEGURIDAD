// ============================================================================
// Tomass Seguridad — El guardia pide autorización al residente
// ============================================================================
// EL CASO REAL DE LA GARITA DE UN CONDOMINIO
//
//   Llega alguien al portón y no está en ninguna lista. El guardia no puede
//   decidir por su cuenta: tiene que preguntarle al residente.
//
//   Hoy eso se hace por teléfono y no queda registro de nada. Si mañana el
//   residente dice "yo nunca autoricé a esa persona", el guardia no tiene con
//   qué defenderse. Con esto, la respuesta queda guardada con la hora.
//
// CÓMO ESTÁ PENSADA LA PANTALLA
//
//   El guardia tiene a la persona PARADA ADELANTE esperando. Entonces:
//
//     · Lo primero que se ve es la lista de lo que está esperando respuesta,
//       no el formulario. Si ya pidió permiso, quiere saber si contestaron.
//     · Cada tarjeta se pinta según en qué quedó: naranja esperando, verde
//       aprobada, roja rechazada. Se entiende sin leer.
//     · A los 3 minutos sin respuesta, la tarjeta le sugiere llamar por
//       teléfono. La visita no puede quedarse ahí para siempre.
//
// POR QUÉ "LO LLAMÉ POR TELÉFONO" ES UN BOTÓN Y NO UNA TRAMPA
//
//   El residente puede estar durmiendo, sin batería o sin señal. El guardia
//   igual tiene que resolver. Entonces puede marcar que llamó y que le dijeron
//   que sí.
//
//   Eso NO vale lo mismo que una aprobación desde la app: una la confirmó el
//   residente con su propio teléfono, la otra la afirma el guardia. Las dos
//   sirven, pero el informe las muestra distinto, y eso protege a los dos.
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/tema.dart';
import '../../estado/proveedores.dart';
import '../../estado/proveedores_guardia.dart';
import '../../modelos/guardia.dart';
import '../../nucleo/errores.dart';
import '../../nucleo/formato.dart';
import '../comunes/componentes.dart';
import 'acciones_de_turno.dart';
import 'formulario_visita_guardia.dart';

class PantallaVisitasGuardia extends ConsumerWidget {
  const PantallaVisitasGuardia({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final visitas = ref.watch(visitasEsperandoProvider);
    final palabras = ref.watch(palabrasProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Visitas'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Ver si ya contestaron',
            onPressed: () => ref.invalidate(visitasEsperandoProvider),
          ),
          const MenuDelGuardia(),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => abrirFormularioDeVisita(context),
        backgroundColor: Colores.grafito,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.person_add_alt_1_rounded),
        label: const Text('Registrar visita',
            style: TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: visitas.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: Colores.grafito),
        ),
        error: (falla, _) => Padding(
          padding: const EdgeInsets.all(Medidas.margen),
          child: AvisoDeError(
            problema: Traductor.traducir(falla),
            alReintentar: () => ref.invalidate(visitasEsperandoProvider),
          ),
        ),
        data: (lista) {
          if (lista.isEmpty) {
            return ListaVacia(
              icono: Icons.person_add_alt_1_outlined,
              titulo: 'No hay visitas en la entrada',
              explicacion:
                  'Cuando llegue alguien que no está en ninguna lista, tocá '
                  '"Registrar visita". Le va a llegar el aviso al '
                  '${palabras.elHabitante} en su celular para que autorice.',
            );
          }

          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(visitasEsperandoProvider),
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(
                  Medidas.margen, Medidas.margen, Medidas.margen, 96),
              itemCount: lista.length,
              itemBuilder: (_, i) =>
                  _Tarjeta(visita: lista[i], palabras: palabras),
            ),
          );
        },
      ),
    );
  }
}

// ============================================================================
// UNA VISITA
// ============================================================================

class _Tarjeta extends ConsumerWidget {
  const _Tarjeta({required this.visita, required this.palabras});

  final VisitaEsperando visita;
  final dynamic palabras;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final v = visita;

    final (color, tono, titulo) = switch (v.estado) {
      'aprobada' => (Colores.verde, Colores.verdeOscuro, 'AUTORIZADA'),
      'rechazada' => (Colores.rojo, Colores.rojoOscuro, 'NO AUTORIZADA'),
      _ => (Colores.naranja, Colores.naranjaOscuro, 'ESPERANDO RESPUESTA'),
    };

    return Card(
      margin: const EdgeInsets.only(bottom: 11),
      color: color.withValues(alpha: 0.05),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Medidas.redondeo),
        side: BorderSide(color: color.withValues(alpha: 0.55), width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(Medidas.margen),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ---- En qué quedó, bien visible ----
            Row(
              children: [
                Icon(
                  switch (v.estado) {
                    'aprobada' => Icons.check_circle_rounded,
                    'rechazada' => Icons.cancel_rounded,
                    _ => Icons.hourglass_top_rounded,
                  },
                  size: 20,
                  color: tono,
                ),
                const SizedBox(width: 8),
                Text(
                  titulo,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.1,
                    color: tono,
                  ),
                ),
                const Spacer(),
                Text(
                  v.estaEsperando
                      ? 'hace ${v.minutosEsperando} min'
                      : Formato.hora(v.creadoEn),
                  style: const TextStyle(
                      fontSize: 11.5, color: Colores.textoSuave),
                ),
              ],
            ),

            const SizedBox(height: 11),

            // ---- Quién es ----
            Text(v.nombreVisitante,
                style: const TextStyle(
                    fontSize: 17, fontWeight: FontWeight.w800, height: 1.2)),
            const SizedBox(height: 3),
            Text(
              [
                if (v.patente != null) v.patente!,
                'Va a ${v.residente}',
                if (v.espacio != '—') '${palabras.elEspacioConMayuscula} ${v.espacio}',
              ].join(' · '),
              style: const TextStyle(fontSize: 12.5, color: Colores.textoSuave),
            ),

            if (v.motivo != null && v.motivo!.isNotEmpty) ...[
              const SizedBox(height: 7),
              Text('Dice: ${v.motivo}',
                  style: const TextStyle(
                      fontSize: 12.5, fontStyle: FontStyle.italic)),
            ],

            // ---- Si el residente rechazó, por qué ----
            if (v.fueRechazada && v.motivoRechazo != null) ...[
              const SizedBox(height: 9),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colores.rojo.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(Medidas.redondeoChico),
                ),
                child: Text('Motivo: ${v.motivoRechazo}',
                    style: const TextStyle(
                        fontSize: 12.5,
                        height: 1.4,
                        fontWeight: FontWeight.w600,
                        color: Colores.rojoOscuro)),
              ),
            ],

            // ---- Si el guardia además llamó ----
            if (v.llamoPorTelefono) ...[
              const SizedBox(height: 9),
              Row(
                children: [
                  const Icon(Icons.phone_in_talk_rounded,
                      size: 15, color: Colores.textoSuave),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Lo llamaste por teléfono y te dijo que sí. Queda '
                      'anotado, pero no es lo mismo que si contesta desde la app.',
                      style: const TextStyle(
                          fontSize: 11.5, height: 1.4, color: Colores.textoSuave),
                    ),
                  ),
                ],
              ),
            ],

            // ---- Si lleva rato esperando, conviene llamar ----
            if (v.convieneLlamar) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(11),
                decoration: BoxDecoration(
                  color: Colores.naranja.withValues(alpha: 0.11),
                  borderRadius: BorderRadius.circular(Medidas.redondeoChico),
                ),
                child: Text(
                  'Lleva ${v.minutosEsperando} minutos sin contestar. Puede '
                  'estar durmiendo o sin señal: conviene llamarlo por teléfono '
                  'y no dejar a la persona esperando en el portón.',
                  style: const TextStyle(
                      fontSize: 12,
                      height: 1.45,
                      fontWeight: FontWeight.w600,
                      color: Colores.naranjaOscuro),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
