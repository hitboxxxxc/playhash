buildscript {
    repositories {
        google()
        mavenCentral()
    }
    dependencies {
        // google-services não publica plugin marker (não funciona com o bloco
        // plugins{}); por isso entra no classpath via buildscript.
        classpath("com.google.gms:google-services:4.4.2")
    }
}

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Plugin google-services aplicado CONDICIONALMENTE (classpath via buildscript
// acima): o build passa mesmo antes de o arquivo google-services.json existir.
// Aplicação pela CLASSE porque o plugin não publica plugin marker (o registro
// por id via bloco plugins{} não funciona para este artefato).
if (file("google-services.json").exists()) {
    val pluginClass = try {
        Class.forName("com.google.gms.googleservices.GoogleServicesPlugin")
    } catch (ex: ClassNotFoundException) {
        null
    }
    if (pluginClass != null) {
        pluginManager.apply(pluginClass)
    } else {
        throw GradleException(
            "google-services.json encontrado, mas o plugin google-services " +
                "não está no classpath. Verifique o bloco buildscript."
        )
    }
}

android {
    namespace = "com.mustarda.playhash"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.mustarda.playhash"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 24
        targetSdk = 36
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
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
