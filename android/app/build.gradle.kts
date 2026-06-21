import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.translate_ko_jp"
    compileSdk = 36
    ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    defaultConfig {
        applicationId = "com.example.translate_ko_jp"
        minSdk = 26
        targetSdk = 35
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
}

// Kotlin 2.x compilerOptions DSL (replaces the removed `kotlinOptions` block).
kotlin {
    compilerOptions {
        jvmTarget = JvmTarget.JVM_11
    }
}

flutter {
    source = "../.."
}

dependencies {
    // LiteRT-LM runtime: runs Gemma 4 (.litertlm) on-device with real GPU
    // acceleration (OpenCL, ~52 tok/s on Android). Replaces the older MediaPipe
    // tasks-genai LLM path, which is in maintenance mode and fell back to CPU.
    implementation("com.google.ai.edge.litertlm:litertlm-android:0.13.1")
}
