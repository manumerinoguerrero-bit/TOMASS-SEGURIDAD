// ============================================================================
// Tomass Seguridad — Capas de mapa comunes (Esri satelital + calles)
// ============================================================================
// POR QUÉ ESTE ARCHIVO
//
//   La app tiene VARIOS mapas: el recorrido del turno del admin, el mapa en
//   vivo del admin, la pantalla de rondas del guardia y los mapas de PDF.
//   Antes cada uno usaba su propio TileLayer con OpenStreetMap, que a veces
//   tardaba en cargar o quedaba en BLANCO (Manuel lo reportó el 10/11/2026
//   al revisar la ronda que hizo Franco Monroy en Encomenderos).
//
//   Centralizamos acá las capas que todos los mapas de la app deben usar,
//   para que todos se vean igual y arreglar uno = arreglar los tres.
//
// POR QUÉ ESRI
//
//   · Es gratis, sin API key, sin límite diario conocido para uso razonable.
//   · Imágenes satelitales de buena calidad en Chile (incluye La Serena).
//   · Capas separadas de "labels + calles" que se apilan arriba del satélite
//     dan una vista "híbrida" como Google Maps Satélite.
//   · Mucho más estable que tile.openstreetmap.org (que viene fallando con
//     mapas en blanco en varios informes).
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

abstract final class CapasMapa {
  /// User-Agent que mandamos a los tile servers. Es BUENA EDUCACIÓN
  /// identificarnos — y Esri a veces banea requests sin UA.
  static const _userAgent = 'cl.tomass.tomass_seguridad';

  /// La capa satelital sola. Esri World Imagery, imágenes aéreas a color.
  static TileLayer satelital() => TileLayer(
        urlTemplate:
            'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
        userAgentPackageName: _userAgent,
        maxNativeZoom: 19,
      );

  /// La capa SATELITAL con nombres de calles encima. Es lo que todos los
  /// mapas de informe usan por defecto desde el 10/11/2026: Manuel pidió
  /// "satelital con los nombres de las calles" cuando los PDFs de ronda
  /// mostraban OSM y a veces salían en blanco.
  ///
  /// Se apilan 3 capas:
  ///   1. Imagen satelital (de fondo)
  ///   2. Transportation (calles, autopistas)
  ///   3. Boundaries & Places (nombres de calles y localidades)
  ///
  /// Devuelve una LISTA porque FlutterMap necesita children sueltos.
  static List<Widget> satelitalConCalles() => [
        satelital(),
        TileLayer(
          urlTemplate:
              'https://server.arcgisonline.com/ArcGIS/rest/services/Reference/World_Transportation/MapServer/tile/{z}/{y}/{x}',
          userAgentPackageName: _userAgent,
          maxNativeZoom: 19,
        ),
        TileLayer(
          urlTemplate:
              'https://server.arcgisonline.com/ArcGIS/rest/services/Reference/World_Boundaries_and_Places/MapServer/tile/{z}/{y}/{x}',
          userAgentPackageName: _userAgent,
          maxNativeZoom: 19,
        ),
      ];

  /// Mapa de calles solo, estilo cartográfico tradicional de OpenStreetMap.
  /// Se usa cuando el guardia toca el toggle "Calles" para orientarse
  /// mejor por nombres de intersecciones.
  static TileLayer calles() => TileLayer(
        urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
        userAgentPackageName: _userAgent,
        maxNativeZoom: 19,
      );
}
