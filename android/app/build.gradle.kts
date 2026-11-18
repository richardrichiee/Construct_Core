plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.cryptone.construction"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.cryptone.construction"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
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

val copyNamedReleaseApks = tasks.register<Sync>("copyNamedReleaseApks") {
    val manifestFile = file("src/main/AndroidManifest.xml")
    val rawAppName = if (manifestFile.exists()) {
        Regex("""android:label\s*=\s*"([^"]+)"""")
            .find(manifestFile.readText())
            ?.groupValues
            ?.getOrNull(1)
            ?: project.name
    } else {
        project.name
    }
    val formattedAppName = rawAppName
        .replace(Regex("""\s+"""), "")
        .replace(Regex("""[^A-Za-z0-9._-]"""), "")
        .ifEmpty { "App" }
    val appVersionName = flutter.versionName.trim().ifEmpty { "1.0.0" }

    dependsOn(tasks.matching { it.name == "packageRelease" })

    from(layout.buildDirectory.dir("outputs/apk/release")) {
        include("*.apk")
    }
    into(layout.buildDirectory.dir("outputs/release-apks"))

    rename { fileName ->
        when {
            fileName == "app-release.apk" -> "$formattedAppName-v$appVersionName.apk"
            fileName.startsWith("app-") && fileName.endsWith("-release.apk") -> {
                val abi = fileName.removePrefix("app-").removeSuffix("-release.apk")
                "$formattedAppName-v$appVersionName-$abi.apk"
            }
            else -> fileName
        }
    }

    doLast {
        val apks = destinationDir
            .listFiles { file -> file.isFile && file.extension == "apk" }
            ?.sortedBy { it.name }
            .orEmpty()
        if (apks.isEmpty()) {
            println("copyNamedReleaseApks: No release APKs found in ${destinationDir.absolutePath}")
        } else {
            apks.forEach { apk ->
                println("Named release APK: ${apk.absolutePath}")
            }
        }
    }
}

tasks.matching { it.name == "assembleRelease" }.configureEach {
    finalizedBy(copyNamedReleaseApks)
}
