# EyeCue — Home Screen Design Specification

> **Stage:** Design-Spec only. No application code, tests, assets, dependency
> declarations, or navigation behavior are changed by this document.
>
> **Task type:** Visual-only Home-screen redesign.
>
> **Source of truth:** The approved [`home-screen-analysis.md`](home-screen-analysis.md:1),
> especially its **Resolved Open Questions / Decisions** section, is the source
> of truth for this specification. The extracted token Markdown is authoritative
> over the token-summary PNG, as resolved in [`home-screen-analysis.md`](home-screen-analysis.md:571).

## 1. Scope, invariants, and implementation boundary

**Analysis cross-reference:** [`home-screen-analysis.md`](home-screen-analysis.md:20)
and [`home-screen-analysis.md`](home-screen-analysis.md:420).

This specification defines the visual hierarchy, local light styling, preference
copy, asset use, responsive relationships, and accessibility expectations for
[`HomeScreen`](../lib/screens/home_screen.dart:11). It does not redesign the
camera experience, other screens, global theme, or app architecture.

The implementation must preserve these contracts:

| Contract | Required behavior |
|---|---|
| [`HomeScreen.settings`](../lib/screens/home_screen.dart:12) | Remains the injected [`SettingsService`](../lib/services/settings_service.dart:60) input. Home continues to observe its [`ListenableBuilder`](../lib/screens/home_screen.dart:89) source so the preference presentation updates when `autoStartDetection` changes. |
| [`HomeScreen.onGoToDetection`](../lib/screens/home_screen.dart:13) | Remains the callback for the real Home action. The accessible CTA invokes it exactly once per activation. |
| [`AppShell`](../lib/navigation/app_shell.dart:20) | Remains the owner of the persistent four-tab [`NavigationBar`](../lib/navigation/app_shell.dart:138), the [`IndexedStack`](../lib/navigation/app_shell.dart:134), and Home-to-Detect routing. |
| Runtime behavior | No camera start, ML initialization, engine coordination, TTS, telemetry, persistence, or gesture state is added to Home. |
| Global theme | The existing global dark [`buildEyeCueTheme()`](../lib/theme/app_theme.dart:13) and its use by [`EyeCueApp`](../lib/main.dart:61) remain unchanged. |

The primary implementation file is [`home_screen.dart`](../lib/screens/home_screen.dart:21).
Changes to [`app_colors.dart`](../lib/theme/app_colors.dart:1),
[`app_radii.dart`](../lib/theme/app_radii.dart:1), the local Home theme styling,
[`pubspec.yaml`](../pubspec.yaml:9), and the two existing test files are limited
to the responsibilities defined in this specification.

## 2. Reference composition and viewport treatment

**Analysis cross-reference:** [`home-screen-analysis.md`](home-screen-analysis.md:238),
[`home-screen-analysis.md`](home-screen-analysis.md:254), and
[`home-screen-analysis.md`](home-screen-analysis.md:653).

The ready composition is based on [`home_screen.png`](../design-reference/screens/home_screen.png).
The preparing composition in [`home-preparing.png`](../design-reference/screens/home-preparing.png)
is a visual reference for a future runtime state, not an implementation state in
this feature.

The Home content area is composed above the existing shell navigation bar:

1. A preference/status badge aligned to the leading content edge.
2. A large centered mark using [`assets/logo.png`](../assets/logo.png).
3. A centered live-text `EyeCue` wordmark below the mark.
4. A lower instruction region containing a truthful headline, supporting copy,
   the retained accessible CTA, and the light cyan rail accent.

The screenshots' OS clock, battery, signal row, and other system artwork are not
part of the widget. The Home widget must not add an app bar or a replacement
navigation control. The retained shell [`NavigationBar`](../lib/navigation/app_shell.dart:138)
reduces the available Home viewport and must remain visible below the redesigned
content.

The composition is a light Home canvas only. The light surface is scoped to the
Home subtree; it must not leak into Detect, Settings, Help, Logs & Reports, or the
shell navigation bar.

## 3. Responsive layout specification

**Analysis cross-reference:** [`home-screen-analysis.md`](home-screen-analysis.md:361)
and [`home-screen-analysis.md`](home-screen-analysis.md:653).

The reference canvas is 390 × 844 and is a proportional baseline, not a source
of Flutter pixel literals. Use the existing [`SafeArea`](../lib/screens/home_screen.dart:25),
[`LayoutBuilder`](../lib/screens/home_screen.dart:27), and
[`SingleChildScrollView`](../lib/screens/home_screen.dart:29) pattern.

### 3.1 Horizontal relationships

**Analysis cross-reference:** [`home-screen-analysis.md`](home-screen-analysis.md:367).

- Use the available content width from parent constraints; do not branch on
  device model or hardware type.
- Keep a leading/trailing content inset based on the approved spacing scale,
  with [`kSpace16`](../lib/theme/app_spacing.dart:34) as the baseline outer inset.
- Keep the status badge intrinsically sized and leading-aligned; it must not
  stretch to the full viewport width.
- Constrain the brand group to a centered bounded width. The mark is a
  proportional visual element rather than a fixed-size 96 logical-pixel icon.
- Constrain the lower instruction region to a centered proportion of the
  viewport so its text and rail do not become unreadably wide on tablets or
  desktop-sized test constraints. Its width must be derived from constraints,
  not from the screenshot's raster width.
- The wordmark remains centered live text and may wrap only in an unusually
  narrow or heavily scaled constraint; it must not be converted to an image.

### 3.2 Vertical relationships

**Analysis cross-reference:** [`home-screen-analysis.md`](home-screen-analysis.md:381).

- Place the badge near the top of the SafeArea content with token-based inset.
- Give the brand group the dominant vertical share of the available content,
  with the mark above the wordmark and a deliberate token-based gap between
  them.
- Anchor the instruction region toward the lower part of the available Home
  viewport, while leaving enough space for the CTA and the retained navigation
  bar.
- Use proportional/flexible relationships for the large blank areas visible in
  the references. Do not encode the reference's absolute `y` coordinates.
- Preserve scrolling when the available height is short or text scaling causes
  the preferred composition to exceed the viewport. Scrolling must not hide the
  CTA or make the badge unreachable.

### 3.3 Narrow, large, and scaled constraints

**Analysis cross-reference:** [`home-screen-analysis.md`](home-screen-analysis.md:374)
and [`home-screen-analysis.md`](home-screen-analysis.md:348).

- At narrow widths, allow the preference copy and lower instruction copy to
  wrap; never clip text or force horizontal overflow.
- At large widths, retain a readable max content width for the lower region and
  preserve the centered brand treatment.
- At short heights, preserve the element order and allow vertical scrolling
  rather than shrinking text below its specified role size.
- At 200% text scale, the badge, copy, and CTA must expand or wrap while the
  logo remains decorative and bounded.
- Do not add [`OrientationBuilder`](../lib/screens/home_screen.dart:27),
  orientation locks, new platform configuration, or portrait-only device
  behavior as part of this visual change.

## 4. Preference-derived status and copy

**Analysis cross-reference:** [`home-screen-analysis.md`](home-screen-analysis.md:485),
[`home-screen-analysis.md`](home-screen-analysis.md:508), and
[`home-screen-analysis.md`](home-screen-analysis.md:523).

### 4.1 Ready badge meaning

The top badge presents only the existing [`autoStartDetection`](../lib/services/settings_service.dart:69)
preference. It is not evidence that the camera, model, engine, or detection
runtime is ready or running.

When `autoStartDetection` is `true`:

- Badge text: `READY`.
- Dot/accent: [`kHomeAccentCyan`](../lib/theme/app_colors.dart:1).
- Badge surface: [`kHomeSurfaceCard96`](../lib/theme/app_colors.dart:1).
- Accessible status meaning: `Auto-Start is on. Detection will begin when you open Detect.`

When `autoStartDetection` is `false`:

- Badge text: `AUTO-START OFF`.
- Dot/accent: [`kHomeInkMuted`](../lib/theme/app_colors.dart:1), not the
  preparing amber, because this is a preference state rather than preparation.
- Badge surface: [`kHomeSurfaceCard96`](../lib/theme/app_colors.dart:1).
- Accessible status meaning: `Auto-Start is off. Open Detect and press Start to begin.`

The off-state badge wording is a truthful Home-specific presentation of the
existing two-way setting. It must not use `PREPARING`, `RUNNING`, or another
runtime claim.

The supplied ready/preparing references do not show an Auto-Start-off badge, so
this off-state is a new composition. Its visual treatment follows the existing
codebase precedent for an inactive/off preference: the current [`_StatusCard`](../lib/screens/home_screen.dart:81)
off branch uses a muted foreground (`theme.colorScheme.onSurfaceVariant`) rather
than an accent color, and the app's muted status token
([`kStatusBlueGrey`](../lib/theme/app_colors.dart:45)) represents a stopped/inactive
state. The off-state badge therefore uses the muted [`kHomeInkMuted`](../lib/theme/app_colors.dart:1)
dot with `AUTO-START OFF` text on the [`kHomeSurfaceCard96`](../lib/theme/app_colors.dart:1)
surface. The badge is intrinsically sized and leading-aligned, uses the
authoritative 18/24 radii, and must wrap rather than clip at 200% text scale.
Its final dot size and pill width are confirmed visually on the physical Android
device during implementation (see §11).

### 4.2 Visible supporting copy

**Analysis cross-reference:** [`home-screen-analysis.md`](home-screen-analysis.md:533).

Use the following exact preference-truthful supporting copy below the lower
instruction headline:

| Preference | Supporting copy |
|---|---|
| On | `Auto-Start is on. Detection will begin when you open Detect.` |
| Off | `Auto-Start is off. Open Detect and press Start to begin.` |

The existing copy beginning `Detection is already running` must be removed. Do
not use `Detection begins immediately`, because that would imply the deferred
app-launch auto-start behavior.

### 4.3 Preparing reference

**Analysis cross-reference:** [`home-screen-analysis.md`](home-screen-analysis.md:508).

Do not add a real `Preparing` branch, timer, fake loading state, or new Home
runtime input. The amber dot and `Preparing` copy in
[`home-preparing.png`](../design-reference/screens/home-preparing.png) remain a
future composition reference only. Connecting that variant requires lifting
Detect-owned runtime state through [`AppShell`](../lib/navigation/app_shell.dart:20),
which is outside this visual-only scope.

## 5. CTA and deferred gesture treatment

**Analysis cross-reference:** [`home-screen-analysis.md`](home-screen-analysis.md:540)
and [`home-screen-analysis.md`](home-screen-analysis.md:330).

The real Home action remains [`AccessibleButton`](../lib/widgets/accessible_button.dart:8)
with:

- visible label: `Go to Live Camera`;
- existing camera icon treatment unless a Home-local visual wrapper is required;
- `prominent: true` or an equivalent Home-local presentation that preserves its
  callback and semantics;
- activation callback: [`onGoToDetection`](../lib/screens/home_screen.dart:13);
- minimum touch target preserved through the existing 64 × 56 logical-pixel
  contract in [`AccessibleButton`](../lib/widgets/accessible_button.dart:41).

The button may be placed inside the lower instruction region and visually styled
through a Home-local light theme. Do not modify the shared visual defaults of
[`AccessibleButton`](../lib/widgets/accessible_button.dart:8), because that
would affect Detection and other screens.

The reference's `Swipe right to start!` text and the corresponding swipe handler
are deferred. This redesign must not add a swipe recognizer, gesture-only start
path, misleading swipe instruction, or semantic swipe action. The CTA is the
fully supported non-gesture action.

The cyan rail from the reference may remain as a static decorative accent below
the instruction/copy area. It is not an interactive track, progress indicator,
or gesture affordance and must be excluded from semantics.

## 6. Local Home visual theme

**Analysis cross-reference:** [`home-screen-analysis.md`](home-screen-analysis.md:557)
and [`home-screen-analysis.md`](home-screen-analysis.md:171).

Home uses a locally scoped light visual theme/token context. The global dark
theme, [`ThemeMode.dark`](../lib/main.dart:77), and shell navigation colors are
unchanged. The local Home context supplies the light background, ink, cyan
accent, and Home typography to the Home subtree only.

### 6.1 Home color tokens

**Analysis cross-reference:** [`home-screen-analysis.md`](home-screen-analysis.md:588)
and [`extracted-design-tokens-screenshot.md`](../design-reference/tokens/extracted-design-tokens-screenshot.md:66).

Add the following semantic constants to [`app_colors.dart`](../lib/theme/app_colors.dart:1)
using the existing `k`-prefixed convention. These are the approved values from
the authoritative extracted Markdown source:

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

Do not replace existing global dark tokens or reinterpret [`kAccent`](../lib/theme/app_colors.dart:27)
for Home. Do not add raw `Color(...)`, `Colors.*`, or alpha color literals to
[`home_screen.dart`](../lib/screens/home_screen.dart:21) for these roles.

### 6.2 Spacing and radii

**Analysis cross-reference:** [`home-screen-analysis.md`](home-screen-analysis.md:199)
and [`home-screen-analysis.md`](home-screen-analysis.md:571).

The extracted Markdown wins over the PNG's coarser spacing summary. Home uses
the spacing scale `6, 8, 12, 16, 20, 24`, represented by the existing
[`app_spacing.dart`](../lib/theme/app_spacing.dart:1) tokens:

- `kSpace6`: rail thickness or compact separation;
- `kSpace8`: closely related text separation;
- `kSpace12`: badge internals and mark/wordmark relationships;
- `kSpace16`: primary content inset and CTA separation;
- `kSpace20`: major local block separation;
- `kSpace24`: brand and lower-region breathing room.

Use the tokens as logical design values and scale layout relationships from
constraints where needed. Do not copy `32`, `48`, or `64` from the token PNG as
new Home spacing values when the extracted Markdown does not include them.

The Home implementation must use the authoritative radii `3, 12, 14, 18, 24`:

| Radius | Home use |
|---:|---|
| 3 | Cyan rail |
| 12 | Compact tags or inner treatments if used |
| 14 | Home-local CTA/toggle-like rounded treatment if a wrapper is needed |
| 18 | Compact status treatment if required by the final composition |
| 24 | Large status badge and large Home surfaces |

[`app_radii.dart`](../lib/theme/app_radii.dart:1) currently lacks the missing
reference values `3`, `14`, `18`, and `24`; add them as named `kRadius*` tokens
in the implementation stage rather than hardcoding them in the screen. Reuse
existing matching tokens where available.

### 6.3 Shadows as a theme component

**Analysis cross-reference:** [`home-screen-analysis.md`](home-screen-analysis.md:588)
and [`extracted-design-tokens-screenshot.md`](../design-reference/tokens/extracted-design-tokens-screenshot.md:86).

Shadows are not entries in [`app_colors.dart`](../lib/theme/app_colors.dart:1).
Define them in a Home-local theme/decoration component consumed only by Home:

| Name | Definition | Intended use |
|---|---|---|
| `shadow-soft` | `0px 6px 18px rgba(10,10,10,0.08)` | Preference/status badge |
| `shadow-elevated` | `0px 10px 28px rgba(10,10,10,0.07)` | A large Home surface only if the implementation retains one |
| `shadow-knob` | `0px 2px 5px rgba(0,0,0,0.12)` | Not used by the current Home composition; reserved for a future control |

The component may be represented by Home-local theme data in the existing
[`app_theme.dart`](../lib/theme/app_theme.dart:13) or another `app_*.dart` theme
file, but it must not mutate [`buildEyeCueTheme()`](../lib/theme/app_theme.dart:13)
or the global navigation theme.

## 7. Typography and offline font packaging

**Analysis cross-reference:** [`home-screen-analysis.md`](home-screen-analysis.md:605)
and [`home-screen-analysis.md`](home-screen-analysis.md:718).

Add [`google_fonts`](https://pub.dev/packages/google_fonts) at version `^8.2.1`
to [`pubspec.yaml`](../pubspec.yaml:9). Apply IBM Plex Sans only in the local
Home typography context through
[`GoogleFonts.plexSansTextTheme(...)`](home-screen-analysis.md:618). Do not
replace the global high-contrast [`highContrastTextTheme()`](../lib/theme/app_typography.dart:13)
used by the dark application theme.

The offline mode is mandatory and is confirmed against the
[`google_fonts`](https://pub.dev/packages/google_fonts) package guidance
(Context7, version 8.2.1):

- bundle the font files as application assets under a dedicated folder (for
  example `assets/fonts/`) and declare that folder under `assets:` in
  [`pubspec.yaml`](../pubspec.yaml:43);
- keep the original Google Fonts filenames so the package can resolve them
  locally — no `fonts:` section is required;
- disable runtime HTTP fetching by setting
  `GoogleFonts.config.allowRuntimeFetching = false` once during app
  initialization, so the package never falls back to a network request;
- keep the wordmark as live text so TalkBack and large-text scaling continue to
  work.

The bundled filenames follow the package's weight-suffix convention confirmed
by Context7: `Regular` (400), `Medium` (500), `SemiBold` (600), and `Bold`
(700). The exact per-file names are the ones produced by the Google Fonts
download for IBM Plex Sans at those weights; the implementation must place them
in the declared asset folder unchanged and verify the package resolves them
locally before relying on the offline path.

### 7.1 Material role mapping

**Analysis cross-reference:** [`home-screen-analysis.md`](home-screen-analysis.md:627)
and [`extracted-design-tokens-screenshot.md`](../design-reference/tokens/extracted-design-tokens-screenshot.md:91).

The local Home text theme maps the extracted IBM Plex Sans roles as follows:

| Material role | Size | Weight | Home application |
|---|---:|---:|---|
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

- Regular — 400;
- Medium — 500;
- SemiBold — 600; and
- Bold — 700.

No other font weights are required by this Home specification.

Line height and letter spacing are not specified in the extracted source. The
codebase precedent confirms the global theme relies on Flutter defaults: the
existing [`highContrastTextTheme()`](../lib/theme/app_typography.dart:13) sets
no `height` or `letterSpacing` on any role, and the only explicit values in the
codebase are localized widget overrides (for example
[`bounding_box_painter.dart`](../lib/widgets/bounding_box_painter.dart:54)
`height: 1.2`, [`priority_badge.dart`](../lib/widgets/priority_badge.dart:41)
`letterSpacing: 0.5`, and [`help_screen.dart`](../lib/screens/help_screen.dart:96)
`height: 1.4`). The local Home IBM Plex Sans theme therefore uses the resolved
Flutter/Google Fonts role defaults for line height and letter spacing, matching
the global theme's convention, rather than inventing new values.

## 8. Logo asset and wordmark

**Analysis cross-reference:** [`home-screen-analysis.md`](home-screen-analysis.md:308)
and [`home-screen-analysis.md`](home-screen-analysis.md:640).

Use the existing mark-only [`assets/logo.png`](../assets/logo.png). The image is
not edited, recolored, cropped to include text, or replaced by an icon. Add its
asset registration to [`pubspec.yaml`](../pubspec.yaml:43) during implementation
so the existing file can be loaded.

The `EyeCue` wordmark is separate live text using the local
`displayLarge` IBM Plex Sans mapping. Do not bake the wordmark into the image.

The logo image is decorative when the adjacent live wordmark is present:

- exclude the image from the semantics tree;
- do not give it a duplicate `EyeCue` label;
- preserve its visual role at constrained sizes by bounding it proportionally;
- revisit this only if a future responsive layout removes the live wordmark.

## 9. Accessibility and semantics specification

**Analysis cross-reference:** [`home-screen-analysis.md`](home-screen-analysis.md:330)
and [`home-screen-analysis.md`](home-screen-analysis.md:356).

The redesign must remain usable through TalkBack without relying on color, logo
shape, or an unimplemented gesture.

### 9.1 Semantic tree

**Analysis cross-reference:** [`home-screen-analysis.md`](home-screen-analysis.md:341).

Use this semantic order:

1. Preference/status badge with the complete preference-truthful meaning.
2. Live `EyeCue` wordmark.
3. Lower instruction headline and supporting copy.
4. Actionable `Go to Live Camera` button.

The status badge is a non-interactive semantic container. Its textual label must
distinguish Auto-Start on from Auto-Start off; cyan versus muted color is only a
visual reinforcement. The logo image and cyan rail are excluded as decorative
descendants. Do not create duplicate semantics from a wrapper and the
[`AccessibleButton`](../lib/widgets/accessible_button.dart:27) child.

The badge may be treated as a deliberate preference-status update when the
settings value changes, but it must never become a per-frame or runtime-ready
live region. It must not announce camera detections.

### 9.2 CTA semantics

**Analysis cross-reference:** [`home-screen-analysis.md`](home-screen-analysis.md:334).

Preserve the existing button role, enabled state, tap action, and activation hint
provided by [`AccessibleButton`](../lib/widgets/accessible_button.dart:27). The
CTA must remain a real focusable control at 200% text scale and must continue to
invoke [`onGoToDetection`](../lib/screens/home_screen.dart:13) without a gesture.

### 9.3 Large text and touch targets

**Analysis cross-reference:** [`home-screen-analysis.md`](home-screen-analysis.md:348)
and [`home-screen-analysis.md`](home-screen-analysis.md:352).

- Test the Home screen with the existing 200% [`scaledApp`](../test/accessibility/semantics_test.dart:54)
  helper.
- Permit status and supporting copy to wrap and expand.
- Do not clip the badge text, wordmark, headline, or CTA label.
- Preserve the existing [`kMinTouchWidth`](../lib/theme/app_spacing.dart:51)
  and [`kMinTouchHeight`](../lib/theme/app_spacing.dart:54) guidance.
- Do not make the deferred right-swipe the only way to start detection.

## 10. Component and file plan

**Analysis cross-reference:** [`home-screen-analysis.md`](home-screen-analysis.md:276)
and [`home-screen-analysis.md`](home-screen-analysis.md:389).

The design does not justify a new public reusable widget. Keep screen-only
helpers private to [`home_screen.dart`](../lib/screens/home_screen.dart:81),
following the existing `_StatusCard` convention. A private status badge and a
private instruction region are acceptable if they reduce build-method complexity;
do not create a public component solely for this redesign.

| File | Design-Spec responsibility | Scope rule |
|---|---|---|
| [`lib/screens/home_screen.dart`](../lib/screens/home_screen.dart:21) | Replace the dark centered-column hierarchy with the responsive reference composition; preserve settings listening and CTA callback. | Primary UI file. |
| [`lib/theme/app_colors.dart`](../lib/theme/app_colors.dart:1) | Add the approved `kHome*` light semantic colors. | UI token layer only. |
| [`lib/theme/app_radii.dart`](../lib/theme/app_radii.dart:1) | Add missing authoritative `kRadius3`, `kRadius14`, `kRadius18`, and `kRadius24` values; reuse existing values where possible. | UI token layer only. |
| [`lib/theme/app_theme.dart`](../lib/theme/app_theme.dart:13) or another `app_*.dart` theme file | Provide Home-local typography/decoration theme data without changing the global dark theme. | Local Home theme only. |
| [`pubspec.yaml`](../pubspec.yaml:9) | Add `google_fonts: ^8.2.1`, register `assets/logo.png`, and register the selected offline IBM Plex Sans font asset folder. | Minimal packaging prerequisite; no unrelated dependency or asset changes. |
| [`test/widget_test.dart`](../test/widget_test.dart:12) | Extend the existing `HomeScreen` group with visual/state/callback regressions. | No new test file. |
| [`test/accessibility/semantics_test.dart`](../test/accessibility/semantics_test.dart:115) | Add Home status, wordmark, CTA, decorative-image, and 200% text-scale semantics coverage using existing helpers. | No new test file. |

Do not modify [`AppShell`](../lib/navigation/app_shell.dart:20),
[`main.dart`](../lib/main.dart:25), [`SettingsService`](../lib/services/settings_service.dart:60),
any model/service, or any non-Home screen for this feature.

## 11. Verification and acceptance criteria

**Analysis cross-reference:** [`home-screen-analysis.md`](home-screen-analysis.md:389),
[`home-screen-analysis.md`](home-screen-analysis.md:420), and
[`home-screen-analysis.md`](home-screen-analysis.md:687).

The implementation is complete only when all of the following are true:

### Visual and responsive acceptance

**Analysis cross-reference:** [`home-screen-analysis.md`](home-screen-analysis.md:361).

- Home renders the light `#F5F5F5`-role surface above the unchanged navigation
  bar.
- The badge, centered mark, live wordmark, lower instruction, cyan rail, and
  CTA follow the reference hierarchy from [`home_screen.png`](../design-reference/screens/home_screen.png).
- The composition uses token values and proportional/bounded relationships,
  not screenshot pixel positions.
- The logo mark is loaded from [`assets/logo.png`](../assets/logo.png), while
  `EyeCue` remains live IBM Plex Sans text.
- The global dark theme and the four-tab navigation remain visually and
  behaviorally unchanged.

### Behavior and copy acceptance

**Analysis cross-reference:** [`home-screen-analysis.md`](home-screen-analysis.md:485).

- Auto-Start on presents `READY` as a preference presentation and uses the
  exact truthful copy specified above.
- Auto-Start off presents `AUTO-START OFF` and the exact manual-start copy.
- No Home copy claims that detection is already running, that app-launch
  auto-start has occurred, or that a runtime is Preparing.
- Changing [`SettingsService.autoStartDetection`](../lib/services/settings_service.dart:69)
  updates the Home presentation through the existing listener behavior.
- Tapping `Go to Live Camera` invokes [`onGoToDetection`](../lib/screens/home_screen.dart:13).
- No right-swipe handler or new runtime state source is introduced.

### Accessibility and automated-test acceptance

**Analysis cross-reference:** [`home-screen-analysis.md`](home-screen-analysis.md:330)
and [`home-screen-analysis.md`](home-screen-analysis.md:669).

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

**Analysis cross-reference:** [`home-screen-analysis.md`](home-screen-analysis.md:330)
and [`ui-conventions.md`](ui-conventions.md:95).

A physical Android device is available and connects to the development host
over USB/wire (confirmed by the project owner). The implemented Home screen is
verified on that connected physical Android device, not an emulator or web
target, per the project verification policy. The device check confirms the
retained four-tab navigation, the light Home surface, the off-state badge
visual tuning, large-text behavior, TalkBack semantics, and the absence of
RenderFlex overflows or exceptions in logcat. The specific connected device may
vary between sessions; the check runs against whichever physical Android device
is attached at implementation time.

## 12. Explicitly deferred work

**Analysis cross-reference:** [`home-screen-analysis.md`](home-screen-analysis.md:460)
and [`home-screen-analysis.md`](home-screen-analysis.md:697).

The following are not part of this Home redesign:

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

**Analysis cross-reference:** [`home-screen-analysis.md`](home-screen-analysis.md:477)
and [`home-screen-analysis.md`](home-screen-analysis.md:726).

The product and architecture decisions required for this Design-Spec are
resolved, and the previously listed implementation details have been confirmed
and moved into their owning sections:

- **IBM Plex Sans offline packaging and no-network configuration** — resolved
  in §7 against the [`google_fonts`](https://pub.dev/packages/google_fonts)
  package guidance (Context7, version 8.2.1): bundle the four weights under an
  asset folder declared in [`pubspec.yaml`](../pubspec.yaml:43), keep the
  original Google Fonts filenames, and set
  `GoogleFonts.config.allowRuntimeFetching = false` to disable HTTP fetching.
- **Subpixel typography tuning** — resolved in §7.1 against the codebase
  precedent: the global [`highContrastTextTheme()`](../lib/theme/app_typography.dart:13)
  sets no line height or letter spacing, so the local Home IBM Plex Sans theme
  uses Flutter/Google Fonts role defaults.
- **Off-state badge visual tuning** — resolved in §4.1 against the codebase
  precedent for an inactive/off preference (muted foreground, muted status
  token) and confirmed for visual tuning on the physical device.
- **Physical Android verification** — resolved in §11: a physical Android
  device connects to the development host over USB/wire (confirmed by the
  project owner) and is used for the device check.

The only remaining implementation-time confirmation is the literal set of
downloaded IBM Plex Sans font filenames for weights 400, 500, 600, and 700.
These are produced by the Google Fonts download and must be placed in the
declared asset folder unchanged so [`google_fonts`](https://pub.dev/packages/google_fonts)
can resolve them locally; the exact names are confirmed when the files are
downloaded during implementation, not from this Design-Spec.
