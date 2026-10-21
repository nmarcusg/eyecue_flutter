plugins {
    id("com.android.application")
    id("dev.flutter.flutter-gradle-plugin")
}

dependencies {
    // A transitive dependency was resolving WorkManager 2.9.1, whose Room-backed
    // startup database fails in this optimized release APK. Pin a recent stable
    // runtime so its matching Room implementation and consumer R8 rules
    // are packaged together.
    implementation("androidx.work:work-runtime:2.11.2")
}

android {
    namespace = "com.example.eyecue_flutter"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.example.eyecue_flutter"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}
