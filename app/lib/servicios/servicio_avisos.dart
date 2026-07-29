// ============================================================================
// Tomass Seguridad — Los avisos que hacen sonar el celular
// ============================================================================
// QUÉ RESUELVE
//
//   Hasta ahora los avisos llegaban al instante SI el guardia tenía la app
//   abierta. Eso alcanza para la garita, donde la tablet está prendida todo el
//   turno. Pero no alcanza para el residente, que tiene el teléfono en el
//   bolsillo: si llega una visita y él no está mirando la app, no se entera.
//
//   Este archivo consigue el permiso del teléfono, le pide a Google un
//   "número de teléfono" para esa app en ese aparato, y lo guarda en el
//   servidor. Con eso el servidor le puede hacer sonar el celular aunque la app
//   esté cerrada.
//
// ⚠️ LA REGLA MÁS IMPORTANTE DE ESTE ARCHIVO
//
//   NADA DE ACÁ PUEDE ROMPER LA APP. Nunca.
//
//   Un sistema de control de acceso que se cae porque falló una notificación es
//   un sistema roto. Si Firebase no está configurado, si Google no responde, si
//   el residente no dio permiso, si el teléfono es viejo: la app tiene que
//   seguir funcionando igual, y el acceso se registra igual.
//
//   Por eso cada función de acá está envuelta en una red de seguridad y jamás
//   deja escapar un error hacia afuera. Lo peor que puede pasar es que el
//   teléfono no suene, y en ese caso el aviso igual queda guardado y la app lo
//   muestra sola cuando está abierta.
//
// LOS DOS CAMINOS DEL AVISO
//
//   Camino 1 (ya funcionaba): el aviso se guarda en la base de datos y la app,
//            si está abierta, se actualiza sola en menos de un segundo.
//   Camino 2 (esto): el teléfono suena aunque la app esté cerrada.
//
//   El servidor manda por los dos caminos siempre. Están en la función del
//   servidor supabase/functions/_compartido/avisos.ts.
// ============================================================================

import 'dart:async';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Qué pasó al intentar preparar los avisos. Sirve para mostrarle al usuario,
/// en la pantalla de perfil, por qué no le suena el teléfono.
enum EstadoAvisos {
  /// Todo listo: el teléfono va a sonar.
  andando,

  /// Firebase todavía no está configurado en el proyecto. No es un error del
  /// usuario: falta el paso que hace el administrador una sola vez.
  sinConfigurar,

  /// La persona dijo que no cuando el teléfono le pidió permiso.
  sinPermiso,

  /// Algo falló. El detalle queda en el registro.
  conProblema,
}

class ServicioAvisos {
  ServicioAvisos(this._supabase);

  final SupabaseClient _supabase;

  EstadoAvisos _estado = EstadoAvisos.sinConfigurar;
  EstadoAvisos get estado => _estado;

  StreamSubscription<String>? _escuchaDeCambioDeToken;

  // ==========================================================================
  // PASO 1 · PRENDER FIREBASE
  // ==========================================================================

  /// Si Firebase arrancó bien.
  ///
  /// Es un dato de TODA LA APP y no de cada copia de esta clase, porque
  /// Firebase se prende una sola vez por app. Si fuera de cada copia, la que se
  /// crea al cerrar sesión nacería creyendo que Firebase no está listo y no
  /// daría de baja el teléfono.
  static bool _firebaseListo = false;

  /// Prende Firebase. Se llama una sola vez, al arrancar la app.
  ///
  /// Si Firebase no está configurado todavía, no pasa nada malo: se anota y la
  /// app sigue. Es lo que ocurre hoy, antes de que el administrador cree la
  /// cuenta de Firebase.
  static Future<void> prenderFirebase() async {
    try {
      await Firebase.initializeApp();
      _firebaseListo = true;
    } catch (falla) {
      // El caso normal por ahora: falta el archivo de configuración de Google.
      _firebaseListo = false;
      if (kDebugMode) {
        debugPrint('[avisos] Firebase todavía no está configurado. Los avisos '
            'en vivo funcionan igual; lo que falta es que el teléfono suene '
            'con la app cerrada. Detalle: $falla');
      }
    }
  }

  // ==========================================================================
  // PASO 2 · PEDIR PERMISO Y GUARDAR EL TELÉFONO
  // ==========================================================================

  /// Pide permiso para avisar y anota este teléfono en el servidor.
  ///
  /// Se llama DESPUÉS de que la persona entró, porque el aviso hay que
  /// guardarlo a nombre de alguien.
  Future<EstadoAvisos> registrarEsteTelefono() async {
    if (!_firebaseListo) return _estado = EstadoAvisos.sinConfigurar;

    final usuario = _supabase.auth.currentUser;
    if (usuario == null) return _estado = EstadoAvisos.conProblema;

    try {
      final mensajeria = FirebaseMessaging.instance;

      // El teléfono le pregunta a la persona. En Android hasta la versión 12
      // el permiso venía dado; de la 13 en adelante hay que pedirlo.
      final permiso = await mensajeria.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      if (permiso.authorizationStatus == AuthorizationStatus.denied) {
        _anotar('La persona no dio permiso para los avisos.');
        return _estado = EstadoAvisos.sinPermiso;
      }

      final token = await mensajeria.getToken();
      if (token == null) {
        _anotar('Google no entregó el identificador del teléfono.');
        return _estado = EstadoAvisos.conProblema;
      }

      await _guardarEnElServidor(token: token, usuarioId: usuario.id);

      // Google cambia ese identificador de vez en cuando (al reinstalar la app,
      // al restaurar el teléfono desde una copia). Si no se vuelve a guardar,
      // los avisos dejan de llegar en silencio y nadie se entera.
      await _escuchaDeCambioDeToken?.cancel();
      _escuchaDeCambioDeToken = mensajeria.onTokenRefresh.listen(
        (nuevo) => _guardarEnElServidor(token: nuevo, usuarioId: usuario.id),
        onError: (Object falla) => _anotar('Falló el cambio de token: $falla'),
      );

      return _estado = EstadoAvisos.andando;
    } catch (falla) {
      _anotar('No se pudo preparar los avisos: $falla');
      return _estado = EstadoAvisos.conProblema;
    }
  }

  /// Guarda o actualiza este teléfono en la tabla de dispositivos.
  ///
  /// Usa la huella del aparato como clave: así, si la misma persona reinstala
  /// la app, se actualiza la fila que ya existía en vez de crear una nueva. Sin
  /// eso, el servidor le mandaría el mismo aviso cinco veces a alguien que
  /// cambió de teléfono varias veces.
  Future<void> _guardarEnElServidor({
    required String token,
    required String usuarioId,
  }) async {
    try {
      final perfil = await _supabase
          .from('usuarios')
          .select('condominio_id')
          .eq('id', usuarioId)
          .maybeSingle();

      final condominioId = perfil?['condominio_id'] as String?;
      if (condominioId == null) {
        _anotar('El usuario todavía no tiene instalación asignada.');
        return;
      }

      final aparato = await _describirElAparato();

      await _supabase.from('dispositivos').upsert({
        'usuario_id': usuarioId,
        'condominio_id': condominioId,
        'token_fcm': token,
        'plataforma': Platform.isIOS ? 'ios' : 'android',
        'modelo': aparato.modelo,
        'huella_dispositivo': aparato.huella,
        'ultimo_uso': DateTime.now().toIso8601String(),
        'activo': true,
        // Si el aparato estaba dado de baja y la persona volvió a instalar la
        // app, se limpia la baja: el teléfono está vivo otra vez.
        'revocado_en': null,
        'motivo_revocacion': null,
      }, onConflict: 'usuario_id,huella_dispositivo');
    } catch (falla) {
      _anotar('No se pudo guardar el teléfono: $falla');
    }
  }

  // ==========================================================================
  // PASO 3 · APAGAR AL CERRAR SESIÓN
  // ==========================================================================

  /// Da de baja este teléfono cuando alguien cierra sesión.
  ///
  /// Es importante en la garita: el guardia del día cierra sesión y entra el de
  /// la noche EN EL MISMO TELÉFONO. Si no se diera de baja, los avisos del
  /// turno de noche le seguirían sonando al guardia del día, que está en su
  /// casa.
  Future<void> darDeBajaEsteTelefono() async {
    await _escuchaDeCambioDeToken?.cancel();
    _escuchaDeCambioDeToken = null;

    final usuario = _supabase.auth.currentUser;
    if (usuario == null || !_firebaseListo) return;

    try {
      final aparato = await _describirElAparato();
      await _supabase
          .from('dispositivos')
          .update({
            'activo': false,
            'revocado_en': DateTime.now().toIso8601String(),
            'motivo_revocacion': 'La persona cerró sesión en este teléfono.',
          })
          .eq('usuario_id', usuario.id)
          .eq('huella_dispositivo', aparato.huella);
    } catch (falla) {
      // Que no se pueda dar de baja no puede impedir cerrar sesión.
      _anotar('No se pudo dar de baja el teléfono: $falla');
    }
  }

  // ==========================================================================
  // LA HUELLA DEL APARATO
  // ==========================================================================

  Future<_Aparato> _describirElAparato() async {
    try {
      final info = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final a = await info.androidInfo;
        return _Aparato(
          // El id de Android cambia si se restaura el teléfono de fábrica, que
          // es exactamente cuando queremos tratarlo como un aparato nuevo.
          huella: a.id,
          modelo: '${a.manufacturer} ${a.model}',
        );
      }
      final i = await info.iosInfo;
      return _Aparato(
        huella: i.identifierForVendor ?? 'iphone-sin-identificador',
        modelo: i.utsname.machine,
      );
    } catch (_) {
      // Si no se puede saber qué aparato es, igual hay que poder guardar algo:
      // la columna no acepta vacío.
      return const _Aparato(huella: 'aparato-desconocido', modelo: 'desconocido');
    }
  }

  void _anotar(String mensaje) {
    if (kDebugMode) debugPrint('[avisos] $mensaje');
  }
}

class _Aparato {
  const _Aparato({required this.huella, required this.modelo});
  final String huella;
  final String modelo;
}
