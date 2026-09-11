# EyeCue — Project Status

> **Last Updated:** 2026-09-09 (Home screen visual redesign)
> See also: [`implementation-progress.md`](implementation-progress.md) (detailed progress), [`app-only-implementation-plan.md`](app-only-implementation-plan.md) (the original 15 repository-owned app task areas and their acceptance criteria), [`known-issues.md`](known-issues.md) (blockers), [`thesis-product-status-audit.md`](thesis-product-status-audit.md) (thesis-aligned completion baseline).

> **Latest release:** v0.2.2. Since the v0.2.0 UI landed, v0.2.1 fixed the startup theme-construction assertion and v0.2.2 fixed the camera viewport resizing with detections plus chart overflow in Logs & Reports. The repository contains committed but unreleased model/layout/backend changes; see the section below and [`changelog.md`](changelog.md).

## Overall Progress

**ML/inference pipeline:** stable v0.2.2 baseline is ~80% complete and on-device validated; the current dual-engine candidate is statically/build validated and both modes have initial one-device smoke evidence, but neither is formally compared or release-validated.
**Thesis product (app as a whole):** ~70% (range 65–75%) — see the [thesis-product-status-audit](thesis-product-status-audit.md) for the weighted breakdown (re-scored after the v0.2.x assistive-UI phase; the earlier ~30% measured the pre-assistive-UI state, and the historical "~60%" measured only the ML/debug pipeline).

## What Changed (v0.2.x — Assistive Application UI)

The app is no longer a single developer camera screen. It now has the thesis-aligned application structure (built in v0.2.0; layout/theme fixes in v0.2.1–v0.2.2):

- **Navigation:** 4-tab bottom bar — Home, Detect, Settings, Help ([`app_shell.dart`](../lib/navigation/app_shell.dart)); Logs & Reports pushed from Settings.
- **Home:** branding, status card (Auto-Start aware), "Go to Live Camera".
- **Detection:** the validated camera/inference pipeline preserved, now with an assistive UI — status pill, audio mute, object cards with priority badges, high-priority warning banner, visible controls, and thesis gestures (two-finger double-tap start/stop, single tap pause/resume, three-finger scan, swipe-down repeat) with haptic + TTS confirmation. The unreleased candidate adds a persisted Custom EyeCue / Ultralytics engine selector; both feed EyeCue's spatial, priority, TTS, and telemetry layers.
- **TTS audio feedback:** implemented ([`tts_service.dart`](../lib/services/tts_service.dart)) — cooldown, de-duplication, urgent bypass, repeat-last, mute state. `flutter_tts` is now wired (previously declared-only).
- **Settings:** persisted preferences — Vibration, Auto-Start, Low Power Mode (dispatch throttle), Audio guidance, inference engine, Logs & Reports ([`settings_service.dart`](../lib/services/settings_service.dart)).
- **Help:** how it works, gestures, confirmation feedback, Android usage tips.
- **Logs & Reports:** Overview / Charts / Logs with `fl_chart`; accuracy/precision/recall/mAP explicitly shown as unavailable (require ground truth).
- **Spatial/priority layer:** left/center/right + priority tiers + approximate proximity band ([`spatial_analysis_service.dart`](../lib/services/spatial_analysis_service.dart)) — kept separate from the inference pipeline.
- Stable v0.2.2 validation remains the historical **59-test** on-device baseline. The current repository has **127 passing tests** and `flutter analyze`: **0 issues**. The app-only lifecycle, accessibility, metadata-safety, and export additions are covered by deterministic tests.

## Current Unreleased Candidate (2026-09-05)

The following changes are present in the repository but are not a new release yet:

- **Two selectable inference modes:** Settings now persists either **Custom EyeCue** (the existing Dart/isolate camera, conversion, resize, orientation, parser, and class-wise NMS path) or **Ultralytics** (`ultralytics_yolo` 0.6.13, native camera/inference/post-processing path). [`engine_detection_screen.dart`](../lib/screens/engine_detection_screen.dart) switches implementations while keeping the surrounding application unchanged.
- **Controlled inputs:** both modes load the same metadata-enriched runtime artifact [`yolov8n_int8_new_metadata.tflite`](../assets/yolov8n_int8_new_metadata.tflite), generated from the byte-identical base graph [`yolov8n_int8_new.tflite`](../assets/yolov8n_int8_new.tflite), plus the authoritative COCO label file. The active confidence threshold defaults to `0.25`, is persisted through settings, and is applied by both engines; IoU remains fixed at `0.45`. [`model_config.dart`](../lib/models/model_config.dart) is the shared source of the artifact paths and bounds.
- **Comparable app outputs:** [`ultralytics_detection_adapter.dart`](../lib/services/ultralytics_detection_adapter.dart) maps native results into EyeCue's existing `Detection` model. Spatial descriptions, priorities, warnings, TTS, gestures, and telemetry therefore remain available in both modes. Logs & Reports now shows separate Custom and Ultralytics summaries instead of mixing their samples.
- **Model:** the runtime artifact [`yolov8n_int8_new_metadata.tflite`](../assets/yolov8n_int8_new_metadata.tflite) preserves the base graph [`yolov8n_int8_new.tflite`](../assets/yolov8n_int8_new.tflite): input `[1,3,640,640]` (NCHW), output `[1,84,8400]`, and FLOAT32 runtime I/O with internally quantized tensors. [`ModelMetadata`](../lib/models/model_metadata.dart) classifies it as *Weight-Quantized* from inspection rather than from the filename.
- **Preprocessing:** the inference path now chooses NHWC or NCHW from runtime input shape. [`tensor_rotation.dart`](../lib/models/tensor_rotation.dart) provides pure, unit-tested rotation/mirror logic for both layouts.
- **Backend:** the isolate attempts explicit XNNPACK, retains the delegate for the interpreter lifetime, and retries on CPU for recoverable Dart-level setup/invocation failures. A native SIGSEGV cannot be caught by Dart, so the historical Snapdragon 695 XNNPACK crash is not considered resolved.
- **Static/build verification:** `flutter analyze` passes; `flutter test` passes with 127 tests; the flatbuffer and PNG validators pass; the metadata packaging check passes; and the debug APK builds with both native runtime families plus the shared model/labels. APK inspection confirmed both runtime families for the packaged ABIs. See [`dual-inference-engine-test.md`](dual-inference-engine-test.md).
- **Device validation:** the fixed dual-engine debug APK installed successfully on the API 33 Snapdragon 695 target (`2201116SG`, arm64). Both modes processed live camera frames and rendered EyeCue outputs. The first Custom→Ultralytics switch revealed a late-result/closed-stream race; lifecycle guards and frame-acceptance handling were added, and post-fix switching succeeded in both directions without recurrence in captured Flutter logs. Fresh settings now default to Ultralytics; an explicitly persisted Custom preference remains Custom, and temporary fallback does not rewrite that preference.
- **Short performance observations:** momentary Ultralytics screen readings were approximately 6.1–9.6 FPS and 86.1–148.1 ms inference (111.4–175.9 ms native total). The final thermally warm Custom reverse-switch run reported approximately 3.5–3.8 FPS and 261.0–289.4 ms average latency, while an earlier cooler Custom candidate run reported 5.7–6.2 FPS and a calculated 164.8 ms mean. These unmatched observations are diagnostic only. Ultralytics' GPU request was not confirmed as the delegate actually used.

This candidate must remain labelled **unreleased and initially device-observed**. The smoke tests are not a formal benchmark, accuracy evaluation, thermal/memory test, long-duration stability test, broad compatibility result, or proof of delegate selection. The controlled paired comparison is still required, and the native SIGSEGV risk remains unresolved.

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
| Persisted Custom/Ultralytics test selector + per-engine reports | ✅ Implemented (unreleased candidate) |
| Error handling in isolate | ✅ Implemented — typed errors, generation filtering, bounded worker recovery, and terminal failure state |
| Permission-denied UI | ✅ Implemented (v0.2.0 — camera-denied screen with retry/open-settings) |
| Isolate restart recovery | ✅ Implemented — injectable coordinator, immediate/delayed bounded retries, stale-event guards, healthy-budget reset, and disposal safety |
| Orientation re-validation (back landscape + front camera) | 🟡 In progress — stable NHWC baseline portrait/static verified; candidate NCHW has an initial short portrait run, while landscape/front-camera device runs remain pending |

## Current Blocker

**XNNPACK/device validation is incomplete.** The stable v0.2.2 path is CPU-only because XNNPACK previously crashed on Snapdragon 695 with the older bundled YOLOv8n model (FLOAT32 I/O, INT8 weights). The current unreleased candidate now installs and runs on the target: the explicit XNNPACK interpreter completed 65 logged live frames in a short observation, with approximately 5.7–6.2 inference FPS in 5-second summaries and no observed candidate-process fatal signal. Native crashes remain uncatchable, and the short run does not establish a performance improvement, long-term stability, full graph delegation, or accuracy result.

See [`known-issues.md`](known-issues.md) for full blocker details.

## Next Objective

1. **Extend candidate device validation** — repeat the target-device run for a controlled duration, collect fallback/crash evidence, and measure detections without treating the short observation as a release benchmark.
2. **Re-validate orientation on-device** — candidate NCHW portrait/landscape and front-camera runs, plus the deferred stable-baseline cases.
3. **Run the controlled dual-engine benchmark** — compare Custom EyeCue and Ultralytics on the same device, model, scene, settings, duration, and thermal starting state using [`dual-inference-engine-test.md`](dual-inference-engine-test.md); do not infer performance from static inspection or a short observational run.
4. **Complete the v0.2.x UI validation** — gestures, TTS, mute toggle, settings persistence, and Logs & Reports charts.
5. **Complete repository-owned release preparation** — confirm Android identity/signing decisions, then validate release artifacts; research evaluation remains intentionally outside this app-only implementation.

## High-Priority Tasks

| # | Task | Priority |
|---|------|----------|
| 1 | On-device validation of gestures + TTS + settings persistence | 🔴 Critical |
| 2 | ~~Implement TTS audio feedback~~ | ✅ Complete (v0.2.0) |
| 3 | ~~Add permission-denied and error UI states~~ | ✅ Complete — permission UI plus typed runtime/recovery states |
| 4 | Extend XNNPACK candidate validation safely and retain a working CPU fallback | 🔴 Critical |
| 5 | ~~Implement thesis gesture controls~~ | ✅ Complete (v0.2.0) |
| 6 | ~~Isolate restart recovery~~ | ✅ Complete — bounded, generation-safe Custom-worker lifecycle |
| 7 | Orientation re-validation (back landscape + front camera) | 🟡 High |
| 8 | Formal FPS/latency benchmark + accuracy evaluation | 🟡 High |
| 9 | Controlled Custom EyeCue vs Ultralytics device comparison | 🔴 Critical |

## Recent Accomplishments

- ✅ **Home screen visual redesign (2026-09-09):** light, responsive Home composition with a preference-truthful `READY` / `AUTO-START OFF` badge, a centered decorative logo + live `EyeCue` wordmark, a lower instruction region with the retained `Go to Live Camera` CTA and a static cyan rail; Home-local light theme ([`app_home_theme.dart`](../lib/theme/app_home_theme.dart)) with offline IBM Plex Sans; `kHome*` color and `kRadius3/14/18/24` tokens; dark status-bar icons on the light surface; **133 tests** and static validation passing; on-device (SM-S9010) confirmed visually
- ✅ **Assistive application UI (v0.2.0):** Home / Detect / Settings / Help navigation + Logs & Reports; TTS audio guidance (cooldown, de-duplication, urgent bypass, repeat, mute); the four thesis gestures with haptic + TTS confirmation; persisted settings (vibration, auto-start, low-power, audio); spatial/priority/proximity interpretation; runtime telemetry + charts
- ✅ **v0.2.1:** fixed startup theme-construction assertion (explicit high-contrast `TextTheme`)
- ✅ **v0.2.2:** fixed camera viewport resizing with detections + chart overflow; 59-test release baseline
- ✅ **Unreleased app-only candidate:** persisted Custom EyeCue / Ultralytics selector; one shared model/labels/threshold configuration; native-result adapter into the existing assistive stack; per-engine telemetry summaries; bounded, generation-safe Custom-worker recovery with deterministic lifecycle tests; typed runtime/error states; accessibility semantics and 200% text-scale coverage; image-free JSON/CSV export; metadata-packaging safety; bundled internally quantized FLOAT32-I/O NCHW model; layout-aware custom preprocessing/rotation; explicit XNNPACK attempt with recoverable CPU fallback; **127 tests** and static validation passing. Both modes and both switch directions have a one-device smoke pass, but controlled comparison, broad compatibility, long-duration, and accuracy validation remain open.
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
