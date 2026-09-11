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
import 'servicio_mapa_estatico.dart';

/// Los colores de la marca, en el formato que entiende el PDF.
class _Tinta {
  // Paleta Merlyn: azul marino corporativo.
  static const grafito = PdfColor.fromInt(0xFF0D2B5E);
  static const gris = PdfColor.fromInt(0xFF6B7280);
  static const grisClaro = PdfColor.fromInt(0xFFE5E7EB);
  static const verde = PdfColor.fromInt(0xFF27AE60);
  static const naranja = PdfColor.fromInt(0xFFF39C12);
  static const rojo = PdfColor.fromInt(0xFFE74C3C);
  static const blanco = PdfColor.fromInt(0xFFFFFFFF);
}

/// Comparación con el período anterior. Sirve para poner en la portada
/// "23 rondas · ↓ 12% vs período anterior". Si es null, el PDF sale sin
/// esa columna.
class ComparacionRondas {
  const ComparacionRondas({
    required this.rondasAnteriores,
    required this.marcasAnteriores,
    required this.diasAnteriores,
  });

  final List<RondaDelInforme> rondasAnteriores;
  final List<MarcaDelInforme> marcasAnteriores;
  final int diasAnteriores;
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
    ComparacionRondas? comparacion,
    String? nombreAdmin,
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

    // Mapa real con calles (Geoapify) para acompañar al plano dibujado
    // de la hoja 2. Marcadores: los sectores con su número, y las marcas
    // del guardia en verde (si estuvo cerca) o rojo (si estuvo lejos).
    // Si Geoapify no responde, mapaBytes queda null y la hoja 2 sólo
    // muestra el plano CustomPaint.
    Uint8List? mapaBytes;
    final sectoresConUbicacion =
        sectores.where((s) => s.tieneUbicacion).toList();
    if (sectoresConUbicacion.isNotEmpty) {
      mapaBytes = await ServicioMapaEstatico.conRecorrido(
        puntos: [
          for (final s in sectoresConUbicacion)
            (lat: s.latitud!, lng: s.longitud!, numero: s.orden),
        ],
        ancho: 900,
        alto: 550,
      );
    }

    // ---- Hoja 1: el resumen ----
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (ctx) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            _encabezado(escudo, instalacion, desde, hasta),
            pw.SizedBox(height: 18),
            _puntosDestacados(rondas, marcas, minutosEntreRondas, comparacion),
            pw.SizedBox(height: 14),
            _resumen(rondas, marcas, sectores, minutosEntreRondas, comparacion),
            pw.SizedBox(height: 18),
            pw.Expanded(child: _tablaDeRondas(rondas)),
            _firmaAlPie(nombreAdmin),
            _pie(),
          ],
        ),
      ),
    );

    // ---- Hoja 2: el mapa real (Geoapify) + el plano dibujado ----
    // El mapa real de arriba ubica al cliente en su barrio: reconoce las
    // calles, las manzanas y hasta el techo del edificio. El plano de
    // abajo es más analítico: círculos de tolerancia y marcas OK/lejanas.
    if (sectoresConUbicacion.isNotEmpty) {
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
              pw.SizedBox(height: 10),
              if (mapaBytes != null) ...[
                pw.ClipRRect(
                  horizontalRadius: 4,
                  verticalRadius: 4,
                  child: pw.Image(
                    pw.MemoryImage(mapaBytes),
                    width: double.infinity,
                    height: 220,
                    fit: pw.BoxFit.cover,
                  ),
                ),
                pw.SizedBox(height: 10),
              ],
              pw.Expanded(
                  child: _plano(
                      sectoresConUbicacion, marcas, normal, negrita)),
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
    // Nueva portada: hero de dos capas. Arriba una banda dorada finita
    // (identidad Tomass), y debajo la banda grande grafito con logo grande
    // + nombre del cliente destacado. Sirve para que el mandante reciba el
    // PDF y lo primero que vea sea "Milagros del Cerro Grande" en gran
    // tipografía, no "TOMASS SEGURIDAD".
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        // Banda dorada arriba (identidad)
        pw.Container(
          height: 4,
          color: const PdfColor.fromInt(0xFFC9A24E),
        ),
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 20, vertical: 20),
          decoration: const pw.BoxDecoration(color: _Tinta.grafito),
          child: pw.Row(
            children: [
              if (escudo != null)
                pw.Container(
                  width: 48,
                  height: 56,
                  child: pw.Image(pw.MemoryImage(escudo), fit: pw.BoxFit.contain),
                ),
              pw.SizedBox(width: 16),
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    // Kicker chico arriba con el nombre de la empresa
                    pw.Row(
                      children: [
                        pw.Text('TOMASS SEGURIDAD',
                            style: pw.TextStyle(
                              fontSize: 11,
                              fontWeight: pw.FontWeight.bold,
                              color: _Tinta.blanco,
                              letterSpacing: 1.4,
                            )),
                        pw.SizedBox(width: 8),
                        pw.Container(
                          padding: const pw.EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: pw.BoxDecoration(
                            color: const PdfColor.fromInt(0xFFC9A24E),
                          ),
                          child: pw.Text('INFORME DE RONDAS',
                              style: pw.TextStyle(
                                fontSize: 7.5,
                                color: _Tinta.grafito,
                                letterSpacing: 1.8,
                                fontWeight: pw.FontWeight.bold,
                              )),
                        ),
                      ],
                    ),
                    pw.SizedBox(height: 10),
                    // Nombre del cliente destacado — el nombre del condominio
                    // es lo que el mandante va a ver primero al abrir el PDF.
                    pw.Text(instalacion,
                        style: pw.TextStyle(
                          fontSize: 20,
                          fontWeight: pw.FontWeight.bold,
                          color: _Tinta.blanco,
                          letterSpacing: 0.3,
                        )),
                    pw.SizedBox(height: 4),
                    pw.Text(
                      'Período: del ${Formato.fecha(desde)} al ${Formato.fecha(hasta)}',
                      style: const pw.TextStyle(
                          fontSize: 10, color: _Tinta.grisClaro),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
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
    ComparacionRondas? comp,
  ) {
    final completas = rondas.where((r) => r.completa).length;
    final fueraDeHora = rondas.where((r) => r.sePasoDelLimite).length;
    final lejanas = marcas.where((m) => m.lejos).length;
    final horas = (minutosEntreRondas / 60).toStringAsFixed(
        minutosEntreRondas % 60 == 0 ? 0 : 1);

    // Números del período anterior para la comparación
    final rondasAnt = comp?.rondasAnteriores.length;
    final completasAnt =
        comp?.rondasAnteriores.where((r) => r.completa).length;
    final marcasAnt = comp?.marcasAnteriores.length;
    final fueraDeHoraAnt =
        comp?.rondasAnteriores.where((r) => r.sePasoDelLimite).length;

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _titulo('Resumen del período'),
        pw.SizedBox(height: 10),
        pw.Row(
          children: [
            _cuadro('${rondas.length}', 'rondas hechas',
                anterior: rondasAnt, mejorSiSube: true),
            pw.SizedBox(width: 8),
            _cuadro('$completas', 'con todos los\nsectores',
                anterior: completasAnt, mejorSiSube: true),
            pw.SizedBox(width: 8),
            _cuadro('${marcas.length}', 'marcaciones',
                anterior: marcasAnt, mejorSiSube: true),
            pw.SizedBox(width: 8),
            _cuadro(
              '$fueraDeHora',
              'pasaron las\n$horas horas',
              tinta: fueraDeHora > 0 ? _Tinta.naranja : _Tinta.verde,
              anterior: fueraDeHoraAnt,
              mejorSiSube: false,
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

  /// Un cuadro de KPI con opción de mostrar comparación con el período
  /// anterior debajo del número. La flecha indica dirección: verde si va
  /// en el sentido "bueno" (más rondas es bueno, más fuera de hora es
  /// malo — se controla con [mejorSiSube]).
  static pw.Widget _cuadro(
    String numero,
    String etiqueta, {
    PdfColor tinta = _Tinta.grafito,
    int? anterior,
    bool mejorSiSube = true,
  }) {
    // Cálculo de la comparación
    String? comparacion;
    PdfColor? colorComp;
    if (anterior != null) {
      final actual = int.tryParse(numero) ?? 0;
      final delta = actual - anterior;
      if (anterior == 0 && actual == 0) {
        comparacion = 'sin cambio';
        colorComp = _Tinta.gris;
      } else if (anterior == 0) {
        comparacion = 'nuevo';
        colorComp = mejorSiSube ? _Tinta.verde : _Tinta.rojo;
      } else {
        final pct = (delta / anterior * 100).round().abs();
        final flecha = delta > 0 ? '↑' : (delta < 0 ? '↓' : '=');
        final subeBien = (delta > 0 && mejorSiSube) ||
            (delta < 0 && !mejorSiSube);
        comparacion = delta == 0 ? '= sin cambio' : '$flecha $pct% vs anterior';
        colorComp = delta == 0
            ? _Tinta.gris
            : (subeBien ? _Tinta.verde : _Tinta.naranja);
      }
    }

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
            if (comparacion != null) ...[
              pw.SizedBox(height: 3),
              pw.Text(comparacion,
                  style: pw.TextStyle(
                    fontSize: 7,
                    color: colorComp,
                    fontWeight: pw.FontWeight.bold,
                  )),
            ],
          ],
        ),
      ),
    );
  }

  // ==========================================================================
  // PUNTOS A DESTACAR
  // ==========================================================================
  // Arriba del resumen numérico, 3-4 bullets que convierten los datos en
  // insight ejecutivo. Es lo que hace que el mandante mire el informe y
  // sepa QUÉ le importa sin tener que interpretar tablas.
  // ==========================================================================

  static pw.Widget _puntosDestacados(
    List<RondaDelInforme> rondas,
    List<MarcaDelInforme> marcas,
    int minutosEntreRondas,
    ComparacionRondas? comp,
  ) {
    final completas = rondas.where((r) => r.completa).length;
    final fueraDeHora = rondas.where((r) => r.sePasoDelLimite).length;
    final lejanas = marcas.where((m) => m.lejos).length;

    // Cada punto tiene: bool esBueno (para el ✓ verde vs ⚠ naranja) y texto.
    final puntos = <({bool bueno, String texto})>[];

    if (rondas.isEmpty) {
      puntos.add((
        bueno: false,
        texto: 'No se registraron rondas en el período. Conviene revisar '
            'con el equipo de guardia qué pasó.'
      ));
    } else if (completas == rondas.length && rondas.length > 1) {
      puntos.add((
        bueno: true,
        texto: 'Las ${rondas.length} rondas del período cubrieron todos los '
            'sectores. El recorrido se cumplió íntegramente.'
      ));
    } else if (completas > 0) {
      final pct = (completas / rondas.length * 100).round();
      puntos.add((
        bueno: completas == rondas.length,
        texto: '$completas de ${rondas.length} rondas cubrieron todos los '
            'sectores ($pct%).'
      ));
    }

    if (fueraDeHora > 0) {
      final horas = (minutosEntreRondas / 60).toStringAsFixed(
          minutosEntreRondas % 60 == 0 ? 0 : 1);
      puntos.add((
        bueno: false,
        texto: '$fueraDeHora ${fueraDeHora == 1 ? "ronda superó" : "rondas superaron"} '
            'las $horas horas que exige el contrato de trabajo.'
      ));
    } else if (rondas.length > 1) {
      puntos.add((
        bueno: true,
        texto: 'Ninguna ronda se pasó del intervalo máximo entre rondas.'
      ));
    }

    if (lejanas > 0) {
      puntos.add((
        bueno: false,
        texto: '$lejanas ${lejanas == 1 ? "marcación GPS quedó" : "marcaciones GPS quedaron"} '
            'lejos del cartel. Puede ser mala señal — el plano de la hoja '
            'siguiente lo muestra en detalle.'
      ));
    }

    // Comparación con el período anterior
    if (comp != null && comp.rondasAnteriores.isNotEmpty) {
      final rondasAnt = comp.rondasAnteriores.length;
      final delta = rondas.length - rondasAnt;
      if (delta != 0) {
        final direccion = delta > 0 ? 'más' : 'menos';
        final abs = delta.abs();
        puntos.add((
          bueno: delta >= 0,
          texto: '$abs ${abs == 1 ? "ronda" : "rondas"} $direccion que el período '
              'anterior (${rondas.length} vs $rondasAnt).'
        ));
      }
    }

    if (puntos.isEmpty) return pw.SizedBox();

    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        color: const PdfColor.fromInt(0xFFF4F7FB),
        border: pw.Border(
          left: pw.BorderSide(color: _Tinta.grafito, width: 3),
        ),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text('PUNTOS A DESTACAR',
              style: pw.TextStyle(
                fontSize: 9,
                fontWeight: pw.FontWeight.bold,
                color: _Tinta.grafito,
                letterSpacing: 1.4,
              )),
          pw.SizedBox(height: 8),
          for (final p in puntos.take(4)) ...[
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Container(
                  width: 12,
                  padding: const pw.EdgeInsets.only(top: 1),
                  child: pw.Text(
                    p.bueno ? '✓' : '⚠',
                    style: pw.TextStyle(
                      fontSize: 10.5,
                      color: p.bueno ? _Tinta.verde : _Tinta.naranja,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ),
                pw.SizedBox(width: 6),
                pw.Expanded(
                  child: pw.Text(
                    p.texto,
                    style: const pw.TextStyle(
                        fontSize: 9.5, lineSpacing: 2, color: _Tinta.grafito),
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 5),
          ],
        ],
      ),
    );
  }

  // ==========================================================================
  // FIRMA AL PIE
  // ==========================================================================
  // Cierre del informe con la clásica "elaborado por / recibido conforme".
  // Es lo que hace que el mandante lo firme y lo archive como constancia.
  // ==========================================================================

  static pw.Widget _firmaAlPie(String? nombreAdmin) {
    final quien = nombreAdmin ?? 'Tomass Seguridad Privada';
    return pw.Padding(
      padding: const pw.EdgeInsets.only(top: 14),
      child: pw.Row(
        children: [
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Container(
                  height: 34,
                  decoration: const pw.BoxDecoration(
                    border: pw.Border(
                      bottom: pw.BorderSide(color: _Tinta.grisClaro, width: 0.6),
                    ),
                  ),
                ),
                pw.SizedBox(height: 3),
                pw.Text('ELABORADO POR',
                    style: pw.TextStyle(
                      fontSize: 7,
                      color: _Tinta.gris,
                      letterSpacing: 1.2,
                      fontWeight: pw.FontWeight.bold,
                    )),
                pw.Text(quien,
                    style: pw.TextStyle(
                      fontSize: 9,
                      color: _Tinta.grafito,
                      fontWeight: pw.FontWeight.bold,
                    )),
              ],
            ),
          ),
          pw.SizedBox(width: 32),
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Container(
                  height: 34,
                  decoration: const pw.BoxDecoration(
                    border: pw.Border(
                      bottom: pw.BorderSide(color: _Tinta.grisClaro, width: 0.6),
                    ),
                  ),
                ),
                pw.SizedBox(height: 3),
                pw.Text('RECIBIDO CONFORME',
                    style: pw.TextStyle(
                      fontSize: 7,
                      color: _Tinta.gris,
                      letterSpacing: 1.2,
                      fontWeight: pw.FontWeight.bold,
                    )),
                pw.Text('Administración de la instalación',
                    style: const pw.TextStyle(
                      fontSize: 9,
                      color: _Tinta.grafito,
                    )),
              ],
            ),
          ),
        ],
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

    // Sectores en metros: siempre entran al cálculo de la escala.
    final sectoresMetros = [
      for (final s in sectores) aMetros(s.latitud!, s.longitud!),
    ];

    // Filtro de outliers del GPS: una marca a kilómetros del sector más
    // cercano es casi seguro un error del chip (rebote, "última posición
    // conocida" vieja, etc.). Si esas marcas entran al cálculo de la escala,
    // el plano se aplana y las marcas válidas quedan invisibles en el centro.
    // Cortamos en 500 m — más que suficiente para el peor GPS urbano.
    const toleranciaOutlierM = 500.0;
    final marcasDentro = <MarcaDelInforme>[];
    final marcasFuera = <MarcaDelInforme>[];
    for (final m in marcas) {
      if (m.marcaLat == null) continue;
      final (mx, my) = aMetros(m.marcaLat!, m.marcaLng!);
      var dMin = double.infinity;
      for (final (sx, sy) in sectoresMetros) {
        final d = math.sqrt((mx - sx) * (mx - sx) + (my - sy) * (my - sy));
        if (d < dMin) dMin = d;
      }
      if (dMin <= toleranciaOutlierM) {
        marcasDentro.add(m);
      } else {
        marcasFuera.add(m);
      }
    }

    // Para calcular la escala, sólo lo que realmente vamos a dibujar
    final puntos = <(double, double)>[
      ...sectoresMetros,
      for (final m in marcasDentro) aMetros(m.marcaLat!, m.marcaLng!),
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
        // Sólo las que están cerca de algún sector. Las outliers (GPS a
        // más de 500 m) se anotan al pie del plano en vez de dibujarlas.
        for (final m in marcasDentro) {
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

        // ---- Aviso de outliers descartados ----
        // Si algunas marcas venían con GPS defectuoso (a kilómetros del
        // sector) las omitimos del plano para que las otras se vieran. Se
        // lo contamos al lector, sin drama: se anota igual en el detalle.
        if (marcasFuera.isNotEmpty) {
          final n = marcasFuera.length;
          final texto = n == 1
              ? '1 marcación quedó fuera del plano: el GPS del teléfono la '
                  'ubicó a kilómetros del cartel. Igual figura en el detalle.'
              : '$n marcaciones quedaron fuera del plano: el GPS del '
                  'teléfono las ubicó a kilómetros del cartel. Igual figuran '
                  'en el detalle.';
          canvas
            ..setFillColor(_Tinta.gris)
            ..drawString(normal, 7.5, texto, 18, 6);
        }
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
