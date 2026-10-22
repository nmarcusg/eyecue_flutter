# EyeCue

**Real-time, on-device object detection assistive app for visually impaired users.**

EyeCue captures camera frames, runs them through a YOLOv8n TFLite model, and speaks detected object names aloud via text-to-speech. All inference runs entirely on-device — no internet connection required.

> **Platform:** EyeCue is **Android-only** (per the thesis). It is intended for Android smartphones and does **not** support iOS, web, Windows, macOS, or Linux; their scaffolding has been removed.

## Status

**Stable release: v0.2.2** — The documented release contains the thesis-aligned application structure: Home / Detect / Settings / Help navigation, **TTS audio guidance** (cooldown + de-duplication + repeat), **thesis gestures** (two-finger double-tap, single tap, three-finger scan, swipe-down repeat), persisted settings (vibration, auto-start, low-power, audio), and a **Logs & Reports** dashboard with charts. Its CPU-only, NHWC inference baseline was validated on the Snapdragon 695 test device.

The current branch replaces the dual-engine candidate with a **single native detection engine** (`ultralytics_yolo`) plus an **optional monocular-depth model** that estimates metric distance (see [`docs/mde-integration.md`](docs/mde-integration.md)). The Custom EyeCue Dart/TFLite engine, `tflite_flutter` and the Gradle classic-LiteRT workaround were removed. Detection uses the metadata-enriched `yolov8n_int8_new_metadata.tflite` artifact and the authoritative `labels.txt`; the depth model is `yolo26n-depth`, downloaded by the plugin on first use. Distance is an **estimate**, not a calibrated measurement; no FPS, latency or depth-accuracy figure is claimed without a device run.

Verification on this branch: `dart format` clean, `flutter analyze` reports only 4 pre-existing issues, `flutter test` reports **452 passing and 1 pre-existing failure** (the failing TTS reconciliation test also fails on `dev@94f74d8`), and `flutter build apk --release` produces an 82.9 MB APK. **No Android device was attached**, so runtime behaviour, depth accuracy and performance remain unverified. Dated totals are recorded in [`docs/session-log.md`](docs/session-log.md).

### Unreleased on-device speech changes (Workstream 1)

Workstream 1 was developed on `fix/tts-lifecycle-arbitration` and merged to `dev` through PR #5 at `665b59b` on 2026-10-17; it remains unreleased and replaces the former fire-and-forget TTS scheduler with a **lifecycle-aware safety alert arbiter**:

- one utterance in flight at a time, plus a **single** pending request (higher priority replaces lower; newest replaces oldest at equal priority);
- accepted-alert history and cooldowns are written **only from a confirmed `onStart`**, never from the moment a decision is made;
- completion, cancellation, drop and failure are distinct terminal states, each reconciled from a **paired** platform signal (`onComplete` + result `1`, `onCancel` + result `0`);
- a bounded recovery + quiet-period quarantine handles missing lifecycle signals;
- `AlertPolicy` keys identity on track ID (label only as a fallback), so two different people are independently eligible;
- wayfinding (destination/boundary phrases) is advisory: accepted only while the scheduler is truly idle, never queued behind Detection speech, and never replaces the Detection utterance replayed by repeat-last;
- parked decisions are revalidated semantically before speaking, and a same-track escalation (`stable/unknown` to `approaching`, proximity-band increase, centre entry, or box growth) re-alerts inside the ordinary suppression window;
- preemption is limited to imminent safety and to a **distinct** equal-priority track that is suddenly approaching; a preemption cooldown plus per-submission guards prevent repeated frames from churning the engine.

**Limits and verification.** `flutter_tts` exposes **no utterance identifier**, so callbacks are correlated by strict serialization and paired signals; the recovery quiet period is a bounded mitigation, not an absolute guarantee against a very late native callback. Alert-latency telemetry is implemented in the unreleased Workstream 2 candidate as bounded lifecycle records, cumulative scheduler counters, and eight per-engine interval summaries exported in schema v2 (see [`telemetry-data-dictionary.md`](docs/telemetry-data-dictionary.md)); the Ultralytics interval is `app-side / post-inference` only, physical audible-warning latency remains unmeasured, and per-frame inference timing must not be read as speech latency. Tests exist for this work but have **not** been executed since the relocation or since the PR #5 merge; `flutter analyze`, Gradle and builds were not run either, and no physical-device TTS validation was performed after the merge. Real Android callback ordering, cancellation timing and total audible-warning latency remain unmeasured on device. EyeCue is **not** proven safe for independent navigation.

Fresh settings default to **Ultralytics**. An explicit persisted **Custom EyeCue** choice is preserved, and Custom remains available as the bounded Advanced/compatibility fallback. Detection sensitivity is also persisted through shared presets or the bounded advanced threshold range; both engines apply the selected value when they start or reload.

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
| [`mde-integration.md`](docs/mde-integration.md) | Monocular depth distance estimation: model, coordinates, cadence, settings matrix, licences |
| [`implementation-plan.md`](docs/implementation-plan.md) | Roadmap, milestones, feature dependencies |
| [`app-only-implementation-plan.md`](docs/app-only-implementation-plan.md) | Detailed status and acceptance criteria for the 15 original repository-owned app task areas; runtime work is complete and release engineering remains gated |
| [`implementation-progress.md`](docs/implementation-progress.md) | Completed/in-progress/remaining work |
| [`implementation-decisions.md`](docs/implementation-decisions.md) | Key engineering decisions and rationale |
| [`known-issues.md`](docs/known-issues.md) | Blockers, technical debt, bugs |
| [`testing-plan.md`](docs/testing-plan.md) | Unit, widget, integration, and manual testing |
| [`benchmark-results.md`](docs/benchmark-results.md) | Performance measurement template |
| [`telemetry-data-dictionary.md`](docs/telemetry-data-dictionary.md) | Stable JSON/CSV telemetry fields, units, and privacy boundaries |
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
- [`comprehensive-project-assessment-2026-08-21.md`](docs/comprehensive-project-assessment-2026-08-21.md) — Point-in-time technical and performance assessment of revision `146c2e7`; it predates the current unreleased model/backend candidate.

## Tech Stack

| Layer | Technology |
|-------|-----------|
| Framework | Flutter/Dart |
| ML Inference | Custom LiteRT via `tflite_flutter`; optional native path via `ultralytics_yolo` |
| Model | YOLOv8n candidate (FLOAT32 I/O, INT8 weights — weight-quantized; 80 COCO classes) |
| Camera | `camera` plugin (YUV420, low resolution) |
| TTS | `flutter_tts` (wired via `TtsService`) |
| State | `ChangeNotifier` services + `setState` (Riverpod declared, unused) |
| Reports | `fl_chart` (latency/FPS/frequency charts in Logs & Reports), forensic file logging (active) |
| Platforms | **Android only** (per thesis). iOS, desktop (Windows/macOS/Linux), and web are out of scope — their scaffolding was removed |

## Project Structure

```
lib/
├── main.dart                          # App entry, theme, service wiring
├── navigation/
│   └── app_shell.dart                 # 4-tab bottom nav (Home/Detect/Settings/Help)
├── models/
│   ├── detection.dart                 # Detection data class
│   ├── detection_info.dart            # Spatial/priority/proximity info
│   ├── detection_correction.dart      # Versioned correction record
│   ├── detection_failure.dart         # Typed runtime failure model
│   ├── detection_runtime_state.dart   # Shared runtime states and failures
│   ├── engine_runtime_selection.dart  # Engine selection snapshot
│   ├── inference_lifecycle_event.dart # Recovery event payload (telemetry)
│   ├── app_settings.dart              # Persisted settings (incl. distance/overlays)
│   ├── box_transform.dart             # Device-independent orientation math
│   ├── tflite_flatbuffer.dart         # Pure-Dart flatbuffer tensor-type scanner
│   ├── telemetry_export.dart           # Versioned JSON/CSV export DTOs
│   └── tracked_detection.dart          # Timestamped motion state
├── screens/
│   ├── home_screen.dart               # Home: branding, status card, Go to Live Camera
│   ├── engine_detection_screen.dart   # Mounts the single detection engine
│   ├── ultralytics_detection_screen.dart # Detection UI, streaming data, MDE layers
│   ├── settings_screen.dart           # Settings: haptics/performance/audio/research
│   ├── help_screen.dart               # Help & Gestures manual
│   └── logs_reports_screen.dart       # Logs & Reports dashboard
├── services/
│   ├── assistive_detection_controller.dart # Shared normalized detection behavior
│   ├── engine_coordinator.dart         # Shared Detection lifecycle/status source
│   ├── ultralytics_detection_adapter.dart # Native result → Detection mapping
│   ├── depth_distance_service.dart    # Pure depth sampling, bands, EMA, staleness
│   ├── monocular_depth_estimator.dart  # Second YOLO instance + 500 ms scheduler
│   ├── tts_service.dart               # Lifecycle-aware speech arbiter: one in-flight
│   │                                  #   utterance, one pending request, preemption,
│   │                                  #   wayfinding, repeat-last
│   ├── alert_policy.dart              # Track-aware risk policy: identity, escalation,
│   │                                  #   pending-decision revalidation
│   ├── settings_service.dart          # File-backed persisted settings (JSON)
│   ├── spatial_analysis_service.dart  # Box → position/priority/proximity (pure)
│   ├── haptics_service.dart           # HapticFeedback wrapper
│   ├── telemetry_service.dart         # Session telemetry + aggregates
│   ├── telemetry_export_service.dart  # Image-free JSON/CSV export
│   ├── correction_service.dart        # Correction capture and records
│   ├── object_tracker.dart             # Cross-frame motion estimates
│   ├── scene_summary_service.dart      # Deterministic alert/scan summaries
│   └── gesture_controller.dart        # Thesis gesture state machine (pure)
└── widgets/
    ├── bounding_box_painter.dart      # Bounding box CustomPainter overlay
    ├── gesture_surface.dart           # Transparent gesture capture layer
    ├── detection_card.dart            # Object card (class/conf/position/priority)
    ├── priority_badge.dart            # HIGH/MEDIUM/LOW badge
    ├── warning_banner.dart            # High-priority obstacle banner
    ├── status_pill.dart               # Detecting/Paused/Stopped indicator
    ├── accessible_button.dart         # Large high-contrast button (48dp+)
    ├── detection_state_panel.dart      # Shared loading/error/recovery panel
    ├── detection_correction_sheet.dart # Correct/incorrect/unsure workflow
    ├── charts.dart                    # fl_chart latency/FPS/frequency charts
    ├── depth_heatmap_view.dart        # Rotated, centre-cropped depth heatmap
    └── info_panel.dart                # Old metrics panel (unused in primary UI)

tool/
├── validate_flatbuffer.dart           # CLI: validates the flatbuffer scanner
└── package_ultralytics_metadata.dart  # CLI: appends metadata to a base graph
```

## License

Thesis project — not yet licensed for distribution beyond its dependencies' terms. `ultralytics_yolo` and the YOLO26n weights are **AGPL-3.0**, so distributing the app requires releasing the complete corresponding source under AGPL-3.0. The third-party notices and the AGPL-compatibility statement are in [`docs/mde-integration.md`](docs/mde-integration.md#third-party-notices).
