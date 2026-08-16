# EyeCue — Architecture

> See also: [`chat_spec.md`](../chat_spec.md) (historical specification), [`implementation-decisions.md`](implementation-decisions.md) (key decisions).

## Project Purpose

EyeCue is a **real-time, on-device object detection assistive application for visually impaired users**. The app captures camera frames, runs them through a YOLOv8n TFLite model, speaks detected object names aloud via text-to-speech, and overlays bounding boxes on the camera preview.

**EyeCue is Android-only** (per the thesis): it targets Android smartphones and does not support iOS, web, Windows, macOS, or Linux — their platform scaffolding has been removed.

Originally prototyped in React Native, EyeCue has been rebuilt in Flutter to eliminate camera preview hitching caused by React Native's threading architecture.

## High-Level Architecture

```
┌──────────────────────────────────────────────────┐
│                  Main Isolate (UI)                │
│                                                  │
│  ┌──────────┐    ┌─────────────────────────┐     │
│  │  Camera   │    │  DetectionScreen (State)│     │
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
│   ├── main.dart                          # App entry, theme, service wiring
│   ├── navigation/
│   │   └── app_shell.dart                 # 4-tab bottom nav (Home/Detect/Settings/Help)
│   ├── models/
│   │   ├── detection.dart                 # Detection data class (classId, label, confidence, box)
│   │   ├── detection_info.dart            # Spatial/priority/proximity user-facing info
│   │   ├── app_settings.dart              # Persisted settings model
│   │   ├── box_transform.dart             # Device-independent orientation math
│   │   ├── model_metadata.dart            # Runtime model metadata (self-describing)
│   │   ├── tflite_flatbuffer.dart         # Pure-Dart flatbuffer tensor-type scanner
│   │   └── png_encoder.dart               # Pure-Dart PNG encoder (forensic dumps)
│   ├── screens/
│   │   ├── home_screen.dart               # Home: branding, status card, Go to Live Camera
│   │   ├── detection_screen.dart          # Detection: assistive UI + camera/inference pipeline
│   │   ├── settings_screen.dart           # Settings: haptics/performance/audio/research
│   │   ├── help_screen.dart               # Help & Gestures manual
│   │   └── logs_reports_screen.dart       # Logs & Reports dashboard (Overview/Charts/Logs)
│   ├── services/
│   │   ├── inference_isolate.dart         # Isolate bridge + inference + preprocessing
│   │   ├── tts_service.dart               # TTS: queue, cooldown, de-duplication, mute, repeat
│   │   ├── settings_service.dart          # File-backed persisted settings (JSON)
│   │   ├── spatial_analysis_service.dart  # Box → position/priority/proximity (pure)
│   │   ├── haptics_service.dart           # HapticFeedback wrapper
│   │   ├── telemetry_service.dart         # Session telemetry + aggregates for reports
│   │   ├── gesture_controller.dart        # Thesis gesture state machine (pure)
│   │   ├── forensic_log.dart              # File-based structured diagnostics
│   │   ├── inference_probe.dart           # Parser probe (disabled, removable)
│   │   └── input_probe.dart               # Input pipeline probe (disabled, removable)
│   └── widgets/
│       ├── bounding_box_painter.dart      # Detection overlay CustomPainter
│       ├── gesture_surface.dart           # Transparent gesture capture layer
│       ├── detection_card.dart            # Object card (class/conf/position/priority)
│       ├── priority_badge.dart            # HIGH/MEDIUM/LOW badge
│       ├── warning_banner.dart            # High-priority obstacle banner
│       ├── status_pill.dart               # Detecting/Paused/Stopped indicator
│       ├── accessible_button.dart         # Large high-contrast button (48dp+)
│       ├── charts.dart                    # fl_chart latency/FPS/frequency charts
│       ├── debug_overlay.dart             # Debug HUD (retained, unused)
│       └── info_panel.dart                # Old developer metrics panel (unused in primary UI)
├── tool/                                  # CLI validation tools (unchanged)
├── assets/                                # Model + labels (+ test image)
├── android/                               # Android platform (the only supported platform)
├── test/                                  # Unit + widget tests (navigation, services, widgets)
├── docs/                                  # Project documentation
├── pubspec.yaml                           # Dependencies & asset declarations
├── chat_spec.md                           # Historical specification (~3100 lines)
└── auditor.md                             # Comprehensive project audit
```

## Major Components

| Component | File | Responsibility |
|-----------|------|---------------|
| App Entry | [`main.dart`](../lib/main.dart) | MaterialApp init, dark high-contrast theme, service wiring |
| Navigation Shell | [`app_shell.dart`](../lib/navigation/app_shell.dart) | 4-tab bottom nav (Home/Detect/Settings/Help), lazy pages, system back, Logs & Reports route |
| Home Screen | [`home_screen.dart`](../lib/screens/home_screen.dart) | Branding, Auto-Start status card, Go to Live Camera |
| Detection Screen | [`detection_screen.dart`](../lib/screens/detection_screen.dart) | Camera lifecycle, permission UI, frame dispatch, assistive UI (gestures, TTS, priority, controls) |
| Settings Screen | [`settings_screen.dart`](../lib/screens/settings_screen.dart) | Vibration / Auto-Start / Low Power / Audio / Logs & Reports |
| Help Screen | [`help_screen.dart`](../lib/screens/help_screen.dart) | Operations + gesture manual |
| Logs & Reports | [`logs_reports_screen.dart`](../lib/screens/logs_reports_screen.dart) | Overview / Charts / Logs dashboard (researcher-facing) |
| Inference Service | [`inference_isolate.dart`](../lib/services/inference_isolate.dart) | Isolate bridge, persistent worker, runtime introspection, preprocessing, model inference, post-processing (argmax + NMS), input rotation |
| TTS Service | [`tts_service.dart`](../lib/services/tts_service.dart) | Speech scheduling, cooldown, de-duplication, mute, repeat-last |
| Settings Service | [`settings_service.dart`](../lib/services/settings_service.dart) | File-backed persisted settings (JSON) |
| Spatial Analysis | [`spatial_analysis_service.dart`](../lib/services/spatial_analysis_service.dart) | Box → position/priority/approximate proximity (pure, outside pipeline) |
| Haptics Service | [`haptics_service.dart`](../lib/services/haptics_service.dart) | HapticFeedback wrapper respecting Vibration setting |
| Telemetry Service | [`telemetry_service.dart`](../lib/services/telemetry_service.dart) | Session records, samples, aggregates for reports |
| Gesture Controller | [`gesture_controller.dart`](../lib/services/gesture_controller.dart) | Thesis gesture state machine (single/two-finger-double/three-finger/swipe-down) |
| Model Metadata | [`model_metadata.dart`](../lib/models/model_metadata.dart) | Immutable runtime snapshot of the loaded model (types, shapes, quantization, model type) |
| Flatbuffer Scanner | [`tflite_flatbuffer.dart`](../lib/models/tflite_flatbuffer.dart) | Pure-Dart scan of internal tensor types for weight-precision detection |
| Box Transform | [`box_transform.dart`](../lib/models/box_transform.dart) | Device-independent orientation math (metadata-driven rotation/mirror) |
| PNG Encoder | [`png_encoder.dart`](../lib/models/png_encoder.dart) | Pure-Dart PNG encoder for forensic image dumps |
| Forensic Log | [`forensic_log.dart`](../lib/services/forensic_log.dart) | File-based structured diagnostics under `<documents>/debug/run_*` |
| Detection Model | [`detection.dart`](../lib/models/detection.dart) | Detection data class (classId, confidence, bounding box) |
| Bounding Box Painter | [`bounding_box_painter.dart`](../lib/widgets/bounding_box_painter.dart) | Draws detection boxes, labels, and confidence on the camera preview |
| Info Panel | [`info_panel.dart`](../lib/widgets/info_panel.dart) | Old Metrics + Detections tabs — retained, unused in the primary UI |
| Debug Overlay | [`debug_overlay.dart`](../lib/widgets/debug_overlay.dart) | Debug-only HUD (retained, unused) |

## External Dependencies

| Package | Version | Purpose |
|---------|---------|---------|
| `camera` | ^0.12.0+1 | Camera access + YUV420 image stream |
| `tflite_flutter` | ^0.12.1 | TFLite inference via FFI |
| `flutter_tts` | ^4.2.0 | Text-to-speech audio feedback |
| `flutter_riverpod` | ^3.3.2 | State management (declared, deliberately unused — state uses `ChangeNotifier` + `setState`) |
| `permission_handler` | ^12.0.3 | Camera permission requests |
| `path_provider` | ^2.1.4 | File-backed settings persistence ([`settings_service.dart`](../lib/services/settings_service.dart)) + forensic run directories ([`forensic_log.dart`](../lib/services/forensic_log.dart)) |
| `fl_chart` | ^1.2.0 | Latency/FPS/frequency charts in Logs & Reports ([`charts.dart`](../lib/widgets/charts.dart)) |

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

## Missing Architectural Components (remaining)

- **No isolate restart recovery:** try/catch + error propagation exist; if the isolate dies the app does not restart it (camera-denied UI is implemented; full crash recovery is not).
- **No dependency injection framework:** Services are wired in `main.dart` and passed via constructors — simple and sufficient, but not a full DI container.
- **State management:** plain `ChangeNotifier` services + `setState`; Riverpod remains declared but unused (intentionally — the app does not need a framework).
- **No service abstraction for `InferenceService`:** it remains coupled to TFLite, camera format, and COCO labels (acceptable for the thesis scope).
- **Configuration:** thresholds/model path/labels remain constants; detection-sensitivity is not yet runtime-configurable (per audit, intentionally not wired to avoid changing inference behavior).
- **Out of scope for the live app:** calibrated distance, movement/approach estimation, and accuracy/precision/recall/mAP (require ground truth — see [`thesis-product-status-audit.md`](thesis-product-status-audit.md)).
