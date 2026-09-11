# EyeCue — Architecture

> **Current status:** The app-only candidate has two independent inference engines: Custom EyeCue and Ultralytics. They share only normalized detections and the assistive application layer; release identity/signing, broad device validation, formal benchmarking, and native-crash validation remain open.
> See also: [`chat_spec.md`](../chat_spec.md) (historical specification), [`implementation-decisions.md`](implementation-decisions.md) (key decisions), and [`model-assets.md`](model-assets.md) (artifact record).

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
│                  │ (Custom bridge)    │          │
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

### Dual-engine boundary

EyeCue deliberately retains two independent inference pipelines:

- **Custom EyeCue:** `CameraController` delivers YUV420 frames to the Dart
  isolate, which performs preprocessing, classic TFLite/LiteRT inference,
  parsing, and class-wise NMS.
- **Ultralytics:** `YOLOView` owns the native CameraX/LiteRT pipeline and its
  native preprocessing, inference, and post-processing.
- **Shared boundary:** both paths normalize their results into the immutable
  [`Detection`](../lib/models/detection.dart) contract. The shared
  [`AssistiveDetectionController`](../lib/services/assistive_detection_controller.dart)
  then performs spatial interpretation, priority/proximity wording, tracking,
  scene summaries, TTS, haptics, corrections, telemetry/export, and
  accessibility-facing state. Engine-specific camera objects never cross that
  boundary.

The [`EngineCoordinator`](../lib/services/engine_coordinator.dart) owns the
preferred-versus-active engine state, one-shot fallback, generation filtering,
and recovery actions. A temporary fallback does not rewrite the persisted
preference and cannot cause automatic engine oscillation.

## Custom EyeCue Data Flow

1. `CameraController.startImageStream()` delivers `CameraImage` at native FPS (~30)
2. `_processCameraImage()` checks `_isInferring` gate → drops frame if busy
3. Extracts Y, U, V `Uint8List` planes + dimensions
4. Sends a frame map via `SendPort` to the inference isolate
5. Isolate introspects runtime tensors + model buffer → builds `ModelMetadata` (types, shapes, quantization, model type)
6. Isolate converts YUV420 → RGB into the dtype-matched input buffer (normalized float or quantized via scale/zeroPoint), in NHWC or NCHW order selected from the runtime shape
7. Isolate rotates/mirrors the square input tensor to upright when orientation metadata requires it
8. Passes raw bytes (`ByteBuffer`) to `interpreter.run()` — **no reshape**, no shape resizing; the current candidate attempts XNNPACK and can retry on CPU after recoverable Dart-level failures
9. Post-processes: argmax per box, dequantization only when the output tensor is quantized, the active configured confidence threshold (default `0.25`), and class-wise NMS (IoU `0.45`)
10. Returns `List<Detection>` to main isolate via `SendPort`
11. Main isolate adds to `StreamController` → `setState()` → UI repaints

## Ultralytics Data Flow

1. `YOLOView` starts the native camera/inference pipeline for the selected
   engine.
2. The native result callback is mapped by
   [`UltralyticsDetectionAdapter`](../lib/services/ultralytics_detection_adapter.dart)
   into the shared [`Detection`](../lib/models/detection.dart) model.
3. The shared assistive controller applies the same spatial, priority,
   approximate-proximity, tracking, TTS, haptic, correction, telemetry, and
   accessibility behavior as the Custom path.
4. Engine-specific lifecycle and failure events are reported to the
   coordinator; a recoverable Ultralytics startup failure can trigger the
   bounded one-shot Custom fallback without changing the saved preference.

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
│   │   ├── detection_failure.dart         # Typed inference failure DTO
│   │   ├── detection_runtime_state.dart   # Shared runtime states and failures
│   │   ├── inference_lifecycle_event.dart # Worker/engine lifecycle event DTO
│   │   ├── inference_recovery_policy.dart # Bounded Custom-worker recovery policy
│   │   ├── box_transform.dart             # Device-independent orientation math
│   │   ├── model_config.dart              # Shared model paths and thresholds
│   │   ├── model_metadata.dart            # Runtime model metadata (self-describing)
│   │   ├── detection_correction.dart      # Correction-record DTO
│   │   ├── tracked_detection.dart          # Movement-tracking DTO
│   │   ├── telemetry_export.dart          # Image-free export DTOs
│   │   ├── tflite_flatbuffer.dart         # Pure-Dart flatbuffer tensor-type scanner
│   │   └── png_encoder.dart               # Pure-Dart PNG encoder (forensic dumps)
│   ├── screens/
│   │   ├── home_screen.dart               # Home: branding, status card, Go to Live Camera
│   │   ├── detection_screen.dart          # Detection: assistive UI + Custom pipeline
│   │   ├── engine_detection_screen.dart   # Engine-selected detection wrapper
│   │   ├── ultralytics_detection_screen.dart # Native Ultralytics detection screen
│   │   ├── settings_screen.dart           # Settings: light Home-theme cards + telemetry metrics
│   │   ├── help_screen.dart               # Help & Gestures manual
│   │   └── logs_reports_screen.dart       # Logs & Reports dashboard (Overview/Charts/Logs)
│   ├── services/
│   │   ├── inference_isolate.dart         # Custom isolate bridge + inference + preprocessing
│   │   ├── inference_worker_lifecycle.dart # Generation-safe bounded worker recovery
│   │   ├── engine_coordinator.dart         # Preferred/active engine and fallback state
│   │   ├── assistive_detection_controller.dart # Shared post-detection behavior
│   │   ├── ultralytics_detection_adapter.dart # Native result → Detection adapter
│   │   ├── tts_service.dart               # TTS: queue, cooldown, de-duplication, mute, repeat
│   │   ├── settings_service.dart          # File-backed persisted settings (JSON)
│   │   ├── spatial_analysis_service.dart  # Box → position/priority/proximity (pure)
│   │   ├── haptics_service.dart           # HapticFeedback wrapper
│   │   ├── telemetry_service.dart         # Session telemetry + aggregates for reports
│   │   ├── telemetry_export_service.dart  # JSON/CSV export
│   │   ├── correction_service.dart        # Detection correction capture
│   │   ├── object_tracker.dart             # Temporal movement tracking
│   │   ├── scene_summary_service.dart     # Deterministic scene summaries
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
│       ├── detection_state_panel.dart     # Runtime/loading/recovery/error panel
│       ├── detection_correction_sheet.dart # Correction capture sheet
│       ├── charts.dart                    # fl_chart latency/FPS/frequency charts
│       ├── debug_overlay.dart             # Debug HUD (retained, unused)
│       └── info_panel.dart                # Old developer metrics panel (unused in primary UI)
│   └── theme/                             # Design tokens + theme (UI-owned)
│       ├── app_colors.dart                # Semantic color tokens
│       ├── app_spacing.dart               # Spacing scale
│       ├── app_radii.dart                 # Corner-radius scale
│       ├── app_typography.dart            # High-contrast TextTheme builder
│       ├── app_theme.dart                 # buildEyeCueTheme() (moved out of main.dart)
│       └── app_home_theme.dart            # Home-local light theme + IBM Plex Sans + shadows
├── tool/                                  # CLI validation tools (unchanged)
├── assets/                                # Model + labels (+ test image + logo + fonts)
├── android/                               # Android platform (the only supported platform)
├── test/                                  # Unit + widget tests (navigation, services, widgets)
├── docs/                                  # Project documentation
├── design-reference/                      # Manually-exported Figma screenshots (screens/ + components/)
├── pubspec.yaml                           # Dependencies & asset declarations
├── chat_spec.md                           # Historical specification (~3100 lines)
└── auditor.md                             # Comprehensive project audit
```

## Major Components

| Component | File | Responsibility |
|-----------|------|---------------|
| App Entry | [`main.dart`](../lib/main.dart) | MaterialApp init, service wiring, debug-only Marionette binding |
| App Theme | [`app_theme.dart`](../lib/theme/app_theme.dart) | `buildEyeCueTheme()` — dark high-contrast theme consuming the token files |
| Design Tokens | [`app_colors.dart`](../lib/theme/app_colors.dart), [`app_spacing.dart`](../lib/theme/app_spacing.dart), [`app_radii.dart`](../lib/theme/app_radii.dart), [`app_typography.dart`](../lib/theme/app_typography.dart) | Semantic color/spacing/radius tokens + high-contrast `TextTheme` builder; includes the `kHome*` light tokens and `kRadius3/14/18/24` |
| Home Theme | [`app_home_theme.dart`](../lib/theme/app_home_theme.dart) | Home-local light `ThemeData` (`buildHomeTheme()`), IBM Plex Sans typography, and Home shadow tokens; scoped to the Home, Help, Settings, Logs & Reports, and Detection subtrees only |
| Navigation Shell | [`app_shell.dart`](../lib/navigation/app_shell.dart) | 4-tab bottom nav (Home/Detect/Settings/Help), lazy pages, system back, Logs & Reports route |
| Home Screen | [`home_screen.dart`](../lib/screens/home_screen.dart) | Light Home composition: preference/status badge, decorative logo + live `EyeCue` wordmark, lower instruction region, accessible CTA, cyan rail |
| Detection Screen | [`detection_screen.dart`](../lib/screens/detection_screen.dart) | Camera lifecycle, permission UI, frame dispatch, assistive UI (gestures, TTS, priority, controls); light Home-theme chrome (`Theme(buildHomeTheme())` + dark status-bar icons) with a rounded dark `kHomeInk` camera viewport and an inline `AUDIO ON` pill |
| Settings Screen | [`settings_screen.dart`](../lib/screens/settings_screen.dart) | Light Home-theme composition (`Theme(buildHomeTheme())` + dark status-bar icons) with four cards — Preferences, Audio Guidance, Engine & Sensitivity, and a dark `kHomeInk` System Performance card; optional `TelemetryService? telemetry` renders `Avg FPS` / `Avg latency (MS)` / `Avg confidence` (showing `—` when empty/null) with no fabricated accuracy metrics |
| Help Screen | [`help_screen.dart`](../lib/screens/help_screen.dart) | Light, responsive operations + gesture manual; consumes the `buildHomeTheme()` light subtree (scoped to Help only) with `kRadius24` cards and `kHomeShadowSoft` shadows |
| Logs & Reports | [`logs_reports_screen.dart`](../lib/screens/logs_reports_screen.dart) | Overview / Charts / Logs dashboard (researcher-facing) |
| Inference Service | [`inference_isolate.dart`](../lib/services/inference_isolate.dart) | Custom-isolate bridge, persistent worker, runtime introspection, preprocessing, model inference, post-processing (argmax + NMS), backend selection, input rotation |
| Worker Lifecycle | [`inference_worker_lifecycle.dart`](../lib/services/inference_worker_lifecycle.dart) | Generation-safe Custom-worker start, bounded restart/backoff, healthy-budget reset, terminal failure, and disposal guards |
| Engine Coordinator | [`engine_coordinator.dart`](../lib/services/engine_coordinator.dart) | Preferred/active engine state, one-shot fallback, stale-generation filtering, and retry actions |
| Ultralytics Adapter | [`ultralytics_detection_adapter.dart`](../lib/services/ultralytics_detection_adapter.dart) | Maps native YOLO results into the shared `Detection` contract |
| Shared Assistive Controller | [`assistive_detection_controller.dart`](../lib/services/assistive_detection_controller.dart) | Common spatial interpretation, tracking, summaries, TTS, haptics, corrections, telemetry, export, and accessibility state |
| TTS Service | [`tts_service.dart`](../lib/services/tts_service.dart) | Speech scheduling, cooldown, de-duplication, mute, repeat-last |
| Settings Service | [`settings_service.dart`](../lib/services/settings_service.dart) | File-backed persisted settings (JSON) |
| Spatial Analysis | [`spatial_analysis_service.dart`](../lib/services/spatial_analysis_service.dart) | Box → position/priority/approximate proximity (pure, outside pipeline) |
| Haptics Service | [`haptics_service.dart`](../lib/services/haptics_service.dart) | HapticFeedback wrapper respecting Vibration setting |
| Telemetry Service | [`telemetry_service.dart`](../lib/services/telemetry_service.dart) | Session records, samples, aggregates for reports |
| Telemetry Export | [`telemetry_export_service.dart`](../lib/services/telemetry_export_service.dart) | Image-free JSON/CSV export |
| Correction Service | [`correction_service.dart`](../lib/services/correction_service.dart) | Detection correction capture and persistence |
| Object Tracker | [`object_tracker.dart`](../lib/services/object_tracker.dart) | Temporal movement tracking from normalized detections |
| Scene Summary | [`scene_summary_service.dart`](../lib/services/scene_summary_service.dart) | Deterministic scene summaries for quick scan/reporting |
| Gesture Controller | [`gesture_controller.dart`](../lib/services/gesture_controller.dart) | Thesis gesture state machine (single/two-finger-double/three-finger/swipe-down) |
| Model Metadata | [`model_metadata.dart`](../lib/models/model_metadata.dart) | Immutable runtime snapshot of the loaded model (types, shapes, quantization, model type) |
| Model Configuration | [`model_config.dart`](../lib/models/model_config.dart) | Shared runtime artifact, base graph, labels, confidence range/default, and NMS configuration |
| Flatbuffer Scanner | [`tflite_flatbuffer.dart`](../lib/models/tflite_flatbuffer.dart) | Pure-Dart scan of internal tensor types for weight-precision detection |
| Tensor Rotation | [`tensor_rotation.dart`](../lib/models/tensor_rotation.dart) | Pure layout-aware square-tensor rotation/mirroring for NHWC and NCHW buffers |
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
| `tflite_flutter` | ^0.12.1 | Classic Interpreter FFI used only by Custom EyeCue; Android packaging extracts its 1.4.0 native library beside Ultralytics' LiteRT Next runtime without placing duplicate legacy Java APIs on the classpath |
| `flutter_tts` | ^4.2.0 | Text-to-speech audio feedback |
| `flutter_riverpod` | ^3.3.2 | State management (declared, deliberately unused — state uses `ChangeNotifier` + `setState`) |
| `permission_handler` | ^12.0.3 | Camera permission requests |
| `path_provider` | ^2.1.4 | File-backed settings persistence ([`settings_service.dart`](../lib/services/settings_service.dart)) + forensic run directories ([`forensic_log.dart`](../lib/services/forensic_log.dart)) |
| `fl_chart` | ^1.2.0 | Latency/FPS/frequency charts in Logs & Reports ([`charts.dart`](../lib/widgets/charts.dart)) |
| `marionette_flutter` | ^0.6.0 | Debug-only runtime-inspection companion for the Marionette MCP server; initialized in [`main.dart`](../lib/main.dart) via `MarionetteBinding.ensureInitialized()` guarded by `kDebugMode` — never runs in release builds |
| `google_fonts` | ^8.2.1 | Offline IBM Plex Sans typography for the Home-local light theme ([`app_home_theme.dart`](../lib/theme/app_home_theme.dart)); fonts bundled under `assets/fonts/`, runtime fetching disabled |

## AI Pipeline

- **Current unreleased candidate:** `assets/yolov8n_int8_new_metadata.tflite` — the deterministic metadata-enriched runtime artifact generated from the byte-identical base graph `assets/yolov8n_int8_new.tflite`. It has **FLOAT32 runtime I/O with internally quantized tensors** (classified *Weight-Quantized*), input `[1, 3, 640, 640]` (NCHW), and output `[1, 84, 8400]` (84 = 4 box coords + 80 COCO classes, 8400 anchors). The artifact is structurally validated, committed, bundled in the debug APK, and has initial target-device evidence: the exact APK installed successfully and a short live run completed 65 XNNPACK-labelled frames on the Snapdragon 695 phone. The calculated latency mean was 164.8 ms (median 157.7 ms; range 150.2–377.3 ms).
- **Stable v0.2.2 baseline:** `assets/yolov8n.tflite` — FLOAT32 I/O with INT8 weights, input `[1, 640, 640, 3]` (NHWC), output `[1, 84, 8400]`.
- **Model identity:** never assumed from filenames — introspected at runtime into a `ModelMetadata` snapshot.
- **Preprocessing:** Manual YUV420 → RGB conversion, nearest-neighbor resize, writes matched to the input dtype (normalized float, or quantized via input scale/zeroPoint). Runtime shape selects NHWC interleaved or NCHW planar output order. [`tensor_rotation.dart`](../lib/models/tensor_rotation.dart) rotates/mirrors the square tensor to UPRIGHT per orientation metadata.
- **Inference:** One persistent `Interpreter` instance in a dedicated isolate. The candidate attempts explicit XNNPACK with a retained delegate and retries on CPU after recoverable setup/invocation exceptions. A native SIGSEGV remains uncatchable. Raw `ByteBuffer`s are passed to `interpreter.run()` — no reshape, no input-tensor resizing.
- **Post-processing:** Argmax per-box, dequantization only when the output tensor is quantized, the active persisted confidence threshold (default `0.25`), and **class-wise Non-Maximum Suppression (IoU `0.45`)**.
- **Remaining validation:** bilinear interpolation, extended candidate stability/fallback validation, and formal candidate benchmarking remain open. Bounded Custom-worker restart recovery is implemented and deterministically tested; native crash recovery and device stability validation remain outside Dart guarantees.
- **Ultralytics path:** `YOLOView` uses the same metadata-enriched runtime artifact and authoritative COCO labels through the native CameraX/LiteRT pipeline. Its native callbacks are normalized by the adapter before entering the shared assistive layer. Delegate selection and long-duration native stability still require device evidence.

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

1. **Persistent Custom Inference Isolate:** The Custom engine uses one `Isolate.spawn()` at startup and one `Interpreter` instance for the active service lifetime. It never creates/destroys an interpreter per frame; the Ultralytics engine retains its independent native runtime.
2. **Frame Dropping:** Boolean `_isInferring` gate drops frames when the inference worker is busy. No queueing — deterministic latency. The gate is released on isolate errors so the pipeline can recover.
3. **Manual Preprocessing:** Custom YUV420→RGB math avoids the `image` package to prevent GC pressure from real-time video.
4. **Runtime Model Introspection:** After interpreter creation, build a `ModelMetadata` snapshot from the runtime tensors plus an internal tensor-type scan. The interpreter is the single source of truth — nothing is hardcoded.
5. **Dynamic Inference Path:** Preprocessing quantizes only when the input tensor is quantized; post-processing dequantizes only when the output tensor is quantized (scale/zeroPoint from runtime metadata).
6. **Backend safety:** The stable v0.2.2 baseline is CPU-only because of the historical Snapdragon 695 XNNPACK SIGSEGV. The unreleased candidate attempts XNNPACK, retains delegate ownership correctly, and falls back to CPU for recoverable Dart-level failures; the initial short device run completed, but native crash safety still requires longer controlled validation.
7. **Stream-Based Results:** `StreamController.broadcast()` for detection results, enabling multiple listeners.

## Remaining Architectural Boundaries

- **Bounded Custom-worker recovery:** implemented through [`inference_worker_lifecycle.dart`](../lib/services/inference_worker_lifecycle.dart), with one immediate retry, one delayed retry, terminal failure, healthy-budget reset, stale-generation guards, and disposal/backoff safety. Native crashes such as SIGSEGV remain uncatchable by Dart and require device-level validation.
- **No dependency injection framework:** Services are wired in `main.dart` and passed via constructors — simple and sufficient, but not a full DI container.
- **State management:** plain `ChangeNotifier` services + `setState`; Riverpod remains declared but unused (intentionally — the app does not need a framework).
- **Engine-specific services:** `InferenceService` remains intentionally coupled to Custom TFLite/camera internals, while Ultralytics is isolated behind its native screen and result adapter. The shared controller and coordinator prevent engine-specific objects from leaking into common assistive behavior.
- **Configuration:** model paths, labels, confidence bounds/default, and NMS IoU are centralized in [`model_config.dart`](../lib/models/model_config.dart). Detection sensitivity is persisted in [`app_settings.dart`](../lib/models/app_settings.dart) and applied by both engines at startup/reload; it is not a per-frame mutation.
- **Out of scope for the live app:** calibrated distance, validated movement/approach estimation, and accuracy/precision/recall/mAP (require ground truth — see [`thesis-product-status-audit.md`](thesis-product-status-audit.md)).
- **Release boundary:** final Android identity, explicit SDK policy, production signing, signed AAB validation, broad device coverage, formal benchmark evidence, licence approval, and Play release remain separate gates.
