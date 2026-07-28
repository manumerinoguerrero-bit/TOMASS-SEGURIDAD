// ============================================================================
// Tomass Seguridad — Iniciar y cerrar sesión
// ============================================================================
// Todo lo que tiene que ver con entrar a la app: correo y contraseña, huella
// digital, Face ID, y traer la ficha del residente desde el servidor.
// ============================================================================

import 'package:local_auth/local_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/entorno.dart';
import '../modelos/modelos.dart';
import '../nucleo/almacenamiento_seguro.dart';
import '../nucleo/errores.dart';

class ServicioSesion {
  ServicioSesion(this._supabase);

  final SupabaseClient _supabase;
  final LocalAuthentication _biometria = LocalAuthentication();

  /// La persona que está usando la app ahora, o null si nadie inició sesión.
  User? get usuarioActual => _supabase.auth.currentUser;

  bool get haySesion => _supabase.auth.currentSession != null;

  /// Avisa cada vez que alguien entra o sale, para que la app reaccione sola.
  Stream<AuthState> get cambiosDeSesion => _supabase.auth.onAuthStateChange;

  // --------------------------------------------------------------------------
  // Entrar con correo y contraseña
  // --------------------------------------------------------------------------
  Future<void> entrar({
    required String correo,
    required String contrasena,
  }) async {
    try {
      await _supabase.auth
          .signInWithPassword(
            email: correo.trim().toLowerCase(),
            password: contrasena,
          )
          .timeout(Entorno.esperaMaxima);

      // Se recuerda el correo para no hacerlo escribir de nuevo la próxima vez
      await Preferencias.guardarUltimoCorreo(correo.trim().toLowerCase());
    } catch (falla) {
      throw Traductor.traducir(falla);
    }
  }

  // --------------------------------------------------------------------------
  // Entrar con huella digital o Face ID
  // --------------------------------------------------------------------------
  // CÓMO FUNCIONA DE VERDAD
  //   La huella NO reemplaza la contraseña en el servidor. Lo que hace es
  //   desbloquear la sesión que ya está guardada en la zona blindada del
  //   teléfono. O sea: primero hay que entrar una vez con la contraseña, y desde
  //   ahí en adelante la huella sirve de atajo.
  //
  //   Por eso, si el residente nunca entró en este teléfono, la huella no puede
  //   funcionar y hay que decírselo con claridad.
  // --------------------------------------------------------------------------

  /// ¿Este teléfono tiene lector de huella o Face ID configurado?
  Future<bool> biometriaDisponible() async {
    try {
      final hayHardware = await _biometria.isDeviceSupported();
      if (!hayHardware) return false;
      return await _biometria.canCheckBiometrics;
    } catch (_) {
      // Si la consulta falla, se asume que no hay. Es más seguro así.
      return false;
    }
  }

  /// Cómo llamarle en pantalla según lo que tenga el teléfono.
  Future<String> nombreDeLaBiometria() async {
    try {
      final tipos = await _biometria.getAvailableBiometrics();
      if (tipos.contains(BiometricType.face)) return 'Face ID';
      if (tipos.contains(BiometricType.fingerprint) ||
          tipos.contains(BiometricType.strong)) {
        return 'huella digital';
      }
      return 'biometría';
    } catch (_) {
      return 'biometría';
    }
  }

  /// ¿Se puede ofrecer el ingreso con huella? Hacen falta tres cosas:
  /// que el teléfono lo soporte, que el residente lo haya activado, y que haya
  /// una sesión guardada de una vez anterior.
  Future<bool> puedeEntrarConBiometria() async {
    if (!await biometriaDisponible()) return false;
    if (!await Preferencias.usaBiometria()) return false;
    return haySesion;
  }

  /// Pide la huella y, si la persona es quien dice ser, deja pasar.
  /// Devuelve true si se autorizó.
  Future<bool> entrarConBiometria() async {
    if (!haySesion) {
      throw const ErrorAmigable(
        'Primero tenés que entrar una vez con tu contraseña.',
        detalle: 'Después vas a poder usar la huella en este teléfono.',
        sePuedeReintentar: false,
      );
    }

    try {
      final autorizado = await _biometria.authenticate(
        localizedReason: 'Confirmá tu identidad para entrar a Tomass Seguridad',
        options: const AuthenticationOptions(
          biometricOnly: false, // permite el PIN del teléfono como respaldo
          stickyAuth: true, // no se cancela si la app pasa a segundo plano
          useErrorDialogs: true,
        ),
      );
      return autorizado;
    } on Exception catch (falla) {
      final texto = falla.toString();

      if (texto.contains('NotAvailable') || texto.contains('NotEnrolled')) {
        throw const ErrorAmigable(
          'Este teléfono no tiene huella ni Face ID configurados.',
          detalle: 'Configuralos en los ajustes del teléfono, o entrá con tu contraseña.',
          sePuedeReintentar: false,
        );
      }

      if (texto.contains('LockedOut') || texto.contains('PermanentlyLockedOut')) {
        throw const ErrorAmigable(
          'Demasiados intentos fallidos con la huella.',
          detalle: 'Desbloqueá el teléfono con tu PIN y volvé a intentar.',
          sePuedeReintentar: false,
        );
      }

      throw const ErrorAmigable(
        'No se pudo verificar tu huella.',
        detalle: 'Probá de nuevo o entrá con tu contraseña.',
      );
    }
  }

  /// Activa o desactiva el ingreso con huella para este teléfono.
  Future<void> configurarBiometria(bool activar) async {
    if (activar) {
      if (!await biometriaDisponible()) {
        throw const ErrorAmigable(
          'Este teléfono no tiene huella ni Face ID configurados.',
          detalle: 'Configuralos primero en los ajustes del teléfono.',
          sePuedeReintentar: false,
        );
      }
      // Se pide la huella una vez para confirmar que funciona antes de activarla
      final ok = await entrarConBiometria();
      if (!ok) return;
    }
    await Preferencias.guardarUsaBiometria(activar);
  }

  // --------------------------------------------------------------------------
  // La ficha del residente
  // --------------------------------------------------------------------------
  /// Trae los datos de la persona que inició sesión: nombre, unidad, rol.
  Future<Perfil> traerPerfil() async {
    final usuario = usuarioActual;
    if (usuario == null) {
      throw const ErrorAmigable(
        'No hay ninguna sesión abierta.',
        hayQueIniciarSesion: true,
        sePuedeReintentar: false,
      );
    }

    try {
      final fila = await _supabase
          .from('usuarios')
          .select('''
            id, condominio_id, nombre_completo, cedula, telefono, email,
            foto_url, unidad_id, relacion_unidad, rol, estado,
            unidades!usuarios_unidad_id_fkey ( numero, torre ),
            condominios ( nombre, nombre_corto, tipo )
          ''')
          .eq('id', usuario.id)
          .maybeSingle()
          .timeout(Entorno.esperaMaxima);

      if (fila == null) {
        throw const ErrorAmigable(
          'Tu cuenta todavía no está asociada a ningún condominio.',
          detalle: 'Avisale a la administración para que te dé de alta.',
          sePuedeReintentar: false,
        );
      }

      final perfil = Perfil.desdeMapa(fila);

      if (!perfil.estaActivo) {
        // Se cierra la sesión: si está inactivo no debe quedar dentro de la app
        await salir();
        throw ErrorAmigable(
          perfil.estado == 'suspendido'
              ? 'Tu cuenta está suspendida.'
              : 'Tu cuenta está desactivada.',
          detalle: 'Comunicate con la administración del condominio.',
          sePuedeReintentar: false,
          hayQueIniciarSesion: true,
        );
      }

      return perfil;
    } catch (falla) {
      throw Traductor.traducir(falla);
    }
  }

  // --------------------------------------------------------------------------
  // Salir
  // --------------------------------------------------------------------------
  Future<void> salir() async {
    try {
      await _supabase.auth.signOut();
    } catch (_) {
      // Si el servidor no responde igual hay que salir localmente: la sesión
      // guardada en el teléfono se borra de todas formas.
    } finally {
      await Preferencias.limpiar();
    }
  }

  /// Manda el correo para recuperar la contraseña.
  Future<void> recuperarContrasena(String correo) async {
    try {
      await _supabase.auth
          .resetPasswordForEmail(correo.trim().toLowerCase())
          .timeout(Entorno.esperaMaxima);
    } catch (falla) {
      throw Traductor.traducir(falla);
    }
  }
}
