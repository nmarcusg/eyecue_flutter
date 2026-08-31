# EyeCue — Known Issues

> **Last Updated:** 2026-09-01
> See also: [`implementation-decisions.md`](implementation-decisions.md) (why decisions were made), [`project-status.md`](project-status.md) (current state).

## Current Blockers

### 🔴 XNNPACK SIGSEGV / Candidate Device Validation (Critical)

- **Description:** The stable v0.2.2 path keeps XNNPACK disabled because the older YOLOv8n model previously caused a segmentation fault during inference on the Snapdragon 695 (Adreno 619 GPU). The current committed but unreleased candidate attempts explicit XNNPACK for `yolov8n_int8_new.tflite`, whose runtime I/O is FLOAT32 with an NCHW input.
- **Location:** [`inference_isolate.dart`](../lib/services/inference_isolate.dart) — interpreter creation / inference path.
- **Impact:** A native SIGSEGV cannot be caught by Dart and could still terminate the isolate/process. The candidate now installs and runs on the target phone, but only a short observation exists: 65 completed frames were labelled `XNNPACK`, with approximately 5.7–6.2 inference FPS in app summaries and no fatal signal observed in the captured process-filtered logs. Detection quality, long-duration stability, and comparative performance remain unestablished. The old stable baseline observed approximately 2–3 FPS and 600 ms latency on the low-end device.
- **Current mitigation:** Delegate ownership is retained for the interpreter lifetime. Recoverable Dart-level setup or invocation failures close the delegate-backed interpreter and retry on a four-thread CPU interpreter. This is not protection against a native crash.
- **Planned Fix:** Extend the controlled target-device run, capture fallback/native-crash evidence, and run the official TFLite benchmark tool for the old CPU baseline, the candidate, and safe NNAPI/GPU alternatives where available. Add ground-truth accuracy, thermal, and memory measurements before selecting a release backend.
- **Status:** **Partially device-observed but unresolved.** The candidate's short XNNPACK run is evidence of initial compatibility, not proof of speedup, long-term stability, full graph delegation, or crash resolution.

### 🟠 Incomplete Error Recovery in Inference Isolate (High)

- **Description:** Error **reporting** is implemented (2026-07-22): try/catch around interpreter creation and the frame loop, plus error propagation to the main isolate via `{'type': 'error'}`. What remains is error **recovery** — if the isolate dies, the app does not restart it, so the UI can still end up with stale state.
- **Location:** [`_isolateEntryPoint`](../lib/services/inference_isolate.dart) (try/catch around interpreter creation + frame loop)
- **Planned Fix:** Implement isolate restart/recovery on fatal error (part of Milestone 4 per [`implementation-plan.md`](implementation-plan.md)).
- **Note:** The permission-denied and camera-error UI states were added in v0.2.0; only isolate self-healing remains.

## Resolved (previously tracked here)

- ✅ **TTS integration** — RESOLVED v0.2.0. `flutter_tts` is now wired via [`tts_service.dart`](../lib/services/tts_service.dart) (cooldown, de-duplication, urgent bypass, mute, repeat-last). No longer a blocker.
- ✅ **Permission-denied UI** — RESOLVED v0.2.0. [`detection_screen.dart`](../lib/screens/detection_screen.dart) shows a camera-denied state with retry / open-settings. No longer a blocker.
- ✅ **Boilerplate counter-app test** — RESOLVED v0.2.0. [`test/widget_test.dart`](../test/widget_test.dart) now contains real Home/Settings/Help screen smoke tests; the full suite is 73 passing as of 2026-09-01.

## Technical Debt

| Priority | Item | Location |
|----------|------|----------|
| 🟡 P1 | `flutter_riverpod` is the only unused dependency (deliberately — state uses `ChangeNotifier` + `setState`); `fl_chart`, `path_provider`, and `flutter_tts` are now used | [`pubspec.yaml:23`](../pubspec.yaml:23) |
| 🟡 P2 | Hardcoded thresholds, model paths, labels path | Multiple locations |
| 🟡 P2 | Full YUV plane copies across SendPort (~460KB per frame) — could use `TransferableTypedData` | [`detection_screen.dart`](../lib/screens/detection_screen.dart) (frame dispatch) |
| 🟡 P2 | Nearest-neighbor resize only — may reduce detection quality vs bilinear | [`inference_isolate.dart`](../lib/services/inference_isolate.dart) |
| 🟢 P3 | Package name is `com.example.eyecue_flutter` instead of specified `com.eyecue` | [`build.gradle.kts:7`](../android/app/build.gradle.kts:7) |
| 🟢 P3 | `minSdkVersion` relies on the Flutter default (24) — thesis targets Android 10 / API 29; not set explicitly | [`build.gradle.kts:18`](../android/app/build.gradle.kts:18) |
| 🟢 P3 | Release build still signs with the debug keystore | [`build.gradle.kts`](../android/app/build.gradle.kts) |
| 🟢 P3 | Detection-sensitivity is a hardcoded constant (0.25) — not yet user-configurable | [`inference_isolate.dart`](../lib/services/inference_isolate.dart) |

## Platform-Specific Limitations

- **Android:** The **only** supported platform (per the thesis). The Snapdragon 695 testing device has a historical XNNPACK crash; the current candidate has only initial short-run validation there after storage was cleared. Other devices are untested.
- **iOS / web / Windows / macOS / Linux:** Out of scope — EyeCue is Android-only. Their scaffolding was removed during the Android-only platform cleanup; no support is provided or planned.

## Known Bugs

| Bug | Details |
|-----|---------|
| ~~Camera frames never rotated to device orientation~~ | ✅ **FIXED (2026-08-01, v0.1.7)** — `BoxTransform` rotates/mirrors the input tensor to upright; portrait detections 0 → 0.91 on-device. See [`docs/orientation-implementation.md`](orientation-implementation.md). Back-landscape re-validation + front-camera runs still pending. |
| ~~YUV420→RGB ignored rowStride/pixelStride~~ | ✅ **FIXED (2026-08-01, v0.1.4)** — converter honors real plane geometry; planar I420 + semi-planar NV12/NV21 verified on-device. See [`docs/camera-path-forensics.md`](camera-path-forensics.md). |
| YUV conversion uses non-standard coefficients | Slight color shift in RGB output. Does not affect detection accuracy but could impact future visual-only features. |
| `dynamic` type for the input buffer | [`inference_isolate.dart:392`](../lib/services/inference_isolate.dart:392) loses type safety. Could use a sealed/branched type per model dtype. |
| ~~Broadcast stream with single listener~~ | ✅ **NO LONGER AN ISSUE (v0.2.0)** — the broadcast `resultsStream` now has multiple listeners (UI + TTS + telemetry), so broadcast is justified. |

## Planned Fixes (by Milestone)

See [`implementation-plan.md`](implementation-plan.md) for the full roadmap.
