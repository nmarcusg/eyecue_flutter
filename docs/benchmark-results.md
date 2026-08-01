# EyeCue — Benchmark Results

> **Template only. No benchmark data has been collected yet.**  
> See [`testing-plan.md`](testing-plan.md) for the benchmark plan.

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

*No benchmarks have been recorded yet. Run the TFLite benchmark tool on the target device and fill out the templates above.*
