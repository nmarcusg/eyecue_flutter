# TalkBack Semantics Analysis

**Stage:** 1 of 5 — Analysis only.

**Task type:** semantics-only accessibility change, no visual output change expected → design-spec stage does not apply; the downstream plan works directly from this analysis.

**Scope discipline:** one output file (this document). No source, test, or existing doc edits. No `flutter analyze` / `flutter test` / builds were run. Every claim below is grounded in a current-tree `path:line` read or an official Flutter API page fetched during this pass; anything else is tagged **Needs Verification** per `.roo/rules/01-verification-policy.md`.

**Verification sources used**

- Current working tree (read-only inspection).
- `api.flutter.dev` pages for `SemanticsProperties.onLongPress`, `SemanticsConfiguration.customSemanticsActions`, `CustomSemanticsAction`, `SemanticsHintOverrides`, `SemanticsConfiguration.hintOverrides`, and `Semantics` constructor — plus `flutter/flutter` issues #14402, #60436, #35112 for Android hint/action behaviour.
- Context7 was **unavailable** during this pass (`fetch failed`), so Flutter API facts were verified directly against `api.flutter.dev` and `flutter/flutter` instead. This is recorded so the plan stage does not assume Context7 confirmation happened.

---

## 0. Executive summary

The app already has broad, deliberate semantics work. The remaining problems are structural, not missing-label problems:

1. **Stop/Start is unreachable through TalkBack.** The consolidated lifecycle control exposes only `onTap` ([`detection_action_controls.dart:292`](lib/widgets/detection_action_controls.dart:292)); the three-second hold lives entirely in a raw `Listener` with timers ([`detection_action_controls.dart:294-298`](lib/widgets/detection_action_controls.dart:294), [`detection_action_controls.dart:161-186`](lib/widgets/detection_action_controls.dart:161)). A screen-reader user can Pause/Resume but can never Stop or Start detection.
2. **Repeat Last Alert is unreachable through any non-gesture path.** `_repeatAlert()` exists ([`ultralytics_detection_screen.dart:1164-1167`](lib/screens/ultralytics_detection_screen.dart:1164)) but is reached only from `EyeCueGesture.swipeDown` ([`ultralytics_detection_screen.dart:1331-1332`](lib/screens/ultralytics_detection_screen.dart:1331)), and the viewport gesture surface exposes no semantics at all ([`gesture_surface.dart:32-42`](lib/widgets/gesture_surface.dart:32)).
3. **The semantics tree teaches TalkBack its own interaction language.** On Android, a node's `hint` is read *in addition to* the platform's own hint; `flutter/flutter#60436` records Android voicing `label – hint – button – hint`. EyeCue currently supplies hints such as `'Double tap to pause. Hold for three seconds to stop.'` ([`detection_action_controls.dart:379-395`](lib/widgets/detection_action_controls.dart:379)) and `'Double tap to activate'` ([`accessible_button.dart:31`](lib/widgets/accessible_button.dart:31)) to 27 button instances.
4. **Fragmented / duplicated nodes** exist on Home, Settings sliders, Logs & Reports, the failure path, and the audio pill (inventory in §2).
5. **The evidence base's engine assumption is stale.** `lib/screens/detection_screen.dart` no longer exists; the Custom EyeCue engine was removed and the app is single-engine (`test/architecture/no_custom_engine_test.dart:5-21` forbids its tokens). Every Custom-engine reference in the prior pass, and in `docs/frontend-workflow/detection-redesign-plan.md`, is now wrong.

### Recommended decisions (for the plan to execute, not to re-litigate)

| # | Decision | Mechanism |
|---|---|---|
| D1 | Make Stop/Start operable from the existing lifecycle card, without a third control or a measured hold | `Semantics.onLongPress` on the lifecycle node, mapped to the same `onStop`/`onStart` outcome dispatch; gesture-teaching hints removed; `hintOverrides.onLongPressHint` supplies the result wording on Android |
| D2 | Make Repeat Last Alert operable without a visible control | `CustomSemanticsAction(label: 'Repeat last alert')` on the audio pill, wired to the existing `_repeatAlert()` |
| D3 | Stop the node from advertising a tap action that does nothing | `onTap` becomes `null` for the `stopped` outcome |
| D4 | Remove all platform-taught wording from semantic hints | Drop `hint` on the lifecycle card, Quick Scan (when enabled) and `AccessibleButton`; use `hintOverrides` only where a second action exists |
| D5 | De-duplicate by excluding redundant visual text behind an explicit label node | `ExcludeSemantics` on duplicated `Text` children; remove wrappers whose label duplicates an un-excluded `Text` |
| D6 | Keep framework-owned semantics untouched | `SwitchListTile`, `RadioListTile`, `Slider` value/actions, charts, the detection overlay, and the safety-disclosure heading keep their current treatment |

---

## 1. Re-verification table

Verdicts: **TRUE** (claim holds, line numbers still accurate), **CHANGED** (claim holds but the cited location/context moved or the surrounding architecture changed), **WRONG** (claim does not hold), **WRONG → corrected** (claim's substance was misleading and is restated).

| # | Prior claim | Verdict | Current evidence |
|---|---|---|---|
| 1 | ONE semantic node for the lifecycle card | **TRUE** | [`detection_action_controls.dart:284-298`](lib/widgets/detection_action_controls.dart:284) — `Semantics(numbered props) → ExcludeSemantics → Listener` |
| 2 | Label is `PAUSE`/`RESUME`/`START`/`PREPARING`/`UNAVAILABLE` | **TRUE** | `_primaryLabel` [`detection_action_controls.dart:129-135`](lib/widgets/detection_action_controls.dart:129); applied at [`detection_action_controls.dart:287`](lib/widgets/detection_action_controls.dart:287) |
| 3 | Value is `HOLD 3 SEC TO STOP` / `KEEP HOLDING` / `HOLD 3 SEC` / label | **TRUE** | constants [`detection_action_controls.dart:20`](lib/widgets/detection_action_controls.dart:20), [`:23`](lib/widgets/detection_action_controls.dart:23), [`:26`](lib/widgets/detection_action_controls.dart:26); `_secondaryLabel` [`:150-159`](lib/widgets/detection_action_controls.dart:150); fallback `secondary ?? _primaryLabel` at [`:288`](lib/widgets/detection_action_controls.dart:288) |
| 4 | Hint teaches gestures and names two actions | **TRUE** | `_lifecycleHint()` [`detection_action_controls.dart:379-395`](lib/widgets/detection_action_controls.dart:379); strings at [`:387`](lib/widgets/detection_action_controls.dart:387), [`:389`](lib/widgets/detection_action_controls.dart:389), [`:391`](lib/widgets/detection_action_controls.dart:391) |
| 5 | `button: true`, `enabled`, `onTap: _dispatchTap`; stopped tap is a deliberate no-op | **TRUE** | [`detection_action_controls.dart:285-292`](lib/widgets/detection_action_controls.dart:285); `_dispatchTap` [`:235-248`](lib/widgets/detection_action_controls.dart:235); stopped branch [`:241-243`](lib/widgets/detection_action_controls.dart:241) |
| 6 | Whole `Listener` subtree is `ExcludeSemantics`d | **TRUE** | [`detection_action_controls.dart:293`](lib/widgets/detection_action_controls.dart:293) |
| 7 | No `onLongPress`, no `customSemanticsActions`, no state flags | **TRUE** | repo-wide grep for `onLongPress`, `onLongPressHint`, `onTapHint`, `customSemanticsActions` across `lib/` returns **zero** hits |
| 8 | 3-second hold is raw `Listener` + timers; one-shot lock | **TRUE** | `kLifecycleHoldDuration` [`detection_action_controls.dart:17`](lib/widgets/detection_action_controls.dart:17); `_startHold` [`:161-186`](lib/widgets/detection_action_controls.dart:161); `kLongPressTimeout` copy swap [`:180-183`](lib/widgets/detection_action_controls.dart:180); `_consumed` set [`:195`](lib/widgets/detection_action_controls.dart:195), guards [`:162`](lib/widgets/detection_action_controls.dart:162) and [`:189`](lib/widgets/detection_action_controls.dart:189), reset on outcome change [`:105`](lib/widgets/detection_action_controls.dart:105) |
| 9 | Quick Scan node = label/hint/enabled/onTap; hint teaches gesture | **TRUE** | [`detection_action_controls.dart:401-408`](lib/widgets/detection_action_controls.dart:401); gesture wording at [`:406`](lib/widgets/detection_action_controls.dart:406) |
| 10 | `AccessibleButton` injects `'Unavailable'` / `'Double tap to activate'`; 28 use sites | **CHANGED** | hint injection is [`accessible_button.dart:31`](lib/widgets/accessible_button.dart:31) — **TRUE**; instantiation count is **27** (4 detection screen, 3 settings, 4 state panel, 1 safety disclosure, 11 Logs & Reports, 4 correction sheet), not 28 |
| 11 | `_repeatAlert()` only reachable from `swipeDown`; `repeatLast()` public | **TRUE (one engine only)** | [`ultralytics_detection_screen.dart:1164-1167`](lib/screens/ultralytics_detection_screen.dart:1164), dispatch [`ultralytics_detection_screen.dart:1319-1340`](lib/screens/ultralytics_detection_screen.dart:1319), [`tts_service.dart:687-704`](lib/services/tts_service.dart:687) |
| 12 | `_startDetection` / `_stopDetection` exist and are injected | **TRUE** | [`ultralytics_detection_screen.dart:806-874`](lib/screens/ultralytics_detection_screen.dart:806), [`ultralytics_detection_screen.dart:876-916`](lib/screens/ultralytics_detection_screen.dart:876), injection at [`:1725-1732`](lib/screens/ultralytics_detection_screen.dart:1725) |
| 13 | Custom screen `lib/screens/detection_screen.dart` exists and duplicates this UI | **WRONG** | file absent from `lib/screens/` (only `engine_detection_screen.dart`, `help_screen.dart`, `home_screen.dart`, `logs_reports_screen.dart`, `settings_screen.dart`, `ultralytics_detection_screen.dart`); [`engine_detection_screen.dart:12`](lib/screens/engine_detection_screen.dart:12) imports only the Ultralytics screen; [`no_custom_engine_test.dart:11-21`](test/architecture/no_custom_engine_test.dart:11) forbids Custom-engine tokens |
| 14 | Home shows the status three ways | **TRUE** | badge node label = combined `meaning` [`home_screen.dart:155-157`](lib/screens/home_screen.dart:155) with child excluded [`:158`](lib/screens/home_screen.dart:158); instruction headline [`home_screen.dart:221-227`](lib/screens/home_screen.dart:221) and supporting [`home_screen.dart:230-238`](lib/screens/home_screen.dart:230) are un-excluded `Text`s; `meaning` strings already concatenate headline + supporting, e.g. [`:307`](lib/screens/home_screen.dart:307) |
| 15 | Settings sliders are 3–4 stops (wrapper + Text + Slider) | **TRUE** | advanced: wrapper [`settings_screen.dart:375-379`](lib/screens/settings_screen.dart:375), title `Text` [`:385-388`](lib/screens/settings_screen.dart:385), `Slider` [`:390-414`](lib/screens/settings_screen.dart:390); detection cadence [`:524-552`](lib/screens/settings_screen.dart:524); depth cadence [`:556-591`](lib/screens/settings_screen.dart:556) |
| 16 | `SwitchListTile` toggles are already one correct merged node, cited at `:98-105` | **CHANGED** | the claim holds but the cited block is not the switch block in the current file; verified switch: [`settings_screen.dart:512-523`](lib/screens/settings_screen.dart:512). Framework-owned merged semantics — do not touch |
| 17 | Logs & Reports has ~8 `Semantics(label:)` + identical `Text` duplicates; up to 3 stops per interval row; snackbar at `:352-366` | **TRUE** | snackbar [`logs_reports_screen.dart:352-366`](lib/screens/logs_reports_screen.dart:352); section wrapper + identical title [`logs_reports_screen.dart:907-919`](lib/screens/logs_reports_screen.dart:907); annotation-style duplicate [`:921-924`](lib/screens/logs_reports_screen.dart:921); 3-stop interval row [`:1042-1060`](lib/screens/logs_reports_screen.dart:1042); export section [`:1089-1101`](lib/screens/logs_reports_screen.dart:1089); corrections section [`:1197-1209`](lib/screens/logs_reports_screen.dart:1197); correction row [`:1231-1246`](lib/screens/logs_reports_screen.dart:1231); model claim [`:1564-1573`](lib/screens/logs_reports_screen.dart:1564); research session [`:2088-2100`](lib/screens/logs_reports_screen.dart:2088) |
| 18 | 9 section titles are not `header` | **WRONG → corrected** | no `header: true` exists anywhere in `logs_reports_screen.dart` (repo grep for `header: true` returns only [`help_screen.dart:150`](lib/screens/help_screen.dart:150), [`settings_screen.dart:883`](lib/screens/settings_screen.dart:883), [`:971`](lib/screens/settings_screen.dart:971), [`safety_disclosure.dart:48`](lib/widgets/safety_disclosure.dart:48)). The count is not 9; the correct statement is "every Logs & Reports section title is a plain text node with no heading semantics" |
| 19 | Audio pill: `Semantics(button, enabled, label)` with no `container` and no `onTap` | **TRUE (widget-level) / needs device nuance** | [`ultralytics_detection_screen.dart:1759-1762`](lib/screens/ultralytics_detection_screen.dart:1759); the tap action originates from `InkWell` [`:1774-1776`](lib/screens/ultralytics_detection_screen.dart:1774) and is very likely merged into the same node (annotation semantics merge into descendants). Effective-node composition is therefore **Needs Verification [device]** — the plan must still attach `label` + `onTap` to one explicit `container` node |
| 20 | Failure state is announced multiple times | **TRUE, and worse than stated** | pill `liveRegion` [`status_pill.dart:16-19`](lib/widgets/status_pill.dart:16); panel `liveRegion` [`detection_state_panel.dart:42-45`](lib/widgets/detection_state_panel.dart:42); card `UNAVAILABLE` [`detection_action_controls.dart:134`](lib/widgets/detection_action_controls.dart:134); header `_modelError` `Text` [`ultralytics_detection_screen.dart:1477-1483`](lib/screens/ultralytics_detection_screen.dart:1477) — and `_modelError` is assigned `failure.userMessage` [`:1275`](lib/screens/ultralytics_detection_screen.dart:1275), i.e. the **same string** the state panel already speaks |
| 21 | Tests encode the defects | **TRUE** | [`detection_action_controls_test.dart:431`](test/widgets/detection_action_controls_test.dart:431), [`:449`](test/widgets/detection_action_controls_test.dart:449); [`semantics_test.dart:141-143`](test/accessibility/semantics_test.dart:141), [`:157`](test/accessibility/semantics_test.dart:157), [`:894-911`](test/accessibility/semantics_test.dart:894), [`:472-495`](test/accessibility/semantics_test.dart:472), [`:207-227`](test/accessibility/semantics_test.dart:207) |
| 22 | Stale user-facing copy | **TRUE** | `'…custom EyeCue mode.'` [`ultralytics_detection_screen.dart:1685-1689`](lib/screens/ultralytics_detection_screen.dart:1685); `'…press Start…'` [`ultralytics_detection_screen.dart:52-54`](lib/screens/ultralytics_detection_screen.dart:52), [`help_screen.dart:71`](lib/screens/help_screen.dart:71); also [`settings_screen.dart:744-746`](lib/screens/settings_screen.dart:744) `'Press Start on the Detection screen'` |

### Additional findings not in the prior evidence base

- **A4.** EyeCue TTS and the live-region pill both fire on every lifecycle change: `_pauseDetection` speaks `'Detection paused'` ([`ultralytics_detection_screen.dart:940`](lib/screens/ultralytics_detection_screen.dart:940)), `_resumeDetection` `'Detection resumed'` ([`:956`](lib/screens/ultralytics_detection_screen.dart:956)), `_stopDetection` `'Detection stopped'` ([`:915`](lib/screens/ultralytics_detection_screen.dart:915)), while the pill is a live region keyed to the same transition. With TalkBack on, two speech engines talk over each other. **Only a device pass can decide the mitigation** (see §6 and §10).
- **A5.** Model-change notice is a second `liveRegion` while the pill also changes ([`ultralytics_detection_screen.dart:1402-1414`](lib/screens/ultralytics_detection_screen.dart:1402)).
- **A6.** The never-started surface still exposes a visible `'Start Detection'` button ([`ultralytics_detection_screen.dart:1691-1696`](lib/screens/ultralytics_detection_screen.dart:1691)) whose hint is `'Double tap to activate'` — the only *working* Start path for a TalkBack user today, and it is not the control row.
- **A7.** `detection_information_overlay.dart` is already correct — one non-live node per row with an excluded child ([`detection_information_overlay.dart:116-119`](lib/widgets/detection_information_overlay.dart:116)). It is the reference pattern for the de-duplication work and must not be touched.
- **A8.** `safety_disclosure.dart` is already correct — grouped container, `header: true`, excluded title, one node per point ([`safety_disclosure.dart:41-74`](lib/widgets/safety_disclosure.dart:41)). This contradicts the brief's assertion that `docs/testing-plan.md:108` is a false claim (see §9).

---

## 2. Effective semantics inventory

Strings are verbatim from the tree. "Stops" = distinct screen-reader stops a TalkBack user traverses.

### 2.1 Detection — consolidated lifecycle card ([`detection_action_controls.dart:278-296`](lib/widgets/detection_action_controls.dart:278))

Single node. Child subtree excluded. No long-press action. No custom actions.

| Outcome | `label` | `value` | `hint` | `button` | `enabled` | `onTap` | Visible secondary text |
|---|---|---|---|---|---|---|---|
| ready | `PAUSE` | `HOLD 3 SEC TO STOP` | `Double tap to pause. Hold for three seconds to stop.` | true | true | Pause | `HOLD 3 SEC TO STOP` |
| paused | `RESUME` | `HOLD 3 SEC TO STOP` | `Double tap to resume. Hold for three seconds to stop.` | true | true | Resume | `HOLD 3 SEC TO STOP` |
| stopped | `START` | `HOLD 3 SEC` | `Hold for three seconds to start detection.` | true | true | no-op | `HOLD 3 SEC` |
| preparing | `PREPARING` | `PREPARING` | `Detection is preparing` | true | false | null | none |
| unavailable | `UNAVAILABLE` | `UNAVAILABLE` | `Detection is unavailable` | true | false | null | none |
| during hold (ready/paused) | unchanged | `KEEP HOLDING` | unchanged | true | false (because `_consumed` is not yet set but `_holding` is true — `enabled` is `_lifecycleEnabled && !_consumed`, unchanged by holding) | Pause/Resume | `KEEP HOLDING` |
| after completed hold | unchanged | `KEEP HOLDING` until outcome change | unchanged | true | false (`_consumed` true, [`detection_action_controls.dart:280`](lib/widgets/detection_action_controls.dart:280)) | null | `KEEP HOLDING` |

Note: during a hold the value becomes the instruction `KEEP HOLDING` ([`detection_action_controls.dart:151`](lib/widgets/detection_action_controls.dart:151)) — a *state instruction* in the `value` slot, which TalkBack may announce on every focus event while the physical hold runs.

### 2.2 Detection — Quick Scan card ([`detection_action_controls.dart:397-408`](lib/widgets/detection_action_controls.dart:397))

| State | `label` | `hint` | `button` | `enabled` | `onTap` |
|---|---|---|---|---|---|
| ready | `QUICK SCAN` | `Double tap to scan the scene` | true | true | Quick Scan |
| any other outcome, or while a lifecycle hold is active | `QUICK SCAN` | `Quick Scan is available only while detection is ready` | true | false | null |

Visible children `'QUICK SCAN'` and `'TAP'` are excluded ([`detection_action_controls.dart:409-411`](lib/widgets/detection_action_controls.dart:409), [`:443-458`](lib/widgets/detection_action_controls.dart:443)).

### 2.3 Detection — audio pill ([`ultralytics_detection_screen.dart:1745-1817`](lib/screens/ultralytics_detection_screen.dart:1745))

| Property | Value |
|---|---|
| `label` | `Audio guidance, on` / `Audio guidance, off` ([`:1762`](lib/screens/ultralytics_detection_screen.dart:1762)) |
| `button` / `enabled` | true / hard-coded true ([`:1760-1761`](lib/screens/ultralytics_detection_screen.dart:1760)) |
| `container` | not set |
| `onTap` | not on the `Semantics`; supplied by `InkWell` ([`:1774-1776`](lib/screens/ultralytics_detection_screen.dart:1774)) |
| tooltip semantics | from `Tooltip` ([`:1763-1764`](lib/screens/ultralytics_detection_screen.dart:1763)) — `Mute audio guidance` / `Unmute audio guidance` ([`:1466-1468`](lib/screens/ultralytics_detection_screen.dart:1466)) |
| excluded children | dot and `AUDIO ON/OFF` text ([`:1789-1808`](lib/screens/ultralytics_detection_screen.dart:1789)) |

### 2.4 Home — status trio ([`home_screen.dart:135-257`](lib/screens/home_screen.dart:135))

| Node | Label | Live | Excluded content |
|---|---|---|---|
| `_StatusBadge` | the combined `meaning` string, e.g. `Ready. Ready when you are. Detection is ready.` ([`:307`](lib/screens/home_screen.dart:307)) | no | badge text + dot |
| instruction headline `Text` | `Ready when you are` ([`:222`](lib/screens/home_screen.dart:222)) | no | — |
| instruction supporting `Text` | `Detection is ready.` ([`:231`](lib/screens/home_screen.dart:231)) | no | — |
| decorative rail | — | — | excluded ([`:243-250`](lib/screens/home_screen.dart:243)) |

All five `meaning` strings are at [`home_screen.dart:297-299`](lib/screens/home_screen.dart:297), [`:307`](lib/screens/home_screen.dart:307), [`:315`](lib/screens/home_screen.dart:315), [`:323`](lib/screens/home_screen.dart:323), [`:332`](lib/screens/home_screen.dart:332). The preparing meaning contains `Swipe left to start!` ([`:298`](lib/screens/home_screen.dart:298)) — wording that describes a gesture TalkBack consumes.

### 2.5 Settings — three sliders

| Slider | Wrapper node label | Duplicate `Text` node | `Slider` node |
|---|---|---|---|
| advanced threshold | `Advanced detection confidence threshold, 0.25` ([`:377-379`](lib/screens/settings_screen.dart:377)) | `Advanced threshold: 0.25` ([`:386`](lib/screens/settings_screen.dart:386)) | value/`increase`/`decrease` ([`:390-414`](lib/screens/settings_screen.dart:390)) |
| detection cadence | `Detector cadence target, 15 Hz` ([`:526`](lib/screens/settings_screen.dart:526)) | `Detector cadence target: 15 Hz` ([`:533`](lib/screens/settings_screen.dart:533)) | slider ([`:537-552`](lib/screens/settings_screen.dart:537)) |
| depth cadence | `Depth cadence target, 5 Hz` + optional `, disabled in bounding box mode` ([`:559-561`](lib/screens/settings_screen.dart:559)) | `Depth cadence target: 5 Hz` ([`:573`](lib/screens/settings_screen.dart:573)) | slider ([`:577-591`](lib/screens/settings_screen.dart:577)) |

Captions also remain their own text nodes ([`:417-419`](lib/screens/settings_screen.dart:417), [`:592-600`](lib/screens/settings_screen.dart:592)). **Differentiator defect:** the cadence sliders range 15–30 and 1–10 ([`:539-540`](lib/screens/settings_screen.dart:539), [`:579-580`](lib/screens/settings_screen.dart:579)), so the platform default announces them as percentages — the plan should add `semanticFormatterCallback` so the spoken value is hertz.

### 2.6 Logs & Reports — duplicate/fragmented sites

| Site | Composition | Stops |
|---|---|---|
| snackbar `_showMessage` ([`:352-366`](lib/screens/logs_reports_screen.dart:352)) | live `container` + `label: message` + **un-excluded** `Text(message)` | 2 |
| alert-latency section ([`:907-919`](lib/screens/logs_reports_screen.dart:907)) | `container` + `label` + un-excluded identical title `Text` | 2 |
| per-engine speech latency note ([`:921-924`](lib/screens/logs_reports_screen.dart:921)) | annotation `Semantics(label: X)` + `Text(X)` → merged, label repeated | 1 (duplicated text) |
| `_AlertIntervalRow` ([`:1042-1060`](lib/screens/logs_reports_screen.dart:1042)) | `label: '$label: $value'` + `Text(label)` + `Text(value)` | 3 |
| export section ([`:1089-1101`](lib/screens/logs_reports_screen.dart:1089)) | `label: 'Offline telemetry export'` + identical `Text` | 2 |
| research upload section ([`:1138`](lib/screens/logs_reports_screen.dart:1138)) | plain title `Text`, no group node | 1+ |
| corrections section ([`:1197-1209`](lib/screens/logs_reports_screen.dart:1197)) | `label: 'Correction reports, N recorded'` + `Text('Correction reports')` | 2 |
| `_CorrectionSummaryRow` ([`:1231-1246`](lib/screens/logs_reports_screen.dart:1231)) | `label` (comma form) + `Text` (dot form) | 2 |
| priority dot ([`:1518-1521`](lib/screens/logs_reports_screen.dart:1518)) | `label: wording` + excluded icon | 1 — **correct, leave** |
| model claim ([`:1564-1573`](lib/screens/logs_reports_screen.dart:1564)) | `label: modelClaim` + `Text(modelClaim)` | 1 (duplicated text) |
| research session card ([`:2088-2100`](lib/screens/logs_reports_screen.dart:2088)) | `label: 'Research session: $stateLabel'` + un-excluded `Text(stateLabel)` + body text | 2+ |

### 2.7 Detection — failure surfaces

| Surface | Node | Live | Notes |
|---|---|---|---|
| `StatusPill` ([`status_pill.dart:16-19`](lib/widgets/status_pill.dart:16)) | `Detection status: Unavailable` | **yes** | excluded text/icon |
| `DetectionStatePanel` ([`detection_state_panel.dart:42-45`](lib/widgets/detection_state_panel.dart:42)) | `'$title. $message'`, e.g. `Engine initialization. The recommended engine could not start.` | **yes** | title/message excluded; action buttons at [`:90-115`](lib/widgets/detection_state_panel.dart:90) |
| lifecycle card | `UNAVAILABLE` / value `UNAVAILABLE` / hint `Detection is unavailable` | no | disabled |
| header `_modelError` ([`ultralytics_detection_screen.dart:1477`](lib/screens/ultralytics_detection_screen.dart:1477)) | the same `failure.userMessage` ([`:1275`](lib/screens/ultralytics_detection_screen.dart:1275)) | no | plain `Text` |

### 2.8 Safety dialog ([`safety_disclosure.dart:102-137`](lib/widgets/safety_disclosure.dart:102))

| Element | Node |
|---|---|
| lead `WarningBanner` ([`:120-122`](lib/widgets/safety_disclosure.dart:120)) | `Warning. Read this before you rely on EyeCue.` — **live region** ([`warning_banner.dart:15-18`](lib/widgets/warning_banner.dart:15)) |
| disclosure group ([`safety_disclosure.dart:41-74`](lib/widgets/safety_disclosure.dart:41)) | `header: true` title node, then one `container` node per bullet |
| acknowledge action ([`:126-131`](lib/widgets/safety_disclosure.dart:126)) | `AccessibleButton('I understand')` → `button/enabled/label/hint='Double tap to activate'` |

### 2.9 `AccessibleButton` ([`accessible_button.dart:27-53`](lib/widgets/accessible_button.dart:27))

| Property | Enabled | Disabled |
|---|---|---|
| `button` | true | true |
| `label` | caller label | caller label |
| `enabled` | true | false |
| `hint` | `Double tap to activate` | `Unavailable` |
| `onTap` | callback | null |
| child | `ExcludeSemantics(ElevatedButton.icon)` | same |

27 instantiation sites (enumerated in §1 row 10) all inherit these strings.

---

## 3. Making Stop/Start operable

### 3.1 Available Flutter mechanisms (verified, not from memory)

| Mechanism | Verified behaviour | Fit |
|---|---|---|
| `Semantics.onLongPress` | Handler for `SemanticsAction.longPress`; `SemanticsProperties.onLongPress` docs: "VoiceOver users on iOS and TalkBack users on Android **may** trigger this action by double-tapping the screen without lifting the finger after the second tap." `SemanticsConfiguration.onLongPress` setter adds `_addArgumentlessAction(SemanticsAction.longPress, …)` | **Selected.** Exactly one extra action on the same node, matches the physical hold idiom, no new control |
| `SemanticsProperties.customSemanticsActions` | `Map<CustomSemanticsAction, VoidCallback>`; "Whenever a custom accessibility action is added to a node, the action `SemanticsAction.customAction` is automatically added." `CustomSemanticsAction({required String label})`; on Android these appear in the **local context menu** | Not selected for Stop/Start (hidden behind the actions menu, and a "Stop" behind a menu is slower than the physical hold it replaces). Kept for Repeat (§4) |
| `Semantics.onTapHint` / `Semantics.onLongPressHint` | Present on the `Semantics` constructor. `SemanticsProperties.hintOverrides` is the documented current mechanism: "On Android, these overrides replace the default hints … instead of saying `Double tap to activate`, the screen reader will say `Double tap to `"; **ignored on iOS** | Selected for *wording only* (`hintOverrides`), never for teaching the gesture |
| `SemanticsProperties.toggled` | `toggled` flag exposed; Android reads toggle state with its own vocabulary ("Ticked"/"Not ticked" family) | **Rejected** for the lifecycle card: it is not a toggle; the label already names the action |
| `Semantics.hint` | Read *in addition to* the platform hint; `flutter/flutter#60436` documents Android voicing `label – hint – button – hint` | **Removed** everywhere it carries instruction wording |

### 3.2 Recommendation

Keep one node, keep `ExcludeSemantics` over the `Listener`, keep the physical hold untouched, and add a semantic long-press that dispatches the **same outcome mapping** the hold uses:

- `onTap`: `ready`/`paused` → `_dispatchTap` (unchanged); `stopped` → **`null`** (D3), because the tap is a documented no-op ([`detection_action_controls.dart:241-243`](lib/widgets/detection_action_controls.dart:241)).
- `onLongPress`: `enabled` → a new private dispatch that mirrors `_completeHold`'s outcome switch ([`:199-208`](lib/widgets/detection_action_controls.dart:199)): ready/paused → `widget.onStop`, stopped → `widget.onStart`. **No timers, no `_progress`, no `_consumed` mutation** — `_consumed` exists only to lock a *physical* hold's one-shot dispatch and must not be coupled to a discrete semantic action.
- `hint`: `null` in all five outcomes.
- `hintOverrides` (Android-only, harmless on iOS):
  - ready → `onTapHint: 'pause'`, `onLongPressHint: 'stop detection'`
  - paused → `onTapHint: 'resume'`, `onLongPressHint: 'stop detection'`
  - stopped → `onLongPressHint: 'start detection'` only
  - preparing/unavailable → none
- `label` becomes the action/state identity, `value` becomes state only (proposed strings in §Appendix A).

### 3.3 Constraints the plan must respect

1. **A semantic long-press is discrete, not a measured hold.** TalkBack's own hold timing decides when `onLongPress` fires; EyeCue cannot observe 3 seconds and must not try. Consequence: the semantic path stops/starts **immediately**, while the physical path still requires 3 seconds. This asymmetry is the intended trade: the safeguard exists to prevent accidental touches, and a TalkBack double-tap-and-hold is not accidental.
2. **The three-second hold code must not change.** `kLifecycleHoldDuration`, `_progressTimer`, `_holdAttemptTimer`, `_completionTimer`, and `_consumed` ([`detection_action_controls.dart:17-209`](lib/widgets/detection_action_controls.dart:17)) stay byte-identical in behaviour.
3. **The two-control composition is locked.** Verified guards: exactly one `GestureDetector` and one `DetectionActionControls` ([`detection_action_controls_test.dart:66-77`](test/widgets/detection_action_controls_test.dart:66)); one `PAUSE` + one `QUICK SCAN` ([`detection_redesign_parity_test.dart:250-252`](test/screens/detection_redesign_parity_test.dart:250), [`detection_screen_layout_test.dart:107-110`](test/screens/detection_screen_layout_test.dart:107), [`ultralytics_detection_screen_layout_test.dart:109-111`](test/screens/ultralytics_detection_screen_layout_test.dart:109)); product lock at [`detection-redesign-plan.md:540`](docs/frontend-workflow/detection-redesign-plan.md:540). A semantic action adds no widget, so all of these keep passing.
4. **`onLongPress` delivery is platform-dependent.** `flutter/flutter#35112` records VoiceOver sending a real long-press gesture instead of the semantics action, and a Flutter maintainer confirming "We can't control how the platform decides to interpret the accessibility long press". The handler must therefore also be **safe if a synthesized pointer hold arrives**: it already is, because the `Listener` path treats >`kLongPressTimeout` releases as abandoned holds with no action ([`detection_action_controls.dart:222-224`](lib/widgets/detection_action_controls.dart:222)) and only a *completed* 3-second hold dispatches. **Needs Verification [device]** that the target TalkBack build delivers `SemanticsAction.longPress`.

---

## 4. Making Repeat Last Alert operable

### 4.1 Existing pieces (no new logic needed)

| Piece | Location |
|---|---|
| `_repeatAlert()` = medium haptic + `_tts.repeatLast()` | [`ultralytics_detection_screen.dart:1164-1167`](lib/screens/ultralytics_detection_screen.dart:1164) |
| `TtsService.repeatLast()` — replays `_lastUtterance`, respects mute, 10 s validity | [`tts_service.dart:687-704`](lib/services/tts_service.dart:687) |
| current only trigger | `EyeCueGesture.swipeDown` [`:1331-1332`](lib/screens/ultralytics_detection_screen.dart:1331) |
| closest existing widget host | `_AudioPill` [`:1745-1817`](lib/screens/ultralytics_detection_screen.dart:1745), already inside a `ListenableBuilder` on `_settings`/`_tts` [`:1459-1471`](lib/screens/ultralytics_detection_screen.dart:1459) |

### 4.2 Options

| Option | Discoverability | Availability | Risk | Verdict |
|---|---|---|---|---|
| **A. `CustomSemanticsAction('Repeat last alert')` on the audio pill** | Medium — TalkBack local context menu | Always enabled, so Repeat works while Paused/Stopped/Unavailable, which is when it is most useful | Requires the pill's node to become an explicit `container` with its own `label` + `onTap` (which is also the D5 de-duplication fix) | **Recommended** |
| B. `CustomSemanticsAction` on the lifecycle card | Medium | Card is disabled for Preparing/Unavailable; the node would then carry tap + long-press + custom (3 ops) | Overloads the primary control and mixes audio semantics into lifecycle | Documented alternative |
| C. New visible Repeat control | High | n/a | Breaks the locked two-card composition ([`detection_action_controls_test.dart:73-76`](test/widgets/detection_action_controls_test.dart:73)) and would need a design-spec, which this task excludes | Rejected |
| D. Semantic node on the viewport gesture surface | Medium | Always available | The viewport has zero semantics today and is covered by a bare `Listener` ([`gesture_surface.dart:32-42`](lib/widgets/gesture_surface.dart:32)) plus a per-frame overlay; adding an interactive node there risks pointer arbitration with `GestureController` | Rejected |
| E. Action on overlay rows | Low | only while Ready | Rows rebuild per detection and are deliberately non-live informational nodes ([`detection_information_overlay.dart:100-119`](lib/widgets/detection_information_overlay.dart:100)) | Rejected |

### 4.3 Recommendation (A) — minimum change set

1. Add `final VoidCallback? onRepeatAlert;` to `_AudioPill` ([`ultralytics_detection_screen.dart:1745-1754`](lib/screens/ultralytics_detection_screen.dart:1745)) and pass `onRepeatAlert: _repeatAlert` at the call site ([`:1463-1469`](lib/screens/ultralytics_detection_screen.dart:1463)).
2. In `_AudioPill.build`, make the `Semantics` an explicit single node: `container: true`, `button: true`, `enabled: true`, `label: 'Audio guidance, on|off'`, `onTap: onPressed`, `customSemanticsActions: {const CustomSemanticsAction(label: 'Repeat last alert'): ?onRepeatAlert}`, and wrap the `Tooltip` subtree in `ExcludeSemantics` so the `InkWell` cannot contribute a second node/duplicate label.
3. No service, TTS, haptic, or settings change. `_repeatAlert()` is reused verbatim.

**Open behaviour gap (product decision, not silently fixed):** `repeatLast()` returns `false` with no audible or haptic signal when there is nothing to replay or audio is muted ([`tts_service.dart:688-694`](lib/services/tts_service.dart:688)). A blind user invoking the action gets silence. See §10 Q3.

---

## 5. De-duplication plan inputs

Fix categories: **EXCLUDE** (keep visual text, hide from the tree behind an explicit label), **REMOVE-WRAPPER** (the wrapper adds only duplicate text), **MERGE-LABEL** (attach the label to the node that owns the action), **HEADER** (promote the title node), **LEAVE**.

| Site | Current trouble | Fix | Why |
|---|---|---|---|
| Lifecycle card [`:284-295`](lib/widgets/detection_action_controls.dart:284) | Instruction vocabulary in `hint` and `value`; dead tap action for stopped | **MERGE-LABEL** (label = action identity, value = state, hint removed, `onLongPress` added, `onTap` null for stopped) | One node must own identity, state and both actions; the platform supplies the gesture wording |
| Quick Scan [`:401-408`](lib/widgets/detection_action_controls.dart:401) | `'Double tap to scan the scene'` | **MERGE-LABEL** (hint null when enabled; keep the Ready-only reason only when disabled, without gesture wording) | Removes teaching; keeps the non-obvious gate explainable |
| `AccessibleButton` [`accessible_button.dart:31`](lib/widgets/accessible_button.dart:31) | `'Double tap to activate'`, `'Unavailable'` | **MERGE-LABEL** (remove `hint`) | Android repeats the hint (`#60436`); `enabled: false` already conveys disablement |
| Audio pill [`:1759-1762`](lib/screens/ultralytics_detection_screen.dart:1759) | No `container`, no explicit `onTap`, tap only via `InkWell`, tooltip node adjacent | **MERGE-LABEL** + `ExcludeSemantics` over the `Tooltip` subtree | One node owning label + tap + custom action; tooltip wording duplicates the label intent |
| Home badge + instruction region [`home_screen.dart:155-158`](lib/screens/home_screen.dart:155), [`:221-238`](lib/screens/home_screen.dart:221) | Same content read twice (badge `meaning` already concatenates headline + supporting) | **EXCLUDE** the two instruction `Text`s | The badge node is the deliberate status surface and already carries the full meaning; visible composition is unchanged |
| Settings advanced slider [`settings_screen.dart:375-414`](lib/screens/settings_screen.dart:375) | Wrapper label duplicates the un-excluded title `Text`; 3 stops | **REMOVE-WRAPPER**; keep title `Text` as the name; add `semanticFormatterCallback` | Two clean stops (name, then adjustable control) instead of three with a repeated value |
| Settings detection cadence [`settings_screen.dart:524-552`](lib/screens/settings_screen.dart:524) | Same, and value announced as a percentage | **REMOVE-WRAPPER** + `semanticFormatterCallback` returning hertz | Same as above; fixes a wrong unit |
| Settings depth cadence [`settings_screen.dart:556-591`](lib/screens/settings_screen.dart:556) | Same, plus disabled reason baked into the wrapper label | **REMOVE-WRAPPER** + formatter; keep the visible disabled caption `Text` ([`:592-600`](lib/screens/settings_screen.dart:592)) as the explanation | The caption is where the disablement reason belongs; it is already visible text |
| Logs snackbar [`logs_reports_screen.dart:352-366`](lib/screens/logs_reports_screen.dart:352) | live `label` + un-excluded `Text` | **EXCLUDE** the child `Text` | Keeps the live region (deliberate status change) and removes the repeat |
| Logs alert-latency section [`logs_reports_screen.dart:907-919`](lib/screens/logs_reports_screen.dart:907) | `label` + identical title `Text` | **EXCLUDE** child + **HEADER** | Matches the established Settings/Help card pattern ([`settings_screen.dart:878-893`](lib/screens/settings_screen.dart:878)) |
| Logs speech-latency note [`:921-924`](lib/screens/logs_reports_screen.dart:921) | annotation duplicates the text | **REMOVE-WRAPPER** | The `Text` already speaks |
| Logs interval row [`:1042-1060`](lib/screens/logs_reports_screen.dart:1042) | 3 stops, value repeated | **EXCLUDE** both `Text`s | One row = one stop |
| Logs export section [`:1089-1101`](lib/screens/logs_reports_screen.dart:1089) | `label` + identical title | **EXCLUDE** child + **HEADER** | Same pattern |
| Logs research upload [`:1138`](lib/screens/logs_reports_screen.dart:1138) | plain title, no group | **HEADER** on the title node only | Structure without a new group node |
| Logs corrections section [`:1197-1209`](lib/screens/logs_reports_screen.dart:1197) | `label` + title `Text` | **EXCLUDE** child + **HEADER** | Label carries the count; title is redundant |
| Logs correction row [`:1231-1246`](lib/screens/logs_reports_screen.dart:1231) | `label` + differently punctuated `Text` | **EXCLUDE** child | One record, one stop |
| Logs model claim [`:1564-1573`](lib/screens/logs_reports_screen.dart:1564) | annotation duplicates text | **REMOVE-WRAPPER** | The `Text` already speaks |
| Logs research session card [`:2088-2100`](lib/screens/logs_reports_screen.dart:2088) | `label` + state `Text` | **EXCLUDE** the duplicated state `Text` only; leave body/participant text as its own nodes | The label states the state once; the rest is independent information |
| Logs priority dot [`:1518-1521`](lib/screens/logs_reports_screen.dart:1518) | already one node | **LEAVE** | Correct |
| Charts [`charts.dart:62-66`](lib/widgets/charts.dart:62) etc. | single node + excluded child | **LEAVE** | Correct |
| Overlay [`detection_information_overlay.dart:116-119`](lib/widgets/detection_information_overlay.dart:116) | single non-live node + excluded child | **LEAVE** | Correct, and per-frame content must stay non-live |
| Correction sheet [`detection_correction_sheet.dart:83-88`](lib/widgets/detection_correction_sheet.dart:83) | single node + excluded child | **LEAVE** | Correct |
| Safety disclosure [`safety_disclosure.dart:41-74`](lib/widgets/safety_disclosure.dart:41) | grouped, headed, excluded title | **LEAVE** | Correct |
| Failure path (§2.7) | `Unavailable` + message announced 2–4 times | Decide one live region (see §10 Q1); **EXCLUDE** the header `_modelError` `Text` at minimum | The header duplicates the panel's exact string (`:1275`) |
| Settings live message [`settings_screen.dart:722-734`](lib/screens/settings_screen.dart:722) | label + excluded child | **LEAVE** | Already the correct pattern |

### 5.1 Must NOT change

- `SwitchListTile` toggles ([`settings_screen.dart:512-523`](lib/screens/settings_screen.dart:512)) and `RadioListTile` groups ([`:362-371`](lib/screens/settings_screen.dart:362)) — framework-owned label/role/toggled/selected state; asserted at [`semantics_test.dart:836-892`](test/accessibility/semantics_test.dart:836).
- Deliberate live regions: `StatusPill` ([`status_pill.dart:16-19`](lib/widgets/status_pill.dart:16)), `WarningBanner` ([`warning_banner.dart:15-18`](lib/widgets/warning_banner.dart:15)), model-change notice ([`ultralytics_detection_screen.dart:1402-1414`](lib/screens/ultralytics_detection_screen.dart:1402)), Settings message ([`settings_screen.dart:722-734`](lib/screens/settings_screen.dart:722)), Logs snackbar ([`logs_reports_screen.dart:358-363`](lib/screens/logs_reports_screen.dart:358)) — the *region flags* stay; only duplicated text inside them is excluded.
- Per-frame detections must remain non-live ([`detection_information_overlay.dart:116`](lib/widgets/detection_information_overlay.dart:116); asserted [`semantics_test.dart:196-205`](test/accessibility/semantics_test.dart:196)).
- Application-domain TTS: detection utterances, `Detection started/paused/resumed/stopped`, Quick Scan summaries, `repeatLast` — never routed through `SemanticsService.announce`.
- Physical gestures, holds, `_consumed` locking, `GestureController`, and shell gesture navigation.
- Telemetry, corrections, research sessions, export, and settings persistence.

---

## 6. TalkBack vs EyeCue boundary

| EyeCue controls (deterministic) | TalkBack controls (not EyeCue's to force) |
|---|---|
| Which nodes exist and what each node's `label`, `value`, `hint`, `enabled`, `button`, `header` are | Traversal order (TalkBack follows its own focus rules; `sortKey` only hints) |
| Which actions a node advertises (`onTap`, `onLongPress`, `customSemanticsActions`) and what each dispatches | How the user invokes an action (double-tap, double-tap-and-hold, actions menu) and how long it takes |
| Whether a node is a live region and its label | Whether and when the live announcement is spoken, at what volume, and whether hints are enabled at all |
| Whether duplicated visual text is excluded | Whether the platform's default hint is appended and repeated (Android) |
| `hintOverrides` text for tap and long-press **on Android** | iOS hint behaviour (`hintOverrides` is ignored; only `hint` is used) — irrelevant while EyeCue is Android-only |
| Application speech via TTS (a separate audio channel) | Whether TalkBack speech ducks, overlaps, or interrupts TTS |

**Consequences for the plan**

- Do not attempt to order announcements; do not add `SemanticsSortKey` unless a specific wrong order is observed on device.
- Do not rely on `hint` to carry information TalkBack users need; anything essential belongs in `label` or `value` (a hint may be disabled by the user).
- Expect that a live-region status announcement and EyeCue's own TTS confirmation can be simultaneous (§A4); coordination is a product decision, not a layout fix.

---

## 7. Risk register (per file)

| File | Change surface | Behavioural risk | Guard |
|---|---|---|---|
| [`lib/widgets/detection_action_controls.dart`](lib/widgets/detection_action_controls.dart) | Semantics props only ([`:278-296`](lib/widgets/detection_action_controls.dart:278)) plus a new dispatch method | Accidentally resetting `_progress`/`_holding`, mutating `_consumed`, or adding a `GestureDetector` would break the 3-second hold, the one-shot lock, or the two-control test | Do not touch [`_startHold`](lib/widgets/detection_action_controls.dart:161)/[`_completeHold`](lib/widgets/detection_action_controls.dart:188)/[`_endHold`](lib/widgets/detection_action_controls.dart:211)/[`_cancelHold`](lib/widgets/detection_action_controls.dart:250); the semantic dispatch is a separate pure method; no new widgets |
| [`lib/widgets/accessible_button.dart`](lib/widgets/accessible_button.dart) | Remove `hint` | None visual; one string change affects 27 call sites at once | `onTap`/`enabled` untouched |
| [`lib/screens/ultralytics_detection_screen.dart`](lib/screens/ultralytics_detection_screen.dart) | `_AudioPill` node + `onRepeatAlert` param; header `_modelError` exclusion; possibly status-pill liveness | Passing the wrong callback could double-fire haptics/TTS; excluding `_modelError` hides a message; changing pill liveness affects every lifecycle transition; `Listener`-based viewport gestures must not be disturbed | Reuse `_repeatAlert` verbatim; `ExcludeSemantics` is semantic-only; the pill is outside `GestureSurface`; do not touch `_startDetection`/`_stopDetection`/`_pauseDetection`/`_resumeDetection` or the action-row wiring ([`:1709-1737`](lib/screens/ultralytics_detection_screen.dart:1709)) |
| [`lib/screens/home_screen.dart`](lib/screens/home_screen.dart) | Exclude two `Text`s; optional `meaning` rewording | An accidental layout change in the fixed non-scrollable composition, or loss of the 200% text-scale guarantee | `ExcludeSemantics` wraps without altering layout; keep the `Flexible`/ellipsis structure ([`:221-238`](lib/screens/home_screen.dart:221)); rewording must be product-approved |
| [`lib/screens/settings_screen.dart`](lib/screens/settings_screen.dart) | Remove 3 wrappers; add `semanticFormatterCallback` | Removing a wrapper is layout-neutral, but a stray `setState` or draft/persist change would break slider persistence | Only wrap/format; never touch `onChanged`/`onChangeEnd` ([`:400-413`](lib/screens/settings_screen.dart:400), [`:546-551`](lib/screens/settings_screen.dart:546), [`:585-590`](lib/screens/settings_screen.dart:585)) |
| [`lib/screens/logs_reports_screen.dart`](lib/screens/logs_reports_screen.dart) | ~8 exclusion/removal edits + header flags | Excluding the wrong `Text` could remove data from the tree; changing a live region could silence a message | Only add `ExcludeSemantics`/`header: true`/remove redundant wrappers; keep every live region |
| [`lib/widgets/detection_state_panel.dart`](lib/widgets/detection_state_panel.dart) / [`lib/widgets/status_pill.dart`](lib/widgets/status_pill.dart) | Possibly one live-region decision | Removing both would silence failures; removing either changes announcement timing on every transition | Decide once (§10 Q1); the pick must keep the failure message reachable |
| Tests (`test/...`) | Amended assertions | Weakening coverage while chasing new strings | Amend only assertions that encode the removed behaviour; add action-existence assertions |

Layout/200% text-scale safety: every recommended change is semantic-only (wrapping, props, callbacks). The one string change that can affect layout is visual copy (`press Start`, `custom EyeCue mode`), which is explicitly **out of scope** for this task (§9 lists it as a follow-up).

---

## 8. Test impact

### 8.1 Must be amended (they encode the behaviour being removed)

| Assertion | Location | Why it must change |
|---|---|---|
| `node.hint` contains `'Hold for three seconds to stop'` | [`detection_action_controls_test.dart:431`](test/widgets/detection_action_controls_test.dart:431) | Hint is removed; replace with a long-press action assertion |
| `node.hint` contains `'Hold for three seconds to start'` | [`detection_action_controls_test.dart:449`](test/widgets/detection_action_controls_test.dart:449) | Same; also `hasAction(tap)` at [`:448`](test/widgets/detection_action_controls_test.dart:448) must flip to `isFalse` (D3) |
| `node.hint == 'Detection is preparing'` | [`detection_action_controls_test.dart:465`](test/widgets/detection_action_controls_test.dart:465) | Hint removed; assert the state is in `label`/`value` |
| `node.hint == 'Detection is unavailable'` | [`detection_action_controls_test.dart:481`](test/widgets/detection_action_controls_test.dart:481) | Same |
| `node.hint` contains `'available only while detection is ready'` | [`detection_action_controls_test.dart:513`](test/widgets/detection_action_controls_test.dart:513) | Reworded to remove gesture vocabulary |
| `hint == 'Double tap to activate'` | [`semantics_test.dart:141-143`](test/accessibility/semantics_test.dart:141) | `AccessibleButton` no longer supplies a hint |
| `hint == 'Unavailable'` | [`semantics_test.dart:157`](test/accessibility/semantics_test.dart:157) | Same; assert `enabled: false` instead |
| Wrapper label `'^Advanced detection confidence threshold, 0.25'` + node `'0.25'` | [`semantics_test.dart:894-911`](test/accessibility/semantics_test.dart:894) | Wrapper removed; assert the title `Text` node plus the slider's value/adjust actions |
| Hand-built audio-pill stand-in | [`semantics_test.dart:207-227`](test/accessibility/semantics_test.dart:207) and [`widget_test.dart:520-540`](test/widget_test.dart:520) | Tests a copy of the widget, not `_AudioPill`; must exercise the real pill (or a public test seam) including the Repeat custom action |

### 8.2 Correct — must stay

- Exactly two controls / one `GestureDetector`: [`detection_action_controls_test.dart:66-77`](test/widgets/detection_action_controls_test.dart:66).
- Visible copy per outcome: [`detection_action_controls_test.dart:81-99`](test/widgets/detection_action_controls_test.dart:81); `PAUSE`/`QUICK SCAN` at [`detection_redesign_parity_test.dart:250-252`](test/screens/detection_redesign_parity_test.dart:250), [`detection_screen_layout_test.dart:107-110`](test/screens/detection_screen_layout_test.dart:107), [`ultralytics_detection_screen_layout_test.dart:109-111`](test/screens/ultralytics_detection_screen_layout_test.dart:109), [`widget_test.dart:508-510`](test/widget_test.dart:508).
- Hold timing/progress/`KEEP HOLDING`/single-dispatch/cancellation groups in [`detection_action_controls_test.dart:250-408`](test/widgets/detection_action_controls_test.dart:250) — semantics work must not perturb them.
- Semantic tap dispatch: [`detection_action_controls_test.dart:517-536`](test/widgets/detection_action_controls_test.dart:517) (and the paused/stopped equivalents).
- Live regions: `StatusPill`/`WarningBanner` [`semantics_test.dart:161-181`](test/accessibility/semantics_test.dart:161); state panel [`semantics_test.dart:269-313`](test/accessibility/semantics_test.dart:269).
- Non-live detection card [`semantics_test.dart:196-205`](test/accessibility/semantics_test.dart:196); charts [`semantics_test.dart:316-375`](test/accessibility/semantics_test.dart:316).
- Safety disclosure heading/order [`semantics_test.dart:623-668`](test/accessibility/semantics_test.dart:623).
- Switch/radio/settings headings [`semantics_test.dart:755-892`](test/accessibility/semantics_test.dart:755).
- 200% text-scale groups on Home, Help, Settings and detection chrome ([`semantics_test.dart:407-457`](test/accessibility/semantics_test.dart:407), [`:553-576`](test/accessibility/semantics_test.dart:553), [`:684-702`](test/accessibility/semantics_test.dart:684), [`:965-988`](test/accessibility/semantics_test.dart:965), [`:229-253`](test/accessibility/semantics_test.dart:229)).
- Home meanings [`semantics_test.dart:459-551`](test/accessibility/semantics_test.dart:459) — unchanged **unless** the `Swipe left to start!` rewording (§10 Q2) is approved.

### 8.3 New assertions needed (intent only)

1. Lifecycle node has a `longPress` action for ready/paused/stopped and **none** for preparing/unavailable; performing it calls `onStop` (ready, paused) and `onStart` (stopped) exactly once, and does not call `onPause`/`onResume`.
2. Stopped lifecycle node exposes **no** `tap` action (D3).
3. No semantic node in the app exposes a hint containing `Double tap`, `Hold`, or `Swipe` (a repo-level guard, mirroring how [`no_custom_engine_test.dart`](test/architecture/no_custom_engine_test.dart) guards architecture).
4. Audio pill: one node with `label`, `tap` action, and a `customAction` whose `CustomSemanticsAction.label` is `'Repeat last alert'`; invoking it calls the repeat callback once.
5. Home: exactly one status node for the instruction region; the headline/supporting strings are not independently navigable.
6. Settings: each slider yields a name node and an adjustable node, and the adjustable node's announced value is not a percentage for the cadence sliders.
7. Logs & Reports: for each de-duplicated site, the section title is a `header` and the duplicated text is not navigable; `_AlertIntervalRow` yields one node.
8. `AccessibleButton`: enabled → `button + enabled + tap`, no hint; disabled → `button + disabled`, no tap, no hint.

---

## 9. Documentation obligations after implementation

Per `.roo/rules/rules-frontend/06-doc-update.md` (root `/docs` is authoritative; only the allow-listed files are copied into `.roo/rules/docs/`). Nothing here is edited in this stage.

| File | Required change | Currently false claim |
|---|---|---|
| [`docs/app-only-implementation-plan.md:330`](docs/app-only-implementation-plan.md:330) | Acceptance criterion becomes true; add that Stop/Start and Repeat are reachable via semantics (long-press + custom action) | "Every primary action is reachable and identifiable with TalkBack" — **false today**: Stop/Start and Repeat are not reachable |
| [`docs/app-only-implementation-plan.md:331`](docs/app-only-implementation-plan.md:331) | Add the single-live-region-per-transition rule | "Engine, detection, pause, error, and fallback states are announced once" — **false today**: failure is announced by the pill, the panel, and a plain `Text` carrying the same string ([`ultralytics_detection_screen.dart:1275`](lib/screens/ultralytics_detection_screen.dart:1275)) |
| [`docs/testing-plan.md:105`](docs/testing-plan.md:105) | Narrow the claim to what is now verified and name the device gate | "All tested interactive elements have TalkBack labels" — **partly false**: labels exist, but the lifecycle card has no operable Stop/Start, the audio pill has no explicit actionable node, and the sliders are fragmented |
| [`docs/testing-plan.md:108`](docs/testing-plan.md:108) | **No correction needed** (contradiction with the brief, flagged not resolved) | The safety-disclosure claim is **accurate**: verified at [`safety_disclosure.dart:41-74`](lib/widgets/safety_disclosure.dart:41) and [`semantics_test.dart:623-668`](test/accessibility/semantics_test.dart:623). If the new no-gesture-wording test lands, extend the row rather than rewriting it |
| [`docs/ui-conventions.md:62-81`](docs/ui-conventions.md:62) | Accessibility section gains: (a) never put gesture instructions in `hint`/`value`; (b) use `hintOverrides` for tap/long-press result wording on Android; (c) one live region per deliberate transition; (d) a control whose physical alternative is a hold must expose a semantic action; (e) do not wrap a framework control in a label-only `Semantics` container | Current bullets say "Expose … a label, role, state, value, hint" ([`:67-68`](docs/ui-conventions.md:67)) — the "hint" guidance is what produced the teaching strings, and "Exclude … duplicate visual labels" ([`:78-79`](docs/ui-conventions.md:78)) is not applied on Home/Logs |
| [`docs/thesis-product-status-audit.md:311`](docs/thesis-product-status-audit.md:311) | Rewrite the Detection row: single engine, dominant viewport, two-card row, semantics contract | "live preview + boxes, status pill, audio mute, object cards with priority, warning banner, visible controls" and "TalkBack semantics are minimal" — **both false**: cards/banner/visible controls were removed in PD1–PD3, and semantics are extensive |
| [`docs/thesis-product-status-audit.md:316`](docs/thesis-product-status-audit.md:316) | Update the "remaining UI work" sentence | Lists "TalkBack/Semantics polish" as outstanding work without stating the operability gap |
| `.roo/rules/docs/ui-conventions.md` (allow-listed copy) | Re-copy after the root edit | Must not be edited independently |
| `docs/changelog.md`, `docs/session-log.md`, `docs/implementation-progress.md`, `docs/project-status.md` | Add the change entry | Required by the same rule for "any UI behavior change" |

**Out of scope but must be reported, not fixed** (pre-existing doc rot discovered while verifying):

- `docs/frontend-workflow/detection-redesign-plan.md:9`, `:120`, `:208`, `:422`, `:540` describe **two** engine screens and link `lib/screens/detection_screen.dart`, which no longer exists ([`no_custom_engine_test.dart:5-21`](test/architecture/no_custom_engine_test.dart:5)).
- The always-on `.roo/rules/docs/architecture.md` copy still lists `detection_screen.dart`, `inference_isolate.dart`, `inference_worker_lifecycle.dart`, `ultralytics_detection_adapter.dart` as current, and describes a dual-engine architecture.

---

## 10. Open Questions / Needs Verification

| # | Item | Tag | Why it needs a decision or a device |
|---|---|---|---|
| Q1 | **Failure announcement ownership.** Keep `StatusPill` live and drop `DetectionStatePanel` `liveRegion`, or the reverse? | `[product-decision]` | Both are live today ([`status_pill.dart:16-19`](lib/widgets/status_pill.dart:16), [`detection_state_panel.dart:42-45`](lib/widgets/detection_state_panel.dart:42)). Recommended default: keep the pill live (it fires on every transition) and drop the panel's live flag, keeping the panel's message navigable — but this makes the safe failure message non-automatic, which only a device read-through can justify |
| Q2 | **Home copy** `'Swipe left to start!'` inside the semantic `meaning` ([`home_screen.dart:298`](lib/screens/home_screen.dart:298)). Reword to remove gesture vocabulary? | `[product-decision]` | It is user-facing copy as well as a semantic label; the gesture is unusable with TalkBack active. Rewording also changes [`semantics_test.dart:477-479`](test/accessibility/semantics_test.dart:477) |
| Q3 | **Silent Repeat.** `repeatLast()` returns `false` silently when muted or when there is nothing to repeat ([`tts_service.dart:688-694`](lib/services/tts_service.dart:688)). Should a semantic invocation add an announcement or a haptic failure cue? | `[product-decision]` | Required for parity: a sighted user sees nothing happens; a blind user hears nothing and cannot tell a dead action from a muted one |
| Q4 | Does the target TalkBack build deliver `SemanticsAction.longPress` to a `Semantics(onLongPress:)` node, or a synthesized raw long-press? | `[needs-device-verification]` | `flutter/flutter#35112` shows platform inconsistency. If unreliable, fall back to a `CustomSemanticsAction('Stop detection')` / `('Start detection')` pair (documented alternative, §4.2 B mechanics) |
| Q5 | Is the audio pill's tap action already merged into the labelled node, and does TalkBack read the tooltip? | `[needs-device-verification]` | `Semantics` without `container` merges with the `InkWell` child in practice, but the effective read-out is unobserved. The plan still converts it to an explicit `container` node |
| Q6 | Does Android still repeat the hint for a **disabled** node (Quick Scan's Ready-only reason, Preparing/Unavailable reasons)? | `[needs-device-verification]` | `flutter/flutter#60436` demonstrates duplication for actionable nodes; the disabled case decides whether a reason hint is safe or must move to a visible caption |
| Q7 | Do the cadence sliders announce as percentages today, and does `semanticFormatterCallback` change the spoken value without changing the visible value-indicator bubble (which uses `label`, [`settings_screen.dart:545`](lib/screens/settings_screen.dart:545))? | `[needs-device-verification]` | Percentage announcement is inferred from the 15–30 / 1–10 ranges plus Flutter's default slider formatting; the exact read-out must be observed |
| Q8 | Does removing the label-only `Semantics` wrapper leave the slider at two stops, or can the title and the slider be collapsed into one? | `[needs-device-verification]` | `MergeSemantics` behaviour over a `Slider` (a semantics boundary) is unverified; do not adopt it without a device/test observation |
| Q9 | TTS vs TalkBack overlap on Pause/Resume/Stop (EyeCue speaks `'Detection paused'` etc. at [`ultralytics_detection_screen.dart:940`](lib/screens/ultralytics_detection_screen.dart:940) while the pill live region speaks `'Detection status: Paused'`). Which side should yield when TalkBack is active? | `[needs-device-verification]` + `[product-decision]` | Detecting active TalkBack reliably is platform-specific; a wrong choice removes either the assistive confirmation or the app's primary feedback channel. EyeCue TTS must remain the application-domain channel (§5.1) |
| Q10 | Live-region churn on lifecycle flapping (e.g. Preparing ↔ Ready during recovery) | `[needs-device-verification]` | Only a device run shows whether repeated status changes produce announcement storms |
| Q11 | Focus return after Stop/Start: where does TalkBack focus land once the lifecycle outcome changes and the node's label/value swap? | `[needs-device-verification]` | Node identity is preserved but the properties change; re-announcement behaviour is platform-decided |
| Q12 | Does the first-use safety dialog's `WarningBanner` live region plus the disclosure group produce two competing announcements on open? | `[needs-device-verification]` | [`safety_disclosure.dart:120-122`](lib/widgets/safety_disclosure.dart:120) is live; the body is not. Confirms or refutes the `docs/testing-plan.md:108` claim on device |
| Q13 | Should `toggled` be added to the audio pill, or is the `on`/`off` label sufficient? | `[product-decision]` | Adding `toggled` may produce a second state phrase ("Ticked") next to "on"; the current label already carries state |
| Q14 | Visual copy `'Ultralytics mode uses the same model and thresholds as the custom EyeCue mode.'` ([`ultralytics_detection_screen.dart:1685-1689`](lib/screens/ultralytics_detection_screen.dart:1685)) and `'press Start'` ([`:52-54`](lib/screens/ultralytics_detection_screen.dart:52), [`help_screen.dart:71`](lib/screens/help_screen.dart:71), [`settings_screen.dart:744-746`](lib/screens/settings_screen.dart:744)) contradict the current single-engine, two-control UI | `[product-decision]` | Copy change is visual-output change, so this task excludes it; it must be scheduled separately and then reflected in the doc obligations above |

---

## Appendix A — Proposed semantics contract (copy-ready input for the plan)

### A.1 Lifecycle card ([`detection_action_controls.dart:278-296`](lib/widgets/detection_action_controls.dart:278))

| Outcome | `label` | `value` | `hint` | `hintOverrides` | `onTap` | `onLongPress` | `enabled` |
|---|---|---|---|---|---|---|---|
| ready | `Pause detection` | `Detection is running` | null | `onTapHint: 'pause'`, `onLongPressHint: 'stop detection'` | `_dispatchTap` | semantic stop dispatch | true |
| paused | `Resume detection` | `Detection is paused` | null | `onTapHint: 'resume'`, `onLongPressHint: 'stop detection'` | `_dispatchTap` | semantic stop dispatch | true |
| stopped | `Start detection` | `Detection is stopped` | null | `onLongPressHint: 'start detection'` | **null** | semantic start dispatch | true |
| preparing | `Detection is preparing` | null | null | none | null | null | false |
| unavailable | `Detection is unavailable` | null | null | none | null | null | false |

Keep: `button: true`, `ExcludeSemantics` over the `Listener`, the visible `PAUSE`/`RESUME`/`START`/`PREPARING`/`UNAVAILABLE` + secondary copy, icons, colours, progress fill.

### A.2 Quick Scan ([`detection_action_controls.dart:401-408`](lib/widgets/detection_action_controls.dart:401))

Enabled: `label: 'Quick scan the scene'`, `hint: null`, `hintOverrides: {onTapHint: 'scan the scene'}` (optional), `onTap` unchanged.
Disabled: same `label`, `enabled: false`, `hint: 'Available only while detection is ready'` (pending Q6).

### A.3 `AccessibleButton` ([`accessible_button.dart:27-33`](lib/widgets/accessible_button.dart:27))

`button: true`, `label: label`, `enabled: onPressed != null`, `onTap: onPressed`, **no `hint`**, `ExcludeSemantics` child unchanged.

### A.4 Audio pill ([`ultralytics_detection_screen.dart:1759-1762`](lib/screens/ultralytics_detection_screen.dart:1759))

`container: true`, `button: true`, `enabled: true`, `label: 'Audio guidance, on|off'`, `onTap: onPressed`, `customSemanticsActions: {CustomSemanticsAction(label: 'Repeat last alert'): onRepeatAlert}`, `ExcludeSemantics(Tooltip(...))`.

### A.5 Home ([`home_screen.dart:155-158`](lib/screens/home_screen.dart:155))

Unchanged single badge node; wrap the instruction headline and supporting `Text`s in `ExcludeSemantics`; badge stays non-live.

### A.6 Settings sliders ([`settings_screen.dart:375-414`](lib/screens/settings_screen.dart:375), [`:524-552`](lib/screens/settings_screen.dart:524), [`:556-591`](lib/screens/settings_screen.dart:556))

Remove the three label-only `Semantics(container: true, label: ...)` wrappers; keep the visible title `Text`s as the accessible names; add `semanticFormatterCallback` — threshold `(v) => v.toStringAsFixed(2)`, detection cadence `(v) => '${v.round()} hertz'`, depth cadence `(v) => '${v.round()} hertz'`. Disabled-state explanation stays in the visible caption `Text`s ([`:592-600`](lib/screens/settings_screen.dart:592)).

### A.7 Logs & Reports

Apply the §5 categories exactly per row; add `header: true` to every section-title node (Settings pattern at [`settings_screen.dart:878-893`](lib/screens/settings_screen.dart:878)); keep every existing live region flag.
