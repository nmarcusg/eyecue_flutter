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
