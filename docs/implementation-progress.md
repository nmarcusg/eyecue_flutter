# EyeCue — Implementation Progress

> **Last Updated:** 2026-09-01 (dual-engine device smoke test)
> See also: [`implementation-plan.md`](implementation-plan.md) (roadmap), [`project-status.md`](project-status.md) (summary).

## Current Unreleased Candidate (2026-09-01)

This section describes unreleased work after the v0.2.2 release; the versioned
sections below remain historical release records.

- ✅ Added [`yolov8n_int8_new.tflite`](../assets/yolov8n_int8_new.tflite) to the asset bundle. Direct inspection found FLOAT32 runtime input/output, input `[1,3,640,640]` (NCHW), output `[1,84,8400]`, and internal INT8 tensors; runtime classification is *Weight-Quantized*, not full integer I/O.
- ✅ Updated [`inference_isolate.dart`](../lib/services/inference_isolate.dart) to select NHWC or NCHW from runtime shape metadata, write the matching YUV→RGB layout, and use [`tensor_rotation.dart`](../lib/models/tensor_rotation.dart) for layout-aware rotation/mirroring.
- 🟡 Added an explicit XNNPACK attempt with delegate lifetime retention, recoverable setup/invocation CPU fallback, and backend logging. The exact debug APK now installs on the Snapdragon 695 target and has initial short-run evidence: 65 completed live frames were labelled `XNNPACK`; the calculated latency mean was 164.8 ms (median 157.7 ms, range 150.2–377.3 ms), and app summaries reported approximately 5.7–6.2 inference FPS. The historical native SIGSEGV remains unresolved because a native fault cannot be caught by Dart.
- ✅ Added 14 tensor-rotation unit tests plus engine-setting, per-engine telemetry, and Ultralytics-adapter coverage; the full suite is now **77 passing** and `flutter analyze` reports **0 issues**.
- ✅ Extended the flatbuffer validator to cover the new model and verified the generated debug APK contains it.
- ⚠️ The exact candidate APK installed after storage was cleared. Startup logs confirmed the NCHW/FLOAT32 model metadata and successful explicit XNNPACK interpreter creation. The controlled short run produced no detections across its 65 logged frames, while a separate earlier observation returned one `tv` at 67.9% confidence and 113.7 ms. These are observational results only; formal benchmark, accuracy, thermal, memory, and long-duration stability evidence remains pending.
- ✅ Added persisted **Custom EyeCue** and **Ultralytics** modes using one model/labels/threshold configuration, with native results adapted into EyeCue's existing spatial, priority, TTS, gesture, and telemetry layers. Logs & Reports separates the two engines.
- ✅ Resolved the Android classic LiteRT/LiteRT Next native-runtime packaging conflict. The debug APK builds with both runtime families and installed on the arm64 Snapdragon 695 target.
- 🟡 Both engines processed live camera frames on that device. Post-fix switching passed in both directions after correcting a late Custom-isolate result that could write to a closed stream during Custom→Ultralytics disposal. Controlled paired benchmarking, wide-device coverage, actual delegate confirmation, and the Ultralytics licence decision remain open.

## v0.2.2 — UI Layout Fixes (2026-08-16)

- ✅ **Stable camera viewport** — Detection screen now reserves a fixed content region (`LayoutBuilder`-derived `SizedBox`, 32% of height, clamped 200–320) for the warning banner + scrollable detection list + controls, so the camera no longer resizes when detections appear ([`detection_screen.dart`](../lib/screens/detection_screen.dart)).
- ✅ **Contained charts** — [`charts.dart`](../lib/widgets/charts.dart) derives Y bounds from the actual data with headroom, draws benchmark lines only when they fit, and sets an explicit dynamic `maxY` for the bar chart; empty data shows a placeholder.
- ✅ `flutter analyze`: 0 issues. `flutter test`: **59 passing** for the v0.2.2 release baseline. On-device (API 33): 0 exceptions / RenderFlex overflows.

## v0.2.1 — Fix Startup Theme Assertion (2026-08-16)

- ✅ Replaced `textTheme.apply(fontSizeFactor: 1.12, ...)` (asserted on M3's color-only `TextTheme`) with an explicit high-contrast `_highContrastTextTheme()` ([`main.dart`](../lib/main.dart)). `flutter analyze`: 0 issues. `flutter test`: **53 passing** (regression test in `test/theme_test.dart`).

## v0.2.0 — Assistive Application UI (2026-08-16)

### Application Navigation (100%)

- ✅ 4-tab bottom navigation shell: Home, Detect, Settings, Help ([`app_shell.dart`](../lib/navigation/app_shell.dart))
- ✅ Lazy page building + state preservation via `IndexedStack` (camera state survives tab switches)
- ✅ System-back returns to Home; Logs & Reports pushed as a route from Settings
- ✅ Home "Go to Live Camera" CTA switches to the Detect tab

### Screens (100% of new screens)

- ✅ **Home** ([`home_screen.dart`](../lib/screens/home_screen.dart)): branding, subtitle, Auto-Start-aware status card, "Go to Live Camera" CTA
- ✅ **Detection** ([`detection_screen.dart`](../lib/screens/detection_screen.dart)): validated camera/inference pipeline preserved; assistive UI (status pill, audio mute, object cards, warning banner, visible controls, gesture surface)
- ✅ **Settings** ([`settings_screen.dart`](../lib/screens/settings_screen.dart)): Vibration, Auto-Start, Low Power, Audio, Logs & Reports
- ✅ **Help** ([`help_screen.dart`](../lib/screens/help_screen.dart)): how it works, gestures, confirmation, Android tips
- ✅ **Logs & Reports** ([`logs_reports_screen.dart`](../lib/screens/logs_reports_screen.dart)): Overview / Charts / Logs tabs

### Audio Guidance (100% of the UI-phase TTS)

- ✅ [`tts_service.dart`](../lib/services/tts_service.dart): `flutter_tts` wired via injectable `TtsEngine`; mute state, cooldown, same-label de-duplication, urgent (high-priority) bypass, repeat-last
- ✅ Detection announcements, start/stop/pause/resume/scan announcements, quick-scan summary
- ✅ Phrasing includes relative position + approximate proximity

### Accessibility / Gestures (100% of the thesis gesture set)

- ✅ [`gesture_controller.dart`](../lib/services/gesture_controller.dart): two-finger double tap (start/stop), single tap (pause/resume), three-finger tap (scan), swipe down (repeat)
- ✅ [`gesture_surface.dart`](../lib/widgets/gesture_surface.dart): transparent capture layer over the viewport
- ✅ Haptic + TTS confirmation per gesture; visible high-contrast fallback controls (`AccessibleButton`)

### Settings Persistence (100%)

- ✅ [`settings_service.dart`](../lib/services/settings_service.dart): file-backed JSON via `path_provider`, injectable `SettingsStore` for tests, defaults on corrupt/missing file

### Spatial / Priority Interpretation (100% of the interface layer)

- ✅ [`spatial_analysis_service.dart`](../lib/services/spatial_analysis_service.dart) + [`detection_info.dart`](../lib/models/detection_info.dart): left/center/right (geometry), priority tiers (class-based), approximate proximity band (labeled heuristic — not a measured distance)
- ✅ Kept fully separate from the inference pipeline

### Telemetry & Reports (100% of the new dashboard)

- ✅ [`telemetry_service.dart`](../lib/services/telemetry_service.dart): session records, detection logs, latency/FPS samples, aggregates, per-minute frequency buckets
- ✅ [`charts.dart`](../lib/widgets/charts.dart): latency (300 ms line), FPS (15 FPS line), detection frequency
- ✅ Accuracy/Precision/Recall/F1/mAP explicitly **unavailable** (require ground truth) — never fabricated

### Haptics (100%)

- ✅ [`haptics_service.dart`](../lib/services/haptics_service.dart): dependency-free `HapticFeedback`, respects Vibration setting

### Tests (100% of the new tests)

- ✅ Navigation shell, screens, widgets, TTS, settings, spatial, telemetry, gesture controller — release baseline `flutter test` 59 passing, `flutter analyze` 0 issues (52 at v0.2.0 → 53 at v0.2.1 → 59 at v0.2.2)

### Notes

- The former developer single-screen UI (`camera_screen.dart`) was retired in v0.2.0 and **removed** during the Android-only platform cleanup; the current primary screen is [`detection_screen.dart`](../lib/screens/detection_screen.dart), while `info_panel.dart` / `debug_overlay.dart` remain but are unused by that UI.
- The ML pipeline (camera, YUV, orientation, TFLite, parser, NMS, thresholds, painter, forensics) was **not** modified.

## Completed Work

### Camera Pipeline (100%)

- ✅ Camera initialization with `ResolutionPreset.low` and YUV420 format
- ✅ Camera permission requesting via `permission_handler`
- ✅ `startImageStream()` delivering frames at native FPS
- ✅ Frame-dropping busy gate (`_isInferring` boolean)
- ✅ Camera preview widget rendering
- ✅ Resource cleanup (`dispose()` on camera and isolate)
- ✅ Structured debug logging: `[Camera]` prefix, frame counters, FPS estimation

### Inference Isolate (100%)

- ✅ Persistent `Isolate.spawn()` at app startup (not per-frame)
- ✅ Single `Interpreter.fromBuffer()` call (model loads once)
- ✅ **Runtime model introspection** — builds a `ModelMetadata` snapshot from runtime tensors + internal tensor scan
- ✅ Dynamic tensor shape querying (not hardcoded)
- ✅ Pre-allocated, dtype-matched input/output buffers; the orientation helper makes a temporary clone only when rotation or mirroring is required
- ✅ Raw `ByteBuffer` I/O to `interpreter.run()` — no reshape, no input-tensor resizing
- ✅ SendPort/ReceivePort communication protocol
- ✅ NHWC/NCHW automatic detection from shape
- ✅ Runtime layout-aware preprocessing and tensor rotation for both NHWC (interleaved) and NCHW (planar) inputs
- 🟡 Explicit XNNPACK attempt with retained delegate ownership and recoverable CPU fallback; initial short target-device evidence exists, while longer native stability remains unverified
- ✅ Structured debug logging: `[Model]`, `[Inference]`, `[Detection]`, `[Error]` prefixes
- ✅ Startup `MODEL INFORMATION` diagnostic banner in the isolate
- ✅ Inference latency timing via `Stopwatch` (reported per-frame)
- ✅ Error handling: try/catch around interpreter creation and frame loop
- ✅ Error propagation: isolate errors sent to main isolate via `{'type': 'error'}`
- ✅ Busy gate releases on isolate error (no permanent frame-drop wedge)

### Preprocessing (100%)

- ✅ Manual YUV420→RGB conversion (no `image` package dependency), writing either NHWC or NCHW layout from runtime metadata
- ✅ Nearest-neighbor resize to model input dimensions
- ✅ Dtype-matched writes driven by runtime metadata (normalized float, or quantized via input scale/zeroPoint)
- ✅ Support for FLOAT32/FLOAT64/FLOAT16/INT8/UINT8/INT16 model input types

### Post-Processing (100%)

- ✅ Argmax per-box (anchors × classes from runtime metadata)
- ✅ Dequantization driven by runtime metadata (only when the output tensor is quantized)
- ✅ Confidence threshold filtering (**0.25** — standard YOLOv8; lowered from 0.5, 2026-08-01)
- ✅ **Class-wise Non-Maximum Suppression (NMS)** — IoU 0.45; suppresses overlapping anchors per class (2026-08-01)
- ✅ Detection list construction (classId, confidence, bounding box)
- ✅ Pre-NMS candidate count exposed for `before NMS → after NMS` logging
- ✅ Per-detection debug logging (label, confidence, normalised box coords)

### Model Introspection (100%) — NEW

- ✅ [`ModelMetadata`](../lib/models/model_metadata.dart) — immutable runtime snapshot (name, I/O types, shapes, scale/zeroPoint, quantized flags, classes, anchors, model type)
- ✅ [`ModelType`](../lib/models/model_metadata.dart) classification: FP32 / Full INT8 Quantized / Full UINT8 Quantized / Weight-Quantized / Unknown — never guessed from filenames
- ✅ [`tflite_flatbuffer.dart`](../lib/models/tflite_flatbuffer.dart) — pure-Dart flatbuffer scanner for internal tensor precision (validated against the reference `tflite` Python package)
- ✅ Float16 (half-precision) byte conversion helpers for FLOAT16 I/O edge cases
- ✅ Metadata shipped to the main isolate via the `model_loaded` message
- ✅ Startup diagnostic logging (`MODEL INFORMATION` banner + `[Model]` summary)
- ✅ Debug overlay renders live model info (name, type, I/O types, shapes, classes, anchors, quantization, scale/zeroPoint)
- ✅ CLI validation tool: `dart run tool/validate_flatbuffer.dart`
- ✅ Fixed the `Float32List.reshape` `NoSuchMethodError` crash (raw `ByteBuffer` I/O)

### Model & Labels (100%)

- ✅ Model loading from the current candidate asset (`yolov8n_int8_new.tflite`); the v0.2.2 release baseline used `yolov8n.tflite`
- ✅ COCO label loading from `labels.txt` (80 classes)
- ✅ Label lookup by class index
- ✅ Model load success/failure logging with tensor metadata

### Orientation Architecture (100%) — NEW (2026-08-01)

- ✅ [`BoxTransform`](../lib/models/box_transform.dart) — single, device-independent source of truth for orientation math (`deviceDegreesFor` using the plugin's counter-clockwise convention, `displayRotationDegrees`, `uprightDims`, reversible `rotateRect`/`invertRect`, `mirrorRect`); no hardcoded angles
- ✅ Upright tensor inference — isolate rotates + optionally X-mirrors the 640×640 input to UPRIGHT before `interpreter.run()`; [`tensor_rotation.dart`](../lib/models/tensor_rotation.dart) handles both NHWC and NCHW while parser/NMS remain untouched
- ✅ Camera screen computes rotation from the same `controller.value.deviceOrientation` as `CameraPreview`; preview/painter sized with upright dims
- ✅ Painter simplified to a pure normalized→pixel mapper (no lens/mirror knowledge)
- ✅ Forensic `recordOrientation` + sensor/lens fields
- ✅ On-device: back portrait detections 0 → 0.91 maxConf; static-image regression byte-identical
- ⏳ Back landscape physical-hold re-validation + front-camera device runs pending

### Forensic File Logging (100%) — NEW (2026-08-01)

- ✅ [`ForensicLog`](../lib/services/forensic_log.dart) — structured file diagnostics under `<documents>/debug/run_*` (summary/camera/preprocess/tensor/output/parser/performance/errors.txt), synchronous flush-per-write, fully try/catch-isolated
- ✅ First-frame PNG dumps (`frame_original/rgb/resized/model_input.png`) via pure-Dart [`PngEncoder`](../lib/models/png_encoder.dart)
- ✅ Auto-generated `summary.txt` every 50 frames + on close (per-stage PASS/FAIL, ranked root causes)
- ✅ Console probes (`InferenceProbe`/`InputProbe`) disabled (`enabled=false`), call sites removed

### Camera Preview & UI (100%) — NEW (2026-08-01)

- ✅ Strict 3:4 portrait preview anchored to the top, feed contained via `BoxFit.contain` (never stretched/warped/cropped)
- ✅ Permanent bottom info panel ([`info_panel.dart`](../lib/widgets/info_panel.dart)) with exactly two tabs: Metrics + Detections
- ✅ Metrics tab: FPS, avg FPS, inference time, end-to-end latency, confidence stats, camera/preview/model input resolutions, aspect ratio, model name, backend, quantization, thread count
- ✅ Detections tab: chronological history (newest first), capped at 50, 1-second age timer
- ✅ Painter-vs-preview alignment via shared `applyBoxFit(BoxFit.contain)` math
- ✅ Aspect-correct preview via `FittedBox(fit: _previewFit)` + `SizedBox` sized to frame (contain/cover switch)

### Camera Preprocessing Repair (100%) — NEW (2026-08-01)

- ✅ `_convertYUV420toRGB` honors real per-plane `rowStride`/`bytesPerRow` + `pixelStride`/`bytesPerPixel`
- ✅ Planar I420 (pixelStride 1) and semi-planar NV12/NV21 (pixelStride 2, U-led) support
- ✅ Geometry-aware forensic `frame_rgb.png` sampling; 2-plane (semi-planar) deliveries handled
- ✅ Validated pixel-exact vs BT.601 reference on synthetic planar + semi-planar data

### Bounding Box Overlay (100%)

- ✅ `BoundingBoxPainter` CustomPainter with coordinate transformation
- ✅ Front-camera horizontal mirroring
- ✅ Label pills with confidence percentages
- ✅ Shadow rendering for visibility on bright backgrounds
- ✅ Colour palette cycling per class
- ✅ Structured debug logging: `[Painter]` prefix, screen dims, scale factor, rendered coords

### Debug Instrumentation (100%) — NEW

- ✅ Structured debug logging with consistent prefixes throughout the pipeline:
  - `[Service]` — InferenceService lifecycle (init, handshake, dispose)
  - `[Model]` — Model loading, tensor shapes/types, interpreter creation
  - `[Camera]` — Permission, initialization, resolution, format, frames received/dropped
  - `[Inference]` — Per-frame latency, input/output tensor shapes
  - `[Detection]` — Per-frame detection count, per-object label/confidence/box
  - `[Painter]` — Box count, screen dimensions, scale factor, rendered coordinates
  - `[Performance]` — 5-second summaries: camera FPS, inference FPS, avg/min/max latency, frame stats
  - `[Error]` — Model load failures, interpreter exceptions, isolate errors with stack traces
- ✅ Visual debug overlay ([`DebugOverlay`](../lib/widgets/debug_overlay.dart) widget, debug builds only via `kDebugMode`)
  - Camera FPS, inference FPS, latency, frame number, dropped frames
  - Detection count, last detected object, confidence
  - Camera resolution, lens direction, image format
- ✅ All `print()` calls replaced with `debugPrint()` (throttled in release)
- ✅ Log throttling: camera frames every 30th, painter every 30th, detections every frame
- ✅ Message protocol extended: `{'type': 'result'/'error'/'model_loaded'}` with metadata
- ✅ Inference latency exposed via `InferenceService.lastLatencyMs` getter

### Documentation (current set synchronized through 2026-09-01)

- ✅ Comprehensive project audit ([`auditor.md`](../auditor.md))
- ✅ Historical specification preserved ([`chat_spec.md`](../chat_spec.md))
- ✅ Architecture documentation ([`docs/architecture.md`](architecture.md))
- ✅ Implementation plan ([`docs/implementation-plan.md`](implementation-plan.md))
- ✅ Implementation decisions log ([`docs/implementation-decisions.md`](implementation-decisions.md))
- ✅ Project status ([`docs/project-status.md`](project-status.md))
- ✅ Known issues tracker ([`docs/known-issues.md`](known-issues.md))
- ✅ Development workflow guide ([`docs/development-workflow.md`](development-workflow.md))
- ✅ Testing plan ([`docs/testing-plan.md`](testing-plan.md))
- ✅ Benchmark results template ([`docs/benchmark-results.md`](benchmark-results.md))
- ✅ Formal README ([`README.md`](../README.md)) — project overview + documentation index
- ✅ Session log ([`docs/session-log.md`](session-log.md)) — all sessions through the orientation architecture recorded
- ✅ Changelog ([`docs/changelog.md`](changelog.md)) — v0.1.0 through v0.1.7 entries
- ✅ Camera-path forensics ([`docs/camera-path-forensics.md`](camera-path-forensics.md)) — input-side defect isolated & fixed (rotation)
- ✅ Orientation design review ([`docs/orientation-design-review.md`](orientation-design-review.md)) + implementation summary ([`docs/orientation-implementation.md`](orientation-implementation.md))
- ✅ Painter↔preview coordinate review ([`docs/painter-coordinate-review.md`](painter-coordinate-review.md))
- ✅ Static-image test report ([`docs/static-image-test.md`](static-image-test.md))
- ✅ Input pipeline investigation ([`docs/input-pipeline-investigation.md`](input-pipeline-investigation.md))
- ✅ Inference tensor diagnosis ([`docs/inference-tensor-diagnosis.md`](inference-tensor-diagnosis.md))

## Current Work

**Unreleased NCHW/XNNPACK candidate validation** — Active

| Task | Status |
|------|--------|
| Exact debug APK installation after storage cleanup | ✅ Successful on `2201116SG` (Android 13/API 33, arm64) |
| Runtime startup metadata and explicit delegate setup | ✅ Candidate metadata confirmed; XNNPACK interpreter created with four threads |
| Short live inference run | ✅ 65 completed frames, all logged `backend=XNNPACK`; no fatal marker observed |
| Formal performance, accuracy, thermal, memory, and long-duration stability validation | ⏳ Pending |

**Orientation re-validation** — Active

| Task | Status |
|------|--------|
| Back · portrait on-device | ✅ Done (maxConf 0.91, was 0) |
| Static-image regression (rot=0) | ✅ Done (byte-identical) |
| Back · landscape physical hold | 🟡 Convention bug fixed; physical-hold re-validation deferred |
| Front · portrait / landscape | 🟡 Math implemented; device run pending |

**Milestone 1: "Audible MVP"** — Complete (v0.2.0)

| Task | Status |
|------|--------|
| TTS audio feedback | ✅ Complete (v0.2.0) |
| Bounding box `CustomPainter` | ✅ Complete (2026-07-22) |
| Error handling in isolate | 🟡 Partial — try/catch added around interpreter creation + frame loop; error propagation to main isolate; restart recovery still open |
| Permission-denied UI | ✅ Complete (v0.2.0 — camera-denied state with retry/open-settings) |
| Remove/wire unused dependencies | ✅ Mostly complete — `flutter_tts`/`path_provider`/`fl_chart` wired; `flutter_riverpod` retained (deliberately unused) |
| Debug instrumentation & logging | ✅ Complete (2026-07-22) |
| Forensic file logging | ✅ Complete (2026-08-01, v0.1.3) |
| Camera preprocessing repair | ✅ Complete (2026-08-01, v0.1.4) |
| Aspect-correct preview | ✅ Complete (2026-08-01, v0.1.5) |
| Camera preview UI redesign | ✅ Complete (2026-08-01, v0.1.6) |
| Device-independent orientation | ✅ Complete (2026-08-01, v0.1.7) |
| NMS (class-wise, IoU 0.45) + conf threshold 0.25 | ✅ Complete (2026-08-01) |

## Next Tasks (Priority Order)

0. **Re-validate orientation on-device** — back landscape physical hold + front camera portrait/landscape (see [`docs/orientation-implementation.md`](orientation-implementation.md)).
1. ~~**Implement TTS audio feedback**~~ — ✅ Done (v0.2.0). See [`lib/services/tts_service.dart`](../lib/services/tts_service.dart).
2. ~~**Implement bounding box `CustomPainter`**~~ — ✅ Done. See [`lib/widgets/bounding_box_painter.dart`](../lib/widgets/bounding_box_painter.dart).
3. ~~**Add debug instrumentation**~~ — ✅ Done. See [`lib/widgets/debug_overlay.dart`](../lib/widgets/debug_overlay.dart), [`lib/services/inference_isolate.dart`](../lib/services/inference_isolate.dart), [`lib/screens/detection_screen.dart`](../lib/screens/detection_screen.dart), [`lib/widgets/bounding_box_painter.dart`](../lib/widgets/bounding_box_painter.dart).
4. ~~**Implement NMS**~~ — ✅ Done (2026-08-01). Class-wise, IoU 0.45, pre-NMS conf 0.25. See [`_parseYolov8Output`](../lib/services/inference_isolate.dart).
5. **On-device validation of the v0.2.x UI** — gestures, TTS, mute toggle, settings persistence, Logs & Reports charts on the Snapdragon 695 device.
6. **Complete error handling in inference isolate** — extend error recovery (isolate restart on crash).
7. ~~**Add permission-denied UI**~~ — ✅ Done (v0.2.0). See [`detection_screen.dart`](../lib/screens/detection_screen.dart).
8. **Extend validation of the unreleased XNNPACK candidate** — capture longer stability/fallback evidence and run the benchmark tool on the test device; the exact APK has already installed and completed an initial short live run.

## Remaining Tasks

See [`implementation-plan.md`](implementation-plan.md) for the full milestone breakdown.

### By Milestone:

- **Milestone 1 (Audible MVP):** ✅ Complete (v0.2.0); isolate restart recovery carried to M4
- **Milestone 2 (Research-Ready):** mostly done — on-device UI validation, formal FPS/latency benchmark, adaptive throttling polish remaining
- **Milestone 3 (Defense-Ready):** gestures + priority TTS queue done; TalkBack semantics, adaptive throttling, extended XNNPACK/NNAPI delegate validation, package rename (`com.eyecue`), explicit minSdk remaining
- **Milestone 4 (Production Candidate):** isolate restart recovery, model variant selection, `TransferableTypedData`, bilinear resize, full coverage, Play Store readiness

**Total Estimated Effort (remaining):** ~40–70 hours (down from ~60–104)

## Estimated Completion

| Milestone | Target |
|-----------|--------|
| M1: Audible MVP | ~2 weeks |
| M2: Research-Ready | ~4 weeks |
| M3: Defense-Ready | ~6 weeks |
| M4: Production Candidate | ~8 weeks |

## Verification Log (2026-07-22)

> **Historical note:** This log records the static/code-review verification state from
> 2026-07-22. It predates the later v0.2.x UI work and the 2026-09-01 candidate
> device retry. The current candidate status is recorded in the sections above;
> the checklist below is retained as a dated audit trail.

### Debug Instrumentation Verification

The following checklist was verified via code review and static analysis (`flutter analyze` — 0 issues):

| Check | Status | Evidence |
|-------|--------|----------|
| Camera initializes | ✅ | `[Camera]` logs at init, permission, stream start |
| Frames received | ✅ | `[Camera]` per-30-frame log with resolution/format |
| Model loads | ✅ | `[Model]` logs with tensor shapes, `type:'model_loaded'` confirm |
| Interpreter runs | ✅ | `[Inference]` per-frame latency (Stopwatch measured) |
| Inference completes | ✅ | `type:'result'` message with detections + latencyMs |
| Detections produced | ✅ | `[Detection]` per-frame count + per-object details |
| Bounding boxes rendered | ✅ | `[Painter]` per-30-paint box count, screen dims, scale |
| Labels displayed | ✅ | Painter draws label pills with confidence % (existing) |
| Confidence displayed | ✅ | Painter shows `label XX%` format (existing) |
| Overlay aligned | ✅ | Coordinate transform logged: norm→screen with scale factor |
| No crashes | ⚠️ Static | Requires on-device testing; try/catch added around critical paths |
| No memory leaks observed | ⚠️ Static | Requires on-device profiling; pre-allocated buffers unchanged |
| Debug overlay visible | ✅ | `DebugOverlay` widget, `kDebugMode` guard, positioned top-left |
| Performance logging | ✅ | `[Performance]` 5-second summaries with FPS/latency/frame stats |
| Error logging active | ✅ | `[Error]` try/catch in model load, interpreter creation, frame loop |
| Message protocol intact | ✅ | Backward-compatible: `type:'result'/'error'/'model_loaded'` |

### Issues Discovered During Instrumentation

1. **No `imageFormatGroup` on `CameraValue`** — The `camera` package's `CameraValue` class does not expose the configured image format group. Workaround: store the statically-configured format string (`'yuv420'`) during controller creation.

2. **Interpreter type narrowed to nullable** — Adding try/catch around `Interpreter.fromBuffer()` forced the interpreter variable to `Interpreter?`. Fixed with `!` null-assert on `interpreter.run()` since the function returns early on failure.

3. **Static method accessing local variables** — `_logDetections()` originally referenced `modelH`/`modelW` which are local to `_isolateEntryPoint()`. Fixed by passing them as parameters.

### Recommended Next Verification Steps

1. Deploy to physical Android device (Snapdragon 695) and observe logcat output
2. Verify `[Performance]` summaries appear every 5 seconds
3. Confirm debug overlay renders in top-left corner of camera preview
4. Check that inference latency is consistent with known CPU-only baseline (~30 ms)
5. Verify error propagation by temporarily introducing a fault
6. Run Android Studio Memory Profiler to check for leaks over a 5-minute session
