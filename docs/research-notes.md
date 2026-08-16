# EyeCue — Research Notes

> Research papers, benchmark references, related work, ideas, and defense notes.  
> Separate from implementation documentation.

---

## Research Paper

### Current Paper

**Title:** EyeCue: Real-Time On-Device Object Detection for Visually Impaired Navigation

The paper evaluates whether on-device object detection (YOLOv8n TFLite) can serve as an assistive navigation aid. Key evaluation metrics:

- Detection accuracy
- Latency (target: ≤300ms)
- FPS (target: ≥15 FPS)
- Usability (SUS — System Usability Scale)
- Audio responsiveness

> **Note:** The latency and FPS targets are internally inconsistent. 300ms latency implies max ~3.3 FPS throughput. The paper later notes 10 FPS may be adequate. These metrics need redefinition — see Metric Consistency below.

### Key Sections

- Chapter 3: Agile methodology with 4 sprints (mobile app dev, model integration, camera detection, TTS)
- Technology-agnostic methodology — changing React Native → Flutter does not invalidate the research
- Logging system records: confidence, inference time, FPS, timestamps, detections

### Metric Consistency Issue

The paper states:
- Detection speed ≥15 FPS
- Latency ≤300ms
- 303ms latency is "highly efficient"

These are internally inconsistent. If latency is 300ms, max throughput is ~3.3 FPS. Need to redefine:
- **FPS:** Camera preview FPS? Detection FPS? Display FPS?
- **Latency:** End-to-end (capture → speech)? Inference-only? Frame processing?
- **Inference time:** Pure model time? Or preprocessing + inference + post-processing?

See [this discussion in chat_spec.md](../chat_spec.md) for the full analysis.

---

## Related Work

### YOLOv8 on Mobile

- YOLOv8n: ~3.2M params, smallest YOLOv8 variant
- INT8 quantization: ~4× smaller, ~2–4× faster on CPU vs float32
- Typical mobile inference: 30–80ms (CPU), 10–30ms (GPU/NNAPI) depending on hardware
- SiLU activation: not supported by older GPU delegates (Mali, some Adreno drivers)

### TFLite on Android

- **XNNPACK:** CPU acceleration delegate. Crashed on Snapdragon 695 with INT8 YOLOv8n. Root cause unknown.
- **NNAPI:** Android Neural Networks API. Uses device-specific drivers (DSP, GPU, NPU). Compatibility varies by manufacturer.
- **GPU Delegate:** OpenGL ES / OpenCL backend. SiLU support depends on TFLite version and driver.
- **Benchmark tool:** `android_aarch64_benchmark_model` from TFLite tools. Should be used to measure raw model latency.

### Assistive Technology for Visual Impairment

- Existing apps: Seeing AI (Microsoft), Lookout (Google), Be My Eyes
- Most cloud-based solutions have latency and privacy concerns
- On-device approaches are newer; EyeCue's research contribution is evaluating feasibility on consumer hardware

---

## Benchmark References

### To Measure (on Snapdragon 695)

- [ ] Raw model latency via TFLite benchmark tool (all 3 model variants)
- [ ] End-to-end pipeline FPS (camera → inference → UI)
- [ ] Preprocessing latency (YUV→RGB conversion time)
- [ ] Memory usage (heap delta during 5-min continuous detection)
- [ ] Battery consumption (% per minute of active detection)
- [ ] Thermal throttling behavior

### Model Variants Available

> The "quantization" column below reflects **runtime introspection** (see [`implementation-decisions.md`](implementation-decisions.md) §4 / [`inference-tensor-diagnosis.md`](inference-tensor-diagnosis.md)) — never assumed from filenames.

| File | I/O precision | Weights | Notes |
|------|---------------|---------|-------|
| `yolov8n.tflite` | FLOAT32 (in/out) | INT8 (62 tensors) | **Active bundled model** — classified *Weight-Quantized*. Input `[1, 640, 640, 3]`, output `[1, 84, 8400]`. Despite its name it is **not** full INT8. |
| `yolov8n_int8.tflite` | FLOAT32 (in/out) | INT8 (62 tensors) | Same weight-quantized structure; present in `assets/` but **not declared in pubspec** (not loadable at runtime). |
| `yolov8n_int8ReLU.tflite` | — | — | GPU-compatible variant from the React Native prototype; **no longer present** in this repository's `assets/`. |

---

## Ideas & Future Directions

### Short-Term (Thesis Scope)

Status reflects the v0.2.x implementation:

- ~~Priority-based TTS queue: person > vehicle > obstacle > furniture > other~~ — ✅ Implemented (v0.2.0): class-based priority tiers + urgent high-priority bypass in [`tts_service.dart`](../lib/services/tts_service.dart) / [`spatial_analysis_service.dart`](../lib/services/spatial_analysis_service.dart).
- ~~Spatial audio cues: "person on your left" using binaural panning~~ — 🟡 Partially implemented: positional phrasing ("person on your left") via [`spatial_analysis_service.dart`](../lib/services/spatial_analysis_service.dart); binaural panning not done.
- ~~Scan mode vs. alert mode: describe full scene vs. warn only about obstacles~~ — 🟡 Partially implemented: three-finger quick-scan summary exists; full-scene vs alert-only distinction not formalized.
- ~~Gesture-based controls: double-tap to pause, swipe to change mode~~ — ✅ Implemented (v0.2.0): all four thesis gestures (two-finger double-tap start/stop, single-tap pause/resume, three-finger scan, swipe-down repeat) in [`gesture_controller.dart`](../lib/services/gesture_controller.dart).
- Earcon audio feedback: non-verbal sound cues for detection confidence — ❌ Not started.

### Long-Term (Post-Thesis)

- Custom model fine-tuned on assistive-specific classes (crosswalk, stairs, door, curb)
- Depth estimation for distance-to-object reporting
- Optical character recognition (OCR) for reading signs/text
- Offline maps integration for navigation context
- Wearable device support (smart glasses form factor)
- Multi-model pipeline: detection + segmentation + depth

---

## Defense Notes

### Key Arguments

1. **On-device inference preserves privacy** — no cloud dependency, no data leaving the device
2. **Real-time audio feedback** — lower latency than cloud-based alternatives
3. **Technology-agnostic methodology** — framework choice (RN vs Flutter) does not affect research validity
4. **Deterministic behavior over maximum FPS** — consistency matters more than throughput for assistive use

### Potential Panel Questions

- "How can 300ms latency correspond to 15 FPS?" → Redefine metrics clearly
- "Why Flutter instead of native Android?" → Cross-platform, faster UI development, GPU rendering
- "Why not use a cloud API?" → Privacy, offline use, latency
- "How did you validate accuracy?" → COCO pre-trained, qualitative testing with target users
- "What about false positives?" → Confidence threshold, priority-based TTS reduces noise

### Metric Definitions (To Finalize)

| Term | Definition | Unit |
|------|-----------|------|
| Camera FPS | Frames delivered by camera sensor per second | fps |
| Inference FPS | Model inferences completed per second | fps |
| Detection FPS | End-to-end: capture → detection → UI update per second | fps |
| Inference Latency | Time from tensor input to tensor output (model only) | ms |
| Frame Processing Latency | Time from camera frame arrival to detection result | ms |
| End-to-End Latency | Time from photon hitting sensor to TTS audio output | ms |
