# EyeCue — Architecture

> See also: [`chat_spec.md`](../chat_spec.md) (historical specification), [`implementation-decisions.md`](implementation-decisions.md) (key decisions).

## Project Purpose

EyeCue is a **real-time, on-device object detection assistive application for visually impaired users**. The app captures camera frames, runs them through a YOLOv8n TFLite model, speaks detected object names aloud via text-to-speech, and overlays bounding boxes on the camera preview.

Originally prototyped in React Native, EyeCue has been rebuilt in Flutter to eliminate camera preview hitching caused by React Native's threading architecture.

## High-Level Architecture

```
┌──────────────────────────────────────────────────┐
│                  Main Isolate (UI)                │
│                                                  │
│  ┌──────────┐    ┌─────────────────────────┐     │
│  │  Camera   │    │   CameraScreen (State)  │     │
│  │  Plugin   │───▶│   _isInferring gate     │     │
│  │  YUV420   │    │   _detections list      │     │
│  │  Stream   │    │   CameraPreview widget  │     │
│  └──────────┘    └──────────┬──────────────┘     │
│                             │                    │
│                    SendPort │  ▲ Stream<List>     │
│                             ▼  │                  │
│                  ┌────────────────────┐          │
│                  │ InferenceService   │          │
│                  │ (Bridge Manager)   │          │
│                  └────────┬───────────┘          │
└───────────────────────────┼──────────────────────┘
                             │ SendPort/ReceivePort
                             │ (Isolate boundary)
┌───────────────────────────┼──────────────────────┐
│            Inference Isolate                      │
│                           ▼                       │
│  ┌──────────────────────────────────────────┐    │
│  │  _isolateEntryPoint()                     │    │
│  │                                          │    │
│  │  1. Interpreter.fromBuffer() — ONCE      │    │
│  │  2. Runtime introspection → ModelMetadata│    │
│  │  3. Pre-allocated dtype-matched buffers  │    │
│  │  4. YUV420 → RGB conversion (manual)     │    │
│  │  5. interpreter.run(raw ByteBuffers)     │    │
│  │  6. Argmax per-box (+dequant if needed)  │    │
│  │  7. Detection list → mainSendPort        │    │
│  └──────────────────────────────────────────┘    │
└──────────────────────────────────────────────────┘
```

## Data Flow

1. `CameraController.startImageStream()` delivers `CameraImage` at native FPS (~30)
2. `_processCameraImage()` checks `_isInferring` gate → drops frame if busy
3. Extracts Y, U, V `Uint8List` planes + dimensions
4. Sends Map via `SendPort` to inference isolate
5. Isolate introspects runtime tensors + model buffer → builds `ModelMetadata` (types, shapes, quantization, model type)
6. Isolate converts YUV420 → RGB into the dtype-matched input buffer (normalized float or quantized via scale/zeroPoint)
7. Passes raw bytes (`ByteBuffer`) to `interpreter.run()` — **no reshape**, no shape resizing
8. Post-processes: argmax per box, dequantization only when the output tensor is quantized, confidence threshold (0.25), class-wise NMS (IoU 0.45)
9. Returns `List<Detection>` to main isolate via `SendPort`
10. Main isolate adds to `StreamController` → `setState()` → UI repaints

## Folder Structure

```
eyecue_flutter/
├── lib/
│   ├── main.dart                          # App entry point, MaterialApp
│   ├── models/
│   │   ├── detection.dart                 # Detection data class
│   │   ├── box_transform.dart             # Device-independent orientation math
│   │   ├── model_metadata.dart            # Runtime model metadata (self-describing)
│   │   ├── tflite_flatbuffer.dart         # Pure-Dart flatbuffer tensor-type scanner
│   │   └── png_encoder.dart               # Pure-Dart PNG encoder (forensic dumps)
│   ├── screens/camera_screen.dart         # Single screen — camera + orchestration
│   ├── services/
│   │   ├── inference_isolate.dart         # Isolate bridge + inference + preprocessing
│   │   ├── forensic_log.dart              # File-based structured diagnostics
│   │   ├── inference_probe.dart           # Parser probe (disabled, removable)
│   │   └── input_probe.dart               # Input pipeline probe (disabled, removable)
│   └── widgets/
│       ├── bounding_box_painter.dart      # Detection overlay CustomPainter
│       ├── debug_overlay.dart             # Debug HUD (retained, unused)
│       └── info_panel.dart                # Metrics + Detections info panel
├── tool/
│   ├── validate_flatbuffer.dart           # CLI: validates the flatbuffer scanner
│   ├── validate_png.dart                  # CLI: validates the PNG encoder
│   ├── dump_graph_tail.py                 # CLI: dumps TFLite graph tail ops
│   └── dump_decode_consts.py              # CLI: dumps TFLite decode constants
├── assets/
│   ├── yolov8n.tflite                     # Active model (FLOAT32 I/O, INT8 weights)
│   ├── yolov8n_int8.tflite                # Present but not in pubspec assets
│   ├── test_image.jpg                     # Static-image test asset (test mode only)
│   └── labels.txt                         # 80 COCO class names
├── android/                               # Android platform (Gradle 9.1, AGP 9.0.1)
├── ios/                                   # iOS platform (bootstrapped)
├── linux/, macos/, windows/, web/         # Desktop/web platforms (bootstrapped)
├── test/                                  # Test directory (boilerplate only)
├── docs/                                  # Project documentation
├── pubspec.yaml                           # Dependencies & asset declarations
├── chat_spec.md                           # Historical specification (~3100 lines)
└── auditor.md                             # Comprehensive project audit
```

## Major Components

| Component | File | Responsibility |
|-----------|------|---------------|
| App Entry | [`main.dart`](../lib/main.dart) | MaterialApp initialization, routing to CameraScreen |
| Camera Screen | [`camera_screen.dart`](../lib/screens/camera_screen.dart) | Camera lifecycle, permission handling, frame dispatch, UI, preview/info-panel wiring |
| Inference Service | [`inference_isolate.dart`](../lib/services/inference_isolate.dart) | Isolate bridge, persistent worker, runtime introspection, preprocessing, model inference, post-processing (argmax + NMS), input rotation |
| Model Metadata | [`model_metadata.dart`](../lib/models/model_metadata.dart) | Immutable runtime snapshot of the loaded model (types, shapes, quantization, model type) |
| Flatbuffer Scanner | [`tflite_flatbuffer.dart`](../lib/models/tflite_flatbuffer.dart) | Pure-Dart scan of internal tensor types for weight-precision detection |
| Box Transform | [`box_transform.dart`](../lib/models/box_transform.dart) | Device-independent orientation math (metadata-driven rotation/mirror) |
| PNG Encoder | [`png_encoder.dart`](../lib/models/png_encoder.dart) | Pure-Dart PNG encoder for forensic image dumps |
| Forensic Log | [`forensic_log.dart`](../lib/services/forensic_log.dart) | File-based structured diagnostics under `<documents>/debug/run_*` |
| Detection Model | [`detection.dart`](../lib/models/detection.dart) | Detection data class (classId, confidence, bounding box) |
| Bounding Box Painter | [`bounding_box_painter.dart`](../lib/widgets/bounding_box_painter.dart) | Draws detection boxes, labels, and confidence on the camera preview |
| Info Panel | [`info_panel.dart`](../lib/widgets/info_panel.dart) | Metrics + Detections tabs (permanent bottom panel) |
| Debug Overlay | [`debug_overlay.dart`](../lib/widgets/debug_overlay.dart) | Debug-only HUD (retained but unused; data moved to Info Panel) |

## External Dependencies

| Package | Version | Purpose |
|---------|---------|---------|
| `camera` | ^0.12.0+1 | Camera access + YUV420 image stream |
| `tflite_flutter` | ^0.12.1 | TFLite inference via FFI |
| `flutter_tts` | ^4.2.0 | Text-to-speech audio feedback |
| `flutter_riverpod` | ^3.3.2 | State management (declared, not yet used) |
| `permission_handler` | ^12.0.3 | Camera permission requests |
| `path_provider` | ^2.1.4 | File system paths (declared, not yet used) |
| `fl_chart` | ^1.2.0 | Data visualization for logging dashboard (declared, not yet used) |

## AI Pipeline

- **Model (as loaded):** `assets/yolov8n.tflite` — **FLOAT32 I/O with INT8 weights** (classified *Weight-Quantized*), input `[1, 640, 640, 3]`, output `[1, 84, 8400]` (84 = 4 box coords + 80 COCO classes, 8400 anchors). `yolov8n_int8.tflite` is also float32-I/O and is not bundled.
- **Model identity:** never assumed from filenames — introspected at runtime into a `ModelMetadata` snapshot.
- **Preprocessing:** Manual YUV420 → RGB conversion, nearest-neighbor resize, writes matched to the input dtype (normalized float, or quantized via input scale/zeroPoint). The 640×640 NHWC input is rotated/mirrored to UPRIGHT per orientation metadata before inference ([`BoxTransform`](../lib/models/box_transform.dart)).
- **Inference:** Single persistent `Interpreter` instance, run in dedicated Isolate. Raw `ByteBuffer`s are passed to `interpreter.run()` — no reshape, no input-tensor resizing.
- **Post-processing:** Argmax per-box, dequantization only when the output tensor is quantized, confidence threshold (0.25), **class-wise Non-Maximum Suppression (IoU 0.45)**.
- **Missing:** bilinear interpolation

## Runtime Model Introspection

The app is **self-describing**: after `Interpreter.fromBuffer()`, the isolate builds an immutable [`ModelMetadata`](../lib/models/model_metadata.dart) from:

- `interpreter.getInputTensor(0)` / `getOutputTensor(0)` — shape, datatype, scale/zeroPoint
- `scanTfliteTensorTypeCounts(modelBytes)` — a pure-Dart flatbuffer walk that counts internal tensor types (needed because the runtime API only exposes I/O tensors)

From this, [`ModelType`](../lib/models/model_metadata.dart) is classified — **never guessed**:

| I/O datatypes | Internal scan | Classified type |
|---|---|---|
| INT8 / INT8 | — | Full INT8 Quantized |
| UINT8 / UINT8 | — | Full UINT8 Quantized |
| FLOAT32 / FLOAT32 | has INT8/UINT8/INT16/FLOAT16 tensors | Weight-Quantized |
| FLOAT32 / FLOAT32 | no quantized tensors | FP32 |
| any | scan unavailable | Unknown (internal tensor precision unavailable) |

The metadata drives every pipeline decision: buffer dtype, whether to quantize input pixels, and whether to dequantize output values. It is shipped to the main isolate, logged at startup, and rendered in the debug overlay. If the runtime metadata ever disagrees with the filename, the runtime metadata wins and the discrepancy is logged.

## Important Architectural Principles

1. **Persistent Inference Isolate:** One `Isolate.spawn()` at startup, one `Interpreter` instance for the app lifetime. Never create/destroy per frame.
2. **Frame Dropping:** Boolean `_isInferring` gate drops frames when the inference worker is busy. No queueing — deterministic latency. The gate is released on isolate errors so the pipeline can recover.
3. **Manual Preprocessing:** Custom YUV420→RGB math avoids the `image` package to prevent GC pressure from real-time video.
4. **Runtime Model Introspection:** After interpreter creation, build a `ModelMetadata` snapshot from the runtime tensors plus an internal tensor-type scan. The interpreter is the single source of truth — nothing is hardcoded.
5. **Dynamic Inference Path:** Preprocessing quantizes only when the input tensor is quantized; post-processing dequantizes only when the output tensor is quantized (scale/zeroPoint from runtime metadata).
6. **XNNPACK Disabled:** Removed due to SIGSEGV on Snapdragon 695. CPU-only inference.
7. **Stream-Based Results:** `StreamController.broadcast()` for detection results, enabling multiple listeners.

## Missing Architectural Components

- **No routing:** Single screen, no navigation
- **No dependency injection:** Services instantiated directly in widgets
- **No state management layer:** Riverpod declared but unused; raw `setState` used
- **No service abstraction:** `InferenceService` coupled directly to TFLite, camera format, and COCO labels
- **Partial error handling:** try/catch + error propagation exist (2026-07-22); **no isolate restart recovery** and **no error/permission-denied UI states**
- **No configuration:** Thresholds are constants; model path and labels path hardcoded
