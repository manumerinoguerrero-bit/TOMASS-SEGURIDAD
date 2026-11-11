// ============================================================================
// Tomass Seguridad — Vaciado automático de la cola offline
// ============================================================================
// Escucha dos cosas:
//
//   1. El stream de connectivity_plus: cuando pasa de "sin conexión" a
//      "con conexión", intenta vaciar la cola.
//   2. Un timer de respaldo cada 60s: por si connectivity_plus no detecta
//      bien un cambio puntual (pasa en algunos routers caseros al reconectar).
//
// La sincronización es serial — una op a la vez — para que si el backend
// está empezando a responder después de un corte, no lo saturemos con un
// paquete de 20 requests. Si una op falla por red se corta el loop y se
// reintenta en el próximo tick. Si falla por validación, se descarta tras
// 3 intentos y se guarda el último error para que el admin pueda mirar.
//
// TIPOS DE OPERACIÓN
//
//   Hay dos familias de ops en la cola:
//
//   * RPC GENÉRICA (ej: 'marcar_punto_control', 'registrar_acceso_manual').
//     El sincronizador invoca supabase.rpc(tipo, params) directamente.
//
//   * CUSTOM (prefijo 'custom:', ej: 'custom:entregar_paquete'). Requieren
//     lógica propia porque mezclan subida de archivos a storage + un
//     insert/update. El sincronizador delega a un método específico que
//     rehidrata los archivos desde cola.carpetaArchivos, los sube a storage,
//     y después hace el INSERT/UPDATE con las URLs resultantes.
// ============================================================================

import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../nucleo/errores.dart';
import 'cola_offline.dart';
import 'servicio_fotos.dart';

/// Cómo clasificamos una falla al intentar enviar una operación de la cola.
enum _Falla {
  /// No hay red: no es culpa de la op. Se corta la pasada sin gastar intento.
  red,

  /// La sesión venció o no hay usuario: se corta sin gastar intento; la cola
  /// espera a que su dueño vuelva a entrar.
  sesion,

  /// 5xx, 429 o algo desconocido: puede andar más tarde. Espera creciente.
  transitoria,

  /// El servidor la rechazó por los datos (validación, permiso, restricción).
  /// No tiene sentido reintentarla sola: se aparta para que alguien la mire.
  permanente,

  /// 23505 por id_local: el envío anterior SÍ había llegado. Es un éxito.
  yaEstaba,
}

class Sincronizador {
  Sincronizador(this._cola, this._supabase, {ServicioFotos? fotos})
      // ignore: prefer_initializing_formals
      : _fotos = fotos;

  final ColaOffline _cola;
  final SupabaseClient _supabase;
  final ServicioFotos? _fotos;

  StreamSubscription<List<ConnectivityResult>>? _subConectividad;
  Timer? _reloj;

  /// Una sola pasada a la vez en TODO el proceso, aunque Riverpod recree el
  /// Sincronizador: dos instancias no pueden pisarse (evita doble envío).
  static Future<int>? _pasadaEnCurso;

  /// Tope por operación. Sin esto una llamada colgada deja la cola bloqueada
  /// hasta reiniciar la app.
  static const _esperaPorOperacion = Duration(seconds: 45);

  void arrancar() {
    final c = Connectivity();
    _subConectividad = c.onConnectivityChanged.listen((rs) {
      final hayConexion = rs.any((r) => r != ConnectivityResult.none);
      if (hayConexion) {
        // Pequeño delay para dejar que el stack TCP termine de levantar;
        // sincronizar en el instante del evento a veces falla con
        // "Network is unreachable" aunque el estado ya diga wifi.
        Future<void>.delayed(const Duration(seconds: 2), sincronizarAhora);
      }
    });

    // Latido de respaldo: cada minuto intentamos. Si hay cola llena vacía
    // rápido, si no es un no-op.
    _reloj = Timer.periodic(const Duration(seconds: 60), (_) {
      sincronizarAhora();
    });

    // Un primer intento al arrancar (cubre el caso de que la app abra con
    // red disponible y cola pendiente de un cierre anterior).
    sincronizarAhora();
  }

  Future<void> detener() async {
    await _subConectividad?.cancel();
    _reloj?.cancel();
  }

  /// Vacía la cola del usuario logueado, respetando el orden. Devuelve cuántas
  /// ops logró enviar en esta pasada. Dos llamadas simultáneas comparten la
  /// misma pasada (no se duplican envíos).
  Future<int> sincronizarAhora() {
    return _pasadaEnCurso ??=
        _pasada().whenComplete(() => _pasadaEnCurso = null);
  }

  Future<int> _pasada() async {
    // Sin sesión no se envía NADA y no se gasta ningún intento: la cola
    // espera a que su dueño vuelva a entrar. Así lo del guardia de día no
    // se manda con la sesión del de noche.
    final usuario = _supabase.auth.currentUser;
    if (usuario == null) return 0;

    var enviadas = 0;
    // Foto del momento: cada op se intenta UNA sola vez por pasada.
    final lote = await _cola.pendientes(usuarioId: usuario.id);
    for (final op in lote) {
      // Si cambió la sesión a mitad de la pasada, cortar.
      if (_supabase.auth.currentUser?.id != usuario.id) break;
      try {
        await _procesar(op).timeout(_esperaPorOperacion);
        await _cola.marcarEnviada(op.idDb);
        enviadas++;
      } catch (falla) {
        switch (_clasificar(falla)) {
          case _Falla.yaEstaba:
            // El envío anterior sí había llegado: es un éxito, no un duplicado.
            await _cola.marcarEnviada(op.idDb);
            enviadas++;
          case _Falla.red:
          case _Falla.sesion:
            // No es culpa de la op. Se corta la pasada para respetar el orden
            // y NO se cuenta como intento.
            return enviadas;
          case _Falla.transitoria:
            // Puede andar más tarde: espera creciente y se corta la pasada
            // para no adelantar ops que dependan de esta.
            await _cola.programarReintento(
                op.idDb, falla.toString(), op.intentos);
            return enviadas;
          case _Falla.permanente:
            // El servidor la rechazó por los datos. Se aparta (NO se borra)
            // y se sigue con las demás.
            await _cola.marcarRechazada(op.idDb, falla.toString());
        }
      }
    }
    return enviadas;
  }

  /// Decide qué hacer con una falla al enviar una operación encolada.
  _Falla _clasificar(Object falla) {
    if (esErrorDeRed(falla)) return _Falla.red;
    if (falla is ErrorAmigable && falla.hayQueIniciarSesion) {
      return _Falla.sesion;
    }
    if (falla is AuthException) return _Falla.sesion;
    if (falla is PostgrestException) {
      final c = falla.code ?? '';
      if (c == 'PGRST301' || c == '401') return _Falla.sesion;
      if (c == '23505') return _Falla.yaEstaba;
      // 22xxx dato mal formado · 23xxx restricción · 42501 permiso/validación
      // propia · P0001 raise_exception · P0002 no_data_found · PGRST1xx/2xx
      // problemas de forma de la petición. Todo eso no mejora reintentando.
      if (c.startsWith('22') ||
          c.startsWith('23') ||
          c == '42501' ||
          c == 'P0001' ||
          c == 'P0002' ||
          c.startsWith('PGRST1') ||
          c.startsWith('PGRST2')) {
        return _Falla.permanente;
      }
      return _Falla.transitoria;
    }
    if (falla is ErrorAmigable && !falla.sePuedeReintentar) {
      return _Falla.permanente;
    }
    // Un StateError es un bug nuestro (ej: falta ServicioFotos): no se arregla
    // reintentando a ciegas, mejor apartarla y que se vea.
    if (falla is StateError) return _Falla.permanente;
    return _Falla.transitoria;
  }

  /// Despacha la operación según su tipo. Las RPC genéricas van directo a
  /// supabase.rpc; las `custom:` tienen handler propio que incluye subida
  /// de archivos a storage antes del INSERT/UPDATE.
  Future<void> _procesar(OperacionPendiente op) async {
    switch (op.tipo) {
      case 'custom:entregar_paquete':
        await _enviarEntregarPaquete(op);
      case 'custom:reportar_incidente':
        await _enviarReportarIncidente(op);
      default:
        // RPC genérico (marcar_punto_control, registrar_acceso_manual, …).
        await _supabase.rpc(op.tipo, params: op.params);
    }
  }

  // --------------------------------------------------------------------------
  // Handler: custom:entregar_paquete
  // --------------------------------------------------------------------------

  Future<void> _enviarEntregarPaquete(OperacionPendiente op) async {
    final fotos = _fotos;
    if (fotos == null) {
      throw StateError(
          'Sincronizador sin ServicioFotos: no puede subir firma/foto.');
    }

    final condominioId = op.params['condominioId'] as String;
    final paqueteId = op.params['paqueteId'] as String;

    // Sube la firma (obligatoria) y la foto (opcional) a storage.
    final firmaLocal = op.archivos['firma'];
    if (firmaLocal == null) {
      throw StateError('Falta la firma local para la entrega encolada.');
    }
    final rutaFirma = await fotos.subir(
      archivo: File(firmaLocal),
      cajon: CajonDeFotos.firmas,
      condominioId: condominioId,
      nombreDescriptivo: 'firma',
    );

    String? rutaFoto;
    final fotoLocal = op.archivos['foto'];
    if (fotoLocal != null) {
      rutaFoto = await fotos.subir(
        archivo: File(fotoLocal),
        cajon: CajonDeFotos.paquetes,
        condominioId: condominioId,
        nombreDescriptivo: 'entrega',
      );
    }

    final datos = <String, dynamic>{
      'estado': 'entregado',
      'entregado_en': op.params['entregadoEn'] as String,
      'guardia_entrega_id': op.params['guardiaEntregaId'] as String,
      if (op.params['turnoId'] != null) 'turno_entrega_id': op.params['turnoId'],
      'firma_url': rutaFirma,
      if (rutaFoto != null) 'foto_entrega_url': rutaFoto,
      'identidad_validada': op.params['identidadValidada'] as bool,
      if (op.params['retiradoPor'] != null)
        'retirado_por': op.params['retiradoPor'],
    };

    await _supabase.from('paquetes').update(datos).eq('id', paqueteId);
  }

  // --------------------------------------------------------------------------
  // Handler: custom:reportar_incidente
  // --------------------------------------------------------------------------

  Future<void> _enviarReportarIncidente(OperacionPendiente op) async {
    final fotos = _fotos;
    if (fotos == null) {
      throw StateError(
          'Sincronizador sin ServicioFotos: no puede subir fotos del incidente.');
    }

    final condominioId = op.params['condominioId'] as String;

    // Las fotos vienen con claves 'foto_0', 'foto_1', ... en orden.
    final rutasRemotas = <String>[];
    final claves = op.archivos.keys.toList()..sort();
    for (final clave in claves) {
      final ruta = await fotos.subir(
        archivo: File(op.archivos[clave]!),
        cajon: CajonDeFotos.paquetes,
        condominioId: condominioId,
        nombreDescriptivo: 'incidente',
      );
      rutasRemotas.add(ruta);
    }

    final datos = Map<String, dynamic>.from(op.params);
    datos.remove('condominioId'); // ya está incluido como 'condominio_id'
    datos['fotos'] = rutasRemotas;

    await _supabase.from('incidentes').insert(datos);
  }
}
