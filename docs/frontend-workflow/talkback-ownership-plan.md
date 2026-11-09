# TalkBack Ownership Plan (Stage 2)

**Stage:** 2 of 2 for this task. **No code, test, or existing-doc edits. No `flutter analyze` / `flutter test` / builds run.**

**Upstream input:** [`talkback-ownership-analysis.md`](docs/frontend-workflow/talkback-ownership-analysis.md) (this task's
re-check) plus the settled evidence base
[`talkback-semantics-analysis.md`](docs/frontend-workflow/talkback-semantics-analysis.md) /
[`talkback-semantics-plan.md`](docs/frontend-workflow/talkback-semantics-plan.md).

**Design-spec: not applicable.** Per [`.roo/rules/02-pipeline-stages.md`](.roo/rules/02-pipeline-stages.md) a design-spec
runs only when visual output changes. The brief fixes the intended visual outcome to **parity with the current UI**; the
only visible deltas permitted are the copy the brief itself prescribes (§1.2). Anything beyond that list must be
**reported, not designed**.

---

## 1. Scope statement

### 1.1 In scope

1. **Speech ownership (Option A):** under `MediaQuery.accessibleNavigationOf`, suppress exactly the four lifecycle
   utterances; leave `StatusPill` / `DetectionStatePanel` live regions intact. No audio focus, no `focus: true`, no
   `setAudioAttributesForNavigation`, no `SemanticsService.announce`.
2. **Failure ownership:** `DetectionStatePanel` is the single automatic announcer; `StatusPill` becomes non-live only while
   the failure panel is mounted, and stays navigable/informational.
3. **Home identity:** fold `'Home. '` into the existing single status node label; promote the `EyeCue` wordmark to a
   header node.
4. **Detection identity:** promote the visible `Detection Mode` title to a header node labelled `Detection`.
5. **Help granularity:** per-item nodes for `Gesture Controls` and `Best Use Tip`; `How It Works` stays grouped;
   `Gesture Confirmation` stays one prose node; `Safety and Limitations` unchanged.
6. **Repeat relocation:** move `Repeat last alert` from the audio pill to a semantic wrapper around the camera viewport;
   the pill returns to mute/unmute only.
7. **Failed Repeat feedback:** a distinct failure haptic plus a transient live-region status; **no TTS** on failure.
8. **Copy corrections** (§1.2) and the detector-model dropdown label.
9. **Tests** that encode the changed behaviour, plus the 17 new assertions in §4.2.

### 1.2 Intended visible deltas (declared, exhaustive)

These are **visible text** changes. `AccessibleButton.label` renders the visible button text
([`accessible_button.dart:36-39`](lib/widgets/accessible_button.dart:36)), and the safety dialog gains a visible title.
They are accepted as part of this task and are the **only** permitted visual deltas.

| Surface | Current | Target |
|---|---|---|
| Failure panel retry | `'Retry'` ([`detection_state_panel.dart:97`](lib/widgets/detection_state_panel.dart:97)) | `'Retry detection'` |
| Failure panel stop | `'Stop'` ([`detection_state_panel.dart:104`](lib/widgets/detection_state_panel.dart:104)) | `'Stop detection'` |
| Failure panel settings | `'Open Settings'` ([`detection_state_panel.dart:90`](lib/widgets/detection_state_panel.dart:90)) | `'Open app permission settings'` |
| Permission panel settings | `'Open Settings'` ([`ultralytics_detection_screen.dart:1660-1665`](lib/screens/ultralytics_detection_screen.dart:1660)) | `'Open app permission settings'` |
| Permission panel retry | `'Retry'` ([`ultralytics_detection_screen.dart:1667-1671`](lib/screens/ultralytics_detection_screen.dart:1667)) | `'Retry camera access'` |
| Stale EyeCue-mode copy | [`ultralytics_detection_screen.dart:1693-1697`](lib/screens/ultralytics_detection_screen.dart:1693) | `'EyeCue uses one bundled detection model and one set of detection thresholds.'` |
| Stale `press Start` (model change) | [`ultralytics_detection_screen.dart:53-55`](lib/screens/ultralytics_detection_screen.dart:53) | `'Detector model changed. Detection is stopped. Start detection to use the new model.'` |
| Stale `press Start` (Help) | [`help_screen.dart:71`](lib/screens/help_screen.dart:71) | `'2. Detection starts automatically, or use the Start control.'` |
| Stale `Press Start` (Settings) | [`settings_screen.dart:730-731`](lib/screens/settings_screen.dart:730) | `'Changing the detector stops detection. Start detection again on the Detection screen to run the selected model.'` |
| Safety dialog title | none ([`safety_disclosure.dart:111`](lib/widgets/safety_disclosure.dart:111)) | `'Before you use EyeCue'` (must **not** duplicate `kSafetyDisclosureTitle`) |

### 1.3 Out of scope (with reasons)

| Excluded | Reason |
|---|---|
| `lib/services/**` including `tts_service.dart` | Services are read-only for UI work ([`.roo/rules/rules-frontend/01-scope.md`](.roo/rules/rules-frontend/01-scope.md)). The analysis (§2.1) proves the Repeat failure causes are separable with the existing `audioEnabled` / `lastUtterance` getters — no service change is needed |
| `lib/models/**` | Read-only; no model contract is touched |
| Shell horizontal navigation, `app_shell.dart`, `gesture_controller.dart`, `gesture_surface.dart`, `GestureController` dispatch | Device-confirmed not to fire under TalkBack; the viewport wrapper is added **above** the existing `GestureSurface` child without touching the `Listener` |
| The 3 s hold, its three timers, `_progress`, `_holding`, `_holdAttempt`, `_consumed`, `_dispatchTap`, `_dispatchSemanticHold` | Locked behaviour; the lifecycle card is not in the change set at all (its semantics are already approved — analysis row 27) |
| Quick Scan gating and the two-card row composition | Locked; no widget is added or removed |
| `SwitchListTile` / `RadioListTile` / `Slider` semantics, per-frame detection rows, telemetry, haptics policy, settings persistence, corrections, research sessions, export | Already correct or explicitly preserved |
| `SemanticsSortKey` / forced focus / `SemanticsService.announce` / audio focus | Analysis §6: traversal and announcement timing are platform-owned |
| Logs & Reports de-duplication and Settings slider work from the previous stage | Already landed or separately decided; this task touches only the `_ModelFilter` label |

---

## 2. Per-file change list (implementation order)

### Group A — shared widgets (change first; they ripple)

**A1. [`lib/widgets/status_pill.dart`](lib/widgets/status_pill.dart) — optional liveness flag**

Add `final bool liveRegion;` to the widget fields ([`:9-10`](lib/widgets/status_pill.dart:9)) and constructor
([`:12`](lib/widgets/status_pill.dart:12)) with `this.liveRegion = true`; replace `liveRegion: true`
([`:18`](lib/widgets/status_pill.dart:18)) with `liveRegion: liveRegion`.
*Rationale:* failure ownership needs one automatic announcer; a default of `true` keeps every existing call site and the
standalone test ([`semantics_test.dart:181-184`](test/accessibility/semantics_test.dart:181)) unchanged.

**A2. [`lib/widgets/warning_banner.dart`](lib/widgets/warning_banner.dart) — optional liveness flag**

Add `final bool liveRegion;` with default `true` ([`:8-11`](lib/widgets/warning_banner.dart:8)) and use it at
[`:17`](lib/widgets/warning_banner.dart:17).
*Rationale:* the safety dialog's live lead-in must not compete with the disclosure on entry, while the depth-degraded
banner ([`ultralytics_detection_screen.dart:1380`](lib/screens/ultralytics_detection_screen.dart:1380)) must stay live.

**A3. [`lib/widgets/detection_state_panel.dart`](lib/widgets/detection_state_panel.dart) — contextual labels**

Rename the three `AccessibleButton` labels only: `'Open Settings'` → `'Open app permission settings'`
([`:90`](lib/widgets/detection_state_panel.dart:90)), `'Retry'` → `'Retry detection'` ([`:97`](lib/widgets/detection_state_panel.dart:97)),
`'Stop'` → `'Stop detection'` ([`:104`](lib/widgets/detection_state_panel.dart:104)). Keep `liveRegion: true`
([`:42`](lib/widgets/detection_state_panel.dart:42)), `canOpenSettings` ([`:37-38`](lib/widgets/detection_state_panel.dart:37)),
exclusions ([`:62-81`](lib/widgets/detection_state_panel.dart:62)), icons, order and `onPressed` wiring untouched.
*Rationale:* this panel is the single automatic failure announcer; its actions must be self-describing out of context.

**A4. [`lib/widgets/help_section_card.dart`](lib/widgets/help_section_card.dart) — new reusable card**

New public `HelpSectionCard` with `required String title` and a mutually exclusive pair
`String? body` / `List<String>? items`. Title semantics are copied **verbatim** from the current private card:
`Semantics(container: true, header: true, label: title, child: ExcludeSemantics(Text(title, ...)))`
([`help_screen.dart:145-160`](lib/screens/help_screen.dart:145)). When `items` is supplied, each item renders as its own
`Semantics(container: true, child: Text(item, style: ...))`; when `body` is supplied the single `Text(body)`
([`:162`](lib/screens/help_screen.dart:162)) is retained unchanged. Card container styling (`kHomeSurfaceCard`,
`kRadius24`, `kHomeShadowSoft`, `kSpace16`) is copied unchanged from [`:134-141`](lib/screens/help_screen.dart:134).
*Rationale:* one public widget per file per
[`.roo/rules/rules-frontend/02-naming-convention.md`](.roo/rules/rules-frontend/02-naming-convention.md); per-item
reading granularity is required for two cards only, so the card must support both modes.

### Group B — screens

**B1. [`lib/screens/home_screen.dart`](lib/screens/home_screen.dart) — identity**

- Wordmark ([`:104-108`](lib/screens/home_screen.dart:104)) becomes
  `Semantics(container: true, header: true, label: 'EyeCue', child: ExcludeSemantics(child: Text('EyeCue', textAlign: TextAlign.center, style: Theme.of(context).textTheme.displayLarge)))`.
- Status badge ([`:155-157`](lib/screens/home_screen.dart:155)) label becomes `'Home. ${presentation.meaning}'`; keep
  `container: true`, keep the child excluded ([`:158`](lib/screens/home_screen.dart:158)), keep it **non-live**.
- Do **not** touch the already-excluded instruction texts ([`:223-245`](lib/screens/home_screen.dart:223)) or the rail
  ([`:249-256`](lib/screens/home_screen.dart:249)).
*Rationale:* screen identity without an extra node and without touching the fixed non-scrollable layout.

**B2. [`lib/screens/ultralytics_detection_screen.dart`](lib/screens/ultralytics_detection_screen.dart) — the main body of work**

1. **Lifecycle speech gate.** Add
   `bool get _talkBackActive => MediaQuery.accessibleNavigationOf(context);`
   and capture it once at the top of each method **before any `await`** (so no post-await `context` use). Wrap only these
   four calls:
   `'Detection started'` ([`:871`](lib/screens/ultralytics_detection_screen.dart:871)),
   `'Detection stopped'` ([`:916`](lib/screens/ultralytics_detection_screen.dart:916)),
   `'Detection paused'` ([`:941`](lib/screens/ultralytics_detection_screen.dart:941)),
   `'Detection resumed'` ([`:957`](lib/screens/ultralytics_detection_screen.dart:957)) — e.g.
   `if (!suppressLifecycleSpeech) await _tts.speak(...)`. Keep the existing `announce` parameter semantics in
   `_startDetection` ([`:807-810`](lib/screens/ultralytics_detection_screen.dart:807)) untouched. Haptics, state
   transitions, coordinator reports, timers and telemetry are **not** gated.
2. **Header identity.** Wrap the `'Detection Mode'` `Text` ([`:1451-1454`](lib/screens/ultralytics_detection_screen.dart:1451))
   in `Semantics(container: true, header: true, label: 'Detection', child: ExcludeSemantics(child: Text('Detection Mode', ...)))`
   — visible string and style unchanged.
3. **Failure ownership.** At the `StatusPill` call ([`:1458`](lib/screens/ultralytics_detection_screen.dart:1458)) pass
   `liveRegion: widget.coordinator.state != DetectionRuntimeState.failed`.
   *Rationale:* that is exactly the condition under which `DetectionStatePanel` is mounted
   ([`:1511-1517`](lib/screens/ultralytics_detection_screen.dart:1511-1517)).
4. **Repeat leaves the pill.** Delete `final VoidCallback? onRepeatAlert;` and its constructor parameter from `_AudioPill`
   ([`:1758-1766`](lib/screens/ultralytics_detection_screen.dart:1758)); delete the `onRepeatAlert: _repeatAlert` argument
   ([`:1470-1472`](lib/screens/ultralytics_detection_screen.dart:1470)) and its comment; remove
   `customSemanticsActions` ([`:1781-1783`](lib/screens/ultralytics_detection_screen.dart:1781)). The pill keeps
   `container: true`, `excludeSemantics: true`, `button: true`, `enabled: true`, `label: 'Audio guidance, on|off'`,
   `onTap: onPressed` and the whole visual subtree.
5. **Repeat lands on the camera view.** At
   [`ultralytics_detection_screen.dart:1639`](lib/screens/ultralytics_detection_screen.dart:1639) change
   `return GestureSurface(controller: _gestureController, child: viewport);` to
   `return GestureSurface(controller: _gestureController, child: Semantics(container: true, explicitChildNodes: true, label: 'Camera view', customSemanticsActions: { const CustomSemanticsAction(label: 'Repeat last alert'): _repeatAlertFromSemantics }, child: viewport));`.
   No `liveRegion`, **no** `excludeSemantics`, no `onTap`, no `onLongPress`. `GestureSurface` itself is unchanged.
6. **Repeat dispatch (new, UI-only).** Add

   ```
   Future<void> _repeatAlertFromSemantics() async {
     if (!_tts.audioEnabled) return _announceRepeatFailure('Audio guidance is off');
     if (_tts.lastUtterance == null) return _announceRepeatFailure('Nothing to repeat yet');
     await _repeatAlert();              // existing behaviour, unchanged
     // repeatLast() can still refuse (validity/superseded) — report generically.
   }
   ```

   plus `_announceRepeatFailure(String message)` which fires `_haptics.heavyTick()` (distinct from the success
   `mediumTick`, [`:1166`](lib/screens/ultralytics_detection_screen.dart:1166)) and sets a `_repeatFailureNotice` string
   that is cleared by a short timer, rendered as a **zero-visual-size**
   `Semantics(container: true, liveRegion: true, label: notice, child: const SizedBox.shrink())` inside the existing
   viewport `Stack`. **No** `_tts.speak` on any failure path (a spoken failure would become the new `lastUtterance` and
   be replayed by Repeat).
   `_repeatAlert()` ([`:1165-1168`](lib/screens/ultralytics_detection_screen.dart:1165)) and the `swipeDown` dispatch
   ([`:1332-1333`](lib/screens/ultralytics_detection_screen.dart:1332)) are otherwise untouched.
7. **Copy corrections.** The four rows in §1.2 that live in this file: `kModelChangedMessage`
   ([`:53-55`](lib/screens/ultralytics_detection_screen.dart:53)), the camera-pending paragraph
   ([`:1693-1697`](lib/screens/ultralytics_detection_screen.dart:1693)), and the two permission-panel labels
   ([`:1660-1671`](lib/screens/ultralytics_detection_screen.dart:1660)).
8. **Do not touch** `_startDetection` / `_stopDetection` / `_pauseDetection` / `_resumeDetection` bodies beyond the four
   gated `speak` calls, the action-row wiring ([`:1717-1745`](lib/screens/ultralytics_detection_screen.dart:1717)),
   `_handleStreamingData`, the depth paths, `_toggleAudio` ([`:1238-1243`](lib/screens/ultralytics_detection_screen.dart:1238)),
   or `_buildMainArea`'s panel branches.

**B3. [`lib/screens/help_screen.dart`](lib/screens/help_screen.dart) — per-item granularity**

Import `../widgets/help_section_card.dart`; replace the const `_HelpCard(...)` entries ([`:67-108`](lib/screens/help_screen.dart:67)):
`How It Works` → `HelpSectionCard(title:, body: <unchanged string>)`; `Gesture Controls` →
`HelpSectionCard(title:, items: [<the four bullet strings verbatim, without the leading '• '>)>]`;
`Gesture Confirmation` → `body:` (unchanged); `Best Use Tip (Android)` → `items:` (the four bullets, verbatim). Fix the
step-2 copy (§1.2). Delete the private `_HelpCard` ([`:122-167`](lib/screens/help_screen.dart:122)).
`SafetyDisclosureCard` ([`:66`](lib/screens/help_screen.dart:66)) and the app bar ([`:37-46`](lib/screens/help_screen.dart:37))
are untouched.
*Rationale:* bullet strings are preserved verbatim so existing `textContaining` assertions
([`test/widget_test.dart:402`](test/widget_test.dart:402), [`:415-420`](test/widget_test.dart:415)) stay valid.

**B4. [`lib/screens/settings_screen.dart`](lib/screens/settings_screen.dart) — stale copy only**

Replace the `Text` at [`:729-734`](lib/screens/settings_screen.dart:729) with the §1.2 wording. No other change in this
file.

**B5. [`lib/screens/logs_reports_screen.dart`](lib/screens/logs_reports_screen.dart) — dropdown label**

Wrap the `_ModelFilter` `Row` ([`:2023-2050`](lib/screens/logs_reports_screen.dart:2023)) in `MergeSemantics`, leaving
the child `Text('Detector model')` ([`:2025`](lib/screens/logs_reports_screen.dart:2025)) and the
`DropdownButton<String?>` ([`:2029`](lib/screens/logs_reports_screen.dart:2029)) byte-identical. **Do not** switch to
`DropdownButtonFormField` (analysis §2.2: it introduces an `InputDecorator`, changes padding/height, and relocates the
suffix icon — a visual delta the parity constraint forbids).

**B6. [`lib/widgets/safety_disclosure.dart`](lib/widgets/safety_disclosure.dart) — dialog identity**

Add `const String kSafetyDialogTitle = 'Before you use EyeCue';` next to
[`kSafetyDisclosureTitle`](lib/widgets/safety_disclosure.dart:15). Give the `AlertDialog`
([`:111-134`](lib/widgets/safety_disclosure.dart:111)) a `title:` built as
`Semantics(container: true, header: true, label: kSafetyDialogTitle, child: ExcludeSemantics(child: Text(kSafetyDialogTitle, ...)))`
using `titleMedium` + `w800` to match the disclosure heading ([`:53-55`](lib/widgets/safety_disclosure.dart:53)). Pass
`liveRegion: false` to the dialog's `WarningBanner` ([`:120-122`](lib/widgets/safety_disclosure.dart:120)) so the lead-in
does not compete with the disclosure on entry. `SafetyDisclosureBody`/`Card` are untouched.

---

## 3. Target semantics contract

No string below contains `double tap`, `hold`, or `swipe`.

### 3.1 Home

| Node | `label` | Flags | Actions | Live |
|---|---|---|---|---|
| Wordmark | `EyeCue` | `container`, `header` | none | no |
| Status badge | `Home. <meaning>` e.g. `Home. Ready. Ready when you are. Detection is ready.` | `container` | none | no |
| Instruction headline/supporting | — | excluded (`ExcludeSemantics`) | — | — |
| Logo / rail | — | excluded | — | — |

Five target labels (prefix only; `meaning` bodies unchanged from
[`home_screen.dart:305-307`](lib/screens/home_screen.dart:305), [`:315`](lib/screens/home_screen.dart:315),
[`:323`](lib/screens/home_screen.dart:323), [`:331`](lib/screens/home_screen.dart:331),
[`:340`](lib/screens/home_screen.dart:340)):
`Home. Preparing. Detection begins immediately.` /
`Home. Preparing. Getting things ready. Detection is preparing.` /
`Home. Ready. Ready when you are. Detection is ready.` /
`Home. Paused. Detection is paused. Open Detect to resume.` /
`Home. Stopped. Detection is stopped. Open Detect to start again.` /
`Home. Unavailable. Detection needs attention. <message>`.

### 3.2 Detection header and status

| Control | `label` | Flags | Actions | Live |
|---|---|---|---|---|
| Header | `Detection` (visible text `Detection Mode`) | `container`, `header`; child excluded | none | no |
| `StatusPill` | `Detection status: <Preparing|Detecting|Paused|Stopped|Unavailable>` | `container` | none | **yes**, except `liveRegion: false` while `coordinator.state == DetectionRuntimeState.failed` |

### 3.3 Camera view (Repeat host)

| Property | Value |
|---|---|
| `container` | `true` |
| `explicitChildNodes` | `true` |
| `label` | `Camera view` |
| `customSemanticsActions` | `{ const CustomSemanticsAction(label: 'Repeat last alert'): _repeatAlertFromSemantics }` |
| `liveRegion` | absent |
| `excludeSemantics` | absent (overlay rows must stay their own nodes) |
| `onTap` / `onLongPress` | absent |
| Child | the existing `viewport` widget, unchanged |

### 3.4 Audio pill (mute/unmute only)

| Property | Value |
|---|---|
| `container` | `true` |
| `excludeSemantics` | `true` |
| `button` / `enabled` | `true` / `true` |
| `label` | `Audio guidance, on` / `Audio guidance, off` |
| `onTap` | `_toggleAudio` |
| `customSemanticsActions` | **absent** |
| `hint` | absent |

### 3.5 Repeat outcomes

| Situation | `_tts` state | Haptic | Announced status (live region, no TTS) |
|---|---|---|---|
| Repeatable | `audioEnabled == true` **and** `lastUtterance != null` | `mediumTick` via `_repeatAlert()` | none (the replayed alert is the feedback) |
| Audio off | `audioEnabled == false` | `heavyTick` | `Audio guidance is off` |
| Nothing cached | `audioEnabled == true`, `lastUtterance == null` | `heavyTick` | `Nothing to repeat yet` |
| Cached but refused (validity/superseded) | both getters pass, `repeatLast()` → `false` | `heavyTick` | `Nothing to repeat yet` |

### 3.6 Help cards

| Card | Shape | Title node |
|---|---|---|
| `How It Works` | one grouped `body` node | `container`, `header`, label = title |
| `Gesture Controls` | one node **per bullet** (4), each `container: true` | `container`, `header`, label = title |
| `Gesture Confirmation` | one prose `body` node | `container`, `header`, label = title |
| `Best Use Tip (Android)` | one node **per bullet** (4) | `container`, `header`, label = title |
| Safety card | unchanged (`SafetyDisclosureBody`) | existing `header` node |

### 3.7 Failure panel

| Node | `label` | Live | Actions |
|---|---|---|---|
| Panel container | `<category label>. <user message>` | **yes** (only automatic failure announcer) | — |
| Settings button | `Open app permission settings` | no | tap (`openAppSettings`) |
| Retry button | `Retry detection` | no | tap |
| Stop button | `Stop detection` | no | tap |

### 3.8 Safety dialog

| Node | `label` | Flags |
|---|---|---|
| Dialog title (new) | `Before you use EyeCue` | `container`, `header`; child excluded |
| Lead banner | `Warning. Read this before you rely on EyeCue.` | `container`, **non-live** |
| Disclosure heading | `Safety and Limitations` | `container`, `header` (unchanged) |
| Each of 5 points | bullet text | `container` (unchanged) |

### 3.9 Detector-model filter

One merged node: label combines `Detector model` + the selected item text; flags keep `button` and `expanded`; the tap
action and `onChanged` behaviour are the dropdown's own (unchanged). No visual or layout change.

---

## 4. Test plan

### 4.1 Tests to amend

| Test | Location | Change |
|---|---|---|
| `the audio pill is one node with a Repeat last alert action` | [`test/screens/gesture_navigation_direction_test.dart:375-415`](test/screens/gesture_navigation_direction_test.dart:375) | Retitle and re-point: the pill asserts **no** labelled custom action (and keeps `label` + `tap`); the `Repeat last alert` label, invocation, and `mediumTick` assertion move to the `Camera view` node (helper currently at [`:378-411`](test/screens/gesture_navigation_direction_test.dart:378)) |
| Permission-panel taps/swipes | [`test/screens/gesture_navigation_direction_test.dart:358-372`](test/screens/gesture_navigation_direction_test.dart:358) | `'Open Settings'` → `'Open app permission settings'`; `'Retry'` → `'Retry camera access'` |
| Home meanings ×5 | [`test/accessibility/semantics_test.dart:459`](test/accessibility/semantics_test.dart:459), [`:475`](test/accessibility/semantics_test.dart:475), [`:497`](test/accessibility/semantics_test.dart:497), [`:511`](test/accessibility/semantics_test.dart:511), [`:520`](test/accessibility/semantics_test.dart:520), [`:539`](test/accessibility/semantics_test.dart:539) | Prefix each expected label with `Home. ` |
| State-panel buttons | [`test/accessibility/semantics_test.dart:286-291`](test/accessibility/semantics_test.dart:286) | `'Retry'` → `'Retry detection'`, `'Stop'` → `'Stop detection'`; the taps at [`:289-290`](test/accessibility/semantics_test.dart:289) follow |
| Wordmark node | [`test/accessibility/semantics_test.dart:461`](test/accessibility/semantics_test.dart:461), [`:498`](test/accessibility/semantics_test.dart:498), [`:552`](test/accessibility/semantics_test.dart:552) | Keep length-1 assertions; add `flagsCollection.isHeader` |
| Help card copy | [`test/widget_test.dart:344-420`](test/widget_test.dart:344) | Re-check the step-2 string (`press Start` row) and the per-item bullets; only the step-2 `textContaining` predicate changes |
| `StatusPill` liveness | [`test/accessibility/semantics_test.dart:181-184`](test/accessibility/semantics_test.dart:181) | Keep (default `true`); the failed-state case is new (N6) |

**Must stay green without edits:** the two-control/one-`GestureDetector` composition
([`test/widgets/detection_action_controls_test.dart:66-77`](test/widgets/detection_action_controls_test.dart:66)); the entire
hold-timing/`KEEP HOLDING`/`_consumed` group ([`:250-408`](test/widgets/detection_action_controls_test.dart:250));
`find.text('Stop')`/`'Start'` find-nothing assertions
([`test/screens/ultralytics_detection_screen_layout_test.dart:112-117`](test/screens/ultralytics_detection_screen_layout_test.dart:112),
[`test/screens/detection_screen_layout_test.dart:110-113`](test/screens/detection_screen_layout_test.dart:110),
[`test/widget_test.dart:511-517`](test/widget_test.dart:511)); default-path start speech
([`test/screens/gesture_navigation_direction_test.dart:317`](test/screens/gesture_navigation_direction_test.dart:317), [`:339`](test/screens/gesture_navigation_direction_test.dart:339));
the 200 % text-scale groups ([`test/accessibility/semantics_test.dart:229-253`](test/accessibility/semantics_test.dart:229),
[`:407-457`](test/accessibility/semantics_test.dart:407), [`:558-576`](test/accessibility/semantics_test.dart:558),
[`:684-702`](test/accessibility/semantics_test.dart:684), [`:965-1000`](test/accessibility/semantics_test.dart:965));
the Help heading assertions ([`:614-625`](test/accessibility/semantics_test.dart:614));
the Logs `header` assertions ([`test/screens/logs_reports_screen_test.dart:2224-2271`](test/screens/logs_reports_screen_test.dart:2224)).

### 4.2 New tests — the brief's 17 items (assertions N1–N18)

| # | Test intent | File | Expected shape |
|---|---|---|---|
| N1 | **Home identity + status:** wordmark is one header node and the status node carries the screen identity | `test/accessibility/semantics_test.dart` | `byLabel('EyeCue')` length 1 **and** `isHeader`; `byLabel('Home. …')` length 1; `byLabel('Go to Live Camera')` empty |
| N2 | **Home status prefix for all five outcomes** | same | Each of the five prefixed labels resolves to exactly one node |
| N3 | **Detection heading:** one header node labelled `Detection` | `test/screens/detection_redesign_parity_test.dart` (real-screen harness) | `byLabel('Detection')` length 1 with `isHeader`; `find.text('Detection Mode')` still one widget |
| N4 | **Lifecycle TTS gated (start):** with `accessibleNavigation: true`, starting speaks no lifecycle utterance | `test/screens/gesture_navigation_direction_test.dart` | `ttsEngine.spoken` is empty after start |
| N5 | **Lifecycle TTS gated (stop/pause/resume):** same flag, none of the three utterances | same | `ttsEngine.spoken` contains none of `Detection stopped/paused/resumed` |
| N6 | **Domain TTS unaffected:** with `accessibleNavigation: true`, Quick Scan still speaks | same | `ttsEngine.spoken` is non-empty and is the scan summary |
| N7 | **Single failure announcer:** while the failure panel is mounted, exactly one live region exists between pill and panel | `test/accessibility/semantics_test.dart` | Pill `isLiveRegion` false, panel `isLiveRegion` true; pill still finds its label |
| N8 | **Help — Gesture Controls per item** | `test/screens/help_screen_test.dart` | 4 distinct nodes, one per bullet; title is a `header` |
| N9 | **Help — Best Use Tip per item** | same | 4 distinct nodes; title is a `header` |
| N10 | **Help — How It Works stays grouped** | same | Exactly one node containing `1. Open EyeCue.` and the on-device note |
| N11 | **Camera view is one node** | `test/screens/gesture_navigation_direction_test.dart` | `byLabel('Camera view')` length 1; `isLiveRegion` false; overlay row still its own node |
| N12 | **Exactly one `Repeat last alert` action** | same | Across the whole screen, labelled custom actions (filtered to `label != null`) equal `['Repeat last alert']`, once |
| N13 | **Pill no longer exposes Repeat** | same | Pill node has no labelled custom action; `label` + `tap` still present |
| N14 | **Successful Repeat unchanged** | same | Invoking the camera-view action with a repeatable utterance records exactly one `medium` haptic and one `tts.repeatLast()` call |
| N15 | **Failed Repeat feedback** | same | Muted → `heavy` haptic **and** live-region `Audio guidance is off`, `tts.speak` never called; empty history → `Nothing to repeat yet` |
| N16 | **Stale strings gone** | `test/architecture/talkback_no_gesture_hints_test.dart` (extend the existing source guard) | No `lib/` source contains `custom EyeCue mode`, `press Start`, or `Press Start on the` |
| N17 | **Detector-model dropdown labelled** | `test/screens/logs_reports_screen_test.dart` | One merged node whose label contains `Detector model` and the selected item; still a `button` with a `tap` action |
| N18 | **Safety dialog identity** | `test/screens/help_screen_test.dart` | Dialog shows `Before you use EyeCue` as a `header` node, `Safety and Limitations` appears exactly once, and exactly one node in the dialog is a live region (`none`) |

*Note on N18:* it is counted alongside N1–N17 as the brief's "safety dialog identity" item, giving 18 assertions for 17
brief items because the Help per-item pair and the lifecycle-gating pair were each split into two tests.

**Test-authoring note (carried from the previous stage):** `hintOverrides` registers anonymous
`CustomSemanticsAction.overridingAction` entries, so any custom-action enumeration must filter to `action.label != null`.

---

## 5. Verification commands and expected results

| Command | Expected |
|---|---|
| `flutter analyze` | `No issues found!` (0 issues) |
| `flutter test` | Full suite green. Record the observed count in the session log; expected to be the current baseline **plus the amended tests plus N1–N18**, with **no deletions** |
| `flutter test test/accessibility/semantics_test.dart test/screens/gesture_navigation_direction_test.dart test/screens/help_screen_test.dart test/screens/detection_redesign_parity_test.dart test/screens/logs_reports_screen_test.dart test/architecture/talkback_no_gesture_hints_test.dart test/widget_test.dart` | Focused run green for the touched surface |
| `flutter test test/widgets/detection_action_controls_test.dart` | Unchanged and green (proves the hold/`_consumed` behaviour was not perturbed) |
| `flutter build apk --debug` | Succeeds; no dependency, Gradle, or asset change is introduced by this plan |
| Device pass (`docs/frontend-workflow/talkback-semantics-plan.md` §6.2 checklist reused) | TalkBack on, physical device: N4/N5 by ear, N11/N12/N14/N15 through the actions menu, N17 in Logs & Reports, N18 on first launch |

---

## 6. Behaviour-preservation risk register (per file)

| File | Must not change | How a regression shows up | Protected by |
|---|---|---|---|
| [`lib/widgets/status_pill.dart`](lib/widgets/status_pill.dart) | Default `liveRegion: true`; `label` format; excluded children | Every lifecycle transition stops being announced | [`semantics_test.dart:181-184`](test/accessibility/semantics_test.dart:181) |
| [`lib/widgets/warning_banner.dart`](lib/widgets/warning_banner.dart) | Default `liveRegion: true`; `'Warning. $message'` label | Depth-degraded banner silently stops announcing | [`semantics_test.dart:182-184`](test/accessibility/semantics_test.dart:182); depth tests |
| [`lib/widgets/detection_state_panel.dart`](lib/widgets/detection_state_panel.dart) | `liveRegion`, container label, `canOpenSettings` logic, exclusions, callback wiring | Failure not announced, or retry/stop stops working | [`semantics_test.dart:279-293`](test/accessibility/semantics_test.dart:279) |
| [`lib/widgets/help_section_card.dart`](lib/widgets/help_section_card.dart) (new) | Title `Semantics(container/header/label)` + excluded title; card decoration tokens; verbatim bullet strings | Duplicate title node, or `textContaining` assertions break | [`semantics_test.dart:614-625`](test/accessibility/semantics_test.dart:614); [`widget_test.dart:344-420`](test/widget_test.dart:344) |
| [`lib/screens/home_screen.dart`](lib/screens/home_screen.dart) | Fixed non-scrollable composition, `Flexible` + ellipsis, excluded rail, badge non-live | 200 % overflow, or status read twice/not at all | [`semantics_test.dart:558-576`](test/accessibility/semantics_test.dart:558); [`widget_test.dart:29-43`](test/widget_test.dart:29) |
| [`lib/screens/ultralytics_detection_screen.dart`](lib/screens/ultralytics_detection_screen.dart) | `_startDetection`/`_stopDetection`/`_pauseDetection`/`_resumeDetection` bodies beyond the four gated `speak` calls; timers; epoch guards; coordinator reporting; `_toggleAudio`; action-row wiring; `GestureSurface`/`GestureController` dispatch; per-frame overlay non-liveness; telemetry/haptics | Lifecycle stops transitioning; double speech; gesture navigation breaks; overlay rows become live; Repeat double-fires haptic + TTS | [`gesture_navigation_direction_test.dart:280-373`](test/screens/gesture_navigation_direction_test.dart:280); [`ultralytics_detection_readiness_test.dart`](test/screens/ultralytics_detection_readiness_test.dart); [`ultralytics_detection_screen_layout_test.dart:121-160`](test/screens/ultralytics_detection_screen_layout_test.dart:121) |
| [`lib/screens/help_screen.dart`](lib/screens/help_screen.dart) | Heading semantics per card; verbatim bullet text; `SafetyDisclosureCard` placement | Headings duplicated/missing; `textContaining` assertions break | [`help_screen_test.dart:28-81`](test/screens/help_screen_test.dart:28); [`semantics_test.dart:614-625`](test/accessibility/semantics_test.dart:614) |
| [`lib/screens/settings_screen.dart`](lib/screens/settings_screen.dart) | Slider `onChanged`/`onChangeEnd`, drafts, persistence, switches/radios/headings | Detector selection stops persisting | [`settings_screen_model_test.dart`](test/screens/settings_screen_model_test.dart); [`settings_service_test.dart`](test/services/settings_service_test.dart) |
| [`lib/screens/logs_reports_screen.dart`](lib/screens/logs_reports_screen.dart) | `DropdownButton` items/`onChanged`/`value`; every live region; export/upload callbacks; tab behaviour | Filter stops filtering or crashes on a stale selection | [`logs_reports_screen_test.dart`](test/screens/logs_reports_screen_test.dart) |
| [`lib/widgets/safety_disclosure.dart`](lib/widgets/safety_disclosure.dart) | Five points and their order; disclosure heading; `PopScope(canPop: false)`; acknowledge callback | Dialog becomes dismissible or loses a point | [`help_screen_test.dart:84-119`](test/screens/help_screen_test.dart:84); [`semantics_test.dart:623-668`](test/accessibility/semantics_test.dart:623) |

**Global rollback:** every change is a semantics-property edit, an `ExcludeSemantics`/`Semantics` wrapper, a new
optional widget parameter defaulting to today's behaviour, a copy string, or an extracted widget. No service, model,
dependency, asset, Android/Gradle file, or new visible control is introduced. Each file reverts independently.

**Out-of-scope leak check:** if implementation finds it needs `lib/services/` (for example a typed repeat-failure reason),
it must **stop and flag** a scope exception rather than proceed.

---

## 7. Open Questions / Needs Verification

| # | Item | Tag | Default assumed |
|---|---|---|---|
| Q1 | Are the §1.2 copy replacements (four labels + four stale-copy strings + one dialog title) approved as visible text? | `[product-decision]` | Approved exactly as written; no other wording changes |
| Q2 | Should `swipeDown` keep its **silent** failure behaviour, or also route through `_repeatAlertFromSemantics` for symmetry? | `[product-decision]` | Keep `swipeDown` on `_repeatAlert()` unchanged; only the semantic action gains failure feedback |
| Q3 | Is `Camera view` the right static label for the viewport node (screen readers will hear it on every focus)? | `[product-decision]` | Keep `Camera view` |
| Q4 | Should the safety dialog title be `Before you use EyeCue`? | `[product-decision]` | Keep it; it must not match `kSafetyDisclosureTitle` |
| Q5 | Does the merged `_ModelFilter` node keep `tap` and re-announce the new selection? | `[needs-device-verification]` | Assume yes |
| Q6 | Is a zero-size live-region node announced on the target TalkBack build? | `[needs-device-verification]` | Assume yes; fallback = transient caption in the model-change slot, which is a visible addition and must be reported first |
| Q7 | Does `explicitChildNodes: true` preserve the overlay rows as separate non-live nodes under the new `Camera view` container? | `[needs-device-verification]` | Assume yes |
| Q8 | Is the `Repeat last alert` action reachable on a node that sits above a platform view? | `[needs-device-verification]` | Assume yes |
| Q9 | Is an unchanged failure label re-announced when Repeat is pressed twice with the same cause? | `[needs-device-verification]` | Assume announcements occur only on label change; a repeated identical label may be silent |
| Q10 | Does removing the dialog lead banner's liveness leave exactly one entry announcement? | `[needs-device-verification]` | Assume the disclosure heading is the single entry announcement |
| Q11 | Do the per-item Help cards keep visual spacing identical to the single-`Text` version (line-height vs per-item gaps)? | `[needs-device-verification]` | Use the same `bodyLarge` + `height: 1.4` style and a small inter-item gap; if spacing differs, report it as a visual delta rather than tuning the design |
