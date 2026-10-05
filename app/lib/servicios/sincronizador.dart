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

import 'cola_offline.dart';
import 'servicio_fotos.dart';

class Sincronizador {
  Sincronizador(this._cola, this._supabase, {ServicioFotos? fotos})
      // ignore: prefer_initializing_formals
      : _fotos = fotos;

  final ColaOffline _cola;
  final SupabaseClient _supabase;
  final ServicioFotos? _fotos;

  StreamSubscription<List<ConnectivityResult>>? _subConectividad;
  Timer? _reloj;
  bool _sincronizando = false;

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

  /// Vacía la cola, respetando el orden FIFO. Devuelve cuántas ops logró
  /// enviar en esta pasada.
  Future<int> sincronizarAhora() async {
    if (_sincronizando) return 0;
    _sincronizando = true;
    var enviadas = 0;
    try {
      while (true) {
        final lote = await _cola.pendientes(limite: 20);
        if (lote.isEmpty) break;
        for (final op in lote) {
          try {
            await _procesar(op);
            await _cola.marcarEnviada(op.idDb);
            enviadas++;
          } catch (falla) {
            if (esErrorDeRed(falla)) {
              // Red cortada otra vez: no insistir, dejar en cola y salir.
              return enviadas;
            }
            // Error no-de-red: el backend rechazó algo (RLS, validación,
            // etc). Registramos el intento. Después de 3 intentos lo
            // descartamos para que la cola no quede atascada por una op
            // tóxica (ej: un QR que ya no existe porque el admin lo borró).
            await _cola.marcarIntentoFallido(op.idDb, falla.toString());
            if (op.intentos + 1 >= 3) {
              await _cola.marcarEnviada(op.idDb);
            }
          }
        }
      }
    } finally {
      _sincronizando = false;
    }
    return enviadas;
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
