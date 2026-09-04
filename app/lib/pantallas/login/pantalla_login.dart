// ============================================================================
// Tomass Seguridad — Pantalla 01 · Iniciar sesión
// ============================================================================
// La primera pantalla que ve el usuario. Diseño estilo Merlyn Seguridad:
//
//   - Fondo con gradiente azul marino (oscuro arriba, claro abajo).
//   - Logo grande con halo dorado.
//   - Tarjeta blanca centrada con los campos de correo y contraseña.
//   - Botón "INGRESAR" con gradiente azul + celeste y sombra profunda.
//   - Debajo de la tarjeta: opciones de huella y "olvidé mi contraseña".
//   - Al pie: filete dorado + versión.
//
// SOBRE LA HUELLA
//   La huella no reemplaza la contraseña en el servidor: desbloquea la
//   sesión que ya está guardada en la zona blindada del teléfono. Por eso
//   solo aparece si la persona ya entró antes en ESTE teléfono.
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/tema.dart';
import '../../estado/proveedores.dart';
import '../../nucleo/almacenamiento_seguro.dart';
import '../../nucleo/errores.dart';
import '../comunes/componentes.dart';

class PantallaLogin extends ConsumerStatefulWidget {
  const PantallaLogin({super.key});

  @override
  ConsumerState<PantallaLogin> createState() => _EstadoLogin();
}

class _EstadoLogin extends ConsumerState<PantallaLogin> {
  final _formulario = GlobalKey<FormState>();
  final _correo = TextEditingController();
  final _contrasena = TextEditingController();

  bool _cargando = false;
  bool _mostrarContrasena = false;
  ErrorAmigable? _problema;

  bool _hayBiometria = false;
  String _nombreBiometria = 'huella digital';

  @override
  void initState() {
    super.initState();
    _prepararPantalla();
  }

  @override
  void dispose() {
    _correo.dispose();
    _contrasena.dispose();
    super.dispose();
  }

  Future<void> _prepararPantalla() async {
    final sesion = ref.read(servicioSesionProvider);

    // Se recuerda el correo de la última vez para no hacerlo escribir de nuevo
    final ultimo = await Preferencias.ultimoCorreo();
    final puedeHuella = await sesion.puedeEntrarConBiometria();
    final nombre = await sesion.nombreDeLaBiometria();

    if (!mounted) return;
    setState(() {
      if (ultimo != null) _correo.text = ultimo;
      _hayBiometria = puedeHuella;
      _nombreBiometria = nombre;
    });

    // La huella NO se dispara automáticamente. Ver commit "Fix login: la
    // huella se dispara sola y saca al usuario" para el motivo.
  }

  Future<void> _entrarConCorreo() async {
    if (!_formulario.currentState!.validate()) return;

    FocusScope.of(context).unfocus();
    setState(() {
      _cargando = true;
      _problema = null;
    });

    try {
      await ref.read(servicioSesionProvider).entrar(
            correo: _correo.text,
            contrasena: _contrasena.text,
          );
      // La navegación la maneja sola el vigilante de sesión de rutas.dart.
    } catch (falla) {
      if (!mounted) return;
      setState(() => _problema = Traductor.traducir(falla));
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _entrarConHuella() async {
    setState(() {
      _cargando = true;
      _problema = null;
    });

    try {
      final autorizado =
          await ref.read(servicioSesionProvider).entrarConBiometria();
      if (!autorizado && mounted) {
        setState(() => _cargando = false);
        return;
      }
      if (mounted) ref.invalidate(perfilProvider);
    } catch (falla) {
      if (!mounted) return;
      setState(() => _problema = Traductor.traducir(falla));
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _recuperarContrasena() async {
    final correo = _correo.text.trim();
    if (correo.isEmpty || !correo.contains('@')) {
      setState(() => _problema = const ErrorAmigable(
            'Escribí tu correo primero.',
            detalle: 'Te mandamos un mensaje para crear una contraseña nueva.',
            sePuedeReintentar: false,
          ));
      return;
    }

    setState(() => _cargando = true);
    try {
      await ref.read(servicioSesionProvider).recuperarContrasena(correo);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Te mandamos un correo a $correo para crear una '
              'contraseña nueva.'),
          duration: const Duration(seconds: 6),
        ),
      );
    } catch (falla) {
      if (mounted) setState(() => _problema = Traductor.traducir(falla));
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colores.azulOscuro,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      ),
      child: Scaffold(
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
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                children: [
                  const SizedBox(height: 50),
                  _armarLogo(),
                  const SizedBox(height: 36),
                  _armarTarjeta(),
                  const SizedBox(height: 20),
                  _armarPie(),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _armarLogo() => Column(
        children: [
          Container(
            width: 128,
            height: 128,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colores.dorado.withValues(alpha: 0.42),
                  blurRadius: 32,
                  spreadRadius: 4,
                ),
              ],
            ),
            child: const LogoTomass(tamano: 128),
          ),
          const SizedBox(height: 20),
          const Text(
            'TOMASS SEGURIDAD',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Control de acceso · MMG Seguridad SPA',
            style: TextStyle(
              fontSize: 12,
              color: Colors.white.withValues(alpha: 0.68),
              letterSpacing: 0.9,
            ),
          ),
        ],
      );

  Widget _armarTarjeta() => Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(26),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.28),
              blurRadius: 34,
              offset: const Offset(0, 14),
            ),
          ],
        ),
        padding: const EdgeInsets.all(26),
        child: Form(
          key: _formulario,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Iniciar sesión',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: Colores.grafito,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Ingresá con tus credenciales',
                style: TextStyle(
                  color: Colores.textoSuave,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 24),
              TextFormField(
                controller: _correo,
                enabled: !_cargando,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                autocorrect: false,
                autofillHints: const [AutofillHints.email],
                decoration: const InputDecoration(
                  labelText: 'Correo electrónico',
                  prefixIcon: Icon(Icons.mail_outline_rounded),
                ),
                validator: (valor) {
                  final texto = (valor ?? '').trim();
                  if (texto.isEmpty) return 'Escribí tu correo.';
                  if (!texto.contains('@') || !texto.contains('.')) {
                    return 'Ese correo no parece completo.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _contrasena,
                enabled: !_cargando,
                obscureText: !_mostrarContrasena,
                textInputAction: TextInputAction.done,
                autofillHints: const [AutofillHints.password],
                onFieldSubmitted: (_) => _entrarConCorreo(),
                decoration: InputDecoration(
                  labelText: 'Contraseña',
                  prefixIcon: const Icon(Icons.lock_outline_rounded),
                  suffixIcon: IconButton(
                    icon: Icon(_mostrarContrasena
                        ? Icons.visibility_off_rounded
                        : Icons.visibility_rounded),
                    tooltip: _mostrarContrasena
                        ? 'Ocultar la contraseña'
                        : 'Ver la contraseña',
                    onPressed: () => setState(
                        () => _mostrarContrasena = !_mostrarContrasena),
                  ),
                ),
                validator: (valor) {
                  if ((valor ?? '').isEmpty) {
                    return 'Escribí tu contraseña.';
                  }
                  return null;
                },
              ),
              if (_problema != null) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colores.rojo.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.error_outline_rounded,
                          color: Colores.rojo, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _problema!.mensaje,
                              style: const TextStyle(
                                color: Colores.rojo,
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            if (_problema!.detalle != null) ...[
                              const SizedBox(height: 4),
                              Text(
                                _problema!.detalle!,
                                style: const TextStyle(
                                  color: Colores.rojoOscuro,
                                  fontSize: 12,
                                  height: 1.4,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 24),
              // Botón principal con gradiente y sombra profunda (Merlyn style).
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  gradient: const LinearGradient(
                    colors: [Colores.grafito, Colores.grafitoSuave],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colores.grafito.withValues(alpha: 0.42),
                      blurRadius: 14,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: ElevatedButton(
                  onPressed: _cargando ? null : _entrarConCorreo,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    shadowColor: Colors.transparent,
                    minimumSize: const Size.fromHeight(54),
                    elevation: 0,
                  ),
                  child: _cargando
                      ? const SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2.5),
                        )
                      : const Text(
                          'INGRESAR',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.5,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 14),
              Center(
                child: TextButton(
                  onPressed: _cargando ? null : _recuperarContrasena,
                  child: const Text(
                    'Olvidé mi contraseña',
                    style: TextStyle(fontSize: 13),
                  ),
                ),
              ),
            ],
          ),
        ),
      );

  Widget _armarPie() => Column(
        children: [
          if (_hayBiometria) ...[
            OutlinedButton.icon(
              onPressed: _cargando ? null : _entrarConHuella,
              icon: const Icon(Icons.fingerprint_rounded, size: 22),
              label: Text('Ingresar con $_nombreBiometria'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(50),
                side: BorderSide(
                  color: Colors.white.withValues(alpha: 0.6),
                  width: 1.4,
                ),
              ),
            ),
            const SizedBox(height: 20),
          ],
          Container(
            width: 44,
            height: 2,
            color: Colores.dorado.withValues(alpha: 0.7),
          ),
          const SizedBox(height: 12),
          Text(
            'v1.0 · La Serena · Chile',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.55),
              fontSize: 11,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Si todavía no tenés cuenta, pedísela a la\n'
            'administración de tu instalación.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11,
              height: 1.5,
              color: Colors.white.withValues(alpha: 0.45),
            ),
          ),
        ],
      );
}
