// ============================================================================
// Tomass Seguridad — Informe individual de labor por guardia (PDF)
// ============================================================================
// LO QUE ARMA
//
//   Un PDF con TODO lo que hizo un guardia en un período: turnos trabajados,
//   sectores marcados en rondas, novedades reportadas y paquetes recibidos.
//   Cada sección tiene sus KPIs propios y una tabla o timeline.
//
// PARA QUÉ SIRVE
//
//   Reunión mensual con el guardia, evaluación de desempeño, pago de horas,
//   entrega al cliente para demostrar la labor concreta de su condominio.
//
// ESTRUCTURA
//
//   1. Encabezado con banda dorada
//   2. Portada: foto de la última selfie + datos personales + período + KPIs
//   3. Sección Turnos: tabla cronológica con hora inicio/fin, puesto, duración
//   4. Sección Rondas: tabla con sector, hora y si tenía GPS
//   5. Sección Novedades: tarjetas con tipo, título, gravedad y fotos
//   6. Sección Paquetes: tabla con destinatario, descripción y fecha
// ============================================================================

import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

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

class InformeDeGuardiaPdf {
  static Future<Uint8List> armar({
    required String instalacion,
    required Map<String, dynamic> data,
    required ServicioFotos servicioFotos,
  }) async {
    final turnos = (data['turnos'] as List).cast<Map<String, dynamic>>();
    final rondas = (data['rondas'] as List).cast<Map<String, dynamic>>();
    final novedades = (data['novedades'] as List).cast<Map<String, dynamic>>();
    final paquetes = (data['paquetes'] as List).cast<Map<String, dynamic>>();
    final desde = data['desde'] as DateTime;
    final hasta = data['hasta'] as DateTime;
    final nombreGuardia = data['guardia_nombre'] as String;

    // Selfie del último turno para la portada.
    Uint8List? selfieBytes;
    if (turnos.isNotEmpty) {
      final foto = turnos.first['foto_url'] as String?;
      if (foto != null && foto.isNotEmpty) {
        try {
          selfieBytes =
              await servicioFotos.bytesParaPdf(foto, CajonDeFotos.guardias);
        } catch (_) {}
      }
    }

    final pdf = pw.Document();
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(30),
        header: (_) => _encabezado(instalacion, nombreGuardia),
        footer: (ctx) => pw.Padding(
          padding: const pw.EdgeInsets.only(top: 8),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'Informe de $nombreGuardia · $instalacion',
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
          ..._portada(
            nombreGuardia: nombreGuardia,
            email: data['guardia_email'] as String?,
            telefono: data['guardia_telefono'] as String?,
            desde: desde,
            hasta: hasta,
            selfie: selfieBytes,
            turnos: turnos.length,
            rondas: rondas.length,
            novedades: novedades.length,
            paquetes: paquetes.length,
            horasTotales: _horasDeTurnos(turnos),
          ),
          pw.SizedBox(height: 20),
          _tituloSeccion('Turnos trabajados'),
          pw.SizedBox(height: 8),
          if (turnos.isEmpty) _sinDatos('Sin turnos en este período.')
          else _tablaTurnos(turnos),
          pw.SizedBox(height: 20),
          _tituloSeccion('Rondas realizadas'),
          pw.SizedBox(height: 8),
          if (rondas.isEmpty) _sinDatos('Sin rondas en este período.')
          else _tablaRondas(rondas),
          pw.SizedBox(height: 20),
          _tituloSeccion('Novedades reportadas'),
          pw.SizedBox(height: 8),
          if (novedades.isEmpty)
            _sinDatos('Sin novedades reportadas en este período.')
          else ...novedades.map(_tarjetaNovedad),
          pw.SizedBox(height: 20),
          _tituloSeccion('Paquetes recibidos'),
          pw.SizedBox(height: 8),
          if (paquetes.isEmpty)
            _sinDatos('Sin paquetes recibidos en este período.')
          else _tablaPaquetes(paquetes),
        ],
      ),
    );
    return pdf.save();
  }

  // -------------------------------------------------------------------------

  static pw.Widget _encabezado(String instalacion, String guardia) {
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
                  '$guardia · $instalacion',
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

  static List<pw.Widget> _portada({
    required String nombreGuardia,
    String? email,
    String? telefono,
    required DateTime desde,
    required DateTime hasta,
    Uint8List? selfie,
    required int turnos,
    required int rondas,
    required int novedades,
    required int paquetes,
    required int horasTotales,
  }) {
    return [
      pw.SizedBox(height: 8),
      pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          _selfieCircular(selfie, tamano: 74),
          pw.SizedBox(width: 16),
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'Informe de labor',
                  style: const pw.TextStyle(
                      fontSize: 12, color: _Tinta.suave),
                ),
                pw.Text(
                  nombreGuardia,
                  style: pw.TextStyle(
                    fontSize: 22,
                    fontWeight: pw.FontWeight.bold,
                    color: _Tinta.grafito,
                  ),
                ),
                pw.SizedBox(height: 3),
                pw.Text(
                  'Del ${Formato.fecha(desde)} al ${Formato.fecha(hasta)}',
                  style: const pw.TextStyle(
                      fontSize: 12, color: _Tinta.suave),
                ),
                if ((email != null && email.isNotEmpty) ||
                    (telefono != null && telefono.isNotEmpty)) ...[
                  pw.SizedBox(height: 4),
                  pw.Text(
                    [
                      if (email != null && email.isNotEmpty) email,
                      if (telefono != null && telefono.isNotEmpty) telefono,
                    ].join(' · '),
                    style: const pw.TextStyle(
                        fontSize: 10, color: _Tinta.tenue),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
      pw.SizedBox(height: 18),
      pw.Row(
        children: [
          _kpi('Turnos', '$turnos', _Tinta.grafito),
          pw.SizedBox(width: 8),
          _kpi('Horas', '${horasTotales}h', _Tinta.verde),
          pw.SizedBox(width: 8),
          _kpi('Rondas', '$rondas', _Tinta.dorado),
          pw.SizedBox(width: 8),
          _kpi('Novedades', '$novedades',
              novedades > 0 ? _Tinta.rojo : _Tinta.suave),
          pw.SizedBox(width: 8),
          _kpi('Paquetes', '$paquetes', _Tinta.naranja),
        ],
      ),
    ];
  }

  static int _horasDeTurnos(List<Map<String, dynamic>> turnos) {
    double total = 0;
    for (final t in turnos) {
      final inicio = DateTime.tryParse(t['inicio']?.toString() ?? '');
      if (inicio == null) continue;
      final fin = t['cerrado_en'] == null
          ? DateTime.now()
          : DateTime.tryParse(t['cerrado_en'].toString()) ?? inicio;
      total += fin.difference(inicio).inMinutes / 60.0;
    }
    return total.round();
  }

  static pw.Widget _selfieCircular(Uint8List? bytes, {required double tamano}) {
    if (bytes == null) {
      return pw.Container(
        width: tamano,
        height: tamano,
        decoration: pw.BoxDecoration(
          color: _Tinta.fondoZebra,
          shape: pw.BoxShape.circle,
          border: pw.Border.all(color: _Tinta.linea, width: 1.5),
        ),
        alignment: pw.Alignment.center,
        child: pw.Text('sin foto',
            style: const pw.TextStyle(fontSize: 8, color: _Tinta.tenue)),
      );
    }
    return pw.ClipOval(
      child: pw.Image(
        pw.MemoryImage(bytes),
        width: tamano,
        height: tamano,
        fit: pw.BoxFit.cover,
      ),
    );
  }

  static pw.Widget _kpi(String etiqueta, String valor, PdfColor color) {
    return pw.Expanded(
      child: pw.Container(
        padding: const pw.EdgeInsets.all(10),
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
                fontSize: 22,
                fontWeight: pw.FontWeight.bold,
                color: color,
              ),
            ),
            pw.SizedBox(height: 2),
            pw.Text(
              etiqueta,
              style: const pw.TextStyle(fontSize: 9.5, color: _Tinta.suave),
            ),
          ],
        ),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Turnos
  // -------------------------------------------------------------------------

  static pw.Widget _tablaTurnos(List<Map<String, dynamic>> turnos) {
    return pw.Table(
      border: pw.TableBorder.all(color: _Tinta.linea, width: 0.6),
      columnWidths: {
        0: const pw.FixedColumnWidth(90),
        1: const pw.FlexColumnWidth(2.0),
        2: const pw.FixedColumnWidth(56),
        3: const pw.FixedColumnWidth(56),
        4: const pw.FixedColumnWidth(50),
        5: const pw.FixedColumnWidth(48),
      },
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: _Tinta.grafito),
          children: [
            _th('Fecha'),
            _th('Puesto'),
            _th('Inicio'),
            _th('Fin'),
            _th('Duración'),
            _th('GPS'),
          ],
        ),
        for (var i = 0; i < turnos.length; i++)
          _filaTurno(turnos[i], i.isEven),
      ],
    );
  }

  static pw.TableRow _filaTurno(Map<String, dynamic> t, bool zebra) {
    final inicio = DateTime.parse(t['inicio'] as String);
    final cerrado = t['cerrado_en'] == null
        ? null
        : DateTime.parse(t['cerrado_en'] as String);
    final puesto = t['puntos_acceso'] is Map
        ? (t['puntos_acceso'] as Map)['nombre']?.toString() ?? '—'
        : 'Cubría todo';
    final horas = cerrado == null
        ? '—'
        : _duracionCorta(cerrado.difference(inicio));
    final gps = t['geo_lat'] != null ? 'Sí' : '—';

    return pw.TableRow(
      decoration: pw.BoxDecoration(
        color: zebra ? _Tinta.fondoZebra : PdfColors.white,
      ),
      children: [
        _td(Formato.fecha(inicio)),
        _td(puesto),
        _td(Formato.hora(inicio)),
        _td(cerrado == null ? 'Abierto' : Formato.hora(cerrado),
            tinta: cerrado == null ? _Tinta.verde : _Tinta.grafito,
            bold: cerrado == null),
        _td(horas),
        _td(gps,
            tinta: gps == 'Sí' ? _Tinta.verde : _Tinta.tenue,
            bold: gps == 'Sí'),
      ],
    );
  }

  static String _duracionCorta(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    if (h == 0) return '${m}m';
    return '${h}h ${m}m';
  }

  // -------------------------------------------------------------------------
  // Rondas
  // -------------------------------------------------------------------------

  static pw.Widget _tablaRondas(List<Map<String, dynamic>> rondas) {
    return pw.Table(
      border: pw.TableBorder.all(color: _Tinta.linea, width: 0.6),
      columnWidths: {
        0: const pw.FixedColumnWidth(96),
        1: const pw.FlexColumnWidth(2.4),
        2: const pw.FixedColumnWidth(56),
      },
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: _Tinta.grafito),
          children: [_th('Fecha/hora'), _th('Sector'), _th('GPS')],
        ),
        for (var i = 0; i < rondas.length; i++)
          _filaRonda(rondas[i], i.isEven),
      ],
    );
  }

  static pw.TableRow _filaRonda(Map<String, dynamic> r, bool zebra) {
    final cuando = DateTime.parse(r['marcado_en'] as String);
    final sector = r['puntos_control'] is Map
        ? (r['puntos_control'] as Map)['nombre']?.toString() ?? '—'
        : '—';
    final gps = r['geo_lat'] != null ? 'Sí' : 'no';
    return pw.TableRow(
      decoration: pw.BoxDecoration(
        color: zebra ? _Tinta.fondoZebra : PdfColors.white,
      ),
      children: [
        _td(Formato.fechaYHora(cuando)),
        _td(sector),
        _td(gps,
            tinta: gps == 'Sí' ? _Tinta.verde : _Tinta.naranja,
            bold: gps == 'Sí'),
      ],
    );
  }

  // -------------------------------------------------------------------------
  // Novedades
  // -------------------------------------------------------------------------

  static pw.Widget _tarjetaNovedad(Map<String, dynamic> n) {
    final gravedad = (n['gravedad'] ?? 'baja').toString();
    final color = switch (gravedad.toLowerCase()) {
      'critica' || 'critico' || 'alta' => _Tinta.rojo,
      'media' => _Tinta.naranja,
      _ => _Tinta.verde,
    };
    final ocurrido = DateTime.parse(n['ocurrido_en'] as String);
    final resuelto = n['estado'] == 'resuelta';

    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 10),
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        color: PdfColors.white,
        borderRadius: pw.BorderRadius.circular(8),
        border: pw.Border.all(color: _Tinta.linea),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            children: [
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(
                    horizontal: 6, vertical: 2),
                decoration: pw.BoxDecoration(
                  color: color,
                  borderRadius: pw.BorderRadius.circular(4),
                ),
                child: pw.Text(
                  gravedad.toUpperCase(),
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
                (n['tipo'] ?? 'otra').toString().toUpperCase(),
                style: pw.TextStyle(
                  fontSize: 9,
                  fontWeight: pw.FontWeight.bold,
                  color: _Tinta.suave,
                  letterSpacing: 0.6,
                ),
              ),
              pw.Spacer(),
              pw.Text(
                Formato.fechaYHora(ocurrido),
                style: const pw.TextStyle(fontSize: 9, color: _Tinta.tenue),
              ),
              pw.SizedBox(width: 8),
              pw.Text(
                resuelto ? 'RESUELTA' : 'ABIERTA',
                style: pw.TextStyle(
                  fontSize: 8.5,
                  fontWeight: pw.FontWeight.bold,
                  color: resuelto ? _Tinta.verde : _Tinta.naranja,
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 6),
          pw.Text(
            (n['titulo'] ?? '').toString(),
            style: pw.TextStyle(
              fontSize: 12,
              fontWeight: pw.FontWeight.bold,
              color: _Tinta.grafito,
            ),
          ),
          if (n['descripcion'] != null &&
              n['descripcion'].toString().isNotEmpty) ...[
            pw.SizedBox(height: 3),
            pw.Text(
              n['descripcion'].toString(),
              style: const pw.TextStyle(
                fontSize: 10, color: _Tinta.grafito, lineSpacing: 2,
              ),
            ),
          ],
        ],
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Paquetes
  // -------------------------------------------------------------------------

  static pw.Widget _tablaPaquetes(List<Map<String, dynamic>> paquetes) {
    return pw.Table(
      border: pw.TableBorder.all(color: _Tinta.linea, width: 0.6),
      columnWidths: {
        0: const pw.FixedColumnWidth(80),
        1: const pw.FlexColumnWidth(2.4),
        2: const pw.FlexColumnWidth(2.0),
        3: const pw.FixedColumnWidth(70),
        4: const pw.FixedColumnWidth(58),
      },
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: _Tinta.grafito),
          children: [
            _th('Fecha'),
            _th('Destinatario'),
            _th('Descripción'),
            _th('Nº Seg.'),
            _th('Estado'),
          ],
        ),
        for (var i = 0; i < paquetes.length; i++)
          _filaPaquete(paquetes[i], i.isEven),
      ],
    );
  }

  static pw.TableRow _filaPaquete(Map<String, dynamic> p, bool zebra) {
    final recibido = DateTime.parse(p['recibido_en'] as String);
    final destinatario = p['usuarios'] is Map
        ? (p['usuarios'] as Map)['nombre_completo']?.toString() ?? '—'
        : (p['destinatario_texto']?.toString() ?? '—');
    final unidad = p['unidades'] is Map
        ? (p['unidades'] as Map)['numero']?.toString() ?? ''
        : (p['unidad_texto']?.toString() ?? '');
    final destinatarioConUnidad = unidad.isNotEmpty
        ? '$destinatario · $unidad'
        : destinatario;
    final estado = (p['estado'] ?? 'en_porteria') as String;
    return pw.TableRow(
      decoration: pw.BoxDecoration(
        color: zebra ? _Tinta.fondoZebra : PdfColors.white,
      ),
      children: [
        _td(Formato.fecha(recibido)),
        _td(destinatarioConUnidad),
        _td(p['descripcion']?.toString() ?? '—'),
        _td(p['numero_seguimiento']?.toString() ?? '—'),
        _td(
          estado == 'entregado' ? 'Entreg.' : 'Portería',
          bold: true,
          tinta: estado == 'entregado' ? _Tinta.verde : _Tinta.naranja,
        ),
      ],
    );
  }

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

  static pw.Widget _sinDatos(String texto) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(14),
      decoration: pw.BoxDecoration(
        color: _Tinta.fondoZebra,
        borderRadius: pw.BorderRadius.circular(8),
      ),
      child: pw.Center(
        child: pw.Text(
          texto,
          style: const pw.TextStyle(fontSize: 10.5, color: _Tinta.suave),
        ),
      ),
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
          ),
          maxLines: 2,
          overflow: pw.TextOverflow.clip,
        ),
      );
}
