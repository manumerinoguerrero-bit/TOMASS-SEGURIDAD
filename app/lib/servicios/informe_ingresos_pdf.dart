// ============================================================================
// Tomass Seguridad — Informe de Ingresos y Egresos (PDF)
// ============================================================================
// LO QUE ARMA
//
//   Un PDF con TODOS los ingresos y egresos del período (peatonales y
//   vehiculares, aprobados y denegados). Sirve como constancia para la
//   administración: quién entró, quién salió, cuándo, por qué puerta.
//
//   Estructura:
//     - Portada con período + 4 KPIs (total, entradas, salidas, denegados)
//     - Desglose por tipo (peatonal vs vehicular)
//     - Desglose por punto de acceso
//     - Tabla completa cronológica con todos los movimientos
//
// PALETA MERLYN
//
//   Azul marino corporativo como color principal, dorado como acento.
//   Verdes/rojos para los estados semánticos.
// ============================================================================

import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../modelos/admin.dart';
import '../nucleo/formato.dart';

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

class InformeDeIngresosPdf {
  /// Arma el PDF completo del período. Los movimientos ya vienen ordenados
  /// del servidor (más recientes primero); el PDF los muestra en el mismo
  /// orden, arriba lo más nuevo.
  static Future<Uint8List> armar({
    required String instalacion,
    required DateTime desde,
    required DateTime hasta,
    required List<MovimientoAdmin> movimientos,
  }) async {
    final pdf = pw.Document();

    final stats = _Estadisticas.calcular(movimientos);

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(30),
        header: (_) => _encabezado(instalacion, desde, hasta),
        footer: (ctx) => pw.Padding(
          padding: const pw.EdgeInsets.only(top: 8),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'Informe de Ingresos · $instalacion',
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
          ..._portada(stats, movimientos.length),
          pw.SizedBox(height: 14),
          _tituloSeccion('Detalle cronológico'),
          pw.SizedBox(height: 8),
          if (movimientos.isEmpty)
            _sinDatos()
          else
            _tablaMovimientos(movimientos),
        ],
      ),
    );

    return pdf.save();
  }

  // -------------------------------------------------------------------------
  // Encabezado / portada / KPIs
  // -------------------------------------------------------------------------

  static pw.Widget _encabezado(
      String instalacion, DateTime desde, DateTime hasta) {
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
          pw.Container(
            width: 4,
            height: 32,
            color: _Tinta.dorado,
          ),
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

  static List<pw.Widget> _portada(_Estadisticas s, int total) {
    return [
      pw.SizedBox(height: 8),
      pw.Text(
        'Informe de Ingresos y Egresos',
        style: pw.TextStyle(
          fontSize: 22,
          fontWeight: pw.FontWeight.bold,
          color: _Tinta.grafito,
        ),
      ),
      pw.SizedBox(height: 4),
      pw.Text(
        'Del ${Formato.fecha(s.desde)} al ${Formato.fecha(s.hasta)}',
        style: const pw.TextStyle(fontSize: 12, color: _Tinta.suave),
      ),
      pw.SizedBox(height: 18),

      // Cuatro KPI cards estilo Merlyn
      pw.Row(
        children: [
          _kpi('Total', '$total', _Tinta.grafito),
          pw.SizedBox(width: 8),
          _kpi('Entradas', '${s.entradas}', _Tinta.verde),
          pw.SizedBox(width: 8),
          _kpi('Salidas', '${s.salidas}', _Tinta.dorado),
          pw.SizedBox(width: 8),
          _kpi('Denegados', '${s.denegados}',
              s.denegados > 0 ? _Tinta.rojo : _Tinta.suave),
        ],
      ),

      pw.SizedBox(height: 16),

      // Desglose por tipo (peatonal / vehicular)
      pw.Row(
        children: [
          _desgloseTarjeta(
            titulo: 'Peatones',
            entradas: s.peatonEntradas,
            salidas: s.peatonSalidas,
          ),
          pw.SizedBox(width: 10),
          _desgloseTarjeta(
            titulo: 'Vehículos',
            entradas: s.autoEntradas,
            salidas: s.autoSalidas,
          ),
        ],
      ),

      if (s.porPunto.isNotEmpty) ...[
        pw.SizedBox(height: 16),
        _tituloSeccion('Por punto de acceso'),
        pw.SizedBox(height: 6),
        pw.Column(
          children: s.porPunto.entries
              .toList()
              .map((e) => _filaPunto(e.key, e.value))
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

  static pw.Widget _desgloseTarjeta({
    required String titulo,
    required int entradas,
    required int salidas,
  }) {
    return pw.Expanded(
      child: pw.Container(
        padding: const pw.EdgeInsets.all(12),
        decoration: pw.BoxDecoration(
          color: _Tinta.fondoZebra,
          borderRadius: pw.BorderRadius.circular(10),
          border: pw.Border.all(color: _Tinta.linea),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              titulo,
              style: pw.TextStyle(
                fontSize: 11,
                fontWeight: pw.FontWeight.bold,
                color: _Tinta.grafito,
                letterSpacing: 0.8,
              ),
            ),
            pw.SizedBox(height: 8),
            pw.Row(
              children: [
                _pequeno('Entradas', '$entradas', _Tinta.verde),
                pw.SizedBox(width: 12),
                _pequeno('Salidas', '$salidas', _Tinta.dorado),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static pw.Widget _pequeno(String etiqueta, String valor, PdfColor color) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          valor,
          style: pw.TextStyle(
            fontSize: 18,
            fontWeight: pw.FontWeight.bold,
            color: color,
          ),
        ),
        pw.Text(
          etiqueta,
          style: const pw.TextStyle(fontSize: 9, color: _Tinta.tenue),
        ),
      ],
    );
  }

  static pw.Widget _filaPunto(String nombre, int cantidad) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 3),
      child: pw.Row(
        children: [
          pw.Container(
            width: 3,
            height: 14,
            color: _Tinta.dorado,
          ),
          pw.SizedBox(width: 8),
          pw.Expanded(
            child: pw.Text(
              nombre,
              style: const pw.TextStyle(fontSize: 10.5, color: _Tinta.grafito),
            ),
          ),
          pw.Text(
            '$cantidad',
            style: pw.TextStyle(
              fontSize: 11,
              fontWeight: pw.FontWeight.bold,
              color: _Tinta.grafito,
            ),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Tabla de movimientos
  // -------------------------------------------------------------------------

  static pw.Widget _tablaMovimientos(List<MovimientoAdmin> movs) {
    return pw.Table(
      border: pw.TableBorder.all(color: _Tinta.linea, width: 0.6),
      columnWidths: {
        0: const pw.FixedColumnWidth(82),  // fecha
        1: const pw.FixedColumnWidth(58),  // tipo
        2: const pw.FixedColumnWidth(48),  // sentido
        3: const pw.FlexColumnWidth(2.2),  // quién
        4: const pw.FlexColumnWidth(1.0),  // unidad
        5: const pw.FixedColumnWidth(62),  // patente
        6: const pw.FlexColumnWidth(1.4),  // punto
        7: const pw.FixedColumnWidth(52),  // estado
      },
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: _Tinta.grafito),
          children: [
            _th('Fecha/hora'),
            _th('Tipo'),
            _th('Sentido'),
            _th('Quién'),
            _th('Unidad'),
            _th('Patente'),
            _th('Punto'),
            _th('Estado'),
          ],
        ),
        for (var i = 0; i < movs.length; i++)
          _fila(movs[i], i.isEven),
      ],
    );
  }

  static pw.TableRow _fila(MovimientoAdmin m, bool zebra) {
    final color = m.aprobado ? _Tinta.verde : _Tinta.rojo;
    return pw.TableRow(
      decoration: pw.BoxDecoration(
        color: zebra ? _Tinta.fondoZebra : PdfColors.white,
      ),
      children: [
        _td(Formato.fechaYHora(m.ocurridoEn)),
        _td(m.esVehicular ? 'Vehículo' : 'Peatón'),
        _td(m.esEntrada ? 'Entrada' : 'Salida'),
        _td(m.quien ?? '—'),
        _td(m.espacio ?? '—'),
        _td(m.patente ?? '—', mono: true),
        _td(m.entrada ?? '—'),
        _td(
          m.aprobado ? 'OK' : 'NEG',
          bold: true,
          tinta: color,
        ),
      ],
    );
  }

  static pw.Widget _th(String texto) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 6),
        child: pw.Text(
          texto,
          style: pw.TextStyle(
            fontSize: 9,
            fontWeight: pw.FontWeight.bold,
            color: PdfColors.white,
            letterSpacing: 0.4,
          ),
        ),
      );

  static pw.Widget _td(
    String texto, {
    bool bold = false,
    bool mono = false,
    PdfColor tinta = _Tinta.grafito,
  }) =>
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 5),
        child: pw.Text(
          texto,
          style: pw.TextStyle(
            fontSize: 8.5,
            fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
            color: tinta,
            fontFeatures: mono ? const [pw.FontFeature.tabularFigures()] : null,
          ),
          maxLines: 2,
          overflow: pw.TextOverflow.clip,
        ),
      );

  // -------------------------------------------------------------------------
  // Ayudantes
  // -------------------------------------------------------------------------

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
          'No hubo ingresos ni egresos en este período.',
          style: const pw.TextStyle(fontSize: 11, color: _Tinta.suave),
        ),
      ),
    );
  }
}

// ============================================================================
// ESTADÍSTICAS del período — calculadas en el momento
// ============================================================================

class _Estadisticas {
  _Estadisticas({
    required this.desde,
    required this.hasta,
    required this.entradas,
    required this.salidas,
    required this.denegados,
    required this.peatonEntradas,
    required this.peatonSalidas,
    required this.autoEntradas,
    required this.autoSalidas,
    required this.porPunto,
  });

  final DateTime desde;
  final DateTime hasta;
  final int entradas;
  final int salidas;
  final int denegados;
  final int peatonEntradas;
  final int peatonSalidas;
  final int autoEntradas;
  final int autoSalidas;
  final Map<String, int> porPunto;

  factory _Estadisticas.calcular(List<MovimientoAdmin> movs) {
    int entradas = 0, salidas = 0, denegados = 0;
    int peatonE = 0, peatonS = 0, autoE = 0, autoS = 0;
    final porPunto = <String, int>{};
    DateTime? desde, hasta;

    for (final m in movs) {
      if (m.esEntrada) {
        entradas++;
        if (m.esVehicular) autoE++;
        else peatonE++;
      } else {
        salidas++;
        if (m.esVehicular) autoS++;
        else peatonS++;
      }
      if (!m.aprobado) denegados++;
      if (m.entrada != null) {
        porPunto.update(m.entrada!, (v) => v + 1, ifAbsent: () => 1);
      }
      desde = desde == null || m.ocurridoEn.isBefore(desde)
          ? m.ocurridoEn
          : desde;
      hasta = hasta == null || m.ocurridoEn.isAfter(hasta)
          ? m.ocurridoEn
          : hasta;
    }

    return _Estadisticas(
      desde: desde ?? DateTime.now(),
      hasta: hasta ?? DateTime.now(),
      entradas: entradas,
      salidas: salidas,
      denegados: denegados,
      peatonEntradas: peatonE,
      peatonSalidas: peatonS,
      autoEntradas: autoE,
      autoSalidas: autoS,
      porPunto: Map.fromEntries(
        porPunto.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value)),
      ),
    );
  }
}
