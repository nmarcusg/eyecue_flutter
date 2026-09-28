# EyeCue — Known Issues

> **Last Updated:** 2026-09-28 (Detection redesign PD1–PD3)
> See also: [`implementation-decisions.md`](implementation-decisions.md) (why decisions were made), [`project-status.md`](project-status.md) (current state).

## Current Blockers

### 🟢 Detection Redesign (PD1–PD3) — Non-Blocking Notes

The Detection redesign (PD1–PD3) is implemented and statically validated (`flutter analyze` 0 issues; `flutter test` **323 passing**), with three runtime repairs applied after physical-device validation (Custom `IntrinsicHeight` layout cascade, Custom post-frame start intent, Ultralytics native-session recreation on start-after-stop). The behavioral-deviation audit found **no unintended deviations** from baseline `f310e73`. The following items are **non-blocking for the redesign** and are recorded for follow-up.

- **Ultralytics Ready timing semantics:** Ready can publish before the native camera returns to `CAMERA_STATE_ACTIVE`. The current definition is model/native initialization readiness, not strict pipeline-operational proof.
- **Post-resume freshness diagnostic limitation:** the epoch diagnostic cannot isolate the first result after Resume.
- **FlutterJNI teardown fatal:** not reproduced in the latest capture and **not fixed** — dedicated full-app teardown verification is pending.
- **Ultralytics GPU path:** falls back to CPU/XNNPACK on this device/session (pre-existing, not redesign-introduced).
- **Native CameraX graph churn** during recreation is expected plugin settling, not a proven leak.
- **Deferred — strict PD3 result provenance/freshness:** remains deferred under its existing scope boundary (see [`detection-redesign-plan.md`](frontend-workflow/detection-redesign-plan.md) §13/§18). The overlay's UI-only snapshot clearing prevents known historical values from remaining visible after a non-Ready transition, but does not prove that a delayed pre-transition result cannot arrive after a later Ready state. This is **non-blocking for the redesign** and is not claimed as resolved.
- **Location:** [`detection_screen.dart`](../lib/screens/detection_screen.dart), [`ultralytics_detection_screen.dart`](../lib/screens/ultralytics_detection_screen.dart), [`detection_action_controls.dart`](../lib/widgets/detection_action_controls.dart), and [`detection_information_overlay.dart`](../lib/widgets/detection_information_overlay.dart).
- **Status:** **Redesign implemented and statically validated; the items above are non-blocking follow-ups.**

### 🟡 Primary Gesture Navigation — Device-Observed Issues (Unresolved)

The primary gesture navigation feature is implemented (persisted `hideBottomNavigation` preference with accessible-navigation override, one-finger linear non-wrapping primary navigation, Detection directional arbitration, Detection-owned horizontal navigation, light/medium haptic wayfinding, minimal best-effort navigation TTS, preserved system Back behavior, and preserved Detection lifecycle). Physical-device testing surfaced three issues. All three are **device-observed, unresolved, and pending a root-cause fix** — they are not fixed.

- **Basic primary navigation:** Unlike the Home, Settings, and Help screens, a long or fast swipe on the Detection screen without releasing your finger triggers navigation. (Moving only one tab is the correct behavior.)
- **Detection horizontal navigation:** Navigation only triggers within the camera viewport.
- **Multi-pointer safety:** On the Home, Settings, and Help screens, swiping with one finger, holding it, adding a second finger, and then releasing the initial finger incorrectly triggers navigation.

- **Location:** [`app_shell.dart`](../lib/navigation/app_shell.dart) (shell gesture layer), [`gesture_controller.dart`](../lib/services/gesture_controller.dart) (Detection directional arbitration), and the Detection viewport [`gesture_surface.dart`](../lib/widgets/gesture_surface.dart).
- **Impact:** Primary navigation can fire on an unintended gesture (Detection long/fast swipe without release; multi-pointer sequence on Home/Settings/Help), and Detection horizontal navigation is limited to the camera viewport rather than the whole screen.
- **Planned Fix:** Root-cause each issue and re-verify on the physical Android device. The provisional horizontal thresholds, displacement guards, and dominance ratio remain subject to physical-device tuning.
- **Status:** **Device-observed, unresolved, pending a root-cause fix.**

### 🟡 Home/Detection Shared Lifecycle — Physical-Device Behavior (Needs Verification)

- **Description:** The shared Home/Detection lifecycle state is implemented and statically validated: [`EngineCoordinator`](../lib/services/engine_coordinator.dart) is the single app-shell-owned, user-facing Detection lifecycle/status source; Home and both Detection implementations render Preparing/Ready/Paused/Stopped/Unavailable from the same snapshot; an explicit `stopped` state and a one-shot start-intent contract were added; Auto-start ON prepares Detection in the background while Home stays visible; Auto-start OFF starts on deliberate entry without writing the preference; manual pause/stop is session-scoped; and the Home `Go to Live Camera` CTA was removed without replacement.
- **Location:** [`app_shell.dart`](../lib/navigation/app_shell.dart) (coordinator ownership + entry/launch intent), [`engine_coordinator.dart`](../lib/services/engine_coordinator.dart), [`home_screen.dart`](../lib/screens/home_screen.dart), [`detection_screen.dart`](../lib/screens/detection_screen.dart), and [`ultralytics_detection_screen.dart`](../lib/screens/ultralytics_detection_screen.dart).
- **Impact:** Offstage camera/native startup behavior on a physical device (Auto-start ON background preparation) has **not** been observed end-to-end. Whether an offstage cached `CameraPreview` or native `YOLOView` genuinely prepares at launch while Home is selected — including permission-dialog behavior and duplicate-open prevention — is unverified. Changing Auto-start while the app is already running, and Android background/foreground, process death, and camera pre-emption lifecycle behavior, are out of scope and unverified.
- **Planned Fix:** Validate the Auto-start ON background-preparation and Auto-start OFF entry-start flows on a physical Android device, and confirm the shared status surfaces (Home + both Detection implementations) match on-device.
- **Status:** **Implemented and statically validated; physical-device behavior Needs Verification.**

### 🔴 Dual-Engine Benchmark, Compatibility, and Licence Validation (Critical)

- **Description:** The selector, adapter, per-engine telemetry, Android packaging bridge, and basic device runtime are implemented. The fixed debug APK now installs and both engines process live camera frames on the Snapdragon 695/API 33 target; switching in both directions passed after correcting a lifecycle race. A controlled benchmark and broad device matrix have not been run.
- **Impact:** The smoke test is enough to establish initial functionality on one phone, but not comparative sustained FPS, detection quality, orientation coverage, thermal/battery behavior, memory use, or wide compatibility. `ultralytics_yolo` 0.6.13 is also AGPL-3.0, so public Play distribution requires compliance with that licence or a suitable commercial licence.
- **Planned Fix:** Complete the paired protocol in [`dual-inference-engine-test.md`](dual-inference-engine-test.md), cover representative Android/API/chipset classes, resolve the native numeric-label presentation issue, confirm delegate selection, and resolve the distribution-licence choice before release.
- **Status:** **Build and one-device smoke test passed; controlled performance, compatibility, and distribution validation pending.**

### 🔴 XNNPACK SIGSEGV / Candidate Device Validation (Critical)

- **Description:** The stable v0.2.2 path keeps XNNPACK disabled because the older YOLOv8n model previously caused a segmentation fault during inference on the Snapdragon 695 (Adreno 619 GPU). The current committed but unreleased runtime artifact `yolov8n_int8_new_metadata.tflite` (generated from the byte-identical `yolov8n_int8_new.tflite` base graph) attempts explicit XNNPACK and has FLOAT32 runtime I/O with an NCHW input.
- **Location:** [`inference_isolate.dart`](../lib/services/inference_isolate.dart) — interpreter creation / inference path.
- **Impact:** A native SIGSEGV cannot be caught by Dart and could still terminate the isolate/process. The candidate now installs and runs on the target phone, but only a short observation exists: 65 completed frames were labelled `XNNPACK`, with approximately 5.7–6.2 inference FPS in app summaries and no fatal signal observed in the captured process-filtered logs. Detection quality, long-duration stability, and comparative performance remain unestablished. The old stable baseline observed approximately 2–3 FPS and 600 ms latency on the low-end device.
- **Current mitigation:** Delegate ownership is retained for the interpreter lifetime. Recoverable Dart-level setup or invocation failures close the delegate-backed interpreter and retry on a four-thread CPU interpreter. This is not protection against a native crash.
- **Planned Fix:** Extend the controlled target-device run, capture fallback/native-crash evidence, and run the official TFLite benchmark tool for the old CPU baseline, the candidate, and safe NNAPI/GPU alternatives where available. Add ground-truth accuracy, thermal, and memory measurements before selecting a release backend.
- **Status:** **Partially device-observed but unresolved.** The candidate's short XNNPACK run is evidence of initial compatibility, not proof of speedup, long-term stability, full graph delegation, or crash resolution.

### ✅ Custom Worker Recovery (Resolved in App-Only Candidate)

- **Description:** The Custom worker now uses a pure injectable lifecycle coordinator with monotonic generations, typed worker-exit/error handling, bounded immediate/delayed retries, terminal failure, healthy-operation budget reset, and disposal-safe backoff.
- **Location:** [`inference_worker_lifecycle.dart`](../lib/services/inference_worker_lifecycle.dart) and [`inference_isolate.dart`](../lib/services/inference_isolate.dart)
- **Verification:** Seven deterministic tests cover worker exit/respawn, stale messages, busy-gate release, delayed retry, terminal failure, disposal during backoff, and successful recovery. Native crashes such as SIGSEGV remain outside Dart recovery guarantees.

## Resolved (previously tracked here)

- ✅ **Engine-switch closed-stream race** — RESOLVED in the unreleased candidate. A late Custom-isolate result could arrive after switching to Ultralytics and attempt to write to a closed result stream. Disposal now marks the service inactive before cancelling/closing resources, ignores late messages, and releases the UI busy gate when a frame is rejected. Both switch directions passed a post-fix device smoke test.
- ✅ **TTS integration** — RESOLVED v0.2.0. `flutter_tts` is now wired via [`tts_service.dart`](../lib/services/tts_service.dart) (cooldown, de-duplication, urgent bypass, mute, repeat-last). No longer a blocker.
- ✅ **Permission-denied UI** — RESOLVED v0.2.0. [`detection_screen.dart`](../lib/screens/detection_screen.dart) shows a camera-denied state with retry / open-settings. No longer a blocker.
- ✅ **Boilerplate counter-app test** — RESOLVED v0.2.0. [`test/widget_test.dart`](../test/widget_test.dart) now contains real Home/Settings/Help screen smoke tests; the full suite is 127 passing as of 2026-09-05.

## Technical Debt

| Priority | Item | Location |
|----------|------|----------|
| 🟡 P1 | `flutter_riverpod` is the only unused dependency (deliberately — state uses `ChangeNotifier` + `setState`); `fl_chart`, `path_provider`, and `flutter_tts` are now used | [`pubspec.yaml:23`](../pubspec.yaml:23) |
| ✅ | Model path, labels path, confidence threshold, and IoU threshold duplicated across engines | Resolved by [`model_config.dart`](../lib/models/model_config.dart) |
| 🟡 P1 | `flutter_tts` and `ultralytics_yolo` still apply the legacy Kotlin Gradle plugin mechanism; current builds pass, but a future Flutter toolchain will reject it | Upstream plugins / Android build |
| 🟡 P1 | Dual LiteRT packaging bridge must be revalidated whenever either inference package or the Android toolchain changes | [`build.gradle.kts`](../android/app/build.gradle.kts) |
| 🟡 P1 | Ultralytics' native overlay still needs device-level revalidation with the current metadata-enriched artifact; EyeCue's own adapted cards/TTS resolve labels correctly from `labels.txt` | Model metadata / Ultralytics overlay |
| 🟡 P2 | Full YUV plane copies across SendPort (~460KB per frame) — could use `TransferableTypedData` | [`detection_screen.dart`](../lib/screens/detection_screen.dart) (frame dispatch) |
| 🟡 P2 | Nearest-neighbor resize only — may reduce detection quality vs bilinear | [`inference_isolate.dart`](../lib/services/inference_isolate.dart) |
| 🟢 P3 | Package name is `com.example.eyecue_flutter` instead of specified `com.eyecue` | [`build.gradle.kts:7`](../android/app/build.gradle.kts:7) |
| 🟢 P3 | `minSdkVersion` relies on the Flutter default (24) — thesis targets Android 10 / API 29; not set explicitly | [`build.gradle.kts:18`](../android/app/build.gradle.kts:18) |
| 🟢 P3 | Release build still signs with the debug keystore | [`build.gradle.kts`](../android/app/build.gradle.kts) |
| ✅ | Detection sensitivity was previously fixed at 0.25 | Resolved by persisted presets and bounded advanced values in [`app_settings.dart`](../lib/models/app_settings.dart), applied through [`model_config.dart`](../lib/models/model_config.dart) |

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
