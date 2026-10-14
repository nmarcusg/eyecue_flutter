# EyeCue — Help Screen Implementation Plan

> **Stage:** Plan only. No application code, tests, assets, dependency
> declarations, or navigation behavior are changed by this document.
>
> **Task type:** Visual-only frontend redesign of the Help Screen.
>
> **Source of truth (in order):** the approved
> [`help-screen-design-spec.md`](help-screen-design-spec.md) (Design-Spec) → the
> approved [`help-screen-analysis.md`](help-screen-analysis.md) (Analysis),
> especially its **Resolved Open Questions / Decisions** section
> ([`help-screen-analysis.md`](help-screen-analysis.md:323)). All open questions
> raised in the Analysis and Design-Spec were resolved by the project owner and
> are treated as confirmed inputs here.

## 1. Scope and invariants

**Design-Spec cross-reference:** [`help-screen-design-spec.md`](help-screen-design-spec.md:14)
and [`help-screen-design-spec.md`](help-screen-design-spec.md:424).

This plan turns the Design-Spec into concrete, implementable edits for a
visual-only Help redesign. Every file listed below traces back to the
Design-Spec/analysis; there are no speculative refactors.

The implementation must preserve these contracts (unchanged from the current
code):

| Contract | Current code | Preservation requirement |
|---|---|---|
| [`HelpScreen`](../lib/screens/help_screen.dart:6) | A `StatelessWidget` with **no required service dependencies**, constructible as `const HelpScreen()` from [`app_shell.dart`](../lib/navigation/app_shell.dart:113) (`case 3: return const HelpScreen();`) | Keep it a `StatelessWidget` constructible as `const HelpScreen()` with no required service dependencies. |
| Shell construction | [`app_shell.dart`](../lib/navigation/app_shell.dart:113) owns the persistent four-tab [`NavigationBar`](../lib/navigation/app_shell.dart:138) and the [`IndexedStack`](../lib/navigation/app_shell.dart:134) | No shell, tab, or navigation change. Only the Help page construction is in scope. |
| Content | The four section titles and their full body copy (the numbered steps, the four gesture bullets, the confirmation prose, and the four Android tips) | Preserved **verbatim** — no wording, ordering, or content change. |
| Section icons | `Icons.timeline_rounded`, `Icons.touch_app_rounded`, `Icons.vibration_rounded`, `Icons.phone_android_rounded` | Retained in the redesigned card headers. |
| Runtime behavior | No camera start, ML init, engine coordination, TTS, telemetry, persistence, gesture state, or new runtime input in Help | No runtime state source is added. |
| Global theme | [`buildEyeCueTheme()`](../lib/theme/app_theme.dart:13) dark theme used by [`EyeCueApp`](../lib/main.dart:61) | Unchanged; Help uses a locally scoped light context. |
| Light-theme scope | Home `Theme` wrapper pattern | The light surface is scoped to the Help subtree only; it must not leak into Detect, Settings, Home, Logs & Reports, or the shell navigation bar. |

### Files in scope

| File | Design-Spec responsibility | Scope rule |
|---|---|---|
| [`lib/screens/help_screen.dart`](../lib/screens/help_screen.dart:6) | Replace the dark plain-card hierarchy with the light, responsive, accessible composition; preserve the `const HelpScreen()` contract, the four sections and their copy verbatim, and the four section icons. | Primary UI file. |
| [`test/widget_test.dart`](../test/widget_test.dart:145) | Extend the existing `HelpScreen` group with the four sections and the screen title (already present) plus any light-theme/visual regression assertions required by the redesign. | No new test file. |
| [`test/accessibility/semantics_test.dart`](../test/accessibility/semantics_test.dart:341) | Add Help section-group, decorative-icon-exclusion, and 200% text-scale coverage using the existing helpers. | No new test file. |
| [`docs/architecture.md`](../docs/architecture.md:197) | Doc update: Help component row / theme section to note Help now consumes the light `buildHomeTheme()` subtree. | Root `/docs` authoritative. |
| [`docs/changelog.md`](../docs/changelog.md:8) | Doc update: add an Unreleased Help Screen Visual Redesign entry. | Root `/docs` authoritative. |
| [`docs/implementation-progress.md`](../docs/implementation-progress.md:6) | Doc update: add a Current Unreleased Candidate Help Screen Visual Redesign section. | Root `/docs` authoritative. |
| [`docs/session-log.md`](../docs/session-log.md:8) | Doc update: append a new session entry at the top. | Root `/docs` authoritative. |
| `.roo/rules/docs/` mirror | Re-copy the entire root `/docs` directory into `.roo/rules/docs/` in the same change (per the doc-update rule). | Plain mirror; never hand-edited independently. |

### Files that must remain untouched

[`app_home_theme.dart`](../lib/theme/app_home_theme.dart:1),
[`app_colors.dart`](../lib/theme/app_colors.dart:1),
[`app_spacing.dart`](../lib/theme/app_spacing.dart:1),
[`app_radii.dart`](../lib/theme/app_radii.dart:1),
[`app_typography.dart`](../lib/theme/app_typography.dart:1),
[`app_theme.dart`](../lib/theme/app_theme.dart:13),
[`app_shell.dart`](../lib/navigation/app_shell.dart:20),
[`main.dart`](../lib/main.dart:25), every model/service, every non-Help screen,
every widget in `lib/widgets/`, `assets/`, `pubspec.yaml`, and all
`design-reference/` files. No new state-management, routing, gesture, or
UI-component package is introduced.

## 2. Confirmed theme/token facts (no change needed)

**Design-Spec cross-reference:** [`help-screen-design-spec.md`](help-screen-design-spec.md:36)
and [`help-screen-design-spec.md`](help-screen-design-spec.md:192).

The following facts are confirmed before being included in this plan:

- **No theme/token file change is required.** Help reuses
  [`buildHomeTheme()`](../lib/theme/app_home_theme.dart:50) and the existing
  `kHome*`/`kSpace*`/`kRadius*` tokens as-is (owner decision, Analysis §12,
  Option 1). No rename, no duplication, no new Help-scoped theme or token.
- **`buildHomeTheme()`** ([`app_home_theme.dart`](../lib/theme/app_home_theme.dart:50))
  already supplies the light surface (`kHomeSurfaceBase`), IBM Plex Sans
  typography, the cyan accent `ColorScheme`, and disables runtime font fetching.
  It is applied to the Help subtree only.
- **`kHomeSurfaceCard`** ([`app_colors.dart`](../lib/theme/app_colors.dart:118),
  `#FFFFFF`) is the card surface; **`kHomeSurfaceBase`**
  ([`app_colors.dart`](../lib/theme/app_colors.dart:115), `#F5F5F5`) is the
  content background.
- **`kRadius24`** ([`app_radii.dart`](../lib/theme/app_radii.dart:34)) is the
  card corner radius (resolved in the Design-Spec §5.2/§6.4).
- **`kHomeShadowSoft`** ([`app_home_theme.dart`](../lib/theme/app_home_theme.dart:18))
  is the card shadow (resolved in the Design-Spec §5.2/§6.5).
- **`kSpace12`/`kSpace16`/`kSpace24`** ([`app_spacing.dart`](../lib/theme/app_spacing.dart:28/34/43))
  are the icon-to-title gap, card padding/separation, and screen-level inset
  respectively.
- **Icon size 28 is retained** (resolved in the Design-Spec §5.3/§6.4); no
  icon-size change is required.

## 3. Reference composition and viewport treatment

**Design-Spec cross-reference:** [`help-screen-design-spec.md`](help-screen-design-spec.md:46).

**No redesigned Help screenshot exists.** The Help redesign is a
**token-consistent restyle of the existing content**, not a screenshot match
(confirmed in the Analysis §6 and Design-Spec §2). The composition is derived
from the established light visual language (Home) and the token layer.

The Help content area is composed above the existing shell navigation bar. The
Help widget must not add a replacement navigation control; the retained shell
[`NavigationBar`](../lib/navigation/app_shell.dart:138) remains the navigation
surface and reduces the available Help viewport.

The composition is a light Help canvas only. The light surface is scoped to the
Help subtree; it must not leak into other tabs or the shell navigation bar.

## 4. Responsive layout plan

**Design-Spec cross-reference:** [`help-screen-design-spec.md`](help-screen-design-spec.md:72)
and [`help-screen-design-spec.md`](help-screen-design-spec.md:248).

The reference canvas is 390×844 and is a proportional baseline, not a source of
Flutter pixel literals. Follow the Home responsive pattern
([`SafeArea`](../lib/screens/home_screen.dart:25) +
[`LayoutBuilder`](../lib/screens/home_screen.dart:27) + bounded/centered width +
scrollable body).

### 4.1 Proposed hierarchy

```
HelpScreen (StatelessWidget, const HelpScreen())
└── Theme (data: buildHomeTheme())            // light subtree, scoped to Help only
    └── AnnotatedRegion<SystemUiOverlayStyle> // dark status-bar icons on light surface
        └── Scaffold
            ├── AppBar (title: 'Help & Gestures')   // plain screen-title treatment
            └── body: SafeArea
                └── LayoutBuilder
                    └── Center
                        └── ConstrainedBox (maxWidth ~480)   // bounded/centered width
                            └── ListView (or CustomScrollView)
                                ├── _HelpCard — How It Works
                                ├── _HelpCard — Gesture Controls
                                ├── _HelpCard — Gesture Confirmation
                                └── _HelpCard — Best Use Tip (Android)
```

The four `_HelpCard` widgets remain private to
[`help_screen.dart`](../lib/screens/help_screen.dart:60) following the existing
`_`-prefixed convention. No new public reusable widget is justified by this
redesign.

### 4.2 Theme wrapper placement

The light `Theme` wrapper must be scoped to the Help subtree only, mirroring the
Home `Theme` wrapper pattern. It must be placed **inside** the Help page so it
does not wrap the shell's [`NavigationBar`](../lib/navigation/app_shell.dart:138)
or leak into other tabs. The wrapper calls
[`buildHomeTheme()`](../lib/theme/app_home_theme.dart:50) as-is.

### 4.3 Status-bar treatment

Because the Help surface is light, the status bar must use **dark icons** via
`AnnotatedRegion<SystemUiOverlayStyle>` (the Home pattern) so the
time/notifications remain visible on the light surface. This is scoped to the
Help subtree.

### 4.4 Horizontal relationships

- Use the available content width from parent constraints; do not branch on
  device model or hardware type.
- Keep a leading/trailing content inset based on the approved spacing scale,
  with [`kSpace16`](../lib/theme/app_spacing.dart:34) as the baseline outer
  inset.
- Constrain the content to a **bounded/centered width** (Home caps at ~480) so
  the cards and text do not become unreadably wide on tablets or
  desktop-sized test constraints. The width is derived from constraints, not
  from a raster width.

### 4.5 Vertical relationships

- Place the screen title in the `AppBar` at the top of the Help viewport.
- Stack the four cards vertically in their existing order, each separated by a
  token-based gap.
- Preserve scrolling when the available height is short or text scaling causes
  the content to exceed the viewport. Scrolling must not hide any card or make
  content unreachable.

### 4.6 Narrow, large, and scaled constraints

- At narrow widths, allow the card titles and body copy to wrap; never clip text
  or force horizontal overflow.
- At large widths, retain a readable max content width and preserve the centered
  card treatment.
- At short heights, preserve the element order and allow vertical scrolling
  rather than shrinking text below its specified role size.
- At **200% text scale**, the cards, titles, and body copy must expand or wrap
  while the layout scrolls — no RenderFlex overflow.
- Do not add `OrientationBuilder`, orientation locks, new platform
  configuration, or portrait-only device behavior.

## 5. Header / title treatment

**Design-Spec cross-reference:** [`help-screen-design-spec.md`](help-screen-design-spec.md:117).

The Help header uses a **plain screen-title treatment** consistent with the
light visual language. It does **not** reuse the brand mark,
[`assets/logo.png`](../assets/logo.png), or the `EyeCue` wordmark. `logo.png` is
therefore out of scope for Help.

The existing `AppBar(title: Text('Help & Gestures'))` is retained as the screen
title. Under the light theme the `AppBar` renders on the light surface with the
light ink text. The title must be a real semantic heading (the `AppBar` title
already provides this role), not merely a styled `Text`.

## 6. Card composition and icon treatment

**Design-Spec cross-reference:** [`help-screen-design-spec.md`](help-screen-design-spec.md:130).

### 6.1 The four sections (content preserved verbatim)

| # | Section | Icon | Title | Body |
|---|---------|------|-------|------|
| 1 | How It Works | `Icons.timeline_rounded` | `How It Works` | 5-step numbered list + "runs entirely on your device — no internet needed" |
| 2 | Gesture Controls | `Icons.touch_app_rounded` | `Gesture Controls` | 4 bullet gesture descriptions |
| 3 | Gesture Confirmation | `Icons.vibration_rounded` | `Gesture Confirmation` | prose paragraph on audio + vibration feedback |
| 4 | Best Use Tip (Android) | `Icons.phone_android_rounded` | `Best Use Tip (Android)` | 4 bullet usage tips |

The four section titles and their full body copy are preserved **verbatim** — no
wording, ordering, or content change.

### 6.2 Card visual composition

Each section is presented as a light card on the light surface:

- **Card surface:** [`kHomeSurfaceCard`](../lib/theme/app_colors.dart:118)
  (`#FFFFFF`) on the [`kHomeSurfaceBase`](../lib/theme/app_colors.dart:115)
  (`#F5F5F5`) content background.
- **Corner radius:** [`kRadius24`](../lib/theme/app_radii.dart:34). No raw
  `BorderRadius.circular(...)` literal.
- **Card padding:** token-based inner padding (baseline
  [`kSpace16`](../lib/theme/app_spacing.dart:34)), not a raw
  `EdgeInsets.all(16)` literal.
- **Card separation:** a token-based bottom margin between cards (baseline
  [`kSpace16`](../lib/theme/app_spacing.dart:34)), not a raw
  `EdgeInsets.only(bottom: 16)` literal.
- **Shadow:** [`kHomeShadowSoft`](../lib/theme/app_home_theme.dart:18), the same
  soft shadow the Home light surface uses, so cards lift off the `#F5F5F5`
  surface.

### 6.3 Card header row

Each card header is a `Row`:

- **Icon:** the retained section icon (see §6.1), rendered in the light accent
  color. The icon is **decorative** — it duplicates the adjacent title — and is
  excluded from the accessibility tree (`ExcludeSemantics`). Icon color uses the
  light accent token (e.g. [`kHomeAccentCyan`](../lib/theme/app_colors.dart:133)
  or the derived `colorScheme.primary` from `buildHomeTheme()`), not a raw
  `Color(...)` literal.
- **Icon size:** retain the current size 28
  ([`help_screen.dart`](../lib/screens/help_screen.dart:83)). This is a
  token-consistent restyle, so the existing icon size is unchanged.
- **Gap:** a token-based gap between icon and title (baseline
  [`kSpace12`](../lib/theme/app_spacing.dart:28)), not a raw
  `SizedBox(width: 12)` literal.
- **Title:** the section title in the light `titleMedium` role (IBM Plex Sans
  via `buildHomeTheme()`), with the existing emphasis weight. The title is the
  semantic heading for the section group.

### 6.4 Card body

The body copy is rendered in the light `bodyLarge` role (IBM Plex Sans via
`buildHomeTheme()`), preserving the existing line-height treatment
(`height: 1.4`) so the multi-line numbered steps, bullets, and prose remain
readable. The body text uses the light ink color from the theme; no raw color
literal.

## 7. Semantic labels and content structure

**Design-Spec cross-reference:** [`help-screen-design-spec.md`](help-screen-design-spec.md:288).

Help is primarily **static reading content** (no interactive controls today), so
the main accessibility work is **semantic structure and readability**, not button
roles.

### 7.1 Semantic tree

Use this semantic order:

1. Screen title `Help & Gestures` (the `AppBar` title, a real semantic heading).
2. Section 1 — How It Works (title + body as one coherent group).
3. Section 2 — Gesture Controls (title + body as one coherent group).
4. Section 3 — Gesture Confirmation (title + body as one coherent group).
5. Section 4 — Best Use Tip (Android) (title + body as one coherent group).

### 7.2 Section grouping

Each section is exposed as a coherent semantic group (title + body). The section
icon is **decorative** (it duplicates the adjacent title) and is excluded from
the accessibility tree via `ExcludeSemantics`. The section title is the semantic
heading for the group.

### 7.3 No color- or motion-only meaning

Any accent/icon color is decorative; the text carries the meaning. No animated
state is introduced, so no motion-only meaning exists.

### 7.4 Live regions

Help is static reading content with no status/fallback/warning changes. No live
region is introduced. Help must never announce camera detections.

## 8. Concrete edits to [`lib/screens/help_screen.dart`](../lib/screens/help_screen.dart:6)

**Design-Spec cross-reference:** [`help-screen-design-spec.md`](help-screen-design-spec.md:72),
[`help-screen-design-spec.md`](help-screen-design-spec.md:117), and
[`help-screen-design-spec.md`](help-screen-design-spec.md:130).

The primary implementation file. The redesign replaces the dark plain-card
hierarchy with the light, responsive, accessible composition while preserving
the `const HelpScreen()` contract, the four sections and their copy verbatim,
and the four section icons.

### 8.1 Build-method structure

Replace the current `Scaffold → AppBar → ListView` body with a Help-local light
context wrapping the responsive/scroll-safe skeleton:

- Wrap the Help subtree in the light theme via
  [`buildHomeTheme()`](../lib/theme/app_home_theme.dart:50) so the light surface
  and ink apply only to Help.
- Wrap the subtree in `AnnotatedRegion<SystemUiOverlayStyle>` for dark
  status-bar icons on the light surface.
- Keep the `Scaffold` with the retained `AppBar(title: Text('Help & Gestures'))`.
- Compose the body as `SafeArea → LayoutBuilder → Center → ConstrainedBox
  (maxWidth ~480) → ListView` (or `CustomScrollView`) containing the four
  `_HelpCard` widgets in their existing order.
- Use token spacing and proportional/bounded relationships; do not encode
  screenshot pixel positions.

### 8.2 Private `_HelpCard` component

Keep the four `_HelpCard` widgets private to
[`help_screen.dart`](../lib/screens/help_screen.dart:60). Update the card
composition to the light visual language:

- Card surface from the light theme (`theme.colorScheme.surface` /
  `kHomeSurfaceCard`), corner radius [`kRadius24`](../lib/theme/app_radii.dart:34),
  and shadow [`kHomeShadowSoft`](../lib/theme/app_home_theme.dart:18).
- Token-based inner padding and card separation.
- Header `Row`: decorative icon (excluded from semantics) at size 28 in the
  light accent color, token gap, and the section title in the light `titleMedium`
  role with the existing emphasis weight.
- Body in the light `bodyLarge` role with `height: 1.4`.
- Wrap each section (title + body) as a coherent semantic group with the title
  as the group heading.

### 8.3 Private component boundary

Keep screen-only helpers private to
[`help_screen.dart`](../lib/screens/help_screen.dart:60), following the existing
`_HelpCard` convention. Do not create a public component solely for this
redesign.

## 9. Concrete edits to [`test/widget_test.dart`](../test/widget_test.dart:145)

**Design-Spec cross-reference:** [`help-screen-design-spec.md`](help-screen-design-spec.md:386).

Extend the existing `HelpScreen` group (no new test file). The current tests
assert the four section titles and the gesture copy; these remain valid because
the content is preserved verbatim. Add/update:

- The screen title `Help & Gestures` is present.
- The four section titles (`How It Works`, `Gesture Controls`, `Gesture
  Confirmation`, `Best Use Tip (Android)`) are present.
- The four section icons are present (the redesign retains them).
- The body copy (numbered steps, gesture bullets, confirmation prose, Android
  tips) is present verbatim.
- The light theme is applied to the Help subtree (e.g. the `Theme` wrapper
  resolves to `buildHomeTheme()`), confirming the light surface does not leak
  into the shell.

**Widget-test font resolution (resolved):** because
[`buildHomeTheme()`](../lib/theme/app_home_theme.dart:50) sets
`GoogleFonts.config.allowRuntimeFetching = false` and the bundled IBM Plex Sans
assets are declared in [`pubspec.yaml`](../pubspec.yaml:43) under
`assets/fonts/`, the Help widget tests resolve the fonts locally from the asset
bundle (flutter_test loads real project assets declared under `assets:`). No
network fetch is attempted and no test-only font override is required.

## 10. Concrete edits to [`test/accessibility/semantics_test.dart`](../test/accessibility/semantics_test.dart:341)

**Design-Spec cross-reference:** [`help-screen-design-spec.md`](help-screen-design-spec.md:388).

Add a Help semantics group (no new test file) reusing the existing helpers
[`scaledApp`](../test/accessibility/semantics_test.dart:56),
[`expectSemanticNode`](../test/accessibility/semantics_test.dart:99), and
[`withSemantics`](../test/accessibility/semantics_test.dart:105). Coverage:

- The screen title `Help & Gestures` is a real semantic heading.
- Each section group (title + body) is exposed as one coherent semantic node.
- The section icons are decorative/excluded from the accessibility tree (no
  duplicate label from icon + title).
- No duplicate semantics from a wrapper and the section content.
- 200% text scale (via `scaledApp`) produces no overflow or clipped primary
  content on the Help screen.

## 11. Concrete edits to the doc-sync files

**Doc-update rule cross-reference:** `.roo/rules/rules-frontend/06-doc-update.md`
and [`ui-conventions.md`](../docs/ui-conventions.md:1).

Any UI change that adds a screen, token, component, or convention must update
the corresponding documentation in **both** the root `/docs` and the
`.roo/rules/docs/` mirror. Root `/docs` is authoritative; `.roo/rules/docs/` is
a plain mirror re-copied in the same change.

### 11.1 [`docs/architecture.md`](../docs/architecture.md:197)

Update the Help Screen component row and the theme/design section to note that
Help now consumes the light [`buildHomeTheme()`](../lib/theme/app_home_theme.dart:50)
subtree (scoped to the Help subtree only), consistent with the Home light
surface. No token/theme file change is recorded because none is made.

### 11.2 [`docs/changelog.md`](../docs/changelog.md:8)

Add an **Unreleased — Help Screen Visual Redesign** entry at the top (above the
existing Home Screen Visual Redesign entry) listing Added/Changed/Verified for
the light Help subtree, the redesigned cards, the responsive layout, and the
accessibility coverage.

### 11.3 [`docs/implementation-progress.md`](../docs/implementation-progress.md:6)

Add a **Current Unreleased Candidate (2026-09-09) — Help Screen Visual Redesign**
section above the Home Screen Visual Redesign section, recording the completed
Help work and the current validation state.

### 11.4 [`docs/session-log.md`](../docs/session-log.md:8)

Append a new session entry at the top (above the 2026-09-09 Home Screen Visual
Redesign entry) recording the objective, completed work, decisions, and next
session for the Help redesign.

### 11.5 `.roo/rules/docs/` mirror

Re-copy the entire root `/docs` directory into `.roo/rules/docs/` in the same
change so the two never diverge. Do not hand-edit `.roo/rules/docs/` files
independently of root `/docs`.

## 12. Acceptance criteria

**Design-Spec cross-reference:** [`help-screen-design-spec.md`](help-screen-design-spec.md:350).

### Visual and responsive acceptance

- Help renders the light `#F5F5F5`-role surface above the unchanged navigation
  bar.
- The four cards follow the light visual language derived from Home (light card
  surfaces on the light background, `kRadius24` corners, `kHomeShadowSoft`
  shadows, IBM Plex Sans).
- The composition uses token values and proportional/bounded relationships, not
  screenshot pixel positions.
- The global dark theme and the four-tab navigation remain visually and
  behaviorally unchanged.
- The light surface is scoped to the Help subtree only and does not leak into
  the shell navigation bar or other tabs.

### Content and behavior acceptance

- The four section titles and their full body copy are preserved **verbatim**.
- The four section icons (`timeline`, `touch_app`, `vibration`,
  `phone_android`) are retained.
- The header uses a plain screen-title treatment; `logo.png` and the `EyeCue`
  wordmark are **not** used.
- `HelpScreen` remains a `StatelessWidget` constructible as `const HelpScreen()`
  with no required service dependencies.
- No runtime, navigation, gesture, or state change is introduced.

### Accessibility and automated-test acceptance

- The screen title and each section group have non-duplicated semantics.
- The section icons are decorative/excluded from the accessibility tree.
- The Help screen has no overflow or clipped primary content at 200% text scale.
- The existing Help group in [`widget_test.dart`](../test/widget_test.dart:145)
  covers the four sections and the screen title.
- [`semantics_test.dart`](../test/accessibility/semantics_test.dart:341) covers
  the Help section groups, decorative-icon exclusions, and 200% scale.

### Physical Android-device acceptance

A physical Android device is available and works on the owner's end (confirmed
in the Analysis). The implemented Help screen is verified on that connected
physical Android device, not an emulator or web target, per the project
verification policy. The device check confirms the retained four-tab navigation,
the light Help surface, the card radius/shadow visual tuning, large-text
behavior, TalkBack semantics, and the absence of RenderFlex overflows or
exceptions in logcat. The specific connected device may vary between sessions;
the check runs against whichever physical Android device is attached at
implementation time.

### Verification commands

- `flutter analyze` reports 0 issues.
- `flutter test` passes (existing suite plus the extended Help tests).
- `flutter build apk --debug` succeeds (confirms the light theme and token
  imports resolve; no new dependency or asset is added).

## 13. Explicitly deferred work

**Design-Spec cross-reference:** [`help-screen-design-spec.md`](help-screen-design-spec.md:402).

1. A redesigned Help screenshot match (no target screenshot exists).
2. Reusing the brand mark / `logo.png` / `EyeCue` wordmark in the Help header.
3. Renaming, duplicating, or generalizing the `kHome*` tokens or
   `buildHomeTheme()` into a shared light theme.
4. Adding a new Help-scoped theme or token.
5. Replacing or removing the persistent four-tab navigation bar.
6. Moving engine, camera, inference, TTS, telemetry, correction, gesture, or
   runtime-state logic into Help.
7. Redesigning Home, Detection, Settings, Logs & Reports, or the shell.
8. Global migration from the dark theme to a light theme.
9. Portrait locking or new orientation configuration.
10. A new state-management, routing, gesture, or UI component package.
11. Any change to `lib/models/`, `lib/services/`, or `lib/main.dart` beyond the
    two pre-approved exceptions.

## Open Questions / Needs Verification

The product and architecture decisions required for this plan are resolved by
the Design-Spec/analysis. The implementation-time items previously listed in the
Design-Spec were confirmed against the codebase and moved into their owning
sections:

- **Card corner radius — resolved: `kRadius24`** (Design-Spec §5.2/§6.4).
- **Card shadow — resolved: `kHomeShadowSoft`** (Design-Spec §5.2/§6.5).
- **Icon size — resolved: retain 28** (Design-Spec §5.3/§6.4).
- **Token-naming/sharing decision — resolved.** Reuse `kHome*`/`buildHomeTheme()`
  as-is (Analysis §12, Option 1); no rename, no duplication, no new Help-scoped
  theme.
- **Header/title treatment — resolved.** Plain screen-title treatment; no
  `logo.png`/wordmark.
- **No redesigned Help screenshot exists — confirmed.** Token-consistent restyle,
  not a screenshot match.
- **Light-theme scope — resolved.** Help is a light subtree matching Home,
  reusing `buildHomeTheme()` scoped to the Help subtree only, with dark
  status-bar icons.
- **Section icon treatment — resolved.** Keep the current four section icons.
- **Physical-device verification — resolved.** A physical Android device is
  available and works on the owner's end.

The following items remain implementation-time steps that cannot be completed in
the plan stage:

- **Card radius/shadow visual tuning.** The final `kRadius24` corner radius and
  `kHomeShadowSoft` shadow are confirmed visually on the physical Android device
  during implementation, per the Design-Spec; they are not re-fixed in this plan.
- **Exact `ListView` vs `CustomScrollView` choice.** The Design-Spec permits
  either a `ListView` or a `CustomScrollView` for the scrollable body. The
  implementation selects whichever satisfies the 200% text-scale no-overflow
  requirement with the least complexity; this is an implementation detail, not a
  design decision.
- **Doc-sync file set.** The exact wording and placement of the four root `/docs`
  edits (architecture, changelog, implementation-progress, session-log) and the
  `.roo/rules/docs/` re-copy are confirmed during implementation against the
  current doc state; the file set itself is fixed by the doc-update rule.
