# EyeCue — Implementation Decisions

> See also: [`architecture.md`](architecture.md) (system design), [`known-issues.md`](known-issues.md) (current blockers).

This document records important engineering decisions made during the development of EyeCue. Each entry captures the decision, context, alternatives considered, and consequences.

---

## Decision 1: Persistent Inference Isolate

- **Decision:** Use `Isolate.spawn()` at app startup to create a single long-lived inference worker with one `Interpreter` instance reused for all frames.
- **Date:** 2026-07 (initial Flutter rebuild)
- **Reason:** The original GLM plan proposed `Isolate.run()` per frame (create isolate → load model → infer → destroy). This would add 100–500ms overhead per frame from model loading alone. A persistent isolate eliminates this completely.
- **Alternatives Considered:**
  - `Isolate.run()` per frame — rejected due to massive per-frame overhead
  - Main-thread inference — rejected due to UI jank
  - Thread pool of workers — rejected as unnecessary overhead for a single-model pipeline
- **Consequences:**
  - Model loads once at startup (~100–500ms one-time cost)
  - Inference latency is pure model time + preprocessing (no setup overhead)
  - Must manage Isolate lifecycle (spawn at init, dispose on app exit)
  - Communicate via SendPort/ReceivePort (message-passing overhead is minimal for byte arrays)

## Decision 2: Manual YUV420 Preprocessing

- **Decision:** Implement custom YUV420→RGB conversion with manual byte manipulation instead of using the `image` package.
- **Date:** 2026-07
- **Reason:** The `image` package is a pure-Dart image library not optimized for real-time video. It would create per-frame allocations generating significant GC pressure, causing UI jank during camera streaming at 30fps.
- **Alternatives Considered:**
  - `image` package — rejected due to GC pressure
  - FFI to native C/C++ conversion — considered future optimization
  - SIMD/NEON intrinsics — not yet explored
- **Consequences:**
  - Minimal per-frame allocations (pre-allocated buffers)
  - Nearest-neighbor resize only (no bilinear interpolation yet)
  - Uses non-standard YUV coefficients (slight color shift, negligible for detection)
  - Full Y/U/V planes copied across SendPort (~460KB per frame at 640×480)

## Decision 3: Dynamic Tensor Shape Querying

- **Decision:** Query `interpreter.getInputTensor(0).shape` and `interpreter.getOutputTensor(0).shape` at runtime rather than hardcoding tensor dimensions.
- **Date:** 2026-07
- **Reason:** YOLOv8 export shapes vary: `[1,84,2100]`, `[1,84,8400]`, `[1,25200,85]`, etc. Hardcoding would break if the model is swapped. Dynamic querying supports model changes without code changes.
- **Alternatives Considered:**
  - Hardcoded `[1, 84, 2100]` — rejected as fragile
- **Consequences:**
  - Model-agnostic: supports different YOLOv8 exports and future model upgrades
  - NHWC/NCHW auto-detection via `shape[1] == 3` heuristic
  - Slightly more code at initialization, but zero runtime cost

## Decision 4: Quantized-Model Support (Dynamic, Metadata-Driven)

- **Decision:** Support quantized models with proper dequantization (scale/zeroPoint from `outputTensor.params`), driven entirely by runtime model metadata rather than assumptions about the file.
- **Date:** 2026-07 (updated 2026-08-14 to reflect the verified model type)
- **Reason:** Support any YOLOv8 export — full INT8/UINT8, weight-quantized, or pure float32 — without code changes. The runtime introspection (`ModelMetadata`) classifies the actual loaded model: the bundled `yolov8n.tflite` is **FLOAT32 I/O with INT8 weights (Weight-Quantized)** — *not* full INT8 despite its filename. Dequantization is applied only when the output tensor is actually quantized.
- **Alternatives Considered:**
  - Assume the model is full INT8 from the filename — rejected; would be wrong for the bundled file and fragile for future swaps
  - Require float32 output layer — rejected; real quantized outputs need dequantization
- **Consequences:**
  - Handles `TensorType.int8`/`uint8` with proper `scale`/`zeroPoint` math
  - Pre-allocated dtype-matched output buffer for dequantized results
  - Works with INT8, UINT8, FLOAT16, and float32 models (detected dynamically)
  - The quantization/dequantization branches are dormant for the current Weight-Quantized model but activate automatically for full INT8 models

## Decision 5: XNNPACK Disabled in the v0.2.2 Baseline

- **Decision:** Explicitly disable XNNPACK acceleration due to SIGSEGV crash on the target test device (Snapdragon 695).
- **Date:** 2026-07
- **Reason:** Enabling XNNPACK caused a segmentation fault during inference on the Snapdragon 695 (Adreno 619 GPU). This is likely a TFLite/Snapdragon compatibility issue. Without XNNPACK, inference runs on plain CPU which is stable but slower.
- **Alternatives Considered:**
  - Keep XNNPACK enabled — rejected due to crash
  - Try NNAPI delegate — not yet tested
  - Try GPU delegate — not yet tested
  - Investigate root cause with TFLite benchmark tool — planned
- **Consequences:**
  - Stable but CPU-only inference
  - Performance ceiling: no hardware acceleration
  - See [`known-issues.md`](known-issues.md) for current blocker status
  - Future: benchmark raw model latency, test NNAPI/GPU delegates
- **Current status (2026-09-01):** This remains the v0.2.2 release decision, not proof that the crash is fixed. The unreleased worktree attempts explicit XNNPACK for `yolov8n_int8_new.tflite`, retains the delegate for the interpreter lifetime, and retries on CPU after recoverable Dart-level setup or invocation failures. A native SIGSEGV remains uncatchable and requires exact-APK device validation.

## Decision 6: Stream-Based Results

- **Decision:** Use `StreamController.broadcast()` to deliver detection results from the inference isolate to the UI.
- **Date:** 2026-07
- **Reason:** Decouples the inference pipeline from the UI layer. Multiple widgets can listen to detection results without tight coupling. Enables future features like logging listeners, TTS listeners, and overlay painters to consume the same data stream independently.
- **Alternatives Considered:**
  - Direct `setState` in callback — rejected as tightly coupled
  - Riverpod providers — planned for future but not yet implemented
- **Consequences:**
  - Clean separation between inference service and UI
  - `StreamBuilder` or manual subscription patterns available
  - **Update (v0.2.0):** the broadcast stream now has multiple listeners — the Detection UI, TTS service, and telemetry service all subscribe, so broadcast (rather than single-subscription) is now the correct choice.

## Decision 8: Bounding Box Coordinate Transformation

- **Decision:** Use a two-stage coordinate transformation: (1) map normalised model coords [0,1] linearly to camera image pixels, then (2) map image pixels to screen pixels accounting for AspectRatio letterboxing.
- **Date:** 2026-07-22
- **Reason:** The YOLO model outputs normalised [0,1] coordinates relative to its 640×640 input (verified from the model graph — boxes are already normalized by `×1/640` inside the exported graph, see [`inference-pipeline-probe.md`](inference-pipeline-probe.md)). The camera image (e.g. 320×240) is stretched (not letterboxed) to fill the square model input during YUV→RGB preprocessing. This means normalised coordinates map linearly to the original camera image: `imgX = normX × imgWidth`. The second stage accounts for the Flutter `CameraPreview` widget's `AspectRatio` behaviour — the preview fills an expanded `Stack` but the actual camera texture is letterboxed to preserve the sensor's native aspect ratio.
- **Alternatives Considered:**
  - Direct normalised-to-screen mapping (ignoring letterboxing) — rejected; boxes would be misaligned on non-matching aspect ratios
  - Using `cameraController.value.aspectRatio` for the preview — rejected; the raw image aspect ratio from the sensor is the authoritative source since the model operates on that data
  - Using `cameraController.value.previewSize` — rejected; the preview size may differ from the raw image dimensions sent to the isolate
- **Consequences:**
  - Boxes align correctly regardless of screen aspect ratio
  - Front-camera horizontal mirroring is a simple `x = previewWidth - x - width` transform
  - `CameraImage.width` and `CameraImage.height` must be stored in UI state for the painter
  - The `_calculateImageRect()` helper encapsulates all aspect-ratio math; easy to test and adjust

## Decision 9: Device-Independent Orientation (Input Rotation)

- **Decision:** Rotate (and optionally X-mirror) the square input tensor to UPRIGHT before `interpreter.run()`, driven entirely by runtime metadata — `CameraDescription.sensorOrientation`, the current `controller.value.deviceOrientation`, and lens direction. [`BoxTransform`](../lib/models/box_transform.dart) remains the source of orientation metadata, while [`tensor_rotation.dart`](../lib/models/tensor_rotation.dart) applies the pixel transform to either NHWC interleaved or NCHW planar buffers. Parser/NMS are untouched; boxes after NMS are already in upright space.
- **Date:** 2026-08-01
- **Reason:** On-device forensics (`docs/camera-path-forensics.md`) proved the last camera defect was missing rotation-to-device-orientation: this device delivers sensor-native 320×240 landscape frames (sensorOrientation 90°) that are never rotated, so a portrait hold feeds the model a 90°-rotated scene → ~0 detections, while landscape holds detect at 0.88. The design review (`docs/orientation-design-review.md`) had recommended **sensor-space inference + post-NMS box transform**, but on-device evidence showed that cannot work: when the model sees a rotated scene there are no boxes to transform. Input rotation is the only design satisfying "portrait detection quality must match landscape" (verified: portrait now 0.91, static-image regression byte-identical).
- **Alternatives Considered:**
  - Post-NMS box transform (design-review option d) — rejected: no boxes exist when the model sees a rotated scene
  - Rotate Y/U/V planes before conversion — rejected: heavy chroma/strides complexity, risk in a just-verified stage
  - Rotate only the preview — rejected: cosmetic; YOLO still sees rotated content
  - Fixed 90° rotation — rejected: sensorOrientation ∈ {0,90,180,270} varies by device/lens; front camera also needs X-mirror
- **Consequences:**
  - Device-independent: works for sensorOrientation 0/90/180/270, all four holds, front/back lenses (no hardcoded angles)
  - The painter became a pure normalized→pixel mapper (no lens/mirror knowledge) — single canonical upright space
  - `DeviceOrientation→degrees` uses the plugin's own counter-clockwise convention (landscapeLeft→90, landscapeRight→270), verified against `camera_android_camerax._getRotationConstantFromDeviceOrientation`; the naive clockwise mapping was the landscape convention bug found on-device
  - Square 640×640 input makes 90°/180°/270° lossless transposes in both supported layouts
  - NCHW rotation clones the input only when a non-identity rotation or mirror is required; the helper is directly unit-tested with small tensors
  - Landscape physical-hold re-validation and front-camera device runs are still pending
  - See [`docs/orientation-implementation.md`](orientation-implementation.md) for full details

## Decision 10: Unreleased NCHW/XNNPACK Candidate Must Not Replace Validation Evidence

- **Decision:** Keep `yolov8n_int8_new.tflite` as the current unreleased model candidate and report it separately from the validated v0.2.2 CPU/NHWC baseline until controlled comparative, accuracy, and stability validation is complete.
- **Date:** 2026-09-01
- **Reason:** Direct flatbuffer/runtime inspection confirms a FLOAT32-I/O NCHW model with internally quantized tensors, and static tests validate layout conversion and rotation. The exact candidate APK now installs on the API 33 phone and a short run confirms startup metadata, explicit XNNPACK setup, and live frame completion. That observation is not sufficient for trustworthy comparative performance, accuracy, long-duration stability, or full-delegation conclusions.
- **Consequences:**
  - Documentation distinguishes release behavior from current uncommitted work.
  - No XNNPACK speedup, model-quality improvement, full graph delegation, or crash resolution is claimed.
  - The candidate retains a CPU fallback for recoverable Dart-level failures, while native crash risk and isolate restart recovery remain open.

## Decision 7: Flutter over React Native

- **Decision:** Rebuild EyeCue in Flutter/Dart rather than continuing with React Native.
- **Date:** 2026-07
- **Reason:** The React Native prototype suffered from camera preview hitching despite using JSI (no bridge), worklets, and frame dropping. The root cause was React Native's threading model: even with all optimizations, the camera preview thread and the UI composition thread could not maintain smooth 60fps while running TFLite inference. Flutter provides true OS-level Isolate threads, Skia GPU rendering, and single-thread ownership of the UI — eliminating the architectural source of the hitching.
- **Alternatives Considered:**
  - Continue React Native with further optimizations — rejected; diminishing returns
  - Native Android (Kotlin) — rejected; Flutter provides cross-platform and faster UI development
  - Native iOS (Swift) — not applicable; Android is primary target
- **Consequences:**
  - 4 Dart source files replace 17 TypeScript files
  - Camera preview is smooth even during inference
  - Lost: existing React Native TTS, accessibility, and UI work (must be reimplemented)
  - Gained: cleaner architecture, GPU overlays via CustomPainter, true multithreading
