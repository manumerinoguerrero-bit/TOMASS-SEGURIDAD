// ============================================================================
// Tomass Seguridad — Mapas estáticos para los PDFs
// ============================================================================
// Baja una imagen PNG con un mapa y unos marcadores encima. Se usa para
// dibujar el recorrido de una ronda dentro del informe PDF de turnos, y
// para pintar el punto de inicio de turno en la tarjeta del guardia.
//
// El servicio es staticmap.openstreetmap.de, gratuito y sin API key. Puede
// tardar o no responder: si eso pasa, esta clase devuelve null y el PDF se
// arma igual, mostrando solo el listado de puntos sin la foto del mapa.
// Un mapa faltante no vale romper un informe.
// ============================================================================

import 'dart:typed_data';
import 'package:http/http.dart' as http;

class ServicioMapaEstatico {
  const ServicioMapaEstatico();

  /// Baja un PNG con [puntos] dibujados encima de un mapa.
  ///
  /// [puntos] es una lista de (latitud, longitud). Se calcula el centro
  /// automáticamente. Devuelve null si el servicio no responde en 6s o si
  /// la respuesta no es una imagen válida — el PDF debe seguir funcionando.
  static Future<Uint8List?> conRecorrido({
    required List<({double lat, double lng, int numero})> puntos,
    int ancho = 600,
    int alto = 400,
  }) async {
    if (puntos.isEmpty) return null;

    final centro = _centroide(puntos);
    final zoom = _zoomAdecuado(puntos);

    final markers = puntos
        .map((p) => '${p.lat},${p.lng},lightblue${p.numero}')
        .join('|');

    // El servicio public de OSM tiene un rate-limit muy bajo pero para el
    // uso ocasional de generar un PDF por vez alcanza.
    final url = Uri.parse(
      'https://staticmap.openstreetmap.de/staticmap.php'
      '?center=${centro.lat},${centro.lng}'
      '&zoom=$zoom'
      '&size=${ancho}x$alto'
      '&maptype=mapnik'
      '&markers=$markers',
    );

    try {
      final resp = await http
          .get(url, headers: {'User-Agent': 'TomassSeguridad/1.0'})
          .timeout(const Duration(seconds: 6));

      // El servidor devuelve HTML de error si algo salió mal; solo aceptamos
      // respuestas de imagen. content-type puede venir como image/png.
      if (resp.statusCode != 200) return null;
      final tipo = resp.headers['content-type'] ?? '';
      if (!tipo.startsWith('image/')) return null;
      if (resp.bodyBytes.length < 500) return null;

      return resp.bodyBytes;
    } catch (_) {
      return null;
    }
  }

  static ({double lat, double lng}) _centroide(
      List<({double lat, double lng, int numero})> puntos) {
    var lat = 0.0, lng = 0.0;
    for (final p in puntos) {
      lat += p.lat;
      lng += p.lng;
    }
    return (lat: lat / puntos.length, lng: lng / puntos.length);
  }

  /// Zoom más ajustado posible para que todos los puntos entren en el marco.
  /// Aproximación: 18 = ~40 m/píxel, cada nivel duplica la escala.
  static int _zoomAdecuado(
      List<({double lat, double lng, int numero})> puntos) {
    if (puntos.length == 1) return 18;
    double minLat = 90, maxLat = -90, minLng = 180, maxLng = -180;
    for (final p in puntos) {
      if (p.lat < minLat) minLat = p.lat;
      if (p.lat > maxLat) maxLat = p.lat;
      if (p.lng < minLng) minLng = p.lng;
      if (p.lng > maxLng) maxLng = p.lng;
    }
    final rangoLat = maxLat - minLat;
    final rangoLng = maxLng - minLng;
    final rango = rangoLat > rangoLng ? rangoLat : rangoLng;
    if (rango < 0.001) return 18;
    if (rango < 0.003) return 17;
    if (rango < 0.008) return 16;
    if (rango < 0.02) return 15;
    if (rango < 0.05) return 14;
    if (rango < 0.1) return 13;
    return 12;
  }
}

