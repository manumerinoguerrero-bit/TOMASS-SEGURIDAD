// ============================================================================
// Tomass Seguridad — Fotos
// ============================================================================
// Sube y muestra las fotos del sistema.
//
// DOS COSAS IMPORTANTES DE CÓMO FUNCIONA
//
//   1. En la base de datos NO se guarda un enlace, se guarda una RUTA.
//      Los cajones de fotos son privados, así que un enlace fijo no serviría de
//      nada (y si sirviera, sería un problema de privacidad). Cuando la app va a
//      mostrar una foto, le pide al servidor un enlace temporal de una hora.
//
//   2. Las fotos se comprimen antes de subirlas.
//      Una foto de celular moderno pesa 4 o 5 MB. Subir eso desde la entrada del
//      condominio con mala señal puede tardar medio minuto. Comprimida a 1600
//      píxeles de ancho pesa unos 300 KB y se ve igual de bien para reconocer un
//      auto o una patente.
// ============================================================================

import 'dart:io';

import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../nucleo/errores.dart';

enum CajonDeFotos {
  vehiculos,
  paquetes,
  firmas,
  personas;

  String get nombre => name;
}

class ServicioFotos {
  ServicioFotos(this._supabase);

  final SupabaseClient _supabase;
  final ImagePicker _selector = ImagePicker();

  /// Los enlaces temporales que ya se pidieron, para no pedirlos dos veces
  /// mientras se recorre una lista.
  final Map<String, _EnlaceGuardado> _cache = {};

  static const _duracionEnlace = Duration(hours: 1);

  // --------------------------------------------------------------------------
  // Sacar una foto
  // --------------------------------------------------------------------------
  /// Abre la cámara. Devuelve null si la persona canceló.
  Future<File?> sacarFoto() async {
    try {
      final foto = await _selector.pickImage(
        source: ImageSource.camera,
        // Se comprime acá mismo, antes de que la imagen ocupe memoria
        maxWidth: 1600,
        imageQuality: 82,
        preferredCameraDevice: CameraDevice.rear,
      );
      return foto == null ? null : File(foto.path);
    } catch (falla) {
      final texto = falla.toString();
      if (texto.contains('camera_access_denied')) {
        throw const ErrorAmigable(
          'La app no tiene permiso para usar la cámara.',
          detalle: 'Andá a los ajustes del teléfono, buscá Tomass Seguridad y '
              'activá el permiso de cámara.',
          sePuedeReintentar: false,
        );
      }
      throw const ErrorAmigable('No se pudo abrir la cámara.');
    }
  }

  /// Elige una foto ya guardada en el teléfono.
  Future<File?> elegirDeLaGaleria() async {
    try {
      final foto = await _selector.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1600,
        imageQuality: 82,
      );
      return foto == null ? null : File(foto.path);
    } catch (falla) {
      final texto = falla.toString();
      if (texto.contains('photo_access_denied')) {
        throw const ErrorAmigable(
          'La app no tiene permiso para ver tus fotos.',
          detalle: 'Podés sacar una foto nueva con la cámara en lugar de elegir '
              'una guardada.',
          sePuedeReintentar: false,
        );
      }
      throw const ErrorAmigable('No se pudo abrir la galería de fotos.');
    }
  }

  // --------------------------------------------------------------------------
  // Subir la foto al servidor
  // --------------------------------------------------------------------------
  /// Devuelve la RUTA de la foto, que es lo que se guarda en la base de datos.
  ///
  /// La ruta siempre empieza con el condominio y después el usuario:
  /// eso es lo que hace que un condominio no pueda ver las fotos de otro.
  Future<String> subir({
    required File archivo,
    required CajonDeFotos cajon,
    required String condominioId,
    String? nombreDescriptivo,
  }) async {
    final usuario = _supabase.auth.currentUser;
    if (usuario == null) {
      throw const ErrorAmigable(
        'Se cerró tu sesión.',
        hayQueIniciarSesion: true,
        sePuedeReintentar: false,
      );
    }

    final extension = archivo.path.split('.').last.toLowerCase();
    final marca = DateTime.now().millisecondsSinceEpoch;
    final etiqueta = nombreDescriptivo == null ? '' : '${nombreDescriptivo}_';
    final ruta = '$condominioId/${usuario.id}/$etiqueta$marca.$extension';

    try {
      await _supabase.storage.from(cajon.nombre).upload(
            ruta,
            archivo,
            fileOptions: const FileOptions(upsert: false),
          );
      return ruta;
    } on StorageException catch (falla) {
      // El servidor rechazó el archivo por tamaño o por tipo
      if (falla.statusCode == '413') {
        throw const ErrorAmigable(
          'La foto es demasiado grande.',
          detalle: 'Sacá una foto nueva desde la app en lugar de elegir una '
              'guardada.',
          sePuedeReintentar: false,
        );
      }
      if (falla.message.contains('mime')) {
        throw const ErrorAmigable(
          'Ese tipo de archivo no se acepta.',
          detalle: 'Tiene que ser una foto (JPG o PNG).',
          sePuedeReintentar: false,
        );
      }
      throw Traductor.traducir(falla);
    } catch (falla) {
      throw Traductor.traducir(falla);
    }
  }

  // --------------------------------------------------------------------------
  // Mostrar una foto
  // --------------------------------------------------------------------------
  /// Pide un enlace temporal para ver la foto. Vale una hora.
  /// Devuelve null si la ruta está vacía o si la foto ya no existe.
  Future<String?> enlaceTemporal(String? ruta, CajonDeFotos cajon) async {
    if (ruta == null || ruta.isEmpty) return null;

    // Si la foto se guardó como enlace completo (datos viejos o de prueba),
    // se devuelve tal cual.
    if (ruta.startsWith('http')) return ruta;

    final clave = '${cajon.nombre}/$ruta';
    final guardado = _cache[clave];
    if (guardado != null && !guardado.estaPorVencer) return guardado.enlace;

    try {
      final enlace = await _supabase.storage
          .from(cajon.nombre)
          .createSignedUrl(ruta, _duracionEnlace.inSeconds);

      _cache[clave] = _EnlaceGuardado(
        enlace: enlace,
        vence: DateTime.now().add(_duracionEnlace),
      );
      return enlace;
    } catch (_) {
      // Una foto que falta no debe romper la pantalla: se muestra el marcador
      // gris y el resto de la información igual.
      return null;
    }
  }

  /// Borra una foto que ya no se usa. Si falla, no se avisa: es limpieza.
  Future<void> borrar(String? ruta, CajonDeFotos cajon) async {
    if (ruta == null || ruta.isEmpty || ruta.startsWith('http')) return;
    try {
      await _supabase.storage.from(cajon.nombre).remove([ruta]);
      _cache.remove('${cajon.nombre}/$ruta');
    } catch (_) {
      // Queda un archivo huérfano. No es grave y no vale interrumpir a nadie.
    }
  }
}

class _EnlaceGuardado {
  const _EnlaceGuardado({required this.enlace, required this.vence});

  final String enlace;
  final DateTime vence;

  /// Se renueva 5 minutos antes de vencer, para que nunca se muestre roto.
  bool get estaPorVencer =>
      DateTime.now().isAfter(vence.subtract(const Duration(minutes: 5)));
}
