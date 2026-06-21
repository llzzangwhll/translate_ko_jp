pluginManagement {
    val flutterSdkPath = run {
        val properties = java.util.Properties()
        file("local.properties").inputStream().use { properties.load(it) }
        val flutterSdkPath = properties.getProperty("flutter.sdk")
        require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
        flutterSdkPath
    }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "8.7.3" apply false
    // 2.3.0+ required: the LiteRT-LM AAR ships Kotlin 2.3.0 metadata, which an
    // older compiler (2.1.0 reads up to 2.2.0) cannot parse.
    id("org.jetbrains.kotlin.android") version "2.3.0" apply false
}

include(":app")
