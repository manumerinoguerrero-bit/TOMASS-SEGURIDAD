// ============================================================================
// Tomass Seguridad — Colores y estilos de toda la app
// ============================================================================
// Todos los colores del sistema salen de acá. Si algún día hay que cambiar un
// color, se cambia en este archivo y cambia en todas las pantallas.
//
// PALETA CORPORATIVA (estilo Merlyn Seguridad)
//
//   La app usa el mismo lenguaje visual de Merlyn: azul marino corporativo
//   como color principal + dorado como acento. Se abandonó el grafito
//   industrial anterior porque el cliente prefiere el look más profesional
//   y "de empresa de seguridad seria" que da el azul.
//
//   Los nombres de las constantes (Colores.grafito, Colores.grafitoClaro)
//   se mantienen a propósito, aunque los valores ahora son azul marino:
//   así el resto del código sigue funcionando sin tocar una sola pantalla.
//   Pensalo como "grafito" = "el color principal de la marca", sea cual sea.
//
// LA REGLA DEL ROJO
//
//   El ROJO se usa ÚNICAMENTE para denegar o alertar. Nunca como decoración.
//   Con el azul de base, el rojo en pantalla significa siempre una sola cosa.
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

class Colores {
  const Colores._();

  // ---- Base: encabezados, botones principales, barra lateral --------------
  // Azul marino corporativo estilo Merlyn.
  static const Color grafito = Color(0xFF0D2B5E);
  static const Color grafitoClaro = Color(0xFF1A4080);
  static const Color grafitoSuave = Color(0xFF2A5AB0);

  /// Azul marino más oscuro, para gradientes y sombras.
  static const Color azulOscuro = Color(0xFF071A3E);

  /// Dorado corporativo, acento y detalles decorativos.
  static const Color dorado = Color(0xFFC9A24E);
  static const Color doradoOscuro = Color(0xFFA08234);
  static const Color doradoClaro = Color(0xFFE5C988);

  // ---- Señales. Cada una significa UNA sola cosa --------------------------
  /// Solo para acceso aprobado.
  static const Color verde = Color(0xFF27AE60);
  static const Color verdeOscuro = Color(0xFF1E7D45);

  /// Solo para acceso denegado o peligro.
  static const Color rojo = Color(0xFFE74C3C);
  static const Color rojoOscuro = Color(0xFFB03225);

  /// Solo para algo que espera atención: autos en la barrera, paquetes viejos.
  static const Color naranja = Color(0xFFF39C12);
  static const Color naranjaOscuro = Color(0xFFB47409);

  // ---- Fondos y textos ----------------------------------------------------
  static const Color fondo = Color(0xFFF4F6FA);
  static const Color superficie = Colors.white;
  static const Color texto = Color(0xFF1A1A2E);
  static const Color textoSuave = Color(0xFF6B7280);
  static const Color textoTenue = Color(0xFF9CA3AF);
  static const Color linea = Color(0xFFE5E7EB);

  /// El rojo del aro del logo. Se usa SOLO al dibujar el logo, en ningún otro
  /// lugar de la interfaz.
  static const Color rojoDelLogo = Color(0xFFC62828);
}

class Medidas {
  const Medidas._();

  static const double margen = 16;
  static const double margenChico = 10;

  /// Radio grande, para cards y bottom sheets (estilo Merlyn).
  static const double redondeo = 18;

  /// Radio mediano, para botones e inputs.
  static const double redondeoChico = 14;

  /// Alto mínimo de un botón que el guardia toca con guantes o el residente
  /// desde el auto. Más grande que el mínimo recomendado, a propósito.
  static const double altoBoton = 52;
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
      secondary: Colores.dorado,
      onSecondary: Colors.white,
      surface: Colores.superficie,
      onSurface: Colores.texto,
      error: Colores.rojo,
      onError: Colors.white,
    );

    final tipografia = GoogleFonts.interTextTheme();

    return ThemeData(
      useMaterial3: true,
      colorScheme: base,
      scaffoldBackgroundColor: Colores.fondo,

      // AppBar azul marino, título centrado, estilo Merlyn.
      appBarTheme: AppBarTheme(
        backgroundColor: Colores.grafito,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        systemOverlayStyle: const SystemUiOverlayStyle(
          statusBarColor: Colores.grafito,
          statusBarIconBrightness: Brightness.light,
          statusBarBrightness: Brightness.dark,
        ),
        titleTextStyle: GoogleFonts.inter(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.2,
          color: Colors.white,
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),

      cardTheme: CardThemeData(
        color: Colores.superficie,
        elevation: 0,
        margin: EdgeInsets.zero,
        shadowColor: Colors.black.withValues(alpha: 0.08),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Medidas.redondeo),
          side: BorderSide(color: Colors.black.withValues(alpha: 0.04)),
        ),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: Colores.grafito,
          foregroundColor: Colors.white,
          disabledBackgroundColor: Colores.textoTenue,
          minimumSize: const Size.fromHeight(Medidas.altoBoton),
          elevation: 2,
          shadowColor: Colores.grafito.withValues(alpha: 0.4),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Medidas.redondeoChico),
          ),
          textStyle: GoogleFonts.inter(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.3,
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
          textStyle: GoogleFonts.inter(
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),

      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(Medidas.altoBoton),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Medidas.redondeoChico),
          ),
          textStyle: GoogleFonts.inter(
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: Colores.grafito,
          textStyle: GoogleFonts.inter(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colores.superficie,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
          borderSide: const BorderSide(color: Colores.grafito, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Medidas.redondeoChico),
          borderSide: const BorderSide(color: Colores.rojo, width: 1.5),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Medidas.redondeoChico),
          borderSide: const BorderSide(color: Colores.rojo, width: 2),
        ),
        labelStyle: GoogleFonts.inter(color: Colores.textoSuave),
        hintStyle: GoogleFonts.inter(color: Colores.textoTenue),
      ),

      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colores.superficie,
        indicatorColor: Colores.grafito.withValues(alpha: 0.12),
        elevation: 4,
        shadowColor: Colors.black.withValues(alpha: 0.05),
        height: 68,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStateProperty.resolveWith((estados) {
          final activo = estados.contains(WidgetState.selected);
          return GoogleFonts.inter(
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

      drawerTheme: const DrawerThemeData(
        backgroundColor: Colores.grafito,
        width: 290,
      ),

      chipTheme: ChipThemeData(
        backgroundColor: Colores.grafito.withValues(alpha: 0.08),
        labelStyle: GoogleFonts.inter(
          fontSize: 12,
          color: Colores.grafito,
          fontWeight: FontWeight.w600,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        side: BorderSide.none,
      ),

      dividerTheme: const DividerThemeData(
        color: Colores.linea,
        thickness: 1,
        space: 1,
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: Colores.superficie,
        surfaceTintColor: Colores.superficie,
        elevation: 10,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        titleTextStyle: GoogleFonts.inter(
          color: Colores.grafito,
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
        contentTextStyle: GoogleFonts.inter(
          color: Colores.texto,
          fontSize: 14,
          height: 1.45,
        ),
      ),

      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Colores.superficie,
        surfaceTintColor: Colores.superficie,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),

      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colores.grafito,
        contentTextStyle: GoogleFonts.inter(
          color: Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),

      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: Colores.grafito,
        foregroundColor: Colors.white,
        elevation: 4,
      ),

      textTheme: tipografia.copyWith(
        headlineLarge: GoogleFonts.inter(
          fontSize: 30,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.6,
          color: Colores.grafito,
        ),
        headlineMedium: GoogleFonts.inter(
          fontSize: 24,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.4,
          color: Colores.grafito,
        ),
        titleLarge: GoogleFonts.inter(
          fontSize: 19,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.2,
          color: Colores.texto,
        ),
        titleMedium: GoogleFonts.inter(
          fontSize: 15,
          fontWeight: FontWeight.w700,
          color: Colores.texto,
        ),
        bodyLarge: GoogleFonts.inter(
          fontSize: 15,
          color: Colores.texto,
          height: 1.45,
        ),
        bodyMedium: GoogleFonts.inter(
          fontSize: 14,
          color: Colores.texto,
          height: 1.45,
        ),
        bodySmall: GoogleFonts.inter(
          fontSize: 12.5,
          color: Colores.textoSuave,
          height: 1.4,
        ),
        labelSmall: GoogleFonts.inter(
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.0,
          color: Colores.textoSuave,
        ),
      ),
    );
  }
}
