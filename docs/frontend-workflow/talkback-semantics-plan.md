# TalkBack Semantics Plan

**Stage:** 2 of 5 — Plan only. No code, test, or existing-doc edits. No `flutter analyze` / `flutter test` / builds were run.

**Upstream input:** [`talkback-semantics-analysis.md`](docs/frontend-workflow/talkback-semantics-analysis.md) (Stage 1) — its inventory §2, decisions D1–D6 §0, mechanism verification §3.1, de-duplication map §5, risk register §7, test map §8, doc obligations §9, open questions §10, and Appendix A contract.

**Design-spec:** intentionally skipped. The analysis records `Task type: semantics-only accessibility change, no visual output change expected`. Per [`.roo/rules/02-pipeline-stages.md`](.roo/rules/02-pipeline-stages.md) a design-spec runs only when visual output changes; this plan therefore works directly from the analysis. The one place where a *visual* change would be needed (`Swipe left to start!`, `press Start`, `custom EyeCue mode`) is deliberately excluded and carried as an open product decision (§8 Q2/Q3).

---

## 1. Scope statement

### In scope

1. **Operable Stop/Start** for TalkBack on the existing lifecycle card — no third control, no measured hold.
2. **Operable Repeat Last Alert** through a semantic action, reusing the existing `_repeatAlert()` verbatim.
3. **Removal of EyeCue-taught gesture vocabulary** from semantic `hint`/`value` (not from visible copy).
4. **Semantic de-duplication** so each duplicated visual text produces one stop (Home, Settings sliders, Logs & Reports, failure header).
5. **Corrected control identity/state** on the lifecycle card and Quick Scan card (label = action identity, value = state).
6. **Removal of one dead, unreachable user-facing surface** (`Use fallback`) — confirmed unreachable below.
7. Tests that encode the removed behaviour, plus new assertions for the added actions.

### Explicitly out of scope

| Excluded | One-line reason |
|---|---|
| Any change to `lib/services/` (incl. `tts_service.dart`) | `repeatLast()` and `_repeatAlert()` already exist; reuse only. Per [`.roo/rules/rules-frontend/01-scope.md`](.roo/rules/rules-frontend/01-scope.md) services are read-only for UI work. |
| Any change to `lib/models/` | Read-only for UI work; no model contract is needed. |
| `SemanticsSortKey` / `sortKey` | Analysis §6 proves traversal order is platform-owned and is not the defect. |
| Forcing spoken sentence order / announcement sequencing | Analysis §6 — TalkBack owns ordering and rendering. |
| `OrdinalSortKey`, `SemanticsService.announce` routing of detection speech | Application-domain TTS stays the audio channel (analysis §5.1). |
| `SwitchListTile` / `RadioListTile` semantics, chart semantics, `detection_information_overlay.dart`, `status_pill.dart`, `warning_banner.dart` | Analysis §5.1 and A7/A8 — already correct; changing them risks regressions. |
| `gesture_surface.dart`, `gesture_controller.dart`, `app_shell.dart`, primary gesture navigation | Physical gesture navigation is out of scope and has its own unresolved device issues. |
| `detection_correction_sheet.dart` | Unreachable from the normal UI — verified below — so its semantics are dead code this stage must not touch. |
| Visible-copy changes (`Swipe left to start!`, `press Start`, `custom EyeCue mode`) | Visual-output changes need a design-spec; carried as Q2/Q3. |
| Package name, SDK versions, Android config, dependencies, assets | No change is needed by any finding. |

### Reachability evidence used to bound scope

- `Use fallback`: `DetectionStatePanel(` has exactly **one** production construction, [`ultralytics_detection_screen.dart:1503-1509`](lib/screens/ultralytics_detection_screen.dart:1503), which passes only `onRetry` and `onStop`. `onFallback` is therefore never non-null in production, so the [`detection_state_panel.dart:104-109`](lib/widgets/detection_state_panel.dart:104) branch, its `'Use fallback'` label, and the parameter are dead.
- Correction sheet: `showDetectionCorrectionSheet` is called only from `_reportCorrection`, which is marked `// ignore: unused_element` and has no call site ([`ultralytics_detection_screen.dart:1176-1187`](lib/screens/ultralytics_detection_screen.dart:1176)). The sheet is unreachable in the normal UI.

### Preserved invariants (must not move)

- The locked two-card row: one lifecycle control + one Quick Scan control, no third visible control ([`test/screens/detection_redesign_parity_test.dart:234`](test/screens/detection_redesign_parity_test.dart:234), [`test/widgets/detection_action_controls_test.dart:66-77`](test/widgets/detection_action_controls_test.dart:66)).
- The three-second physical hold, its timers, `_progress`, `_holdAttempt`, and the `_consumed` one-shot lock.
- Quick Scan's `!_holding` gate and its `TAP`/`QUICK SCAN` visual copy.
- Every existing live-region flag (§4.5), per-frame non-live detections, application TTS/haptics/telemetry/saved settings.

---

## 2. Decision record

### 2.0 API verification (how each mechanism was confirmed)

**Context7 was unavailable during this pass** (`resolve-library-id` → `TypeError: fetch failed`), exactly as recorded in Stage 1 §0. Verification therefore used **the installed Flutter SDK source** (stronger than docs for the pinned toolchain), with the `api.flutter.dev` pages named as the cross-check reference:

- SDK location: [`.dart_tool/package_config.json:132`](.dart_tool/package_config.json:132) → `file:///C:/src/flutter/packages/flutter`.
- Channel/revision: [`.metadata:7-8`](.metadata:7) → `stable`, revision `c9a6c484230f8b5e408ec57be1ef71dee1e77020`.
- Dart constraint of this app: [`pubspec.yaml:7`](pubspec.yaml:7) → `>=3.12.0 <4.0.0`.
- Exact Flutter **version number** is `[needs-device-verification]`/unrecorded — no `C:/src/flutter/version` file exists. The revision above is the compile-time truth.
- Cross-check URLs (documentation, not executed): `https://api.flutter.dev/flutter/widgets/Semantics-class.html`, `…/widgets/SemanticsProperties/onLongPress.html`, `…/widgets/SemanticsProperties/hintOverrides.html`, `…/widgets/CustomSemanticsAction-class.html`, `…/material/Slider/semanticFormatterCallback.html`.

| API | Verified location | Verified fact | Status |
|---|---|---|---|
| `Semantics(onLongPress:)` | `packages/flutter/lib/src/widgets/basic.dart:7910` (`super.onLongPress`) | Exists on the widget constructor in the installed SDK | ✅ Verified |
| `SemanticsProperties.onLongPress` | `packages/flutter/lib/src/semantics/semantics.dart:1696`; doc `:2339-2341` | "VoiceOver users on iOS and TalkBack users on Android *may* trigger this action by double-tapping the screen without lifting the finger after the second tap" — i.e. a **discrete action**, not a measured hold, and delivery is platform-decided | ✅ Verified (delivery = device check, Q4) |
| `Semantics(customSemanticsActions:)` | `basic.dart:7930`; `semantics.dart:1718` | Exists on widget + properties | ✅ Verified |
| `CustomSemanticsAction({required String label})` | `semantics.dart:741` | Non-empty label asserted; appears as a labelled action | ✅ Verified |
| `SemanticsAction.customAction` auto-add | `semantics.dart:5926-5928` | "Whenever a custom accessibility action is added to a node, the action `SemanticsAction.customAction` is automatically added" | ✅ Verified |
| `SemanticsProperties.hintOverrides` | `semantics.dart:1686`, doc `:2255-2278` | "On Android, these overrides replace the default hints … instead of saying `Double tap to activate`, the screen reader will say `Double tap to <onTapHint>`"; "On iOS, this property is ignored"; "does not affect how the platform processes hints" | ✅ Verified |
| `SemanticsHintOverrides({onTapHint, onLongPressHint})` | `semantics.dart:1578-1603` | Only these two fields; non-empty asserted; `isNotEmpty` helper | ✅ Verified |
| `Semantics(onTapHint:, onLongPressHint:)` convenience params | `basic.dart:7904-7905` → mapped to `SemanticsHintOverrides` at `basic.dart:4230-4233` | Still present; **not deprecated** (the only `@Deprecated` members in that file are unrelated: `semantics.dart:1119, 1652, 1848, 3403, 6371`) | ✅ Verified |
| `hintOverrides` constraint check | `semantics.dart:1721-1745` (constructor asserts) | No assert ties `hintOverrides` to `onTap`/`textDirection`; safe to set `onLongPressHint` alone | ✅ Verified |
| `Slider.semanticFormatterCallback` | `packages/flutter/lib/src/material/slider.dart:187, 547-548`; applied `:1976-1983` | Exists; overrides `value`, `increasedValue`, `decreasedValue` only — the visible value-indicator bubble still uses `label` | ✅ Verified |
| Test support: long press | `packages/flutter_test/lib/src/controller.dart:430` | `tester.semantics.longPress(finder)` | ✅ Verified |
| Test support: custom action | `controller.dart:393-410` | `performAction(finder, SemanticsAction.customAction, args: <identifier>)`; throws if the action is absent unless `checkForAction: false` | ✅ Verified |
| Test support: matchers | `packages/flutter_test/lib/src/matchers.dart:726-751, 926, 3113-3140` | `matchesSemantics(hasLongPressAction:, customActions:, onTapHint:, onLongPressHint:)`; compares `SemanticsData.customSemanticsActionIds` | ✅ Verified |

**Important consequence of `hintOverrides` (verified at `semantics.dart:3843-3857` and `3914-3929`):** each hint override is registered as a `CustomSemanticsAction.overridingAction(hint:, action:)`. Those entries appear in `customSemanticsActionIds` with `label == null`. Any test that enumerates custom actions on the lifecycle card must filter to `action.label != null`, otherwise it will see the two override entries as unexpected actions.

### 2.1 D-A — Stop/Start mechanism

**Decision: `Semantics.onLongPress` on the existing lifecycle node, dispatching the same outcome mapping the completed physical hold uses. `customSemanticsActions` with `Stop detection`/`Start detection` is evaluated and rejected (documented fallback).**

Rationale (traced to analysis §3.1–§3.3):

1. It is the **only** additional action on a node that already has `onTap`; custom actions would make the primary control carry 3 operations (tap, long-press, custom) or 2 custom entries in the local context menu.
2. A custom action is reachable only through TalkBack's **local context menu** — strictly slower than the physical hold it replaces, and undiscoverable from the linear reading path. The long-press is delivered by the same double-tap-and-hold idiom as the physical gesture.
3. It adds **no widget**, so the locked two-card composition and every layout/parity assertion stay intact (analysis §3.3.3).
4. It is a **discrete action**: TalkBack's own timing decides when it fires, so no 3-second measurement is attempted and the timer code is untouched (analysis §3.3.1).
5. Safe against **synthesized pointer holds**: the existing `Listener` path treats a >`kLongPressTimeout` release as an abandoned hold with no action ([`detection_action_controls.dart:222-224`](lib/widgets/detection_action_controls.dart:222)), so a platform that synthesizes a real pointer cannot double-fire.

**Rejected alternative (documented fallback, Q4):** `customSemanticsActions: {CustomSemanticsAction('Stop detection'): onStop}` / `{'Start detection': onStart}`. Adopt only if the target TalkBack build proves `SemanticsAction.longPress` is not delivered.

**Per-state mapping (exact):**

| Outcome | `onTap` | `onLongPress` | `enabled` |
|---|---|---|---|
| `ready` | `_dispatchTap` (Pause) | `_dispatchSemanticHold` → `widget.onStop` | `_lifecycleEnabled && !_consumed` (unchanged) |
| `paused` | `_dispatchTap` (Resume) | `_dispatchSemanticHold` → `widget.onStop` | unchanged |
| `stopped` | **`null`** | `_dispatchSemanticHold` → `widget.onStart` | unchanged |
| `preparing` | `null` | `null` | `false` |
| `unavailable` | `null` | `null` | `false` |

**Handling of the existing `_dispatchTap` no-op for `stopped`:** `_dispatchTap` ([`detection_action_controls.dart:235-248`](lib/widgets/detection_action_controls.dart:235)) keeps its `stopped` branch **byte-identical**, because that method is still reached by the *physical* pointer-up path via `_endHold` ([`:227`](lib/widgets/detection_action_controls.dart:227)). Only the **semantic** exposure changes: the node stops advertising `onTap` for `stopped` so TalkBack cannot invoke a documented no-op. No code is deleted from `_dispatchTap`.

**New dispatch contract (`_dispatchSemanticHold`, new private method):**

- Early-return when `!_lifecycleEnabled || _holding || _consumed` — prevents a second lifecycle call if a semantic action arrives while a physical hold is counting down or after a completed hold locked the control.
- `switch` on `widget.outcome`: `ready`/`paused` → `widget.onStop?.call()`; `stopped` → `widget.onStart?.call()`; `preparing`/`unavailable` → no-op.
- **No** `setState`, **no** timer mutation, **no** `_progress`/`_holding`/`_holdAttempt`/`_consumed` write. It is a pure dispatch (analysis §3.2, §3.3.2).

**Known, intended asymmetry (must be stated in the comment, not "fixed"):** the semantic path stops/starts immediately; the physical path still requires three seconds. The hold exists to prevent accidental touch; a TalkBack double-tap-and-hold is not accidental.

### 2.2 D-B — Repeat Last Alert host

**Decision: keep the analysis's host (the audio pill) and implement it as `CustomSemanticsAction(label: 'Repeat last alert')` on an explicit `container` node; the pill's own `onTap` becomes the audio toggle. The wiring reuses `_repeatAlert()` verbatim.**

Evaluation against the brief's objection (hosting "repeat last alert" on the *audio* pill is semantically questionable):

| Candidate host | Availability | Discoverability | Verdict |
|---|---|---|---|
| **Audio pill** | Always — works while Ready, Paused, Stopped, and even Unavailable | TalkBack actions menu, labelled by its own string | **Selected.** The mismatch is mitigated because a custom action is announced by **its own `label`**, not by its host's name; and both the pill's tap and the repeat action concern the audio output channel. |
| Quick Scan card | Only while `ready` and never during a hold ([`detection_action_controls.dart:125-126`](lib/widgets/detection_action_controls.dart:125)) | same | **Rejected** — repeat is most useful precisely when nothing is being spoken (Paused/Stopped), and the card is disabled exactly then. |
| Lifecycle card | Enabled for ready/paused/stopped | same | **Rejected** — overloads the primary control and mixes audio into lifecycle (analysis §4.2 B). |
| New visible control | — | High | **Rejected** — breaks the locked two-card composition and needs a design-spec. |
| Viewport gesture surface | Always | same | **Rejected** — zero semantics today, bare `Listener` + per-frame overlay; risks pointer arbitration with `GestureController` (analysis §4.2 D). |

**Wiring constraints:** `onRepeatAlert: _repeatAlert` is passed at the existing call site ([`ultralytics_detection_screen.dart:1463-1469`](lib/screens/ultralytics_detection_screen.dart:1463)); the action calls the same method that `swipeDown` calls, so haptic + `TtsService.repeatLast()` behaviour, mute handling, and the 10-second validity window are unchanged. **No `lib/services/` edit, no new service logic.**

**Known behaviour gap (not silently fixed, Q5):** `repeatLast()` returns `false` silently when muted or when there is nothing to replay ([`tts_service.dart:688-694`](lib/services/tts_service.dart:688)). A blind user invoking the action may hear nothing. This is a product decision, and adding an announcement would require service/UI additions outside this plan's minimal scope.

### 2.3 D-C — Hint wording

**Decision: delete EyeCue's gesture teaching from `hint` everywhere; keep `hintOverrides` only on the lifecycle card, and only to name the *result* of each action.**

| Option | Verified cost | Verdict |
|---|---|---|
| Delete `hint` only | One-line removal per site; TalkBack appends its own platform hint | Needed, but insufficient alone |
| `hintOverrides.onTapHint` / `onLongPressHint` | Android-only wording replacement (`semantics.dart:2260-2265`); ignored on iOS | **Selected, lifecycle card only** |
| Keep `hint` but reword | Android voices `label – hint – button – hint` (`flutter/flutter#60436`) — still duplicated | Rejected |

Why `hintOverrides` is required on the lifecycle card specifically: after `hint` is removed, TalkBack would announce a tap affordance from the platform but would have **no way to learn that a long-press action exists**. `onLongPressHint` is the only mechanism that makes Stop/Start discoverable without teaching a gesture in EyeCue's own words — the string the plan supplies is a *result* (`stop detection`), and the platform supplies the gesture wording.

Deliberately **not** using `hintOverrides` for:

- **Quick Scan** — single action; the platform default hint is accurate.
- **`AccessibleButton`** — single action; `enabled: false` is the platform-correct disabled signal.
- **Audio pill** — the custom action carries its own label.

The exact strings supplied to `hintOverrides` contain no `double tap`, `hold`, or `swipe` tokens (§4). Nothing else in the plan relies on `hint` carrying information: everything essential moves into `label` or `value` (analysis §6).

---

## 3. Per-file change list

Ordered by implementation sequence. Every row traces to an analysis finding; no row is a speculative refactor.

### 3.1 Group A — shared primitives (change first; they ripple)

| File | Change concept | Exact symbols / lines | Rationale (analysis finding) |
|---|---|---|---|
| [`lib/widgets/accessible_button.dart`](lib/widgets/accessible_button.dart) | Remove all hint text; keep role/state/action | Delete the `hint: onPressed == null ? 'Unavailable' : 'Double tap to activate'` argument at [`accessible_button.dart:31`](lib/widgets/accessible_button.dart:31). Keep `button: true`, `label: label`, `enabled: onPressed != null`, `onTap: onPressed`, and `ExcludeSemantics(ElevatedButton.icon(...))` untouched. | §2.9 + §5 (`MERGE-LABEL`): "Android repeats the hint (#60436); `enabled: false` already conveys disablement." 27 call sites inherit the change. |
| [`lib/widgets/accessible_button.dart`](lib/widgets/accessible_button.dart) | **Disabled-reason contract decision** | **No new parameter.** Disabled callers get no hint. Enumerated disabled call sites (all have self-evident or adjacent state): `Start Detection` while `_starting` ([`ultralytics_detection_screen.dart:1691-1696`](lib/screens/ultralytics_detection_screen.dart:1691), adjacent `Starting detection…` text at `:1679`); `Choose model file…` while `_busy` and `Use built-in detector` while `_busy \|\| builtIn` ([`settings_screen.dart:758-772`](lib/screens/settings_screen.dart:758), model selection is visible in the same card); `Save JSON/CSV export` while `exporting` ([`logs_reports_screen.dart:1113-1122`](lib/screens/logs_reports_screen.dart:1113), adjacent `Saving export…` at `:1125-1132`); `Finish session`/`Upload session` while finishing/uploading ([`logs_reports_screen.dart:2167-2178`](lib/screens/logs_reports_screen.dart:2167)); `Upload trial` while uploading ([`logs_reports_screen.dart:2300-2304`](lib/screens/logs_reports_screen.dart:2300)). | §5 row `AccessibleButton`; analysis §2.9 shows the hint is the only injected string. A caller-supplied reason is Q6 (deferred; default = none). |
| [`lib/widgets/detection_action_controls.dart`](lib/widgets/detection_action_controls.dart) | Lifecycle node: identity/state contract, action exposure | In `_buildLifecycleControl` ([`:278-296`](lib/widgets/detection_action_controls.dart:278)): replace `label: _primaryLabel` with a new `_semanticLabel` getter; replace `value: secondary ?? _primaryLabel` with a new `_semanticValue` getter (**never** `_secondaryLabel`); delete `hint: hint`; add `onLongPress`; change `onTap` to the per-state mapping; add `hintOverrides` per state. Keep `button: true`, `enabled: enabled`, and the whole `ExcludeSemantics(Listener(...))` subtree byte-identical. | §2.1 (authoritative current contract) + §5 row lifecycle card (`MERGE-LABEL`) + Appendix A.1. |
| [`lib/widgets/detection_action_controls.dart`](lib/widgets/detection_action_controls.dart) | Remove instruction vocabulary from `value` | `_secondaryLabel` ([`:150-159`](lib/widgets/detection_action_controls.dart:150)) **stays for the visible secondary `Text` only** ([`:358-367`](lib/widgets/detection_action_controls.dart:358)); it must no longer feed `value`. During a physical hold the `value` therefore keeps reporting state instead of flipping to `KEEP HOLDING`. | §2.1 note: "a *state instruction* in the `value` slot, which TalkBack may announce on every focus event while the physical hold runs". |
| [`lib/widgets/detection_action_controls.dart`](lib/widgets/detection_action_controls.dart) | Stop `value == label` duplication in preparing/unavailable | `_semanticValue` returns `null` for `preparing`/`unavailable`; `_semanticLabel` carries the state (`Detection is preparing` / `Detection is unavailable`). | §2.1 row preparing/unavailable (`value` equals `label` today). |
| [`lib/widgets/detection_action_controls.dart`](lib/widgets/detection_action_controls.dart) | Delete the instruction-hint helper | Remove `_lifecycleHint()` ([`:379-395`](lib/widgets/detection_action_controls.dart:379)) and its call site (`final hint = _lifecycleHint();` at `:282`). | §2.1 row 4; §3.1 (`Semantics.hint` read in addition to the platform hint). |
| [`lib/widgets/detection_action_controls.dart`](lib/widgets/detection_action_controls.dart) | Add the semantic hold dispatch | New private method `_dispatchSemanticHold()` per §2.1 (guard `!_lifecycleEnabled \|\| _holding \|\| _consumed`; outcome switch; no state writes). | §3.2 recommendation; §3.3.2 constraint. |
| [`lib/widgets/detection_action_controls.dart`](lib/widgets/detection_action_controls.dart) | Quick Scan node: identity + reason wording | In `_buildQuickScanControl` ([`:401-408`](lib/widgets/detection_action_controls.dart:401)): `label: 'Quick scan the scene'`; `hint: enabled ? null : 'Available only while detection is ready'`; no `hintOverrides`; `onTap` unchanged. Keep `enabled`, the `ExcludeSemantics`, the `GestureDetector`, and the `!_holding` gate untouched. | §2.2 table + §5 (`MERGE-LABEL`, "keep the Ready-only reason only when disabled, without gesture wording"). |
| [`lib/widgets/detection_action_controls.dart`](lib/widgets/detection_action_controls.dart) | Post-hold hint coherence | Because `hint` is gone and `value` no longer flips to `KEEP HOLDING`, there is no instruction string left to become stale after a completed hold. `_consumed` still drives `enabled: false` and `onTap: null` exactly as today. | §2.1 "after completed hold" row. |

### 3.2 Group B — Detection screen

| File | Change concept | Exact symbols / lines | Rationale (analysis finding) |
|---|---|---|---|
| [`lib/screens/ultralytics_detection_screen.dart`](lib/screens/ultralytics_detection_screen.dart) | Make Repeat reachable; make the pill one explicit node | `_AudioPill` ([`:1745-1817`](lib/screens/ultralytics_detection_screen.dart:1745)): add `final VoidCallback? onRepeatAlert;` to the constructor and fields; change `Semantics(...)` to `container: true, button: true, enabled: true, label: 'Audio guidance, ${on ? 'on' : 'off'}', onTap: onPressed, customSemanticsActions: {const CustomSemanticsAction(label: 'Repeat last alert'): ?onRepeatAlert}`; wrap the `Tooltip` subtree in `ExcludeSemantics`. Pass `onRepeatAlert: _repeatAlert` at [`1463-1469`](lib/screens/ultralytics_detection_screen.dart:1463). Reuse `_repeatAlert()` ([`:1164-1167`](lib/screens/ultralytics_detection_screen.dart:1164)) unchanged. | §2.3 (pill inventory: no `container`, no `onTap`, tooltip adjacent) + §4.2/§4.3 (Option A) + §5 row audio pill. |
| [`lib/screens/ultralytics_detection_screen.dart`](lib/screens/ultralytics_detection_screen.dart) | Remove the duplicated failure string | Wrap the header `_modelError` `Text` ([`:1477-1483`](lib/screens/ultralytics_detection_screen.dart:1477)) in `ExcludeSemantics` (keep the widget, style, `maxLines`, ellipsis, and the `_modelError` assignment at `:1275` untouched). Keep it visible for sighted users. | §2.7 + §5 failure-path row: the header speaks the exact string `DetectionStatePanel` already speaks. |
| [`lib/screens/ultralytics_detection_screen.dart`](lib/screens/ultralytics_detection_screen.dart) | `Tooltip` overlap | Covered by the `ExcludeSemantics` over the `Tooltip` subtree above; the `Tooltip` message strings at [`:1466-1468`](lib/screens/ultralytics_detection_screen.dart:1466) are **not** changed (they remain the sighted long-press affordance). | §2.3 tooltip row. |
| [`lib/screens/ultralytics_detection_screen.dart`](lib/screens/ultralytics_detection_screen.dart) | Stale copy — **reported, not fixed** | `'Ultralytics mode uses the same model and thresholds as the custom EyeCue mode.'` ([`:1685-1689`](lib/screens/ultralytics_detection_screen.dart:1685)) and `'press Start…'` ([`:52-54`](lib/screens/ultralytics_detection_screen.dart:52)) stay as-is; carried to Q3. | §1 row 22 + §10 Q14: a copy change is a visual-output change. |
| [`lib/screens/ultralytics_detection_screen.dart`](lib/screens/ultralytics_detection_screen.dart) | **No other change** | No change to `_startDetection`/`_stopDetection`/`_pauseDetection`/`_resumeDetection`, the action-row wiring ([`:1709-1737`](lib/screens/ultralytics_detection_screen.dart:1709)), `StatusPill`, `GestureSurface`, or the gesture dispatch at [`:1319-1340`](lib/screens/ultralytics_detection_screen.dart:1319). | §7 risk register guard for this file. |

### 3.3 Group C — state panel

| File | Change concept | Exact symbols / lines | Rationale (analysis finding) |
|---|---|---|---|
| [`lib/widgets/detection_state_panel.dart`](lib/widgets/detection_state_panel.dart) | Remove the dead `Use fallback` path | Delete the `final VoidCallback? onFallback;` field ([`:20`](lib/widgets/detection_state_panel.dart:20)), the constructor parameter ([`:28`](lib/widgets/detection_state_panel.dart:28)), and the `if (onFallback != null) AccessibleButton(label: 'Use fallback', …)` block ([`:104-109`](lib/widgets/detection_state_panel.dart:104)). | Verified unreachable (§1). Removes a user-facing string that can never be produced and one more `AccessibleButton` instance. |
| [`lib/widgets/detection_state_panel.dart`](lib/widgets/detection_state_panel.dart) | **No contextual label change** | `'Retry'` and `'Stop'` labels stay. Group/title context is already provided by the container label `'$title. $message'` ([`:42-45`](lib/widgets/detection_state_panel.dart:42)), which precedes the buttons in traversal order. Renaming would change **visible** copy (the `label` is also the button text, [`accessible_button.dart:37-40`](lib/widgets/accessible_button.dart:37)). | §2.7 + Q3/Q14: a rename is a visual-output change. |
| [`lib/widgets/detection_state_panel.dart`](lib/widgets/detection_state_panel.dart) | Live-region decision (**conservative default**) | **Keep** `liveRegion: true` at [`:42-45`](lib/widgets/detection_state_panel.dart:42) and keep `StatusPill`'s live flag. Only the duplicated header `Text` is excluded (Group B). | §10 Q1 default is deferred to device evidence; keeping both flags loses **no** announcement and leaves `semantics_test.dart:269-313` valid. Analysis §8.2 also classifies those assertions as must-stay. See §8 Q1 for the contradiction this avoids. |

### 3.4 Group D — Home

| File | Change concept | Exact symbols / lines | Rationale (analysis finding) |
|---|---|---|---|
| [`lib/screens/home_screen.dart`](lib/screens/home_screen.dart) | One status node instead of three | Wrap the instruction headline `Text` ([`:221-228`](lib/screens/home_screen.dart:221)) and the supporting `Text` ([`:230-239`](lib/screens/home_screen.dart:230)) in `ExcludeSemantics`. Keep `Flexible`, `TextOverflow.ellipsis`, styles, and the excluded decorative rail ([`:243-251`](lib/screens/home_screen.dart:243)) unchanged. | §2.4 (badge `meaning` already concatenates headline + supporting) + §5 Home row (`EXCLUDE`). |
| [`lib/screens/home_screen.dart`](lib/screens/home_screen.dart) | Remove gesture-only wording from the semantic meaning | In `_homeStatusPresentation` ([`:280-336`](lib/screens/home_screen.dart:280)) change only the initial-idle `meaning` ([`:297-299`](lib/screens/home_screen.dart:297)) from `'Preparing. Swipe left to start! Detection begins immediately.'` to `'Preparing. Detection begins immediately.'`. **Visible** `headline: 'Swipe left to start!'` ([`:292`](lib/screens/home_screen.dart:292)) and `supporting` stay byte-identical. | §2.4 + §10 Q2. The gesture is not usable while TalkBack is active, so it must not be advertised as the action. No new claim is invented. |
| [`lib/screens/home_screen.dart`](lib/screens/home_screen.dart) | **Not changed** | `_StatusBadge` stays `container: true`, non-live, child excluded ([`:155-158`](lib/screens/home_screen.dart:155)); `kHome*` tokens, padding, dot, wordmark untouched. | §5 Home row + risk register (fixed non-scrollable composition). |

### 3.5 Group E — Settings

| File | Change concept | Exact symbols / lines | Rationale (analysis finding) |
|---|---|---|---|
| [`lib/screens/settings_screen.dart`](lib/screens/settings_screen.dart) | Advanced slider: one name + one adjustable control | Delete the label-only wrapper `Semantics(container: true, label: 'Advanced detection confidence threshold, …')` ([`:375-380`](lib/screens/settings_screen.dart:375)) and reparent its `Column` directly. Keep the title `Text` ([`:385-388`](lib/screens/settings_screen.dart:385)). Add `semanticFormatterCallback: (v) => v.toStringAsFixed(2)` to the `Slider` ([`:390-414`](lib/screens/settings_screen.dart:390)). Do not touch `onChanged`/`onChangeEnd`, `min`/`max`, `divisions`, or `label`. | §2.5 + §5 row (`REMOVE-WRAPPER` + formatter). |
| [`lib/screens/settings_screen.dart`](lib/screens/settings_screen.dart) | Detection cadence: fix the announced unit | Delete the wrapper ([`:524-526`](lib/screens/settings_screen.dart:524)); add `semanticFormatterCallback: (v) => '${v.round()} hertz'` to the `Slider` ([`:537-552`](lib/screens/settings_screen.dart:537)). Keep the disabled (`automatic`) `onChanged: null` gate. | §2.5 "differentiator defect": a 15–30 range is voiced as a percentage without a formatter. |
| [`lib/screens/settings_screen.dart`](lib/screens/settings_screen.dart) | Depth cadence: same, reason moves to the caption | Delete the wrapper ([`:556-561`](lib/screens/settings_screen.dart:556)); add `semanticFormatterCallback: (v) => '${v.round()} hertz'` ([`:577-591`](lib/screens/settings_screen.dart:577)); keep the disabled caption `Text` ([`:592-600`](lib/screens/settings_screen.dart:592)) as the explanation and keep its `depthDisabled` condition. | §5 row: "the caption is where the disablement reason belongs; it is already visible text." |
| [`lib/screens/settings_screen.dart`](lib/screens/settings_screen.dart) | **Not changed** | `SwitchListTile` ([`:512-523`](lib/screens/settings_screen.dart:512)), `RadioListTile` group ([`:362-371`](lib/screens/settings_screen.dart:362)), the live settings message ([`:722-734`](lib/screens/settings_screen.dart:722)), and section headings ([`:878-893`](lib/screens/settings_screen.dart:878)) stay as-is. | §5.1 `Must NOT change` + §2.5. |

### 3.6 Group F — Logs & Reports

| File | Change concept | Exact symbols / lines | Rationale (analysis finding) |
|---|---|---|---|
| [`lib/screens/logs_reports_screen.dart`](lib/screens/logs_reports_screen.dart) | Snackbar: one live node | In `_showMessage` ([`:352-366`](lib/screens/logs_reports_screen.dart:352)) wrap the child `Text(message)` in `ExcludeSemantics`; keep `container: true`, `liveRegion: true`, and `label: message`. | §2.6 snackbar row (`EXCLUDE`) — keeps the deliberate live region, removes the repeat. |
| [`lib/screens/logs_reports_screen.dart`](lib/screens/logs_reports_screen.dart) | Alert-latency section: heading + no duplicate title | In `_AlertLatencySection` ([`:907-919`](lib/screens/logs_reports_screen.dart:907)) add `header: true` to the existing `Semantics` and wrap the title `Text` ([`:914-919`](lib/screens/logs_reports_screen.dart:914)) in `ExcludeSemantics`. | §2.6 + §5 row (`EXCLUDE` + `HEADER`), matching the Settings card pattern ([`settings_screen.dart:878-893`](lib/screens/settings_screen.dart:878)). |
| [`lib/screens/logs_reports_screen.dart`](lib/screens/logs_reports_screen.dart) | Speech-latency note: remove the annotation wrapper | Delete the `Semantics(label: 'Per-engine speech latency — all detector models', …)` wrapper ([`:921-924`](lib/screens/logs_reports_screen.dart:921)); keep the `Text`. | §5 row (`REMOVE-WRAPPER`) — the `Text` already speaks. |
| [`lib/screens/logs_reports_screen.dart`](lib/screens/logs_reports_screen.dart) | Interval row: one stop per row | In `_AlertIntervalRow` ([`:1044-1058`](lib/screens/logs_reports_screen.dart:1044)) wrap both child `Text`s in one `ExcludeSemantics`; keep `label: '$label: $value'`. | §2.6 interval row (currently 3 stops). |
| [`lib/screens/logs_reports_screen.dart`](lib/screens/logs_reports_screen.dart) | Export section: heading + no duplicate | In `_ExportSection` ([`:1089-1101`](lib/screens/logs_reports_screen.dart:1089)) add `header: true`; wrap the title `Text` ([`:1096-1101`](lib/screens/logs_reports_screen.dart:1096)) in `ExcludeSemantics`. | §5 row. |
| [`lib/screens/logs_reports_screen.dart`](lib/screens/logs_reports_screen.dart) | Research upload / `_SectionHeading` / summary titles: promote to headings | Add `header: true` to every true section title: wrap the `'Research database upload'` `Text` ([`:1136-1143`](lib/screens/logs_reports_screen.dart:1136)) and convert `_SectionHeading` ([`:1703-1716`](lib/screens/logs_reports_screen.dart:1703)) to expose `Semantics(container: true, header: true, label: title, child: ExcludeSemantics(Text(...)))`. Leave the research-session **state** label ([`:2095-2100`](lib/screens/logs_reports_screen.dart:2095)) and the stored-session count ([`:2202-2204`](lib/screens/logs_reports_screen.dart:2202)) as non-headings. | §1 row 18 corrected: **no** `header: true` exists in this file today. |
| [`lib/screens/logs_reports_screen.dart`](lib/screens/logs_reports_screen.dart) | Corrections section: heading + no duplicate title | Add `header: true` to [`:1197-1199`](lib/screens/logs_reports_screen.dart:1197) and wrap the title `Text` ([`:1204-1209`](lib/screens/logs_reports_screen.dart:1204)) in `ExcludeSemantics`. | §5 row. |
| [`lib/screens/logs_reports_screen.dart`](lib/screens/logs_reports_screen.dart) | Correction row: one record, one stop | In `_CorrectionSummaryRow` ([`:1233-1245`](lib/screens/logs_reports_screen.dart:1233)) wrap the child `Text` in `ExcludeSemantics`; keep the comma-form `label`. | §2.6 "label (comma form) + Text (dot form)" duplication. |
| [`lib/screens/logs_reports_screen.dart`](lib/screens/logs_reports_screen.dart) | Model claim: remove the annotation wrapper | Delete the `Semantics(label: modelClaim, …)` wrapper ([`:1564-1573`](lib/screens/logs_reports_screen.dart:1564)); keep the `Text`. | §5 row (`REMOVE-WRAPPER`). |
| [`lib/screens/logs_reports_screen.dart`](lib/screens/logs_reports_screen.dart) | Research session card: exclude only the duplicated state | Keep `container: true` + `label: 'Research session: ${sessions.stateLabel}'` ([`:2088-2090`](lib/screens/logs_reports_screen.dart:2088)); wrap **only** the state `Text` ([`:2095-2100`](lib/screens/logs_reports_screen.dart:2095)) in `ExcludeSemantics`. Leave body/participant text as its own nodes. | §5 row (explicitly not a blanket exclusion). |
| [`lib/screens/logs_reports_screen.dart`](lib/screens/logs_reports_screen.dart) | **Not changed** | Priority dot ([`:1518-1521`](lib/screens/logs_reports_screen.dart:1518)) — already one node; the disabled export/upload buttons — see the `AccessibleButton` contract in §3.1. | §5 rows marked `LEAVE`. |

### 3.7 Group G — deliberately unchanged (recorded so implementation does not "improve" them)

| File | Status | Reason |
|---|---|---|
| [`lib/widgets/safety_disclosure.dart`](lib/widgets/safety_disclosure.dart) | **No change** | Analysis A8 verified it is already correct: grouped container, `header: true` title, excluded title, one node per point ([`safety_disclosure.dart:41-74`](lib/widgets/safety_disclosure.dart:41)). Its only semantic risk is the entry-time overlap between the live `WarningBanner` ([`:120-122`](lib/widgets/safety_disclosure.dart:120)) and the disclosure body, which is **device-only** (Q12). Adding a dialog *title* would be a visual change, so it is excluded. `AccessibleButton('I understand')` inherits the hint removal. |
| [`lib/widgets/detection_correction_sheet.dart`](lib/widgets/detection_correction_sheet.dart) | **Out of scope** | Unreachable from the normal UI (verified §1). Its node shape is already correct ([`:83-88`](lib/widgets/detection_correction_sheet.dart:83)). |
| [`lib/widgets/status_pill.dart`](lib/widgets/status_pill.dart), [`lib/widgets/warning_banner.dart`](lib/widgets/warning_banner.dart), [`lib/widgets/charts.dart`](lib/widgets/charts.dart), [`lib/widgets/detection_information_overlay.dart`](lib/widgets/detection_information_overlay.dart), [`lib/widgets/gesture_surface.dart`](lib/widgets/gesture_surface.dart) | **No change** | Deliberate live regions / already-correct single nodes / pointer-arbitration risk (analysis §5.1, A7). |

### 3.8 Group H — tests (see §5 for assertions)

| File | Change concept |
|---|---|
| [`test/widgets/detection_action_controls_test.dart`](test/widgets/detection_action_controls_test.dart) | Amend semantics assertions; add long-press/stop/start coverage |
| [`test/accessibility/semantics_test.dart`](test/accessibility/semantics_test.dart) | Amend `AccessibleButton`, Home meaning, slider, audio-pill, `Use fallback` expectations |
| `test/architecture/talkback_no_gesture_hints_test.dart` (**new**) | Source-level guard: no gesture teaching in semantic strings |
| [`test/screens/logs_reports_screen_test.dart`](test/screens/logs_reports_screen_test.dart) | Add de-duplication/`header` assertions using its existing real-screen harness |
| [`test/screens/gesture_navigation_direction_test.dart`](test/screens/gesture_navigation_direction_test.dart) **or** a sibling screen test | Add a real-`_AudioPill` semantics test using the existing screen harness |

### 3.9 Docs (post-verification stage only — listed, not edited here)

Per [`.roo/rules/rules-frontend/06-doc-update.md`](.roo/rules/rules-frontend/06-doc-update.md) and analysis §9:

| File | Required change |
|---|---|
| [`docs/app-only-implementation-plan.md:330`](docs/app-only-implementation-plan.md:330) | Criterion becomes true; state that Stop/Start and Repeat are reachable via semantics |
| [`docs/app-only-implementation-plan.md:331`](docs/app-only-implementation-plan.md:331) | Add the single-live-region-per-transition rule |
| [`docs/testing-plan.md:105`](docs/testing-plan.md:105) | Narrow the claim and name the device gate |
| [`docs/testing-plan.md:108`](docs/testing-plan.md:108) | No correction needed (analysis contradicts the brief); extend the row if the no-gesture-wording guard lands |
| [`docs/ui-conventions.md:62-81`](docs/ui-conventions.md:62-81) | Add the five accessibility bullets from analysis §9 |
| `.roo/rules/docs/ui-conventions.md` | Re-copy from root `/docs` after the edit; never edit independently |
| [`docs/thesis-product-status-audit.md:311`](docs/thesis-product-status-audit.md:311), `:316` | Rewrite the Detection row (single engine, two-card row, semantics contract) |
| [`docs/changelog.md`](docs/changelog.md), [`docs/session-log.md`](docs/session-log.md), [`docs/implementation-progress.md`](docs/implementation-progress.md), [`docs/project-status.md`](docs/project-status.md) | Add the change entry |

**Doc rot to report, not fix** (analysis §9): `detection-redesign-plan.md:9/120/208/422/540` and the always-on `.roo/rules/docs/architecture.md` still describe a removed second engine.

---

## 4. Target semantics contract (implementation-ready)

All `hint` values below contain **no** `double tap`, `hold`, or `swipe` tokens. Visible copy is unchanged everywhere.

### 4.1 Lifecycle card — [`detection_action_controls.dart:284-295`](lib/widgets/detection_action_controls.dart:284)

Common: `button: true`; `ExcludeSemantics` over the `Listener`; no `hint`; `enabled = _lifecycleEnabled && !_consumed`.

| Outcome | `label` | `value` | `hint` | `hintOverrides` | `onTap` | `onLongPress` | `enabled` |
|---|---|---|---|---|---|---|---|
| ready | `Pause detection` | `Detection is running` | `null` | `onTapHint: 'pause'`, `onLongPressHint: 'stop detection'` | `_dispatchTap` | `_dispatchSemanticHold` | `true` |
| paused | `Resume detection` | `Detection is paused` | `null` | `onTapHint: 'resume'`, `onLongPressHint: 'stop detection'` | `_dispatchTap` | `_dispatchSemanticHold` | `true` |
| stopped | `Start detection` | `Detection is stopped` | `null` | `onLongPressHint: 'start detection'` only | **`null`** | `_dispatchSemanticHold` | `true` |
| preparing | `Detection is preparing` | `null` | `null` | none | `null` | `null` | `false` |
| unavailable | `Detection is unavailable` | `null` | `null` | none | `null` | `null` | `false` |

During a physical hold: `label`, `value`, `hint`, `hintOverrides` are **unchanged** (the visible secondary `Text` still flips to `KEEP HOLDING` at the `kLongPressTimeout` boundary, [`detection_action_controls.dart:180-183`](lib/widgets/detection_action_controls.dart:180)). After a completed hold: `enabled` becomes `false` and both actions become `null` until the outcome changes (unchanged `_consumed` behaviour).

### 4.2 Quick Scan — [`detection_action_controls.dart:401-408`](lib/widgets/detection_action_controls.dart:401)

| State | `label` | `value` | `hint` | `hintOverrides` | `onTap` | `enabled` |
|---|---|---|---|---|---|---|
| ready (and not holding) | `Quick scan the scene` | `null` | `null` | none | `widget.onQuickScan` | `true` |
| any other outcome, or `_holding` | `Quick scan the scene` | `null` | `Available only while detection is ready` | none | `null` | `false` |

### 4.3 Audio pill — [`ultralytics_detection_screen.dart:1759-1762`](lib/screens/ultralytics_detection_screen.dart:1759)

| Property | Value |
|---|---|
| `container` | `true` |
| `button` | `true` |
| `enabled` | `true` |
| `label` | `Audio guidance, on` / `Audio guidance, off` (unchanged) |
| `value` | `null` |
| `hint` | `null` |
| `onTap` | `onPressed` (the audio toggle) |
| `customSemanticsActions` | `{ const CustomSemanticsAction(label: 'Repeat last alert'): onRepeatAlert }` (empty map when `onRepeatAlert == null`) |
| child | `ExcludeSemantics(Tooltip(…))` |

Deliberately **no** `toggled` flag (Q7: the label already carries state; `toggled` would add a second state phrase).

### 4.4 `AccessibleButton` — [`accessible_button.dart:27-33`](lib/widgets/accessible_button.dart:27)

| Property | Enabled | Disabled |
|---|---|---|
| `button` | `true` | `true` |
| `label` | caller label | caller label |
| `enabled` | `true` | `false` |
| `hint` | `null` | `null` |
| `onTap` | callback | `null` |
| child | `ExcludeSemantics(ElevatedButton.icon)` | same |

### 4.5 Surfaces that keep their current semantics

| Surface | Kept |
|---|---|
| `StatusPill` | `container: true`, `liveRegion: true`, `label: 'Detection status: X'` |
| `WarningBanner` | `container: true`, `liveRegion: true`, `label: 'Warning. X'` |
| `DetectionStatePanel` | `container: true`, `liveRegion: true`, `label: '$title. $message'`, excluded children, `Retry`/`Stop` buttons |
| Settings live message, Logs snackbar | `liveRegion: true` retained; only their duplicated inner `Text` is excluded |
| Detection overlay rows, `DetectionCard`, charts | non-live, single node, child excluded |
| Model-change notice | `liveRegion: true` retained |
| Home status badge | `container: true`, non-live, child excluded |
| Settings switches / radios / section headings | framework-owned / already `header: true` |

---

## 5. Test plan

### 5.1 Assertions that currently encode the removed behaviour (must be amended)

| Location | Current assertion | Replace with |
|---|---|---|
| [`test/widgets/detection_action_controls_test.dart:431`](test/widgets/detection_action_controls_test.dart:431) | `node.hint` contains `'Hold for three seconds to stop'` | `data.hasAction(SemanticsAction.longPress)` is `true`; `node.hint` is `null`/empty; `data.hasAction(SemanticsAction.tap)` is `true` |
| [`test/widgets/detection_action_controls_test.dart:448-449`](test/widgets/detection_action_controls_test.dart:448) | `hasAction(tap)` is `true` **and** hint contains `'Hold for three seconds to start'` | `hasAction(tap)` is **`false`**; `hasAction(longPress)` is `true`; hint null |
| [`test/widgets/detection_action_controls_test.dart:465`](test/widgets/detection_action_controls_test.dart:465) | `node.hint == 'Detection is preparing'` | hint null; `node.label == 'Detection is preparing'`; `value` empty; no tap/long-press actions |
| [`test/widgets/detection_action_controls_test.dart:481`](test/widgets/detection_action_controls_test.dart:481) | `node.hint == 'Detection is unavailable'` | same shape as preparing, with the unavailable label |
| [`test/widgets/detection_action_controls_test.dart:492`](test/widgets/detection_action_controls_test.dart:492), [`:507`](test/widgets/detection_action_controls_test.dart:507) | `nodeFor(tester, 'QUICK SCAN')` | `nodeFor(tester, 'Quick scan the scene')`; enabled case also asserts hint null |
| [`test/widgets/detection_action_controls_test.dart:513`](test/widgets/detection_action_controls_test.dart:513) | hint contains `'available only while detection is ready'` | hint equals `'Available only while detection is ready'` (no gesture verb) |
| [`test/widgets/detection_action_controls_test.dart:426`](test/widgets/detection_action_controls_test.dart:426), [`:442`](test/widgets/detection_action_controls_test.dart:442), [`:460`](test/widgets/detection_action_controls_test.dart:460), [`:476`](test/widgets/detection_action_controls_test.dart:476) | `nodeFor` labels `PAUSE`/`START`/`PREPARING`/`UNAVAILABLE` | `Pause detection` / `Start detection` / `Detection is preparing` / `Detection is unavailable` |
| [`test/widgets/detection_action_controls_test.dart:529`](test/widgets/detection_action_controls_test.dart:529), [`:547`](test/widgets/detection_action_controls_test.dart:547), [`:563`](test/widgets/detection_action_controls_test.dart:563) | `byLabel('PAUSE'/'RESUME'/'START')` for tap dispatch | `byLabel('Pause detection'/'Resume detection'/'Start detection')`; the stopped case must now use `SemanticsAction.longPress`, not `tap` |
| [`test/accessibility/semantics_test.dart:140-143`](test/accessibility/semantics_test.dart:140) | `hint == 'Double tap to activate'` | hint is null; `button`/`enabled`/`tap` still asserted |
| [`test/accessibility/semantics_test.dart:156-158`](test/accessibility/semantics_test.dart:156) | `hint == 'Unavailable'` | hint is null; keep `enabled: false`, no tap |
| [`test/accessibility/semantics_test.dart:301-307`](test/accessibility/semantics_test.dart:301) | Asserts/taps `'Use fallback'` | Delete the fallback expectations (path removed); keep `Retry`/`Stop` |
| [`test/accessibility/semantics_test.dart:207-227`](test/accessibility/semantics_test.dart:207) | Pumps a hand-built `Semantics` stand-in for the audio pill | Exercise the **real** pill through the existing real-screen harness ([`gesture_navigation_direction_test.dart:149-172`](test/screens/gesture_navigation_direction_test.dart:149)); assert one node labelled `Audio guidance, on`, `tap` present, and a custom action labelled `Repeat last alert` |
| [`test/accessibility/semantics_test.dart:894-911`](test/accessibility/semantics_test.dart:894) | Wrapper label `^Advanced detection confidence threshold, 0\.25` + slider node `0.25` | Assert the title `Text` node (`Advanced threshold: 0.25`) and the slider node (`0.25`) separately; keep `increase`/`decrease` and `isSlider` |
| [`test/accessibility/semantics_test.dart:477-479`](test/accessibility/semantics_test.dart:477) | Home meaning `'Preparing. Swipe left to start! Detection begins immediately.'` | `'Preparing. Detection begins immediately.'` |
| [`test/widget_test.dart:520-540`](test/widget_test.dart:520) | Audio-pill stand-in | Same treatment as above (or delete in favour of the real-screen test) |

**Keep exactly as-is** (regression tripwires): two-control/one-`GestureDetector` composition ([`detection_action_controls_test.dart:66-77`](test/widgets/detection_action_controls_test.dart:66)); visible copy per outcome ([`:81-99`](test/widgets/detection_action_controls_test.dart:81)); the entire hold-timing/progress/`KEEP HOLDING`/single-dispatch/cancellation group ([`:250-408`](test/widgets/detection_action_controls_test.dart:250)); live regions ([`semantics_test.dart:161-181`](test/accessibility/semantics_test.dart:161), [`:269-313`](test/accessibility/semantics_test.dart:269)); non-live detection card and charts ([`:196-205`](test/accessibility/semantics_test.dart:196), [`:316-375`](test/accessibility/semantics_test.dart:316)); switch/radio/heading semantics ([`:755-892`](test/accessibility/semantics_test.dart:755)); 200% text-scale groups ([`:229-253`](test/accessibility/semantics_test.dart:229), [`:407-457`](test/accessibility/semantics_test.dart:407), [`:553-576`](test/accessibility/semantics_test.dart:553), [`:684-702`](test/accessibility/semantics_test.dart:684), [`:965-988`](test/accessibility/semantics_test.dart:965)); `find.text('Swipe left to start!')` ([`widget_test.dart:38`](test/widget_test.dart:38)) and the visible `PAUSE`/`QUICK SCAN` parity assertions.

### 5.2 New assertions

| # | Intent | Where | Expected node count / shape |
|---|---|---|---|
| N1 | Ready long-press stops once, and does **not** pause/resume | `detection_action_controls_test.dart`, new `group('TalkBack long press')` | `tester.semantics.longPress(...)` → `recorder.stop == 1`, `recorder.pause == 0` |
| N2 | Paused long-press stops once | same | `stop == 1`, `resume == 0` |
| N3 | Stopped long-press starts once; stopped node has **no** tap | same | `start == 1`; `data.hasAction(SemanticsAction.tap)` is `false` |
| N4 | Preparing/unavailable expose **no** long press | same | `data.hasAction(SemanticsAction.longPress)` is `false` for both |
| N5 | A semantic long-press never mutates hold state | same | After `longPress`, pump 0 ms: no progress fill, `enabled` still `true` for ready (i.e. `_consumed` untouched) |
| N6 | Audio pill: one node, tap + labelled custom action, callback fires once | real-screen test on `UltralyticsDetectionScreen` | exactly one node labelled `Audio guidance, on`; `tap` present; `customSemanticsActionIds` → labels filtered to non-null contain exactly `Repeat last alert`; `performAction(..., SemanticsAction.customAction, args: id)` → haptic `medium` recorded once and `tts.repeatLast` called once |
| N7 | Home: one status node, no independent instruction stops | `semantics_test.dart` | `find.semantics.byLabel('Preparing. Detection begins immediately.')` finds one; `find.semantics.byLabel(RegExp('Ready when you are'))` empty for other states' instructions; `find.text('Swipe left to start!')` still finds one |
| N8 | Settings: each slider yields a name node + an adjustable node, and the cadence value is not a percentage | `semantics_test.dart` | No node labelled `Detector cadence target, …`; slider node `value` matches `RegExp(r'^\d+ hertz$')`; `increase`/`decrease` present |
| N9 | Logs & Reports: one stop per de-duplicated site, section titles are headings | `logs_reports_screen_test.dart` (existing real-screen harness at `:206-240`) | `header` flag set on each section title; `_AlertIntervalRow` produces exactly one node whose label contains `p50`; no node whose label is `Offline telemetry export` **and** a second text stop for the same string |
| N10 | No semantic string in `lib/` teaches a gesture | **new** `test/architecture/talkback_no_gesture_hints_test.dart` | Source scan (mirroring [`no_custom_engine_test.dart:1-40`](test/architecture/no_custom_engine_test.dart:1)) over `lib/**/*.dart` rejecting the literal tokens `'Double tap`, `'Hold for three`, and `'Swipe left to start! Detection` (the concatenated semantic-meaning form). Visible copy (`HOLD 3 SEC…`, `Swipe left to start!` as a headline) is unaffected by these patterns |
| N11 | `AccessibleButton` exposes no hint in either state | `semantics_test.dart` | enabled → `button`+`enabled`+`tap`, hint null; disabled → `button`+`disabled`, no `tap`, hint null |

**Test-authoring trap (from §2.0):** the lifecycle node will report `SemanticsAction.customAction` **not** because of a custom action but because `hintOverrides` registers two `overridingAction` entries. Custom-action assertions belong on the audio pill, and any enumeration must filter `action.label != null`.

**Pass criteria:** `flutter analyze` → 0 issues; `flutter test` → all tests pass (currently 343 passing per [`docs/testing-plan.md`](docs/testing-plan.md)); every amended assertion above reflects the new contract; no test is deleted except the `Use fallback` expectations and the two audio-pill stand-ins that are replaced by real-widget coverage.

---

## 6. Verification plan

### 6.1 Static / automated (implementation stage)

| Command | Expected |
|---|---|
| `flutter analyze` | `No issues found!` |
| `flutter test` | All tests pass; the amended + new tests above included |
| `flutter test test/widgets/detection_action_controls_test.dart test/accessibility/semantics_test.dart test/architecture/talkback_no_gesture_hints_test.dart` | Focused run for the changed surface |
| `flutter build apk --debug` | Succeeds (no dependency or Gradle change is expected by this plan) |

### 6.2 Physical-device checklist (Android, TalkBack on)

Build a debug APK, install on the target device (Snapdragon 695 / API 33 per project docs), enable TalkBack, and walk the app. Nothing below can be proven by widget tests.

| # | Precondition | Action | Expected | Evidence | Blocking? |
|---|---|---|---|---|---|
| V1 | Detection Ready | Focus the lifecycle card, double-tap and hold | Stop fires once; no Pause; TTS/haptics match a physical Stop | Screen recording + logcat + telemetry `Detection stopped` | **Yes** (Q4) — if it does not fire, apply the §2.1 fallback |
| V2 | Detection Stopped | Focus the card, double-tap and hold | Start fires once | Recording | **Yes** |
| V3 | Detection Paused | Focus the card | Node reads identity + state, and a long-press hint is announced | Recording | No |
| V4 | Detection Stopped | Focus the card, double-tap | No action (no tap action exposed) | Recording | No |
| V5 | Any | Read any button | No EyeCue hint is spoken, and the platform hint is **not** duplicated (`label – hint – … – hint`) | Recording | No |
| V6 | Any | Compare Ready/Paused announcements | The long-press result wording appears once, not twice | Recording | No |
| V7 | Ready | Focus Quick Scan | Reads as one node; disabled state (Paused) does not add a second gesture phrase | Recording | No |
| V8 | Any | Open the TalkBack actions menu on the audio pill | Exactly one entry: `Repeat last alert`; invoking it replays the last alert | Recording | **Yes** (Q5 silent-repeat is excluded from pass criteria) |
| V9 | Audio off, then on | Focus the pill | Never reads `Ticked/On` (no `toggled` flag); reads `Audio guidance, off/on` | Recording | No (Q7) |
| V10 | Any | Focus the pill | No duplicated tooltip text and no second node after the label | Recording | No (Q8) |
| V11 | Detection failed | Trigger a failure | Failure is announced; the same message is not read from the header `Text` afterwards | Recording | No (Q1) |
| V12 | First launch | Open Settings, focus a slider, swipe up/down | Cadence sliders announce `… hertz`; the visible bubble still shows `15 Hz` | Recording | No (Q9) |
| V13 | Settings | Focus the advanced slider title, then the slider | Two stops only (name, then adjustable), no repeated value | Recording | No (Q10) |
| V14 | Logs & Reports, Overview/Charts/Logs | Traverse each section | Section titles announce as headings; no string read twice; one stop per interval row | Recording | No |
| V15 | Home, auto-start OFF | Focus the status area | One status node; `Swipe left to start` is not spoken | Recording | No |
| V16 | Stop, then Start | After the outcome changes, check focus | Focus stays on the lifecycle card; the new label/value is announced once | Recording | No (Q11) |
| V17 | Detection conversationally active | Trigger detecting → paused → ready repeatedly | No announcement storm from the status live region | Recording (30 s) | No (Q12) |
| V18 | First launch | Open the safety dialog | Exactly one announcement on entry (banner **or** body), not two | Recording | No (Q13) |
| V19 | Any | Compare TTS and TalkBack during Pause/Resume/Stop | Both channels' behaviour is recorded for the product decision; no change is made by this plan | Recording | No (Q14) |
| V20 | Any | Run 5 minutes with TalkBack on | No RenderFlex overflow, no exception; camera preview does not hitch | logcat + recording | **Yes** (regression gate) |

Blocking items (V1, V2, V8, V20) must pass before the change is considered verified; the rest are recorded observations for follow-up.

---

## 7. Rollback / risk

Per-file: what must not change, how a regression shows up, and which existing test catches it.

| File | Must not change | How a regression appears | Protected by |
|---|---|---|---|
| [`lib/widgets/detection_action_controls.dart`](lib/widgets/detection_action_controls.dart) | `_startHold`/`_completeHold`/`_endHold`/`_cancelHold`, the three timers, `_progress`, `_holding`, `_holdAttempt`, `_consumed`, the `Listener`, the visible `Text`s, `ExcludeSemantics`, the two-card `Row` | Hold stops completing, progress restarts at `kLongPressTimeout`, double dispatch, missing progress fill, Quick Scan tappable mid-hold | [`detection_action_controls_test.dart:66-99`](test/widgets/detection_action_controls_test.dart:66), [`:250-408`](test/widgets/detection_action_controls_test.dart:250), [`detection_redesign_parity_test.dart:250-252`](test/screens/detection_redesign_parity_test.dart:250), [`detection_screen_layout_test.dart:107-110`](test/screens/detection_screen_layout_test.dart:107) |
| [`lib/widgets/accessible_button.dart`](lib/widgets/accessible_button.dart) | `onTap`, `enabled`, the `ExcludeSemantics` child, `minimumSize`, colours | A button stops responding to TalkBack or loses its enabled state across 27 sites | [`semantics_test.dart:126-159`](test/accessibility/semantics_test.dart:126) plus every screen smoke test |
| [`lib/screens/ultralytics_detection_screen.dart`](lib/screens/ultralytics_detection_screen.dart) | `_startDetection`/`_stopDetection`/`_pauseDetection`/`_resumeDetection`, the action-row wiring, `StatusPill`, `GestureSurface`, gesture dispatch, `_toggleAudio` | Double haptics/TTS on Repeat; audio toggle stops working; swipe gestures break; header error visible but unread (semantics-only exclusion) | [`gesture_navigation_direction_test.dart`](test/screens/gesture_navigation_direction_test.dart), [`ultralytics_detection_readiness_test.dart`](test/screens/ultralytics_detection_readiness_test.dart) |
| [`lib/screens/home_screen.dart`](lib/screens/home_screen.dart) | Fixed non-scrollable composition, `Flexible` + ellipsis, decorative rail, badge node | Layout overflow at 200% text scale; status read twice or not at all | [`semantics_test.dart:229-253`](test/accessibility/semantics_test.dart:229), [`:459-551`](test/accessibility/semantics_test.dart:459), [`widget_test.dart:30-45`](test/widget_test.dart:30) |
| [`lib/screens/settings_screen.dart`](lib/screens/settings_screen.dart) | `onChanged`/`onChangeEnd`, `_draft`/`_detectionDraft`/`_depthDraft`, persistence calls, switches/radios/headings | A slider stops persisting, or the draft/persisted value diverges | [`settings_screen_cadence_test.dart`](test/screens/settings_screen_cadence_test.dart), [`settings_service_test.dart`](test/services/settings_service_test.dart), [`semantics_test.dart:755-892`](test/accessibility/semantics_test.dart:755) |
| [`lib/screens/logs_reports_screen.dart`](lib/screens/logs_reports_screen.dart) | Every live region, every data-bearing `Text`, export/upload callbacks, tab behaviour | Data silently disappears from the tree; a snackbar stops being announced; export buttons stop working | [`logs_reports_screen_test.dart`](test/screens/logs_reports_screen_test.dart), [`semantics_test.dart:316-375`](test/accessibility/semantics_test.dart:316) |
| [`lib/widgets/detection_state_panel.dart`](lib/widgets/detection_state_panel.dart) | Live region, container label, `Retry`/`Stop` callbacks, exclusion of title/message | Failure stops being announced, or the user can no longer retry/stop | [`semantics_test.dart:269-313`](test/accessibility/semantics_test.dart:269) |

**Global rollback:** every change is additive/removal of semantics properties or `ExcludeSemantics` wrappers, except the dead `onFallback` removal. Reverting a single file cannot affect another file's behaviour because no shared widget contract is narrowed (the only API change is the removal of an unused optional parameter).

**Out-of-scope leak check:** the plan adds no dependency, no service, no model, no Android/Gradle change, no asset, and no new visible control. If implementation finds that a change requires `lib/services/` (e.g. a silent-failure signal for Repeat), it must **stop and flag** it as a scope exception rather than proceed.

---

## 8. Open Questions / Needs Verification

| # | Item | Tag | Default assumed if unanswered |
|---|---|---|---|
| Q1 | Does the target TalkBack build deliver `SemanticsAction.longPress` to a `Semantics(onLongPress:)` node, or a synthesized raw long-press? (`flutter/flutter#35112` records platform inconsistency.) | `[needs-device-verification]` | Ship `onLongPress`; if V1/V2 fail, switch to `customSemanticsActions` with `Stop detection`/`Start detection` (labels already agreed in §2.1) |
| Q2 | Should Home copy `Swipe left to start!` be reworded in the **visible** UI (auto-start OFF)? This plan only removes it from the semantic meaning. | `[product-decision]` | Keep visible copy; semantic meaning becomes `Preparing. Detection begins immediately.` |
| Q3 | Should the stale visible copy (`custom EyeCue mode`, `press Start`) be rewritten? | `[product-decision]` | No change; out of scope for a semantics-only stage; schedule separately |
| Q4 | Single-live-region decision for the failure path: keep `StatusPill` + `DetectionStatePanel` both live (chosen), or drop one? | `[product-decision]` | Keep both live; only the duplicated header `_modelError` text is excluded. **Note the analysis contradiction:** §8.2 lists `semantics_test.dart:269-313` as must-stay while §10 Q1 recommends dropping the panel's live flag. The conservative default preserves both the tests and the automatic safety announcement |
| Q5 | Silent Repeat: `repeatLast()` returns `false` with no audible/haptic signal when muted or when nothing is cached. | `[product-decision]` | Out of scope (would need a service change → scope exception); record as a known gap |
| Q6 | Should `AccessibleButton` accept a caller-supplied disabled reason instead of no hint? | `[product-decision]` | No new parameter; `enabled: false` only |
| Q7 | Is `toggled` wanted on the audio pill (may produce a second state phrase alongside `on`/`off`)? | `[product-decision]` | No `toggled`; label carries state |
| Q8 | Does the pill's effective node merge correctly once it becomes `container: true` with `ExcludeSemantics(Tooltip)` — and does TalkBack read the tooltip? | `[needs-device-verification]` | Assume one node and no tooltip speech; verify V10 |
| Q9 | Do the cadence sliders announce as percentages today, and does `semanticFormatterCallback` leave the visible bubble untouched? | `[needs-device-verification]` | Add the formatter; verify V12 |
| Q10 | After removing the label-only `Semantics` wrapper, does the slider settle at exactly two stops, or can title + slider merge into one? | `[needs-device-verification]` | Two stops (name, adjustable); do **not** adopt `MergeSemantics` without evidence |
| Q11 | Where does TalkBack focus land after the lifecycle outcome changes and label/value swap? | `[needs-device-verification]` | Assume focus is retained on the node; verify V16 |
| Q12 | Live-region churn during recovery flapping (Preparing ↔ Ready). | `[needs-device-verification]` | No change in this stage; observe V17 |
| Q13 | Does the safety dialog produce two competing announcements on open (live banner + disclosure body)? | `[needs-device-verification]` | No change (analysis A8 says the widget is already correct); observe V18 |
| Q14 | TTS vs TalkBack overlap on Pause/Resume/Stop: which channel yields when TalkBack is active? | `[needs-device-verification]` + `[product-decision]` | No change; TTS remains the application channel and the status live region remains as-is |
| Q15 | Exact Flutter version number for the record (revision `c9a6c484…`, channel stable, no `version` file on disk). | `[needs-device-verification]` | Cite revision + SDK path; no API used here is version-specific beyond `hintOverrides`/`semanticFormatterCallback`, both verified present |
| Q16 | Are `'Available only while detection is ready'` (Quick Scan) and the lifecycle labels acceptable product copy? | `[product-decision]` | Accept as written; they contain no gesture vocabulary and change no visible text |
