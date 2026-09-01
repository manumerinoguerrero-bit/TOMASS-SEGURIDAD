// ============================================================================
// Tomass Seguridad — Informe de turnos de los guardias (PDF)
// ============================================================================
// LO QUE ARMA
//
//   Un PDF con todos los turnos del período que el administrador ve en la
//   pestaña Turnos. Por cada turno:
//     - la selfie que se sacó el guardia al abrir el turno (prueba de quién
//       estaba a cargo)
//     - la hora de inicio y de fin (y la duración)
//     - la ubicación GPS (si el teléfono la pudo dar) con link a Google Maps
//     - el puesto que cubría
//     - las notas que dejó al siguiente turno
//
// POR QUÉ SIRVE
//
//   Es lo que la administradora imprime o guarda para pagar horas, para pasarle
//   al abogado si hay que discutir un incidente, o para tenerlo archivado como
//   prueba de que la seguridad estuvo cubierta.
//
// FOTOS QUE FALTAN
//
//   Si una selfie ya no existe en el servidor (se borró por antigüedad, por
//   ejemplo), esa fila queda con el marcador gris "sin foto" y el resto del
//   turno sigue apareciendo. Un PDF que se rompe entero por una foto que falta
//   deja al administrador sin nada.
// ============================================================================

import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../modelos/admin.dart';
import '../nucleo/formato.dart';
import 'servicio_fotos.dart';

abstract class _Tinta {
  static const grafito = PdfColor.fromInt(0xFF1C1E24);
  static const suave = PdfColor.fromInt(0xFF6B7280);
  static const tenue = PdfColor.fromInt(0xFF9CA3AF);
  static const linea = PdfColor.fromInt(0xFFE5E7EB);
  static const verde = PdfColor.fromInt(0xFF16A34A);
  static const naranja = PdfColor.fromInt(0xFFB45309);
}

class InformeDeTurnosPdf {
  /// Arma el PDF completo con TODOS los turnos.
  ///
  /// [servicioFotos] se usa para bajar cada selfie una por una. Puede tardar
  /// varios segundos si hay muchas fotos, por eso quien llama muestra un
  /// aviso antes.
  static Future<Uint8List> armar({
    required String instalacion,
    required List<TurnoAdmin> turnos,
    required ServicioFotos servicioFotos,
  }) async {
    // Bajamos todas las fotos en paralelo (limitando de a 6 para no saturar)
    final fotos = <String, Uint8List?>{};
    for (var i = 0; i < turnos.length; i += 6) {
      final tanda = turnos.skip(i).take(6);
      final resultados = await Future.wait(
        tanda.map((t) async {
          if (!t.tieneFoto) return MapEntry(t.id, null);
          final bytes = await servicioFotos.bytesParaPdf(
            t.fotoUrl,
            CajonDeFotos.guardias,
          );
          return MapEntry(t.id, bytes);
        }),
      );
      for (final entry in resultados) {
        fotos[entry.key] = entry.value;
      }
    }

    final pdf = pw.Document();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(30),
        header: (_) => _encabezado(instalacion, turnos),
        footer: (ctx) => pw.Padding(
          padding: const pw.EdgeInsets.only(top: 8),
          child: pw.Text(
            'Tomass Seguridad · Página ${ctx.pageNumber} de ${ctx.pagesCount}',
            style: const pw.TextStyle(fontSize: 9, color: _Tinta.tenue),
          ),
        ),
        build: (_) => turnos
            .map((t) => _tarjetaDeTurno(t, fotos[t.id]))
            .toList(),
      ),
    );

    return pdf.save();
  }

  // ==========================================================================
  // ENCABEZADO
  // ==========================================================================

  static pw.Widget _encabezado(String instalacion, List<TurnoAdmin> lista) {
    return pw.Container(
      padding: const pw.EdgeInsets.only(bottom: 14),
      margin: const pw.EdgeInsets.only(bottom: 16),
      decoration: const pw.BoxDecoration(
        border: pw.Border(
          bottom: pw.BorderSide(color: _Tinta.grafito, width: 2),
        ),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'Informe de turnos',
            style: pw.TextStyle(
              fontSize: 22,
              fontWeight: pw.FontWeight.bold,
              color: _Tinta.grafito,
            ),
          ),
          pw.SizedBox(height: 3),
          pw.Text(
            instalacion,
            style: const pw.TextStyle(
              fontSize: 12,
              color: _Tinta.suave,
            ),
          ),
          pw.SizedBox(height: 6),
          pw.Text(
            '${lista.length} ${lista.length == 1 ? "turno" : "turnos"} · '
            'generado el ${Formato.fecha(DateTime.now())} '
            'a las ${Formato.hora(DateTime.now())}',
            style: const pw.TextStyle(fontSize: 10, color: _Tinta.suave),
          ),
        ],
      ),
    );
  }

  // ==========================================================================
  // UNA TARJETA POR TURNO
  // ==========================================================================

  static pw.Widget _tarjetaDeTurno(TurnoAdmin t, Uint8List? fotoBytes) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 12),
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: _Tinta.linea, width: 1),
        borderRadius: pw.BorderRadius.circular(6),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          // ---- Selfie ----
          _foto(fotoBytes),
          pw.SizedBox(width: 12),

          // ---- Datos del turno ----
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Expanded(
                      child: pw.Text(
                        t.guardia,
                        style: pw.TextStyle(
                          fontSize: 13,
                          fontWeight: pw.FontWeight.bold,
                          color: _Tinta.grafito,
                        ),
                      ),
                    ),
                    if (t.sigueAbierto)
                      _pastilla('DE TURNO', _Tinta.verde)
                    else
                      pw.Text(
                        t.duracionEnPalabras,
                        style: pw.TextStyle(
                          fontSize: 11,
                          fontWeight: pw.FontWeight.bold,
                          color: _Tinta.suave,
                        ),
                      ),
                  ],
                ),
                pw.SizedBox(height: 4),

                _lineaDeDato(
                  'Horario',
                  '${Formato.diaCompleto(t.inicio)}  ·  '
                      '${Formato.hora(t.inicio)}'
                      '${t.cerradoEn == null ? " a AHORA" : " a ${Formato.hora(t.cerradoEn!)}"}',
                ),
                _lineaDeDato(
                  'Puesto',
                  t.puesto ?? 'Cubría todas las entradas',
                ),
                _lineaDeDato(
                  'Ubicación',
                  t.tieneUbicacion
                      ? '${t.geoLat!.toStringAsFixed(6)}, ${t.geoLng!.toStringAsFixed(6)}'
                      : 'Sin registrar (el guardia no tenía GPS al abrir turno)',
                  colorValor: t.tieneUbicacion ? _Tinta.verde : _Tinta.naranja,
                ),
                if (t.tieneUbicacion)
                  pw.UrlLink(
                    destination: 'https://www.google.com/maps/search/?api=1'
                        '&query=${t.geoLat},${t.geoLng}',
                    child: pw.Padding(
                      padding: const pw.EdgeInsets.only(top: 3, left: 62),
                      child: pw.Text(
                        'Ver en Google Maps →',
                        style: const pw.TextStyle(
                          fontSize: 9,
                          color: PdfColor.fromInt(0xFF1E6FC5),
                          decoration: pw.TextDecoration.underline,
                        ),
                      ),
                    ),
                  ),
                if (t.notas != null && t.notas!.isNotEmpty) ...[
                  pw.SizedBox(height: 6),
                  pw.Container(
                    padding: const pw.EdgeInsets.all(6),
                    decoration: pw.BoxDecoration(
                      color: const PdfColor.fromInt(0xFFF7F7F8),
                      borderRadius: pw.BorderRadius.circular(3),
                    ),
                    child: pw.RichText(
                      text: pw.TextSpan(
                        style: const pw.TextStyle(fontSize: 10),
                        children: [
                          pw.TextSpan(
                            text: 'Nota al siguiente turno: ',
                            style:
                                pw.TextStyle(fontWeight: pw.FontWeight.bold),
                          ),
                          pw.TextSpan(text: t.notas!),
                        ],
                      ),
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

  // ==========================================================================
  // Foto del guardia (o marcador si no existe)
  // ==========================================================================

  static pw.Widget _foto(Uint8List? bytes) {
    const lado = 90.0;
    if (bytes == null) {
      return pw.Container(
        width: lado,
        height: lado,
        decoration: pw.BoxDecoration(
          color: const PdfColor.fromInt(0xFFF3F4F6),
          borderRadius: pw.BorderRadius.circular(6),
          border: pw.Border.all(color: _Tinta.linea),
        ),
        alignment: pw.Alignment.center,
        child: pw.Text(
          'sin foto',
          style: const pw.TextStyle(fontSize: 8, color: _Tinta.tenue),
        ),
      );
    }
    return pw.Container(
      width: lado,
      height: lado,
      decoration: pw.BoxDecoration(
        borderRadius: pw.BorderRadius.circular(6),
        border: pw.Border.all(color: _Tinta.linea),
      ),
      child: pw.ClipRRect(
        horizontalRadius: 6,
        verticalRadius: 6,
        child: pw.Image(
          pw.MemoryImage(bytes),
          fit: pw.BoxFit.cover,
        ),
      ),
    );
  }

  // ==========================================================================
  // Una fila "Etiqueta: valor"
  // ==========================================================================

  static pw.Widget _lineaDeDato(
    String etiqueta,
    String valor, {
    PdfColor colorValor = _Tinta.grafito,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(top: 2),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(
            width: 60,
            child: pw.Text(
              etiqueta,
              style: const pw.TextStyle(fontSize: 9.5, color: _Tinta.tenue),
            ),
          ),
          pw.Expanded(
            child: pw.Text(
              valor,
              style: pw.TextStyle(
                fontSize: 10.5,
                color: colorValor,
                fontWeight: colorValor == _Tinta.verde
                    ? pw.FontWeight.bold
                    : pw.FontWeight.normal,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _pastilla(String texto, PdfColor color) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: pw.BoxDecoration(
        color: color,
        borderRadius: pw.BorderRadius.circular(3),
      ),
      child: pw.Text(
        texto,
        style: pw.TextStyle(
          fontSize: 8,
          fontWeight: pw.FontWeight.bold,
          color: PdfColors.white,
        ),
      ),
    );
  }
}
