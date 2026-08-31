# EyeCue — Changelog

> Human-readable summary of changes per version. Not a Git log.  
> See [`implementation-progress.md`](implementation-progress.md) for detailed task tracking.

---

## Unreleased — NCHW Model and Backend Candidate (2026-09-01)

### Added
- Added [`yolov8n_int8_new.tflite`](../assets/yolov8n_int8_new.tflite), a structurally validated YOLOv8n candidate with FLOAT32 runtime I/O, input shape `[1,3,640,640]` (NCHW), output shape `[1,84,8400]`, and internally quantized tensors.
- Added [`tensor_rotation.dart`](../lib/models/tensor_rotation.dart) with pure NHWC (interleaved) and NCHW (planar) square-tensor rotation/mirroring support, plus 14 focused unit tests.

### Changed
- [`inference_isolate.dart`](../lib/services/inference_isolate.dart) now selects input layout from runtime metadata, writes NCHW or NHWC preprocessing data, and attempts explicit XNNPACK for the candidate. The delegate is retained for the interpreter lifetime; recoverable setup/invocation failures retry on a four-thread CPU interpreter.
- [`validate_flatbuffer.dart`](../tool/validate_flatbuffer.dart) now validates the new model's verified tensor counts: 2 FLOAT32, 90 INT32, and 356 INT8 tensors.

### Verified
- `flutter analyze`: 0 issues. `flutter test`: **73 passing**.
- The flatbuffer and PNG validators pass, and the generated debug APK contains the new model asset.
- After device storage was cleared, the exact debug APK installed on the API 33 Snapdragon 695 test phone (`2201116SG`). Startup confirmed the NCHW/FLOAT32 candidate and successful explicit XNNPACK interpreter creation. A short live run completed 65 XNNPACK-labelled frames with calculated mean latency 164.8 ms (median 157.7 ms; range 150.2–377.3 ms); app summaries reported approximately 5.7–6.2 inference FPS. A separate earlier observation returned one `tv` detection at 67.9% confidence and 113.7 ms. No candidate-process fatal signal was observed in the captured logs.

### Notes
- This entry is intentionally unreleased. The stable v0.2.2 CPU/NHWC baseline and its informal 2.1 FPS / 606 ms observations remain the only release-baseline evidence; the candidate values are short app-telemetry observations, not formal benchmark results.
- The historical Snapdragon 695 XNNPACK SIGSEGV remains unresolved: native faults are not catchable by Dart, even though recoverable Dart-level failures now have a CPU fallback.

---

## v0.2.2 — "UI Layout Fixes: Stable Camera Viewport + Contained Charts" (2026-08-16)

### Fixed
- **Camera viewport no longer resizes when detections appear.** The Detection
  screen used a `Column` with the camera in `Expanded` and a content-sized
  controls panel whose card list height was `detections × 78`, so adding
  detections shrank the camera region. The layout now reserves a **fixed**
  content region ([`detection_screen.dart`](../lib/screens/detection_screen.dart)):
  a `LayoutBuilder`-derived `SizedBox` (height = `constraints.maxHeight × 0.32`,
  clamped to 200–320) holds the warning banner + a scrollable detection list +
  controls; the camera stays in the remaining `Expanded` space. Detection
  content only scrolls inside its own allocated region. The warning banner
  moved out of the camera overlay and below the camera.
- **Logs & Reports charts now stay inside their containers.**
  [`charts.dart`](../lib/widgets/charts.dart) previously used fixed upper clamps
  (`latency clamp(50,500)`, `FPS clamp(1,30)`), so unusually high values were
  drawn outside the plot, benchmark lines could sit above a shrunken scale, and
  the bar chart had no `maxY` (fl_chart defaults it to 0). Each chart now
  derives its Y bounds from the actual dataset with headroom
  (`max(dataMax × 1.2 + padding, floor)`), benchmark lines are drawn only when
  they fit the computed scale, and the bar chart sets an explicit dynamic
  `maxY`. Empty datasets show a "No data available yet" placeholder.

### Verified
- `flutter analyze`: 0 issues. `flutter test`: 59 passing (added chart
  regression tests for empty / very-high / constant / single-bucket data).
- On-device (Android 13, API 33): Home → Detect renders with the fixed content
  region; camera starts on demand and streamed 2-object detections; Settings
  and Logs & Reports render with live telemetry (Avg FPS 2.1, Avg Latency
  606 ms, 123 detections); Overview/Charts/Logs all render. **0 exceptions /
  RenderFlex overflows across the whole session.**

---

## v0.2.1 — "Fix Startup Theme Assertion" (2026-08-16)

### Fixed
- **Startup crash during theme construction.** [`EyeCueApp._buildTheme()`](../lib/main.dart) called
  `base.textTheme.apply(fontSizeFactor: 1.12, ...)`, which failed the Flutter
  assertion `fontSize != null || (fontSizeFactor == 1.0 && fontSizeDelta == 0.0)`.
  In Flutter's Material 3 typography the default `TextTheme` is **color-only**
  (`fontSize == null` for every style; geometry is merged per-locale at render
  time), so `TextTheme.apply(fontSizeFactor:)` asserts on every style.
- **Fix:** the theme now supplies an explicit high-contrast `TextTheme`
  ([`_highContrastTextTheme()`](../lib/main.dart)) with concrete font sizes (M3
  defaults scaled ~1.12×) and white text — same accessibility intent, valid
  theme. No camera/inference/UI behavior changed.

### Verified
- `flutter analyze`: 0 issues. `flutter test`: 53 passing (new regression test
  pumps `EyeCueApp` and asserts the Home screen renders with a concrete
  white text theme).
- On-device (Android 13, API 33): app installs, launches, renders Home, and the
  detection pipeline continues to run (live `[Detection]` frames); no FATAL, no
  assertion, no overflow in logcat.

---

## v0.2.0 — "Assistive Application UI" (2026-08-16)

### Added
- **Application navigation** ([`lib/navigation/app_shell.dart`](../lib/navigation/app_shell.dart)): 4-tab bottom navigation — **Home, Detect, Settings, Help** — with lazy page building and state preservation (`IndexedStack`), system-back to Home, and Logs & Reports pushed as a route from Settings.
- **Home screen** ([`lib/screens/home_screen.dart`](../lib/screens/home_screen.dart)): EyeCue branding/subtitle, detection status card (reflects Auto-Start), and a primary "Go to Live Camera" action.
- **Detection screen** ([`lib/screens/detection_screen.dart`](../lib/screens/detection_screen.dart)): the validated camera/inference pipeline (persistent isolate, YUV420, orientation, NMS, bounding-box painter) preserved, now wrapped in an assistive UI — live preview + boxes, status pill, audio mute toggle, detection object cards with priority badges, high-priority warning banner, and visible high-contrast controls (Start/Stop, Pause/Resume, Repeat, Scan). Developer telemetry moved off the primary screen.
- **Text-to-speech** ([`lib/services/tts_service.dart`](../lib/services/tts_service.dart)): `flutter_tts` wired via an injectable `TtsEngine`; audio enabled/muted state, announcement cooldown, same-label de-duplication, urgent (high-priority) bypass, and repeat-last-alert.
- **Thesis gestures** ([`lib/services/gesture_controller.dart`](../lib/services/gesture_controller.dart) + [`lib/widgets/gesture_surface.dart`](../lib/widgets/gesture_surface.dart)): two-finger double tap (start/stop), single tap (pause/resume), three-finger tap (quick scan), swipe down (repeat alert) — each with haptic + TTS confirmation.
- **Settings screen** ([`lib/screens/settings_screen.dart`](../lib/screens/settings_screen.dart)) with persisted preferences ([`lib/services/settings_service.dart`](../lib/services/settings_service.dart), file-backed JSON): Vibration Feedback, Auto-Start on Open, Low Power Mode (applies a dispatch throttle), Audio/Voice guidance, and Logs & Reports entry.
- **Help screen** ([`lib/screens/help_screen.dart`](../lib/screens/help_screen.dart)): how it works, gesture controls, confirmation feedback, and Android usage tips.
- **Logs & Reports** ([`lib/screens/logs_reports_screen.dart`](../lib/screens/logs_reports_screen.dart) + [`lib/widgets/charts.dart`](../lib/widgets/charts.dart)): Overview (FPS, latency, detections, high-priority alerts, session duration), Charts (latency with 300 ms line, FPS with 15 FPS line, detection-frequency bars), and a chronological Logs tab. Accuracy/Precision/Recall/F1/mAP are explicitly shown as **unavailable** (require ground truth) rather than fabricated.
- **Spatial / priority interpretation** ([`lib/services/spatial_analysis_service.dart`](../lib/services/spatial_analysis_service.dart) + [`lib/models/detection_info.dart`](../lib/models/detection_info.dart)): left/center/right from box geometry, class-based priority tiers, and an *approximate* proximity band (explicitly labeled as a heuristic, not a measured distance).
- **Runtime telemetry** ([`lib/services/telemetry_service.dart`](../lib/services/telemetry_service.dart)): session records, detection log entries, latency/FPS samples, aggregates, and per-minute frequency buckets.
- **Haptics** ([`lib/services/haptics_service.dart`](../lib/services/haptics_service.dart)): dependency-free `HapticFeedback` wrapper respecting the Vibration Feedback setting.

### Tests
- Replaced the boilerplate counter test with meaningful tests: navigation shell (4 tabs + Home CTA), Home/Settings/Help screens, priority badge / detection card / warning banner / accessible button, TTS cooldown + de-duplication + repeat, settings persistence, spatial/priority classification, telemetry aggregation, and the gesture controller state machine. `flutter test` → **52 passing**.

### Notes
- The previous single-screen developer UI (`camera_screen.dart`) was retired in favor of `detection_screen.dart`; `info_panel.dart` / `debug_overlay.dart` remain in the tree but are no longer used by the primary UI.
- Proximity bands are heuristics and are always phrased as "approximately …"; calibrated distance, movement/approach tracking, and accuracy/precision/recall/mAP remain intentionally out of scope for the live app (see the [thesis-product-status-audit](thesis-product-status-audit.md)).
- The ML pipeline (camera, YUV, orientation, TFLite, parser, NMS, thresholds, painter, forensics) was **not** modified.

---

## v0.1.7.1 — "Post-Processing Completion: NMS + Confidence Threshold" (2026-08-01)

### Added
- **Class-wise Non-Maximum Suppression (NMS)** in [`_parseYolov8Output`](../lib/services/inference_isolate.dart) — IoU threshold `0.45`; overlapping anchors of the same class are suppressed, so each object renders as one box instead of a jumble (previously every object fired many overlapping anchors).
- **Pre-NMS confidence threshold lowered to `0.25`** (standard YOLOv8) — was `0.5`, which dropped true detections while passing spurious full-frame boxes.
- Pre-NMS candidate count exposed and logged as `candidates(before NMS)=N → after NMS=M`.

### Fixed
- The real post-processing gaps identified in [`docs/inference-pipeline-probe.md`](inference-pipeline-probe.md): missing NMS and an over-high pre-NMS threshold. Verified on-device by the static-image test ([`docs/static-image-test.md`](static-image-test.md)): bus + 4 people detected at 0.47–0.92 confidence (44 pre-NMS → 5 post-NMS).

### Notes
- No preprocessing, YUV conversion, model loading, or parser indexing changed — only threshold + NMS added after argmax.
- This entry was added retroactively during the 2026-08-14 documentation sync; the implementation dates from 2026-08-01.

---

## v0.1.7 — "Device-Independent Orientation" (2026-08-01)

### Added
- [`BoxTransform`](../lib/models/box_transform.dart) (NEW) — the single, device-independent source of truth for all orientation math:
  - `deviceDegreesFor` — `DeviceOrientation` → degrees using the camera plugin's own counter-clockwise convention (`landscapeLeft→90`, `landscapeRight→270`), verified against `camera_android_camerax._getRotationConstantFromDeviceOrientation`
  - `displayRotationDegrees` — `sensorOrientation` + device degrees + lens direction (back: `(s − d + 360) % 360`, front: `(s + d + 360) % 360`); no hardcoded angles
  - `uprightDims` — display dimensions for a rotated sensor frame (swap W/H on 90°/270°)
  - `rotateRect` / `invertRect` — pure, mutually-inverse normalized-box rotations (kept for unit tests / future sensor-space consumers)
  - `mirrorRect` — front-camera X-flip in upright space
- **Upright tensor inference** ([`inference_isolate.dart`](../lib/services/inference_isolate.dart)) — `processFrame` now carries orientation metadata (`rotationDegrees`, `mirror`, `sensorOrientation`, `deviceDegrees`, `lensFacing`); the isolate rotates + optionally X-mirrors the square 640×640 NHWC input tensor to UPRIGHT before `interpreter.run()` (lossless transpose). Parser/NMS untouched — boxes after NMS are already in upright space.
- [`detection_screen.dart`](../lib/screens/detection_screen.dart) — computes rotation per frame from the same `controller.value.deviceOrientation` that `CameraPreview` uses (painter and preview agree by construction); preview + painter sized with the UPRIGHT image dimensions; feeds sensor/lens into `recordCamera`.
- [`forensic_log.dart`](../lib/services/forensic_log.dart) — `recordOrientation` (per-frame sensor/device/rot/mirror/lens/dims) + sensor/lens fields in `recordCamera`.

### Changed
- [`bounding_box_painter.dart`](../lib/widgets/bounding_box_painter.dart) — removed all sensor-orientation/lens/mirror knowledge; now a pure normalized→pixel mapper over the upright image (`applyBoxFit` math identical to the preview `FittedBox`).

### Fixed
- **Portrait camera detection** — the last camera-path defect (`docs/camera-path-forensics.md`): frames are delivered in sensor orientation (this device: `sensorOrientation=90°`, always 320×240 landscape) and were never rotated, so portrait-hold scenes reached the model rotated 90° → ~0 detections. Rotating the input to upright makes portrait detection parity with landscape.

### Verified
- `flutter analyze`: 0 issues.
- Back · portrait: ✅ detections at maxConf 0.91 (was 0); `rot=90 in=320×240 out=240×320`; input rotation byte-exact (MAE 0.000).
- Static-image regression: ✅ `rot=0`, byte-identical detections (person 0.9173, 5 objects).
- Back · landscape: convention bug found & fixed (plugin counter-clockwise mapping); physical-hold re-validation deferred to next session.
- Front · portrait/landscape: math implemented (verified against plugin convention); device run pending.

### Notes
- **Deliberate deviation from the design review** (`docs/orientation-design-review.md` recommended sensor-space inference + post-NMS box transform): on-device evidence proved the model sees a 90°-rotated scene in portrait → 0 detections, so there are no boxes to transform. Input rotation is the only design satisfying "portrait quality matches landscape"; parser/NMS code is unchanged. See `docs/orientation-implementation.md` §4.
- No preprocessing, YUV conversion, parser, thresholds, NMS, model loading, or forensic-logging behavior changed (beyond the added orientation channels).

---

## v0.1.3 — "Forensic File Logging" (2026-08-01)

### Added
- [`ForensicLog`](../lib/services/forensic_log.dart) — structured, file-based diagnostics written to `<application_documents>/debug/run_YYYYMMDD_HHMMSS/` so the pipeline can be diagnosed offline without logcat:
  - `camera.txt` — CameraImage geometry (rowStride/pixelStride/plane lengths) + inferred format (I420 / NV21-NV12 / UNKNOWN), once
  - `preprocess.txt` — per-channel R/G/B min/max/mean/std, resize info, normalization stats (allZero/allOne/NaN/Inf), frame 1
  - `tensor.txt` — input tensor before `run()`: shape/dtype/expected vs actual length/first-64/last-64/sample/min/max/mean/std, frame 1
  - `output.txt` — raw output stats, top-20 confidences, p50/p95/p99, counts at >0.01…>0.50, frame 1
  - `parser.txt` — top-20 before thresholding with raw + decoded boxes; counts after threshold and after NMS (0 — none implemented), frame 1
  - `performance.txt` — per-frame latency, camera/inference FPS, queue depth, dropped frames, max confidence, detections
  - `errors.txt` — every exception raised by the instrumentation itself (never affects inference)
  - `summary.txt` — auto-generated diagnosis every 50 processed frames and on close (PASS/FAIL per stage, max confidence, P99, top class, distribution, ranked root causes)
  - PNG image dumps of the first frame: `frame_original.png` (Y luma), `frame_rgb.png` (YUV→RGB at camera res), `frame_resized.png`, `frame_model_input.png`
- [`PngEncoder`](../lib/models/png_encoder.dart) — pure-Dart PNG encoder (isolate-safe, no `dart:ui`); validated with [`tool/validate_png.dart`](../tool/validate_png.dart) and cross-decoded with Python (pixels match exactly)
- Every `ForensicLogger` write is synchronous and flushed; all writes are try/catch-guarded so logging can never break inference
- Replaced the console-based probes: [`InferenceProbe`](../lib/services/inference_probe.dart) and [`InputProbe`](../lib/services/input_probe.dart) are now disabled (`enabled = false`) and their call sites removed

### Changed
- [`inference_isolate.dart`](../lib/services/inference_isolate.dart) — run directory created at startup and passed to the isolate; forensic channels wired into the frame loop via `_safeForensic`; `processFrame` now forwards `cameraFps`/`droppedFrames` (logging only)
- [`detection_screen.dart`](../lib/screens/detection_screen.dart) — records `camera.txt` on the first frame

### Notes
- All instrumentation is removable: delete the forensic files/call sites and flip the `enabled` switches.
- No inference, preprocessing, postprocessing, thresholds, model loading, or timing behavior was changed.

---

## v0.1.6 — "Camera Preview UI Redesign" (2026-08-01)

### Added
- **Redesigned main screen** (`camera_screen.dart`):
  - Strict **3:4 portrait camera preview anchored to the top** (`AspectRatio(3/4)` box), feed contained via `BoxFit.contain` — never stretched, warped, or cropped; full frame always visible.
  - Permanent **bottom information panel** with Material Tabs — exactly two tabs: **Metrics** and **Detections** (the panel never floats over the preview).
  - Preview width is computed from screen size while reserving a minimum panel height, so the layout adapts to different screens without ever squeezing the panel or distorting the feed.
- **Metrics tab** ([`info_panel.dart`](../lib/widgets/info_panel.dart)): live FPS / average FPS / inference time / end-to-end latency, objects detected, highest/lowest/average confidence, camera resolution, preview resolution, model input resolution, aspect ratio, model name, backend, quantization type, thread count (un-instrumented values shown as "—").
- **Detections tab**: chronological detection history (newest at top), each entry with object class, confidence %, and relative age ("Just now / Xs ago / Xm ago"); scrolls independently; capped at 50 entries; 1-second timer refreshes ages.
- Bounding boxes and labels rendered by [`BoundingBoxPainter`](../lib/widgets/bounding_box_painter.dart) directly inside the preview box using the same `applyBoxFit(BoxFit.contain)` transform as the preview — geometrically accurate, never scaled independently.

### Changed
- Floating debug overlay removed from the screen (its data now lives in the Metrics tab); `DebugOverlay` widget retained but unused.

### Verified
- `flutter analyze`: 0 issues.
- Layout math checked for portrait (412×915 → 412×549 preview + 366 panel) and landscape (915×412 → 114×152 preview + 260 panel) — panel never squeezed below the minimum.

### Notes
- No inference, preprocessing, parser, thresholds, NMS, model loading, or forensic-logging behavior changed.

---

## v0.1.5 — "Aspect-Correct Preview & Overlay Alignment" (2026-08-01)

### Fixed
- **Preview stretching:** `CameraPreview` was placed directly in a `Stack(fit: StackFit.expand)`, so the camera texture was scaled to fill the screen without preserving aspect ratio, while the painter assumed a letterboxed preview — the two disagreed, misaligning boxes.
- **Preview layout** (`camera_screen.dart`): the preview is now rendered at the camera's native aspect ratio inside `FittedBox(fit: _previewFit)` with a `SizedBox` sized to the frame (`BoxFit.contain` = letterbox, `BoxFit.cover` = center-crop; single `static const` switch).
- **Overlay transform** ([`bounding_box_painter.dart`](../lib/widgets/bounding_box_painter.dart)): `_calculateImageRect` now uses `applyBoxFit` — the exact same math as `FittedBox` — so the painter and the preview layout always agree (no offsets or magic constants).
- Normalized → screen mapping (per-axis): `sx = offX + nx·destW`, `sy = offY + ny·destH`, where `(destW, destH, offX, offY)` come from `applyBoxFit`; front-camera horizontal mirroring unchanged; boxes are clamped to the image rect (edges correctly fall off-screen under `cover`).

### Verified
- Transform numerically checked for a 320×240 frame on a 1080×2400 portrait screen: contain → 1080×810 centered (bars), cover → 3200×2400 with edge crop; aspect preserved in both; matches `FittedBox` exactly.
- `flutter analyze`: 0 issues.

### Notes
- No preprocessing, YUV conversion, inference, parser, thresholds, NMS, model loading, or forensic logging changed.

---

## v0.1.4 — "Camera Preprocessing Repair" (2026-08-01)

### Fixed
- **Manual YUV420→RGB converter** ([`_convertYUV420toRGB`](../lib/services/inference_isolate.dart)) repaired to handle the actual CameraX delivery:
  - Honors real per-plane `rowStride`/`bytesPerRow` and `pixelStride`/`bytesPerPixel` (previously assumed tightly-packed rows — the Y rowStride 512 vs width caused row smearing).
  - Supports **planar I420** (pixelStride 1) and **semi-planar NV12/NV21** (pixelStride 2, interleaved chroma read from the U-led plane per the YUV_420_888 contract).
  - Resize (nearest-neighbor) and normalization math unchanged.
- `camera_screen.dart` now forwards each plane's geometry to the isolate and handles 2-plane (semi-planar) deliveries.
- Forensic image dumps (`frame_rgb.png`) use the same geometry-aware sampling.

### Verified
- Converter algorithm validated against synthetic planar I420 and semi-planar NV12 data (including rowStride padding) — pixel-exact vs the BT.601 reference; color primaries correct.
- `flutter analyze`: 0 issues.

### Notes
- No libraries, model, parser, or thresholds changed.

---

## v0.1.2 — "Runtime Model Introspection" (2026-08-01)

### Added
- [`ModelMetadata`](../lib/models/model_metadata.dart) — immutable, self-describing runtime snapshot of the loaded model:
  - model name, input/output datatypes & shapes, scale/zeroPoint, quantized flags
  - derived classes/anchors, requires-input-quantization / requires-output-dequantization
- [`ModelType`](../lib/models/model_metadata.dart) classification — FP32 / Full INT8 Quantized / Full UINT8 Quantized / Weight-Quantized / Unknown. Detected from runtime tensors + an internal tensor scan. **Never guessed from filenames.**
- [`tflite_flatbuffer.dart`](../lib/models/tflite_flatbuffer.dart) — pure-Dart flatbuffer walker that counts internal tensor types (validated 1:1 against the reference `tflite` Python package on both bundled models)
- Float16 (half-precision) byte conversion helpers for FLOAT16 I/O edge cases
- Dynamic inference-path selection: preprocessing quantizes only when the input tensor is quantized; the parser dequantizes only when the output tensor is quantized — all from runtime metadata
- Startup diagnostic logging: `MODEL INFORMATION` banner in the isolate + `[Model]` summary on the main isolate
- Debug overlay now renders live model info (name, type, I/O types, shapes, classes, anchors, quantized, scale/zeroPoint) — updates automatically for any model type
- CLI validation tool [`tool/validate_flatbuffer.dart`](../tool/validate_flatbuffer.dart) — `dart run tool/validate_flatbuffer.dart`
- Busy gate releases on isolate errors (`errorStream` in `InferenceService`), preventing permanent frame-drop wedges

### Changed
- [`inference_isolate.dart`](../lib/services/inference_isolate.dart) rewritten around `ModelMetadata`:
  - dtype-matched pre-allocated buffers (Float32/Float64/Int8/Uint8/Int16/Float16)
  - raw `ByteBuffer` I/O to `interpreter.run()` — **no reshape**, no input-tensor resizing
  - `model_loaded` message now carries the full metadata JSON map
- [`debug_overlay.dart`](../lib/widgets/debug_overlay.dart) — sections for MODEL / PERFORMANCE / CAMERA
- `camera_screen.dart` — overlay wired to `metadataNotifier`; `_isInferring` reset on isolate error

### Fixed
- **Inference-isolate crash** `NoSuchMethodError: Class 'Float32List' has no instance method 'reshape'` — `reshape()` was a `List` extension method invoked on a `dynamic` receiver; replaced with raw `ByteBuffer` I/O
- **Latent output crash** — flat `List` output buffer would have failed tflite_flutter's `copyTo()` shape check; now a shape-exempt raw `ByteBuffer` is used
- **Latent input corruption** — flat `Float32List` input would have triggered an automatic 1-D `resizeInputTensor`; `ByteBuffer` input bypasses shape inference

### Notes
- Both bundled models are **FLOAT32 I/O with INT8 weights** → classified **Weight-Quantized** (input `[1, 640, 640, 3]`, output `[1, 84, 8400]`). The `yolov8n_int8.tflite` file is float32-I/O too and is not bundled.
- The debug overlay now changes automatically if a full INT8 model is loaded later (no code changes needed).

### Up Next (v0.2.0 — "Audible MVP")
- TTS audio feedback
- Permission-denied UI state
- Complete error recovery (isolate restart)
- Wire or remove unused dependencies

---

## v0.1.1 — "Bounding Box Overlay & Debug Instrumentation" (2026-07-22)

### Added
- Bounding box `CustomPainter` overlay ([`lib/widgets/bounding_box_painter.dart`](../lib/widgets/bounding_box_painter.dart))
  - Normalised→screen coordinate transformation accounting for AspectRatio letterboxing
  - Front-camera horizontal mirroring
  - Label pills with confidence percentages, shadow rendering, per-class colour palette
- Structured debug logging across the whole pipeline with consistent prefixes:
  `[Service]`, `[Model]`, `[Camera]`, `[Inference]`, `[Detection]`, `[Painter]`, `[Performance]`, `[Error]`
- Per-frame inference latency timing via `Stopwatch` (exposed via `InferenceService.lastLatencyMs`)
- 5-second `[Performance]` summaries (camera FPS, inference FPS, avg/min/max latency, frame stats)
- Visual debug overlay ([`lib/widgets/debug_overlay.dart`](../lib/widgets/debug_overlay.dart)) — debug builds only (`kDebugMode`)
- Error handling: try/catch around interpreter creation and the frame processing loop
- Isolate error propagation to the main isolate via `{'type': 'error'}`

### Changed
- Replaced all `print()` calls with `debugPrint()` (throttled in release)
- Extended isolate message protocol: `{'type': 'result'/'error'/'model_loaded'}` with latency + frame metadata
- `InferenceService` now exposes `lastLatencyMs` and `lastFrameNumber` getters

### Fixed
- Inference isolate can no longer die silently — errors are caught and reported to the main isolate

### Known Issues
- No TTS integration (`flutter_tts` declared but unused)
- No NMS (Non-Maximum Suppression) — duplicate boxes for the same object
- No permission-denied UI
- Error recovery (isolate restart) not yet implemented — only error reporting exists
- 4 unused dependencies (Riverpod, fl_chart, path_provider, flutter_tts)
- See [`known-issues.md`](known-issues.md) for full list

### Up Next (v0.2.0 — "Audible MVP")
- TTS audio feedback
- Permission-denied UI state
- Complete error recovery (isolate restart)
- Wire or remove unused dependencies

---

## v0.1.0 — "Inference Pipeline" (2026-07-22)

### Added
- Persistent inference isolate (`Isolate.spawn()` at startup, single `Interpreter` instance for app lifetime)
- Dynamic tensor shape querying from TFLite model metadata
- Manual YUV420→RGB conversion (no external image library)
- INT8 dequantization support (scale/zeroPoint from tensor params)
- Argmax per-box post-processing with confidence threshold (0.5)
- Frame-dropping busy gate (`_isInferring` boolean)
- Stream-based detection results via `StreamController.broadcast()`
- NHWC/NCHW automatic detection from tensor shape
- COCO 80-class label loading from `labels.txt`
- Camera initialization with `ResolutionPreset.low` and YUV420 format
- Camera permission handling via `permission_handler`
- Camera preview widget with `CameraPreview`
- `Detection` data class with classId, confidence, and bounding box
- Project documentation system (`docs/` directory, 12 files)
- `README.md` with project overview and documentation index

### Changed
- Rebuilt from React Native to Flutter/Dart
- Camera resolution: full 1080p → `ResolutionPreset.low` (avoids unnecessary downscaling)

### Removed
- XNNPACK acceleration disabled due to SIGSEGV on Snapdragon 695 (Adreno 619)

### Known Issues
- No TTS integration (`flutter_tts` declared but unused)
- ~~No bounding box overlay (`CustomPainter` stubbed as TODO)~~ — ✅ Implemented in v0.1.1
- No NMS (Non-Maximum Suppression)
- ~~No error handling in inference isolate~~ — 🟡 Partially addressed in v0.1.1 (try/catch + error propagation; restart recovery still missing)
- No permission-denied UI
- 4 unused dependencies (Riverpod, fl_chart, path_provider, flutter_tts)
- See [`known-issues.md`](known-issues.md) for full list

### Up Next (v0.2.0 — "Audible MVP")
- TTS audio feedback
- ~~Bounding box `CustomPainter` overlay~~ — ✅ Done in v0.1.1
- ~~Error handling in inference isolate~~ — 🟡 Partially done in v0.1.1
- Permission-denied UI state
