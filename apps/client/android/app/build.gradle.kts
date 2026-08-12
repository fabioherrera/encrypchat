import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Optional release signing. Create android/key.properties (gitignored) with:
//   storeFile=/abs/path/upload-keystore.jks
//   storePassword=...
//   keyAlias=upload
//   keyPassword=...
// Without that file the release build falls back to the debug keystore (sideload only).
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties().apply {
    if (keystorePropertiesFile.exists()) {
        keystorePropertiesFile.inputStream().use { load(it) }
    }
}
val hasReleaseKeystore = keystorePropertiesFile.exists() &&
    keystoreProperties.getProperty("storeFile").isNullOrBlank().not()

// Only ABIs with a matching crates/core JNI build are shippable; see
// scripts/package-android.sh. Override with -Pencrypchat.abis=arm64-v8a,armeabi-v7a.
val encrypchatAbis: List<String> =
    (project.findProperty("encrypchat.abis") as String? ?: "arm64-v8a")
        .split(",")
        .map { it.trim() }
        .filter { it.isNotEmpty() }

android {
    namespace = "com.encrypchat.encrypchat"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.encrypchat.encrypchat"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        ndk {
            abiFilters.clear()
            abiFilters.addAll(encrypchatAbis)
        }
    }

    packaging {
        jniLibs {
            // Compressed .so keeps the sideload download small; Android extracts
            // them at install time. AAB uploads recompute this on the server side.
            useLegacyPackaging = true
        }
    }

    signingConfigs {
        if (hasReleaseKeystore) {
            create("release") {
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasReleaseKeystore) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
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
