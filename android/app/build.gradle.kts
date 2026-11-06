plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing is supplied by the environment so no keystore or password is
// ever committed. CI decodes the keystore to a temporary file and passes these
// variables; local release builds without them fall back to debug signing,
// which is explicitly labelled as unsuitable for distribution.
val releaseKeystorePath: String? = System.getenv("CI_ANDROID_KEYSTORE_PATH")
val releaseKeystorePassword: String? = System.getenv("CI_ANDROID_KEYSTORE_PASSWORD")
val releaseKeyAlias: String? = System.getenv("CI_ANDROID_KEY_ALIAS")
val releaseKeyPassword: String? = System.getenv("CI_ANDROID_KEY_PASSWORD")
val signingInputs = listOf(
    releaseKeystorePath,
    releaseKeystorePassword,
    releaseKeyAlias,
    releaseKeyPassword,
)

if (signingInputs.any { !it.isNullOrBlank() } && signingInputs.any { it.isNullOrBlank() }) {
    throw GradleException(
        "Partial Android release signing configuration. Set all of " +
            "CI_ANDROID_KEYSTORE_PATH, CI_ANDROID_KEYSTORE_PASSWORD, " +
            "CI_ANDROID_KEY_ALIAS and CI_ANDROID_KEY_PASSWORD, or none of them."
    )
}

android {
    namespace = "com.mindpocket.mindpocket"
    // permission_handler_android and receive_sharing_intent require compileSdk
    // 37; the SDK ships it as the minor-version platform `android-37.0`.
    compileSdk = 37
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.mindpocket.mindpocket"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // sherpa_onnx native libs require API 21+; ML Kit text recognition and
        // the Android photo picker need 21 and 33+ respectively (the picker
        // falls back gracefully on older devices).
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (!releaseKeystorePath.isNullOrBlank()) {
            create("release") {
                storeFile = file(releaseKeystorePath)
                storePassword = releaseKeystorePassword
                keyAlias = releaseKeyAlias
                keyPassword = releaseKeyPassword
                enableV1Signing = true
                enableV2Signing = true
            }
        }
    }

    buildTypes {
        release {
            // Real distribution signing when CI supplies a keystore; otherwise
            // debug signing keeps local `flutter run --release` working. Release
            // tooling labels artifacts built without a keystore accordingly.
            signingConfig = if (!releaseKeystorePath.isNullOrBlank()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }

    lint {
        // AGP 9.3's lint crashes parsing JavaDoc in image_picker_android
        // (NoSuchMethodError inside JavaDocParser), which aborts release builds.
        // Static analysis runs through `flutter analyze` instead.
        checkReleaseBuilds = false
        abortOnError = false
    }

    packaging {
        // The sherpa native libraries are shared objects inside the APK; keep
        // them uncompressed so the loader can map them directly.
        jniLibs {
            useLegacyPackaging = false
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
