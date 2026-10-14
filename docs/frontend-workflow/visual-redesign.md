# Visual Redesign — Presentation-Only Implementation Plan

> **Implementation closeout (2026-09-29):** Completed as presentation-only work.
> `flutter analyze` reported 0 issues, `flutter test` reported 343 passing / 0
> failing, and the user explicitly confirmed the required physical Android
> visual checks. This closeout records confirmed outcomes without changing the
> locked planning source of truth below.

## Source of Truth and Fixed Scope

**Task type:** visual redesign implementation planning only. This document is the implementation plan for the locked product decisions in the task prompt, grounded in direct source inspection and the supplied discovery findings. It supersedes contradictory discovery material in [`extracted-design-tokens-screenshot.md`](design-reference/tokens/extracted-design-tokens-screenshot.md), particularly its removed-bottom-navigation, Home-right-swipe, and `%ACC` proposals.

### Fixed product decisions

- Home → Detection remains a **left swipe**. Preserve the existing linear tab navigation implemented by [`navigateRelative()`](lib/navigation/app_shell.dart:246) and the existing Home status copy; do not reverse the gesture direction or add a separate start gesture.
- Keep the same primary destinations and order: **Home, Detection, Settings, Help**. Retain the shell cache, selected-state handling, bottom-bar callbacks, Back behavior, visible-bar accessibility override, and persisted hide/show preference.
- Bottom-navigation work is visual only. Ownership stays in [`AppShell`](lib/navigation/app_shell.dart:123), not in a new routing or navigation abstraction.
- Home becomes fixed/non-scrollable in its normal composition without changing shared lifecycle status rendering, the logo/wordmark meaning, or shell swipe behavior.
- Settings and Help retain their existing scrolling behavior, but their app bar and scroll body must share one fixed, consistent light visual surface while scrolling. Logs & Reports follows the same light route/app-bar treatment.
- Detection action controls remain the existing shared two-control component: visual restyling only. Preserve Pause, Resume, Start, Preparing, Unavailable, long-hold Stop/Start, and Quick Scan behavior, gating, callbacks, semantics, timing, and state mappings.
- System Performance retains truthful current metrics/content. Do not add `%ACC`, accuracy, or any other ungrounded performance claim.

## Confirmed Baseline and Change Boundary

The application entry remains [`main.dart`](lib/main.dart:15), which wires the app and theme into [`AppShell`](lib/navigation/app_shell.dart:123). The four cached primary pages are supplied through [`AppShellState._buildPage()`](lib/navigation/app_shell.dart:299), and the existing navigation bar is rendered in [`AppShellState.build()`](lib/navigation/app_shell.dart:345). No app-wiring or lifecycle changes belong in this redesign.

The presentation work is limited to these UI owners:

| Owner | Confirmed current responsibility | Planned presentation-only responsibility |
|---|---|---|
| [`HomeScreen`](lib/screens/home_screen.dart:26) | Light Home composition, shared lifecycle badge/copy, decorative logo and wordmark | Convert the normal composition from scrollable to fixed while retaining content/status semantics and responsive safety |
| [`AppShell`](lib/navigation/app_shell.dart:123) | Four-tab cache, shell drag navigation, primary bar, callbacks, selection | Modernize only the bar visual treatment while retaining all behavior |
| [`SettingsScreen`](lib/screens/settings_screen.dart:22) | Preference controls, engine/sensitivity radios, truthful performance card | Restyle layout/card/controls without changing services, values, handlers, or telemetry content |
| [`HelpScreen`](lib/screens/help_screen.dart:17) | Scrollable instruction cards | Restyle card surfaces and remove decorative icons without changing copy, sections, semantics headings, or scrolling |
| [`LogsReportsScreen`](lib/screens/logs_reports_screen.dart:28) | Settings-launched researcher route with a light local theme | Apply the shared fixed light app-bar/background treatment without changing route, tabs, export, or metrics logic |
| [`DetectionActionControls`](lib/widgets/detection_action_controls.dart:39) | Shared lifecycle/Quick Scan control presentation and local hold interaction | Apply distinct visual surfaces/shadows only; preserve interaction implementation exactly |
| [`DetectionScreen`](lib/screens/detection_screen.dart:980) and [`UltralyticsDetectionScreen`](lib/screens/ultralytics_detection_screen.dart:923) | Compose the shared action row for each engine | Consume the already-shared control visual update; do not alter engine-specific state, actions, or camera/native behavior |
| [`app_colors.dart`](lib/theme/app_colors.dart:1), [`app_spacing.dart`](lib/theme/app_spacing.dart:1), [`app_radii.dart`](lib/theme/app_radii.dart:1), and [`app_home_theme.dart`](lib/theme/app_home_theme.dart:1) | Light semantic tokens and scoped `ThemeData` | Add/use only confirmed semantic presentation tokens and light component themes necessary for this redesign |

## Implementation Sequence

### 1. Verify and extend the light token layer minimally

**Files:** [`app_colors.dart`](lib/theme/app_colors.dart:1), [`app_home_theme.dart`](lib/theme/app_home_theme.dart:1); inspect-only context from [`app_spacing.dart`](lib/theme/app_spacing.dart:1) and [`app_radii.dart`](lib/theme/app_radii.dart:1).

1. Reuse confirmed token names already present:
   - `surface-base` → [`kHomeSurfaceBase`](lib/theme/app_colors.dart:115) (`#F5F5F5`)
   - `surface-card` → [`kHomeSurfaceCard`](lib/theme/app_colors.dart:118) (`#FFFFFF`)
   - `surface-card-96` → [`kHomeSurfaceCard96`](lib/theme/app_colors.dart:121)
   - `ink` → [`kHomeInk`](lib/theme/app_colors.dart:124) (`#0A0A0A`)
   - `ink-muted` → [`kHomeInkMuted`](lib/theme/app_colors.dart:127)
   - `accent-cyan` → [`kHomeAccentCyan`](lib/theme/app_colors.dart:133) (`#22C7F2`)
   - `accent-cyan-light` → [`kHomeAccentCyanLight`](lib/theme/app_colors.dart:136)
   - existing soft shadow → [`kHomeShadowSoft`](lib/theme/app_home_theme.dart:18), whose confirmed values match the supplied `shadow-soft` definition.
2. Retain existing spacing and radius tokens; do not introduce literal spacing or radius values in screens/widgets. Use the established [`kSpace*`](lib/theme/app_spacing.dart:7) and [`kRadius*`](lib/theme/app_radii.dart:7) scales.
3. Add a named `overlay-white-11` color token **only if source review confirms no existing equivalent**. The intended semantic role is the inner surface for `View Logs & Reports`; its provided value is `rgba(255,255,255,0.11)`. **Needs Verification [design-verified]:** the exact new Dart symbol name is not established in current source and must be selected according to the token naming convention before implementation; do not invent a final symbol in this plan.
4. Do **not** add a second soft-shadow token unless implementation review finds a genuine semantic distinction. [`kHomeShadowSoft`](lib/theme/app_home_theme.dart:18) already exists and matches the required design value; reuse it for Settings/Help cards and both Detection controls.
5. Extend [`buildHomeTheme()`](lib/theme/app_home_theme.dart:50) with a light `AppBarTheme`, plus the necessary Material component themes for active toggle/radio/navigation presentation, using only the semantic tokens above. This gives Settings, Help, and Logs & Reports a theme-owned fixed light app-bar/background treatment rather than per-screen ad hoc colors.

### 2. Make the Home composition fixed in normal use

**File:** [`home_screen.dart`](lib/screens/home_screen.dart:26).

1. Replace the current normal-layout [`CustomScrollView`](lib/screens/home_screen.dart:69) / [`SliverFillRemaining`](lib/screens/home_screen.dart:76) structure with a bounded, non-scrollable layout that retains the same hierarchy: `_StatusBadge`, centered logo/wordmark, and `_InstructionRegion`.
2. Retain `LayoutBuilder`, the responsive `boundedWidth`, safe areas, the Home-local theme, and the light status-bar styling. The layout must remain responsive without fixed screenshot dimensions.
3. Preserve [`_homeStatusPresentation()`](lib/screens/home_screen.dart:281) verbatim: Preparing, Ready, Paused, Stopped, and Unavailable text/semantics derive exclusively from the app-shell-owned coordinator.
4. Do not add a CTA, gesture detector, callback, or lifecycle action. Home-to-Detection remains the shell-owned left swipe supplied by [`_SingleFingerHorizontalDragRecognizer`](lib/navigation/app_shell.dart:24) and [`AppShellState.navigateRelative()`](lib/navigation/app_shell.dart:246).
5. Define implementation behavior for constrained/large-text layouts before editing: the requirement names the **normal layout** as fixed, but the current scroll behavior is the documented overflow safeguard at 200% text scale. **Needs Verification [product-decision]:** confirm whether the fixed/non-scrollable requirement applies at 200% text scale too, or whether an accessibility-only overflow-safe fallback is permitted. Do not silently trade away the existing no-overflow accessibility contract.

### 3. Modernize the four-tab bar without moving its behavioral ownership

**Files:** [`app_shell.dart`](lib/navigation/app_shell.dart:123) and the light component theme in [`app_home_theme.dart`](lib/theme/app_home_theme.dart:50), with semantic token support in [`app_colors.dart`](lib/theme/app_colors.dart:1) if needed.

1. Keep the `NavigationBar` in [`AppShellState.build()`](lib/navigation/app_shell.dart:379) as the sole primary-navigation visual owner. It already has the correct `selectedIndex`, [`goToTab()`](lib/navigation/app_shell.dart:232) callback, labels, destinations, order, and visibility gate.
2. Apply the refreshed light/Home-theme appearance through `NavigationBarThemeData` and/or the existing bar instance properties: light background, tokenized selected indicator/accent, selected/unselected icon and label colors, and required shape/elevation treatment. Do not wrap it in a second navigation widget or move it into individual tabs.
3. Preserve the exact four destinations and labels: Home, Detect, Settings, Help. Preserve [`_effectiveHideBar`](lib/navigation/app_shell.dart:342), persisted settings listener rebuilds, [`MediaQuery.accessibleNavigationOf`](lib/navigation/app_shell.dart:338) override, `IndexedStack` cache, Back behavior, and `onDestinationSelected: goToTab`.
4. Leave the shell gesture recognizer, threshold, multi-pointer invalidation, swipe direction, feedback, and the Detection-owner exclusion unchanged. Detection must still be excluded from shell recognition via `enabled: () => _index != 1` in [`AppShellState.build()`](lib/navigation/app_shell.dart:369).

### 4. Restyle Settings while retaining every preference and truthful metric

**File:** [`settings_screen.dart`](lib/screens/settings_screen.dart:22).

1. Continue using the existing `ListView` in [`SettingsScreen.build()`](lib/screens/settings_screen.dart:66). Do not change scrolling, data bindings, persistence, or invocation of `SettingsService` setters.
2. Rely on the theme-owned light `AppBarTheme` / `scaffoldBackgroundColor` from [`buildHomeTheme()`](lib/theme/app_home_theme.dart:50) so the fixed app bar and scrolling content retain the same visual surface throughout scrolling. Do not add scroll-driven color transitions or per-frame effects.
3. Remove decorative section icons from `_SettingsCard`; update its API and call sites so its semantic heading is still exposed once, as it is currently in [`_SettingsCard.build()`](lib/screens/settings_screen.dart:337). Keep all interactive row labels and control semantics.
4. Remove decorative leading/secondary icons from preference switches and from engine/sensitivity explanatory rows where those icons duplicate text; preserve the `SwitchListTile`, both [`RadioGroup`](lib/screens/settings_screen.dart:138) clusters, [`RadioListTile`](lib/screens/settings_screen.dart:154) selections, slider, values, callbacks, and their existing accessibility behavior.
5. Align Settings child typography to the section-heading system by using the established light `TextTheme` roles consistently. This is type styling only; do not alter content, text, confidence ranges, or callbacks.
6. Relocate radio affordances to the trailing/right position, aligned with the switches. Retain the same mutually exclusive grouping, selected values, labels, subtitles, and tap targets; use supported `RadioListTile` positioning/configuration instead of manually rebuilding radio semantics.
7. Use accent cyan for active `SwitchListTile`, radio, and slider states through the light component themes or token-backed per-control state properties. Keep disabled/inactive contrast and existing semantic checked/selected state.
8. Keep `_SystemPerformanceCard` metrics exactly as written: Avg FPS, Avg latency (MS), Avg confidence, and `—` where data is absent. Explicitly preserve the no-accuracy rule described in [`_SystemPerformanceCard`](lib/screens/settings_screen.dart:400); do not add `%ACC`.
9. For the System Performance card: remove the decorative chart icon; set the title/label accent to `accent-cyan-light`; set the retained chevron to `accent-cyan`; retain the ListTile action and its `onOpenLogsReports` callback; apply the tokenized `overlay-white-11` inner surface to the `View Logs & Reports` action area only. Keep its text/semantics and truthful telemetry content unchanged.

### 5. Restyle Help and Logs & Reports with stable light surfaces

**Files:** [`help_screen.dart`](lib/screens/help_screen.dart:17), [`logs_reports_screen.dart`](lib/screens/logs_reports_screen.dart:28), and shared light theming in [`app_home_theme.dart`](lib/theme/app_home_theme.dart:50).

1. Keep Help's existing `ListView`, section order, copy, 200%-text-scale support, title semantics, and semantic headings.
2. Simplify `_HelpCard` to a surface-card background with the established soft shadow/radius and remove the decorative icon parameter, call-site icons, and icon row. Preserve the text heading and body hierarchy so each title remains one semantic heading.
3. Keep the standard app bars in Settings, Help, and Logs & Reports; make their fixed app-bar and the route/body background consistently light via the theme. Confirm that the TabBar portion of Logs & Reports is visibly part of the same surface treatment.
4. In [`LogsReportsScreen`](lib/screens/logs_reports_screen.dart:28), change only route-level presentation/theme consumption necessary for the stable app bar/body surface. Do not modify telemetry calculations, exports, correction history, chart configuration/data, tabs, tab behavior, or unavailability copy.

### 6. Apply the shared Detection action-control visual treatment

**File:** [`detection_action_controls.dart`](lib/widgets/detection_action_controls.dart:39).

1. Keep the exact two-control `Row` and its layout in [`_DetectionActionControlsState.build()`](lib/widgets/detection_action_controls.dart:253). Do not add or remove controls.
2. Restyle the lifecycle control to `surface-card` and the Quick Scan control to `accent-cyan`; apply [`kHomeShadowSoft`](lib/theme/app_home_theme.dart:18) to both. Use semantic token imports rather than raw colors.
3. Define disabled and press/hold-progress presentation using existing semantic colors/tokens while preserving contrast. The progress treatment remains visual feedback only and must not change `kLifecycleHoldDuration`, long-press classification, hit testing, or dispatch locks.
4. Preserve all labels, semantics, hints, enabled values, touch-target constraints, callback references, physical pointer timing, TalkBack tap behavior, Quick Scan Ready-only gate, and outcome-change cancellation logic in [`_DetectionActionControlsState`](lib/widgets/detection_action_controls.dart:76).
5. Do not change the shared composition in [`DetectionScreen._buildActionControlsRow()`](lib/screens/detection_screen.dart:1010) or [`UltralyticsDetectionScreen._buildActionControlsRow()`](lib/screens/ultralytics_detection_screen.dart:929) except if a purely presentational spacing/surface dependency cannot be owned by the shared widget. Any required engine-screen composition modification must first be justified against the existing two-control contract and tracked as a regression-test update.

## Files Explicitly Not to Modify

The implementation must not modify any file outside the scoped UI/theme/test ownership listed above without returning for approval.

- [`main.dart`](lib/main.dart:15): no app construction, service wiring, theme-mode, or `MaterialApp` behavior change.
- **All [`lib/models/`](lib/models/) files:** no persisted settings schema, runtime state, model/configuration, or DTO changes.
- **All [`lib/services/`](lib/services/) files:** no lifecycle internals, coordinator transitions, telemetry calculations, settings persistence, camera/inference behavior, gesture interpretation, TTS, haptics, engine selection, or recovery changes.
- Navigation behavior in [`app_shell.dart`](lib/navigation/app_shell.dart:123): do not change callbacks, selected index/state, tab cache, `IndexedStack`, Back handling, shell swipe recognizer, directional behavior, haptic/TTS feedback, Detection's separate gesture ownership, or bottom-bar preference semantics.
- Engine and camera internals in [`detection_screen.dart`](lib/screens/detection_screen.dart:980) and [`ultralytics_detection_screen.dart`](lib/screens/ultralytics_detection_screen.dart:923): no change to lifecycle methods, coordinator reporting, permission flow, camera/native view, inference, overlays, telemetry, gestures, or callbacks.
- [`logs_reports_screen.dart`](lib/screens/logs_reports_screen.dart:28) content/logic: no metric definition changes, no new accuracy metric, no tab/route/export/correction/chart behavior changes.
- Assets, fonts, dependencies, Android files, documentation other than this plan, test infrastructure, and all source files not explicitly listed under implementation ownership.

## Preservation Constraints

1. **Lifecycle integrity:** The shared coordinator remains the user-facing lifecycle source. Presentation updates must not change Ready/Paused/Stopped/Preparing/Unavailable mapping, auto-start intent, explicit starts/stops, fallback/retry behavior, or session-scoped pause/stop semantics.
2. **Gesture integrity:** Home left swipe advances to Detection; right swipe returns toward Home. Shell gestures remain single-finger, linear, non-wrapping, and protected from multi-pointer commits. Detection continues to own horizontal navigation within its gesture surface, without a shell duplicate.
3. **Control integrity:** The lifecycle action control retains pause-on-tap, resume-on-tap, stop/start-on-three-second-hold, Preparing/Unavailable disabled behavior, and all existing TalkBack hints. Quick Scan remains visible but Ready-only.
4. **Accessibility:** Decorative icons must be removed or excluded rather than replaced with duplicate semantics. Existing heading, switch/radio checked state, button role/state/hint, and live-region policies remain intact. All revised controls retain at least the existing minimum touch dimensions.
5. **Responsive behavior:** Use constraints, `Expanded`/`Flexible`, token spacing, and Material adaptive components; do not reproduce screenshot dimensions as fixed layout values. Confirm no overflow at 200% text scale.
6. **Data truthfulness:** Do not expose `%ACC`, Accuracy, Precision, Recall, F1, or mAP as live performance data. Preserve explicit unavailable messaging where the app lacks ground truth.

## Test and Validation Plan

### Automated test updates

| Test file | Required adjustment / preservation assertion |
|---|---|
| [`test/theme_test.dart`](test/theme_test.dart:1) | Extend light-theme regression coverage to assert the light app-bar/background component treatment and token-backed active controls build without exceptions. Keep the global dark-theme wiring assertion intact. |
| [`test/widget_test.dart`](test/widget_test.dart:1) | Update visual-structure expectations: Home no longer builds `CustomScrollView` in normal layout; Settings/Help decorative icon expectations change to absence; card/surface hierarchy and active control treatment are asserted through widget properties where stable. Preserve all visible copy, headings, `%ACC` absence, metrics, and callbacks. |
| [`test/navigation/app_shell_test.dart`](test/navigation/app_shell_test.dart:1) | Preserve all existing tests for four-tab order, bar callback selection, cache, visible/hidden preference, accessible-navigation override, Home-left direction, shell gesture ownership, and Detection exclusion. Add targeted assertions only for navigation-bar presentation/theme properties if they can be stable without over-coupling to Material internals. |
| [`test/accessibility/semantics_test.dart`](test/accessibility/semantics_test.dart:1) | Update expectations for icon removal while preserving one heading node per section/card, switch/radio semantics, and 200% text-scale no-overflow coverage. Add checks that new visual grouping does not introduce duplicate labels or change control hints/actions. |
| [`test/widgets/detection_action_controls_test.dart`](test/widgets/detection_action_controls_test.dart:1) | Retain every state/dispatch/hold/Quick Scan/TalkBack assertion unchanged. Add narrow visual tests for lifecycle `surface-card`, Quick Scan `accent-cyan`, shared soft shadow, and disabled contrast only where testable through stable widget decoration inspection. |
| [`test/screens/detection_redesign_parity_test.dart`](test/screens/detection_redesign_parity_test.dart:1), [`test/screens/detection_redesign_regression_test.dart`](test/screens/detection_redesign_regression_test.dart:1), [`test/screens/detection_screen_layout_test.dart`](test/screens/detection_screen_layout_test.dart:1), and [`test/screens/ultralytics_detection_screen_layout_test.dart`](test/screens/ultralytics_detection_screen_layout_test.dart:1) | Review first; modify only if the action-row composition or shared control visual contract makes an existing structural expectation stale. Do not broaden scope into engine behavior. |
| [`test/screens/logs_reports_screen_test.dart`](test/screens/logs_reports_screen_test.dart:1) | Add or adjust route-level light app-bar/background surface assertions only. Retain existing coverage for telemetry, tabs, exports, charts, correction content, and unavailable-metric truthfulness. |

### Scoped visual/golden coverage

Add golden coverage only if the repository already has an approved golden-test harness or one can be added without dependency/tooling scope expansion. The highest-value snapshots are:

1. Home normal fixed layout at the reference phone viewport, plus the agreed large-text behavior.
2. Settings top, radio/slider region, and System Performance card showing the cyan labels, chevron, and overlay-white-11 action region.
3. Help cards with icon-free surface-card styling and stable app bar.
4. Shared [`DetectionActionControls`](lib/widgets/detection_action_controls.dart:39) in Ready, Paused, Stopped, Preparing, and Unavailable outcomes.
5. [`AppShell`](lib/navigation/app_shell.dart:123) navigation bar with each selected destination.

**Needs Verification [inferred-from-codebase]:** source inspection confirms widget tests but did not confirm an existing golden-test harness, baseline images, font-stable rendering workflow, or device-pixel policy. Do not introduce a new snapshot framework until that is verified.

### Mandatory physical Android-device verification

On the supported physical Android device, validate all of the following after automated checks:

1. Visual review on Home, Settings, Help, Logs & Reports, and both detection engines: tokenized light surfaces, cards, nav bar, cyan control treatment, shadows, section icon removal, and System Performance styling match the approved design intent.
2. Home's normal composition is fixed/non-scrollable; validate the final agreed behavior at 200% text scale and confirm no clipping/overflow.
3. Settings, Help, and Logs & Reports scroll normally while their app-bar and background surface do not visibly shift color/material treatment; verify AppBar and Logs TabBar surface continuity.
4. Toggle/radio/slider active visuals use cyan and remain legible; all controls retain touch targets, TalkBack labels/roles/states/hints, and no duplicate icon semantics.
5. Bottom navigation retains all four destinations, selected state, visibility preference behavior, accessibility override, and callbacks; Home-left swipe still goes to Detection; shell direction and one-tab movement remain unchanged; Detection horizontal gesture ownership remains separate and produces no duplicate navigation.
6. On both Custom and Ultralytics Detection screens, verify Pause, Resume, Start, Preparing, Unavailable, long-hold Stop/Start, and Quick Scan behavior remains unchanged after the visual control update.
7. Confirm System Performance displays only truthful existing values/`—`, contains no `%ACC`, and that View Logs & Reports still opens its route.
8. Check `flutter analyze` reports zero issues, `flutter test` passes, and device logcat contains no new exceptions or `RenderFlex`/constraint overflows.

## Open Questions / Needs Verification

1. **App-bar/nav visual details [design-verified]:** The supplied locked decisions do not define exact bar height, indicator shape, icon/label selected-state colors, elevation, or divider values beyond the completed light/Home-theme refresh. Current Material dimensions and the implemented theme treatment were retained; any future geometry change requires an approved design source.
2. **Golden-test readiness [inferred-from-codebase]:** No golden harness/baselines were confirmed during scoped source review. The user-confirmed physical Android visual checks close the required redesign validation, but deterministic golden coverage remains unconfirmed and must not be added without tooling approval.
