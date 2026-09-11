# EyeCue — Implementation Progress

> **Last Updated:** 2026-09-10 (Detection screen visual redesign)
> See also: [`implementation-plan.md`](implementation-plan.md) (roadmap), [`project-status.md`](project-status.md) (summary).

## Current Unreleased Candidate (2026-09-10) — Detection Screen Visual Redesign

- ✅ Restyled both Detection child screens — [`detection_screen.dart`](../lib/screens/detection_screen.dart) (Custom) and [`ultralytics_detection_screen.dart`](../lib/screens/ultralytics_detection_screen.dart) (Ultralytics) — as a visual-only change per [`detection-screen-plan.md`](detection-screen-plan.md). Both scope the Home-local light theme [`buildHomeTheme()`](../lib/theme/app_home_theme.dart) to the Detection subtree with dark status-bar icons (`AnnotatedRegion<SystemUiOverlayStyle>`), using the existing `kHome*`/`kSpace*`/`kRadius*` tokens as-is (no theme/token file change). The light chrome does not leak into Home, Help, Settings, Logs & Reports, or the shell navigation bar.
- ✅ The camera viewport is now a rounded dark card (`kHomeInk`, `kRadius24`, clipped). The viewport stack (`FittedBox` → `CustomPaint(BoundingBoxPainter)` → `_GestureHint` → `GestureSurface`) and the `applyBoxFit` overlay math are unchanged; the Ultralytics `YOLOView` native overlay is unchanged. No `LIVE CAMERA` label was added.
- ✅ The header keeps the single `Detection Mode` title using the theme's `titleLarge` (non-bold `w600`, matching the Settings/Help `AppBar` title style) with the `StatusPill` retained as its own live-region element. The `StatusPill` and the `AUDIO ON` pill share one horizontal row, with the audio pill end-aligned right; the Ultralytics performance line and error text remain below that row.
- ✅ Replaced the circular audio `IconButton` with an inline `AUDIO ON` / `AUDIO OFF` pill (private `_AudioPill` helper colocated in each screen file): `kHomeSurfaceCard`, `kRadius20`, `kHomeShadowSoft`, `kSpace8` leading dot (`kHomeAccentCyan` on / `kHomeInkMuted` off), uppercase `labelMedium` label with `letterSpacing: 0.5`, `kSpace12`/`kSpace6` padding (matching `StatusPill`), and a ≥48dp touch target. Toggle behavior, tooltip text, enabled state, and the `ListenableBuilder` merge are preserved; the pill exposes a semantic label/role/state.
- ✅ The controls panel now uses `kHomeSurfaceBase` with `kSpace12`/`kSpace8` padding; the five-button `Wrap` is preserved with `kSpace8` spacing/runSpacing and `prominent: true` on Pause/Resume and Scan only. The disabled Pause/Resume state and the conditional Correct button are preserved. The panel content is wrapped in a `SingleChildScrollView` (detection list bounded to `maxHeight: 160`, still scrolling internally) so the fixed-height region can never overflow. The gesture-hint text color is now `kHomeInkMuted`.
- ✅ `_GestureHint` (both screens) now uses `kOverlayBlack`, `kRadius20`, and `kSpace14`/`kSpace8`/`kSpace10`; white text, `Colors.white24` border, bottom-center position, and copy are preserved.
- ✅ Token-consistent restyle of the shared Detection widgets: [`status_pill.dart`](../lib/widgets/status_pill.dart), [`warning_banner.dart`](../lib/widgets/warning_banner.dart), [`detection_card.dart`](../lib/widgets/detection_card.dart), [`priority_badge.dart`](../lib/widgets/priority_badge.dart), [`detection_state_panel.dart`](../lib/widgets/detection_state_panel.dart), and [`detection_correction_sheet.dart`](../lib/widgets/detection_correction_sheet.dart). The correction sheet uses a `Material` surface so `ListTile` ink/splash behavior is preserved.
- ✅ Restyled the [`engine_detection_screen.dart`](../lib/screens/engine_detection_screen.dart) temporary-fallback notice to the light surface; `liveRegion: true` is preserved.
- ✅ The exact live-region split is preserved: `StatusPill`, `WarningBanner`, `DetectionStatePanel`, and the fallback notice remain live regions; `DetectionCard` remains **not** a live region.
- ✅ Added a `DetectionScreen` group to [`test/widget_test.dart`](../test/widget_test.dart) (plugin-free subtrees: title, `StatusPill`, all five controls, `AUDIO ON` pill, no overflow) and extended [`test/accessibility/semantics_test.dart`](../test/accessibility/semantics_test.dart) (audio-pill enabled semantics, `DetectionCard` non-live-region, 200% text-scale no-overflow).
- ✅ Post-implementation fixes (on-device, SM S9010 / Android 15 / API 35): the controls-panel overflow (`BOTTOM OVERFLOWED BY 74 PIXELS`) was fixed by wrapping the panel in a `SingleChildScrollView` (detection list bounded to `maxHeight: 160`) and raising the `contentHeight` clamp floor from `200.0` to `260.0`; the `AUDIO ON` pill padding was reduced to `kSpace12`/`kSpace6` to match `StatusPill`; and the `Detection Mode` header now uses the theme's `titleLarge` (non-bold `w600`) with `kSpace16` top padding, matching the Settings/Help `AppBar` title position, with the `StatusPill` and `AUDIO ON` pill sharing one row (audio pill end-aligned right).
- ✅ Current validation: `flutter analyze` reports 0 issues, `flutter test` reports **185 passing tests**, and `flutter build apk --debug` succeeds and installs on the physical SM S9010 (API 35) device. On-device verification confirmed the overflow banner is gone, no RenderFlex overflows/exceptions appear, the `AUDIO ON` pill padding matches the status pill, and the header title aligns with the Settings/Help headers.

## Current Unreleased Candidate (2026-09-10) — Logs & Reports Screen Visual Restyle

- ✅ Restyled the existing pushed Logs & Reports route in [`logs_reports_screen.dart`](../lib/screens/logs_reports_screen.dart) as a visual-only change per [`logs-reports-screen-plan.md`](logs-reports-screen-plan.md). The route now scopes the existing Home-local light theme [`buildHomeTheme()`](../lib/theme/app_home_theme.dart) locally with dark status-bar icons (`AnnotatedRegion<SystemUiOverlayStyle>`), scoped to the pushed route only and not leaking into the shell navigation bar or other tabs.
- ✅ The route now uses a centered bounded secondary-screen layout (~480 logical px content bound, constraint-derived) with light surfaces/typography from the existing `kHome*`/`kSpace*`/`kRadius*` tokens as-is (no theme/token file change); spacing follows the 6/8/12/16/20/24 scale and existing radius roles.
- ✅ The Overview, Charts, and Logs tabs were restyled while preserving all telemetry/correction/export/chart bindings, truthful unavailable metrics, navigation, scrolling, and accessibility contracts. [`charts.dart`](../lib/widgets/charts.dart) was **not** modified.
- ✅ Added a focused widget test file [`test/screens/logs_reports_screen_test.dart`](../test/screens/logs_reports_screen_test.dart) (25 tests) covering the real screen, route-local theme scope, all three tabs, exports, correction states, unavailable states, Logs priority semantics, and 200% text-scale no-overflow.
- ✅ Fixed the Engine Comparison rows to render as a single horizontal row with the engine label visible on the left and the value right-aligned flush to the trailing edge (corrected an alignment issue, then a label-starvation regression).
- ✅ Current validation: `flutter analyze` reports 0 issues and `flutter test` reports **178 passing tests**. Physical-device visual QA of the restyled route remains pending.

## Current Unreleased Candidate (2026-09-10) — Settings Screen Visual Redesign

- ✅ Redesigned [`settings_screen.dart`](../lib/screens/settings_screen.dart) as a light, responsive composition that reuses the Home-local light theme [`buildHomeTheme()`](../lib/theme/app_home_theme.dart) and the existing `kHome*`/`kSpace*`/`kRadius*` tokens as-is (no theme/token file change). The light surface is scoped to the Settings subtree only and does not leak into the shell navigation bar or other tabs.
- ✅ The screen is now a `StatelessWidget` that wraps the subtree in `Theme(buildHomeTheme())` with dark status-bar icons (`AnnotatedRegion<SystemUiOverlayStyle>`), then `Scaffold`/`AppBar('Settings')` → `ListenableBuilder` → `SafeArea` → `LayoutBuilder` → `Center` → `ConstrainedBox (~480)` → plain `ListView`. The four cards are ordered Preferences, Audio Guidance, Engine & Sensitivity, and System Performance (dark `kHomeInk` #0A0A0A).
- ✅ Added an optional `TelemetryService? telemetry` parameter; the System Performance card renders `Avg FPS`, `Avg latency (MS)`, and `Avg confidence`, showing `—` when the value is empty or null. No accuracy/precision/recall/F1/mAP/%ACC values are fabricated.
- ✅ [`app_shell.dart`](../lib/navigation/app_shell.dart) forwards `telemetry: widget.telemetry` into the `SettingsScreen` construction (single additive change).
- ✅ Extended the existing `SettingsScreen` group in [`test/widget_test.dart`](../test/widget_test.dart) and added a Settings semantics group to [`test/accessibility/semantics_test.dart`](../test/accessibility/semantics_test.dart) (8 tests).
- ✅ Current validation: `flutter analyze` reports 0 issues, `flutter test` reports **153 passing tests**, and `flutter build apk --debug` succeeds.

## Current Unreleased Candidate (2026-09-09) — Help Screen Visual Redesign

- ✅ Redesigned [`help_screen.dart`](../lib/screens/help_screen.dart) as a light, responsive, accessible composition that reuses the Home-local light theme [`buildHomeTheme()`](../lib/theme/app_home_theme.dart) and the existing `kHome*`/`kSpace*`/`kRadius*` tokens as-is (no theme/token file change). The light surface is scoped to the Help subtree only and does not leak into the shell navigation bar or other tabs.
- ✅ The Help subtree now uses `Theme(buildHomeTheme())` with dark status-bar icons (`AnnotatedRegion<SystemUiOverlayStyle>`); the retained `AppBar(title: 'Help & Gestures')` and the four sections and their copy are preserved verbatim.
- ✅ The four `_HelpCard` sections are now light cards on the light surface with `kRadius24` corners, `kHomeShadowSoft` shadows, token-based padding/separation, and the retained 28px section icons (decorative, excluded from semantics). The section title is the semantic heading for each group.
- ✅ The body is a responsive `SafeArea → LayoutBuilder → Center → ConstrainedBox (maxWidth ~480) → ListView` that scrolls at 200% text scale with no overflow.
- ✅ Extended the existing `HelpScreen` group in [`test/widget_test.dart`](../test/widget_test.dart) (screen title, four section titles, four section icons, verbatim body copy, light-theme assertion) and added a Help semantics group to [`test/accessibility/semantics_test.dart`](../test/accessibility/semantics_test.dart) (screen-title heading, section groups, decorative-icon exclusion, 200% text-scale no-overflow).
- ✅ Current validation: `flutter analyze` reports 0 issues, `flutter test` reports **141 passing tests**, and `flutter build apk --debug` succeeds. On-device (physical Android) the light Help surface, card radius/shadow, large-text behavior, TalkBack semantics, and no RenderFlex overflows/exceptions were confirmed.

## Current Unreleased Candidate (2026-09-09) — Home Screen Visual Redesign

- ✅ Added the `kHome*` light semantic color tokens to [`app_colors.dart`](../lib/theme/app_colors.dart) and the `kRadius3`/`kRadius14`/`kRadius18`/`kRadius24` radius tokens to [`app_radii.dart`](../lib/theme/app_radii.dart).
- ✅ Added the Home-local light theme [`app_home_theme.dart`](../lib/theme/app_home_theme.dart) (`buildHomeTheme()`) with IBM Plex Sans typography and Home shadow tokens; runtime font fetching is disabled there.
- ✅ Added `google_fonts` (^8.2.1) and bundled offline IBM Plex Sans fonts under `assets/fonts/`; registered `assets/logo.png`.
- ✅ Redesigned [`home_screen.dart`](../lib/screens/home_screen.dart): a light, responsive composition with a leading preference/status badge (`READY` / `AUTO-START OFF`), a centered decorative logo + live `EyeCue` wordmark, and a lower instruction region with a truthful headline, supporting copy, the retained `Go to Live Camera` CTA, and a static decorative cyan rail. The layout fills the viewport when short and scrolls at large text scale; the Home subtree uses dark status-bar icons.
- ✅ Replaced the old `_StatusCard` (which claimed "Detection is already running") with a preference-truthful `_StatusBadge` driven by `settings.autoStartDetection`.
- ✅ Updated [`test/widget_test.dart`](../test/widget_test.dart) Home tests, added a Home semantics group to [`test/accessibility/semantics_test.dart`](../test/accessibility/semantics_test.dart), and updated [`test/theme_test.dart`](../test/theme_test.dart) for the light Home text color.
- ✅ Current validation: `flutter analyze` reports 0 issues, `flutter test` reports **133 passing tests**, and `flutter build apk --debug` succeeds. On-device (SM-S9010, Android 15/API 35) the Home renders with the light surface, spread layout, reduced logo/font sizes, and visible status bar; the user confirmed the result visually.

## Current Unreleased Candidate (2026-09-05)

This section describes unreleased work after the v0.2.2 release; the versioned
sections below remain historical release records.

- ✅ Added the metadata-enriched runtime artifact [`yolov8n_int8_new_metadata.tflite`](../assets/yolov8n_int8_new_metadata.tflite) to the asset bundle. It is generated from the byte-identical base graph [`yolov8n_int8_new.tflite`](../assets/yolov8n_int8_new.tflite). Direct inspection found FLOAT32 runtime input/output, input `[1,3,640,640]` (NCHW), output `[1,84,8400]`, and internal INT8 tensors; runtime classification is *Weight-Quantized*, not full integer I/O.
- ✅ Updated [`inference_isolate.dart`](../lib/services/inference_isolate.dart) to select NHWC or NCHW from runtime shape metadata, write the matching YUV→RGB layout, and use [`tensor_rotation.dart`](../lib/models/tensor_rotation.dart) for layout-aware rotation/mirroring.
- 🟡 Added an explicit XNNPACK attempt with delegate lifetime retention, recoverable setup/invocation CPU fallback, and backend logging. The exact debug APK now installs on the Snapdragon 695 target and has initial short-run evidence: 65 completed live frames were labelled `XNNPACK`; the calculated latency mean was 164.8 ms (median 157.7 ms, range 150.2–377.3 ms), and app summaries reported approximately 5.7–6.2 inference FPS. The historical native SIGSEGV remains unresolved because a native fault cannot be caught by Dart.
- ✅ Added 14 tensor-rotation unit tests plus engine-setting, per-engine telemetry, and Ultralytics-adapter coverage; the current repository suite is now **127 passing** and `flutter analyze` reports **0 issues**.
- ✅ Extended the flatbuffer validator to cover the new model and verified the generated debug APK contains it.
- ⚠️ The exact candidate APK installed after storage was cleared. Startup logs confirmed the NCHW/FLOAT32 model metadata and successful explicit XNNPACK interpreter creation. The controlled short run produced no detections across its 65 logged frames, while a separate earlier observation returned one `tv` at 67.9% confidence and 113.7 ms. These are observational results only; formal benchmark, accuracy, thermal, memory, and long-duration stability evidence remains pending.
- ✅ Added persisted **Custom EyeCue** and **Ultralytics** modes using one model/labels/threshold configuration, with native results adapted into EyeCue's existing spatial, priority, TTS, gesture, and telemetry layers. Logs & Reports separates the two engines.
- ✅ Resolved the Android classic LiteRT/LiteRT Next native-runtime packaging conflict. The debug APK builds with both runtime families and installed on the arm64 Snapdragon 695 target.
- 🟡 Both engines processed live camera frames on that device. Post-fix switching passed in both directions after correcting a late Custom-isolate result that could write to a closed stream during Custom→Ultralytics disposal. Controlled paired benchmarking, wide-device coverage, actual delegate confirmation, and the Ultralytics licence decision remain open.
- ✅ Extracted Custom-worker lifecycle/recovery orchestration into [`inference_worker_lifecycle.dart`](../lib/services/inference_worker_lifecycle.dart), with generation-safe stale-message filtering, bounded immediate/delayed retries, healthy-operation budget reset, explicit retry, terminal failure, and disposal/backoff guards.
- ✅ Added seven deterministic lifecycle tests covering worker exit/respawn, stale generations, busy-gate release, delayed retry, terminal failure, disposal during backoff, and healthy recovery. The explicit `reportWorkerExit` API now carries the generation and typed failure at production exit/error call sites.
- ✅ Added bounded recovery telemetry/export rows, metadata-packaging input safety, and synchronized CSV data-dictionary coverage.
- ✅ Added accessibility semantics and 200% text-scale coverage across controls, state panels, charts, detections, correction flows, warnings, and live regions.
- ✅ Current validation: `flutter analyze` reports 0 issues and `flutter test` reports **127 passing tests**. Android identity/signing, release AAB generation, and device validation remain intentionally blocked on project-owner decisions, credentials, and an available Android device.

## v0.2.2 — UI Layout Fixes (2026-08-16)

- ✅ **Stable camera viewport** — Detection screen now reserves a fixed content region (`LayoutBuilder`-derived `SizedBox`, 32% of height, clamped 200–320) for the warning banner + scrollable detection list + controls, so the camera no longer resizes when detections appear ([`detection_screen.dart`](../lib/screens/detection_screen.dart)).
- ✅ **Contained charts** — [`charts.dart`](../lib/widgets/charts.dart) derives Y bounds from the actual data with headroom, draws benchmark lines only when they fit, and sets an explicit dynamic `maxY` for the bar chart; empty data shows a placeholder.
- ✅ `flutter analyze`: 0 issues. `flutter test`: **59 passing** for the v0.2.2 release baseline. On-device (API 33): 0 exceptions / RenderFlex overflows.

## v0.2.1 — Fix Startup Theme Assertion (2026-08-16)

- ✅ Replaced `textTheme.apply(fontSizeFactor: 1.12, ...)` (asserted on M3's color-only `TextTheme`) with an explicit high-contrast `_highContrastTextTheme()` ([`main.dart`](../lib/main.dart)). `flutter analyze`: 0 issues. `flutter test`: **53 passing** (regression test in `test/theme_test.dart`).

## v0.2.0 — Assistive Application UI (2026-08-16)

### Application Navigation (100%)

- ✅ 4-tab bottom navigation shell: Home, Detect, Settings, Help ([`app_shell.dart`](../lib/navigation/app_shell.dart))
- ✅ Lazy page building + state preservation via `IndexedStack` (camera state survives tab switches)
- ✅ System-back returns to Home; Logs & Reports pushed as a route from Settings
- ✅ Home "Go to Live Camera" CTA switches to the Detect tab

### Screens (100% of new screens)

- ✅ **Home** ([`home_screen.dart`](../lib/screens/home_screen.dart)): branding, subtitle, Auto-Start-aware status card, "Go to Live Camera" CTA
- ✅ **Detection** ([`detection_screen.dart`](../lib/screens/detection_screen.dart)): validated camera/inference pipeline preserved; assistive UI (status pill, audio mute, object cards, warning banner, visible controls, gesture surface)
- ✅ **Settings** ([`settings_screen.dart`](../lib/screens/settings_screen.dart)): Vibration, Auto-Start, Low Power, Audio, Logs & Reports
- ✅ **Help** ([`help_screen.dart`](../lib/screens/help_screen.dart)): how it works, gestures, confirmation, Android tips
- ✅ **Logs & Reports** ([`logs_reports_screen.dart`](../lib/screens/logs_reports_screen.dart)): Overview / Charts / Logs tabs

### Audio Guidance (100% of the UI-phase TTS)

- ✅ [`tts_service.dart`](../lib/services/tts_service.dart): `flutter_tts` wired via injectable `TtsEngine`; mute state, cooldown, same-label de-duplication, urgent (high-priority) bypass, repeat-last
- ✅ Detection announcements, start/stop/pause/resume/scan announcements, quick-scan summary
- ✅ Phrasing includes relative position + approximate proximity

### Accessibility / Gestures (100% of the thesis gesture set)

- ✅ [`gesture_controller.dart`](../lib/services/gesture_controller.dart): two-finger double tap (start/stop), single tap (pause/resume), three-finger tap (scan), swipe down (repeat)
- ✅ [`gesture_surface.dart`](../lib/widgets/gesture_surface.dart): transparent capture layer over the viewport
- ✅ Haptic + TTS confirmation per gesture; visible high-contrast fallback controls (`AccessibleButton`)

### Settings Persistence (100%)

- ✅ [`settings_service.dart`](../lib/services/settings_service.dart): file-backed JSON via `path_provider`, injectable `SettingsStore` for tests, defaults on corrupt/missing file

### Spatial / Priority Interpretation (100% of the interface layer)

- ✅ [`spatial_analysis_service.dart`](../lib/services/spatial_analysis_service.dart) + [`detection_info.dart`](../lib/models/detection_info.dart): left/center/right (geometry), priority tiers (class-based), approximate proximity band (labeled heuristic — not a measured distance)
- ✅ Kept fully separate from the inference pipeline

### Telemetry & Reports (100% of the new dashboard)

- ✅ [`telemetry_service.dart`](../lib/services/telemetry_service.dart): session records, detection logs, latency/FPS samples, aggregates, per-minute frequency buckets
- ✅ [`charts.dart`](../lib/widgets/charts.dart): latency (300 ms line), FPS (15 FPS line), detection frequency
- ✅ Accuracy/Precision/Recall/F1/mAP explicitly **unavailable** (require ground truth) — never fabricated

### Haptics (100%)

- ✅ [`haptics_service.dart`](../lib/services/haptics_service.dart): dependency-free `HapticFeedback`, respects Vibration setting

### Tests (100% of the new tests)

- ✅ Navigation shell, screens, widgets, TTS, settings, spatial, telemetry, gesture controller — release baseline `flutter test` 59 passing, `flutter analyze` 0 issues (52 at v0.2.0 → 53 at v0.2.1 → 59 at v0.2.2)

### Notes

- The former developer single-screen UI (`camera_screen.dart`) was retired in v0.2.0 and **removed** during the Android-only platform cleanup; the current primary screen is [`detection_screen.dart`](../lib/screens/detection_screen.dart), while `info_panel.dart` / `debug_overlay.dart` remain but are unused by that UI.
- The ML pipeline (camera, YUV, orientation, TFLite, parser, NMS, thresholds, painter, forensics) was **not** modified.

## Completed Work

### Camera Pipeline (100%)

- ✅ Camera initialization with `ResolutionPreset.low` and YUV420 format
- ✅ Camera permission requesting via `permission_handler`
- ✅ `startImageStream()` delivering frames at native FPS
- ✅ Frame-dropping busy gate (`_isInferring` boolean)
- ✅ Camera preview widget rendering
- ✅ Resource cleanup (`dispose()` on camera and isolate)
- ✅ Structured debug logging: `[Camera]` prefix, frame counters, FPS estimation

### Inference Isolate (100%)

- ✅ Persistent `Isolate.spawn()` at app startup (not per-frame)
- ✅ Single `Interpreter.fromBuffer()` call (model loads once)
- ✅ **Runtime model introspection** — builds a `ModelMetadata` snapshot from runtime tensors + internal tensor scan
- ✅ Dynamic tensor shape querying (not hardcoded)
- ✅ Pre-allocated, dtype-matched input/output buffers; the orientation helper makes a temporary clone only when rotation or mirroring is required
- ✅ Raw `ByteBuffer` I/O to `interpreter.run()` — no reshape, no input-tensor resizing
- ✅ SendPort/ReceivePort communication protocol
- ✅ NHWC/NCHW automatic detection from shape
- ✅ Runtime layout-aware preprocessing and tensor rotation for both NHWC (interleaved) and NCHW (planar) inputs
- 🟡 Explicit XNNPACK attempt with retained delegate ownership and recoverable CPU fallback; initial short target-device evidence exists, while longer native stability remains unverified
- ✅ Structured debug logging: `[Model]`, `[Inference]`, `[Detection]`, `[Error]` prefixes
- ✅ Startup `MODEL INFORMATION` diagnostic banner in the isolate
- ✅ Inference latency timing via `Stopwatch` (reported per-frame)
- ✅ Error handling: try/catch around interpreter creation and frame loop
- ✅ Error propagation: isolate errors sent to main isolate via `{'type': 'error'}`
- ✅ Busy gate releases on isolate error (no permanent frame-drop wedge)

### Preprocessing (100%)

- ✅ Manual YUV420→RGB conversion (no `image` package dependency), writing either NHWC or NCHW layout from runtime metadata
- ✅ Nearest-neighbor resize to model input dimensions
- ✅ Dtype-matched writes driven by runtime metadata (normalized float, or quantized via input scale/zeroPoint)
- ✅ Support for FLOAT32/FLOAT64/FLOAT16/INT8/UINT8/INT16 model input types

### Post-Processing (100%)

- ✅ Argmax per-box (anchors × classes from runtime metadata)
- ✅ Dequantization driven by runtime metadata (only when the output tensor is quantized)
- ✅ Confidence threshold filtering (**0.25** — standard YOLOv8; lowered from 0.5, 2026-08-01)
- ✅ **Class-wise Non-Maximum Suppression (NMS)** — IoU 0.45; suppresses overlapping anchors per class (2026-08-01)
- ✅ Detection list construction (classId, confidence, bounding box)
- ✅ Pre-NMS candidate count exposed for `before NMS → after NMS` logging
- ✅ Per-detection debug logging (label, confidence, normalised box coords)

### Model Introspection (100%) — NEW

- ✅ [`ModelMetadata`](../lib/models/model_metadata.dart) — immutable runtime snapshot (name, I/O types, shapes, scale/zeroPoint, quantized flags, classes, anchors, model type)
- ✅ [`ModelType`](../lib/models/model_metadata.dart) classification: FP32 / Full INT8 Quantized / Full UINT8 Quantized / Weight-Quantized / Unknown — never guessed from filenames
- ✅ [`tflite_flatbuffer.dart`](../lib/models/tflite_flatbuffer.dart) — pure-Dart flatbuffer scanner for internal tensor precision (validated against the reference `tflite` Python package)
- ✅ Float16 (half-precision) byte conversion helpers for FLOAT16 I/O edge cases
- ✅ Metadata shipped to the main isolate via the `model_loaded` message
- ✅ Startup diagnostic logging (`MODEL INFORMATION` banner + `[Model]` summary)
- ✅ Debug overlay renders live model info (name, type, I/O types, shapes, classes, anchors, quantization, scale/zeroPoint)
- ✅ CLI validation tool: `dart run tool/validate_flatbuffer.dart`
- ✅ Fixed the `Float32List.reshape` `NoSuchMethodError` crash (raw `ByteBuffer` I/O)

### Model & Labels (100%)

- ✅ Model loading from the current metadata-enriched runtime artifact (`yolov8n_int8_new_metadata.tflite`), generated from `yolov8n_int8_new.tflite`; the v0.2.2 release baseline used `yolov8n.tflite`
- ✅ COCO label loading from `labels.txt` (80 classes)
- ✅ Label lookup by class index
- ✅ Model load success/failure logging with tensor metadata

### Orientation Architecture (100%) — NEW (2026-08-01)

- ✅ [`BoxTransform`](../lib/models/box_transform.dart) — single, device-independent source of truth for orientation math (`deviceDegreesFor` using the plugin's counter-clockwise convention, `displayRotationDegrees`, `uprightDims`, reversible `rotateRect`/`invertRect`, `mirrorRect`); no hardcoded angles
- ✅ Upright tensor inference — isolate rotates + optionally X-mirrors the 640×640 input to UPRIGHT before `interpreter.run()`; [`tensor_rotation.dart`](../lib/models/tensor_rotation.dart) handles both NHWC and NCHW while parser/NMS remain untouched
- ✅ Camera screen computes rotation from the same `controller.value.deviceOrientation` as `CameraPreview`; preview/painter sized with upright dims
- ✅ Painter simplified to a pure normalized→pixel mapper (no lens/mirror knowledge)
- ✅ Forensic `recordOrientation` + sensor/lens fields
- ✅ On-device: back portrait detections 0 → 0.91 maxConf; static-image regression byte-identical
- ⏳ Back landscape physical-hold re-validation + front-camera device runs pending

### Forensic File Logging (100%) — NEW (2026-08-01)

- ✅ [`ForensicLog`](../lib/services/forensic_log.dart) — structured file diagnostics under `<documents>/debug/run_*` (summary/camera/preprocess/tensor/output/parser/performance/errors.txt), synchronous flush-per-write, fully try/catch-isolated
- ✅ First-frame PNG dumps (`frame_original/rgb/resized/model_input.png`) via pure-Dart [`PngEncoder`](../lib/models/png_encoder.dart)
- ✅ Auto-generated `summary.txt` every 50 frames + on close (per-stage PASS/FAIL, ranked root causes)
- ✅ Console probes (`InferenceProbe`/`InputProbe`) disabled (`enabled=false`), call sites removed

### Camera Preview & UI (100%) — NEW (2026-08-01)

- ✅ Strict 3:4 portrait preview anchored to the top, feed contained via `BoxFit.contain` (never stretched/warped/cropped)
- ✅ Permanent bottom info panel ([`info_panel.dart`](../lib/widgets/info_panel.dart)) with exactly two tabs: Metrics + Detections
- ✅ Metrics tab: FPS, avg FPS, inference time, end-to-end latency, confidence stats, camera/preview/model input resolutions, aspect ratio, model name, backend, quantization, thread count
- ✅ Detections tab: chronological history (newest first), capped at 50, 1-second age timer
- ✅ Painter-vs-preview alignment via shared `applyBoxFit(BoxFit.contain)` math
- ✅ Aspect-correct preview via `FittedBox(fit: _previewFit)` + `SizedBox` sized to frame (contain/cover switch)

### Camera Preprocessing Repair (100%) — NEW (2026-08-01)

- ✅ `_convertYUV420toRGB` honors real per-plane `rowStride`/`bytesPerRow` + `pixelStride`/`bytesPerPixel`
- ✅ Planar I420 (pixelStride 1) and semi-planar NV12/NV21 (pixelStride 2, U-led) support
- ✅ Geometry-aware forensic `frame_rgb.png` sampling; 2-plane (semi-planar) deliveries handled
- ✅ Validated pixel-exact vs BT.601 reference on synthetic planar + semi-planar data

### Bounding Box Overlay (100%)

- ✅ `BoundingBoxPainter` CustomPainter with coordinate transformation
- ✅ Front-camera horizontal mirroring
- ✅ Label pills with confidence percentages
- ✅ Shadow rendering for visibility on bright backgrounds
- ✅ Colour palette cycling per class
- ✅ Structured debug logging: `[Painter]` prefix, screen dims, scale factor, rendered coords

### Debug Instrumentation (100%) — NEW

- ✅ Structured debug logging with consistent prefixes throughout the pipeline:
  - `[Service]` — InferenceService lifecycle (init, handshake, dispose)
  - `[Model]` — Model loading, tensor shapes/types, interpreter creation
  - `[Camera]` — Permission, initialization, resolution, format, frames received/dropped
  - `[Inference]` — Per-frame latency, input/output tensor shapes
  - `[Detection]` — Per-frame detection count, per-object label/confidence/box
  - `[Painter]` — Box count, screen dimensions, scale factor, rendered coordinates
  - `[Performance]` — 5-second summaries: camera FPS, inference FPS, avg/min/max latency, frame stats
  - `[Error]` — Model load failures, interpreter exceptions, isolate errors with stack traces
- ✅ Visual debug overlay ([`DebugOverlay`](../lib/widgets/debug_overlay.dart) widget, debug builds only via `kDebugMode`)
  - Camera FPS, inference FPS, latency, frame number, dropped frames
  - Detection count, last detected object, confidence
  - Camera resolution, lens direction, image format
- ✅ All `print()` calls replaced with `debugPrint()` (throttled in release)
- ✅ Log throttling: camera frames every 30th, painter every 30th, detections every frame
- ✅ Message protocol extended: `{'type': 'result'/'error'/'model_loaded'}` with metadata
- ✅ Inference latency exposed via `InferenceService.lastLatencyMs` getter

### Documentation (current set synchronized through 2026-09-05)

- ✅ Comprehensive project audit ([`auditor.md`](../auditor.md))
- ✅ Historical specification preserved ([`chat_spec.md`](../chat_spec.md))
- ✅ Architecture documentation ([`docs/architecture.md`](architecture.md))
- ✅ Implementation plan ([`docs/implementation-plan.md`](implementation-plan.md))
- ✅ Implementation decisions log ([`docs/implementation-decisions.md`](implementation-decisions.md))
- ✅ Project status ([`docs/project-status.md`](project-status.md))
- ✅ Known issues tracker ([`docs/known-issues.md`](known-issues.md))
- ✅ Development workflow guide ([`docs/development-workflow.md`](development-workflow.md))
- ✅ Testing plan ([`docs/testing-plan.md`](testing-plan.md))
- ✅ Benchmark results template ([`docs/benchmark-results.md`](benchmark-results.md))
- ✅ Formal README ([`README.md`](../README.md)) — project overview + documentation index
- ✅ Session log ([`docs/session-log.md`](session-log.md)) — all sessions through the app-only lifecycle validation recorded
- ✅ Changelog ([`docs/changelog.md`](changelog.md)) — v0.1.0 through v0.1.7 entries
- ✅ Camera-path forensics ([`docs/camera-path-forensics.md`](camera-path-forensics.md)) — input-side defect isolated & fixed (rotation)
- ✅ Orientation design review ([`docs/orientation-design-review.md`](orientation-design-review.md)) + implementation summary ([`docs/orientation-implementation.md`](orientation-implementation.md))
- ✅ Painter↔preview coordinate review ([`docs/painter-coordinate-review.md`](painter-coordinate-review.md))
- ✅ Static-image test report ([`docs/static-image-test.md`](static-image-test.md))
- ✅ Input pipeline investigation ([`docs/input-pipeline-investigation.md`](input-pipeline-investigation.md))
- ✅ Inference tensor diagnosis ([`docs/inference-tensor-diagnosis.md`](inference-tensor-diagnosis.md))

## Current Work

**Unreleased NCHW/XNNPACK candidate validation** — Active

| Task | Status |
|------|--------|
| Exact debug APK installation after storage cleanup | ✅ Successful on `2201116SG` (Android 13/API 33, arm64) |
| Runtime startup metadata and explicit delegate setup | ✅ Candidate metadata confirmed; XNNPACK interpreter created with four threads |
| Short live inference run | ✅ 65 completed frames, all logged `backend=XNNPACK`; no fatal marker observed |
| Formal performance, accuracy, thermal, memory, and long-duration stability validation | ⏳ Pending |

**Orientation re-validation** — Active

| Task | Status |
|------|--------|
| Back · portrait on-device | ✅ Done (maxConf 0.91, was 0) |
| Static-image regression (rot=0) | ✅ Done (byte-identical) |
| Back · landscape physical hold | 🟡 Convention bug fixed; physical-hold re-validation deferred |
| Front · portrait / landscape | 🟡 Math implemented; device run pending |

**Milestone 1: "Audible MVP"** — Complete (v0.2.0)

| Task | Status |
|------|--------|
| TTS audio feedback | ✅ Complete (v0.2.0) |
| Bounding box `CustomPainter` | ✅ Complete (2026-07-22) |
| Error handling in isolate | ✅ Complete — typed errors, explicit worker-exit handling, generation-safe bounded recovery, and terminal failure state |
| Permission-denied UI | ✅ Complete (v0.2.0 — camera-denied state with retry/open-settings) |
| Remove/wire unused dependencies | ✅ Mostly complete — `flutter_tts`/`path_provider`/`fl_chart` wired; `flutter_riverpod` retained (deliberately unused) |
| Debug instrumentation & logging | ✅ Complete (2026-07-22) |
| Forensic file logging | ✅ Complete (2026-08-01, v0.1.3) |
| Camera preprocessing repair | ✅ Complete (2026-08-01, v0.1.4) |
| Aspect-correct preview | ✅ Complete (2026-08-01, v0.1.5) |
| Camera preview UI redesign | ✅ Complete (2026-08-01, v0.1.6) |
| Device-independent orientation | ✅ Complete (2026-08-01, v0.1.7) |
| NMS (class-wise, IoU 0.45) + conf threshold 0.25 | ✅ Complete (2026-08-01) |

## Next Tasks (Priority Order)

0. **Re-validate orientation on-device** — back landscape physical hold + front camera portrait/landscape (see [`docs/orientation-implementation.md`](orientation-implementation.md)).
1. ~~**Implement TTS audio feedback**~~ — ✅ Done (v0.2.0). See [`lib/services/tts_service.dart`](../lib/services/tts_service.dart).
2. ~~**Implement bounding box `CustomPainter`**~~ — ✅ Done. See [`lib/widgets/bounding_box_painter.dart`](../lib/widgets/bounding_box_painter.dart).
3. ~~**Add debug instrumentation**~~ — ✅ Done. See [`lib/widgets/debug_overlay.dart`](../lib/widgets/debug_overlay.dart), [`lib/services/inference_isolate.dart`](../lib/services/inference_isolate.dart), [`lib/screens/detection_screen.dart`](../lib/screens/detection_screen.dart), [`lib/widgets/bounding_box_painter.dart`](../lib/widgets/bounding_box_painter.dart).
4. ~~**Implement NMS**~~ — ✅ Done (2026-08-01). Class-wise, IoU 0.45, pre-NMS conf 0.25. See [`_parseYolov8Output`](../lib/services/inference_isolate.dart).
5. **On-device validation of the v0.2.x UI** — gestures, TTS, mute toggle, settings persistence, Logs & Reports charts on the Snapdragon 695 device.
6. ~~**Complete error handling in inference isolate**~~ — ✅ Done for the app-only scope: typed errors and bounded generation-safe worker recovery.
7. ~~**Add permission-denied UI**~~ — ✅ Done (v0.2.0). See [`detection_screen.dart`](../lib/screens/detection_screen.dart).
8. **Extend validation of the unreleased XNNPACK candidate** — capture longer stability/fallback evidence and run the benchmark tool on the test device; the exact APK has already installed and completed an initial short live run.

## Remaining Tasks

See [`implementation-plan.md`](implementation-plan.md) for the full milestone breakdown.

### By Milestone:

- **Milestone 1 (Audible MVP):** ✅ Complete (v0.2.0); bounded isolate restart recovery now implemented in the unreleased app-only candidate
- **Milestone 2 (Research-Ready):** mostly done — on-device UI validation, formal FPS/latency benchmark, adaptive throttling polish, and controlled engine comparison remain
- **Milestone 3 (Defense-Ready):** gestures + priority TTS queue + TalkBack semantics + accessibility tests done; adaptive throttling, extended XNNPACK/NNAPI delegate validation, package rename (`com.eyecue`), and explicit minSdk remain
- **Milestone 4 (Production Candidate):** bounded isolate recovery, model variant selection, metadata safety, export foundation, and broad test coverage done; `TransferableTypedData`, bilinear resize, release signing, full device matrix, and Play Store readiness remain

**Total Estimated Effort (remaining):** ~40–70 hours (down from ~60–104)

## Estimated Completion

| Milestone | Target |
|-----------|--------|
| M1: Audible MVP | ~2 weeks |
| M2: Research-Ready | ~4 weeks |
| M3: Defense-Ready | ~6 weeks |
| M4: Production Candidate | ~8 weeks |

## Verification Log (2026-07-22)

> **Historical note:** This log records the static/code-review verification state from
> 2026-07-22. It predates the later v0.2.x UI work and the 2026-09-01 candidate
> device retry. The current candidate status is recorded in the sections above;
> the checklist below is retained as a dated audit trail.

### Debug Instrumentation Verification

The following checklist was verified via code review and static analysis (`flutter analyze` — 0 issues):

| Check | Status | Evidence |
|-------|--------|----------|
| Camera initializes | ✅ | `[Camera]` logs at init, permission, stream start |
| Frames received | ✅ | `[Camera]` per-30-frame log with resolution/format |
| Model loads | ✅ | `[Model]` logs with tensor shapes, `type:'model_loaded'` confirm |
| Interpreter runs | ✅ | `[Inference]` per-frame latency (Stopwatch measured) |
| Inference completes | ✅ | `type:'result'` message with detections + latencyMs |
| Detections produced | ✅ | `[Detection]` per-frame count + per-object details |
| Bounding boxes rendered | ✅ | `[Painter]` per-30-paint box count, screen dims, scale |
| Labels displayed | ✅ | Painter draws label pills with confidence % (existing) |
| Confidence displayed | ✅ | Painter shows `label XX%` format (existing) |
| Overlay aligned | ✅ | Coordinate transform logged: norm→screen with scale factor |
| No crashes | ⚠️ Static | Requires on-device testing; try/catch added around critical paths |
| No memory leaks observed | ⚠️ Static | Requires on-device profiling; pre-allocated buffers unchanged |
| Debug overlay visible | ✅ | `DebugOverlay` widget, `kDebugMode` guard, positioned top-left |
| Performance logging | ✅ | `[Performance]` 5-second summaries with FPS/latency/frame stats |
| Error logging active | ✅ | `[Error]` try/catch in model load, interpreter creation, frame loop |
| Message protocol intact | ✅ | Backward-compatible: `type:'result'/'error'/'model_loaded'` |

### Issues Discovered During Instrumentation

1. **No `imageFormatGroup` on `CameraValue`** — The `camera` package's `CameraValue` class does not expose the configured image format group. Workaround: store the statically-configured format string (`'yuv420'`) during controller creation.

2. **Interpreter type narrowed to nullable** — Adding try/catch around `Interpreter.fromBuffer()` forced the interpreter variable to `Interpreter?`. Fixed with `!` null-assert on `interpreter.run()` since the function returns early on failure.

3. **Static method accessing local variables** — `_logDetections()` originally referenced `modelH`/`modelW` which are local to `_isolateEntryPoint()`. Fixed by passing them as parameters.

### Recommended Next Verification Steps

1. Deploy to physical Android device (Snapdragon 695) and observe logcat output
2. Verify `[Performance]` summaries appear every 5 seconds
3. Confirm debug overlay renders in top-left corner of camera preview
4. Check that inference latency is consistent with known CPU-only baseline (~30 ms)
5. Verify error propagation by temporarily introducing a fault
6. Run Android Studio Memory Profiler to check for leaks over a 5-minute session
