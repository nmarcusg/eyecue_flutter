# EyeCue — Settings Screen Design Specification

> **Stage:** Design-Spec only. No application code, tests, assets, dependency
> declarations, or navigation behavior are changed by this document.
>
> **Task type:** Visual-only frontend redesign of the Settings Screen.
>
> **Source of truth:** The approved [`settings-screen-analysis.md`](settings-screen-analysis.md:1),
> especially its **Resolved Open Questions / Decisions** section
> ([`settings-screen-analysis.md`](settings-screen-analysis.md:540)), is the
> source of truth for this specification. All open questions raised in the
> Analysis were resolved by the project owner and by confirming them against the
> codebase, and are treated as confirmed inputs here.

## 1. Scope, invariants, and implementation boundary

**Analysis cross-reference:** [`settings-screen-analysis.md`](settings-screen-analysis.md:25)
and [`settings-screen-analysis.md`](settings-screen-analysis.md:454).

This specification defines the visual hierarchy, local light styling, header/title
treatment, card grouping and order, icon treatment, the dark System Performance
card, responsive relationships, truthful telemetry presentation, and
accessibility expectations for [`SettingsScreen`](../lib/screens/settings_screen.dart:11).
It does not redesign the camera experience, other screens, the global theme, or
the app architecture.

The implementation must preserve these contracts:

| Contract | Required behavior |
|---|---|
| [`SettingsScreen`](../lib/screens/settings_screen.dart:11) | Remains a `StatelessWidget` with constructor `SettingsScreen({super.key, required SettingsService settings, required VoidCallback onOpenLogsReports})`, plus the optional `TelemetryService? telemetry` input described in §11. Existing two-argument constructions must still compile. |
| Shell construction | [`app_shell.dart`](../lib/navigation/app_shell.dart:108) remains the owner of the persistent four-tab [`NavigationBar`](../lib/navigation/app_shell.dart:138), the [`IndexedStack`](../lib/navigation/app_shell.dart:134), the `PopScope` tab-back behavior, and Logs & Reports as a pushed `MaterialPageRoute` (not a fifth tab). Only the Settings page construction is in scope; no navigation, tab, or shell change is allowed. |
| Navigation invariants (resolved) | The global four-tab bottom navigation (Home, Detect, Settings, Help) **must not be removed**. The conflict with [`extracted-design-tokens-screenshot.md`](../design-reference/tokens/extracted-design-tokens-screenshot.md), which proposes removing the persistent bottom navigation, is **resolved in favor of preserving the existing [`AppShell`](../lib/navigation/app_shell.dart:20) navigation**. This is an owner decision; no navigation change is made by this redesign. |
| Settings listener | The body remains wrapped in a [`ListenableBuilder`](../lib/screens/settings_screen.dart:25) over the injected [`SettingsService`](../lib/services/settings_service.dart:60) so every control reflects and writes the persisted value. |
| Persistence | All six persisted settings keep their current keys, defaults, setters, and persistence timing: `setVibrationFeedback`, `setAutoStartDetection`, `setLowPowerMode`, `setAudioEnabled`, `setInferenceEngine`, `setDetectionConfidence` ([`settings-screen-analysis.md`](settings-screen-analysis.md:90)). |
| Sensitivity draft behavior | Preset taps persist immediately; slider changes are draft-only until `onChangeEnd`; `_handleSettingsChanged` re-syncs the draft from the service ([`settings_screen.dart`](../lib/screens/settings_screen.dart:145)). |
| Runtime behavior | No camera start, ML initialization, engine coordination, TTS, telemetry computation, persistence, or gesture state is added to Settings. |
| Global theme | The existing global dark [`buildEyeCueTheme()`](../lib/theme/app_theme.dart:13) and its use by [`EyeCueApp`](../lib/main.dart:61) remain unchanged. |
| Light-theme scope | The light surface is scoped to the Settings subtree only (the Home/Help `Theme` wrapper pattern). It must not leak into Detect, Home, Help, Logs & Reports, or the shell navigation bar. |

The primary implementation file is [`settings_screen.dart`](../lib/screens/settings_screen.dart:11).
No change is expected to [`app_home_theme.dart`](../lib/theme/app_home_theme.dart:1),
[`app_colors.dart`](../lib/theme/app_colors.dart:1),
[`app_spacing.dart`](../lib/theme/app_spacing.dart:1),
[`app_radii.dart`](../lib/theme/app_radii.dart:1), or
[`app_typography.dart`](../lib/theme/app_typography.dart:1) — Settings reuses the
existing `buildHomeTheme()` and `kHome*`/`kSpace*`/`kRadius*` tokens as-is
(see §7). The two existing test files are limited to the responsibilities defined
in this specification.

## 2. Reference composition and viewport treatment

**Analysis cross-reference:** [`settings-screen-analysis.md`](settings-screen-analysis.md:151)
and [`settings-screen-analysis.md`](settings-screen-analysis.md:410).

Three references inform this specification, and they play different roles:

| Reference | Role |
|---|---|
| [`design-reference/screens/settings-screen.png`](../design-reference/screens/settings-screen.png) | The **newer light direction** — the target visual language (light surface, rounded white cards, pale cyan Audio Guidance card, dark System Performance card). |
| [`design-reference/old_screen/settings_screen.jpg`](../design-reference/old_screen/settings_screen.jpg) | Confirms the **existing feature inventory** (Haptics, Performance, Inference Engine, Detection Sensitivity, Audio, Research). It is the pre-redesign dark screen and is **not** a target composition. |
| [`design-reference/tokens/design-tokens.png`](../design-reference/tokens/design-tokens.png) and [`design-reference/tokens/extracted-design-tokens-screenshot.md`](../design-reference/tokens/extracted-design-tokens-screenshot.md) | Supply the **token language** (colors, spacing, radii, shadows, type roles). The extracted Markdown is authoritative over the PNG where they disagree ([`settings-screen-analysis.md`](settings-screen-analysis.md:391)). |

**This is a token-consistent restyle, not a screenshot match.** The target
screenshot's sample metric values (`91.4 / % ACC`) and its `Concise` audio
mode/status-pill treatment are **overridden** by the authoritative token/spec
document ([`settings-screen-analysis.md`](settings-screen-analysis.md:169)):

1. **Audio Guidance is a standard On/Off toggle**, not a mode selector.
2. **Engine Selection and Detection Sensitivity are preserved** and regrouped
   into the card composition.
3. **The System Performance card shows live values**, not the screenshot's
   static sample values — and the third metric is truthful (see §6.4 and §11).

The Settings content area is composed above the existing shell navigation bar.
The Settings widget must not add a replacement navigation control; the retained
shell [`NavigationBar`](../lib/navigation/app_shell.dart:138) remains the
navigation surface and reduces the available Settings viewport.

The composition is a light Settings canvas only. The light surface is scoped to
the Settings subtree; it must not leak into other tabs or the shell navigation
bar.

## 3. Layout hierarchy

**Analysis cross-reference:** [`settings-screen-analysis.md`](settings-screen-analysis.md:75)
and [`settings-screen-analysis.md`](settings-screen-analysis.md:410).

The redesigned Settings layout follows the Home/Help responsive pattern
([`SafeArea`](../lib/screens/home_screen.dart:43) +
[`LayoutBuilder`](../lib/screens/home_screen.dart:44) + bounded/centered width +
scrollable body). The proposed hierarchy is:

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
                                └── ListView (or CustomScrollView)
                                    ├── _SettingsCard — Preferences
                                    ├── _SettingsCard — Audio Guidance
                                    ├── _SettingsCard — Engine & Sensitivity
                                    └── _SettingsCard — System Performance (dark)
```

The card widgets remain private to [`settings_screen.dart`](../lib/screens/settings_screen.dart:11)
following the existing `_`-prefixed convention (`_SectionHeader`,
`_SensitivityControls`). No new public reusable widget is justified by this
redesign.

### 3.1 Theme wrapper placement

The light `Theme` wrapper must be scoped to the Settings subtree only, mirroring
the Home/Help `Theme` wrapper pattern. It must be placed **inside** the Settings
page so it does not wrap the shell's [`NavigationBar`](../lib/navigation/app_shell.dart:138)
or leak into other tabs. The wrapper calls [`buildHomeTheme()`](../lib/theme/app_home_theme.dart:50)
as-is — no rename, no duplication, no new Settings-scoped theme builder
([`settings-screen-analysis.md`](settings-screen-analysis.md:277)).

### 3.2 Status-bar treatment

Because the Settings surface is light, the status bar must use **dark icons** via
`AnnotatedRegion<SystemUiOverlayStyle>` (the Home/Help pattern) so the
time/notifications remain visible on the light surface. This is scoped to the
Settings subtree ([`settings-screen-analysis.md`](settings-screen-analysis.md:446)).

## 4. Card grouping and order

**Analysis cross-reference:** [`settings-screen-analysis.md`](settings-screen-analysis.md:566)
and [`settings-screen-analysis.md`](settings-screen-analysis.md:574).

The Analysis confirms that Engine Selection and Detection Sensitivity **must be
added** to the card composition (they already exist and are preserved/regrouped)
and that the **exact card placement and order is a Design-Spec decision**
([`settings-screen-analysis.md`](settings-screen-analysis.md:577)).

**Card order (resolved — this specification's decision):**

| # | Card | Contents | Source of the controls |
|---|------|----------|------------------------|
| 1 | **Preferences** | `Vibration Feedback`, `Auto-Start on Open`, `Low Power Mode` | Existing `SwitchListTile`s ([`settings_screen.dart`](../lib/screens/settings_screen.dart:31)) |
| 2 | **Audio Guidance** | `Audio / Voice Guidance` On/Off toggle | Existing `SwitchListTile` bound to `settings.audioEnabled` / `settings.setAudioEnabled` ([`settings_screen.dart`](../lib/screens/settings_screen.dart:97)) |
| 3 | **Engine & Sensitivity** | `Inference Engine` (`RadioGroup<InferenceEngine>` + `RadioListTile`s) and `Detection Sensitivity` (preset `RadioGroup<DetectionSensitivityPreset>` + advanced `Slider`) | Existing controls ([`settings_screen.dart`](../lib/screens/settings_screen.dart:58), [`settings_screen.dart`](../lib/screens/settings_screen.dart:121)) |
| 4 | **System Performance** (dark) | Live FPS / latency / average-confidence metrics + `View Logs & Reports` action row | New presentation of existing telemetry + existing `onOpenLogsReports` callback ([`settings_screen.dart`](../lib/screens/settings_screen.dart:105)) |

**Rationale for this order (resolved):** it mirrors the existing top-to-bottom
control order in [`settings_screen.dart`](../lib/screens/settings_screen.dart:30)
(Vibration → Auto-Start → Low Power → Inference Engine → Detection Sensitivity →
Audio → Research), keeping the frequently-toggled switches first and the
researcher-facing entry last, while inserting the preserved Engine/Sensitivity
controls as a single grouped card immediately before the performance card so the
researcher-facing controls sit adjacent to the researcher-facing metrics. The
`View Logs & Reports` affordance moves from the old standalone `Research` section
into the System Performance card, matching the target composition
([`settings-screen-analysis.md`](settings-screen-analysis.md:166)).

**Engine Selection and Detection Sensitivity placement (resolved):** they are
kept together in one `Engine & Sensitivity` card placed **after Audio Guidance
and before System Performance**. Both are inference-configuration controls, they
are already adjacent in the current implementation
([`settings_screen.dart`](../lib/screens/settings_screen.dart:57) and
[`settings_screen.dart`](../lib/screens/settings_screen.dart:94)), and grouping
them avoids scattering inference settings across cards. This card order is
settled and is not an open item.

## 5. Header / title treatment

**Analysis cross-reference:** [`settings-screen-analysis.md`](settings-screen-analysis.md:260).

The Settings header uses a **plain screen-title treatment** consistent with the
light visual language. The retained `AppBar(title: Text('Settings'))`
([`settings_screen.dart`](../lib/screens/settings_screen.dart:24)) is the screen
title and renders on the light surface with the light ink text. The title must
be a real semantic heading (the `AppBar` title already provides this role), not
merely a styled `Text`.

The target screenshot's `YOUR EYECUE` brand label and its introductory paragraph
are **excluded** (owner decision, [`settings-screen-analysis.md`](settings-screen-analysis.md:562)).
No new intro/brand copy is added; the redesign follows the current Settings
content.

## 6. Card composition, icon treatment, and the dark System Performance card

**Analysis cross-reference:** [`settings-screen-analysis.md`](settings-screen-analysis.md:251)
and [`settings-screen-analysis.md`](settings-screen-analysis.md:301).

### 6.1 Light card composition

Each light card is presented on the light surface:

- **Card surface:** [`kHomeSurfaceCard`](../lib/theme/app_colors.dart:118) (`#FFFFFF`)
  on the [`kHomeSurfaceBase`](../lib/theme/app_colors.dart:115) (`#F5F5F5`) content
  background.
- **Corner radius:** [`kRadius24`](../lib/theme/app_radii.dart:34), matching the
  Home/Help large light surface. No raw `BorderRadius.circular(...)` literal.
- **Card padding:** token-based inner padding (baseline [`kSpace16`](../lib/theme/app_spacing.dart:34)),
  not a raw `EdgeInsets.all(16)` literal.
- **Card separation:** a token-based bottom margin between cards (baseline
  [`kSpace16`](../lib/theme/app_spacing.dart:34)), not a raw
  `EdgeInsets.only(bottom: 16)` literal.
- **Shadow:** [`kHomeShadowSoft`](../lib/theme/app_home_theme.dart:18), the same
  soft shadow the Home/Help light surfaces use, so cards lift off the `#F5F5F5`
  surface.

### 6.2 Audio Guidance card

The Audio Guidance card is a light card carrying the single On/Off toggle bound
to `settings.audioEnabled` / `settings.setAudioEnabled`
([`settings-screen-analysis.md`](settings-screen-analysis.md:174)). The target
screenshot's pale cyan card treatment may be expressed with the existing
[`kHomeAccentCyanLight`](../lib/theme/app_colors.dart:136) token as a card
surface tint; the toggle itself remains a standard `SwitchListTile` with its
existing semantics. **No `Concise` mode is reproduced** and no mode selector is
introduced.

### 6.3 Icon treatment

Existing leading icons on the setting rows (`Icons.vibration`, `Icons.autorenew`,
`Icons.battery_saver`, `Icons.volume_up`, `Icons.memory_rounded`,
`Icons.code_rounded`, `Icons.bar_chart_rounded`) are retained. Each icon is
**decorative** — it duplicates the adjacent title — and is excluded from the
accessibility tree (`ExcludeSemantics`). Icon color uses the light accent token
(e.g. [`kHomeAccentCyan`](../lib/theme/app_colors.dart:133) or the derived
`colorScheme.primary` from `buildHomeTheme()`), not a raw `Color(...)` literal.

### 6.4 Dark System Performance card

The System Performance card is the one **dark** surface in the light Settings
composition. Its surface is [`kHomeInk`](../lib/theme/app_colors.dart:124)
(`#0A0A0A`) — the confirmed value, which is already an existing token, so **no
new token is required** ([`settings-screen-analysis.md`](settings-screen-analysis.md:301)).

- **Card surface:** [`kHomeInk`](../lib/theme/app_colors.dart:124) (`#0A0A0A`).
- **Corner radius:** [`kRadius24`](../lib/theme/app_radii.dart:34).
- **Foreground text and metric values:** a light color derived from the active
  theme/`ColorScheme` (e.g. `onPrimary`/white) rather than a new token.
- **Shadow:** [`kHomeShadowElevated`](../lib/theme/app_home_theme.dart:27) is
  available for this large surface; [`kHomeShadowSoft`](../lib/theme/app_home_theme.dart:18)
  is the baseline.
- **Metrics:** three columns — `Avg FPS`, `Avg latency` (MS), and
  `Avg confidence` — using the truthful retained averages described in §11. The
  labels explicitly include "average" because the values are arithmetic means
  over retained samples, not instantaneous readings (§11.1). The
  `View Logs & Reports` action row sits inside this card and invokes the existing
  `onOpenLogsReports` callback ([`settings_screen.dart`](../lib/screens/settings_screen.dart:105)).

**The `%ACC` metric is excluded (confirmed).** No fabricated accuracy, precision,
recall, F1, or mAP value is displayed
([`settings-screen-analysis.md`](settings-screen-analysis.md:364)). The third
metric is **average detection confidence**, not accuracy/precision/recall/F1/mAP;
the app has no ground-truth evaluation, so any accuracy-style figure would be
fabricated.

## 7. Exact token usage

**Analysis cross-reference:** [`settings-screen-analysis.md`](settings-screen-analysis.md:277)
and [`settings-screen-analysis.md`](settings-screen-analysis.md:391).

Settings reuses the existing Home light theme and tokens **as-is** — no rename,
no duplication, no new Settings-scoped theme or token. The `kHome*`/`buildHomeTheme`
naming is retained even though Settings now consumes it; this is an accepted
naming trade-off confirmed by the owner ([`settings-screen-analysis.md`](settings-screen-analysis.md:517)).

### 7.1 Theme

| Token / builder | File | Settings use |
|---|---|---|
| [`buildHomeTheme()`](../lib/theme/app_home_theme.dart:50) | [`app_home_theme.dart`](../lib/theme/app_home_theme.dart:1) | The light `ThemeData` applied to the Settings subtree (IBM Plex Sans typography, light surface, cyan accent). Reused as-is. |

### 7.2 Color tokens

| Token | Value | Settings use |
|---|---|---|
| [`kHomeSurfaceBase`](../lib/theme/app_colors.dart:115) | `#F5F5F5` | Settings content background |
| [`kHomeSurfaceCard`](../lib/theme/app_colors.dart:118) | `#FFFFFF` | Light card surface |
| [`kHomeInk`](../lib/theme/app_colors.dart:124) | `#0A0A0A` | Dark System Performance card surface; primary light text |
| [`kHomeInkMuted`](../lib/theme/app_colors.dart:127) | `#667085` | Supporting copy on light cards |
| [`kHomeAccentCyan`](../lib/theme/app_colors.dart:133) | `#22C7F2` | Section/row icon accent (or the derived `colorScheme.primary`) |
| [`kHomeAccentCyanLight`](../lib/theme/app_colors.dart:136) | `#B9EFFF` | Optional Audio Guidance card surface tint |

No raw `Color(...)`, `Colors.*`, or alpha color literals are added to
[`settings_screen.dart`](../lib/screens/settings_screen.dart:11) for these roles.
Colors already derived from the active light `ThemeData`/`ColorScheme` (e.g.
`theme.colorScheme.surface`, `theme.colorScheme.primary`) are used via theme
lookup rather than duplicated as tokens.

### 7.3 Spacing tokens

Settings spacing is restricted to exactly these tokens:

| Token | Value | Settings use |
|---|---|---|
| [`kSpace6`](../lib/theme/app_spacing.dart:1) | 6 | Compact separation |
| [`kSpace8`](../lib/theme/app_spacing.dart:1) | 8 | Closely related text separation |
| [`kSpace12`](../lib/theme/app_spacing.dart:1) | 12 | Icon-to-title gap; metric column internals |
| [`kSpace16`](../lib/theme/app_spacing.dart:34) | 16 | Card inner padding and card-to-card separation |
| [`kSpace20`](../lib/theme/app_spacing.dart:1) | 20 | Major local block separation |
| [`kSpace24`](../lib/theme/app_spacing.dart:43) | 24 | Screen-level outer inset / large section gap |

`kSpace32` exists in [`app_spacing.dart`](../lib/theme/app_spacing.dart:1) but is
**not authorized for Settings**. Do not copy `32`, `48`, or `64` from the token
PNG as new Settings spacing values ([`settings-screen-analysis.md`](settings-screen-analysis.md:401)).

### 7.4 Radius tokens

| Token | Value | Settings use |
|---|---:|---|
| [`kRadius3`](../lib/theme/app_radii.dart:25) | 3 | Reserved accent rail treatment if used |
| [`kRadius14`](../lib/theme/app_radii.dart:28) | 14 | Compact toggle-like rounded treatment if a wrapper is needed |
| [`kRadius18`](../lib/theme/app_radii.dart:31) | 18 | Compact status treatment if required by the final composition |
| [`kRadius24`](../lib/theme/app_radii.dart:34) | 24 | Card corner radius (light cards and the dark System Performance card) |

No raw `BorderRadius.circular(...)` literal.

### 7.5 Shadow tokens

| Token | File | Settings use |
|---|---|---|
| [`kHomeShadowSoft`](../lib/theme/app_home_theme.dart:18) | [`app_home_theme.dart`](../lib/theme/app_home_theme.dart:1) | Baseline card shadow so cards lift off the light surface |
| [`kHomeShadowElevated`](../lib/theme/app_home_theme.dart:27) | [`app_home_theme.dart`](../lib/theme/app_home_theme.dart:1) | Optional elevated shadow for the large dark System Performance card |

### 7.6 Typography

Typography comes from [`buildHomeTheme()`](../lib/theme/app_home_theme.dart:50)
(IBM Plex Sans, runtime fetching disabled at the top of the builder). Card
headings use the light `titleMedium`/`titleLarge` roles; row titles use the
light `bodyLarge`/`titleMedium` roles; supporting copy uses the light
`bodyMedium` role with the muted ink color. No new type roles are introduced.

## 8. Responsive sizing rules

**Analysis cross-reference:** [`settings-screen-analysis.md`](settings-screen-analysis.md:410).

The reference canvas is **390 × 844** and is a proportional baseline, not a
source of Flutter pixel literals. Do not hardcode screenshot pixel dimensions.

### 8.1 Horizontal relationships

- Use the available content width from parent constraints; do not branch on
  device model or hardware type.
- Keep a leading/trailing content inset based on the approved spacing scale,
  with [`kSpace16`](../lib/theme/app_spacing.dart:34) as the baseline outer
  inset.
- Constrain the content to a **bounded/centered width** (Home/Help cap at ~480)
  so cards and text do not become unreadably wide on tablets or desktop-sized
  test constraints. The width is derived from constraints, not from a raster
  width.

### 8.2 Vertical relationships

- Place the screen title in the `AppBar` at the top of the Settings viewport.
- Stack the cards vertically in the order defined in §4, each separated by a
  token-based gap.
- Preserve scrolling when the available height is short or text scaling causes
  the content to exceed the viewport. Scrolling must not hide any card or make
  content unreachable.

### 8.3 Narrow, large, and scaled constraints

**Compact/wide transition (resolved):** the layout is **single-column at all
widths**, centered and capped at the same ~480 max content width used by Home and
Help, with **no breakpoint-driven layout switch** and no card reflow. This
matches the established Home/Help precedent (`LayoutBuilder` +
`constraints.maxWidth` + a ~480 max content width, no device branching) and
avoids `OrientationBuilder`/device branching while keeping the Settings cards
readable on wide constraints.

- At narrow widths, allow card titles, row titles, and supporting copy to wrap;
  never clip text or force horizontal overflow.
- At large widths, retain a readable max content width and preserve the centered
  card treatment.
- At short heights, preserve element order and allow vertical scrolling rather
  than shrinking text below its specified role size.
- At **200% text scale**, cards, titles, and copy must expand or wrap while the
  layout scrolls — no RenderFlex overflow.
- Do not add `OrientationBuilder`, orientation locks, new platform
  configuration, or portrait-only device behavior. The extracted token
  document's portrait-only statement is a broader product direction; the current
  app does not lock orientation, and this visual-only task must not introduce an
  orientation lock or change navigation ([`settings-screen-analysis.md`](settings-screen-analysis.md:426)).

## 9. Semantic labels and content structure

**Analysis cross-reference:** [`settings-screen-analysis.md`](settings-screen-analysis.md:433).

Settings is an interactive configuration screen, so the accessibility work is
both **semantic structure** and **control semantics**.

### 9.1 Semantic tree

Use this semantic order:

1. Screen title `Settings` (the `AppBar` title, a real semantic heading).
2. Preferences card — its heading, then the three toggles.
3. Audio Guidance card — its heading, then the On/Off toggle.
4. Engine & Sensitivity card — its heading, then the engine radios and the
   sensitivity presets/slider.
5. System Performance card — its heading, the three metric values as text, and
   the `View Logs & Reports` action.

### 9.2 Control semantics

Every interactive control keeps a semantic label, role, state (checked/selected),
hint, and enabled status:

- Toggles expose their checked state.
- Engine radios expose their selected state and the `Recommended`/`Advanced`
  grouping semantics already carried by the `InferenceEngine` enum
  ([`settings-screen-analysis.md`](settings-screen-analysis.md:108)).
- Sensitivity presets expose their selected state; the advanced slider keeps its
  existing container + label semantics including the current threshold value
  ([`settings_screen.dart`](../lib/screens/settings_screen.dart:177)).
- The `View Logs & Reports` row exposes a button/tap role and its hint.

### 9.3 Decorative exclusion and live regions

- Section/row icons are **decorative** (they duplicate the adjacent title) and
  are excluded from the accessibility tree via `ExcludeSemantics`.
- The live performance values are exposed as **text/semantics**, not color-only.
- The performance metrics must **not** become a per-frame TalkBack live region.
  Only deliberate status changes may be live regions
  ([`settings-screen-analysis.md`](settings-screen-analysis.md:448)).

### 9.4 No color- or motion-only meaning

Any accent/status color is decorative; the text and semantics carry the meaning.
No animated state is introduced, so no motion-only meaning exists.

## 10. Large-text behavior

**Analysis cross-reference:** [`settings-screen-analysis.md`](settings-screen-analysis.md:440).

- Test the Settings screen with the existing 200% [`scaledApp`](../test/accessibility/semantics_test.dart:54)
  helper.
- Permit card titles, row titles, supporting copy, and metric values to wrap and
  expand.
- Do not clip the screen title, any card heading, any row title, or any metric
  value.
- The layout must scroll rather than overflow at 200% text scale.
- Preserve the existing [`kMinTouchWidth`](../lib/theme/app_spacing.dart:51) and
  [`kMinTouchHeight`](../lib/theme/app_spacing.dart:54) guidance for every
  interactive control.

## 11. Loading / unavailable / disabled presentation

**Analysis cross-reference:** [`settings-screen-analysis.md`](settings-screen-analysis.md:313)
and [`settings-screen-analysis.md`](settings-screen-analysis.md:364).

### 11.1 Telemetry semantics (verified — must be reflected accurately)

[`TelemetryService`](../lib/services/telemetry_service.dart:175) exposes
**retained/rolling averages**, NOT instantaneous values:

| Member | Semantics |
|---|---|
| [`averageInferenceFps`](../lib/services/telemetry_service.dart:352) | Arithmetic mean of retained `RuntimeSample.inferenceFps`. |
| [`averageLatencyMs`](../lib/services/telemetry_service.dart:346) | Arithmetic mean of retained `RuntimeSample.latencyMs`. |
| [`averageConfidence`](../lib/services/telemetry_service.dart:358) | Arithmetic mean of retained `TelemetryRecord.confidence` (combines all engines and classes). |
| [`samples`](../lib/services/telemetry_service.dart:208) / [`records`](../lib/services/telemetry_service.dart:207) | Public unmodifiable lists. |
| [`summaryFor(engine)`](../lib/services/telemetry_service.dart:364) | Per-engine runtime summary. |

Runtime samples are capped at **500** and detection records at **2,000**, with
the oldest evicted first; the averages operate only on retained entries
([`telemetry_service.dart`](../lib/services/telemetry_service.dart:194)).
`totalDetections` reflects retained records after eviction and `framesProcessed`
counts `recordSample` calls ([`telemetry_service.dart`](../lib/services/telemetry_service.dart:215)).
There is **no** public clear/reset method, **no** `current`/`latest`/`last`
getter, and `startSession()` does not visibly clear retained telemetry
([`telemetry_service.dart`](../lib/services/telemetry_service.dart:219)).

**Therefore the spec describes FPS, latency, and confidence as retained/rolling
averages and must NOT imply instantaneous current values.**

### 11.2 Metric presentation

**Labels (resolved):** the three columns are labeled `Avg FPS`, `Avg latency`
(MS), and `Avg confidence`. The "average" wording is required because the values
are arithmetic means over retained samples, so omitting it would misrepresent
them as instantaneous.

| Column | Source | Label |
|---|---|---|
| FPS | [`averageInferenceFps`](../lib/services/telemetry_service.dart:352) | `Avg FPS` |
| MS | [`averageLatencyMs`](../lib/services/telemetry_service.dart:346) | `Avg latency` |
| Confidence | [`averageConfidence`](../lib/services/telemetry_service.dart:358) | `Avg confidence` |

`averageConfidence` is the arithmetic mean of retained detection confidences
across all engines and classes; `Avg confidence` is truthful and does not imply
accuracy.

**The `%ACC` metric is excluded (confirmed).** No fabricated accuracy, precision,
recall, F1, or mAP value is displayed
([`settings-screen-analysis.md`](settings-screen-analysis.md:364)). The third
metric is average detection confidence, not accuracy/precision/recall/F1/mAP.

### 11.3 Empty-telemetry presentation

When the retained lists are empty, the averages return `0`
([`telemetry_service.dart`](../lib/services/telemetry_service.dart:347);
confirmed by [`telemetry_service_test.dart`](../test/services/telemetry_service_test.dart:97),
which asserts `averageLatencyMs == 0` on an empty service).

**Presentation (resolved):** show `—` (em dash) for all three metrics when there
are no retained samples/records, and keep the metric rows visible. `0` would
falsely read as a measured zero FPS/latency/confidence, while hiding the rows
would make the card look broken; `—` is the conventional "no data" affordance and
stays readable at 200% text scale.

### 11.4 Null telemetry input

The optional `TelemetryService? telemetry` input keeps the existing two-argument
construction compiling. **Behavior (resolved):** when `telemetry` is `null`, the
System Performance card renders with the same `—` placeholders and no live
updates. This keeps the visual composition stable and avoids a conditional
layout, while remaining truthful that no data is available.

### 11.5 Disabled presentation

No Settings control is disabled by this redesign. If a future change introduces
a disabled control, its enabled/disabled presentation must follow the
accessibility rule (label, role, state, hint, enabled status), but that is out
of scope here.

## 12. Verification and acceptance criteria

**Analysis cross-reference:** [`settings-screen-analysis.md`](settings-screen-analysis.md:501)
and [`settings-screen-analysis.md`](settings-screen-analysis.md:586).

The implementation is complete only when all of the following are true:

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
- The light surface is scoped to the Settings subtree only and does not leak
  into the shell navigation bar or other tabs.

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
  two-argument test constructions compiling; it is called out here so the Plan
  stage does not treat it as an unapproved scope expansion.
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
verification policy ([`settings-screen-analysis.md`](settings-screen-analysis.md:586)).
The implemented Settings screen is verified on that connected physical Android
device, not an emulator or web target. The device check confirms the retained
four-tab navigation, the light Settings surface, the dark System Performance
card, the card radius/shadow visual tuning, large-text behavior, TalkBack
semantics, and the absence of RenderFlex overflows or exceptions in logcat. The
specific connected device may vary between sessions; the check runs against
whichever physical Android device is attached at implementation time, consistent
with the Home and Help specs.

## 13. Explicitly deferred work

**Analysis cross-reference:** [`settings-screen-analysis.md`](settings-screen-analysis.md:31)
and [`settings-screen-analysis.md`](settings-screen-analysis.md:469).

The following are not part of this Settings redesign:

1. A screenshot match of the target Settings composition (this is a
   token-consistent restyle).
2. The `YOUR EYECUE` brand label and the introductory paragraph from the target
   screenshot ([`settings-screen-analysis.md`](settings-screen-analysis.md:562)).
3. A `Concise` audio mode or any audio mode selector — Audio Guidance remains a
   standard On/Off toggle ([`settings-screen-analysis.md`](settings-screen-analysis.md:174)).
4. A `%ACC` metric or any fabricated accuracy/precision/recall/F1/mAP value
   ([`settings-screen-analysis.md`](settings-screen-analysis.md:364)).
5. Renaming, duplicating, or generalizing the `kHome*` tokens or
   `buildHomeTheme()` into a shared light theme
   ([`settings-screen-analysis.md`](settings-screen-analysis.md:277)).
6. Adding a new Settings-scoped theme or token.
7. Replacing or removing the persistent four-tab navigation bar, or moving
   Logs & Reports out of its pushed-route behavior
   ([`settings-screen-analysis.md`](settings-screen-analysis.md:116)).
8. Moving engine, camera, inference, TTS, telemetry computation, correction, or
   runtime-state logic into Settings.
9. Redesigning Home, Help, Detection, Logs & Reports, or the shell.
10. Global migration from the dark theme to a light theme.
11. Portrait locking or new orientation configuration
    ([`settings-screen-analysis.md`](settings-screen-analysis.md:426)).
12. A new state-management, routing, gesture, or UI component package.
13. Any change to `lib/models/`, `lib/services/`, or `lib/main.dart` beyond the
    two pre-approved exceptions ([`settings-screen-analysis.md`](settings-screen-analysis.md:469)).
14. Any change to `SettingsService`, `AppSettings` JSON/migration/clamping/
    quantization behavior, inference behavior, camera/runtime behavior, or TTS
    behavior.

## Open Questions / Needs Verification

**Analysis cross-reference:** [`settings-screen-analysis.md`](settings-screen-analysis.md:540)
and [`settings-screen-analysis.md`](settings-screen-analysis.md:574).

The product and architecture decisions required for this Design-Spec are
resolved by the Analysis and by confirming them against the codebase. Each
confirmed value has been moved into its owning section above and removed from
this list:

- **Exact card grouping and order — RESOLVED.** Preferences → Audio Guidance →
  Engine & Sensitivity → System Performance. Confirmed against the existing
  top-to-bottom control order in
  [`settings_screen.dart`](../lib/screens/settings_screen.dart:30). (§4)
- **Exact placement of Engine Selection and Detection Sensitivity — RESOLVED.**
  Kept together in one `Engine & Sensitivity` card placed after Audio Guidance
  and before System Performance. (§4)
- **FPS/latency labels — RESOLVED.** Label them `Avg FPS` and `Avg latency`,
  because the values are arithmetic means over retained samples. (§11.2)
- **Confidence label — RESOLVED.** `Avg confidence`; `averageConfidence` is the
  arithmetic mean of retained detection confidences and does not imply accuracy.
  (§11.2)
- **Empty-telemetry presentation — RESOLVED.** Show `—` (em dash) for all three
  metrics when there are no retained samples/records, and keep the metric rows
  visible. (§11.3)
- **Null-state behavior when `TelemetryService?` is absent — RESOLVED.** Render
  the System Performance card with the same `—` placeholders and no live
  updates. (§11.4)
- **Optional telemetry constructor seam — RESOLVED.** Classified as a narrow,
  additive UI-boundary change (an optional `TelemetryService?` parameter on
  `SettingsScreen` plus forwarding the already-constructed service from
  [`app_shell.dart`](../lib/navigation/app_shell.dart:108)); it adds no new
  service and changes no existing constructor argument. (§12)
- **Responsive compact/wide transition — RESOLVED.** Single-column layout at all
  widths, centered and capped at the same ~480 max content width used by Home
  and Help, with no breakpoint-driven layout switch. (§8.3)
- **Extracted-token-document navigation conflict — RESOLVED (owner decision).**
  The global four-tab bottom navigation (Home, Detect, Settings, Help) is
  preserved; the conflict with
  [`extracted-design-tokens-screenshot.md`](../design-reference/tokens/extracted-design-tokens-screenshot.md)
  is resolved in favor of preserving the existing
  [`AppShell`](../lib/navigation/app_shell.dart:20) navigation. No navigation
  change is made. (§1)
- **`%ACC` exclusion and no fabricated metric — CONFIRMED.** `%ACC` is excluded,
  and the third metric is average detection confidence, not
  accuracy/precision/recall/F1/mAP. (§6.4, §11.2)
- **Physical-device verification timing — RESOLVED.** The device check runs at
  implementation time against whichever physical Android device is attached,
  consistent with the Home and Help specs. (§12)

No items remain open. The only implementation-time confirmations are the visual
tuning of the dark System Performance card and the card radius/shadow on the
attached physical Android device, which are performed during the Code stage per
the project verification policy.