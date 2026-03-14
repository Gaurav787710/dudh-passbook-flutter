plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    // Add the Google services Gradle plugin
    id("com.google.gms.google-services")
}

android {
    namespace = "com.dairymaster.pro"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // IMPORTANT: Before Play Store release, change this to "com.dairymaster.pro"
        // AND register a new Android app in Firebase Console with the same package name,
        // then download updated google-services.json.
        applicationId = "com.dairymaster.pro"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        
        // Multidex support for Firebase
        multiDexEnabled = true
    }

    buildTypes {
        release {
            // IMPORTANT: Before Play Store release, create a proper keystore:
            //   keytool -genkey -v -keystore dairy-release-key.jks -keyalg RSA -keysize 2048 -validity 10000 -alias dairy
            // Then create android/key.properties with:
            //   storePassword=<password>
            //   keyPassword=<password>
            //   keyAlias=dairy
            //   storeFile=<path>/dairy-release-key.jks
            // And configure signingConfigs.create("release") above.
            signingConfig = signingConfigs.getByName("debug")

            // Enable code shrinking, obfuscation, and optimization for release
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
}

dependencies {
    // Import the Firebase BoM
    implementation(platform("com.google.firebase:firebase-bom:34.7.0"))

    // Firebase Analytics
    implementation("com.google.firebase:firebase-analytics")

    // Firebase Auth (for authentication)
    implementation("com.google.firebase:firebase-auth")

    // Firebase Firestore (for database sync)
    implementation("com.google.firebase:firebase-firestore")
}

flutter {
    source = "../.."
}
