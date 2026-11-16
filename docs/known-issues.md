# EyeCue — Known Issues

Reviewed **2026-11-16** against local `main` at `aadf9e0`. This list separates unresolved evidence gaps from implemented behavior. See [project status](project-status.md), [testing](testing-plan.md), and [dated session evidence](session-log.md).

## Current validation gaps

| Area | Open question / required evidence | Source or procedure |
| --- | --- | --- |
| Current campus detector | Ground-truth precision/recall/mAP, class coverage, robustness and sustained on-device performance are not established by old COCO/Custom observations | [Model assets](model-assets.md), [benchmark procedure](benchmark-procedure.md) |
| Depth cost and quality | Achieved cadence, inference/transport cost, thermal/battery impact, memory, and metric accuracy need current-build measurements. The previously reported Redmi slowdown is not closed by instrumentation alone | [MDE](mde-integration.md), [benchmark results](benchmark-results.md) |
| Native lifecycle | Offstage launch preparation, permission-dialog behavior, background/foreground, camera pre-emption, first result after Resume, and full FlutterJNI teardown need device-specific evidence | [`engine_coordinator.dart`](../lib/services/engine_coordinator.dart), [`ultralytics_detection_screen.dart`](../lib/screens/ultralytics_detection_screen.dart) |
| Imported model | Real Android document-provider grants, imported graph execution, GPU acceptance/fallback, and screen-reader interaction need device validation | [`detector_model_service.dart`](../lib/services/detector_model_service.dart), [model contract](model-assets.md) |
| Gesture feel | Release-to-navigation latency, haptic timing, thresholds and dominance ratio need a targeted physical-device check; deterministic pointer tests do not measure feel | [`gesture_controller.dart`](../lib/services/gesture_controller.dart), [navigation record](frontend-workflow/navigation-plan.md) |
| Audible warning latency | App-side lifecycle timestamps do not measure physical sound onset. Platform callback ordering and missing/late callbacks still require care | [`tts_service.dart`](../lib/services/tts_service.dart), [telemetry dictionary](telemetry-data-dictionary.md) |
| Live Study upload | Deployed URL/key, ingest version, database access and a real upload need service-specific verification; local validators do not establish deployment state | [Supabase](supabase-research-telemetry.md), [threat model](ingest-threat-model.md) |
| Distribution | Actual Play track/review, production signing state, installed artifact identity, and source/licensing correspondence must be checked for each intended release | [Release procedure](release-procedure.md), [third-party notices](../THIRD_PARTY_NOTICES.md) |

## Depth limitations and implemented recovery

- Metres are uncalibrated estimates; bounding-box distance is heuristic. Neither proves safe independent navigation.
- Native/Dart geometry handling has limited orientation information; inspect the current [MDE contract](mde-integration.md) before assuming 180-degree or both landscape directions are resolved. Dated heatmap alignment verification covers its recorded device/layout, not all geometries.
- A map older than 1000 ms or incompatible with current geometry is not used for the heatmap; box distance is the fallback.
- Hiding boxes or the heatmap changes presentation. Selecting bounding-box approximation disables depth inference and releases the model; pause/stop/background retain it for reuse.
- Detection and depth models are bundled. The former first-use depth download problem is superseded; no download is needed for either built-in model.
- Detection Automatic/1–30 Hz and depth 2–10 Hz are requested targets. `EYECUE_DEPTH_ACCELERATOR=auto|cpu|gpu` is a build-time request; telemetry must be read as the native-reported actual accelerator, not proof of the request being honored.

## Model and research-session boundaries

Custom imports must satisfy the [supported model contract](model-assets.md#supported-custom-model-contract), including embedded labels/task metadata and size/class-count limits. A model change stops detection, clears the previous model's context, and requires Start. This is distinct from restarting a paused Study recording.

Only [`main_study.dart`](../lib/main_study.dart) constructs research sessions and watches detector identity changes. A change pauses an active trial and records a boundary; a no-op identity notification is not a boundary. Export model suffixes such as `~2` are local to that export and cannot be joined blindly across exports. Public builds retain detector selection and local telemetry but expose no Logs & Reports route or research-session service.

## Completed checks and non-blocking follow-ups

The 2026-11-09 [session record](session-log.md) reports TalkBack semantic operability/speech ownership and Detection alignment / chart-and-Logs polish as completed and device-verified on the tested devices. Do not reopen those exact checks merely because older design plans say pending. Conversely, that result does not close the full runtime/performance matrix above.

Remaining polish includes Camera view / Repeat discoverability, very long chart elapsed-time labels, and documented layout choices at 200% text scale. The native startup timeout and stale-view rejection are implemented protections; they do not establish native crash recovery or complete result provenance after every transition.

## Toolchain and maintenance

- Android SDK bounds inherit Flutter defaults; there is no explicit API-29-only floor. CI pins Flutter 3.44.2; update compatibility guidance if the toolchain changes.
- The local native plugin fork has required depth/metrics changes. Revalidate its native compilation and payload contracts on upgrades; app-only tests do not prove native behavior. See [fork maintenance](../plugins/ultralytics_yolo/VENDORED.md).
- Public release signing falls back to a marked test-signed artifact without upload credentials. Study tasks fail without retained Study signing material. The previous blanket claim that all release builds use the debug key is obsolete.
- Public/Study privacy surfaces differ. The public policy-launch failure path displays an actionable message; opening the external page still depends on the browser/network.

## Settings TalkBack crash fix now on main

The imported PR #17 commits remove slider value-label overlays without removing semantic formatting (`f95ffd6`), and add a narrow guard for the Flutter accessibility hover-transform exception in [`MainActivity.kt`](../android/app/src/main/kotlin/app/eyecue/mobile/MainActivity.kt) (`dd8aa53`). Other runtime exceptions remain visible. This session reviewed source only; it does not provide new device confirmation or prove every Flutter accessibility crash is prevented.

## Retired issues

The Custom-engine XNNPACK SIGSEGV, Custom-worker recovery, old dual-runtime packaging bridge, Dart YUV conversion, SendPort copies, and the old engine-switch race belong to removed code. Their [historical diagnostic records](index.md#historical-records) remain evidence for earlier revisions; they are not current blockers or promises of fixes in the native pipeline.
