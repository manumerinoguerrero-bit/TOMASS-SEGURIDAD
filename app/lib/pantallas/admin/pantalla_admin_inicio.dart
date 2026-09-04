// ============================================================================
// Tomass Seguridad — Panel de administración · Inicio
// ============================================================================
// Rediseñado con el estilo Merlyn Seguridad:
//   - Encabezado "Panel de Control" en azul marino + subtítulo con el
//     nombre de la instalación.
//   - Selector de instalación (si el admin atiende varias).
//   - Card destacada si hay algo pendiente ("Te están esperando") o
//     verde de "Todo al día".
//   - Grid 2x3 de KPI cards con ícono de color arriba y número grande.
//   - Sección "ADMINISTRAR" con accesos a las otras pantallas.
//
// Lo primero que ve el administrador. Está pensado para contestar en tres
// segundos una sola pregunta: ¿HAY ALGO QUE TENGO QUE HACER AHORA?
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../config/tema.dart';
import '../../estado/proveedores.dart';
import '../../estado/proveedores_admin.dart';
import '../../modelos/admin.dart';
import '../../navegacion/rutas.dart';
import '../../nucleo/errores.dart';
import '../comunes/componentes.dart';
import 'acciones_admin.dart';

class PantallaAdminInicio extends ConsumerWidget {
  const PantallaAdminInicio({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resumen = ref.watch(resumenAdminProvider);
    final perfil = ref.watch(perfilProvider).valueOrNull;
    final palabras = ref.watch(palabrasProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Panel de administración'),
        actions: const [MenuDelAdmin()],
      ),
      body: resumen.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: Colores.grafito),
        ),
        error: (falla, _) => Padding(
          padding: const EdgeInsets.all(Medidas.margen),
          child: AvisoDeError(
            problema: Traductor.traducir(falla),
            alReintentar: () => ref.invalidate(resumenAdminProvider),
          ),
        ),
        data: (r) => RefreshIndicator(
          onRefresh: () async => refrescarPanel(ref),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              // Encabezado
              const _Bienvenida(),
              const SizedBox(height: 6),
              Text(
                perfil?.nombreCondominio ?? '…',
                style: const TextStyle(
                  fontSize: 13,
                  color: Colores.textoSuave,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 20),

              // Selector de instalación (solo si atiende más de una)
              const SelectorDeInstalacion(),

              // Card destacada: pendientes o todo al día
              if (r.hayPendientes)
                _LoQueFalta(resumen: r)
              else
                const _TodoAlDia(),

              const SizedBox(height: 24),
              const _TituloSeccion('CÓMO VA TODO'),
              const SizedBox(height: 12),

              _KpiGrid(resumen: r, palabras: palabras),

              const SizedBox(height: 24),
              const _TituloSeccion('ADMINISTRAR'),
              const SizedBox(height: 12),

              // ⚠️ ACÁ VA push Y NO go. NO LO CAMBIES.
              //
              //    "go" REEMPLAZA la pantalla; "push" la APILA encima.
              //    El administrador no tiene barra de pestañas abajo:
              //    con "go" quedaría encerrado sin flecha de volver.

              _Acceso(
                icono: Icons.directions_car_rounded,
                titulo: 'Vehículos',
                detalle: r.vehiculosPorAprobar == 0
                    ? 'No hay ninguno esperando'
                    : '${r.vehiculosPorAprobar} esperando tu aprobación',
                urgente: r.vehiculosPorAprobar > 0,
                alTocar: () => context.push(Rutas.adminVehiculos),
              ),
              _Acceso(
                icono: Icons.people_alt_rounded,
                titulo: palabras.losHabitantesConMayuscula,
                detalle: 'Dar de alta, editar y desactivar personas',
                alTocar: () => context.push(Rutas.adminPersonas),
              ),
              _Acceso(
                icono: Icons.meeting_room_rounded,
                titulo: palabras.losEspaciosConMayuscula,
                detalle: '${r.espacios} registrados',
                alTocar: () => context.push(Rutas.adminEspacios),
              ),
              _Acceso(
                icono: Icons.add_location_alt_rounded,
                titulo: 'Sectores de la ronda',
                detalle: 'Los carteles que marca el guardia al recorrer',
                alTocar: () => context.push(Rutas.adminSectores),
              ),
              _Acceso(
                icono: Icons.assessment_rounded,
                titulo: 'Informes',
                detalle: 'Quién entró y salió, y los turnos de los guardias',
                alTocar: () => context.push(Rutas.adminInformes),
              ),

              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// ENCABEZADO ESTILO MERLYN
// ============================================================================

class _Bienvenida extends StatelessWidget {
  const _Bienvenida();

  @override
  Widget build(BuildContext context) {
    return const Text(
      'Panel de Control',
      style: TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.w800,
        color: Colores.grafito,
        letterSpacing: -0.4,
      ),
    );
  }
}

class _TituloSeccion extends StatelessWidget {
  const _TituloSeccion(this.texto);

  final String texto;

  @override
  Widget build(BuildContext context) {
    return Text(
      texto,
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w800,
        color: Colores.grafito,
        letterSpacing: 1.2,
      ),
    );
  }
}

// ============================================================================
// LO QUE ESTÁ ESPERANDO
// ============================================================================

class _LoQueFalta extends StatelessWidget {
  const _LoQueFalta({required this.resumen});

  final ResumenAdmin resumen;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colores.naranja.withValues(alpha: 0.08),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Medidas.redondeo),
        side: BorderSide(
            color: Colores.naranja.withValues(alpha: 0.4), width: 1.3),
      ),
      child: Padding(
        padding: const EdgeInsets.all(Medidas.margen),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.pending_actions_rounded,
                    color: Colores.naranjaOscuro, size: 22),
                const SizedBox(width: 10),
                const Text(
                  'Te están esperando',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: Colores.naranjaOscuro,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (resumen.vehiculosPorAprobar > 0)
              _Punto(
                texto: '${resumen.vehiculosPorAprobar} '
                    '${resumen.vehiculosPorAprobar == 1 ? "vehículo" : "vehículos"} '
                    'por aprobar',
                explicacion: 'Hasta que los apruebes, esas personas no pueden '
                    'entrar con su auto.',
              ),
            if (resumen.novedadesAbiertas > 0)
              _Punto(
                texto: '${resumen.novedadesAbiertas} '
                    '${resumen.novedadesAbiertas == 1 ? "novedad" : "novedades"} '
                    'sin resolver',
                explicacion: 'Cosas que anotaron los guardias y siguen abiertas.',
              ),
          ],
        ),
      ),
    );
  }
}

class _Punto extends StatelessWidget {
  const _Punto({required this.texto, required this.explicacion});

  final String texto;
  final String explicacion;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(texto,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
          Text(
            explicacion,
            style: const TextStyle(
                fontSize: 12, height: 1.4, color: Colores.textoSuave),
          ),
        ],
      ),
    );
  }
}

class _TodoAlDia extends StatelessWidget {
  const _TodoAlDia();

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colores.verde.withValues(alpha: 0.08),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Medidas.redondeo),
        side: BorderSide(color: Colores.verde.withValues(alpha: 0.35)),
      ),
      child: const Padding(
        padding: EdgeInsets.all(Medidas.margen),
        child: Row(
          children: [
            Icon(Icons.check_circle_rounded,
                color: Colores.verdeOscuro, size: 24),
            SizedBox(width: 11),
            Expanded(
              child: Text(
                'Todo al día. No hay nada esperando que hagas.',
                style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                  color: Colores.verdeOscuro,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// KPI GRID ESTILO MERLYN
// ============================================================================

class _KpiGrid extends StatelessWidget {
  const _KpiGrid({required this.resumen, required this.palabras});

  final ResumenAdmin resumen;
  final dynamic palabras;

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: 1.4,
      children: [
        _KpiCard(
          etiqueta: 'Personas activas',
          numero: '${resumen.personasActivas}',
          icono: Icons.people_alt_outlined,
          color: Colores.grafito,
        ),
        _KpiCard(
          etiqueta: resumen.guardiasDeTurno == 1
              ? 'Guardia de turno'
              : 'Guardias de turno',
          numero: '${resumen.guardiasDeTurno}',
          icono: Icons.shield_outlined,
          color: resumen.guardiasDeTurno == 0
              ? Colores.rojo
              : Colores.verde,
        ),
        _KpiCard(
          etiqueta: 'Paquetes en portería',
          numero: '${resumen.paquetesEnPorteria}',
          icono: Icons.inventory_2_outlined,
          color: Colores.naranja,
        ),
        _KpiCard(
          etiqueta: palabras.losEspacios as String,
          numero: '${resumen.espacios}',
          icono: Icons.meeting_room_outlined,
          color: Colores.dorado,
        ),
      ],
    );
  }
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({
    required this.etiqueta,
    required this.numero,
    required this.icono,
    required this.color,
  });

  final String etiqueta;
  final String numero;
  final IconData icono;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Icon(icono, color: color, size: 24),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  numero,
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    color: color,
                    height: 1.1,
                    letterSpacing: -0.5,
                  ),
                ),
                Text(
                  etiqueta,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: Colores.textoSuave,
                    height: 1.25,
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
// LOS ACCESOS A LAS OTRAS PANTALLAS
// ============================================================================

class _Acceso extends StatelessWidget {
  const _Acceso({
    required this.icono,
    required this.titulo,
    required this.detalle,
    required this.alTocar,
    this.urgente = false,
  });

  final IconData icono;
  final String titulo;
  final String detalle;
  final VoidCallback alTocar;
  final bool urgente;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: alTocar,
        borderRadius: BorderRadius.circular(Medidas.redondeo),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: (urgente ? Colores.naranja : Colores.grafito)
                      .withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icono,
                    size: 22,
                    color: urgente ? Colores.naranjaOscuro : Colores.grafito),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      titulo,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      detalle,
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.3,
                        color: urgente
                            ? Colores.naranjaOscuro
                            : Colores.textoSuave,
                        fontWeight: urgente ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded,
                  color: Colores.textoTenue),
            ],
          ),
        ),
      ),
    );
  }
}
