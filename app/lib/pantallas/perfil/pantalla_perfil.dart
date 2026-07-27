// ============================================================================
// Tomass Seguridad — Pantalla 09 · Mi perfil e historial
// ============================================================================
// POR QUÉ EL RESIDENTE VE SU PROPIO HISTORIAL
//   Porque resuelve los reclamos sin que la administración tenga que revisar
//   nada. "¿A qué hora entré ayer?" se contesta solo. Y si un día alguien discute
//   que no estaba, el registro está ahí.
//
// QUÉ PUEDE CAMBIAR EL RESIDENTE Y QUÉ NO
//   Puede cambiar su foto y su teléfono. NO puede cambiar su nombre, su cédula ni
//   su unidad: esos son los datos que lo identifican, y si los pudiera editar el
//   registro de accesos dejaría de servir como prueba. Los cambia la
//   administración.
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/tema.dart';
import '../../estado/proveedores.dart';
import '../../modelos/modelos.dart';
import '../../nucleo/almacenamiento_seguro.dart';
import '../../nucleo/errores.dart';
import '../../nucleo/formato.dart';
import '../../servicios/servicio_fotos.dart';
import '../comunes/componentes.dart';

class PantallaPerfil extends ConsumerStatefulWidget {
  const PantallaPerfil({super.key});

  @override
  ConsumerState<PantallaPerfil> createState() => _EstadoPerfil();
}

class _EstadoPerfil extends ConsumerState<PantallaPerfil> {
  bool _biometriaActiva = false;
  bool _biometriaDisponible = false;
  String _nombreBiometria = 'huella digital';
  bool _cambiandoFoto = false;

  @override
  void initState() {
    super.initState();
    _cargarAjustes();
  }

  Future<void> _cargarAjustes() async {
    final sesion = ref.read(servicioSesionProvider);
    final disponible = await sesion.biometriaDisponible();
    final activa = await Preferencias.usaBiometria();
    final nombre = await sesion.nombreDeLaBiometria();
    if (!mounted) return;
    setState(() {
      _biometriaDisponible = disponible;
      _biometriaActiva = activa;
      _nombreBiometria = nombre;
    });
  }

  Future<void> _cambiarBiometria(bool activar) async {
    try {
      await ref.read(servicioSesionProvider).configurarBiometria(activar);
      final quedo = await Preferencias.usaBiometria();
      if (!mounted) return;
      setState(() => _biometriaActiva = quedo);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(quedo
              ? 'Listo. La próxima vez entrás con tu $_nombreBiometria.'
              : 'Desactivado. Vas a tener que escribir tu contraseña.'),
        ),
      );
    } catch (falla) {
      if (!mounted) return;
      final problema = Traductor.traducir(falla);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(problema.mensaje),
          backgroundColor: Colores.rojo,
        ),
      );
    }
  }

  Future<void> _cambiarFoto(Perfil perfil) async {
    setState(() => _cambiandoFoto = true);
    try {
      final foto = await ref.read(servicioFotosProvider).sacarFoto();
      if (foto == null) {
        if (mounted) setState(() => _cambiandoFoto = false);
        return;
      }

      await ref.read(servicioResidenteProvider).cambiarMiFoto(
            condominioId: perfil.condominioId,
            foto: foto,
            rutaAnterior: perfil.fotoUrl,
          );

      ref.invalidate(perfilProvider);
      if (!mounted) return;
      setState(() => _cambiandoFoto = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cambiamos tu foto.')),
      );
    } catch (falla) {
      if (!mounted) return;
      setState(() => _cambiandoFoto = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(Traductor.traducir(falla).mensaje),
          backgroundColor: Colores.rojo,
        ),
      );
    }
  }

  Future<void> _salir() async {
    final seguro = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Cerrar sesión?'),
        content: const Text(
          'Vas a tener que escribir tu correo y contraseña la próxima vez que '
          'abras la app.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colores.rojo),
            child: const Text('Sí, cerrar sesión'),
          ),
        ],
      ),
    );

    if (seguro != true) return;
    // El vigilante de sesión manda solo al login
    await ref.read(servicioSesionProvider).salir();
  }

  @override
  Widget build(BuildContext context) {
    final perfil = ref.watch(perfilProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Mi perfil')),
      body: perfil.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: Colores.grafito),
        ),
        error: (falla, _) => Padding(
          padding: const EdgeInsets.all(Medidas.margen),
          child: AvisoDeError(
            problema: Traductor.traducir(falla),
            alReintentar: () => ref.invalidate(perfilProvider),
          ),
        ),
        data: (datos) => RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(perfilProvider);
            ref.invalidate(miHistorialProvider);
          },
          child: ListView(
            padding: const EdgeInsets.all(Medidas.margen),
            children: [
              _Ficha(
                perfil: datos,
                cambiandoFoto: _cambiandoFoto,
                alCambiarFoto: () => _cambiarFoto(datos),
              ),

              const SizedBox(height: 22),
              Text('AJUSTES', style: Theme.of(context).textTheme.labelSmall),
              const SizedBox(height: 8),
              Card(
                child: Column(
                  children: [
                    if (_biometriaDisponible)
                      SwitchListTile.adaptive(
                        value: _biometriaActiva,
                        onChanged: _cambiarBiometria,
                        activeThumbColor: Colores.grafito,
                        secondary: const Icon(Icons.fingerprint_rounded),
                        title: Text(
                          'Entrar con $_nombreBiometria',
                          style: const TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        subtitle: const Text(
                          'Más rápido que escribir la contraseña',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: Colores.textoSuave,
                          ),
                        ),
                      )
                    else
                      const ListTile(
                        leading: Icon(Icons.fingerprint_rounded,
                            color: Colores.textoTenue),
                        title: Text(
                          'Entrar con huella o Face ID',
                          style: TextStyle(fontSize: 14.5),
                        ),
                        subtitle: Text(
                          'Este teléfono no lo tiene configurado',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: Colores.textoSuave,
                          ),
                        ),
                        enabled: false,
                      ),
                  ],
                ),
              ),

              const SizedBox(height: 22),
              Row(
                children: [
                  Text('MIS ÚLTIMOS ACCESOS',
                      style: Theme.of(context).textTheme.labelSmall),
                  const Spacer(),
                  Text(
                    'no se pueden borrar',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontStyle: FontStyle.italic,
                      color: Colores.textoTenue,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const _Historial(),

              const SizedBox(height: 26),
              OutlinedButton.icon(
                onPressed: _salir,
                icon: const Icon(Icons.logout_rounded, size: 19),
                label: const Text('Cerrar sesión'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colores.rojo,
                  side: const BorderSide(color: Colores.rojo, width: 1.4),
                ),
              ),
              const SizedBox(height: 14),
              Center(
                child: Text(
                  'Tomass Seguridad · versión 1.0.0',
                  style: TextStyle(fontSize: 11.5, color: Colores.textoTenue),
                ),
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
// La ficha con los datos
// ============================================================================

class _Ficha extends StatelessWidget {
  const _Ficha({
    required this.perfil,
    required this.cambiandoFoto,
    required this.alCambiarFoto,
  });

  final Perfil perfil;
  final bool cambiandoFoto;
  final VoidCallback alCambiarFoto;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Medidas.margen),
        child: Column(
          children: [
            Stack(
              children: [
                if (perfil.fotoUrl != null && perfil.fotoUrl!.isNotEmpty)
                  FotoDelServidor(
                    ruta: perfil.fotoUrl,
                    cajon: CajonDeFotos.personas,
                    ancho: 88,
                    alto: 88,
                    redondeo: 44,
                    iconoSiFalta: Icons.person_rounded,
                  )
                else
                  Avatar(iniciales: perfil.iniciales, tamano: 88),
                Positioned(
                  right: -2,
                  bottom: -2,
                  child: Material(
                    color: Colores.grafito,
                    shape: const CircleBorder(),
                    child: InkWell(
                      onTap: cambiandoFoto ? null : alCambiarFoto,
                      customBorder: const CircleBorder(),
                      child: Padding(
                        padding: const EdgeInsets.all(7),
                        child: cambiandoFoto
                            ? const SizedBox(
                                width: 15,
                                height: 15,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.photo_camera_rounded,
                                size: 15, color: Colors.white),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              perfil.nombreCompleto,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 3),
            Text(
              [
                if (perfil.unidad != null) 'Unidad ${perfil.unidad}',
                if (perfil.relacionUnidad != null)
                  Formato.nombrePropio(perfil.relacionUnidad!),
              ].join(' · '),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 10),
            Etiqueta(
              texto: perfil.estaActivo ? 'Residente activo' : 'Inactivo',
              tono: perfil.estaActivo ? TonoEtiqueta.bueno : TonoEtiqueta.malo,
            ),

            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 12),

            _Fila(
              icono: Icons.badge_outlined,
              etiqueta: 'Cédula',
              valor: perfil.cedula ?? 'No registrada',
            ),
            _Fila(
              icono: Icons.phone_outlined,
              etiqueta: 'Teléfono',
              valor: perfil.telefono ?? 'No registrado',
            ),
            _Fila(
              icono: Icons.mail_outline_rounded,
              etiqueta: 'Correo',
              valor: perfil.email,
            ),
            if (perfil.nombreCondominio != null)
              _Fila(
                icono: Icons.apartment_rounded,
                etiqueta: 'Condominio',
                valor: perfil.nombreCondominio!,
              ),

            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                color: Colores.grafito.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(Medidas.redondeoChico),
              ),
              child: const Text(
                'Tu nombre, cédula y unidad los cambia la administración. Si hay '
                'algo mal, avisales.',
                style: TextStyle(
                  fontSize: 12,
                  height: 1.45,
                  color: Colores.textoSuave,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Fila extends StatelessWidget {
  const _Fila({
    required this.icono,
    required this.etiqueta,
    required this.valor,
  });

  final IconData icono;
  final String etiqueta;
  final String valor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(
        children: [
          Icon(icono, size: 17, color: Colores.textoSuave),
          const SizedBox(width: 11),
          Text(
            etiqueta,
            style: const TextStyle(fontSize: 13, color: Colores.textoSuave),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              valor,
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// El historial de entradas y salidas
// ============================================================================

class _Historial extends ConsumerWidget {
  const _Historial();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historial = ref.watch(miHistorialProvider);

    return historial.when(
      loading: () => const Card(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 34),
          child: Center(
            child: CircularProgressIndicator(color: Colores.grafito),
          ),
        ),
      ),
      error: (falla, _) => AvisoDeError(
        problema: Traductor.traducir(falla),
        alReintentar: () => ref.invalidate(miHistorialProvider),
        compacto: true,
      ),
      data: (lista) {
        if (lista.isEmpty) {
          return const Card(
            child: Padding(
              padding: EdgeInsets.all(Medidas.margen),
              child: Center(
                child: Text(
                  'Todavía no tenés movimientos registrados.\n'
                  'Cuando entres o salgas, van a aparecer acá.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.5,
                    color: Colores.textoSuave,
                  ),
                ),
              ),
            ),
          );
        }

        return Card(
          child: Column(
            children: [
              for (var i = 0; i < lista.length; i++) ...[
                if (i > 0) const Divider(height: 1),
                _FilaHistorial(movimiento: lista[i]),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _FilaHistorial extends StatelessWidget {
  const _FilaHistorial({required this.movimiento});

  final Movimiento movimiento;

  @override
  Widget build(BuildContext context) {
    final m = movimiento;
    final color = m.aprobado
        ? (m.esEntrada ? Colores.verde : Colores.grafito)
        : Colores.rojo;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  m.esVehicular
                      ? Icons.directions_car_rounded
                      : Icons.directions_walk_rounded,
                  size: 17,
                  color: color,
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          m.esEntrada
                              ? Icons.arrow_downward_rounded
                              : Icons.arrow_upward_rounded,
                          size: 13,
                          color: Colores.textoSuave,
                        ),
                        const SizedBox(width: 3),
                        Text(
                          m.descripcion,
                          style: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (m.patente != null) ...[
                          const SizedBox(width: 6),
                          Text(
                            m.patente!,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colores.textoSuave,
                              fontFeatures: [FontFeature.tabularFigures()],
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [
                        Formato.cuandoRelativo(m.ocurridoEn),
                        if (m.puntoAcceso != null) m.puntoAcceso!,
                      ].join(' · '),
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: Colores.textoSuave,
                      ),
                    ),
                  ],
                ),
              ),
              if (!m.aprobado)
                const Etiqueta(texto: 'Denegado', tono: TonoEtiqueta.malo),
              if (m.sincronizadoOffline)
                const Padding(
                  padding: EdgeInsets.only(left: 6),
                  child: Tooltip(
                    message: 'Se registró sin internet y se sincronizó después',
                    child: Icon(Icons.cloud_sync_rounded,
                        size: 14, color: Colores.textoTenue),
                  ),
                ),
            ],
          ),
          if (!m.aprobado && m.motivoDenegacion != null) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                color: Colores.rojo.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                m.motivoDenegacion!,
                style: const TextStyle(
                  fontSize: 12,
                  height: 1.4,
                  color: Colores.rojoOscuro,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
