// ============================================================================
// Tomass Seguridad — El informe de encomiendas entregadas, con foto
// ============================================================================
// QUÉ ES Y PARA QUÉ SIRVE
//
//   Manuel pidió esto para no llenar el servidor de fotos de cajas: una vez a
//   la semana, el administrador saca este informe (queda la foto de cada
//   encomienda entregada, en un papel que se puede guardar para siempre) y
//   después borra esas fotos de la aplicación con el botón de al lado.
//
//   El texto (quién la retiró, cuándo, quién la entregó) y la firma del
//   residente NUNCA se borran: eso vive en la base de datos para siempre y no
//   depende de este informe. Lo único que se borra es la foto.
//
// POR QUÉ LAS FOTOS SE ACHICAN OTRA VEZ ACÁ
//
//   Ya vienen comprimidas desde que se sacaron (servicio_fotos.dart), pero un
//   informe con 50 fotos a ese tamaño pesaría varios MB: demasiado para
//   mandar por WhatsApp con mala señal, que es justo el problema que este
//   informe tiene que evitar. Por eso ServicioFotos.bytesParaPdf las achica
//   una vez más, solo para esta hoja.
// ============================================================================

import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../modelos/admin.dart';
import '../nucleo/formato.dart';

class _Tinta {
  static const grafito = PdfColor.fromInt(0xFF1C1E24);
  static const gris = PdfColor.fromInt(0xFF6B6F78);
  static const grisClaro = PdfColor.fromInt(0xFFE2E4E8);
  static const naranja = PdfColor.fromInt(0xFFEF6C00);
  static const blanco = PdfColor.fromInt(0xFFFFFFFF);
  static const fondoFoto = PdfColor.fromInt(0xFFF4F5F6);
}

class InformeDeEncomiendasPdf {
  /// Arma el PDF y lo devuelve listo para compartir, imprimir o guardar.
  ///
  /// [fotos] trae, para cada encomienda que sí se pudo bajar, sus bytes ya
  /// achicados. La que no está en el mapa sale con el aviso de "sin foto":
  /// eso pasa si la foto ya no existía en el servidor cuando se armó el
  /// informe, y no debe romper el resto del documento.
  static Future<Uint8List> armar({
    required String instalacion,
    required int dias,
    required List<EncomiendaDelInforme> encomiendas,
    required Map<String, Uint8List> fotos,
  }) async {
    final doc = pw.Document(
      title: 'Informe de encomiendas — $instalacion',
      author: 'Tomass Seguridad Privada',
    );

    final escudo = await _leerEscudo();
    final hasta = DateTime.now();
    final desde = hasta.subtract(Duration(days: dias));
    final conFoto = encomiendas.where((e) => fotos[e.id] != null).length;

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        header: (ctx) => ctx.pageNumber == 1
            ? _encabezado(escudo, instalacion, desde, hasta)
            : pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 10),
                child: pw.Text('Encomiendas entregadas — $instalacion',
                    style: const pw.TextStyle(fontSize: 9, color: _Tinta.gris)),
              ),
        footer: (ctx) => _pie(ctx),
        build: (ctx) => [
          pw.SizedBox(height: 16),
          _resumen(encomiendas.length, conFoto),
          pw.SizedBox(height: 18),
          _titulo('Detalle, del más reciente al más antiguo'),
          pw.SizedBox(height: 10),
          ..._grilla(encomiendas, fotos),
        ],
      ),
    );

    return doc.save();
  }

  // ==========================================================================
  // ENCABEZADO
  // ==========================================================================

  static pw.Widget _encabezado(
    Uint8List? escudo,
    String instalacion,
    DateTime desde,
    DateTime hasta,
  ) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(16),
      margin: const pw.EdgeInsets.only(bottom: 4),
      decoration: const pw.BoxDecoration(color: _Tinta.grafito),
      child: pw.Row(
        children: [
          if (escudo != null)
            pw.Container(
              width: 40,
              height: 46,
              child: pw.Image(pw.MemoryImage(escudo), fit: pw.BoxFit.contain),
            ),
          pw.SizedBox(width: 14),
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('TOMASS SEGURIDAD',
                    style: pw.TextStyle(
                      fontSize: 15,
                      fontWeight: pw.FontWeight.bold,
                      color: _Tinta.blanco,
                      letterSpacing: 1.2,
                    )),
                pw.SizedBox(height: 2),
                pw.Text('INFORME DE ENCOMIENDAS ENTREGADAS',
                    style: const pw.TextStyle(
                        fontSize: 8, color: _Tinta.grisClaro, letterSpacing: 1.6)),
                pw.SizedBox(height: 8),
                pw.Text(instalacion,
                    style: pw.TextStyle(
                        fontSize: 13,
                        fontWeight: pw.FontWeight.bold,
                        color: _Tinta.blanco)),
                pw.Text(
                  'Del ${Formato.fecha(desde)} al ${Formato.fecha(hasta)}',
                  style: const pw.TextStyle(fontSize: 9.5, color: _Tinta.grisClaro),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================================================
  // RESUMEN
  // ==========================================================================

  static pw.Widget _resumen(int total, int conFoto) {
    final sinFoto = total - conFoto;
    return pw.Row(
      children: [
        _cuadro('$total', 'encomiendas\nentregadas'),
        pw.SizedBox(width: 8),
        _cuadro('$conFoto', 'con foto en\neste informe'),
        if (sinFoto > 0) ...[
          pw.SizedBox(width: 8),
          _cuadro('$sinFoto', 'sin foto\ndisponible', tinta: _Tinta.naranja),
        ],
      ],
    );
  }

  static pw.Widget _cuadro(String numero, String etiqueta,
      {PdfColor tinta = _Tinta.grafito}) {
    return pw.Expanded(
      child: pw.Container(
        padding: const pw.EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: pw.BoxDecoration(border: pw.Border.all(color: _Tinta.grisClaro)),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(numero,
                style: pw.TextStyle(
                    fontSize: 20, fontWeight: pw.FontWeight.bold, color: tinta)),
            pw.Text(etiqueta,
                style: const pw.TextStyle(
                    fontSize: 7.5, color: _Tinta.gris, lineSpacing: 1.5)),
          ],
        ),
      ),
    );
  }

  // ==========================================================================
  // LA GRILLA DE TARJETAS, DE A DOS POR FILA
  // ==========================================================================

  static List<pw.Widget> _grilla(
    List<EncomiendaDelInforme> encomiendas,
    Map<String, Uint8List> fotos,
  ) {
    final filas = <pw.Widget>[];
    for (var i = 0; i < encomiendas.length; i += 2) {
      final izquierda = encomiendas[i];
      final derecha = i + 1 < encomiendas.length ? encomiendas[i + 1] : null;
      filas.add(
        pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 8),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(child: _tarjeta(izquierda, fotos[izquierda.id])),
              pw.SizedBox(width: 8),
              pw.Expanded(
                child: derecha == null
                    ? pw.SizedBox()
                    : _tarjeta(derecha, fotos[derecha.id]),
              ),
            ],
          ),
        ),
      );
    }
    return filas;
  }

  static pw.Widget _tarjeta(EncomiendaDelInforme e, Uint8List? foto) {
    final descripcion = (e.descripcion ?? '').trim();

    return pw.Container(
      padding: const pw.EdgeInsets.all(8),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: _Tinta.grisClaro),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(3)),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Container(
            width: 60,
            height: 60,
            alignment: pw.Alignment.center,
            decoration: const pw.BoxDecoration(color: _Tinta.fondoFoto),
            child: foto == null
                ? pw.Text('Sin foto',
                    textAlign: pw.TextAlign.center,
                    style: const pw.TextStyle(fontSize: 6.5, color: _Tinta.gris))
                : pw.Image(pw.MemoryImage(foto), fit: pw.BoxFit.cover,
                    width: 60, height: 60),
          ),
          pw.SizedBox(width: 8),
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  descripcion.isEmpty ? 'Encomienda' : descripcion,
                  maxLines: 1,
                  overflow: pw.TextOverflow.clip,
                  style: pw.TextStyle(
                      fontSize: 8.5, fontWeight: pw.FontWeight.bold, color: _Tinta.grafito),
                ),
                pw.SizedBox(height: 2),
                pw.Text('Retiró: ${e.quienRetiro}',
                    maxLines: 1,
                    overflow: pw.TextOverflow.clip,
                    style: const pw.TextStyle(fontSize: 7.5, color: _Tinta.grafito)),
                if (e.unidad != null)
                  pw.Text(e.unidad!,
                      style: const pw.TextStyle(fontSize: 7, color: _Tinta.gris)),
                pw.SizedBox(height: 2),
                pw.Text(Formato.fechaYHora(e.entregadoEn),
                    style: const pw.TextStyle(fontSize: 7, color: _Tinta.gris)),
                if (e.guardiaEntrega != null)
                  pw.Text('Entregó: ${e.guardiaEntrega}',
                      style: const pw.TextStyle(fontSize: 7, color: _Tinta.gris)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================================================
  // PIEZAS SUELTAS
  // ==========================================================================

  static pw.Widget _titulo(String texto) => pw.Text(
        texto.toUpperCase(),
        style: pw.TextStyle(
          fontSize: 9,
          fontWeight: pw.FontWeight.bold,
          letterSpacing: 1.4,
          color: _Tinta.grafito,
        ),
      );

  static pw.Widget _pie(pw.Context ctx) => pw.Padding(
        padding: const pw.EdgeInsets.only(top: 10),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Divider(color: _Tinta.grisClaro, thickness: 0.5),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  'Generado el ${Formato.fechaYHora(DateTime.now())} · '
                  'Tomass Seguridad Privada',
                  style: const pw.TextStyle(fontSize: 7, color: _Tinta.gris),
                ),
                pw.Text('Hoja ${ctx.pageNumber} de ${ctx.pagesCount}',
                    style: const pw.TextStyle(fontSize: 7, color: _Tinta.gris)),
              ],
            ),
          ],
        ),
      );

  /// El escudo de la empresa. Si no está, el informe sale igual sin él.
  static Future<Uint8List?> _leerEscudo() async {
    try {
      final datos = await rootBundle.load('assets/imagenes/logo.png');
      return datos.buffer.asUint8List();
    } catch (_) {
      return null;
    }
  }
}
