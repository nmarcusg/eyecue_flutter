# EyeCue

**Real-time, on-device object detection assistive app for visually impaired users.**

EyeCue captures camera frames, runs them through a YOLOv8n TFLite model, and speaks detected object names aloud via text-to-speech. All inference runs entirely on-device — no internet connection required.

## Status

**Early Prototype (~50% complete)** — Core inference pipeline, bounding box overlay, and debug instrumentation are functional. Error reporting in the inference isolate is partially implemented. TTS, NMS, and permission-denied UI are not yet implemented.

See [`docs/project-status.md`](docs/project-status.md) for current status and blockers.

## Quick Start

```bash
flutter pub get
flutter run
```

Requires Flutter SDK >=3.12.0, Android API 24+.

## Documentation

All project documentation is in the [`docs/`](docs/) directory:

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

### Historical Records

- [`chat_spec.md`](chat_spec.md) — Full conversation history and original specification (~3100 lines). Canonical reference. Do not modify.
- [`auditor.md`](auditor.md) — Comprehensive project audit (2026-07-22).

## Tech Stack

| Layer | Technology |
|-------|-----------|
| Framework | Flutter/Dart |
| ML Inference | TFLite via `tflite_flutter` |
| Model | YOLOv8n (INT8 quantized, 80 COCO classes) |
| Camera | `camera` plugin (YUV420, low resolution) |
| TTS | `flutter_tts` (declared, not yet wired) |
| State | `flutter_riverpod` (declared, not yet wired) |
| Platforms | Android (primary), iOS, Linux, macOS, Windows, Web |

## Project Structure

```
lib/
├── main.dart                          # App entry point
├── models/detection.dart              # Detection data class
├── screens/camera_screen.dart         # Camera + orchestration + debug overlay
├── services/inference_isolate.dart    # Isolate bridge + inference + logging
└── widgets/
    ├── bounding_box_painter.dart      # Bounding box CustomPainter overlay
    └── debug_overlay.dart             # Debug HUD (debug builds only)
```

## License

Thesis project — not yet licensed for distribution.
