// ============================================================================
// Tomass Seguridad — Panel de administración · Informes
// ============================================================================
// Dos cosas en dos pestañas:
//
//   ACCESOS → quién entró y salió, con fecha y hora. Es lo que se revisa cuando
//             hay un problema, y lo que el administrador lleva a la reunión de
//             copropietarios.
//
//   TURNOS  → qué guardia estuvo a cargo y en qué horario. Sirve para el pago
//             de horas y para saber a quién preguntarle por algo que pasó.
//
// Los registros de acceso no se pueden modificar ni borrar: la base de datos lo
// impide. Por eso sirven como prueba.
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/tema.dart';
import '../../estado/proveedores_admin.dart';
import '../../modelos/admin.dart';
import '../../nucleo/errores.dart';
import '../../nucleo/formato.dart';
import '../comunes/componentes.dart';
import 'acciones_admin.dart';

class PantallaAdminInformes extends ConsumerWidget {
  const PantallaAdminInformes({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Informes'),
          actions: const [MenuDelAdmin()],
          bottom: const TabBar(
            indicatorColor: Colors.white,
            indicatorWeight: 3,
            labelColor: Colors.white,
            labelStyle: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
            tabs: [
              Tab(text: 'Accesos'),
              Tab(text: 'Turnos'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [_PestanaAccesos(), _PestanaTurnos()],
        ),
      ),
    );
  }
}

// ============================================================================
// PESTAÑA 1 · QUIÉN ENTRÓ Y SALIÓ
// ============================================================================

class _PestanaAccesos extends ConsumerWidget {
  const _PestanaAccesos();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final movimientos = ref.watch(movimientosAdminProvider);
    final dias = ref.watch(diasDelInformeProvider);

    return Column(
      children: [
        // ---- Cuánto tiempo hacia atrás ----
        Padding(
          padding: const EdgeInsets.all(Medidas.margen),
          child: SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 1, label: Text('Hoy')),
              ButtonSegment(value: 7, label: Text('7 días')),
              ButtonSegment(value: 30, label: Text('30 días')),
            ],
            selected: {dias},
            onSelectionChanged: (s) =>
                ref.read(diasDelInformeProvider.notifier).state = s.first,
            showSelectedIcon: false,
          ),
        ),

        Expanded(
          child: movimientos.when(
            loading: () => const Center(
              child: CircularProgressIndicator(color: Colores.grafito),
            ),
            error: (falla, _) => Padding(
              padding: const EdgeInsets.all(Medidas.margen),
              child: AvisoDeError(
                problema: Traductor.traducir(falla),
                alReintentar: () => ref.invalidate(movimientosAdminProvider),
              ),
            ),
            data: (lista) {
              if (lista.isEmpty) {
                return const ListaVacia(
                  icono: Icons.history_rounded,
                  titulo: 'No hay accesos en este período',
                  explicacion:
                      'Probá con un período más largo, o esperá a que empiece '
                      'a usarse el sistema.',
                );
              }

              final denegados = lista.where((m) => !m.aprobado).length;

              return RefreshIndicator(
                onRefresh: () async => ref.invalidate(movimientosAdminProvider),
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(
                      Medidas.margen, 0, Medidas.margen, Medidas.margen),
                  itemCount: lista.length + 1,
                  itemBuilder: (_, i) {
                    if (i == 0) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text(
                          '${lista.length} '
                          '${lista.length == 1 ? "movimiento" : "movimientos"}'
                          '${denegados > 0 ? " · $denegados denegado${denegados == 1 ? "" : "s"}" : ""}',
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      );
                    }
                    return _FilaAcceso(movimiento: lista[i - 1]);
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _FilaAcceso extends StatelessWidget {
  const _FilaAcceso({required this.movimiento});

  final MovimientoAdmin movimiento;

  @override
  Widget build(BuildContext context) {
    final m = movimiento;
    final color = m.aprobado ? Colores.verde : Colores.rojo;

    return Card(
      margin: const EdgeInsets.only(bottom: 7),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
        child: Row(
          children: [
            // La flecha dice de un vistazo si entró o salió
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.11),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(
                m.esEntrada ? Icons.login_rounded : Icons.logout_rounded,
                size: 18,
                color: color,
              ),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    m.quien ?? 'Sin nombre registrado',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 13.5, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    [
                      m.esEntrada ? 'Entrada' : 'Salida',
                      if (m.esVehicular && m.patente != null) m.patente!,
                      if (m.espacio != null) m.espacio!,
                      if (m.entrada != null) m.entrada!,
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 11.5, color: Colores.textoSuave),
                  ),
                  if (!m.aprobado && m.motivoDenegacion != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(
                        m.motivoDenegacion!,
                        style: const TextStyle(
                            fontSize: 11.5,
                            height: 1.35,
                            fontWeight: FontWeight.w600,
                            color: Colores.rojoOscuro),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(Formato.hora(m.ocurridoEn),
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w700)),
                Text(Formato.diaYMes(m.ocurridoEn),
                    style: const TextStyle(
                        fontSize: 10.5, color: Colores.textoTenue)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// PESTAÑA 2 · LOS TURNOS DE LOS GUARDIAS
// ============================================================================

class _PestanaTurnos extends ConsumerWidget {
  const _PestanaTurnos();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final turnos = ref.watch(turnosAdminProvider);

    return turnos.when(
      loading: () => const Center(
        child: CircularProgressIndicator(color: Colores.grafito),
      ),
      error: (falla, _) => Padding(
        padding: const EdgeInsets.all(Medidas.margen),
        child: AvisoDeError(
          problema: Traductor.traducir(falla),
          alReintentar: () => ref.invalidate(turnosAdminProvider),
        ),
      ),
      data: (lista) {
        if (lista.isEmpty) {
          return const ListaVacia(
            icono: Icons.schedule_rounded,
            titulo: 'No hay turnos en las últimas dos semanas',
            explicacion:
                'Los turnos aparecen acá cuando un guardia abre el suyo en la app.',
          );
        }

        return RefreshIndicator(
          onRefresh: () async => ref.invalidate(turnosAdminProvider),
          child: ListView.builder(
            padding: const EdgeInsets.all(Medidas.margen),
            itemCount: lista.length,
            itemBuilder: (_, i) => _FilaTurno(turno: lista[i]),
          ),
        );
      },
    );
  }
}

class _FilaTurno extends StatelessWidget {
  const _FilaTurno({required this.turno});

  final TurnoAdmin turno;

  @override
  Widget build(BuildContext context) {
    final t = turno;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(13),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(t.guardia,
                      style: const TextStyle(
                          fontSize: 14.5, fontWeight: FontWeight.w700)),
                ),
                if (t.sigueAbierto)
                  const Etiqueta(texto: 'De turno', tono: TonoEtiqueta.bueno)
                else
                  Text(t.duracionEnPalabras,
                      style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: Colores.textoSuave)),
              ],
            ),
            const SizedBox(height: 5),
            Text(
              [
                // Sin puesto significa que cubría TODAS las entradas, que es el
                // caso normal cuando hay un solo guardia.
                t.puesto ?? 'Cubría todas las entradas',
                '${Formato.diaYMes(t.inicio)} · ${Formato.hora(t.inicio)}'
                    '${t.cerradoEn == null ? "" : " a ${Formato.hora(t.cerradoEn!)}"}',
              ].join(' · '),
              style: const TextStyle(fontSize: 12, color: Colores.textoSuave),
            ),
            if (t.notas != null && t.notas!.isNotEmpty) ...[
              const SizedBox(height: 9),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colores.grafito.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(Medidas.redondeoChico),
                ),
                child: Text(
                  'Dejó anotado: ${t.notas}',
                  style: const TextStyle(
                      fontSize: 12, height: 1.4, color: Colores.texto),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
