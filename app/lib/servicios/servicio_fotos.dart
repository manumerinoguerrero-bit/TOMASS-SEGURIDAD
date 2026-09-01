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
//   2. Cada foto se comprime SEGÚN PARA QUÉ SIRVE, y eso importa.
//
//      Una foto de celular moderno pesa 4 o 5 MB. Subir eso desde la entrada
//      del condominio con mala señal tarda medio minuto, y guardarla llena el
//      espacio del servidor rapidísimo: con 90 encomiendas por día son 1,3 GB
//      por mes solo en fotos de cajas.
//
//      ⚠️ PERO NO TODAS SE PUEDEN COMPRIMIR IGUAL.
//
//         La foto de la patente NO es para mirarla: la app la LEE para sacar el
//         número solo. Si se le quita detalle, el lector deja de acertar y el
//         guardia tiene que escribir la patente a mano cada vez. Ahí la
//         compresión ahorra unos KB y cuesta el doble de trabajo por auto.
//
//         La foto de una caja, en cambio, solo tiene que mostrar que llegó y en
//         qué estado. Con la mitad de tamaño se ve igual.
//
//      Por eso cada foto declara PARA QUÉ es, y de eso sale cuánto se comprime.
// ============================================================================

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute;
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../nucleo/errores.dart';

enum CajonDeFotos {
  vehiculos,
  paquetes,
  firmas,
  personas,
  guardias;

  String get nombre => name;
}

// ============================================================================
// PARA QUÉ ES ESTA FOTO
// ============================================================================
// De acá sale cuánto se comprime. Los números salieron de mirar qué necesita
// cada caso, no de elegir uno parejo para todos.
// ============================================================================

enum PropositoDeLaFoto {
  /// La patente, para que la APP LA LEA SOLA.
  ///
  /// ⚠️ NO BAJAR ESTOS NÚMEROS. Esta foto no es para mirar: el lector
  ///    automático saca el número de acá. Cada píxel que se le quita es una
  ///    patente que el guardia va a tener que escribir a mano.
  ///
  ///    Pesa unos 350 KB, y son pocas por día: un residente registra su auto
  ///    una vez y listo. No es lo que llena el espacio.
  leerLaPatente(ancho: 1600, calidad: 85),

  /// El paquete en portería. Es la que más se saca y la que más pesa en total.
  ///
  /// Solo tiene que mostrar que el paquete llegó y en qué estado. Para eso
  /// 1280 píxeles alcanzan de sobra: una caja golpeada se ve golpeada igual.
  /// Baja de ~350 KB a ~170 KB, o sea la mitad del espacio del servidor.
  elPaquete(ancho: 1280, calidad: 72),

  /// El auto completo, para reconocerlo después. No se lee nada de acá.
  elVehiculo(ancho: 1280, calidad: 78),

  /// Una persona, un documento o una novedad. Tiene que dejar reconocer una
  /// cara o leer un texto grande, pero no un número chico.
  unaPersona(ancho: 1200, calidad: 75),

  /// La selfie del guardia al iniciar turno. Solo tiene que dejar reconocer
  /// la cara para que el admin vea quién estaba a cargo. No pesa nada porque
  /// se saca una sola vez por turno (una vez al día, no cientos por día como
  /// las de paquetes).
  elGuardiaEnTurno(ancho: 900, calidad: 72);

  const PropositoDeLaFoto({required this.ancho, required this.calidad});

  /// A cuántos píxeles de ancho se achica.
  final double ancho;

  /// De 0 a 100. Más bajo pesa menos y se ve peor.
  final int calidad;
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
  ///
  /// [proposito] decide cuánto se comprime. Ver PropositoDeLaFoto: no es un
  /// detalle, de eso depende que el lector de patentes siga acertando y que el
  /// espacio del servidor no se llene con fotos de cajas.
  Future<File?> sacarFoto({
    PropositoDeLaFoto proposito = PropositoDeLaFoto.unaPersona,
    bool frontal = false,
  }) async {
    try {
      final foto = await _selector.pickImage(
        source: ImageSource.camera,
        // Se comprime acá mismo, antes de que la imagen ocupe memoria
        maxWidth: proposito.ancho,
        imageQuality: proposito.calidad,
        preferredCameraDevice:
            frontal ? CameraDevice.front : CameraDevice.rear,
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
  Future<File?> elegirDeLaGaleria({
    PropositoDeLaFoto proposito = PropositoDeLaFoto.unaPersona,
  }) async {
    try {
      final foto = await _selector.pickImage(
        source: ImageSource.gallery,
        maxWidth: proposito.ancho,
        imageQuality: proposito.calidad,
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

  // --------------------------------------------------------------------------
  // Bajar una foto para meterla en un PDF (el informe de encomiendas)
  // --------------------------------------------------------------------------
  /// Baja los bytes de la foto y los achica, para incrustarla en el informe.
  ///
  /// Devuelve null si la foto ya no existe (por ejemplo, se borró antes de
  /// generar el informe). Un informe con una foto faltante no debe romperse
  /// entero: esa fila queda con el aviso de "sin foto" y el resto sigue.
  Future<Uint8List?> bytesParaPdf(String? ruta, CajonDeFotos cajon) async {
    if (ruta == null || ruta.isEmpty || ruta.startsWith('http')) return null;
    try {
      final original = await _supabase.storage.from(cajon.nombre).download(ruta);
      // compute() lo manda a otro hilo: achicar y recomprimir varias fotos
      // seguidas en el mismo hilo trabaría la pantalla mientras se arma el
      // informe.
      return await compute(_achicarParaElInforme, original);
    } catch (_) {
      return null;
    }
  }
}

/// La achica solo para el informe: ahí no hace falta calidad de foto, alcanza
/// con que se reconozca el paquete. Una foto de portería ya viene a ~170 KB
/// (ver PropositoDeLaFoto); un informe con 50 de esas pesaría varios MB,
/// demasiado para mandar por WhatsApp con mala señal. Achicada así queda en
/// unos 20-30 KB.
///
/// Función de nivel superior (no un método de clase) a propósito: es lo que
/// pide compute() para poder correrla en otro hilo.
Uint8List _achicarParaElInforme(Uint8List original) {
  try {
    final decodificada = img.decodeImage(original);
    if (decodificada == null) return original;
    final chica = img.copyResize(decodificada, width: 480);
    return Uint8List.fromList(img.encodeJpg(chica, quality: 55));
  } catch (_) {
    // Si algo sale mal achicándola, mejor mostrar la original que no mostrar
    // nada.
    return original;
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
