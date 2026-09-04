// ============================================================================
// Tomass Seguridad — Pantalla 01 · Iniciar sesión
// ============================================================================
// La primera pantalla que ve el residente. Tiene dos caminos:
//
//   Correo y contraseña   → la primera vez, o si cambió de teléfono.
//   Huella o Face ID      → un atajo, para todas las veces siguientes.
//
// SOBRE LA HUELLA, PARA QUE QUEDE CLARO
//   La huella no reemplaza la contraseña en el servidor: lo que hace es
//   desbloquear la sesión que ya está guardada en la zona blindada del teléfono.
//   Por eso solo aparece si el residente ya entró antes en ESTE teléfono.
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

    // ⚠️ NO se dispara huella automáticamente al abrir la pantalla.
    //
    //    Antes se lanzaba solo, con la idea de que era el camino más
    //    rápido. Pero en muchos celulares el prompt del sistema aparece y
    //    se cierra en menos de un segundo (por race con la construcción de
    //    la pantalla), y al usuario le queda solo el login con el correo
    //    prefill y sin poder hacer nada. Peor, si la huella falla dos
    //    veces, Android bloquea el sensor 30 segundos.
    //
    //    Ahora la huella SOLO se dispara cuando el usuario toca el botón
    //    "Ingresar con {nombre}". Es un toque más, pero previsible.
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
      //
      // ⚠️ NO se ofrece acá activar la huella. El vigilante navega al home
      //    apenas detecta sesión válida, y si acá abrimos un diálogo, se
      //    cierra en el aire porque la pantalla ya se está desmontando —
      //    el usuario ve la pantalla del login por medio segundo antes de
      //    llegar al home. Confuso.
      //
      //    La activación de huella vive en la pantalla de perfil, con un
      //    switch, donde el usuario puede prenderla y apagarla cuando
      //    quiera sin sorpresas.
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
      final autorizado = await ref.read(servicioSesionProvider).entrarConBiometria();
      if (!autorizado && mounted) {
        // La persona canceló. No es un error, no hay nada que mostrar.
        setState(() => _cargando = false);
        return;
      }
      // Con la sesión ya válida, el vigilante redirige solo.
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
        statusBarColor: Colores.grafito,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      ),
      child: Scaffold(
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colores.grafito, Colores.grafitoClaro],
            ),
          ),
          child: SafeArea(
            child: LayoutBuilder(
              builder: (context, espacio) => SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 20),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: espacio.maxHeight - 40),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(height: 10),
                      const LogoTomass(tamano: 96),
                      const SizedBox(height: 18),
                      const Text(
                        'Tomass Seguridad',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Seguridad privada · Control de acceso',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: Colors.white.withValues(alpha: 0.65),
                        ),
                      ),
                      const SizedBox(height: 34),

                      if (_problema != null) ...[
                        AvisoDeError(problema: _problema!),
                        const SizedBox(height: 16),
                      ],

                      Form(
                        key: _formulario,
                        child: Column(
                          children: [
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
                            const SizedBox(height: 12),
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
                          ],
                        ),
                      ),

                      const SizedBox(height: 18),

                      ElevatedButton(
                        onPressed: _cargando ? null : _entrarConCorreo,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: Colores.grafito,
                          disabledBackgroundColor:
                              Colors.white.withValues(alpha: 0.5),
                        ),
                        child: _cargando
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.4,
                                  color: Colores.grafito,
                                ),
                              )
                            : const Text('Ingresar'),
                      ),

                      if (_hayBiometria) ...[
                        const SizedBox(height: 10),
                        OutlinedButton.icon(
                          onPressed: _cargando ? null : _entrarConHuella,
                          icon: const Icon(Icons.fingerprint_rounded, size: 22),
                          label: Text('Ingresar con $_nombreBiometria'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: BorderSide(
                              color: Colors.white.withValues(alpha: 0.55),
                              width: 1.5,
                            ),
                          ),
                        ),
                      ],

                      const SizedBox(height: 20),
                      TextButton(
                        onPressed: _cargando ? null : _recuperarContrasena,
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.white.withValues(alpha: 0.8),
                        ),
                        child: const Text('Olvidé mi contraseña'),
                      ),

                      const SizedBox(height: 16),
                      Text(
                        'Si todavía no tenés cuenta, pedísela a la\n'
                        'administración de tu instalación.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.5,
                          color: Colors.white.withValues(alpha: 0.5),
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
