# EyeCue — Custom vs Ultralytics Test

> **Status:** Unreleased test candidate, 2026-09-01. The Android debug APK builds, installs, and has run both engines on the Snapdragon 695/API 33 target. Bidirectional switching also passed a short smoke test after a lifecycle race was fixed. The controlled comparison is still pending; this document does not claim a winning engine before those runs are completed.

## What the two modes mean

| Mode | Camera and preprocessing | Inference/post-processing | EyeCue features retained |
|---|---|---|---|
| **Custom EyeCue** | EyeCue camera stream, YUV420 conversion, resize, tensor layout/orientation, and mirroring | EyeCue isolate, TFLite interpreter, YOLO parser, confidence filtering, and class-wise NMS | Spatial/priority analysis, warnings, object cards, TTS, haptics, gestures, and telemetry |
| **Ultralytics** | `ultralytics_yolo` native camera and preprocessing pipeline | Plugin-managed LiteRT inference, output parsing, filtering, and NMS | The native results are mapped back into the same EyeCue spatial/priority, warnings, object cards, TTS, haptics, gestures, and telemetry layers |

Both modes use the same `assets/yolov8n_int8_new.tflite`, `assets/labels.txt`, confidence threshold `0.25`, and IoU threshold `0.45`. The selector changes the runtime engine, not the recognition model or EyeCue's assistive interpretation.

Android needs both the classic `libtensorflowlite_jni.so` used by the Custom FFI path and LiteRT Next's `libLiteRt.so` used by Ultralytics. [`android/app/build.gradle.kts`](../android/app/build.gradle.kts) packages those native runtimes side by side while removing the duplicate legacy Java API artifact. The built debug APK was inspected and contains both libraries for arm64-v8a, armeabi-v7a, and x86_64, plus the model and labels. Both paths subsequently loaded and processed camera frames on the arm64 test device.

## How to switch

1. Open **Settings**.
2. Under **Inference Engine**, choose **Custom EyeCue** or **Ultralytics**.
3. Open **Detect**. If detection was already open, the engine screen is replaced automatically.
4. After a run, open **Settings → Logs & Reports**. The Overview tab shows separate engine summaries.

The selected engine is persisted across app restarts. **Custom EyeCue is the default** so an upgrade does not silently replace the previously validated pipeline.

## Controlled comparison protocol

Use one physical device and do not compare results captured on different phones.

1. Charge the phone to at least 80%, close other apps, disable battery saver, and let the device cool to room temperature.
2. Fix the phone in one position. Use the same lighting, scene, objects, distance, orientation, and rear camera for both runs.
3. Keep EyeCue settings identical. Start with **Low Power Mode off**; run a separate paired test with it on if that mode matters.
4. Select the first engine, open Detect, and allow a 30-second warm-up. Then run continuously for 5 minutes.
5. Record average FPS, average inference latency, detection count, stability/errors, battery percentage, and temperature if available.
6. Stop detection and let the phone return near its starting temperature.
7. Repeat the same warm-up and 5-minute run with the other engine.
8. Repeat the pair at least three times and alternate order: Custom→Ultralytics, Ultralytics→Custom, Custom→Ultralytics.
9. Report the median of the three runs as the main performance result; keep the individual runs visible.

Use the same object script in every run—for example: empty scene for 30 seconds, one person for 60 seconds, person plus chair for 60 seconds, moving person for 60 seconds, and mixed objects for the remaining time. This makes detection count somewhat comparable, although it is not an accuracy benchmark.

## Interpreting the metrics

- **FPS** measures the engine-reported inference rate. Higher is better, but it does not by itself prove smoother preview, lower speech delay, or better detection accuracy.
- **Inference latency** is intended to represent model execution time. Ultralytics also displays its native total processing time on the Detect screen; that broader number should not be compared directly with Custom's model-only latency.
- **Detection count** has no accuracy meaning without labelled ground truth. More detections can mean better recall or more false positives.
- **Stability** includes crashes, frozen previews, model-load failures, camera failures, and sustained thermal slowdown. A fast engine that fails on a supported device is not the better default.
- Custom retains synchronous forensic diagnostics that Ultralytics does not reproduce. The test therefore compares the two complete app modes as implemented, not isolated native kernels under laboratory conditions.

## Decision rule for wide device support

Keep **Custom EyeCue** as the compatibility default until Ultralytics completes the device matrix. Prefer Ultralytics by default only if it:

1. loads and runs reliably on every minimum-supported Android/API and representative chipset class;
2. produces equal or acceptable qualitative detections and orientation behavior;
3. improves sustained median FPS or latency materially, rather than only in a short cold run;
4. preserves permission, pause/resume, TTS, TalkBack, and lifecycle behavior; and
5. has acceptable APK-size, licensing, memory, battery, and thermal costs.

A practical release design is to keep both engines, select the proven default per compatibility policy, and retain the other as an advanced/fallback option until the evidence supports removing it.

## Release and maintenance constraints

- `ultralytics_yolo` 0.6.13 is AGPL-3.0. Before distributing this mode through Google Play, the project must satisfy that licence's source/distribution obligations or obtain an appropriate Ultralytics enterprise licence. This is a release gate, not a performance issue.
- The debug APK is approximately 204 MB because it is unoptimized and contains multiple ABIs. Do not use that number as the Play download size; measure a release Android App Bundle and Play's ABI-split delivery separately.
- The current Flutter toolchain warns that `flutter_tts` and `ultralytics_yolo` apply the legacy Kotlin Gradle plugin mechanism. It builds today, but those dependencies must be upgraded or patched before a future Flutter version removes compatibility.
- The classic/Next LiteRT bridge is an Android-specific integration seam. Re-run the native build and both engine smoke tests after upgrading either `tflite_flutter`, `ultralytics_yolo`, AGP, Gradle, or Flutter.

## Verification completed before controlled benchmarking

- `flutter analyze`: 0 issues.
- `flutter test`: 77 passing.
- Flatbuffer and PNG validators: passing.
- `flutter build apk --debug`: passing.
- APK inspection: shared model/labels and both native runtime families present.
- Target-phone installation: passing after the initial Android-cancelled attempt was retried; the fixed dual-engine build was installed on `2201116SG` (Snapdragon 695, Android 13/API 33, arm64).
- Custom smoke test: camera, explicit XNNPACK interpreter, detections, overlays, and app process remained active.
- Ultralytics smoke test: native camera/inference results, EyeCue cards, controls, and app process remained active. GPU was requested with CPU fallback, but the smoke test did not prove which delegate executed the graph.
- Engine lifecycle: the first Custom→Ultralytics switch exposed a late isolate result attempting to write to a closed stream. Disposal and frame-gate handling were hardened; post-fix Custom→Ultralytics and Ultralytics→Custom switches completed without recurrence in captured Flutter logs.

## Short device observations — not benchmark results

These readings were taken while interactively verifying the build. They used different moments, scenes, run lengths, and thermal states, so they must not be used to declare a winner.

| Engine | Observed readings | Functional evidence | Important limitation |
|---|---|---|---|
| Custom | In the final warm reverse-switch run, 5-second summaries showed about 3.5–3.8 inference FPS and 261.0–289.4 ms average model latency. An earlier cooler candidate run reported about 5.7–6.2 FPS and 164.8 ms calculated mean latency. | XNNPACK-labelled frames completed; `tv`, `laptop`, `keyboard`, `cup`, and other detections rendered. | Different thermal/scene conditions; no proof of full graph delegation or long-duration stability. |
| Ultralytics | Momentary on-screen readings ranged from about 6.1–9.6 FPS, 86.1–148.1 ms inference, and 111.4–175.9 ms native total. | Native preview and results ran; a `cup` result was mapped into EyeCue's labelled object card and assistive stack. | Not a timed average; actual GPU-versus-CPU delegate selection was not confirmed. |

The native Ultralytics overlay displayed a numeric fallback such as `class 41` for this metadata-light model, while EyeCue's adapted card used `labels.txt` and displayed `cup`. This is a presentation inconsistency to resolve before making Ultralytics the default; it did not prevent EyeCue's own label/TTS mapping.

## Results table

| Device / API | Engine | Run | Warm-up | Duration | Avg FPS | Avg inference ms | Detections | Battery Δ | Temperature | Errors/notes |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---|
| Snapdragon 695 / API 33 | Custom | 1 | 30 s | 5 min | — | — | — | — | — | Pending controlled run |
| Snapdragon 695 / API 33 | Ultralytics | 1 | 30 s | 5 min | — | — | — | — | — | Pending controlled run |

Do not fill missing results from the earlier 65-frame Custom observation: its duration and conditions do not match this protocol.
