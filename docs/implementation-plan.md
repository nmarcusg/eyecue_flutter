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
- NMS (Non-Maximum Suppression) implemented for clean multi-object detection
- Performance logging: FPS, inference latency, confidence scores, timestamps
- Pause/resume detection toggle with camera deactivation
- `fl_chart` logging dashboard for real-time metrics visualization
- Unit tests for core pipeline (YUV→RGB, output parsing, dequantization)
- Adaptive throttling based on measured inference time

**Feature Dependencies:**
- NMS depends on: detection list (already available)
- Performance logging depends on: NMS (for meaningful per-frame metrics)
- Logging dashboard depends on: performance logging, fl_chart
- Unit tests depend on: stable pipeline API

### Milestone 3: "Defense-Ready" (Target: ~6 weeks)

**Definition of Done:**
- Accessibility features: TalkBack/VoiceOver semantics, gesture controls
- Priority-based TTS queue (person > vehicle > obstacle > other)
- Adaptive throttling fully implemented
- GPU/NNAPI delegate support (if XNNPACK resolved) with fallback to CPU
- Integration tests for end-to-end pipeline
- Package name fixed to `com.eyecue`
- `minSdkVersion` set to 24 explicitly
- All documentation up to date

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
        ├── Bounding Boxes (M1)
        │   └── Accessibility (M3)
        ├── NMS (M2)
        │   └── Performance Logging (M2)
        │       └── Logging Dashboard (M2)
        ├── Error Handling (M1)
        │   └── Error Recovery (M4)
        └── Pause/Resume (M2)
            └── Adaptive Throttling (M3)
```

## Current Priorities

1. **TTS Audio Feedback** — Makes the app functional as an assistive tool
2. **Bounding Box Overlay** — Visual confirmation of detections
3. **Error Handling** — Prevents silent crashes
4. **Permission-Denied UI** — Basic UX completeness
5. **XNNPACK Investigation** — Unlocks faster inference
