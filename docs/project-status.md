# EyeCue — Project Status

> **Last Updated:** 2026-08-16
> See also: [`implementation-progress.md`](implementation-progress.md) (detailed progress), [`known-issues.md`](known-issues.md) (blockers), [`thesis-product-status-audit.md`](thesis-product-status-audit.md) (thesis-aligned completion baseline).

## Overall Progress

**ML/inference pipeline:** ~80% complete and on-device validated.
**Thesis product (app as a whole):** ~30–35% — see the [thesis-product-status-audit](thesis-product-status-audit.md) for the weighted breakdown. The historical "~60%" figure measured only the ML/debug pipeline and is not a product-completion number.

## What Changed (v0.2.0 — Assistive Application UI)

The app is no longer a single developer camera screen. It now has the thesis-aligned application structure:

- **Navigation:** 4-tab bottom bar — Home, Detect, Settings, Help ([`app_shell.dart`](../lib/navigation/app_shell.dart)); Logs & Reports pushed from Settings.
- **Home:** branding, status card (Auto-Start aware), "Go to Live Camera".
- **Detection:** the validated camera/inference pipeline preserved, now with an assistive UI — status pill, audio mute, object cards with priority badges, high-priority warning banner, visible controls, and thesis gestures (two-finger double-tap start/stop, single tap pause/resume, three-finger scan, swipe-down repeat) with haptic + TTS confirmation.
- **TTS audio feedback:** implemented ([`tts_service.dart`](../lib/services/tts_service.dart)) — cooldown, de-duplication, urgent bypass, repeat-last, mute state. `flutter_tts` is now wired (previously declared-only).
- **Settings:** persisted preferences — Vibration, Auto-Start, Low Power Mode (dispatch throttle), Audio guidance, Logs & Reports ([`settings_service.dart`](../lib/services/settings_service.dart)).
- **Help:** how it works, gestures, confirmation feedback, Android usage tips.
- **Logs & Reports:** Overview / Charts / Logs with `fl_chart`; accuracy/precision/recall/mAP explicitly shown as unavailable (require ground truth).
- **Spatial/priority layer:** left/center/right + priority tiers + approximate proximity band ([`spatial_analysis_service.dart`](../lib/services/spatial_analysis_service.dart)) — kept separate from the inference pipeline.
- `flutter analyze`: **0 issues**. `flutter test`: **52 passing**.

## Current Milestone

**Milestone 2: "Research-Ready"** (extends the v0.1 "Audible MVP" work — audio + assistive UI now landed)

| Task | Status |
|------|--------|
| TTS audio feedback (start/stop, detections, scan, repeat) | ✅ Implemented (v0.2.0) |
| Thesis gesture controls + haptic/TTS confirmation | ✅ Implemented (v0.2.0) |
| Home / Settings / Help / Logs & Reports screens + navigation | ✅ Implemented (v0.2.0) |
| Persisted settings (vibration, auto-start, low-power, audio) | ✅ Implemented (v0.2.0) |
| Spatial position (left/center/right) + priority classification | ✅ Implemented (heuristic proximity band) (v0.2.0) |
| Runtime telemetry + charts (latency/FPS/frequency) | ✅ Implemented (v0.2.0) |
| Error handling in isolate | 🟡 Partial — try/catch + error propagation done; restart recovery missing |
| Permission-denied UI | ✅ Implemented (v0.2.0 — camera-denied screen with retry/open-settings) |
| Isolate restart recovery | ❌ Not started |
| Orientation re-validation (back landscape + front camera) | 🟡 In progress — portrait + static verified; deferred runs pending |

## Current Blocker

**XNNPACK SIGSEGV** — XNNPACK crashes on Snapdragon 695 with the bundled YOLOv8n model (FLOAT32 I/O, INT8 weights). Without hardware acceleration, inference is CPU-bound. Investigation with the official TFLite benchmark tool is needed.

See [`known-issues.md`](known-issues.md) for full blocker details.

## Next Objective

1. **On-device validation of the v0.2.0 UI** — run on the Snapdragon 695 device: gestures, TTS, mute toggle, settings persistence, Logs & Reports charts.
2. **Re-validate orientation on-device** — back-camera landscape physical hold and front-camera portrait/landscape runs (deferred from v0.1.7).
3. **Isolate restart recovery** and remaining research-evaluation work (see the audit's phases).

## High-Priority Tasks

| # | Task | Priority |
|---|------|----------|
| 1 | On-device validation of gestures + TTS + settings persistence | 🔴 Critical |
| 2 | ~~Implement TTS audio feedback~~ | ✅ Complete (v0.2.0) |
| 3 | ~~Add permission-denied and error UI states~~ | 🟡 Partial — permission UI done; isolate restart recovery remaining |
| 4 | Investigate XNNPACK SIGSEGV | 🔴 Critical |
| 5 | ~~Implement thesis gesture controls~~ | ✅ Complete (v0.2.0) |
| 6 | Isolate restart recovery | 🔴 High |
| 7 | Orientation re-validation (back landscape + front camera) | 🟡 High |
| 8 | Formal FPS/latency benchmark + accuracy evaluation | 🟡 High |

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
