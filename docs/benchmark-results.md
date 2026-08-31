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

These are **informal historical baseline** figures from the app's runtime telemetry (subject to the low-end CPU-only pipeline), not the formal TFLite-benchmark-tool results the thesis requires. They illustrate that the stable CPU-only throughput is far below the ≥15 FPS hypothesis target. No comparison with the current NCHW/XNNPACK candidate is available because the candidate APK was not installed successfully.

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
- **Current NCHW/XNNPACK candidate:** no runtime result. APK installation was blocked by `INSTALL_FAILED_INSUFFICIENT_STORAGE`; run the benchmark only after the exact candidate build is installed and verified.
