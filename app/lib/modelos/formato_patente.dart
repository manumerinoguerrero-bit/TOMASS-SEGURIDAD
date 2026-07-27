// ============================================================================
// Tomass Seguridad — Formato de las patentes chilenas
// ============================================================================
// Está en su propio archivo porque lo usan tanto los modelos de datos como las
// pantallas, y así la regla vive en un solo lugar.
//
// Las patentes chilenas tienen dos formatos vigentes:
//   Autos nuevos (desde 2007):  BBBB-99   → 4 letras y 2 números
//   Autos viejos:               AA-9999   → 2 letras y 4 números
//   Motos:                      AAA-99    → 3 letras y 2 números
//
// La app acepta cualquiera de los tres y los guarda siempre con guion y en
// mayúsculas, para que "abc123" y "ABC-123" queden idénticos en la base de datos
// y el guardia no vea la misma patente escrita de dos formas.
// ============================================================================

class FormatoPatente {
  const FormatoPatente._();

  /// Deja la patente en su forma canónica: mayúsculas y con un solo guion.
  /// Si no reconoce el formato, devuelve el texto limpio sin guion, para no
  /// perder lo que la persona escribió.
  static String normalizar(String cruda) {
    final limpia = cruda.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    if (limpia.length < 5 || limpia.length > 6) return limpia;

    // 6 caracteres → el guion va después del cuarto (BBBB-99)
    // 5 caracteres → el guion va después del tercero (AAA-99)
    final corte = limpia.length == 6 ? 4 : 3;
    return '${limpia.substring(0, corte)}-${limpia.substring(corte)}';
  }

  /// Solo letras y números, sin guion. Para comparar o buscar.
  static String soloCaracteres(String cruda) =>
      cruda.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');

  /// ¿Tiene forma de patente chilena válida?
  static bool esValida(String cruda) {
    final limpia = soloCaracteres(cruda);
    return RegExp(r'^[A-Z]{4}\d{2}$').hasMatch(limpia) || // BBBB99
        RegExp(r'^[A-Z]{2}\d{4}$').hasMatch(limpia) || // AA9999
        RegExp(r'^[A-Z]{3}\d{2}$').hasMatch(limpia); // AAA99
  }

  /// El mensaje que se le muestra al residente si la patente está mal escrita.
  static String? mensajeSiEstaMal(String? cruda) {
    if (cruda == null || cruda.trim().isEmpty) {
      return 'Escribí la patente.';
    }
    if (!esValida(cruda)) {
      return 'Esa patente no tiene un formato válido. Ejemplos: BCDF-12, AB-1234.';
    }
    return null;
  }
}
