# EyeCue — Session Log

> Append a new entry at the top of this file at the end of every development session.
> See [`development-workflow.md`](development-workflow.md) for the full workflow.

---

## 2026-09-01 (12th session) — NCHW Candidate, XNNPACK Fallback, and Status Sync

### Objective
- Assess the post-v0.2.2 worktree, validate the new model/layout path, synchronize current documentation, and prepare one atomic commit without overstating device validation.

### Completed
- Reviewed the uncommitted model, inference, tensor-rotation, test, validator, and documentation changes.
- Confirmed the candidate model directly: `yolov8n_int8_new.tflite` is 3,481,792 bytes with input `[1,3,640,640]` / FLOAT32, output `[1,84,8400]` / FLOAT32, and 448 tensors (2 FLOAT32, 90 INT32, 356 INT8).
- Added runtime NCHW preprocessing and a standalone layout-aware [`tensor_rotation.dart`](../lib/models/tensor_rotation.dart) helper. The helper has 14 focused tests covering NHWC/NCHW rotations, mirroring, equivalence, and guards.
- Hardened the experimental XNNPACK path in [`inference_isolate.dart`](../lib/services/inference_isolate.dart): delegate ownership is retained for interpreter lifetime; setup failures and recoverable invocation failures retry on a four-thread CPU interpreter. Native SIGSEGV remains uncatchable.
- Extended [`validate_flatbuffer.dart`](../tool/validate_flatbuffer.dart) to cover the candidate model.
- Synchronized current status, architecture, implementation progress/decisions, known issues, research notes, benchmark notes, testing plan, changelog, and README. The 2026-08-21 comprehensive assessment remains a historical snapshot.

### Verified
- `flutter analyze`: 0 issues.
- `flutter test`: 73 passing.
- Flatbuffer and PNG validators pass; the generated debug APK contains the candidate model asset.
- Candidate APK installation on the Android 13/API 33 test phone failed with `INSTALL_FAILED_INSUFFICIENT_STORAGE`. The old installed application was launched afterward, so no candidate runtime, detection, latency, accuracy, or XNNPACK result is available.

### Decisions
- Treat the v0.2.2 CPU/NHWC path as the stable documented baseline.
- Treat the NCHW/XNNPACK path as unreleased and statically validated only until the exact APK is installed and tested.
- Do not claim a performance improvement or that the historical Snapdragon 695 XNNPACK crash is resolved.

### Next Session
- Free device storage, install the exact candidate APK, verify runtime metadata and backend behavior, then collect formal model/backend and end-to-end measurements.
- Re-validate back landscape and front-camera orientation, complete UI/gesture/TTS/settings checks, and continue isolate restart-recovery work.

---

## 2026-08-16 (11th session) — Android-Only Platform Cleanup

### Objective
- Scope EyeCue to Android only (per the thesis): remove unused Flutter platform
  scaffolding and document that iOS/desktop/web are out of scope.

### Completed
- Removed the unused generated platform directories: `ios/`, `web/`, `windows/`,
  `macos/`, `linux/` (103 tracked files deleted, unstaged — not committed).
- Confirmed the app is Android-self-contained: `lib/` has no platform checks
  (`Platform.is*`/`defaultTargetPlatform`/`kIsWeb`), no explicit platform blocks
  in `pubspec.yaml`, and every dependency (camera, tflite_flutter, flutter_tts,
  permission_handler, path_provider, fl_chart) has an Android implementation.
- Ran `flutter pub get` to regenerate the (gitignored) plugin metadata.
- Docs updated: README (platform note + Platforms row), `docs/architecture.md`
  (Android-only statement + folder structure), `docs/known-issues.md`
  (Platform-Specific Limitations). Historical docs (implementation-decisions,
  orientation reviews, research-notes, thesis audit) intentionally retained.
- Android config checked against the thesis: `minSdk=24` (Flutter default) vs
  thesis Android 10 / API 29 minimum; `applicationId=com.example.eyecue_flutter`
  vs expected `com.eyecue`; `targetSdk=36`; release still signs with the debug
  keystore. These are reported as follow-ups, not changed (platform-scope
  cleanup only).

### Verified
- `flutter analyze`: 0 issues. `flutter test`: 59 passing.
- `flutter devices`: Android device detected; Linux desktop target no longer
  present. `flutter build apk --debug` succeeds.

### Next Session
- Release hardening: package rename (`com.eyecue`), minSdk alignment with the
  thesis (API 29), release signing; on-device validation of gestures/TTS.

---

## 2026-08-16 (10th session) — UI Layout Fixes (v0.2.2)

### Objective
- Fix two UI/layout bugs: (1) the camera viewport resized when detections
  appeared, and (2) Logs & Reports charts could extend beyond their container.

### Diagnosis
- **Camera resizing:** [`detection_screen.dart`](../lib/screens/detection_screen.dart)
  built a `Column` with the camera in `Expanded` and a content-sized controls
  panel whose card list height was `detections × 78` — so detection count drove
  the bottom panel's height and shrank the camera region.
- **Chart overflow:** [`charts.dart`](../lib/widgets/charts.dart) capped `maxY`
  with fixed clamps (latency `clamp(50,500)`, FPS `clamp(1,30)`), so values
  above the clamp were drawn outside the plot; benchmark lines could sit above a
  shrunken scale; and the bar chart set no `maxY` (fl_chart defaults it to 0).

### Fix
- Reserved a **fixed** content region: `LayoutBuilder` → `SizedBox(height:
  constraints.maxHeight × 0.32, clamped 200–320)` holds the warning banner +
  a scrollable detection list + controls; the camera stays in the remaining
  `Expanded` space. Warning banner moved below the camera.
- Charts now derive Y bounds from the data with headroom
  (`max(dataMax × 1.2 + padding, floor)`), draw benchmark lines only when they
  fit, and give the bar chart an explicit dynamic `maxY`. Empty data shows a
  placeholder. No protected ML/camera/inference code touched.

### Verified
- `flutter analyze`: 0 issues. `flutter test`: 59 passing (new chart tests:
  empty, very-high, constant, single-bucket data).
- On-device (Android 13 / API 33): Home → Detect (idle + started + 2-object
  detections + paused/stopped), Settings, and Logs & Reports (Overview with
  live FPS/latency/detections, Charts with latency/FPS/frequency, Logs) all
  render with **0 exceptions / RenderFlex overflows** in logcat.

### Next Session
- On-device validation of gestures, TTS, and settings persistence; orientation
  re-validation; isolate restart recovery; formal FPS/latency benchmark.

---

## 2026-08-16 (9th session) — Fix Startup Theme Assertion (v0.2.1)

### Objective
- Fix the on-device startup crash: `Failed assertion: 'fontSize != null || (fontSizeFactor == 1.0 && fontSizeDelta == 0.0)'` thrown from `EyeCueApp._buildTheme()` during initial widget construction.

### Diagnosis
- The crash came from [`lib/main.dart`](../lib/main.dart) `_buildTheme()` calling
  `base.textTheme.apply(fontSizeFactor: 1.12, ...)`.
- Flutter's Material 3 default `TextTheme` is **color-only**: `Typography.material2021().white` /
  `ThemeData.textTheme` styles all have `fontSize == null` (geometry is merged per-locale
  from `englishLike`/`dense`/`tall` at render time). `TextStyle.apply` asserts when
  `fontSizeFactor != 1.0` on a null-fontSize style — so the assertion fired for every style.
- Confirmed empirically with a throwaway diagnostic test (all 15 styles report `fontSize == null`).

### Fix
- Replaced `textTheme.apply(fontSizeFactor: 1.12, ...)` with an explicit high-contrast
  `TextTheme` (`_highContrastTextTheme()`) using concrete font sizes (M3 defaults scaled
  ~1.12×) and white text. Only [`lib/main.dart`](../lib/main.dart) changed — camera,
  inference, TTS, gestures, and UI behavior untouched.

### Verified
- `flutter analyze`: 0 issues.
- `flutter test`: 53 passing, including a new regression test
  ([`test/theme_test.dart`](../test/theme_test.dart)) that pumps `EyeCueApp` and asserts the
  Home screen renders with a concrete white text theme.
- On-device (Android 13 / API 33, `2201116SG`): debug APK built, installed, launched. Process
  alive, `MainActivity` resumed (Home screen), detection pipeline running (live `[Detection]`
  frames), no FATAL/assertion/overflow in logcat.

### Next Session
- Continue on-device validation of gestures, TTS, settings persistence, and Logs & Reports;
  orientation re-validation; isolate restart recovery.

---

## 2026-08-16 (8th session) — Assistive Application UI (v0.2.0)

### Objective
- Turn the validated computer-vision prototype into the thesis-aligned assistive
  application: application UI/navigation, TTS audio guidance, thesis gestures,
  settings persistence, and Logs & Reports — without touching the ML pipeline.

### Completed
- **Navigation:** 4-tab bottom bar (Home, Detect, Settings, Help) with lazy pages
  and state preservation ([`lib/navigation/app_shell.dart`](../lib/navigation/app_shell.dart)).
- **Screens:** [`home_screen.dart`](../lib/screens/home_screen.dart),
  [`detection_screen.dart`](../lib/screens/detection_screen.dart),
  [`settings_screen.dart`](../lib/screens/settings_screen.dart),
  [`help_screen.dart`](../lib/screens/help_screen.dart),
  [`logs_reports_screen.dart`](../lib/screens/logs_reports_screen.dart).
- **TTS:** [`tts_service.dart`](../lib/services/tts_service.dart) — `flutter_tts`
  wired; cooldown, same-label de-duplication, urgent bypass, mute, repeat-last.
- **Gestures:** [`gesture_controller.dart`](../lib/services/gesture_controller.dart)
  + [`gesture_surface.dart`](../lib/widgets/gesture_surface.dart) — two-finger
  double tap (start/stop), single tap (pause/resume), three-finger tap (scan),
  swipe down (repeat); haptic + TTS confirmation.
- **Settings:** [`settings_service.dart`](../lib/services/settings_service.dart)
  (file-backed JSON via `path_provider`) — Vibration, Auto-Start, Low Power
  (dispatch throttle), Audio, Logs & Reports.
- **Spatial/priority:** [`spatial_analysis_service.dart`](../lib/services/spatial_analysis_service.dart)
  + [`detection_info.dart`](../lib/models/detection_info.dart) — left/center/right,
  class-based priority, approximate proximity band (labeled heuristic).
- **Telemetry/reports:** [`telemetry_service.dart`](../lib/services/telemetry_service.dart)
  + [`charts.dart`](../lib/widgets/charts.dart) — Overview/Charts/Logs; accuracy/
  precision/recall/mAP shown as unavailable (require ground truth).
- **Haptics:** [`haptics_service.dart`](../lib/services/haptics_service.dart).
- Retired the old single-screen [`camera_screen.dart`](../lib/screens/camera_screen.dart)
  in favor of `detection_screen.dart`; `info_panel.dart`/`debug_overlay.dart`
  remain but are unused by the primary UI.
- **Tests:** replaced the boilerplate counter test with 52 passing tests across
  navigation, screens, widgets, TTS, settings, spatial, telemetry, and gestures.
- `flutter analyze`: **0 issues**. `flutter test`: **52 passing**.

### Decisions
- No new dependencies: settings persistence uses `path_provider` (already used by
  `ForensicLog`) rather than `shared_preferences`; haptics use built-in
  `HapticFeedback`; state stays on plain `ChangeNotifier` services + `setState`.
- The ML pipeline (camera, YUV, orientation, TFLite, parser, NMS, thresholds,
  painter, forensics) was **not** modified.
- Proximity is a box-size heuristic phrased as "approximately …" — calibrated
  distance, movement tracking, and accuracy metrics remain out of scope (per the
  thesis audit).

### Next Session
- On-device validation of gestures, TTS, mute toggle, settings persistence, and
  Logs & Reports on the Snapdragon 695 device; orientation re-validation; isolate
  restart recovery.

---

## 2026-08-16 (7th session) — Thesis-Product Status Audit (Documentation Only)

### Objective
- Produce an independent, evidence-based baseline of the current Flutter codebase
  against the **EyeCue thesis** (thesis PDF:
  `GRP8-P1-EyeCue_ Machine Learning-Based Real-Time Object Recognition and Audio
  Guidance System for the Visually Impaired (1).pdf`), as an audit only. No code
  was modified.

### Completed
- Read the thesis PDF plus the full repository (`README.md`, all `docs/`,
  `pubspec.yaml`, the complete `lib/`, `test/`, `android/`, `assets/`) and
  verified every claim against the actual code (not the documentation).
- Created a full thesis-to-code feature matrix (core system, interactions,
  screens, settings, telemetry, evaluation), screen/UI gap analysis, assistive
  (B/C/D) and spatial-guidance gap analyses, research/evaluation and production
  readiness gap analyses.
- Produced a weighted completion estimate: **Vision/ML ~80%, Spatial ~5%,
  Audio guidance ~0%, Accessibility/interaction ~0%, Application UI ~15%,
  Research instrumentation ~45%, Research evaluation ~10%, Production readiness
  ~10% → Overall thesis-product ≈ 30% (range 25–35%)**.
- Identified the single biggest mismatch (the **audio guidance system is
  entirely missing** — `flutter_tts` declared but zero usages) and the next five
  highest-impact gaps.
- Proposed a target Flutter architecture (5 screens, navigation, audio/spatial/
  priority/telemetry/accessibility services) and a phased roadmap
  (A: Vision validation → B: Assistive core → C: Accessibility → D: App UI →
  E: Research evaluation → F: Production release).
- New deliverable: [`docs/thesis-product-status-audit.md`](thesis-product-status-audit.md).

### Findings / Decisions
- The project's self-reported **~60%** (README / project-status) measures the
  ML/debug pipeline only and **overstates thesis-product completion**; the audit
  establishes ~30% for the product as a whole. Existing status numbers were
  **not** edited (flagged in the audit report instead).
- `docs/known-issues.md` claim that `path_provider` is unused is **stale** — it
  is used by `forensic_log.dart`; only `flutter_tts`, `flutter_riverpod`, and
  `fl_chart` are unused.
- `test/widget_test.dart` is the Flutter counter boilerplate and does **not**
  test the app (it would fail if run).

### Next Session
- Begin Phase B (Assistive core): TTS service wired to the detection stream,
  spatial interpretation, and priority tiers. See the audit report §13.

### Objective
- Read all markdown documentation and sync it with the actual codebase state
  (the docs were last updated 2026-08-01 at v0.1.7, and had drifted from the
  implemented code).

### Completed
- **Read all markdown:** root docs (`README.md`, `chat_spec.md`, `auditor.md`)
  plus all 21 files under [`docs/`](.) and cross-checked against the source in
  `lib/`, `tool/`, `test/`, and `pubspec.yaml`.
- **Verified NMS is implemented** (contradicting several status docs): the
  isolate's [`_parseYolov8Output`](../lib/services/inference_isolate.dart)
  applies class-wise NMS (IoU 0.45) after a pre-NMS confidence threshold of
  0.25. Fixed the stale "NMS missing" claims across:
  - [`README.md`](../README.md)
  - [`project-status.md`](project-status.md)
  - [`implementation-progress.md`](implementation-progress.md)
  - [`known-issues.md`](known-issues.md)
  - [`architecture.md`](architecture.md)
  - [`implementation-plan.md`](implementation-plan.md)
- **README refreshed:** status (~60%, NMS done), tech stack (model is
  weight-quantized FLOAT32-I/O), full project structure (added `BoxTransform`,
  `PngEncoder`, `ForensicLog`, probes, `InfoPanel`, `tool/` scripts), and a
  new "Investigations & Diagnosis" docs index.
- **Changelog:** added the retroactive `v0.1.7.1` entry documenting the
  NMS + confidence-threshold work (2026-08-01) that had no changelog record.
- **Dates:** updated `Last Updated` timestamps to 2026-08-14 where touched.

### Decisions
- Keep `chat_spec.md` and `auditor.md` as historical records (untouched).
- Document the existing NMS implementation rather than re-planning it as
  pending work (it has been on-device validated).

### Next Session
- Implement TTS audio feedback (Milestone 1) — the last missing core feature.
- Re-validate orientation on-device (back landscape + front camera).
- Add permission-denied UI + isolate restart recovery.

---

## 2026-08-01 (5th session) — Orientation Architecture

### Objective
- Fix the last remaining camera-path defect: frames are delivered in sensor
  orientation (this device `sensorOrientation = 90°`, always 320×240
  landscape) and were never rotated, so portrait-hold scenes reached the model
  rotated 90° → ~0 detections. Make detection orientation-independent and
  device-independent.

### Completed
- [`BoxTransform`](../lib/models/box_transform.dart) (new) — single source of
  truth for all orientation math: `deviceDegreesFor` (plugin counter-clockwise
  `DeviceOrientation` convention), `displayRotationDegrees` (metadata-driven,
  per-lens), `uprightDims`, and reversible `rotateRect`/`invertRect` +
  `mirrorRect`. No hardcoded angles.
- [`inference_isolate.dart`](../lib/services/inference_isolate.dart) —
  `processFrame` carries orientation metadata; isolate rotates + optionally
  X-mirrors the 640×640 NHWC input to UPRIGHT before `interpreter.run()`
  (lossless square transpose). Parser/NMS untouched; boxes after NMS are
  already upright.
- [`camera_screen.dart`](../lib/screens/camera_screen.dart) — per-frame
  rotation computed from the SAME `controller.value.deviceOrientation` that
  `CameraPreview` uses, so painter and preview agree by construction; preview
  + painter sized with upright dims; sensor/lens fed to `recordCamera`.
- [`bounding_box_painter.dart`](../lib/widgets/bounding_box_painter.dart) —
  stripped of all lens/mirror/orientation logic; now a pure normalized→pixel
  mapper over the upright image (`applyBoxFit` identical to the preview
  `FittedBox`).
- [`forensic_log.dart`](../lib/services/forensic_log.dart) — `recordOrientation`
  per frame + sensor/lens fields in `recordCamera`.
- `flutter analyze`: 0 issues.

### Decisions
- **Input rotation, not post-NMS box transform** (deliberate deviation from
  `docs/orientation-design-review.md`): on-device evidence proved the model
  sees a 90°-rotated scene in portrait → 0 detections, so there are no boxes
  to transform. Rotating the input is the only design that satisfies "portrait
  detection quality matches landscape". Documented in
  [`docs/orientation-implementation.md`](orientation-implementation.md) §4.
- The plugin's counter-clockwise `DeviceOrientation` convention is used
  (`landscapeLeft→90`, `landscapeRight→270`), not the naive clockwise mapping —
  the convention bug found on-device in landscape and fixed.

### Issues
- Landscape physical-hold showed R=180 instead of 0 until the convention
  mapping was corrected; physical-hold re-validation deferred to next session.
- Front-camera portrait/landscape math implemented but device run pending.

### Next Session
- Re-validate back-camera landscape physical hold on-device; run front-camera
  portrait/landscape validation; then begin Milestone 1 (TTS audio feedback).

---

## 2026-08-01 (4th session) — Camera Preview Redesign (v0.1.6)

### Objective
- Replace the floating debug overlay with a permanent bottom information panel
  and a strictly portrait 3:4 camera preview.

### Completed
- [`camera_screen.dart`](../lib/screens/camera_screen.dart) — strict 3:4
  portrait preview anchored to the top (`AspectRatio(3/4)` + `BoxFit.contain`);
  permanent bottom panel with exactly two Material tabs (Metrics, Detections).
- [`info_panel.dart`](../lib/widgets/info_panel.dart) — Metrics tab (live FPS,
  avg FPS, inference time, latency, confidence stats, resolutions, model info,
  backend, quantization, threads) and Detections tab (chronological history,
  capped 50, 1-second age timer).
- Floating `DebugOverlay` removed from the screen (data lives in Metrics tab);
  widget retained but unused.
- Layout math checked for portrait and landscape; panel never squeezed below
  minimum. `flutter analyze`: 0 issues.

### Decision
- Preview width computed from screen size while reserving a minimum panel
  height; preview never stretched, warped, or cropped.

### Next Session
- Implement the orientation architecture (per `docs/orientation-design-review.md`).

---

## 2026-08-01 (3rd session) — Aspect-Correct Preview & Preprocessing Repair (v0.1.4 + v0.1.5)

### Objective
- Fix preview stretching (camera texture scaled without aspect ratio, painter
  assumed letterbox) and repair the manual YUV420→RGB converter for the real
  CameraX delivery.

### Completed
- [`bounding_box_painter.dart`](../lib/widgets/bounding_box_painter.dart) —
  `_calculateImageRect` now uses `applyBoxFit` (identical math to the preview
  `FittedBox`), so painter and preview layout always agree; normalized→screen
  mapping `sx = offX + nx·destW`, `sy = offY + ny·destH`; boxes clamped to the
  image rect; front-camera mirroring unchanged.
- [`camera_screen.dart`](../lib/screens/camera_screen.dart) — preview rendered
  at native aspect inside `FittedBox(fit: _previewFit)` with a `SizedBox` sized
  to the frame (`contain` = letterbox, `cover` = center-crop, single static
  switch).
- [`inference_isolate.dart`](../lib/services/inference_isolate.dart) —
  `_convertYUV420toRGB` repaired to honor real per-plane `rowStride`/
  `bytesPerRow` and `pixelStride`/`bytesPerPixel`; supports planar I420
  (pixelStride 1) and semi-planar NV12/NV21 (pixelStride 2, U-led per the
  YUV_420_888 contract); resize/normalization math unchanged.
- `camera_screen.dart` forwards per-plane geometry and handles 2-plane
  (semi-planar) deliveries; forensic `frame_rgb.png` uses the same
  geometry-aware sampling.
- Converter validated against synthetic planar I420 + semi-planar NV12
  (incl. rowStride padding) — pixel-exact vs BT.601 reference.
  `flutter analyze`: 0 issues.

### Decision
- Single `_previewFit` switch for letterbox vs center-crop; painter and preview
  share one `applyBoxFit` transform (no offsets or magic constants).

### Next Session
- Continue preview/UI work (v0.1.6).

---

## 2026-08-01 (2nd session)

### Objective
- Replace console-based diagnostics with a structured, file-based forensic logging system (logcat was becoming unusable).

### Completed
- [`ForensicLog`](../lib/services/forensic_log.dart) — timestamped run directories under `<documents>/debug/run_YYYYMMDD_HHMMSS/` with `summary/camera/preprocess/tensor/output/parser/performance/errors.txt`, synchronous flush-per-write, and full try/catch isolation (logging can never break inference).
- First-frame PNG dumps: `frame_original.png` (Y luma), `frame_rgb.png` (YUV→RGB at camera res), `frame_resized.png`, `frame_model_input.png`.
- [`PngEncoder`](../lib/models/png_encoder.dart) — pure-Dart PNG encoder (isolate-safe). Validated by [`tool/validate_png.dart`](../tool/validate_png.dart) (signature/CRC/chunks/dims) and cross-decoded in Python — pixel-exact.
- Auto-generated `summary.txt` every 50 frames and on close: per-stage PASS/FAIL, max confidence, P99, top class, distribution, ranked root causes computed from collected statistics.
- Wired run-dir creation into `initIsolate` (path passed to the isolate), frame-loop channels via `_safeForensic`, and `camera.txt` on the first frame in `camera_screen.dart`; `processFrame` forwards `cameraFps`/`droppedFrames` for the performance log.
- Replaced console probes: `InferenceProbe`/`InputProbe` disabled (`enabled=false`) and call sites removed.
- `flutter analyze`: 0 issues.

### Decisions
- All writes are synchronous + flushed so a crash cannot lose logs.
- Image dumps are produced inside the inference isolate using a pure-Dart PNG encoder (no `dart:ui`, no engine dependency).
- Console probes are disabled rather than deleted, keeping them re-enableable; everything remains removable.

### Next Session
- Use the forensic run output to confirm the input-side root cause, then implement the single targeted fix.

---

## 2026-08-01

### Objective
- Make the app **self-describing**: report exactly what model is running, based on the loaded interpreter (not filenames or assumptions).
- Drive the inference pipeline from runtime model metadata (dynamic inference-path selection).

### Completed
- **Diagnosis (pre-implementation):** traced the `NoSuchMethodError: Float32List has no instance method 'reshape'` crash to [`inference_isolate.dart:257`](../lib/services/inference_isolate.dart) — `reshape()` is a `List` *extension* method invoked on a `dynamic` receiver (extensions are never resolved via dynamic dispatch). Also identified two latent tensor-handling bugs (flat `List` output fails tflite_flutter's `copyTo()` shape check; flat float input triggers automatic 1-D `resizeInputTensor`). Full report: [`docs/inference-tensor-diagnosis.md`](inference-tensor-diagnosis.md).
- **Model metadata:** parsed both bundled `.tflite` files with the reference `tflite` Python package → both are **FLOAT32 I/O** (input `[1, 640, 640, 3]`, output `[1, 84, 8400]`) with INT8 weights → *Weight-Quantized*.
- **Implemented [`ModelMetadata`](../lib/models/model_metadata.dart)** — immutable runtime snapshot (name, I/O types, shapes, scale/zeroPoint, quantized flags, classes, anchors, model type) built from `getInputTensor(0)`/`getOutputTensor(0)` + an internal tensor scan.
- **Implemented [`tflite_flatbuffer.dart`](../lib/models/tflite_flatbuffer.dart)** — pure-Dart FlatBuffers walker counting internal tensor types; validated 1:1 against the Python reference (324/23/62 and 324/25/62), plus IEEE-754 float16 helpers.
- **Rewrote [`inference_isolate.dart`](../lib/services/inference_isolate.dart)** around metadata: dtype-matched buffers, raw `ByteBuffer` I/O (fixes the reshape crash + latent output/input bugs), quantize-only-if-quantized preprocessing, dequantize-only-if-quantized post-processing, `MODEL INFORMATION` startup banner.
- **Extended [`debug_overlay.dart`](../lib/widgets/debug_overlay.dart)** with a live MODEL section (name, type, I/O types, shapes, classes, anchors, quantization, scale/zeroPoint) that adapts automatically to any model.
- **Wired [`camera_screen.dart`](../lib/screens/camera_screen.dart)**: overlay reacts to `metadataNotifier`; busy gate releases on isolate errors via `errorStream`.
- **Added [`tool/validate_flatbuffer.dart`](../tool/validate_flatbuffer.dart)** — `dart run tool/validate_flatbuffer.dart` → all validations pass.
- `flutter analyze`: 0 issues.

### Issues
- FlatBuffers vtable field slots are `4 + 2×index` (not `2 + 2×index`) — caught while validating the walker against the Python reference.
- Float16 subnormal threshold off-by-one (`exponent > 103` → `>= 103`) and NaN→Inf loss — fixed with roundtrip tests.

### Decision
- The runtime interpreter is the single source of truth; internal weight precision is scanned from the model buffer (never guessed, reported as "Unknown" if unavailable).
- Buffers are passed to `interpreter.run()` as raw `ByteBuffer`s — the zero-copy, shape-exempt path (no reshape, no automatic input-tensor resizing).
- Metadata is serialized to a JSON map to cross the isolate boundary and reconstructed on the main side.

### Next Session
- Begin Milestone 1: Implement TTS audio feedback
- Add permission-denied UI state
- Complete error recovery (isolate restart on fatal error)

---

## 2026-07-22

### Objective
- Verify the bounding box overlay & detection pipeline (feature verification)
- Make the pipeline observable via structured debug logging + a visual debug overlay

### Completed
- Traced the full pipeline: Camera → CameraImage → inference isolate → YOLOv8 → post-processing → Detection → bounding box overlay → UI
- Implemented bounding box `CustomPainter` overlay ([`lib/widgets/bounding_box_painter.dart`](../lib/widgets/bounding_box_painter.dart))
  - Normalised→screen coordinate transform with AspectRatio letterboxing
  - Front-camera mirroring, label pills with confidence %, shadow rendering
- Added structured debug logging with consistent prefixes: `[Service]`, `[Model]`, `[Camera]`, `[Inference]`, `[Detection]`, `[Painter]`, `[Performance]`, `[Error]`
- Added per-frame inference latency timing via `Stopwatch` (exposed via `InferenceService.lastLatencyMs`)
- Added 5-second `[Performance]` summaries (camera FPS, inference FPS, avg/min/max latency, frame stats)
- Created [`lib/widgets/debug_overlay.dart`](../lib/widgets/debug_overlay.dart) — visual HUD for debug builds (`kDebugMode`)
- Added error handling: try/catch around interpreter creation + frame loop; isolate errors propagated to main isolate via `{'type': 'error'}`
- Extended isolate message protocol: `{'type': 'result'/'error'/'model_loaded'}` with latency + frame metadata
- Replaced all `print()` calls with `debugPrint()`
- `flutter analyze`: 0 issues

### Issues
- `CameraValue` has no `imageFormatGroup` getter — workaround: store the configured format string
- try/catch on `Interpreter.fromBuffer()` made interpreter nullable — fixed with `!` null-assert
- `_logDetections()` needed locals from `_isolateEntryPoint()` — passed as parameters

### Decision
- Use `debugPrint()` with consistent bracketed prefixes (avoid `print()`)
- Debug overlay rendered only when `kDebugMode` — absent in release builds
- Log throttling (every 30th frame/paint) to avoid console spam
- Message protocol extended backward-compatibly via a `type` field

### Next Session
- Begin Milestone 1: Implement TTS audio feedback
- Add permission-denied UI state
- Complete error recovery (isolate restart on crash)

## 2026-07-22

### Objective
- Establish project documentation system (`docs/` directory)

### Completed
- Created `docs/` directory with 9 documentation files
- Documented architecture, implementation plan, progress, decisions, known issues
- Created testing plan, benchmark template, development workflow guide
- Updated `README.md` from boilerplate to project-specific content
- Preserved `chat_spec.md` and `auditor.md` as historical records

### Issues
- None — documentation-only session

### Decision
- All documentation lives in `docs/`; historical files preserved at root
- Cross-reference via "See also" headers rather than duplicated content

### Next Session
- Begin Milestone 1: Implement TTS audio feedback
