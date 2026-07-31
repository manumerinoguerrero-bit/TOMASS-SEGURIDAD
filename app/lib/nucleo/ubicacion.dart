// ============================================================================
// Tomass Seguridad — Dónde está el teléfono
// ============================================================================
// PARA QUÉ SE USA
//
//   Dos cosas, las dos de las rondas:
//
//     1. El administrador camina hasta un sector y toca "agregar acá". El
//        teléfono guarda esa ubicación como la del cartel.
//
//     2. El guardia escanea un cartel durante la ronda. El teléfono manda dónde
//        estaba, y el servidor compara: si el cartel está a 500 metros de donde
//        se escaneó, la marca queda señalada.
//
//   Eso es lo que separa "tuvo el código" de "estuvo ahí". Sin esto, alguien
//   podría sacarle una foto a los seis carteles el primer día y después
//   escanear las fotos desde la garita sin moverse en toda la noche.
//
// ⚠️ LA REGLA DE ESTE ARCHIVO: NUNCA LANZAR UN ERROR HACIA AFUERA
//
//   El GPS falla todo el tiempo por motivos que no son culpa de nadie: el
//   guardia está en un subterráneo, hay paredes gruesas, el teléfono es viejo,
//   se quedó sin señal, o la persona no dio permiso.
//
//   Si cualquiera de esas cosas impidiera marcar un punto, el guardia no podría
//   registrar una ronda que SÍ hizo. Y un sistema que le impide al guardia
//   hacer su trabajo termina desinstalado.
//
//   Por eso acá, cuando algo falla, se devuelve null y la vida sigue. La marca
//   se anota igual, solo que sin ubicación, y el informe lo muestra como
//   "sin dato" en vez de como "hizo trampa".
// ============================================================================

import 'package:geolocator/geolocator.dart';

/// Dónde está el teléfono, con cuánto error.
class Ubicacion {
  const Ubicacion({
    required this.latitud,
    required this.longitud,
    required this.metrosDeError,
  });

  final double latitud;
  final double longitud;

  /// Cuántos metros de error declara el propio teléfono.
  ///
  /// A cielo abierto suele andar en 5 a 15 metros. Adentro de un edificio
  /// puede irse a 50 o más, y ahí conviene desconfiar del dato.
  final double metrosDeError;

  /// true si la medición es lo bastante buena como para tomarla en serio.
  bool get esConfiable => metrosDeError <= 50;

  /// Para mostrárselo a una persona: "±8 m".
  String get errorEnPalabras => '±${metrosDeError.round()} m';
}

abstract final class Localizador {
  /// Dónde está el teléfono ahora, o null si no se pudo saber.
  ///
  /// Nunca lanza un error. Ver la explicación de arriba.
  static Future<Ubicacion?> donde({
    Duration esperaMaxima = const Duration(seconds: 12),
  }) async {
    try {
      // ¿Está prendida la ubicación del teléfono?
      if (!await Geolocator.isLocationServiceEnabled()) return null;

      var permiso = await Geolocator.checkPermission();
      if (permiso == LocationPermission.denied) {
        permiso = await Geolocator.requestPermission();
      }

      // "deniedForever" significa que la persona dijo que no y marcó
      // "no volver a preguntar". Pedirlo de nuevo no hace nada.
      if (permiso == LocationPermission.denied ||
          permiso == LocationPermission.deniedForever) {
        return null;
      }

      final p = await Geolocator.getCurrentPosition(
        locationSettings: LocationSettings(
          accuracy: LocationAccuracy.high,
          // Sin este tope, en un lugar con mala señal la app se quedaría
          // esperando para siempre con el guardia mirando la pantalla.
          timeLimit: esperaMaxima,
        ),
      );

      return Ubicacion(
        latitud: p.latitude,
        longitud: p.longitude,
        metrosDeError: p.accuracy,
      );
    } catch (_) {
      // A propósito: cualquier falla devuelve null y la app sigue andando.
      return null;
    }
  }

  /// Por qué no se pudo tomar la ubicación, dicho para una persona.
  ///
  /// Solo se usa para explicarle al administrador por qué el botón de "tomar
  /// ubicación acá" no funcionó. Al guardia no se le muestra: a él no le tiene
  /// que importar, su marca se anota igual.
  static Future<String?> porQueNoSePudo() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        return 'La ubicación del teléfono está apagada. Prendela en los '
            'ajustes y volvé a intentar.';
      }

      final permiso = await Geolocator.checkPermission();
      if (permiso == LocationPermission.deniedForever) {
        return 'La app no tiene permiso para usar la ubicación, y el teléfono '
            'no va a volver a preguntar. Andá a los ajustes del teléfono → '
            'Aplicaciones → Tomass Seguridad → Permisos, y activá Ubicación.';
      }
      if (permiso == LocationPermission.denied) {
        return 'Hace falta permiso para usar la ubicación. Cuando el teléfono '
            'pregunte, tocá "Permitir".';
      }

      return 'No se pudo tomar la ubicación. Probá saliendo al aire libre: '
          'bajo techo o entre paredes gruesas el GPS no llega.';
    } catch (_) {
      return 'No se pudo tomar la ubicación.';
    }
  }
}
