import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val releaseSigningProperties = Properties()
val releaseSigningFile = rootProject.file("key.properties")
if (releaseSigningFile.exists()) {
    FileInputStream(releaseSigningFile).use(releaseSigningProperties::load)
}
val releaseStoreFile = releaseSigningProperties.getProperty("storeFile")
    ?: System.getenv("ANDROID_KEYSTORE_PATH")
val releaseStorePassword = releaseSigningProperties.getProperty("storePassword")
    ?: System.getenv("ANDROID_KEYSTORE_PASSWORD")
val releaseKeyAlias = releaseSigningProperties.getProperty("keyAlias")
    ?: System.getenv("ANDROID_KEY_ALIAS")
val releaseKeyPassword = releaseSigningProperties.getProperty("keyPassword")
    ?: System.getenv("ANDROID_KEY_PASSWORD")
val releaseSigningReady = listOf(
    releaseStoreFile,
    releaseStorePassword,
    releaseKeyAlias,
    releaseKeyPassword,
).all { !it.isNullOrBlank() }
val releaseTaskRequested = gradle.startParameter.taskNames.any {
    it.contains("release", ignoreCase = true)
}
if (releaseTaskRequested && !releaseSigningReady) {
    throw GradleException(
        "Release signing is required. Configure android/key.properties or the ANDROID_KEYSTORE_* environment variables.",
    )
}

android {
    namespace = "com.moehe.checklists.checklist_entry"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.moehe.checklists.checklist_entry"
        minSdk = maxOf(24, flutter.minSdkVersion)
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (releaseSigningReady) {
            create("release") {
                storeFile = file(releaseStoreFile!!)
                storePassword = releaseStorePassword
                keyAlias = releaseKeyAlias
                keyPassword = releaseKeyPassword
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.findByName("release")
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
