package cl.tomass.tomass_seguridad

import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import android.os.Bundle
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

class MainActivity : FlutterFragmentActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        crearLosCanalesDeAviso()
    }

    // ========================================================================
    // LOS DOS TONOS DE AVISO
    // ========================================================================
    // De Android 8 en adelante, cada aviso pertenece a un "canal", y el canal
    // decide cómo suena: el volumen, si vibra, y si aparece encima de lo que la
    // persona esté haciendo.
    //
    // POR QUÉ HAY DOS Y NO UNO
    //
    //   No todos los avisos valen lo mismo. Un auto detenido en la barrera está
    //   trabando la entrada del condominio y hay que atenderlo AHORA. Que llegó
    //   un paquete puede esperar.
    //
    //   Con dos canales separados, Android trata distinto a cada uno: el urgente
    //   aparece en pantalla y vibra con un ritmo propio; el normal solo aparece
    //   en la barra de arriba.
    //
    //   Y hay una razón más importante todavía: la persona puede silenciar los
    //   avisos comunes desde los ajustes del teléfono SIN silenciar los urgentes.
    //   Si fueran todos el mismo canal, un guardia cansado de que le suenen los
    //   paquetes apagaría también los avisos de los autos.
    //
    // ⚠️ LOS NOMBRES accesos_urgentes Y avisos NO SE PUEDEN CAMBIAR ACÁ SOLO.
    //
    //    El servidor los nombra al mandar cada aviso, en el archivo
    //    supabase/functions/_compartido/avisos.ts. Si acá se llaman distinto,
    //    Android no encuentra el canal, usa uno cualquiera por defecto y se
    //    pierde toda esta configuración sin ningún mensaje de error.
    //
    // Los canales se crean al arrancar la app. Crear uno que ya existe no hace
    // nada, así que no molesta que esto corra cada vez.
    // ========================================================================

    private fun crearLosCanalesDeAviso() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return

        val gestor = getSystemService(NotificationManager::class.java) ?: return

        val urgentes = NotificationChannel(
            "accesos_urgentes",
            "Accesos urgentes",
            NotificationManager.IMPORTANCE_HIGH
        ).apply {
            description = "Autos esperando en la barrera y visitas que necesitan " +
                "que alguien conteste ahora. Aparecen en pantalla y vibran."
            enableVibration(true)
            // Ritmo propio, para reconocerlo sin mirar: dos golpes seguidos.
            vibrationPattern = longArrayOf(0, 500, 300, 500)
            enableLights(true)
        }

        val comunes = NotificationChannel(
            "avisos",
            "Avisos",
            NotificationManager.IMPORTANCE_DEFAULT
        ).apply {
            description = "Paquetes que llegaron, vehículos aprobados y novedades. " +
                "Aparecen en la barra de arriba sin interrumpir."
            enableVibration(true)
        }

        gestor.createNotificationChannel(urgentes)
        gestor.createNotificationChannel(comunes)
    }
}
