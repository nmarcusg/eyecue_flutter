## Executive Verdict

The approved non-visual navigation change is feasible with the existing Flutter and application architecture. The primary tab state, page retention, tab bar, Back interception, settings propagation, speech service, vibration service, and the two Detection gesture surfaces already have clear integration seams in [`AppShellState`](../../lib/navigation/app_shell.dart#L45-L169), [`SettingsService`](../../lib/services/settings_service.dart#L60-L117), [`TtsService`](../../lib/services/tts_service.dart#L64-L233), [`HapticsService`](../../lib/services/haptics_service.dart#L9-L47), and [`GestureController`](../../lib/services/gesture_controller.dart#L24-L164).

Implementation must keep the existing architectural split:

- The shell owns primary-tab selection, bar visibility, relative navigation decisions, and wayfinding feedback. It must not make raw pointer observations across the app.
- Detection owns its viewport-local, raw-pointer gesture state machine. It must classify one-pointer horizontal movement versus the existing downward repeat action, then request shell navigation through injected callbacks.
- Persistence remains in the existing immutable settings model plus file-backed settings service.
- TTS needs a narrow best-effort, drop-if-busy wayfinding capability. It must be separate from Detection replay bookkeeping and must not interrupt or delay Detection alerts; no general priority scheduler is proposed unless a direct implementation review proves a minimal guard insufficient.

This is a behavior change, not a visual redesign. No dependency, Android, inference, camera, model, or routing-package change is required. The implementation must not expand into unrelated refactoring.

## Repository Changes Since Previous Audit

There is no existing navigation-specific planning artifact in [`docs/frontend-workflow`](.). This plan is the baseline for this feature; no repository file has been changed during analysis.

The current implementation already differs from a simple stateless tab shell in ways that determine the safe implementation:

- [`AppShellState`](../../lib/navigation/app_shell.dart#L45-L123) retains visited pages in an [`IndexedStack`](../../lib/navigation/app_shell.dart#L135-L137), rather than rebuilding pages for every tab move.
- [`EngineDetectionScreen`](../../lib/screens/engine_detection_screen.dart#L101-L145) selects a Custom or Ultralytics child using generation-based keys. Ordinary tab changes preserve Detection, but engine changes, recovery/fallback, and confidence-triggered restarts can remount the active engine.
- [`SettingsScreen`](../../lib/screens/settings_screen.dart#L39-L195) is a vertically scrollable settings page with a Material [`Slider`](../../lib/screens/settings_screen.dart#L229-L306), which already owns a horizontal drag recognizer.
- [`LogsReportsScreen`](../../lib/screens/logs_reports_screen.dart#L46-L100) is a pushed secondary route with a route-local horizontal [`TabBarView`](../../lib/screens/logs_reports_screen.dart#L52-L100).
- Both Detection implementations place the existing raw-pointer [`GestureSurface`](../../lib/widgets/gesture_surface.dart#L25-L39) only over their camera viewports, using the shared [`GestureController`](../../lib/services/gesture_controller.dart#L24-L164).

## AppShell Gesture Placement

Implement primary navigation as an arena-aware **one-finger-only** horizontal drag layer around the shell body only: the [`IndexedStack`](../../lib/navigation/app_shell.dart#L135-L137) that supplies the [`Scaffold`](../../lib/navigation/app_shell.dart#L127-L168) body. Do not wrap the complete [`Scaffold`](../../lib/navigation/app_shell.dart#L127-L168), the [`NavigationBar`](../../lib/navigation/app_shell.dart#L143-L165), or any pushed route.

The primary-navigation recognizer must be arena-aware and must structurally enforce an **exactly-one-active-pointer** contract for the full gesture sequence. If a standard Flutter `GestureDetector` / `HorizontalDragGestureRecognizer` cannot expose or enforce invalidation when any second pointer joins, use a narrowly scoped custom single-finger horizontal recognizer through Flutter's `RawGestureDetector` from the outset. Do not use a shell-wide raw [`Listener`](../../lib/widgets/gesture_surface.dart#L27-L39). The recognizer should maintain shell-local drag state, accumulate one drag displacement, and commit at most once in its end callback. A second pointer joining at any time invalidates the complete sequence and resets without primary navigation, even if that second pointer later lifts. [implementation requirement]

The shell gesture layer must:

1. recognize one-finger horizontal drags only;
2. invalidate the complete physical-drag transaction when a second pointer joins, including when it joins after horizontal movement has begun;
3. maintain one eligible physical-drag transaction from start to end/cancel;
4. call a shell-private relative-navigation method once only after the committed direction is known;
5. reset without navigation on cancellation, multi-pointer invalidation, or insufficient displacement;
6. leave [`goToTab`](../../lib/navigation/app_shell.dart#L68-L74) as the direct, feedback-free path for the visible navigation bar, Home CTA, and Back behavior; and
7. never use a shell-wide raw [`Listener`](../../lib/widgets/gesture_surface.dart#L27-L39).

The relative-navigation method should translate the current [`_index`](../../lib/navigation/app_shell.dart#L46-L48) plus direction into the linear Home → Detection → Settings → Help range. It must not modulo-wrap. A successful result changes the tab once; an out-of-range result remains on the current tab and emits boundary feedback once.

Use one explicitly named gesture-origin path, separate from direct tab selection, so only actual horizontal-drag navigation can produce wayfinding feedback. This prevents taps on [`NavigationBar.onDestinationSelected`](../../lib/navigation/app_shell.dart#L143-L165), the Home CTA, and system Back from receiving accidental gesture haptics or speech.

The public Flutter documentation/source inspected from the installed SDK supports this placement and the `MediaQuery` APIs used below. Context7 did not return a matching Flutter API result, so installed framework source is the evidence for those framework expectations. [framework-verified]

## Slider and Scroll Gesture Ownership

The shell layer must have only a horizontal recognizer. It must not add a pan recognizer, vertical-drag recognizer, or raw pointer observer above page content.

That preserves the existing vertical gesture owners:

- Home scrolls with [`CustomScrollView`](../../lib/screens/home_screen.dart#L63-L131).
- Settings scrolls with [`ListView`](../../lib/screens/settings_screen.dart#L50-L195).
- Help scrolls with [`ListView`](../../lib/screens/help_screen.dart#L30-L104).

The Settings sensitivity control is a Material [`Slider`](../../lib/screens/settings_screen.dart#L229-L306) whose value changes on drag and persists only from its end callback. Flutter's installed Material source shows that Slider adds a child [`HorizontalDragGestureRecognizer`](../../lib/screens/settings_screen.dart#L229-L306) before its tap recognizer and is hit-testable. The child Slider recognizer must therefore win its horizontal drag against the shell ancestor in the arena. [framework-verified]

The required automated regression is exact: **Dragging the Slider changes its value and does not change [`_index`](../../lib/navigation/app_shell.dart#L46-L48).** The test must use the real Settings slider under the shell gesture layer, not merely call a setting setter.

For ordinary vertically scrollable pages, a vertical drag must scroll without changing the primary tab. For diagonal drags, the framework arena and the shell's horizontal-only recognizer decide ownership; tests must cover both vertical-dominant and clearly horizontal gestures. If device testing reveals that a diagonal motion can navigate unexpectedly, tune the provisional shell commit-distance guard before introducing a custom recognizer. [Needs Verification: physical Android gesture tuning]

## Detection Gesture Integration

Extend the existing pure [`GestureController`](../../lib/services/gesture_controller.dart#L24-L164), rather than adding a second controller or moving Detection gestures into the shell.

The controller currently recognizes a single tap, two-finger double tap, three-finger tap, and downward swipe through [`EyeCueGesture`](../../lib/services/gesture_controller.dart#L5-L17) and [`onPointerMove`](../../lib/services/gesture_controller.dart#L81-L91). Extend its intent model with explicit left and right horizontal intents, or an equivalent direction-bearing intent. Keep the existing intent meanings unchanged:

- single tap: pause or resume;
- two-finger double tap: start or stop Detection;
- three-finger tap: quick scan;
- downward-dominant swipe: repeat the latest alert;
- horizontal-dominant swipe: request one relative primary-tab move.

The controller must classify the first committed directional intent for a one-pointer sequence and lock that sequence. A horizontal commit prevents a later downward repeat; a downward commit prevents a later horizontal navigation. A second pointer before directional commitment invalidates one-pointer directional classification, and pointer cancellation must suppress every delayed or directional action from that sequence. Existing two-finger double tap and three-finger tap recognition remains authoritative for their multi-pointer sequences; slight horizontal jitter during either gesture must never emit a relative primary-tab request.

Add one navigation callback with a relative direction parameter to [`EngineDetectionScreen`](../../lib/screens/engine_detection_screen.dart#L18-L36). [`AppShellState`](../../lib/navigation/app_shell.dart#L45-L169) supplies the callback; [`EngineDetectionScreen`](../../lib/screens/engine_detection_screen.dart#L101-L145) passes the same stable callback to both [`DetectionScreen`](../../lib/screens/detection_screen.dart#L53-L83) and [`UltralyticsDetectionScreen`](../../lib/screens/ultralytics_detection_screen.dart#L30-L59).

Each engine's existing [`_onGesture`](../../lib/screens/detection_screen.dart#L437-L448) and [`_onGesture`](../../lib/screens/ultralytics_detection_screen.dart#L369-L380) must map the new horizontal intents to that callback, while preserving the existing downward mapping to [`_repeatAlert`](../../lib/screens/detection_screen.dart#L374-L377) and [`_repeatAlert`](../../lib/screens/ultralytics_detection_screen.dart#L273-L276). The existing viewport-only [`GestureSurface`](../../lib/widgets/gesture_surface.dart#L25-L39) remains the only raw-pointer implementation.

Both engines must expose identical direction-to-callback behavior. The plan deliberately does not make the Ultralytics native view itself responsible for tab navigation; the Flutter overlay surface is the parity boundary.

## Detection State Preservation

Ordinary primary navigation must preserve the selected Detection engine, camera lifecycle, inference lifecycle, pause state, detected cards, and viewport state. This is already structurally possible because [`AppShellState`](../../lib/navigation/app_shell.dart#L45-L123) caches each visited page and displays them through [`IndexedStack`](../../lib/navigation/app_shell.dart#L135-L137).

Do not change page cache logic, insert an ordinary-navigation generation key, or recreate [`EngineDetectionScreen`](../../lib/screens/engine_detection_screen.dart#L18-L36) when a gesture moves away from or back to Detection. The newly injected navigation callback must have stable identity for the cached page lifetime.

The plan must preserve the existing, separate remount paths in [`EngineDetectionScreen`](../../lib/screens/engine_detection_screen.dart#L58-L67) and [`EngineDetectionScreen.build`](../../lib/screens/engine_detection_screen.dart#L101-L145): engine selection, fallback/recovery, and active-engine restart are allowed to remount via their existing generation keys. Gesture navigation must not add any new remount path or disguise an existing engine restart as navigation.

Tests must prove that leaving and returning to the Detection tab through primary navigation does not dispose or recreate the cached page. Engine switch/restart behavior is outside this feature's behavioral change but must remain covered by existing tests. [inferred-from-codebase]

## Secondary Route Isolation

The shell recognizer must not operate when an overlay or pushed route is topmost. The relevant current routes are:

- [`LogsReportsScreen`](../../lib/screens/logs_reports_screen.dart#L28-L143), pushed by [`openLogsReports`](../../lib/navigation/app_shell.dart#L77-L87);
- the Detection correction modal bottom sheet opened in [`detection_correction_sheet.dart`](../../lib/widgets/detection_correction_sheet.dart#L174).

The normal `Navigator` route stack and modal barrier should prevent the underlying shell body from receiving input while these routes are on top. [framework-verified] Verify this with a widget test and on a physical device rather than relying only on route layering.

In particular, horizontal interaction inside the route-local [`TabBarView`](../../lib/screens/logs_reports_screen.dart#L52-L100) must change only Logs & Reports content, never the primary [`_index`](../../lib/navigation/app_shell.dart#L46-L48). A modal correction interaction must likewise never invoke shell navigation.

## Accessible-Navigation Integration

Read [`MediaQuery.accessibleNavigationOf`](../../lib/navigation/app_shell.dart#L126-L168) from [`AppShellState.build`](../../lib/navigation/app_shell.dart#L126-L168). The installed Flutter framework source confirms this aspect-specific API rebuilds a dependent widget when the accessibility-navigation feature changes, and that `MaterialApp` maintains the relevant `MediaQuery` data. [framework-verified]

Calculate an effective bar-visibility value at build time:

| Persisted hide preference | Accessible-navigation mode | Effective bottom-bar visibility |
| --- | --- | --- |
| false | false | shown |
| true | false | hidden |
| false | true | shown |
| true | true | shown |

The implementation must rebuild the shell when either [`SettingsService`](../../lib/services/settings_service.dart#L60-L117) changes or the accessibility-navigation `MediaQuery` aspect changes. It must not write an accessibility override back to [`AppSettings`](../../lib/models/app_settings.dart#L61-L174) or [`SettingsService`](../../lib/services/settings_service.dart#L60-L117). When accessibility mode subsequently turns off, the persisted hide preference takes effect again.

The custom one-finger shell recognizer may remain mounted while accessibility-navigation mode is active, but EyeCue must not rely on it in that state. The forcibly visible semantic [`NavigationBar`](../../lib/navigation/app_shell.dart#L143-L165) is the authoritative primary-navigation path. Gesture-origin wayfinding speech is suppressed in accessibility-navigation mode; haptic behavior remains controlled by the existing vibration preference. [implementation choice]

## Persistent Navigation-Bar Preference

Add a non-nullable `hideBottomNavigation` field to [`AppSettings`](../../lib/models/app_settings.dart#L61-L174) with default `false`. Include it in the constructor, [`copyWith`](../../lib/models/app_settings.dart#L85-L103), JSON serialization, JSON parsing, equality, and hash code.

Existing persisted JSON that lacks the field must parse as `false`, so users keep the visible navigation bar after upgrading. The model already applies defensive parsing for older/malformed settings in [`AppSettings.fromJson`](../../lib/models/app_settings.dart#L119-L139); use that established pattern. A schema-version increment is appropriate only if the current schema convention requires every added optional field to increment its version; no explicit migration branch is currently present. [Needs Verification: persisted-schema versioning convention]

Add a read-only service getter and an asynchronous setter to [`SettingsService`](../../lib/services/settings_service.dart#L60-L117), following existing update methods and the immediate in-memory `notifyListeners` plus best-effort file write in [`_update`](../../lib/services/settings_service.dart#L107-L116).

Add a clearly labeled Settings control in the Preferences section of [`SettingsScreen`](../../lib/screens/settings_screen.dart#L71-L118). It must explain that hiding the bar does not remove destinations or swipe navigation, and that accessibility navigation keeps the bar visible. The control's displayed value represents the persisted preference, not the effective accessibility override.

## Haptic Wayfinding Integration

Use the injected [`HapticsService`](../../lib/services/haptics_service.dart#L9-L47) at the shell gesture-origin path only:

- successful relative navigation: [`lightTick`](../../lib/services/haptics_service.dart#L31-L34);
- committed boundary attempt: [`mediumTick`](../../lib/services/haptics_service.dart#L37-L40);
- no navigation / insufficient drag / cancellation: no haptic;
- routine navigation: never [`heavyTick`](../../lib/services/haptics_service.dart#L43-L46).

The service already gates feedback with the persisted vibration setting supplied from [`main.dart`](../../lib/main.dart#L15-L45), so no duplicate preference check belongs in the shell. Tests must inject recording callbacks into [`HapticsService`](../../lib/services/haptics_service.dart#L9-L47) and assert that navigation-bar taps, Home CTA navigation, and system Back do not produce gesture wayfinding feedback.

## TTS Wayfinding and Priority

Do not call the current general [`TtsService.speak`](../../lib/services/tts_service.dart#L112-L132) directly for destination or boundary feedback. It uses a global cooldown and replay state, and it records its input as the last utterance. That would allow a destination phrase to replace the Detection message replayed by [`repeatLast`](../../lib/services/tts_service.dart#L220-L224) and could contend with Detection announcements from [`announceDetections`](../../lib/services/tts_service.dart#L136-L164). [confirmed fact]

Add a narrow, explicit best-effort/drop-if-busy wayfinding API to [`TtsService`](../../lib/services/tts_service.dart#L64-L233), rather than a second TTS service. Its required policy is:

1. Return without speech when app audio is disabled or accessible-navigation mode is enabled.
2. Keep destination and boundary phrases separate from Detection replay state.
3. Use independent, minimal anti-repeat behavior for repeated boundary attempts and avoid a global cooldown that delays Detection announcements. Exact anti-repeat timing is implementation tuning under Product Decision 3, not a product-decision blocker or unresolved gate.
4. Never interrupt current Detection or critical/hazard speech to say navigation feedback.
5. Drop wayfinding speech when Detection speech is active or begins before it is sent; do not queue, coalesce, or delay Detection speech for wayfinding.
6. Preserve Detection replay state regardless of whether wayfinding is spoken or dropped.

Direct review confirms the current [`TtsService`](../../lib/services/tts_service.dart#L64-L233) has no speech queue, explicit priority type, or selective cancellation policy. That does **not** by itself justify a scheduler: first implement and test the smallest direct busy/replay guard that can drop wayfinding speech without mutating Detection state. Recommend scheduling complexity only if that direct review and its focused tests prove the guard cannot meet the non-interference policy. [confirmed fact; implementation choice]

Use concise fixed phrases supplied by the shell, such as destination names and a boundary phrase. Exact destination/boundary strings are implementation copy/tuning under Product Decision 3, not a product-decision blocker or unresolved gate. Native Android `stop`/queue behavior still requires device validation before interruption guarantees are treated as proven. [implementation choice; Needs Verification: Android TTS engine behavior]

## System Back Preservation

Preserve the existing primary-tab behavior in [`PopScope`](../../lib/navigation/app_shell.dart#L126-L168): Back from a non-Home primary tab returns to Home; Back from Home follows the platform's normal route/exit behavior.

Do not put Back behavior inside the gesture layer. A pushed secondary route must receive Back first. The required sequence is Settings → Logs & Reports → Back → Settings; only a subsequent Back from Settings returns to Home. [`openLogsReports`](../../lib/navigation/app_shell.dart#L77-L87) already pushes the secondary route through the same navigator, so this should be retained with a regression test. [inferred-from-codebase]

## Proposed Threshold/Tuning Strategy

Keep tuning values centralized and constructor-injectable where the existing pure [`GestureController`](../../lib/services/gesture_controller.dart#L24-L164) already supports injected timings/thresholds. Do not scatter magic values through the two Detection screens.

| Interaction | Initial implementation value | Commit rule | Evidence/status |
| --- | --- | --- | --- |
| Shell primary horizontal drag | Provisional/tunable; no final value set by this plan | Commit once on drag end only when absolute accumulated horizontal displacement meets the centrally configured provisional threshold | [implementation choice; Needs Verification: physical Android gesture tuning] |
| Detection downward repeat | Existing 80 logical pixels | Downward displacement must meet threshold and exceed horizontal displacement by the dominance ratio | Confirmed existing threshold in [`GestureController`](../../lib/services/gesture_controller.dart#L25-L32) |
| Detection horizontal move | Provisional/tunable; no final value set by this plan | Horizontal displacement must meet the centrally configured provisional threshold and exceed vertical displacement by the provisional dominance ratio | [implementation choice; Needs Verification: physical Android gesture tuning] |
| Directional dominance ratio | Provisional/tunable; no final value set by this plan | Dominant axis must exceed the other axis by the centrally configured provisional ratio; otherwise emit no directional intent | [implementation choice; Needs Verification: physical Android gesture tuning] |
| Existing tap / two-finger timings | 300 ms and 350 ms | Retain current values unless dedicated regression or device evidence requires a change | Confirmed in [`GestureController`](../../lib/services/gesture_controller.dart#L25-L32) |

The shell's recognizer should continue to rely on Flutter's device-aware drag acceptance and `MediaQuery` gesture settings for touch slop; any newly configured command-commit guard is provisional/tunable and is not a replacement for framework slop. Flutter source confirms the horizontal recognizer consults gesture settings. [framework-verified]

Every new horizontal threshold, displacement guard, and dominance-ratio value is provisional/tunable—not a final implementation requirement—and is subject to physical-device testing. The existing Detection downward threshold is the only confirmed threshold stated above. Physical-device tests must record false activations, missed gestures, diagonal classification, multi-pointer jitter, screen-edge conflicts, and TalkBack interaction before any new value is settled. [Needs Verification: target-device tuning]

## Automated Test Plan

Add/extend tests in the following order.

1. **Settings model and service** — Extend [`settings_service_test.dart`](../../test/services/settings_service_test.dart) to prove the default is visible-bar mode, a missing JSON field parses to `false`, the field round-trips through JSON, the service setter notifies listeners, and the in-memory store persists the choice.
2. **Shared Detection gesture state machine** — Extend [`gesture_controller_test.dart`](../../test/services/gesture_controller_test.dart#L27-L136) for left/right intents, one emitted action per pointer sequence, short-movement rejection, ambiguous-diagonal rejection, downward repeat preservation, horizontal/downward mutual exclusion, second-pointer invalidation, cancellation suppression, and reset behavior. Regress both the existing two-finger double tap and three-finger tap with slight horizontal jitter: they must retain their current Detection action and emit no horizontal intent.
3. **TTS best-effort wayfinding policy** — Extend [`tts_service_test.dart`](../../test/services/tts_service_test.dart) using the existing fake engine pattern to prove disabled audio suppresses wayfinding, accessible-navigation callers suppress wayfinding, a wayfinding phrase cannot replace Detection replay state, repeated boundaries apply the implementation-tuned anti-repeat rule, and active/pending Detection speech causes wayfinding to drop without interruption or delay. Add scheduler tests only if direct proof shows the minimal guard cannot satisfy that policy.
4. **Shell gesture navigation** — Extend [`app_shell_test.dart`](../../test/navigation/app_shell_test.dart#L38-L109) with body-only one-finger left/right drags across all four tabs, linear non-wrapping boundary attempts, one movement per physical swipe, second-pointer invalidation for the full sequence, no extra feedback from visible bar taps, CTA navigation, or Back, and cached-page preservation. Regress an in-progress shell drag joined by a second pointer so it cannot navigate even if the first pointer ends horizontally. At the integrated shell/Detection boundary, regress the existing two-finger double tap and three-finger tap with slight horizontal jitter and assert that neither changes the primary tab.
5. **Shell accessibility/bar truth table** — In [`app_shell_test.dart`](../../test/navigation/app_shell_test.dart#L38-L109), pump each persisted preference and `MediaQuery` accessibility combination, asserting the exact four-case visibility table, that a live accessibility change does not mutate the saved preference, and that the visible semantic [`NavigationBar`](../../lib/navigation/app_shell.dart#L143-L165) remains the tested authoritative primary-navigation path when accessibility navigation is on.
6. **Settings ownership regression** — In [`app_shell_test.dart`](../../test/navigation/app_shell_test.dart#L38-L109), navigate to the real Settings page, drag the actual [`Slider`](../../lib/screens/settings_screen.dart#L229-L306), assert its draft/persisted value changes, and assert the shell [`_index`](../../lib/navigation/app_shell.dart#L46-L48) remains Settings.
7. **Route and Back isolation** — Extend [`app_shell_test.dart`](../../test/navigation/app_shell_test.dart#L38-L109) to open Logs & Reports, exercise its route-local horizontal content, assert the primary selection does not change, then verify Back pops Logs & Reports to Settings before the next Back selects Home.
8. **Engine callback parity** — Add focused widget coverage only if required to prove both [`DetectionScreen`](../../lib/screens/detection_screen.dart#L53-L83) and [`UltralyticsDetectionScreen`](../../lib/screens/ultralytics_detection_screen.dart#L30-L59) forward shared horizontal intents through [`EngineDetectionScreen`](../../lib/screens/engine_detection_screen.dart#L101-L145). Prefer a small injected test seam over platform-camera or native-YOLO integration tests. [Needs Verification: current engine-widget test seam]

Run [`flutter analyze`](../../docs/testing-plan.md) with zero diagnostics and [`flutter test`](../../docs/testing-plan.md) after implementation. Test additions must preserve the project's existing no-camera shell test approach through [`pagesOverride`](../../lib/navigation/app_shell.dart#L20-L43).

## Physical-Device Test Plan

Use the supported physical Android device, not an emulator or web target, in line with the repository verification policy in [`ui-conventions.md`](../ui-conventions.md). Complete the following checks for both Custom and Ultralytics Detection engines where applicable:

1. With the bar shown, one-finger left/right swipes move linearly through Home, Detection, Settings, and Help; Home-right and Help-left remain in place.
2. Confirm one eligible one-finger physical drag causes at most one destination change, including fast and long swipes. Confirm that a second pointer joining at any point invalidates the entire sequence and yields no primary-tab navigation.
3. Confirm Home, Settings, and Help still scroll vertically; test clearly horizontal, vertical, and diagonal movements.
4. Drag the Settings sensitivity slider repeatedly; confirm the slider moves and the selected primary tab remains Settings.
5. Enable and disable the hide-bar preference; restart the app to verify persistence.
6. Toggle Android accessibility navigation/TalkBack state while the app is active; confirm the bar is forced visible without rewriting the preference, and that it hides again only when the persisted preference is true and accessibility mode is off. Confirm the visible semantic [`NavigationBar`](../../lib/navigation/app_shell.dart#L143-L165) is used as the authoritative primary-navigation path in this state; the retained custom recognizer is not relied upon.
7. With vibration enabled, verify a light successful-navigation tick and medium boundary tick; with vibration disabled, verify no haptic feedback.
8. With audio enabled and accessibility navigation off, verify concise destination/boundary speech; with audio disabled or accessibility navigation on, verify no wayfinding speech.
9. Trigger high-priority Detection speech near a navigation gesture; verify wayfinding speech drops rather than masks, interrupts, or delays the alert, and verify the repeat gesture still replays the Detection alert.
10. In both engine camera viewports, test left/right, down, diagonal, second-finger, and cancelled gestures; verify directional parity and that downward repeat still works. Specifically perform the existing two-finger double tap and three-finger tap with slight horizontal jitter; neither sequence may navigate a primary tab.
11. Open Logs & Reports from Settings, switch its local tabs horizontally, then Back to Settings; verify neither interaction changes the primary tab.
12. Exercise the Detection correction bottom sheet and verify its interactions cannot move the primary tab.
13. Test left/right swipes starting close to Android system gesture edges as well as safely inboard. Android may reserve system gesture insets and not deliver edge swipes to Flutter. [framework-verified]
14. Check device logs for framework exceptions, gesture conflicts, camera/inference restarts caused by ordinary navigation, and layout overflows.

## Risks / Edge Cases

- **Nested horizontal controls:** The Settings Slider and Logs & Reports [`TabBarView`](../../lib/screens/logs_reports_screen.dart#L52-L100) must retain their gesture ownership. Widget and device tests are mandatory because arena behavior is context-dependent.
- **Ambiguous diagonals:** Without dominance and commit guards, an intended vertical scroll/repeat could become tab navigation. The controller must reject ambiguous Detection diagonals; shell tuning requires device evidence.
- **Multi-pointer input:** Detection must invalidate one-finger directional classification when another pointer joins while preserving the existing two-finger double tap and three-finger tap. The shell must invalidate an entire primary-navigation pointer sequence when any second pointer joins; regress this with slight horizontal jitter. [implementation choice; Needs Verification: physical Android multi-pointer behavior]
- **Pointer cancellation:** Cancellation must clear directional/tap state without a delayed single tap, repeat, or navigation action.
- **System edge gestures:** Android system navigation may consume edge-origin swipes before Flutter receives them. This is not an application bug; test and document the inboard fallback behavior.
- **TTS ordering:** Current TTS has no explicit priority scheduler. Implementing destination speech without the planned best-effort/drop-if-busy guard would risk replay corruption and critical speech interference; do not introduce a scheduler unless direct implementation evidence proves the minimal guard inadequate.
- **Detection lifecycle:** The current engine coordinator legitimately remounts an engine on engine/fallback/restart changes. Ordinary tab navigation must not accidentally trigger this behavior.
- **Accessibility override:** Persisting the effective visibility instead of the user preference would make the bar remain visible or hidden incorrectly after an accessibility-state change.
- **Secondary routes and modal overlays:** The route stack should isolate underlying shell input, but this must be proven with the Logs route and correction sheet.

## Needs Verification

- **[Needs Verification: persisted-schema versioning convention]** Confirm whether a backward-compatible optional preference requires incrementing [`AppSettings.currentSchemaVersion`](../../lib/models/app_settings.dart#L61-L83), because the current parser supports missing fields but no explicit migration policy was found during this scoped audit.
- **[Needs Verification: physical Android gesture tuning]** Validate the provisional new horizontal thresholds, displacement guards, and dominance ratio; record diagonal behavior, touch distance, false activations, missed gestures, and system-edge conflicts before settling any value. The existing Detection downward threshold is already confirmed.
- **[Needs Verification: physical Android multi-pointer behavior]** After selecting an arena-aware recognizer that structurally enforces exactly one active pointer, validate its behavior on the target device. Test second-pointer arrival before and after horizontal movement begins, plus the existing two-finger double tap and three-finger tap with slight horizontal jitter. Physical-device testing verifies the behavior of the chosen implementation; it must not be relied upon to determine whether the implementation itself enforces the one-finger contract.
- **[Needs Verification: Android TTS engine behavior]** Validate the target TTS engine's handling of best-effort wayfinding while Detection speech is active or begins immediately afterward. The direct guard must drop wayfinding rather than interrupting or delaying Detection; native engine behavior cannot be inferred from Dart source.
- **[Needs Verification: current engine-widget test seam]** Confirm whether the existing test-mode/injected surfaces can instantiate both Detection engines without native camera/YOLO dependencies. If not, add only the smallest constructor-level test seam needed to prove callback parity.
- Exact destination/boundary strings and exact wayfinding anti-repeat timing are implementation copy/tuning under Product Decision 3. They are not product-decision blockers or unresolved verification gates. [implementation choice]

## Final Implementation Plan

1. Update [`AppSettings`](../../lib/models/app_settings.dart#L61-L174) with the persistent hide-bar field, default, copy, JSON, equality, and backward-compatible parse behavior. Decide and apply the schema-version treatment only after resolving the versioning verification item. Add model/service tests first so persistence semantics are fixed before UI integration.
2. Add the matching getter/setter to [`SettingsService`](../../lib/services/settings_service.dart#L60-L117), using the established synchronous listener notification and asynchronous file write path. Extend [`settings_service_test.dart`](../../test/services/settings_service_test.dart) for persistence and live notification.
3. Add the persisted-preference control to [`SettingsScreen`](../../lib/screens/settings_screen.dart#L71-L118). Keep it in Preferences, disclose its relationship to gestures/accessibility, and do not represent the temporary accessibility override as a saved-value change.
4. Extend [`TtsService`](../../lib/services/tts_service.dart#L64-L233) with the smallest explicit best-effort/drop-if-busy wayfinding guard that preserves Detection replay and never interrupts or delays Detection speech. Prove that guard with [`tts_service_test.dart`](../../test/services/tts_service_test.dart) before invoking it from navigation; recommend scheduling complexity only if direct review and those tests prove the guard cannot meet the policy.
5. Extend [`GestureController`](../../lib/services/gesture_controller.dart#L24-L164) with horizontal direction classification, provisional centralized tuning inputs, second-pointer/cancel handling, and sequence lockout, while preserving all existing non-navigation intents. Regress the existing two-finger double tap and three-finger tap with slight horizontal jitter so neither can emit a navigation intent. Add its pure unit tests in [`gesture_controller_test.dart`](../../test/services/gesture_controller_test.dart#L27-L136).
6. Add a relative-navigation callback parameter to [`EngineDetectionScreen`](../../lib/screens/engine_detection_screen.dart#L18-L36), propagate it unchanged to both engine widgets in [`EngineDetectionScreen.build`](../../lib/screens/engine_detection_screen.dart#L101-L145), and handle horizontal intents in both engine-local [`_onGesture`](../../lib/screens/detection_screen.dart#L437-L448) implementations. Do not alter engine-generation keys, camera setup, or inference lifecycle.
7. In [`AppShellState`](../../lib/navigation/app_shell.dart#L45-L169), add an arena-aware, body-only, one-finger primary horizontal gesture layer. Invalidate the full sequence if any second pointer joins, commit no more than once, preserve non-wrapping boundaries, and emit gesture-origin haptic/best-effort TTS feedback only for eligible navigation. Keep direct [`goToTab`](../../lib/navigation/app_shell.dart#L68-L74) free of gesture feedback and never add a shell-wide raw [`Listener`](../../lib/widgets/gesture_surface.dart#L27-L39).
8. In [`AppShellState.build`](../../lib/navigation/app_shell.dart#L126-L168), derive bottom-bar visibility from the persisted setting plus [`MediaQuery.accessibleNavigationOf`](../../lib/navigation/app_shell.dart#L126-L168). Subscribe to live settings updates without persisting the effective accessibility override. While accessible-navigation mode is active, retain the custom recognizer if desired but treat the forcibly visible semantic [`NavigationBar`](../../lib/navigation/app_shell.dart#L143-L165) as the authoritative primary-navigation path.
9. Extend [`app_shell_test.dart`](../../test/navigation/app_shell_test.dart#L38-L109) for one-finger gesture movement, boundaries, second-pointer invalidation, feedback origin, bar-visibility truth table, authoritative accessible-navigation bar interaction, real Slider ownership, cached Detection state, Logs route isolation, and Back order. Add an engine callback-parity test only if the existing seams cannot prove it.
10. Run static analysis and all automated tests, then complete the physical Android matrix before documenting verification results.
11. After implementation and verification, update the required behavior-change records in [`changelog.md`](../changelog.md), [`session-log.md`](../session-log.md), and [`implementation-progress.md`](../implementation-progress.md). Those documentation updates are future implementation-stage work; this planning stage intentionally changes only this file.

## Likely Files to Modify

| Classification | File | Reason |
| --- | --- | --- |
| Required application | [`app_settings.dart`](../../lib/models/app_settings.dart#L61-L174) | Persist the new preference and backward-compatible default. |
| Required application | [`settings_service.dart`](../../lib/services/settings_service.dart#L60-L117) | Expose live getter/setter and file persistence. |
| Required application | [`settings_screen.dart`](../../lib/screens/settings_screen.dart#L39-L195) | Add the user-facing persisted preference control. |
| Required application | [`tts_service.dart`](../../lib/services/tts_service.dart#L64-L233) | Add minimal best-effort/drop-if-busy wayfinding guarding that protects Detection speech/replay; introduce scheduling only if direct evidence proves it necessary. |
| Required application | [`gesture_controller.dart`](../../lib/services/gesture_controller.dart#L24-L164) | Add shared Detection directional classification and sequence safety. |
| Required application | [`engine_detection_screen.dart`](../../lib/screens/engine_detection_screen.dart#L18-L145) | Carry the shell relative-navigation callback to the active engine. |
| Required application | [`detection_screen.dart`](../../lib/screens/detection_screen.dart#L53-L83) | Forward Custom horizontal gesture intents to the shell callback. |
| Required application | [`ultralytics_detection_screen.dart`](../../lib/screens/ultralytics_detection_screen.dart#L30-L59) | Forward Ultralytics horizontal gesture intents to the shell callback. |
| Required application | [`app_shell.dart`](../../lib/navigation/app_shell.dart#L20-L169) | Own effective bar visibility, arena-aware primary navigation, feedback, and preserved Back behavior. |
| Required test | [`settings_service_test.dart`](../../test/services/settings_service_test.dart) | Verify persistence defaults, migration behavior, and notifications. |
| Required test | [`gesture_controller_test.dart`](../../test/services/gesture_controller_test.dart#L27-L136) | Verify direction, lockout, multi-pointer, diagonal, and cancellation behavior, including two-finger-double-tap and three-finger-tap jitter regressions. |
| Required test | [`tts_service_test.dart`](../../test/services/tts_service_test.dart) | Verify best-effort wayfinding cannot displace Detection replay or interrupt/delay protected Detection behavior. |
| Required test | [`app_shell_test.dart`](../../test/navigation/app_shell_test.dart#L38-L109) | Verify one-finger shell gestures, full-sequence second-pointer invalidation, accessibility-bar authority, Slider ownership, route isolation, Back, and feedback origin. |
| Test-only if existing seams are insufficient | New focused engine callback widget test under [`test`](../../test) | Prove Custom and Ultralytics callback parity without introducing native-camera integration dependencies. [Needs Verification: current engine-widget test seam] |
| Documentation-only after implementation | [`changelog.md`](../changelog.md), [`session-log.md`](../session-log.md), [`implementation-progress.md`](../implementation-progress.md) | Required behavior-change records after implementation and verification. |
| Planning artifact only in this stage | [`navigation-plan.md`](navigation-plan.md) | This source-of-truth plan; the only file changed during the current planning task. |

No dependency manifest, Android platform file, inference service, model, camera pipeline, or route package is expected to change for this feature.
