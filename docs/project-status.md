# EyeCue — Project Status

Reviewed **2026-11-16** against local `main` at `aadf9e0`. This is a repository audit; no new app tests, build, device run, backend call, or Play Console inspection is claimed.

## Current application

EyeCue remains available for side-project development in `/home/nico/repos/eyecue_flutter`. Extra local worktrees were consolidated into compressed snapshots under `/home/nico/repos/eyecue-archive/2026-11-16`; their branches remain available. Build/dependency caches regenerate on demand.

| Area | Current implementation | Evidence |
| --- | --- | --- |
| Distribution | Public `app.eyecue.mobile`; Study `app.eyecue.mobile.study` | [`build.gradle.kts`](../android/app/build.gradle.kts), [`main.dart`](../lib/main.dart), [`main_study.dart`](../lib/main_study.dart) |
| Native runtime | One vendored Ultralytics detection engine; no Custom-engine selector | [`app_settings.dart`](../lib/models/app_settings.dart), [fork notes](../plugins/ultralytics_yolo/VENDORED.md) |
| Detector | Campus-trained built-in model, 14 labels; validated custom import is also available | [`model_config.dart`](../lib/models/model_config.dart), [`labels.txt`](../assets/labels.txt), [model contract](model-assets.md) |
| Distance | Optional bundled monocular depth, or bounding-box approximation; configurable cadence/overlays | [MDE](mde-integration.md), [`app_settings.dart`](../lib/models/app_settings.dart) |
| Assistive UI | Home / Detect / Settings / Help, shared lifecycle, gestures, haptics, TalkBack semantics | [`app_shell.dart`](../lib/navigation/app_shell.dart), [UI conventions](ui-conventions.md) |
| Speech | Lifecycle-aware serialized arbiter, track-aware policy, controlled preemption, repeat/scan | [`tts_service.dart`](../lib/services/tts_service.dart), [alert responsiveness](alert-responsiveness.md) |
| Research | Study entry point owns explicit trials, Logs & Reports, exports, optional manual upload | [`main_study.dart`](../lib/main_study.dart), [export](log-export.md), [upload](supabase-research-telemetry.md) |
| Persistence | Settings schema 8; Study telemetry export schema 4 | [`app_settings.dart`](../lib/models/app_settings.dart), [`telemetry_export.dart`](../lib/models/telemetry_export.dart) |
| Release tooling | Public/Study cloud artifacts, retained signing configuration, optional Play internal upload | [Cloud builds](cloud-builds.md), [Play automation](play-internal-automation.md) |

The public entry point does not construct `ResearchSessionService` or a Logs & Reports route. The shared main manifest declares camera access; only Study's release manifest adds internet access. Public Help opens the policy in an external browser. Development debug/profile networking is separate.

## Verification evidence and limits

The [session log](session-log.md) records completion and target-device verification of TalkBack ownership and the Detection alignment / Charts and Logs presentation phases on 2026-11-09. Its chart-polish entry records **882 passing tests** and a clean analyzer at that revision. Later commits added public/Study separation, the campus model, Play automation, and the policy-link failure test. Do not reuse an older suite total as the result of this checkout.

The [changelog](changelog.md), [progress history](implementation-progress.md), and historical audits retain older versions and evidence. `v0.2.2`, 59/127/527-test totals, dual-engine comparisons, and NCHW/XNNPACK observations refer to their dated revisions. `pubspec.yaml` currently declares `1.0.0+1`; workflows can override version name/code. Published track/version and live service state remain unverified here.

The checkout was fast-forwarded from `879be04` to remote `main` at `aadf9e0` during this audit. The added commits remove slider value-label overlays while retaining semantic formatting (`f95ffd6`) and guard the specific Flutter accessibility hover-transform exception in Android (`dd8aa53`, PR #17). These are source-verified fixes, without a fresh build or device result in this session.

## Next work

1. Restore dependencies when resuming implementation, then run relevant checks for the changed behavior. CI's baseline is Flutter 3.44.2; the manifest's 3.12 constraint is Dart.
2. Evaluate the **current campus model** with labelled ground truth and a controlled device matrix. Retired COCO/Custom observations do not measure it.
3. Measure depth cadence, sustained detection FPS, thermal/battery cost, memory, and physical audible-warning latency under the [benchmark protocol](benchmark-procedure.md).
4. Close the remaining native startup/resume/teardown, custom-model picker/execution, and accessibility checks listed in [known issues](known-issues.md).
5. Before distribution, verify artifact identity/signing/source correspondence and the actual service/Play state using the [release procedure](release-procedure.md).

No completion percentage or remaining-hours estimate is assigned without a new evaluation baseline. Implementation coverage, device observations, research outcomes, and distribution readiness are separate evidence categories.
