// ============================================================================
// Tomass Seguridad — El informe de rondas en PDF
// ============================================================================
// ES EL DOCUMENTO QUE SE LE ENTREGA AL CLIENTE.
//
// Hoy un condominio le paga por rondas nocturnas y no tiene forma de saber si se
// hicieron. Esto es la prueba: a qué hora se recorrió cada sector, y que el
// guardia estaba ahí cuando lo marcó.
//
// ============================================================================
// POR QUÉ EL PLANO ES UN DIBUJO Y NO UN MAPA DE CALLES
// ============================================================================
//
// Un mapa con calles (tipo Google Maps) tiene tres problemas concretos:
//
//   1. Necesita internet EN EL MOMENTO de armar el informe. El administrador lo
//      va a sacar parado en la instalación, muchas veces con mala señal.
//   2. Necesita una cuenta paga con Google o Mapbox, con una llave que hay que
//      renovar y que se puede vencer sin aviso.
//   3. Se cobra por cada mapa generado.
//
// Y sobre todo: no agrega nada. Todos los sectores están dentro de la misma
// propiedad, a doscientos metros unos de otros. Las calles de alrededor no son
// lo que se quiere demostrar.
//
// Lo que sí importa —y es lo que este plano muestra— es DÓNDE ESTABA EL GUARDIA
// respecto de cada cartel. Un punto pegado al sector prueba que estuvo ahí; un
// punto a 400 metros prueba lo contrario. Eso se ve igual de claro en un dibujo
// con escala en metros, funciona sin internet y no cuesta nada.
//
// Si algún día un cliente pide el mapa de calles, se puede agregar: es una
// decisión de costo, no técnica.
// ============================================================================

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../modelos/admin.dart';
import '../nucleo/formato.dart';

/// Los colores de la marca, en el formato que entiende el PDF.
class _Tinta {
  // Paleta Merlyn: azul marino corporativo + dorado.
  static const grafito = PdfColor.fromInt(0xFF0D2B5E);
  static const dorado = PdfColor.fromInt(0xFFC9A24E);
  static const gris = PdfColor.fromInt(0xFF6B7280);
  static const grisClaro = PdfColor.fromInt(0xFFE5E7EB);
  static const verde = PdfColor.fromInt(0xFF27AE60);
  static const naranja = PdfColor.fromInt(0xFFF39C12);
  static const rojo = PdfColor.fromInt(0xFFE74C3C);
  static const blanco = PdfColor.fromInt(0xFFFFFFFF);
}

class InformeDeRondasPdf {
  /// Arma el PDF y lo devuelve listo para compartir, imprimir o guardar.
  static Future<Uint8List> armar({
    required String instalacion,
    required int dias,
    required List<RondaDelInforme> rondas,
    required List<MarcaDelInforme> marcas,
    required List<SectorDelPlano> sectores,
    required int minutosEntreRondas,
  }) async {
    final doc = pw.Document(
      title: 'Informe de rondas — $instalacion',
      author: 'Tomass Seguridad Privada',
    );

    // Las fuentes del DIBUJO (no las de los textos comunes). Se crean acá
    // porque hacen falta el documento, y dentro del dibujo no se puede llegar
    // a él.
    final normal = PdfFont.helvetica(doc.document);
    final negrita = PdfFont.helveticaBold(doc.document);

    final escudo = await _leerEscudo();
    final hasta = DateTime.now();
    final desde = hasta.subtract(Duration(days: dias));

    // ---- Hoja 1: el resumen ----
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (ctx) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            _encabezado(escudo, instalacion, desde, hasta),
            pw.SizedBox(height: 22),
            _resumen(rondas, marcas, sectores, minutosEntreRondas),
            pw.SizedBox(height: 20),
            pw.Expanded(child: _tablaDeRondas(rondas)),
            _pie(),
          ],
        ),
      ),
    );

    // ---- Hoja 2: el plano ----
    final conUbicacion = sectores.where((s) => s.tieneUbicacion).toList();
    if (conUbicacion.isNotEmpty) {
      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(32),
          build: (ctx) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              _titulo('Dónde se hicieron las marcaciones'),
              pw.SizedBox(height: 4),
              pw.Text(
                'Cada círculo es un sector con su cartel. Cada punto es una '
                'marcación del guardia, en el lugar exacto donde estaba su '
                'teléfono al escanear.',
                style: const pw.TextStyle(fontSize: 9.5, color: _Tinta.gris),
              ),
              pw.SizedBox(height: 14),
              pw.Expanded(
                  child: _plano(conUbicacion, marcas, normal, negrita)),
              pw.SizedBox(height: 12),
              _leyendaDelPlano(),
              _pie(),
            ],
          ),
        ),
      );
    }

    // ---- Hojas siguientes: el detalle con horarios ----
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        header: (ctx) => ctx.pageNumber == 1
            ? pw.SizedBox()
            : pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 12),
                child: pw.Text('Detalle de las rondas — $instalacion',
                    style: const pw.TextStyle(fontSize: 9, color: _Tinta.gris)),
              ),
        footer: (ctx) => _pieConPagina(ctx),
        build: (ctx) => [
          _titulo('Detalle de cada ronda, con horarios'),
          pw.SizedBox(height: 4),
          pw.Text(
            'La hora de cada marcación es la que registró el teléfono al '
            'escanear el cartel del sector. Estos registros no se pueden '
            'modificar ni borrar.',
            style: const pw.TextStyle(fontSize: 9.5, color: _Tinta.gris),
          ),
          pw.SizedBox(height: 16),
          ..._detallePorRonda(rondas, marcas, sectores.length),
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
                pw.Text('INFORME DE RONDAS',
                    style: const pw.TextStyle(
                        fontSize: 8, color: _Tinta.grisClaro, letterSpacing: 2)),
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
  // EL RESUMEN: lo que el cliente lee primero
  // ==========================================================================

  static pw.Widget _resumen(
    List<RondaDelInforme> rondas,
    List<MarcaDelInforme> marcas,
    List<SectorDelPlano> sectores,
    int minutosEntreRondas,
  ) {
    final completas = rondas.where((r) => r.completa).length;
    final fueraDeHora = rondas.where((r) => r.sePasoDelLimite).length;
    final lejanas = marcas.where((m) => m.lejos).length;
    final horas = (minutosEntreRondas / 60).toStringAsFixed(
        minutosEntreRondas % 60 == 0 ? 0 : 1);

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _titulo('Resumen del período'),
        pw.SizedBox(height: 10),
        pw.Row(
          children: [
            _cuadro('${rondas.length}', 'rondas hechas'),
            pw.SizedBox(width: 8),
            _cuadro('$completas', 'con todos los\nsectores'),
            pw.SizedBox(width: 8),
            _cuadro('${marcas.length}', 'marcaciones'),
            pw.SizedBox(width: 8),
            _cuadro(
              '$fueraDeHora',
              'pasaron las\n$horas horas',
              tinta: fueraDeHora > 0 ? _Tinta.naranja : _Tinta.verde,
            ),
          ],
        ),
        if (lejanas > 0) ...[
          pw.SizedBox(height: 12),
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(
              color: const PdfColor.fromInt(0xFFFDF3E7),
              border: pw.Border.all(color: _Tinta.naranja, width: 0.8),
            ),
            child: pw.Text(
              '$lejanas ${lejanas == 1 ? "marcación se hizo" : "marcaciones se hicieron"} '
              'a más distancia del cartel de lo esperado. Puede deberse a mala '
              'señal de GPS bajo techo: conviene revisar el plano de la hoja '
              'siguiente antes de sacar conclusiones.',
              style: const pw.TextStyle(fontSize: 9, lineSpacing: 2),
            ),
          ),
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
  // TABLA DE RONDAS
  // ==========================================================================

  static pw.Widget _tablaDeRondas(List<RondaDelInforme> rondas) {
    if (rondas.isEmpty) {
      return pw.Center(
        child: pw.Text('No hubo rondas en este período.',
            style: const pw.TextStyle(fontSize: 11, color: _Tinta.gris)),
      );
    }

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _titulo('Las rondas, una por una'),
        pw.SizedBox(height: 8),
        pw.Table(
          border: pw.TableBorder.all(color: _Tinta.grisClaro, width: 0.5),
          columnWidths: const {
            0: pw.FlexColumnWidth(1.5),
            1: pw.FlexColumnWidth(2.4),
            2: pw.FlexColumnWidth(1.5),
            3: pw.FlexColumnWidth(1.1),
            4: pw.FlexColumnWidth(1.3),
          },
          children: [
            pw.TableRow(
              decoration: const pw.BoxDecoration(color: _Tinta.grafito),
              children: [
                _celdaTitulo('Día y hora'),
                _celdaTitulo('Guardia'),
                _celdaTitulo('Sectores'),
                _celdaTitulo('Duró'),
                _celdaTitulo('Desde la\nanterior'),
              ],
            ),
            for (final r in rondas.take(24))
              pw.TableRow(
                children: [
                  _celda('${Formato.diaYMes(r.inicio)}  ${Formato.hora(r.inicio)}'),
                  _celda(r.guardia),
                  _celda('${r.marcados} de ${r.total}',
                      tinta: r.completa ? _Tinta.verde : _Tinta.naranja),
                  _celda(r.sigueAbierta ? 'en curso' : '${r.minutos} min'),
                  _celda(
                    r.horasDesdeLaAnterior == null
                        ? '—'
                        : '${r.horasDesdeLaAnterior} h',
                    tinta: r.sePasoDelLimite ? _Tinta.rojo : _Tinta.gris,
                  ),
                ],
              ),
          ],
        ),
        if (rondas.length > 24)
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 6),
            child: pw.Text(
              'Se muestran las 24 más recientes de ${rondas.length}. '
              'El detalle completo está en las hojas siguientes.',
              style: const pw.TextStyle(fontSize: 8, color: _Tinta.gris),
            ),
          ),
      ],
    );
  }

  // ==========================================================================
  // EL PLANO
  // ==========================================================================
  // Se dibuja con las coordenadas reales, proyectadas a metros. A esta escala
  // (una propiedad, no una ciudad) la curvatura de la Tierra no se nota, así que
  // alcanza con la cuenta simple y no hace falta ninguna librería de mapas.
  // ==========================================================================

  static pw.Widget _plano(
    List<SectorDelPlano> sectores,
    List<MarcaDelInforme> marcas,
    PdfFont normal,
    PdfFont negrita,
  ) {
    // El centro del plano: el promedio de los sectores
    final latCentro =
        sectores.map((s) => s.latitud!).reduce((a, b) => a + b) / sectores.length;
    final lngCentro =
        sectores.map((s) => s.longitud!).reduce((a, b) => a + b) / sectores.length;

    // Cuántos metros hay por grado, en esta latitud
    const metrosPorGradoLat = 110540.0;
    final metrosPorGradoLng = 111320.0 * math.cos(latCentro * math.pi / 180);

    (double, double) aMetros(double lat, double lng) => (
          (lng - lngCentro) * metrosPorGradoLng,
          -(lat - latCentro) * metrosPorGradoLat, // el norte va hacia arriba
        );

    // Todo lo que hay que mostrar, para calcular la escala
    final puntos = <(double, double)>[
      for (final s in sectores) aMetros(s.latitud!, s.longitud!),
      for (final m in marcas)
        if (m.marcaLat != null) aMetros(m.marcaLat!, m.marcaLng!),
    ];

    var maxDistancia = 30.0; // mínimo, para que no se vea vacío
    for (final (x, y) in puntos) {
      maxDistancia = math.max(maxDistancia, math.max(x.abs(), y.abs()));
    }
    final radioMetros = maxDistancia * 1.25;

    return pw.CustomPaint(
      size: const PdfPoint(480, 420),
      painter: (canvas, size) {
        final lado = math.min(size.x, size.y);
        final cx = size.x / 2;
        final cy = size.y / 2;
        final escala = (lado / 2) / radioMetros; // puntos de PDF por metro

        double px(double metrosX) => cx + metrosX * escala;
        double py(double metrosY) => cy - metrosY * escala;

        // ---- El marco ----
        canvas
          ..setStrokeColor(_Tinta.grisClaro)
          ..setLineWidth(0.8)
          ..drawRect(0, 0, size.x, size.y)
          ..strokePath();

        // ---- La cuadrícula, cada 25 metros ----
        canvas
          ..setStrokeColor(const PdfColor.fromInt(0xFFF0F1F3))
          ..setLineWidth(0.4);
        for (var m = 25.0; m < radioMetros; m += 25) {
          final r = m * escala;
          canvas.drawEllipse(cx, cy, r, r);
        }
        canvas.strokePath();

        // ---- Cada sector con su círculo de tolerancia ----
        for (final s in sectores) {
          final (mx, my) = aMetros(s.latitud!, s.longitud!);
          final x = px(mx);
          final y = py(my);
          final rTol = s.tolerancia * escala;

          // La tolerancia: hasta acá se considera "estuvo ahí"
          canvas
            ..setStrokeColor(const PdfColor.fromInt(0xFFBBBDC2))
            ..setLineWidth(0.5)
            ..drawEllipse(x, y, rTol, rTol)
            ..strokePath();

          // El cartel
          canvas
            ..setFillColor(_Tinta.grafito)
            ..drawEllipse(x, y, 7, 7)
            ..fillPath();

          canvas
            ..setFillColor(_Tinta.blanco)
            ..drawString(
              negrita,
              7,
              '${s.orden}',
              x - (s.orden > 9 ? 4 : 2),
              y - 2.5,
            );
        }

        // ---- Cada marcación ----
        for (final m in marcas) {
          if (m.marcaLat == null) continue;
          final (mx, my) = aMetros(m.marcaLat!, m.marcaLng!);
          canvas
            ..setFillColor(m.lejos ? _Tinta.rojo : _Tinta.verde)
            ..drawEllipse(px(mx), py(my), 2.6, 2.6)
            ..fillPath();
        }

        // ---- La escala, abajo a la derecha ----
        final largoBarra = 50 * escala;
        final xBarra = size.x - largoBarra - 18;
        const yBarra = 20.0;
        canvas
          ..setStrokeColor(_Tinta.grafito)
          ..setLineWidth(1.2)
          ..moveTo(xBarra, yBarra)
          ..lineTo(xBarra + largoBarra, yBarra)
          ..moveTo(xBarra, yBarra - 3)
          ..lineTo(xBarra, yBarra + 3)
          ..moveTo(xBarra + largoBarra, yBarra - 3)
          ..lineTo(xBarra + largoBarra, yBarra + 3)
          ..strokePath();
        canvas
          ..setFillColor(_Tinta.grafito)
          ..drawString(normal, 8, '50 metros', xBarra + 4, yBarra + 6);

        // ---- El norte ----
        canvas
          ..setFillColor(_Tinta.gris)
          ..drawString(negrita, 9, 'N', 18, size.y - 26)
          ..drawString(normal, 12, '^', 19, size.y - 40);
      },
    );
  }

  static pw.Widget _leyendaDelPlano() {
    return pw.Container(
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(border: pw.Border.all(color: _Tinta.grisClaro)),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            children: [
              _muestra(_Tinta.grafito, 'Sector con su cartel (el número es el orden)'),
              pw.SizedBox(width: 18),
              _muestra(_Tinta.verde, 'Marcación hecha en el lugar'),
              pw.SizedBox(width: 18),
              _muestra(_Tinta.rojo, 'Marcación hecha desde lejos'),
            ],
          ),
          pw.SizedBox(height: 7),
          pw.Text(
            'El círculo gris alrededor de cada sector es la distancia que se '
            'considera aceptable. El GPS de un teléfono puede errarle varios '
            'metros bajo techo o entre paredes gruesas, así que un punto rojo '
            'aislado no prueba nada por sí solo: lo que importa es si se repite.',
            style: const pw.TextStyle(fontSize: 8, color: _Tinta.gris, lineSpacing: 2),
          ),
        ],
      ),
    );
  }

  static pw.Widget _muestra(PdfColor color, String texto) {
    return pw.Row(
      children: [
        pw.Container(
          width: 8,
          height: 8,
          decoration: pw.BoxDecoration(color: color, shape: pw.BoxShape.circle),
        ),
        pw.SizedBox(width: 5),
        pw.Text(texto, style: const pw.TextStyle(fontSize: 7.5)),
      ],
    );
  }

  // ==========================================================================
  // DETALLE POR RONDA, CON LOS HORARIOS
  // ==========================================================================

  static List<pw.Widget> _detallePorRonda(
    List<RondaDelInforme> rondas,
    List<MarcaDelInforme> marcas,
    int totalSectores,
  ) {
    final hojas = <pw.Widget>[];

    for (final r in rondas) {
      final suyas = marcas.where((m) => m.rondaId == r.id).toList()
        ..sort((a, b) => a.marcadoEn.compareTo(b.marcadoEn));

      hojas.add(
        pw.Container(
          margin: const pw.EdgeInsets.only(bottom: 14),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(
              color: r.hayAlgoQueMirar ? _Tinta.naranja : _Tinta.grisClaro,
              width: r.hayAlgoQueMirar ? 1 : 0.5,
            ),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // Cabecera de la ronda
              pw.Container(
                width: double.infinity,
                padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: const pw.BoxDecoration(
                    color: PdfColor.fromInt(0xFFF4F5F6)),
                child: pw.Row(
                  children: [
                    pw.Expanded(
                      child: pw.Text(
                        '${Formato.diaCompleto(r.inicio)} · ${Formato.hora(r.inicio)}'
                        '${r.cerradaEn == null ? "" : " a ${Formato.hora(r.cerradaEn!)}"}',
                        style: pw.TextStyle(
                            fontSize: 10, fontWeight: pw.FontWeight.bold),
                      ),
                    ),
                    pw.Text(r.guardia,
                        style: const pw.TextStyle(fontSize: 9.5, color: _Tinta.gris)),
                  ],
                ),
              ),

              // Los sectores con su hora
              pw.Padding(
                padding: const pw.EdgeInsets.all(10),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Table(
                      columnWidths: const {
                        0: pw.FlexColumnWidth(0.6),
                        1: pw.FlexColumnWidth(4),
                        2: pw.FlexColumnWidth(1.2),
                        3: pw.FlexColumnWidth(1.6),
                      },
                      children: [
                        for (final m in suyas)
                          pw.TableRow(
                            children: [
                              _celdaChica('${m.sectorOrden}'),
                              _celdaChica(m.sector),
                              _celdaChica(Formato.hora(m.marcadoEn)),
                              _celdaChica(
                                m.metrosDeLejos == null
                                    ? 'sin GPS'
                                    : 'a ${m.metrosDeLejos!.round()} m',
                                tinta: m.lejos
                                    ? _Tinta.rojo
                                    : (m.metrosDeLejos == null
                                        ? _Tinta.gris
                                        : _Tinta.verde),
                              ),
                            ],
                          ),
                      ],
                    ),
                    if (suyas.length < totalSectores) ...[
                      pw.SizedBox(height: 6),
                      pw.Text(
                        'Quedaron ${totalSectores - suyas.length} '
                        '${totalSectores - suyas.length == 1 ? "sector" : "sectores"} '
                        'sin marcar en esta ronda.',
                        style: pw.TextStyle(
                            fontSize: 8.5,
                            color: _Tinta.naranja,
                            fontWeight: pw.FontWeight.bold),
                      ),
                    ],
                    if (r.sePasoDelLimite) ...[
                      pw.SizedBox(height: 4),
                      pw.Text(
                        'Pasaron ${r.horasDesdeLaAnterior} horas desde la ronda '
                        'anterior.',
                        style: pw.TextStyle(
                            fontSize: 8.5,
                            color: _Tinta.rojo,
                            fontWeight: pw.FontWeight.bold),
                      ),
                    ],
                    if (r.notas != null && r.notas!.isNotEmpty) ...[
                      pw.SizedBox(height: 6),
                      pw.Text('Novedad anotada: ${r.notas}',
                          style: const pw.TextStyle(fontSize: 8.5, lineSpacing: 2)),
                    ],
                    for (final m in suyas.where(
                        (m) => m.novedad != null && m.novedad!.isNotEmpty))
                      pw.Padding(
                        padding: const pw.EdgeInsets.only(top: 3),
                        child: pw.Text('${m.sector}: ${m.novedad}',
                            style:
                                const pw.TextStyle(fontSize: 8.5, lineSpacing: 2)),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (hojas.isEmpty) {
      hojas.add(pw.Text('No hubo rondas en este período.',
          style: const pw.TextStyle(fontSize: 11, color: _Tinta.gris)));
    }

    return hojas;
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

  static pw.Widget _celdaTitulo(String texto) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
        child: pw.Text(texto,
            style: pw.TextStyle(
                fontSize: 7.5,
                fontWeight: pw.FontWeight.bold,
                color: _Tinta.blanco)),
      );

  static pw.Widget _celda(String texto, {PdfColor tinta = _Tinta.grafito}) =>
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: pw.Text(texto,
            style: pw.TextStyle(fontSize: 8.5, color: tinta)),
      );

  static pw.Widget _celdaChica(String texto, {PdfColor tinta = _Tinta.grafito}) =>
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 2),
        child: pw.Text(texto, style: pw.TextStyle(fontSize: 8.5, color: tinta)),
      );

  /// La nota del pie. Es lo que le da peso al documento frente al cliente.
  static pw.Widget _pie() => pw.Padding(
        padding: const pw.EdgeInsets.only(top: 10),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Divider(color: _Tinta.grisClaro, thickness: 0.5),
            pw.Text(
              'Generado el ${Formato.fechaYHora(DateTime.now())} · '
              'Tomass Seguridad Privada',
              style: const pw.TextStyle(fontSize: 7, color: _Tinta.gris),
            ),
            pw.Text(
              'Los registros de marcación no se pueden modificar ni borrar: la '
              'base de datos lo impide. Por eso sirven como respaldo.',
              style: const pw.TextStyle(fontSize: 7, color: _Tinta.gris),
            ),
          ],
        ),
      );

  static pw.Widget _pieConPagina(pw.Context ctx) => pw.Padding(
        padding: const pw.EdgeInsets.only(top: 10),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text('Tomass Seguridad Privada',
                style: const pw.TextStyle(fontSize: 7, color: _Tinta.gris)),
            pw.Text('Hoja ${ctx.pageNumber} de ${ctx.pagesCount}',
                style: const pw.TextStyle(fontSize: 7, color: _Tinta.gris)),
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
