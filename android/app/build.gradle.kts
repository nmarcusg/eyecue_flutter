plugins {
    id("com.android.application")
    id("dev.flutter.flutter-gradle-plugin")
}

// Ultralytics uses LiteRT Next 2.x while tflite_flutter's Dart FFI still
// opens the classic 1.4.x native library. Keep LiteRT Next on the Java
// classpath, remove the obsolete Java/GPU artifacts that duplicate its
// classes, and extract only the classic FFI .so under its original name.
configurations.configureEach {
    exclude(group = "com.google.ai.edge.litert", module = "litert-api")
    exclude(group = "com.google.ai.edge.litert", module = "litert-gpu")
}

val classicLiteRtAar by configurations.creating

dependencies {
    // A transitive dependency was resolving WorkManager 2.9.1, whose Room-backed
    // startup database fails in this optimized release APK. Pin a recent stable
    // runtime so its matching Room implementation and consumer R8 rules
    // are packaged together.
    implementation("androidx.work:work-runtime:2.11.2")

    add(classicLiteRtAar.name, "com.google.ai.edge.litert:litert:1.4.0@aar") {
        isTransitive = false
    }
}

val classicLiteRtJniDir = layout.buildDirectory
    .dir("generated/classicLiteRtJni")
    .get()
    .asFile
val extractClassicLiteRtJni by tasks.registering(Sync::class) {
    from(classicLiteRtAar.map(::zipTree)) {
        include("jni/**/libtensorflowlite_jni.so")
        eachFile { path = path.removePrefix("jni/") }
        includeEmptyDirs = false
    }
    into(classicLiteRtJniDir)
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

    sourceSets.getByName("main").jniLibs.srcDir(classicLiteRtJniDir)
}

tasks.matching { it.name == "preBuild" }.configureEach {
    dependsOn(extractClassicLiteRtJni)
}

flutter {
    source = "../.."
}
