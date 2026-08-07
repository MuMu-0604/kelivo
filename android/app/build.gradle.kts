import java.util.Properties
import java.io.File

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android Gradle plugin.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.psyche.kelivo"
    compileSdk = flutter.compileSdkVersion
//    ndkVersion = flutter.ndkVersion
    ndkVersion = "28.2.13676358"
    val appIdOverride = (findProperty("kelivoApplicationId") as String?)?.takeIf { it.isNotBlank() }
    val appLabelOverride = (findProperty("kelivoAppLabel") as String?)?.takeIf { it.isNotBlank() }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        // Default to the 9015 coexist package so 9020+ upgrades replace Kelivo Slider,
        // while still installing beside upstream Kelivo (com.psyche.kelivo).
        applicationId = appIdOverride ?: "com.psyche.kelivo.sliderpreview"
        manifestPlaceholders["appLabel"] = appLabelOverride ?: "Kelivo Slider"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    val keystorePropertiesFile = rootProject.file("key.properties")
    val keystoreProperties = Properties()
    if (keystorePropertiesFile.exists()) {
        keystoreProperties.load(keystorePropertiesFile.inputStream())
    }

    fun signingProperty(name: String): String {
        val direct = keystoreProperties.getProperty(name)?.trim()
        if (!direct.isNullOrEmpty()) return direct
        val normalized = keystoreProperties.entries.firstOrNull { entry ->
            entry.key.toString()
                .trim()
                .removePrefix("\uFEFF")
                .removePrefix("\u00EF\u00BB\u00BF") == name
        }?.value?.toString()?.trim()
        if (!normalized.isNullOrEmpty()) return normalized
        error("Missing Android signing property '$name' in ${keystorePropertiesFile.absolutePath}")
    }

    fun signingFile(path: String): File {
        val file = File(path)
        return if (file.isAbsolute) file else keystorePropertiesFile.parentFile.resolve(file)
    }

    signingConfigs {
        create("release") {
            if (keystorePropertiesFile.exists()) {
                storeFile = signingFile(signingProperty("storeFile"))
                storePassword = signingProperty("storePassword")
                keyAlias = signingProperty("keyAlias")
                keyPassword = signingProperty("keyPassword")
            }
        }
    }

    buildTypes {
        getByName("release") {
            if (keystorePropertiesFile.exists()) {
                signingConfig = signingConfigs.getByName("release")
            }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_11
    }
}

flutter {
    source = "../.."
}

dependencies {
    // Required for core library desugaring (used by flutter_local_notifications)
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.4")
}
