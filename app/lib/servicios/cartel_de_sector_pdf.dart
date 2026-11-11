// ============================================================================
// Tomass Seguridad — El cartel de un sector de ronda, en PDF
// ============================================================================
// PARA QUÉ ES
//
//   Manuel prefiere ir en persona a cada instalación y crear ahí mismo los
//   sectores de ronda (pantalla_admin_sectores.dart ya toma la ubicación real,
//   parado en el lugar). Lo que faltaba era poder imprimir el cartel de cada
//   sector desde el mismo teléfono, sin tener que volver a una computadora.
//
//   Este archivo arma ese cartel como PDF. Quien lo abre desde la app puede
//   mandarlo a una impresora, guardarlo como PDF, o compartirlo por WhatsApp
//   para imprimirlo más tarde: las tres opciones las da el mismo diálogo del
//   sistema operativo (ver Printing.layoutPdf en pantalla_admin_sectores.dart).
//
// MARCAJE POR GPS, NO MÁS QR
//
//   El 11/11/2026 se eliminó el QR del cartel: las rondas se marcan por GPS
//   al acercarse al sector (radio de tolerancia configurable). El cartel
//   ahora identifica el sector solamente y recuerda al guardia que la marca
//   es automática. Los carteles viejos con QR pegados en los sectores pueden
//   seguir ahí mientras tanto — el QR ya no se usa pero no molesta.
// ============================================================================

import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../nucleo/formato.dart';

class _Tinta {
  // Paleta Merlyn: azul marino corporativo.
  static const grafito = PdfColor.fromInt(0xFF0D2B5E);
  static const gris = PdfColor.fromInt(0xFF6B7280);
  static const grisClaro = PdfColor.fromInt(0xFFE5E7EB);
  static const naranja = PdfColor.fromInt(0xFFF39C12);
  static const naranjaFondo = PdfColor.fromInt(0xFFFDF3E7);
  static const blanco = PdfColor.fromInt(0xFFFFFFFF);
}

class CartelDeSectorPdf {
  /// Arma el cartel de un sector, listo para imprimir o guardar.
  ///
  /// [codigoQr] se mantiene en la firma por compatibilidad con los callers,
  /// pero ya no se dibuja en el PDF: las rondas se marcan por GPS.
  static Future<Uint8List> armar({
    required String instalacion,
    required String sector,
    required String codigoQr,
    required bool tieneUbicacion,
    int metrosDeTolerancia = 20,
  }) async {
    final doc = pw.Document(
      title: 'Cartel de sector — $sector',
      author: 'Tomass Seguridad Privada',
    );

    final escudo = await _leerEscudo();

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: pw.EdgeInsets.zero,
        build: (ctx) => pw.Column(
          children: [
            _banda(escudo, instalacion),
            pw.Expanded(
              child: pw.Center(
                child: pw.Column(
                  mainAxisSize: pw.MainAxisSize.min,
                  children: [
                    pw.Text(
                      'PUNTO DE CONTROL DE RONDA',
                      style: const pw.TextStyle(
                          fontSize: 10,
                          letterSpacing: 2,
                          color: _Tinta.gris),
                    ),
                    pw.SizedBox(height: 12),
                    pw.Padding(
                      padding: const pw.EdgeInsets.symmetric(horizontal: 40),
                      child: pw.Text(
                        sector,
                        textAlign: pw.TextAlign.center,
                        style: pw.TextStyle(
                          fontSize: 32,
                          fontWeight: pw.FontWeight.bold,
                          color: _Tinta.grafito,
                        ),
                      ),
                    ),
                    pw.SizedBox(height: 36),
                    // Sello grande "MARCAJE POR GPS" en reemplazo del QR.
                    // El guardia no escanea nada: con acercarse al sector, la
                    // app lo detecta por el GPS del teléfono.
                    pw.Container(
                      padding: const pw.EdgeInsets.symmetric(
                          horizontal: 40, vertical: 30),
                      decoration: pw.BoxDecoration(
                        color: _Tinta.blanco,
                        border: pw.Border.all(color: _Tinta.grafito, width: 1.4),
                        borderRadius: pw.BorderRadius.circular(10),
                      ),
                      child: pw.Column(
                        children: [
                          pw.Text('📍',
                              style: const pw.TextStyle(fontSize: 64)),
                          pw.SizedBox(height: 10),
                          pw.Text('MARCAJE POR GPS',
                              style: pw.TextStyle(
                                fontSize: 18,
                                fontWeight: pw.FontWeight.bold,
                                letterSpacing: 2.5,
                                color: _Tinta.grafito,
                              )),
                          pw.SizedBox(height: 6),
                          pw.Text(
                            tieneUbicacion
                                ? 'Radio de tolerancia: $metrosDeTolerancia m'
                                : 'Ubicación pendiente de tomar',
                            style: pw.TextStyle(
                              fontSize: 10,
                              color: tieneUbicacion
                                  ? _Tinta.gris
                                  : _Tinta.naranja,
                              fontWeight: tieneUbicacion
                                  ? pw.FontWeight.normal
                                  : pw.FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                    pw.SizedBox(height: 24),
                    pw.Padding(
                      padding: const pw.EdgeInsets.symmetric(horizontal: 50),
                      child: pw.Text(
                        'El guardia no necesita escanear nada. Al acercarse '
                        'a este sector durante la ronda, la app lo detecta '
                        'automáticamente por GPS y registra la marca con '
                        'fecha, hora y ubicación.',
                        textAlign: pw.TextAlign.center,
                        style: const pw.TextStyle(
                          fontSize: 10,
                          color: _Tinta.gris,
                          lineSpacing: 2.5,
                        ),
                      ),
                    ),
                    if (!tieneUbicacion) ...[
                      pw.SizedBox(height: 20),
                      pw.Container(
                        padding: const pw.EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        decoration: pw.BoxDecoration(
                          color: _Tinta.naranjaFondo,
                          border: pw.Border.all(
                              color: _Tinta.naranja, width: 0.8),
                        ),
                        child: pw.Text(
                          'Este sector todavía no tiene ubicación tomada. '
                          'El guardia no va a poder marcarlo hasta que el '
                          'admin pase y la cargue.',
                          style: pw.TextStyle(
                              fontSize: 9,
                              fontWeight: pw.FontWeight.bold,
                              color: _Tinta.naranja),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            _pie(),
          ],
        ),
      ),
    );

    return doc.save();
  }

  static pw.Widget _banda(Uint8List? escudo, String instalacion) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(20),
      decoration: const pw.BoxDecoration(color: _Tinta.grafito),
      child: pw.Row(
        children: [
          if (escudo != null)
            pw.Container(
              width: 34,
              height: 39,
              child: pw.Image(pw.MemoryImage(escudo), fit: pw.BoxFit.contain),
            ),
          pw.SizedBox(width: 12),
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('TOMASS SEGURIDAD',
                    style: pw.TextStyle(
                      fontSize: 13,
                      fontWeight: pw.FontWeight.bold,
                      color: _Tinta.blanco,
                      letterSpacing: 1.2,
                    )),
                pw.Text(instalacion,
                    style: const pw.TextStyle(fontSize: 8.5, color: _Tinta.grisClaro)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _pie() => pw.Padding(
        padding: const pw.EdgeInsets.fromLTRB(24, 0, 24, 16),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              'Generado el ${Formato.fechaYHora(DateTime.now())}',
              style: const pw.TextStyle(fontSize: 7, color: _Tinta.gris),
            ),
            pw.Text('Tomass Seguridad Privada',
                style: const pw.TextStyle(fontSize: 7, color: _Tinta.gris)),
          ],
        ),
      );

  /// El escudo de la empresa. Si no está, el cartel sale igual sin él.
  static Future<Uint8List?> _leerEscudo() async {
    try {
      final datos = await rootBundle.load('assets/imagenes/logo.png');
      return datos.buffer.asUint8List();
    } catch (_) {
      return null;
    }
  }
}
