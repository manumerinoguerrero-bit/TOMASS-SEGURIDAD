// ============================================================================
// Tomass Seguridad — Preparador del logo y del ícono de la app
// ============================================================================
// QUÉ HACE ESTE ARCHIVO
//
//   Toma el logo original de la empresa y prepara las tres imágenes que usa
//   la app. El original NUNCA se toca: se lee y se deja como está.
//
//   ENTRA:   marca/logo-original.png       el archivo tal como llegó
//
//   SALEN:   assets/imagenes/logo.png      el escudo SIN el fondo blanco. Es el
//                                          que muestra la app en sus pantallas.
//
//            marca/icono-app.png           el escudo sobre fondo grafito. Lo usan
//                                          el iPhone y los Android antiguos.
//
//            marca/icono-adaptativo.png    solo el escudo, transparente y más
//                                          chico. Lo usa Android moderno.
//
// POR QUÉ HAY DOS CARPETAS
//
//   Todo lo que está en assets/ se copia DENTRO de la app instalada y ocupa
//   espacio en el teléfono del usuario. Por eso ahí va solo el logo que la app
//   muestra en pantalla.
//
//   Las otras tres imágenes son materia prima: se usan una vez, acá en el
//   computador, para fabricar los íconos. Por eso viven en marca/, que no viaja
//   con la app.
//
// POR QUÉ HAY QUE SACARLE EL FONDO
//
//   El logo original viene sobre un cuadrado blanco. En una hoja de papel eso no
//   se nota, pero las pantallas de la app son grafito oscuro: el escudo aparecería
//   metido dentro de un recuadro blanco, como una estampilla mal pegada.
//
//   Este programa borra ese blanco y deja solo el escudo recortado.
//
// CÓMO SABE QUÉ ES FONDO Y QUÉ ES ESCUDO
//
//   No borra "todo lo blanco": el escudo tiene brillos plateados casi blancos y
//   se le harían agujeros. Lo que hace es entrar por los cuatro bordes de la
//   imagen y avanzar hacia adentro mientras encuentre blanco, como si fuera agua
//   filtrándose. Cuando choca con el escudo, se detiene. Así el blanco de afuera
//   desaparece y los brillos de adentro quedan intactos.
//
// POR QUÉ EL ÍCONO DE ANDROID VA MÁS CHICO
//
//   Android recorta el ícono para darle la forma que el usuario eligió en su
//   teléfono: círculo, cuadrado redondeado, gota. El recorte se come los bordes.
//   Por eso el escudo se achica y se centra, y queda entero en cualquier forma.
//
// CUÁNDO HAY QUE VOLVER A CORRERLO
//
//   Solo si cambia el logo de la empresa. Los pasos están en marca/LEEME.txt.
// ============================================================================

import 'dart:io';
import 'dart:math' as math;

import 'package:image/image.dart' as img;

// ---- Configuración ---------------------------------------------------------

/// Color grafito de la marca (el mismo de AppTema.grafito en lib/config/tema.dart)
const int _grafitoR = 0x1C;
const int _grafitoG = 0x1E;
const int _grafitoB = 0x24;

/// Los íconos se entregan en 1024x1024: es el tamaño que piden Apple y Google.
/// Los tamaños chicos los genera flutter_launcher_icons a partir de este.
const int _lado = 1024;

/// Cuánto del cuadrado ocupa el escudo en el ícono con fondo (80%).
const double _proporcionConFondo = 0.80;

/// Cuánto ocupa el escudo en el ícono de Android (58%).
/// Es más chico a propósito: la "zona segura" que Android promete no recortar
/// es el 61% del centro, así que con 58% entra con margen en todas las formas.
const double _proporcionAdaptativo = 0.58;

/// Qué tan claro tiene que ser un punto para considerarlo fondo.
///
/// ⚠️ NO BAJAR ESTE NÚMERO. Está en 200 (de 255) y ahí se queda.
///
///    El filo plateado de la punta de arriba del escudo llega a 218 de claro:
///    está a un pelo de este umbral. Lo probamos en 180 y el borrado se le metió
///    por ahí y le dejó la punta rota, como mordida.
///
///    Y no hace falta bajarlo: este paso solo tiene que sacar el blanco. De la
///    sombra gris se encarga el paso siguiente, que no mira el color.
const int _umbralDeFondo = 200;

/// Qué tan oscuro tiene que ser un punto para ser "escudo de verdad".
///
/// Está en 110 porque lo medimos columna por columna: el material del escudo
/// termina siempre por debajo de 100, y la sombra arranca recién en 125 y sube
/// de ahí. Entre 100 y 125 no hay nada: ese hueco es el que separa a los dos.
const int _umbralDeEscudo = 110;

/// Cuántos puntos de desvanecido se dejan bajo el borde del escudo.
/// Es el respiro para que el filo de abajo no quede cortado a cuchillo.
const int _desvanecidoBajoElEscudo = 10;

/// Dónde vive la materia prima (no viaja dentro de la app)
const String _marca = 'marca';

/// Dónde va el logo que la app muestra (sí viaja dentro de la app)
const String _assets = 'assets/imagenes';

/// A cuántos puntos se achica el logo que se guarda dentro de la app.
///
/// La pantalla más grande donde se muestra es la del login, a 96 puntos. En un
/// teléfono de pantalla muy fina eso son 384 puntos reales, así que con 420 va
/// sobrado y se ve nítido. Guardarlo en 599, como viene el original, era cargar
/// al teléfono del usuario con 445 KB para mostrar una estampilla.
const int _ladoDelLogoEnLaApp = 420;

// ---- Programa --------------------------------------------------------------

void main() {
  final origen = File('$_marca/logo-original.png');

  if (!origen.existsSync()) {
    stderr.writeln('No encontré el logo en $_marca/logo-original.png');
    stderr.writeln('Guardá ahí el archivo del logo con ese nombre exacto,');
    stderr.writeln('todo en minúsculas, y volvé a correr este programa.');
    stderr.writeln('');
    stderr.writeln('Ojo: hay que correr este programa parado en la carpeta app/');
    exit(1);
  }

  final crudo = img.decodePng(origen.readAsBytesSync());
  if (crudo == null) {
    stderr.writeln('El archivo logo-original.png está dañado o no es un PNG.');
    exit(1);
  }

  stdout.writeln('Logo original: ${crudo.width} x ${crudo.height} puntos');

  // Paso 1 — sacarle el fondo claro
  final sinFondo = _quitarFondo(crudo);

  // Paso 2 — borrarle la sombra que el logo trae dibujada
  final sinSombra = _quitarLaSombra(crudo, sinFondo);

  // Paso 3 — recortar el aire que sobra alrededor del escudo
  final escudo = _recortarMargenes(sinSombra);
  stdout.writeln('Escudo recortado: ${escudo.width} x ${escudo.height} puntos');
  stdout.writeln('');

  // Paso 4 — escribir las tres imágenes
  //
  // El logo de la app se guarda achicado: es el único que ocupa espacio en el
  // teléfono del usuario. Los otros dos van en grande porque son la materia
  // prima con la que se fabrican los íconos, y esos nunca se instalan.
  _escribir(
    '$_assets/logo.png',
    img.copyResize(
      escudo,
      height: _ladoDelLogoEnLaApp,
      interpolation: img.Interpolation.cubic,
    ),
    'el escudo solo, sin fondo — el que muestra la app en pantalla',
  );
  _escribir(
    '$_marca/icono-app.png',
    _armarCuadrado(escudo, _proporcionConFondo, conFondo: true),
    'ícono con fondo grafito (iPhone y Android antiguo)',
  );
  _escribir(
    '$_marca/icono-adaptativo.png',
    _armarCuadrado(escudo, _proporcionAdaptativo, conFondo: false),
    'ícono transparente y centrado (Android moderno)',
  );

  stdout.writeln('');
  stdout.writeln('Listo. Ahora corré:  dart run flutter_launcher_icons');
}

// ---- Paso 1: sacar el fondo ------------------------------------------------

/// Borra el fondo claro entrando por los bordes de la imagen.
///
/// Avanza punto por punto desde las orillas hacia adentro mientras encuentre
/// color claro, y se detiene al chocar con el escudo. Los brillos claros que
/// están DENTRO del escudo nunca se alcanzan, así que no se borran.
img.Image _quitarFondo(img.Image entrada) {
  final ancho = entrada.width;
  final alto = entrada.height;
  final esFondo = List<bool>.filled(ancho * alto, false);
  final porRevisar = <int>[];

  bool esClaro(int x, int y) {
    final p = entrada.getPixel(x, y);
    // Un punto ya transparente también cuenta como fondo.
    if (p.a < 128) return true;
    final masOscuro = math.min(p.r, math.min(p.g, p.b));
    return masOscuro >= _umbralDeFondo;
  }

  void encolar(int x, int y) {
    final i = y * ancho + x;
    if (esFondo[i]) return;
    if (!esClaro(x, y)) return;
    esFondo[i] = true;
    porRevisar.add(i);
  }

  // Se empieza por las cuatro orillas
  for (var x = 0; x < ancho; x++) {
    encolar(x, 0);
    encolar(x, alto - 1);
  }
  for (var y = 0; y < alto; y++) {
    encolar(0, y);
    encolar(ancho - 1, y);
  }

  // Y se avanza hacia adentro
  while (porRevisar.isNotEmpty) {
    final i = porRevisar.removeLast();
    final x = i % ancho;
    final y = i ~/ ancho;
    if (x > 0) encolar(x - 1, y);
    if (x < ancho - 1) encolar(x + 1, y);
    if (y > 0) encolar(x, y - 1);
    if (y < alto - 1) encolar(x, y + 1);
  }

  final borrados = esFondo.where((b) => b).length;
  final porcentaje = (borrados * 100 / (ancho * alto)).toStringAsFixed(1);
  stdout.writeln('Fondo borrado: $porcentaje% de la imagen');

  // Se arma la imagen final, dejando en transparente todo lo marcado como fondo
  final salida = img.Image(width: ancho, height: alto, numChannels: 4);
  for (var y = 0; y < alto; y++) {
    for (var x = 0; x < ancho; x++) {
      if (esFondo[y * ancho + x]) {
        salida.setPixelRgba(x, y, 0, 0, 0, 0);
      } else {
        final p = entrada.getPixel(x, y);
        salida.setPixelRgba(x, y, p.r.toInt(), p.g.toInt(), p.b.toInt(), p.a.toInt());
      }
    }
  }

  return _suavizarElBorde(salida, esFondo);
}

/// Suaviza el filo del recorte.
///
/// El borrado deja el borde "en escalera", como los dientes de una sierra. Esto
/// recorre los puntos que quedaron pegados al fondo y les baja un poco la
/// opacidad, para que la orilla del escudo se vea pareja y no dentada.
img.Image _suavizarElBorde(img.Image imagen, List<bool> esFondo) {
  final ancho = imagen.width;
  final alto = imagen.height;

  bool fondoEn(int x, int y) {
    if (x < 0 || y < 0 || x >= ancho || y >= alto) return true;
    return esFondo[y * ancho + x];
  }

  for (var y = 0; y < alto; y++) {
    for (var x = 0; x < ancho; x++) {
      if (esFondo[y * ancho + x]) continue;

      // Cuántos de los 8 vecinos son fondo
      var vecinosFondo = 0;
      for (var dy = -1; dy <= 1; dy++) {
        for (var dx = -1; dx <= 1; dx++) {
          if (dx == 0 && dy == 0) continue;
          if (fondoEn(x + dx, y + dy)) vecinosFondo++;
        }
      }
      if (vecinosFondo == 0) continue;

      final p = imagen.getPixel(x, y);
      final nuevaOpacidad = (p.a * (1 - vecinosFondo / 16)).round();
      imagen.setPixelRgba(
        x, y, p.r.toInt(), p.g.toInt(), p.b.toInt(), nuevaOpacidad,
      );
    }
  }

  return imagen;
}

// ---- Paso 2: borrar la sombra ---------------------------------------------

/// Borra la sombra que el logo original trae dibujada debajo del escudo.
///
/// POR QUÉ NO ALCANZA CON EL PASO ANTERIOR
///
///   El paso anterior borra lo claro. Pero la sombra es un gris que va de medio
///   a casi blanco, y arranca pegada al escudo. Medimos el logo punto por punto:
///
///     · lo más claro del ESCUDO es el filo plateado de la punta de arriba: 218
///     · la SOMBRA arranca en 125, junto al escudo, y de ahí sube hasta el 255
///
///   Los dos rangos se pisan: hay sombra (125) MÁS OSCURA que partes del escudo
///   (218). No existe un nivel de claridad que borre toda la sombra sin comerse
///   la punta de arriba. Mirar el color, solo, no alcanza.
///
/// CÓMO SE DISTINGUEN ENTONCES
///
///   Por dónde están. Una sombra siempre cae DEBAJO del objeto que la produce.
///
///   Entonces se recorre la imagen en columnas, de izquierda a derecha, como
///   pasando un peine. En cada columna se busca el punto más bajo que sea escudo
///   de verdad. Todo lo que quede por debajo de ese punto es sombra y se borra,
///   sin importar de qué color sea.
///
///   Y ahí el corte sí es limpio: mirando cada columna, el material del escudo
///   siempre termina por debajo de 100 y la sombra recién empieza en 125. Ese
///   hueco vacío entre 100 y 125 es la frontera, y por eso el corte no le come
///   nada al escudo.
///
///   Las últimas rayas se desvanecen de a poco en vez de cortarse de golpe, para
///   que el filo de abajo del escudo no quede serruchado.
img.Image _quitarLaSombra(img.Image original, img.Image imagen) {
  final ancho = imagen.width;
  final alto = imagen.height;
  var borrados = 0;

  for (var x = 0; x < ancho; x++) {
    // El punto más bajo de esta columna que es escudo de verdad
    var fondoDelEscudo = -1;
    for (var y = alto - 1; y >= 0; y--) {
      if (imagen.getPixel(x, y).a < 8) continue; // ya se borró en el paso 1
      final p = original.getPixel(x, y);
      final masOscuro = math.min(p.r, math.min(p.g, p.b));
      if (masOscuro < _umbralDeEscudo) {
        fondoDelEscudo = y;
        break;
      }
    }

    // Si en toda la columna no hay nada oscuro, es que el escudo no pasa por
    // acá: lo que haya es sombra suelta y se va entero.
    if (fondoDelEscudo < 0) {
      for (var y = 0; y < alto; y++) {
        if (imagen.getPixel(x, y).a == 0) continue;
        imagen.setPixelRgba(x, y, 0, 0, 0, 0);
        borrados++;
      }
      continue;
    }

    // Todo lo que está más abajo se desvanece hasta desaparecer
    for (var y = fondoDelEscudo + 1; y < alto; y++) {
      final p = imagen.getPixel(x, y);
      if (p.a == 0) continue;

      final distancia = y - fondoDelEscudo;
      if (distancia > _desvanecidoBajoElEscudo) {
        imagen.setPixelRgba(x, y, 0, 0, 0, 0);
        borrados++;
        continue;
      }

      // Dentro del desvanecido se desaparece por dos motivos a la vez:
      // por estar lejos del escudo, y por ser claro. Así el filo oscuro del
      // escudo aguanta, y el gris de la sombra que quedaba mezclado se va.
      final porDistancia = 1 - (distancia / (_desvanecidoBajoElEscudo + 1));
      final masOscuro = math.min(p.r, math.min(p.g, p.b));
      final porOscuridad = (255 - masOscuro) / 255;

      imagen.setPixelRgba(
        x, y, p.r.toInt(), p.g.toInt(), p.b.toInt(),
        (p.a * porDistancia * porOscuridad).round(),
      );
    }
  }

  final porcentaje = (borrados * 100 / (ancho * alto)).toStringAsFixed(1);
  stdout.writeln('Sombra borrada: $porcentaje% más de la imagen');
  return imagen;
}

// ---- Paso 3: recortar los márgenes ----------------------------------------

/// Corta el espacio vacío que rodea al escudo, para que quede justo a su medida.
/// Sin esto, el escudo se vería más chico de lo previsto dentro del ícono.
img.Image _recortarMargenes(img.Image imagen) {
  var izq = imagen.width, der = -1, arr = imagen.height, aba = -1;

  for (var y = 0; y < imagen.height; y++) {
    for (var x = 0; x < imagen.width; x++) {
      if (imagen.getPixel(x, y).a < 8) continue; // sigue siendo vacío
      if (x < izq) izq = x;
      if (x > der) der = x;
      if (y < arr) arr = y;
      if (y > aba) aba = y;
    }
  }

  if (der < 0) {
    stderr.writeln('Quedó todo transparente: el logo se borró entero.');
    stderr.writeln('Probablemente el fondo no era blanco. Revisá el original.');
    exit(1);
  }

  return img.copyCrop(
    imagen,
    x: izq,
    y: arr,
    width: der - izq + 1,
    height: aba - arr + 1,
  );
}

// ---- Paso 3: armar los cuadrados ------------------------------------------

/// Arma un cuadrado de 1024x1024 con el escudo centrado adentro.
img.Image _armarCuadrado(
  img.Image escudo,
  double proporcion, {
  required bool conFondo,
}) {
  final lienzo = img.Image(width: _lado, height: _lado, numChannels: 4);

  if (conFondo) {
    img.fill(lienzo, color: img.ColorRgba8(_grafitoR, _grafitoG, _grafitoB, 255));
  } else {
    // Transparente: Android le pone el fondo grafito por su cuenta.
    img.fill(lienzo, color: img.ColorRgba8(0, 0, 0, 0));
  }

  // El escudo es más alto que ancho. Se escala por el lado más largo para que
  // entre entero en el espacio disponible, sin deformarse.
  final disponible = _lado * proporcion;
  final escala = disponible /
      (escudo.width > escudo.height ? escudo.width : escudo.height);

  final ajustado = img.copyResize(
    escudo,
    width: (escudo.width * escala).round(),
    height: (escudo.height * escala).round(),
    interpolation: img.Interpolation.cubic, // bordes suaves al achicar
  );

  img.compositeImage(
    lienzo,
    ajustado,
    dstX: ((_lado - ajustado.width) / 2).round(),
    dstY: ((_lado - ajustado.height) / 2).round(),
  );

  return lienzo;
}

void _escribir(String ruta, img.Image imagen, String descripcion) {
  File(ruta).writeAsBytesSync(img.encodePng(imagen));
  final kb = (File(ruta).lengthSync() / 1024).round();
  stdout.writeln('  $ruta  ($kb KB)');
  stdout.writeln('      $descripcion');
}
