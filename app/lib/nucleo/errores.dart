// ============================================================================
// Tomass Seguridad — Errores explicados en español
// ============================================================================
// QUÉ PROBLEMA RESUELVE
//
//   Cuando algo falla, las librerías devuelven mensajes como
//   "SocketException: Failed host lookup" o "AuthApiException: invalid_grant".
//   Un residente no entiende nada de eso, y peor: no le dice qué hacer.
//
//   Este archivo traduce cada falla a una frase que una persona entiende y que
//   indica el siguiente paso. Es lo que se muestra en la pantalla.
// ============================================================================

import 'dart:async';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

/// Un problema ya traducido, listo para mostrar en pantalla.
class ErrorAmigable implements Exception {
  const ErrorAmigable(
    this.mensaje, {
    this.detalle,
    this.sePuedeReintentar = true,
    this.hayQueIniciarSesion = false,
  });

  /// La frase principal. Corta y clara.
  final String mensaje;

  /// Explicación o siguiente paso, si aporta algo.
  final String? detalle;

  /// Si es true, tiene sentido ofrecer un botón de "intentar de nuevo".
  final bool sePuedeReintentar;

  /// Si es true, hay que mandar a la persona a la pantalla de login.
  final bool hayQueIniciarSesion;

  @override
  String toString() => detalle == null ? mensaje : '$mensaje $detalle';
}

class Traductor {
  const Traductor._();

  /// Convierte cualquier falla en algo que se puede mostrar en pantalla.
  static ErrorAmigable traducir(Object falla) {
    // Ya está traducido
    if (falla is ErrorAmigable) return falla;

    // ---- Problemas de red -------------------------------------------------
    if (falla is SocketException) {
      return const ErrorAmigable(
        'Sin conexión a internet.',
        detalle: 'Revisá el wifi o los datos del celular e intentá de nuevo.',
      );
    }

    if (falla is TimeoutException) {
      return const ErrorAmigable(
        'El servidor no responde.',
        detalle: 'Puede ser tu conexión. Intentá de nuevo en unos segundos.',
      );
    }

    if (falla is HandshakeException || falla is TlsException) {
      return const ErrorAmigable(
        'No se pudo establecer una conexión segura.',
        detalle: 'Si estás en una red pública, probá con los datos del celular.',
      );
    }

    // ---- Problemas de sesión y contraseña ---------------------------------
    if (falla is AuthApiException) {
      return _traducirLogin(falla);
    }

    if (falla is AuthException) {
      return ErrorAmigable(
        'No se pudo iniciar sesión.',
        detalle: falla.message,
      );
    }

    // ---- Respuestas de las funciones del servidor -------------------------
    // Nuestras funciones devuelven un mensaje ya escrito en español dentro de
    // "mensaje". Se usa ese, que es mucho mejor que cualquier traducción.
    if (falla is FunctionException) {
      final cuerpo = falla.details;
      if (cuerpo is Map) {
        final mensaje = cuerpo['mensaje'];
        final detalle = cuerpo['detalle'];
        if (mensaje is String && mensaje.isNotEmpty) {
          return ErrorAmigable(
            mensaje,
            detalle: detalle is String && detalle.isNotEmpty ? detalle : null,
            sePuedeReintentar: falla.status >= 500 || falla.status == 429,
            hayQueIniciarSesion: falla.status == 401,
          );
        }
      }

      if (falla.status == 401) {
        return const ErrorAmigable(
          'Tu sesión venció.',
          detalle: 'Volvé a iniciar sesión.',
          hayQueIniciarSesion: true,
        );
      }

      return const ErrorAmigable(
        'El servidor rechazó la operación.',
        detalle: 'Si vuelve a pasar, avisale a la administración.',
      );
    }

    // ---- Problemas de la base de datos ------------------------------------
    if (falla is PostgrestException) {
      return _traducirBaseDeDatos(falla);
    }

    // ---- Cualquier otra cosa ----------------------------------------------
    return const ErrorAmigable(
      'Algo no funcionó como esperábamos.',
      detalle: 'Intentá de nuevo. Si sigue pasando, avisale a la administración.',
    );
  }

  static ErrorAmigable _traducirLogin(AuthApiException falla) {
    final codigo = falla.code ?? '';
    final texto = falla.message.toLowerCase();

    if (codigo == 'invalid_credentials' ||
        texto.contains('invalid login credentials')) {
      return const ErrorAmigable(
        'El correo o la contraseña no son correctos.',
        detalle: 'Revisá que no tengas activado el bloqueo de mayúsculas.',
      );
    }

    if (codigo == 'email_not_confirmed' || texto.contains('not confirmed')) {
      return const ErrorAmigable(
        'Tu correo todavía no está confirmado.',
        detalle: 'Buscá el mensaje de confirmación en tu correo, o pedile a la '
            'administración que active tu cuenta.',
      );
    }

    if (codigo == 'over_request_rate_limit' || falla.statusCode == '429') {
      return const ErrorAmigable(
        'Demasiados intentos seguidos.',
        detalle: 'Esperá un minuto antes de volver a probar.',
      );
    }

    if (codigo == 'user_not_found' || texto.contains('user not found')) {
      return const ErrorAmigable(
        'No encontramos una cuenta con ese correo.',
        detalle: 'Pedile a la administración que te dé de alta.',
      );
    }

    if (texto.contains('weak password')) {
      return const ErrorAmigable(
        'Esa contraseña es demasiado fácil de adivinar.',
        detalle: 'Usá al menos 8 caracteres, con letras y números.',
      );
    }

    return ErrorAmigable('No se pudo iniciar sesión.', detalle: falla.message);
  }

  static ErrorAmigable _traducirBaseDeDatos(PostgrestException falla) {
    final codigo = falla.code ?? '';

    // Tabla de solo agregar: alguien intentó modificar un registro de acceso
    if (codigo == '23001' || falla.message.contains('solo agregar')) {
      return const ErrorAmigable(
        'Los registros de acceso no se pueden modificar.',
        detalle: 'Es a propósito: así el historial sirve como prueba.',
        sePuedeReintentar: false,
      );
    }

    // Los candados de la base de datos rechazaron la operación
    if (codigo == '42501' || codigo == 'PGRST301' || falla.code == '403') {
      return const ErrorAmigable(
        'No tenés permiso para hacer eso.',
        detalle: 'Si creés que es un error, avisale a la administración.',
        sePuedeReintentar: false,
      );
    }

    // Dato repetido
    if (codigo == '23505') {
      if (falla.message.contains('patente')) {
        return const ErrorAmigable(
          'Esa patente ya está registrada en el condominio.',
          detalle: 'Si es tu auto y no lo ves en tu lista, avisale a la administración.',
          sePuedeReintentar: false,
        );
      }
      return const ErrorAmigable(
        'Ese dato ya estaba registrado.',
        sePuedeReintentar: false,
      );
    }

    // Falta un dato obligatorio
    if (codigo == '23502') {
      return const ErrorAmigable(
        'Falta completar un dato obligatorio.',
        sePuedeReintentar: false,
      );
    }

    // No pasó una validación de la base de datos
    if (codigo == '23514') {
      return const ErrorAmigable(
        'Alguno de los datos no es válido.',
        detalle: 'Revisá el formulario e intentá de nuevo.',
        sePuedeReintentar: false,
      );
    }

    return ErrorAmigable(
      'La base de datos rechazó la operación.',
      detalle: falla.message,
    );
  }
}
