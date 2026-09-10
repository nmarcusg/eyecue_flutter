# EyeCue — Settings Screen Implementation Plan

> **Stage:** Plan only. No application code, tests, assets, dependency
> declarations, or navigation behavior are changed by this document.
>
> **Task type:** Visual-only frontend redesign of the Settings Screen.
>
> **Source of truth (in order):** the approved
> [`settings-screen-design-spec.md`](settings-screen-design-spec.md) (Design-Spec)
> → the approved [`settings-screen-analysis.md`](settings-screen-analysis.md)
> (Analysis), especially its **Resolved Open Questions / Decisions** section
> ([`settings-screen-analysis.md`](settings-screen-analysis.md:540)) → the
> frontend rules in `.roo/rules/` (scope, naming, tokens, accessibility,
> animation, doc-update, verification). All open questions raised in the Analysis
> and Design-Spec were resolved by the project owner and by confirming them
> against the codebase, and are treated as confirmed inputs here.

## 1. Scope and invariants

**Design-Spec cross-reference:** [`settings-screen-design-spec.md`](settings-screen-design-spec.md:15)
and [`settings-screen-design-spec.md`](settings-screen-design-spec.md:627).

This plan turns the Design-Spec into concrete, implementable edits for a
visual-only Settings redesign. Every file listed below traces back to the
Design-Spec/analysis; there are no speculative refactors.

The implementation must preserve these contracts (unchanged from the current
code):

| Contract | Current code | Preservation requirement |
|---|---|---|
| [`SettingsScreen`](../lib/screens/settings_screen.dart:11) | A `StatelessWidget` with constructor `SettingsScreen({super.key, required SettingsService settings, required VoidCallback onOpenLogsReports})` ([`settings_screen.dart`](../lib/screens/settings_screen.dart:15)) | Keep it a `StatelessWidget`; keep both required inputs; add only the optional `TelemetryService? telemetry` input described in §2. Existing two-argument constructions must still compile. |
| Shell construction | [`app_shell.dart`](../lib/navigation/app_shell.dart:108) builds `SettingsScreen(settings: widget.settings, onOpenLogsReports: openLogsReports)` as tab index 2 | Only the Settings page construction is in scope; the single additive forward of `widget.telemetry` is the only shell change (§2). |
| Navigation invariants | [`app_shell.dart`](../lib/navigation/app_shell.dart:20) owns the persistent four-tab [`NavigationBar`](../lib/navigation/app_shell.dart:138), the [`IndexedStack`](../lib/navigation/app_shell.dart:134), the `PopScope` tab-back behavior, and Logs & Reports as a pushed `MaterialPageRoute` | No removal or restructuring of the global four-tab bottom navigation; `AppShell` keeps ownership of `NavigationBar`, `IndexedStack`, `PopScope`, and the pushed Logs & Reports route. |
| Settings listener | The body is wrapped in a [`ListenableBuilder`](../lib/screens/settings_screen.dart:25) over the injected [`SettingsService`](../lib/services/settings_service.dart:60) | Keep the listener-driven update behavior so every control reflects and writes the persisted value. |
| Persistence | Six persisted settings with setters `setVibrationFeedback`, `setAutoStartDetection`, `setLowPowerMode`, `setAudioEnabled`, `setInferenceEngine`, `setDetectionConfidence` ([`settings-screen-analysis.md`](settings-screen-analysis.md:90)) | Keys, defaults, setters, and persistence timing unchanged. |
| Sensitivity draft behavior | Preset taps persist immediately; slider changes are draft-only until `onChangeEnd`; `_handleSettingsChanged` re-syncs the draft from the service ([`settings_screen.dart`](../lib/screens/settings_screen.dart:145)) | Preserve the draft/`onChangeEnd` behavior exactly. |
| Existing accessibility semantics | The advanced slider keeps its `Semantics(container: true, label: ...)` wrapper including the current threshold value ([`settings_screen.dart`](../lib/screens/settings_screen.dart:177)) | Preserve the existing slider container + label semantics. |
| Runtime behavior | No camera start, ML init, engine coordination, TTS, telemetry computation, persistence, or gesture state in Settings | No runtime state source is added. |
| Global theme | [`buildEyeCueTheme()`](../lib/theme/app_theme.dart:13) dark theme used by [`EyeCueApp`](../lib/main.dart:61) | Unchanged; Settings uses a locally scoped light context. |
| Light-theme scope | Home/Help `Theme` wrapper pattern | The light surface is scoped to the Settings subtree only; it must not leak into Detect, Home, Help, Logs & Reports, or the shell navigation bar. |

### Files in scope

| File | Design-Spec responsibility | Scope rule |
|---|---|---|
| [`lib/screens/settings_screen.dart`](../lib/screens/settings_screen.dart:11) | Replace the dark plain-`ListView` hierarchy with the light, responsive, accessible card composition; preserve all existing controls, setters, persistence timing, the sensitivity draft/`onChangeEnd` behavior, and existing accessibility semantics; add the optional `TelemetryService? telemetry` input. | Primary UI file. |
| [`lib/navigation/app_shell.dart`](../lib/navigation/app_shell.dart:108) | Forward the already-constructed `widget.telemetry` into the `SettingsScreen` construction (one additive line). | **Only approved non-UI boundary change** (see §2). |
| [`test/widget_test.dart`](../test/widget_test.dart:102) | Extend the existing `SettingsScreen` group with the preserved controls and the new card structure. | No new test file. |
| [`test/accessibility/semantics_test.dart`](../test/accessibility/semantics_test.dart:1) | Add a Settings semantics group (grouped nodes, decorative-icon exclusion, 200% text scale, no overflow) using the existing helpers. | No new test file. |
| [`docs/architecture.md`](../docs/architecture.md:1) | Doc update: Settings component row / theme section to note Settings now consumes the light `buildHomeTheme()` subtree and the optional telemetry input. | Root `/docs` authoritative. |
| [`docs/changelog.md`](../docs/changelog.md:1) | Doc update: add an Unreleased Settings Screen Visual Redesign entry. | Root `/docs` authoritative. |
| [`docs/implementation-progress.md`](../docs/implementation-progress.md:1) | Doc update: add a Current Unreleased Candidate Settings Screen Visual Redesign section. | Root `/docs` authoritative. |
| [`docs/session-log.md`](../docs/session-log.md:1) | Doc update: append a new session entry at the top. | Root `/docs` authoritative. |
| `.roo/rules/docs/` mirror | Re-copy the entire root `/docs` directory into `.roo/rules/docs/` in the same change (per the doc-update rule). | Plain mirror; never hand-edited independently. |

### Files that must remain untouched

[`app_home_theme.dart`](../lib/theme/app_home_theme.dart:1),
[`app_colors.dart`](../lib/theme/app_colors.dart:1),
[`app_spacing.dart`](../lib/theme/app_spacing.dart:1),
[`app_radii.dart`](../lib/theme/app_radii.dart:1),
[`app_typography.dart`](../lib/theme/app_typography.dart:1),
[`app_theme.dart`](../lib/theme/app_theme.dart:13),
[`main.dart`](../lib/main.dart:25), every model/service (including
[`settings_service.dart`](../lib/services/settings_service.dart:60),
[`app_settings.dart`](../lib/models/app_settings.dart:1), and
[`telemetry_service.dart`](../lib/services/telemetry_service.dart:175)), every
non-Settings screen, every widget in `lib/widgets/`, `assets/`, `pubspec.yaml`,
and all `design-reference/` files. No new state-management, routing, gesture, or
UI-component package is introduced.

## 2. The only approved non-UI boundary change (flagged)

**Design-Spec cross-reference:** [`settings-screen-design-spec.md`](settings-screen-design-spec.md:574)
and [`settings-screen-analysis.md`](settings-screen-analysis.md:486).

Showing live FPS/latency/confidence on the Settings screen requires the screen to
read an existing service it does not currently receive. This is the **only**
change outside the primary UI file, and it is explicitly approved as a narrow,
additive UI-boundary change:

1. **Optional constructor parameter** on [`SettingsScreen`](../lib/screens/settings_screen.dart:11):
   `final TelemetryService? telemetry;` added as an optional named parameter
   (`this.telemetry`) alongside the existing required `settings` and
   `onOpenLogsReports`. Existing two-argument constructions continue to compile.
2. **One forwarding line** in [`app_shell.dart`](../lib/navigation/app_shell.dart:108):
   pass `telemetry: widget.telemetry` into the `SettingsScreen` construction.

Why this is in scope and not an architecture change:

- It adds **no new service** — [`TelemetryService`](../lib/services/telemetry_service.dart:175)
  is already constructed in [`main.dart`](../lib/main.dart:27) and already held by
  [`AppShell`](../lib/navigation/app_shell.dart:21).
- It changes **no existing constructor argument** and no service/model API.
- It touches only UI-owned files (`lib/screens/`, `lib/navigation/`).
- It is a **read-only consumption** of what the service layer already exposes,
  which the UI scope rule explicitly permits.
- **No `main.dart` change is required.**

If the change were restricted to `settings_screen.dart` alone, the System
Performance card would render the `—` placeholders with no live updates (§7.4);
that fallback is documented but not the chosen path.

## 3. Confirmed theme/token facts (no change needed)

**Design-Spec cross-reference:** [`settings-screen-design-spec.md`](settings-screen-design-spec.md:260)
and [`settings-screen-analysis.md`](settings-screen-analysis.md:277).

The following facts are confirmed before being included in this plan:

- **No theme/token file change is required.** Settings reuses
  [`buildHomeTheme()`](../lib/theme/app_home_theme.dart:50) and the existing
  `kHome*`/`kSpace*`/`kRadius*` tokens as-is (established Home/Help precedent).
  No rename, no duplication, no new Settings-scoped theme or token.
- **`buildHomeTheme()`** ([`app_home_theme.dart`](../lib/theme/app_home_theme.dart:50))
  already supplies the light surface (`kHomeSurfaceBase`), IBM Plex Sans
  typography, the cyan accent `ColorScheme`, and disables runtime font fetching.
  It is applied to the Settings subtree only.
- **`kHomeSurfaceCard`** ([`app_colors.dart`](../lib/theme/app_colors.dart:118),
  `#FFFFFF`) is the light card surface; **`kHomeSurfaceBase`**
  ([`app_colors.dart`](../lib/theme/app_colors.dart:115), `#F5F5F5`) is the
  content background.
- **`kHomeInk`** ([`app_colors.dart`](../lib/theme/app_colors.dart:124),
  `#0A0A0A`) is the dark System Performance card surface — the confirmed value,
  already an existing token, so no new token is required.
- **`kRadius24`** ([`app_radii.dart`](../lib/theme/app_radii.dart:34)) is the
  card corner radius for both the light cards and the dark System Performance
  card.
- **Settings spacing is limited to `kSpace6`/`kSpace8`/`kSpace12`/`kSpace16`/`kSpace20`/`kSpace24`.**
  `kSpace32` exists in [`app_spacing.dart`](../lib/theme/app_spacing.dart:1) but is
  **not authorized for Settings**; do not copy `32`, `48`, or `64` from the token
  PNG as new Settings spacing values.
- **Shadow choice (resolved — confirmed against the codebase): `kHomeShadowSoft`
  is the single baseline for all cards, including the dark System Performance
  card.** The Design-Spec lists
  [`kHomeShadowElevated`](../lib/theme/app_home_theme.dart:27) as an *optional*
  alternative for the large dark surface. This plan selects the single
  `kHomeShadowSoft` baseline for every card so the composition is uniform and the
  change stays minimal. This is confirmed against the codebase: both existing
  light surfaces use `kHomeShadowSoft` only
  ([`help_screen.dart`](../lib/screens/help_screen.dart:130),
  [`home_screen.dart`](../lib/screens/home_screen.dart:174)), and
  `kHomeShadowElevated` is **not referenced anywhere in `lib/`** — it is a
  reserved token. Using it would introduce a shadow treatment the app does not
  currently render. `kHomeShadowElevated` is therefore not used.
- **Typography** comes from `buildHomeTheme()` (IBM Plex Sans). Card headings use
  the light `titleMedium`/`titleLarge` roles; row titles use the light
  `bodyLarge`/`titleMedium` roles; supporting copy uses the light `bodyMedium`
  role with the muted ink color. No new type roles are introduced.

## 4. Reference composition and viewport treatment

**Design-Spec cross-reference:** [`settings-screen-design-spec.md`](settings-screen-design-spec.md:51).

**This is a token-consistent restyle, not a screenshot match.** The target
screenshot's sample metric values (`91.4 / % ACC`) and its `Concise` audio
mode/status-pill treatment are overridden by the authoritative token/spec
document ([`settings-screen-analysis.md`](settings-screen-analysis.md:169)):

1. **Audio Guidance is a standard On/Off toggle**, not a mode selector.
2. **Engine Selection and Detection Sensitivity are preserved** and regrouped
   into the card composition.
3. **The System Performance card shows live values**, and the third metric is
   truthful average confidence (see §7).

The Settings content area is composed above the existing shell navigation bar.
The Settings widget must not add a replacement navigation control; the retained
shell [`NavigationBar`](../lib/navigation/app_shell.dart:138) remains the
navigation surface and reduces the available Settings viewport.

The composition is a light Settings canvas only. The light surface is scoped to
the Settings subtree; it must not leak into other tabs or the shell navigation
bar.

## 5. Layout hierarchy

**Design-Spec cross-reference:** [`settings-screen-design-spec.md`](settings-screen-design-spec.md:84)
and [`settings-screen-design-spec.md`](settings-screen-design-spec.md:336).

The redesigned Settings layout follows the Home/Help responsive pattern. The
proposed hierarchy is:

```
SettingsScreen (StatelessWidget)
└── Theme (data: buildHomeTheme())            // light subtree, scoped to Settings only
    └── AnnotatedRegion<SystemUiOverlayStyle> // dark status-bar icons on light surface
        └── Scaffold
            ├── AppBar (title: 'Settings')          // plain screen-title treatment
            └── body: ListenableBuilder(settings)
                └── SafeArea
                    └── LayoutBuilder
                        └── Center
                            └── ConstrainedBox (maxWidth ~480)   // bounded/centered width
                                └── ListView
                                    ├── _SettingsCard — Preferences
                                    ├── _SettingsCard — Audio Guidance
                                    ├── _SettingsCard — Engine & Sensitivity
                                    └── _SettingsCard — System Performance (dark)
```

**Scroll widget (resolved — confirmed against the codebase): use `ListView`.**
The Design-Spec permits either a `ListView` or a `CustomScrollView`. This plan
selects a plain `ListView` because:

- The Settings body is a fixed, short list of four cards that must simply scroll
  when the viewport is short or text is scaled — the exact case the Help screen
  already solves with a plain `ListView`
  ([`help_screen.dart`](../lib/screens/help_screen.dart:43)), which is the
  closest precedent (a light, card-stacked, scrollable screen).
- `CustomScrollView` is used by Home only because it needs
  `SliverFillRemaining(hasScrollBody: false)` to fill a short viewport with a
  bottom-anchored CTA ([`home_screen.dart`](../lib/screens/home_screen.dart:56)).
  Settings has no bottom-anchored element, so that sliver machinery is
  unnecessary complexity.
- A `ListView` satisfies the 200% text-scale no-overflow requirement (it scrolls
  by construction) with the least complexity, matching the Design-Spec's
  "least complexity" guidance.

The card widgets remain private to [`settings_screen.dart`](../lib/screens/settings_screen.dart:11)
following the existing `_`-prefixed convention (`_SectionHeader`,
`_SensitivityControls`). No new public reusable widget is justified by this
redesign.

### 5.1 Theme wrapper placement

The light `Theme` wrapper must be scoped to the Settings subtree only, mirroring
the Home/Help `Theme` wrapper pattern. It must be placed **inside** the Settings
page so it does not wrap the shell's [`NavigationBar`](../lib/navigation/app_shell.dart:138)
or leak into other tabs. The wrapper calls
[`buildHomeTheme()`](../lib/theme/app_home_theme.dart:50) as-is.

### 5.2 Status-bar treatment

Because the Settings surface is light, the status bar must use **dark icons** via
`AnnotatedRegion<SystemUiOverlayStyle>` (the Home/Help pattern) so the
time/notifications remain visible on the light surface. This is scoped to the
Settings subtree.

### 5.3 Responsive rules

- **Single column at all widths**, centered and capped at the same ~480 max
  content width used by Home and Help, with **no breakpoint-driven layout switch**
  and no card reflow.
- Use the available content width from parent constraints; do not branch on
  device model or hardware type.
- Keep a leading/trailing content inset based on the approved spacing scale, with
  [`kSpace16`](../lib/theme/app_spacing.dart:34) as the baseline outer inset.
- Preserve scrolling when the available height is short or text scaling causes
  the content to exceed the viewport; never overflow at 200% text scale.
- Do not add `OrientationBuilder`, orientation locks, new platform configuration,
  or portrait-only device behavior.

## 6. Card order and contents

**Design-Spec cross-reference:** [`settings-screen-design-spec.md`](settings-screen-design-spec.md:133).

**Card order (resolved by the Design-Spec — authoritative):**

| # | Card | Contents | Source of the controls |
|---|------|----------|------------------------|
| 1 | **Preferences** | `Vibration Feedback`, `Auto-Start on Open`, `Low Power Mode` | Existing `SwitchListTile`s ([`settings_screen.dart`](../lib/screens/settings_screen.dart:31)) |
| 2 | **Audio Guidance** | `Audio / Voice Guidance` On/Off toggle | Existing `SwitchListTile` bound to `settings.audioEnabled` / `settings.setAudioEnabled` ([`settings_screen.dart`](../lib/screens/settings_screen.dart:97)) |
| 3 | **Engine & Sensitivity** | `Inference Engine` (`RadioGroup<InferenceEngine>` + `RadioListTile`s) and `Detection Sensitivity` (preset `RadioGroup<DetectionSensitivityPreset>` + advanced `Slider`) | Existing controls ([`settings_screen.dart`](../lib/screens/settings_screen.dart:58), [`settings_screen.dart`](../lib/screens/settings_screen.dart:121)) |
| 4 | **System Performance** (dark) | Live `Avg FPS` / `Avg latency` (MS) / `Avg confidence` metrics + `View Logs & Reports` action row | New presentation of existing telemetry + existing `onOpenLogsReports` callback ([`settings_screen.dart`](../lib/screens/settings_screen.dart:105)) |

**Rationale (from the Design-Spec):** the order mirrors the existing
top-to-bottom control order (Vibration → Auto-Start → Low Power → Inference
Engine → Detection Sensitivity → Audio → Research), keeping the frequently
toggled switches first and the researcher-facing entry last, while inserting the
preserved Engine/Sensitivity controls as a single grouped card immediately before
the performance card. The `View Logs & Reports` affordance moves from the old
standalone `Research` section into the System Performance card.

### 6.1 Research-card discrepancy (resolved — four-card structure)

The task brief lists a fifth card, **Research**, in the required card order. The
approved Design-Spec and Analysis describe **four** cards and place the
`View Logs & Reports` action **inside the System Performance card**
([`settings-screen-design-spec.md`](settings-screen-design-spec.md:150),
[`settings-screen-design-spec.md`](settings-screen-design-spec.md:159)).

**Resolution (recommended, confirmed against the codebase): the four-card
structure from the approved Design-Spec is authoritative; no fifth Research card
is created.** Rationale:

- The current implementation has **no** standalone Research *card* — `Research`
  is only a `_SectionHeader` label above the single `View Logs & Reports`
  `ListTile` ([`settings_screen.dart`](../lib/screens/settings_screen.dart:104)).
  A fifth card would therefore contain exactly one row, which is not a card
  grouping the rest of the composition uses.
- The Design-Spec and Analysis both explicitly move that single affordance into
  the System Performance card ([`settings-screen-design-spec.md`](settings-screen-design-spec.md:159)),
  so the researcher-facing entry remains present and last in the order — the
  brief's intent (a researcher-facing entry at the end) is satisfied without a
  separate card.
- Creating a fifth card would contradict the approved Design-Spec, which the
  source-of-truth order ranks above the task brief's card list.

The `View Logs & Reports` action is therefore rendered **inside the System
Performance card** (§6, §8.4). If the owner later wants a visually separate
Research card, that is a Design-Spec change and must be re-approved before the
Code stage.

## 7. Telemetry presentation rules

**Design-Spec cross-reference:** [`settings-screen-design-spec.md`](settings-screen-design-spec.md:450)
and [`settings-screen-analysis.md`](settings-screen-analysis.md:313).

### 7.1 Metric semantics (verified — must be reflected accurately)

[`TelemetryService`](../lib/services/telemetry_service.dart:175) exposes
**retained/rolling averages**, NOT instantaneous values:

| Member | Semantics |
|---|---|
| [`averageInferenceFps`](../lib/services/telemetry_service.dart:352) | Arithmetic mean of retained `RuntimeSample.inferenceFps`. |
| [`averageLatencyMs`](../lib/services/telemetry_service.dart:346) | Arithmetic mean of retained `RuntimeSample.latencyMs`. |
| [`averageConfidence`](../lib/services/telemetry_service.dart:358) | Arithmetic mean of retained `TelemetryRecord.confidence` (combines all engines and classes). |

Runtime samples are capped at **500** and detection records at **2,000**, with the
oldest evicted first; the averages operate only on retained entries. There is
**no** public clear/reset method and **no** `current`/`latest`/`last` getter.

### 7.2 Labels (exact)

The three columns are labeled exactly:

| Column | Source | Label |
|---|---|---|
| FPS | [`averageInferenceFps`](../lib/services/telemetry_service.dart:352) | `Avg FPS` |
| MS | [`averageLatencyMs`](../lib/services/telemetry_service.dart:346) | `Avg latency` |
| Confidence | [`averageConfidence`](../lib/services/telemetry_service.dart:358) | `Avg confidence` |

The "average" wording is required because the values are arithmetic means over
retained samples; omitting it would misrepresent them as instantaneous.

### 7.3 No fabricated metrics

**The `%ACC` metric is excluded.** No fabricated accuracy, precision, recall, F1,
or mAP value is displayed. The third metric is average detection confidence, not
accuracy/precision/recall/F1/mAP. The target screenshot's `91.4 / % ACC` is a
sample/illustrative value and must not be reproduced as a live accuracy claim.

### 7.4 Empty and null presentation

- **Empty telemetry:** when the retained lists are empty, the averages return `0`.
  Show `—` (em dash) for all three metrics and keep the metric rows visible. `0`
  would falsely read as a measured zero; hiding the rows would make the card look
  broken.
- **Null `telemetry`:** when the optional `TelemetryService? telemetry` is `null`,
  the System Performance card renders with the same `—` placeholders and no live
  updates. This keeps the visual composition stable and avoids a conditional
  layout, while remaining truthful that no data is available.

### 7.5 No disabled controls

No Settings control is disabled by this redesign.

## 8. Concrete edits to [`lib/screens/settings_screen.dart`](../lib/screens/settings_screen.dart:11)

**Design-Spec cross-reference:** [`settings-screen-design-spec.md`](settings-screen-design-spec.md:84),
[`settings-screen-design-spec.md`](settings-screen-design-spec.md:172), and
[`settings-screen-design-spec.md`](settings-screen-design-spec.md:188).

The primary implementation file. The redesign replaces the dark plain-`ListView`
hierarchy with the light, responsive, accessible card composition while
preserving all existing controls, setters, persistence timing, the sensitivity
draft/`onChangeEnd` behavior, and existing accessibility semantics.

### 8.1 Constructor and imports

- Add `import '../services/telemetry_service.dart';` (read-only consumption).
- Add `final TelemetryService? telemetry;` and the optional named parameter
  `this.telemetry` to the constructor, keeping `settings` and
  `onOpenLogsReports` required and unchanged.

### 8.2 Build-method structure

Replace the current `Scaffold → AppBar → ListenableBuilder → ListView` body with
a Settings-local light context wrapping the responsive/scroll-safe skeleton:

- Wrap the Settings subtree in the light theme via
  [`buildHomeTheme()`](../lib/theme/app_home_theme.dart:50) so the light surface
  and ink apply only to Settings.
- Wrap the subtree in `AnnotatedRegion<SystemUiOverlayStyle>` for dark
  status-bar icons on the light surface.
- Keep the `Scaffold` with the retained `AppBar(title: Text('Settings'))`.
- Keep the `ListenableBuilder` over the injected `settings` service.
- Compose the body as `SafeArea → LayoutBuilder → Center → ConstrainedBox
  (maxWidth ~480) → ListView` containing the four `_SettingsCard` widgets in the
  order defined in §6. The scroll widget is a plain `ListView` (resolved in §5).
- Use token spacing and proportional/bounded relationships; do not encode
  screenshot pixel positions.

### 8.3 Private `_SettingsCard` component

Introduce a private `_SettingsCard` (replacing the standalone `_SectionHeader`
usage) that renders one card:

- **Surface:** [`kHomeSurfaceCard`](../lib/theme/app_colors.dart:118) on the
  [`kHomeSurfaceBase`](../lib/theme/app_colors.dart:115) background.
- **Corner radius:** [`kRadius24`](../lib/theme/app_radii.dart:34). No raw
  `BorderRadius.circular(...)` literal.
- **Shadow:** [`kHomeShadowSoft`](../lib/theme/app_home_theme.dart:18) (the
  single baseline chosen in §3).
- **Padding/separation:** token-based inner padding and card-to-card separation
  (baseline [`kSpace16`](../lib/theme/app_spacing.dart:34)), not raw
  `EdgeInsets` literals.
- **Header row:** a decorative section icon (excluded via `ExcludeSemantics`) at
  the retained size, a token gap, and the card heading in the light
  `titleMedium`/`titleLarge` role. The heading is the semantic heading for the
  card group.
- **Body:** the card's controls, with typography from `buildHomeTheme()`.

**Audio Guidance card tint (resolved — recommended: do not apply the tint).**
The Design-Spec permits expressing the target's pale cyan card treatment with
[`kHomeAccentCyanLight`](../lib/theme/app_colors.dart:136) as a card surface
tint. This plan **does not apply it**: the token is currently used only as the
static cyan rail accent on Home
([`home_screen.dart`](../lib/screens/home_screen.dart:256)), not as a card
surface, and the Design-Spec's own baseline card surface is
`kHomeSurfaceCard` (§6.1). Keeping every light card on the same
`kHomeSurfaceCard` surface keeps the composition uniform and the change minimal,
and the Audio Guidance toggle remains a standard `SwitchListTile` with its
existing semantics either way. If device visual tuning in the Code stage shows
the Audio Guidance card needs to be distinguished, applying
`kHomeAccentCyanLight` as its surface is a Code-stage visual-tuning decision
within the approved token set.

**Conditional radius tokens (resolved — recommended: use only `kRadius24`).**
`kRadius3`, `kRadius14`, and `kRadius18` are listed in the Design-Spec as
conditional/reserved treatments (accent rail, compact toggle-like wrapper,
compact status). This plan uses **only `kRadius24`** for the cards: the Settings
composition has no accent rail, no compact toggle-like wrapper, and no compact
status treatment, so none of the conditional radii applies. Confirmed against
the codebase: `kRadius3` is used only by the Home cyan rail
([`home_screen.dart`](../lib/screens/home_screen.dart:257)), and `kRadius14` and
`kRadius18` are **not referenced anywhere in `lib/`** — they are reserved tokens.
Introducing them here would add treatments the composition does not need.

### 8.4 Dark System Performance card

The System Performance card is the one dark surface:

- **Surface:** [`kHomeInk`](../lib/theme/app_colors.dart:124) (`#0A0A0A`) —
  confirmed as an existing token
  ([`app_colors.dart`](../lib/theme/app_colors.dart:124)); no new token is
  required.
- **Corner radius:** [`kRadius24`](../lib/theme/app_radii.dart:34) — confirmed as
  an existing token ([`app_radii.dart`](../lib/theme/app_radii.dart:34)).
- **Foreground text and metric values:** a light color derived from the active
  theme/`ColorScheme` (e.g. `onPrimary`/white) rather than a new token. The light
  `buildHomeTheme()` `ColorScheme` is seeded from `kHomeAccentCyan`
  ([`app_home_theme.dart`](../lib/theme/app_home_theme.dart:57)), so
  `colorScheme.onPrimary` resolves to a light foreground suitable for the dark
  `kHomeInk` surface.
- **Shadow:** [`kHomeShadowSoft`](../lib/theme/app_home_theme.dart:18) (baseline
  per §3).
- **Metrics:** three columns labeled `Avg FPS`, `Avg latency` (MS), and
  `Avg confidence`, using the truthful retained averages and the `—` empty/null
  presentation from §7.
- **Action row:** a `View Logs & Reports` row inside this card that invokes the
  existing `onOpenLogsReports` callback ([`settings_screen.dart`](../lib/screens/settings_screen.dart:105)).

### 8.5 Preserved controls and semantics

- All existing controls are preserved with their current bindings: the three
  Preferences switches, the Audio Guidance switch, the engine `RadioGroup` +
  `RadioListTile`s (with the `Recommended`/`Advanced` header `ListTile`s), and
  the `_SensitivityControls` preset `RadioGroup` + advanced `Slider`.
- The advanced slider keeps its existing `Semantics(container: true, label: ...)`
  wrapper including the current threshold value.
- The sensitivity draft/`onChangeEnd` behavior and `_handleSettingsChanged`
  re-sync are unchanged.
- Decorative icons are excluded from the accessibility tree via
  `ExcludeSemantics`.

**`MergeSemantics` nesting constraint (confirmed against the Flutter SDK source
in this toolchain).** `RadioListTile` and `SwitchListTile` each wrap their
children in a `MergeSemantics` widget and **throw an error if any descendant
requires its own `Semantics` node** (confirmed in
`package:flutter/src/material/radio_list_tile.dart` and
`package:flutter/src/material/switch_list_tile.dart`). The implementation must
therefore **not** add a duplicate `Semantics` wrapper around these tiles. The
existing advanced slider `Semantics(container: true, ...)` wrapper is preserved
because it wraps a `Slider` (not a `RadioListTile`/`SwitchListTile`), so it does
not conflict with this constraint.

**Deprecated-parameter avoidance (confirmed against the Flutter SDK source in
this toolchain).** The implementation must not introduce:

- `RadioListTile.groupValue` / `RadioListTile.onChanged` — deprecated after
  `v3.32.0-0.0.pre` (confirmed in
  `package:flutter/src/material/radio_list_tile.dart`).
- `SwitchListTile.activeColor` — deprecated after `v3.31.0-2.0.pre` (confirmed
  in `package:flutter/src/material/switch_list_tile.dart`).
- `Slider.year2023` — deprecated after `v3.27.0-0.2.pre`.

The existing `RadioGroup<T>` + per-tile `value` pattern and the existing
`Slider` configuration (min `0.10`, max `0.75`, divisions `13`, draft-only
`onChanged`, persist on `onChangeEnd`) are retained unchanged.

### 8.6 Private component boundary

Keep screen-only helpers private to [`settings_screen.dart`](../lib/screens/settings_screen.dart:11),
following the existing `_`-prefixed convention. Do not create a public component
solely for this redesign.

## 9. Concrete edit to [`lib/navigation/app_shell.dart`](../lib/navigation/app_shell.dart:108)

**Design-Spec cross-reference:** [`settings-screen-design-spec.md`](settings-screen-design-spec.md:574).

Add the single additive forward of the already-constructed telemetry service into
the Settings page construction:

```
case 2:
  return SettingsScreen(
    settings: widget.settings,
    onOpenLogsReports: openLogsReports,
    telemetry: widget.telemetry,
  );
```

No other shell change. `AppShell` keeps ownership of the `NavigationBar`,
`IndexedStack`, `PopScope`, and the pushed Logs & Reports route.

## 10. Concrete edits to [`test/widget_test.dart`](../test/widget_test.dart:102)

**Design-Spec cross-reference:** [`settings-screen-design-spec.md`](settings-screen-design-spec.md:595).

Extend the existing `SettingsScreen` group (no new test file). The current tests
assert the preserved controls; these remain valid because the controls are
preserved. Add/update:

- The screen title `Settings` is present.
- The four card headings (`Preferences`, `Audio Guidance`, `Engine & Sensitivity`,
  `System Performance`) are present.
- The preserved controls are present: `Vibration Feedback`, `Auto-Start on Open`,
  `Low Power Mode`, `Audio / Voice Guidance`, the engine options, and the
  sensitivity presets/slider.
- The `View Logs & Reports` action is present and invokes `onOpenLogsReports`.
- The light theme is applied to the Settings subtree (e.g. the `Theme` wrapper
  resolves to `buildHomeTheme()`), confirming the light surface does not leak
  into the shell.
- The System Performance card shows `—` placeholders when telemetry is absent or
  empty, and shows the labeled `Avg FPS` / `Avg latency` / `Avg confidence`
  metrics when telemetry is provided.

**Widget-test font resolution:** because
[`buildHomeTheme()`](../lib/theme/app_home_theme.dart:50) sets
`GoogleFonts.config.allowRuntimeFetching = false` and the bundled IBM Plex Sans
assets are declared in [`pubspec.yaml`](../pubspec.yaml:43) under
`assets/fonts/`, the Settings widget tests resolve the fonts locally from the
asset bundle. No network fetch is attempted and no test-only font override is
required.

## 11. Concrete edits to [`test/accessibility/semantics_test.dart`](../test/accessibility/semantics_test.dart:1)

**Design-Spec cross-reference:** [`settings-screen-design-spec.md`](settings-screen-design-spec.md:595).

Add a Settings semantics group (no new test file) reusing the existing helpers
[`scaledApp`](../test/accessibility/semantics_test.dart:54),
[`expectSemanticNode`](../test/accessibility/semantics_test.dart:99), and
[`withSemantics`](../test/accessibility/semantics_test.dart:105). Coverage:

- The screen title `Settings` is a real semantic heading.
- Each card group (heading + controls) is exposed as a coherent semantic node.
- Every interactive control exposes label, role, state (checked/selected), hint,
  and enabled status.
- The decorative card/row icons are excluded from the accessibility tree (no
  duplicate label from icon + title).
- The performance metrics are exposed as text/semantics, not color-only, and are
  **not** a per-frame live region.
- 200% text scale (via `scaledApp`) produces no overflow or clipped primary
  content on the Settings screen.

## 12. Concrete edits to the doc-sync files

**Doc-update rule cross-reference:** `.roo/rules/rules-frontend/06-doc-update.md`
and [`ui-conventions.md`](ui-conventions.md:1).

Any UI change that adds a screen, token, component, or convention must update the
corresponding documentation in **both** the root `/docs` and the
`.roo/rules/docs/` mirror. Root `/docs` is authoritative; `.roo/rules/docs/` is a
plain mirror re-copied in the same change.

### 12.1 [`docs/architecture.md`](../docs/architecture.md:1)

Update the Settings Screen component row and the theme/design section to note
that Settings now consumes the light
[`buildHomeTheme()`](../lib/theme/app_home_theme.dart:50) subtree (scoped to the
Settings subtree only) and that `SettingsScreen` takes an optional
`TelemetryService? telemetry` input forwarded from `AppShell`. No token/theme
file change is recorded because none is made.

### 12.2 [`docs/changelog.md`](../docs/changelog.md:1)

Add an **Unreleased — Settings Screen Visual Redesign** entry at the top (above
the existing Help Screen Visual Redesign entry) listing Added/Changed/Verified
for the light Settings subtree, the card composition, the dark System Performance
card, the truthful telemetry presentation, and the accessibility coverage.

### 12.3 [`docs/implementation-progress.md`](../docs/implementation-progress.md:1)

Add a **Current Unreleased Candidate (2026-09-10) — Settings Screen Visual
Redesign** section above the Help Screen Visual Redesign section, recording the
completed Settings work and the current validation state.

### 12.4 [`docs/session-log.md`](../docs/session-log.md:1)

Append a new session entry at the top (above the 2026-09-09 Help Screen Visual
Redesign entry) recording the objective, completed work, decisions, and next
session for the Settings redesign.

### 12.5 `.roo/rules/docs/` mirror

Re-copy the entire root `/docs` directory into `.roo/rules/docs/` in the same
change so the two never diverge. Do not hand-edit `.roo/rules/docs/` files
independently of root `/docs`.

## 13. Acceptance criteria

**Design-Spec cross-reference:** [`settings-screen-design-spec.md`](settings-screen-design-spec.md:530).

### Visual and responsive acceptance

- Settings renders the light `#F5F5F5`-role surface above the unchanged
  navigation bar.
- The cards follow the light visual language derived from Home/Help (light card
  surfaces on the light background, `kRadius24` corners, `kHomeShadowSoft`
  shadows, IBM Plex Sans), with the single dark System Performance card using
  `kHomeInk`.
- The composition uses token values and proportional/bounded relationships, not
  screenshot pixel positions.
- The global dark theme and the four-tab navigation remain visually and
  behaviorally unchanged.
- The light surface is scoped to the Settings subtree only and does not leak into
  the shell navigation bar or other tabs.
- No RenderFlex overflow or clipped primary content at narrow, large, short, or
  200%-text-scale constraints.

### Content and behavior acceptance

- All existing controls are preserved: Vibration Feedback, Auto-Start on Open,
  Low Power Mode, Inference Engine, Detection Sensitivity, Audio/Voice Guidance,
  View Logs & Reports.
- Audio Guidance remains a normal On/Off switch bound to `settings.audioEnabled`
  / `settings.setAudioEnabled`.
- Engine Selection (`InferenceEngine.ultralytics` / `InferenceEngine.custom` via
  `RadioGroup` + `RadioListTile`) and Detection Sensitivity (presets `0.15` /
  `0.25` / `0.40` plus advanced `0.10–0.75` in `0.05` steps) are preserved even
  though their visual grouping changes.
- The screenshot-only `YOUR EYECUE` branding and introductory copy are excluded.
- No `Concise` mode is reproduced.
- No misleading `%ACC` metric is displayed.
- Live/runtime FPS and latency/MS values come from `TelemetryService`, and the
  third metric is average detection confidence, clearly labeled.
- No accuracy, precision, recall, F1, mAP, or other ground-truth metric is
  fabricated.
- `SettingsScreen` remains a `StatelessWidget` with the constructor
  `SettingsScreen({super.key, required SettingsService settings, required VoidCallback onOpenLogsReports})`
  plus the optional `TelemetryService? telemetry`; existing two-argument test
  constructions still compile.
- The optional `TelemetryService? telemetry` input plus the shell forward is
  classified as a **narrow, additive UI-boundary change** (an optional parameter
  on `SettingsScreen` plus forwarding the already-constructed service from
  [`app_shell.dart`](../lib/navigation/app_shell.dart:108)). It adds no new
  service, changes no existing constructor argument, and keeps existing
  two-argument test constructions compiling.
- `ListenableBuilder` over the injected `SettingsService` continues to drive
  control synchronization.
- All setters and persistence timing are unchanged.
- Detection Sensitivity draft behavior is unchanged: preset taps persist
  immediately; slider changes are draft-only until `onChangeEnd`;
  `_handleSettingsChanged` re-syncs the draft from the service.
- Existing accessibility semantics for the advanced slider are preserved
  (container + label including the current threshold value).
- `AppShell` remains the owner of the four-tab bottom navigation, `IndexedStack`
  page retention, `PopScope` tab-back behavior, and Logs & Reports as a pushed
  `MaterialPageRoute` (NOT a fifth tab).
- `SettingsService`, `AppSettings` JSON/migration/clamping/quantization behavior,
  inference behavior, camera/runtime behavior, and TTS behavior are unchanged.

### Accessibility and automated-test acceptance

- Every interactive control has non-duplicated semantics with label, role,
  state, hint, and enabled status.
- Decorative icons are excluded from the accessibility tree.
- The Settings screen has no overflow or clipped primary content at 200% text
  scale.
- The existing `SettingsScreen` group in [`widget_test.dart`](../test/widget_test.dart:102)
  covers the preserved controls and the new card structure.
- [`semantics_test.dart`](../test/accessibility/semantics_test.dart:1) covers
  the Settings control semantics, decorative-icon exclusions, and 200% scale.

### Verification commands

- `flutter analyze` reports 0 issues.
- `flutter test` passes (existing suite plus the extended Settings tests).
- `flutter build apk --debug` succeeds (confirms the light theme and token
  imports resolve; no new dependency or asset is added).

### Physical Android-device acceptance

A physical Android device is used for the device check, per the project
verification policy. The implemented Settings screen is verified on that
connected physical Android device, not an emulator or web target. The device
check confirms the retained four-tab navigation, the light Settings surface, the
dark System Performance card, the card radius/shadow visual tuning, large-text
behavior, TalkBack semantics, and the absence of RenderFlex overflows or
exceptions in logcat. The specific connected device may vary between sessions;
the check runs against whichever physical Android device is attached at
implementation time, consistent with the Home and Help specs.

## 14. Explicitly deferred work

**Design-Spec cross-reference:** [`settings-screen-design-spec.md`](settings-screen-design-spec.md:627).

The following are not part of this Settings redesign:

1. A screenshot match of the target Settings composition (this is a
   token-consistent restyle).
2. The `YOUR EYECUE` brand label and the introductory paragraph from the target
   screenshot.
3. A `Concise` audio mode or any audio mode selector — Audio Guidance remains a
   standard On/Off toggle.
4. A `%ACC` metric or any fabricated accuracy/precision/recall/F1/mAP value.
5. Renaming, duplicating, or generalizing the `kHome*` tokens or
   `buildHomeTheme()` into a shared light theme.
6. Adding a new Settings-scoped theme or token.
7. Replacing or removing the persistent four-tab navigation bar, or moving
   Logs & Reports out of its pushed-route behavior.
8. Moving engine, camera, inference, TTS, telemetry computation, correction, or
   runtime-state logic into Settings.
9. Redesigning Home, Help, Detection, Logs & Reports, or the shell.
10. Global migration from the dark theme to a light theme.
11. Portrait locking or new orientation configuration.
12. A new state-management, routing, gesture, or UI component package.
13. Any change to `lib/models/`, `lib/services/`, or `lib/main.dart` beyond the
    two pre-approved exceptions.
14. Any change to `SettingsService`, `AppSettings` JSON/migration/clamping/
    quantization behavior, inference behavior, camera/runtime behavior, or TTS
    behavior.

## Open Questions / Needs Verification

The product and architecture decisions required for this plan are resolved by
the Design-Spec/analysis and by confirming them against the codebase. Each
confirmed value has been moved into its owning section above and removed from
this list:

- **Fifth `Research` card vs four-card structure — RESOLVED.** The four-card
  structure from the approved Design-Spec is authoritative; no fifth Research
  card is created, and the `View Logs & Reports` action lives inside the System
  Performance card. (§6.1)
- **`ListView` vs `CustomScrollView` choice — RESOLVED.** Use a plain `ListView`,
  matching the Help precedent; `CustomScrollView` is unnecessary because Settings
  has no bottom-anchored element. (§5, §8.2)
- **Dark System Performance card visual tuning — RESOLVED.** Surface `kHomeInk`
  (`#0A0A0A`), corner radius `kRadius24`, and a light foreground derived from the
  light `ColorScheme` (`onPrimary`) are confirmed as existing tokens/derivations;
  no new token is required. (§8.4)
- **Shadow choice — RESOLVED.** `kHomeShadowSoft` is the single baseline for all
  cards; `kHomeShadowElevated` is not used (it is unreferenced anywhere in
  `lib/`). (§3, §8.3, §8.4)
- **Optional cyan tint on the Audio Guidance card — RESOLVED.** Do not apply the
  `kHomeAccentCyanLight` tint; keep every light card on `kHomeSurfaceCard` for a
  uniform, minimal composition. (§8.3)
- **Conditional radius usage — RESOLVED.** Use only `kRadius24`; `kRadius3`,
  `kRadius14`, and `kRadius18` are not used because the composition has no accent
  rail, compact toggle-like wrapper, or compact status treatment. (§8.3)
- **`MergeSemantics` nesting constraint — RESOLVED (confirmed against the Flutter
  SDK source).** `RadioListTile` and `SwitchListTile` wrap their children in
  `MergeSemantics` and throw if a descendant requires its own `Semantics` node;
  no duplicate `Semantics` wrapper is added around these tiles, and the existing
  advanced slider `Semantics(container: true, ...)` wrapper is preserved. (§8.5)
- **Deprecated-parameter avoidance — RESOLVED (confirmed against the Flutter SDK
  source).** `RadioListTile.groupValue`/`onChanged` (deprecated after
  `v3.32.0-0.0.pre`), `SwitchListTile.activeColor` (deprecated after
  `v3.31.0-2.0.pre`), and `Slider.year2023` (deprecated after `v3.27.0-0.2.pre`)
  are not introduced; the existing `RadioGroup<T>` + per-tile `value` pattern and
  the existing `Slider` configuration are retained. (§8.5)

The following items genuinely cannot be confirmed in the Plan stage and remain
flagged:

- **Attached physical device identity — Needs Verification.** The specific
  physical Android device attached at implementation time is confirmed at the
  Code stage, per the project verification policy; it may differ from the
  SM-S9010 referenced by the Home plan. `[product-decision]`
- **Doc-sync wording and placement — Needs Verification.** The exact wording and
  placement of the four root `/docs` edits (architecture, changelog,
  implementation-progress, session-log) and the `.roo/rules/docs/` re-copy are
  confirmed during implementation against the current doc state; the file set
  itself is fixed by the doc-update rule. `[inferred-from-codebase]`