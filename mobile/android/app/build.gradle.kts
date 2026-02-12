import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

// Load .env file
val envFile = project.rootProject.file("../.env")
val envProperties = Properties()
if (envFile.exists()) {
    if (envFile.exists()) {
        try {
            envProperties.load(FileInputStream(envFile))
            println("✅ Loaded .env file successfully")
        } catch (e: Exception) {
            println("⚠️ Error loading .env file: ${e.message}")
        }
    } else {
        println("⚠️ .env file not found at: ${envFile.absolutePath}")
    }
}

android {
    namespace = "com.example.tripthread"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.tripthread"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // Inject Mapbox token from .env
        resValue("string", "mapbox_access_token", 
            envProperties.getProperty("MAPBOX_ACCESS_TOKEN", ""))
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}
