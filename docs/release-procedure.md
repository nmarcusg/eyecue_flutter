# EyeCue — Release Procedure (versioning, signing, app bundle)

Operational procedure for producing a Play Store upload. It records what the
configuration in this tree does and which decisions remain owner gates; measured
build evidence lives in [`play-store-readiness.md`](play-store-readiness.md)
(the L8/L9 rows).

## 1. Application identity

| Field | Value | Status |
| --- | --- | --- |
| `applicationId` / `namespace` | `app.eyecue.mobile` | **Provisional** — owner gate D1 |
| `android:label` (launcher) | `EyeCue` | set |
| Kotlin package / `MainActivity` | `app.eyecue.mobile` | moved with the id |
| `taskAffinity` | `""` (unchanged) | deliberate: the app never merges into another task's affinity |
| Launcher icon | `@mipmap/ic_launcher` (unchanged) | generic Flutter icon is still an L10 asset item |
| Deep links / providers / authorities | none declared | nothing to rename |

Changing `applicationId` after the first Play upload is not possible for that
listing, so it stays provisional until the owner confirms the reverse-domain
namespace ([`play-store-readiness.md`](play-store-readiness.md) §8 D1).

## 2. Versioning

Both version fields come from [`pubspec.yaml`](../pubspec.yaml:4) — `flutter`
reads `version: <versionName>+<versionCode>` and passes them to Gradle through
`flutter.versionName` / `flutter.versionCode`, which
[`android/app/build.gradle.kts`](../android/app/build.gradle.kts) assigns
unchanged. There is no second copy in Gradle to drift.

To ship a change:

1. Bump `versionCode` by at least one for **every** upload — Play rejects a
   build whose code was already used.
2. Bump `versionName` for anything a user would call a new version.
3. Rebuild the bundle (§4); the values land in `versionCode` / `versionName` of
   the generated manifest.

## 3. Signing

Two sources are read at configuration time, properties first, then environment:

| `android/key.properties` key | Environment variable |
| --- | --- |
| `storeFile` | `EYECUE_KEYSTORE_PATH` |
| `storePassword` | `EYECUE_KEYSTORE_PASSWORD` |
| `keyAlias` | `EYECUE_KEY_ALIAS` |
| `keyPassword` | `EYECUE_KEY_PASSWORD` |

`android/key.properties`, `*.jks` and `*.keystore` are gitignored. Never commit a
keystore, a password, or `key.properties`. `storeFile` is resolved against
`android/app/`, so use an absolute path unless the keystore really lives there.

**No material present** → the release build falls back to the debug signing
config, sets `versionNameSuffix = "-testsigned"` and prints a Gradle warning. A
`1.0.0-testsigned` APK or AAB is a **test artifact**: it is not installable from
Play (a debug-signed bundle is refused at upload) and must never be described as
a release candidate.

Create the upload keystore once, outside the repository:

```sh
keytool -genkeypair -v -keystore ~/eyecue-upload.jks -alias upload \
  -keyalg RSA -keysize 2048 -validity 10000
```

### Play App Signing

Production signing is an **external gate**. With Play App Signing:

1. The upload key above signs the AAB locally; Google Play holds the app signing
   key and re-signs the artefacts it serves.
2. The first upload enrols the app in Play App Signing; if the upload key is
   later lost, Google replaces it (Play Console → App integrity → upload key
   reset) without a new listing.
3. Losing the **app signing key** handed to Play is recoverable only through
   Play support — so the upload keystore and its passwords belong in the owner's
   password manager, not in this repository.

Until the owner provides the upload keystore (or the environment variables),
every artifact produced here is debug-signed and test-only.

## 4. Building the app bundle

```sh
cd /home/nico/repos/eyecue_flutter-playstore
flutter build appbundle --release
```

Output: `build/app/outputs/bundle/release/app-release.aab`. Release shrinking is
enabled (`isMinifyEnabled`, `isShrinkResources` in the release build type) with
[`android/app/proguard-rules.pro`](../android/app/proguard-rules.pro) added on
top of the default optimized rules; R8 full mode is not forced.

For inspection use a release APK as well — most tools cannot read an AAB:

```sh
flutter build apk --release
unzip -p build/app/outputs/flutter-apk/app-release.apk 'classes*.dex' | strings | grep -c 'androidx/work/impl/WorkDatabase'
```

## 5. Owner gates

| Gate | Needed for |
| --- | --- |
| Confirm final `applicationId` (D1) | first upload; irreversible per listing |
| Provide the upload keystore / `EYECUE_KEYSTORE_*` | a bundle Play will accept |
| Enrol the app in Play App Signing | production distribution |
| Final licence + store listing + Data Safety (D2/D3, L10) | submission |
| Device install smoke test | the `CONFIRMED-ON-DEVICE` rows in the ledger |

## 6. Measured build evidence — 2026-10-25

Two artefacts were built from this tree and inspected. **Both are debug-signed
(`-testsigned`) test artefacts**: no `android/key.properties` and no
`EYECUE_*` environment variable existed on the build host, so the fallback in
§3 applied. Nothing below is a claim that the release works on a device.

`CONFIRMED-BY-BUILD` (the builds ran to completion and the files exist),
`CONFIRMED-BY-INSPECTION` (the contents listed below were read out of those
files). No `CONFIRMED-ON-DEVICE` claim exists.

```sh
cd /home/nico/repos/eyecue_flutter-playstore
flutter build appbundle --release   # Gradle bundleRelease 242.0s, 4:05 wall
flutter build apk --release         # Gradle assembleRelease  33.3s, 0:37 wall
```

| Artefact | Path | Size | sha256 |
| --- | --- | --- | --- |
| AAB | `build/app/outputs/bundle/release/app-release.aab` | 78 607 421 B (78.6 MB) | `feaab199c74dda67985cd596e1e873313159a49c12d916c9b33219ea43cb821b` |
| APK (inspection only) | `build/app/outputs/flutter-apk/app-release.apk` | 91 191 297 B (91.2 MB) | `99ac0da9a49697d3e027a4b8920d1ae3e9fd220061ea7db47056295351439a83` |

`sha256sum build/app/outputs/bundle/release/app-release.aab build/app/outputs/flutter-apk/app-release.apk`
reproduces both digests for these exact files.

### 6.1 Bundle manifest (`unzip -l`)

`BUNDLE-METADATA/` (23 entries: `com.android.tools.build.debugsymbols/*.sym`)
plus the `base` module (202 entries) — a standard single-module AAB.

Model assets, exactly one depth model and one detector model:

```
  5474749  base/assets/flutter_assets/assets/yolo26n-depth_w8a32.tflite
  3483114  base/assets/flutter_assets/assets/yolov8n_int8_new_metadata.tflite
```

The tooling-only models are **absent** (`yolov8n.tflite`, `yolov8n_int8.tflite`,
`yolov8n_int8_new.tflite` all return no match). The whole
`assets/flutter_assets/assets/` set is the two models, `labels.txt`, `logo.png`
and four IBM Plex `.ttf` files — nothing else.

No `design-reference/`, `docs/`, `tool/` or `test/` entry appears in the bundle.

Native libraries by ABI (`base/lib/<abi>/*.so`):

| ABI | Libraries |
| --- | --- |
| `arm64-v8a` | `libLiteRt.so`, `libLiteRtClGlAccelerator.so`, `libapp.so`, `libc++_shared.so`, `libdartjni.so`, `libdatastore_shared_counter.so`, `libflutter.so`, `libimage_processing_util_jni.so`, `libsurface_util_jni.so`, `libultralytics.so` |
| `armeabi-v7a` | same set minus `libLiteRtClGlAccelerator.so` |
| `x86_64` | same set as `arm64-v8a` |

Three ABIs, no `x86`. The GPU accelerator library is absent from `armeabi-v7a`
(no GPU delegate for 32-bit ARM).

### 6.2 Manifest facts from the release APK

`aapt2` and `apkanalyzer` are both present
(`~/Android/Sdk/build-tools/36.1.0/aapt2`,
`~/Android/Sdk/cmdline-tools/latest/bin/apkanalyzer`).

```sh
$ANDROID_HOME/build-tools/36.1.0/aapt2 dump badging app-release.apk
$ANDROID_HOME/cmdline-tools/latest/bin/apkanalyzer manifest print app-release.apk
```

```
package: name='app.eyecue.mobile' versionCode='1' versionName='1.0.0-testsigned'
         platformBuildVersionName='16' platformBuildVersionCode='36'
         compileSdkVersion='36' compileSdkVersionCodename='16'
minSdkVersion:'24'
targetSdkVersion:'36'
application-label:'EyeCue'
launchable-activity: name='app.eyecue.mobile.MainActivity'
```

`apkanalyzer` prints no `android:debuggable` attribute on `<application>`, i.e.
`debuggable` is **false** — as required for a release build type.

Effective permission list, all inherited from the merged manifest (the app's own
manifests declare only `CAMERA` and `INTERNET`):

| Permission | Declared by |
| --- | --- |
| `CAMERA` | app |
| `INTERNET` | app |
| `FOREGROUND_SERVICE` | plugin |
| `FOREGROUND_SERVICE_DATA_SYNC` | plugin |
| `WAKE_LOCK` | WorkManager / plugin |
| `ACCESS_NETWORK_STATE` | plugin |
| `RECEIVE_BOOT_COMPLETED` | plugin |
| `RECORD_AUDIO` | `flutter_tts` |
| `WRITE_EXTERNAL_STORAGE` (`maxSdkVersion='28'`) | plugin |
| `READ_EXTERNAL_STORAGE` | plugin |
| `app.eyecue.mobile.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION` | androidx (auto-generated) |

`RECORD_AUDIO` and the storage permissions are not referenced by any Dart code in
this tree; they arrive with the TTS and image-processing plugins. They are a
Data Safety input for L10 (D3), not a build defect.

### 6.3 R8 / WorkManager-Room evidence

The historical release crash was Room failing to instantiate
`androidx.work.impl.WorkDatabase` after shrinking removed the generated
`_Impl` class. The minified APK still contains what that lookup needs:

```sh
unzip -p app-release.apk 'classes*.dex' | strings | grep -c 'androidx/work/impl/WorkDatabase'
# 2
unzip -p app-release.apk 'classes*.dex' | strings | grep -c 'androidx/work/impl/WorkDatabase_Impl'
# 1
unzip -p app-release.apk 'classes*.dex' | strings | grep -c 'RoomDatabase'
# 1
apkanalyzer dex packages --defined-only app-release.apk | grep -E 'WorkDatabase|androidx\.room\.'
```

The negative-form checks all pass: the class is not merely referenced. The single
`classes.dex` (3 370 088 B) **defines** `androidx.work.impl.WorkDatabase_Impl`
with 33 methods including a public no-arg `<init>()`, 727 `androidx.room.*`
class/method rows survive, and the descriptors `Landroidx/work/impl/WorkDatabase;`
and `Landroidx/work/impl/WorkDatabase_Impl;` are both present.

**Verdict: not a blocker.** The R8/runtime-classpath hazard is closed for this
build — `CONFIRMED-BY-INSPECTION`. This is presence evidence, not proof: only an
installed launch exercises the reflective construction and the Room migration at
open time (§6.4).

### 6.4 Device gate — installed startup is NOT verified

WorkManager/Room startup: **NOT VERIFIED ON A DEVICE.**

No Android device is attached and no AVD is present; creating one is not
permitted on this host (5.0 GB free, 95 % used). The DEX-presence evidence in
§6.3 is the strongest proxy available here — it is not proof that the app starts.
The install/launch commands to close this gate are recorded in §5.1 of
[`benchmark-procedure.md`](benchmark-procedure.md).

The same gate applies to anything else that only a running app can show: the
first-run camera permission flow, model load from the bundled `.tflite` assets,
TTS initialisation and the `RECORD_AUDIO` prompt.

### 6.5 Secret scan

Both artefacts were decompressed (`unzip -p`) before scanning, so compressed
payloads cannot hide a match. Hits per pattern, APK and AAB:

| Pattern | APK | AAB |
| --- | --- | --- |
| `service_role` | 0 | 0 |
| `SUPABASE_SECRET` | 0 | 0 |
| `BEGIN PRIVATE KEY` | 0 | 0 |
| `eyJhbGciOi` (JWT header) | 0 | 0 |
| `supabase.co` / `EYECUE_TELEMETRY_INGEST_URL` / `EYECUE_SUPABASE_PUBLISHABLE_KEY` | 0 | — |

No `--dart-define` was passed to either build, so there were no define values to
bake in. The telemetry ingest URL and publishable key are still supplied at build
time by the owner ([`supabase-research-telemetry.md`](supabase-research-telemetry.md:189));
with both defines unset `TelemetryUploadConfiguration.isConfigured` is false
([`telemetry_upload_service.dart`](../lib/services/telemetry_upload_service.dart:30)),
which gates the upload at both the service and the button
([`telemetry_upload_service.dart`](../lib/services/telemetry_upload_service.dart:165),
[`logs_reports_screen.dart`](../lib/screens/logs_reports_screen.dart:113)), so these
artefacts cannot upload anything.

### 6.6 Reproducing this section

```sh
cd /home/nico/repos/eyecue_flutter-playstore
flutter build appbundle --release
flutter build apk --release
sha256sum build/app/outputs/bundle/release/app-release.aab build/app/outputs/flutter-apk/app-release.apk
unzip -l build/app/outputs/bundle/release/app-release.aab | head -40
unzip -p build/app/outputs/flutter-apk/app-release.apk 'classes*.dex' | strings | grep -c 'androidx/work/impl/WorkDatabase'
```

The digests change on every rebuild (timestamps, signing block); the model-asset,
ABI, manifest and R8 facts above are the parts expected to be stable.
