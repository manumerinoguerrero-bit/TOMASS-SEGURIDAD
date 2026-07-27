// ============================================================================
// Tomass Seguridad — Datos de conexión al servidor
// ============================================================================
// Acá se guarda la dirección del servidor y la llave pública de la app.
//
// ¿ES SEGURO QUE ESTA LLAVE ESTÉ ACÁ DENTRO?
//   Sí. La "llave pública" (anon key) está pensada para vivir dentro de la app y
//   no da acceso a nada por sí sola: todo lo que se puede leer o escribir con
//   ella lo deciden los candados de la base de datos, según quién inició sesión.
//
//   La que JAMÁS puede estar acá es la llave maestra (service role). Esa vive
//   solo en el servidor.
// ============================================================================

class Entorno {
  const Entorno._();

  /// Dirección del servidor del condominio.
  static const String urlSupabase = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://ymgadpinqxqkjgxslftg.supabase.co',
  );

  /// Llave pública de la app. Ver la explicación de arriba.
  static const String llavePublica = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6'
        'InltZ2FkcGlucXhxa2pneHNsZnRnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODUwNjE1'
        'NzAsImV4cCI6MjEwMDYzNzU3MH0.-jFCh_uTFKLuRZ2X8LY9E4l8Sa_xKZcDRLdwtm_AF4o',
  );

  /// Nombres de las funciones del servidor.
  static const String funcionGenerarCodigo = 'generar-qr';
  static const String funcionValidarAcceso = 'validar-acceso';
  static const String funcionValidarCredencial = 'validar-credencial';

  /// Cuántos segundos antes de que venza el código se pide uno nuevo.
  /// Se pide con anticipación para que nunca se muestre un código muerto.
  static const int margenRenovacionSegundos = 5;

  /// Cuánto se espera al servidor antes de avisar que no responde.
  static const Duration esperaMaxima = Duration(seconds: 20);
}
