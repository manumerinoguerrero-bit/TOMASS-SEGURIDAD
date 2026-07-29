// ⚠️ EL BLOQUE plugins DEBE SER LO PRIMERO DEL ARCHIVO.
//
//    Gradle lo exige: si arriba de él hay cualquier otra línea, aunque sea una
//    variable, la compilación falla entera. Por eso la parte de Firebase está
//    MÁS ABAJO y no acá, que sería el lugar natural para leerla.
plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// ============================================================================
// ¿ESTÁ CONFIGURADO FIREBASE?
// ============================================================================
// Firebase es lo que hace sonar el celular con la app cerrada. Para funcionar
// necesita un archivo que se baja de la consola de Google y se guarda acá:
//
//     app/android/app/google-services.json
//
// POR QUÉ SE PREGUNTA SI EXISTE EN VEZ DE USARLO Y LISTO
//
//   Porque el complemento de Google, si se aplica y el archivo no está, hace
//   FALLAR la compilación entera con un error que no dice nada útil. Eso
//   dejaría a la app sin poder compilarse hasta que alguien complete todo el
//   trámite de Firebase.
//
//   Así, en cambio: mientras el archivo no esté, la app compila igual y todo
//   funciona salvo el sonido con la app cerrada. En cuanto se guarda el
//   archivo, la próxima compilación lo detecta sola y los avisos se prenden.
//   No hay que tocar ni una línea de código.
//
// Los pasos para conseguir ese archivo están en LEEME-AVISOS.md.
// ============================================================================
if (file("google-services.json").exists()) {
    apply(plugin = "com.google.gms.google-services")
    logger.lifecycle("Tomass: Firebase configurado, los avisos van a sonar.")
} else {
    logger.lifecycle(
        "Tomass: falta google-services.json, la app se compila igual pero el " +
        "celular no va a sonar con la app cerrada (ver LEEME-AVISOS.md)."
    )
}

android {
    namespace = "cl.tomass.tomass_seguridad"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "cl.tomass.tomass_seguridad"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // ========================================================================
    // FIRMA DE LAS COMPILACIONES DE PRUEBA
    // ========================================================================
    // QUÉ PROBLEMA RESUELVE
    //
    //   Cada compilación en GitHub generaba una firma digital NUEVA. Android ve
    //   dos apps con el mismo nombre pero firmas distintas, y se niega a
    //   actualizar con este mensaje:
    //
    //       "No se instaló la app debido a un conflicto con un paquete"
    //
    //   Eso obligaba a desinstalar la app antes de cada prueba, perdiendo
    //   además la sesión guardada y teniendo que volver a iniciar sesión.
    //
    //   Con una firma FIJA, cada APK nuevo se instala encima del anterior como
    //   una actualización normal, conservando la sesión.
    //
    // ⚠️ ESTA FIRMA ES SOLO PARA PRUEBAS. Su contraseña es "android", que es
    //    pública y estándar en Android. NO sirve para publicar en Google Play:
    //    para eso hay que crear una firma de verdad, con contraseña secreta,
    //    y guardarla como secreto de GitHub. Eso va en la Fase 5.
    // ========================================================================
    signingConfigs {
        getByName("debug") {
            storeFile = file("../firma-pruebas.jks")
            storePassword = "android"
            keyAlias = "androiddebugkey"
            keyPassword = "android"
        }
    }

    buildTypes {
        release {
            // Por ahora la versión de publicación también usa la firma de
            // pruebas, para poder compilarla y verla funcionar. Antes de subirla
            // a Google Play hay que cambiarla por una firma real.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
