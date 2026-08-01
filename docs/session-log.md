# EyeCue — Session Log

> Append a new entry at the top of this file at the end of every development session.  
> See [`development-workflow.md`](development-workflow.md) for the full workflow.

---

## 2026-08-01 (2nd session)

### Objective
- Replace console-based diagnostics with a structured, file-based forensic logging system (logcat was becoming unusable).

### Completed
- [`ForensicLog`](../lib/services/forensic_log.dart) — timestamped run directories under `<documents>/debug/run_YYYYMMDD_HHMMSS/` with `summary/camera/preprocess/tensor/output/parser/performance/errors.txt`, synchronous flush-per-write, and full try/catch isolation (logging can never break inference).
- First-frame PNG dumps: `frame_original.png` (Y luma), `frame_rgb.png` (YUV→RGB at camera res), `frame_resized.png`, `frame_model_input.png`.
- [`PngEncoder`](../lib/models/png_encoder.dart) — pure-Dart PNG encoder (isolate-safe). Validated by [`tool/validate_png.dart`](../tool/validate_png.dart) (signature/CRC/chunks/dims) and cross-decoded in Python — pixel-exact.
- Auto-generated `summary.txt` every 50 frames and on close: per-stage PASS/FAIL, max confidence, P99, top class, distribution, ranked root causes computed from collected statistics.
- Wired run-dir creation into `initIsolate` (path passed to the isolate), frame-loop channels via `_safeForensic`, and `camera.txt` on the first frame in `camera_screen.dart`; `processFrame` forwards `cameraFps`/`droppedFrames` for the performance log.
- Replaced console probes: `InferenceProbe`/`InputProbe` disabled (`enabled=false`) and call sites removed.
- `flutter analyze`: 0 issues.

### Decisions
- All writes are synchronous + flushed so a crash cannot lose logs.
- Image dumps are produced inside the inference isolate using a pure-Dart PNG encoder (no `dart:ui`, no engine dependency).
- Console probes are disabled rather than deleted, keeping them re-enableable; everything remains removable.

### Next Session
- Use the forensic run output to confirm the input-side root cause, then implement the single targeted fix.

---

## 2026-08-01

### Objective
- Make the app **self-describing**: report exactly what model is running, based on the loaded interpreter (not filenames or assumptions).
- Drive the inference pipeline from runtime model metadata (dynamic inference-path selection).

### Completed
- **Diagnosis (pre-implementation):** traced the `NoSuchMethodError: Float32List has no instance method 'reshape'` crash to [`inference_isolate.dart:257`](../lib/services/inference_isolate.dart) — `reshape()` is a `List` *extension* method invoked on a `dynamic` receiver (extensions are never resolved via dynamic dispatch). Also identified two latent tensor-handling bugs (flat `List` output fails tflite_flutter's `copyTo()` shape check; flat float input triggers automatic 1-D `resizeInputTensor`). Full report: [`docs/inference-tensor-diagnosis.md`](inference-tensor-diagnosis.md).
- **Model metadata:** parsed both bundled `.tflite` files with the reference `tflite` Python package → both are **FLOAT32 I/O** (input `[1, 640, 640, 3]`, output `[1, 84, 8400]`) with INT8 weights → *Weight-Quantized*.
- **Implemented [`ModelMetadata`](../lib/models/model_metadata.dart)** — immutable runtime snapshot (name, I/O types, shapes, scale/zeroPoint, quantized flags, classes, anchors, model type) built from `getInputTensor(0)`/`getOutputTensor(0)` + an internal tensor scan.
- **Implemented [`tflite_flatbuffer.dart`](../lib/models/tflite_flatbuffer.dart)** — pure-Dart FlatBuffers walker counting internal tensor types; validated 1:1 against the Python reference (324/23/62 and 324/25/62), plus IEEE-754 float16 helpers.
- **Rewrote [`inference_isolate.dart`](../lib/services/inference_isolate.dart)** around metadata: dtype-matched buffers, raw `ByteBuffer` I/O (fixes the reshape crash + latent output/input bugs), quantize-only-if-quantized preprocessing, dequantize-only-if-quantized post-processing, `MODEL INFORMATION` startup banner.
- **Extended [`debug_overlay.dart`](../lib/widgets/debug_overlay.dart)** with a live MODEL section (name, type, I/O types, shapes, classes, anchors, quantization, scale/zeroPoint) that adapts automatically to any model.
- **Wired [`camera_screen.dart`](../lib/screens/camera_screen.dart)**: overlay reacts to `metadataNotifier`; busy gate releases on isolate errors via `errorStream`.
- **Added [`tool/validate_flatbuffer.dart`](../tool/validate_flatbuffer.dart)** — `dart run tool/validate_flatbuffer.dart` → all validations pass.
- `flutter analyze`: 0 issues.

### Issues
- FlatBuffers vtable field slots are `4 + 2×index` (not `2 + 2×index`) — caught while validating the walker against the Python reference.
- Float16 subnormal threshold off-by-one (`exponent > 103` → `>= 103`) and NaN→Inf loss — fixed with roundtrip tests.

### Decision
- The runtime interpreter is the single source of truth; internal weight precision is scanned from the model buffer (never guessed, reported as "Unknown" if unavailable).
- Buffers are passed to `interpreter.run()` as raw `ByteBuffer`s — the zero-copy, shape-exempt path (no reshape, no automatic input-tensor resizing).
- Metadata is serialized to a JSON map to cross the isolate boundary and reconstructed on the main side.

### Next Session
- Begin Milestone 1: Implement TTS audio feedback
- Add permission-denied UI state
- Complete error recovery (isolate restart on fatal error)

---

## 2026-07-22

### Objective
- Verify the bounding box overlay & detection pipeline (feature verification)
- Make the pipeline observable via structured debug logging + a visual debug overlay

### Completed
- Traced the full pipeline: Camera → CameraImage → inference isolate → YOLOv8 → post-processing → Detection → bounding box overlay → UI
- Implemented bounding box `CustomPainter` overlay ([`lib/widgets/bounding_box_painter.dart`](../lib/widgets/bounding_box_painter.dart))
  - Normalised→screen coordinate transform with AspectRatio letterboxing
  - Front-camera mirroring, label pills with confidence %, shadow rendering
- Added structured debug logging with consistent prefixes: `[Service]`, `[Model]`, `[Camera]`, `[Inference]`, `[Detection]`, `[Painter]`, `[Performance]`, `[Error]`
- Added per-frame inference latency timing via `Stopwatch` (exposed via `InferenceService.lastLatencyMs`)
- Added 5-second `[Performance]` summaries (camera FPS, inference FPS, avg/min/max latency, frame stats)
- Created [`lib/widgets/debug_overlay.dart`](../lib/widgets/debug_overlay.dart) — visual HUD for debug builds (`kDebugMode`)
- Added error handling: try/catch around interpreter creation + frame loop; isolate errors propagated to main isolate via `{'type': 'error'}`
- Extended isolate message protocol: `{'type': 'result'/'error'/'model_loaded'}` with latency + frame metadata
- Replaced all `print()` calls with `debugPrint()`
- `flutter analyze`: 0 issues

### Issues
- `CameraValue` has no `imageFormatGroup` getter — workaround: store the configured format string
- try/catch on `Interpreter.fromBuffer()` made interpreter nullable — fixed with `!` null-assert
- `_logDetections()` needed locals from `_isolateEntryPoint()` — passed as parameters

### Decision
- Use `debugPrint()` with consistent bracketed prefixes (avoid `print()`)
- Debug overlay rendered only when `kDebugMode` — absent in release builds
- Log throttling (every 30th frame/paint) to avoid console spam
- Message protocol extended backward-compatibly via a `type` field

### Next Session
- Begin Milestone 1: Implement TTS audio feedback
- Add permission-denied UI state
- Complete error recovery (isolate restart on crash)

## 2026-07-22

### Objective
- Establish project documentation system (`docs/` directory)

### Completed
- Created `docs/` directory with 9 documentation files
- Documented architecture, implementation plan, progress, decisions, known issues
- Created testing plan, benchmark template, development workflow guide
- Updated `README.md` from boilerplate to project-specific content
- Preserved `chat_spec.md` and `auditor.md` as historical records

### Issues
- None — documentation-only session

### Decision
- All documentation lives in `docs/`; historical files preserved at root
- Cross-reference via "See also" headers rather than duplicated content

### Next Session
- Begin Milestone 1: Implement TTS audio feedback
