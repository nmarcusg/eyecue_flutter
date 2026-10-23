# EyeCue — Changelog

> Human-readable summary of changes per version. Not a Git log.  
> See [`implementation-progress.md`](implementation-progress.md) for detailed task tracking.

---

## Unreleased — Configurable inference cadence (2026-10-23)

### Added
- Persisted **Inference Cadence** settings: detector target Automatic (default)
  or 1–30 Hz, and depth target 2–10 Hz (default 2 Hz). Settings schema `4 → 5`.
- Pure [`InferenceCadence.resolve`](../lib/services/inference_cadence.dart)
  policy: low power caps detection at 4 Hz and depth at 2 Hz, a numeric detector
  rate also caps depth (source-limited), and bounding-box distance mode disables
  depth work.
- Detector cadence is applied through `YOLOStreamingConfig.inferenceFrequency`
  and re-applied live with `setStreamingConfig`; depth cadence re-arms the single
  latest-frame scheduler without queueing.
- Telemetry schema **3** adds per-sample cadence fields (requested/effective
  rates, automatic flag, low-power and source-limit flags, observed depth
  cadence and latency), carried through the manual Supabase upload; no migration
  is needed.
- `INTERNET` is declared in the main manifest for that optional manual upload
  only. Both detection and depth models remain bundled; nothing is downloaded.

### Verified
- `flutter analyze --no-pub`: 4 pre-existing issues; `flutter test --no-pub`:
  527 passing, 1 pre-existing `tts_service_test` failure. No build, device or
  performance measurement was run, so no cadence/FPS figure is claimed.

---

## 2026-10-22 — MDE depth model bundled

> **Later change (2026-10-23):** the main manifest now also declares `INTERNET`,
> but only for the optional manual telemetry upload. The depth model remains
> bundled and no model is downloaded.

### Fixed
- Depth could not run in a release build. The estimator passed the official
  `yolo26n-depth` id, so the plugin downloaded the model on first use, but
  release manifests declare only `CAMERA` (`INTERNET` exists only in the
  debug/profile manifests). The load always failed, the estimator degraded, and
  the screen showed the degraded banner while detection kept working.
- `yolo26n-depth_w8a32.tflite` is now a bundled asset
  ([`assets/yolo26n-depth_w8a32.tflite`](../assets/yolo26n-depth_w8a32.tflite)),
  loaded through the same asset path detection already uses. MDE is fully
  offline and needs no `INTERNET` permission.

### Added
- One-shot `[Depth]` diagnostics: the requested model path and `useGpu` before
  loading, the error string on load failure, and the first frame's map size,
  depth range, elapsed milliseconds and accelerator choice.

### Verified
- Static only: `dart format`, `flutter analyze`, `flutter test` and
  `flutter build apk --release`. **No device run** — the heatmap, metric
  distances and on-device latency remain unverified.

---

## 2026-10-21 — Monocular depth estimation; single engine

### Added
- Optional metric distance from the official `yolo26n-depth` model, run as a
  second `ultralytics_yolo` instance on the streamed analysis JPEG; see
  [`mde-integration.md`](mde-integration.md).
- `DistanceEstimationMode` (`monocularDepth` default, `boundingBoxApproximation`)
  plus independent `showBoundingBoxes` / `showDepthHeatmap` preferences and the
  Settings "Distance & Overlays" card; settings schema `3 → 4`.
- Pure depth helpers ([`depth_distance_service.dart`](../lib/services/depth_distance_service.dart)),
  the scheduler/estimator ([`monocular_depth_estimator.dart`](../lib/services/monocular_depth_estimator.dart)),
  and the rotated centre-crop heatmap widget
  ([`depth_heatmap_view.dart`](../lib/widgets/depth_heatmap_view.dart)).
- Metric distance on `DetectionInfo` (`estimatedMeters`, `distanceSource`,
  `distanceLabel`) mapped onto the existing proximity bands; speech says
  "about N m" when a metric estimate exists.
- Non-blocking degraded path (model load failure, offline, stale map, geometry
  change, GPU failure after one CPU retry) with a banner and retry.

### Removed
- The Custom EyeCue engine and its Dart/TFLite runtime, `tflite_flutter`, the
  Gradle classic-LiteRT native-library workaround, the `yolov8n` base/INT8
  assets, the forensic tooling, and the two-engine coordinator fallback APIs.
- `InferenceEngine.custom`; a persisted legacy value now loads as
  `ultralytics`.

### Verified
- `dart format` clean; `flutter analyze` shows only 4 pre-existing issues;
  `flutter test` **452 passing, 1 pre-existing failure** (the
  2026-10-21 revision total); `flutter build apk --release` succeeds (82.9 MB,
  no `libtensorflowlite_jni.so` in the APK).
- **No device run.** Depth accuracy, on-device latency/FPS, thermal behaviour
  and the manual matrix in [`mde-integration.md`](mde-integration.md) remain
  unverified.

---

## Unreleased — Waste-Reduction Cleanup (WS4, 2026-10-19)

### Changed
- `28ffa9c` — removed the static-image diagnostic chain: service/screen branch, decoder-only API, `InputProbe.rgbaToI420`, `pubspec.yaml` declaration, and `assets/test_image.jpg`.
- `6188974` — deleted verified zero-fan-in probes, debug overlay, info panel, compatibility export wrappers, and unused model/theme declarations.
- `a466077` — removed the unused `flutter_riverpod` dependency; the tool-regenerated lockfile also normalized ten documented toolchain-forced downgrades under Flutter 3.44.2. This is not a dependency upgrade and no build was validated.
- `1516dfe` — stopped bundling `assets/yolov8n_int8_new.tflite` and `assets/yolov8n.tflite`; both remain tracked for tools, tests, and history.
- `7e89461` — C5 changed the existing forensic master switch to `!kReleaseMode`, so forensic file logging is now release-disabled. Debug/profile diagnostics remain, and some eager forensic CPU work still runs before the gated writes.
- Current documentation and stale source comments were reconciled, and historical investigations now carry retirement/current-status notices instead of rewritten evidence.

### Verified
- **Static only.** WS4 commits were checked with focused reference searches, exact diff/boundary checks, `git diff --check`, clean status, and preserved-ref/lock checks.
- No tests, analyzer, dependency resolution (beyond the authorized C3 regeneration), Gradle/build, APK/bundle inspection, emulator/device, or benchmark run was performed. No speed, storage, privacy, or release-readiness improvement is claimed.

---

## Unreleased — Alert-Latency Telemetry (Workstream 2)

> **Later changes:** the Custom engine was removed on 2026-10-21, so only the
> four Ultralytics summaries carry samples; the export schema is now **3** after
> the cadence telemetry, and the suite has since run (527 passing, 1 known
> pre-existing failure).

### Added
- Bounded alert-lifecycle telemetry in [`alert_lifecycle.dart`](../lib/models/alert_lifecycle.dart) and [`telemetry_service.dart`](../lib/services/telemetry_service.dart): one event-delta record per terminal TTS submission (capped at 500) plus a replace-only cumulative scheduler-counter snapshot.
- Custom frame anchors (analysis received, worker inference start/completion, result receipt, detection accepted) correlated through the shared assistive controller and TTS request. Ultralytics records only result receipt and later app-side anchors; pre-result fields stay null.
- Eight detection-origin alert-latency summaries — four intervals per engine — using nearest-rank p50/p95/max/count, with null or negative endpoints excluded and zero-duration samples retained.
- Additive schema-v2 export in [`telemetry_export.dart`](../lib/models/telemetry_export.dart) and [`telemetry_export_service.dart`](../lib/services/telemetry_export_service.dart): `alertLifecycle`, `alertCounters`, and `alertSummaries` JSON payloads plus `alert_lifecycle`, `alert_counter`, and `alert_summary` CSV rows. Schema-v1 input still parses with empty alert collections.
- Logs & Reports Overview section `Alert latency and scheduler health` showing every interval and scheduler counter, with `No samples` for empty distributions.

### Verified
- **Static only.** Owning tests were written but not executed; `flutter analyze`, the test suite, Gradle, builds, and emulator/device runs were not performed.
- Physical audible-warning latency remains unmeasured. The Ultralytics interval is `app-side / post-inference`, not full inference or end-to-end latency, and no performance, safety, or release-readiness claim is made.

---

## Unreleased — Lifecycle-Aware TTS Safety Arbitration (Workstream 1)

### Changed
- Replaced the fire-and-forget TTS path with a serialized scheduler in [`tts_service.dart`](../lib/services/tts_service.dart): exactly one utterance in flight and exactly one pending request (higher priority replaces lower; newest replaces oldest at equal priority).
- Accepted-alert history, cooldowns, and repeat-last state are now committed **only from a confirmed `onStart`**. A decision that is rejected, dropped, or cancelled before speech begins arms nothing.
- Completion, cancellation, drop and failure are distinct terminal states reconciled from paired platform signals (`onComplete` + result `1`, `onCancel` + result `0`). Missing signals enter a bounded recovery with a restartable quiet-period quarantine.
- Label-only suppression was replaced by track-aware identity in the new [`alert_policy.dart`](../lib/services/alert_policy.dart). A different person (different track ID) is independently eligible even when the `person` label was announced moments earlier.
- Escalation re-alerts within the ordinary same-object window on risk increase, `stable/unknown → approaching`, proximity-band increase, centre-corridor entry, or smoothed-box growth. Parked decisions are revalidated semantically (TTL-aware) before speaking.
- Added controlled preemption: imminent safety alerts outrank lower priorities, and a distinct suddenly-approaching track may preempt an equal-priority, non-approaching active warning. Both preserve a preemption cooldown and the serialized stop/cancel/reconcile path.
- Wayfinding (destination/boundary phrases) now runs through the serialized scheduler: accepted only while idle, never queued behind Detection speech, never replacing Detection repeat-last state, with anti-repeat history committed only on confirmed `onStart`.
- Widget-test fake engines now install lifecycle handlers, emit start before completion, and are disposed after each test.

### Verified
- **Static checks only.** `dart format` and `git diff --check` are clean; no conflict markers or unmerged paths remain.
- `flutter analyze`, the full test suite, Gradle, and builds were **not** run after relocating this work onto `origin/dev`. Test totals from earlier revisions are historical, not current verification.

---

## Unreleased — Presentation-Only Visual Redesign Closeout (2026-09-29)

### Changed
- Completed the presentation-only redesign across the retained four-tab shell and its Home, Settings, Help, Logs & Reports, and Detection surfaces. Home now has a fixed, non-scrollable normal composition with an enlarged fixed decorative logo; the light/Home-theme bottom bar retains its Home / Detect / Settings / Help order, callbacks, selection, cached pages, and visibility behavior.
- Refined Settings typography and leading-edge alignment; removed decorative icons; retained active cyan controls; clarified the Engine & Sensitivity hierarchy with indented sensitivity sub-options; preserved the dark System Performance card's truthful values; and restyled the `View Logs & Reports` entry without changing its callback.
- Refined Help's icon-free cards and app-bar title styling, and applied the same fixed light app-bar/body surface treatment to the scrolling Settings, Help, and Logs & Reports routes.
- Updated both Detection presentations with higher-contrast `Detection Mode` title treatment, a bottom edge-inset overlay with left-aligned information rows, and two mockup-inspired action cards with state icons and left-aligned content. Lifecycle mappings, action callbacks, hold/tap timing, Quick Scan gating, gestures, and accessibility semantics are unchanged.

### Added
- Added [`kHomeOverlayWhite11`](../lib/theme/app_colors.dart:146), the semantic 11%-white overlay token used only for the `View Logs & Reports` action surface in Settings.

### Verified
- `flutter analyze`: **0 issues**.
- `flutter test`: **343 passing, 0 failing**.
- Physical Android visual checks were explicitly confirmed by the user for this completed redesign. The confirmed scope includes the fixed Home layout/logo; retained four-tab navigation presentation; Settings, Help, and Logs & Reports light surfaces; Settings control hierarchy and truthful System Performance presentation; Detection title, overlay, and two-card controls. No visual requirements remain outstanding for this redesign.

---

## Unreleased — Detection Redesign (PD1–PD3) (2026-09-28)

### Added
- Added the shared presentation widget [`detection_action_controls.dart`](../lib/widgets/detection_action_controls.dart) (`DetectionActionControls`): one coordinator-driven consolidated lifecycle control plus a physical Quick Scan control, rendered side-by-side in a single non-scrolling row. It owns local physical-pointer hold tracking and horizontal progress from 0% at pointer down through the full three-second hold, and imports no camera/inference/native/service internals.
- Added the shared presentation widget [`detection_information_overlay.dart`](../lib/widgets/detection_information_overlay.dart) (`DetectionInformationOverlay`): a compact in-viewport informational overlay of at most two rows, with stable High-priority promotion preserving source order, no confidence/debug/metric values, a dark translucent container using the existing overlay token, cyan/neutral normal and amber high-priority treatment, no animations, one manual non-live informational semantics node per row, and pointer transparency.

### Changed
- Implemented the locked PD1–PD3 Detection redesign per [`detection-redesign-plan.md`](frontend-workflow/detection-redesign-plan.md) in both engine screens — [`detection_screen.dart`](../lib/screens/detection_screen.dart) (Custom) and [`ultralytics_detection_screen.dart`](../lib/screens/ultralytics_detection_screen.dart) (Ultralytics).
- **PD1 (unified composition):** the dominant flexible camera viewport is retained; the top area keeps `Detection Mode`, the coordinator-derived status pill, and the Audio pill; exactly two side-by-side physical controls sit in one row beneath the viewport; and the normal screen no longer scrolls vertically. Removed from the normal UI: the detection card list, empty-state messages, `_GestureHint`, the visual `WarningBanner`, standalone Start/Stop, standalone Pause/Resume, visible Repeat, the standalone correction button, and correction/report actions on detection items. Correction removal is UI-only — [`CorrectionService`](../lib/services/correction_service.dart), its persistence, and the correction sheet remain intact. Ultralytics developer metrics were removed from the normal UI while telemetry collection is retained. The stopped viewport shell and [`GestureSurface`](../lib/widgets/gesture_surface.dart) are retained (Custom already did this; Ultralytics now does too).
- **PD2 (consolidated lifecycle control):** one coordinator-driven control. Ready tap Pause / hold 3s Stop; Paused tap Resume / hold 3s Stop; Stopped tap no-op / hold 3s Start; Preparing and Unavailable disabled. Visible copy: `PAUSE` + `HOLD 3 SEC TO STOP`; `RESUME` + `HOLD 3 SEC TO STOP`; `START` + `HOLD 3 SEC`; `PREPARING`; `UNAVAILABLE`. Progress starts at 0% on pointer down and fills continuously over the full three seconds; `kLongPressTimeout` only flips the secondary copy to `KEEP HOLDING` without restarting progress; early release maps to tap; release after the timeout but before three seconds is an abandoned hold with no action; completion dispatches exactly once with a duplicate-dispatch lock; existing engine-owned completion TTS/haptics are reused without duplication. Quick Scan is tap-only, Ready/healthy-fallback only, and disabled during an active physical hold.
- **PD3 (compact overlay):** a compact in-viewport informational overlay, maximum two rows, stable High-priority promotion preserving source order, no confidence/debug/metric values, dark translucent container using the existing overlay token, cyan/neutral normal and amber high-priority accent, no animations, one manual non-live informational semantics node per row, hidden outside Ready/healthy fallback.

### Fixed (post-implementation, on-device)
- **Custom infinite-height layout cascade:** fixed by wrapping the shared control row in `IntrinsicHeight` in [`detection_screen.dart`](../lib/screens/detection_screen.dart) (mirroring the Ultralytics screen).
- **Custom `setState() or markNeedsBuild() called during build`:** fixed by deferring the one-shot start intent to a post-frame callback in [`detection_screen.dart`](../lib/screens/detection_screen.dart).
- **Ultralytics Stop → Start stuck in Preparing:** fixed by recreating the native session on start-after-stop (native-view epoch in the `YOLOView` key, an `_activeNativeEpoch` stale-`onModelLoad` guard, and a `_startInFlight` duplicate-start guard) in [`ultralytics_detection_screen.dart`](../lib/screens/ultralytics_detection_screen.dart). Native `stop()` permanently destroys the predictor and is not reversible by `start()`.

### Verified
- `flutter analyze`: 0 issues.
- `flutter test`: **323 passing**.
- Behavioral-deviation audit: no unintended deviations. Proven unchanged from baseline `f310e73`: `InferenceService`, [`inference_isolate.dart`](../lib/services/inference_isolate.dart), `_processCameraImage()`, model initialization, XNNPACK configuration, preprocessing, rotation, NMS, confidence thresholds, detection ordering, bounding-box coordinates, [`BoundingBoxPainter`](../lib/widgets/bounding_box_painter.dart), [`AssistiveDetectionController`](../lib/services/assistive_detection_controller.dart), [`DetectionInfo`](../lib/models/detection_info.dart), spatial analysis, telemetry service, haptics service, correction service, and the Ultralytics adapter/model configuration. Custom Pause keeping the preview live is pre-existing baseline behavior, not a regression.

### Non-Blocking Notes
- **Ultralytics Ready timing semantics:** Ready can publish before the native camera returns to `CAMERA_STATE_ACTIVE`; the current definition is model/native initialization readiness, not strict pipeline-operational proof.
- **Post-resume freshness diagnostic limitation:** the epoch diagnostic cannot isolate the first result after Resume.
- **FlutterJNI teardown fatal:** not reproduced in the latest capture and **not fixed** — dedicated full-app teardown verification is pending.
- **Ultralytics GPU path:** falls back to CPU/XNNPACK on this device/session (pre-existing, not redesign-introduced).
- **Native CameraX graph churn** during recreation is expected plugin settling, not a proven leak.
- **Deferred:** strict PD3 result provenance/freshness remains deferred under its existing scope boundary.

---

## Unreleased — Home/Detection Shared Lifecycle State (2026-09-28)

### Added
- Added a `stopped` runtime state to [`detection_runtime_state.dart`](../lib/models/detection_runtime_state.dart) so an explicit manual stop is distinguishable from `idle` (never started) and `disposed` (teardown). Every exhaustive state mapping (including [`detection_state_panel.dart`](../lib/widgets/detection_state_panel.dart) and [`status_pill.dart`](../lib/widgets/status_pill.dart)) handles the new state.
- Added start-intent / entry-start / stop APIs to [`engine_coordinator.dart`](../lib/services/engine_coordinator.dart): a monotonic one-shot start-intent token (silent launch origin versus user-entry origin) plus guarded transition APIs. The coordinator remains the single cross-engine `ChangeNotifier`; it does not own camera/controller instances.

### Changed
- Promoted [`EngineCoordinator`](../lib/services/engine_coordinator.dart) from a Detect-tab-local runtime observer to the single app-shell-owned, user-facing Detection lifecycle/status source. [`app_shell.dart`](../lib/navigation/app_shell.dart) now constructs exactly one coordinator for the shell lifetime and injects it into Home and [`engine_detection_screen.dart`](../lib/screens/engine_detection_screen.dart); the coordinator is no longer constructed/disposed inside `_EngineDetectionScreenState`.
- Home and both Detection implementations (Custom [`detection_screen.dart`](../lib/screens/detection_screen.dart) and Ultralytics [`ultralytics_detection_screen.dart`](../lib/screens/ultralytics_detection_screen.dart)) now render visible status (Preparing / Ready / Paused / Stopped / Unavailable) from the same coordinator snapshot via a shared mapping. Engine-local booleans remain only for camera/controller/inference mechanics and no longer select user-facing lifecycle/status content.
- **Auto-start ON:** app launch keeps Home visible while Detection initializes/starts in the background; the shared status moves Preparing → Ready/Unavailable; opening Detection later reuses the already-initialized cached instance without a second start.
- **Auto-start OFF:** Detection stays off at launch; a deliberate primary navigation into Detection starts it immediately without changing the persisted `autoStartDetection` preference.
- **Manual pause/stop is session-scoped:** leaving and re-entering Detection during the retained session does not auto-restart; an explicit resume/start is required. There is no cross-process persistence.
- Removed the Home `Go to Live Camera` CTA and its callback/import/layout gap without replacement. Home now shows coordinator-derived status and the finalized copy set (`Preparing` / `Ready` / `Paused` / `Stopped` / `Unavailable`).
- Preserved Home → Detect one-finger LEFT swipe, Detection-local gestures, TTS, haptics, accessibility semantics, cached-page behavior, Settings, system Back, and Logs & Reports.

### Verified
- `flutter analyze`: no issues.
- `flutter test`: all **247 tests passed**.

### Needs Verification
- Changing Auto-start while the app is already running is out of scope and has no defined behavior.
- Android background/foreground, process death, and camera pre-emption lifecycle behavior is out of scope and unverified.
- Offstage camera/native startup behavior on a physical device (Auto-start ON background preparation) is **Needs Verification** — it has not been observed end-to-end on a physical Android device.

---

## Unreleased — Primary Gesture Navigation (2026-09-28)

### Added
- Added a persisted `hideBottomNavigation` preference to [`app_settings.dart`](../lib/models/app_settings.dart) (default `false`, backward-compatible parse for older JSON) with a matching getter/setter on [`settings_service.dart`](../lib/services/settings_service.dart) and a labeled Preferences control in [`settings_screen.dart`](../lib/screens/settings_screen.dart). The control represents the persisted preference, not the effective accessibility override.
- Added one-finger linear, non-wrapping primary navigation in [`app_shell.dart`](../lib/navigation/app_shell.dart): a body-only, arena-aware horizontal drag layer moves linearly through Home → Detection → Settings → Help and does not modulo-wrap. A boundary attempt stays on the current tab and emits boundary feedback once.
- Added Detection directional arbitration in [`gesture_controller.dart`](../lib/services/gesture_controller.dart): the first committed directional intent for a one-pointer sequence is locked (horizontal commit prevents a later downward repeat and vice versa), a second pointer before commitment invalidates one-pointer directional classification, and pointer cancellation suppresses every delayed or directional action from that sequence. Existing single-tap, two-finger double-tap, three-finger-tap, and downward-repeat intents are unchanged.
- Added Detection-owned horizontal navigation: [`engine_detection_screen.dart`](../lib/screens/engine_detection_screen.dart) carries a stable relative-navigation callback to both [`detection_screen.dart`](../lib/screens/detection_screen.dart) and [`ultralytics_detection_screen.dart`](../lib/screens/ultralytics_detection_screen.dart), which forward horizontal intents while preserving the existing downward repeat mapping. The viewport-only [`gesture_surface.dart`](../lib/widgets/gesture_surface.dart) remains the only raw-pointer implementation.
- Added light/medium haptic wayfinding at the shell gesture-origin path only: [`lightTick`](../lib/services/haptics_service.dart) on successful relative navigation and [`mediumTick`](../lib/services/haptics_service.dart) on a committed boundary attempt; no haptic on insufficient drag or cancellation, and never `heavyTick` for routine navigation.
- Added a minimal best-effort, drop-if-busy wayfinding API to [`tts_service.dart`](../lib/services/tts_service.dart) for destination/boundary phrases. It is suppressed when audio is disabled or accessible-navigation mode is on, never interrupts or delays Detection speech, and preserves Detection replay state.

### Changed
- [`app_shell.dart`](../lib/navigation/app_shell.dart) now derives effective bottom-bar visibility from the persisted `hideBottomNavigation` preference plus `MediaQuery.accessibleNavigationOf`: the bar is forced visible whenever accessible-navigation mode is active, and the accessibility override is never written back to the persisted preference. When accessibility mode turns off, the persisted preference takes effect again.
- Gesture-origin wayfinding feedback is emitted only from the horizontal-drag navigation path; direct tab selection (`goToTab`), the Home CTA, and system Back remain feedback-free.
- Preserved system Back behavior: Back from a non-Home primary tab returns to Home, Back from Home follows the platform's normal route/exit behavior, and a pushed secondary route (Logs & Reports) receives Back first.
- Preserved Detection lifecycle: ordinary primary navigation does not dispose or recreate the cached Detection page, and no new remount path was added; engine selection, fallback/recovery, and active-engine restart retain their existing generation-key remount behavior.

### Verified
- `flutter analyze`: 0 issues.
- `flutter test`: passing, including new coverage for the settings preference, Detection directional arbitration, TTS wayfinding policy, shell gesture navigation, the accessibility/bar truth table, Slider ownership, route/Back isolation, and cached-page preservation.
- Physical-device testing surfaced three unresolved issues (see [`known-issues.md`](known-issues.md)): Detection long/fast swipe without releasing the finger triggers navigation; Detection horizontal navigation only triggers within the camera viewport; and a multi-pointer sequence on Home/Settings/Help (one finger held, second finger added, initial finger released) incorrectly triggers navigation. These are device-observed, unresolved, and pending a root-cause fix.

---

## Unreleased — Detection Screen Visual Redesign (2026-09-10)

### Changed
- Restyled the two Detection child screens — [`detection_screen.dart`](../lib/screens/detection_screen.dart) (Custom engine) and [`ultralytics_detection_screen.dart`](../lib/screens/ultralytics_detection_screen.dart) (Ultralytics engine) — as a visual-only change per [`detection-screen-plan.md`](detection-screen-plan.md). Both now scope the existing Home-local light theme [`buildHomeTheme()`](../lib/theme/app_home_theme.dart) to the Detection subtree with dark status-bar icons (`AnnotatedRegion<SystemUiOverlayStyle>`), and use the existing `kHome*`/`kSpace*`/`kRadius*` tokens as-is (no theme/token file change). The light chrome does not leak into Home, Help, Settings, Logs & Reports, or the shell navigation bar.
- The camera viewport is now a rounded dark card (`kHomeInk` `#0A0A0A`, `kRadius24`, clipped) sitting on the light chrome. The viewport stack (`FittedBox` → `CustomPaint(BoundingBoxPainter)` → `_GestureHint` → `GestureSurface`) and the `applyBoxFit` overlay math are unchanged; the Ultralytics `YOLOView` native overlay is unchanged. No `LIVE CAMERA` label was added.
- The header keeps the single `Detection Mode` title using the theme's `titleLarge` (non-bold `w600`, matching the Settings/Help `AppBar` title style) with the `StatusPill` retained as its own live-region element. The `StatusPill` and the `AUDIO ON` pill share one horizontal row, with the audio pill end-aligned right; the Ultralytics performance line and error text remain below that row.
- The circular audio `IconButton` was replaced by an inline `AUDIO ON` / `AUDIO OFF` pill (a private `_AudioPill` helper colocated in each screen file): `kHomeSurfaceCard` surface, `kRadius20`, `kHomeShadowSoft`, a `kSpace8` leading dot (`kHomeAccentCyan` on / `kHomeInkMuted` off), uppercase `labelMedium` label with `letterSpacing: 0.5`, `kSpace12`/`kSpace6` padding (matching `StatusPill`), and a ≥48dp touch target. The toggle behavior, tooltip text, enabled state, and `ListenableBuilder(listenable: Listenable.merge([_settings, _tts]))` are preserved; the pill exposes a semantic label/role/state ("Audio guidance, on/off").
- The controls panel now uses `kHomeSurfaceBase` with `kSpace12`/`kSpace8` padding; the five-button `Wrap` is preserved with `kSpace8` spacing/runSpacing and `prominent: true` applied to Pause/Resume and Scan only. The disabled Pause/Resume state and the conditional Correct button are preserved. The panel content is now wrapped in a `SingleChildScrollView` (with the detection list bounded to `maxHeight: 160` and still scrolling internally) so the fixed-height region can never overflow; the gesture-hint text color is now `kHomeInkMuted`.
- `_GestureHint` (both screens) now uses `kOverlayBlack`, `kRadius20`, and `kSpace14`/`kSpace8`/`kSpace10`; the white text, `Colors.white24` border, bottom-center position, and copy are preserved.
- Token-consistent restyle of the shared Detection widgets: [`status_pill.dart`](../lib/widgets/status_pill.dart) (`kStatus*` colors, `kRadius20`, `kSpace12`/`kSpace6`), [`warning_banner.dart`](../lib/widgets/warning_banner.dart) (`kWarningRed`, `kRadius12`, `kSpace16`/`kSpace14`/`kSpace12`), [`detection_card.dart`](../lib/widgets/detection_card.dart) (`kHomeSurfaceCard`, `kRadius12`, `kSpace4`/`kSpace12`/`kSpace14`, `kWarningRed` highlight border, `kHomeInkMuted` secondary text), [`priority_badge.dart`](../lib/widgets/priority_badge.dart) (`kWarningRed`/`kMediumAmber`/`kLowGreen`, `kOnAmberDark`, `kRadius6`, `kSpace14`/`kSpace10`/`kSpace8`/`kSpace4`), [`detection_state_panel.dart`](../lib/widgets/detection_state_panel.dart) (`kHomeSurfaceCard`, `kRadius24`, `kHomeShadowSoft`, `kSpace24`/`kSpace20`/`kSpace12`/`kSpace8`), and [`detection_correction_sheet.dart`](../lib/widgets/detection_correction_sheet.dart) (`kHomeSurfaceCard` via `Material`, `kHomeInk`/`kHomeInkMuted`, `kSpace20`/`kSpace12`/`kSpace16`/`kSpace8`).
- Restyled the [`engine_detection_screen.dart`](../lib/screens/engine_detection_screen.dart) temporary-fallback notice to the light surface (`kHomeSurfaceCard`, `kRadius12`, `kHomeInk`/`kHomeInkMuted`, `kSpace*` padding) for consistency with the light Detection chrome; `liveRegion: true` is preserved.
- The exact live-region split is preserved: `StatusPill`, `WarningBanner`, `DetectionStatePanel`, and the fallback notice remain live regions; `DetectionCard` remains **not** a live region.

### Added
- Added a `DetectionScreen` group to [`test/widget_test.dart`](../test/widget_test.dart) covering the plugin-free subtrees (title, `StatusPill`, all five controls, the `AUDIO ON` pill, and no overflow at default scale).
- Extended [`test/accessibility/semantics_test.dart`](../test/accessibility/semantics_test.dart) with the audio-pill enabled semantics, the `DetectionCard` non-live-region assertion, and a 200% text-scale no-overflow check.

### Fixed (post-implementation, on-device)
- **Controls-panel overflow:** the physical SM S9010 (Android 15/API 35) showed a `BOTTOM OVERFLOWED BY 74 PIXELS` banner on the Detection screen. The restyled fixed-height controls region could not fit the two-row five-button `Wrap` plus the gesture-hint text at the 200dp floor. The panel content is now wrapped in a `SingleChildScrollView` (detection list bounded to `maxHeight: 160`, still scrolling internally) so the region can never overflow; the `contentHeight` clamp floor was raised from `200.0` to `260.0` in both screens.
- **`AUDIO ON` pill padding:** the pill's horizontal padding was reduced from `kSpace16` to `kSpace12`/`kSpace6`, matching the `StatusPill` treatment.
- **Header alignment:** the `Detection Mode` title now uses the theme's `titleLarge` (non-bold `w600`) instead of the `w800` override, and the header top padding was raised to `kSpace16`, matching the Settings/Help `AppBar` title position. The `StatusPill` and `AUDIO ON` pill now share one horizontal row with the audio pill end-aligned right.

### Verified
- `flutter analyze`: 0 issues.
- `flutter test`: **185 passing**.
- `flutter build apk --debug`: succeeds; the debug APK installs on the physical SM S9010 (API 35) device.
- Physical-device verification (SM S9010, `R5CTA03XNZD`, Android 15/API 35): after the post-implementation fixes, the overflow banner is gone, no RenderFlex overflows/exceptions appear, the `AUDIO ON` pill padding matches the status pill, and the header title aligns with the Settings/Help headers.

---

## Unreleased — Logs & Reports Screen Visual Restyle (2026-09-10)

### Added
- Added a focused widget test file [`test/screens/logs_reports_screen_test.dart`](../test/screens/logs_reports_screen_test.dart) (25 tests) covering the real screen, route-local theme scope, all three tabs, exports, correction states, unavailable states, Logs priority semantics, and 200% text-scale no-overflow.

### Changed
- Restyled the existing pushed Logs & Reports route in [`logs_reports_screen.dart`](../lib/screens/logs_reports_screen.dart) as a visual-only change per [`logs-reports-screen-plan.md`](logs-reports-screen-plan.md). The route now scopes the existing Home-local light theme [`buildHomeTheme()`](../lib/theme/app_home_theme.dart) locally with dark status-bar icons (`AnnotatedRegion<SystemUiOverlayStyle>`), scoped to the pushed route only and not leaking into the shell navigation bar or other tabs.
- The route now uses a centered bounded secondary-screen layout (~480 logical px content bound, constraint-derived) with light surfaces/typography from the existing `kHome*`/`kSpace*`/`kRadius*` tokens as-is (no theme/token file change); spacing follows the 6/8/12/16/20/24 scale and existing radius roles.
- The Overview, Charts, and Logs tabs were restyled while preserving all telemetry/correction/export/chart bindings, truthful unavailable metrics, navigation, scrolling, and accessibility contracts. [`charts.dart`](../lib/widgets/charts.dart) was **not** modified.
- Fixed the Engine Comparison rows to render as a single horizontal row with the engine label visible on the left and the value right-aligned flush to the trailing edge (corrected an alignment issue, then a label-starvation regression).

### Verified
- `flutter analyze`: 0 issues.
- `flutter test`: **178 passing**.
- Physical-device visual QA of the restyled route remains pending.

---

## Unreleased — Settings Screen Visual Redesign (2026-09-10)

### Added
- Redesigned [`settings_screen.dart`](../lib/screens/settings_screen.dart) as a light, responsive composition that reuses the Home-local light theme [`buildHomeTheme()`](../lib/theme/app_home_theme.dart) and the existing `kHome*`/`kSpace*`/`kRadius*` tokens as-is (no theme/token file change). The light surface is scoped to the Settings subtree only and does not leak into the shell navigation bar or other tabs.
- Added an optional `TelemetryService? telemetry` parameter to `SettingsScreen`; when supplied, the System Performance card renders `Avg FPS`, `Avg latency (MS)`, and `Avg confidence`, showing `—` when the value is empty or null. No accuracy/precision/recall/F1/mAP/%ACC values are fabricated.
- Added a Settings semantics group to [`test/accessibility/semantics_test.dart`](../test/accessibility/semantics_test.dart) (8 tests).

### Changed
- [`settings_screen.dart`](../lib/screens/settings_screen.dart) is now a `StatelessWidget` that wraps the subtree in `Theme(buildHomeTheme())` with dark status-bar icons (`AnnotatedRegion<SystemUiOverlayStyle>`), then `Scaffold`/`AppBar('Settings')` → `ListenableBuilder` → `SafeArea` → `LayoutBuilder` → `Center` → `ConstrainedBox (~480)` → plain `ListView`. The four cards are ordered Preferences, Audio Guidance, Engine & Sensitivity, and System Performance (dark `kHomeInk` #0A0A0A).
- [`app_shell.dart`](../lib/navigation/app_shell.dart) now forwards `telemetry: widget.telemetry` into the `SettingsScreen` construction (single additive change).
- Extended the existing `SettingsScreen` group in [`test/widget_test.dart`](../test/widget_test.dart).

### Verified
- `flutter analyze`: 0 issues.
- `flutter test`: **153 passing**.
- `flutter build apk --debug`: succeeds.

---

## Unreleased — Help Screen Visual Redesign (2026-09-09)

### Added
- Redesigned [`help_screen.dart`](../lib/screens/help_screen.dart) as a light, responsive, accessible composition that reuses the Home-local light theme [`buildHomeTheme()`](../lib/theme/app_home_theme.dart) and the existing `kHome*`/`kSpace*`/`kRadius*` tokens as-is (no theme/token file change). The light surface is scoped to the Help subtree only and does not leak into the shell navigation bar or other tabs.
- Added a Help semantics group to [`test/accessibility/semantics_test.dart`](../test/accessibility/semantics_test.dart) covering the screen-title heading, the four section groups, decorative-icon exclusion, and 200% text-scale no-overflow.

### Changed
- [`help_screen.dart`](../lib/screens/help_screen.dart) now wraps the Help subtree in `Theme(buildHomeTheme())` with dark status-bar icons (`AnnotatedRegion<SystemUiOverlayStyle>`), matching the Home light surface. The retained `AppBar(title: 'Help & Gestures')` and the four sections and their copy are preserved verbatim.
- The four `_HelpCard` sections are now light cards on the light surface with `kRadius24` corners, `kHomeShadowSoft` shadows, token-based padding/separation, and the retained 28px section icons (decorative, excluded from semantics). The section title is the semantic heading for each group.
- The body is a responsive `SafeArea → LayoutBuilder → Center → ConstrainedBox (maxWidth ~480) → ListView` that scrolls at 200% text scale with no overflow.
- Extended the existing `HelpScreen` group in [`test/widget_test.dart`](../test/widget_test.dart) with the screen title, all four section titles, the four section icons, verbatim body copy, and a light-theme assertion.

### Verified
- `flutter analyze`: 0 issues.
- `flutter test`: **137 passing** (existing suite plus the extended Help widget and semantics tests).
- `flutter build apk --debug`: succeeds.
- On-device (physical Android): the light Help surface, card radius/shadow, large-text behavior, TalkBack semantics, and no RenderFlex overflows/exceptions were confirmed.

---

## Unreleased — Home Screen Visual Redesign (2026-09-09)

### Added
- Added the Home-local light theme [`app_home_theme.dart`](../lib/theme/app_home_theme.dart) (`buildHomeTheme()`), which supplies the light surface, ink, cyan accent, IBM Plex Sans typography, and Home shadow tokens to the Home subtree only. The global dark theme and shell navigation are unchanged.
- Added the `kHome*` light semantic color tokens to [`app_colors.dart`](../lib/theme/app_colors.dart) and the `kRadius3`/`kRadius14`/`kRadius18`/`kRadius24` radius tokens to [`app_radii.dart`](../lib/theme/app_radii.dart).
- Added `google_fonts` (^8.2.1) and bundled offline IBM Plex Sans fonts (Regular/Medium/SemiBold/Bold) under `assets/fonts/`; runtime font fetching is disabled in the Home theme builder.
- Registered `assets/logo.png` as an asset.

### Changed
- Redesigned [`home_screen.dart`](../lib/screens/home_screen.dart) as a light, responsive composition: a leading preference/status badge (`READY` / `AUTO-START OFF`), a centered decorative logo with a live `EyeCue` wordmark, and a lower instruction region with a truthful headline, supporting copy, the retained `Go to Live Camera` CTA, and a static decorative cyan rail. The layout fills the viewport when short and scrolls at large text scale.
- Replaced the old `_StatusCard` (which claimed "Detection is already running") with a preference-truthful `_StatusBadge` driven by `settings.autoStartDetection`. The Home subtree uses dark status-bar icons so the time/notifications remain visible on the light surface.
- Updated [`test/widget_test.dart`](../test/widget_test.dart) Home tests and added a Home semantics group to [`test/accessibility/semantics_test.dart`](../test/accessibility/semantics_test.dart); updated [`test/theme_test.dart`](../test/theme_test.dart) for the light Home text color.

### Verified
- `flutter analyze`: 0 issues.
- `flutter test`: **133 passing**.
- `flutter build apk --debug`: succeeds.
- On-device (SM-S9010, Android 15/API 35): Home renders with the light surface, spread layout, reduced logo/font sizes, and visible status bar; user confirmed visually.

---

## Unreleased — Frontend Workspace Scaffolding (2026-09-09)

### Added
- Added the `lib/theme/` design-token layer: [`app_colors.dart`](../lib/theme/app_colors.dart) (semantic color tokens), [`app_spacing.dart`](../lib/theme/app_spacing.dart) (spacing scale), [`app_radii.dart`](../lib/theme/app_radii.dart) (radius scale), [`app_typography.dart`](../lib/theme/app_typography.dart) (high-contrast `TextTheme` builder), and [`app_theme.dart`](../lib/theme/app_theme.dart) (`buildEyeCueTheme()`).
- Added `marionette_flutter` (^0.6.0), a debug-only runtime-inspection companion for the Marionette MCP server, initialized in [`main.dart`](../lib/main.dart) via `MarionetteBinding.ensureInitialized()` guarded by `kDebugMode`. It never runs in release builds.
- Added `design-reference/` at the repository root with `screens/` and `components/` subfolders as the destination for manually-exported Figma screenshots.
- Added the Figma-to-widget component inventory template (`.roo/rules/docs/component-inventory.md`) with one row per known screen/component and blank screenshot paths pending manual Figma export.
- Added seven frontend rule files under `.roo/rules/rules-frontend/` (scope boundary, naming convention, design tokens, accessibility, animation, doc-update, verification).
- Added [`docs/ui-conventions.md`](ui-conventions.md) codifying the naming, token, accessibility, animation, and verification conventions.

### Changed
- [`main.dart`](../lib/main.dart) now consumes `buildEyeCueTheme()` from [`app_theme.dart`](../lib/theme/app_theme.dart) instead of defining the theme inline; the inline `_buildTheme()` / `_highContrastTextTheme()` were moved into the token layer. No visual output changed.
- [`docs/architecture.md`](architecture.md) folder structure, component table, and External Dependencies table updated for the new `lib/theme/`, `design-reference/`, and `marionette_flutter`.

### Verified
- `flutter analyze`: 0 issues.
- `flutter test`: **127 passing** (theme regression test confirms `EyeCueApp` still renders the Home screen with the extracted theme).

### Notes
- Whether Marionette attaches to a physical Android device over the Dart VM Service remains **Needs Verification** — no physical device was connected during this scaffolding session.
- This is workspace scaffolding only; no placeholder screen was converted to a real implementation.

---

## Unreleased — App-Only Runtime Hardening (2026-09-05)

### Added
- Added [`inference_worker_lifecycle.dart`](../lib/services/inference_worker_lifecycle.dart), a pure injectable coordinator for Custom-worker generations, bounded recovery, explicit retry, terminal failure, healthy-budget reset, and disposal-safe backoff.
- Added explicit `reportWorkerExit` integration in [`inference_isolate.dart`](../lib/services/inference_isolate.dart), typed recovery telemetry/export records, metadata-packaging input safety, and accessibility coverage for runtime states, controls, detections, charts, warnings, and correction flows.
- Added seven deterministic lifecycle-orchestration tests covering respawn, stale-generation rejection, busy-gate release, delayed retry, terminal failure, disposal during backoff, and successful healthy recovery.

### Changed
- Custom worker recovery now performs one immediate retry, one delayed retry, then terminates cleanly; stale callbacks cannot restart a replaced or disposed worker, and the retry budget resets only after sustained healthy operation.
- Current repository validation is now **127 passing Flutter tests** with `flutter analyze` reporting 0 issues. The previous 77-test count remains in the historical 2026-09-01 entry below.

### Verified
- `flutter analyze`: 0 issues.
- `flutter test test/services/inference_lifecycle_test.dart`: 7 passing.
- `flutter test`: **127 passing**.
- `git diff --check`, FlatBuffer validation, and deterministic metadata packaging checks pass.

### Notes
- Android package identity, production signing, release AAB generation, and device smoke validation remain pending project-owner decisions, credentials, and device availability. No release identity or credential values were guessed.

---

## Unreleased — NCHW Model and Backend Candidate (2026-09-01)

### Added
- Added [`yolov8n_int8_new.tflite`](../assets/yolov8n_int8_new.tflite), a structurally validated YOLOv8n candidate with FLOAT32 runtime I/O, input shape `[1,3,640,640]` (NCHW), output shape `[1,84,8400]`, and internally quantized tensors.
- Added [`tensor_rotation.dart`](../lib/models/tensor_rotation.dart) with pure NHWC (interleaved) and NCHW (planar) square-tensor rotation/mirroring support, plus 14 focused unit tests.
- Added a persisted **Custom EyeCue / Ultralytics** selector in Settings. Custom retains the existing isolate/YUV/orientation/parser/NMS pipeline; Ultralytics uses `ultralytics_yolo` 0.6.13 for the native camera/inference path and maps results back into EyeCue's spatial, TTS, gesture, and telemetry layers.
- Added per-engine summaries to Logs & Reports and the controlled comparison protocol in [`dual-inference-engine-test.md`](dual-inference-engine-test.md).

### Changed
- [`inference_isolate.dart`](../lib/services/inference_isolate.dart) now selects input layout from runtime metadata, writes NCHW or NHWC preprocessing data, and attempts explicit XNNPACK for the candidate. The delegate is retained for the interpreter lifetime; recoverable setup/invocation failures retry on a four-thread CPU interpreter.
- [`validate_flatbuffer.dart`](../tool/validate_flatbuffer.dart) now validates the new model's verified tensor counts: 2 FLOAT32, 90 INT32, and 356 INT8 tensors.
- Model asset path, label asset path, confidence threshold, and IoU threshold now come from one shared configuration so the two modes use controlled inputs.
- Added a narrow Android packaging bridge for the two LiteRT generations: Ultralytics retains the LiteRT Next Java/runtime artifact, duplicate legacy Java/GPU artifacts are excluded, and only `tflite_flutter`'s classic 1.4.0 FFI library is extracted beside it. EyeCue's existing Custom `Interpreter` code is unchanged.

### Verified
- `flutter analyze`: 0 issues. `flutter test`: **77 passing**.
- The flatbuffer and PNG validators pass. `flutter build apk --debug` succeeds; APK inspection confirms the shared model/labels plus classic `libtensorflowlite_jni.so` and LiteRT Next `libLiteRt.so` for the packaged Android ABIs.
- After device storage was cleared, the exact debug APK installed on the API 33 Snapdragon 695 test phone (`2201116SG`). Startup confirmed the NCHW/FLOAT32 candidate and successful explicit XNNPACK interpreter creation. A short live run completed 65 XNNPACK-labelled frames with calculated mean latency 164.8 ms (median 157.7 ms; range 150.2–377.3 ms); app summaries reported approximately 5.7–6.2 inference FPS. A separate earlier observation returned one `tv` detection at 67.9% confidence and 113.7 ms. No candidate-process fatal signal was observed in the captured logs.
- After the first dual-engine replacement install was cancelled by Android with `INSTALL_FAILED_USER_RESTRICTED`, a retry installed the fixed build successfully. Both Custom and Ultralytics processed live camera frames on the target; Custom rendered labelled boxes and Ultralytics fed native results into EyeCue's labelled card/assistive layer.
- The first Custom→Ultralytics switch exposed a late-isolate-result race (`Cannot add new events after calling close`). Isolate disposal is now guarded and frame dispatch reports whether work was accepted, allowing the UI busy gate to release safely. Post-fix switches in both directions completed without recurrence in the captured Flutter logs.
- Short interactive readings suggested that Ultralytics may be faster on this device, but they were not controlled: momentary Ultralytics readings were about 6.1–9.6 FPS and 86.1–148.1 ms inference, while the final warm Custom run reported about 3.5–3.8 FPS and 261.0–289.4 ms average latency. No winner is claimed until the paired protocol is run.

### Notes
- This entry is intentionally unreleased. The stable v0.2.2 CPU/NHWC baseline and its informal 2.1 FPS / 606 ms observations remain the only release-baseline evidence; the candidate values are short app-telemetry observations, not formal benchmark results.
- The historical Snapdragon 695 XNNPACK SIGSEGV remains unresolved: native faults are not catchable by Dart, even though recoverable Dart-level failures now have a CPU fallback.
- The Ultralytics smoke test requested GPU with CPU fallback, but did not confirm the delegate actually used. Its native overlay also fell back to a numeric class label for the current model; EyeCue's adapted card resolved the correct COCO label from `labels.txt`.
- `ultralytics_yolo` 0.6.13 is AGPL-3.0; Play distribution requires compliance with its open-source terms or a suitable commercial licence. Flutter also emits a forward-compatibility warning for the legacy Kotlin plugin application used by `flutter_tts` and `ultralytics_yolo`.

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
