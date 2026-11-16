# EyeCue — Research Notes

> Research papers, benchmark references, related work, ideas, and defense notes.  
> Separate from implementation documentation.

> **Current implementation note (local `main`, 2026-11-16):** the bundled
> detector is the 14-class campus model and the optional depth asset is
> `yolo26n-depth`; both run through the native Ultralytics plugin. Older YOLOv8
> artifact measurements and thesis targets below are historical planning/evidence,
> not claims about the current model. No current-model accuracy or benchmark
> result is recorded here.
---

## Research Paper

### Existing thesis draft (model description is historical)

**Title:** EyeCue: Real-Time On-Device Object Detection for Visually Impaired Navigation

The existing draft describes YOLOv8n TFLite; that model description predates the current campus detector. Its research questions and proposed metrics remain draft material, not current implementation evidence:

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

- **XNNPACK:** CPU acceleration delegate. The older stable YOLOv8n path crashed on the Snapdragon 695; root cause remains unknown. The replacement NCHW candidate has initial short-run XNNPACK evidence on that device, but longer stability and comparative performance are not established.
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

- [ ] Raw model latency via TFLite benchmark tool (all available model variants)
- [ ] End-to-end pipeline FPS (camera → inference → UI)
- [ ] Preprocessing latency (YUV→RGB conversion time)
- [ ] Memory usage (heap delta during 5-min continuous detection)
- [ ] Battery consumption (% per minute of active detection)
- [ ] Thermal throttling behavior

### Historical model artifacts (not current runtime assets)

> The following table records older YOLOv8 artifacts. They are not bundled by
> current `pubspec.yaml`; measurements are historical and should not be used as
> current-model results.

| File | I/O precision | Weights / internal types | Notes |
|------|---------------|--------------------------|-------|
| `yolov8n_int8_new_metadata.tflite` | FLOAT32 (in/out) | INT8 (356), INT32 (90), FLOAT32 (2) | **Historical NCHW/XNNPACK candidate** — generated from the byte-identical base graph `yolov8n_int8_new.tflite`; classified *Weight-Quantized*. Input `[1, 3, 640, 640]` (NCHW), output `[1, 84, 8400]`. Previously declared in `pubspec.yaml`; not a current runtime asset. |
| `yolov8n.tflite` | FLOAT32 (in/out) | INT8 (62 tensors) | **Historical v0.2.2 baseline** — classified *Weight-Quantized*. Input `[1, 640, 640, 3]` (NHWC), output `[1, 84, 8400]`. Despite its name it is **not** full INT8. |
| `yolov8n_int8.tflite` | FLOAT32 (in/out) | INT8 (62 tensors) | Same weight-quantized structure; historical artifact; absent from the current runtime bundle. |
| `yolov8n_int8ReLU.tflite` | — | — | GPU-compatible variant from the React Native prototype; **no longer present** in this repository's `assets/`. |

### Current model evidence boundary

The current campus artifact identity, size, labels, and provenance note are in
[`model-assets.md`](model-assets.md). Historical short-run measurements for the
older NCHW/XNNPACK candidate are retained in [`benchmark-results.md`](benchmark-results.md);
they do not measure the campus detector. Accuracy, latency, thermal/memory
behaviour, and broad-device validation for the current model remain open in the
available records.

---

## Ideas & Future Directions

### Short-Term (Thesis Scope)

This list records a mixture of older thesis planning and implemented features; check current source before treating any status as a present-day roadmap:

- ~~Priority-based TTS queue: person > vehicle > obstacle > furniture > other~~ — ✅ Implemented (v0.2.0): class-based priority tiers + urgent high-priority bypass in [`tts_service.dart`](../lib/services/tts_service.dart) / [`spatial_analysis_service.dart`](../lib/services/spatial_analysis_service.dart).
- ~~Spatial audio cues: "person on your left" using binaural panning~~ — 🟡 Partially implemented: positional phrasing ("person on your left") via [`spatial_analysis_service.dart`](../lib/services/spatial_analysis_service.dart); binaural panning not done.
- ~~Scan mode vs. alert mode: describe full scene vs. warn only about obstacles~~ — 🟡 Partially implemented: three-finger quick-scan summary exists; full-scene vs alert-only distinction not formalized.
- ~~Gesture-based controls: double-tap to pause, swipe to change mode~~ — ✅ Implemented (v0.2.0): all four thesis gestures (two-finger double-tap start/stop, single-tap pause/resume, three-finger scan, swipe-down repeat) in [`gesture_controller.dart`](../lib/services/gesture_controller.dart).
- Earcon audio feedback: non-verbal sound cues for detection confidence — ❌ Not started.

### Long-Term (Post-Thesis)

- Custom model fine-tuned on assistive-specific classes (crosswalk, stairs, door, curb)
- Depth estimation for distance-to-object reporting — implemented as optional MDE; calibration and device validation remain open
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
- "Why Flutter with Android as the supported platform?" → Explain the project decision from its dated rationale; do not claim current multi-platform support.
- "Why not use a cloud API?" → Privacy, offline use, latency
- "How did you validate accuracy?" → The current detector is campus-trained. The repository records no application-level accuracy metrics or target-user results; do not present model metadata or engineering checks as an accuracy result.
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
