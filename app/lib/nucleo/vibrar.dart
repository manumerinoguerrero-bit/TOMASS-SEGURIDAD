// ============================================================================
// Tomass Seguridad — Vibración al marcar un punto de la ronda
// ============================================================================
// Cuando el guardia entra al radio de un punto y se pone verde, el celular
// tiene que vibrar fuerte para que se dé cuenta aunque lo lleve en el
// bolsillo o con la pantalla apagada.
//
// Antes se usaba solo HapticFeedback.heavyImpact(): es un golpecito muy
// corto, y en muchos Android no se siente nada si el usuario tiene apagada la
// "respuesta táctil" en Ajustes. Por eso ahora se usa el motor de vibración
// directo (librería vibration, permiso VIBRATE ya declarado).
//
// Patrón: dos pulsos firmes. Es distinto del de "acceso rechazado" (tres
// pulsos largos, en pantalla_resultado.dart) para que no se confundan.
// ============================================================================

import 'package:flutter/services.dart';
import 'package:vibration/vibration.dart';

/// Dos pulsos firmes: "punto completado". Nunca lanza error.
Future<void> vibrarPuntoMarcado() async {
  try {
    final puede = await Vibration.hasVibrator();
    if (!puede) {
      // Sin motor de vibración, al menos el golpecito del sistema.
      await HapticFeedback.heavyImpact();
      return;
    }
    await Vibration.vibrate(pattern: [0, 350, 150, 350]);
  } catch (_) {
    // Si la vibración falla, queda el aviso en pantalla. No es crítico.
  }
}
