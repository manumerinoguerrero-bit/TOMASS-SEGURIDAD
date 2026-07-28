plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
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
