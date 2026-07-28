// ============================================================================
// Tomass Seguridad — Fabricante de los carteles del muro
// ============================================================================
// QUÉ HACE ESTE ARCHIVO
//
//   Arma los carteles con código QR que se pegan en la entrada de cada
//   instalación. Es lo que convierte una pared en una puerta del sistema.
//
//   ENTRA:  carteles/entradas.json          la lista de entradas y sus códigos
//
//   SALE:   carteles/carteles-para-imprimir.html
//           Un archivo que se abre con doble clic en cualquier navegador.
//           Un cartel por hoja, listo para imprimir o guardar como PDF.
//
// POR QUÉ UNA PÁGINA WEB Y NO UN PDF DIRECTO
//
//   Porque un PDF necesitaría otra librería más, y el resultado sería el mismo:
//   cualquier navegador imprime esta página o la guarda como PDF con dos clics.
//   Menos piezas, menos cosas que se pueden romper con el tiempo.
//
// EL ARCHIVO NO NECESITA INTERNET
//
//   Todo va adentro: el logo, los códigos QR dibujados y los estilos. Se puede
//   copiar a un pendrive y llevarlo a imprimir a cualquier lado, aunque en la
//   imprenta no haya señal.
//
// CÓMO SE USA
//
//   Parado en la carpeta app/, corré:
//
//       dart run herramientas/generar_carteles.dart
//
//   Después abrí carteles/carteles-para-imprimir.html y presioná Ctrl+P.
//   Las instrucciones completas están en carteles/LEEME.txt.
// ============================================================================

import 'dart:convert';
import 'dart:io';

import 'package:qr/qr.dart';

// ---- Configuración ---------------------------------------------------------

const String _carpeta = '../carteles';
const String _salida = '$_carpeta/carteles-para-imprimir.html';
const String _logo = 'assets/imagenes/logo.png';

/// Cuánta suciedad aguanta el código QR antes de dejar de leerse.
///
/// Se usa el nivel más alto (H) a propósito. Estos carteles viven a la
/// intemperie: se les cae polvo, los raya el sol, alguien los toca con la mano
/// sucia. Con este nivel, el código se sigue leyendo aunque se arruine hasta un
/// tercio de su superficie.
///
/// El precio es que el dibujo queda más apretado, pero como el cartel es una
/// hoja entera, sobra espacio.
const int _resistenciaASuciedad = QrErrorCorrectLevel.H;

// ---- Programa --------------------------------------------------------------

void main() {
  final archivo = File('$_carpeta/entradas.json');
  if (!archivo.existsSync()) {
    stderr.writeln('No encontré la lista de entradas en $_carpeta/entradas.json');
    stderr.writeln('Ojo: hay que correr este programa parado en la carpeta app/');
    exit(1);
  }

  final datos = jsonDecode(archivo.readAsStringSync()) as Map<String, dynamic>;
  final entradas = (datos['entradas'] as List).cast<Map<String, dynamic>>();

  if (entradas.isEmpty) {
    stderr.writeln('La lista de entradas está vacía. No hay nada que imprimir.');
    exit(1);
  }

  // Se revisa ANTES de dibujar nada: un cartel con el código repetido o vacío
  // se imprime igual de lindo y no funciona, y eso no se nota hasta que alguien
  // está parado en la puerta.
  _revisarLosCodigos(entradas);

  final logoIncrustado = _leerLogo();
  final carteles = entradas.map(_armarCartel).join('\n');

  File(_salida).writeAsStringSync(_paginaCompleta(
    carteles: carteles,
    logo: logoIncrustado,
    cuantos: entradas.length,
  ));

  final kb = (File(_salida).lengthSync() / 1024).round();
  stdout.writeln('');
  stdout.writeln('Listo: ${entradas.length} carteles ($kb KB)');
  stdout.writeln('  $_salida');
  stdout.writeln('');
  for (final e in entradas) {
    stdout.writeln('  · ${e['instalacion']} — ${e['entrada']}');
  }
  stdout.writeln('');
  stdout.writeln('Abrí ese archivo con doble clic y presioná Ctrl+P para imprimir.');
}

/// Revisa que los códigos sirvan, antes de gastar papel.
void _revisarLosCodigos(List<Map<String, dynamic>> entradas) {
  final vistos = <String, String>{};
  final problemas = <String>[];

  for (final e in entradas) {
    final donde = '${e['instalacion']} — ${e['entrada']}';
    final codigo = (e['codigo'] as String?)?.trim() ?? '';

    if (codigo.isEmpty) {
      problemas.add('$donde: no tiene código.');
      continue;
    }

    // Los códigos de práctica del condominio de prueba no sirven en la calle
    if (codigo.startsWith('demo_')) {
      problemas.add('$donde: es un código de práctica, no sirve de verdad.');
      continue;
    }

    if (vistos.containsKey(codigo)) {
      problemas.add('$donde: tiene el MISMO código que ${vistos[codigo]}. '
          'Dos entradas con el mismo código se confunden entre sí.');
      continue;
    }

    vistos[codigo] = donde;
  }

  if (problemas.isEmpty) return;

  stderr.writeln('No se generó nada. Hay que arreglar esto primero:');
  stderr.writeln('');
  for (final p in problemas) {
    stderr.writeln('  · $p');
  }
  exit(1);
}

/// Mete el logo adentro del archivo, para que no dependa de nada de afuera.
String _leerLogo() {
  final archivo = File(_logo);
  if (!archivo.existsSync()) {
    stderr.writeln('Aviso: no encontré $_logo, los carteles van sin el escudo.');
    return '';
  }
  return 'data:image/png;base64,${base64Encode(archivo.readAsBytesSync())}';
}

// ---- El código QR ----------------------------------------------------------

/// Dibuja el código QR como un dibujo de líneas, no como una foto.
///
/// La diferencia importa al imprimir: una foto se pixela si se agranda, y el
/// cartel va a hoja completa. Un dibujo de líneas sale nítido en cualquier
/// tamaño, desde una hoja carta hasta un cartel de un metro.
String _dibujarQr(String contenido) {
  final codigo = QrCode.fromData(
    data: contenido,
    errorCorrectLevel: _resistenciaASuciedad,
  );
  final imagen = QrImage(codigo);
  final lado = imagen.moduleCount;

  // El marco blanco alrededor no es decoración: la norma del código QR lo
  // exige. Sin ese respiro, muchos lectores no encuentran dónde empieza.
  const marco = 4;
  final total = lado + marco * 2;

  final trazo = StringBuffer();
  for (var fila = 0; fila < lado; fila++) {
    for (var col = 0; col < lado; col++) {
      if (!imagen.isDark(fila, col)) continue;
      trazo.write('M${col + marco} ${fila + marco}h1v1h-1z');
    }
  }

  return '<svg class="qr" viewBox="0 0 $total $total" '
      'xmlns="http://www.w3.org/2000/svg" shape-rendering="crispEdges">'
      '<rect width="$total" height="$total" fill="#fff"/>'
      '<path d="$trazo" fill="#000"/>'
      '</svg>';
}

// ---- Las palabras de cada tipo de instalación ------------------------------

/// Cómo se le dice a la gente que vive o estudia ahí.
///
/// Es la misma idea que la función palabras_de_la_instalacion de la base de
/// datos: a un colegio no se le habla de "residentes".
String _quienEntra(String tipo) => switch (tipo) {
      'colegio' => 'Apoderados y visitas',
      'empresa' => 'Trabajadores y visitas',
      _ => 'Residentes y visitas',
    };

/// A quién recurrir si alguien no tiene la app.
String _aQuienAvisar(String tipo) => switch (tipo) {
      'colegio' => 'Acercate a portería y avisá al guardia.',
      _ => 'Tocá el timbre o avisá al guardia de la garita.',
    };

// ---- Un cartel -------------------------------------------------------------

String _armarCartel(Map<String, dynamic> e) {
  final esVehicular = e['tipo_entrada'] == 'vehicular';
  final tipo = e['tipo'] as String;
  final codigo = (e['codigo'] as String).trim();

  // Los pasos dicen EXACTAMENTE lo que dicen los botones de la app. Si el
  // cartel manda a tocar algo que en la pantalla se llama distinto, la persona
  // se queda mirando el teléfono sin encontrarlo.
  final pasos = <String>[
    if (esVehicular) 'Detené el auto <b>antes</b> de la barrera.',
    'Abrí la app <b>Tomass Seguridad</b> en tu celular.',
    'Arriba, elegí <b>${esVehicular ? 'VEHICULAR' : 'PEATONAL'}</b>.',
    'Tocá <b>«Escanear QR de la ${esVehicular ? 'barrera' : 'entrada'}»</b>.',
    'Apuntá la cámara a este código. Se lee solo.',
  ];

  final listaDePasos = pasos
      .asMap()
      .entries
      .map((p) => '<li><span class="n">${p.key + 1}</span>'
          '<span class="t">${p.value}</span></li>')
      .join();

  return '''
  <section class="cartel">
    <header class="banda">
      <div class="escudo"></div>
      <div class="marca">
        <div class="m1">TOMASS SEGURIDAD</div>
        <div class="m2">Control de acceso</div>
      </div>
      <div class="tipoEntrada">${esVehicular ? 'VEHICULAR' : 'PEATONAL'}</div>
    </header>

    <div class="lugar">
      <h1>${_escapar(e['instalacion'] as String)}</h1>
      <h2>${_escapar(e['entrada'] as String)}</h2>
      <p class="quien">${_quienEntra(tipo)}</p>
    </div>

    <div class="cuadroQr">
      ${_dibujarQr(codigo)}
    </div>

    <div class="pasos">
      <h3>Para entrar</h3>
      <ol>$listaDePasos</ol>
    </div>

    <div class="sinApp">
      <b>¿No tenés la app?</b> ${_aQuienAvisar(tipo)}
    </div>

    <footer class="pie">
      <span>${_escapar(e['nombre_corto'] as String? ?? e['instalacion'] as String)}
        · ${_escapar(e['ubicacion'] as String? ?? '')}</span>
      <span class="codigo">$codigo</span>
    </footer>
  </section>''';
}

/// Evita que un nombre con un signo raro (&, <, >) rompa la página.
String _escapar(String texto) => texto
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;');

// ---- La página entera ------------------------------------------------------

String _paginaCompleta({
  required String carteles,
  required String logo,
  required int cuantos,
}) {
  final hoy = DateTime.now();
  final fecha = '${hoy.day.toString().padLeft(2, '0')}/'
      '${hoy.month.toString().padLeft(2, '0')}/${hoy.year}';

  final html = '''<!doctype html>
<html lang="es">
<head>
<meta charset="utf-8">
<title>Carteles para imprimir — Tomass Seguridad</title>
<style>
  /* Márgenes de la hoja. Sirven igual para tamaño Carta y para A4. */
  @page { margin: 12mm; }

  * { box-sizing: border-box; margin: 0; padding: 0; }

  body {
    font-family: "Segoe UI", system-ui, -apple-system, Arial, sans-serif;
    color: #1B1D22;
    background: #E8E9EC;
    -webkit-print-color-adjust: exact;
    print-color-adjust: exact;
  }

  /* ---- La hoja de instrucciones: se ve en pantalla, NO se imprime ---- */
  .instrucciones {
    max-width: 186mm;
    margin: 24px auto;
    padding: 26px 30px;
    background: #fff;
    border-radius: 10px;
    border-left: 6px solid #1C1E24;
    line-height: 1.65;
    font-size: 14px;
  }
  .instrucciones h1 { font-size: 20px; margin-bottom: 4px; }
  .instrucciones h2 { font-size: 14px; margin: 18px 0 6px; color: #1C1E24; }
  .instrucciones p, .instrucciones li { color: #40444C; }
  .instrucciones ol, .instrucciones ul { margin-left: 20px; }
  .instrucciones li { margin: 3px 0; }
  .aviso {
    margin-top: 18px; padding: 12px 14px;
    background: #FDF3E7; border-left: 4px solid #EF6C00;
    border-radius: 4px; font-size: 13.5px;
  }

  /* ---- Un cartel = una hoja ---- */
  .cartel {
    width: 186mm;
    min-height: 250mm;
    margin: 20px auto;
    padding: 0;
    background: #fff;
    display: flex;
    flex-direction: column;
    align-items: center;
    border-radius: 6px;
    overflow: hidden;
  }

  .banda {
    width: 100%;
    background: #1C1E24;
    color: #fff;
    padding: 7mm 9mm;
    display: flex;
    align-items: center;
    gap: 5mm;
  }
  /* El escudo se incrusta acá, UNA sola vez, y los diez carteles lo reusan.
     Pegado en cada cartel, el archivo pesaría diez veces más. El escudo mide
     523 x 599, por eso el ancho es un poco menor que el alto. */
  .escudo {
    flex: 0 0 auto;
    height: 15mm; width: 13.1mm;
    background: url(LOGO_AQUI) center / contain no-repeat;
  }
  .marca { flex: 1; }
  .m1 { font-size: 15pt; font-weight: 800; letter-spacing: 1.2px; }
  .m2 { font-size: 8.5pt; opacity: .62; letter-spacing: 2.4px;
        text-transform: uppercase; margin-top: 1mm; }
  .tipoEntrada {
    font-size: 9pt; font-weight: 800; letter-spacing: 1.6px;
    border: 1.5px solid rgba(255,255,255,.55);
    border-radius: 3mm; padding: 1.8mm 4mm;
  }

  .lugar { text-align: center; padding: 8mm 9mm 0; }
  .lugar h1 { font-size: 25pt; font-weight: 800; line-height: 1.12; }
  .lugar h2 { font-size: 14pt; font-weight: 600; color: #55595F;
              margin-top: 2mm; }
  .quien {
    display: inline-block; margin-top: 4mm;
    font-size: 10pt; font-weight: 700; letter-spacing: .6px;
    text-transform: uppercase; color: #1C1E24;
    background: #EFF0F2; border-radius: 20mm; padding: 2mm 6mm;
  }

  .cuadroQr { padding: 7mm 0 6mm; }
  .qr { width: 92mm; height: 92mm; display: block; }

  .pasos { width: 100%; padding: 0 14mm; }
  .pasos h3 {
    font-size: 11pt; font-weight: 800; letter-spacing: 2px;
    text-transform: uppercase; color: #1C1E24;
    text-align: center; margin-bottom: 4mm;
  }
  .pasos ol { list-style: none; }
  .pasos li {
    display: flex; align-items: flex-start; gap: 4mm;
    margin-bottom: 3mm; font-size: 12.5pt; line-height: 1.4;
  }
  .pasos .n {
    flex: 0 0 auto;
    width: 7mm; height: 7mm; border-radius: 50%;
    background: #1C1E24; color: #fff;
    font-size: 10pt; font-weight: 800;
    display: flex; align-items: center; justify-content: center;
  }
  .pasos .t { padding-top: .6mm; }

  .sinApp {
    margin: 6mm 14mm 0; padding: 4mm 6mm;
    background: #F4F5F6; border-left: 4px solid #55595F;
    border-radius: 2mm; font-size: 11pt; color: #40444C;
  }

  .pie {
    margin-top: auto; width: 100%;
    padding: 5mm 9mm; border-top: 1px solid #E2E4E8;
    display: flex; justify-content: space-between; align-items: center;
    font-size: 8pt; color: #9AA0A8;
  }
  .codigo { font-family: Consolas, "Courier New", monospace; letter-spacing: .4px; }

  /* ---- Lo que cambia al imprimir ---- */
  @media print {
    body { background: #fff; }
    .instrucciones { display: none; }
    .cartel {
      margin: 0;
      border-radius: 0;
      width: 100%;
      min-height: auto;
      height: 100%;
      page-break-after: always;
      break-after: page;
    }
    .cartel:last-of-type { page-break-after: auto; break-after: auto; }
  }
</style>
</head>
<body>

<div class="instrucciones">
  <h1>Carteles del muro — Tomass Seguridad</h1>
  <p>Generados el $fecha. Son <b>$cuantos carteles</b>, uno por hoja.</p>

  <h2>Para imprimir</h2>
  <ol>
    <li>Presioná <b>Ctrl+P</b> (o Cmd+P en Mac).</li>
    <li>En «Más ajustes», activá <b>Gráficos de fondo</b>. Sin eso la franja
        negra de arriba sale en blanco.</li>
    <li>Dejá la escala en <b>100%</b>, no en «Ajustar al papel».</li>
    <li>Para llevar a una imprenta, elegí <b>Guardar como PDF</b> en vez de una
        impresora.</li>
  </ol>

  <h2>Antes de pegarlos</h2>
  <ul>
    <li><b>Plastificalos.</b> Van a estar a la intemperie: sol, lluvia y manos
        sucias. Un cartel de papel dura semanas; plastificado, años.</li>
    <li><b>Cartel peatonal:</b> a la altura de los ojos, entre 1,40 y 1,60 m del
        suelo, junto al portón.</li>
    <li><b>Cartel vehicular:</b> más bajo, entre 1,00 y 1,20 m, para que se
        alcance desde la ventanilla del auto sin bajarse.</li>
    <li>Que no le pegue el sol de frente todo el día: el reflejo sobre el
        plástico no deja leer el código con la cámara.</li>
  </ul>

  <div class="aviso">
    <b>Cada cartel es distinto y no son intercambiables.</b> El código de cada
    hoja pertenece a una entrada puntual. Si se pega el cartel de la entrada
    vehicular en la peatonal, el sistema va a registrar todas las entradas en el
    lugar equivocado. Antes de pegar, mirá el pie de la hoja: ahí dice a qué
    instalación y a qué entrada corresponde.
  </div>
</div>

$carteles

</body>
</html>
''';

  // El escudo entra recién acá, en el único lugar del CSS que lo pide. Se usa
  // un marcador y no la imagen directa porque el texto del logo mide 300.000
  // letras y haría ilegible la plantilla de arriba.
  return html.replaceFirst('LOGO_AQUI', logo);
}
