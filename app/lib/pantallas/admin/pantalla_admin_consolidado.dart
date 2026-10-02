// ============================================================================
// Tomass Seguridad — Panel de administración · Vista general
// ============================================================================
// Para los admins que atienden más de una instalación (como Manuel con 6),
// esta pantalla muestra en un solo vistazo los números clave de todas:
// guardias en turno, novedades abiertas y críticas, encomiendas en portería,
// paquetes atrasados, autos esperando y accesos del día.
//
// POR QUÉ EXISTE
//
//   Antes, para saber "¿cómo va Encomenderos ahora?" había que cambiar de
//   instalación, mirar el inicio, cambiar a Milagros, etc. Con 6 instalaciones
//   eso son 6 cambios de instalación y 6 pantallas de inicio para empezar el
//   día. Acá se ve todo junto y se baja a la instalación específica solo si
//   hay algo que necesita atención.
//
// INTERACCIÓN
//
//   Tocar una tarjeta → cambia la instalación activa a esa + navega al inicio
//   del admin. Al volver con la flecha, la vista general se refresca sola.
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

class PantallaAdminConsolidado extends ConsumerWidget {
  const PantallaAdminConsolidado({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final datos = ref.watch(resumenDeMisInstalacionesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Vista general'),
        actions: const [MenuDelAdmin()],
      ),
      body: datos.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: Colores.grafito),
        ),
        error: (falla, _) => Padding(
          padding: const EdgeInsets.all(Medidas.margen),
          child: AvisoDeError(
            problema: Traductor.traducir(falla),
            alReintentar: () =>
                ref.invalidate(resumenDeMisInstalacionesProvider),
          ),
        ),
        data: (lista) {
          if (lista.isEmpty) {
            return const ListaVacia(
              icono: Icons.business_rounded,
              titulo: 'Todavía no tenés instalaciones asignadas',
              explicacion:
                  'Pedile al administrador general que te asigne acceso a '
                  'alguna instalación. Mientras tanto no hay nada que mostrar.',
            );
          }

          // Las que tienen cosas urgentes van primero. Dentro de cada grupo,
          // la instalación activa aparece primero (es más probable que el
          // admin la revise sin tocar) y las demás alfabéticas.
          final conPendientes = lista.where((r) => r.hayPendientes).toList()
            ..sort(_porActivaYNombre);
          final tranquilas = lista.where((r) => !r.hayPendientes).toList()
            ..sort(_porActivaYNombre);

          return RefreshIndicator(
            onRefresh: () async =>
                ref.invalidate(resumenDeMisInstalacionesProvider),
            child: ListView(
              padding: const EdgeInsets.all(Medidas.margen),
              children: [
                _ResumenTotal(lista: lista),
                const SizedBox(height: 16),
                if (conPendientes.isNotEmpty) ...[
                  const _TituloSeccion('CON PENDIENTES'),
                  const SizedBox(height: 8),
                  ...conPendientes.map(
                    (r) => _TarjetaInstalacion(resumen: r),
                  ),
                  const SizedBox(height: 16),
                ],
                if (tranquilas.isNotEmpty) ...[
                  const _TituloSeccion('AL DÍA'),
                  const SizedBox(height: 8),
                  ...tranquilas.map(
                    (r) => _TarjetaInstalacion(resumen: r),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  int _porActivaYNombre(ResumenInstalacion a, ResumenInstalacion b) {
    if (a.esLaActiva != b.esLaActiva) {
      return a.esLaActiva ? -1 : 1;
    }
    return a.condominio
        .toLowerCase()
        .compareTo(b.condominio.toLowerCase());
  }
}

// ============================================================================

class _TituloSeccion extends StatelessWidget {
  const _TituloSeccion(this.texto);
  final String texto;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 2),
      child: Text(
        texto,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: Colores.textoSuave,
          letterSpacing: 1.1,
        ),
      ),
    );
  }
}

// ============================================================================

class _ResumenTotal extends StatelessWidget {
  const _ResumenTotal({required this.lista});
  final List<ResumenInstalacion> lista;

  @override
  Widget build(BuildContext context) {
    final totalGuardias =
        lista.fold<int>(0, (t, r) => t + r.guardiasDeTurno);
    final totalCriticas =
        lista.fold<int>(0, (t, r) => t + r.novedadesCriticasAbiertas);
    final totalPaquetesAtrasados =
        lista.fold<int>(0, (t, r) => t + r.paquetesAtrasados);
    final sinGuardia =
        lista.where((r) => r.guardiasDeTurno == 0).length;

    return Card(
      color: Colores.grafito.withValues(alpha: 0.06),
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${lista.length} '
              '${lista.length == 1 ? "instalación" : "instalaciones"}',
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: Colores.grafito,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 16,
              runSpacing: 6,
              children: [
                _ResumenDato(
                  icono: Icons.shield_outlined,
                  color: totalGuardias == 0 ? Colores.rojo : Colores.verde,
                  texto: '$totalGuardias en turno',
                ),
                if (sinGuardia > 0)
                  _ResumenDato(
                    icono: Icons.warning_amber_rounded,
                    color: Colores.rojo,
                    texto:
                        '$sinGuardia sin guardia',
                  ),
                if (totalCriticas > 0)
                  _ResumenDato(
                    icono: Icons.report_gmailerrorred_rounded,
                    color: Colores.rojo,
                    texto: '$totalCriticas críticas',
                  ),
                if (totalPaquetesAtrasados > 0)
                  _ResumenDato(
                    icono: Icons.inventory_2_outlined,
                    color: Colores.naranjaOscuro,
                    texto: '$totalPaquetesAtrasados paquetes atrasados',
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ResumenDato extends StatelessWidget {
  const _ResumenDato({
    required this.icono,
    required this.color,
    required this.texto,
  });
  final IconData icono;
  final Color color;
  final String texto;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icono, size: 15, color: color),
        const SizedBox(width: 4),
        Text(
          texto,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ],
    );
  }
}

// ============================================================================

class _TarjetaInstalacion extends ConsumerWidget {
  const _TarjetaInstalacion({required this.resumen});

  final ResumenInstalacion resumen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final critico = resumen.hayAlgoCritico;
    final sinGuardia = resumen.guardiasDeTurno == 0;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Medidas.redondeo),
        side: critico
            ? const BorderSide(color: Colores.rojo, width: 1.5)
            : BorderSide.none,
      ),
      child: InkWell(
        onTap: () => _entrar(context, ref),
        borderRadius: BorderRadius.circular(Medidas.redondeo),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      resumen.condominio,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  if (resumen.esLaActiva)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colores.verde.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        'ACTIVA',
                        style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w800,
                          color: Colores.verde,
                          letterSpacing: 0.9,
                        ),
                      ),
                    ),
                  const SizedBox(width: 6),
                  const Icon(Icons.chevron_right_rounded,
                      color: Colores.textoTenue),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 14,
                runSpacing: 6,
                children: [
                  _Dato(
                    icono: Icons.shield_outlined,
                    color: sinGuardia ? Colores.rojo : Colores.verde,
                    valor: '${resumen.guardiasDeTurno}',
                    etiqueta: sinGuardia
                        ? (resumen.guardiasDeTurno == 1
                            ? 'guardia'
                            : 'sin guardia')
                        : (resumen.guardiasDeTurno == 1
                            ? 'guardia'
                            : 'guardias'),
                  ),
                  if (resumen.novedadesCriticasAbiertas > 0)
                    _Dato(
                      icono: Icons.report_gmailerrorred_rounded,
                      color: Colores.rojo,
                      valor: '${resumen.novedadesCriticasAbiertas}',
                      etiqueta: resumen.novedadesCriticasAbiertas == 1
                          ? 'crítica'
                          : 'críticas',
                    )
                  else if (resumen.novedadesAbiertas > 0)
                    _Dato(
                      icono: Icons.report_gmailerrorred_outlined,
                      color: Colores.naranjaOscuro,
                      valor: '${resumen.novedadesAbiertas}',
                      etiqueta: resumen.novedadesAbiertas == 1
                          ? 'novedad'
                          : 'novedades',
                    ),
                  if (resumen.paquetesAtrasados > 0)
                    _Dato(
                      icono: Icons.inventory_2_rounded,
                      color: Colores.naranjaOscuro,
                      valor: '${resumen.paquetesAtrasados}',
                      etiqueta: 'paquetes atrasados',
                    )
                  else if (resumen.paquetesEnPorteria > 0)
                    _Dato(
                      icono: Icons.inventory_2_outlined,
                      color: Colores.grafito,
                      valor: '${resumen.paquetesEnPorteria}',
                      etiqueta: resumen.paquetesEnPorteria == 1
                          ? 'paquete'
                          : 'paquetes',
                    ),
                  if (resumen.autosEsperando > 0)
                    _Dato(
                      icono: Icons.directions_car_rounded,
                      color: Colores.rojo,
                      valor: '${resumen.autosEsperando}',
                      etiqueta: resumen.autosEsperando == 1
                          ? 'auto esperando'
                          : 'autos esperando',
                    ),
                  if (resumen.accesosHoy > 0)
                    _Dato(
                      icono: Icons.login_rounded,
                      color: Colores.textoSuave,
                      valor: '${resumen.accesosHoy}',
                      etiqueta: 'accesos hoy',
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _entrar(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final navegador = GoRouter.of(context);

    // Si ya es la activa no hace falta llamar al RPC — ahorra una llamada.
    if (!resumen.esLaActiva) {
      try {
        await ref
            .read(servicioAdminProvider)
            .cambiarDeInstalacion(resumen.condominioId);
        // Invalidamos TODOS los providers que dependen del condominio activo
        // para que la pantalla de inicio del admin ya se abra con los datos
        // de la instalación recién elegida.
        ref.invalidate(perfilProvider);
        ref.invalidate(resumenAdminProvider);
        ref.invalidate(misInstalacionesProvider);
      } catch (falla) {
        messenger.showSnackBar(
          SnackBar(
            content: Text('No se pudo abrir ${resumen.condominio}: '
                '${Traductor.traducir(falla).mensaje}'),
            backgroundColor: Colores.rojo,
          ),
        );
        return;
      }
    }

    // push (no go) para que el admin vuelva con la flecha a la vista
    // general sin perder su scroll.
    navegador.push(Rutas.adminInicio);
  }
}

// Mini-tile con icono + número grande + etiqueta chica, para mostrar un dato
// del condominio en el card. Más compacto que _KpiCard, pensado para que
// quepan varios en una tarjeta sin ocupar media pantalla.
class _Dato extends StatelessWidget {
  const _Dato({
    required this.icono,
    required this.color,
    required this.valor,
    required this.etiqueta,
  });

  final IconData icono;
  final Color color;
  final String valor;
  final String etiqueta;

  @override
  Widget build(BuildContext context) {
    return IntrinsicWidth(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(icono, size: 18, color: color),
          const SizedBox(width: 5),
          RichText(
            text: TextSpan(
              style: const TextStyle(fontSize: 12.5, color: Colores.texto),
              children: [
                TextSpan(
                  text: valor,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
                TextSpan(
                  text: ' $etiqueta',
                  style: const TextStyle(
                    fontSize: 11.5,
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
