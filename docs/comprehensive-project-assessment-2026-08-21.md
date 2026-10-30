# EyeCue Comprehensive Project Assessment and Performance Strategy

**Assessment date:** 2026-08-21
**Repository assessed:** `eyecue_flutter`
**Assessed revision:** `146c2e7` (`main`, matching `origin/main` at the time of assessment)
**Scope:** Repository contents, documentation, application code, tests, Android configuration, assets, inference pipeline, research-readiness claims, performance opportunities, and multi-device deployment strategy.

> **Historical assessment notice (2026-08-21):** This document is a point-in-time
> assessment of revision `146c2e7` and preserves the evidence and conclusions
> observed at that revision, including its 59-test baseline and then-current
> model/runtime inventory. It is not the current implementation status.
> **Superseding status (2026-09-05):** The app-only candidate now includes
> bounded generation-safe Custom-worker recovery, persisted sensitivity,
> Custom/Ultralytics engine coordination, correction capture, image-free
> JSON/CSV export, tracking/scene summaries, expanded accessibility coverage,
> and metadata-safe runtime packaging. Current implementation and release gates
> are tracked in [`project-status.md`](project-status.md) and
> [`implementation-progress.md`](implementation-progress.md). The historical
> assessment's research, broad-device, native-crash, licensing, Android
> identity/signing, and Play-release risks remain relevant unless those current
> documents explicitly mark them resolved.
>
> **WS4 addendum (2026-10-19):** forensic file writes and PNG dumps are now gated
> out of release builds (`!kReleaseMode`); debug/profile still write them, and
> some eager forensic CPU calculations remain. The dated "always-on" cost
> observation below is therefore historical, and no measured speed or storage
> improvement is claimed.

## Executive Summary

EyeCue is a credible, compiling thesis prototype with a valid YOLOv8n TensorFlow Lite model, a modular Flutter application, an offline inference architecture, assistive interaction features, and unusually extensive development documentation.

The project is not yet ready for unsupervised navigation, formal research evaluation, or production distribution. The largest risks are:

1. User-visible assistive behavior does not always match the documentation, especially Auto-Start and the initial two-finger start gesture.
2. The camera and inference startup path contains a race around the inference-isolate handshake.
3. Several COCO class IDs are assigned incorrect navigation priorities.
4. Always-on forensic logging adds storage, privacy, latency, and thermal costs that are excluded from the reported inference metric.
5. The automated suite does not exercise the critical camera, preprocessing, model, parser, NMS, orientation, or forensic pipeline.
6. Documentation contains contradicted claims, stale historical links, inconsistent versioning, and unsupported research statements.
7. Android release configuration, licensing, privacy, accessibility validation, and device-matrix testing remain incomplete.

The best performance strategy for broad Android support is not one fixed model or delegate. EyeCue should use a guaranteed CPU baseline with progressively enhanced GPU/NNAPI/NPU paths, multiple model input tiers, on-device benchmarking, correctness validation, cached device profiles, and runtime fallback.

## 1. Assessment Scope and Repository Inventory

The active project is located at `/home/nico/repos/eyecue_flutter`. The similarly named workspace at `/home/nico/Documents/ChatGPT/Eyecue` contained only an unborn Git repository and empty support directories during the assessment.

The active repository contained 102 tracked files:

| Category | Count |
|---|---:|
| Application Dart files under `lib/` | 34 |
| Dart test files | 10 |
| Markdown documents | 25 |
| Diagnostic tools | 4 |
| Assets | 4 |
| Android files | 19 |
| Other configuration files | 6 |

The assessment covered all tracked application source, tests, tools, assets, Android configuration, README content, current status documents, investigation reports, historical records, and thesis audit material.

No application code was changed as part of the technical assessment. The only repository change made afterward was the addition of this assessment document at the user's request.

## 2. Verification Results

The following non-destructive checks were run against the clean repository:

| Verification | Result |
|---|---|
| Flutter version | 3.44.2 stable |
| Dart version | 3.12.2 |
| `flutter analyze` | Passed, 0 issues |
| `flutter test` | Passed, all 59 tests |
| Android debug build | Passed |
| Debug APK size | 194,452,262 bytes |
| TFLite FlatBuffer validator | Passed for both tracked models |
| Active model graph tools | Passed |
| Pure-Dart PNG encoder validator | Passed signature, chunk, CRC, and dimension checks |
| Git state after verification | Clean tracked tree |

The Android build emitted a forward-compatibility warning: the current `flutter_tts` plugin still applies the Kotlin Gradle Plugin, which a future Flutter version plans to reject.

The built APK contained:

- `assets/yolov8n.tflite`
- `assets/labels.txt`
- `assets/test_image.jpg`

The tracked `assets/yolov8n_int8.tflite` file was not declared in `pubspec.yaml` and was therefore not included in the application bundle.

## 3. Verified Strengths

### 3.1 Build and repository health

- The tracked repository was clean and synchronized with `origin/main` during the assessment.
- Static analysis was clean.
- All 59 existing tests passed.
- The Android debug application compiled and packaged successfully.
- The app is organized into models, services, screens, navigation, widgets, tests, assets, and diagnostic tools.

### 3.2 Offline inference architecture

- Application inference is local; no application network calls were found.
- The main Android manifest requests camera permission but not general internet access.
- The model is created once in a persistent isolate rather than once per frame.
- A latest-frame/busy-gate policy prevents an unbounded inference queue.
- Runtime metadata drives current input/output buffer allocation and quantization decisions.

### 3.3 Model and assets

- `assets/labels.txt` contains the expected 80 COCO labels.
- The active model graph has an input shape of `[1, 640, 640, 3]` and output shape of `[1, 84, 8400]`.
- The graph produces four decoded box channels plus 80 class-score channels.
- Both tracked model files are structurally valid TFLite FlatBuffers.
- The static test image is a valid JPEG and supports the repository's diagnostic path.

### 3.4 Product structure

The repository genuinely contains:

- Home, Detect, Settings, Help, and Logs & Reports experiences.
- TTS integration with cooldown, de-duplication, repeat, scan, and mute behavior.
- Relative-position and approximate-proximity descriptions.
- High/medium/low class-based priority tiers.
- Four gesture concepts with haptic/TTS feedback.
- File-backed settings.
- Runtime telemetry and charts.
- Orientation metadata and input rotation logic.

These features exist in code even where additional validation or correction is required.

## 4. High-Priority Functional Findings

### 4.1 Auto-Start does not run at application launch

`AppShell` initially builds only the Home page. The Detect page is constructed lazily after the user first opens the Detect tab. Detection auto-start logic resides in `DetectionScreen.initState`, so it cannot run before that screen exists.

The Home status card nevertheless says that the camera began detecting when the app opened. This is a functional and documentation mismatch, not just a wording issue.

Relevant files:

- [`lib/navigation/app_shell.dart`](../lib/navigation/app_shell.dart)
- [`lib/screens/detection_screen.dart`](../lib/screens/detection_screen.dart)
- [`lib/screens/home_screen.dart`](../lib/screens/home_screen.dart)
- [`lib/screens/settings_screen.dart`](../lib/screens/settings_screen.dart)

### 4.2 Initial two-finger start gesture is unavailable

When Auto-Start is disabled and the camera has never been initialized, the pending screen instructs the user to use a two-finger double tap on the preview. The transparent `GestureSurface` is only mounted inside the initialized viewport, so the gesture cannot start the first camera session from the pending state.

The visible Start button works, but the nonvisual interaction promise does not.

### 4.3 Inference-isolate startup race

`DetectionScreen.initState` starts `InferenceService.initIsolate()` without awaiting it, subscribes to streams, and may immediately start the camera. The camera frame path calls `processFrame`, which sends through a late-initialized `_sendPort` without awaiting the isolate's readiness completer.

If a camera frame arrives before the handshake, the send can fail with a `LateInitializationError`. Because the UI busy flag is set before dispatch, this can also prevent later frames from progressing normally.

Relevant files:

- [`lib/screens/detection_screen.dart`](../lib/screens/detection_screen.dart)
- [`lib/services/inference_isolate.dart`](../lib/services/inference_isolate.dart)

### 4.4 Generic camera/model error UI is missing

Permission denial is handled with a visible recovery screen, but the initial calls to `availableCameras`, controller initialization, stream startup, model loading, and isolate initialization do not produce a general rendered error state.

Several documents claim that a camera-error UI exists. The implementation provides a permission-denied UI, not a complete camera/model startup error UI.

### 4.5 Camera selection is not guaranteed to be rear-facing

The application selects `cameras[0]` and comments that it is the back camera. Camera enumeration order is not an application-level guarantee. A device may return a front, external, or otherwise unexpected camera first.

### 4.6 Camera lifecycle and hidden-tab behavior

The Detect page is preserved by an `IndexedStack`. After it has been visited, camera inference can continue while the user is on Home, Settings, or Help. No `WidgetsBindingObserver` or application lifecycle handler was found to explicitly stop or resume the stream during background/inactive transitions.

This may be intentional for continuous assistance, but the battery and privacy behavior should be explicit and user-controlled.

## 5. Spatial Priority and TTS Findings

### 5.1 Incorrect COCO priority IDs

The medium-priority table contains shifted IDs. Comparing `SpatialAnalysisService` with `assets/labels.txt` shows the following behavioral errors:

| Intended medium class omitted | Unintended medium class included |
|---|---|
| Elephant, class 20 | Bear, class 21 |
| Banana, class 46 | Spoon, class 44 |
| Oven, class 69 | Scissors, class 76 |

Several adjacent comments are also one position away from the actual label. Existing tests do not detect the problem because they repeat an incorrect comment: class 73 is described as refrigerator, although class 73 is book. Refrigerator is class 72.

Relevant files:

- [`lib/services/spatial_analysis_service.dart`](../lib/services/spatial_analysis_service.dart)
- [`assets/labels.txt`](../assets/labels.txt)
- [`test/services/spatial_analysis_service_test.dart`](../test/services/spatial_analysis_service_test.dart)

### 5.2 TTS de-duplication can suppress unsaid detections

`announceDetections` records the selected label and timestamp before calling `speak`. `speak` may then decline the utterance because audio is muted or the global cooldown is active. That object is still treated as recently announced and may be suppressed for the same-label cooldown despite never reaching the speech engine.

### 5.3 The TTS service is not a queue

Documentation repeatedly calls the implementation a priority-based TTS queue. The service actually selects one primary detection and applies priority ordering, cooldowns, and urgent bypass behavior. It does not maintain or drain an utterance queue.

### 5.4 Muting does not explicitly stop current speech

Changing `audioEnabled` prevents future calls but does not stop an utterance already being spoken by the engine.

Relevant file:

- [`lib/services/tts_service.dart`](../lib/services/tts_service.dart)

## 6. Telemetry and Research-Metric Findings

### 6.1 Detection totals are retained-window totals

Telemetry retains at most 2,000 detection records, and `totalDetections` returns the current list length. After the cap is reached, it no longer represents the full session total.

### 6.2 “High-priority alerts” counts detections, not alerts

The high-priority counter increments for every high-priority detection record. It is not connected to whether TTS actually announced an alert. At inference frequency, the same object can therefore be counted repeatedly.

### 6.3 FPS is derived rather than measured end to end

The reported inference FPS is calculated from reciprocal rolling model latency. The stopwatch covers only `interpreter.run()`. It excludes:

- Isolate transfer
- YUV conversion and resizing
- Tensor rotation/mirroring
- Output parsing and NMS
- Forensic output rescans
- Synchronous file writes
- Main-isolate UI, telemetry, and TTS work

The metric is useful as model-kernel throughput but should not be labeled full pipeline FPS.

### 6.4 Research charts lack explanatory axes

The three `fl_chart` widgets hide titles and axes. This makes it difficult to interpret units, time progression, and exact meaning, and leaves limited semantic content for accessibility services.

Relevant files:

- [`lib/services/telemetry_service.dart`](../lib/services/telemetry_service.dart)
- [`lib/screens/detection_screen.dart`](../lib/screens/detection_screen.dart)
- [`lib/widgets/charts.dart`](../lib/widgets/charts.dart)
- [`lib/screens/logs_reports_screen.dart`](../lib/screens/logs_reports_screen.dart)

## 7. Forensic Logging, Privacy, and Performance

### 7.1 Always-on raw-frame retention

`ForensicLog.enabled` and `dumpImages` are compile-time `true`. Each initialized inference session creates a timestamped debug directory under application documents and may save camera-frame imagery, model-input imagery, parser output, tensor statistics, performance logs, and summaries.

The repository provides no user setting, consent flow, retention limit, automatic deletion, encryption layer, or in-app export/delete control for these artifacts.

The data remains on-device and application-private, but retaining raw camera imagery materially qualifies the project's broad “privacy-preserving” claim.

### 7.2 Synchronous storage work

Every forensic text append uses synchronous file I/O with `flush: true`. PNG encoding and writing are also synchronous inside the inference isolate. These choices improve crash survivability of diagnostics but reduce throughput and increase storage and thermal activity.

### 7.3 Redundant per-frame output scan

After the parser has scanned all `8400 × 80` class scores, `recordPerformance` scans them again solely to find maximum confidence. This adds approximately 672,000 class-value visits per processed frame.

On diagnostic dump frames, `recordParser` constructs and sorts an entry for every anchor/class combination to display only the top 20.

### 7.4 Incomplete final summary behavior

Forensic state is isolate-local. `InferenceService.dispose` finalizes logging in the main isolate and immediately kills the inference isolate. Most inference statistics live in the worker isolate, so the claimed final on-close summary is not guaranteed to contain the worker's complete accumulated state.

The static finalized/closed state is also not reset for a later service lifecycle inside the same isolate.

Relevant file:

- [`lib/services/forensic_log.dart`](../lib/services/forensic_log.dart)

## 8. Inference-Pipeline Findings

### 8.1 Current model characteristics

Read-only tensor inspection found:

| Model | Input | Output | Practical classification |
|---|---|---|---|
| `yolov8n.tflite` | FLOAT32 `[1,640,640,3]` | FLOAT32 `[1,84,8400]` | Weight-quantized / float activation path |
| `yolov8n_int8.tflite` | FLOAT32 `[1,640,640,3]` | FLOAT32 `[1,84,8400]` | Also retains float I/O and many float tensors |

The alternate filename therefore should not be treated as proof of full-integer inference.

### 8.2 Per-frame orientation allocation

After conversion, the orientation path clones the complete input tensor and performs a second full-frame pass. A FLOAT32 640×640×3 tensor is approximately 4.9 MB, contradicting documentation that claims no per-frame allocations.

Rotation and mirroring can instead be fused into the YUV-to-model source-coordinate mapping.

### 8.3 Model-layout portability is overstated

The converter can write NHWC or NCHW layouts, but the later rotation helper always indexes data as interleaved RGB/NHWC. Rotated or mirrored NCHW models would therefore be handled incorrectly.

The rotation helper also skips non-square models.

### 8.4 Output-layout portability is limited

`ModelMetadata` and the YOLO parser expect `[1, 4+C, N]`. Documentation claims broader dynamic support, including layouts such as `[1,25200,85]`, which the current parser does not implement.

### 8.5 Chroma geometry is not fully per-plane

The application forwards both U and V row/pixel strides, but conversion uses the U row stride for both planar chroma planes and reads semi-planar V from the U buffer. This worked with the documented test device geometry but is not fully portable across every valid Android `YUV_420_888` layout.

### 8.6 Stretch resize and nearest-neighbor sampling

Camera imagery is stretched directly to the square model input with nearest-neighbor sampling. The pipeline does not use the letterbox preprocessing typically associated with Ultralytics YOLO exports. This changes object proportions and can reduce accuracy, particularly when source aspect ratios vary by device.

### 8.7 Boundary boxes and NMS

The parser clamps left and top coordinates but stores independently clamped width and height. Right or bottom can therefore exceed normalized bounds. NMS area and IoU calculations may be biased for boxes crossing image edges even though painting visually clips them.

NMS is quadratic and has no pre-NMS top-K limit.

Relevant files:

- [`lib/services/inference_isolate.dart`](../lib/services/inference_isolate.dart)
- [`lib/models/model_metadata.dart`](../lib/models/model_metadata.dart)
- [`lib/models/box_transform.dart`](../lib/models/box_transform.dart)

## 9. Automated Test Assessment

The 59 passing tests cover useful application and service behavior:

- Navigation shell
- Screen smoke tests
- Settings behavior
- Gesture controller
- TTS selection/cooldown behavior
- Spatial helper behavior
- Telemetry aggregates
- Theme construction
- Cards, badges, banners, buttons, and chart construction

The following critical paths are not covered by automated tests:

- Actual model creation and tensor inspection
- Isolate handshake and startup timing
- Camera permission/error integration
- Camera frame dispatch and busy-gate recovery
- YUV420-to-RGB correctness
- Row/pixel stride variants
- Quantization and dequantization
- YOLO output parsing
- NMS and boundary cases
- Tensor orientation and NCHW handling
- Painter coordinate alignment with real camera previews
- Forensic log lifecycle and retention
- Application lifecycle camera behavior
- TalkBack/live-region semantics
- Android device integration

`docs/testing-plan.md` accurately lists many of these as future work. `docs/implementation-plan.md` incorrectly marks core YUV, parser, dequantization, and NMS unit testing complete by associating them with the unrelated 59-test total.

Relevant files:

- [`test/`](../test/)
- [`docs/testing-plan.md`](testing-plan.md)
- [`docs/implementation-plan.md`](implementation-plan.md)

## 10. Documentation Assessment

### 10.1 Accurate or substantially accurate content

The following repository claims were verified or appropriately qualified:

- Android-only tracked application scaffolding
- Offline application inference
- Current dependency usage, including intentionally unused Riverpod
- 59 passing tests and clean analysis
- Active model input/output structure and 80 labels
- CPU-only performance limitation in the current implementation
- Missing formal FPS, accuracy, mAP, SUS, and participant-study evidence
- Release signing, package-name, and Play Store readiness gaps
- Pending front-camera and landscape device validation
- Approximate proximity being a heuristic rather than measured distance

### 10.2 Claims contradicted by implementation

- Auto-Start begins detection when the app opens.
- A generic camera-error UI exists.
- UI, TTS, and telemetry independently subscribe to the broadcast detection stream.
- TTS uses a priority queue.
- Input/output buffers cause no per-frame allocation.
- Core inference-pipeline unit tests are complete.
- Arbitrary dynamic YOLO output layouts are supported.
- Inference is fully per-plane-geometry portable.
- “High-priority alerts” represent actual alerts.

In reality, DetectionScreen has one result listener that performs UI, telemetry, and TTS work sequentially.

### 10.3 Versioning inconsistencies

- Documentation calls the project `v0.2.2`.
- `pubspec.yaml` and the built APK report `1.0.0+1` / `1.0.0`.
- No Git tags were present.
- Changelog ordering is not consistently chronological.

The README says “Requires Flutter SDK >=3.12.0,” but the corresponding `pubspec.yaml` field is a Dart SDK constraint, not a Flutter SDK constraint.

### 10.4 Link integrity

A local Markdown-link audit found 40 non-resolving local targets across `README.md` and `docs/`. Most point to the removed `camera_screen.dart` or use unsupported `file.dart:line` paths instead of valid Markdown/GitHub line anchors.

`auditor.md`, `chat_spec.md`, the diagnostic investigations, and parts of the session/changelog material are historical snapshots. They are useful records but should be labeled and treated as archives rather than current implementation specifications.

### 10.5 Research claims

`research-notes.md` includes generalized mobile latency and quantization claims without direct supporting citations. Its defense answer states that accuracy was validated through COCO pre-training and qualitative testing with target users. Pre-training is not application accuracy validation, and no target-user study artifacts exist in the repository; the thesis status audit says the participant study has not started.

`benchmark-results.md` is primarily a template and informal evidence record, not a completed formal benchmark report.

## 11. Android, Distribution, Accessibility, and Safety

### 11.1 Android release configuration

- Namespace and application ID remain `com.example.eyecue_flutter`.
- Application label remains `eyecue_flutter`.
- Release builds use the debug signing configuration.
- Effective minimum SDK is 24, while the thesis audit cites API 29 as the target.
- No production signing, CI workflow, store configuration, or integration-test workflow was found.

### 11.2 Licensing

The repository contains no project `LICENSE` file and README states that it is not yet licensed for distribution. The tracked alternate TFLite model contains Ultralytics metadata declaring an AGPL-3.0 license. Distribution requires an explicit project and model licensing review.

### 11.3 Accessibility

The app contains high-contrast controls, large buttons, gesture concepts, and an `AccessibleButton` wrapper. Comprehensive TalkBack semantics, live-region announcements, chart descriptions, correction workflows, and testing with blind or visually impaired participants are still missing.

### 11.4 Safety positioning

The project presents “smart navigation assistance,” high-priority obstacles, and path-adjustment language, but proximity is uncalibrated, frame rate is low on the documented device, object tracking is absent, and formal accuracy has not been measured.

A production or study build needs a clear statement that EyeCue supplements rather than replaces a cane, guide dog, trained orientation/mobility practice, or other primary navigation aid.

## 12. Inference-Efficiency Strategy

The documented approximately 600 ms model latency implies a raw ceiling near 1.7 model invocations per second. Five FPS requires end-to-end latency at or below 200 ms, and ten FPS requires 100 ms or less.

### 12.1 Highest-impact opportunities

#### A. Benchmark hardware delegates

Run the same model with:

- CPU: 1, 2, 4, and 6 threads
- XNNPACK
- NNAPI
- GPU delegate
- Delegate failure with automatic CPU fallback

Use the official LiteRT `benchmark_model` tool on target devices. Application telemetry should separately measure complete frame-to-result latency.

#### B. Export smaller-input models

| Input size | Pixels versus 640 | Compute-bound theoretical ratio |
|---|---:|---:|
| 512×512 | 64% | ~1.6× potential |
| 416×416 | 42% | ~2.4× potential |
| 320×320 | 25% | ~4× potential |

Actual gains will be smaller and device-dependent. A new model must be exported at each input size; reducing only the camera resolution does not reduce the fixed 640×640 model computation.

#### C. Produce genuine full-INT8 variants

Use representative EyeCue camera frames to quantize weights and activations. Validate per-class accuracy, especially for people, vehicles, traffic controls, and indoor obstacles.

#### D. Remove normal-operation forensic overhead

Disable PNG dumps, per-frame synchronous file flushes, redundant confidence scans, and diagnostic sorting in normal use. Keep an explicitly enabled diagnostic mode with retention controls.

#### E. Fuse preprocessing

Combine YUV conversion, aspect handling, resize, orientation, mirroring, normalization/quantization, and tensor write in a single optimized pass. This removes the orientation clone and avoids repeated traversal.

#### F. Optimize post-processing

- Remove the duplicate forensic class scan.
- Reuse candidate/output storage.
- Limit pre-NMS candidates with top-K selection.
- Clip complete rectangles before IoU/NMS.
- If the thesis only needs a smaller navigation class set, consider a model trained/exported for that subset.

### 12.2 What will and will not improve raw model FPS

Disabling forensics, fusing preprocessing, and reducing isolate copies improve real frame-to-result throughput and thermal behavior. They do not materially change the `interpreter.run()` time currently reported as inference latency.

To move far beyond approximately 2–3 FPS, EyeCue will probably need at least one of:

- A smaller model input
- A successful hardware delegate
- A more efficient model architecture
- Genuine full-integer execution

## 13. Wide-Device Performance Architecture

For broad Android support, use progressive enhancement rather than a single device-specific backend.

```text
Flutter UI, TTS, settings, gestures, and telemetry
                         |
               InferenceBackend interface
                         |
            Native Android LiteRT integration
                         |
       Capability check + benchmark + validation
                         |
       CPU | XNNPACK | GPU | NNAPI | optional NPU
                         |
              320 | 416 | 512/640 tiers
```

### 13.1 Recommended model portfolio

| Variant | Role |
|---|---|
| 320 full INT8 | Universal low-end and emergency fallback |
| 416 full INT8 | Balanced CPU/XNNPACK/NNAPI tier |
| 416 or 512 FP16 | GPU-oriented tier |
| 640 FP16 | Optional quality tier for devices that prove capable |

Every model should expose the same parser contract where possible.

### 13.2 Runtime selection

Do not select a backend only from manufacturer, model name, SoC, RAM, or Android version. Drivers and delegate support vary even within similar hardware families.

On first use or after a relevant update:

1. Start with the safe CPU baseline.
2. Discover available runtimes and accelerators.
3. Benchmark viable model/backend combinations using representative inputs.
4. Compare accelerated outputs with known CPU/golden outputs.
5. Reject configurations that crash, return NaNs, produce invalid boxes, diverge beyond tolerance, or exceed memory/latency limits.
6. Cache the winning profile.

The cache key should include:

- Device and SoC
- Android version
- Application version
- Model version/hash
- LiteRT runtime version
- Delegate/provider version

### 13.3 Suggested fallback table

| Condition | Preferred path | Fallback |
|---|---|---|
| Unknown device | 320 INT8 CPU | Lower dispatch rate |
| Good CPU result | 416 INT8 XNNPACK | 320 INT8 CPU |
| Validated GPU | 416/512 FP16 GPU | XNNPACK/CPU |
| Validated NNAPI/NPU | 416 INT8 accelerator | XNNPACK/CPU |
| Battery saver or thermal pressure | Step down model tier | Reduce dispatch rate |
| Delegate initialization/invoke failure | Recreate CPU interpreter | 320 INT8 CPU |

### 13.4 Runtime distribution

On Google Play Services devices, prefer a system-provided LiteRT runtime when available and retain a bundled runtime fallback for non-GMS/AOSP/Huawei devices. This preserves offline operation while allowing updated runtimes where supported.

Do not make a beta acceleration-selection service or a vendor-specific NPU delegate the universal path. These can be optional providers behind the same backend interface.

### 13.5 Runtime adaptation

Track rolling:

- Preprocessing time
- Model time
- Parsing/NMS time
- Complete frame-to-result latency
- p50 and p95 latency
- Dropped frames
- Memory failures
- Battery-saver state
- Thermal state where supported

If p95 latency exceeds the target for several seconds, reduce the model tier or dispatch rate. If the device is cool and remains comfortably below budget, a quality tier may be increased conservatively.

Do not queue stale camera frames. For assistive use, a smaller number of current results is more useful than a larger number of delayed results.

### 13.6 Recommended implementation boundary

Keep Flutter for application behavior. Put camera-to-tensor and model execution behind a project-owned inference interface, with a native Android implementation providing:

- LiteRT runtime selection
- Delegate creation and teardown
- Automatic CPU fallback
- Native/direct buffers
- Fused preprocessing
- Model-tier switching
- Correctness-validation hooks
- Segmented performance counters

This boundary also leaves room for a future iOS backend without rewriting the assistive UI and domain services.

## 14. Benchmark and Validation Plan

### Phase 1: Establish honest metrics

- Disable active diagnostics or measure them separately.
- Record transfer, preprocessing, model, post-processing, and end-to-end time.
- Report p50, p95, and sustained FPS, not only reciprocal average latency.
- Warm up each configuration before measuring.
- Measure sustained runs long enough to observe thermal throttling.

### Phase 2: Device matrix

Include at minimum:

- Older API 24–28 device
- Low-end modern Android device
- Midrange Qualcomm device
- MediaTek device
- Samsung Exynos device if in scope
- Recent Pixel/Tensor device
- High-end Snapdragon device
- Non-GMS device if distribution includes it

### Phase 3: Model/backend matrix

For each device, compare:

- 320 INT8 CPU/XNNPACK/NNAPI
- 416 INT8 CPU/XNNPACK/NNAPI
- 416/512 FP16 CPU/GPU
- Optional vendor NPU provider
- Current 640 model baseline

### Phase 4: Accuracy and safety validation

For every selected tier, evaluate:

- Per-class precision and recall
- Priority-class false negatives
- Indoor/outdoor scenes
- Day, night, backlight, and low-light conditions
- Portrait and landscape orientation
- Front and rear cameras if both are supported
- Near and distant objects
- Motion blur
- End-to-end TTS delay

Performance selection must satisfy an accuracy floor. The fastest backend is not acceptable if delegate precision or reduced resolution loses critical obstacles.

## 15. Prioritized Remediation Roadmap

### P0 — Correctness and safety

1. Make Auto-Start behavior and Home status truthful.
2. Make the initial two-finger start gesture available or remove the unavailable instruction.
3. Gate camera dispatch on inference-isolate readiness.
4. Correct COCO priority IDs and strengthen label-driven tests.
5. Update TTS de-duplication only after successful speech dispatch.
6. Add complete camera/model startup error recovery UI.
7. Add an explicit assistive-use safety disclaimer.

### P0 — Privacy and measurement integrity

1. Disable forensic frame capture in normal builds.
2. Add explicit diagnostic consent, retention, export, and deletion behavior.
3. Separate raw model latency from end-to-end latency.
4. Rename telemetry metrics to match what they actually count.

### P1 — Performance

1. Benchmark delegates and thread counts on real devices.
2. Export 320/416 model variants.
3. Produce genuine full-INT8 and GPU-oriented FP16 variants.
4. Fuse preprocessing and orientation.
5. Remove redundant output scans and synchronous per-frame storage.
6. Add top-K and reusable post-processing buffers.

### P1 — Critical-path testing

1. Unit-test conversion, quantization, parser, NMS, orientation, and boxes.
2. Test isolate startup and error recovery.
3. Add camera/lifecycle integration tests where feasible.
4. Add real-device delegate and golden-output validation.
5. Add TalkBack and semantic-label verification.

### P1 — Documentation integrity

1. Resolve versioning between Git/docs and `pubspec.yaml`.
2. Repair broken local links.
3. Separate current specifications from historical investigations.
4. Correct Auto-Start, listener, queue, allocation, and camera-error claims.
5. Add citations or measured evidence for research performance claims.

### P2 — Production readiness

1. Rename the Android package and application label.
2. Add production signing and CI.
3. Resolve project and model licensing.
4. Add privacy policy and store artifacts.
5. Complete accessibility and controlled user validation.
6. Validate battery, thermal, memory, and lifecycle behavior across the device matrix.

## 16. Readiness Conclusion

### Engineering prototype

**Status: Credible and buildable.** The model, application structure, tests, and Android build are real and functional enough to support continued development.

### Assistive navigation product

**Status: Not ready for independent navigation use.** Startup behavior, latency, accuracy evidence, lifecycle handling, accessibility validation, and safety positioning remain incomplete.

### Thesis research instrument

**Status: Partially ready.** Telemetry and charts exist, but metric semantics, structured export, formal benchmarking, ground-truth accuracy evaluation, and participant-study evidence are incomplete.

### Production Android release

**Status: Not ready.** Release signing, package identity, licensing, privacy controls, store requirements, CI, device validation, and production diagnostic policy are unfinished.

### Performance potential

**Status: Meaningful headroom remains.** A smaller model, genuine full-integer inference, successful delegates, fused preprocessing, removal of forensic overhead, and adaptive per-device selection could plausibly deliver a substantial improvement. Five FPS or better is a reasonable engineering target for compatible devices, but ten FPS cannot be promised without a device/model benchmark matrix and accuracy validation.

The most robust product principle is:

> Compatibility comes from a guaranteed CPU fallback. Performance comes from measured progressive enhancement. Safety comes from validating both latency and detection quality on every selected tier.

## 17. Primary External Technical References

- [LiteRT Android overview](https://ai.google.dev/edge/litert/android)
- [LiteRT delegate overview](https://ai.google.dev/edge/litert/performance/delegates)
- [LiteRT benchmark measurement guide](https://github.com/tensorflow/tensorflow/blob/master/tensorflow/lite/g3doc/performance/measurement.md)
- [XNNPACK backend documentation](https://github.com/tensorflow/tensorflow/blob/master/tensorflow/lite/delegates/xnnpack/README.md)
- [TensorFlow post-training quantization guide](https://www.tensorflow.org/model_optimization/guide/quantization/post_training)
- [LiteRT runtime selection API](https://ai.google.dev/edge/api/tflite/java/org/tensorflow/lite/InterpreterApi.Options.TfLiteRuntime)
- [LiteRT GPU compatibility API](https://ai.google.dev/edge/api/tflite/java/org/tensorflow/lite/gpu/CompatibilityList)
- [LiteRT Android NPU overview](https://ai.google.dev/edge/litert/android/npu)
- [LiteRT Android Acceleration Service](https://ai.google.dev/edge/litert/android/acceleration_service)
- [TensorFlow Flutter TFLite repository](https://github.com/tensorflow/flutter-tflite)
