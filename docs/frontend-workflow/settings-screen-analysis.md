# EyeCue — Settings Screen Visual Redesign: Analysis

> **Stage:** Analysis (read-only). No application code, tests, assets,
> `pubspec.yaml`, or other project files were modified to produce this document.
> **Date:** 2026-09-09
> **Task type:** Visual-only frontend redesign.
> **Scope:** Redesign the Settings Screen's visual presentation while preserving
> its existing content and behavior. This is a token-consistent restyle of the
> existing content, not a screenshot match (see §6) and not an architecture
> change.
> **Source-of-truth order:** this prompt → (later) `settings-screen-plan.md` →
> `settings-screen-design-spec.md` → this analysis → general `.roo/rules/`.
> **Resolution note (2026-09-09):** The Open Questions / Needs Verification items
> were answered by the project owner and by confirming them against the codebase.
> Each confirmed value is moved into its owning section below; the resolved items
> are removed from the Open Questions section. The Dark System Performance card
> surface is confirmed as `#0A0A0A` (the existing `kHomeInk` token); the
> Intro/brand copy is dropped (follow the current Settings content); Engine
> Selection and Sensitivity are confirmed as added to the card composition; and
> the live-metrics wiring and truthful-accuracy handling are resolved with
> recommended choices and rationale.

---

## 1. Task type

**Visual-only frontend redesign.** The goal is to restyle the Settings Screen's
visual presentation using the established light visual language and token layer,
while preserving all existing content and runtime behavior.

This task is **not** combined with: navigation architecture changes; gesture
changes; app-launch camera/ML initialization; runtime-state ownership; engine
fallback; TTS; telemetry/accuracy computation; model/service refactoring;
portrait-lock configuration; or new state-management/DI frameworks. No new
repository, ViewModel, use-case, state-management package, or architecture
migration is introduced. The existing project structure, constructor-injection
patterns, and the light-theme pattern established by the completed Home and Help
features are reused.

**Critical scope boundary (flagged):** the target/token composition requires the
Settings screen to display **live** FPS/MS performance metrics. The current
[`SettingsScreen`](../lib/screens/settings_screen.dart:11) does **not** receive a
`TelemetryService` — it is constructed with only `settings` and
`onOpenLogsReports` ([`app_shell.dart`](../lib/navigation/app_shell.dart:108)).
Showing live metrics therefore requires adding a `TelemetryService` constructor
dependency and threading it through [`app_shell.dart`](../lib/navigation/app_shell.dart:108).
Confirmed against the codebase that `TelemetryService` is already constructed in
[`main.dart`](../lib/main.dart:27) and passed to `AppShell`, so no `main.dart`
change is required. The recommended resolution is to add an optional
`TelemetryService? telemetry` input to `SettingsScreen` and forward
`widget.telemetry` through the shell construction. This is a **service-wiring
change outside the UI-owned folders** and must be approved before any Code stage
(see §8.1, §12, and §14).

---

## 2. Current Settings behavior and structure

### 2.1 Behavior contract (must be preserved)

[`SettingsScreen`](../lib/screens/settings_screen.dart:11) is a
**`StatelessWidget`** with two required constructor inputs:

| Input | Current role | Preservation requirement |
|---|---|---|
| [`settings`](../lib/screens/settings_screen.dart:12) | The injected [`SettingsService`](../lib/services/settings_service.dart:60); the body is wrapped in a [`ListenableBuilder`](../lib/screens/settings_screen.dart:25) so every control reflects and writes the persisted value. | Keep the input and the listener-driven update behavior. |
| [`onOpenLogsReports`](../lib/screens/settings_screen.dart:13) | Callback invoked by the **View Logs & Reports** row; wired to [`AppShellState.openLogsReports`](../lib/navigation/app_shell.dart:77) which pushes the [`LogsReportsScreen`](../lib/screens/logs_reports_screen.dart:23) route. | Keep the callback and invoke it from the redesigned Logs & Reports affordance. |

The screen is constructed from [`app_shell.dart`](../lib/navigation/app_shell.dart:108)
(`case 2: return SettingsScreen(settings: widget.settings, onOpenLogsReports:
openLogsReports);`) inside the shell's `IndexedStack` as the third bottom-nav tab
(Settings). It inherits the shell's `Scaffold`/`NavigationBar` and the global
dark `ThemeData` today.

### 2.2 Current structure

The current build is a `Scaffold` with an `AppBar(title: Text('Settings'))` and a
`ListView` body (inside a `ListenableBuilder`) containing section headers and
controls in this order:

| # | Section | Controls |
|---|---------|----------|
| 1 | Haptics | `Vibration Feedback` `SwitchListTile` |
| 2 | Performance | `Auto-Start on Open` `SwitchListTile`, `Low Power Mode` `SwitchListTile` |
| 3 | Inference Engine | `RadioGroup<InferenceEngine>`: a non-selectable `Recommended` header `ListTile`, `Ultralytics` `RadioListTile`, a non-selectable `Advanced / compatibility` header `ListTile`, `Custom EyeCue` `RadioListTile` |
| 4 | Detection Sensitivity | `_SensitivityControls` (preset `RadioGroup<DetectionSensitivityPreset>` + an advanced `Slider`) |
| 5 | Audio | `Audio / Voice Guidance` `SwitchListTile` |
| 6 | Research | `View Logs & Reports` `ListTile` (invokes `onOpenLogsReports`) |

### 2.3 Persisted settings (must remain unchanged)

All values are persisted by [`SettingsService`](../lib/services/settings_service.dart:60)
as JSON under the application documents directory, with safe defaults on a
missing/corrupt file. The model is [`AppSettings`](../lib/models/app_settings.dart:61)
(schema version 2). The fields surfaced by the Settings screen are:

| Field | Default | Setter |
|---|---|---|
| `vibrationFeedback` | `true` | `setVibrationFeedback` |
| `autoStartDetection` | `true` | `setAutoStartDetection` |
| `lowPowerMode` | `false` | `setLowPowerMode` |
| `audioEnabled` | `true` | `setAudioEnabled` |
| `inferenceEngine` | `ultralytics` | `setInferenceEngine` |
| `detectionConfidence` | `0.25` | `setDetectionConfidence` |

The engine and sensitivity controls already exist in the current implementation
and are **not** new features to add — they are existing behavior that the
redesign must preserve and visually regroup. The `InferenceEngine` enum
([`app_settings.dart`](../lib/models/app_settings.dart:1)) already carries the
`Recommended`/`Advanced` semantics via `isRecommended` and the `label`/
`description` strings. The `DetectionSensitivityPreset` enum
([`app_settings.dart`](../lib/models/app_settings.dart:22)) already carries the
three presets (`More detections` 0.15, `Balanced` 0.25, `Fewer false alerts`
0.40) plus the advanced slider range 0.10–0.75 in 0.05 steps.

### 2.4 Navigation contract (must remain unchanged)

The Settings screen is one of four tabs in the persistent bottom
[`NavigationBar`](../lib/navigation/app_shell.dart:138) owned by
[`AppShell`](../lib/navigation/app_shell.dart:20). Logs & Reports is pushed as a
separate full-screen route from Settings ([`app_shell.dart`](../lib/navigation/app_shell.dart:77)).
The redesign must not remove or restyle the shell navigation bar, and must not
move Logs & Reports out of its pushed-route behavior.

---

## 3. Direct dependencies only

The Settings Screen's direct dependencies are the injected `SettingsService`, the
`onOpenLogsReports` callback, Material, and the shell that constructs it. It does
not currently consume `TelemetryService`, `TtsService`, `HapticsService`, or any
engine/camera service.

| Dependency | File | Role for Settings |
|---|---|---|
| Material | `package:flutter/material.dart` | `Scaffold`, `AppBar`, `ListView`, `SwitchListTile`, `RadioGroup`/`RadioListTile`, `Slider`, `ListTile`, `Theme` |
| Settings model | [`app_settings.dart`](../lib/models/app_settings.dart:1) | `InferenceEngine`, `DetectionSensitivityPreset`, `AppSettings` bounds/defaults |
| Settings service | [`settings_service.dart`](../lib/services/settings_service.dart:60) | Persisted values + setters; `ChangeNotifier` |
| Shell construction | [`app_shell.dart`](../lib/navigation/app_shell.dart:108) | `SettingsScreen` as tab index 2; only the Settings page construction is in scope |
| Theme (global) | [`app_theme.dart`](../lib/theme/app_theme.dart:13) | Dark `buildEyeCueTheme()` currently inherited by Settings |
| Light-theme pattern | [`app_home_theme.dart`](../lib/theme/app_home_theme.dart:50) | `buildHomeTheme()` — the established light `ThemeData` + IBM Plex Sans + shadow tokens to reuse |
| Tokens | [`app_colors.dart`](../lib/theme/app_colors.dart:1), [`app_spacing.dart`](../lib/theme/app_spacing.dart:1), [`app_radii.dart`](../lib/theme/app_radii.dart:1), [`app_typography.dart`](../lib/theme/app_typography.dart:1) | Semantic color/spacing/radius/type tokens |
| Reference implementations | [`home_screen.dart`](../lib/screens/home_screen.dart:22), [`help_screen.dart`](../lib/screens/help_screen.dart:17) | Light-theme, responsive, accessibility pattern to follow |
| Telemetry (only if live metrics are approved) | [`telemetry_service.dart`](../lib/services/telemetry_service.dart:175) | `averageInferenceFps`, `averageLatencyMs`, `averageConfidence` — **not currently injected into Settings** |

No unrelated routes or services were inspected. No repository-wide audit was
performed.

---

## 4. Confirmed visual facts from the references

### 4.1 Target Settings reference (`design-reference/screens/settings-screen.png`)

The target Settings composition is a **light, spacious, rounded-card** layout:

- A light gray/off-white screen background.
- A small all-caps brand label (`YOUR EYECUE`) near the upper-left.
- A large black `Settings` title.
- A large muted supporting intro paragraph: *"Personalize audio, touch, and
  performance without adding complexity to detection."*
- A large **white Preferences card** with an `Accessibility` heading and three
  preference rows (`Vibration feedback`, `Auto-start detection`, `Low power
  mode`), each with supporting copy and a toggle.
- A **pale cyan Audio Guidance card**.
- A **black System Performance card** with three metric columns (`FPS`, `MS`,
  `% ACC`) and a rounded `View Logs & Reports` action row.

### 4.2 Authoritative overrides (from the extracted token/spec markdown)

The extracted token/spec document is authoritative over the target screenshot
and **overrides** several visible details:

1. **Audio Guidance must be a standard On/Off toggle**, not the visible
   `Concise` mode/status-pill treatment shown in the screenshot.
2. **Engine Selection and Sensitivity controls must be added** to the Settings
   composition (they already exist in the current implementation and must be
   preserved/regrouped).
3. **The System Performance card must display live FPS/MS/%ACC values**, not the
   static/sample values shown in the screenshot.

### 4.3 Legacy Settings reference (`design-reference/old_screen/settings_screen.jpg`)

The legacy reference is a **dark, icon-heavy, sectioned** Settings screen with
amber section headings (Haptics, Performance, Inference Engine, Detection
Sensitivity, Audio, Research) and the same underlying setting concepts. It is a
useful inventory of the existing setting concepts but is **not** the target
visual language. The current implementation already matches the legacy concept
set (Vibration, Auto-Start, Low Power, Engine, Sensitivity, Audio, Logs &
Reports).

### 4.4 Established light language (`design-reference/screens/home_screen.png`)

The Home reference establishes the light palette, strong black typography, muted
secondary text, cyan accent, generous whitespace, and rounded surfaces that the
Settings redesign should reuse. The completed Home and Help implementations
([`home_screen.dart`](../lib/screens/home_screen.dart:22),
[`help_screen.dart`](../lib/screens/help_screen.dart:17)) are the concrete
reference for how that language is applied in code.

### 4.5 Design-token PNG (`design-reference/tokens/design-tokens.png`)

The user supplied the token values extracted from `design-tokens.png` directly
in the task prompt (the current model cannot process the PNG natively). That
visual-summary set is: IBM Plex Sans; brand colors `#F5F5F5`/`#0A0A0A`/
`#99A5AA`/`#22C7F2`/`#087A9E`/`#B9EFFF`; system colors `#32D583`/`#F5B942`/
`#FF5C5C`/`#4DA3FF`/`#667085`; spacing `8/16/24/32/48/64`; and type sizes
Display 56 / Title 32 / Action 24 / Body 18 / Label 14.

Per the established Home precedent (see [`home-screen-analysis.md`](home-screen-analysis.md:571)),
the **extracted token Markdown is authoritative over the token-summary PNG**
where they disagree. The PNG is a visual cross-check only. The Markdown's finer
spacing scale (`6, 8, 12, 16, 20, 24`) and its complete color/radius/shadow
definitions govern the Settings implementation; the PNG's coarser spacing
(`8/16/24/32/48/64`) is not used as new spacing values. The PNG's type sizes
(Display 56 / Title 32 / Action 24 / Body 18 / Label 14) are consistent with the
Markdown's role mapping and are already reflected in the Home theme builder
([`app_home_theme.dart`](../lib/theme/app_home_theme.dart:62)) at the sizes the
Home/Help implementations actually use.

---

## 5. Existing behavior that must remain unchanged

The following are **behavioral contracts**, not visual details. The redesign must
preserve them exactly:

1. **`SettingsScreen` remains a `StatelessWidget`** constructible with the
   existing `settings` and `onOpenLogsReports` inputs (unless a live-metrics
   dependency is separately approved — see §12).
2. **All six persisted settings** (vibration, auto-start, low-power, audio,
   engine, sensitivity) keep their current keys, defaults, setters, and
   persistence behavior via [`SettingsService`](../lib/services/settings_service.dart:60).
3. **Engine Selection** keeps the `Recommended`/`Ultralytics` and
   `Advanced`/`Custom EyeCue` semantics and the `InferenceEngine` enum labels.
4. **Detection Sensitivity** keeps the three presets and the advanced slider
   (0.10–0.75, 0.05 steps) and its "changes apply after detection restarts"
   behavior.
5. **Audio Guidance** remains a single On/Off toggle bound to `audioEnabled`
   (per the authoritative override).
6. **Logs & Reports** remains a pushed route invoked through `onOpenLogsReports`;
   the shell's four-tab bottom navigation is unchanged.
7. **Accessibility contracts**: every interactive control keeps a semantic
   label/role/state/hint and enabled status; toggles keep their checked state;
   the screen must not overflow at 200% text scale; no color-only meaning.
8. **No service/model/engine/camera/TTS/telemetry logic changes** (beyond the
   flagged live-metrics wiring decision).

---

## 6. Required visual changes

The redesign moves Settings from the current dark, plain `ListView` + section
headers to the light, card-based composition, following the Home/Help pattern:

1. **Light surface scoped to the Settings subtree** via a `Theme(buildHomeTheme())`
   wrapper (the Home/Help pattern), with dark status-bar icons
   (`AnnotatedRegion<SystemUiOverlayStyle>`) on the light surface. The global
   dark theme and shell navigation bar remain unchanged.
2. **A screen title** consistent with the light language (the retained
   `AppBar(title: 'Settings')`). The target's `YOUR EYECUE` brand label and intro
   paragraph are **not** added — the redesign follows the current Settings
   content (owner decision).
3. **Card-based grouping** of the existing controls into the target card
   structure (Preferences / Audio Guidance / System Performance), reusing the
   existing `kHome*`/`kSpace*`/`kRadius*` tokens and `kHomeShadowSoft`.
4. **Engine Selection and Sensitivity** regrouped into the appropriate card(s)
   with their existing controls and semantics preserved.
5. **Audio Guidance** presented as a standard On/Off toggle (authoritative
   override), not a mode selector.
6. **A System Performance card** that surfaces live metrics and a Logs & Reports
   affordance (see §8 for the truthful-metrics handling and §12 for the wiring
   flag).

---

## 7. Theme reuse vs. generalization (RESOLVED — reuse `buildHomeTheme()` as-is)

The existing light tokens are **Home-scoped**: `kHome*` in
[`app_colors.dart`](../lib/theme/app_colors.dart:114) and `buildHomeTheme()` in
[`app_home_theme.dart`](../lib/theme/app_home_theme.dart:50). The completed Help
feature already established the precedent of **reusing `buildHomeTheme()` and the
`kHome*` tokens as-is** for a non-Home screen (owner decision, Help Analysis §12,
Option 1), scoped to that screen's subtree only.

**Decision (recommended):** Settings reuses `buildHomeTheme()` and the existing
`kHome*`/`kSpace*`/`kRadius*` tokens as-is, scoped to the Settings subtree only.
No rename, no duplication, no new Settings-scoped theme or token, and no
generalization of the light theme into a shared builder. This matches the
established Home/Help precedent, keeps the change visual-only, and avoids
touching Home/Help or renaming approved tokens. Any future generalization into a
shared light theme is a separate, explicitly approved task and is out of scope
here.

**Token sufficiency check:** the light surface (`kHomeSurfaceBase` `#F5F5F5`),
card surface (`kHomeSurfaceCard` `#FFFFFF`), ink (`kHomeInk` `#0A0A0A`), muted ink
(`kHomeInkMuted` `#667085`), cyan accent (`kHomeAccentCyan` `#22C7F2`), cyan light
(`kHomeAccentCyanLight` `#B9EFFF`), and the `kRadius3/14/18/24` radii already
exist.

**Dark System Performance card surface — RESOLVED: `#0A0A0A` (the existing
[`kHomeInk`](../lib/theme/app_colors.dart:124) token).** The project owner
confirmed the black System Performance card surface is `#0A0A0A`. That exact
value is already the existing `kHomeInk` token, so **no new token is required** —
the card surface reuses `kHomeInk` as its background, with light/white foreground
text on it (the inverse of the light cards). This keeps the change within the
existing token set and satisfies the design-token rule (no invented color). The
card's foreground text and metric values use a light color derived from the
theme/`ColorScheme` (e.g. `onPrimary`/white) rather than a new token.

---

## 8. Live FPS/MS and truthful %ACC handling (RESOLVED with a flag)

### 8.1 Live FPS and MS

FPS and MS are **live, truthful** metrics available from
[`TelemetryService`](../lib/services/telemetry_service.dart:175):
`averageInferenceFps` ([`telemetry_service.dart`](../lib/services/telemetry_service.dart:352))
and `averageLatencyMs` ([`telemetry_service.dart`](../lib/services/telemetry_service.dart:346)),
plus per-engine summaries via `summaryFor(engine)`
([`telemetry_service.dart`](../lib/services/telemetry_service.dart:364)). These
are the same values the Logs & Reports Overview tab already displays
([`logs_reports_screen.dart`](../lib/screens/logs_reports_screen.dart:160)).

**Wiring decision (recommended, confirmed against the codebase):** to display
live FPS/MS on the Settings screen, `SettingsScreen` must receive a
`TelemetryService` and rebuild on its notifications. Confirmed against the
codebase: [`SettingsScreen`](../lib/screens/settings_screen.dart:11) currently
takes only `settings` and `onOpenLogsReports`
([`app_shell.dart`](../lib/navigation/app_shell.dart:108)), and
[`TelemetryService`](../lib/services/telemetry_service.dart:175) is already
constructed in [`main.dart`](../lib/main.dart:27) and passed to
[`AppShell`](../lib/navigation/app_shell.dart:21). The recommended resolution is
to add an optional `TelemetryService? telemetry` input to `SettingsScreen` and
thread `widget.telemetry` through the shell construction
([`app_shell.dart`](../lib/navigation/app_shell.dart:108)).

**Scope assessment — this is NOT an architecture change.** It is a UI-owned
wiring addition that only *reads* an existing service:

- It does **not** modify any file in `lib/services/` or `lib/models/` — those
  stay read-only, and no service/model behavior, API, or lifecycle changes.
- It touches only UI-owned files: [`settings_screen.dart`](../lib/screens/settings_screen.dart:11)
  (`lib/screens/`) and [`app_shell.dart`](../lib/navigation/app_shell.dart:108)
  (`lib/navigation/`).
- It follows the **existing constructor-injection pattern** the shell already
  uses to pass `settings`, `tts`, `telemetry`, `corrections`, and `haptics` to
  other screens ([`app_shell.dart`](../lib/navigation/app_shell.dart:100)).
- It is a **read-only consumption** of what the service layer already exposes,
  which the UI scope rule explicitly permits ("New UI may *read* what those
  layers expose, but must not modify them").
- No `main.dart` change is required, because `TelemetryService` is already
  constructed there and passed to `AppShell`.

Because it is a UI-owned wiring addition rather than a service/model or
architecture change, it is **within the visual-only scope**; it should be
acknowledged in the Plan (one optional constructor param + one shell forward),
not treated as an architecture change requiring separate approval. The only
scenario that would push it out of scope is if the change were restricted to
`settings_screen.dart` alone — in that case the performance card would show an
empty/unavailable state or be omitted, and the live values would be deferred.

### 8.2 Truthful %ACC

**Accuracy (`%ACC`) cannot be computed from a live camera feed.** It requires
ground-truth labels (offline evaluation). This is an explicit, documented honesty
rule in the codebase: [`TelemetryService`](../lib/services/telemetry_service.dart:172)
"deliberately does **not** compute model accuracy," and the Logs & Reports screen
shows Accuracy/Precision/Recall/F1/mAP as **unavailable** for exactly this reason
([`logs_reports_screen.dart`](../lib/screens/logs_reports_screen.dart:220)).

**Decision (recommended):** the Settings performance card must **not** display a
fabricated `%ACC` value. The recommended choice is **(a) show average confidence**
as the third metric, because it is a genuine, real measured value that the
codebase already computes and surfaces (`TelemetryService.averageConfidence`,
[`telemetry_service.dart`](../lib/services/telemetry_service.dart:358), shown in
Logs & Reports at [`logs_reports_screen.dart`](../lib/screens/logs_reports_screen.dart:205)),
and it keeps the three-column performance card populated with truthful data. The
metric is labeled clearly (e.g. `Avg confidence`) so it is never mistaken for
model accuracy. Option (b) — showing accuracy as **unavailable** with the same
explanatory note used in Logs & Reports — is the fallback if a third live value is
not desired.

The target screenshot's `91.4 / % ACC` is a **sample/illustrative** value and must
not be reproduced as a live accuracy claim. This is a product decision
(`[product-decision]`), resolved as recommended above.

---

## 9. Spacing-scale reconciliation (RESOLVED — extracted Markdown wins)

The two token sources disagree on spacing:

| Source | Spacing |
|---|---|
| `design-tokens.png` (visual summary) | `8, 16, 24, 32, 48, 64` |
| `extracted-design-tokens-screenshot.md` (authoritative) | `6, 8, 12, 16, 20, 24` |
| [`app_spacing.dart`](../lib/theme/app_spacing.dart:1) | `1, 2, 3, 4, 6, 8, 10, 12, 14, 16, 18, 20, 24, 32` |

**Decision (recommended):** the extracted Markdown is authoritative over the PNG
(established Home precedent). Settings uses the existing `kSpace*` tokens
(`kSpace6/8/12/16/20/24`) as logical design values and scales layout
relationships from available constraints. Do **not** copy `32`, `48`, or `64`
from the PNG as new Settings spacing values. The PNG's type sizes are consistent
with the Markdown role mapping and are already reflected in `buildHomeTheme()`.

---

## 10. Responsive-layout considerations

The reference canvas is 390×844 and is a proportional baseline, not a source of
Flutter pixel literals. Follow the Home/Help responsive pattern
([`SafeArea`](../lib/screens/home_screen.dart:43) +
[`LayoutBuilder`](../lib/screens/home_screen.dart:44) + bounded/centered width +
scrollable body):

- Use the available content width from parent constraints; do not branch on
  device model or hardware type.
- Constrain the content to a bounded/centered width (Home/Help cap at ~480) so
  cards and text stay readable on wide constraints.
- Preserve scrolling when the available height is short or text scaling causes
  the content to exceed the viewport; never overflow at 200% text scale.
- The shell's bottom `NavigationBar` remains the navigation surface and reduces
  the available Settings viewport.
- Do not add `OrientationBuilder`, orientation locks, or new platform
  configuration. The extracted token document's portrait-only statement is a
  broader product direction; the current app does not lock orientation, and this
  visual-only task must not introduce an orientation lock or change navigation.

---

## 11. Accessibility considerations

Per [`ui-conventions.md`](ui-conventions.md) and the accessibility rule:

- Every interactive control (toggles, engine radios, sensitivity radios/slider,
  Logs & Reports affordance) must keep a semantic label, role, state (checked/
  selected), hint, and enabled status.
- The screen must remain readable at **200% text scale with no overflow**; the
  layout must scroll rather than overflow.
- No color-only meaning: any accent/status color is decorative and the text/
  semantics carry the meaning.
- Decorative icons (e.g. a section icon that duplicates an adjacent title) must
  be excluded from the accessibility tree.
- The Settings subtree, if given a light surface, must use **dark status-bar
  icons** via `AnnotatedRegion<SystemUiOverlayStyle>` (the Home/Help pattern).
- Live performance values, if shown, must be exposed as text/semantics, not
  color-only, and must not become a per-frame TalkBack live region.
- Device TalkBack validation remains a manual step.

---

## 12. Files and layers that must remain untouched / flagged

### UI-owned candidates (for a later Plan, after approval)

| File | Likely role |
|---|---|
| [`lib/screens/settings_screen.dart`](../lib/screens/settings_screen.dart:11) | Primary redesign target: light `Theme` wrapper (reusing `buildHomeTheme()`), card-based grouping, preserved controls/callbacks |
| [`test/widget_test.dart`](../test/widget_test.dart:102) | Extend the existing `SettingsScreen` group (no new file) |
| [`test/accessibility/semantics_test.dart`](../test/accessibility/semantics_test.dart:1) | Add Settings semantics + 200% text-scale coverage (no new file) |
| [`docs/architecture.md`](../docs/architecture.md:1) | Doc update (Settings component row / theme section) if a token/theme change lands |
| [`docs/changelog.md`](../docs/changelog.md:1) | Doc update |
| [`docs/implementation-progress.md`](../docs/implementation-progress.md:1) | Doc update |
| [`docs/session-log.md`](../docs/session-log.md:1) | Doc update |
| `.roo/rules/docs/` mirror | Re-copy of root `/docs` after any doc change (per doc-update rule) |

### Files that must remain untouched

- **`lib/models/`** — read-only for UI work.
- **`lib/services/`** — read-only for UI work.
- **`lib/main.dart`** — only the two pre-approved exceptions (Marionette binding,
  theme consumption) apply; no Settings-related change is expected here.
- **`lib/navigation/app_shell.dart`** — the Settings **page construction** is in
  scope only to confirm the `SettingsScreen(settings:, onOpenLogsReports:)`
  contract; no navigation, tab, or shell change is allowed.
- **`lib/screens/`** other than `settings_screen.dart` — Home, Help, Detection,
  Logs & Reports, and the engine screens are out of scope.
- **`lib/widgets/`** — no existing reusable widget is required to change for
  Settings; any new reusable widget must be justified in the Plan.
- **`assets/`**, **`pubspec.yaml`** — no asset or dependency change is expected.
- **Camera, inference, engine, TTS, telemetry, correction, gesture, and
  runtime-state behavior** — unchanged.

### UI-owned wiring addition (in scope, acknowledged in the Plan)

Showing **live FPS/MS** on the Settings screen requires adding an optional
`TelemetryService? telemetry` input to `SettingsScreen` and forwarding
`widget.telemetry` through the shell's Settings construction
([`app_shell.dart`](../lib/navigation/app_shell.dart:108)). Both files are
UI-owned (`lib/screens/`, `lib/navigation/`), no `lib/services/` or `lib/models/`
file changes, and no `main.dart` change is required (`TelemetryService` is
already constructed in [`main.dart`](../lib/main.dart:27) and passed to
`AppShell`). This is a read-only consumption of an existing service via the
existing constructor-injection pattern, so it is **within the visual-only scope**
and is acknowledged in the Plan rather than treated as an architecture change.

---

## 13. Risks and constraints

- **Live-metrics wiring:** the target requires live FPS/MS on Settings, but
  `SettingsScreen` does not receive `TelemetryService`. Adding an optional
  `TelemetryService? telemetry` input and forwarding it through
  [`app_shell.dart`](../lib/navigation/app_shell.dart:108) is a UI-owned,
  read-only wiring addition (no service/model change, no `main.dart` change), so
  it is within the visual-only scope. If the change were restricted to
  `settings_screen.dart` alone, the performance card would show an
  empty/unavailable state instead.
- **Truthful accuracy:** `%ACC` cannot be computed from a live feed; showing a
  fabricated value would violate the codebase's documented honesty rule. Resolved
  as recommended: show **average confidence** as the third metric (see §8.2).
- **No target screenshot match:** the redesign is a token-consistent restyle; the
  target screenshot's sample values and `Concise` audio mode are overridden by
  the authoritative token/spec document.
- **Token-scope naming:** Settings reuses `kHome*`/`buildHomeTheme()` as-is
  (established precedent), so the "Home-local" naming is retained even though
  Settings now consumes it. Accepted naming trade-off.
- **`const`/constructor contract:** `SettingsScreen` is constructed with two
  inputs from the shell. Adding an optional `TelemetryService? telemetry` input
  keeps the existing inputs intact; the shell construction
  ([`app_shell.dart`](../lib/navigation/app_shell.dart:108)) and the Settings
  tests are updated together in the same change.
- **Dark System Performance card:** the target shows a black card; resolved as
  `#0A0A0A` = the existing [`kHomeInk`](../lib/theme/app_colors.dart:124) token
  (see §7). No new token is required.
- **Global dark theme vs light subtree:** Settings currently inherits the dark
  theme. Introducing a light subtree must be scoped so it does not leak into the
  shell `NavigationBar` or other tabs (the Home/Help `Theme` wrapper pattern).
- **Large text / overflow:** the Settings content is long (six setting groups);
  the layout must scroll at 200% text scale without RenderFlex overflow.
- **No unrelated refactors:** only Settings and its direct UI-owned dependencies
  may change; no service/model/engine/navigation changes.
- **Doc sync:** any token/theme or screen change must update root `/docs` and
  re-copy into `.roo/rules/docs/` in the same change.

---

## 14. Open Questions / Needs Verification

The product and architecture decisions required for this analysis are resolved by
the project owner and by confirming them against the codebase. Each confirmed
value is moved into its owning section above and removed from this list:

- **Live-metrics wiring — RESOLVED (recommended, in scope).** Add an optional
  `TelemetryService? telemetry` input to `SettingsScreen` and forward
  `widget.telemetry` through the shell construction
  ([`app_shell.dart`](../lib/navigation/app_shell.dart:108)). Confirmed against
  the codebase that `TelemetryService` is already constructed in
  [`main.dart`](../lib/main.dart:27) and passed to `AppShell`, so no `main.dart`
  change is required. This is a UI-owned, read-only wiring addition (no
  service/model change), so it is **within the visual-only scope** and is
  acknowledged in the Plan rather than treated as an architecture change. (§8.1,
  §12)
- **Truthful `%ACC` — RESOLVED (recommended).** Show **average confidence** as the
  third metric (a real measured value), labeled clearly so it is never mistaken
  for model accuracy; do not show a fabricated accuracy value. (§8.2)
- **Dark System Performance card surface — RESOLVED.** `#0A0A0A`, which is the
  existing [`kHomeInk`](../lib/theme/app_colors.dart:124) token. No new token is
  required. (§7)
- **Intro/brand copy — RESOLVED.** Ignore the target's `YOUR EYECUE` brand label
  and intro paragraph; follow the current Settings content (the retained
  `AppBar(title: 'Settings')` and the existing setting rows). No new intro/brand
  copy is added. (§6)
- **Card grouping of Engine/Sensitivity — RESOLVED.** Engine Selection and
  Detection Sensitivity **must be added** to the card composition (they already
  exist in the current implementation and are preserved/regrouped). The exact card
  placement is a Design-Spec decision. (§6)
- **`design-tokens.png` visual inspection — RESOLVED.** The token values were
  supplied by the user in text form; the extracted Markdown remains authoritative
  over the PNG where they disagree (established Home precedent). (§4.5)

The following items remain implementation-time steps that cannot be completed in
the analysis stage:

- **Exact card placement of Engine/Sensitivity and the Audio Guidance toggle.**
  The Design-Spec decides which card(s) hold the existing engine and sensitivity
  controls and the Audio Guidance On/Off toggle, and the exact card order.
- **Live-metrics wiring acknowledgement.** The optional `TelemetryService?`
  input on `SettingsScreen` plus the shell forward
  ([`app_shell.dart`](../lib/navigation/app_shell.dart:108)) is a UI-owned,
  read-only wiring addition within the visual-only scope; it is acknowledged in
  the Plan. If the change were restricted to `settings_screen.dart` alone, the
  performance card would show an empty/unavailable state instead.
- **Physical-device verification.** Whether a physical Android device is attached
  at implementation time is confirmed at Code stage, per the project verification
  policy.
