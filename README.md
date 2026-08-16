# EyeCue

**Real-time, on-device object detection assistive app for visually impaired users.**

EyeCue captures camera frames, runs them through a YOLOv8n TFLite model, and speaks detected object names aloud via text-to-speech. All inference runs entirely on-device — no internet connection required.

## Status

**Assistive application UI (v0.2.0)** — The core inference pipeline (camera → Isolate → TFLite → argmax → NMS → bounding boxes), device-independent orientation, and forensic logging are validated on-device. The app now has the thesis-aligned application structure: Home / Detect / Settings / Help navigation, **TTS audio guidance** (cooldown + de-duplication + repeat), **thesis gestures** (two-finger double-tap, single tap, three-finger scan, swipe-down repeat), persisted settings (vibration, auto-start, low-power, audio), and a **Logs & Reports** dashboard with charts. The ML pipeline was not modified.

For an honest thesis-product completion baseline, see [`docs/thesis-product-status-audit.md`](docs/thesis-product-status-audit.md) and [`docs/project-status.md`](docs/project-status.md).

## Quick Start

```bash
flutter pub get
flutter run
```

Requires Flutter SDK >=3.12.0, Android API 24+.

## Documentation

All project documentation is in the [`docs/`](docs/) directory:

### Status & Planning

| Document | Purpose |
|----------|---------|
| [`project-status.md`](docs/project-status.md) | Current state, blockers, next steps — **read first** |
| [`architecture.md`](docs/architecture.md) | System design, data flow, component map |
| [`implementation-plan.md`](docs/implementation-plan.md) | Roadmap, milestones, feature dependencies |
| [`implementation-progress.md`](docs/implementation-progress.md) | Completed/in-progress/remaining work |
| [`implementation-decisions.md`](docs/implementation-decisions.md) | Key engineering decisions and rationale |
| [`known-issues.md`](docs/known-issues.md) | Blockers, technical debt, bugs |
| [`testing-plan.md`](docs/testing-plan.md) | Unit, widget, integration, and manual testing |
| [`benchmark-results.md`](docs/benchmark-results.md) | Performance measurement template |
| [`development-workflow.md`](docs/development-workflow.md) | Session checklist for developers and AI agents |
| [`session-log.md`](docs/session-log.md) | Per-session log of objectives, progress, and decisions |
| [`changelog.md`](docs/changelog.md) | Human-readable version history |
| [`research-notes.md`](docs/research-notes.md) | Papers, benchmarks, ideas, defense notes |

### Investigations & Diagnosis

| Document | Purpose |
|----------|---------|
| [`camera-path-forensics.md`](docs/camera-path-forensics.md) | Live-camera path forensics — orientation defect isolated & fixed |
| [`static-image-test.md`](docs/static-image-test.md) | Static-image ground-truth test (camera removed) |
| [`input-pipeline-investigation.md`](docs/input-pipeline-investigation.md) | "max confidence ≈ 0.05" input-side forensics |
| [`inference-pipeline-probe.md`](docs/inference-pipeline-probe.md) | "Objects: 0" parser-side forensics (graph-verified) |
| [`inference-tensor-diagnosis.md`](docs/inference-tensor-diagnosis.md) | Tensor-handling crash diagnosis (reshape/ByteBuffer) |
| [`phase1-preprocessing-diagnosis.md`](docs/phase1-preprocessing-diagnosis.md) | Preprocessing health after the converter fix |
| [`painter-coordinate-review.md`](docs/painter-coordinate-review.md) | Painter ↔ preview coordinate-space math review |
| [`orientation-design-review.md`](docs/orientation-design-review.md) | Orientation architecture design review |
| [`orientation-implementation.md`](docs/orientation-implementation.md) | Orientation implementation summary & validation |

### Historical Records

- [`chat_spec.md`](chat_spec.md) — Full conversation history and original specification (~3100 lines). Canonical reference. Do not modify.
- [`auditor.md`](auditor.md) — Comprehensive project audit (2026-07-22).

## Tech Stack

| Layer | Technology |
|-------|-----------|
| Framework | Flutter/Dart |
| ML Inference | TFLite via `tflite_flutter` |
| Model | YOLOv8n (FLOAT32 I/O, INT8 weights — weight-quantized; 80 COCO classes) |
| Camera | `camera` plugin (YUV420, low resolution) |
| TTS | `flutter_tts` (wired via `TtsService`) |
| State | `ChangeNotifier` services + `setState` (Riverpod declared, unused) |
| Reports | `fl_chart` (latency/FPS/frequency charts in Logs & Reports), forensic file logging (active) |
| Platforms | Android (primary, per thesis), iOS, Linux, macOS, Windows, Web (bootstrapped) |

## Project Structure

```
lib/
├── main.dart                          # App entry, theme, service wiring
├── navigation/
│   └── app_shell.dart                 # 4-tab bottom nav (Home/Detect/Settings/Help)
├── models/
│   ├── detection.dart                 # Detection data class
│   ├── detection_info.dart            # Spatial/priority/proximity info
│   ├── app_settings.dart              # Persisted settings model
│   ├── box_transform.dart             # Device-independent orientation math
│   ├── model_metadata.dart            # Runtime model introspection snapshot
│   ├── tflite_flatbuffer.dart         # Pure-Dart flatbuffer tensor-type scanner
│   └── png_encoder.dart               # Pure-Dart PNG encoder (forensic dumps)
├── screens/
│   ├── home_screen.dart               # Home: branding, status card, Go to Live Camera
│   ├── detection_screen.dart          # Detection: assistive UI + camera/inference pipeline
│   ├── settings_screen.dart           # Settings: haptics/performance/audio/research
│   ├── help_screen.dart               # Help & Gestures manual
│   └── logs_reports_screen.dart       # Logs & Reports dashboard
├── services/
│   ├── inference_isolate.dart         # Isolate bridge + inference + preprocessing
│   ├── tts_service.dart               # TTS queue, cooldown, de-duplication, mute, repeat
│   ├── settings_service.dart          # File-backed persisted settings (JSON)
│   ├── spatial_analysis_service.dart  # Box → position/priority/proximity (pure)
│   ├── haptics_service.dart           # HapticFeedback wrapper
│   ├── telemetry_service.dart         # Session telemetry + aggregates
│   ├── gesture_controller.dart        # Thesis gesture state machine (pure)
│   ├── forensic_log.dart              # File-based structured diagnostics
│   ├── inference_probe.dart           # Parser probe (disabled)
│   └── input_probe.dart               # Input pipeline probe (disabled)
└── widgets/
    ├── bounding_box_painter.dart      # Bounding box CustomPainter overlay
    ├── gesture_surface.dart           # Transparent gesture capture layer
    ├── detection_card.dart            # Object card (class/conf/position/priority)
    ├── priority_badge.dart            # HIGH/MEDIUM/LOW badge
    ├── warning_banner.dart            # High-priority obstacle banner
    ├── status_pill.dart               # Detecting/Paused/Stopped indicator
    ├── accessible_button.dart         # Large high-contrast button (48dp+)
    ├── charts.dart                    # fl_chart latency/FPS/frequency charts
    ├── debug_overlay.dart             # Debug HUD (retained, unused)
    └── info_panel.dart                # Old metrics panel (unused in primary UI)

tool/
├── validate_flatbuffer.dart           # CLI: validates the flatbuffer scanner
├── validate_png.dart                  # CLI: validates the PNG encoder
├── dump_graph_tail.py                 # CLI: dumps TFLite graph tail ops
└── dump_decode_consts.py              # CLI: dumps decode constants
```

## License

Thesis project — not yet licensed for distribution.
