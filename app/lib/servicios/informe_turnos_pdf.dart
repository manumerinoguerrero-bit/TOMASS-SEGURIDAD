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
  static const rojo = PdfColor.fromInt(0xFFC1272D);
}

class InformeDeTurnosPdf {
  /// Arma el PDF completo con TODOS los turnos.
  ///
  /// [servicioFotos] se usa para bajar cada selfie una por una. Puede tardar
  /// varios segundos si hay muchas fotos, por eso quien llama muestra un
  /// aviso antes.
  ///
  /// [stats] es opcional: si viene, el PDF arranca con una portada de KPIs +
  /// alertas + ranking + encomiendas pendientes. Si no viene, salta directo
  /// a la lista de turnos (comportamiento anterior, útil para retro).
  static Future<Uint8List> armar({
    required String instalacion,
    required List<TurnoAdmin> turnos,
    required ServicioFotos servicioFotos,
    EstadisticasTurnos? stats,
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
        build: (_) => [
          if (stats != null) ..._portadaStats(stats),
          ...turnos.map((t) => _tarjetaDeTurno(t, fotos[t.id])),
        ],
      ),
    );

    return pdf.save();
  }

  // ==========================================================================
  // PORTADA CON KPIs (Sprint 1)
  // ==========================================================================
  // Todo lo que va ANTES de la lista de turnos: los siete widgets que Manuel
  // pidió para que el cliente vea de un vistazo cómo estuvo el período.
  // ==========================================================================

  static List<pw.Widget> _portadaStats(EstadisticasTurnos s) {
    return [
      // ---- 1. KPIs de cumplimiento ----
      _tituloDeSeccion('Cumplimiento del período'),
      pw.Row(
        children: [
          pw.Expanded(child: _tarjetaKpi(
            '${s.kpi.pctSelfie}%',
            'Turnos con selfie',
            '${s.kpi.turnosConSelfie} de ${s.kpi.totalTurnos}',
            _colorPorPorcentaje(s.kpi.pctSelfie),
          )),
          pw.SizedBox(width: 8),
          pw.Expanded(child: _tarjetaKpi(
            '${s.kpi.pctGps}%',
            'Turnos con GPS',
            '${s.kpi.turnosConGps} de ${s.kpi.totalTurnos}',
            _colorPorPorcentaje(s.kpi.pctGps),
          )),
          pw.SizedBox(width: 8),
          pw.Expanded(child: _tarjetaKpi(
            '${s.kpi.pctRondasCompletas}%',
            'Rondas completas',
            '${s.kpi.rondasCompletas} de ${s.kpi.totalRondas}',
            _colorPorPorcentaje(s.kpi.pctRondasCompletas),
          )),
          pw.SizedBox(width: 8),
          pw.Expanded(child: _tarjetaKpi(
            '${s.kpi.horasCubiertas.toStringAsFixed(1)} h',
            'Horas cubiertas',
            '${s.kpi.totalTurnos} turno${s.kpi.totalTurnos == 1 ? "" : "s"}',
            _Tinta.grafito,
          )),
        ],
      ),

      // ---- 3. Distribución de accesos por hora ----
      pw.SizedBox(height: 20),
      _tituloDeSeccion('Accesos por hora del día'),
      _graficoAccesosPorHora(s.accesosPorHora),
      pw.SizedBox(height: 4),
      pw.Text(
        s.horaPico == -1
            ? 'Sin registros de accesos en el período.'
            : 'Hora pico: ${s.horaPico.toString().padLeft(2, "0")}:00 '
              '(${s.accesosPorHora[s.horaPico]} accesos)  ·  '
              'Total período: ${s.totalAccesos}',
        style: const pw.TextStyle(fontSize: 9.5, color: _Tinta.suave),
      ),

      // ---- 10. Ranking de guardias ----
      if (s.ranking.isNotEmpty) ...[
        pw.SizedBox(height: 20),
        _tituloDeSeccion('Ranking de guardias'),
        _tablaRanking(s.ranking),
      ],

      // ---- 4. Alertas del período ----
      if (s.alertas.isNotEmpty) ...[
        pw.SizedBox(height: 20),
        _tituloDeSeccion(
            'Alertas del período (${s.alertas.length})'),
        ...s.alertas.take(15).map(_filaAlerta),
        if (s.alertas.length > 15)
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 4, left: 4),
            child: pw.Text(
              '... y ${s.alertas.length - 15} más.',
              style: const pw.TextStyle(fontSize: 9, color: _Tinta.tenue),
            ),
          ),
      ],

      // ---- 6. Encomiendas pendientes viejas ----
      if (s.encomiendasPendientes.isNotEmpty) ...[
        pw.SizedBox(height: 20),
        _tituloDeSeccion(
            'Encomiendas pendientes hace más de 7 días '
            '(${s.encomiendasPendientes.length})'),
        ...s.encomiendasPendientes.map(_filaEncomiendaVieja),
      ],

      // ---- Salto antes de la lista de turnos ----
      pw.SizedBox(height: 24),
      _tituloDeSeccion('Detalle de cada turno'),
    ];
  }

  static pw.Widget _tituloDeSeccion(String texto) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 8),
      child: pw.Text(
        texto,
        style: pw.TextStyle(
          fontSize: 13,
          fontWeight: pw.FontWeight.bold,
          color: _Tinta.grafito,
        ),
      ),
    );
  }

  static pw.Widget _tarjetaKpi(
      String valor, String etiqueta, String subtitulo, PdfColor color) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        color: color == _Tinta.grafito
            ? const PdfColor.fromInt(0xFFF7F7F8)
            : PdfColor.fromInt(color.toInt()).shade(0.94),
        borderRadius: pw.BorderRadius.circular(6),
        border: pw.Border.all(color: color, width: 1),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            valor,
            style: pw.TextStyle(
              fontSize: 20,
              fontWeight: pw.FontWeight.bold,
              color: color,
            ),
          ),
          pw.SizedBox(height: 2),
          pw.Text(etiqueta,
              style: pw.TextStyle(
                fontSize: 9,
                fontWeight: pw.FontWeight.bold,
                color: _Tinta.grafito,
              )),
          pw.SizedBox(height: 1),
          pw.Text(subtitulo,
              style: const pw.TextStyle(
                fontSize: 8,
                color: _Tinta.tenue,
              )),
        ],
      ),
    );
  }

  static PdfColor _colorPorPorcentaje(int pct) {
    if (pct >= 90) return _Tinta.verde;
    if (pct >= 70) return const PdfColor.fromInt(0xFFA16207); // amarillo
    return _Tinta.rojo;
  }

  /// Barras horizontales de accesos por hora (24 barras).
  static pw.Widget _graficoAccesosPorHora(List<int> valores) {
    final maximo = valores.fold<int>(0, (a, b) => b > a ? b : a);
    if (maximo == 0) {
      return pw.Container(
        height: 40,
        alignment: pw.Alignment.center,
        child: pw.Text(
          'Sin datos de accesos en el período',
          style: const pw.TextStyle(fontSize: 10, color: _Tinta.tenue),
        ),
      );
    }
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(vertical: 6),
      decoration: const pw.BoxDecoration(
        border: pw.Border(
          bottom: pw.BorderSide(color: _Tinta.linea),
        ),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        children: List.generate(24, (h) {
          final v = valores[h];
          final alto = v == 0 ? 1.0 : (v / maximo * 60).clamp(2.0, 60.0);
          return pw.Expanded(
            child: pw.Column(
              mainAxisAlignment: pw.MainAxisAlignment.end,
              children: [
                if (v > 0)
                  pw.Text(
                    '$v',
                    style: const pw.TextStyle(fontSize: 6, color: _Tinta.suave),
                  ),
                pw.Container(
                  margin: const pw.EdgeInsets.symmetric(horizontal: 0.6),
                  height: alto,
                  decoration: pw.BoxDecoration(
                    color: v == 0
                        ? _Tinta.linea
                        : (v == maximo ? _Tinta.grafito : _Tinta.suave),
                    borderRadius: const pw.BorderRadius.only(
                      topLeft: pw.Radius.circular(2),
                      topRight: pw.Radius.circular(2),
                    ),
                  ),
                ),
                pw.SizedBox(height: 3),
                pw.Text(
                  h % 3 == 0 ? h.toString().padLeft(2, "0") : '',
                  style: const pw.TextStyle(fontSize: 6, color: _Tinta.tenue),
                ),
              ],
            ),
          );
        }),
      ),
    );
  }

  static pw.Widget _tablaRanking(List<RankingGuardia> ranking) {
    return pw.Container(
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: _Tinta.linea),
        borderRadius: pw.BorderRadius.circular(6),
      ),
      child: pw.Table(
        columnWidths: const {
          0: pw.FixedColumnWidth(24),   // #
          1: pw.FlexColumnWidth(3),     // Guardia
          2: pw.FlexColumnWidth(1.2),   // Turnos
          3: pw.FlexColumnWidth(1.2),   // Horas
          4: pw.FlexColumnWidth(1.2),   // % Selfie
          5: pw.FlexColumnWidth(1.2),   // % GPS
          6: pw.FlexColumnWidth(1),     // Puntaje
        },
        children: [
          pw.TableRow(
            decoration: const pw.BoxDecoration(
              color: PdfColor.fromInt(0xFFF7F7F8),
            ),
            children: [
              _celdaHead('#'),
              _celdaHead('Guardia'),
              _celdaHead('Turnos'),
              _celdaHead('Horas'),
              _celdaHead('% Selfie'),
              _celdaHead('% GPS'),
              _celdaHead('Puntaje'),
            ],
          ),
          for (var i = 0; i < ranking.length; i++)
            pw.TableRow(
              decoration: pw.BoxDecoration(
                border: const pw.Border(
                  top: pw.BorderSide(color: _Tinta.linea, width: 0.5),
                ),
              ),
              children: [
                _celda('${i + 1}', bold: true),
                _celda(ranking[i].guardia),
                _celda('${ranking[i].totalTurnos}'),
                _celda(ranking[i].horasTrabajadas.toStringAsFixed(1)),
                _celda('${ranking[i].pctSelfie}%',
                    color: _colorPorPorcentaje(ranking[i].pctSelfie)),
                _celda('${ranking[i].pctGps}%',
                    color: _colorPorPorcentaje(ranking[i].pctGps)),
                _celda('${ranking[i].puntaje}',
                    bold: true,
                    color: _colorPorPorcentaje(ranking[i].puntaje)),
              ],
            ),
        ],
      ),
    );
  }

  static pw.Widget _celdaHead(String t) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 5),
        child: pw.Text(t,
            style: pw.TextStyle(
              fontSize: 9,
              fontWeight: pw.FontWeight.bold,
              color: _Tinta.grafito,
            )),
      );

  static pw.Widget _celda(String t,
      {bool bold = false, PdfColor color = _Tinta.grafito}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 5),
      child: pw.Text(
        t,
        style: pw.TextStyle(
          fontSize: 9.5,
          fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
          color: color,
        ),
      ),
    );
  }

  static pw.Widget _filaAlerta(AlertaTurno a) {
    final color = switch (a.tipo) {
      TipoAlerta.rondaSospechosa => _Tinta.rojo,
      TipoAlerta.gapCobertura => _Tinta.rojo,
      TipoAlerta.turnoSinSelfie => _Tinta.naranja,
      TipoAlerta.turnoSinGps => _Tinta.naranja,
    };
    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 4),
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: pw.BoxDecoration(
        border: pw.Border(
          left: pw.BorderSide(color: color, width: 3),
        ),
        color: const PdfColor.fromInt(0xFFFAFAFB),
      ),
      child: pw.Row(
        children: [
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: pw.BoxDecoration(
              color: color,
              borderRadius: pw.BorderRadius.circular(2),
            ),
            child: pw.Text(a.tipo.etiqueta.toUpperCase(),
                style: pw.TextStyle(
                  fontSize: 7,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.white,
                )),
          ),
          pw.SizedBox(width: 6),
          pw.Expanded(
            child: pw.Text(
              [
                a.descripcion,
                if (a.guardia != null) '— ${a.guardia}',
                if (a.cuando != null)
                  '· ${Formato.diaYMes(a.cuando!)} ${Formato.hora(a.cuando!)}',
              ].join(' '),
              style: const pw.TextStyle(fontSize: 9, color: _Tinta.grafito),
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _filaEncomiendaVieja(EncomiendaPendiente e) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 4),
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: const pw.BoxDecoration(
        color: PdfColor.fromInt(0xFFFAFAFB),
        border: pw.Border(
          left: pw.BorderSide(color: _Tinta.naranja, width: 3),
        ),
      ),
      child: pw.Row(
        children: [
          pw.Container(
            width: 40,
            padding: const pw.EdgeInsets.symmetric(vertical: 2),
            decoration: pw.BoxDecoration(
              color: _Tinta.naranja,
              borderRadius: pw.BorderRadius.circular(3),
            ),
            child: pw.Column(
              children: [
                pw.Text('${e.diasEsperando}',
                    style: pw.TextStyle(
                      fontSize: 11,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.white,
                    )),
                pw.Text('días',
                    style: const pw.TextStyle(
                        fontSize: 6, color: PdfColors.white)),
              ],
            ),
          ),
          pw.SizedBox(width: 8),
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  [
                    if (e.residente != null) e.residente!,
                    if (e.unidad != null) 'Unidad ${e.unidad}',
                  ].join(' · '),
                  style: pw.TextStyle(
                    fontSize: 10,
                    fontWeight: pw.FontWeight.bold,
                    color: _Tinta.grafito,
                  ),
                ),
                pw.Text(
                  [
                    e.descripcion,
                    if (e.empresaCourier != null) e.empresaCourier!,
                    'Recibido el ${Formato.diaYMes(e.recibidoEn)}',
                  ].join(' · '),
                  style: const pw.TextStyle(fontSize: 9, color: _Tinta.suave),
                ),
              ],
            ),
          ),
        ],
      ),
    );
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
                // ---- 14. Actividad del turno ----
                if (t.actividad != null && !t.actividad!.vacio) ...[
                  pw.SizedBox(height: 6),
                  pw.Row(
                    children: [
                      _chipActividad(
                          'Accesos', '${t.actividad!.accesos}'),
                      pw.SizedBox(width: 5),
                      _chipActividad(
                          'Rondas', '${t.actividad!.rondas}'),
                      pw.SizedBox(width: 5),
                      _chipActividad(
                          'Encomiendas', '${t.actividad!.encomiendas}'),
                    ],
                  ),
                ],
                // ---- 15. Nota al siguiente turno ----
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

  static pw.Widget _chipActividad(String etiqueta, String valor) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: pw.BoxDecoration(
        color: const PdfColor.fromInt(0xFFEEF0F3),
        borderRadius: pw.BorderRadius.circular(3),
      ),
      child: pw.Row(
        mainAxisSize: pw.MainAxisSize.min,
        children: [
          pw.Text(
            valor,
            style: pw.TextStyle(
              fontSize: 10,
              fontWeight: pw.FontWeight.bold,
              color: _Tinta.grafito,
            ),
          ),
          pw.SizedBox(width: 3),
          pw.Text(
            etiqueta.toLowerCase(),
            style: const pw.TextStyle(fontSize: 8, color: _Tinta.suave),
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
