# EyeCue — Project Status

> **Last Updated:** 2026-08-01
> See also: [`implementation-progress.md`](implementation-progress.md) (detailed progress), [`known-issues.md`](known-issues.md) (blockers).

## Overall Progress: ~55%

The core inference pipeline — camera → Isolate → TFLite → argmax → UI stream — is functional and architecturally sound. Bounding box overlay, full debug instrumentation, and **runtime model introspection** are implemented. Error reporting in the isolate is partially complete (the busy gate now recovers on isolate errors). The app is **not yet usable as an assistive tool**: no TTS audio, no NMS, no isolate restart recovery, no permission-denied UI.

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

## Current Blocker

**XNNPACK SIGSEGV** — XNNPACK crashes on Snapdragon 695 with the bundled YOLOv8n model (FLOAT32 I/O, INT8 weights). Without hardware acceleration, inference is CPU-bound. Investigation with the official TFLite benchmark tool is needed.

See [`known-issues.md`](known-issues.md) for full blocker details.

## Next Objective

Implement **TTS audio feedback** — the app's entire purpose is to speak detected objects. Without TTS, it's a silent camera viewer. The `flutter_tts` package is already declared as a dependency.

## High-Priority Tasks

| # | Task | Priority |
|---|------|----------|
| 1 | Implement TTS audio feedback | 🔴 Critical |
| 2 | ~~Implement bounding box `CustomPainter`~~ | ✅ Complete |
| 3 | ~~Add error handling to inference isolate~~ | 🟡 Partial — error reporting done; restart recovery remaining |
| 4 | Add permission-denied and error UI states | 🔴 Critical |
| 5 | Investigate XNNPACK SIGSEGV | 🔴 Critical |
| 6 | Implement NMS (Non-Maximum Suppression) | 🟡 High |
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
