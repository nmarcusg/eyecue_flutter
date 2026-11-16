# EyeCue

EyeCue is an Android app that detects objects on-device and provides spoken object, position, and approximate distance guidance. The current checkout uses a campus-trained detector with 14 labels, a vendored native Ultralytics engine, and optional monocular depth estimation.

> Documentation reviewed on **2026-11-16** against local `main` at `aadf9e0`. The version declared in `pubspec.yaml` is `1.0.0+1`; CI can override it. Earlier `v0.2.x` versions and test counts are historical records, not a statement about the latest published release. No Play Console or live service status was verified in this documentation pass.

## Build variants

| Variant | Android identity | Dart entry point | User-facing differences |
| --- | --- | --- | --- |
| Public EyeCue | `app.eyecue.mobile` | [`lib/main.dart`](lib/main.dart) | Home, Detect, Settings, Help; no Logs & Reports route or research-session service; Help links to the privacy policy |
| EyeCue Study | `app.eyecue.mobile.study` | [`lib/main_study.dart`](lib/main_study.dart) | Adds explicit research trials, Logs & Reports, document export, and optional manual telemetry upload |

Both entry points wire detector selection, settings, on-device detection, speech, haptics, and local telemetry. The public release manifest has no `INTERNET` permission; Study adds it for manual upload. Opening the public privacy-policy link delegates to an external browser. Android debug/profile manifests permit development networking.

## Start development

CI pins **Flutter 3.44.2**. The `>=3.12.0 <4.0.0` constraint in [`pubspec.yaml`](pubspec.yaml) refers to **Dart**, not Flutter. Use a compatible Flutter SDK and Android toolchain; the native build uses Java 17. Android SDK levels are inherited from Flutter in [`android/app/build.gradle.kts`](android/app/build.gradle.kts).

```bash
cd /home/nico/repos/eyecue_flutter
flutter pub get
flutter run --flavor public -t lib/main.dart
```

Study requires its retained signing credentials, including for a debug run, because the Gradle configuration refuses Study tasks without them:

```bash
flutter run --flavor study -t lib/main_study.dart
```

See [Study installation](docs/study-installation.md) and the [release procedure](docs/release-procedure.md) before building signed artifacts. Builds and caches were removed during workspace consolidation; the first run will regenerate them.

## Current behavior

- One native detection engine: the local [`ultralytics_yolo`](plugins/ultralytics_yolo/VENDORED.md) fork (upstream version 0.6.13). The Custom Dart/isolate engine was removed in October 2026.
- Built-in detector: `assets/eyecue_v8_campus_only_w8a32.tflite`, with 14 labels from [`assets/labels.txt`](assets/labels.txt). An imported detector uses its own validated metadata/labels; class IDs must not be assumed to be COCO IDs.
- Optional bundled `yolo26n-depth` graph estimates distance. Bounding-box mode disables depth inference. Metres are uncalibrated estimates; configured cadence is a target, not a measured rate.
- Shared lifecycle coordination, object tracking, spatial/priority interpretation, lifecycle-aware TTS arbitration, gesture controls, and persisted settings (schema 8).
- Study telemetry exports use schema 4 and contain numeric/label data rather than camera images. These exports do not establish accuracy, mAP, or physical audible-warning latency.
- TalkBack ownership and presentation phases have dated device-verification records in the [session log](docs/session-log.md). Those records apply to the described checks and tested devices, not every later build.

## Documentation

Start with the [complete documentation index](docs/index.md), then:

| Need | Document |
| --- | --- |
| Current state and next steps | [Project status](docs/project-status.md), [known issues](docs/known-issues.md) |
| Resume the side project | [Development workflow](docs/development-workflow.md), [roadmap](docs/implementation-plan.md) |
| Understand the implementation | [Architecture](docs/architecture.md), [component inventory](docs/component-inventory.md) |
| Model and depth contracts | [Model assets](docs/model-assets.md), [MDE](docs/mde-integration.md) |
| Validate behavior and performance | [Testing plan](docs/testing-plan.md), [benchmark procedure](docs/benchmark-procedure.md), [benchmark results](docs/benchmark-results.md) |
| Study data | [Log export](docs/log-export.md), [telemetry dictionary](docs/telemetry-data-dictionary.md), [Supabase upload](docs/supabase-research-telemetry.md) |
| Build/distribute | [Cloud builds](docs/cloud-builds.md), [release procedure](docs/release-procedure.md), [Play automation](docs/play-internal-automation.md) |
| Privacy and licensing | [Privacy/data safety](docs/privacy-and-data-safety.md), [third-party notices](THIRD_PARTY_NOTICES.md) |
| Dated implementation evidence | [Progress log](docs/implementation-progress.md), [session log](docs/session-log.md), [changelog](docs/changelog.md) |

## Repository layout

```text
lib/main.dart              Public entry point
lib/main_study.dart        Study entry point
lib/app.dart               Shared application wiring
lib/navigation/            Shell, lifecycle ownership, navigation
lib/screens/               Screens and native Detection integration
lib/models/                Settings, detection, model, export contracts
lib/services/              Speech, tracking, depth, model selection, research data
lib/widgets/               Controls, overlays, semantics, charts
assets/                    Bundled detector, depth model, labels, offline fonts
plugins/ultralytics_yolo/   Maintained local native/Dart fork
test/                      App unit, widget, accessibility and source-contract tests
supabase/                  Study ingest function, validators and migrations
tool/                      Metadata, icons and Study artifact helpers
.github/                   Build and Play automation
docs/                      Current guidance and dated records
```

## License

Application source is declared `AGPL-3.0-only`; see [`LICENSE`](LICENSE). Preserve the vendored plugin and model notices and consult [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md) and the [release procedure](docs/release-procedure.md) for the repository's distribution checklist. This documentation pass does not establish external licence clearance.
