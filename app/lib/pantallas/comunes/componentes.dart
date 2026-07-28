// ============================================================================
// Tomass Seguridad — Piezas visuales que se repiten
// ============================================================================
// Todo lo que aparece en más de una pantalla vive acá: el logo, el avatar, los
// avisos de error. Así se ven iguales en toda la app y se arreglan en un solo
// lugar.
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/tema.dart';
import '../../estado/proveedores.dart';
import '../../nucleo/errores.dart';
import '../../servicios/servicio_fotos.dart';

// ============================================================================
// EL LOGO
// ============================================================================
// El escudo de Tomass Seguridad Privada, tal como se ve en la pantalla de
// inicio y en la de turno del guardia.
//
// El archivo sale de  assets/imagenes/logo.png  y NO se edita a mano: se
// fabrica a partir del logo original de la empresa. Si algún día cambia el
// logo, los pasos están en  marca/LEEME.txt.
//
// ⚠️ EL NOMBRE DEL ARCHIVO VA EN MINÚSCULAS, SIEMPRE.
//
//    Windows trata igual a "LOGO.png" y "logo.png", pero Android y el servidor
//    de GitHub que compila la app NO. Con el nombre en mayúsculas la app
//    compila igual, se instala igual, y recién en el teléfono aparece sin
//    logo. Ya nos pasó una vez.
//
// SI EL ARCHIVO FALTARA, más abajo hay un escudo dibujado con código que entra
// en su lugar. Es parecido pero simplificado: sirve para que la pantalla no
// muestre el ícono roto de imagen faltante, no para reemplazar al logo. El
// original tiene metal cepillado y degradados que no se reproducen dibujando.
// ============================================================================

class LogoTomass extends StatelessWidget {
  const LogoTomass({super.key, this.tamano = 80});

  final double tamano;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: tamano,
      height: tamano,
      child: Image.asset(
        'assets/imagenes/logo.png',
        fit: BoxFit.contain,
        // Si el archivo todavía no está, se dibuja el escudo de respaldo en
        // lugar de mostrar el ícono roto de imagen faltante.
        errorBuilder: (_, __, ___) => CustomPaint(
          painter: _EscudoDeRespaldo(),
          size: Size(tamano, tamano),
        ),
      ),
    );
  }
}

/// Escudo dibujado con código. Solo se usa si falta assets/imagenes/logo.png.
class _EscudoDeRespaldo extends CustomPainter {
  @override
  void paint(Canvas lienzo, Size medida) {
    final ancho = medida.width;
    final alto = medida.height;

    // ---- La silueta del escudo ----
    Path escudo(double margen) {
      final izq = ancho * margen;
      final der = ancho * (1 - margen);
      final arriba = alto * margen;
      final abajo = alto * (1 - margen * 0.5);
      final hombro = alto * 0.55;

      return Path()
        ..moveTo(izq, arriba + alto * 0.04)
        ..quadraticBezierTo(izq, arriba, izq + ancho * 0.05, arriba)
        ..lineTo(der - ancho * 0.05, arriba)
        ..quadraticBezierTo(der, arriba, der, arriba + alto * 0.04)
        ..lineTo(der, hombro)
        ..quadraticBezierTo(der, abajo - alto * 0.16, ancho / 2, abajo)
        ..quadraticBezierTo(izq, abajo - alto * 0.16, izq, hombro)
        ..close();
    }

    // Borde metálico oscuro
    lienzo.drawPath(
      escudo(0.06),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF4A4F57), Color(0xFF1E2126)],
        ).createShader(Rect.fromLTWH(0, 0, ancho, alto)),
    );

    // Cara roja del escudo
    lienzo.drawPath(
      escudo(0.13),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF9B1B2E), Color(0xFF6B1220)],
        ).createShader(Rect.fromLTWH(0, 0, ancho, alto)),
    );

    // ---- El monograma: una T con una E incrustada ----
    final metal = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF3C4149), Color(0xFF17191D)],
      ).createShader(Rect.fromLTWH(0, 0, ancho, alto));

    final centroX = ancho / 2;
    final grosor = ancho * 0.115;

    // Barra horizontal de la T
    lienzo.drawRect(
      Rect.fromLTWH(ancho * 0.27, alto * 0.26, ancho * 0.46, grosor),
      metal,
    );
    // Pata vertical de la T
    lienzo.drawRect(
      Rect.fromLTWH(centroX - grosor / 2, alto * 0.26, grosor, alto * 0.36),
      metal,
    );

    // Las tres barritas de la E, a la derecha de la pata
    final anchoE = ancho * 0.11;
    final altoE = alto * 0.026;
    for (final y in [0.335, 0.435, 0.535]) {
      lienzo.drawRect(
        Rect.fromLTWH(centroX + grosor / 2, alto * y, anchoE, altoE),
        metal,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter viejo) => false;
}

// ============================================================================
// AVATAR
// ============================================================================
// Muestra la foto de la persona. Si no tiene foto, muestra sus iniciales sobre
// un fondo gris, que es mucho mejor que un ícono genérico: se distingue de un
// vistazo de quién se trata.
// ============================================================================

class Avatar extends StatelessWidget {
  const Avatar({
    super.key,
    required this.iniciales,
    this.fotoUrl,
    this.tamano = 44,
    this.sobreFondoOscuro = false,
  });

  final String iniciales;
  final String? fotoUrl;
  final double tamano;
  final bool sobreFondoOscuro;

  @override
  Widget build(BuildContext context) {
    final fondo = sobreFondoOscuro
        ? Colors.white.withValues(alpha: 0.16)
        : Colores.grafito.withValues(alpha: 0.08);
    final textoColor = sobreFondoOscuro ? Colors.white : Colores.grafito;

    return Container(
      width: tamano,
      height: tamano,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: fondo,
        border: Border.all(
          color: sobreFondoOscuro
              ? Colors.white.withValues(alpha: 0.3)
              : Colores.linea,
        ),
        image: (fotoUrl != null && fotoUrl!.isNotEmpty)
            ? DecorationImage(
                image: NetworkImage(fotoUrl!),
                fit: BoxFit.cover,
              )
            : null,
      ),
      alignment: Alignment.center,
      child: (fotoUrl == null || fotoUrl!.isEmpty)
          ? Text(
              iniciales,
              style: TextStyle(
                fontSize: tamano * 0.36,
                fontWeight: FontWeight.w800,
                color: textoColor,
                letterSpacing: 0.3,
              ),
            )
          : null,
    );
  }
}

// ============================================================================
// FOTO GUARDADA EN EL SERVIDOR
// ============================================================================
// Las fotos del sistema son privadas: no tienen un enlace fijo. Este componente
// le pide al servidor un enlace temporal y después muestra la imagen.
//
// Mientras carga muestra un recuadro gris, y si la foto no existe muestra un
// marcador con un ícono. Nunca deja un hueco en blanco ni rompe la pantalla:
// una foto que falta no es motivo para que el residente no pueda ver el resto.
// ============================================================================

class FotoDelServidor extends ConsumerWidget {
  const FotoDelServidor({
    super.key,
    required this.ruta,
    required this.cajon,
    this.ancho,
    this.alto,
    this.redondeo = Medidas.redondeoChico,
    this.iconoSiFalta = Icons.image_not_supported_outlined,
  });

  final String? ruta;
  final CajonDeFotos cajon;
  final double? ancho;
  final double? alto;
  final double redondeo;
  final IconData iconoSiFalta;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Widget marco(Widget dentro) => ClipRRect(
          borderRadius: BorderRadius.circular(redondeo),
          child: SizedBox(width: ancho, height: alto, child: dentro),
        );

    Widget marcador({bool cargando = false}) => marco(
          ColoredBox(
            color: Colores.grafito.withValues(alpha: 0.06),
            child: Center(
              child: cargando
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colores.textoTenue,
                      ),
                    )
                  : Icon(iconoSiFalta, size: 20, color: Colores.textoTenue),
            ),
          ),
        );

    if (ruta == null || ruta!.isEmpty) return marcador();

    return FutureBuilder<String?>(
      future: ref.read(servicioFotosProvider).enlaceTemporal(ruta, cajon),
      builder: (context, resultado) {
        if (resultado.connectionState == ConnectionState.waiting) {
          return marcador(cargando: true);
        }
        final enlace = resultado.data;
        if (enlace == null) return marcador();

        return marco(
          Image.network(
            enlace,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => marcador(),
            loadingBuilder: (_, hijo, progreso) =>
                progreso == null ? hijo : marcador(cargando: true),
          ),
        );
      },
    );
  }
}

// ============================================================================
// PANTALLA VACÍA
// ============================================================================
// Qué mostrar cuando una lista no tiene nada. Nunca se deja en blanco: se
// explica por qué está vacía y qué se puede hacer.
// ============================================================================

class ListaVacia extends StatelessWidget {
  const ListaVacia({
    super.key,
    required this.icono,
    required this.titulo,
    required this.explicacion,
    this.accion,
  });

  final IconData icono;
  final String titulo;
  final String explicacion;
  final Widget? accion;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: Colores.grafito.withValues(alpha: 0.06),
                shape: BoxShape.circle,
              ),
              child: Icon(icono, size: 28, color: Colores.textoTenue),
            ),
            const SizedBox(height: 18),
            Text(
              titulo,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              explicacion,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13.5,
                height: 1.5,
                color: Colores.textoSuave,
              ),
            ),
            if (accion != null) ...[
              const SizedBox(height: 22),
              accion!,
            ],
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// AVISO DE ERROR
// ============================================================================
// Muestra un problema con su explicación y, si tiene sentido, un botón para
// intentar de nuevo. Nunca muestra jerga técnica.
// ============================================================================

class AvisoDeError extends StatelessWidget {
  const AvisoDeError({
    super.key,
    required this.problema,
    this.alReintentar,
    this.compacto = false,
  });

  final ErrorAmigable problema;
  final VoidCallback? alReintentar;
  final bool compacto;

  @override
  Widget build(BuildContext context) {
    final contenido = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.error_outline_rounded,
                color: Colores.rojo, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                problema.mensaje,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14.5,
                  color: Colores.texto,
                ),
              ),
            ),
          ],
        ),
        if (problema.detalle != null) ...[
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.only(left: 30),
            child: Text(
              problema.detalle!,
              style: const TextStyle(fontSize: 13, color: Colores.textoSuave),
            ),
          ),
        ],
        if (alReintentar != null && problema.sePuedeReintentar) ...[
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.only(left: 30),
            child: OutlinedButton.icon(
              onPressed: alReintentar,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Intentar de nuevo'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(0, 42),
                padding: const EdgeInsets.symmetric(horizontal: 16),
              ),
            ),
          ),
        ],
      ],
    );

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(compacto ? 12 : Medidas.margen),
      decoration: BoxDecoration(
        color: Colores.superficie,
        borderRadius: BorderRadius.circular(Medidas.redondeo),
        border: Border.all(color: Colores.rojo.withValues(alpha: 0.4)),
      ),
      child: contenido,
    );
  }
}

// ============================================================================
// ETIQUETA DE ESTADO
// ============================================================================

enum TonoEtiqueta { bueno, espera, malo, neutro }

class Etiqueta extends StatelessWidget {
  const Etiqueta({super.key, required this.texto, required this.tono, this.icono});

  final String texto;
  final TonoEtiqueta tono;
  final IconData? icono;

  @override
  Widget build(BuildContext context) {
    final (fondo, letra) = switch (tono) {
      TonoEtiqueta.bueno => (
          Colores.verde.withValues(alpha: 0.14),
          Colores.verdeOscuro
        ),
      TonoEtiqueta.espera => (
          Colores.naranja.withValues(alpha: 0.16),
          Colores.naranjaOscuro
        ),
      TonoEtiqueta.malo => (
          Colores.rojo.withValues(alpha: 0.13),
          Colores.rojoOscuro
        ),
      TonoEtiqueta.neutro => (
          Colores.grafito.withValues(alpha: 0.08),
          Colores.grafito
        ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: fondo,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icono != null) ...[
            Icon(icono, size: 12, color: letra),
            const SizedBox(width: 4),
          ],
          Text(
            texto.toUpperCase(),
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
              color: letra,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// RELOJ CIRCULAR DEL CÓDIGO
// ============================================================================
// El anillo que se va vaciando mientras el código pierde vigencia, con los
// segundos en el centro. Se pone naranja en los últimos 10 segundos para que el
// residente sepa que conviene esperar el siguiente antes de escanear.
// ============================================================================

class RelojDelCodigo extends StatelessWidget {
  const RelojDelCodigo({
    super.key,
    required this.segundosRestantes,
    required this.fraccion,
    this.tamano = 46,
  });

  final int segundosRestantes;
  final double fraccion;
  final double tamano;

  @override
  Widget build(BuildContext context) {
    final apurado = segundosRestantes <= 10;
    final color = apurado ? Colores.naranja : Colores.grafito;

    return SizedBox(
      width: tamano,
      height: tamano,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: tamano,
            height: tamano,
            child: CircularProgressIndicator(
              value: fraccion,
              strokeWidth: 4,
              backgroundColor: Colores.linea,
              valueColor: AlwaysStoppedAnimation(color),
              strokeCap: StrokeCap.round,
            ),
          ),
          Text(
            '$segundosRestantes',
            style: TextStyle(
              fontSize: tamano * 0.32,
              fontWeight: FontWeight.w800,
              color: color,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// MARCO DE ESCANEO
// ============================================================================
// Las cuatro esquinas verdes que le indican al residente dónde apuntar.
// ============================================================================

class MarcoDeEscaneo extends StatelessWidget {
  const MarcoDeEscaneo({super.key, this.lado = 240});

  final double lado;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: lado,
      height: lado,
      child: CustomPaint(painter: _PintorDelMarco()),
    );
  }
}

class _PintorDelMarco extends CustomPainter {
  @override
  void paint(Canvas lienzo, Size medida) {
    final trazo = Paint()
      ..color = Colores.verde
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;

    final largo = medida.width * 0.18;
    final r = 14.0;

    // Esquina superior izquierda
    lienzo.drawPath(
      Path()
        ..moveTo(0, largo)
        ..lineTo(0, r)
        ..arcToPoint(Offset(r, 0), radius: Radius.circular(r))
        ..lineTo(largo, 0),
      trazo,
    );
    // Superior derecha
    lienzo.drawPath(
      Path()
        ..moveTo(medida.width - largo, 0)
        ..lineTo(medida.width - r, 0)
        ..arcToPoint(Offset(medida.width, r), radius: Radius.circular(r))
        ..lineTo(medida.width, largo),
      trazo,
    );
    // Inferior derecha
    lienzo.drawPath(
      Path()
        ..moveTo(medida.width, medida.height - largo)
        ..lineTo(medida.width, medida.height - r)
        ..arcToPoint(Offset(medida.width - r, medida.height),
            radius: Radius.circular(r))
        ..lineTo(medida.width - largo, medida.height),
      trazo,
    );
    // Inferior izquierda
    lienzo.drawPath(
      Path()
        ..moveTo(largo, medida.height)
        ..lineTo(r, medida.height)
        ..arcToPoint(Offset(0, medida.height - r), radius: Radius.circular(r))
        ..lineTo(0, medida.height - largo),
      trazo,
    );

    // Línea de barrido al medio
    lienzo.drawLine(
      Offset(8, medida.height * 0.5),
      Offset(medida.width - 8, medida.height * 0.5),
      Paint()
        ..color = Colores.verde.withValues(alpha: 0.85)
        ..strokeWidth = 2
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter viejo) => false;
}
