// ============================================================================
// Tomass Seguridad — Mapas estáticos para los PDFs
// ============================================================================
// Baja una imagen PNG con un mapa con calles y marcadores encima. Se usa
// para dibujar el recorrido de una ronda dentro del informe PDF.
//
// PROVEEDOR: Mapbox Static Images API
//   * Cuota gratuita: 50.000 mapas por mes (plan "Free"). Alcanza y sobra.
//   * Estilo 'mapbox/satellite-streets-v12': imagen satelital con nombres
//     de calles encima. Es lo que Manuel pidió el 10/11/2026 cuando los
//     PDFs anteriores (con Geoapify estilo 'osm-carto') a veces fallaban
//     y quedaban en el "plano abstracto" dibujado a mano.
//   * Requiere access_token público. Se genera gratis en mapbox.com y
//     se pone acá abajo en _accessToken.
//
// FALLBACK
//   Si Mapbox no responde en 8 s o devuelve algo raro, esta clase devuelve
//   null y el generador del PDF cae al esquema dibujado a mano (círculos
//   concéntricos sin fondo). Un mapa faltante no vale romper un informe —
//   el detalle de las rondas en la página siguiente sigue siendo la info
//   que cuenta ante el cliente.
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

  /// Access token público de Mapbox para la cuenta "manuelmerino".
  /// Es un token PÚBLICO (empieza con pk.) — está pensado para viajar al
  /// servidor de Mapbox desde el cliente al pedir cada imagen. No es un
  /// secreto; si en algún momento aparece abuso en el dashboard, se rota
  /// desde mapbox.com → Tokens y se actualiza esta constante.
  static const _mapboxToken =
      'pk.eyJ1IjoibWFudWVsbWVyaW5vIiwiYSI6ImNtd2E1eGlvcjAxdGQyeXEzMDZoZ3BzdmEifQ.TGVydJ8BeiLPK1nD-ARL8w';

  /// Estilo del mapa. `satellite-streets-v12` es la vista "híbrida" de
  /// Mapbox: imagen satelital con nombres de calles encima. Es lo que
  /// Manuel pidió el 10/11/2026 cuando el PDF antiguo salía con círculos
  /// concéntricos sin mapa.
  static const _mapboxStyle = 'mapbox/satellite-streets-v12';

  /// Colores de los markers (hex SIN el "#"). Mapbox Static Images API
  /// acepta hex personalizado en los pines, al contrario de Geoapify
  /// (que terminó restringiendo a nombres predefinidos).
  static const _colorSector = '1c2e5c';         // grafito / azul oscuro
  static const _colorMarcaCerca = '27ae60';     // verde: dentro de tolerancia
  static const _colorMarcaLejos = 'e74c3c';     // rojo: lejos del cartel

  /// Baja un PNG con el mapa centrado en [sectores] y las [marcas] del
  /// guardia superpuestas. Devuelve null si el servicio no responde en 10 s
  /// o si la respuesta no es una imagen válida — el PDF debe seguir
  /// funcionando aún sin mapa, cae al plano abstracto dibujado a mano.
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

    // Overlays de Mapbox Static Images API. Formato general:
    //
    //   pin-s-<letra_o_numero>+<hex>(<lng>,<lat>)
    //
    // Soporta `pin-s` (chico), `pin-m` (mediano), `pin-l` (grande). La
    // "letra_o_numero" acepta 0-99 y a-z. Si Mapbox no reconoce el
    // texto, dibuja el pin vacío — por eso para números > 99 se le
    // pone un pin sin label.
    //
    // Mapbox separa overlays con comas, al contrario de Geoapify que
    // usaba "|".
    final overlays = [
      for (final s in sectores)
        _pinSector(s),
      for (final m in marcas)
        'pin-s+${m.lejos ? _colorMarcaLejos : _colorMarcaCerca}'
            '(${m.lng},${m.lat})',
    ].join(',');

    final url = Uri.parse(
      'https://api.mapbox.com/styles/v1/$_mapboxStyle/static'
      '/$overlays'
      '/${centro.lng},${centro.lat},$zoom'
      '/${ancho}x$alto'
      '?access_token=$_mapboxToken',
    );

    try {
      final resp = await http
          .get(url, headers: {'User-Agent': 'TomassSeguridad/1.0'})
          .timeout(const Duration(seconds: 10));

      if (resp.statusCode != 200) return null;
      final tipo = resp.headers['content-type'] ?? '';
      if (!tipo.startsWith('image/')) return null;
      if (resp.bodyBytes.length < 800) return null;

      return resp.bodyBytes;
    } catch (_) {
      return null;
    }
  }

  /// Arma el string del pin de un sector. Mapbox acepta números 0-99 en
  /// la "label" del pin — si el sector tuviera número mayor (hoy no pasa,
  /// el máximo en producción son los 11 puntos de Encomenderos) le pone
  /// un pin sin label.
  static String _pinSector(SectorMapa s) {
    if (s.numero < 0 || s.numero > 99) {
      return 'pin-l+$_colorSector(${s.lng},${s.lat})';
    }
    return 'pin-l-${s.numero}+$_colorSector(${s.lng},${s.lat})';
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
