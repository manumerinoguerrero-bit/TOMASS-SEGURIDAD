// ============================================================================
// Tomass Seguridad — Pack mensual consolidado para el mandante
// ============================================================================
// Genera un ZIP con los 5 informes del mes en PDF, listo para pasarle al
// mandante al cierre del mes:
//
//   01-ingresos-YYYY-MM.pdf      — accesos del período
//   02-turnos-YYYY-MM.pdf        — qué guardia estuvo cuándo + KPIs
//   03-rondas-YYYY-MM.pdf        — rondas con marcas en mapa
//   04-novedades-YYYY-MM.pdf     — incidentes reportados
//   05-encomiendas-YYYY-MM.pdf   — encomiendas entregadas
//   LEEME.txt                    — explicación de qué contiene el pack
//
// La generación tarda varios minutos para un mes entero: bajar selfies de
// turnos y fotos de novedades es la parte lenta. Por eso el método acepta
// un callback [alProgresar] para que la UI pueda mostrar qué está haciendo.
//
// POR QUÉ ZIP Y NO PDF ÚNICO
//
//   Un PDF de 100 páginas es incómodo de abrir en celular. El mandante en
//   general solo quiere ver UN capítulo (p.ej. las novedades) y después
//   archivar el resto; con 5 archivos separados puede abrir solo el que
//   necesita. El ZIP se abre nativo en WhatsApp, Gmail, Drive e iOS/Android.
//
// FOTOS Y FIRMAS DE ENCOMIENDAS SÍ VAN EN EL PACK
//
//   La versión anterior las omitía para ahorrar tiempo, pero el mandante
//   necesita verlas en el informe mensual (son la prueba de la entrega
//   junto con la firma del residente). Se bajan en tandas de 5 en paralelo,
//   igual que el informe individual de encomiendas. Sí, agrega minutos a
//   la generación cuando hay 100+ paquetes; es el costo de tener un
//   respaldo completo en un solo pack.
// ============================================================================

import 'dart:typed_data';

import 'package:archive/archive.dart';

import 'informe_encomiendas_pdf.dart';
import 'informe_incidentes_pdf.dart';
import 'informe_ingresos_pdf.dart';
import 'informe_pdf.dart';
import 'informe_turnos_pdf.dart';
import 'servicio_admin.dart';
import 'servicio_fotos.dart';

typedef AlProgresar = void Function(String seccion);

class PackMensualPdf {
  const PackMensualPdf._();

  /// Arma el ZIP con los 5 PDFs y devuelve sus bytes.
  ///
  /// [alProgresar] se llama antes de arrancar cada sección con el nombre
  /// de lo que está haciendo ('Accesos', 'Turnos', etc.). Sirve para que
  /// la UI muestre "Generando 3 de 5…" sin que el servicio dependa de
  /// Riverpod ni de un widget.
  static Future<Uint8List> armar({
    required int anio,
    required int mes,
    required String instalacion,
    required ServicioAdmin admin,
    required ServicioFotos servicioFotos,
    AlProgresar? alProgresar,
  }) async {
    // Rango del mes en hora LOCAL. desde = primer día 00:00, hasta = último
    // día 23:59:59.999. Los generadores aceptan ambos como absolutos y los
    // convierten a UTC internamente al armar los filtros.
    final desde = DateTime(anio, mes, 1, 0, 0, 0);
    final hasta =
        DateTime(anio, mes + 1, 1, 0, 0, 0).subtract(const Duration(seconds: 1));
    final dias = hasta.difference(desde).inDays + 1;
    final sufijo =
        '${anio.toString().padLeft(4, '0')}-${mes.toString().padLeft(2, '0')}';

    final archive = Archive();

    // ---- 1. INGRESOS ----
    alProgresar?.call('Accesos');
    final movimientos =
        await admin.movimientos(desde: desde, hasta: hasta);
    final ingresosBytes = await InformeDeIngresosPdf.armar(
      instalacion: instalacion,
      desde: desde,
      hasta: hasta,
      movimientos: movimientos,
    );
    _agregar(archive, '01-ingresos-$sufijo.pdf', ingresosBytes);

    // ---- 2. TURNOS ----
    alProgresar?.call('Turnos (bajando selfies)');
    final (statsTurnos, turnosEnriquecidos) =
        await admin.estadisticasTurnos(desde: desde, hasta: hasta);
    final turnosBytes = await InformeDeTurnosPdf.armar(
      instalacion: instalacion,
      turnos: turnosEnriquecidos,
      servicioFotos: servicioFotos,
      stats: statsTurnos,
    );
    _agregar(archive, '02-turnos-$sufijo.pdf', turnosBytes);

    // ---- 3. RONDAS ----
    alProgresar?.call('Rondas');
    final rondasInforme =
        await admin.informeDeRondas(desde: desde, hasta: hasta);
    final marcas = await admin.detalleDeRondas(desde: desde, hasta: hasta);
    final sectores = await admin.sectoresParaElPlano();
    final rondasBytes = await InformeDeRondasPdf.armar(
      instalacion: instalacion,
      dias: dias,
      rondas: rondasInforme,
      marcas: marcas,
      sectores: sectores,
      // 2 horas entre rondas es el default del sistema (minutos_entre_rondas
      // en condominios). Si en el futuro cambia por instalación, se puede
      // leer del resumen admin.
      minutosEntreRondas: 120,
    );
    _agregar(archive, '03-rondas-$sufijo.pdf', rondasBytes);

    // ---- 4. NOVEDADES ----
    alProgresar?.call('Novedades (bajando fotos)');
    final incidentes = await admin.incidentesDelPeriodo(
      desde: desde,
      hasta: hasta,
    );
    final incidentesBytes = await InformeDeIncidentesPdf.armar(
      instalacion: instalacion,
      desde: desde,
      hasta: hasta,
      incidentes: incidentes,
      servicioFotos: servicioFotos,
    );
    _agregar(archive, '04-novedades-$sufijo.pdf', incidentesBytes);

    // ---- 5. ENCOMIENDAS ----
    alProgresar?.call('Encomiendas');
    final encomiendas = await admin.encomiendasEntregadas(
      desde: desde,
      hasta: hasta,
    );

    // Las tres pruebas visuales por entrega (recepción, entrega, firma) en
    // tandas de 5 en paralelo: una por una va lento, todas juntas satura la
    // conexión. Mismo patrón que informe_de_encomiendas.
    final fotosRecepcion = <String, Uint8List>{};
    final fotosEntrega = <String, Uint8List>{};
    final firmas = <String, Uint8List>{};
    const tandasDe = 5;
    var hechas = 0;
    for (var i = 0; i < encomiendas.length; i += tandasDe) {
      final grupo = encomiendas.skip(i).take(tandasDe).toList();
      final resultados = await Future.wait(grupo.map((e) async {
        final recepcion = servicioFotos.bytesParaPdf(
            e.fotoUrl, CajonDeFotos.paquetes);
        final entrega = e.fotoEntregaUrl != null
            ? servicioFotos.bytesParaPdf(
                e.fotoEntregaUrl, CajonDeFotos.paquetes)
            : Future<Uint8List?>.value(null);
        final firma = e.tieneFirma
            ? servicioFotos.bytesParaPdf(e.firmaUrl, CajonDeFotos.firmas)
            : Future<Uint8List?>.value(null);
        final (rb, eb, sb) = await (recepcion, entrega, firma).wait;
        return (id: e.id, recepcion: rb, entrega: eb, firmaBytes: sb);
      }));
      for (final r in resultados) {
        if (r.recepcion != null) fotosRecepcion[r.id] = r.recepcion!;
        if (r.entrega != null) fotosEntrega[r.id] = r.entrega!;
        if (r.firmaBytes != null) firmas[r.id] = r.firmaBytes!;
        hechas++;
      }
      alProgresar?.call(
          'Encomiendas (bajando fotos y firmas $hechas de ${encomiendas.length})');
    }

    final encomiendasBytes = await InformeDeEncomiendasPdf.armar(
      instalacion: instalacion,
      dias: dias,
      encomiendas: encomiendas,
      fotosRecepcion: fotosRecepcion,
      fotosEntrega: fotosEntrega,
      firmas: firmas,
    );
    _agregar(archive, '05-encomiendas-$sufijo.pdf', encomiendasBytes);

    // ---- LEEME ----
    final leeme = _leeme(instalacion, anio, mes);
    final leemeBytes = Uint8List.fromList(leeme.codeUnits);
    _agregar(archive, 'LEEME.txt', leemeBytes);

    alProgresar?.call('Empaquetando');
    // ZipEncoder.encode() devuelve List<int>?: devuelve null solo si el
    // archive está vacío, cosa que acá no puede pasar porque siempre
    // agregamos al menos los 5 PDFs y el LEEME.
    final zipBytes = ZipEncoder().encode(archive) ?? const <int>[];
    return Uint8List.fromList(zipBytes);
  }

  static void _agregar(Archive a, String nombre, Uint8List bytes) {
    final file = ArchiveFile(nombre, bytes.length, bytes);
    a.addFile(file);
  }

  static String _leeme(String instalacion, int anio, int mes) {
    final mesTxt = _nombreMes(mes);
    return '''
TOMASS SEGURIDAD PRIVADA
Informe mensual consolidado · $instalacion
Período: $mesTxt de $anio

Qué contiene este pack:

  01-ingresos      Todas las entradas y salidas registradas en el mes,
                   con fecha, hora, nombre, tipo (peatonal o vehicular),
                   y quién autorizó cada ingreso.

  02-turnos        Qué guardia estuvo a cargo en cada período, con
                   selfies al abrir el turno, estadísticas de cumplimiento
                   y ranking.

  03-rondas        Las rondas que hicieron los guardias, con mapa y
                   marcación de cada sector del recorrido. Los puntos
                   verdes son marcas dentro de la tolerancia; los rojos,
                   marcas desde más lejos.

  04-novedades     Las novedades que reportaron los guardias en el mes
                   (puertas abiertas, autos extraños, incidentes de
                   convivencia), con las fotos adjuntas.

  05-encomiendas   Las encomiendas entregadas en el mes, con la foto del
                   paquete y la firma del residente al retirarlo. Si una
                   fila aparece como "sin foto" o "sin firma" es porque
                   el guardia no las capturó al entregar (entregas viejas
                   previas a la función de firma, o cortes de conexión).

Los registros no se pueden modificar ni borrar: la base de datos lo
impide. Por eso sirven como respaldo.
''';
  }

  static String _nombreMes(int mes) {
    const nombres = [
      'enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio',
      'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre',
    ];
    if (mes < 1 || mes > 12) return 'mes';
    return nombres[mes - 1];
  }
}
