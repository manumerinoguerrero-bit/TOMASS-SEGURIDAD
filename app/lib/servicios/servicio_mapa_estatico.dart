// ============================================================================
// Tomass Seguridad — Mapas estáticos para los PDFs
// ============================================================================
// Baja una imagen PNG con un mapa con calles y marcadores encima. Se usa
// para dibujar el recorrido de una ronda dentro del informe PDF.
//
// PROVEEDOR: Geoapify (https://www.geoapify.com/)
//   * Cuota gratuita: 3.000 requests por día — sobra de sobra para el uso
//     de la app (un informe son 1-2 mapas).
//   * No requiere tarjeta de crédito para el plan gratuito.
//   * Tiles derivados de OpenStreetMap con calles nítidas. Se usa
//     el estilo 'osm-carto' porque es EL MISMO render (OSM Carto
//     Standard) que sirve tile.openstreetmap.org, y ese es justo el
//     tileset que muestra el Mapa en Vivo del admin. Así el mapa
//     del PDF queda visualmente idéntico al que ve el admin dentro
//     de la app.
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

/// Un sector para pintar en el mapa: cartel con número y su radio de
/// tolerancia en metros.
class SectorMapa {
  const SectorMapa({
    required this.lat,
    required this.lng,
    required this.numero,
    required this.toleranciaMetros,
  });

  final double lat;
  final double lng;
  final int numero;
  final int toleranciaMetros;
}

/// Una marcación del guardia para pintar en el mapa. Verde si estuvo cerca
/// (dentro de la tolerancia), roja si estuvo lejos.
class MarcaMapa {
  const MarcaMapa({
    required this.lat,
    required this.lng,
    required this.lejos,
  });

  final double lat;
  final double lng;
  final bool lejos;
}

class ServicioMapaEstatico {
  const ServicioMapaEstatico();

  /// API key de Geoapify para el proyecto "Tomass seguridad".
  /// Restringida por cuota; no es un secreto (viaja al servidor de Geoapify
  /// desde el celular del admin al generar el PDF). Si algún día se llena la
  /// cuota o alguien la usa de más, se rota en 1 minuto desde el dashboard.
  static const _apiKey = '44dde378496349dda5132e78d3c11869';

  /// Colores de los markers. Geoapify dejó de aceptar hex en el parámetro
  /// `color:` de los markers (`type:material` y `type:circle`) y ahora solo
  /// acepta nombres predefinidos — el 02/10/2026 el informe PDF empezó a
  /// caer al plano abstracto porque la API devolvía HTTP 400
  /// ("marker[0][2] does not match any of the allowed types").
  /// Pasamos a nombres equivalentes del grafito/verde/rojo que teníamos.
  static const _colorSector = 'navy';         // grafito / azul oscuro
  static const _colorMarcaCerca = 'green';    // marca dentro de tolerancia
  static const _colorMarcaLejos = 'red';      // marca lejos del cartel

  /// Baja un PNG con el mapa centrado en [sectores] y las [marcas] del
  /// guardia superpuestas. Devuelve null si el servicio no responde en 8 s
  /// o si la respuesta no es una imagen válida — el PDF debe seguir
  /// funcionando aún sin mapa.
  ///
  /// El zoom se calcula para que TODO entre en el marco (sectores + marcas).
  static Future<Uint8List?> conRecorrido({
    required List<SectorMapa> sectores,
    List<MarcaMapa> marcas = const [],
    int ancho = 900,
    int alto = 550,
  }) async {
    if (sectores.isEmpty) return null;

    final centro = _centroide(sectores, marcas);
    final zoom = _zoomAdecuado(sectores, marcas);

    // Marcadores Geoapify. Dos formatos distintos:
    //   * Sectores → pin material grafito con el NÚMERO adentro. Se usa
    //     `text:N` sin `icon`: Geoapify pone el texto centrado en el pin.
    //     Antes había `icon:map-marker` (que es un nombre FontAwesome) y
    //     `whitecircle:no`; esa combinación devolvía 400 y el PDF caía al
    //     plano abstracto.
    //   * Marcas del guardia → `type:circle` (nativo de Geoapify): un
    //     punto redondo verde o rojo, sin pin ni sombra. Es exactamente
    //     lo que se quería y no requiere ícono.
    final marcadores = [
      for (final s in sectores)
        'lonlat:${s.lng},${s.lat};'
            'type:material;'
            'color:$_colorSector;'
            'size:medium;'
            'text:${s.numero};'
            'textsize:medium',
      for (final m in marcas)
        'lonlat:${m.lng},${m.lat};'
            'type:circle;'
            'color:${m.lejos ? _colorMarcaLejos : _colorMarcaCerca};'
            'size:small',
    ].join('|');

    final url = Uri.parse(
      'https://maps.geoapify.com/v1/staticmap'
      '?style=osm-carto'
      '&width=$ancho'
      '&height=$alto'
      '&center=lonlat:${centro.lng},${centro.lat}'
      '&zoom=$zoom'
      '&marker=$marcadores'
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
    List<SectorMapa> sectores,
    List<MarcaMapa> marcas,
  ) {
    var lat = 0.0, lng = 0.0;
    var n = 0;
    for (final s in sectores) {
      lat += s.lat;
      lng += s.lng;
      n++;
    }
    for (final m in marcas) {
      lat += m.lat;
      lng += m.lng;
      n++;
    }
    return (lat: lat / n, lng: lng / n);
  }

  /// Zoom más ajustado posible para que todos los puntos entren en el marco.
  /// Aproximación: 18 = ~40 m/píxel, cada nivel duplica la escala.
  static int _zoomAdecuado(
    List<SectorMapa> sectores,
    List<MarcaMapa> marcas,
  ) {
    if (sectores.length + marcas.length == 1) return 18;
    double minLat = 90, maxLat = -90, minLng = 180, maxLng = -180;
    void expandir(double lat, double lng) {
      if (lat < minLat) minLat = lat;
      if (lat > maxLat) maxLat = lat;
      if (lng < minLng) minLng = lng;
      if (lng > maxLng) maxLng = lng;
    }

    for (final s in sectores) {
      expandir(s.lat, s.lng);
    }
    for (final m in marcas) {
      expandir(m.lat, m.lng);
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
