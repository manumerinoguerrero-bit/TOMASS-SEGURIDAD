// ============================================================================
// Tomass Seguridad — Panel de administración · Inicio
// ============================================================================
// Lo primero que ve el administrador al entrar. Está pensado para contestar una
// sola pregunta en tres segundos: ¿HAY ALGO QUE TENGO QUE HACER AHORA?
//
// Por eso lo pendiente va arriba, grande y en naranja, y los números generales
// van abajo, chicos. Si no hay nada pendiente, lo primero que se ve es un
// cartel verde que lo dice, y el administrador cierra la app tranquilo.
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
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Administración'),
            Text(
              perfil?.nombreCondominio ?? '…',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w400,
                color: Colors.white.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
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
            padding: const EdgeInsets.all(Medidas.margen),
            children: [
              // En qué instalación estás trabajando. Solo aparece si atendés
              // más de una.
              const SelectorDeInstalacion(),

              if (r.hayPendientes)
                _LoQueFalta(resumen: r)
              else
                const _TodoAlDia(),

              const SizedBox(height: 20),
              Text('CÓMO VA TODO',
                  style: Theme.of(context).textTheme.labelSmall),
              const SizedBox(height: 10),

              _Numeros(resumen: r, palabras: palabras),

              const SizedBox(height: 20),
              Text('ADMINISTRAR',
                  style: Theme.of(context).textTheme.labelSmall),
              const SizedBox(height: 10),

              // ⚠️ ACÁ VA push Y NO go. NO LO CAMBIES.
              //
              //    "go" REEMPLAZA la pantalla; "push" la APILA encima.
              //
              //    El administrador no tiene barra de pestañas abajo: estas
              //    pantallas se abren solas, ocupando todo. Con "go" no queda
              //    ninguna pantalla debajo, así que Flutter no dibuja la flecha
              //    de volver y el botón físico del teléfono tampoco hace nada:
              //    el administrador entra y queda encerrado, sin salida.
              //
              //    (En las pantallas del guardia sí se usa "go", y está bien:
              //     ahí la barra de pestañas está siempre visible, así que nunca
              //     se queda sin forma de moverse.)

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
                detalle: 'Los carteles que marca el guardia al hacer el recorrido',
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
// LO QUE ESTÁ ESPERANDO
// ============================================================================

class _LoQueFalta extends StatelessWidget {
  const _LoQueFalta({required this.resumen});

  final ResumenAdmin resumen;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colores.naranja.withValues(alpha: 0.07),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Medidas.redondeo),
        side: BorderSide(color: Colores.naranja.withValues(alpha: 0.5), width: 1.4),
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
                const SizedBox(width: 9),
                Text(
                  'Te están esperando',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: Colores.naranjaOscuro,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
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
      color: Colores.verde.withValues(alpha: 0.07),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Medidas.redondeo),
        side: BorderSide(color: Colores.verde.withValues(alpha: 0.4)),
      ),
      child: const Padding(
        padding: EdgeInsets.all(Medidas.margen),
        child: Row(
          children: [
            Icon(Icons.check_circle_rounded, color: Colores.verdeOscuro, size: 24),
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
// LOS NÚMEROS
// ============================================================================

class _Numeros extends StatelessWidget {
  const _Numeros({required this.resumen, required this.palabras});

  final ResumenAdmin resumen;
  final dynamic palabras;

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 1.9,
      mainAxisSpacing: 9,
      crossAxisSpacing: 9,
      children: [
        _Cuadro(
          numero: '${resumen.personasActivas}',
          etiqueta: 'personas activas',
          icono: Icons.people_outline_rounded,
        ),
        _Cuadro(
          numero: '${resumen.guardiasDeTurno}',
          etiqueta: resumen.guardiasDeTurno == 1
              ? 'guardia de turno'
              : 'guardias de turno',
          icono: Icons.shield_outlined,
          color: resumen.guardiasDeTurno == 0 ? Colores.rojo : Colores.verde,
        ),
        _Cuadro(
          numero: '${resumen.paquetesEnPorteria}',
          etiqueta: 'paquetes en portería',
          icono: Icons.inventory_2_outlined,
        ),
        _Cuadro(
          numero: '${resumen.espacios}',
          etiqueta: palabras.losEspacios as String,
          icono: Icons.meeting_room_outlined,
        ),
      ],
    );
  }
}

class _Cuadro extends StatelessWidget {
  const _Cuadro({
    required this.numero,
    required this.etiqueta,
    required this.icono,
    this.color,
  });

  final String numero;
  final String etiqueta;
  final IconData icono;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
        child: Row(
          children: [
            Icon(icono, size: 22, color: color ?? Colores.textoTenue),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    numero,
                    style: TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.w800,
                      height: 1.1,
                      color: color ?? Colores.texto,
                    ),
                  ),
                  Text(
                    etiqueta,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 11, height: 1.25, color: Colores.textoSuave),
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
      margin: const EdgeInsets.only(bottom: 9),
      child: ListTile(
        onTap: alTocar,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Medidas.redondeo),
        ),
        leading: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: (urgente ? Colores.naranja : Colores.grafito)
                .withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(11),
          ),
          child: Icon(icono,
              size: 21,
              color: urgente ? Colores.naranjaOscuro : Colores.grafito),
        ),
        title: Text(titulo,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        subtitle: Text(detalle,
            style: const TextStyle(fontSize: 12.5, height: 1.3)),
        trailing: const Icon(Icons.chevron_right_rounded,
            color: Colores.textoTenue),
      ),
    );
  }
}
