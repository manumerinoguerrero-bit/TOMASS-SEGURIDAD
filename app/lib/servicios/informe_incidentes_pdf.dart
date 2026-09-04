// ============================================================================
// Tomass Seguridad — Informe de Novedades / Incidentes (PDF)
// ============================================================================
// LO QUE ARMA
//
//   Un PDF con TODAS las novedades reportadas por los guardias durante el
//   período. En la base se llaman "incidentes" pero en la UI son "novedades".
//
//   Cada novedad viene con: fecha, tipo, gravedad, título, descripción,
//   ubicación, quién la reportó, y hasta 3 fotos adjuntas. Si está resuelta,
//   también la fecha y la nota de resolución.
//
// PARA QUÉ SIRVE
//
//   Constancia oficial para la administración. La copia impresa se le pasa
//   al comité, se archiva mensualmente, o va anexa al informe a la
//   aseguradora cuando hay que reclamar por un daño.
//
// FOTOS QUE FALTAN
//
//   Igual criterio que en informe_turnos_pdf: si una foto se borró del
//   servidor, aparece un marcador gris y la novedad sigue apareciendo. Un
//   PDF que se rompe entero por una foto ausente deja al administrador sin
//   nada.
// ============================================================================

import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../modelos/admin.dart';
import '../nucleo/formato.dart';
import 'servicio_fotos.dart';

abstract class _Tinta {
  static const grafito = PdfColor.fromInt(0xFF0D2B5E);
  static const dorado = PdfColor.fromInt(0xFFC9A24E);
  static const suave = PdfColor.fromInt(0xFF6B7280);
  static const tenue = PdfColor.fromInt(0xFF9CA3AF);
  static const linea = PdfColor.fromInt(0xFFE5E7EB);
  static const fondoZebra = PdfColor.fromInt(0xFFF9FAFB);
  static const verde = PdfColor.fromInt(0xFF27AE60);
  static const rojo = PdfColor.fromInt(0xFFE74C3C);
  static const naranja = PdfColor.fromInt(0xFFF39C12);
}

class InformeDeIncidentesPdf {
  /// Arma el PDF con todas las novedades del período. Baja las fotos del
  /// servidor de a 6 en paralelo para no saturar la red.
  static Future<Uint8List> armar({
    required String instalacion,
    required DateTime desde,
    required DateTime hasta,
    required List<IncidenteAdmin> incidentes,
    required ServicioFotos servicioFotos,
  }) async {
    // Bajar todas las fotos de una vez.
    final fotos = <String, Uint8List?>{};
    final rutasTodas = <String>[
      for (final i in incidentes) ...i.fotos,
    ];
    for (var k = 0; k < rutasTodas.length; k += 6) {
      final tanda = rutasTodas.skip(k).take(6).toList();
      final bytes = await Future.wait(tanda.map((ruta) async {
        try {
          return await servicioFotos.bytesParaPdf(ruta, CajonDeFotos.paquetes);
        } catch (_) {
          return null;
        }
      }));
      for (var j = 0; j < tanda.length; j++) {
        fotos[tanda[j]] = bytes[j];
      }
    }

    final stats = _Estadisticas.calcular(incidentes);
    final pdf = pw.Document();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(30),
        header: (_) => _encabezado(instalacion),
        footer: (ctx) => pw.Padding(
          padding: const pw.EdgeInsets.only(top: 8),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'Informe de Novedades · $instalacion',
                style: const pw.TextStyle(fontSize: 9, color: _Tinta.tenue),
              ),
              pw.Text(
                'Página ${ctx.pageNumber} de ${ctx.pagesCount}',
                style: const pw.TextStyle(fontSize: 9, color: _Tinta.tenue),
              ),
            ],
          ),
        ),
        build: (_) => [
          ..._portada(stats, desde, hasta),
          pw.SizedBox(height: 16),
          if (incidentes.isEmpty)
            _sinDatos()
          else
            ...incidentes.map((i) => _tarjeta(i, fotos)),
        ],
      ),
    );

    return pdf.save();
  }

  // -------------------------------------------------------------------------
  // Encabezado + portada
  // -------------------------------------------------------------------------

  static pw.Widget _encabezado(String instalacion) {
    return pw.Container(
      padding: const pw.EdgeInsets.only(bottom: 10),
      decoration: const pw.BoxDecoration(
        border: pw.Border(
          bottom: pw.BorderSide(color: _Tinta.linea, width: 1),
        ),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          pw.Container(width: 4, height: 32, color: _Tinta.dorado),
          pw.SizedBox(width: 10),
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'TOMASS SEGURIDAD',
                  style: pw.TextStyle(
                    fontSize: 10,
                    fontWeight: pw.FontWeight.bold,
                    letterSpacing: 1.4,
                    color: _Tinta.grafito,
                  ),
                ),
                pw.Text(
                  instalacion,
                  style: const pw.TextStyle(
                      fontSize: 12.5, color: _Tinta.suave),
                ),
              ],
            ),
          ),
          pw.Text(
            'Generado ${Formato.fechaYHora(DateTime.now())}',
            style: const pw.TextStyle(fontSize: 9, color: _Tinta.tenue),
          ),
        ],
      ),
    );
  }

  static List<pw.Widget> _portada(
      _Estadisticas s, DateTime desde, DateTime hasta) {
    return [
      pw.SizedBox(height: 8),
      pw.Text(
        'Informe de Novedades',
        style: pw.TextStyle(
          fontSize: 22,
          fontWeight: pw.FontWeight.bold,
          color: _Tinta.grafito,
        ),
      ),
      pw.SizedBox(height: 4),
      pw.Text(
        'Del ${Formato.fecha(desde)} al ${Formato.fecha(hasta)}',
        style: const pw.TextStyle(fontSize: 12, color: _Tinta.suave),
      ),
      pw.SizedBox(height: 18),
      pw.Row(
        children: [
          _kpi('Total', '${s.total}', _Tinta.grafito),
          pw.SizedBox(width: 8),
          _kpi('Abiertas', '${s.abiertas}',
              s.abiertas > 0 ? _Tinta.naranja : _Tinta.verde),
          pw.SizedBox(width: 8),
          _kpi('Resueltas', '${s.resueltas}', _Tinta.verde),
          pw.SizedBox(width: 8),
          _kpi('Con fotos', '${s.conFotos}', _Tinta.dorado),
        ],
      ),
      if (s.porGravedad.isNotEmpty) ...[
        pw.SizedBox(height: 16),
        _tituloSeccion('Por gravedad'),
        pw.SizedBox(height: 6),
        pw.Row(
          children: s.porGravedad.entries
              .map((e) => pw.Expanded(
                    child: _cajaGravedad(e.key, e.value),
                  ))
              .toList(),
        ),
      ],
    ];
  }

  static pw.Widget _kpi(String etiqueta, String valor, PdfColor color) {
    return pw.Expanded(
      child: pw.Container(
        padding: const pw.EdgeInsets.all(12),
        decoration: pw.BoxDecoration(
          color: PdfColors.white,
          borderRadius: pw.BorderRadius.circular(10),
          border: pw.Border.all(color: _Tinta.linea, width: 1),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              valor,
              style: pw.TextStyle(
                fontSize: 26,
                fontWeight: pw.FontWeight.bold,
                color: color,
              ),
            ),
            pw.SizedBox(height: 2),
            pw.Text(
              etiqueta,
              style: const pw.TextStyle(fontSize: 10, color: _Tinta.suave),
            ),
          ],
        ),
      ),
    );
  }

  static pw.Widget _cajaGravedad(String gravedad, int cantidad) {
    final color = _colorGravedad(gravedad);
    return pw.Container(
      margin: const pw.EdgeInsets.only(right: 6),
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        color: color.shade(0.9),
        borderRadius: pw.BorderRadius.circular(8),
        border: pw.Border.all(color: color, width: 1.2),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            '$cantidad',
            style: pw.TextStyle(
              fontSize: 18,
              fontWeight: pw.FontWeight.bold,
              color: color,
            ),
          ),
          pw.Text(
            gravedad.toUpperCase(),
            style: pw.TextStyle(
              fontSize: 9,
              fontWeight: pw.FontWeight.bold,
              color: color,
              letterSpacing: 0.6,
            ),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Tarjeta de una novedad
  // -------------------------------------------------------------------------

  static pw.Widget _tarjeta(
      IncidenteAdmin i, Map<String, Uint8List?> fotos) {
    final color = _colorGravedad(i.gravedad ?? 'baja');
    final fotosBytes =
        i.fotos.map((r) => fotos[r]).where((b) => b != null).toList();

    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 12),
      decoration: pw.BoxDecoration(
        color: PdfColors.white,
        borderRadius: pw.BorderRadius.circular(10),
        border: pw.Border.all(color: _Tinta.linea, width: 1),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          // Franja superior con estado + fecha
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: pw.BoxDecoration(
              color: _Tinta.grafito,
              borderRadius: const pw.BorderRadius.only(
                topLeft: pw.Radius.circular(10),
                topRight: pw.Radius.circular(10),
              ),
            ),
            child: pw.Row(
              children: [
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(
                      horizontal: 6, vertical: 2),
                  decoration: pw.BoxDecoration(
                    color: color,
                    borderRadius: pw.BorderRadius.circular(4),
                  ),
                  child: pw.Text(
                    (i.gravedad ?? 'baja').toUpperCase(),
                    style: pw.TextStyle(
                      fontSize: 8,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.white,
                      letterSpacing: 0.6,
                    ),
                  ),
                ),
                pw.SizedBox(width: 8),
                pw.Text(
                  i.tipo.toUpperCase(),
                  style: pw.TextStyle(
                    fontSize: 9,
                    color: PdfColors.white,
                    fontWeight: pw.FontWeight.bold,
                    letterSpacing: 0.8,
                  ),
                ),
                pw.Spacer(),
                pw.Text(
                  Formato.fechaYHora(i.ocurridoEn),
                  style: pw.TextStyle(
                    fontSize: 9,
                    color: PdfColors.white.shade(0.15),
                  ),
                ),
                pw.SizedBox(width: 8),
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(
                      horizontal: 6, vertical: 2),
                  decoration: pw.BoxDecoration(
                    color: i.abierta ? _Tinta.naranja : _Tinta.verde,
                    borderRadius: pw.BorderRadius.circular(4),
                  ),
                  child: pw.Text(
                    i.abierta ? 'ABIERTA' : 'RESUELTA',
                    style: pw.TextStyle(
                      fontSize: 8,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.white,
                      letterSpacing: 0.6,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Cuerpo
          pw.Padding(
            padding: const pw.EdgeInsets.all(12),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  i.titulo,
                  style: pw.TextStyle(
                    fontSize: 13,
                    fontWeight: pw.FontWeight.bold,
                    color: _Tinta.grafito,
                  ),
                ),
                if (i.descripcion != null && i.descripcion!.isNotEmpty) ...[
                  pw.SizedBox(height: 6),
                  pw.Text(
                    i.descripcion!,
                    style: const pw.TextStyle(
                      fontSize: 10.5,
                      color: _Tinta.grafito,
                      lineSpacing: 2.5,
                    ),
                  ),
                ],
                pw.SizedBox(height: 8),
                _metadatos(i),

                if (fotosBytes.isNotEmpty) ...[
                  pw.SizedBox(height: 10),
                  pw.Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final bytes in fotosBytes)
                        pw.ClipRRect(
                          horizontalRadius: 6,
                          verticalRadius: 6,
                          child: pw.Image(
                            pw.MemoryImage(bytes!),
                            width: 140,
                            height: 100,
                            fit: pw.BoxFit.cover,
                          ),
                        ),
                    ],
                  ),
                ],

                if (!i.abierta) ...[
                  pw.SizedBox(height: 10),
                  pw.Container(
                    padding: const pw.EdgeInsets.all(8),
                    decoration: pw.BoxDecoration(
                      color: _Tinta.verde.shade(0.9),
                      borderRadius: pw.BorderRadius.circular(6),
                      border: pw.Border.all(color: _Tinta.verde, width: 0.8),
                    ),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Row(
                          children: [
                            pw.Text(
                              'RESUELTA',
                              style: pw.TextStyle(
                                fontSize: 8.5,
                                fontWeight: pw.FontWeight.bold,
                                color: _Tinta.verde,
                                letterSpacing: 0.8,
                              ),
                            ),
                            if (i.resueltoEn != null) ...[
                              pw.Text(
                                ' · ${Formato.fechaYHora(i.resueltoEn!)}',
                                style: const pw.TextStyle(
                                  fontSize: 8.5,
                                  color: _Tinta.suave,
                                ),
                              ),
                            ],
                          ],
                        ),
                        if (i.notaResolucion != null &&
                            i.notaResolucion!.isNotEmpty) ...[
                          pw.SizedBox(height: 4),
                          pw.Text(
                            i.notaResolucion!,
                            style: const pw.TextStyle(
                              fontSize: 10,
                              color: _Tinta.grafito,
                              lineSpacing: 2,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _metadatos(IncidenteAdmin i) {
    final items = <List<String>>[
      if (i.reportadoPor != null) ['Reportado por', i.reportadoPor!],
      if (i.ubicacion != null && i.ubicacion!.isNotEmpty)
        ['Ubicación', i.ubicacion!],
      if (i.unidadTexto != null) ['Unidad', i.unidadTexto!],
      if (i.patente != null && i.patente!.isNotEmpty)
        ['Patente', i.patente!],
    ];
    if (items.isEmpty) return pw.SizedBox();

    return pw.Wrap(
      spacing: 14,
      runSpacing: 4,
      children: items
          .map((par) => pw.RichText(
                text: pw.TextSpan(
                  children: [
                    pw.TextSpan(
                      text: '${par[0]}: ',
                      style: const pw.TextStyle(
                        fontSize: 9,
                        color: _Tinta.tenue,
                      ),
                    ),
                    pw.TextSpan(
                      text: par[1],
                      style: pw.TextStyle(
                        fontSize: 9.5,
                        fontWeight: pw.FontWeight.bold,
                        color: _Tinta.grafito,
                      ),
                    ),
                  ],
                ),
              ))
          .toList(),
    );
  }

  // -------------------------------------------------------------------------
  // Ayudantes
  // -------------------------------------------------------------------------

  static PdfColor _colorGravedad(String g) {
    return switch (g.toLowerCase()) {
      'critica' || 'critico' || 'alta' => _Tinta.rojo,
      'media' => _Tinta.naranja,
      _ => _Tinta.verde,
    };
  }

  static pw.Widget _tituloSeccion(String texto) {
    return pw.Row(
      children: [
        pw.Container(width: 3, height: 16, color: _Tinta.dorado),
        pw.SizedBox(width: 8),
        pw.Text(
          texto.toUpperCase(),
          style: pw.TextStyle(
            fontSize: 11,
            fontWeight: pw.FontWeight.bold,
            color: _Tinta.grafito,
            letterSpacing: 1.1,
          ),
        ),
      ],
    );
  }

  static pw.Widget _sinDatos() {
    return pw.Container(
      padding: const pw.EdgeInsets.all(20),
      decoration: pw.BoxDecoration(
        color: _Tinta.fondoZebra,
        borderRadius: pw.BorderRadius.circular(10),
      ),
      child: pw.Center(
        child: pw.Text(
          'Sin novedades registradas en este período.',
          style: const pw.TextStyle(fontSize: 11, color: _Tinta.suave),
        ),
      ),
    );
  }
}

// ============================================================================
// ESTADÍSTICAS calculadas al vuelo
// ============================================================================

class _Estadisticas {
  _Estadisticas({
    required this.total,
    required this.abiertas,
    required this.resueltas,
    required this.conFotos,
    required this.porGravedad,
  });

  final int total;
  final int abiertas;
  final int resueltas;
  final int conFotos;
  final Map<String, int> porGravedad;

  factory _Estadisticas.calcular(List<IncidenteAdmin> lista) {
    int abiertas = 0, resueltas = 0, conFotos = 0;
    final gr = <String, int>{};
    for (final i in lista) {
      if (i.abierta) {
        abiertas++;
      } else {
        resueltas++;
      }
      if (i.tieneFotos) conFotos++;
      final g = i.gravedad ?? 'baja';
      gr.update(g, (v) => v + 1, ifAbsent: () => 1);
    }
    return _Estadisticas(
      total: lista.length,
      abiertas: abiertas,
      resueltas: resueltas,
      conFotos: conFotos,
      porGravedad: gr,
    );
  }
}
