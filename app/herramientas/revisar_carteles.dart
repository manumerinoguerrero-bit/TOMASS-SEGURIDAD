// ============================================================================
// Tomass Seguridad — Revisor de los carteles
// ============================================================================
// QUÉ HACE
//
//   Lee el archivo de carteles ya generado, vuelve a armar cada código QR a
//   partir del dibujo, y le revisa la estructura por dentro.
//
// POR QUÉ EXISTE
//
//   Un código QR mal dibujado se ve perfecto: sigue siendo un cuadrado con
//   dibujitos negros. El error recién aparece cuando alguien está parado en la
//   puerta, de noche, apuntando el teléfono a un cartel que no lee.
//
//   Y hay un error clásico que es invisible al ojo: dibujar el código dado
//   vuelta sobre su diagonal (cambiar filas por columnas). Queda igual de
//   simétrico y hasta algunos lectores lo perdonan, pero otros no.
//
//   Esta revisión busca las marcas que todo código QR tiene que tener en un
//   lugar exacto. Si alguna no está donde corresponde, el dibujo está mal.
//
//   Corré esto DESPUÉS de generar los carteles y ANTES de mandar a imprimir.
//
//       dart run herramientas/revisar_carteles.dart
// ============================================================================

import 'dart:convert';
import 'dart:io';

const String _carpeta = '../carteles';

void main() {
  final pagina = File('$_carpeta/carteles-para-imprimir.html');
  if (!pagina.existsSync()) {
    stderr.writeln('No encontré los carteles. Generalos primero con:');
    stderr.writeln('  dart run herramientas/generar_carteles.dart');
    exit(1);
  }

  final datos = jsonDecode(
      File('$_carpeta/entradas.json').readAsStringSync()) as Map<String, dynamic>;
  final entradas = (datos['entradas'] as List).cast<Map<String, dynamic>>();

  final html = pagina.readAsStringSync();
  final dibujos = _sacarLosDibujos(html);

  stdout.writeln('Carteles en el archivo: ${dibujos.length}');
  stdout.writeln('Entradas en la lista:   ${entradas.length}');
  stdout.writeln('');

  if (dibujos.length != entradas.length) {
    stderr.writeln('No coinciden. Faltan carteles o sobran.');
    exit(1);
  }

  var fallas = 0;

  for (var i = 0; i < dibujos.length; i++) {
    final e = entradas[i];
    final donde = '${e['instalacion']} — ${e['entrada']}';
    final problemas = _revisarElDibujo(dibujos[i]);

    // Que el nombre y el código de esta entrada estén escritos en el cartel
    if (!html.contains(e['codigo'] as String)) {
      problemas.add('el código no aparece escrito en el cartel');
    }

    if (problemas.isEmpty) {
      stdout.writeln('  OK   $donde');
    } else {
      fallas++;
      stdout.writeln('  MAL  $donde');
      for (final p in problemas) {
        stdout.writeln('         · $p');
      }
    }
  }

  stdout.writeln('');
  if (fallas > 0) {
    stderr.writeln('$fallas carteles con problemas. NO los mandes a imprimir.');
    exit(1);
  }

  stdout.writeln('Los ${dibujos.length} carteles pasaron la revisión.');
  stdout.writeln('');
  stdout.writeln('Igual, antes de imprimir todos: imprimí UNO en papel común');
  stdout.writeln('y escaneálo con la app. Esta revisión comprueba que el dibujo');
  stdout.writeln('esté bien hecho, pero la prueba de verdad es la cámara.');
}

/// Saca de la página cada dibujo de código QR, ya convertido en cuadrícula.
List<_Cuadricula> _sacarLosDibujos(String html) {
  final resultado = <_Cuadricula>[];

  final svgs = RegExp(r'<svg class="qr" viewBox="0 0 (\d+) \1"[^>]*>(.*?)</svg>',
          dotAll: true)
      .allMatches(html);

  for (final svg in svgs) {
    final total = int.parse(svg.group(1)!);
    final cuerpo = svg.group(2)!;

    final trazo = RegExp(r'<path d="([^"]*)"').firstMatch(cuerpo)?.group(1) ?? '';
    final cuadricula = _Cuadricula(total);

    for (final punto in RegExp(r'M(\d+) (\d+)h1v1h-1z').allMatches(trazo)) {
      cuadricula.pintar(
        int.parse(punto.group(2)!), // fila
        int.parse(punto.group(1)!), // columna
      );
    }

    resultado.add(cuadricula);
  }

  return resultado;
}

/// Revisa que el dibujo tenga las marcas obligatorias en su lugar exacto.
List<String> _revisarElDibujo(_Cuadricula c) {
  final problemas = <String>[];

  // El marco blanco que exige la norma: 4 puntos de aire por los cuatro lados
  const marco = 4;
  for (var i = 0; i < c.total; i++) {
    for (var j = 0; j < marco; j++) {
      if (c.esNegro(i, j) ||
          c.esNegro(i, c.total - 1 - j) ||
          c.esNegro(j, i) ||
          c.esNegro(c.total - 1 - j, i)) {
        problemas.add('le falta el marco blanco de los bordes');
        i = c.total; // cortar
        break;
      }
    }
  }

  final lado = c.total - marco * 2;

  // Las tres marcas de las esquinas: son los cuadrados grandes que el lector usa
  // para encontrar el código y saber para qué lado está girado.
  final esquinas = {
    'arriba a la izquierda': [0, 0],
    'arriba a la derecha': [0, lado - 7],
    'abajo a la izquierda': [lado - 7, 0],
  };
  for (final esquina in esquinas.entries) {
    if (!_hayMarcaDeEsquina(c, marco + esquina.value[0], marco + esquina.value[1])) {
      problemas.add('le falta la marca de la esquina de ${esquina.key}');
    }
  }

  // La regla punteada: una fila y una columna de puntos alternados que le dan
  // la escala al lector.
  for (var i = 8; i < lado - 8; i++) {
    final esperado = i.isEven;
    if (c.esNegro(marco + 6, marco + i) != esperado) {
      problemas.add('la regla punteada horizontal está mal');
      break;
    }
  }
  for (var i = 8; i < lado - 8; i++) {
    final esperado = i.isEven;
    if (c.esNegro(marco + i, marco + 6) != esperado) {
      problemas.add('la regla punteada vertical está mal');
      break;
    }
  }

  // El punto que SIEMPRE va negro. Está en un lugar que no es simétrico, así
  // que si el dibujo quedó dado vuelta sobre su diagonal, acá se nota.
  final version = (lado - 21) ~/ 4 + 1;
  if (!c.esNegro(marco + 4 * version + 9, marco + 8)) {
    problemas.add('el dibujo está transpuesto (filas y columnas cambiadas)');
  }

  return problemas;
}

/// Una marca de esquina: cuadrado negro de 7x7, con un anillo blanco adentro
/// y un cuadrado negro de 3x3 en el centro.
bool _hayMarcaDeEsquina(_Cuadricula c, int fila, int col) {
  for (var f = 0; f < 7; f++) {
    for (var g = 0; g < 7; g++) {
      final enElBorde = f == 0 || f == 6 || g == 0 || g == 6;
      final enElAnillo = f == 1 || f == 5 || g == 1 || g == 5;
      final debeSerNegro = enElBorde || (!enElAnillo);
      if (c.esNegro(fila + f, col + g) != debeSerNegro) return false;
    }
  }
  return true;
}

class _Cuadricula {
  _Cuadricula(this.total) : _puntos = List.filled(total * total, false);

  final int total;
  final List<bool> _puntos;

  void pintar(int fila, int col) {
    if (fila < 0 || col < 0 || fila >= total || col >= total) return;
    _puntos[fila * total + col] = true;
  }

  bool esNegro(int fila, int col) {
    if (fila < 0 || col < 0 || fila >= total || col >= total) return false;
    return _puntos[fila * total + col];
  }
}
