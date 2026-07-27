// ============================================================================
// Tomass Seguridad — Arranque de la app
// ============================================================================
// Este es el primer archivo que corre cuando alguien abre la app. Se encarga de
// tres cosas y nada más:
//
//   1. Conectarse al servidor.
//   2. Preparar el idioma español para las fechas.
//   3. Mostrar la primera pantalla.
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config/entorno.dart';
import 'config/tema.dart';
import 'navegacion/rutas.dart';
import 'nucleo/almacenamiento_seguro.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Las fechas se muestran en español ("lunes 26 de julio")
  initializeDateFormatting('es');

  // OJO: la orientación NO se bloquea acá a propósito.
  //
  // El residente usa la app en vertical, pero el guardia usa LA MISMA app en una
  // tablet horizontal. Si se bloqueara en vertical desde acá, la pantalla del
  // guardia quedaría inservible cuando se construya (Fase 4).
  //
  // Cada parte de la app fija su propia orientación: las pantallas del residente
  // lo hacen en pantallas/inicio/contenedor_principal.dart.

  // Conexión al servidor.
  //
  // La sesión se guarda en la zona blindada del teléfono (Keychain en iPhone,
  // Keystore en Android), no en el almacenamiento común. Eso lo hace
  // AlmacenamientoSeguro.
  await Supabase.initialize(
    url: Entorno.urlSupabase,
    publishableKey: Entorno.llavePublica,
    authOptions: FlutterAuthClientOptions(
      localStorage: AlmacenamientoSeguro(),
    ),
  );

  runApp(const ProviderScope(child: AppTomass()));
}

class AppTomass extends ConsumerWidget {
  const AppTomass({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rutas = ref.watch(rutasProvider);

    return MaterialApp.router(
      title: 'Tomass Seguridad',
      debugShowCheckedModeBanner: false,
      theme: Tema.claro(),
      routerConfig: rutas,

      // La app funciona solo en español de Chile. Esto pone en español los
      // textos que trae el propio sistema: los botones de los selectores de
      // fecha y hora, los nombres de los meses, "Cancelar", "Listo".
      locale: const Locale('es'),
      supportedLocales: const [Locale('es'), Locale('es', 'CL')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],

      // El tamaño de los textos no se pasa de 1.3 veces lo normal. Si alguien
      // tiene la letra gigante configurada en el teléfono, las pantallas de
      // acceso igual se tienen que poder leer completas sin cortarse.
      builder: (context, hijo) {
        final escala = MediaQuery.textScalerOf(context).clamp(
          minScaleFactor: 0.9,
          maxScaleFactor: 1.3,
        );
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: escala),
          child: hijo!,
        );
      },
    );
  }
}
