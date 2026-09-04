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
// POR QUÉ EL CÓDIGO QR SE DIBUJA COMO LÍNEAS Y NO COMO UNA FOTO
//
//   Un dibujo de líneas (vectorial) sale nítido en cualquier tamaño, desde una
//   hoja carta hasta un cartel ampliado en una imprenta. Una foto se pixela al
//   agrandarla. Es la misma razón por la que herramientas/generar_carteles.dart
//   dibuja sus QR como SVG en vez de como imagen.
// ============================================================================

import 'dart:typed_data';

import 'package:barcode/barcode.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../nucleo/formato.dart';

class _Tinta {
  // Paleta Merlyn: azul marino corporativo.
  static const grafito = PdfColor.fromInt(0xFF0D2B5E);
  static const dorado = PdfColor.fromInt(0xFFC9A24E);
  static const gris = PdfColor.fromInt(0xFF6B7280);
  static const grisClaro = PdfColor.fromInt(0xFFE5E7EB);
  static const naranja = PdfColor.fromInt(0xFFF39C12);
  static const naranjaFondo = PdfColor.fromInt(0xFFFDF3E7);
  static const blanco = PdfColor.fromInt(0xFFFFFFFF);
}

class CartelDeSectorPdf {
  /// Arma el cartel de un sector, listo para imprimir o guardar.
  static Future<Uint8List> armar({
    required String instalacion,
    required String sector,
    required String codigoQr,
    required bool tieneUbicacion,
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
                          fontSize: 30,
                          fontWeight: pw.FontWeight.bold,
                          color: _Tinta.grafito,
                        ),
                      ),
                    ),
                    pw.SizedBox(height: 30),
                    pw.Container(
                      padding: const pw.EdgeInsets.all(18),
                      decoration: pw.BoxDecoration(
                        color: _Tinta.blanco,
                        border: pw.Border.all(color: _Tinta.grafito, width: 1.4),
                      ),
                      // El nivel más alto de resistencia a la suciedad: este
                      // cartel va a vivir a la intemperie, con polvo, sol y
                      // manos sucias.
                      child: pw.BarcodeWidget(
                        data: codigoQr,
                        barcode: Barcode.qrCode(
                            errorCorrectLevel: BarcodeQRCorrectionLevel.high),
                        drawText: false,
                        width: 230,
                        height: 230,
                      ),
                    ),
                    pw.SizedBox(height: 26),
                    pw.Padding(
                      padding: const pw.EdgeInsets.symmetric(horizontal: 60),
                      child: pw.Text(
                        'El guardia escanea este código al pasar por acá '
                        'durante la ronda.',
                        textAlign: pw.TextAlign.center,
                        style: const pw.TextStyle(fontSize: 10, color: _Tinta.gris),
                      ),
                    ),
                    if (!tieneUbicacion) ...[
                      pw.SizedBox(height: 18),
                      pw.Container(
                        padding:
                            const pw.EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: pw.BoxDecoration(
                          color: _Tinta.naranjaFondo,
                          border: pw.Border.all(color: _Tinta.naranja, width: 0.8),
                        ),
                        child: pw.Text(
                          'Este sector todavía no tiene ubicación tomada.',
                          style: pw.TextStyle(
                              fontSize: 9, fontWeight: pw.FontWeight.bold,
                              color: _Tinta.naranja),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            _pie(codigoQr),
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

  static pw.Widget _pie(String codigoQr) => pw.Padding(
        padding: const pw.EdgeInsets.fromLTRB(24, 0, 24, 16),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              'Generado el ${Formato.fechaYHora(DateTime.now())}',
              style: const pw.TextStyle(fontSize: 7, color: _Tinta.gris),
            ),
            pw.Text(codigoQr,
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
