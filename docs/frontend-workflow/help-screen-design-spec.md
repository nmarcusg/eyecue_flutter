# EyeCue — Help Screen Design Specification

> **Stage:** Design-Spec only. No application code, tests, assets, dependency
> declarations, or navigation behavior are changed by this document.
>
> **Task type:** Visual-only frontend redesign of the Help Screen.
>
> **Source of truth:** The approved [`help-screen-analysis.md`](help-screen-analysis.md:1),
> especially its **Resolved Open Questions / Decisions** section
> ([`help-screen-analysis.md`](help-screen-analysis.md:323)), is the source of
> truth for this specification. All open questions raised in the Analysis were
> resolved by the project owner and are treated as confirmed inputs here.

## 1. Scope, invariants, and implementation boundary

**Analysis cross-reference:** [`help-screen-analysis.md`](help-screen-analysis.md:15)
and [`help-screen-analysis.md`](help-screen-analysis.md:293).

This specification defines the visual hierarchy, local light styling, header/title
treatment, card composition, icon treatment, responsive relationships, and
accessibility expectations for [`HelpScreen`](../lib/screens/help_screen.dart:6).
It does not redesign the camera experience, other screens, the global theme, or
the app architecture.

The implementation must preserve these contracts:

| Contract | Required behavior |
|---|---|
| [`HelpScreen`](../lib/screens/help_screen.dart:6) | Remains a `StatelessWidget` with **no required service dependencies**, constructible as `const HelpScreen()` from [`app_shell.dart`](../lib/navigation/app_shell.dart:113) (`case 3: return const HelpScreen();`). |
| Shell construction | [`app_shell.dart`](../lib/navigation/app_shell.dart:113) remains the owner of the persistent four-tab [`NavigationBar`](../lib/navigation/app_shell.dart:138) and the [`IndexedStack`](../lib/navigation/app_shell.dart:134). Only the Help page construction is in scope; no navigation, tab, or shell change is allowed. |
| Content | The four section titles and their full body copy (the numbered steps, the four gesture bullets, the confirmation prose, and the four Android tips) are preserved **verbatim**. Only the visual presentation changes. |
| Runtime behavior | No camera start, ML initialization, engine coordination, TTS, telemetry, persistence, gesture state, or new runtime input is added to Help. |
| Global theme | The existing global dark [`buildEyeCueTheme()`](../lib/theme/app_theme.dart:13) and its use by [`EyeCueApp`](../lib/main.dart:61) remain unchanged. |
| Light-theme scope | The light surface is scoped to the Help subtree only (the Home `Theme` wrapper pattern). It must not leak into Detect, Settings, Home, Logs & Reports, or the shell navigation bar. |

The primary implementation file is [`help_screen.dart`](../lib/screens/help_screen.dart:6).
No change is expected to [`app_home_theme.dart`](../lib/theme/app_home_theme.dart:1),
[`app_colors.dart`](../lib/theme/app_colors.dart:1),
[`app_spacing.dart`](../lib/theme/app_spacing.dart:1),
[`app_radii.dart`](../lib/theme/app_radii.dart:1), or
[`app_typography.dart`](../lib/theme/app_typography.dart:1) — Help reuses the
existing `buildHomeTheme()` and `kHome*`/`kSpace*`/`kRadius*` tokens as-is
(see §6). The two existing test files are limited to the responsibilities defined
in this specification.

## 2. Reference composition and viewport treatment

**Analysis cross-reference:** [`help-screen-analysis.md`](help-screen-analysis.md:120)
and [`help-screen-analysis.md`](help-screen-analysis.md:143).

**No redesigned Help screenshot exists.** A recursive listing of
`design-reference/screens/` contains `detection_screen.png`, `home_screen.png`,
`home-preparing.png`, and `settings-screen.png` — there is **no** `help_screen.png`
or any Help redesign screenshot. The only Help image present is the **legacy**
`design-reference/old_screen/help_screen.jpg`, which is the pre-redesign dark Help
screen and is **not** a target composition.

**Implication:** The Help redesign is a **token-consistent restyle of the existing
content**, not a screenshot match. No target Help composition is fabricated. The
composition is derived from the established light visual language (Home) and the
token layer, not from a nonexistent Help reference. This is stated explicitly so
the implementation does not attempt to match a screenshot that does not exist.

The Help content area is composed above the existing shell navigation bar. The
Help widget must not add a replacement navigation control; the retained shell
[`NavigationBar`](../lib/navigation/app_shell.dart:138) remains the navigation
surface and reduces the available Help viewport.

The composition is a light Help canvas only. The light surface is scoped to the
Help subtree; it must not leak into other tabs or the shell navigation bar.

## 3. Layout hierarchy

**Analysis cross-reference:** [`help-screen-analysis.md`](help-screen-analysis.md:105)
and [`help-screen-analysis.md`](help-screen-analysis.md:242).

The redesigned Help layout follows the Home responsive pattern
([`SafeArea`](../lib/screens/home_screen.dart:25) +
[`LayoutBuilder`](../lib/screens/home_screen.dart:27) + bounded/centered width +
scrollable body). The proposed hierarchy is:

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

The four `_HelpCard` widgets remain private to [`help_screen.dart`](../lib/screens/help_screen.dart:60)
following the existing `_`-prefixed convention. No new public reusable widget is
justified by this redesign.

### 3.1 Theme wrapper placement

The light `Theme` wrapper must be scoped to the Help subtree only, mirroring the
Home `Theme` wrapper pattern. It must be placed **inside** the Help page so it does
not wrap the shell's [`NavigationBar`](../lib/navigation/app_shell.dart:138) or
leak into other tabs. The wrapper calls [`buildHomeTheme()`](../lib/theme/app_home_theme.dart:50)
as-is — no rename, no duplication, no new Help-scoped theme builder.

### 3.2 Status-bar treatment

Because the Help surface is light, the status bar must use **dark icons** via
`AnnotatedRegion<SystemUiOverlayStyle>` (the Home pattern) so the time/notifications
remain visible on the light surface. This is scoped to the Help subtree.

## 4. Header / title treatment

**Analysis cross-reference:** [`help-screen-analysis.md`](help-screen-analysis.md:331).

The Help header uses a **plain screen-title treatment** consistent with the light
visual language. It does **not** reuse the brand mark, [`assets/logo.png`](../assets/logo.png),
or the `EyeCue` wordmark. `logo.png` is therefore out of scope for Help.

The existing `AppBar(title: Text('Help & Gestures'))` is retained as the screen
title. Under the light theme the `AppBar` renders on the light surface with the
light ink text. The title must be a real semantic heading (the `AppBar` title
already provides this role), not merely a styled `Text`.

## 5. Card composition and icon treatment

**Analysis cross-reference:** [`help-screen-analysis.md`](help-screen-analysis.md:49),
[`help-screen-analysis.md`](help-screen-analysis.md:91), and
[`help-screen-analysis.md`](help-screen-analysis.md:342).

### 5.1 The four sections (content preserved verbatim)

| # | Section | Icon | Title | Body |
|---|---------|------|-------|------|
| 1 | How It Works | `Icons.timeline_rounded` | `How It Works` | 5-step numbered list + "runs entirely on your device — no internet needed" |
| 2 | Gesture Controls | `Icons.touch_app_rounded` | `Gesture Controls` | 4 bullet gesture descriptions |
| 3 | Gesture Confirmation | `Icons.vibration_rounded` | `Gesture Confirmation` | prose paragraph on audio + vibration feedback |
| 4 | Best Use Tip (Android) | `Icons.phone_android_rounded` | `Best Use Tip (Android)` | 4 bullet usage tips |

The four section titles and their full body copy are preserved **verbatim** — no
wording, ordering, or content change.

### 5.2 Card visual composition

Each section is presented as a light card on the light surface:

- **Card surface:** [`kHomeSurfaceCard`](../lib/theme/app_colors.dart:118) (`#FFFFFF`)
  on the [`kHomeSurfaceBase`](../lib/theme/app_colors.dart:115) (`#F5F5F5`) content
  background.
- **Corner radius:** [`kRadius24`](../lib/theme/app_radii.dart:34), matching the
  Home large light surface (the preference/status badge uses `kRadius24` in
  [`home_screen.dart`](../lib/screens/home_screen.dart:173)). No raw
  `BorderRadius.circular(...)` literal.
- **Card padding:** token-based inner padding (baseline `kSpace16`), not a raw
  `EdgeInsets.all(16)` literal.
- **Card separation:** a token-based bottom margin between cards (baseline
  `kSpace16`), not a raw `EdgeInsets.only(bottom: 16)` literal.
- **Shadow:** [`kHomeShadowSoft`](../lib/theme/app_home_theme.dart:18), the same
  soft shadow the Home light surface uses ([`home_screen.dart`](../lib/screens/home_screen.dart:174)),
  so cards lift off the `#F5F5F5` surface.

### 5.3 Card header row

Each card header is a `Row`:

- **Icon:** the retained section icon (see §5.1), rendered in the light accent
  color. The icon is **decorative** — it duplicates the adjacent title — and is
  excluded from the accessibility tree (`ExcludeSemantics`). Icon color uses the
  light accent token (e.g. [`kHomeAccentCyan`](../lib/theme/app_colors.dart:133)
  or the derived `colorScheme.primary` from `buildHomeTheme()`), not a raw
  `Color(...)` literal.
- **Icon size:** retain the current size 28 ([`help_screen.dart`](../lib/screens/help_screen.dart:83)).
  This is a token-consistent restyle, so the existing icon size is unchanged.
- **Gap:** a token-based gap between icon and title (baseline `kSpace12`), not a
  raw `SizedBox(width: 12)` literal.
- **Title:** the section title in the light `titleMedium` role (IBM Plex Sans via
  `buildHomeTheme()`), with the existing emphasis weight. The title is the semantic
  heading for the section group.

### 5.4 Card body

The body copy is rendered in the light `bodyLarge` role (IBM Plex Sans via
`buildHomeTheme()`), preserving the existing line-height treatment (`height: 1.4`)
so the multi-line numbered steps, bullets, and prose remain readable. The body
text uses the light ink color from the theme; no raw color literal.

## 6. Exact token usage

**Analysis cross-reference:** [`help-screen-analysis.md`](help-screen-analysis.md:258)
and [`help-screen-analysis.md`](help-screen-analysis.md:143).

Help reuses the existing Home light theme and tokens **as-is** — no rename, no
duplication, no new Help-scoped theme or token. The `kHome*`/`buildHomeTheme`
naming is retained even though Help now consumes it; this is an accepted naming
trade-off confirmed by the owner (Analysis §12, Option 1).

### 6.1 Theme

| Token / builder | File | Help use |
|---|---|---|
| [`buildHomeTheme()`](../lib/theme/app_home_theme.dart:50) | [`app_home_theme.dart`](../lib/theme/app_home_theme.dart:1) | The light `ThemeData` applied to the Help subtree (IBM Plex Sans typography, light surface, cyan accent). Reused as-is. |

### 6.2 Color tokens

| Token | Value | Help use |
|---|---|---|
| [`kHomeSurfaceBase`](../lib/theme/app_colors.dart:115) | `#F5F5F5` | Help content background |
| [`kHomeSurfaceCard`](../lib/theme/app_colors.dart:118) | `#FFFFFF` | Help card surface |
| [`kHomeInk`](../lib/theme/app_colors.dart:124) | `#0A0A0A` | Card titles and body text (via the theme text roles) |
| [`kHomeAccentCyan`](../lib/theme/app_colors.dart:133) | `#22C7F2` | Section icon accent (or the derived `colorScheme.primary` from `buildHomeTheme()`) |

No raw `Color(...)`, `Colors.*`, or alpha color literals are added to
[`help_screen.dart`](../lib/screens/help_screen.dart:6) for these roles. Colors
already derived from the active light `ThemeData`/`ColorScheme` (e.g.
`theme.colorScheme.surface`, `theme.colorScheme.primary`) are used via theme lookup
rather than duplicated as tokens.

### 6.3 Spacing tokens

| Token | Value | Help use |
|---|---|---|
| [`kSpace12`](../lib/theme/app_spacing.dart:28) | 12 | Icon-to-title gap in the card header |
| [`kSpace16`](../lib/theme/app_spacing.dart:34) | 16 | Card inner padding and card-to-card separation |
| [`kSpace24`](../lib/theme/app_spacing.dart:43) | 24 | Screen-level outer inset / large section gap |

Use the tokens as logical design values and scale layout relationships from
constraints where needed. Do not copy raw pixel literals into the screen.

### 6.4 Radius tokens

| Token | Value | Help use |
|---|---|---|
| [`kRadius24`](../lib/theme/app_radii.dart:34) | 24 | Card corner radius, matching the Home large light surface |

No raw `BorderRadius.circular(...)` literal.

### 6.5 Shadow tokens

| Token | File | Help use |
|---|---|---|
| [`kHomeShadowSoft`](../lib/theme/app_home_theme.dart:18) | [`app_home_theme.dart`](../lib/theme/app_home_theme.dart:1) | Soft card shadow so cards lift off the light surface (same as the Home light surface) |

## 7. Responsive sizing rules

**Analysis cross-reference:** [`help-screen-analysis.md`](help-screen-analysis.md:242)
and [`help-screen-analysis.md`](help-screen-analysis.md:314).

The reference canvas is **390 × 844** and is a proportional baseline, not a source
of Flutter pixel literals. Do not hardcode screenshot pixel dimensions.

### 7.1 Horizontal relationships

- Use the available content width from parent constraints; do not branch on device
  model or hardware type.
- Keep a leading/trailing content inset based on the approved spacing scale, with
  [`kSpace16`](../lib/theme/app_spacing.dart:34) as the baseline outer inset.
- Constrain the content to a **bounded/centered width** (Home caps at ~480) so the
  cards and text do not become unreadably wide on tablets or desktop-sized test
  constraints. The width is derived from constraints, not from a raster width.

### 7.2 Vertical relationships

- Place the screen title in the `AppBar` at the top of the Help viewport.
- Stack the four cards vertically in their existing order, each separated by a
  token-based gap.
- Preserve scrolling when the available height is short or text scaling causes the
  content to exceed the viewport. Scrolling must not hide any card or make content
  unreachable.

### 7.3 Narrow, large, and scaled constraints

- At narrow widths, allow the card titles and body copy to wrap; never clip text or
  force horizontal overflow.
- At large widths, retain a readable max content width and preserve the centered
  card treatment.
- At short heights, preserve the element order and allow vertical scrolling rather
  than shrinking text below its specified role size.
- At **200% text scale**, the cards, titles, and body copy must expand or wrap while
  the layout scrolls — no RenderFlex overflow.
- Do not add `OrientationBuilder`, orientation locks, new platform configuration, or
  portrait-only device behavior as part of this visual change.

## 8. Semantic labels and content structure

**Analysis cross-reference:** [`help-screen-analysis.md`](help-screen-analysis.md:218).

Help is primarily **static reading content** (no interactive controls today), so the
main accessibility work is **semantic structure and readability**, not button roles.

### 8.1 Semantic tree

Use this semantic order:

1. Screen title `Help & Gestures` (the `AppBar` title, a real semantic heading).
2. Section 1 — How It Works (title + body as one coherent group).
3. Section 2 — Gesture Controls (title + body as one coherent group).
4. Section 3 — Gesture Confirmation (title + body as one coherent group).
5. Section 4 — Best Use Tip (Android) (title + body as one coherent group).

### 8.2 Section grouping

Each section is exposed as a coherent semantic group (title + body). The section
icon is **decorative** (it duplicates the adjacent title) and is excluded from the
accessibility tree via `ExcludeSemantics`. The section title is the semantic
heading for the group.

### 8.3 No color- or motion-only meaning

Any accent/icon color is decorative; the text carries the meaning. No animated
state is introduced, so no motion-only meaning exists.

### 8.4 Live regions

Help is static reading content with no status/fallback/warning changes. No live
region is introduced. Help must never announce camera detections.

## 9. Large-text behavior

**Analysis cross-reference:** [`help-screen-analysis.md`](help-screen-analysis.md:218)
and [`help-screen-analysis.md`](help-screen-analysis.md:314).

- Test the Help screen with the existing 200% [`scaledApp`](../test/accessibility/semantics_test.dart:54)
  helper.
- Permit card titles and body copy to wrap and expand.
- Do not clip the screen title, any card title, or any body copy.
- The layout must scroll rather than overflow at 200% text scale (the Home
  `CustomScrollView`/`SliverFillRemaining` pattern is the reference).
- Help is currently non-interactive, so no touch-target change is required; if any
  interactive element is later added, it must preserve the existing
  [`kMinTouchWidth`](../lib/theme/app_spacing.dart:51) and
  [`kMinTouchHeight`](../lib/theme/app_spacing.dart:54) guidance.

## 10. Loading / unavailable / disabled presentation

**Analysis cross-reference:** [`help-screen-analysis.md`](help-screen-analysis.md:218).

Help is a **static, always-available** reading screen with no service dependency,
no loading state, no unavailable state, and no disabled control. The four sections
and their copy are always present and rendered synchronously. No loading spinner,
empty state, error state, or disabled presentation is applicable to this redesign.
If a future change introduces an interactive control, its enabled/disabled
presentation must follow the accessibility rule (label, role, state, hint, enabled
status), but that is out of scope here.

## 11. Verification and acceptance criteria

**Analysis cross-reference:** [`help-screen-analysis.md`](help-screen-analysis.md:293),
[`help-screen-analysis.md`](help-screen-analysis.md:314), and
[`help-screen-analysis.md`](help-screen-analysis.md:345).

The implementation is complete only when all of the following are true:

### Visual and responsive acceptance

- Help renders the light `#F5F5F5`-role surface above the unchanged navigation bar.
- The four cards follow the light visual language derived from Home (light card
  surfaces on the light background, token radii, soft shadows, IBM Plex Sans).
- The composition uses token values and proportional/bounded relationships, not
  screenshot pixel positions.
- The global dark theme and the four-tab navigation remain visually and
  behaviorally unchanged.
- The light surface is scoped to the Help subtree only and does not leak into the
  shell navigation bar or other tabs.

### Content and behavior acceptance

- The four section titles and their full body copy are preserved **verbatim**.
- The four section icons (`timeline`, `touch_app`, `vibration`, `phone_android`)
  are retained.
- The header uses a plain screen-title treatment; `logo.png` and the `EyeCue`
  wordmark are **not** used.
- `HelpScreen` remains a `StatelessWidget` constructible as `const HelpScreen()`
  with no required service dependencies.
- No runtime, navigation, gesture, or state change is introduced.

### Accessibility and automated-test acceptance

- The screen title and each section group have non-duplicated semantics.
- The section icons are decorative/excluded from the accessibility tree.
- The Help screen has no overflow or clipped primary content at 200% text scale.
- The existing Help group in [`widget_test.dart`](../test/widget_test.dart) covers
  the four sections and the screen title.
- [`semantics_test.dart`](../test/accessibility/semantics_test.dart) covers the
  Help section groups, decorative-icon exclusions, and 200% scale.

### Physical Android-device acceptance

A physical Android device is available and works on the owner's end (confirmed in
the Analysis). The implemented Help screen is verified on that connected physical
Android device, not an emulator or web target, per the project verification policy.
The device check confirms the retained four-tab navigation, the light Help surface,
the card radius/shadow visual tuning, large-text behavior, TalkBack semantics, and
the absence of RenderFlex overflows or exceptions in logcat. The specific connected
device may vary between sessions; the check runs against whichever physical Android
device is attached at implementation time.

## 12. Explicitly deferred work

**Analysis cross-reference:** [`help-screen-analysis.md`](help-screen-analysis.md:15)
and [`help-screen-analysis.md`](help-screen-analysis.md:293).

The following are not part of this Help redesign:

1. A redesigned Help screenshot match (no target screenshot exists).
2. Reusing the brand mark / `logo.png` / `EyeCue` wordmark in the Help header.
3. Renaming, duplicating, or generalizing the `kHome*` tokens or `buildHomeTheme()`
   into a shared light theme.
4. Adding a new Help-scoped theme or token.
5. Replacing or removing the persistent four-tab navigation bar.
6. Moving engine, camera, inference, TTS, telemetry, correction, gesture, or
   runtime-state logic into Help.
7. Redesigning Home, Detection, Settings, Logs & Reports, or the shell.
8. Global migration from the dark theme to a light theme.
9. Portrait locking or new orientation configuration.
10. A new state-management, routing, gesture, or UI component package.
11. Any change to `lib/models/`, `lib/services/`, or `lib/main.dart` beyond the two
    pre-approved exceptions.

## Open Questions / Needs Verification

**Analysis cross-reference:** [`help-screen-analysis.md`](help-screen-analysis.md:323).

The product and architecture decisions required for this Design-Spec are resolved,
and the previously listed implementation details have been confirmed and moved into
their owning sections:

- **Token-naming/sharing decision — resolved.** Reuse `kHome*`/`buildHomeTheme()`
  as-is (Analysis §12, Option 1); the Help theme must match the Home screen. No
  rename, no duplication, no new Help-scoped theme. Confirmed in §6.
- **Header/title treatment — resolved.** The Help header does not reuse the brand
  mark / `logo.png` / wordmark; it uses a plain screen-title treatment. Confirmed
  in §4.
- **No redesigned Help screenshot exists — confirmed.** The Help redesign is a
  token-consistent restyle of the existing content, not a screenshot match.
  Confirmed in §2.
- **Light-theme scope — resolved.** Help is a light subtree matching Home, reusing
  `buildHomeTheme()` scoped to the Help subtree only, with dark status-bar icons.
  Confirmed in §3.
- **Section icon treatment — resolved.** Keep the current four section icons
  (`timeline`, `touch_app`, `vibration`, `phone_android`). Confirmed in §5.
- **Physical-device verification — resolved.** A physical Android device is
  available and works on the owner's end. Confirmed in §11.

The three remaining implementation-time confirmations (card radius, card shadow,
icon size) were resolved against the codebase and the established Home light
visual language. They are no longer open:

- **Card corner radius — resolved: `kRadius24`.** The Home screen uses
  [`kRadius24`](../lib/theme/app_radii.dart:34) for its large light surface (the
  preference/status badge, [`home_screen.dart`](../lib/screens/home_screen.dart:173)),
  which is the established radius for a large light surface lifting off the
  `#F5F5F5` background. The Help cards are the same kind of large light content
  surface, so they use `kRadius24` for consistency with the Home large-surface
  treatment. `kRadius16` is documented as the "home status card" radius but is not
  the radius the current Home large surface actually uses; `kRadius24` is the
  codebase-confirmed choice. (§5.2, §6.4)
- **Card shadow — resolved: `kHomeShadowSoft`.** The Home screen applies
  [`kHomeShadowSoft`](../lib/theme/app_home_theme.dart:18) to its light surface
  ([`home_screen.dart`](../lib/screens/home_screen.dart:174)) so it lifts off the
  `#F5F5F5` background. The Help cards use the same soft shadow for a consistent
  light-surface treatment. (§5.2, §6.5)
- **Icon size — resolved: retain 28.** The current Help card renders its section
  icon at size 28 ([`help_screen.dart`](../lib/screens/help_screen.dart:83)). This
  is a token-consistent restyle, so the existing icon size is retained as-is; no
  icon-size change is required. (§5.3)
