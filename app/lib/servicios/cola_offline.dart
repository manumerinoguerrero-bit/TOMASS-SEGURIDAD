// ============================================================================
// Tomass Seguridad — Cola de operaciones pendientes de enviar
// ============================================================================
// La garita del condominio Encomenderos y los pasillos de Milagros tienen
// zonas sin señal. El guardia escanea un cartel de ronda, abre la barrera a
// un residente, carga una encomienda y nada de eso llega al servidor hasta
// que vuelve el WiFi. Antes la app simplemente fallaba con "No hay internet"
// y el guardia perdía el registro.
//
// Esta cola persiste las operaciones en SQLite (sqflite) y las reintenta
// cuando vuelve la señal. Es idempotente por `id_local` (UUID generado al
// momento), igual que los RPCs del backend, así que un envío duplicado por
// red flaky no crea dos filas en la BD.
//
// Las operaciones se encolan desde `servicio_guardia.dart` cuando el RPC
// falla por error de red (`SocketException`, timeout, hostname lookup).
// Si el error es de validación (ej: "ese QR no es de esta instalación"),
// no se encola: la app muestra el error como siempre.
// ============================================================================

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class ColaOffline {
  ColaOffline._(this._db);

  final Database _db;

  /// Streams para que la UI pueda escuchar el conteo sin tener que hacer
  /// polling. Cada `encolar` y `marcarEnviada` emite el nuevo total.
  final StreamController<int> _conteoCtrl = StreamController<int>.broadcast();
  Stream<int> get conteoStream => _conteoCtrl.stream;

  // --------------------------------------------------------------------------
  // Inicialización
  // --------------------------------------------------------------------------

  /// Carpeta donde se guardan los archivos (firmas, fotos) que acompañan
  /// a una operación en cola. Vive junto a la BD de sqflite para no sumar
  /// path_provider como dep. Los archivos se borran al enviar la operación
  /// con éxito.
  late final Directory _dirArchivos;

  static Future<ColaOffline> abrir() async {
    // Usamos el directorio nativo de sqflite para no sumar path_provider
    // como dep directa — la BD vive junto al resto de las bases locales
    // que la app pueda usar.
    final dir = await getDatabasesPath();
    final ruta = p.join(dir, 'cola_offline.db');
    final db = await openDatabase(
      ruta,
      version: 2,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE pendientes (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            id_local TEXT NOT NULL UNIQUE,
            tipo TEXT NOT NULL,
            params TEXT NOT NULL,
            archivos TEXT,
            creada_en TEXT NOT NULL,
            intentos INTEGER NOT NULL DEFAULT 0,
            ultimo_error TEXT
          )
        ''');
        await db.execute(
            'CREATE INDEX idx_pendientes_creada ON pendientes(creada_en)');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        // v1 → v2: agregamos la columna 'archivos' para firmas/fotos que
        // acompañan a entregarPaquete y reportarIncidente offline.
        if (oldVersion < 2) {
          await db.execute('ALTER TABLE pendientes ADD COLUMN archivos TEXT');
        }
      },
    );
    final cola = ColaOffline._(db);
    cola._dirArchivos = Directory(p.join(dir, 'cola_offline_blobs'));
    await cola._dirArchivos.create(recursive: true);
    // Emitir el conteo inicial para que la UI arranque con el valor correcto.
    final n = await cola.conteo();
    cola._conteoCtrl.add(n);
    return cola;
  }

  /// Carpeta de archivos adjuntos. La exponemos para que el sincronizador
  /// pueda leer los paths al rehidratar una operación.
  Directory get carpetaArchivos => _dirArchivos;

  Future<void> cerrar() async {
    await _db.close();
    await _conteoCtrl.close();
  }

  // --------------------------------------------------------------------------
  // Operaciones
  // --------------------------------------------------------------------------

  /// Guarda una operación para reintentarla después. Idempotente: si el
  /// mismo `idLocal` ya estaba encolado, no se duplica.
  ///
  /// [tipo] es el nombre del RPC a invocar (ej: 'marcar_punto_control')
  /// cuando no hay archivos, o `custom:<nombre>` cuando el handler del
  /// sincronizador tiene que hacer algo especial (subir archivos a storage
  /// antes de la RPC/insert).
  /// [params] son los parámetros tal como irían a `supabase.rpc(tipo, params:)`.
  /// [archivos] son los archivos locales que acompañan la operación. Se
  /// COPIAN a la carpeta persistente de la cola (sobreviven a reinicios
  /// del celular). La clave es el nombre lógico que el handler usa
  /// (ej: 'firma', 'foto', 'foto_0'). Se borran al enviar con éxito.
  Future<void> encolar({
    required String idLocal,
    required String tipo,
    required Map<String, dynamic> params,
    Map<String, File> archivos = const {},
  }) async {
    final rutasGuardadas = <String, String>{};
    for (final e in archivos.entries) {
      final extension = p.extension(e.value.path);
      final destino = File(p.join(
        _dirArchivos.path,
        '${idLocal}_${e.key}$extension',
      ));
      await e.value.copy(destino.path);
      rutasGuardadas[e.key] = destino.path;
    }

    await _db.insert(
      'pendientes',
      {
        'id_local': idLocal,
        'tipo': tipo,
        'params': jsonEncode(params),
        'archivos': rutasGuardadas.isEmpty ? null : jsonEncode(rutasGuardadas),
        'creada_en': DateTime.now().toUtc().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
    _conteoCtrl.add(await conteo());
  }

  Future<List<OperacionPendiente>> pendientes({int limite = 50}) async {
    final filas = await _db.query(
      'pendientes',
      orderBy: 'creada_en ASC',
      limit: limite,
    );
    return filas.map(OperacionPendiente.desdeFila).toList();
  }

  Future<int> conteo() async {
    final r = await _db.rawQuery('SELECT COUNT(*) AS c FROM pendientes');
    return Sqflite.firstIntValue(r) ?? 0;
  }

  Future<void> marcarEnviada(int idDb) async {
    // Antes de borrar la fila, limpiamos los archivos locales adjuntos.
    // Lo hacemos best-effort: si alguno falla igual seguimos. En peor caso
    // queda un blob huérfano que el OS libera cuando el usuario desinstala.
    final filas = await _db.query(
      'pendientes',
      columns: ['archivos'],
      where: 'id = ?',
      whereArgs: [idDb],
      limit: 1,
    );
    if (filas.isNotEmpty && filas.first['archivos'] != null) {
      final mapa = Map<String, String>.from(
          jsonDecode(filas.first['archivos'] as String) as Map);
      for (final ruta in mapa.values) {
        try {
          final f = File(ruta);
          if (await f.exists()) await f.delete();
        } catch (_) {
          // best-effort
        }
      }
    }
    await _db.delete('pendientes', where: 'id = ?', whereArgs: [idDb]);
    _conteoCtrl.add(await conteo());
  }

  /// Registra un intento fallido. Si pasa cierto tope de intentos el
  /// llamador puede decidir descartarla.
  Future<void> marcarIntentoFallido(int idDb, String error) async {
    await _db.rawUpdate(
      'UPDATE pendientes SET intentos = intentos + 1, ultimo_error = ? WHERE id = ?',
      [error, idDb],
    );
  }

  /// Borra todo (solo para pruebas o para resetear tras un error gordo).
  Future<void> vaciarTodo() async {
    await _db.delete('pendientes');
    _conteoCtrl.add(0);
  }
}

// ============================================================================

class OperacionPendiente {
  const OperacionPendiente({
    required this.idDb,
    required this.idLocal,
    required this.tipo,
    required this.params,
    required this.archivos,
    required this.creadaEn,
    required this.intentos,
    this.ultimoError,
  });

  final int idDb;
  final String idLocal;
  final String tipo;
  final Map<String, dynamic> params;

  /// Archivos locales que acompañan la operación. Clave = nombre lógico
  /// ('firma', 'foto', 'foto_0'…); valor = path persistente dentro de
  /// `ColaOffline.carpetaArchivos`. Vacío si la operación no tiene adjuntos.
  final Map<String, String> archivos;

  final DateTime creadaEn;
  final int intentos;
  final String? ultimoError;

  factory OperacionPendiente.desdeFila(Map<String, Object?> f) {
    final archivosRaw = f['archivos'] as String?;
    return OperacionPendiente(
      idDb: f['id'] as int,
      idLocal: f['id_local'] as String,
      tipo: f['tipo'] as String,
      params:
          Map<String, dynamic>.from(jsonDecode(f['params'] as String) as Map),
      archivos: archivosRaw == null
          ? const {}
          : Map<String, String>.from(jsonDecode(archivosRaw) as Map),
      creadaEn: DateTime.parse(f['creada_en'] as String),
      intentos: (f['intentos'] as int?) ?? 0,
      ultimoError: f['ultimo_error'] as String?,
    );
  }
}

// ============================================================================
// Clasificación de errores
// ============================================================================
// Si el error es de RED (sin internet, timeout, DNS no resuelve), la op se
// encola para reintento. Cualquier otro error (validación, permiso, etc.)
// se propaga normal — no tiene sentido encolar una op que el backend ya
// rechazó por motivos de datos.
// ============================================================================

bool esErrorDeRed(Object falla) {
  if (falla is TimeoutException) return true;
  if (falla is SocketException) return true;
  if (falla is HttpException) return true;
  final s = falla.toString().toLowerCase();
  return s.contains('socketexception') ||
      s.contains('failed host lookup') ||
      s.contains('network is unreachable') ||
      s.contains('connection closed') ||
      s.contains('connection refused') ||
      s.contains('clientexception');
}
