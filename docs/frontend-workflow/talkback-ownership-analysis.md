# TalkBack Ownership Analysis (Stage 1 — re-check)

**Stage:** 1 of 2 for this task (re-verification + feasibility analysis). **No code, test, or existing-doc edits.**
No `flutter analyze` / `flutter test` / builds were run.

**Task type:** semantics-ownership change. Speech ownership (TalkBack vs EyeCue TTS), failure-announcement ownership,
screen identity, Help reading granularity, Repeat relocation, and label copy. No layout or styling redesign is intended;
a design-spec therefore does not apply (see the plan's scope statement).

**Upstream inputs (read-only, decisions not re-litigated):**
[`talkback-semantics-analysis.md`](docs/frontend-workflow/talkback-semantics-analysis.md) (evidence base) and
[`talkback-semantics-plan.md`](docs/frontend-workflow/talkback-semantics-plan.md) (settled mechanism decisions).

**Scope discipline:** this file is the only output of Stage 1. Every claim below is a current-tree `path:line` read, or a
read of the **installed Flutter SDK** through `package:` URIs (used only for the dropdown feasibility question). Anything
unconfirmed is tagged **Needs Verification** per [`.roo/rules/01-verification-policy.md`](.roo/rules/01-verification-policy.md).

---

## 0. Executive summary of the re-check

The settled decisions are **implementable**, and the four lifecycle utterances, the identity nodes, the Repeat host, and
the failure surfaces all exist where the brief says they do. Three re-check findings change what the plan must *do*:

1. **The previous semantics stage is already landed in the tree.** The lifecycle card already exposes
   `onLongPress` + `hintOverrides` ([`detection_action_controls.dart:307-319`](lib/widgets/detection_action_controls.dart:307),
   [`:349-370`](lib/widgets/detection_action_controls.dart:349)), `AccessibleButton` already has no `hint`
   ([`accessible_button.dart:27-51`](lib/widgets/accessible_button.dart:27)), the Home instruction region is already
   excluded ([`home_screen.dart:223-245`](lib/screens/home_screen.dart:223)), the `Use fallback` path is already gone
   ([`detection_state_panel.dart:16-28`](lib/widgets/detection_state_panel.dart:16)), and the header `_modelError`
   duplicate is already excluded ([`ultralytics_detection_screen.dart:1483-1491`](lib/screens/ultralytics_detection_screen.dart:1483)).
   Several items the brief lists as additions are therefore **moves or re-scopes**, not first-time additions.

2. **Repeat is currently on the audio pill, not absent.** `_AudioPill` already carries
   `container: true, excludeSemantics: true, button: true, label, onTap` **and**
   `customSemanticsActions: {CustomSemanticsAction('Repeat last alert'): repeat}`
   ([`ultralytics_detection_screen.dart:1772-1783`](lib/screens/ultralytics_detection_screen.dart:1772)), fed by
   `onRepeatAlert: _repeatAlert` ([`:1472`](lib/screens/ultralytics_detection_screen.dart:1472)). The settled decision is a
   **relocation** to the camera viewport, which means deleting working code from the pill and a test that currently
   *passes* against it.

3. **Three settled line references are stale by a few lines, and two stale-copy references moved.** Details in §1.

**Feasibility verdicts (detail in §2):**
`(a)` Repeat-failure cause discrimination **without a service change: FEASIBLE** — see §2.1.
`(b)` Detector-model dropdown **labelled with visual parity: `MergeSemantics` around the existing `Row`** (not
`DropdownButtonFormField`) — see §2.2.

---

## 1. Re-verification table

Verdicts: **TRUE** (holds, cited location accurate) · **CHANGED** (holds, cited location/line moved) · **ALREADY DONE**
(the behaviour the brief asks for is already in the tree, so the plan must move/re-scope rather than add) ·
**WRONG** (does not hold). Line numbers are current-tree.

| # | Settled fact | Verdict | Current evidence |
|---|---|---|---|
| 1 | `'Detection started'` utterance | **TRUE** | [`ultralytics_detection_screen.dart:871`](lib/screens/ultralytics_detection_screen.dart:871) — last statement of `_startDetection` ([`:807`](lib/screens/ultralytics_detection_screen.dart:807)), itself guarded by `announce` |
| 2 | `'Detection stopped'` | **TRUE** | [`ultralytics_detection_screen.dart:916`](lib/screens/ultralytics_detection_screen.dart:916) |
| 3 | `'Detection paused'` | **TRUE** | [`ultralytics_detection_screen.dart:941`](lib/screens/ultralytics_detection_screen.dart:941) |
| 4 | `'Detection resumed'` | **TRUE** | [`ultralytics_detection_screen.dart:957`](lib/screens/ultralytics_detection_screen.dart:957) |
| 5 | `StatusPill` is a live region and has no `liveRegion` parameter | **TRUE** | [`status_pill.dart:16-19`](lib/widgets/status_pill.dart:16) sets `container: true, liveRegion: true, label: 'Detection status: $label'`; the constructor takes only `label`/`color` ([`:9-12`](lib/widgets/status_pill.dart:9)) → the plan must add the optional parameter |
| 6 | `DetectionStatePanel` is the failure surface and a live region | **TRUE** | [`detection_state_panel.dart:40-43`](lib/widgets/detection_state_panel.dart:40) `container: true, liveRegion: true, label: '$title. $message'`; it is mounted only for the failed state at [`ultralytics_detection_screen.dart:1511-1517`](lib/screens/ultralytics_detection_screen.dart:1511) |
| 7 | Failure panel still offers `Retry` / `Stop` / `Open Settings` labels | **TRUE** | [`detection_state_panel.dart:88-107`](lib/widgets/detection_state_panel.dart:88) — `'Open Settings'` [`:90`](lib/widgets/detection_state_panel.dart:90), `'Retry'` [`:97`](lib/widgets/detection_state_panel.dart:97), `'Stop'` [`:104`](lib/widgets/detection_state_panel.dart:104). `onFallback` is **already removed** (absent from fields/ctor, [`:16-28`](lib/widgets/detection_state_panel.dart:16)) |
| 8 | Header `_modelError` duplicates the panel message | **ALREADY DONE** | [`ultralytics_detection_screen.dart:1483-1491`](lib/screens/ultralytics_detection_screen.dart:1483) already wraps it in `ExcludeSemantics`; the string assignment at [`:1276`](lib/screens/ultralytics_detection_screen.dart:1276) is unchanged. No further work in this task |
| 9 | Home has exactly one status node candidates at `:155-157` | **TRUE** | [`home_screen.dart:155-157`](lib/screens/home_screen.dart:155) `Semantics(container: true, label: presentation.meaning)` with the child excluded at [`:158`](lib/screens/home_screen.dart:158) |
| 10 | Home instruction copy is a second/third stop | **CHANGED → ALREADY DONE** | Both instruction `Text`s are already inside `ExcludeSemantics` ([`home_screen.dart:223-245`](lib/screens/home_screen.dart:223)). The remaining Home work is only identity: the `'Home. '` prefix and the wordmark header |
| 11 | Home wordmark is a bare `Text('EyeCue')` at `:104-108` | **TRUE** | [`home_screen.dart:104-108`](lib/screens/home_screen.dart:104) — plain `Text`, no `Semantics` wrapper; the decorative logo above it is already excluded ([`:95-102`](lib/screens/home_screen.dart:95)) |
| 12 | `'Detection Mode'` header `Text` at `:1451-1454` | **TRUE** | [`ultralytics_detection_screen.dart:1451-1454`](lib/screens/ultralytics_detection_screen.dart:1451) |
| 13 | `GestureSurface(child: viewport)` at `:1639` | **TRUE** | [`ultralytics_detection_screen.dart:1639`](lib/screens/ultralytics_detection_screen.dart:1639); the surface itself is a bare `Listener` with no semantics ([`gesture_surface.dart:32-42`](lib/widgets/gesture_surface.dart:32)) |
| 14 | Repeat custom action lives on the audio pill | **CHANGED (this is the relocation target, not an addition)** | Pill semantics at [`ultralytics_detection_screen.dart:1772-1783`](lib/screens/ultralytics_detection_screen.dart:1772); wiring at [`:1472`](lib/screens/ultralytics_detection_screen.dart:1472) |
| 15 | `_repeatAlert()` at `:1164-1167` | **CHANGED** | Actual declaration [`ultralytics_detection_screen.dart:1165-1168`](lib/screens/ultralytics_detection_screen.dart:1165) — medium haptic + `_tts.repeatLast()` |
| 16 | `swipeDown` dispatches `_repeatAlert` at `:1331-1332` | **CHANGED** | [`ultralytics_detection_screen.dart:1332-1333`](lib/screens/ultralytics_detection_screen.dart:1332) |
| 17 | `TtsService.repeatLast()` fails silently | **TRUE** | [`tts_service.dart:688-704`](lib/services/tts_service.dart:688) — `false` with no output when `_lastUtterance == null` ([`:690`](lib/services/tts_service.dart:690)) or when muted ([`:691-694`](lib/services/tts_service.dart:691)) |
| 18 | `TtsService` exposes the state needed to disambiguate | **TRUE** | `bool get audioEnabled` [`tts_service.dart:237`](lib/services/tts_service.dart:237); `String? get lastUtterance` [`:240`](lib/services/tts_service.dart:240) |
| 19 | Help has `Gesture Controls` / `Best Use Tip` / `How It Works` / `Gesture Confirmation` as one grouped body each | **TRUE** | Titles at [`help_screen.dart:68`](lib/screens/help_screen.dart:68), [`:79`](lib/screens/help_screen.dart:79), [`:90`](lib/screens/help_screen.dart:90), [`:98`](lib/screens/help_screen.dart:98); single body `Text` at [`:162`](lib/screens/help_screen.dart:162); heading semantics at [`:145-160`](lib/screens/help_screen.dart:145) |
| 20 | Help/Gesture copy says `press Start` | **TRUE** | [`help_screen.dart:71`](lib/screens/help_screen.dart:71) |
| 21 | `kSafetyDisclosureTitle` + dialog has no title | **TRUE** | Constant [`safety_disclosure.dart:15`](lib/widgets/safety_disclosure.dart:15); `AlertDialog` with `content:` only ([`:111-134`](lib/widgets/safety_disclosure.dart:111)); live lead banner [`:118-122`](lib/widgets/safety_disclosure.dart:118) whose liveness comes from [`warning_banner.dart:15-18`](lib/widgets/warning_banner.dart:15) |
| 22 | Stale copy `'…custom EyeCue mode.'` at `:1685-1689` | **CHANGED** | [`ultralytics_detection_screen.dart:1693-1697`](lib/screens/ultralytics_detection_screen.dart:1693) |
| 23 | Stale copy `'press Start'` sites | **CHANGED** | `kModelChangedMessage` [`ultralytics_detection_screen.dart:53-55`](lib/screens/ultralytics_detection_screen.dart:53); [`help_screen.dart:71`](lib/screens/help_screen.dart:71); **and** [`settings_screen.dart:730-731`](lib/screens/settings_screen.dart:730) (the brief cited `:744-746`) |
| 24 | Detector-model dropdown is a labelled-control gap | **TRUE** | `_ModelFilter` at [`logs_reports_screen.dart:2006-2054`](lib/screens/logs_reports_screen.dart:2006): sibling `Text('Detector model')` at [`:2025`](lib/screens/logs_reports_screen.dart:2025) and a bare `DropdownButton<String?>` at [`:2029`](lib/screens/logs_reports_screen.dart:2029) inside a `Row` ([`:2023-2050`](lib/screens/logs_reports_screen.dart:2023)). This is the only dropdown in `lib/` (repo search) |
| 25 | Shell horizontal navigation must not be touched | **NOT RE-VERIFIED (no change proposed)** | The brief's citation (`app_shell.dart:412-430`) was not re-read in this pass. Only [`app_shell.dart:395`](lib/navigation/app_shell.dart:395) (`MediaQuery.accessibleNavigationOf`) was read, to confirm the API exists in this tree. No file in `lib/navigation/` is in the change set |
| 26 | `AccessibleButton.label` is also the visible button text | **TRUE — constrains the copy changes** | [`accessible_button.dart:27-31`](lib/widgets/accessible_button.dart:27) sets `label:` on `Semantics`; [`:36-39`](lib/widgets/accessible_button.dart:36) renders `Text(label)`. Therefore **renaming `Retry`/`Stop`/`Open Settings` is a visible-copy change**, not a semantics-only change |
| 27 | Lifecycle card semantics already carry long-press + result-only hints | **ALREADY DONE** | [`detection_action_controls.dart:357-370`](lib/widgets/detection_action_controls.dart:357) (`onTap` gated for stopped, `onLongPress`, `onTapHint`, `onLongPressHint`), dispatch [`:307-319`](lib/widgets/detection_action_controls.dart:307) |

### 1.1 Consequences of the re-check for the plan

- The plan must **delete** the pill's custom action and **delete/rewrite** a currently-green test
  ([`test/screens/gesture_navigation_direction_test.dart:375-415`](test/screens/gesture_navigation_direction_test.dart:375)).
  This is a regression surface, not just an addition.
- Home and the failure path are already de-duplicated; the plan's Home/failure work is narrower than the brief implies
  (`'Home. '` prefix, wordmark header, pill liveness while failed).
- Copy changes on `Retry`/`Stop`/`Open Settings` are **visible** text changes. The brief scopes them in; the plan must
  state them as the intended visible deltas rather than claim "no visual change".

---

## 2. Feasibility notes for the two least-certain items

### 2.1 Distinguishing Repeat failure causes **without a service change** — verdict: FEASIBLE

`repeatLast()` has three distinct exit paths ([`tts_service.dart:688-704`](lib/services/tts_service.dart:688)):

| Cause | Service-internal condition | Return | Observable from the screen **without** a service change |
|---|---|---|---|
| Audio is off | `!_audioEnabled` ([`:691-694`](lib/services/tts_service.dart:691)) | `false` | **Yes** — `_tts.audioEnabled` getter ([`tts_service.dart:237`](lib/services/tts_service.dart:237)); the screen already reads audio state for the toggle at [`ultralytics_detection_screen.dart:1239-1242`](lib/screens/ultralytics_detection_screen.dart:1239) |
| Nothing has ever started | `_lastUtterance == null` ([`:689-690`](lib/services/tts_service.dart:689)) | `false` | **Yes** — `_tts.lastUtterance` getter ([`tts_service.dart:240`](lib/services/tts_service.dart:240)) |
| Cached utterance exists but the submission is refused (validity window / superseded) | `_submit(...)` result ([`:695-703`](lib/services/tts_service.dart:695), `validity: 10 s`) | `false` | **No** — indistinguishable from the previous case from outside; must fall back to the same generic wording |

**Conclusion.** The two causes the brief names are separable purely in UI code, so the two required strings are achievable
with **zero** `lib/services/` edits:
`!_tts.audioEnabled` → `'Audio guidance is off'`; otherwise `_tts.lastUtterance == null` → `'Nothing to repeat yet'`;
otherwise call `_tts.repeatLast()` and, if it still returns `false`, emit the same `'Nothing to repeat yet'` wording.
The screen must read `_tts.audioEnabled` (not `_settings.audioEnabled`) so the wording can never disagree with the service
that actually refused.

**Residual limitation to state in the plan, not fix:** the third row's cause cannot be named. No service change is
therefore required, and none is proposed.

### 2.2 Detector-model dropdown vs visual parity — verdict: `MergeSemantics`, **not** `DropdownButtonFormField`

Verified against the installed SDK (`package:flutter/src/material/dropdown.dart`, read through the Dart MCP
`read_package_uris` tool — not from memory):

| Mechanism | Verified behaviour | Visual impact |
|---|---|---|
| `DropdownButton.build` | Returns `Semantics(button: !childHasButtonSemantic, expanded: _isMenuExpanded, child: Actions(...))` — a **non-container** annotation, so it merges upward into the nearest grouping node | none |
| `DropdownMenuItem` (via `_DropdownMenuItemContainer`) | Returns `Semantics(button: true, child: ConstrainedBox(...))` — also **non-container** | none |
| `DropdownButtonFormField` | Renders the same `DropdownButton` **inside an `InputDecorator`** with `decoration` applied, `isDense: true` by default, and `suffixIcon` constraints/padding recomputed (`suffixIconConstraints`, `suffixIconEndMargin`) | **structural**: introduces a decorator border/underline, changes intrinsic height and horizontal padding, and relocates the arrow glyph |

Because the brief makes visual parity a hard constraint, `DropdownButtonFormField` is rejected: reproducing
[`logs_reports_screen.dart:2022-2053`](lib/screens/logs_reports_screen.dart:2022) exactly would require decoration/padding
tuning that is a design change, not a semantics change.

`MergeSemantics` around the existing `Row` ([`:2023-2050`](lib/screens/logs_reports_screen.dart:2023)) is the correct
mechanism: both the label `Text` and the dropdown's non-container annotations merge into one node carrying
`Detector model` + the selected item + `button`/`expanded` + the tap action, with **zero layout, paint, or focus change**.

**Needs Verification (test/device):** whether the merged node still exposes a usable `tap` action and whether the selected
value is announced after selection. `MergeSemantics` does not guarantee an action survives if an intermediate node is a
container; the SDK read above shows none on this path, but only a semantics-tree test can confirm the effective node shape.

---

## 3. Tests that encode the behaviour this task changes

Only assertions that will **fail or become misleading** are listed. Line numbers are current-tree.

| Test | Location | Encodes | Why it must change |
|---|---|---|---|
| `the audio pill is one node with a Repeat last alert action` | [`test/screens/gesture_navigation_direction_test.dart:375-415`](test/screens/gesture_navigation_direction_test.dart:375) | `expect(labelled, ['Repeat last alert'])` ([`:397`](test/screens/gesture_navigation_direction_test.dart:397)) and the invocation at [`:400-411`](test/screens/gesture_navigation_direction_test.dart:400) | The pill must expose **no** custom action; the same assertions move to the camera-view node |
| Permission-denied panel taps | [`test/screens/gesture_navigation_direction_test.dart:358-372`](test/screens/gesture_navigation_direction_test.dart:358) | `find.text('Open Settings')` / `find.text('Retry')` ([`:358`](test/screens/gesture_navigation_direction_test.dart:358), [`:369`](test/screens/gesture_navigation_direction_test.dart:369), [`:371`](test/screens/gesture_navigation_direction_test.dart:371)) | Both labels are renamed |
| Home meanings ×5 | [`test/accessibility/semantics_test.dart:459`](test/accessibility/semantics_test.dart:459), [`:475`](test/accessibility/semantics_test.dart:475), [`:497`](test/accessibility/semantics_test.dart:497), [`:511`](test/accessibility/semantics_test.dart:511), [`:520`](test/accessibility/semantics_test.dart:520), [`:539`](test/accessibility/semantics_test.dart:539) | Exact label strings with no `Home. ` prefix | The prefix is folded into the same node |
| `expectButtonSemantics(tester, 'Retry')` / `('Stop')`, and the taps | [`test/accessibility/semantics_test.dart:286-291`](test/accessibility/semantics_test.dart:286) | Panel button labels | Renamed for context |
| Wordmark assertions | [`test/accessibility/semantics_test.dart:461`](test/accessibility/semantics_test.dart:461), [`:498`](test/accessibility/semantics_test.dart:498), [`:552`](test/accessibility/semantics_test.dart:552) | `byLabel('EyeCue')` length 1 | **Still pass** (label unchanged) — extend with a `header` flag assertion instead of rewriting |
| Help section headings | [`test/accessibility/semantics_test.dart:614-625`](test/accessibility/semantics_test.dart:614) | Heading nodes for the four cards, length 1 | Should still pass if the title semantics are preserved verbatim; re-check after extracting the card widget |
| Help copy assertions | [`test/widget_test.dart:344-420`](test/widget_test.dart:344) | `find.textContaining('Two-finger double tap — start or exit')` ([`:402`](test/widget_test.dart:402)), Best Use Tip bullets ([`:415-420`](test/widget_test.dart:415)), `'1. Open EyeCue.'` ([`:395`](test/widget_test.dart:395)) | Pass **only** if the per-item split preserves the exact bullet strings; the `press Start` fix breaks the How-It-Works step string at [`help_screen.dart:71`](lib/screens/help_screen.dart:71) |
| `StatusPill` live region | [`test/accessibility/semantics_test.dart:181-184`](test/accessibility/semantics_test.dart:181) | Pill is live | Unaffected if the new parameter defaults to `true`; add a failed-state case |
| State panel live region | [`test/accessibility/semantics_test.dart:279-293`](test/accessibility/semantics_test.dart:279) | Panel is live and its buttons work | Panel liveness is retained; only labels change |
| `'Detection started'` speech | [`test/screens/gesture_navigation_direction_test.dart:317`](test/screens/gesture_navigation_direction_test.dart:317), [`:339`](test/screens/gesture_navigation_direction_test.dart:339) | Default (non-TalkBack) start speech | **Must keep passing** — these pin the gated path's unaffected behaviour |
| Two-control row / no visible `Start`/`Stop` | [`test/screens/ultralytics_detection_screen_layout_test.dart:108-118`](test/screens/ultralytics_detection_screen_layout_test.dart:108), [`test/screens/detection_screen_layout_test.dart:107-113`](test/screens/detection_screen_layout_test.dart:107), [`test/widget_test.dart:507-517`](test/widget_test.dart:507) | `find.text('Stop')`/`'Start'` find nothing | Still pass **only** because `find.text` matches whole strings — the renames must not produce an exact `'Stop'` |
| `Detection Mode` visible title | [`test/widget_test.dart:455-472`](test/widget_test.dart:455), [`test/screens/detection_redesign_parity_test.dart:92`](test/screens/detection_redesign_parity_test.dart:92) | Visible `Text` | Visible text is unchanged by the header promotion; assertions stay |

No test asserts the stale copy (`custom EyeCue mode`, `press Start`) or the dropdown label today, so §5 of the plan adds
new coverage rather than amending existing coverage for those.

---

## 4. `lib/services/` and `lib/models/` impact — none required

| Directory | Needed? | Evidence |
|---|---|---|
| `lib/services/tts_service.dart` | **No** | `repeatLast()` ([`:688-704`](lib/services/tts_service.dart:688)) and the two observable getters ([`:237`](lib/services/tts_service.dart:237), [`:240`](lib/services/tts_service.dart:240)) are sufficient for UI-side cause discrimination (§2.1) |
| `lib/services/haptics_service.dart` | **No** | `lightTick`/`mediumTick`/`heavyTick` already used by the screen ([`ultralytics_detection_screen.dart:934`](lib/screens/ultralytics_detection_screen.dart:934), [`:1161`](lib/screens/ultralytics_detection_screen.dart:1161), [`:1166`](lib/screens/ultralytics_detection_screen.dart:1166)); the distinct failure cue reuses `heavyTick` |
| `lib/models/` | **No** | Nothing in the change set reads a new model field |

**Standing scope exception (flag only, do not plan):** if implementation finds it needs a typed repeat-failure reason
(for example a `RepeatOutcome` return from `repeatLast()`) to distinguish the third cause in §2.1, that is a
`lib/services/` change and must be **stopped and flagged** as a scope exception rather than implemented.

---

## 5. Open Questions / Needs Verification (device-only)

| # | Item | Tag | Default recorded |
|---|---|---|---|
| D1 | Does the target TalkBack build announce a **zero-size** live-region node (planned mechanism for Repeat failure feedback without adding visible text)? | `[needs-device-verification]` | Assume yes; if not, the fallback is a transient caption in the existing model-change notice slot, which is a visible addition and must be reported |
| D2 | After the `Semantics(container: true, explicitChildNodes: true)` wrapper is added around the viewport, does the overlay's per-row informational node stay a **separate, non-live** stop? | `[needs-device-verification]` | Assume yes (explicit child nodes preserve them); confirm no merge into `Camera view` |
| D3 | Does the `Repeat last alert` custom action remain reachable on a node that also contains a platform view (`YOLOView`)? | `[needs-device-verification]` | Assume yes; the action is on our own node, not the platform view's |
| D4 | Is `'Nothing to repeat yet'` announced as a change when the previous label was identical (repeat pressed twice in a row)? | `[needs-device-verification]` | Assume the platform re-announces on label change only; a repeated identical label may be silent |
| D5 | Does the merged `_ModelFilter` node expose `tap` and re-announce the selected value after selection? | `[needs-device-verification]` | Assume yes; verify the effective node shape on device |
| D6 | Does removing the lead banner's liveness in the safety dialog leave exactly one entry announcement? | `[needs-device-verification]` | Assume the disclosure heading is the single entry announcement |

No device-only item in this table blocks writing the plan; each has a stated default.
