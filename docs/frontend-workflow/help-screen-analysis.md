# EyeCue — Help Screen Visual Redesign: Analysis

> **Stage:** Analysis (read-only). No application code, tests, assets,
> `pubspec.yaml`, or other project files were modified to produce this document.
> **Date:** 2026-09-09
> **Task type:** Visual-only frontend redesign.
> **Scope:** Redesign the Help Screen's visual presentation while preserving its
> existing content and behavior. This is a token-consistent restyle of the
> existing content, not a screenshot match (see §6).
> **Source-of-truth order:** this prompt → (later) `help-screen-plan.md` →
> `help-screen-design-spec.md` → this analysis → general `.roo/rules/`.

---

## 1. Task type

**Visual-only frontend redesign.** The goal is to restyle the Help Screen's
visual presentation using the established light visual language and token layer,
while preserving all existing content and runtime behavior.

This task is **not** combined with: navigation architecture changes; gesture
changes; app-launch camera/ML initialization; runtime-state ownership; engine
fallback; TTS; telemetry/accuracy; model/service refactoring; portrait-lock
configuration; or new state-management/DI frameworks. No new repository,
ViewModel, use-case, state-management package, or architecture migration is
introduced. The existing project structure, constructor-injection patterns, and
the light-theme pattern established by the completed Home feature are reused.

---

## 2. Current Help behavior and structure

### 2.1 Behavior contract (must be preserved)

[`HelpScreen`](../lib/screens/help_screen.dart) is a **`StatelessWidget`** with
**no required service dependencies** and is constructible as
`const HelpScreen()` from [`app_shell.dart`](../lib/navigation/app_shell.dart:113)
(`case 3: return const HelpScreen();`). It renders inside the shell's
`IndexedStack` as the fourth bottom-nav tab (Help), so it inherits the shell's
`Scaffold`/`NavigationBar` and the global dark `ThemeData`. It has no
`SafeArea`, no `LayoutBuilder`, and no `Theme` wrapper of its own today.

### 2.2 Current structure

The current build is a `Scaffold` with an `AppBar(title: Text('Help &
Gestures'))` and a `ListView(padding: EdgeInsets.all(16))` containing four
private `_HelpCard` widgets in a `const` list:

| # | Section | Icon | Title | Body |
|---|---------|------|-------|------|
| 1 | How It Works | `Icons.timeline_rounded` | `How It Works` | 5-step numbered list + "runs entirely on your device — no internet needed" |
| 2 | Gesture Controls | `Icons.touch_app_rounded` | `Gesture Controls` | 4 bullet gesture descriptions |
| 3 | Gesture Confirmation | `Icons.vibration_rounded` | `Gesture Confirmation` | prose paragraph on audio + vibration feedback |
| 4 | Best Use Tip (Android) | `Icons.phone_android_rounded` | `Best Use Tip (Android)` | 4 bullet usage tips |

Each `_HelpCard` is a `Card` with `margin: EdgeInsets.only(bottom: 16)` and a
`Padding(EdgeInsets.all(16))` containing a `Column`: a header `Row` (icon at
`theme.colorScheme.primary`, size 28, + `SizedBox(width: 12)` + `Expanded`
title in `titleMedium` w800), then `SizedBox(height: 10)`, then the body in
`bodyLarge` with `height: 1.4`.

### 2.3 Content to preserve verbatim

The four section titles and their full body copy (including the numbered steps,
the four gesture bullets, the confirmation prose, and the four Android tips)
must remain unchanged. Only the visual presentation of that content changes.

---

## 3. Direct dependencies only

The Help Screen's direct dependencies are limited to Flutter Material and the
shell that constructs it. No service, model, or engine is consumed by
[`help_screen.dart`](../lib/screens/help_screen.dart).

| Dependency | File | Role for Help |
|---|---|---|
| Material | `package:flutter/material.dart` | `Scaffold`, `AppBar`, `ListView`, `Card`, `Icon`, `Text`, `Theme` |
| Shell construction | [`app_shell.dart`](../lib/navigation/app_shell.dart:113) | `const HelpScreen()` as tab index 3; only the Help page construction is in scope |
| Theme (global) | [`app_theme.dart`](../lib/theme/app_theme.dart) | Dark `buildEyeCueTheme()` currently inherited by Help |
| Light-theme pattern | [`app_home_theme.dart`](../lib/theme/app_home_theme.dart) | `buildHomeTheme()` — the established light `ThemeData` + IBM Plex Sans + shadow tokens to reuse/mirror |
| Tokens | [`app_colors.dart`](../lib/theme/app_colors.dart), [`app_spacing.dart`](../lib/theme/app_spacing.dart), [`app_radii.dart`](../lib/theme/app_radii.dart), [`app_typography.dart`](../lib/theme/app_typography.dart) | Semantic color/spacing/radius/type tokens |
| Reference implementation | [`home_screen.dart`](../lib/screens/home_screen.dart) | Light-theme, responsive, accessibility pattern to follow |
| Fonts/assets | [`pubspec.yaml`](../pubspec.yaml) | `google_fonts` + bundled `assets/fonts/` (IBM Plex Sans), `assets/logo.png` |

No unrelated routes or services were inspected. No repository-wide audit was
performed.

---

## 4. The four existing content sections

Confirmed present in [`help_screen.dart`](../lib/screens/help_screen.dart:16-53):

1. **How It Works** — `Icons.timeline_rounded`.
2. **Gesture Controls** — `Icons.touch_app_rounded`.
3. **Gesture Confirmation** — `Icons.vibration_rounded`.
4. **Best Use Tip (Android)** — `Icons.phone_android_rounded`.

These four sections and their copy are the content that the redesign must
preserve.

---

## 5. Current layout structure

- **Root:** `Scaffold` with an `AppBar` titled `Help & Gestures`.
- **Body:** a single `ListView` with `EdgeInsets.all(16)` padding.
- **Children:** four `_HelpCard` widgets in a `const` list, each separated by a
  16px bottom margin.
- **Card internals:** `Card` → `Padding(16)` → `Column` → header `Row`
  (icon + title) + body `Text`.
- **No** `SafeArea`, `LayoutBuilder`, `ConstrainedBox`, `CustomScrollView`,
  `SliverFillRemaining`, `Theme` wrapper, or `AnnotatedRegion` is currently
  used. The screen relies on the shell's `Scaffold` and the inherited global
  dark theme.

---

## 6. Does a redesigned Help screenshot exist?

**No.** A recursive listing of `design-reference/` shows the following screens
under `design-reference/screens/`:

- `detection_screen.png`
- `home_screen.png`
- `home-preparing.png`
- `settings-screen.png`

There is **no** `help_screen.png` (or any Help redesign screenshot) under
`design-reference/screens/`. The only Help image present is the **legacy**
`design-reference/old_screen/help_screen.jpg`, which is the pre-redesign dark
Help screen and is not a target composition.

**Implication:** The Help redesign is a **token-consistent restyle of the
existing content**, not a screenshot match. No target Help composition is
fabricated. The design-spec (later stage) must state this explicitly and derive
the composition from the established light visual language (Home) and the token
layer, not from a nonexistent Help reference.

---

## 7. Visual differences between current Help and the established light visual language

The current Help renders in the **global dark theme** (dark scaffold, light
text, `theme.colorScheme.primary` icons) with plain Material `Card`s and an
`AppBar`. The established light visual language (from the completed Home
feature) is:

- **Light surface:** `kHomeSurfaceBase` (`#F5F5F5`) background, `kHomeSurfaceCard`
  (`#FFFFFF`) cards, `kHomeSurfaceCard96` for badges.
- **Ink text:** `kHomeInk` (`#0A0A0A`) primary, `kHomeInkMuted` (`#667085`)
  supporting, `kHomeInkSubtle` (`#99A5AA`) tertiary.
- **Cyan accent:** `kHomeAccentCyan` (`#22C7F2`), `kHomeAccentCyanLight`
  (`#B9EFFF`), `kHomeAccentCyanDark` (`#087A9E`).
- **IBM Plex Sans typography** via `buildHomeTheme()` (offline, runtime fetching
  disabled).
- **Radii:** `kRadius3/14/18/24` (Home additions) plus the shared
  `kRadius12/16/20`.
- **Shadows:** `kHomeShadowSoft` / `kHomeShadowElevated` / `kHomeShadowKnob`.
- **Responsive pattern:** `SafeArea` + `LayoutBuilder` + bounded/centered width
  (`maxWidth` cap ~480) + `CustomScrollView`/`SliverFillRemaining` so content
  fills short viewports and scrolls at large text scale.
- **Accessibility pattern:** `ExcludeSemantics` for decorative elements,
  `Semantics` containers for meaningful groups, dark status-bar icons on the
  light surface via `AnnotatedRegion<SystemUiOverlayStyle>`.

The redesign moves Help from the dark, plain-card presentation to this light,
token-driven, responsive, accessible presentation while keeping the four
sections and their copy.

---

## 8. Exact files that may be candidates for later modification

These are **candidates only** — the final allowed set is decided in the Plan
stage after Design-Spec approval. All are UI-owned per
[`ui-conventions.md`](ui-conventions.md) / `.roo/rules/rules-frontend/01-scope.md`:

| File | Likely role |
|---|---|
| [`lib/screens/help_screen.dart`](../lib/screens/help_screen.dart) | Primary redesign target: light `Theme` wrapper (reusing `buildHomeTheme()`), header/title treatment (no logo), redesigned cards, icon treatment, responsive layout, semantics |
| [`lib/theme/app_home_theme.dart`](../lib/theme/app_home_theme.dart) | **Not expected to change** — Help reuses `buildHomeTheme()` as-is (owner decision, §12); no new or generalized theme builder |
| [`lib/theme/app_colors.dart`](../lib/theme/app_colors.dart) | **Not expected to change** — Help reuses the existing `kHome*` tokens; no new color anticipated |
| [`lib/theme/app_spacing.dart`](../lib/theme/app_spacing.dart) | **Not expected to change** — Help reuses the existing `kSpace*` scale |
| [`lib/theme/app_radii.dart`](../lib/theme/app_radii.dart) | **Not expected to change** — Help reuses the existing `kRadius*` scale |
| [`lib/theme/app_typography.dart`](../lib/theme/app_typography.dart) | **Not expected to change** — Help reuses the IBM Plex Sans `TextTheme` from `buildHomeTheme()` |
| [`test/widget_test.dart`](../test/widget_test.dart) | Help widget regression coverage (the existing `HelpScreen` group) |
| [`test/accessibility/semantics_test.dart`](../test/accessibility/semantics_test.dart) | Help semantics + 200% text-scale coverage |
| [`docs/architecture.md`](../docs/architecture.md) | Doc update (Help component row / theme section) if a token/theme change lands |
| [`docs/changelog.md`](../docs/changelog.md) | Doc update |
| [`docs/implementation-progress.md`](../docs/implementation-progress.md) | Doc update |
| [`docs/session-log.md`](../docs/session-log.md) | Doc update |
| `.roo/rules/docs/` mirror | Re-copy of root `/docs` after any doc change (per doc-update rule) |

---

## 9. Files and layers that must remain untouched

- **`lib/models/`** — read-only for UI work.
- **`lib/services/`** — read-only for UI work.
- **`lib/main.dart`** — only the two pre-approved exceptions (Marionette
  binding, theme consumption) apply; no Help-related change is expected here.
- **`lib/navigation/app_shell.dart`** — the Help **page construction** is in
  scope only to confirm the `const HelpScreen()` contract; no navigation,
  tab, or shell change is allowed.
- **`lib/screens/`** other than `help_screen.dart` — Detection, Settings,
  Logs & Reports, Home, and the engine screens are out of scope.
- **`lib/widgets/`** — no existing reusable widget is required to change for
  Help; any new reusable widget must be justified in the Plan.
- **`assets/`**, **`pubspec.yaml`** — no asset or dependency change is expected
  (IBM Plex Sans and `logo.png` already exist and are declared).
- **Camera, inference, engine, TTS, telemetry, correction, gesture, and
  runtime-state behavior** — unchanged.

---

## 10. Accessibility considerations

Per [`ui-conventions.md`](ui-conventions.md) and the accessibility rule:

- Help is primarily **static reading content** (no interactive controls today),
  so the main accessibility work is **semantic structure and readability**, not
  button roles.
- Each section should be exposed as a coherent semantic group (title + body),
  with the section icon treated as **decorative** and excluded from the
  accessibility tree (icons duplicate the adjacent title).
- The header/title treatment must be a real semantic heading, not just a styled
  `Text`.
- Content must be readable at **200% text scale with no overflow**; the layout
  must scroll rather than overflow (the Home `CustomScrollView` /
  `SliverFillRemaining` pattern is the reference).
- No color- or motion-only meaning: any accent/icon color is decorative and the
  text carries the meaning.
- The Help subtree, if given a light surface, must use **dark status-bar icons**
  via `AnnotatedRegion<SystemUiOverlayStyle>` (as Home does) so the status bar
  remains visible on the light surface.
- Device TalkBack validation remains a manual step.

---

## 11. Responsive-layout considerations

- The reference canvas is **390 × 844**; treat it as a baseline, not an absolute
  device size. Do not hardcode screenshot pixel dimensions.
- Follow the Home pattern: `SafeArea` + `LayoutBuilder` + a bounded/centered
  content width (Home caps at ~480) so text and cards stay readable on wide
  constraints, plus a scrollable body that never overflows at large text scale.
- Use proportional spacing from the token scale (`kSpace*`) rather than fixed
  pixel literals.
- Preserve minimum touch targets (`kMinTouchWidth`/`kMinTouchHeight`) for any
  interactive element, though Help is currently non-interactive.
- The shell's bottom `NavigationBar` remains the navigation surface; Help does
  not add its own navigation.

---

## 12. Token-naming / sharing decision (RESOLVED — reuse the Home light theme as-is)

The existing light tokens are **Home-scoped**: `kHome*` in
[`app_colors.dart`](../lib/theme/app_colors.dart) and `buildHomeTheme()` in
[`app_home_theme.dart`](../lib/theme/app_home_theme.dart). Three options were
considered:

1. **Reuse as-is.** Help imports `kHome*` tokens and `buildHomeTheme()` directly
   (or a Help-scoped `Theme` wrapper that calls `buildHomeTheme()`). Lowest
   effort; but the `kHome*`/`buildHomeTheme` names become semantically
   misleading once used by a non-Home screen, and the doc/architecture language
   ("Home-local", "scoped to the Home subtree") would need updating.
2. **Generalize into a shared light theme.** Rename/refactor the light tokens
   and `buildHomeTheme()` into a shared light theme (e.g. a `buildLightTheme()`
   and non-`kHome` token names) used by both Home and Help. Cleaner long-term,
   but it is a **rename/refactor of existing approved tokens** and touches Home
   + its tests + docs — a larger, riskier change that must be explicitly
   approved and is arguably beyond a "visual-only Help restyle."
3. **Help adds its own scoped tokens/theme.** Add `kHelp*` tokens and/or a
   `buildHelpTheme()` mirroring the Home pattern. Keeps Home untouched and
   preserves the scoped convention, but duplicates the light values and risks
   drift between the two light themes.

**Decision (owner-confirmed):** **Option 1 — reuse `buildHomeTheme()` and the
`kHome*` tokens as-is, without renaming or duplicating them.** The owner
directed that the Help theme must **match the Home screen**, so Help reuses the
same light theme builder and tokens rather than introducing a parallel light
theme. This is the smallest, safest change for a visual-only Help restyle and
avoids touching Home or renaming approved tokens. The `kHome*`/`buildHomeTheme`
naming is retained as-is; any future generalization into a shared light theme is
a separate, explicitly approved task and is out of scope here. The Design-Spec
must scope the light `Theme` wrapper to the Help subtree only (the Home `Theme`
wrapper pattern) so it does not leak into the shell `NavigationBar` or other
tabs.

---

## 13. Risks and constraints

- **No target screenshot:** the redesign is a token-consistent restyle; there is
  no Help reference to match, so the composition must be derived from the Home
  light language and tokens. Risk of over-designing without a reference is
  mitigated by reusing the established Home composition patterns.
- **Token-scope naming:** Help reuses `kHome*`/`buildHomeTheme()` as-is (owner
  decision, §12), so the "Home-local" naming is retained even though Help now
  consumes it. This is an accepted naming trade-off, not a blocker; any future
  generalization into a shared light theme is a separate task.
- **`const HelpScreen()` contract:** the shell constructs `const HelpScreen()`.
  If Help gains a `Theme` wrapper, it must remain a `StatelessWidget`
  constructible as `const HelpScreen()` with no required service dependencies.
- **Global dark theme vs light subtree:** Help currently inherits the dark
  theme. Introducing a light subtree must be scoped so it does not leak into the
  shell `NavigationBar` or other tabs (the Home `Theme` wrapper is scoped to the
  Home subtree only).
- **Status-bar contrast:** a light Help surface requires dark status-bar icons
  (Home's `AnnotatedRegion` pattern).
- **Large text / overflow:** the four sections contain long copy; the layout
  must scroll at 200% text scale without RenderFlex overflow.
- **No unrelated refactors:** only Help and its direct UI-owned dependencies may
  change; no service/model/engine/navigation changes.
- **Doc sync:** any token/theme or screen change must update root `/docs` and
  re-copy into `.roo/rules/docs/` in the same change.

---

## 14. Open Questions / Needs Verification

All items raised in the initial Analysis were resolved by the project owner and
are now confirmed inputs to the Design-Spec:

- **Token-naming/sharing decision — RESOLVED.** Reuse `kHome*`/`buildHomeTheme()`
  as-is (Option 1 in §12); the Help theme must **match the Home screen**. No
  rename, no duplication, no new Help-scoped theme.
- **Header/title treatment — RESOLVED.** The Help header does **not** reuse the
  brand mark / `logo.png` / wordmark. `logo.png` is therefore out of scope for
  Help. The header uses a plain screen-title treatment consistent with the light
  visual language.
- **No redesigned Help screenshot exists — CONFIRMED.** `design-reference/screens/`
  contains no Help image; the only Help image is the legacy
  `design-reference/old_screen/help_screen.jpg`. The Help redesign is a
  token-consistent restyle of the existing content, not a screenshot match.
- **Light-theme scope — RESOLVED.** Help is a light subtree matching Home,
  reusing `buildHomeTheme()` scoped to the Help subtree only (the Home `Theme`
  wrapper pattern), with dark status-bar icons on the light surface.
- **Section icon treatment — RESOLVED.** Keep the current four section icons
  (`timeline`, `touch_app`, `vibration`, `phone_android`) in the redesigned card
  headers.
- **Physical-device verification — RESOLVED.** A physical Android device is
  available and works on the owner's end; no further confirmation is required
  for the eventual Code-stage verification.
