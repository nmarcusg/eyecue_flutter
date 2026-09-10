# EyeCue — Home Screen Implementation Plan

> **Stage:** Plan only. No application code, tests, assets, dependency
> declarations, or navigation behavior are changed by this document.
>
> **Task type:** Visual-only Home-screen redesign.
>
> **Source of truth (in order):** the approved
> [`home-screen-design-spec.md`](home-screen-design-spec.md) (Design-Spec) →
> the approved [`home-screen-analysis.md`](home-screen-analysis.md) (Analysis),
> especially its **Resolved Open Questions / Decisions** section → the
> authoritative token source
> [`extracted-design-tokens-screenshot.md`](../design-reference/tokens/extracted-design-tokens-screenshot.md).
> The extracted token Markdown is authoritative over the token-summary PNG, as
> resolved in [`home-screen-analysis.md`](home-screen-analysis.md:571).

## 1. Scope and invariants

**Design-Spec cross-reference:** [`home-screen-design-spec.md`](home-screen-design-spec.md:13)
and [`home-screen-design-spec.md`](home-screen-design-spec.md:468).

This plan turns the Design-Spec into concrete, implementable edits for a
visual-only Home redesign. Every file listed below traces back to the
Design-Spec/analysis; there are no speculative refactors.

The implementation must preserve these contracts (unchanged from the current
code):

| Contract | Current code | Preservation requirement |
|---|---|---|
| [`HomeScreen.settings`](../lib/screens/home_screen.dart:12) | Injected [`SettingsService`](../lib/services/settings_service.dart:60) input | Keep the input and the [`ListenableBuilder`](../lib/screens/home_screen.dart:89) listener so the preference presentation updates when `autoStartDetection` changes. |
| [`HomeScreen.onGoToDetection`](../lib/screens/home_screen.dart:13) | Callback invoked by the CTA | Keep the callback; the redesigned accessible CTA invokes it exactly once per activation. |
| [`AppShell`](../lib/navigation/app_shell.dart:20) | Persistent four-tab [`NavigationBar`](../lib/navigation/app_shell.dart:138) + [`IndexedStack`](../lib/navigation/app_shell.dart:134) | No shell change; the retained nav bar stays visible below the redesigned Home content. |
| Runtime behavior | No camera/ML/engine/TTS/telemetry/persistence/gesture state in Home | No runtime state source is added. |
| Global theme | [`buildEyeCueTheme()`](../lib/theme/app_theme.dart:13) dark theme used by [`EyeCueApp`](../lib/main.dart:61) with `ThemeMode.dark` | Unchanged; Home uses a locally scoped light context. |

### Files in scope

| File | Design-Spec responsibility | Scope rule |
|---|---|---|
| [`lib/screens/home_screen.dart`](../lib/screens/home_screen.dart:21) | Replace the dark centered-column hierarchy with the responsive reference composition; preserve settings listening and CTA callback. | Primary UI file. |
| [`lib/theme/app_colors.dart`](../lib/theme/app_colors.dart:1) | Add the approved `kHome*` light semantic colors. | UI token layer only. |
| [`lib/theme/app_radii.dart`](../lib/theme/app_radii.dart:1) | Add missing authoritative `kRadius3`, `kRadius14`, `kRadius18`, and `kRadius24`; reuse existing values where possible. | UI token layer only. |
| Local Home theme file (see §6) | Provide Home-local typography/decoration theme data without changing the global dark theme. | Local Home theme only. |
| [`pubspec.yaml`](../pubspec.yaml:9) | Add `google_fonts: ^8.2.1`, register `assets/logo.png`, and register the offline IBM Plex Sans font asset folder. | Minimal packaging prerequisite. |
| [`test/widget_test.dart`](../test/widget_test.dart:12) | Extend the existing `HomeScreen` group with visual/state/callback regressions. | No new test file. |
| [`test/accessibility/semantics_test.dart`](../test/accessibility/semantics_test.dart:115) | Add Home status, wordmark, CTA, decorative-image, and 200% text-scale semantics coverage using existing helpers. | No new test file. |

### Files that must remain untouched

[`AppShell`](../lib/navigation/app_shell.dart:20), [`main.dart`](../lib/main.dart:25),
[`SettingsService`](../lib/services/settings_service.dart:60), every model/service,
every non-Home screen, [`assets/logo.png`](../assets/logo.png) (consumed, not
edited), and all `design-reference/` files. No new state-management, routing,
gesture, or UI-component package is introduced.

## 2. Confirmed packaging facts

**Design-Spec cross-reference:** [`home-screen-design-spec.md`](home-screen-design-spec.md:322)
and [`home-screen-design-spec.md`](home-screen-design-spec.md:397).

The following facts are confirmed before being included in this plan:

- **`google_fonts: ^8.2.1`** — confirmed as the dependency to add to
  [`pubspec.yaml`](../pubspec.yaml:9). The package exposes
  `GoogleFonts.plexSans(...)` and `GoogleFonts.plexSansTextTheme(...)` and
  supports offline asset bundling.
- **Offline asset-bundling setup** — confirmed: download the required IBM Plex
  Sans weights, place them under a dedicated asset folder (`assets/fonts/`),
  declare that folder under `assets:` in [`pubspec.yaml`](../pubspec.yaml:43),
  and keep the original Google Fonts filenames so the package resolves them
  locally. No `fonts:` section is required. Set
  `GoogleFonts.config.allowRuntimeFetching = false` so the package never falls
  back to a network request; the resolved placement is at the top of the
  Home-local theme builder (see §7.1), not in `main.dart`.
- **`assets/logo.png` registration** — confirmed: the file exists (512×545 RGBA,
  mark-only on transparency) but is **not** declared in
  [`pubspec.yaml`](../pubspec.yaml:45). Add the one-line `- assets/logo.png`
  registration. The image is consumed, never edited; the wordmark stays live
  text.
- **New `kHome*` color tokens** — confirmed for addition to
  [`app_colors.dart`](../lib/theme/app_colors.dart:1) (see §5.1).
- **Missing `kRadius3`/`kRadius14`/`kRadius18`/`kRadius24` tokens** — confirmed
  as absent from [`app_radii.dart`](../lib/theme/app_radii.dart:1) (current set:
  `kRadius4`, `kRadius6`, `kRadius8`, `kRadius12`, `kRadius16`, `kRadius20`).
  Add the four missing values (see §5.2).

### IBM Plex Sans font filenames (resolved)

The exact IBM Plex Sans font filenames for the four required weights are
confirmed. The `google_fonts` package resolves bundled fonts by the original
Google Fonts filename (family name with spaces removed + the weight suffix from
the package's documented `FontWeight`→suffix mapping). The canonical Google
Fonts static filenames for the IBM Plex family follow the
`IBMPlexSans-{Weight}.ttf` convention (confirmed against the google/fonts repo
naming for the IBM Plex family). The four files to bundle under `assets/fonts/`
are:

| Weight | Filename |
|---|---:|
| 400 (Regular) | `IBMPlexSans-Regular.ttf` |
| 500 (Medium) | `IBMPlexSans-Medium.ttf` |
| 600 (SemiBold) | `IBMPlexSans-SemiBold.ttf` |
| 700 (Bold) | `IBMPlexSans-Bold.ttf` |

These are placed in the declared asset folder unchanged so `google_fonts` can
resolve them locally. The files are downloaded from Google Fonts during
implementation; the filenames above are the canonical names the package expects.
See §7.

## 3. Reference composition and viewport treatment

**Design-Spec cross-reference:** [`home-screen-design-spec.md`](home-screen-design-spec.md:39).

The ready composition is based on
[`home_screen.png`](../design-reference/screens/home_screen.png). The preparing
composition in [`home-preparing.png`](../design-reference/screens/home-preparing.png)
is a visual reference for a future runtime state only and is **not** implemented
in this feature.

The Home content area is composed above the retained shell navigation bar:

1. A preference/status badge aligned to the leading content edge.
2. A large centered mark using [`assets/logo.png`](../assets/logo.png).
3. A centered live-text `EyeCue` wordmark below the mark.
4. A lower instruction region containing a truthful headline, supporting copy,
   the retained accessible CTA, and the light cyan rail accent.

The screenshots' OS clock/battery/signal row and any app bar or replacement
navigation control are not part of the widget. The light surface is scoped to
the Home subtree and must not leak into Detect, Settings, Help, Logs & Reports,
or the shell navigation bar.

## 4. Responsive layout plan

**Design-Spec cross-reference:** [`home-screen-design-spec.md`](home-screen-design-spec.md:68).

The reference canvas is 390×844 and is a proportional baseline, not a source of
Flutter pixel literals. Reuse the existing [`SafeArea`](../lib/screens/home_screen.dart:25),
[`LayoutBuilder`](../lib/screens/home_screen.dart:27), and
[`SingleChildScrollView`](../lib/screens/home_screen.dart:29) pattern.

### 4.1 Horizontal relationships

- Use the available content width from parent constraints; do not branch on
  device model or hardware type.
- Keep a leading/trailing content inset based on the approved spacing scale,
  with [`kSpace16`](../lib/theme/app_spacing.dart:34) as the baseline outer
  inset.
- Keep the status badge intrinsically sized and leading-aligned; it must not
  stretch to the full viewport width.
- Constrain the brand group to a centered bounded width. The mark is a
  proportional visual element, not a fixed 96-logical-pixel icon.
- Constrain the lower instruction region to a centered proportion of the
  viewport so its text and rail do not become unreadably wide on large
  constraints. Derive the width from constraints, not from the screenshot's
  raster width.
- The wordmark remains centered live text and may wrap only in an unusually
  narrow or heavily scaled constraint; it must not become an image.

### 4.2 Vertical relationships

- Place the badge near the top of the SafeArea content with token-based inset.
- Give the brand group the dominant vertical share, with the mark above the
  wordmark and a deliberate token-based gap between them.
- Anchor the instruction region toward the lower part of the available Home
  viewport, leaving space for the CTA and the retained navigation bar.
- Use proportional/flexible relationships for the large blank areas; do not
  encode the reference's absolute `y` coordinates.
- Preserve scrolling when the available height is short or text scaling causes
  the preferred composition to exceed the viewport. Scrolling must not hide the
  CTA or make the badge unreachable.

### 4.3 Narrow, large, and scaled constraints

- At narrow widths, allow the preference copy and lower instruction copy to
  wrap; never clip text or force horizontal overflow.
- At large widths, retain a readable max content width for the lower region and
  preserve the centered brand treatment.
- At short heights, preserve element order and allow vertical scrolling rather
  than shrinking text below its specified role size.
- At 200% text scale, the badge, copy, and CTA must expand or wrap while the
  logo remains decorative and bounded.
- Do not add `OrientationBuilder`, orientation locks, new platform
  configuration, or portrait-only device behavior.

## 5. Token additions

**Design-Spec cross-reference:** [`home-screen-design-spec.md`](home-screen-design-spec.md:242).

### 5.1 Color tokens — [`lib/theme/app_colors.dart`](../lib/theme/app_colors.dart:1)

Add the following semantic constants using the existing `k`-prefixed convention.
These are the approved values from the authoritative extracted Markdown source.
Do not replace existing global dark tokens or reinterpret
[`kAccent`](../lib/theme/app_colors.dart:27) for Home.

| Token | Value | Home use |
|---|---|---|
| `kHomeSurfaceBase` | `#F5F5F5` | Home content background |
| `kHomeSurfaceCard` | `#FFFFFF` | Light CTA/badge/card surfaces when needed |
| `kHomeSurfaceCard96` | `rgba(255,255,255,0.96)` | Preference/status badge surface |
| `kHomeInk` | `#0A0A0A` | Wordmark and primary Home text |
| `kHomeInkMuted` | `#667085` | Supporting copy and off-state dot |
| `kHomeInkSubtle` | `#99A5AA` | Tertiary Home text only if required by the approved composition |
| `kHomeAccentCyan` | `#22C7F2` | Ready dot, primary Home accent, active light treatment |
| `kHomeAccentCyanLight` | `#B9EFFF` | Static rail accent |
| `kHomeAccentCyanDark` | `#087A9E` | Accessible dark cyan variant for a Home-specific pressed/glyph treatment if needed |
| `kHomeWarningAmber` | `#F5B942` | Reserved for the deferred Preparing variant; not used to imply Auto-Start off |

Do not add raw `Color(...)`, `Colors.*`, or alpha color literals to
[`home_screen.dart`](../lib/screens/home_screen.dart:21) for these roles.

### 5.2 Radius tokens — [`lib/theme/app_radii.dart`](../lib/theme/app_radii.dart:1)

Add the missing authoritative values as named `kRadius*` tokens. Reuse existing
matching tokens where available (`kRadius12` already exists).

| Token | Value | Home use |
|---|---:|---|
| `kRadius3` | 3 | Cyan rail |
| `kRadius14` | 14 | Home-local CTA/toggle-like rounded treatment if a wrapper is needed |
| `kRadius18` | 18 | Compact status treatment if required by the final composition |
| `kRadius24` | 24 | Large status badge and large Home surfaces |

### 5.3 Spacing

The extracted Markdown wins over the PNG's coarser spacing summary. Home uses
the spacing scale `6, 8, 12, 16, 20, 24`, represented by the existing
[`app_spacing.dart`](../lib/theme/app_spacing.dart:1) tokens (`kSpace6`,
`kSpace8`, `kSpace12`, `kSpace16`, `kSpace20`, `kSpace24`). No new spacing
tokens are required; do not copy `32`, `48`, or `64` from the token PNG.

### 5.4 Shadows as a theme component

Shadows are not entries in [`app_colors.dart`](../lib/theme/app_colors.dart:1).
Define them in the Home-local theme/decoration component (see §6):

| Name | Definition | Intended use |
|---|---|---|
| `shadow-soft` | `0px 6px 18px rgba(10,10,10,0.08)` | Preference/status badge |
| `shadow-elevated` | `0px 10px 28px rgba(10,10,10,0.07)` | A large Home surface only if the implementation retains one |
| `shadow-knob` | `0px 2px 5px rgba(0,0,0,0.12)` | Not used by the current Home composition; reserved for a future control |

## 6. Local Home theme file

**Design-Spec cross-reference:** [`home-screen-design-spec.md`](home-screen-design-spec.md:232)
and [`home-screen-design-spec.md`](home-screen-design-spec.md:303).

Home uses a locally scoped light visual theme/token context. The global dark
theme, `ThemeMode.dark`, and shell navigation colors are unchanged. The local
Home context supplies the light background, ink, cyan accent, and Home
typography to the Home subtree only.

The Design-Spec permits this to live in [`app_theme.dart`](../lib/theme/app_theme.dart:13)
**or** another `app_*.dart` theme file, provided it does not mutate
[`buildEyeCueTheme()`](../lib/theme/app_theme.dart:13) or the global navigation
theme. **Plan decision (resolved):** add a new UI-owned theme file
[`lib/theme/app_home_theme.dart`](../lib/theme/app_home_theme.dart) (new) that
exposes a Home-local light `ThemeData`/decoration builder and the `shadow-soft` /
`shadow-elevated` / `shadow-knob` `BoxShadow` lists.

**Why this location:** the naming-convention rule
([`.roo/rules/rules-frontend/02-naming-convention.md`](../.roo/rules/rules-frontend/02-naming-convention.md:14))
requires design tokens/theme in `lib/theme/` to be `app_*.dart` files, so the
file is named `app_home_theme.dart` (not `home_theme.dart`). This keeps the
global [`app_theme.dart`](../lib/theme/app_theme.dart:13) byte-stable and
satisfies the Design-Spec's "another `app_*.dart` theme file" option. It is the
only new file in the plan and is justified by the Design-Spec's explicit
allowance for a separate `app_*.dart` theme file.

The Home-local theme consumes the new `kHome*` color tokens and the IBM Plex
Sans text theme (see §7). It must not be applied above the Home subtree.

## 7. Typography and offline font packaging

**Design-Spec cross-reference:** [`home-screen-design-spec.md`](home-screen-design-spec.md:322).

### 7.1 Dependency and offline setup

- Add `google_fonts: ^8.2.1` to the `dependencies:` section of
  [`pubspec.yaml`](../pubspec.yaml:9).
- Bundle the IBM Plex Sans font files under a dedicated asset folder (e.g.
  `assets/fonts/`) and declare that folder under `assets:` in
  [`pubspec.yaml`](../pubspec.yaml:43). Keep the original Google Fonts filenames
  so the package resolves them locally; no `fonts:` section is required.
- Set `GoogleFonts.config.allowRuntimeFetching = false` so the package never
  falls back to a network request.

**Placement decision (resolved):** set `GoogleFonts.config.allowRuntimeFetching
= false` at the top of the Home-local theme builder in
[`lib/theme/app_home_theme.dart`](../lib/theme/app_home_theme.dart), before any
`GoogleFonts.plexSansTextTheme(...)` call. **Why:** the frontend scope rule's
narrow [`main.dart`](../lib/main.dart:25) exception
([`.roo/rules/rules-frontend/01-scope.md`](../.roo/rules/rules-frontend/01-scope.md:16))
covers only Marionette initialization and theme consumption; setting the flag in
`main()` would be a third `main.dart` change not covered by that exception.
Because IBM Plex Sans is applied only in the Home-local theme, setting the flag
at the top of that theme builder (before the `GoogleFonts` call) achieves the
same no-network guarantee without touching `main.dart`. The flag is a static
config that can be set repeatedly without side effects, so this is safe and
idempotent. This keeps the change entirely within the UI-owned `lib/theme/`
folder.

The four bundled font files are `IBMPlexSans-Regular.ttf` (400),
`IBMPlexSans-Medium.ttf` (500), `IBMPlexSans-SemiBold.ttf` (600), and
`IBMPlexSans-Bold.ttf` (700) under `assets/fonts/` (see §2).

### 7.2 Material role mapping

The local Home text theme maps the extracted IBM Plex Sans roles as follows:

| Material role | Size | Weight | Home application |
|---|---|---:|---:|---|
| `displayLarge` | 56 | 700 | Live `EyeCue` wordmark |
| `displaySmall` | 24 | 700 | Reference role retained in the local mapping; not required by the current Home composition |
| `headlineLarge` | 32 | 700 | Lower instruction headline |
| `titleLarge` | 24 | 600 | Optional Home-local major action heading; do not use to replace the CTA semantics |
| `titleMedium` | 18 | 600 | Optional supporting emphasis |
| `bodyLarge` | 18 | 500 | Optional emphasized guidance |
| `bodyMedium` | 18 | 400 | Preference-truthful supporting copy |
| `labelLarge` | 14 | 600 | CTA text where the local button theme controls it |
| `labelMedium` | 14 | 500 | Status badge text or compact hints |
| `labelSmall` | 14 | 500 | Dense label only if introduced by the approved composition |

Bundle exactly these IBM Plex Sans weights for the current Home mapping:
Regular (400), Medium (500), SemiBold (600), and Bold (700). No other font
weights are required.

Line height and letter spacing are not specified in the extracted source. The
local Home IBM Plex Sans theme uses the resolved Flutter/Google Fonts role
defaults for line height and letter spacing, matching the global theme's
convention (which sets no `height`/`letterSpacing` on any role).

## 8. Concrete edits to [`lib/screens/home_screen.dart`](../lib/screens/home_screen.dart:21)

**Design-Spec cross-reference:** [`home-screen-design-spec.md`](home-screen-design-spec.md:131),
[`home-screen-design-spec.md`](home-screen-design-spec.md:202), and
[`home-screen-design-spec.md`](home-screen-design-spec.md:468).

The primary implementation file. The redesign replaces the dark centered-column
hierarchy with the responsive reference composition while preserving the
`settings` input, the `ListenableBuilder` listener, and the `onGoToDetection`
callback.

### 8.1 Build-method structure

Replace the current `Scaffold → SafeArea → LayoutBuilder → SingleChildScrollView
→ ConstrainedBox → Column` body with a Home-local light context wrapping the
same responsive/scroll-safe skeleton:

- Wrap the Home subtree in the Home-local light theme (from §6) so the light
  surface and ink apply only to Home.
- Keep `SafeArea`, `LayoutBuilder`, and `SingleChildScrollView`.
- Compose, in order: the leading status badge, the centered brand group (logo
  mark + live wordmark), and the lower instruction region (headline, supporting
  copy, accessible CTA, cyan rail).
- Use proportional/flexible relationships and token spacing; do not encode
  screenshot pixel positions.

### 8.2 Preference-derived status badge (private `_StatusBadge`)

Replace the current private [`_StatusCard`](../lib/screens/home_screen.dart:81)
with a private status badge that keeps the `ListenableBuilder` over the injected
`settings` service. The badge is a non-interactive semantic container.

When `autoStartDetection` is `true`:

- Badge text: `READY`.
- Dot/accent: [`kHomeAccentCyan`](../lib/theme/app_colors.dart:1).
- Badge surface: [`kHomeSurfaceCard96`](../lib/theme/app_colors.dart:1).
- Accessible status meaning: `Auto-Start is on. Detection will begin when you open Detect.`

When `autoStartDetection` is `false`:

- Badge text: `AUTO-START OFF`.
- Dot/accent: [`kHomeInkMuted`](../lib/theme/app_colors.dart:1), not the
  preparing amber.
- Badge surface: [`kHomeSurfaceCard96`](../lib/theme/app_colors.dart:1).
- Accessible status meaning: `Auto-Start is off. Open Detect and press Start to begin.`

The off-state badge wording is a truthful Home-specific presentation of the
existing two-way setting. It must not use `PREPARING`, `RUNNING`, or another
runtime claim. The badge is intrinsically sized and leading-aligned, uses the
authoritative 18/24 radii, and must wrap rather than clip at 200% text scale.
Its final dot size and pill width are confirmed visually on the physical Android
device during implementation.

### 8.3 Preference-truthful supporting copy

Use the following exact preference-truthful supporting copy below the lower
instruction headline:

| Preference | Supporting copy |
|---|---|
| On | `Auto-Start is on. Detection will begin when you open Detect.` |
| Off | `Auto-Start is off. Open Detect and press Start to begin.` |

The existing copy beginning `Detection is already running` must be removed. Do
not use `Detection begins immediately`, because that would imply the deferred
app-launch auto-start behavior.

### 8.4 Retained accessible CTA

The real Home action remains [`AccessibleButton`](../lib/widgets/accessible_button.dart:8)
with:

- visible label: `Go to Live Camera`;
- existing camera icon treatment unless a Home-local visual wrapper is required;
- `prominent: true` or an equivalent Home-local presentation that preserves its
  callback and semantics;
- activation callback: [`onGoToDetection`](../lib/screens/home_screen.dart:13);
- minimum touch target preserved through the existing 64×56 logical-pixel
  contract in [`AccessibleButton`](../lib/widgets/accessible_button.dart:41).

The button may be placed inside the lower instruction region and visually styled
through the Home-local light theme. Do not modify the shared visual defaults of
[`AccessibleButton`](../lib/widgets/accessible_button.dart:8).

### 8.5 Deferred gesture and rail

Do not add a swipe recognizer, gesture-only start path, misleading swipe
instruction, or semantic swipe action. The reference's `Swipe right to start!`
text and handler are deferred. The cyan rail may remain as a static decorative
accent below the instruction/copy area; it is not an interactive track, progress
indicator, or gesture affordance and must be excluded from semantics.

### 8.6 Logo and wordmark

Use the existing mark-only [`assets/logo.png`](../assets/logo.png) as the visual
mark (decorative, excluded from semantics when the adjacent live wordmark is
present). The `EyeCue` wordmark is separate live text using the local
`displayLarge` IBM Plex Sans mapping. Do not bake the wordmark into the image.

### 8.7 Private component boundary

Keep screen-only helpers private to [`home_screen.dart`](../lib/screens/home_screen.dart:81),
following the existing `_StatusCard` convention. A private status badge and a
private instruction region are acceptable if they reduce build-method
complexity; do not create a public component solely for this redesign.

## 9. Concrete edits to the token files

### 9.1 [`lib/theme/app_colors.dart`](../lib/theme/app_colors.dart:1)

Append the ten `kHome*` semantic color constants from §5.1 using the existing
`k`-prefixed convention and doc-comment style. No existing token is modified.

### 9.2 [`lib/theme/app_radii.dart`](../lib/theme/app_radii.dart:1)

Append `kRadius3`, `kRadius14`, `kRadius18`, and `kRadius24` from §5.2 using the
existing doc-comment style. `kRadius12` already exists and is reused; no
existing token is modified.

## 10. Concrete edits to [`pubspec.yaml`](../pubspec.yaml:9)

**Design-Spec cross-reference:** [`home-screen-design-spec.md`](home-screen-design-spec.md:322)
and [`home-screen-design-spec.md`](home-screen-design-spec.md:397).

- Add `google_fonts: ^8.2.1` to the `dependencies:` section.
- Under `flutter: assets:`, add `- assets/logo.png`.
- Under `flutter: assets:`, add the offline IBM Plex Sans font asset folder
  (e.g. `- assets/fonts/`).

No unrelated dependency or asset changes. The font files themselves are added
under `assets/fonts/` during implementation (downloaded from Google Fonts with
their original filenames); this plan does not commit binary font files.

## 11. Concrete edits to [`test/widget_test.dart`](../test/widget_test.dart:12)

**Design-Spec cross-reference:** [`home-screen-design-spec.md`](home-screen-design-spec.md:486)
and [`home-screen-design-spec.md`](home-screen-design-spec.md:530).

Extend the existing `HomeScreen` group (no new test file). The current tests
assert the old copy (`Smart navigation assistance for visually impaired users.`
and `Detection is already running`), which the redesign removes, so those
assertions must be updated to the new preference-truthful copy. Add/update:

- Branding: the live `EyeCue` wordmark is present.
- Auto-Start on: `READY` badge and the exact on copy
  (`Auto-Start is on. Detection will begin when you open Detect.`).
- Auto-Start off: `AUTO-START OFF` badge and the exact off copy
  (`Auto-Start is off. Open Detect and press Start to begin.`).
- Listener update: toggling `SettingsService.autoStartDetection` updates the
  Home presentation through the existing listener behavior.
- CTA activation: tapping `Go to Live Camera` invokes `onGoToDetection` exactly
  once.

**Widget-test font resolution (resolved):** because the resolved placement sets
`GoogleFonts.config.allowRuntimeFetching = false` in the Home-local theme
builder, and the bundled IBM Plex Sans assets are declared in
[`pubspec.yaml`](../pubspec.yaml:43) under `assets/fonts/`, the Home widget
tests resolve the fonts locally from the asset bundle (flutter_test loads real
project assets declared under `assets:`). No network fetch is attempted and no
test-only font override is required. The existing `HomeScreen` group in
[`widget_test.dart`](../test/widget_test.dart:12) and the new Home semantics
group in [`semantics_test.dart`](../test/accessibility/semantics_test.dart:115)
render with the bundled fonts, matching production.

## 12. Concrete edits to [`test/accessibility/semantics_test.dart`](../test/accessibility/semantics_test.dart:115)

**Design-Spec cross-reference:** [`home-screen-design-spec.md`](home-screen-design-spec.md:487)
and [`home-screen-design-spec.md`](home-screen-design-spec.md:530).

Add a Home semantics group (no new test file) reusing the existing helpers
[`scaledApp`](../test/accessibility/semantics_test.dart:54),
[`expectButtonSemantics`](../test/accessibility/semantics_test.dart:63),
[`expectSemanticNode`](../test/accessibility/semantics_test.dart:97), and
[`withSemantics`](../test/accessibility/semantics_test.dart:103). Coverage:

- The status node exposes the complete preference-truthful meaning for both
  Auto-Start on and off (distinguishing the two states by text, not color).
- The live `EyeCue` wordmark is present.
- The `Go to Live Camera` CTA retains an actionable button role, enabled state,
  hint, and callback.
- The logo image and cyan rail are decorative/excluded (no duplicate `EyeCue`
  label).
- No duplicate semantics from a wrapper and the `AccessibleButton` child.
- 200% text scale (via `scaledApp`) produces no overflow or clipped primary
  content on the Home screen.

## 13. Preference-truthful copy and badge behavior summary

**Design-Spec cross-reference:** [`home-screen-design-spec.md`](home-screen-design-spec.md:131).

| `autoStartDetection` | Badge text | Dot/accent | Accessible status meaning | Supporting copy |
|---|---|---|---|---|
| `true` | `READY` | `kHomeAccentCyan` | `Auto-Start is on. Detection will begin when you open Detect.` | `Auto-Start is on. Detection will begin when you open Detect.` |
| `false` | `AUTO-START OFF` | `kHomeInkMuted` | `Auto-Start is off. Open Detect and press Start to begin.` | `Auto-Start is off. Open Detect and press Start to begin.` |

The `READY` badge is a presentation of the `autoStartDetection` preference only;
it is not evidence that the camera, model, engine, or detection runtime is ready
or running. No `PREPARING`, `RUNNING`, or app-launch auto-start claim is made.
The real `Preparing` variant is deferred (it requires lifting Detect-owned
runtime state through `AppShell`, which is outside this visual-only scope).

## 14. Acceptance criteria

**Design-Spec cross-reference:** [`home-screen-design-spec.md`](home-screen-design-spec.md:493).

### Visual and responsive acceptance

- Home renders the light `#F5F5F5`-role surface above the unchanged navigation
  bar.
- The badge, centered mark, live wordmark, lower instruction, cyan rail, and CTA
  follow the reference hierarchy from [`home_screen.png`](../design-reference/screens/home_screen.png).
- The composition uses token values and proportional/bounded relationships, not
  screenshot pixel positions.
- The logo mark is loaded from [`assets/logo.png`](../assets/logo.png), while
  `EyeCue` remains live IBM Plex Sans text.
- The global dark theme and the four-tab navigation remain visually and
  behaviorally unchanged.
- No RenderFlex overflow or clipped primary content at narrow, large, short, or
  200%-text-scale constraints.

### Behavior and copy acceptance

- Auto-Start on presents `READY` as a preference presentation and uses the exact
  truthful copy.
- Auto-Start off presents `AUTO-START OFF` and the exact manual-start copy.
- No Home copy claims that detection is already running, that app-launch
  auto-start has occurred, or that a runtime is Preparing.
- Changing `SettingsService.autoStartDetection` updates the Home presentation
  through the existing listener behavior.
- Tapping `Go to Live Camera` invokes `onGoToDetection`.
- No right-swipe handler or new runtime state source is introduced.

### Accessibility and automated-test acceptance

- The wordmark, status meaning, and CTA have non-duplicated semantics.
- The logo and rail are decorative/excluded.
- The CTA retains an actionable button role, enabled state, hint, and callback.
- The Home screen has no overflow or clipped primary content at 200% text scale.
- The existing Home group in [`widget_test.dart`](../test/widget_test.dart:12)
  covers branding, both preference presentations, listener updates, and CTA
  activation.
- [`semantics_test.dart`](../test/accessibility/semantics_test.dart:115) covers
  the status node, live wordmark, CTA, decorative exclusions, and 200% scale.

### Physical Android-device acceptance

The physical Android test device confirmed by the project owner is the
**SM-S9010** (Galaxy S22) with serial **R5CTA03XNZD**, `android-arm64`, running
**Android 15 (API 35)**. The implemented Home screen is verified on this
connected physical Android device, not an emulator or web target, per the
project verification policy. The device check confirms the retained four-tab
navigation, the light Home surface, the off-state badge visual tuning,
large-text behavior, TalkBack semantics, and the absence of RenderFlex overflows
or exceptions in logcat.

> **Note:** the earlier project docs referenced the Snapdragon 695 / Android 13 /
> API 33 device `2201116SG`; the device confirmed for this implementation is the
> SM-S9010 / Android 15 / API 35 device above. The check runs against whichever
> physical Android device is attached at implementation time.

### Verification commands

- `flutter analyze` reports 0 issues.
- `flutter test` passes (existing suite plus the extended Home tests).
- `flutter build apk --debug` succeeds (confirms the `google_fonts` dependency,
  the `assets/logo.png` registration, and the `assets/fonts/` folder resolve).

## 15. Explicitly deferred work

**Design-Spec cross-reference:** [`home-screen-design-spec.md`](home-screen-design-spec.md:560).

1. A real runtime-owned `Preparing` or `Ready` state.
2. App-launch camera or ML auto-start.
3. Home right-swipe-to-start behavior.
4. Replacing or removing the persistent four-tab navigation bar.
5. Moving engine, camera, inference, TTS, telemetry, correction, or persistence
   logic into Home.
6. Redesigning Detection, Settings, Help, Logs & Reports, or the shell.
7. Global migration from the dark theme to a light theme.
8. Portrait locking or new orientation configuration.
9. A new state-management, routing, gesture, or UI component package.

## Open Questions / Needs Verification

The product and architecture decisions required for this plan are resolved by
the Design-Spec/analysis. The implementation-time items previously listed here
were confirmed against the codebase and MCP and moved into their owning
sections:

- **IBM Plex Sans font filenames (400/500/600/700)** — resolved in §2: the
  canonical filenames are `IBMPlexSans-Regular.ttf` (400),
  `IBMPlexSans-Medium.ttf` (500), `IBMPlexSans-SemiBold.ttf` (600), and
  `IBMPlexSans-Bold.ttf` (700), confirmed against the `google_fonts` package
  weight-suffix mapping (pub.dev, version 8.2.1) and the google/fonts repo
  naming for the IBM Plex family.
- **Local Home theme file location** — resolved in §6: a new
  `lib/theme/app_home_theme.dart` (following the `app_*.dart` naming-convention
  rule), keeping the global `app_theme.dart` byte-stable.
- **`GoogleFonts.config.allowRuntimeFetching = false` placement** — resolved in
  §7.1: set at the top of the Home-local theme builder (before the `GoogleFonts`
  call), keeping `main.dart` untouched and avoiding a scope expansion.
- **Widget-test font resolution** — resolved in §11: with
  `allowRuntimeFetching = false` and the bundled assets declared in pubspec,
  `flutter test` resolves the fonts locally from the asset bundle; no network
  fetch or test-only override is required.

The physical Android device is now confirmed by the project owner as the
**SM-S9010** (Galaxy S22), serial **R5CTA03XNZD**, `android-arm64`, Android 15
(API 35) — recorded in §14. The following items remain implementation-time
steps that cannot be completed in the plan stage:

- **Off-state badge visual tuning.** The final dot size and pill width of the
  `AUTO-START OFF` badge are confirmed visually on the physical Android device
  (SM-S9010) during implementation, per the Design-Spec; they are not fixed in
  this plan.
- **IBM Plex Sans font file download.** The four canonical filenames are
  confirmed, but the binary `.ttf` files themselves must be downloaded from
  Google Fonts and placed under `assets/fonts/` during implementation. This plan
  does not commit binary font files.