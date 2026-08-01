# EyeCue Flutter — Comprehensive Project Audit Report

**Date:** 2026-07-22  
**Auditor:** Automated Project Status Auditor  
**Repository:** `/home/nico/repos/eyecue_flutter`  
**Branch/Methodology:** Evidence-based — every conclusion cites repository artifacts.

---

## 1. Executive Summary

EyeCue is a **real-time, on-device object detection assistive application for visually impaired users**, originally prototyped in React Native and now being rebuilt in Flutter. The app captures camera frames, runs them through a YOLOv8n TFLite model, and speaks detected object names aloud via text-to-speech.

**Current State:** The Flutter rebuild is at an **early prototype stage (~35–40% complete)**. The core inference pipeline — camera → Isolate → TFLite → argmax → UI stream — is functional and architecturally sound. However, the app is **not yet usable as an assistive tool**: no bounding box overlay, no TTS audio feedback, no NMS, no pause/resume, no accessibility features, no logging, and no tests exist.

**The single most significant achievement** is the persistent-inference-isolate architecture with dynamic tensor shape querying and INT8 dequantization support. This directly addresses the React Native prototype's bottlenecks (JS bridge overhead, per-frame model loading, 300ms hard throttle).

**Total source files (lib/):** 4 Dart files (~550 lines total).  
**Test files:** 1 (boilerplate counter app — irrelevant).  
**Documentation:** 1 massive specification file (`chat_spec.md`, ~3100 lines) containing the full conversation history that guided development. No formal README, no architecture doc, no implementation plan.

---

## 2. Technology Stack

| Layer | Technology | Version | Status |
|-------|-----------|---------|--------|
| Framework | Flutter/Dart | SDK >=3.12.0 <4.0.0 | ✅ Active |
| Rendering | Impeller (Vulkan + OpenGLES) | Bundled | ✅ Active |
| Camera | `camera` plugin | ^0.12.0+1 | ✅ |
| ML Inference | `tflite_flutter` | ^0.12.1 | ✅ |
| TTS | `flutter_tts` | ^4.2.0 | 📦 Declared, not used |
| State Mgmt | `flutter_riverpod` | ^3.3.2 | 📦 Declared, not used |
| Permissions | `permission_handler` | ^12.0.3 | ✅ |
| Path Provider | `path_provider` | ^2.1.4 | 📦 Declared, not used |
| Charts | `fl_chart` | ^1.2.0 | 📦 Declared, not used |
| Lints | `flutter_lints` | ^6.0.0 | ✅ |
| Build | Gradle 9.1.0, AGP 9.0.1, Kotlin 2.3.20 | — | ✅ |
| Model | YOLOv8n (INT8 quantized) | `yolov8n.tflite` | ✅ Bundled |
| Labels | COCO 80-class | `labels.txt` | ✅ Bundled |
| Platforms | Android (primary), iOS, Linux, macOS, Windows, Web | — | Bootstrapped but untested |

**Note:** The `.flutter-plugins` file is stale and references `camera-0.10.5+9` (pubspec declares `^0.12.0+1`). The `.flutter-plugins-dependencies` correctly reflects the resolved versions.

---

## 3. Architecture Overview

### 3.1 High-Level Architecture

```
┌──────────────────────────────────────────────────┐
│                  Main Isolate (UI)                │
│                                                  │
│  ┌──────────┐    ┌─────────────────────────┐     │
│  │  Camera   │    │   CameraScreen (State)  │     │
│  │  Plugin   │───▶│   _isInferring gate     │     │
│  │  YUV420   │    │   _detections list      │     │
│  │  Stream   │    │   CameraPreview widget  │     │
│  └──────────┘    └──────────┬──────────────┘     │
│                             │                    │
│                    SendPort │  ▲ Stream<List>     │
│                             ▼  │                  │
│                  ┌────────────────────┐          │
│                  │ InferenceService   │          │
│                  │ (Bridge Manager)   │          │
│                  └────────┬───────────┘          │
└───────────────────────────┼──────────────────────┘
                            │ SendPort/ReceivePort
                            │ (Isolate boundary)
┌───────────────────────────┼──────────────────────┐
│            Inference Isolate                      │
│                           ▼                       │
│  ┌──────────────────────────────────────────┐    │
│  │  _isolateEntryPoint()                     │    │
│  │                                          │    │
│  │  1. Interpreter.fromBuffer() — ONCE      │    │
│  │  2. Dynamic tensor shape querying        │    │
│  │  3. Pre-allocated input/output buffers   │    │
│  │  4. YUV420 → RGB conversion (manual)     │    │
│  │  5. interpreter.run()                    │    │
│  │  6. Argmax per-box + dequantization      │    │
│  │  7. Detection list → mainSendPort        │    │
│  └──────────────────────────────────────────┘    │
└──────────────────────────────────────────────────┘
```

### 3.2 Key Architectural Decisions

| Decision | Implementation | Assessment |
|----------|---------------|------------|
| Persistent isolate | `Isolate.spawn()` at app startup, one Interpret instance for lifetime | ✅ Correct — avoids per-frame model loading |
| Frame dropping | Boolean `_isInferring` gate; drop if busy | ✅ Correct — deterministic latency |
| Manual YUV→RGB | Custom math, no `image` package | ✅ Correct — avoids GC pressure |
| Dynamic tensor shapes | `interpreter.getInputTensor(0).shape` | ✅ Correct — not hardcoded |
| INT8 dequantization | Scale/zeroPoint from `outputTensor.params` | ✅ Correct |
| Stream-based results | `StreamController.broadcast()` | ✅ Good for multiple listeners |
| NHWC/NCHW detection | `shape[1] == 3` heuristic | ⚠️ Works for YOLOv8 but fragile |

### 3.3 Data Flow

1. `CameraController.startImageStream()` delivers `CameraImage` at native FPS (~30)
2. `_processCameraImage()` checks `_isInferring` gate → drops frame if busy
3. Extracts Y, U, V `Uint8List` planes + dimensions
4. Sends Map via `SendPort` to inference isolate
5. Isolate converts YUV420 → RGB Float32/Uint8 (depending on model input type)
6. Reshapes buffer to model input shape, calls `interpreter.run()`
7. Post-processes: argmax per box, dequantization (if INT8), confidence threshold (0.5)
8. Returns `List<Detection>` to main isolate via `SendPort`
9. Main isolate adds to `StreamController` → `setState()` → UI repaints

### 3.4 Project Structure

```
eyecue_flutter/
├── lib/
│   ├── main.dart                          # App entry point, MaterialApp
│   ├── models/detection.dart              # Detection data class
│   ├── screens/camera_screen.dart         # Single screen — camera + orchestration
│   └── services/inference_isolate.dart    # Isolate bridge + inference + preprocessing
├── assets/
│   ├── yolov8n.tflite                     # Active model (INT8, despite name)
│   ├── yolov8n_int8.tflite                # Present but not in pubspec assets
│   └── labels.txt                         # 80 COCO class names (+ trailing empty line 81)
├── test/
│   └── widget_test.dart                   # Boilerplate counter test (irrelevant)
├── android/                               # Android platform (Gradle 9.1, AGP 9.0.1)
├── ios/                                   # iOS platform (bootstrapped, not configured)
├── linux/, macos/, windows/, web/         # Desktop/web platforms (bootstrapped)
├── pubspec.yaml                           # Dependencies & asset declarations
├── chat_spec.md                           # Full conversation history (~3100 lines)
└── auditor.md                             # This report
```

### 3.5 Missing Architectural Components

- **No routing:** Single screen, no navigation
- **No dependency injection:** Services instantiated directly in widgets
- **No state management layer:** Riverpod declared but unused; raw `setState` used
- **No service abstraction:** `InferenceService` coupled directly to TFLite, camera format, and COCO labels
- **No error handling strategy:** No try/catch around inference, no error states in UI
- **No configuration:** All thresholds, model paths, and labels hardcoded

---

## 4. Feature Inventory

### 4.1 Implemented Features

| # | Feature | Status | Evidence | Files | Remaining Work |
|---|---------|--------|----------|-------|----------------|
| 1 | Camera initialization (YUV420, low res) | ✅ Complete | [`camera_screen.dart:52-57`](lib/screens/camera_screen.dart:52) | `camera_screen.dart` | None |
| 2 | Camera permission handling | ✅ Mostly Complete | [`camera_screen.dart:38-45`](lib/screens/camera_screen.dart:38) | `camera_screen.dart` | No UI for denied state |
| 3 | Persistent inference isolate | ✅ Complete | [`inference_isolate.dart:31-34`](lib/services/inference_isolate.dart:31) | `inference_isolate.dart` | None |
| 4 | TFLite model loading (once) | ✅ Complete | [`inference_isolate.dart:98`](lib/services/inference_isolate.dart:98) | `inference_isolate.dart` | None |
| 5 | Dynamic tensor shape querying | ✅ Complete | [`inference_isolate.dart:101-107`](lib/services/inference_isolate.dart:101) | `inference_isolate.dart` | None |
| 6 | Manual YUV420→RGB conversion | ✅ Complete | [`inference_isolate.dart:195-262`](lib/services/inference_isolate.dart:195) | `inference_isolate.dart` | Nearest-neighbor resize only |
| 7 | INT8 dequantization | ✅ Complete | [`inference_isolate.dart:280-309`](lib/services/inference_isolate.dart:280) | `inference_isolate.dart` | None |
| 8 | Argmax per-box post-processing | ✅ Complete | [`inference_isolate.dart:269-330`](lib/services/inference_isolate.dart:269) | `inference_isolate.dart` | None |
| 9 | COCO label loading | ✅ Complete | [`inference_isolate.dart:50-58`](lib/services/inference_isolate.dart:50) | `inference_isolate.dart` | None |
| 10 | Frame-dropping gate | ✅ Complete | [`camera_screen.dart:87`](lib/screens/camera_screen.dart:87) | `camera_screen.dart` | None |
| 11 | Stream-based results to UI | ✅ Complete | [`camera_screen.dart:73-81`](lib/screens/camera_screen.dart:73) | `camera_screen.dart` | None |
| 12 | Camera preview rendering | ✅ Complete | [`camera_screen.dart:128`](lib/screens/camera_screen.dart:128) | `camera_screen.dart` | None |

### 4.2 Partially Implemented Features

| # | Feature | Status | Evidence | Files | Remaining Work |
|---|---------|--------|----------|-------|----------------|
| 13 | Bounding box overlay | 🔶 Stubbed | [`camera_screen.dart:130-131`](lib/screens/camera_screen.dart:130) — TODO comment | `camera_screen.dart` | Implement `CustomPainter`, wire to `_detections` |
| 14 | Object label display | 🔶 Data available | `_detections` list populated but not rendered | `camera_screen.dart` | Add text overlay |

### 4.3 Missing Features (Declared but Not Implemented)

| # | Feature | Evidence | Dependency |
|---|---------|----------|------------|
| 15 | Text-to-Speech (TTS) audio feedback | `flutter_tts: ^4.2.0` in pubspec, zero usages | Package declared |
| 16 | State management via Riverpod | `flutter_riverpod: ^3.3.2` in pubspec, zero usages | Package declared |
| 17 | Logging & data visualization | `fl_chart: ^1.2.0` in pubspec, zero usages | Package declared |
| 18 | Path provider for model file access | `path_provider: ^2.1.4` in pubspec, zero usages | Package declared |
| 19 | Pause/resume detection toggle | Not implemented | New feature |
| 20 | Non-Maximum Suppression (NMS) | Not implemented — argmax output has duplicate boxes | `inference_isolate.dart` |
| 21 | Adaptive throttling | Not implemented — fixed frame-drop only | `camera_screen.dart` |
| 22 | Accessibility (Semantics, TalkBack) | Not implemented | New feature |
| 23 | High-contrast UI / accessibility mode | Not implemented | New feature |
| 24 | Gesture-based controls | Not implemented | New feature |
| 25 | Error/loading/permission-denied UI | Not implemented — just returns silently | `camera_screen.dart:43-44` |
| 26 | INT8 model variant selection | `yolov8n_int8.tflite` exists in assets but not in pubspec | `pubspec.yaml` |
| 27 | GPU/NNAPI delegate support | XNNPACK explicitly removed (SIGSEGV); no delegate config | `inference_isolate.dart:93-94` |
| 28 | Performance logging (FPS, latency) | Not implemented | New feature |
| 29 | Label confidence display | Not implemented | `camera_screen.dart` |
| 30 | Object priority-based TTS | Not implemented | New feature |

---

## 5. Progress Estimation

### Overall Progress: ~38%

```
Camera Pipeline         ████████████████████ 100%  (Init, stream, frame-drop, preview)
Inference Isolate       ████████████████████ 100%  (Spawn, load, shape query, dequant)
Preprocessing (YUV→RGB) ████████████████████ 100%  (Manual conversion, NHWC/NCHW)
Post-processing (Argmax)█████████████████████  95%  (Missing NMS only)
Model/Labels Loading    ████████████████████ 100%
Bounding Box Overlay    █░░░░░░░░░░░░░░░░░░░░   5%  (TODO comment only)
Text-to-Speech (TTS)    ░░░░░░░░░░░░░░░░░░░░░   0%  (Package declared, no code)
State Management        ░░░░░░░░░░░░░░░░░░░░░   0%  (Riverpod declared, no code)
Logging / Visualization ░░░░░░░░░░░░░░░░░░░░░   0%  (fl_chart declared, no code)
Accessibility           ░░░░░░░░░░░░░░░░░░░░░   0%
Error/Edge Case UI      ░░░░░░░░░░░░░░░░░░░░░   0%
Testing                 ░░░░░░░░░░░░░░░░░░░░░   0%  (Irrelevant boilerplate)
Documentation           ████░░░░░░░░░░░░░░░░░  20%  (chat_spec.md only, no README)
```

### Confidence: **High** — Based on full source analysis of all 4 Dart files and configuration files.

---

## 6. Documentation Consistency Check

### 6.1 `chat_spec.md` vs. Implementation

| Plan Item | Plan Status | Implementation Status | Match? |
|-----------|-------------|----------------------|--------|
| Persistent inference isolate | ✅ Specified | ✅ Implemented | ✅ Match |
| Load interpreter ONCE | ✅ Specified | ✅ Implemented | ✅ Match |
| Manual YUV→RGB (no `image` package) | ✅ Specified | ✅ Implemented | ✅ Match |
| Dynamic tensor shape querying | ✅ Specified | ✅ Implemented | ✅ Match |
| Frame dropping (busy gate) | ✅ Specified | ✅ Implemented | ✅ Match |
| `ResolutionPreset.low` | ✅ Specified | ✅ Implemented | ✅ Match |
| `ImageFormatGroup.yuv420` | ✅ Specified | ✅ Implemented | ✅ Match |
| Stream-based results | ✅ Specified | ✅ Implemented | ✅ Match |
| XNNPACK enabled | ✅ Specified | ❌ Removed (SIGSEGV) | ⚠️ Intentional deviation |
| Bounding box `CustomPainter` | ✅ Specified | ❌ TODO only | ❌ Not implemented |
| TTS with priority cooldown | ✅ Specified | ❌ Not implemented | ❌ Not implemented |
| `fl_chart` for logging UI | ✅ Specified | ❌ Not implemented | ❌ Not implemented |
| Riverpod state management | ✅ Specified | ❌ Not used | ❌ Not implemented |
| COCO labels from `labels.txt` | ✅ Specified | ✅ Implemented | ✅ Match |
| INT8 model (`yolov8n_int8.tflite`) | ✅ Specified | ⚠️ Model in assets, not in pubspec | ⚠️ Partial |
| `minSdkVersion 24` | ✅ Specified | ⚠️ Uses `flutter.minSdkVersion` (21) | ⚠️ May cause issues |
| Package name `com.eyecue` | ✅ Specified | ❌ `com.example.eyecue_flutter` | ❌ Deviation |

### 6.2 Key Discrepancies

1. **XNNPACK removal (critical):** The plan explicitly called for XNNPACK. The implementation removed it due to a SIGSEGV on the test device (Snapdragon 695) — see [`inference_isolate.dart:93-94`](lib/services/inference_isolate.dart:93). This is a valid deviation but should be documented as a known limitation.

2. **Package name:** Uses `com.example.eyecue_flutter` instead of specified `com.eyecue`. Low priority but should be fixed before any store submission.

3. **minSdk:** Relies on Flutter's default `minSdkVersion` (21) rather than the recommended 24. The `tflite_flutter` plugin may fail on API 21–23 devices. This is a latent issue.

4. **Model file:** The plan suggested using `yolov8n_int8.tflite`. The implementation uses `yolov8n.tflite` (which is actually INT8-quantized according to the conversation). The `yolov8n_int8.tflite` file exists in assets but is not declared in `pubspec.yaml`'s assets section. Only one model is loadable.

5. **Unused dependencies:** 4 of 7 direct dependencies (`flutter_riverpod`, `flutter_tts`, `fl_chart`, `path_provider`) have zero usages in `lib/`. These represent ~57% of declared dependencies being dead weight.

---

## 7. Code Quality Assessment

### 7.1 Strengths

| Area | Observation |
|------|------------|
| **Isolate architecture** | [`inference_isolate.dart`](lib/services/inference_isolate.dart) is well-structured: clean separation between bridge (InferenceService) and worker logic (static methods). The decision to use `Isolate.spawn()` with a persistent receive loop is the correct architectural pattern for this use case. |
| **Dynamic tensor shapes** | Querying `interpreter.getInputTensor(0).shape` and `interpreter.getOutputTensor(0).shape` instead of hardcoding `[1,84,2100]` is excellent practice. Supports model changes without code changes. |
| **INT8 dequantization** | Handles `TensorType.int8`/`uint8` with proper `scale`/`zeroPoint` — [`inference_isolate.dart:280-309`](lib/services/inference_isolate.dart:280). This is technically correct and non-trivial. |
| **NHWC/NCHW detection** | Auto-detects channel ordering from shape — [`inference_isolate.dart:126-128`](lib/services/inference_isolate.dart:126). Good defensive programming. |
| **Manual YUV conversion** | Avoiding the `image` package for real-time video is the right call. The direct byte manipulation in [`_convertYUV420toRGB`](lib/services/inference_isolate.dart:195) avoids GC pressure. |
| **Frame dropping** | The `_isInferring` boolean gate in [`camera_screen.dart:87`](lib/screens/camera_screen.dart:87) is simple and correct. |
| **Diagnostic logging** | Tensor metadata logging in [`inference_isolate.dart:113-121`](lib/services/inference_isolate.dart:113) is useful for debugging. |
| **Resource cleanup** | [`camera_screen.dart:108-113`](lib/screens/camera_screen.dart:108) properly disposes camera and isolate. |

### 7.2 Weaknesses

| Area | Observation | Severity |
|------|------------|----------|
| **No error handling in isolate** | The inference pipeline in [`_isolateEntryPoint`](lib/services/inference_isolate.dart:84) has zero try/catch blocks. If TFLite crashes, the isolate dies silently and the app freezes. | 🔴 High |
| **No permission-denied UI** | [`camera_screen.dart:43-44`](lib/screens/camera_screen.dart:43) just returns. User sees infinite spinner. | 🔴 High |
| **Hardcoded labels path** | Labels loaded from hardcoded `'assets/labels.txt'` — [`inference_isolate.dart:51`](lib/services/inference_isolate.dart:51). Not configurable. | 🟡 Medium |
| **Hardcoded model path** | Model loaded from hardcoded `'assets/yolov8n.tflite'` — [`inference_isolate.dart:46`](lib/services/inference_isolate.dart:46). No runtime model selection. | 🟡 Medium |
| **Hardcoded confidence threshold** | `0.5` in [`inference_isolate.dart:179`](lib/services/inference_isolate.dart:179). Not tunable. | 🟡 Medium |
| **Nearest-neighbor resize** | YUV→RGB uses `round().clamp()` for resize — [`inference_isolate.dart:212-217`](lib/services/inference_isolate.dart:212). No bilinear interpolation. May reduce detection quality. | 🟡 Medium |
| **YUV conversion constants** | The conversion uses non-standard coefficients (1.402, 0.344, 1.772 with unsigned u/v minus 128). The standard ITU-R BT.601 uses (u-128) and (v-128) with slightly different coefficients. The current implementation uses `uVal = uPlane[...] - 128` and `vVal = vPlane[...] - 128` which is correct, but the coefficients differ from the typical SDTV formula. This may cause subtle color shifts but likely doesn't affect detection accuracy significantly. | 🟢 Low |
| **Full plane bytes sent over SendPort** | [`camera_screen.dart:98-104`](lib/screens/camera_screen.dart:98) sends entire Y, U, V planes across the isolate boundary every frame. At 640×480 YUV420, that's ~460KB per frame. This is a memory copy that could be optimized with `TransferableTypedData`. | 🟡 Medium |
| **No NMS** | Multiple boxes for the same object are all returned. The UI would show overlapping rectangles. | 🟡 Medium |
| **Broadcast stream** | Using `StreamController.broadcast()` is fine but unnecessary — only one listener exists. | 🟢 Low |
| **`dynamic` type for input buffer** | [`inference_isolate.dart:137`](lib/services/inference_isolate.dart:137) uses `dynamic` for the input buffer. Loses type safety. Could use a sealed class or union type. | 🟢 Low |
| **Unused Riverpod dependency** | Zero usages of `flutter_riverpod` in all of `lib/`. Adds unnecessary dependency weight. | 🟡 Medium |
| **`path_provider` unused** | Declared but never imported. | 🟢 Low |

### 7.3 Code Organization

- **Good:** Separation of model ([`detection.dart`](lib/models/detection.dart)), service ([`inference_isolate.dart`](lib/services/inference_isolate.dart)), and screen ([`camera_screen.dart`](lib/screens/camera_screen.dart)).
- **Needs improvement:** All business logic is in static methods on `InferenceService`. As the project grows, preprocessing, post-processing, and label management should be extracted into separate classes.
- **Needs improvement:** Configuration is scattered as hardcoded values. A central config file or class is needed.

---

## 8. Technical Debt

### 8.1 Prioritized Debt Items

| Priority | Item | Location | Impact |
|----------|------|----------|--------|
| 🔴 P0 | No error handling in inference isolate | [`inference_isolate.dart:151-187`](lib/services/inference_isolate.dart:151) | Silent crashes, app freeze |
| 🔴 P0 | No permission-denied UI | [`camera_screen.dart:43`](lib/screens/camera_screen.dart:43) | Broken UX |
| 🔴 P0 | XNNPACK SIGSEGV — no fallback or investigation | [`inference_isolate.dart:93`](lib/services/inference_isolate.dart:93) | Performance ceiling |
| 🟡 P1 | No NMS implementation | [`inference_isolate.dart:269`](lib/services/inference_isolate.dart:269) | Duplicate detections |
| 🟡 P1 | Unused dependencies (4 packages) | [`pubspec.yaml:22-32`](pubspec.yaml:22) | Bloat, confusion |
| 🟡 P1 | No bounding box painter | [`camera_screen.dart:130`](lib/screens/camera_screen.dart:130) | Core feature missing |
| 🟡 P1 | No TTS integration | — | Core feature missing |
| 🟡 P2 | Hardcoded thresholds/paths | Multiple locations | Inflexibility |
| 🟡 P2 | Large memory copies per frame | [`camera_screen.dart:98`](lib/screens/camera_screen.dart:98) | Memory pressure |
| 🟡 P2 | Nearest-neighbor resize only | [`inference_isolate.dart:212`](lib/services/inference_isolate.dart:212) | Quality degradation |
| 🟢 P3 | Stale `.flutter-plugins` file | [`.flutter-plugins`](.flutter-plugins) | Confusion during debugging |
| 🟢 P3 | Package name `com.example` | [`build.gradle.kts:17`](android/app/build.gradle.kts:17) | Not production-ready |
| 🟢 P3 | `minSdk` relies on Flutter default (21) | [`build.gradle.kts:18`](android/app/build.gradle.kts:18) | May fail on API 21-23 |
| 🟢 P3 | Boilerplate test file | [`test/widget_test.dart`](test/widget_test.dart) | Misleading |

### 8.2 TODOs and FIXMEs

Only one TODO exists in the codebase:

- [`camera_screen.dart:130-131`](lib/screens/camera_screen.dart:130): `// TODO: We will add the CustomPainter overlay here later`

No FIXMEs, HACKs, or XXX markers found.

---

## 9. Testing Status

### 9.1 Current Tests

The only test file is [`test/widget_test.dart`](test/widget_test.dart) — a **boilerplate Flutter counter app test** that was generated by `flutter create`. It tests for a counter that does not exist in the EyeCue app. **Zero functional tests exist.**

### 9.2 Missing Tests (Critical Paths)

| Test Area | Priority | Notes |
|-----------|----------|-------|
| TFLite model loading | 🔴 P0 | Verify model loads without crash |
| YUV→RGB conversion correctness | 🔴 P0 | Verify against known test image |
| YOLOv8 output parsing | 🔴 P0 | Verify with pre-computed tensor |
| INT8 dequantization | 🔴 P0 | Verify scale/zeroPoint math |
| Camera permission flow | 🟡 P1 | Test grant/deny paths |
| Frame dropping logic | 🟡 P1 | Verify no concurrent inference |
| Isolate communication | 🟡 P1 | Verify SendPort/ReceivePort flow |
| Label loading | 🟢 P2 | Verify 80 labels parsed correctly |
| NHWC/NCHW detection | 🟢 P2 | Test with both layout types |
| Detection model serialization | 🟢 P2 | Verify Detection class correctness |

### 9.3 Manual Testing Requirements

- On-device camera preview smoothness
- Inference FPS measurement on target hardware (Snapdragon 695)
- Audio feedback latency (once TTS is implemented)
- Battery consumption under sustained use
- Thermal throttling behavior

---

## 10. Current Blockers

### 10.1 Active Blockers

| # | Blocker | Severity | Details |
|---|---------|----------|---------|
| 1 | **XNNPACK SIGSEGV** | 🔴 Critical | XNNPACK crashes on Snapdragon 695 with the INT8 YOLOv8n model. See [`inference_isolate.dart:93-94`](lib/services/inference_isolate.dart:93). Without hardware acceleration, inference is CPU-bound and slower than it could be. |
| 2 | **No TTS integration** | 🔴 Critical | The app's entire purpose is to speak detected objects. Without TTS, it's a silent camera viewer. |
| 3 | **No bounding box overlay** | 🟡 High | Detections are computed but never displayed. Users cannot see what was detected. |
| 4 | **No error recovery** | 🟡 High | Any TFLite crash kills the isolate silently. The UI shows stale state indefinitely. |

### 10.2 Latent Issues (Not Yet Blocking)

| # | Issue | Details |
|---|-------|---------|
| 5 | `minSdkVersion` may be too low | Flutter default is 21; `tflite_flutter` may need 24+. The app builds now but could fail on older devices. |
| 6 | No model variant selection | Only one model loadable despite multiple variants in assets. |
| 7 | No logging/metrics | Cannot measure FPS, latency, or detection accuracy programmatically. |

### 10.3 Resolved Issues

| # | Issue | Resolution |
|---|-------|------------|
| 1 | `Isolate.run()` per frame (from GLM's initial plan) | Fixed — uses persistent `Isolate.spawn()` |
| 2 | `Interpreter.fromAsset()` per frame | Fixed — loads once in `_isolateEntryPoint` |
| 3 | Hardcoded tensor shapes | Fixed — queries dynamically |

---

## 11. Recommended Next Steps

### Priority 1 — Critical (Must Fix to Be Usable)

| # | Task | Effort | Dependencies |
|---|------|--------|-------------|
| P1-1 | **Implement TTS audio feedback** | 2–4 hours | `flutter_tts` (already declared) |
| P1-2 | **Implement bounding box `CustomPainter`** | 2–3 hours | Detection data already available |
| P1-3 | **Add error handling to inference isolate** | 1–2 hours | None |
| P1-4 | **Add permission-denied and error UI states** | 1–2 hours | None |
| P1-5 | **Investigate XNNPACK SIGSEGV** | 4–8 hours | Test device, TFLite benchmark tool |

### Priority 2 — MVP Features

| # | Task | Effort | Dependencies |
|---|------|--------|-------------|
| P2-1 | **Implement NMS (Non-Maximum Suppression)** | 2–4 hours | None |
| P2-2 | **Add pause/resume detection toggle** | 1–2 hours | UI button |
| P2-3 | **Add detection label text overlay** | 1–2 hours | Detection data |
| P2-4 | **Implement performance logging (FPS, latency)** | 2–3 hours | None |
| P2-5 | **Wire Riverpod or remove it** | 1–2 hours | Decision needed |
| P2-6 | **Remove unused dependencies or implement them** | 0.5 hours | Decision needed |

### Priority 3 — Quality & Robustness

| # | Task | Effort | Dependencies |
|---|------|--------|-------------|
| P3-1 | **Add unit tests for YUV→RGB, parsing, dequant** | 4–6 hours | Test framework |
| P3-2 | **Extract configuration constants** | 1–2 hours | None |
| P3-3 | **Extract preprocessing into separate class** | 1–2 hours | None |
| P3-4 | **Extract post-processing into separate class** | 1–2 hours | None |
| P3-5 | **Use `TransferableTypedData` for isolate messages** | 1–2 hours | None |
| P3-6 | **Add bilinear interpolation to resize** | 2–3 hours | None |
| P3-7 | **Add runtime model selection** | 2–3 hours | Multiple model files |
| P3-8 | **Set explicit `minSdkVersion 24`** | 0.5 hours | None |
| P3-9 | **Fix package name to `com.eyecue`** | 0.5 hours | None |
| P3-10 | **Regenerate `.flutter-plugins`** | 0.1 hours | `flutter clean && flutter pub get` |

### Priority 4 — Nice-to-Have

| # | Task | Effort | Dependencies |
|---|------|--------|-------------|
| P4-1 | **Logging dashboard with `fl_chart`** | 4–8 hours | P2-4 |
| P4-2 | **Accessibility: Semantics widget, TalkBack** | 3–5 hours | UI elements in place |
| P4-3 | **Gesture controls (double-tap, swipe)** | 2–4 hours | UI |
| P4-4 | **Priority-based TTS queue** | 3–5 hours | P1-1 |
| P4-5 | **GPU/NNAPI delegate with fallback** | 4–8 hours | P1-5 |
| P4-6 | **Adaptive throttling** | 2–3 hours | P2-4 |
| P4-7 | **README and architecture documentation** | 2–3 hours | None |
| P4-8 | **Integration tests** | 4–6 hours | P3-1 |

---

## 12. Risks

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| XNNPACK SIGSEGV blocks CPU acceleration | Medium | High | Benchmark with official TFLite tool; test alternative delegates (NNAPI); fall back to plain CPU |
| Inference FPS too low for real-time use | Medium | High | Benchmark raw model latency; optimize preprocessing; lower resolution further |
| Model accuracy insufficient for assistive use | Low | High | Already validated in React Native prototype |
| TTS latency makes app feel unresponsive | Medium | Medium | Measure end-to-end latency; use speech queue with prioritization |
| Camera plugin API changes | Low | Medium | Pin versions in pubspec |
| Device fragmentation (Mali GPUs, older Adreno) | Medium | Medium | Target CPU-only path as primary; GPU as opt-in bonus |
| Research paper metric inconsistency | High | Critical (for defense) | Redefine FPS vs latency vs throughput as distinct metrics per the chat_spec discussion |

---

## 13. Suggested Milestones

### Milestone 1: "Audible MVP" (Target: ~2 weeks)
- TTS speaks detected objects
- Bounding boxes rendered on screen
- Error handling in isolate
- Permission-denied UI
- Remove unused dependencies or wire them

### Milestone 2: "Research-Ready" (Target: ~4 weeks)
- NMS implemented
- Performance logging (FPS, latency, confidence)
- Pause/resume toggle
- `fl_chart` logging dashboard
- Unit tests for core pipeline

### Milestone 3: "Defense-Ready" (Target: ~6 weeks)
- Accessibility features (TalkBack, Semantics)
- Priority-based TTS queue
- Adaptive throttling
- GPU delegate (if XNNPACK resolved)
- Integration tests
- README and architecture docs
- Package name and minSdk fixes

### Milestone 4: "Production Candidate" (Target: ~8 weeks)
- Comprehensive error recovery
- Model variant selection at runtime
- `TransferableTypedData` optimization
- Bilinear interpolation
- Full test coverage
- Play Store readiness

---

## 14. Summary Verdict

The Flutter rebuild of EyeCue has a **solid architectural foundation** — the persistent inference isolate with dynamic tensor shape handling and INT8 dequantization is technically impressive for an early-stage prototype. The core pipeline works: camera frames flow through the isolate, YOLOv8 inference runs, and detections are parsed correctly.

However, the app is **not yet functional as an assistive tool**. The three most critical missing pieces are:
1. **TTS audio feedback** (the entire purpose of the app)
2. **Bounding box overlay** (visual confirmation of detections)
3. **Error handling** (the isolate has no crash recovery)

The project also carries **technical debt in the form of 4 unused dependencies** and a **known XNNPACK SIGSEGV on the target device** that caps CPU inference performance. Fixing these should be done in parallel with feature development.

The architectural decisions made so far are sound and align well with the research paper's goals. With focused effort on the Priority 1 and Priority 2 items, a functional MVP suitable for thesis evaluation is achievable within 2–4 weeks.

---

*End of audit. All conclusions are based on direct inspection of repository files as of 2026-07-22.*
