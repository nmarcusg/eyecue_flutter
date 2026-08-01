# EyeCue — Known Issues

> See also: [`implementation-decisions.md`](implementation-decisions.md) (why decisions were made), [`project-status.md`](project-status.md) (current state).

## Current Blockers

### 🔴 XNNPACK SIGSEGV (Critical)

- **Description:** Enabling XNNPACK acceleration causes a segmentation fault during inference on the Snapdragon 695 (Adreno 619 GPU) with the INT8 YOLOv8n model.
- **Location:** [`inference_isolate.dart:93-94`](../lib/services/inference_isolate.dart:93)
- **Impact:** Without hardware acceleration, inference is CPU-bound and slower than it could be. This caps maximum detection FPS.
- **Planned Fix:** Benchmark raw model latency with the official TFLite benchmark tool on the target device. Test NNAPI delegate and GPU delegate as alternatives. Investigate whether the crash is TFLite version-specific or device-specific.
- **Workaround:** XNNPACK explicitly disabled; CPU-only inference is stable.

### 🔴 No TTS Integration (Critical)

- **Description:** `flutter_tts` is declared as a dependency but has zero usages in the codebase. The app's entire purpose — speaking detected objects — is not functional.
- **Planned Fix:** Implement TTS service in Milestone 1. Wire to detection stream with priority-based cooldown.

### 🟠 Incomplete Error Recovery in Inference Isolate (Critical)

- **Description:** Error **reporting** is now implemented (2026-07-22): try/catch around interpreter creation and the frame loop, plus error propagation to the main isolate via `{'type': 'error'}`. What remains is error **recovery** — if the isolate dies, the app does not restart it, so the UI can still end up with stale state.
- **Location:** [`_isolateEntryPoint`](../lib/services/inference_isolate.dart) (try/catch around interpreter creation + frame loop)
- **Planned Fix:** Implement isolate restart/recovery on fatal error (part of Milestone 4 per [`implementation-plan.md`](implementation-plan.md)).

### 🔴 No Permission-Denied UI (Critical)

- **Description:** When camera permission is denied, [`_setupCamera()`](../lib/screens/camera_screen.dart) just returns. The user sees an infinite loading spinner with no feedback.
- **Location:** [`camera_screen.dart`](../lib/screens/camera_screen.dart) — `_setupCamera()` permission check
- **Planned Fix:** Add permission-denied UI state with explanation and "Open Settings" button.

## Technical Debt

| Priority | Item | Location |
|----------|------|----------|
| 🟡 P1 | No NMS implementation — duplicate detections for same object | [`inference_isolate.dart:269`](../lib/services/inference_isolate.dart:269) |
| 🟡 P1 | 4 unused dependencies (~57% of deps): Riverpod, fl_chart, path_provider, flutter_tts | [`pubspec.yaml:22-32`](../pubspec.yaml:22) |
| 🟡 P1 | ~~No bounding box painter~~ — ✅ Implemented 2026-07-22 | [`lib/widgets/bounding_box_painter.dart`](../lib/widgets/bounding_box_painter.dart) |
| 🟡 P2 | Hardcoded thresholds, model paths, labels path | Multiple locations |
| 🟡 P2 | Full YUV plane copies across SendPort (~460KB per frame) — could use `TransferableTypedData` | [`camera_screen.dart:98`](../lib/screens/camera_screen.dart:98) |
| 🟡 P2 | Nearest-neighbor resize only — may reduce detection quality vs bilinear | [`inference_isolate.dart:212`](../lib/services/inference_isolate.dart:212) |
| 🟢 P3 | Package name is `com.example.eyecue_flutter` instead of specified `com.eyecue` | [`build.gradle.kts:17`](../android/app/build.gradle.kts:17) |
| 🟢 P3 | `minSdkVersion` relies on Flutter default (21) — `tflite_flutter` may need 24+ | [`build.gradle.kts:18`](../android/app/build.gradle.kts:18) |
| 🟢 P3 | Boilerplate counter-app test file — zero functional tests | [`test/widget_test.dart`](../test/widget_test.dart) |
| 🟢 P3 | Stale `.flutter-plugins` file — references old camera version | [`.flutter-plugins`](../.flutter-plugins) |

## Platform-Specific Limitations

- **Android:** Primary target. Snapdragon 695 testing device has XNNPACK crash. Other devices untested.
- **iOS:** Bootstrapped but not configured. No camera permissions plist, no Podfile customization.
- **Linux/macOS/Windows/Web:** Bootstrapped by `flutter create`. Untested, likely non-functional for camera/ML features.

## Known Bugs

| Bug | Details |
|-----|---------|
| ~~Camera frames never rotated to device orientation~~ | ✅ **FIXED (2026-08-01, v0.1.7)** — `BoxTransform` rotates/mirrors the input tensor to upright; portrait detections 0 → 0.91 on-device. See [`docs/orientation-implementation.md`](orientation-implementation.md). Back-landscape re-validation + front-camera runs still pending. |
| ~~YUV420→RGB ignored rowStride/pixelStride~~ | ✅ **FIXED (2026-08-01, v0.1.4)** — converter honors real plane geometry; planar I420 + semi-planar NV12/NV21 verified on-device. See [`docs/camera-path-forensics.md`](camera-path-forensics.md). |
| YUV conversion uses non-standard coefficients | Slight color shift in RGB output. Does not affect detection accuracy but could impact future visual-only features. |
| `dynamic` type for input buffer | [`inference_isolate.dart:137`](../lib/services/inference_isolate.dart:137) loses type safety. Could use sealed class. |
| Broadcast stream with single listener | Over-provisioned but harmless. Could be simplified to a single-subscription stream. |

## Planned Fixes (by Milestone)

See [`implementation-plan.md`](implementation-plan.md) for the full roadmap.
