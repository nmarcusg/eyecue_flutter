# EyeCue — Project Status

> **Last Updated:** 2026-09-01 (candidate device retry)
> See also: [`implementation-progress.md`](implementation-progress.md) (detailed progress), [`known-issues.md`](known-issues.md) (blockers), [`thesis-product-status-audit.md`](thesis-product-status-audit.md) (thesis-aligned completion baseline).

> **Latest release:** v0.2.2. Since the v0.2.0 UI landed, v0.2.1 fixed the startup theme-construction assertion and v0.2.2 fixed the camera viewport resizing with detections plus chart overflow in Logs & Reports. The repository contains committed but unreleased model/layout/backend changes; see the section below and [`changelog.md`](changelog.md).

## Overall Progress

**ML/inference pipeline:** stable v0.2.2 baseline is ~80% complete and on-device validated; the current model/backend candidate is statically validated and has initial short-run device evidence, but is not formally benchmarked or release-validated.
**Thesis product (app as a whole):** ~70% (range 65–75%) — see the [thesis-product-status-audit](thesis-product-status-audit.md) for the weighted breakdown (re-scored after the v0.2.x assistive-UI phase; the earlier ~30% measured the pre-assistive-UI state, and the historical "~60%" measured only the ML/debug pipeline).

## What Changed (v0.2.x — Assistive Application UI)

The app is no longer a single developer camera screen. It now has the thesis-aligned application structure (built in v0.2.0; layout/theme fixes in v0.2.1–v0.2.2):

- **Navigation:** 4-tab bottom bar — Home, Detect, Settings, Help ([`app_shell.dart`](../lib/navigation/app_shell.dart)); Logs & Reports pushed from Settings.
- **Home:** branding, status card (Auto-Start aware), "Go to Live Camera".
- **Detection:** the validated camera/inference pipeline preserved, now with an assistive UI — status pill, audio mute, object cards with priority badges, high-priority warning banner, visible controls, and thesis gestures (two-finger double-tap start/stop, single tap pause/resume, three-finger scan, swipe-down repeat) with haptic + TTS confirmation.
- **TTS audio feedback:** implemented ([`tts_service.dart`](../lib/services/tts_service.dart)) — cooldown, de-duplication, urgent bypass, repeat-last, mute state. `flutter_tts` is now wired (previously declared-only).
- **Settings:** persisted preferences — Vibration, Auto-Start, Low Power Mode (dispatch throttle), Audio guidance, Logs & Reports ([`settings_service.dart`](../lib/services/settings_service.dart)).
- **Help:** how it works, gestures, confirmation feedback, Android usage tips.
- **Logs & Reports:** Overview / Charts / Logs with `fl_chart`; accuracy/precision/recall/mAP explicitly shown as unavailable (require ground truth).
- **Spatial/priority layer:** left/center/right + priority tiers + approximate proximity band ([`spatial_analysis_service.dart`](../lib/services/spatial_analysis_service.dart)) — kept separate from the inference pipeline.
- Stable v0.2.2 validation remains the historical **59-test** on-device baseline. The current repository has **73 passing tests** and `flutter analyze`: **0 issues**.

## Current Unreleased Candidate (2026-09-01)

The following changes are present in the repository but are not a new release yet:

- **Model:** [`yolov8n_int8_new.tflite`](../assets/yolov8n_int8_new.tflite) has input `[1,3,640,640]` (NCHW) and output `[1,84,8400]`; both runtime I/O tensors are FLOAT32 while the flatbuffer contains internally quantized tensors. [`ModelMetadata`](../lib/models/model_metadata.dart) classifies it as *Weight-Quantized* from inspection rather than from the filename.
- **Preprocessing:** the inference path now chooses NHWC or NCHW from runtime input shape. [`tensor_rotation.dart`](../lib/models/tensor_rotation.dart) provides pure, unit-tested rotation/mirror logic for both layouts.
- **Backend:** the isolate attempts explicit XNNPACK, retains the delegate for the interpreter lifetime, and retries on CPU for recoverable Dart-level setup/invocation failures. A native SIGSEGV cannot be caught by Dart, so the historical Snapdragon 695 XNNPACK crash is not considered resolved.
- **Static verification:** `flutter analyze` passes; `flutter test` passes with 73 tests; the flatbuffer and PNG validators pass; and the generated debug APK contains the new model asset.
- **Device validation:** after storage was cleared, the exact debug APK installed successfully on the API 33 Snapdragon 695 target (`2201116SG`, arm64). Startup logs confirmed the candidate metadata (`[1,3,640,640]` FLOAT32 input, `[1,84,8400]` FLOAT32 output, *Weight-Quantized*) and successful explicit XNNPACK interpreter creation with four threads. A short live run completed 65 frames, all logged as `backend=XNNPACK`; calculated latency was 164.8 ms mean, 157.7 ms median, and 150.2–377.3 ms range. The app process remained alive and no candidate-process `SIGSEGV`/fatal marker appeared in the captured logs. An earlier short observation also returned one `tv` detection at 67.9% confidence and 113.7 ms.

This candidate must remain labelled **unreleased and initially device-observed**. The short run is not a formal benchmark, accuracy evaluation, thermal/memory test, long-duration stability test, or proof that every graph operation was delegated to XNNPACK. The native SIGSEGV risk therefore remains unresolved.

## Current Milestone

**Milestone 2: "Research-Ready"** (extends the v0.1 "Audible MVP" work — audio + assistive UI now landed)

| Task | Status |
|------|--------|
| TTS audio feedback (start/stop, detections, scan, repeat) | ✅ Implemented (v0.2.0) |
| Thesis gesture controls + haptic/TTS confirmation | ✅ Implemented (v0.2.0) |
| Home / Settings / Help / Logs & Reports screens + navigation | ✅ Implemented (v0.2.0) |
| Persisted settings (vibration, auto-start, low-power, audio) | ✅ Implemented (v0.2.0) |
| Spatial position (left/center/right) + priority classification | ✅ Implemented (heuristic proximity band) (v0.2.0) |
| Runtime telemetry + charts (latency/FPS/frequency) | ✅ Implemented (v0.2.0) |
| Error handling in isolate | 🟡 Partial — setup/invocation CPU fallback and error propagation exist; fatal isolate restart recovery is missing |
| Permission-denied UI | ✅ Implemented (v0.2.0 — camera-denied screen with retry/open-settings) |
| Isolate restart recovery | ❌ Not started |
| Orientation re-validation (back landscape + front camera) | 🟡 In progress — stable NHWC baseline portrait/static verified; candidate NCHW has an initial short portrait run, while landscape/front-camera device runs remain pending |

## Current Blocker

**XNNPACK/device validation is incomplete.** The stable v0.2.2 path is CPU-only because XNNPACK previously crashed on Snapdragon 695 with the older bundled YOLOv8n model (FLOAT32 I/O, INT8 weights). The current unreleased candidate now installs and runs on the target: the explicit XNNPACK interpreter completed 65 logged live frames in a short observation, with approximately 5.7–6.2 inference FPS in 5-second summaries and no observed candidate-process fatal signal. Native crashes remain uncatchable, and the short run does not establish a performance improvement, long-term stability, full graph delegation, or accuracy result.

See [`known-issues.md`](known-issues.md) for full blocker details.

## Next Objective

1. **Extend candidate device validation** — repeat the target-device run for a controlled duration, collect fallback/crash evidence, and measure detections without treating the short observation as a release benchmark.
2. **Re-validate orientation on-device** — candidate NCHW portrait/landscape and front-camera runs, plus the deferred stable-baseline cases.
3. **Run formal model/backend benchmarks** — compare the old CPU/NHWC baseline, the NCHW candidate, and any safe delegates; do not infer performance from static inspection or the app's short observational run.
4. **Complete the v0.2.x UI validation** — gestures, TTS, mute toggle, settings persistence, and Logs & Reports charts.
5. **Implement isolate restart recovery** and remaining research-evaluation work (see the audit's phases).

## High-Priority Tasks

| # | Task | Priority |
|---|------|----------|
| 1 | On-device validation of gestures + TTS + settings persistence | 🔴 Critical |
| 2 | ~~Implement TTS audio feedback~~ | ✅ Complete (v0.2.0) |
| 3 | ~~Add permission-denied and error UI states~~ | 🟡 Partial — permission UI done; isolate restart recovery remaining |
| 4 | Extend XNNPACK candidate validation safely and retain a working CPU fallback | 🔴 Critical |
| 5 | ~~Implement thesis gesture controls~~ | ✅ Complete (v0.2.0) |
| 6 | Isolate restart recovery | 🔴 High |
| 7 | Orientation re-validation (back landscape + front camera) | 🟡 High |
| 8 | Formal FPS/latency benchmark + accuracy evaluation | 🟡 High |

## Recent Accomplishments

- ✅ **Assistive application UI (v0.2.0):** Home / Detect / Settings / Help navigation + Logs & Reports; TTS audio guidance (cooldown, de-duplication, urgent bypass, repeat, mute); the four thesis gestures with haptic + TTS confirmation; persisted settings (vibration, auto-start, low-power, audio); spatial/priority/proximity interpretation; runtime telemetry + charts
- ✅ **v0.2.1:** fixed startup theme-construction assertion (explicit high-contrast `TextTheme`)
- ✅ **v0.2.2:** fixed camera viewport resizing with detections + chart overflow; 59-test release baseline
- 🟡 **Unreleased model/backend candidate:** bundled internally quantized FLOAT32-I/O NCHW model; layout-aware preprocessing/rotation; explicit XNNPACK attempt with recoverable CPU fallback; 73 tests and static validation passing; exact APK now installed and initially exercised on the Snapdragon 695 target, but formal benchmarking and long-duration/accuracy validation remain open
- ✅ Persistent inference isolate with runtime model introspection (`ModelMetadata`)
- ✅ Automatic model-type detection (FP32 / Full INT8 / Full UINT8 / Weight-Quantized / Unknown) — never guessed
- ✅ Pure-Dart flatbuffer scanner for internal tensor precision ([`tflite_flatbuffer.dart`](../lib/models/tflite_flatbuffer.dart))
- ✅ Dynamic inference-path selection: input quantization + output dequantization driven by runtime metadata only
- ✅ Fixed the inference-isolate crash (`Float32List.reshape`) — raw `ByteBuffer` I/O, no reshape
- ✅ Busy gate now releases on isolate errors (pipeline no longer wedges permanently)
- ✅ Debug overlay renders live runtime model info (name, type, I/O types, shapes, classes, anchors, quantization)
- ✅ Startup diagnostic report (`MODEL INFORMATION` banner) in the isolate + `[Model]` summary on the main isolate
- ✅ Manual YUV420→RGB conversion (no external image library)
- ✅ Frame-dropping busy gate (no queue buildup)
- ✅ Stream-based detection results to UI
- ✅ COCO label loading from assets
- ✅ Camera initialization with YUV420 format at low resolution
- ✅ Project documentation system established (`docs/` directory)
- ✅ Bounding box overlay with `CustomPainter`, coordinate transformation, and front-camera mirroring
- ✅ Debug instrumentation: structured `debugPrint` logging (`[Service]`/`[Model]`/`[Camera]`/`[Inference]`/`[Detection]`/`[Painter]`/`[Performance]`/`[Error]`) + visual debug overlay (debug builds only)
- ✅ Performance logging: 5-second summaries with camera FPS, inference FPS, and avg/min/max latency
- ✅ Partial isolate error handling: try/catch + error propagation to main isolate
- ✅ Forensic file-based diagnostics (`ForensicLog`): structured logs + first-frame PNG dumps + auto-diagnosis written under `<documents>/debug/run_*` (replaces console probes)
- ✅ Camera preprocessing repair: geometry-aware YUV420→RGB (rowStride/pixelStride honored; planar I420 + semi-planar NV12/NV21)
- ✅ Aspect-correct preview: `FittedBox` + painter share `applyBoxFit` math; no stretching/warping
- ✅ Camera preview UI redesign: strict 3:4 portrait preview + permanent Metrics/Detections info panel
- ✅ Class-wise NMS (IoU 0.45) + pre-NMS confidence threshold lowered to 0.25 (standard YOLOv8)
- ✅ **Device-independent orientation** (`BoxTransform`): input tensor rotated/mirrored to upright per runtime metadata; portrait detections 0 → 0.91 on-device; static-image regression byte-identical
