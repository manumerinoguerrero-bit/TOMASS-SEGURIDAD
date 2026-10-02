// ============================================================================
// Tomass Seguridad — Exportación CSV de informes
// ============================================================================
// El administrador necesita a veces llevar los datos a Excel, pasárselos al
// contador para el pago de horas, o mandárselos al mandante en un formato
// que puedan pegar en su propio sistema. El PDF es para mostrar; el CSV es
// para procesar.
//
// NOTAS DE FORMATO
//
//   - UTF-8 con BOM (﻿). Sin el BOM, Excel abre el archivo asumiendo
//     cp1252 y los acentos salen rotos (Ã³ en vez de ó).
//   - Separador coma (RFC 4180). Excel chileno a veces prefiere punto y
//     coma; se puede cambiar al abrir si no lo detecta.
//   - Comillas dobles alrededor de los campos que tienen coma, salto de
//     línea o comillas. Las comillas dentro del campo se escapan duplicadas
//     ("Juan ""el gordo"" Pérez").
//   - Fechas en dd/MM/yyyy y horas en HH:mm:ss porque es lo que los
//     usuarios chilenos esperan ver en Excel.
// ============================================================================

import 'dart:convert';
import 'dart:typed_data';

import 'package:intl/intl.dart';

import '../modelos/admin.dart';

class ExportadorCsv {
  const ExportadorCsv._();

  // --------------------------------------------------------------------------
  // Accesos
  // --------------------------------------------------------------------------

  static Uint8List csvDeAccesos(List<MovimientoAdmin> lista) {
    final sb = StringBuffer()
      ..writeCharCode(0xFEFF)
      ..writeln(_fila(const [
        'Fecha',
        'Hora',
        'Tipo',
        'Sentido',
        'Estado',
        'Nombre',
        'RUT',
        'Unidad',
        'Patente',
        'Entrada',
        'Autorizado por',
        'Guardia',
        'Motivo denegación',
      ]));

    final fmtFecha = DateFormat('dd/MM/yyyy');
    final fmtHora = DateFormat('HH:mm:ss');

    for (final m in lista) {
      final local = m.ocurridoEn.toLocal();
      sb.writeln(_fila([
        fmtFecha.format(local),
        fmtHora.format(local),
        m.esVehicular ? 'Vehicular' : 'Peatonal',
        m.esEntrada ? 'Entrada' : 'Salida',
        m.aprobado ? 'Aprobado' : 'Denegado',
        m.quien ?? '',
        m.rut ?? '',
        m.espacio ?? '',
        m.patente ?? '',
        m.entrada ?? '',
        m.autorizadoPor ?? '',
        m.guardia ?? '',
        m.motivoDenegacion ?? '',
      ]));
    }

    return Uint8List.fromList(utf8.encode(sb.toString()));
  }

  // --------------------------------------------------------------------------
  // Turnos (pensado para pago de horas)
  // --------------------------------------------------------------------------

  static Uint8List csvDeTurnos(List<TurnoAdmin> lista) {
    final sb = StringBuffer()
      ..writeCharCode(0xFEFF)
      ..writeln(_fila(const [
        'Fecha inicio',
        'Hora inicio',
        'Fecha cierre',
        'Hora cierre',
        'Horas trabajadas',
        'Minutos trabajados',
        'Estado',
        'Guardia',
        'Puesto',
        'Notas de entrega',
      ]));

    final fmtFecha = DateFormat('dd/MM/yyyy');
    final fmtHora = DateFormat('HH:mm:ss');

    for (final t in lista) {
      final inicio = t.inicio.toLocal();
      final cierre = t.cerradoEn?.toLocal();
      final abierto = t.sigueAbierto;
      // Si el turno sigue abierto NO contamos las "horas en curso" al CSV
      // de pago: estaría mal pagarlas sin saber cuándo terminan. Queda en
      // blanco y el admin ve el estado "Abierto".
      final minutos = abierto ? null : t.duracion.inMinutes;
      final horas = minutos == null ? '' : (minutos / 60).toStringAsFixed(2);

      sb.writeln(_fila([
        fmtFecha.format(inicio),
        fmtHora.format(inicio),
        cierre == null ? '' : fmtFecha.format(cierre),
        cierre == null ? '' : fmtHora.format(cierre),
        horas,
        minutos?.toString() ?? '',
        abierto ? 'Abierto' : 'Cerrado',
        t.guardia,
        t.puesto ?? 'Cubre todo',
        t.notas ?? '',
      ]));
    }

    return Uint8List.fromList(utf8.encode(sb.toString()));
  }

  // --------------------------------------------------------------------------
  // Helpers
  // --------------------------------------------------------------------------

  static String _fila(List<String> campos) =>
      campos.map(_escapar).join(',');

  static String _escapar(String campo) {
    final c = campo.replaceAll('\r\n', '\n');
    final necesita =
        c.contains(',') || c.contains('"') || c.contains('\n');
    if (!necesita) return c;
    final conComillasEscapadas = c.replaceAll('"', '""');
    return '"$conComillasEscapadas"';
  }
}
