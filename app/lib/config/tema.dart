// ============================================================================
// Tomass Seguridad — Colores y estilos de toda la app
// ============================================================================
// Todos los colores del sistema salen de acá. Si algún día hay que cambiar un
// color, se cambia en este archivo y cambia en todas las pantallas.
//
// LA REGLA MÁS IMPORTANTE DE ESTE ARCHIVO
//
//   El ROJO se usa ÚNICAMENTE para denegar o alertar. Nunca como decoración,
//   nunca como color de marca dentro de la interfaz.
//
//   El motivo: el rojo está en el logo de Tomass, así que si además fuera el
//   color de base de la app, el guardia lo vería todo el día y "ACCESO DENEGADO"
//   perdería fuerza justo cuando más importa. Con el grafito de base, el rojo en
//   pantalla significa siempre una sola cosa.
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class Colores {
  const Colores._();

  // ---- Base: encabezados, botones principales, barra lateral --------------
  static const Color grafito = Color(0xFF1C1E24);
  static const Color grafitoClaro = Color(0xFF2B2F39);
  static const Color grafitoSuave = Color(0xFF3A3F4C);

  // ---- Señales. Cada una significa UNA sola cosa --------------------------
  /// Solo para acceso aprobado.
  static const Color verde = Color(0xFF2E7D32);
  static const Color verdeOscuro = Color(0xFF1B5E20);

  /// Solo para acceso denegado o peligro.
  static const Color rojo = Color(0xFFD32F2F);
  static const Color rojoOscuro = Color(0xFF8E1616);

  /// Solo para algo que espera atención: autos en la barrera, paquetes viejos.
  static const Color naranja = Color(0xFFEF6C00);
  static const Color naranjaOscuro = Color(0xFF8A3D00);

  // ---- Fondos y textos ----------------------------------------------------
  static const Color fondo = Color(0xFFF4F5F6);
  static const Color superficie = Colors.white;
  static const Color texto = Color(0xFF1B1D22);
  static const Color textoSuave = Color(0xFF6B6F78);
  static const Color textoTenue = Color(0xFF9AA0A8);
  static const Color linea = Color(0xFFE2E4E8);

  /// El rojo del aro del logo. Se usa SOLO al dibujar el logo, en ningún otro
  /// lugar de la interfaz.
  static const Color rojoDelLogo = Color(0xFFC62828);
}

class Medidas {
  const Medidas._();

  static const double margen = 16;
  static const double margenChico = 10;
  static const double redondeo = 12;
  static const double redondeoChico = 8;

  /// Alto mínimo de un botón que el guardia toca con guantes o el residente
  /// desde el auto. Más grande que el mínimo recomendado, a propósito.
  static const double altoBoton = 54;
  static const double altoBotonGigante = 72;
}

class Tema {
  const Tema._();

  static ThemeData claro() {
    final base = ColorScheme.fromSeed(
      seedColor: Colores.grafito,
      brightness: Brightness.light,
      primary: Colores.grafito,
      onPrimary: Colors.white,
      secondary: Colores.grafitoClaro,
      surface: Colores.superficie,
      onSurface: Colores.texto,
      error: Colores.rojo,
      onError: Colors.white,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: base,
      scaffoldBackgroundColor: Colores.fondo,

      // Los textos en español no llevan mayúsculas forzadas: se lee peor.
      appBarTheme: const AppBarTheme(
        backgroundColor: Colores.grafito,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colores.grafito,
          statusBarIconBrightness: Brightness.light,
          statusBarBrightness: Brightness.dark,
        ),
        titleTextStyle: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.2,
          color: Colors.white,
        ),
      ),

      cardTheme: CardThemeData(
        color: Colores.superficie,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Medidas.redondeo),
          side: const BorderSide(color: Colores.linea),
        ),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: Colores.grafito,
          foregroundColor: Colors.white,
          disabledBackgroundColor: Colores.textoTenue,
          minimumSize: const Size.fromHeight(Medidas.altoBoton),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Medidas.redondeoChico),
          ),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.1,
          ),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: Colores.grafito,
          minimumSize: const Size.fromHeight(Medidas.altoBoton),
          side: const BorderSide(color: Colores.grafito, width: 1.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Medidas.redondeoChico),
          ),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colores.superficie,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Medidas.redondeoChico),
          borderSide: const BorderSide(color: Colores.linea),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Medidas.redondeoChico),
          borderSide: const BorderSide(color: Colores.linea),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Medidas.redondeoChico),
          borderSide: const BorderSide(color: Colores.grafito, width: 1.8),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Medidas.redondeoChico),
          borderSide: const BorderSide(color: Colores.rojo, width: 1.5),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Medidas.redondeoChico),
          borderSide: const BorderSide(color: Colores.rojo, width: 1.8),
        ),
        labelStyle: const TextStyle(color: Colores.textoSuave),
      ),

      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colores.superficie,
        indicatorColor: Colores.grafito.withValues(alpha: 0.10),
        elevation: 0,
        height: 68,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStateProperty.resolveWith((estados) {
          final activo = estados.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: activo ? Colores.grafito : Colores.textoSuave,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((estados) {
          final activo = estados.contains(WidgetState.selected);
          return IconThemeData(
            size: 24,
            color: activo ? Colores.grafito : Colores.textoSuave,
          );
        }),
      ),

      dividerTheme: const DividerThemeData(
        color: Colores.linea,
        thickness: 1,
        space: 1,
      ),

      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colores.grafito,
        contentTextStyle: const TextStyle(color: Colors.white, fontSize: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Medidas.redondeoChico),
        ),
      ),

      textTheme: const TextTheme(
        headlineLarge: TextStyle(
          fontSize: 30,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.6,
          color: Colores.texto,
        ),
        titleLarge: TextStyle(
          fontSize: 19,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.2,
          color: Colores.texto,
        ),
        titleMedium: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w700,
          color: Colores.texto,
        ),
        bodyLarge: TextStyle(fontSize: 15, color: Colores.texto, height: 1.45),
        bodyMedium: TextStyle(fontSize: 14, color: Colores.texto, height: 1.45),
        bodySmall: TextStyle(fontSize: 12.5, color: Colores.textoSuave, height: 1.4),
        labelSmall: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.0,
          color: Colores.textoSuave,
        ),
      ),
    );
  }
}
