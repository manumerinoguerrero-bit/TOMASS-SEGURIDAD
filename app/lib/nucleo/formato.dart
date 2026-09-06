// ============================================================================
// Tomass Seguridad — Fechas y textos en español de Chile
// ============================================================================
// Todas las fechas y horas que se muestran pasan por acá, para que en toda la
// app se vean iguales y en la hora de Chile.
// ============================================================================

import 'package:intl/intl.dart';

import '../modelos/formato_patente.dart';

class Formato {
  const Formato._();

  static final _hora = DateFormat('HH:mm');
  static final _horaSegundos = DateFormat('HH:mm:ss');
  static final _fechaCorta = DateFormat('dd/MM/yyyy');
  static final _fechaHora = DateFormat("dd/MM/yyyy 'a las' HH:mm");
  static final _diaMes = DateFormat('d MMM', 'es');
  static final _diaCompleto = DateFormat("EEEE d 'de' MMMM", 'es');

  static String hora(DateTime cuando) => _hora.format(cuando.toLocal());

  static String horaConSegundos(DateTime cuando) =>
      _horaSegundos.format(cuando.toLocal());

  static String fecha(DateTime cuando) => _fechaCorta.format(cuando.toLocal());

  static String fechaYHora(DateTime cuando) => _fechaHora.format(cuando.toLocal());

  static String diaYMes(DateTime cuando) => _diaMes.format(cuando.toLocal());

  static String diaCompleto(DateTime cuando) =>
      _diaCompleto.format(cuando.toLocal());

  /// "hoy 18:04", "ayer 09:12", "24 jul 20:15".
  /// Sirve para las listas de historial, donde lo que importa es ubicarse rápido.
  static String cuandoRelativo(DateTime cuando) {
    final local = cuando.toLocal();
    final ahora = DateTime.now();
    final hoy = DateTime(ahora.year, ahora.month, ahora.day);
    final dia = DateTime(local.year, local.month, local.day);
    final diferencia = hoy.difference(dia).inDays;

    if (diferencia == 0) return 'hoy ${hora(local)}';
    if (diferencia == 1) return 'ayer ${hora(local)}';
    if (diferencia < 7) return '${_diaCompleto.format(local).split(' ').first} ${hora(local)}';
    return '${diaYMes(local)} ${hora(local)}';
  }

  /// "hace 4 segundos", "hace 3 minutos", "hace 2 horas", "hace 9 días".
  static String haceCuanto(DateTime desde) {
    final segundos = DateTime.now().difference(desde.toLocal()).inSeconds;

    if (segundos < 5) return 'recién';
    if (segundos < 60) return 'hace $segundos segundos';

    final minutos = segundos ~/ 60;
    if (minutos < 60) {
      return minutos == 1 ? 'hace 1 minuto' : 'hace $minutos minutos';
    }

    final horas = minutos ~/ 60;
    if (horas < 24) return horas == 1 ? 'hace 1 hora' : 'hace $horas horas';

    final dias = horas ~/ 24;
    return dias == 1 ? 'hace 1 día' : 'hace $dias días';
  }

  /// "1 día", "9 días". Para los paquetes en portería.
  static String cantidadDeDias(int dias) {
    if (dias <= 0) return 'hoy';
    return dias == 1 ? '1 día' : '$dias días';
  }

  /// Deja la patente como se escribe en Chile: mayúsculas y con guion.
  /// La regla vive en modelos/formato_patente.dart, para tenerla en un solo lugar.
  static String patente(String cruda) => FormatoPatente.normalizar(cruda);

  /// Deja el RUT como se escribe en Chile: sin puntos, con guion antes del
  /// dígito verificador y con la K en mayúscula. Ej.: "12345678K" → "12345678-K",
  /// "12.345.678-k" → "12345678-K", "123456785" → "12345678-5".
  /// Si viene vacío o con menos de 2 caracteres, devuelve la cadena como está.
  static String rut(String? crudo) {
    if (crudo == null) return '';
    final limpio = crudo
        .replaceAll('.', '')
        .replaceAll('-', '')
        .replaceAll(' ', '')
        .toUpperCase();
    if (limpio.length < 2) return limpio;
    final cuerpo = limpio.substring(0, limpio.length - 1);
    final dv = limpio.substring(limpio.length - 1);
    return '$cuerpo-$dv';
  }

  /// Pone el nombre con la primera letra de cada palabra en mayúscula.
  static String nombrePropio(String texto) {
    return texto
        .trim()
        .split(RegExp(r'\s+'))
        .map((p) => p.isEmpty
            ? p
            : '${p[0].toUpperCase()}${p.substring(1).toLowerCase()}')
        .join(' ');
  }

  /// Solo el nombre y el primer apellido. Para cuando no hay espacio.
  static String nombreCorto(String completo) {
    final partes = completo.trim().split(RegExp(r'\s+'));
    if (partes.length <= 2) return completo;
    return '${partes[0]} ${partes[1]}';
  }
}
