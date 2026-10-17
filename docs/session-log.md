# EyeCue — Session Log

> Append a new entry at the top of this file at the end of every development session.
> See [`development-workflow.md`](development-workflow.md) for the full workflow.

---

## 2026-10-17 — Workstream 1: TTS lifecycle arbitration

### Context
A device test produced an obstacle warning only after the user had already collided. Review traced this to speech scheduling, not to detection: history was committed before speech was attempted, suppression was label-based, and announcement decisions were not serialized.

### Changed
- Replaced the fire-and-forget TTS path with a serialized scheduler in [`tts_service.dart`](../lib/services/tts_service.dart): one in-flight utterance, one pending request, `Future<int>` results, start/completion/cancel/error handlers, `recover()`, bounded recovery with a restartable quiet period, and paired-signal terminal reconciliation.
- Added [`alert_policy.dart`](../lib/services/alert_policy.dart): track-preferred identity with label fallback, stable-object suppression, risk/motion/proximity/corridor/height escalation, read-only `decide()`, confirmed-`onStart` commits, TTL expiry, and semantic pending revalidation.
- Added controlled preemption: imminent safety outranks lower priorities; a distinct approaching track may preempt an equal-priority non-approaching warning; preemption cooldown and anti-churn are preserved.
- Integrated wayfinding through the scheduler: idle-only acceptance, never queued behind Detection, separate confirmed-start anti-repeat state, and Detection may interrupt it through serialized cancellation.
- Relocated the work onto `origin/dev` (`71693d4`) plus the WorkManager commit (`74d4649`); widget-test fake engines now install handlers, emit start before completion, and are disposed after each test.

### Verified
- **Static only:** `dart format` clean, `git diff --check` clean, no conflict markers, no unmerged paths.
- **Not verified:** no `flutter test`, `flutter analyze`, Gradle or build was run after relocation. Test totals recorded in earlier entries remain historical evidence, not current status.

### Known limitations
- `flutter_tts` lifecycle callbacks carry no utterance identifier; the quiet-period mitigation is bounded, so a very late native callback cannot be identified.
- Real Android callback ordering, cancellation timing and audible-warning latency are unmeasured.
- Scheduler work begins only after detection/tracking produces an alert decision; camera/inference/tracking latency still needs device measurement.
- EyeCue is not proven safe for independent navigation.

### Next Session
- Run `flutter analyze` and the full suite on `codex/tts-lifecycle-arbitration`, then review the single Workstream 1 commit.

---

## 2026-09-29 (25th session) — Presentation-Only Visual Redesign Closeout

### Objective
- Close out the confirmed presentation-only visual redesign in the authoritative documentation without changing application behavior, runtime logic, tests, assets, Android configuration, or other non-documentation files.

### Completed
- Recorded the completed fixed/non-scrollable Home layout with its enlarged fixed decorative logo, while retaining shared lifecycle status rendering and the shell-owned Home-left swipe.
- Recorded the retained four-tab light/Home-theme navigation presentation without changing destination order, selection, callbacks, visibility preference, accessibility override, cache, Back behavior, or gesture ownership.
- Recorded the completed Settings typography/alignment, decorative icon removal, cyan active controls, Engine & Sensitivity hierarchy/indentation, truthful System Performance presentation, and unchanged Logs entry values/callback.
- Recorded Help's icon-free card and app-bar title styling, plus the shared fixed light surface treatment for the scrolling Settings, Help, and Logs & Reports routes.
- Recorded the Detection title contrast, edge-inset left-aligned information overlay, and two state-icon, left-aligned action cards. Existing lifecycle mappings, gesture behavior, action callbacks, hold/tap timing, Quick Scan gate, and semantics remain unchanged.
- Recorded [`kHomeOverlayWhite11`](../lib/theme/app_colors.dart:146) as the semantic 11%-white Settings action-surface token.
- Updated the applicable root documentation and synchronized only the changed curated copies of [`architecture.md`](architecture.md) and [`testing-plan.md`](testing-plan.md).

### Verified
- `flutter analyze`: **0 issues**.
- `flutter test`: **343 passing, 0 failing**.
- The user explicitly confirmed physical Android visual checks for the full redesign scope. No visual requirements remain outstanding for this redesign.

### Remaining Needs Verification
- **Golden-test readiness [inferred-from-codebase]:** no approved golden-test harness, baselines, font-stable workflow, or device-pixel policy has been confirmed. This was not required for the confirmed physical-device visual closeout.
- Existing unrelated device/runtime follow-ups remain tracked separately in [`known-issues.md`](known-issues.md); this closeout does not resolve them.

---

## 2026-09-28 (24th session) — Detection Redesign (PD1–PD3)

### Objective
- Implement the locked PD1–PD3 Detection redesign per [`detection-redesign-plan.md`](frontend-workflow/detection-redesign-plan.md): a unified, engine-parity Detection composition (PD1), one coordinator-driven consolidated physical lifecycle control (PD2), and a compact current-information overlay (PD3), without merging the Custom and Ultralytics camera/inference internals or changing the app-shell lifecycle policy.

### Completed
- Implemented PD1–PD3 in both engine screens — [`detection_screen.dart`](../lib/screens/detection_screen.dart) (Custom) and [`ultralytics_detection_screen.dart`](../lib/screens/ultralytics_detection_screen.dart) (Ultralytics).
- **PD1:** dominant flexible camera viewport retained; top area keeps `Detection Mode`, the coordinator-derived status pill, and the Audio pill; exactly two side-by-side physical controls in one row beneath the viewport; no normal vertical scrolling. Removed from the normal UI: the detection card list, empty-state messages, `_GestureHint`, the visual `WarningBanner`, standalone Start/Stop, standalone Pause/Resume, visible Repeat, the standalone correction button, and correction/report actions on detection items. Correction removal is UI-only — [`CorrectionService`](../lib/services/correction_service.dart), its persistence, and the correction sheet remain intact. Ultralytics developer metrics were removed from the normal UI while telemetry collection is retained. The stopped viewport shell and [`GestureSurface`](../lib/widgets/gesture_surface.dart) are retained (Custom already did this; Ultralytics now does too).
- **PD2:** one coordinator-driven consolidated lifecycle control. Ready tap Pause / hold 3s Stop; Paused tap Resume / hold 3s Stop; Stopped tap no-op / hold 3s Start; Preparing and Unavailable disabled. Visible copy: `PAUSE` + `HOLD 3 SEC TO STOP`; `RESUME` + `HOLD 3 SEC TO STOP`; `START` + `HOLD 3 SEC`; `PREPARING`; `UNAVAILABLE`. Progress starts at 0% on pointer down and fills continuously over the full three seconds; `kLongPressTimeout` only flips the secondary copy to `KEEP HOLDING` without restarting progress; early release maps to tap; release after the timeout but before three seconds is an abandoned hold with no action; completion dispatches exactly once with a duplicate-dispatch lock; existing engine-owned completion TTS/haptics are reused without duplication. Quick Scan is tap-only, Ready/healthy-fallback only, and disabled during an active physical hold.
- **PD3:** compact in-viewport informational overlay, maximum two rows, stable High-priority promotion preserving source order, no confidence/debug/metric values, dark translucent container using the existing overlay token, cyan/neutral normal and amber high-priority accent, no animations, one manual non-live informational semantics node per row, hidden outside Ready/healthy fallback.
- Added the shared presentation widgets [`detection_action_controls.dart`](../lib/widgets/detection_action_controls.dart) (`DetectionActionControls`) and [`detection_information_overlay.dart`](../lib/widgets/detection_information_overlay.dart) (`DetectionInformationOverlay`).

### Runtime Repairs (post-implementation, on-device)
- **Custom infinite-height layout cascade:** fixed by wrapping the shared control row in `IntrinsicHeight` in [`detection_screen.dart`](../lib/screens/detection_screen.dart) (mirroring the Ultralytics screen).
- **Custom `setState() or markNeedsBuild() called during build`:** fixed by deferring the one-shot start intent to a post-frame callback in [`detection_screen.dart`](../lib/screens/detection_screen.dart).
- **Ultralytics Stop → Start stuck in Preparing:** fixed by recreating the native session on start-after-stop (native-view epoch in the `YOLOView` key, an `_activeNativeEpoch` stale-`onModelLoad` guard, and a `_startInFlight` duplicate-start guard) in [`ultralytics_detection_screen.dart`](../lib/screens/ultralytics_detection_screen.dart). Native `stop()` permanently destroys the predictor and is not reversible by `start()`.

### Behavioral-Deviation Audit
- Result: **no unintended deviations.** Proven unchanged from baseline `f310e73`: `InferenceService`, [`inference_isolate.dart`](../lib/services/inference_isolate.dart), `_processCameraImage()`, model initialization, XNNPACK configuration, preprocessing, rotation, NMS, confidence thresholds, detection ordering, bounding-box coordinates, [`BoundingBoxPainter`](../lib/widgets/bounding_box_painter.dart), [`AssistiveDetectionController`](../lib/services/assistive_detection_controller.dart), [`DetectionInfo`](../lib/models/detection_info.dart), spatial analysis, telemetry service, haptics service, correction service, and the Ultralytics adapter/model configuration. Custom Pause keeping the preview live is pre-existing baseline behavior, not a regression.

### Verified
- `flutter analyze`: 0 issues.
- `flutter test`: **323 passing**.

### Decisions / Limitations
- Strict PD3 result provenance/freshness remains deferred under its existing scope boundary (non-blocking for the redesign).
- Ultralytics Ready timing semantics: Ready can publish before the native camera returns to `CAMERA_STATE_ACTIVE`; the current definition is model/native initialization readiness, not strict pipeline-operational proof.
- Post-resume freshness diagnostic limitation: the epoch diagnostic cannot isolate the first result after Resume.
- FlutterJNI teardown fatal was not reproduced in the latest capture and is **not fixed** — dedicated full-app teardown verification is pending.
- Ultralytics GPU path falls back to CPU/XNNPACK on this device/session (pre-existing, not redesign-introduced).
- Native CameraX graph churn during recreation is expected plugin settling, not a proven leak.

### Next Session
- Complete dedicated full-app teardown verification for the FlutterJNI fatal, and continue the deferred strict PD3 provenance work under its existing scope boundary.

---

## 2026-09-28 (23rd session) — Home/Detection Shared Lifecycle State

### Objective
- Implement the finalized Home and Detection state behavior per [`home-detection-state-plan.md`](frontend-workflow/home-detection-state-plan.md): promote [`EngineCoordinator`](../lib/services/engine_coordinator.dart) to the single app-shell-owned, user-facing Detection lifecycle/status source shared by Home, Custom Detection, and Ultralytics Detection; add an explicit `stopped` state and a one-shot start-intent contract; remove the Home CTA; and make Auto-start control startup only.

### Completed
- Promoted [`EngineCoordinator`](../lib/services/engine_coordinator.dart) from a Detect-tab-local runtime observer to the single app-shell-owned, user-facing Detection lifecycle/status source. [`app_shell.dart`](../lib/navigation/app_shell.dart) now constructs exactly one coordinator for the shell lifetime and injects it into Home and [`engine_detection_screen.dart`](../lib/screens/engine_detection_screen.dart); the coordinator is no longer constructed/disposed inside `_EngineDetectionScreenState`.
- Home and both Detection implementations (Custom [`detection_screen.dart`](../lib/screens/detection_screen.dart) and Ultralytics [`ultralytics_detection_screen.dart`](../lib/screens/ultralytics_detection_screen.dart)) now render visible status (Preparing / Ready / Paused / Stopped / Unavailable) from the same coordinator snapshot via a shared mapping. Engine-local booleans remain only for camera/controller/inference mechanics and no longer select user-facing lifecycle/status content.
- Added a `stopped` runtime state to [`detection_runtime_state.dart`](../lib/models/detection_runtime_state.dart) so an explicit manual stop is distinguishable from `idle` (never started) and `disposed` (teardown); every exhaustive state mapping (including [`detection_state_panel.dart`](../lib/widgets/detection_state_panel.dart) and [`status_pill.dart`](../lib/widgets/status_pill.dart)) handles the new state.
- Added start-intent / entry-start / stop APIs to [`engine_coordinator.dart`](../lib/services/engine_coordinator.dart): a monotonic one-shot start-intent token (silent launch origin versus user-entry origin) plus guarded transition APIs.
- **Auto-start ON:** app launch keeps Home visible while Detection initializes/starts in the background; the shared status moves Preparing → Ready/Unavailable; opening Detection later reuses the already-initialized cached instance without a second start.
- **Auto-start OFF:** Detection stays off at launch; a deliberate primary navigation into Detection starts it immediately without changing the persisted `autoStartDetection` preference.
- **Manual pause/stop is session-scoped:** leaving and re-entering Detection during the retained session does not auto-restart; an explicit resume/start is required. There is no cross-process persistence.
- Removed the Home `Go to Live Camera` CTA and its callback/import/layout gap without replacement. Home now shows coordinator-derived status and the finalized copy set.
- Preserved Home → Detect one-finger LEFT swipe, Detection-local gestures, TTS, haptics, accessibility semantics, cached-page behavior, Settings, system Back, and Logs & Reports.

### Verified
- `flutter analyze`: no issues.
- `flutter test`: all **247 tests passed**.

### Decisions / Limitations
- Changing Auto-start while the app is already running is out of scope and has no defined behavior.
- Android background/foreground, process death, and camera pre-emption lifecycle behavior is out of scope and unverified.
- Offstage camera/native startup behavior on a physical device (Auto-start ON background preparation) is **Needs Verification** — it has not been observed end-to-end on a physical Android device. No physical-device validation is claimed for this change.

### Next Session
- Validate the Auto-start ON background-preparation and Auto-start OFF entry-start flows on a physical Android device, and confirm the shared status surfaces (Home + both Detection implementations) match on-device.

---

## 2026-09-28 (22nd session) — Primary Gesture Navigation

### Objective
- Implement the approved non-visual primary gesture navigation feature per [`navigation-plan.md`](frontend-workflow/navigation-plan.md), preserving the existing camera/inference architecture, Detection lifecycle, system Back behavior, and accessibility contracts.

### Completed
- Added the persisted `hideBottomNavigation` preference to [`app_settings.dart`](../lib/models/app_settings.dart) (default `false`, backward-compatible parse for older JSON) with a matching getter/setter on [`settings_service.dart`](../lib/services/settings_service.dart) and a labeled Preferences control in [`settings_screen.dart`](../lib/screens/settings_screen.dart). The control represents the persisted preference, not the effective accessibility override.
- Added one-finger linear, non-wrapping primary navigation in [`app_shell.dart`](../lib/navigation/app_shell.dart): a body-only, arena-aware horizontal drag layer moves linearly through Home → Detection → Settings → Help and does not modulo-wrap. A boundary attempt stays on the current tab and emits boundary feedback once.
- Added Detection directional arbitration in [`gesture_controller.dart`](../lib/services/gesture_controller.dart): the first committed directional intent for a one-pointer sequence is locked (horizontal commit prevents a later downward repeat and vice versa), a second pointer before commitment invalidates one-pointer directional classification, and pointer cancellation suppresses every delayed or directional action from that sequence. Existing single-tap, two-finger double-tap, three-finger-tap, and downward-repeat intents are unchanged.
- Added Detection-owned horizontal navigation: [`engine_detection_screen.dart`](../lib/screens/engine_detection_screen.dart) carries a stable relative-navigation callback to both [`detection_screen.dart`](../lib/screens/detection_screen.dart) and [`ultralytics_detection_screen.dart`](../lib/screens/ultralytics_detection_screen.dart), which forward horizontal intents while preserving the existing downward repeat mapping. The viewport-only [`gesture_surface.dart`](../lib/widgets/gesture_surface.dart) remains the only raw-pointer implementation.
- Added light/medium haptic wayfinding at the shell gesture-origin path only: `lightTick` on successful relative navigation and `mediumTick` on a committed boundary attempt; no haptic on insufficient drag or cancellation, and never `heavyTick` for routine navigation.
- Added a minimal best-effort, drop-if-busy wayfinding API to [`tts_service.dart`](../lib/services/tts_service.dart) for destination/boundary phrases. It is suppressed when audio is disabled or accessible-navigation mode is on, never interrupts or delays Detection speech, and preserves Detection replay state.
- [`app_shell.dart`](../lib/navigation/app_shell.dart) now derives effective bottom-bar visibility from the persisted `hideBottomNavigation` preference plus `MediaQuery.accessibleNavigationOf`: the bar is forced visible whenever accessible-navigation mode is active, and the accessibility override is never written back to the persisted preference. When accessibility mode turns off, the persisted preference takes effect again.
- Gesture-origin wayfinding feedback is emitted only from the horizontal-drag navigation path; direct tab selection (`goToTab`), the Home CTA, and system Back remain feedback-free.
- Preserved system Back behavior (Back from a non-Home primary tab returns to Home; a pushed secondary route receives Back first) and the Detection lifecycle (ordinary primary navigation does not dispose or recreate the cached Detection page, and no new remount path was added).

### Verified
- `flutter analyze`: 0 issues.
- `flutter test`: passing, including new coverage for the settings preference, Detection directional arbitration, TTS wayfinding policy, shell gesture navigation, the accessibility/bar truth table, Slider ownership, route/Back isolation, and cached-page preservation.

### Decisions / Limitations
- Physical-device testing surfaced three unresolved issues (recorded in [`known-issues.md`](known-issues.md)): Detection long/fast swipe without releasing the finger triggers navigation; Detection horizontal navigation only triggers within the camera viewport; and a multi-pointer sequence on Home/Settings/Help (one finger held, second finger added, initial finger released) incorrectly triggers navigation. These are device-observed, unresolved, and pending a root-cause fix.
- The provisional horizontal thresholds, displacement guards, and dominance ratio remain subject to physical-device tuning; the existing Detection downward threshold is unchanged.

### Next Session
- Root-cause and fix the three device-observed gesture-navigation issues, then re-verify on the physical Android device.

---

## 2026-09-10 (21st session) — Detection Screen Visual Redesign

### Objective
- Implement the approved visual-only Detection-screen redesign per [`detection-screen-plan.md`](detection-screen-plan.md), [`detection-screen-design-spec.md`](detection-screen-design-spec.md), and [`detection-screen-analysis.md`](detection-screen-analysis.md), preserving the existing camera/inference architecture, gestures, TTS/haptics/telemetry/correction flow, runtime-state reporting, engine fallback, navigation, and accessibility contracts.

### Completed
- Restyled both Detection child screens — [`detection_screen.dart`](../lib/screens/detection_screen.dart) (Custom) and [`ultralytics_detection_screen.dart`](../lib/screens/ultralytics_detection_screen.dart) (Ultralytics) — as a visual-only change. Both now scope the Home-local light theme [`buildHomeTheme()`](../lib/theme/app_home_theme.dart) to the Detection subtree with dark status-bar icons (`AnnotatedRegion<SystemUiOverlayStyle>`), using the existing `kHome*`/`kSpace*`/`kRadius*` tokens as-is (no theme/token file change). The light chrome does not leak into Home, Help, Settings, Logs & Reports, or the shell navigation bar.
- The camera viewport is now a rounded dark card (`kHomeInk`, `kRadius24`, clipped). The viewport stack (`FittedBox` → `CustomPaint(BoundingBoxPainter)` → `_GestureHint` → `GestureSurface`) and the `applyBoxFit` overlay math are unchanged; the Ultralytics `YOLOView` native overlay is unchanged. No `LIVE CAMERA` label was added.
- The header keeps the single `Detection Mode` title using the theme's `titleLarge` (non-bold `w600`, matching the Settings/Help `AppBar` title style) with the `StatusPill` retained as its own live-region element. The `StatusPill` and the `AUDIO ON` pill share one horizontal row, with the audio pill end-aligned right; the Ultralytics performance line and error text remain below that row.
- Replaced the circular audio `IconButton` with an inline `AUDIO ON` / `AUDIO OFF` pill (private `_AudioPill` helper colocated in each screen file): `kHomeSurfaceCard`, `kRadius20`, `kHomeShadowSoft`, `kSpace8` leading dot (`kHomeAccentCyan` on / `kHomeInkMuted` off), uppercase `labelMedium` label with `letterSpacing: 0.5`, `kSpace12`/`kSpace6` padding (matching `StatusPill`), and a ≥48dp touch target. Toggle behavior, tooltip text, enabled state, and the `ListenableBuilder` merge are preserved; the pill exposes a semantic label/role/state.
- The controls panel now uses `kHomeSurfaceBase` with `kSpace12`/`kSpace8` padding; the five-button `Wrap` is preserved with `kSpace8` spacing/runSpacing and `prominent: true` on Pause/Resume and Scan only. The disabled Pause/Resume state and the conditional Correct button are preserved. The panel content is wrapped in a `SingleChildScrollView` (detection list bounded to `maxHeight: 160`, still scrolling internally) so the fixed-height region can never overflow. The gesture-hint text color is now `kHomeInkMuted`.
- `_GestureHint` (both screens) now uses `kOverlayBlack`, `kRadius20`, and `kSpace14`/`kSpace8`/`kSpace10`; white text, `Colors.white24` border, bottom-center position, and copy are preserved.
- Token-consistent restyle of the shared Detection widgets: [`status_pill.dart`](../lib/widgets/status_pill.dart), [`warning_banner.dart`](../lib/widgets/warning_banner.dart), [`detection_card.dart`](../lib/widgets/detection_card.dart), [`priority_badge.dart`](../lib/widgets/priority_badge.dart), [`detection_state_panel.dart`](../lib/widgets/detection_state_panel.dart), and [`detection_correction_sheet.dart`](../lib/widgets/detection_correction_sheet.dart). The correction sheet uses a `Material` surface (not a `Container` color) so `ListTile` ink/splash behavior is preserved.
- Restyled the [`engine_detection_screen.dart`](../lib/screens/engine_detection_screen.dart) temporary-fallback notice to the light surface; `liveRegion: true` is preserved.
- The exact live-region split is preserved: `StatusPill`, `WarningBanner`, `DetectionStatePanel`, and the fallback notice remain live regions; `DetectionCard` remains **not** a live region.
- Added a `DetectionScreen` group to [`test/widget_test.dart`](../test/widget_test.dart) (plugin-free subtrees: title, `StatusPill`, all five controls, `AUDIO ON` pill, no overflow) and extended [`test/accessibility/semantics_test.dart`](../test/accessibility/semantics_test.dart) (audio-pill enabled semantics, `DetectionCard` non-live-region, 200% text-scale no-overflow).

### Post-Implementation Fixes (on-device)
- **Classification:** implementation bug (not a spec gap). The plan §1.1 preserves the "no overflow at 200% text scale" contract and §5.4/§4.6 preserve the fixed-height controls region; the restyle increased the fixed content's intrinsic height without adjusting the region floor.
- **Overflow:** the physical SM S9010 (Android 15/API 35) showed `BOTTOM OVERFLOWED BY 74 PIXELS`. Traced to [`_buildControlsPanel()`](../lib/screens/detection_screen.dart:1048) / [`ultralytics_detection_screen.dart`](../lib/screens/ultralytics_detection_screen.dart:633): the fixed-height region (`contentHeight` clamped 200–320) could not fit the two-row five-button `Wrap` (~120dp) plus the gesture-hint text at the 200dp floor. Fixed by wrapping the panel content in a `SingleChildScrollView` (detection list bounded to `maxHeight: 160`, still scrolling internally) and raising the clamp floor from `200.0` to `260.0` in both screens.
- **`AUDIO ON` pill padding:** reduced from `kSpace16` to `kSpace12`/`kSpace6` to match the `StatusPill` treatment.
- **Header alignment:** the `Detection Mode` title now uses the theme's `titleLarge` (non-bold `w600`) instead of the `w800` override, and the header top padding was raised to `kSpace16`, matching the Settings/Help `AppBar` title position. The `StatusPill` and `AUDIO ON` pill now share one horizontal row with the audio pill end-aligned right.

### Verified
- `flutter analyze`: 0 issues.
- `flutter test`: **185 passing**.
- `flutter build apk --debug`: succeeds; the debug APK installs on the physical SM S9010 (API 35) device.
- Physical-device verification (SM S9010, `R5CTA03XNZD`, Android 15/API 35): after the post-implementation fixes, the overflow banner is gone, no RenderFlex overflows/exceptions appear, the `AUDIO ON` pill padding matches the status pill, and the header title aligns with the Settings/Help headers.

### Decisions / Limitations
- No theme/token file change was made; Detection reuses `buildHomeTheme()` and the existing `kHome*`/`kSpace*`/`kRadius*` tokens as-is.
- The camera viewport stays dark (`kHomeInk`); the light theme applies to the screen chrome only.
- The `BoundingBoxPainter` palette unification and the Home `_StatusBadge` extraction remain deferred (per the plan).
- The full `DetectionScreen` is not pumped in tests (it needs `CameraPlatform`/`permission_handler` mocks); the visual/state contract is covered via plugin-free subtrees.

### Next Session
- Continue any remaining frontend work or documentation sync as directed.

---

## 2026-09-10 (20th session) — Logs & Reports Screen Visual Restyle

### Objective
- Implement the approved visual-only restyle of the existing pushed Logs & Reports route per [`logs-reports-screen-plan.md`](logs-reports-screen-plan.md), [`logs-reports-screen-design-spec.md`](logs-reports-screen-design-spec.md), and [`logs-reports-screen-analysis.md`](logs-reports-screen-analysis.md), preserving the existing architecture, telemetry/export/correction bindings, navigation, and accessibility contracts.

### Completed
- Restyled [`logs_reports_screen.dart`](../lib/screens/logs_reports_screen.dart) as a visual-only change: the route now scopes the existing Home-local light theme [`buildHomeTheme()`](../lib/theme/app_home_theme.dart) locally with dark status-bar icons (`AnnotatedRegion<SystemUiOverlayStyle>`), scoped to the pushed route only and not leaking into the shell navigation bar or other tabs.
- The route now uses a centered bounded secondary-screen layout (~480 logical px content bound, constraint-derived) with light surfaces/typography from the existing `kHome*`/`kSpace*`/`kRadius*` tokens as-is (no theme/token file change); spacing follows the 6/8/12/16/20/24 scale and existing radius roles.
- The Overview, Charts, and Logs tabs were restyled while preserving all telemetry/correction/export/chart bindings, truthful unavailable metrics, navigation, scrolling, and accessibility contracts. [`charts.dart`](../lib/widgets/charts.dart) was **not** modified.
- Added a focused widget test file [`test/screens/logs_reports_screen_test.dart`](../test/screens/logs_reports_screen_test.dart) (25 tests) covering the real screen, route-local theme scope, all three tabs, exports, correction states, unavailable states, Logs priority semantics, and 200% text-scale no-overflow.
- Post-implementation fixes: Engine Comparison rows now render as a single horizontal row with the engine label visible on the left and the value right-aligned flush to the trailing edge (corrected an alignment issue, then a label-starvation regression).

### Verified
- `flutter analyze`: 0 issues.
- `flutter test`: **178 passing**.
- Physical-device visual QA of the restyled route remains pending.

### Decisions / Limitations
- No theme/token file change was made; the route reuses `buildHomeTheme()` and the existing `kHome*`/`kSpace*`/`kRadius*` tokens as-is.
- The route uses a locally scoped light theme and dark status-bar icons; the global dark theme, shell navigation, and other screens are unchanged.
- [`charts.dart`](../lib/widgets/charts.dart) was not modified; chart data binding, dynamic bounds, conditional benchmark lines, semantics summaries, and touch-disabled behavior are preserved.

### Next Session
- Perform physical-device visual QA of the restyled Logs & Reports route (light surface, bounded layout, tab styling, Engine Comparison row alignment, large-text behavior, TalkBack semantics, and no RenderFlex overflows/exceptions).

---

## 2026-09-10 (19th session) — Settings Screen Visual Redesign

### Objective
- Implement the approved visual-only Settings-screen redesign per [`settings-screen-plan.md`](settings-screen-plan.md), [`settings-screen-design-spec.md`](settings-screen-design-spec.md), and [`settings-screen-analysis.md`](settings-screen-analysis.md), preserving the existing architecture, navigation, and runtime behavior.

### Completed
- Redesigned [`settings_screen.dart`](../lib/screens/settings_screen.dart) as a light, responsive composition that reuses the Home-local light theme [`buildHomeTheme()`](../lib/theme/app_home_theme.dart) and the existing `kHome*`/`kSpace*`/`kRadius*` tokens as-is (no theme/token file change). The light surface is scoped to the Settings subtree only and does not leak into the shell navigation bar or other tabs.
- The screen is now a `StatelessWidget` that wraps the subtree in `Theme(buildHomeTheme())` with dark status-bar icons (`AnnotatedRegion<SystemUiOverlayStyle>`), then `Scaffold`/`AppBar('Settings')` → `ListenableBuilder` → `SafeArea` → `LayoutBuilder` → `Center` → `ConstrainedBox (~480)` → plain `ListView`. The four cards are ordered Preferences, Audio Guidance, Engine & Sensitivity, and System Performance (dark `kHomeInk` #0A0A0A).
- Added an optional `TelemetryService? telemetry` parameter; the System Performance card renders `Avg FPS`, `Avg latency (MS)`, and `Avg confidence`, showing `—` when the value is empty or null. No accuracy/precision/recall/F1/mAP/%ACC values are fabricated.
- [`app_shell.dart`](../lib/navigation/app_shell.dart) forwards `telemetry: widget.telemetry` into the `SettingsScreen` construction (single additive change).
- Extended the existing `SettingsScreen` group in [`test/widget_test.dart`](../test/widget_test.dart) and added a Settings semantics group to [`test/accessibility/semantics_test.dart`](../test/accessibility/semantics_test.dart) (8 tests).

### Verified
- `flutter analyze`: 0 issues.
- `flutter test`: **153 passing**.
- `flutter build apk --debug`: succeeds.

### Decisions / Limitations
- No theme/token file change was made; Settings reuses `buildHomeTheme()` and the existing `kHome*`/`kSpace*`/`kRadius*` tokens as-is.
- The Settings subtree uses a locally scoped light theme and dark status-bar icons; the global dark theme, shell navigation, and other screens are unchanged.
- The telemetry metrics are read-only display values; no accuracy/precision/recall/F1/mAP/%ACC values are shown or fabricated.

### Next Session
- Continue any remaining frontend work or documentation sync as directed.

---

## 2026-09-09 (18th session) — Help Screen Visual Redesign

### Objective
- Implement the approved visual-only Help-screen redesign per [`help-screen-plan.md`](help-screen-plan.md), [`help-screen-design-spec.md`](help-screen-design-spec.md), and [`help-screen-analysis.md`](help-screen-analysis.md), preserving the existing architecture, navigation, and runtime behavior.

### Completed
- Redesigned [`help_screen.dart`](../lib/screens/help_screen.dart) as a light, responsive, accessible composition that reuses the Home-local light theme [`buildHomeTheme()`](../lib/theme/app_home_theme.dart) and the existing `kHome*`/`kSpace*`/`kRadius*` tokens as-is (no theme/token file change). The light surface is scoped to the Help subtree only and does not leak into the shell navigation bar or other tabs.
- The Help subtree now uses `Theme(buildHomeTheme())` with dark status-bar icons (`AnnotatedRegion<SystemUiOverlayStyle>`); the retained `AppBar(title: 'Help & Gestures')` and the four sections and their copy are preserved verbatim.
- The four `_HelpCard` sections are now light cards on the light surface with `kRadius24` corners, `kHomeShadowSoft` shadows, token-based padding/separation, and the retained 28px section icons (decorative, excluded from semantics). The section title is the semantic heading for each group.
- The body is a responsive `SafeArea → LayoutBuilder → Center → ConstrainedBox (maxWidth ~480) → ListView` that scrolls at 200% text scale with no overflow.
- Extended the existing `HelpScreen` group in [`test/widget_test.dart`](../test/widget_test.dart) (screen title, four section titles, four section icons, verbatim body copy, light-theme assertion) and added a Help semantics group to [`test/accessibility/semantics_test.dart`](../test/accessibility/semantics_test.dart) (screen-title heading, section groups, decorative-icon exclusion, 200% text-scale no-overflow).

### Verified
- `flutter analyze`: 0 issues.
- `flutter test`: **141 passing**.
- `flutter build apk --debug`: succeeds.
- On-device (physical Android): the light Help surface, card radius/shadow, large-text behavior, TalkBack semantics, and no RenderFlex overflows/exceptions were confirmed.

### Decisions / Limitations
- No theme/token file change was made; Help reuses `buildHomeTheme()` and the existing `kHome*`/`kSpace*`/`kRadius*` tokens as-is (owner decision, Analysis §12, Option 1).
- The Help subtree uses a locally scoped light theme and dark status-bar icons; the global dark theme, shell navigation, and other screens are unchanged.
- The four section titles and their full body copy are preserved verbatim; the four section icons are retained and treated as decorative (excluded from semantics).

### Next Session
- Continue any remaining frontend work or documentation sync as directed.

---

## 2026-09-09 (17th session) — Home Screen Visual Redesign

### Objective
- Implement the approved visual-only Home-screen redesign per [`home-screen-plan.md`](home-screen-plan.md), [`home-screen-design-spec.md`](home-screen-design-spec.md), and [`home-screen-analysis.md`](home-screen-analysis.md), preserving the existing architecture, navigation, and runtime behavior.

### Completed
- Added the `kHome*` light semantic color tokens to [`app_colors.dart`](../lib/theme/app_colors.dart) and the `kRadius3`/`kRadius14`/`kRadius18`/`kRadius24` radius tokens to [`app_radii.dart`](../lib/theme/app_radii.dart).
- Added the Home-local light theme [`app_home_theme.dart`](../lib/theme/app_home_theme.dart) (`buildHomeTheme()`) with IBM Plex Sans typography and Home shadow tokens; runtime font fetching is disabled there.
- Added `google_fonts` (^8.2.1) and bundled offline IBM Plex Sans fonts under `assets/fonts/`; registered `assets/logo.png`.
- Redesigned [`home_screen.dart`](../lib/screens/home_screen.dart): a light, responsive composition with a leading preference/status badge (`READY` / `AUTO-START OFF`), a centered decorative logo + live `EyeCue` wordmark, and a lower instruction region with a truthful headline, supporting copy, the retained `Go to Live Camera` CTA, and a static decorative cyan rail. The layout fills the viewport when short and scrolls at large text scale; the Home subtree uses dark status-bar icons.
- Replaced the old `_StatusCard` (which claimed "Detection is already running") with a preference-truthful `_StatusBadge` driven by `settings.autoStartDetection`.
- Updated [`test/widget_test.dart`](../test/widget_test.dart) Home tests, added a Home semantics group to [`test/accessibility/semantics_test.dart`](../test/accessibility/semantics_test.dart), and updated [`test/theme_test.dart`](../test/theme_test.dart) for the light Home text color.

### Verified
- `flutter analyze`: 0 issues.
- `flutter test`: **133 passing**.
- `flutter build apk --debug`: succeeds.
- On-device (SM-S9010, Android 15/API 35): Home renders with the light surface, spread layout, reduced logo/font sizes, and visible status bar; the user confirmed the result visually.

### Decisions / Limitations
- The reference screenshot's "Swipe right to start!" and "Detection begins immediately" copy were intentionally not reproduced; the approved constraints forbid a swipe gesture and require preference-truthful copy. The visual composition (badge top, centered logo/wordmark, lower instruction, cyan rail) was matched instead.
- The Home subtree uses a locally scoped light theme and dark status-bar icons; the global dark theme, shell navigation, and other screens are unchanged.

### Next Session
- Continue any remaining frontend work or documentation sync as directed.

---

## 2026-09-05 (16th session) — App-Only Runtime Hardening and Validation

### Objective
- Complete the repository-owned implementation described in [`app-only-implementation-plan.md`](app-only-implementation-plan.md), finish deterministic Custom-worker lifecycle coverage, and synchronize current project documentation without guessing Android release identity or credentials.

### Completed
- Extracted Custom-worker lifecycle orchestration into [`inference_worker_lifecycle.dart`](../lib/services/inference_worker_lifecycle.dart), including monotonic generations, stale-message rejection, bounded immediate/delayed retries, explicit retry, terminal failure, healthy-operation budget reset, and disposal-safe backoff.
- Added the explicit `reportWorkerExit` contract to [`inference_isolate.dart`](../lib/services/inference_isolate.dart) and added seven deterministic lifecycle tests for respawn, stale callbacks, busy-gate release, delayed retry, terminal failure, disposal during backoff, and successful recovery.
- Completed the shared runtime/error state, engine fallback coordination, persisted sensitivity, correction capture, movement tracking, scene summaries, recovery telemetry, image-free JSON/CSV export, accessibility semantics, and 200% text-scale coverage across the two independent inference engines.
- Added deterministic metadata-packaging input safety and synchronized the model, telemetry CSV, testing, architecture, roadmap, status, known-issues, README, and changelog documentation.

### Verified
- `flutter analyze`: 0 issues.
- `flutter test test/services/inference_lifecycle_test.dart`: 7 passing.
- `flutter test`: **127 passing**.
- `git diff --check`: passing.
- [`validate_flatbuffer.dart`](../tool/validate_flatbuffer.dart) and [`package_ultralytics_metadata.dart`](../tool/package_ultralytics_metadata.dart) checks: passing.
- `flutter build apk --debug`: passing; APK contains both model artifacts, `labels.txt`, classic `libtensorflowlite_jni.so`, and LiteRT Next `libLiteRt.so` for the packaged ABIs.
- `flutter devices`: only Linux desktop is connected; no Android device/emulator is available for a new smoke run.

### Decisions / Limitations
- Android package identity, production signing, release AAB generation, formal performance/accuracy evaluation, broad device compatibility, Ultralytics licence approval, and Play submission remain separate gated work. No release identity or secret was inferred.
- Native faults such as the historical XNNPACK SIGSEGV cannot be recovered by Dart; the bounded coordinator covers typed worker exits and Dart-level failures, while device stability requires device-level evidence.
- Historical 77-test and release-baseline counts remain in dated records; current status documents report 127 passing tests.

### Next Session
- Confirm the final Android application ID and signing ownership, then implement fail-closed release configuration and validate a signed AAB when credentials and a target Android device are available.

---

## 2026-09-01 (15th session) — App-Only Implementation Planning

### Objective
- Create implementation plans for the remaining application-owned tasks that do not require model training/evaluation, labelled datasets, external test devices, or research respondents.

### Completed
- Added [`app-only-implementation-plan.md`](app-only-implementation-plan.md) covering isolate restart recovery, engine fallback/default policy, TalkBack semantics, correction input, sensitivity, telemetry export, Ultralytics labels, Android identity/configuration/signing/AAB, unified error/loading UI, scene summaries, and movement tracking.
- Defined shared runtime/failure and assistive-output contracts so the features can serve both engines without merging or duplicating their camera/inference internals.
- Added task dependencies, relative size, likely integration points, automated test expectations, acceptance criteria, delivery phases, commit slices, and a plan-wide definition of done.
- Kept model metrics, the multi-device performance matrix, participant studies, licence approval, and Play submission outside this app-only scope.
- Linked the detailed plan from the main roadmap, project status, and README; corrected the roadmap's current automated-test count to 77.

### Decisions / Limitations
- Plan Ultralytics as the recommended new-install default only after bounded engine fallback and visible recovery states exist; preserve explicit existing Custom preferences.
- Treat a temporary runtime fallback separately from the persisted user preference.
- Reuse one shared post-detection assistive layer while retaining separate Custom and Ultralytics camera/inference implementations.
- This session produced documentation only; none of the fifteen application tasks was implemented or marked complete.

### Next Session
- Begin Phase A with typed runtime/failure state and the shared error/loading panel, then implement bounded Custom isolate restart before automatic engine fallback.

---

## 2026-09-01 (14th session) — Dual Inference Modes and Device Smoke Test

### Objective
- Add two selectable test modes—Custom EyeCue and Ultralytics—without removing EyeCue's existing pipeline, then verify both with controlled inputs and document how to compare them fairly.

### Completed
- Added a persisted engine selector with Custom as the compatibility default and centralized the shared model, labels, confidence threshold, and IoU threshold.
- Added the Ultralytics native detection screen and a result adapter so native detections continue through EyeCue's spatial/priority, object-card, warning, TTS, haptic, gesture, and telemetry layers.
- Added separate per-engine telemetry summaries and focused tests for setting persistence, telemetry partitioning, and result adaptation.
- Added an Android packaging bridge that keeps LiteRT Next for Ultralytics and extracts the classic LiteRT FFI library needed by the existing Custom interpreter.
- During the first live Custom→Ultralytics switch, found a late-isolate-result race that attempted to add to a closed stream. Hardened isolate disposal and frame acceptance so late messages are ignored and the UI busy gate is released safely.

### Verified
- `flutter analyze`: 0 issues. `flutter test`: 77 passing. Flatbuffer and PNG validators: passing.
- `flutter build apk --debug`: passing. APK inspection found the shared model/labels plus both native runtime families for arm64-v8a, armeabi-v7a, and x86_64.
- Installed the fixed build on `2201116SG` (Snapdragon 695, Android 13/API 33, arm64). Both engines processed live camera frames; Custom rendered labelled detections and Ultralytics fed native results into EyeCue's labelled assistive UI.
- Post-fix Custom→Ultralytics and Ultralytics→Custom switches completed without recurrence of the closed-stream failure in captured Flutter logs. Custom remained the persisted default after testing.
- Short unmatched observations placed Ultralytics around 6.1–9.6 FPS with 86.1–148.1 ms momentary inference readings; the final thermally warm Custom run reported about 3.5–3.8 FPS and 261.0–289.4 ms average latency. These are smoke-test readings, not comparative benchmark results.

### Decisions / Limitations
- Keep Custom as the default until repeated controlled runs and a representative device matrix establish sustained performance and compatibility.
- Do not claim GPU execution: Ultralytics requested GPU with CPU fallback, but the actual selected delegate was not confirmed.
- Resolve the AGPL-3.0/commercial-licence choice before Play distribution. Also resolve the native overlay's numeric fallback label for this metadata-light model; EyeCue's own card/TTS label mapping is correct.

### Next Session
- Run the paired three-run, five-minute protocol with alternating order, controlled thermal state, battery/temperature/memory capture, qualitative detection checks, and lifecycle/rotation tests.
- Expand to representative low-, mid-, and high-tier Android devices before changing the default engine.

---

## 2026-09-01 (13th session) — Target Device Candidate Retry

### Objective
- Retry the unreleased NCHW/XNNPACK candidate on the Snapdragon 695 phone after device storage was cleared, then capture startup and live inference evidence without treating a short run as a formal benchmark.

### Completed
- Installed the exact generated debug APK successfully on `2201116SG` (`android-arm64`, Android 13/API 33); the old package installation was replaced as part of the install flow.
- Navigated to the Detection screen, which initialized the camera and inference isolate.
- Confirmed startup metadata for `yolov8n_int8_new.tflite`: 3,481,792 bytes, *Weight-Quantized*, FLOAT32 input `[1,3,640,640]` (NCHW), FLOAT32 output `[1,84,8400]`, and internally quantized tensor counts matching the static validator.
- Confirmed explicit XNNPACK delegate creation and interpreter setup with four threads.

### Verified
- A controlled short live run completed 65 logged frames (`#1`–`#65`), all with `backend=XNNPACK`.
- Calculated per-frame latency was 164.8 ms mean, 157.7 ms median, and 150.2–377.3 ms range. App 5-second summaries reported approximately 5.7–6.2 inference FPS and 13.9–14.9 camera FPS.
- The controlled run returned zero detections across its 65 logged frames. A separate earlier short observation returned one `tv` detection at 67.9% confidence and 113.7 ms, confirming a live result can reach the parser/UI path.
- The application process remained alive at capture end; no candidate-process `SIGSEGV` or fatal marker appeared in the captured process-filtered log.

### Decisions / Limitations
- Record this as **initial device evidence**, not a formal benchmark, accuracy result, full-delegation proof, long-duration stability result, or resolution of the historical native XNNPACK crash.
- Keep v0.2.2 CPU/NHWC as the stable documented baseline and keep the NCHW/XNNPACK candidate unreleased until controlled comparison, accuracy, thermal, memory, orientation, and longer stability validation are complete.

### Next Session
- Run longer controlled candidate and CPU comparison sessions, collect fallback/native-crash evidence, run the official TFLite benchmark tool, and perform ground-truth accuracy evaluation.
- Re-validate back-camera landscape and front-camera portrait/landscape orientation, then complete UI/gesture/TTS/settings checks and isolate restart recovery.

---

## 2026-09-01 (12th session) — NCHW Candidate, XNNPACK Fallback, and Status Sync

### Objective
- Assess the post-v0.2.2 worktree, validate the new model/layout path, synchronize current documentation, and prepare one atomic commit without overstating device validation.

### Completed
- Reviewed the then-uncommitted model, inference, tensor-rotation, test, validator, and documentation changes before they were committed.
- Confirmed the candidate model directly: `yolov8n_int8_new.tflite` is 3,481,792 bytes with input `[1,3,640,640]` / FLOAT32, output `[1,84,8400]` / FLOAT32, and 448 tensors (2 FLOAT32, 90 INT32, 356 INT8).
- Added runtime NCHW preprocessing and a standalone layout-aware [`tensor_rotation.dart`](../lib/models/tensor_rotation.dart) helper. The helper has 14 focused tests covering NHWC/NCHW rotations, mirroring, equivalence, and guards.
- Hardened the experimental XNNPACK path in [`inference_isolate.dart`](../lib/services/inference_isolate.dart): delegate ownership is retained for interpreter lifetime; setup failures and recoverable invocation failures retry on a four-thread CPU interpreter. Native SIGSEGV remains uncatchable.
- Extended [`validate_flatbuffer.dart`](../tool/validate_flatbuffer.dart) to cover the candidate model.
- Synchronized current status, architecture, implementation progress/decisions, known issues, research notes, benchmark notes, testing plan, changelog, and README. The 2026-08-21 comprehensive assessment remains a historical snapshot.

### Verified
- `flutter analyze`: 0 issues.
- `flutter test`: 73 passing.
- Flatbuffer and PNG validators pass; the generated debug APK contains the candidate model asset.
- Candidate APK installation was blocked at that time by `INSTALL_FAILED_INSUFFICIENT_STORAGE`; this was later resolved in the 13th-session retry recorded above. The earlier session therefore produced no candidate runtime result.

### Decisions
- Treat the v0.2.2 CPU/NHWC path as the stable documented baseline.
- Treat the NCHW/XNNPACK path as unreleased and initially device-observed; the exact APK install and short live run are now recorded in the 13th-session entry above.
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
- Retired the old single-screen `camera_screen.dart`
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
- `camera_screen.dart` — per-frame
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
- `camera_screen.dart` — strict 3:4
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
- `camera_screen.dart` — preview rendered
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
- **Wired `camera_screen.dart`**: overlay reacts to `metadataNotifier`; busy gate releases on isolate errors via `errorStream`.
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
