# Android builds on GitHub Actions

Workflow: `.github/workflows/android-build.yml` (**Android cloud build**).
It builds on GitHub-hosted Ubuntu runners; Android Studio and a connected phone
are not needed. The workflow does not deploy Supabase. A signed public manual
dispatch can upload to Play internal testing when `upload_internal` is enabled;
it does not publish to the production track.

## Get a testing APK

Push to `main` or `dev`, or open/update a pull request targeting either branch.
The CI branch `ci/android-cloud-build` and feature branch
`feat/tts-speech-continuity` also trigger push builds.
After the workflow is merged into the default branch, you can also use
**GitHub → Actions → Android cloud build → Run workflow**. Leave **signed_release**
unchecked to build a testing APK from the selected branch.

Open the finished run and download `eyecue-android-<run>-<attempt>` under
**Artifacts**. Unzip it to obtain:

- `eyecue-public-testsigned.apk` — optimized public APK, with the repository's
  `-testsigned` version suffix. It has no `INTERNET` permission; the public app does not construct or invoke
  an upload client.
- If `study_build` is selected: `eyecue-study.apk`, built with the retained Study
  key and research entrypoint. Study never produces an AAB.
- `BUILD.txt` — exact source commit, Flutter version, version name/code and
  whether upload configuration was supplied.
- `SHA256SUMS` — file checksums.

Artifacts expire after 14 days. Download any build you need to keep.
The workflow runs `flutter pub get --enforce-lockfile`, `flutter analyze`,
`flutter test --concurrency=1`, and the Node backend validator before building.
It pins Flutter 3.44.2 on stable and Java 17. The project declares a Dart SDK
constraint of `>=3.12.0 <4.0.0` in `pubspec.yaml`; the constraint is not a local
SDK version report. Gradle memory/workers are limited for the hosted runner.

Cloud fallback signing uses the runner's generated Android debug keystore.
It is **not guaranteed to match** the existing phone installation or another
workflow run. Do not uninstall EyeCue to overcome a signature mismatch: doing
so can delete local trials. Use a stable, compatible signing key for updates.

## Configure Study upload

In **repository Settings → Secrets and variables → Actions → Variables**, add:

| Repository variable | Value |
| --- | --- |
| `EYECUE_TELEMETRY_INGEST_URL` | `https://ovgkmrfpivgggsnunlov.supabase.co/functions/v1/ingest-telemetry` |
| `EYECUE_SUPABASE_PUBLISHABLE_KEY` | This project's `sb_publishable_...` client key |

Both are client build configuration, not server credentials. Never use a
Supabase secret/service-role key or study upload token here. The workflow
requires both variables for Study and ignores configured variables on public
builds. Public EyeCue declares no `INTERNET` permission and never constructs an
upload client; the uploader class may remain compiled-in but is unreachable.
`BUILD.txt` records the
variant, entrypoint and telemetry state.

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

The public download will contain `eyecue-public-release.apk`,
`eyecue-public-release.aab`, `BUILD.txt` and checksums. If `upload_internal`
remains enabled, the same dispatch also uploads the signed public AAB to Play's
internal track after the artifact is saved. Uncheck it to build without a Play
upload. Missing signing secrets cause failure, not a debug-signed AAB.
The workflow never uploads the keystore, source build directories or signing
properties. Temporary signing material is removed in an `always()` step.

Version code defaults to the workflow run number, not `pubspec.yaml`'s `+1`.
For a Play upload choose a code greater than every previously uploaded code.
Rerunning the same workflow run retains its code; start a new run or explicitly
choose a new code for a new Play upload. Default version name is 1.0.0.

An upload-key-signed APK may not match a locally debug-signed installation;
Play-delivered APKs are signed with the Play app-signing key, which may differ
from the upload key. Check certificate compatibility before updating a phone.
The app's Help screen links to `https://nmarcusg.github.io/eyecue_flutter/` in
the public flavor. This workflow does not verify that page's current content or
availability. Building or uploading an AAB does not complete privacy/store
declarations or Play review.

## Troubleshooting

- No Run workflow button: merge the workflow into GitHub's default branch first.
- Run fails: open the failed step before attempting another build. Tests block
  artifacts intentionally; don't bypass them to label a failing build successful.
- Study telemetry upload unavailable: configure `EYECUE_TELEMETRY_INGEST_URL`
  and `EYECUE_SUPABASE_PUBLISHABLE_KEY`, then rebuild Study.
- Play internal upload unavailable: verify `EYECUE_PLAY_SERVICE_ACCOUNT_JSON`,
  the public signing secrets, and a manual signed dispatch with `upload_internal`
  enabled; see [Play automation](play-internal-automation.md).
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
