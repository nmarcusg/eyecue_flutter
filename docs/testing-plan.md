# EyeCue — Testing Plan

> See also: [`architecture.md`](architecture.md) (system design), [`implementation-progress.md`](implementation-progress.md) (what's built).

> **Current suite:** `flutter test` → **77 passing**, `flutter analyze` → **0 issues**. Existing automated coverage lives in [`test/`](../test/): navigation shell, screen smoke tests, widgets (priority badge, detection card, warning banner, accessible button, charts), services (TTS, settings, spatial, telemetry, gesture controller), theme regression, NHWC/NCHW tensor-rotation tests, engine-setting persistence, per-engine telemetry, and Ultralytics-result adaptation. The 59-test v0.2.2 suite remains the release baseline; the tables below are the forward-looking plan (not all items are automated yet).

## Unit Testing Strategy

### Core Pipeline Tests (Critical Path)

| Test | Priority | Description |
|------|----------|-------------|
| TFLite model loading | 🔴 P0 | Verify `Interpreter.fromBuffer()` loads without crash; check input/output tensor metadata |
| YUV→RGB conversion correctness | 🔴 P0 | Verify against known test image with pre-computed RGB output |
| YOLOv8 output parsing | 🔴 P0 | Verify argmax with pre-computed synthetic tensor; check class ID, confidence, bounding box |
| INT8 dequantization | 🔴 P0 | Verify scale/zeroPoint math against known values |
| Label loading | 🟢 P2 | Verify 80 COCO labels parsed correctly from `labels.txt` |
| NHWC/NCHW detection | 🟢 P2 | Test channel-order heuristic with both layout types |
| NHWC/NCHW tensor rotation | 🟢 P2 | Verify identity, 90°/180°/270°, mirror, buffer guards, and logical equivalence across interleaved and planar layouts — ✅ 14 unit tests |
| Detection model serialization | 🟢 P2 | Verify `Detection` class JSON serialization/deserialization |

### Inference Isolate Tests

| Test | Priority | Description |
|------|----------|-------------|
| Isolate spawn and communication | 🟡 P1 | Verify SendPort/ReceivePort message passing works |
| Frame dropping logic | 🟡 P1 | Verify `_isInferring` gate prevents concurrent inference |
| Error propagation | 🟡 P1 | Verify isolate errors are sent to main isolate |
| Buffer reuse | 🟢 P2 | Verify pre-allocated buffers are reused (no new allocations per frame) |

## Widget Testing Strategy

| Test | Priority | Description |
|------|----------|-------------|
| Detection screen renders | 🟡 P1 | Verify camera preview widget mounts |
| Detection overlay renders | 🟡 P1 | Verify `CustomPainter` draws boxes correctly |
| Permission-denied UI | 🟡 P1 | Verify fallback UI renders when permission is denied |
| Loading state UI | 🟢 P2 | Verify loading spinner renders during camera init |
| Error state UI | 🟡 P1 | Verify error message renders on isolate failure |
| Pause/resume button | 🟢 P2 | Verify toggle changes detection state |
| Screen/navigation smoke tests | ✅ | Home / Settings / Help screens + 4-tab shell (implemented) |
| Assistive widgets | ✅ | Priority badge, detection card, warning banner, accessible button (implemented) |
| Charts | ✅ | Latency/FPS/frequency chart bounds incl. empty/very-high/constant data (implemented) |

## Integration Testing Strategy

| Test | Priority | Description |
|------|----------|-------------|
| Camera → Isolate → Detection pipeline | 🔴 P0 | End-to-end: start camera, receive frame, run inference, get detections |
| Detection → TTS pipeline | 🟡 P1 | End-to-end: detection triggers speech |
| Camera permission flow | 🟡 P1 | Full flow: request → grant → initialize; request → deny → fallback UI |
| Isolate lifecycle | 🟡 P1 | Spawn at startup, survive multiple inferences, dispose on app exit |
| Model swap | 🟢 P2 | Dynamic tensor shape query handles different model shapes |
| Engine switch | 🟡 P0 | One-device bidirectional smoke pass completed after fixing a late-result disposal race; repeated/rotated/background lifecycle coverage remains |
| Ultralytics native path | 🟡 P0 | On-device camera → native preprocessing/inference/NMS → EyeCue adapter/cards ran on Snapdragon 695; controlled TTS/telemetry/delegate validation remains |

## Manual Testing Checklist

### Camera & Preview
- [ ] Camera preview is smooth (no visible stuttering)
- [ ] Camera initializes within 2 seconds on cold start
- [ ] Camera preview orientation matches device orientation
- [ ] Preview fills screen correctly on different aspect ratios

### Inference
- [x] Both engine modes load the same model and thresholds — shared configuration plus APK/device smoke verification
- [ ] Switching engines does not leave the camera occupied or duplicate speech
- [ ] Detection FPS meets or exceeds target on test device
- [ ] Inference does not cause camera preview hitching
- [ ] Detections are reasonably accurate (qualitative assessment)
- [ ] No memory leaks during sustained use (>5 minutes)

### Audio Feedback (TTS implemented v0.2.0)
- [x] TTS speaks detected objects clearly — ✅ implemented (`tts_service.dart`), dedicated on-device audio validation pending
- [x] TTS does not overlap/spam (cooldown works) — ✅ cooldown + same-label de-duplication implemented
- [ ] TTS latency from detection to speech is acceptable
- [ ] TTS works with screen reader (TalkBack) active

### Accessibility
- [ ] All interactive elements have TalkBack labels
- [ ] Gesture controls work (double-tap, swipe)
- [ ] High-contrast mode is readable
- [ ] App is fully navigable without vision

### Error Handling
- [ ] Camera permission denied → shows explanation UI
- [ ] Model fails to load → shows error UI
- [ ] Inference crashes → app recovers gracefully
- [ ] Device rotation → no state loss

## Benchmark Plan

See [`benchmark-results.md`](benchmark-results.md) for the recording template.
For the two selectable runtime modes, follow the paired protocol in [`dual-inference-engine-test.md`](dual-inference-engine-test.md).

### Required Benchmarks

1. **Raw Model Latency:** Run each declared model candidate through the TFLite benchmark tool on the target device; the current NCHW/XNNPACK candidate has initial short-run device evidence, but has not yet received a formal benchmark
2. **End-to-End Pipeline FPS:** Measure detection FPS on target device under sustained use
3. **Preprocessing Latency:** Profile YUV→RGB conversion time
4. **Memory Usage:** Monitor heap usage during 5-minute continuous detection
5. **Battery Consumption:** Measure battery drain per minute of active detection
6. **Thermal Behavior:** Record device temperature during sustained use

## Validation Steps for Major Features

### Feature: TTS Audio Feedback
1. Start app → point camera at a person → verify "person" is spoken within 500ms
2. Point camera at multiple objects → verify highest-confidence object is spoken
3. Keep camera on same object → verify TTS cooldown prevents spam
4. Switch objects → verify new object is spoken immediately

### Feature: Bounding Box Overlay
1. Start app → verify boxes appear over detected objects
2. Move camera → verify boxes track objects smoothly
3. Multiple objects → verify multiple distinct boxes (one per object — class-wise NMS at IoU 0.45 suppresses duplicates)
4. Box scaling → verify boxes are correctly positioned regardless of preview size

### Feature: Error Recovery
1. Force model load failure → verify error UI appears
2. Force inference crash → verify isolate restarts automatically
3. Force camera disconnect → verify app handles gracefully

### Feature: Performance Logging
1. Enable logging → verify FPS, latency, and confidence are recorded — ✅ telemetry records these (v0.2.0)
2. Export logs → verify data is in parseable format (JSON/CSV) — ❌ export not yet implemented
3. Dashboard → verify `fl_chart` renders real-time metrics — ✅ Logs & Reports Overview/Charts/Logs (v0.2.0–v0.2.2)
