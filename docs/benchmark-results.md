# EyeCue — Benchmark Results

> **No formal candidate benchmark has been collected yet** (the official TFLite benchmark tool has not been run on the target device). The informal values below are historical observations for the stable v0.2.2 CPU/NHWC baseline and must not be attributed to the current NCHW/XNNPACK candidate.
> See [`testing-plan.md`](testing-plan.md) for the benchmark plan, and [`research-notes.md`](research-notes.md) for metric definitions.

---

## Informal On-Device Observations (not formal benchmarks)

Captured live from the app's own telemetry during the v0.2.2 session on the Snapdragon 695 test device (Android 13 / API 33), using the stable CPU-only NHWC path (XNNPACK disabled):

| Metric | Observed |
|--------|----------|
| Avg Detection FPS | ~2.1 |
| Avg Inference Latency | ~606 ms |
| Detections in session | 123 |

These are **informal historical baseline** figures from the app's runtime telemetry (subject to the low-end CPU-only pipeline), not the formal TFLite-benchmark-tool results the thesis requires. They illustrate that the stable CPU-only throughput is far below the ≥15 FPS hypothesis target. An initial, non-formal observation of the current NCHW/XNNPACK candidate is recorded below; it is not a like-for-like benchmark or an accuracy comparison.

---

## Initial Candidate Device Observation (not a formal benchmark)

Captured after device storage was cleared and the exact debug APK was installed on
the target `2201116SG` (Snapdragon 695, Android 13/API 33, `android-arm64`). The
Detection screen loaded `yolov8n_int8_new.tflite`, reported the expected NCHW
FLOAT32 I/O, and created an explicit four-thread XNNPACK interpreter.

| Observation | Result |
|-------------|--------|
| Logged live inference completions | 65 (frames #1–#65) |
| Backend label on completed frames | XNNPACK on all 65 logged completions |
| Per-frame latency, calculated mean | 164.8 ms |
| Per-frame latency, median | 157.7 ms |
| Per-frame latency, range | 150.2–377.3 ms |
| 5-second summary inference FPS | ~5.7–6.2 |
| 5-second summary camera FPS | ~13.9–14.9 |
| Detections in this controlled short run | 0 across the 65 logged frames |
| Separate earlier live observation | 1 `tv` at 67.9% confidence, 113.7 ms |
| Candidate-process fatal signal in captured logs | None observed; process remained alive at capture end |

The run was short and used the app's debug telemetry rather than the official
TFLite benchmark tool. It does not establish model accuracy, thermal or memory
behavior, long-duration XNNPACK stability, a CPU-vs-XNNPACK speedup, or complete
graph delegation. The `tv` observation is evidence that the parser and detection
delivery path can return a live result, not a ground-truth accuracy result.

---

## Benchmark Template

Copy and fill out one table per test configuration.

### Device Information

| Field | Value |
|-------|-------|
| Device Model | |
| SoC (e.g., Snapdragon 695) | |
| Android Version | |
| RAM | |
| Flutter Version | |
| TFLite Version | |

### Model Information

| Field | Value |
|-------|-------|
| Model File | |
| Quantization | |
| Input Shape | |
| Output Shape | |
| Delegate | |

---

### Raw Model Latency (TFLite Benchmark Tool)

| Metric | Value |
|--------|-------|
| Average Inference Time (ms) | |
| Min Inference Time (ms) | |
| Max Inference Time (ms) | |
| Standard Deviation (ms) | |
| Warm-up Time (ms) | |

---

### End-to-End Pipeline Performance

| Metric | Value |
|--------|-------|
| **Detection FPS** (effective) | |
| **Camera Preview FPS** | |
| Inference Latency (ms) | |
| Frame Processing Latency (ms) | |
| Preprocessing Latency (ms) | |
| Post-processing Latency (ms) | |
| Isolate Communication Latency (ms) | |

---

### Resource Usage

| Metric | Value |
|--------|-------|
| Memory Usage (MB) — Idle | |
| Memory Usage (MB) — Active Detection | |
| Memory Usage (MB) — Peak | |
| CPU Usage (%) — Average | |
| CPU Usage (%) — Peak | |
| Battery Consumption (% per minute) | |
| Thermal Observations | |

---

### Notes

<!-- Record any observations about performance, anomalies, or test conditions -->

---

## Historical Results

- **v0.2.2 CPU/NHWC baseline:** informal application telemetry only — approximately 2.1 detection FPS, 606 ms average inference latency, and 123 detections on Android 13/API 33 Snapdragon 695. These values are not formal benchmark results.
- **Current NCHW/XNNPACK candidate:** initial short device observation recorded above after successful installation — 65 XNNPACK-labelled completions, calculated mean latency 164.8 ms, and one separate live `tv` result at 67.9%/113.7 ms. No formal benchmark or accuracy/stability claim is attached to these observations.
