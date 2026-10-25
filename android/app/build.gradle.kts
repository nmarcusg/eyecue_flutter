import java.io.FileInputStream
import java.util.Properties

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

// Release signing material is owner-supplied and never committed: either
// android/key.properties (gitignored) or the EYECUE_KEYSTORE_* environment
// variables. Store file paths are resolved against android/app/, so use an
// absolute path unless the keystore really lives under android/app/.
val uploadKeyProperties = Properties().apply {
    val file = rootProject.file("key.properties")
    if (file.exists()) FileInputStream(file).use { load(it) }
}
fun uploadSecret(property: String, env: String): String? =
    uploadKeyProperties.getProperty(property)?.takeIf { it.isNotBlank() }
        ?: System.getenv(env)?.takeIf { it.isNotBlank() }

val uploadStoreFile = uploadSecret("storeFile", "EYECUE_KEYSTORE_PATH")
val uploadStorePassword = uploadSecret("storePassword", "EYECUE_KEYSTORE_PASSWORD")
val uploadKeyAlias = uploadSecret("keyAlias", "EYECUE_KEY_ALIAS")
val uploadKeyPassword = uploadSecret("keyPassword", "EYECUE_KEY_PASSWORD")
val hasUploadSigning = uploadStoreFile != null && uploadStorePassword != null &&
    uploadKeyAlias != null && uploadKeyPassword != null

android {
    // Provisional Play Store identity; the final applicationId is an owner gate
    // (docs/release-procedure.md). Changing it after the first upload is not
    // possible for the same listing.
    namespace = "app.eyecue.mobile"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "app.eyecue.mobile"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasUploadSigning) {
            create("release") {
                storeFile = file(uploadStoreFile!!)
                storePassword = uploadStorePassword
                keyAlias = uploadKeyAlias
                keyPassword = uploadKeyPassword
            }
        }
    }

    buildTypes {
        release {
            // Flutter's Gradle plugin does not enable shrinking; these are the
            // effective release values and R8 (including its consumer rules from
            // WorkManager/Room) runs on this build type.
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )

            if (hasUploadSigning) {
                signingConfig = signingConfigs.getByName("release")
            } else {
                // No keystore: the build must never pass for a Play release.
                logger.warn(
                    "EyeCue: no release signing material (android/key.properties or " +
                        "EYECUE_KEYSTORE_*). This release build is DEBUG-SIGNED and its " +
                        "versionName carries -testsigned: it is a test artifact, not a " +
                        "Play Store release.",
                )
                signingConfig = signingConfigs.getByName("debug")
                versionNameSuffix = "-testsigned"
            }
        }
    }
}

// A debug-signed bundle is refused by Play, yet it used to be written as
// `app-release.aab` / `app-release.apk` — a filename indistinguishable from a
// production artefact. On the no-keystore fallback only, rename the outputs so
// the file itself says the build is not a Play release. The production path
// keeps the normal names; AGP 9 no longer exposes the file name through the
// variant API, so the rename happens after the task that writes the file.
if (!hasUploadSigning) {
    val markTestSigned: (String) -> Unit = { path ->
        val artefact = layout.buildDirectory.file(path).get().asFile
        if (artefact.exists()) {
            val renamed = artefact.resolveSibling(
                artefact.name.replace("app-release", "app-release-testsigned"),
            )
            check(artefact.renameTo(renamed)) {
                "EyeCue: could not mark ${artefact.name} as test-signed"
            }
        }
    }

    // The bundle is renamed by the task that writes it. `flutter build
    // appbundle` then reports the renamed file.
    afterEvaluate {
        tasks.matching { it.name == "bundleRelease" }.configureEach {
            doLast { markTestSigned("outputs/bundle/release/app-release.aab") }
        }
    }

    // The APK cannot be marked from `assembleRelease`: Flutter's own plugin copies
    // it into `flutter-apk/` after that task has finished, so at doLast time the
    // file does not exist yet (measured: the APK stayed plain-named, while
    // `flutter build apk` reported success). Mark it after the build instead:
    // `./gradlew markTestSignedApk`.
    tasks.register("markTestSignedApk") {
        doLast {
            markTestSigned("outputs/flutter-apk/app-release.apk")
            // The tool also writes the APK's sha1 sidecar; keep the pair together.
            markTestSigned("outputs/flutter-apk/app-release.apk.sha1")
        }
    }
}

flutter {
    source = "../.."
}
