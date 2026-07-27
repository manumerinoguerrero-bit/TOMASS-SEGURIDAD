// ============================================================================
// Tomass Seguridad — Guardado seguro de la sesión
// ============================================================================
// QUÉ PROBLEMA RESUELVE
//
//   Cuando el residente inicia sesión, el teléfono tiene que recordar quién es
//   para no pedirle la contraseña cada vez que abre la app. Ese "recuerdo" es un
//   dato sensible: con él, cualquiera podría hacerse pasar por esa persona.
//
//   Por defecto, la librería de Supabase lo guarda en el almacenamiento común
//   del teléfono, que es texto plano y se puede leer con herramientas comunes en
//   un teléfono desbloqueado o con acceso físico.
//
//   Este archivo cambia eso: lo manda a la ZONA BLINDADA del teléfono —
//   el Keychain en iPhone y el Keystore en Android. Ahí el sistema operativo lo
//   encripta con una llave que está en un chip aparte y no sale nunca.
// ============================================================================

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AlmacenamientoSeguro extends LocalStorage {
  AlmacenamientoSeguro();

  static const _clave = 'tomass_sesion';

  static const _cajaFuerte = FlutterSecureStorage(
    aOptions: AndroidOptions(
      // Pide al sistema Android que use su almacén de llaves encriptado
      encryptedSharedPreferences: true,
    ),
    iOptions: IOSOptions(
      // El dato solo se puede leer cuando el teléfono está desbloqueado, y no
      // se copia a iCloud ni a un teléfono nuevo al restaurar un respaldo.
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );

  @override
  Future<void> initialize() async {
    // La zona blindada no necesita preparación previa.
  }

  @override
  Future<String?> accessToken() => _cajaFuerte.read(key: _clave);

  @override
  Future<bool> hasAccessToken() => _cajaFuerte.containsKey(key: _clave);

  @override
  Future<void> persistSession(String sesion) =>
      _cajaFuerte.write(key: _clave, value: sesion);

  @override
  Future<void> removePersistedSession() => _cajaFuerte.delete(key: _clave);
}

// ============================================================================
// Preferencias del usuario que NO son secretas
// ============================================================================
// Cosas como "este residente activó el ingreso con huella". No son sensibles,
// pero se guardan en la misma caja fuerte porque ya está configurada y así no
// hay que sumar otra librería.
// ============================================================================

class Preferencias {
  const Preferencias._();

  static const _cajaFuerte = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static const _claveBiometria = 'tomass_usar_biometria';
  static const _claveCorreo = 'tomass_ultimo_correo';

  /// ¿El residente eligió entrar con huella o Face ID?
  static Future<bool> usaBiometria() async {
    return await _cajaFuerte.read(key: _claveBiometria) == 'si';
  }

  static Future<void> guardarUsaBiometria(bool usar) {
    return _cajaFuerte.write(key: _claveBiometria, value: usar ? 'si' : 'no');
  }

  /// El último correo con el que se inició sesión, para no hacerlo escribir
  /// de nuevo. No es un dato secreto.
  static Future<String?> ultimoCorreo() => _cajaFuerte.read(key: _claveCorreo);

  static Future<void> guardarUltimoCorreo(String correo) {
    return _cajaFuerte.write(key: _claveCorreo, value: correo);
  }

  static Future<void> limpiar() async {
    await _cajaFuerte.delete(key: _claveBiometria);
  }
}
