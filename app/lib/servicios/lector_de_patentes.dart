// ============================================================================
// Tomass Seguridad — Lectura automática de la patente
// ============================================================================
// QUÉ HACE
//   El residente le saca una foto a la patente de su auto y la app lee el texto
//   sola. Después le muestra lo que leyó para que confirme o corrija.
//
// POR QUÉ SE LE PIDE QUE CONFIRME EN LUGAR DE CONFIAR
//   Ninguna lectura automática acierta el 100% de las veces. Una patente mal
//   cargada significa que el auto no va a poder entrar y que el residente va a
//   discutir con el guardia sin entender por qué. Que confirme un dato de 6
//   caracteres cuesta dos segundos y evita ese problema entero.
//
// CÓMO ELIGE ENTRE VARIOS TEXTOS
//   Una foto de un auto tiene texto por todos lados: la marca, el modelo, el
//   nombre de la automotora, un adhesivo. Así que no alcanza con "leer texto":
//   hay que buscar cuál de todos esos textos TIENE FORMA de patente chilena.
// ============================================================================

import 'dart:io';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../modelos/formato_patente.dart';

class PatenteLeida {
  const PatenteLeida({
    required this.patente,
    required this.confianza,
    this.textoCompleto,
  });

  /// La patente ya normalizada: "BCDF-12".
  final String patente;

  /// Qué tan seguro está el sistema, de 0 a 1. Sirve para decidir el mensaje
  /// que se le muestra al residente.
  final double confianza;

  /// Todo lo que se leyó en la foto. Solo para diagnóstico.
  final String? textoCompleto;

  bool get esConfiable => confianza >= 0.7;
}

class LectorDePatentes {
  LectorDePatentes();

  final TextRecognizer _lector =
      TextRecognizer(script: TextRecognitionScript.latin);

  /// Lee la patente de una foto. Devuelve null si no encontró nada con forma
  /// de patente.
  Future<PatenteLeida?> leer(File foto) async {
    try {
      final resultado = await _lector.processImage(InputImage.fromFile(foto));
      return _elegirLaPatente(resultado);
    } catch (_) {
      // Si la lectura falla, el residente igual puede escribir la patente a
      // mano. No es un error que valga la pena mostrarle.
      return null;
    }
  }

  PatenteLeida? _elegirLaPatente(RecognizedText resultado) {
    final candidatos = <(String, double)>[];

    // Se revisa cada línea de texto que encontró en la foto
    for (final bloque in resultado.blocks) {
      for (final linea in bloque.lines) {
        _evaluar(linea.text, candidatos);

        // También se prueban las palabras sueltas: a veces la patente queda
        // partida en dos porque el guion se lee como un espacio.
        final palabras = linea.elements.map((e) => e.text).toList();
        for (var i = 0; i < palabras.length; i++) {
          _evaluar(palabras[i], candidatos);
          if (i + 1 < palabras.length) {
            _evaluar('${palabras[i]}${palabras[i + 1]}', candidatos);
          }
        }
      }
    }

    if (candidatos.isEmpty) return null;

    // Se queda con el candidato de mayor puntaje
    candidatos.sort((a, b) => b.$2.compareTo(a.$2));
    final (mejor, puntaje) = candidatos.first;

    return PatenteLeida(
      patente: FormatoPatente.normalizar(mejor),
      confianza: puntaje,
      textoCompleto: resultado.text,
    );
  }

  /// Le pone puntaje a un texto según cuánto se parezca a una patente chilena.
  void _evaluar(String texto, List<(String, double)> candidatos) {
    final limpio = FormatoPatente.soloCaracteres(texto);

    // Muy corto o muy largo: no es una patente
    if (limpio.length < 5 || limpio.length > 6) return;

    // Formato exacto: es casi seguro la patente
    if (FormatoPatente.esValida(limpio)) {
      // Las de 6 (formato nuevo, desde 2007) son mucho más comunes hoy
      candidatos.add((limpio, limpio.length == 6 ? 0.95 : 0.85));
      return;
    }

    // No calza exacto, pero tiene la mezcla de letras y números correcta.
    // Suele pasar cuando la foto confunde O con 0, o I con 1.
    final letras = RegExp(r'[A-Z]').allMatches(limpio).length;
    final numeros = RegExp(r'\d').allMatches(limpio).length;

    if (letras >= 2 && numeros >= 2 && letras + numeros == limpio.length) {
      // Se prueba corrigiendo las confusiones típicas de la lectura automática
      final corregido = _corregirConfusiones(limpio);
      if (FormatoPatente.esValida(corregido)) {
        candidatos.add((corregido, 0.72));
      } else {
        candidatos.add((limpio, 0.45));
      }
    }
  }

  /// Corrige los errores típicos de la lectura automática: la letra O que se lee
  /// como cero, la I como uno, y así.
  String _corregirConfusiones(String texto) {
    if (texto.length != 6 && texto.length != 5) return texto;

    // En las patentes chilenas las letras van primero y los números después.
    final cantidadDeLetras = texto.length == 6 ? 4 : 3;

    final letras = texto.substring(0, cantidadDeLetras).split('').map((c) {
      return switch (c) {
        '0' => 'O',
        '1' => 'I',
        '5' => 'S',
        '8' => 'B',
        '2' => 'Z',
        _ => c,
      };
    }).join();

    final numeros = texto.substring(cantidadDeLetras).split('').map((c) {
      return switch (c) {
        'O' || 'Q' || 'D' => '0',
        'I' || 'L' => '1',
        'S' => '5',
        'B' => '8',
        'Z' => '2',
        'G' => '6',
        _ => c,
      };
    }).join();

    return '$letras$numeros';
  }

  /// Hay que llamarlo al cerrar la pantalla: la lectura automática usa memoria
  /// del sistema que no se libera sola.
  Future<void> cerrar() => _lector.close();
}
