# EyeCue — Implementation Plan

> See also: [`architecture.md`](architecture.md) (system design), [`project-status.md`](project-status.md) (current state), [`implementation-progress.md`](implementation-progress.md) (tracking).

## Long-Term Roadmap

EyeCue is a thesis project evaluating whether on-device object detection can serve as an assistive navigation aid for visually impaired users. The roadmap is structured around thesis milestones: from functional prototype through research data collection to defense readiness.

## Milestones

### Milestone 1: "Audible MVP" (Target: ~2 weeks)

**Definition of Done:**
- TTS speaks detected object names aloud with priority-based cooldown
- Bounding boxes rendered on camera preview via `CustomPainter`
- Error handling in inference isolate (try/catch + error state propagation)
- Permission-denied UI with explanation and settings redirect
- Unused dependencies either wired or removed from `pubspec.yaml`

**Feature Dependencies:**
- TTS depends on: detection stream (already implemented)
- Bounding boxes depend on: detection data (already available), `CustomPainter`
- Error handling depends on: SendPort error protocol

### Milestone 2: "Research-Ready" (Target: ~4 weeks)

**Definition of Done:**
- ~~NMS (Non-Maximum Suppression) for clean multi-object detection~~ — ✅ Implemented 2026-08-01 (class-wise, IoU 0.45, pre-NMS conf 0.25)
- Performance logging: FPS, inference latency, confidence scores, timestamps — ✅ done (5-second summaries + Info Panel metrics + Logs & Reports telemetry)
- Pause/resume detection toggle with camera deactivation — ✅ done (v0.2.0 — single-tap pause/resume via [`gesture_controller.dart`](../lib/services/gesture_controller.dart) + visible controls)
- `fl_chart` logging dashboard for real-time metrics visualization — ✅ done (v0.2.0 — Logs & Reports Overview/Charts/Logs, [`charts.dart`](../lib/widgets/charts.dart))
- Unit tests for core pipeline (YUV→RGB, output parsing, dequantization, NMS) — ✅ 59 passing across navigation, screens, widgets, services, charts, theme
- Adaptive throttling based on measured inference time — 🟡 partial (v0.2.0 Low Power Mode applies a dispatch throttle; formal measured throttling remains)

**Feature Dependencies:**
- ~~NMS~~ — ✅ done; depends on detection list (available)
- Performance logging depends on: NMS (done) + frame/confidence stats (in place)
- Logging dashboard depends on: performance logging, fl_chart
- Unit tests depend on: stable pipeline API

### Milestone 3: "Defense-Ready" (Target: ~6 weeks)

**Definition of Done:**
- Accessibility features: TalkBack/VoiceOver semantics, gesture controls — 🟡 gestures ✅ done (v0.2.0); TalkBack/Semantics polish remaining
- Priority-based TTS queue (person > vehicle > obstacle > other) — ✅ done (v0.2.0 — class-based priority tiers + urgent high-priority bypass in [`tts_service.dart`](../lib/services/tts_service.dart) / [`spatial_analysis_service.dart`](../lib/services/spatial_analysis_service.dart))
- Adaptive throttling fully implemented — 🟡 partial (Low Power Mode dispatch throttle)
- GPU/NNAPI delegate support (if XNNPACK resolved) with fallback to CPU — ❌ (XNNPACK investigation pending)
- Integration tests for end-to-end pipeline — ❌ (unit/widget suite in place)
- Package name fixed to `com.eyecue` — ❌ (still `com.example.eyecue_flutter`)
- `minSdkVersion` set explicitly to thesis-aligned API 29 — 🟡 (currently relies on Flutter default 24)
- All documentation up to date — ✅ (this sync)

**Feature Dependencies:**
- Accessibility depends on: UI elements in place (bounding boxes, labels)
- TTS priority queue depends on: TTS integration (M1), multi-object detection (M2)
- GPU delegate depends on: XNNPACK investigation resolution

### Milestone 4: "Production Candidate" (Target: ~8 weeks)

**Definition of Done:**
- Comprehensive error recovery (isolate restart, model reload)
- Runtime model variant selection
- `TransferableTypedData` optimization for isolate messaging
- Bilinear interpolation for resize quality
- Full test coverage (unit + widget + integration)
- Play Store readiness (signing, privacy policy, content rating)

## Feature Dependencies Map

```
Camera Pipeline (done)
    └── Detection Stream (done)
        ├── TTS Audio (M1)
        │   └── Priority Queue (M3)
        ├── Bounding Boxes (done — M1)
        │   └── Accessibility (M3)
        ├── NMS (done — M2)
        │   └── Performance Logging (done — M2)
        │       └── Logging Dashboard (M2)
        ├── Error Handling (partial — M1)
        │   └── Error Recovery (M4)
        └── Pause/Resume (M2)
            └── Adaptive Throttling (M3)
```

## Current Priorities

1. ~~**TTS Audio Feedback**~~ — ✅ Done (v0.2.0). See [`tts_service.dart`](../lib/services/tts_service.dart).
2. ~~**Bounding Box Overlay**~~ — ✅ Done. See [`bounding_box_painter.dart`](../lib/widgets/bounding_box_painter.dart).
3. ~~**NMS**~~ — ✅ Done (class-wise, IoU 0.45, conf 0.25). See [`inference_isolate.dart`](../lib/services/inference_isolate.dart).
4. **On-device validation of the v0.2.x UI** — gestures, TTS, settings persistence, Logs & Reports on the Snapdragon 695 device
5. **Error Recovery** — Isolate restart on fatal error
6. ~~**Permission-Denied UI**~~ — ✅ Done (v0.2.0). See [`detection_screen.dart`](../lib/screens/detection_screen.dart).
7. **XNNPACK Investigation** — Unlocks faster inference
8. **Orientation re-validation** — back landscape physical hold + front camera
9. **Formal FPS/latency benchmark + accuracy evaluation** — research metrics
