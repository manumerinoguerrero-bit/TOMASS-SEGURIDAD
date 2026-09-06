// ============================================================================
// Tomass Seguridad — Mapas estáticos para los PDFs
// ============================================================================
// Baja una imagen PNG con un mapa con calles y marcadores numerados encima.
// Se usa para dibujar el recorrido de una ronda dentro del informe PDF de
// turnos.
//
// PROVEEDOR: Geoapify (https://www.geoapify.com/)
//   * Cuota gratuita: 3.000 requests por día — sobra de sobra para el uso
//     de la app (un turno son 5-8 mapas en el PDF).
//   * No requiere tarjeta de crédito para el plan gratuito.
//   * Tiles derivados de OpenStreetMap con calles nítidas.
//
// Antes intentamos con staticmap.openstreetmap.de (el servidor público
// gratuito): era inestable, devolvía imágenes blancas seguido y quedaba
// vacío el rectángulo en el PDF. Geoapify es mucho más confiable.
//
// FALLBACK
//   Si Geoapify no responde en 8 s o devuelve algo raro, esta clase
//   devuelve null y el generador del PDF cae al esquema dibujado a mano
//   (rectángulo con puntos GPS sin fondo). Un mapa faltante no vale
//   romper un informe.
// ============================================================================

import 'dart:typed_data';
import 'package:http/http.dart' as http;

class ServicioMapaEstatico {
  const ServicioMapaEstatico();

  /// API key de Geoapify para el proyecto "Tomass seguridad".
  /// Restringida por cuota; no es un secreto (viaja al servidor de Geoapify
  /// desde el celular del admin al generar el PDF). Si algún día se llena la
  /// cuota o alguien la usa de más, se rota en 1 minuto desde el dashboard.
  static const _apiKey = '44dde378496349dda5132e78d3c11869';

  /// Baja un PNG con el mapa centrado en [puntos] y los marcadores numerados.
  /// Devuelve null si el servicio no responde en 8 s o si la respuesta no es
  /// una imagen válida — el PDF debe seguir funcionando.
  static Future<Uint8List?> conRecorrido({
    required List<({double lat, double lng, int numero})> puntos,
    int ancho = 800,
    int alto = 400,
  }) async {
    if (puntos.isEmpty) return null;

    final centro = _centroide(puntos);
    final zoom = _zoomAdecuado(puntos);

    // Marcadores Geoapify: uno por punto, color grafito Tomass, con el
    // número dentro. Formato:
    //   lonlat:LNG,LAT;color:%23xxxxxx;size:medium;text:N;textsize:small
    final markers = puntos
        .map((p) => 'lonlat:${p.lng},${p.lat};'
            'color:%230D2B5E;'
            'size:medium;'
            'text:${p.numero};'
            'textsize:small')
        .join('|');

    final url = Uri.parse(
      'https://maps.geoapify.com/v1/staticmap'
      '?style=osm-bright'
      '&width=$ancho'
      '&height=$alto'
      '&center=lonlat:${centro.lng},${centro.lat}'
      '&zoom=$zoom'
      '&marker=$markers'
      '&apiKey=$_apiKey',
    );

    try {
      final resp = await http
          .get(url, headers: {'User-Agent': 'TomassSeguridad/1.0'})
          .timeout(const Duration(seconds: 8));

      if (resp.statusCode != 200) return null;
      final tipo = resp.headers['content-type'] ?? '';
      if (!tipo.startsWith('image/')) return null;
      if (resp.bodyBytes.length < 800) return null;

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
