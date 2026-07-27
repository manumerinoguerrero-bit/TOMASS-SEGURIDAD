package cl.tomass.tomass_seguridad

import io.flutter.embedding.android.FlutterFragmentActivity

// ============================================================================
// Tomass Seguridad — Arranque en Android
// ============================================================================
// ⚠️ ACÁ DICE FlutterFragmentActivity Y NO FlutterActivity. NO LO CAMBIES.
//
// Flutter crea este archivo con FlutterActivity, que es lo normal en cualquier
// proyecto. Pero la huella digital y el Face ID (la librería local_auth)
// necesitan FlutterFragmentActivity para poder mostrar el cuadro de diálogo del
// sistema operativo.
//
// Si esto vuelve a FlutterActivity, la app compila igual y arranca igual, pero
// SE CAE en el momento exacto en que el residente toca "Ingresar con huella".
// Es un error difícil de encontrar, porque no aparece hasta que alguien usa esa
// función y el mensaje de error no menciona este archivo.
// ============================================================================

class MainActivity : FlutterFragmentActivity()
