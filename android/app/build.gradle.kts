plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    // Note: Replaced with your project's namespace
    namespace = "com.example.crm3"

    compileSdk = 36

    defaultConfig {
        applicationId = "com.example.crm3"

        // Minimum SDK 21 = Android 5.0 Lollipop
        minSdk = flutter.minSdkVersion

        // targetSdk 36
        targetSdk = 35

        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // MultiDex: Essential for large Flutter apps
        multiDexEnabled = true
    }

    buildTypes {
        release {
            // Shrink + obfuscate release build
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
            signingConfig = signingConfigs.getByName("debug")
        }
        debug {
            isDebuggable = true
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_1_8
        targetCompatibility = JavaVersion.VERSION_1_8
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = "1.8"
    }

    packaging {
        resources {
            excludes += setOf(
                "META-INF/DEPENDENCIES",
                "META-INF/LICENSE",
                "META-INF/LICENSE.txt",
                "META-INF/NOTICE",
                "META-INF/NOTICE.txt"
            )
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // Core library desugaring for Java 8 APIs on older devices
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")

    // MultiDex support
    implementation("androidx.multidex:multidex:2.0.1")

    // AndroidX Core
    implementation("androidx.core:core-ktx:1.13.1")
}
