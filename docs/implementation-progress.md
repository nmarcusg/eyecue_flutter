# EyeCue — Implementation Progress

> **Last Updated:** 2026-08-01
> See also: [`implementation-plan.md`](implementation-plan.md) (roadmap), [`project-status.md`](project-status.md) (summary).

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
- ✅ Pre-allocated, dtype-matched input/output buffers (no per-frame allocation)
- ✅ Raw `ByteBuffer` I/O to `interpreter.run()` — no reshape, no input-tensor resizing
- ✅ SendPort/ReceivePort communication protocol
- ✅ NHWC/NCHW automatic detection from shape
- ✅ Structured debug logging: `[Model]`, `[Inference]`, `[Detection]`, `[Error]` prefixes
- ✅ Startup `MODEL INFORMATION` diagnostic banner in the isolate
- ✅ Inference latency timing via `Stopwatch` (reported per-frame)
- ✅ Error handling: try/catch around interpreter creation and frame loop
- ✅ Error propagation: isolate errors sent to main isolate via `{'type': 'error'}`
- ✅ Busy gate releases on isolate error (no permanent frame-drop wedge)

### Preprocessing (100%)

- ✅ Manual YUV420→RGB conversion (no `image` package dependency)
- ✅ Nearest-neighbor resize to model input dimensions
- ✅ Dtype-matched writes driven by runtime metadata (normalized float, or quantized via input scale/zeroPoint)
- ✅ Support for FLOAT32/FLOAT64/FLOAT16/INT8/UINT8/INT16 model input types

### Post-Processing (95%)

- ✅ Argmax per-box (anchors × classes from runtime metadata)
- ✅ Dequantization driven by runtime metadata (only when the output tensor is quantized)
- ✅ Confidence threshold filtering (0.5)
- ✅ Detection list construction (classId, confidence, bounding box)
- ✅ Per-detection debug logging (label, confidence, normalised box coords)
- ❌ NMS (Non-Maximum Suppression) — missing

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

- ✅ Model loading from assets (`yolov8n.tflite`)
- ✅ COCO label loading from `labels.txt` (80 classes)
- ✅ Label lookup by class index
- ✅ Model load success/failure logging with tensor metadata

### Orientation Architecture (100%) — NEW (2026-08-01)

- ✅ [`BoxTransform`](../lib/models/box_transform.dart) — single, device-independent source of truth for orientation math (`deviceDegreesFor` using the plugin's counter-clockwise convention, `displayRotationDegrees`, `uprightDims`, reversible `rotateRect`/`invertRect`, `mirrorRect`); no hardcoded angles
- ✅ Upright tensor inference — isolate rotates + optionally X-mirrors the 640×640 NHWC input to UPRIGHT before `interpreter.run()` (parser/NMS untouched)
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

### Documentation (60%)

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

**Orientation re-validation** — Active

| Task | Status |
|------|--------|
| Back · portrait on-device | ✅ Done (maxConf 0.91, was 0) |
| Static-image regression (rot=0) | ✅ Done (byte-identical) |
| Back · landscape physical hold | 🟡 Convention bug fixed; physical-hold re-validation deferred |
| Front · portrait / landscape | 🟡 Math implemented; device run pending |

**Milestone 1: "Audible MVP"** — Active

| Task | Status |
|------|--------|
| TTS audio feedback | ❌ Not started |
| Bounding box `CustomPainter` | ✅ Complete (2026-07-22) |
| Error handling in isolate | 🟡 Partial — try/catch added around interpreter creation + frame loop; error propagation to main isolate |
| Permission-denied UI | ❌ Not started |
| Remove/wire unused dependencies | ❌ Not started |
| Debug instrumentation & logging | ✅ Complete (2026-07-22) |
| Forensic file logging | ✅ Complete (2026-08-01, v0.1.3) |
| Camera preprocessing repair | ✅ Complete (2026-08-01, v0.1.4) |
| Aspect-correct preview | ✅ Complete (2026-08-01, v0.1.5) |
| Camera preview UI redesign | ✅ Complete (2026-08-01, v0.1.6) |
| Device-independent orientation | ✅ Complete (2026-08-01, v0.1.7) |

## Next Tasks (Priority Order)

0. **Re-validate orientation on-device** — back landscape physical hold + front camera portrait/landscape (see [`docs/orientation-implementation.md`](orientation-implementation.md)).
1. **Implement TTS audio feedback** — 2–4 hours. Wire `flutter_tts` to detection stream.
2. ~~**Implement bounding box `CustomPainter`**~~ — ✅ Done. See [`lib/widgets/bounding_box_painter.dart`](../lib/widgets/bounding_box_painter.dart).
3. ~~**Add debug instrumentation**~~ — ✅ Done. See [`lib/widgets/debug_overlay.dart`](../lib/widgets/debug_overlay.dart), [`lib/services/inference_isolate.dart`](../lib/services/inference_isolate.dart), [`lib/screens/camera_screen.dart`](../lib/screens/camera_screen.dart), [`lib/widgets/bounding_box_painter.dart`](../lib/widgets/bounding_box_painter.dart).
4. **Complete error handling in inference isolate** — 0.5–1 hours. Extend error recovery (isolate restart on crash).
5. **Add permission-denied UI** — 1–2 hours.
6. **Investigate XNNPACK SIGSEGV** — 4–8 hours. Benchmark tool on test device.

## Remaining Tasks

See [`implementation-plan.md`](implementation-plan.md) for the full milestone breakdown.

### By Milestone:

- **Milestone 1 (Audible MVP):** 4.5 tasks remaining (~8–15 hours)
- **Milestone 2 (Research-Ready):** 6 tasks (~14–24 hours)
- **Milestone 3 (Defense-Ready):** 7 tasks (~22–37 hours)
- **Milestone 4 (Production Candidate):** 6 tasks (~16–28 hours)

**Total Estimated Effort (remaining):** ~60–104 hours

## Estimated Completion

| Milestone | Target |
|-----------|--------|
| M1: Audible MVP | ~2 weeks |
| M2: Research-Ready | ~4 weeks |
| M3: Defense-Ready | ~6 weeks |
| M4: Production Candidate | ~8 weeks |

## Verification Log (2026-07-22)

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
