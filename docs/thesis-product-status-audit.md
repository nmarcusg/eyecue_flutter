# EyeCue — Thesis-Product Status Audit

> **Audit date:** 2026-08-16
> **Scope:** Full status assessment of the current Flutter codebase against the application structure and functional requirements implied by the **EyeCue thesis PDF**.
> **Thesis source of truth:** `GRP8-P1-EyeCue_ Machine Learning-Based Real-Time Object Recognition and Audio Guidance System for the Visually Impaired (1).pdf` (latest version, per the project owner).
> **Implementation source of truth:** the actual code in `lib/`, `test/`, `pubspec.yaml`, and `android/` — **not** the documentation.
> **Update note:** The original audit (also 2026-08-16) captured the **pre-v0.2.0** state — a single developer camera screen with no audio, spatial, gesture, or settings layers. Since then the v0.2.x phase landed the thesis-aligned assistive application (v0.2.0), fixed the startup theme assertion (v0.2.1), and fixed the camera viewport + chart overflow (v0.2.2). This revision re-runs the audit against the current v0.2.2 codebase; the original findings are preserved in the project's git history and session log.
> **This is an audit only.** No code was modified.
>
> **TTS superseded notice (2026-10-17):** the speech rows in this audit describe
> the v0.2.x scheduler (cooldown, same-label de-duplication, urgent bypass).
> That scheduler has since been replaced by a lifecycle-aware arbiter with
> track-aware suppression/escalation, confirmed-`onStart` history and controlled
> preemption ([`architecture.md`](architecture.md#speech-scheduling-workstream-1)).
> Read those rows as dated evidence, not current behaviour.
> **Historical snapshot notice (2026-09-01):** This audit's dated v0.2.2
> conclusions predate the committed-but-unreleased NCHW/XNNPACK candidate and
> its initial Snapdragon 695 device observation. Do not read its CPU-only,
> XNNPACK-blocked, or pending-device-validation statements as the current
> candidate status; [`project-status.md`](project-status.md) is authoritative
> for the current state. The audit's product-scope gaps and release-readiness
> conclusions remain applicable unless explicitly superseded there.
> **Superseding status notice (2026-09-05):** The app-only candidate now also
> includes bounded, generation-safe Custom-worker recovery, persisted detection
> sensitivity applied by both engines, correction capture, image-free JSON/CSV
> export, tracking/scene-summary services, expanded accessibility coverage, and
> a selectable Custom/Ultralytics runtime boundary. The dated findings below
> that say these capabilities are absent or only planned are historical audit
> observations; current implementation status is tracked in
> [`project-status.md`](project-status.md) and
> [`implementation-progress.md`](implementation-progress.md). Native crash
> recovery, formal research evaluation, broad device validation, Android
> release identity/signing, and Play-release readiness remain open.
> **WS4 removal notice (2026-10-19):** the unused `info_panel.dart`,
> `debug_overlay.dart`, `inference_probe.dart`, and `input_probe.dart` files and
> the `flutter_riverpod` dependency were removed, the static-image diagnostic
> path was removed, and forensic file I/O is now release-disabled. The
> metadata-enriched artifact is the sole bundled runtime model; the base graph
> and v0.2.2 baseline remain tracked but unbundled. Inventory statements below
> are corrected where they describe current files; dated measurements and
> conclusions remain historical.

---

## Table of Contents

1. [Executive Summary](#1-executive-summary)
2. [Thesis-Defined Product Scope](#2-thesis-defined-product-scope)
3. [Current Flutter Architecture](#3-current-flutter-architecture)
4. [Thesis-to-Code Feature Matrix](#4-thesis-to-code-feature-matrix)
5. [Screen / UI Gap Analysis](#5-screen--ui-gap-analysis)
6. [Assistive Functionality Gap Analysis](#6-assistive-functionality-gap-analysis)
7. [Spatial Guidance Gap Analysis](#7-spatial-guidance-gap-analysis)
8. [Research / Evaluation Gap Analysis](#8-research--evaluation-gap-analysis)
9. [Production Readiness Gap Analysis](#9-production-readiness-gap-analysis)
10. [Target Flutter Architecture](#10-target-flutter-architecture)
11. [Completion Estimates](#11-completion-estimates)
12. [Critical Missing Features](#12-critical-missing-features)
13. [Recommended Development Phases](#13-recommended-development-phases)
14. [Risks / Dependencies](#14-risks--dependencies)
15. [Explicit "What Is Already Complete"](#15-explicit-what-is-already-complete)
16. [Explicit "What Is Still Missing"](#16-explicit-what-is-still-missing)
17. [Conclusion](#17-conclusion)

---

## 1. Executive Summary

The current EyeCue Flutter codebase is now a **functional, thesis-aligned assistive application**, not just a computer-vision prototype. The v0.2.x phase implemented the assistive layers that the original audit identified as entirely missing: **audio guidance, spatial/priority interpretation, gesture-based interaction, the five application screens, persisted settings, and the research telemetry/charts dashboard** — while leaving the validated ML pipeline untouched.

The thesis is titled *"EyeCue: Machine Learning-Based Real-Time Object Recognition and **Audio Guidance System** for the Visually Impaired."* Its central product promise is a **blind-first mobile app** that:

1. detects objects in real time on-device (YOLOv8 / TFLite),
2. **speaks detected objects plus their relative position** via TTS,
3. classifies objects by **priority/obstacle importance** and raises an audio alarm for dangerous barriers,
4. is operated **non-visually via gestures** (start/exit, quick scan, repeat last alert, pause/resume),
5. exposes a small set of **screens** (Home, Detect, Settings, Help, Logs & Reports), and
6. **records telemetry** for research evaluation (detection logs, confidence, inference time, FPS, charts).

**What the code now does:** captures the camera, runs YOLOv8 in a persistent isolate, draws bounding boxes with confidence on a preview, **speaks detections via TTS with cooldown/de-duplication/repeat**, interprets **left/center/right position + class-based priority + approximate proximity**, responds to the **four thesis gestures** with haptic + TTS confirmation, persists **settings** (vibration, auto-start, low-power, audio), and renders a **Logs & Reports dashboard** with live telemetry and charts.

**Bottom line:** The ML engine (domain A) remains ~80% complete, and the assistive layers that constitute the thesis's reason for existence — audio guidance, spatial position, priority, accessibility/interaction (domains B, C, D) — are now implemented at a functional/heuristic level. The remaining work is concentrated in **research evaluation** (formal benchmarks, accuracy/recall/F1/mAP, the ≥30-participant study), **production hardening** (release signing, package rename, isolate restart recovery), and **refinement** (calibrated distance, TalkBack semantics).

> **Weighted overall thesis-product completion: approximately 70% (range 65–75%).**
> This is a deliberate, honest re-scoring versus the original audit's **~30%** (which measured the pre-assistive-UI state). The assistive product layer — the largest gap in the original audit — is now substantially built; what remains is evaluation, hardening, and calibration, not core product construction. See [§11](#11-completion-estimates).

The **single largest remaining mismatch** with the thesis is now **research evaluation + production hardening** rather than missing product features: no formal FPS/latency/accuracy results exist, no SUS/participant study has been run, and the release build is not yet Play-Store-ready.

---

## 2. Thesis-Defined Product Scope

Extracted directly from the thesis PDF. This is the functional contract the final product must satisfy.

### 2.1 Core system (Ch. 1–2)

| Thesis requirement | Detail from thesis |
|---|---|
| Real-time object detection | YOLOv8, "high-speed object detector and recognizer" |
| On-device ML | TensorFlow Lite, "model runs entirely on the device without relying on internet connectivity" |
| Smartphone camera | Primary input ("smartphone camera is the first input that continuously records visual information") |
| Audio feedback / TTS | "verbal output generated by the EyeCue application through text-to-speech technology, **which informs the user about detected objects and their relative position**" |
| Object identity | Recognized class (persons, chairs, doors, vehicles…) |
| Confidence | "assign objects the confidence scores"; thresholded in a "decision stage" |
| Relative position | "barrier and its **approximate position relative to the user**" (Detection screen) |
| Approximate distance / spatial info | Short-range detection; approximate position; no GPS/pathfinding (Limitations) |
| Movement / navigation relevance | Literature motivation (object type **and movement**); detection of navigation-space objects |
| Priority / obstacle importance | "objects identified are classified based on the **priority levels**, with obstacles of high priority identified… On recognizing a potentially dangerous barrier, the system will generate an **audio alarm**" |

### 2.2 User interaction (Ch. 2 Conceptual Framework + Ch. 3 Detection screen)

- User "interacts with the application through **gestures and options**, the **change of the detection sensitivity**, and the provision of control gestures, including **repeating an output** or **signaling errors**."
- "In case of incorrect detections or missing objects the user may give **corrective input by gesture** or using an **in-application correction interface**."
- Detection-screen gestures (explicit list — do not invent more):
  - **Two-finger double tap** — start or exit detection mode
  - **Three-finger tap** — perform a quick environmental scan
  - **Swipe down** — repeat the most recent audio alert
  - **Single tap** — pause or resume detection

### 2.3 Application screens (Ch. 3 High-Fidelity Prototype)

| Screen | Thesis description |
|---|---|
| **Home** | Launch screen. Logo/title + subtitle "Smart navigation assistance for visually impaired users." **Status card** (e.g. "Detection is already running" when Auto-Start is enabled). Primary CTA **"Go to Live Camera"**. Bottom menu bar: **Home, Detect, Settings, Help**. |
| **Detection** | Core screen. Camera → YOLOv8 → bounding boxes + confidence; objects classified by **priority**; **audio alarm with type + approximate position** for dangerous barriers; **gesture controls**. |
| **Settings** | **Vibration feedback**, **Automatic detection startup**, **Low power mode** (battery optimization), and a **"Logs and Report"** option. "Adjusted to user preferences and device capability." |
| **Help** | "Guide the user on how to operate the application… descriptions of system operations, **gestures and usage suggestions**." |
| **Logs & Reports** | Researcher/developer-facing **data visualization**. Charts tab: **Detection Frequency**, **Inference Latency**, **FPS**, and a **comparative chart (Accuracy, Precision, Recall, F1-Score)**. Kept inside Settings "to prevent overcomplicating the interface for the visually impaired user." |

### 2.4 Settings / configuration (thesis-defined)

- Vibration feedback
- Automatic detection startup (auto-start)
- Low-power mode for battery optimization
- Logs and Report option
- Detection sensitivity (user-changeable, per Conceptual Framework)

### 2.5 Research / telemetry (thesis-defined)

- The app "records detection results, confidence scores, inference time, and other performance metrics."
- During testing the app records: **detected objects, prediction confidence scores, bounding box coordinates, inference time and FPS, time-stamped system logs**, plus **errors and device statistics**.
- Data visualization: **Detection Frequency chart** (per day), **Inference Latency graph**, **FPS graph**, comparative **Accuracy/Precision/Recall/F1** chart, plus overview metrics + detailed logs on structured tabs.

### 2.6 Research evaluation (Ch. 3)

| Metric | Thesis requirement |
|---|---|
| Accuracy / Precision / Recall / F1 | Computed from detection logs / confusion matrix |
| mAP | Target **≥ 0.85** (0.933 @ IoU 0.5 cited as strong) |
| FPS | **≥ 15 FPS** targeted; 30 optimal, **10 adequate** |
| Latency | **≤ 300 ms**; ~303 ms considered "highly efficient" |
| SUS | 10-item System Usability Scale, benchmark **68** |
| Statistical testing | **One-sample t-test** of mean SUS vs 68; reject H₀ if p < 0.05 |
| Participants | ≥ **30** visually impaired participants, purposive sampling (WHO definition), controlled navigation testing, chest-mounted phone, supervised |
| Hypothesis | H₀: mAP < 0.85 **or** speed < 15 FPS **or** latency > 300 ms; H₁: mAP ≥ 0.85 **and** ≥ 15 FPS **and** ≤ 300 ms |

**In-app vs external distinction:** most evaluation metrics (mAP, precision/recall/F1 computation, SUS scoring, t-tests, participant recruitment) are **research procedures/tooling**, not shipped-app features. What the *app* must do is: (a) be usable by a blind person, and (b) **record** the raw telemetry (detections, confidence, inference time, FPS, timestamps) so those analyses can be performed. The app now records this telemetry ([`telemetry_service.dart`](../lib/services/telemetry_service.dart)).

---

## 3. Current Flutter Architecture

Verified directly from the code (not from docs).

### 3.1 Entry point

[`lib/main.dart`](../lib/main.dart) → `MaterialApp(home: AppShell())` with a dark high-contrast theme. Navigation via a 4-tab bottom bar.

### 3.2 Navigation — [`lib/navigation/app_shell.dart`](../lib/navigation/app_shell.dart)

- 4-tab bottom navigation: **Home, Detect, Settings, Help**, with lazy page building and state preservation (`IndexedStack`), system-back returns to Home, and Logs & Reports pushed as a route from Settings.

### 3.3 Screens

- [`home_screen.dart`](../lib/screens/home_screen.dart) — branding/subtitle, Auto-Start-aware status card, "Go to Live Camera" CTA.
- [`detection_screen.dart`](../lib/screens/detection_screen.dart) — the validated camera/inference pipeline preserved, now wrapped in the assistive UI: status pill, audio mute, detection object cards with priority badges, high-priority warning banner, visible high-contrast controls, gesture surface, and a camera-denied/error UI state.
- [`settings_screen.dart`](../lib/screens/settings_screen.dart) — Vibration, Auto-Start, Low Power, Audio/Voice, Logs & Reports entry.
- [`help_screen.dart`](../lib/screens/help_screen.dart) — how it works, gesture manual, confirmation, Android tips.
- [`logs_reports_screen.dart`](../lib/screens/logs_reports_screen.dart) — Overview / Charts / Logs dashboard.

### 3.4 Inference service — [`lib/services/inference_isolate.dart`](../lib/services/inference_isolate.dart)

- Persistent isolate (`Isolate.spawn` once), single `Interpreter`, pre-allocated dtype-matched buffers.
- Runtime model introspection ([`ModelMetadata`](../lib/models/model_metadata.dart), [`tflite_flatbuffer.dart`](../lib/models/tflite_flatbuffer.dart)).
- Manual YUV420→RGB (stride-aware), nearest-neighbor resize, metadata-driven quantization, input-tensor rotation/mirror to upright.
- Argmax per anchor → confidence threshold 0.25 → **class-wise NMS (IoU 0.45)**.
- Emits `List<Detection>` via a broadcast `StreamController` — consumed by the UI, TTS, and telemetry.
- **Historical audit finding (2026-08-16):** Error propagation used
  `{'type': 'error'}` only; bounded isolate restart recovery was not present in
  the revision assessed by this audit.

### 3.5 Assistive services (v0.2.0)

- [`tts_service.dart`](../lib/services/tts_service.dart) — `flutter_tts` wired via injectable `TtsEngine`; mute, cooldown, same-label de-duplication, urgent (high-priority) bypass, repeat-last, scan summary.
- [`gesture_controller.dart`](../lib/services/gesture_controller.dart) — pure state machine for the four thesis gestures; [`gesture_surface.dart`](../lib/widgets/gesture_surface.dart) is the transparent capture layer.
- [`settings_service.dart`](../lib/services/settings_service.dart) — file-backed JSON persistence via `path_provider`.
- [`spatial_analysis_service.dart`](../lib/services/spatial_analysis_service.dart) + [`detection_info.dart`](../lib/models/detection_info.dart) — left/center/right from box geometry, class-based priority tiers, approximate proximity band (labeled heuristic).
- [`haptics_service.dart`](../lib/services/haptics_service.dart) — `HapticFeedback` wrapper respecting the Vibration setting.
- [`telemetry_service.dart`](../lib/services/telemetry_service.dart) — session records, detection logs, latency/FPS samples, aggregates, per-minute frequency buckets.

### 3.6 Models / widgets / diagnostics

- Models: [`Detection`](../lib/models/detection.dart), [`DetectionInfo`](../lib/models/detection_info.dart), [`AppSettings`](../lib/models/app_settings.dart), [`BoxTransform`](../lib/models/box_transform.dart), [`ModelMetadata`](../lib/models/model_metadata.dart), [`tflite_flatbuffer.dart`](../lib/models/tflite_flatbuffer.dart), [`png_encoder.dart`](../lib/models/png_encoder.dart).
- Widgets: [`bounding_box_painter.dart`](../lib/widgets/bounding_box_painter.dart), [`detection_card.dart`](../lib/widgets/detection_card.dart), [`priority_badge.dart`](../lib/widgets/priority_badge.dart), [`warning_banner.dart`](../lib/widgets/warning_banner.dart), [`status_pill.dart`](../lib/widgets/status_pill.dart), [`accessible_button.dart`](../lib/widgets/accessible_button.dart), [`charts.dart`](../lib/widgets/charts.dart); the unused `info_panel.dart` / `debug_overlay.dart` widgets were removed in WS4.
- Diagnostics: [`forensic_log.dart`](../lib/services/forensic_log.dart) (file-based structured logs + PNG dumps, debug/profile only; release file I/O disabled); the `inference_probe.dart` / `input_probe.dart` files were removed in WS4.

### 3.7 Dependencies ([`pubspec.yaml`](../pubspec.yaml))

Used: `camera`, `tflite_flutter`, `ultralytics_yolo`, `permission_handler`, `path_provider` (settings + forensic log), `flutter_tts` (TTS service), `fl_chart` (charts). The previously unused `flutter_riverpod` dependency was removed in WS4; state uses `ChangeNotifier` + constructor injection + `setState`.

### 3.8 Tests

[`test/`](../test/) holds a real suite: navigation shell, screens, widgets (priority badge, detection card, warning banner, accessible button, charts), services (TTS, settings, spatial, telemetry, gesture controller), and theme. `flutter test` → **59 passing**; `flutter analyze` → **0 issues**.

### 3.9 Android config

[`android/app/build.gradle.kts`](../android/app/build.gradle.kts): package `com.example.eyecue_flutter`, `minSdk = flutter.minSdkVersion` (default 24; thesis targets Android 10 / API 29+), release build signs with the **debug** keystore. Android is the only supported platform (iOS/web/desktop scaffolding removed).

---

## 4. Thesis-to-Code Feature Matrix

Legend: ✅ COMPLETE · 🟡 PARTIAL · ❌ MISSING · ⚪ OUTSIDE APP / RESEARCH TOOLING · ❓ UNCLEAR

### 4.1 Core system

| Thesis requirement | Current Flutter equivalent | Relevant file(s) | Status | Evidence | Remaining work | Priority |
|---|---|---|---|---|---|---|
| Real-time object detection (YOLOv8) | Persistent-isolate inference, argmax + class-wise NMS | [`inference_isolate.dart`](../lib/services/inference_isolate.dart) | ✅ COMPLETE | `_parseYolov8Output` (argmax, conf 0.25, NMS IoU 0.45); on-device portrait detections 0.91 | None functional | — |
| LiteRT on-device | `tflite_flutter` 0.12.1 classic `Interpreter.fromBuffer` with raw `ByteBuffer` I/O for Custom; `ultralytics_yolo` 0.6.13 LiteRT Next path for Ultralytics | [`pubspec.yaml`](../pubspec.yaml), [`inference_isolate.dart`](../lib/services/inference_isolate.dart), [`ultralytics_detection_screen.dart`](../lib/screens/ultralytics_detection_screen.dart) | 🟡 IMPLEMENTED / DEVICE COMPARISON PENDING | Static/test/build checks plus controlled device protocol | Complete paired device runs | [`dual-inference-engine-test.md`](dual-inference-engine-test.md) |
| Smartphone camera | `camera` 0.12, `ResolutionPreset.low`, YUV420, `startImageStream` | [`detection_screen.dart`](../lib/screens/detection_screen.dart) | ✅ COMPLETE | `_setupCamera`, frame dispatch | None | — |
| On-device inference (no network) | Whole pipeline is local | [`inference_isolate.dart`](../lib/services/inference_isolate.dart) | ✅ COMPLETE | No network deps | None | — |
| Real-time processing | Busy-gate frame dropping; CPU-only (XNNPACK disabled — SIGSEGV) | [`detection_screen.dart`](../lib/screens/detection_screen.dart) | 🟡 PARTIAL | Frame-dropping works; throughput capped by CPU inference; informal on-device telemetry (Avg FPS ~2–3, Avg Latency ~600 ms on low-end device) but no formal report | XNNPACK/NNAPI/GPU investigation; formal FPS benchmark; metric redefinition | 🔴 High |
| Audio feedback / text-to-speech | `flutter_tts` wired via [`tts_service.dart`](../lib/services/tts_service.dart) | [`tts_service.dart`](../lib/services/tts_service.dart) | ✅ COMPLETE | Cooldown, de-dup, urgent bypass, mute, repeat-last, scan summary | Speech latency tuning; on-device TTS validation | 🟡 Medium |
| Object identity | `Detection.label` from `labels.txt` (80 COCO classes) | [`detection.dart`](../lib/models/detection.dart), `assets/labels.txt` | ✅ COMPLETE | Verified 80 labels | None | — |
| Confidence | `Detection.confidence`, threshold + display | [`inference_isolate.dart`](../lib/services/inference_isolate.dart) | ✅ COMPLETE | Confidence logged/rendered | None | — |
| Relative position (left/right/center) | `SpatialAnalysisService.analyze` → left/center/right from box geometry | [`spatial_analysis_service.dart`](../lib/services/spatial_analysis_service.dart), [`detection_info.dart`](../lib/models/detection_info.dart) | ✅ COMPLETE | Pure function over `Detection.box`; phrased in TTS | None functional | — |
| Approximate distance / spatial info | Approximate proximity band from box size/height (explicitly labeled heuristic) | [`spatial_analysis_service.dart`](../lib/services/spatial_analysis_service.dart) | 🟡 PARTIAL | Band is "approximately …", not calibrated distance | Calibrated distance estimation | 🟡 Medium |
| Movement / approach | **None** (no cross-frame tracking) | — | ❌ MISSING | No history-based motion logic | Temporal tracking (optional) | 🟡 Low |
| Priority / obstacle importance | Class-based priority tiers (HIGH/MEDIUM/LOW) | [`spatial_analysis_service.dart`](../lib/services/spatial_analysis_service.dart), [`priority_badge.dart`](../lib/widgets/priority_badge.dart) | ✅ COMPLETE | Priority badges + TTS urgent bypass | Tier calibration to thesis classes | 🟡 Medium |
| Audio alarm for dangerous barrier | High-priority warning banner + urgent TTS bypass | [`warning_banner.dart`](../lib/widgets/warning_banner.dart), [`tts_service.dart`](../lib/services/tts_service.dart) | ✅ COMPLETE | Urgent (high-priority) announcements bypass cooldown | Alarm phrasing/calibration | 🟡 Medium |

### 4.2 User interaction

| Thesis requirement | Current Flutter equivalent | Relevant file(s) | Status | Evidence | Remaining work | Priority |
|---|---|---|---|---|---|---|
| Start / exit detection mode (two-finger double tap) | `GestureController` two-finger double tap → start/stop | [`gesture_controller.dart`](../lib/services/gesture_controller.dart), [`gesture_surface.dart`](../lib/widgets/gesture_surface.dart) | ✅ COMPLETE | State machine + haptic/TTS confirmation | On-device validation | 🟡 Medium |
| Quick environmental scan (three-finger tap) | Three-finger tap → scan → TTS scene summary | [`gesture_controller.dart`](../lib/services/gesture_controller.dart) | ✅ COMPLETE | Scan summary implemented | On-device validation | 🟡 Medium |
| Repeat most recent audio alert (swipe down) | Swipe down → repeat-last-alert | [`tts_service.dart`](../lib/services/tts_service.dart), [`gesture_controller.dart`](../lib/services/gesture_controller.dart) | ✅ COMPLETE | Repeat-last implemented | On-device validation | 🟡 Medium |
| Pause / resume detection (single tap) | Single tap → pause/resume (camera preview stays live) | [`gesture_controller.dart`](../lib/services/gesture_controller.dart), [`detection_screen.dart`](../lib/screens/detection_screen.dart) | ✅ COMPLETE | Pause/resume state + dispatch throttle | On-device validation | 🟡 Medium |
| Change detection sensitivity | **None.** Threshold is a `const` (0.25) | [`inference_isolate.dart`](../lib/services/inference_isolate.dart) | ❌ MISSING | `kConfThreshold` const | Runtime-configurable threshold (thesis §2.4) | 🟡 Medium |
| Error/correction interaction | **None** (visible fallback controls exist, but no corrective-input gesture/interface) | — | ❌ MISSING | — | Error-signal path (design decision) | 🟡 Low |

### 4.3 Application screens / modules

| Thesis requirement | Current Flutter equivalent | Relevant file(s) | Status | Evidence | Remaining work | Priority |
|---|---|---|---|---|---|---|
| Home | [`home_screen.dart`](../lib/screens/home_screen.dart) | — | ✅ COMPLETE | Branding, subtitle, Auto-Start status card, "Go to Live Camera" | None functional | — |
| Detection | [`detection_screen.dart`](../lib/screens/detection_screen.dart) | — | ✅ COMPLETE | Assistive UI: status pill, object cards, priority badges, warning banner, controls, gestures, TTS | Blind-first polish, on-device validation | 🟡 Medium |
| Settings | [`settings_screen.dart`](../lib/screens/settings_screen.dart) | — | ✅ COMPLETE | Vibration, Auto-Start, Low Power, Audio, Logs & Reports | Sensitivity setting (add) | 🟡 Medium |
| Help | [`help_screen.dart`](../lib/screens/help_screen.dart) | — | ✅ COMPLETE | Operations + gesture manual + tips | None functional | — |
| Logs & Reports | [`logs_reports_screen.dart`](../lib/screens/logs_reports_screen.dart) + [`charts.dart`](../lib/widgets/charts.dart) | — | ✅ COMPLETE | Overview/Charts/Logs; latency/FPS/frequency charts; accuracy metrics shown as unavailable (require ground truth) | Accuracy/Precision/Recall/F1 comparative chart needs ground-truth tooling | 🟡 Medium |

### 4.4 Settings / configuration

| Thesis requirement | Status | Notes |
|---|---|---|
| Vibration / haptics | ✅ | `HapticFeedback` wrapper respecting setting |
| Automatic detection startup | ✅ | Auto-Start setting + Home status card |
| Low-power mode | ✅ | Low Power Mode setting → dispatch throttle |
| Sound / audio behavior | ✅ | Audio/Voice guidance setting + mute toggle |
| Detection configuration | ❌ | Sensitivity threshold still a hardcoded constant |
| Other runtime preferences | ✅ | Persisted via file-backed JSON (vibration, auto-start, low-power, audio) |

### 4.5 Research / telemetry

| Thesis requirement | Current Flutter equivalent | Relevant file(s) | Status | Evidence | Remaining work | Priority |
|---|---|---|---|---|---|---|
| Detection logs | `TelemetryService` detection log entries + Logs tab | [`telemetry_service.dart`](../lib/services/telemetry_service.dart) | ✅ COMPLETE | Chronological logs in Logs & Reports | Structured export (CSV/JSON) | 🟡 Medium |
| Confidence logs | Telemetry records confidence per detection | [`telemetry_service.dart`](../lib/services/telemetry_service.dart) | ✅ COMPLETE | Recorded per detection | Export | 🟡 Medium |
| Inference timing | Per-frame latency (`Stopwatch`) + telemetry samples | [`inference_isolate.dart`](../lib/services/inference_isolate.dart) | ✅ COMPLETE | Latency chart with 300 ms line | Formal results report | 🟡 Medium |
| FPS | Camera FPS + inference FPS + telemetry samples | [`telemetry_service.dart`](../lib/services/telemetry_service.dart) | ✅ COMPLETE | FPS chart with 15 FPS line | Formal results report | 🟡 Medium |
| Performance statistics | Overview tab aggregates | [`logs_reports_screen.dart`](../lib/screens/logs_reports_screen.dart) | ✅ COMPLETE | FPS, latency, detections, alerts, session duration | Export | 🟡 Medium |
| Charts / graphs | `fl_chart` latency/FPS/frequency charts | [`charts.dart`](../lib/widgets/charts.dart) | ✅ COMPLETE | Three charts with dynamic Y-bounds | Acc/Prec/Rec/F1 chart (needs ground truth) | 🟡 Medium |
| Evaluation metrics (Acc/Prec/Rec/F1/mAP) | **None** in-app | — | ❌ MISSING | Shown as "unavailable" (require ground truth) | ⚪ Research tooling (external or researcher tab) | 🟡 Low |
| Session information | Session records in telemetry | [`telemetry_service.dart`](../lib/services/telemetry_service.dart) | ✅ COMPLETE | Per-session aggregates | Export | 🟡 Medium |
| Data visualization | Reports dashboard with charts | [`logs_reports_screen.dart`](../lib/screens/logs_reports_screen.dart) | ✅ COMPLETE | Overview/Charts/Logs | — | — |

### 4.6 Research evaluation

| Thesis requirement | Status | Classification |
|---|---|---|
| Accuracy / Precision / Recall / F1 | ❌ MISSING (no computation anywhere) | ⚪ Offline/research tooling (from logs) |
| mAP | ❌ MISSING (bundled model is pre-trained COCO; no custom eval run recorded in repo) | ⚪ Offline/research tooling |
| FPS evaluation | 🟡 PARTIAL (measured in-app informally; no formal results report) | 🟡 In-app capture + external analysis |
| Inference/detection latency evaluation | 🟡 PARTIAL (measured; no formal report; end-to-end audio latency not yet measured) | 🟡 In-app capture + external analysis |
| SUS questionnaire | ❌ MISSING in-app (paper/external instrument — the app only needs to be usable to gather it) | ⚪ External instrument |
| Participant testing (≥30, controlled navigation) | ❌ Not performed | ⚪ Research procedure |
| Statistical testing (one-sample t-test vs 68) | ❌ Not performed | ⚪ External analysis |
| Controlled navigation testing | ❌ Not performed | ⚪ Research procedure |

---

## 5. Screen / UI Gap Analysis

The app now exposes all five thesis screens via 4-tab bottom navigation + a Logs & Reports route.

| Thesis screen | Exists? | Assessment |
|---|---|---|
| Home | ✅ | Branding, subtitle, Auto-Start status card, "Go to Live Camera", bottom nav |
| Detection | ✅ | Blind-first assistive UI: live preview + boxes, status pill, audio mute, object cards with priority, warning banner, visible controls, gesture surface. Not yet validated on-device with a blind user; TalkBack semantics are minimal. |
| Settings | ✅ | Vibration, Auto-Start, Low Power, Audio, Logs & Reports — persisted |
| Help | ✅ | Operations + gestures + confirmation + Android tips |
| Logs & Reports | ✅ | Overview / Charts / Logs researcher dashboard, reached from Settings |

**Overall screen verdict:** the thesis screen set is **implemented**. The remaining UI work is refinement — TalkBack/Semantics polish, detection-sensitivity setting, and a blind-user usability pass — rather than screen construction.

---

## 6. Assistive Functionality Gap Analysis (domains B, C, D)

The v0.2.x phase converted domains B/C/D from 0% to functional implementations layered on top of the untouched ML pipeline.

### Domain A — Vision / ML engine ✅ (~80%)
Complete: camera acquisition, YUV preprocessing, orientation, TFLite, YOLO parsing, NMS, confidence handling, detection stream, bounding boxes. Open: throughput/hardware acceleration validation, formal FPS/latency validation, and candidate stability. At the audit date, the v0.2.2 release path was CPU-only; the later candidate status is recorded in [`project-status.md`](project-status.md).

### Domain B — Spatial interpretation 🟡 (~65%)
Implemented as a pure layer over `Detection.box`: left/center/right classification, class-based priority tiers, and an approximate proximity band (labeled heuristic, not a calibrated distance). Missing: calibrated distance, movement/approach tracking, context-aware multi-object scene descriptions.

### Domain C — Audio guidance 🟡 (~70%)
`flutter_tts` wired with cooldown, same-label de-duplication, urgent (high-priority) bypass, mute, repeat-last-alert, and quick-scan summaries; phrasing includes relative position + approximate proximity. Missing: calibrated distance phrasing, speech-latency tuning, formal on-device TTS validation, and full-scene vs alert-mode distinction.

### Domain D — Accessibility / interaction 🟡 (~60%)
The four thesis gestures (two-finger double tap, single tap, three-finger tap, swipe down) with haptic + TTS confirmation; high-contrast 48dp+ fallback controls. Missing: comprehensive TalkBack/Semantics labels, the thesis's in-app correction interface, and on-device gesture validation.

---

## 7. Spatial Guidance Gap Analysis

> **Update:** the spatial-position gap identified in the original audit is now **implemented** (as an explicit heuristic layer), though it is not yet calibrated or movement-aware.

The thesis's operational definition of *Audio Feedback* is explicit: TTS "informs the user about detected objects **and their relative position**," and the Detection screen requires announcing "the type of the barrier and its **approximate position relative to the user**."

What the code now computes:

- [`DetectionInfo`](../lib/models/detection_info.dart) + [`spatial_analysis_service.dart`](../lib/services/spatial_analysis_service.dart): a pure function over [`Detection.box`](../lib/models/detection.dart) that produces:
  - **left / center / right** from box-center-X vs the frame (with a center band),
  - **priority tier** (HIGH / MEDIUM / LOW) from a class-based mapping (people, vehicles, doors, obstacles),
  - an **approximate proximity band** ("approximately near/mid/far") derived from box height/area — explicitly labeled as a heuristic, **not** a measured distance.
- This feeds the **TTS phrasing** ("person on your left, approximately close") and the **priority badge / warning banner** UI.

**Remaining:** there is still **no calibrated distance** (the box-size heuristic is uncalibrated), **no movement/approach detection** (no cross-frame tracking), and **no context-aware scene description** (the scan summary lists detections but does not yet compose a narrative). These are refinement items, not missing product blocks.

---

## 8. Research / Evaluation Gap Analysis

**What exists (strong):** per-frame inference latency, camera/inference FPS, confidence stats, forensic file logging with PNG dumps and auto-diagnosis, plus the new **runtime telemetry service** (session records, detection logs, latency/FPS samples, aggregates, per-minute frequency buckets) and the **Logs & Reports dashboard** with `fl_chart` latency/FPS/frequency charts and a Logs tab.

**What is missing to satisfy the thesis:**

1. **Comparative Accuracy/Precision/Recall/F1 chart** — the thesis specifies it; the app shows these as "unavailable" (they require ground truth / confusion-matrix tooling that does not exist yet). ❌ (This belongs in research tooling.)
2. **Structured, exportable logs** — telemetry is recorded in-app but there is no CSV/JSON export. 🟡
3. **Accuracy/precision/recall/F1 computation** — not performed anywhere. ❌ (External tooling.)
4. **mAP** — not computed; model is pre-trained COCO; no custom-dataset evaluation artifacts in the repo. ❌ (External tooling.)
5. **Formal FPS/latency results** — metrics are *measured* informally (on-device telemetry observed Avg FPS ~2–3, Avg Latency ~600 ms on the low-end test device) but there is no formal benchmark report; end-to-end **audio** latency is not yet measured. 🟡
6. **SUS / participant study / t-test** — research procedures; not started. ⚪ External. The app is now usable enough that a controlled study can begin.

**In-app vs external:** The app must record (detections, confidence, inference time, FPS, timestamps, errors) and render researcher charts — both are now in place. It should **not** compute mAP/SUS/t-tests inside the app — those remain offline analysis steps.

---

## 9. Production Readiness Gap Analysis

| Area | Status | Evidence / notes |
|---|---|---|
| Camera permission | ✅ | `permission_handler` + manifest entry |
| Permission-denied UI | ✅ | Camera-denied state with retry / open-settings ([`detection_screen.dart`](../lib/screens/detection_screen.dart)) |
| Crash / error recovery | 🟡 | Isolate errors reported + camera-error UI; **no isolate restart** |
| Release configuration | ❌ | Release build signs with **debug keystore** ([`build.gradle.kts`](../android/app/build.gradle.kts)); package `com.example.eyecue_flutter`; `minSdk` default 24 (thesis: Android 10 / API 29) |
| Play Store readiness | ❌ | No privacy policy, content rating, app icon/branding, release signing, package rename |
| Accessibility validation | 🟡 | Gestures + high-contrast controls done; TalkBack semantics partial; no blind-user study yet |
| Device testing | 🟡 | One Snapdragon 695 device; XNNPACK crash; front-camera/landscape re-validation pending |
| Battery / low-power | ✅ | Low Power Mode setting + dispatch throttle (battery optimization), camera pause deactivates inference |
| iOS / other platforms | ⚪ | Thesis is Android-only; scaffolding removed |

---

## 10. Target Flutter Architecture

The target architecture proposed in the original audit has, for the most part, **been implemented**. Mapping current files into the target (✅ = implemented):

```
lib/
├── main.dart                      # bootstrap (EXISTS)
├── navigation/
│   └── app_shell.dart             # ✅ bottom nav Home / Detect / Settings / Help
├── models/
│   ├── detection.dart             # EXISTS
│   ├── detection_info.dart        # ✅ spatial/priority/proximity info
│   ├── app_settings.dart          # ✅ persisted settings model
│   ├── telemetry_record.dart      # 🟡 telemetry lives in telemetry_service.dart (no standalone record file)
│   └── (box_transform, model_metadata, tflite_flatbuffer, png_encoder — EXIST)
├── services/
│   ├── inference_isolate.dart     # EXISTS — detection engine (keep as-is)
│   ├── spatial_analysis_service.dart  # ✅ Detection.box → position/priority/proximity (pure)
│   ├── tts_service.dart           # ✅ flutter_tts wrapper; cooldown; de-dup; urgent; repeat-last
│   ├── haptics_service.dart       # ✅ HapticFeedback wrapper
│   ├── settings_service.dart      # ✅ file-backed persistence (JSON)
│   ├── telemetry_service.dart     # ✅ session records + aggregates
│   ├── gesture_controller.dart    # ✅ four thesis gestures (pure state machine)
│   └── (forensic_log.dart EXISTS — dev diagnostics)
├── screens/
│   ├── home_screen.dart           # ✅
│   ├── detection_screen.dart      # ✅ evolved from camera_screen.dart (retired/removed)
│   ├── settings_screen.dart       # ✅
│   ├── help_screen.dart           # ✅
│   └── logs_reports_screen.dart   # ✅ Logs & Reports (fl_chart charts)
├── widgets/
│   ├── bounding_box_painter.dart  # EXISTS
│   ├── detection_card.dart        # ✅
│   ├── priority_badge.dart        # ✅
│   ├── warning_banner.dart        # ✅
│   ├── status_pill.dart           # ✅
│   ├── accessible_button.dart     # ✅ high-contrast controls
│   ├── gesture_surface.dart       # ✅ gesture capture layer
│   ├── charts.dart                # ✅ fl_chart wrappers
│   └── (info_panel.dart, debug_overlay.dart were removed in WS4)
```

**Not yet in place:** a standalone `utterance_builder.dart` (phrasing is currently built inside the TTS/spatial layer), standalone `telemetry_record.dart`, and the in-app correction interface. These are refinements, not structural gaps.

**Thesis requirements this now covers:** all 5 screens; gestures; TTS + spatial + priority audio; settings; telemetry; charts; accessibility (partial); production hardening (partial).

---

## 11. Completion Estimates

Percentages are **weighted by thesis emphasis**, not counted by files. The thesis is co-titled "Object Recognition **and Audio Guidance**," so the audio/spatial/accessibility layers are weighted as heavily as the detection engine. Ranges are given because several items are partially measurable (e.g. "real-time processing" throughput) or unvalidated on-device.

### Domain completion (evidence-based)

| # | Domain | Weight | Completion | Basis |
|---|---|---|---|---|
| A | Vision / ML engine | 30% | ~80% | Camera, YUV, orientation, TFLite, parsing, NMS, confidence, stream, boxes all verified in code; open items = hardware acceleration + formal FPS/latency |
| B | Spatial interpretation | 15% | ~65% | left/center/right + priority + approximate proximity implemented (pure layer, heuristic); no calibrated distance / movement tracking |
| C | Audio guidance | 20% | ~70% | `flutter_tts` wired (cooldown, de-dup, urgent, repeat, scan, mute); phrasing includes position + proximity; needs calibration + latency tuning |
| D | Accessibility / interaction | 12% | ~60% | all four thesis gestures + haptics + high-contrast controls; TalkBack semantics + correction interface + on-device validation pending |
| E | Application UI | 10% | ~80% | all five screens + navigation + settings implemented; blind-first polish + semantics remaining |
| F | Research instrumentation | 8% | ~75% | telemetry + charts + logs done; structured export + accuracy computation missing |
| G | Research evaluation | 3% | ~10% | metrics measured informally in-app; no formal accuracy/precision/recall/F1/mAP/SUS/t-test data |
| H | Production readiness | 2% | ~25% | permission UI done; no release config, isolate restart, Play Store, accessibility validation |

### Weighted total

```
A: 30% × 0.80 = 24.0
B: 15% × 0.65 =  9.75
C: 20% × 0.70 = 14.0
D: 12% × 0.60 =  7.2
E: 10% × 0.80 =  8.0
F:  8% × 0.75 =  6.0
G:  3% × 0.10 =  0.3
H:  2% × 0.25 =  0.5
────────────────────────
                 ≈ 69.75%  →  Overall thesis-product completion ≈ 70% (range 65–75%)
```

### Reading the numbers

- **Vision/ML completion:** ~80% — the pipeline genuinely works.
- **Assistive-functionality completion:** ~65% (spatial ~65%, audio ~70%, interaction ~60%).
- **UI/application completion:** ~80%.
- **Research/evaluation completion:** ~30% (instrumentation ~75% + evaluation ~10%).
- **Production-readiness:** ~25%.
- **Overall thesis-product:** **~70%**.

### Discrepancy with existing docs

- The original audit (pre-v0.2.0) computed **~30%** and described a single silent developer camera screen. That was accurate for that snapshot; the v0.2.x phase has since implemented the assistive product layer. This revision supersedes the ~30% figure.
- [`docs/known-issues.md`](known-issues.md) previously listed `path_provider`, `fl_chart`, and `flutter_tts` as unused — **stale**; all three are now used. The remaining unused `flutter_riverpod` dependency was removed in WS4.
- [`README.md`](../README.md) and [`docs/project-status.md`](project-status.md) now reflect v0.2.2 (59 tests, 0 analyze issues).

---

## 12. Critical Missing Features

### The single biggest remaining gap

> **Research evaluation + production hardening, not missing product features.** The core assistive product — audio guidance, spatial/priority interpretation, gestures, all five screens, settings, and telemetry/charts — is now implemented. What would prevent a successful thesis defense is the **absence of formal evaluation data** (FPS/latency/accuracy/recall/F1/mAP results, the ≥30-participant SUS study) and **production readiness** (release signing, package rename, isolate restart recovery).

### The next 5 highest-impact gaps (prioritized)

1. **Formal evaluation metrics** (FPS, latency, accuracy/precision/recall/F1, mAP) — the thesis's core hypothesis (mAP ≥ 0.85 **and** ≥ 15 FPS **and** ≤ 300 ms) cannot be argued without measured results. Metric definitions must be reconciled first (see §14).
2. **XNNPACK/NNAPI/GPU acceleration** — without it, CPU-only throughput may fail the ≥15 FPS hypothesis on the target device.
3. **Production/release hardening** — release signing, package rename (`com.eyecue`), minSdk alignment, Play Store artifacts, privacy policy.
4. **Isolate restart recovery** — a crash during a supervised study must self-heal.
5. **Accessibility polish + controlled usability study** — TalkBack semantics, on-device gesture validation, then the ≥30-visually-impaired-participant SUS + navigation study.

---

## 13. Recommended Development Phases

> Phases are advisory; order follows dependency + thesis-impact. Status reflects the v0.2.2 codebase.

### Phase A — Vision validation (small) 🟡 in progress
- Resolve XNNPACK SIGSEGV (benchmark tool; test NNAPI/GPU with CPU fallback); formal FPS/latency measurement; orientation re-validation (back landscape + front camera).

### Phase B — Assistive core (highest thesis impact) ✅ done (v0.2.0)
- **TTS service** (`flutter_tts`) wired to the detection stream with cooldown/de-dup/urgent/repeat; **spatial service** (left/center/right + approximate proximity); **priority tiers** + high-priority warning/urgent audio. Calibration refinement remains.

### Phase C — Accessibility / interaction 🟡 mostly done (v0.2.0)
- Gesture controller (four thesis gestures), pause/resume, quick environmental scan, repeat-last-alert, haptics, high-contrast theme. Remaining: TalkBack/Semantics polish, in-app correction interface, on-device gesture validation.

### Phase D — Application UI ✅ done (v0.2.0–v0.2.2)
- Home (status card, "Go to Live Camera"), bottom navigation (Home/Detect/Settings/Help), Settings (vibration, auto-start, low-power, audio) with persistence, Help, and the Logs & Reports screen (charts), plus layout/theme fixes. Remaining: detection-sensitivity setting.

### Phase E — Research evaluation ❌ not started
- Structured telemetry export; accuracy/recall/F1/mAP computation (offline tooling); run the controlled navigation study with ≥30 participants; SUS + one-sample t-test. Fix the thesis's FPS/latency metric definitions first (see §14).

### Phase F — Production release 🟡 partial
- ✅ Permission-denied UI done. Remaining: isolate restart recovery, package rename (`com.eyecue`), minSdk 29 per thesis, release signing, privacy policy/content rating, device-matrix testing, Play Store submission.

---

## 14. Risks / Dependencies

1. **Thesis metric inconsistency (defense risk):** Hypothesis states ≥15 FPS **and** ≤300 ms latency, but 300 ms implies ≤3.3 FPS. [`docs/research-notes.md`](../docs/research-notes.md:30) already flags this. Must be redefined (camera FPS vs detection FPS vs end-to-end audio latency) before defense.
2. **Thesis names React Native** in the "Software Framework" section while the implementation is Flutter. The methodology is stated as technology-agnostic, so this is a **documentation inconsistency in the thesis that should be revised** — not a reason to return to React Native.
3. **XNNPACK SIGSEGV** blocks throughput; CPU-only may fail the ≥15 FPS hypothesis on the target device. Mitigate with NNAPI/GPU/fallback + realistic metric definitions.
4. **Participant recruitment** (≥30 VI participants, ethical consent, supervised sessions) is a schedule risk and requires a *usable* audio app first — the app is now usable enough that this can begin.
5. **Calibrated distance** — the current proximity band is a box-size heuristic; if the thesis is read as requiring measured distance, calibration or an explicit limitation note is needed.
6. **TTS engine availability** — platform quirks (engine availability, speech latency on low-end devices) need on-device validation.
7. **Battery drain** (thesis lists it as a limitation) — Low Power Mode and camera-deactivation-on-pause are implemented; battery measurements are still needed.

---

## 15. Explicit "What Is Already Complete"

Verified in code:

- **Camera acquisition:** init, permission request, YUV420 low-resolution stream, frame-dropping busy gate, resource cleanup, permission-denied UI.
- **Inference engine:** persistent isolate, single `Interpreter`, runtime model introspection, dtype-matched buffers, raw `ByteBuffer` I/O, dynamic NHWC/NCHW handling, FLOAT16/INT8/UINT8 support.
- **Preprocessing:** stride/pixel-aware manual YUV420→RGB (I420 + NV12/NV21), nearest-neighbor resize, metadata-driven quantization.
- **Orientation:** device-independent `BoxTransform`; input rotated/mirrored to upright; on-device portrait detections validated (0 → 0.91).
- **Post-processing:** argmax per anchor, confidence threshold 0.25, class-wise NMS (IoU 0.45).
- **Detection output:** class label, confidence, normalized bounding box; streamed to UI.
- **Overlay:** bounding boxes + label pills + confidence via `CustomPainter`, aligned with the preview (`applyBoxFit`).
- **Spatial / priority:** left/center/right, class-based priority tiers, approximate proximity band (labeled heuristic).
- **Audio guidance:** `flutter_tts` wired — cooldown, same-label de-duplication, urgent (high-priority) bypass, mute, repeat-last, quick-scan summary; phrasing includes position + proximity.
- **Interaction:** four thesis gestures (two-finger double tap, single tap, three-finger tap, swipe down) with haptic + TTS confirmation; visible high-contrast fallback controls.
- **Screens & navigation:** Home / Detect / Settings / Help + Logs & Reports (Overview/Charts/Logs).
- **Settings persistence:** file-backed JSON (vibration, auto-start, low-power, audio).
- **Research instrumentation:** runtime telemetry (sessions, detection logs, latency/FPS samples, aggregates) + `fl_chart` charts + forensic file logging with PNG dumps and auto-diagnosis.
- **Developer diagnostics:** metrics panel, 5-second performance summaries, error propagation to the main isolate.
- **On-device, offline, privacy-preserving** end-to-end detection.

---

## 16. Explicit "What Is Still Missing"

- **Calibrated spatial semantics:** measured distance, movement/approach tracking, context-aware scene descriptions.
- **Research evaluation execution:** formal FPS/latency results, accuracy/precision/recall/F1/mAP computation, SUS collection, one-sample t-test, ≥30-participant controlled navigation study.
- **Structured telemetry export:** CSV/JSON export of session/detection data for offline analysis.
- **Detection-sensitivity setting** (thesis §2.4 — runtime-configurable confidence threshold).
- **Accessibility polish:** comprehensive TalkBack/Semantics labels, in-app correction interface.
- **Production hardening:** isolate restart recovery, release signing, package rename (`com.eyecue`), minSdk alignment (API 29), Play Store artifacts (privacy policy, content rating), device-matrix testing.
- **Hardware acceleration:** comparative XNNPACK/NNAPI/GPU validation. The committed candidate has initial XNNPACK device evidence, but selection of a release backend remains open.
- **On-device validation:** gestures, TTS, settings persistence, Logs & Reports on the Snapdragon 695 device; candidate back-landscape and front-camera orientation re-validation.

---

## 17. Conclusion

> **If we froze development today, what genuinely works:** a complete thesis-aligned assistive application — real-time on-device YOLOv8/TFLite detection (camera → isolate → preprocessing → inference → NMS → bounding boxes), **spoken audio guidance with relative position and priority**, **gesture-based nonvisual interaction**, **all five application screens with persisted settings**, and a **research telemetry/charts dashboard** — running offline on Android. This is roughly **80% of the computer-vision engine** and, after the v0.2.x phase, a **substantial majority of the usable product** (~70% weighted overall).

> **What is still missing:** the evidence and polish that make a thesis defensible — formal FPS/latency/accuracy/mAP evaluation, the SUS/participant study, production release hardening (signing, package rename, isolate restart recovery), and refinement of the heuristic layers (calibrated distance, TalkBack semantics).

> **What must be completed before we can honestly call this the final EyeCue product:** (1) resolve the thesis metric definitions and measure FPS/latency formally (XNNPACK/NNAPI/GPU if possible), (2) run the accuracy/mAP + SUS/participant study, (3) production-release hardening, and (4) accessibility + on-device validation polish.

In short: **the eyes of EyeCue were already nearly complete; the voice, the hands, the screens, and the data dashboard — its entire reason to exist — are now built.** The honest thesis-product completion today is approximately **70%**, with the remaining ~30% concentrated in evaluation, hardening, and refinement rather than core product construction.
