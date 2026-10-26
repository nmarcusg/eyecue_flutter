# EyeCue — Release Procedure (versioning, signing, app bundle)

Operational procedure for producing a Play Store upload. It records what the
configuration in this tree does and which decisions remain owner gates; measured
build evidence lives in [`play-store-readiness.md`](play-store-readiness.md)
(the L8/L9 rows).

## 1. Application identity

| Field | Value | Status |
| --- | --- | --- |
| `applicationId` / `namespace` | `app.eyecue.mobile` | **Final** — owner-approved (gate D1 decided) |
| `android:label` (launcher) | `EyeCue` | set |
| Kotlin package / `MainActivity` | `app.eyecue.mobile` | moved with the id |
| `taskAffinity` | `""` (unchanged) | deliberate: the app never merges into another task's affinity |
| Launcher icon | `@mipmap/ic_launcher` + `@mipmap/ic_launcher_round`, adaptive (API 26+) and monochrome layers | generated from `assets/logo.png` — see [`icon-generation.md`](icon-generation.md) |
| Deep links / providers / authorities | none declared | nothing to rename |

The owner approved `app.eyecue.mobile` as the permanent application ID; gate D1 is
decided and there is nothing left to confirm ([`play-store-readiness.md`](play-store-readiness.md)
§8 D1). Do not change it: `applicationId` cannot be changed after the first Play
upload for that listing.

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
config, sets `versionNameSuffix = "-testsigned"`, prints a Gradle warning and
marks the outputs as `app-release-testsigned.aab` / `app-release-testsigned.apk`.
A `1.0.0-testsigned` APK or AAB is a **test artifact**: it is not installable
from Play (a debug-signed bundle is refused at upload) and must never be
described as a release candidate. The name is what makes that visible in a
directory listing — the version name alone did not stop
`build/app/outputs/bundle/release/app-release.aab` from looking exactly like a
production artefact. Both rules live in
[`android/app/build.gradle.kts`](../android/app/build.gradle.kts) and are active
only when `hasUploadSigning` is false: with a keystore the names stay
`app-release.aab` / `app-release.apk`.

The two artefacts are marked in different places, for a measured reason:

* **AAB** — a `doLast` on `bundleRelease` renames
  `outputs/bundle/release/app-release.aab`. `flutter build appbundle` then reports
  the renamed file.
* **APK** — renaming inside `assembleRelease` does **not** work: Flutter's own
  Gradle step copies `app-release.apk` into `outputs/flutter-apk/` *after*
  `assembleRelease` finishes, so a rename there leaves a plain-named
  `app-release.apk` behind (measured on this tree) and `flutter build apk` only
  looks up the plain name. Mark it explicitly after the build:

  ```sh
  flutter build apk --release          # writes outputs/flutter-apk/app-release.apk
  (cd android && ./gradlew markTestSignedApk)   # renames it (+ its .sha1) to -testsigned
  ```

  `markTestSignedApk` is a Gradle task registered in
  [`android/app/build.gradle.kts`](../android/app/build.gradle.kts) and is
  **only** meaningful on the debug-signed fallback. Inspection can equally be run
  on the plain-named file; only the published name changes.

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

Output: `build/app/outputs/bundle/release/app-release.aab` with production
signing, or `app-release-testsigned.aab` on the debug-signed fallback (§3).
Release shrinking is
enabled (`isMinifyEnabled`, `isShrinkResources` in the release build type) with
[`android/app/proguard-rules.pro`](../android/app/proguard-rules.pro) added on
top of the default optimized rules; R8 full mode is not forced.

For inspection use a release APK as well — most tools cannot read an AAB:

```sh
flutter build apk --release
(cd android && ./gradlew markTestSignedApk)   # only on the debug-signed fallback (§3)
unzip -p build/app/outputs/flutter-apk/app-release-testsigned.apk 'classes*.dex' | strings | grep -c 'androidx/work/impl/WorkDatabase'
```

## 5. Owner gates

| Gate | Needed for |
| --- | --- |
| `applicationId` (D1) — **decided**: `app.eyecue.mobile` | nothing left to decide; irreversible per listing, so it must not change |
| Provide the upload keystore / `EYECUE_KEYSTORE_*` | a bundle Play will accept |
| Enrol the app in Play App Signing | production distribution |
| Licence (D2) — **decided**: `AGPL-3.0-only` | nothing left to decide; the obligations are in [`THIRD_PARTY_NOTICES.md`](../THIRD_PARTY_NOTICES.md) §1 and §7, and R1–R7 there still warrant qualified legal review |
| Privacy policy + Data Safety answers (D3) | [`privacy-and-data-safety.md`](privacy-and-data-safety.md) §8 and [`play-store-checklist.md`](play-store-checklist.md) §2 |
| Store listing, screenshots, content rating, support contact | [`play-store-checklist.md`](play-store-checklist.md) §6–§10 |
| Device install smoke test | the `CONFIRMED-ON-DEVICE` rows in the ledger |

## 6. Measured build evidence — final rebuild at `3eafed0`, 2026-10-26

Two artefacts were built from this tree and inspected. **Both are debug-signed
(`-testsigned`) test artefacts**: no `android/key.properties` and no
`EYECUE_*` environment variable existed on the build host, so the fallback in
§3 applied. Nothing below is a claim that the release works on a device.

`CONFIRMED-BY-BUILD` (the builds ran to completion and the files exist),
`CONFIRMED-BY-INSPECTION` (the contents listed below were read out of those
files). No `CONFIRMED-ON-DEVICE` claim exists.

Two earlier pairs are **superseded** and stay recorded only as history:

| Superseded at | AAB | APK |
| --- | --- | --- |
| `870c24e` (L8/L9) | 78 607 421 B / `feaab199…` | 91 191 297 B / `99ac0da9…` |
| `8766586`/`842d38b` (L10) | 78 607 313 B / `6d566ed416f7aa7fc2452f47b43fe80a872576bd8639ef2e67b9772e23ba22c6` | 91 191 189 B / `3c932ed4c2ef3b3057cf0653577a246128769145b08236caa507546a7c3d2974` |

The L10 pair was built before `5c78769` (generated launcher/adaptive/monochrome
icons) and before `3eafed0` (the safety gate), so neither is valid for any file in
the tree any more: the manifest is unchanged but the icons and the Dart AOT payload
are not, which is why the current artefacts are ≈155 KB larger.

```sh
cd /home/nico/repos/eyecue_flutter-playstore
flutter build appbundle --release   # Gradle bundleRelease 219.3s (221.7s wall, cold)
flutter build apk --release         # Gradle assembleRelease  46.7s ( 49.2s wall)
(cd android && ./gradlew markTestSignedApk)   # marks the APK (§3)
```

| Artefact | Path | Size | sha256 |
| --- | --- | --- | --- |
| AAB | `build/app/outputs/bundle/release/app-release-testsigned.aab` | 78 762 272 B (78.8 MB) | `6425a1e5f6420935b32f547a965e5be5bc11b80dcdc9d0ef9a04caf8d0c0ec56` |
| APK (inspection only) | `build/app/outputs/flutter-apk/app-release-testsigned.apk` | 91 345 913 B (91.3 MB) | `4df0f2c8a3b7767c5579dc059bd316d8903f9aab14b88afbe7a73bc5d526a573` |

`sha256sum build/app/outputs/bundle/release/app-release-testsigned.aab build/app/outputs/flutter-apk/app-release-testsigned.apk`
reproduces both digests for these exact files. `apksigner verify --print-certs`
on the APK reports `Signer #1 certificate DN: C=US, O=Android, CN=Android Debug`
— the fallback, as documented. No plain-named `app-release.aab` or
`app-release.apk` remains after `markTestSignedApk`, so a directory listing cannot
present a debug-signed file as a Play upload.

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
$ANDROID_HOME/build-tools/36.1.0/aapt2 dump badging app-release-testsigned.apk
$ANDROID_HOME/cmdline-tools/latest/bin/apkanalyzer manifest print app-release-testsigned.apk
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

Effective permission list after the L10 removal rules. The injectors below are
read out of the merger's own blame report —
`build/app/intermediates/manifest_merge_blame_file/release/processReleaseMainManifest/manifest-merger-blame-release-report.txt`
(element line followed by a `-->[<dependency>] <path>:<line>` line) — and its
human report `build/app/outputs/logs/manifest-merger-release-report.txt`:

| Permission | True injector (blame report evidence) |
| --- | --- |
| `CAMERA` | app — `android/app/src/main/AndroidManifest.xml:5` |
| `INTERNET` | app — `android/app/src/main/AndroidManifest.xml:7` |
| `FOREGROUND_SERVICE` | `com.google.ai.edge.litert:litert:2.1.5` — `litert-2.1.5/AndroidManifest.xml:23` |
| `FOREGROUND_SERVICE_DATA_SYNC` | `com.google.ai.edge.litert:litert:2.1.5` — `litert-2.1.5/AndroidManifest.xml:24` |
| `WAKE_LOCK` | `androidx.work:work-runtime:2.11.2` — `work-runtime-2.11.2/AndroidManifest.xml:23` |
| `ACCESS_NETWORK_STATE` | `androidx.work:work-runtime:2.11.2` — `work-runtime-2.11.2/AndroidManifest.xml:24` |
| `RECEIVE_BOOT_COMPLETED` | `androidx.work:work-runtime:2.11.2` — `work-runtime-2.11.2/AndroidManifest.xml:25` |
| `app.eyecue.mobile.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION` | `androidx.core:core:1.18.0` — signature-level, auto-generated (`core-1.18.0/AndroidManifest.xml:22-24`) |

Proof (`aapt2 dump badging` on the L10 release APK, §6):

```
uses-permission: name='android.permission.CAMERA'
uses-permission: name='android.permission.INTERNET'
uses-permission: name='android.permission.FOREGROUND_SERVICE'
uses-permission: name='android.permission.FOREGROUND_SERVICE_DATA_SYNC'
uses-permission: name='android.permission.WAKE_LOCK'
uses-permission: name='android.permission.ACCESS_NETWORK_STATE'
uses-permission: name='android.permission.RECEIVE_BOOT_COMPLETED'
uses-permission: name='app.eyecue.mobile.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION'
```

#### 6.2.1 Permissions removed in L10

Three `tools:node="remove"` rules in
[`android/app/src/main/AndroidManifest.xml`](../android/app/src/main/AndroidManifest.xml:8)
drop the two permissions `camera_android_camerax` injects for paths this app never
uses, plus the storage permission the merger *implies* from them:

| Removed | Injected by | Why unused | Residual risk |
| --- | --- | --- | --- |
| `RECORD_AUDIO` | `camera_android_camerax` — merged manifest `:10` | the app only reads the CameraX analysis stream; no audio is ever recorded | recording a **video with audio** would throw a `SecurityException`; that path is not used |
| `WRITE_EXTERNAL_STORAGE` (`maxSdkVersion='28'`) | `camera_android_camerax` — merged manifest `:11-13` | exports are written to the app's own documents directory ([`telemetry_export_service.dart`](../lib/services/telemetry_export_service.dart:424)) | a CameraX capture that saves into shared storage would fail on API ≤ 28; not used |
| `READ_EXTERNAL_STORAGE` | **implied by the manifest merger** — declared by no manifest | nothing reads shared storage | same as above — capture-from-gallery flows would fail; not used |

`READ_EXTERNAL_STORAGE` needs its own rule. The merger derives it from camerax's
`WRITE_EXTERNAL_STORAGE` request and states so verbatim:

```
uses-permission#android.permission.READ_EXTERNAL_STORAGE
IMPLIED from …/android/app/src/main/AndroidManifest.xml:1:1-… reason: io.flutter.plugins.camerax requested WRITE_EXTERNAL_STORAGE
```

The implication is computed from the library's *request*, not from the surviving
set, so removing `WRITE_EXTERNAL_STORAGE` alone does **not** remove it — measured
on this tree by re-running `:app:processReleaseMainManifest` with only the first
two rules, which still declared `READ_EXTERNAL_STORAGE`. (An earlier version of
this section claimed the opposite; the measurement is the correction.)

**Unverified without a device:** removals are proven at manifest level only. A
device run of the camera path would confirm that no code path asks for the dropped
permissions. Neither the microphone nor shared storage is requested at runtime
anywhere in `lib/` or `plugins/`.

#### 6.2.2 Kept permissions and why

| Permission | Used by this app? | Kept because |
| --- | --- | --- |
| `CAMERA` | yes — camera preview and the only frame source | without it there is no app |
| `INTERNET` | yes — manual telemetry upload only | models are bundled; no other network use |
| `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_DATA_SYNC` | not directly; litert's NPU manager starts a foreground service | removing them can raise `SecurityException` in litert's NPU startup path, which cannot be exercised without a device |
| `WAKE_LOCK`, `ACCESS_NETWORK_STATE`, `RECEIVE_BOOT_COMPLETED` | not directly; `androidx.work:work-runtime:2.11.2` needs them | WorkManager is constructed on the startup path this release pins (R8/Room, §6.3); dropping its permissions risks a startup `SecurityException` that cannot be tested here |
| `app.eyecue.mobile.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION` | framework-internal | auto-generated by `androidx.core`, signature-protected, not removable |

A permission that is merely declared and never requested produces no runtime
prompt, so this table drives the Play Data Safety answer, not the first-run
experience (§6.4).

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
first-run permission flow, model load from the bundled `.tflite` assets and TTS
initialisation.

**The only first-run prompt is `CAMERA`.** Nothing in this tree requests
microphone or storage access, and since L10 the release manifest no longer
declares those permissions at all (§6.2.1) — so no microphone or storage dialog
can appear. Any document that implies such prompts existed was wrong.

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

### 6.6 The `<queries>` `IMAGE_CAPTURE` block was removed (documented)

`2d0d0cd` deleted a `<queries><intent><action
android:name="android.media.action.IMAGE_CAPTURE"/></intent></queries>` block from
[`android/app/src/main/AndroidManifest.xml`](../android/app/src/main/AndroidManifest.xml)
without saying so in the message. It is inert for this app, and the removal is
recorded here rather than silently:

```sh
# no ACTION_IMAGE_CAPTURE usage anywhere in the app's Dart, Kotlin or manifest
grep -rn "ACTION_IMAGE_CAPTURE\|image_picker" lib/ android/ pubspec.yaml pubspec.lock
# (no matches)
```

`<queries>` only widens package-visibility for an explicit intent query. This app
never launches or resolves `ACTION_IMAGE_CAPTURE` — the camera is used in-process
through CameraX/`camera_android_camerax` — and `image_picker` is not a dependency
(it appears in neither `pubspec.yaml` nor `pubspec.lock`). The block was a Flutter
template leftover, so it is removed rather than restored.

### 6.7 Reproducing this section

```sh
cd /home/nico/repos/eyecue_flutter-playstore
flutter build appbundle --release
flutter build apk --release
(cd android && ./gradlew markTestSignedApk)   # marks the APK (§3)
sha256sum build/app/outputs/bundle/release/app-release-testsigned.aab build/app/outputs/flutter-apk/app-release-testsigned.apk
$ANDROID_HOME/build-tools/36.1.0/aapt2 dump badging build/app/outputs/flutter-apk/app-release-testsigned.apk | grep -E 'package:|uses-permission'
unzip -l build/app/outputs/bundle/release/app-release-testsigned.aab | head -40
unzip -p build/app/outputs/flutter-apk/app-release-testsigned.apk 'classes*.dex' | strings | grep -c 'androidx/work/impl/WorkDatabase'
$ANDROID_HOME/build-tools/36.1.0/zipalign -c -P 16 4 build/app/outputs/flutter-apk/app-release-testsigned.apk && echo 16KB-ALIGNED-OK
mkdir -p /tmp/eyecue-libs && unzip -q -o build/app/outputs/flutter-apk/app-release-testsigned.apk 'lib/*' -d /tmp/eyecue-libs
for f in $(find /tmp/eyecue-libs -name '*.so' | sort); do echo "$f $(readelf -lW $f | awk '/^  LOAD/ {print $NF}' | sort -u | tr '\n' ' ')"; done
```

On the debug-signed fallback the names carry `-testsigned` (§3); with a keystore
they are `app-release.aab` / `app-release.apk`. The digests change on every real
rebuild (timestamps, signing block); the model-asset, ABI, manifest and R8 facts
above are the parts expected to be stable. A rename-only run reuses the packaged
bytes and therefore does not change a digest.

### 6.8 16 KB page-size alignment (`targetSdk 36`, Android 15+)

The packaged APK passes `zipalign -c -P 16` and every 64-bit library is 16 KB aligned; the two 32-bit (`armeabi-v7a`) objects listed below are not:

```
$ $ANDROID_HOME/build-tools/36.1.0/zipalign -c -P 16 4 build/app/outputs/flutter-apk/app-release-testsigned.apk
$ echo $?
0        # 16KB-ALIGNED-OK
```

Per-library `LOAD` segment alignment (`readelf -lW` over the APK's `lib/`; the AAB
carries byte-identical copies — md5-compared for all 29 files):

| ABI | Library | `LOAD` align | 16 KB? |
| --- | --- | --- | --- |
| `arm64-v8a` | `libapp.so`, `libflutter.so` | `0x10000` | yes (64 KB) |
| `arm64-v8a` | `libc++_shared.so`, `libdartjni.so`, `libdatastore_shared_counter.so`, `libimage_processing_util_jni.so`, `libLiteRt.so`, `libLiteRtClGlAccelerator.so`, `libsurface_util_jni.so`, `libultralytics.so` | `0x4000` | yes |
| `x86_64` | `libapp.so`, `libflutter.so` | `0x10000` | yes (64 KB) |
| `x86_64` | the other eight | `0x4000` | yes |
| `armeabi-v7a` | `libapp.so`, `libdartjni.so`, `libdatastore_shared_counter.so`, `libimage_processing_util_jni.so`, `libLiteRt.so`, `libsurface_util_jni.so`, `libflutter.so` | `0x4000` / `0x10000` | not applicable (32-bit) |
| `armeabi-v7a` | **`libc++_shared.so`, `libultralytics.so`** | `0x1000` | **no — 4 KB** |

**Every 64-bit library (`arm64-v8a`, `x86_64`) is 16 KB aligned**, and the APK
passes `zipalign -c -P 16`. The only two libraries at 4 KB are `armeabi-v7a`
(32-bit) objects; 16 KB-page devices run the 64-bit split, so the Android 15+
requirement is met, and this is recorded rather than assumed. If `armeabi-v7a`
were ever brought into scope for 16 KB, those two libraries would have to be
rebuilt with that alignment.

### 6.9 Launcher and adaptive icons in the packaged artefacts

`aapt2 dump xmltree --file AndroidManifest.xml` on the release APK binds
`android:icon` to `mipmap/ic_launcher` and `android:roundIcon` to
`mipmap/ic_launcher_round`. `aapt2 dump resources` lists four mipmap resources —
`ic_launcher`, `ic_launcher_foreground`, `ic_launcher_monochrome`,
`ic_launcher_round` — each present at mdpi, hdpi, xhdpi, xxhdpi and xxxhdpi, with an
`anydpi-v26` XML for `ic_launcher` and `ic_launcher_round`. The adaptive XML
<code><adaptive-icon></code> declares `background` (the
`ic_launcher_background` colour), `foreground` (`ic_launcher_foreground`) and
`monochrome` (`ic_launcher_monochrome`), i.e. themed icons are supported. Resource
file names inside the APK are obfuscated by the resource shrinker (`res/BW.xml`,
`res/9w.png`), so the resource table — not the file names — is the evidence.

## 7. Publishing the corresponding source (AGPL-3.0-only)

The application is licensed **`AGPL-3.0-only`** ([`LICENSE`](../LICENSE)), the same
licence as the vendored plugin and the bundled models. The inventory, the obligations
and the review items are in [`THIRD_PARTY_NOTICES.md`](../THIRD_PARTY_NOTICES.md) §1,
§6 and §7. Every released binary must map to the complete corresponding source of that
exact build.

1. **Tag ↔ `versionName`+`versionCode`.** Tag the commit that is built, before
   building it:

   ```sh
   git tag -a v<versionName>+<versionCode> -m "EyeCue <versionName>+<versionCode> source"
   git show v<versionName>+<versionCode>:pubspec.yaml | head -5   # same pair as the artefact (§2)
   ```

2. **What to publish.** The source archive produced from that tag. It already contains
   the application code, the **modified vendored plugin** with its deviation record
   ([`plugins/ultralytics_yolo/VENDORED.md`](../plugins/ultralytics_yolo/VENDORED.md)),
   both model assets and the build instructions in §3–§4 above:

   ```sh
   TAG=v<versionName>+<versionCode>
   git archive --format=tar.gz --prefix="eyecue-${TAG}/" -o "eyecue-${TAG}-source.tar.gz" "${TAG}"
   sha256sum "eyecue-${TAG}-source.tar.gz"
   ```

   Publish that archive, together with
   [`THIRD_PARTY_NOTICES.md`](../THIRD_PARTY_NOTICES.md), wherever the AGPL-3.0 §6
   written offer names — an offer is only valid if it names a place and a period — and
   keep it available for as long as the matching binaries are distributed.

3. **`-testsigned` artefacts are never releases.** The debug-signed fallback in §3
   (`versionName …-testsigned`) must not be tagged, published or offered as source:
   tagging one would assert a release that does not exist.

No legal review has been performed. This section records the mechanics and where the
evidence lives; it does not state that AGPL compliance is verified
([`THIRD_PARTY_NOTICES.md`](../THIRD_PARTY_NOTICES.md) §6).
