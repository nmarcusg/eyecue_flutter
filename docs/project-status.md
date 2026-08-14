# EyeCue — Project Status

> **Last Updated:** 2026-08-14
> See also: [`implementation-progress.md`](implementation-progress.md) (detailed progress), [`known-issues.md`](known-issues.md) (blockers).

## Overall Progress: ~60%

The core inference pipeline — camera → Isolate → TFLite → argmax → NMS → UI stream — is functional and architecturally sound. Bounding box overlay, class-wise NMS, full debug instrumentation, **runtime model introspection**, forensic file logging, aspect-correct preview UI, and the **device-independent orientation architecture** are implemented. The last camera-path defect (frames never rotated to device orientation — portrait detections were ~0) is fixed and on-device validated (portrait now 0.91). Error reporting in the isolate is partially complete (the busy gate now recovers on isolate errors). The app is **not yet usable as an assistive tool**: no TTS audio, no isolate restart recovery, no permission-denied UI.

## Current Milestone

**Milestone 1: "Audible MVP"** — Target: ~2 weeks

| Task | Status |
|------|--------|
| TTS speaks detected objects | ❌ Not started |
| Bounding boxes rendered on screen | ✅ Complete |
| Error handling in isolate | 🟡 Partial — try/catch + error propagation done; restart recovery missing |
| Permission-denied UI | ❌ Not started |
| Remove unused dependencies or wire them | ❌ Not started |
| Debug instrumentation & logging | ✅ Complete |
| NMS (class-wise, IoU 0.45, conf 0.25) | ✅ Complete |
| Orientation re-validation (back landscape + front camera) | 🟡 In progress — portrait + static verified; deferred runs pending |

## Current Blocker

**XNNPACK SIGSEGV** — XNNPACK crashes on Snapdragon 695 with the bundled YOLOv8n model (FLOAT32 I/O, INT8 weights). Without hardware acceleration, inference is CPU-bound. Investigation with the official TFLite benchmark tool is needed.

See [`known-issues.md`](known-issues.md) for full blocker details.

## Next Objective

1. **Re-validate orientation on-device** — back-camera landscape physical hold and front-camera portrait/landscape runs (deferred from v0.1.7). See [`orientation-implementation.md`](orientation-implementation.md).
2. Then implement **TTS audio feedback** — the app's entire purpose is to speak detected objects. Without TTS, it's a silent camera viewer. The `flutter_tts` package is already declared as a dependency.

## High-Priority Tasks

| # | Task | Priority |
|---|------|----------|
| 1 | Implement TTS audio feedback | 🔴 Critical |
| 2 | ~~Implement bounding box `CustomPainter`~~ | ✅ Complete |
| 3 | ~~Add error handling to inference isolate~~ | 🟡 Partial — error reporting done; restart recovery remaining |
| 4 | Add permission-denied and error UI states | 🔴 Critical |
| 5 | Investigate XNNPACK SIGSEGV | 🔴 Critical |
| 6 | ~~Implement NMS (Non-Maximum Suppression)~~ | ✅ Complete — class-wise, IoU 0.45, pre-NMS conf 0.25 |
| 7 | Add pause/resume detection toggle | 🟡 High |
| 8 | ~~Implement performance logging (FPS, latency)~~ | ✅ Complete |

## Recent Accomplishments

- ✅ Persistent inference isolate with runtime model introspection (`ModelMetadata`)
- ✅ Automatic model-type detection (FP32 / Full INT8 / Full UINT8 / Weight-Quantized / Unknown) — never guessed
- ✅ Pure-Dart flatbuffer scanner for internal tensor precision ([`tflite_flatbuffer.dart`](../lib/models/tflite_flatbuffer.dart))
- ✅ Dynamic inference-path selection: input quantization + output dequantization driven by runtime metadata only
- ✅ Fixed the inference-isolate crash (`Float32List.reshape`) — raw `ByteBuffer` I/O, no reshape
- ✅ Busy gate now releases on isolate errors (pipeline no longer wedges permanently)
- ✅ Debug overlay renders live runtime model info (name, type, I/O types, shapes, classes, anchors, quantization)
- ✅ Startup diagnostic report (`MODEL INFORMATION` banner) in the isolate + `[Model]` summary on the main isolate
- ✅ Manual YUV420→RGB conversion (no external image library)
- ✅ Frame-dropping busy gate (no queue buildup)
- ✅ Stream-based detection results to UI
- ✅ COCO label loading from assets
- ✅ Camera initialization with YUV420 format at low resolution
- ✅ Project documentation system established (`docs/` directory)
- ✅ Bounding box overlay with `CustomPainter`, coordinate transformation, and front-camera mirroring
- ✅ Debug instrumentation: structured `debugPrint` logging (`[Service]`/`[Model]`/`[Camera]`/`[Inference]`/`[Detection]`/`[Painter]`/`[Performance]`/`[Error]`) + visual debug overlay (debug builds only)
- ✅ Performance logging: 5-second summaries with camera FPS, inference FPS, and avg/min/max latency
- ✅ Partial isolate error handling: try/catch + error propagation to main isolate
- ✅ Forensic file-based diagnostics (`ForensicLog`): structured logs + first-frame PNG dumps + auto-diagnosis written under `<documents>/debug/run_*` (replaces console probes)
- ✅ Camera preprocessing repair: geometry-aware YUV420→RGB (rowStride/pixelStride honored; planar I420 + semi-planar NV12/NV21)
- ✅ Aspect-correct preview: `FittedBox` + painter share `applyBoxFit` math; no stretching/warping
- ✅ Camera preview UI redesign: strict 3:4 portrait preview + permanent Metrics/Detections info panel
- ✅ Class-wise NMS (IoU 0.45) + pre-NMS confidence threshold lowered to 0.25 (standard YOLOv8)
- ✅ **Device-independent orientation** (`BoxTransform`): input tensor rotated/mirrored to upright per runtime metadata; portrait detections 0 → 0.91 on-device; static-image regression byte-identical
