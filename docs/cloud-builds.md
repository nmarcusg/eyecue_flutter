# Android builds on GitHub Actions

Workflow: `.github/workflows/android-build.yml` (**Android cloud build**).
It builds on GitHub-hosted Ubuntu runners; Android Studio and a connected phone
are not needed. This workflow does not deploy Supabase or publish to Google Play.

## Get a testing APK

Push to `main` or `dev`, or open/update a pull request targeting either branch.
The setup branch `codex/android-cloud-build` also triggers a build for verification.
After the workflow is merged into the default branch, you can also use
**GitHub → Actions → Android cloud build → Run workflow**. Leave **signed_release**
unchecked to build a testing APK from the selected branch.

Open the finished run and download `eyecue-android-<run>-<attempt>` under
**Artifacts**. Unzip it to obtain:

- `eyecue-testsigned.apk` — optimized universal APK, with the repository's
  `-testsigned` version suffix. It is not a Play submission artifact.
- `BUILD.txt` — exact source commit, Flutter version, version name/code and
  whether upload configuration was supplied.
- `SHA256SUMS` — file checksums.

Artifacts expire after 14 days. Download any build you need to keep.
The workflow checks analyzer, Flutter tests and the backend validator before
building. Flutter is pinned to 3.44.2 (Dart 3.12.2), matching the tested local SDK;
Java is 17. Gradle memory/workers are limited for the hosted runner.

Cloud fallback signing uses the runner's generated Android debug keystore.
It is **not guaranteed to match** the existing phone installation or another
workflow run. Do not uninstall EyeCue to overcome a signature mismatch: doing
so can delete local trials. Use a stable, compatible signing key for updates.

## Configure online upload

In **repository Settings → Secrets and variables → Actions → Variables**, add:

| Repository variable | Value |
| --- | --- |
| `EYECUE_TELEMETRY_INGEST_URL` | `https://ovgkmrfpivgggsnunlov.supabase.co/functions/v1/ingest-telemetry` |
| `EYECUE_SUPABASE_PUBLISHABLE_KEY` | This project's `sb_publishable_...` client key |

Both are client build configuration, not server credentials. Never use a
Supabase secret/service-role key or study upload token here. The workflow
rejects partial configuration or an incorrect client-key type. If both variables
are absent, testing builds still work for local save/export, but **cannot upload**;
BUILD.txt and the run notice state that explicitly. Signed releases require both.

## Build a signed release APK and Play AAB

Use your existing upload keystore, or complete the upload-keystore setup in
`docs/release-procedure.md`. Back up the key and credentials privately. Do not
commit a keystore or `android/key.properties`.

Add these **repository Actions secrets**:

| Secret | Contents |
| --- | --- |
| `EYECUE_KEYSTORE_BASE64` | Base64-encoded upload keystore file |
| `EYECUE_KEYSTORE_PASSWORD` | Keystore password |
| `EYECUE_KEY_ALIAS` | Upload key alias |
| `EYECUE_KEY_PASSWORD` | Upload key password |

On Linux, `base64 -w 0 /absolute/path/to/upload.jks` produces the first value.
Copy it privately into GitHub's secret field; never paste it into chat or commit
it. Base64 is a transport encoding, not encryption.

Run the workflow manually on **main**, check **signed_release**, and set the
version name and version code. Signed releases from other branches are refused,
and signing secrets are only provided to signing steps in this manual mode.
Never enable `pull_request_target` to expose secrets to PR code.

The download will contain `eyecue-release.apk`, `eyecue-release.aab`, BUILD.txt
and checksums. Missing signing secrets cause failure, not a debug-signed AAB.
The workflow never uploads the keystore, source build directories or signing
properties. Temporary signing material is removed in an `always()` step.

Version code defaults to the workflow run number, not `pubspec.yaml`'s `+1`.
For a Play upload choose a code greater than every previously uploaded code.
Rerunning the same workflow run retains its code; start a new run or explicitly
choose a new code for a new Play upload. Default version name is 1.0.0.

An upload-key-signed APK may not match a locally debug-signed installation;
Play-delivered APKs are signed with the Play app-signing key, which may differ
from the upload key. Check certificate compatibility before updating a phone.
Building an AAB does not complete privacy/store declarations or Play review.

## Troubleshooting

- No Run workflow button: merge the workflow into GitHub's default branch first.
- Run fails: open the failed step before attempting another build. Tests block
  artifacts intentionally; don't bypass them to label a failing build successful.
- Upload unavailable: configure both repository variables and build again.
- Signed build refuses to start: select main and configure all four secrets.
- Actions restricted: check repository Settings → Actions → General permits
  the pinned checkout/setup-java/upload-artifact actions and subosito/flutter-action.
- Android wrapper files are ignored in this repository. Flutter regenerates
  them as needed during `flutter build`; the post-build test-signing task runs
  only after that generation.

References: [manual workflows](https://docs.github.com/en/actions/how-tos/manage-workflow-runs/manually-running-a-workflow),
[artifact upload](https://github.com/actions/upload-artifact),
[Flutter setup](https://github.com/subosito/flutter-action),
[Android app signing](https://developer.android.com/studio/publish/app-signing).
