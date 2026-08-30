plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.warimesh"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // flutter_local_notifications requires this (java.time APIs on API < 26).
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.warimesh"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // flutter.minSdkVersion resolves to 24 on this Flutter version, which
        // already clears the >=23 (Android 8.0) floor BLE peripheral/advertising
        // needs -- see SETUP_AND_FILMING_GUIDE.md. Left as the Flutter default
        // rather than hand-pinned, since `flutter build` rewrites this line back
        // to the default on every build anyway.
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

            // Minification is deliberately OFF. R8 renamed MediaPipe's
            // AutoValue-generated LlmInferenceOptions, and MediaPipe resolves
            // those fields by name at runtime, so the assistant died on a
            // real phone with "field modelPath for b1.g not found" — a
            // failure no unit test and no startup check can catch, because it
            // only appears when somebody opens the assistant.
            //
            // proguard-rules.pro has keep rules that should cover it, but
            // every one of them is a guess about what MediaPipe reflects on,
            // and the cost of guessing wrong is a feature that looks healthy
            // until it is demonstrated. Shrinking buys a smaller APK; that is
            // not worth trading for an assistant that breaks on stage.
            //
            // The rules are kept and kept correct so re-enabling this is a
            // one-line change followed by testing the assistant END TO END on
            // a device — not just checking that the app starts.
            isMinifyEnabled = false
            isShrinkResources = false
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }
}

dependencies {
    // Required by compileOptions.isCoreLibraryDesugaringEnabled above.
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    // On-device LLM inference (MediaPipe LLM Inference API) — runs Gemma
    // completely offline on the phone; see LlmBridge.kt + lib/llm_service.dart.
    // 0.10.35 required: 0.10.27 crashes loading the Gemma-3n E2B bundle
    // ("Unknown model type: tf_lite_audio_adapter").
    implementation("com.google.mediapipe:tasks-genai:0.10.35")
}

flutter {
    source = "../.."
}
