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

## Decision 4: INT8 Model Support

- **Decision:** Support INT8 quantized models with proper dequantization (scale/zeroPoint from `outputTensor.params`).
- **Date:** 2026-07
- **Reason:** The target model (`yolov8n.tflite`) is actually INT8-quantized despite its name. INT8 models are ~4× smaller and ~2–4× faster on CPU than float32. Dequantization is required to interpret the confidence scores correctly.
- **Alternatives Considered:**
  - Float32-only model — rejected due to larger size and slower inference
  - Require float32 output layer — rejected; INT8 outputs need dequantization
- **Consequences:**
  - Handles `TensorType.int8`/`uint8` with proper `scale`/`zeroPoint` math
  - Pre-allocated Float32 output buffer for dequantized results
  - Works with both INT8 and float32 models (detected dynamically)

## Decision 5: XNNPACK Disabled

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
  - Currently only one listener exists (CameraScreen); broadcast is slightly over-provisioned but harmless

## Decision 8: Bounding Box Coordinate Transformation

- **Decision:** Use a two-stage coordinate transformation: (1) map normalised model coords [0,1] linearly to camera image pixels, then (2) map image pixels to screen pixels accounting for AspectRatio letterboxing.
- **Date:** 2026-07-22
- **Reason:** The YOLO model outputs normalised [0,1] coordinates relative to its 320×320 input. The camera image (e.g. 640×480) is stretched (not letterboxed) to fill the square model input during YUV→RGB preprocessing. This means normalised coordinates map linearly to the original camera image: `imgX = normX × imgWidth`. The second stage accounts for the Flutter `CameraPreview` widget's `AspectRatio` behaviour — the preview fills an expanded `Stack` but the actual camera texture is letterboxed to preserve the sensor's native aspect ratio.
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

- **Decision:** Rotate (and optionally X-mirror) the 640×640 NHWC input tensor to UPRIGHT before `interpreter.run()`, driven entirely by runtime metadata — `CameraDescription.sensorOrientation`, the current `controller.value.deviceOrientation`, and lens direction — centralized in a single pure helper ([`BoxTransform`](../lib/models/box_transform.dart)). Parser/NMS are untouched; boxes after NMS are already in upright space.
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
  - Square 640×640 input makes 90°/180°/270° lossless transposes
  - Landscape physical-hold re-validation and front-camera device runs are still pending
  - See [`docs/orientation-implementation.md`](orientation-implementation.md) for full details

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
