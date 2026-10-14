# EyeCue — Home Screen Analysis

> **Stage:** Analysis only (open questions resolved against the codebase)
>
> **Task type:** visual-only frontend redesign
>
> **Scope:** Understand the existing Home experience and the supplied Home
> references before producing a Design-Spec. No implementation code, tests,
> assets, dependency declarations, navigation behavior, or runtime behavior is
> changed in this stage.
>
> **Resolution note (2026-09-09):** The Open Questions / Needs Verification
> items from the initial analysis were answered by inspecting the actual
> codebase and are now recorded as **Resolved Open Questions / Decisions** with
> recommended choices and rationale. The IBM Plex Sans typography item was
> additionally confirmed through MCP (pub.dev + Context7): the `google_fonts`
> package provides IBM Plex Sans and is the recommended way to use it offline.
> All items are now resolved; none remain guessed.

## 1. Analysis boundary and evidence

This analysis is limited to the Home screen and its direct dependencies:

- [`HomeScreen`](../lib/screens/home_screen.dart:11)
- [`AppShell`](../lib/navigation/app_shell.dart:20)
- [`app_colors.dart`](../lib/theme/app_colors.dart)
- [`app_spacing.dart`](../lib/theme/app_spacing.dart)
- [`app_radii.dart`](../lib/theme/app_radii.dart)
- [`app_typography.dart`](../lib/theme/app_typography.dart)
- [`app_theme.dart`](../lib/theme/app_theme.dart)
- [`settings_service.dart`](../lib/services/settings_service.dart)
- [`pubspec.yaml`](../pubspec.yaml)
- [`widget_test.dart`](../test/widget_test.dart)
- [`app_shell_test.dart`](../test/navigation/app_shell_test.dart)
- [`semantics_test.dart`](../test/accessibility/semantics_test.dart)
- [`ui-conventions.md`](ui-conventions.md)
- [`architecture.md`](architecture.md)

The visual references inspected were:

- [`home_screen.png`](../design-reference/screens/home_screen.png)
- [`home-preparing.png`](../design-reference/screens/home-preparing.png)
- [`home_screen.jpg`](../design-reference/old_screen/home_screen.jpg)
- [`design-tokens.png`](../design-reference/tokens/design-tokens.png)
- [`extracted-design-tokens-screenshot.md`](../design-reference/tokens/extracted-design-tokens-screenshot.md)
- [`logo.png`](../assets/logo.png)

The reference files are visual/design evidence, not implementation contracts
for deferred navigation, initialization, or gesture behavior. Where they
conflict with the current task instruction, the current task instruction is the
source of truth.

## 2. Current Home behavior

### 2.1 Inputs and ownership

[`HomeScreen`](../lib/screens/home_screen.dart:11) is a `StatelessWidget` with
two existing constructor inputs:

| Input | Current role | Preservation requirement |
|---|---|---|
| [`settings`](../lib/screens/home_screen.dart:12) | Reads `SettingsService.autoStartDetection`; the private status card listens to the service for changes. | Keep the existing settings input and the current listener-driven update behavior. |
| [`onGoToDetection`](../lib/screens/home_screen.dart:13) | Callback invoked by the existing **Go to Live Camera** action. | Keep the callback and invoke it from the redesigned accessible action. |

The Home screen does not own camera setup, ML initialization, engine selection,
TTS, telemetry, corrections, or gesture state. [`SettingsService`](../lib/services/settings_service.dart:60)
is read only for the existing Auto-Start value in this feature. No service or
model currently exposes a Home-owned runtime `Preparing` state.

### 2.2 Existing status behavior

The private [`_StatusCard`](../lib/screens/home_screen.dart:81) uses a
[`ListenableBuilder`](../lib/screens/home_screen.dart:89) over the injected
settings service. It derives two text variants from
[`autoStartDetection`](../lib/services/settings_service.dart:69):

- When enabled, it displays text beginning **“Detection is already running.”**
  and continues with the Auto-Start explanation.
- When disabled, it displays **“Auto-Start is off. Open Detection and press
  Start to begin.”**

The current default in [`AppSettings`](../lib/models/app_settings.dart:61) is
`autoStartDetection: true`. That setting is available to Home, but it is not a
runtime camera-status contract. In particular, the current shell constructs
Home first and constructs the detection page lazily only after the Detect tab
is visited ([`AppShellState._ensurePage`](../lib/navigation/app_shell.dart:119)).
Therefore, the existing Home status copy should not be interpreted as proof
that camera or ML initialization has completed.

This creates an important design boundary:

> A future Ready/Preparing presentation may be visually specified, but a real
> Preparing state cannot be truthfully connected during this visual-only
> feature without a runtime-state ownership change. Such a state must be
> deferred unless an already-existing runtime source is explicitly confirmed.

### 2.3 Existing callback and navigation behavior

[`AppShellState._buildPage`](../lib/navigation/app_shell.dart:89) supplies Home
with the existing callback:

```text
onGoToDetection: () => goToTab(1)
```

[`goToTab`](../lib/navigation/app_shell.dart:68) marks the Detect page visited
and changes the selected index. The shell uses an [`IndexedStack`](../lib/navigation/app_shell.dart:134)
and a persistent [`NavigationBar`](../lib/navigation/app_shell.dart:138) for
the four-tab Home/Detect/Settings/Help workflow. The redesign must retain this
behavior and must not move camera startup, replace the shell navigation, or
add Home-to-runtime initialization.

## 3. Current Home layout structure

The current tree in [`HomeScreen.build`](../lib/screens/home_screen.dart:21)
is:

```text
Scaffold
└── SafeArea
    └── LayoutBuilder
        └── SingleChildScrollView(padding: 24 on all sides)
            └── ConstrainedBox(minHeight: availableHeight - 48)
                └── Column(centered, stretched horizontally)
                    ├── top gap: 24
                    ├── Material eye icon: 96
                    ├── gap: 12
                    ├── “EyeCue”: displaySmall, extra-bold
                    ├── gap: 8
                    ├── thesis subtitle: titleMedium
                    ├── gap: 32
                    ├── private status card
                    ├── gap: 20
                    ├── AccessibleButton(“Go to Live Camera”)
                    └── bottom gap: 24
```

The current implementation is already scroll-safe for content that exceeds the
available height because of [`SingleChildScrollView`](../lib/screens/home_screen.dart:29),
and it uses [`LayoutBuilder`](../lib/screens/home_screen.dart:27). However, its
vertical centering and fixed logical gaps are based on the previous dark Home
layout rather than the supplied proportional reference composition.

The current status card is a plain [`Container`](../lib/screens/home_screen.dart:97)
with a theme-derived surface, a 16 logical-pixel padding, a 16 logical-pixel
radius, an icon, and expandable body text. The current CTA reuses
[`AccessibleButton`](../lib/widgets/accessible_button.dart:8), whose public
contract already provides an accessible label, enabled state, tap action, and a
minimum 64×56 logical-pixel button size.

## 4. Direct theme and token inventory

### 4.1 Current application theme

[`buildEyeCueTheme`](../lib/theme/app_theme.dart:13) creates a Material 3 dark
theme. It derives its color scheme from [`kSeedColor`](../lib/theme/app_colors.dart:15),
sets the scaffold to [`kScaffoldBackground`](../lib/theme/app_colors.dart:18),
uses [`kSurfaceBar`](../lib/theme/app_colors.dart:21) for the app and navigation
bars, and supplies [`highContrastTextTheme`](../lib/theme/app_typography.dart:13).
[`EyeCueApp`](../lib/main.dart:61) uses this theme for both `theme` and
`darkTheme` and forces `ThemeMode.dark` ([`EyeCueApp.build`](../lib/main.dart:77)).

The new Home references use a light `#F5F5F5` base and dark `#0A0A0A` text.
Changing [`app_theme.dart`](../lib/theme/app_theme.dart:13) globally would
change screens outside this feature, so a global theme migration is outside the
current Home-only boundary unless separately approved. The Design-Spec must
decide whether Home consumes new semantic tokens locally while the global dark
theme remains unchanged, or whether a broader theme migration is intentionally
deferred.

### 4.2 Existing color tokens versus reference tokens

The existing token layer contains dark Material-era values such as
[`kScaffoldBackground`](../lib/theme/app_colors.dart:18),
[`kSurfaceBar`](../lib/theme/app_colors.dart:21),
[`kAccent`](../lib/theme/app_colors.dart:27), and
[`kStatusAmber`](../lib/theme/app_colors.dart:42). It does not currently expose
the Home reference's light semantic values:

| Reference role | Reference value | Current token status |
|---|---:|---|
| Surface base | `#F5F5F5` | Not present; **Needs Verification** whether to add a Home semantic token. |
| Surface card | `#FFFFFF` | Not present as a named token; theme surfaces are dark-derived. |
| Primary ink | `#0A0A0A` | Not present. |
| Muted ink | `#667085` | Not present. |
| Subtle ink | `#99A5AA` | Not present. |
| Cyan accent | `#22C7F2` | Not present; current primary accent is amber. |
| Cyan light rail | `#B9EFFF` | Not present. |
| Cyan strong | `#087A9E` | Not present. |
| Preparing amber | `#F5B942` | Not present; current amber status token is a different value. |
| White 96% badge surface | `rgba(255,255,255,0.96)` | Not present. |
| Card/rail shadows | Reference rgba shadows | Not represented as tokens. |

Per the project token rule, later implementation must not put these values
inline in [`home_screen.dart`](../lib/screens/home_screen.dart:21). Any values
approved from the design source belong in [`app_colors.dart`](../lib/theme/app_colors.dart:1)
or in a theme-level mechanism approved in the Design-Spec.

### 4.3 Spacing discrepancy that must be resolved later

The two supplied token references disagree and must not be silently combined:

| Source | Spacing information |
|---|---|
| [`design-tokens.png`](../design-reference/tokens/design-tokens.png) | Visually shows `8`, `16`, `24`, `32`, `48`, and `64`; its typography area shows `56px Display`, `32px Title`, `24px Action`, `18px Body`, and `14px Label`. |
| [`extracted-design-tokens-screenshot.md`](../design-reference/tokens/extracted-design-tokens-screenshot.md:104) | States a spacing scale of `6, 8, 12, 16, 20, 24` and shape radii of `3, 12, 14, 18, 24`. |
| [`app_spacing.dart`](../lib/theme/app_spacing.dart:1) | Existing app scale includes `1, 2, 3, 4, 6, 8, 10, 12, 14, 16, 18, 20, 24, 32`, but not `48` or `64`. |

The Design-Spec must explicitly select a source for Home spacing, explain any
mapping between the two references, and identify any new token additions. The
current analysis does not select one.

### 4.4 Radii

The current token layer provides [`kRadius12`](../lib/theme/app_radii.dart:15)
and [`kRadius16`](../lib/theme/app_radii.dart:18), among others. The reference
Markdown describes 24 for large cards, 18 for small badges, 14 for toggles or
detection boxes, 12 for tags, and 3 for rails ([`extracted-design-tokens-screenshot.md`](../design-reference/tokens/extracted-design-tokens-screenshot.md:104)).
The Home badge, cards, and cyan rail therefore cannot be mapped completely from
the current radius token set without an approved token decision.

### 4.5 Typography and font availability

[`highContrastTextTheme`](../lib/theme/app_typography.dart:13) currently uses
concrete sizes and white text for the global dark theme. It does not specify
IBM Plex Sans. The reference Markdown requests IBM Plex Sans for the live
wordmark and maps Home-adjacent roles to Material text styles ([`extracted-design-tokens-screenshot.md`](../design-reference/tokens/extracted-design-tokens-screenshot.md:91)).

No IBM Plex Sans font files or explicit font-weight/line-height/letter-spacing
mapping was found in the inspected project files or asset declarations. Exact
font files, weight mappings, line heights, and letter spacing are therefore
**Needs Verification**. The reference itself also lists those typography gaps
as pending ([`extracted-design-tokens-screenshot.md`](../design-reference/tokens/extracted-design-tokens-screenshot.md:41)).

The wordmark must remain live text, not an image. The logo image is only the
visual mark ([`extracted-design-tokens-screenshot.md`](../design-reference/tokens/extracted-design-tokens-screenshot.md:35)).

## 5. Screenshot-to-code mapping

### 5.1 Current implementation versus new Home reference

| Reference element | Reference observation | Current implementation | Later candidate |
|---|---|---|---|
| Light screen background | Light `#F5F5F5` canvas, with system status-bar artwork excluded. | Dark scaffold from [`kScaffoldBackground`](../lib/theme/app_colors.dart:18). | [`home_screen.dart`](../lib/screens/home_screen.dart:21) plus approved semantic tokens in [`app_colors.dart`](../lib/theme/app_colors.dart:1); avoid global theme changes by default. |
| Top status badge | White rounded pill near the upper-left content area; cyan dot and uppercase **READY** in the ready reference. | No badge; status is a full-width-ish dark card lower in the column. | Home layout/status presentation in [`home_screen.dart`](../lib/screens/home_screen.dart:79), with new approved color/radius/shadow tokens if needed. |
| Preparing variant | White pill with amber dot and **Preparing**; lower headline reads **EyeCue is getting ready!** | No Preparing state or runtime input. | Visual variant only after its source and semantics are resolved; real runtime state is deferred. |
| Logo mark | Large centered EyeCue mark. | Material [`Icons.remove_red_eye_rounded`](../lib/screens/home_screen.dart:39). | Use [`logo.png`](../assets/logo.png) through an asset declaration, with decorative semantics unless the mark is the sole brand identifier. |
| Wordmark | Large black live **EyeCue** text beneath the mark. | Live text exists, but uses `displaySmall` and global white theme text. | [`home_screen.dart`](../lib/screens/home_screen.dart:45) consuming an approved typography token; IBM Plex Sans details remain unverified. |
| Subtitle / supporting copy | Reference lower content uses muted text such as **Detection begins immediately**. | Existing thesis subtitle is **Smart navigation assistance for visually impaired users.** | Copy hierarchy in [`home_screen.dart`](../lib/screens/home_screen.dart:53); exact copy and state-dependent wording require Design-Spec approval. |
| Start/instruction card | Lower content has **Swipe right to start!**, supporting copy, and a cyan rounded rail/gesture affordance. | Existing lower action is **Go to Live Camera**, an accessible button that invokes the navigation callback. | Home visual component in [`home_screen.dart`](../lib/screens/home_screen.dart:61), while retaining the existing callback and an accessible alternative. Right-swipe behavior is explicitly deferred. |
| Status explanation | New reference is concise and visual. | Existing status copy is long and claims detection already started when Auto-Start is on. | Preserve the input and listener behavior; wording must avoid claiming unavailable runtime truth. |
| Bottom navigation | New Home screenshots do not show the current persistent bar; token Markdown proposes removing it. | [`AppShell`](../lib/navigation/app_shell.dart:133) always renders the four-tab [`NavigationBar`](../lib/navigation/app_shell.dart:138). | No shell change in this feature; the current navigation remains. |

### 5.2 Ready and Preparing reference comparison

The supplied ready and preparing images have the same overall composition:

1. a top status badge,
2. a very large centered logo mark,
3. a centered live wordmark,
4. a lower headline and supporting line, and
5. a light cyan rounded horizontal affordance.

The visible differences are the status indicator color/text and the lower
headline:

| Variant | Badge dot/text | Lower headline | Runtime truth in current code |
|---|---|---|---|
| Ready | Cyan dot, **READY** | **Swipe right to start!** | No runtime-ready state is exposed to Home. The Auto-Start setting alone is insufficient. |
| Preparing | Amber dot, **Preparing** | **EyeCue is getting ready!** | No runtime-preparing state is exposed to Home. Implementing this as real state would require a runtime change. |

The reference text **“Detection begins immediately”** also implies app-launch
auto-start. That behavior is explicitly deferred by the current task and must
not be introduced as part of this redesign.

## 6. Reusable widgets and component boundaries

### Existing reusable UI

- [`AccessibleButton`](../lib/widgets/accessible_button.dart:8) is the only
  existing reusable component directly used by Home. It provides the current
  accessible CTA contract and should be reused or wrapped without changing the
  callback semantics.
- [`ListenableBuilder`](../lib/screens/home_screen.dart:89) is a Flutter
  framework widget used to rebuild the status presentation from settings.
- The Material [`Scaffold`](../lib/screens/home_screen.dart:24),
  [`SafeArea`](../lib/screens/home_screen.dart:25),
  [`LayoutBuilder`](../lib/screens/home_screen.dart:27), and
  [`SingleChildScrollView`](../lib/screens/home_screen.dart:29) already provide
  useful responsive and accessibility-safe structure.

### Home-private components

The current status card is a private screen-local widget,
[`_StatusCard`](../lib/screens/home_screen.dart:81), matching the naming
convention that screen-only helpers remain in the screen file. A new public
widget is not yet justified by the direct dependency set. A Home-private
status badge or start/instruction card may be sufficient if the Design-Spec
confirms those elements do not need reuse by another screen.

Changing [`AccessibleButton`](../lib/widgets/accessible_button.dart:8) is a
possible later candidate only if the approved Home design cannot be achieved
through its existing public parameters. It is shared with other controls, and
changing its visual defaults would create out-of-scope visual changes on
Detection or other screens. Prefer Home-local composition or a narrowly scoped
new Home component over changing shared button behavior.

## 7. Asset-packaging findings

[`logo.png`](../assets/logo.png) is present in the repository and was inspected
as a 512×545 RGBA PNG. It contains the black/cyan EyeCue visual mark on
transparency. It is suitable for the light reference canvas, subject to visual
verification at the responsive display size.

The asset is **not declared** in [`pubspec.yaml`](../pubspec.yaml:43). The
current Flutter asset list contains model files, labels, and the temporary test
image, but no logo entry ([`pubspec.yaml`](../pubspec.yaml:45)). Therefore:

- no application code should be changed to work around the missing declaration;
- the image must remain untouched;
- adding `assets/logo.png` to [`pubspec.yaml`](../pubspec.yaml:45) is a minimal
  cross-folder prerequisite for the later implementation;
- that declaration must not be made until an approved Plan explicitly includes
  it; and
- no new image, font, icon, or dependency should be introduced speculatively.

The wordmark must remain live text and must not be baked into or substituted by
the image asset.

## 8. Accessibility considerations

The redesign must preserve and extend the existing accessibility behavior:

1. The existing **Go to Live Camera** control must remain a real actionable
   control with the current callback, a semantic label, enabled state, and
   activation hint supplied by [`AccessibleButton`](../lib/widgets/accessible_button.dart:27).
2. If the visual card says **Swipe right to start**, the copy must not imply
   that the swipe is implemented during this feature. The existing accessible
   CTA remains the non-gesture alternative until the gesture follow-up is
   approved and implemented.
3. The status badge must expose its textual state, not rely only on cyan or
   amber. A future real state should be announced as a deliberate status change,
   not as a per-frame live region.
4. The logo mark is decorative when the adjacent live wordmark already identifies
   EyeCue. It should be excluded from the semantics tree to avoid duplicate
   announcements. If the wordmark is visually absent in a constrained layout,
   this decision must be revisited in the Design-Spec.
5. Visible text and status controls must remain readable at 200% text scale.
   Cards and badge labels must wrap or expand rather than clip or overflow.
6. Color must not be the only indication of Ready versus Preparing; the status
   text and semantic label must carry the distinction.
7. Touch targets must continue to meet the existing [`kMinTouchWidth`](../lib/theme/app_spacing.dart:51)
   and [`kMinTouchHeight`](../lib/theme/app_spacing.dart:54) guidance. Any
   gesture affordance is supplemental, never the sole accessible interaction.

The current [`semantics_test.dart`](../test/accessibility/semantics_test.dart:115)
does not contain a Home-specific semantics group. Later test work should add
Home coverage without weakening the existing detection, runtime-state, chart,
correction, and large-text tests.

## 9. Responsive-layout considerations

The reference canvas is 390×844, while the supplied PNGs are 1387×3000. Their
ratio is approximately the same, so the reference is a baseline composition,
not a set of absolute Flutter dimensions. Later layout work should:

- measure the available app window using [`MediaQuery.sizeOf`](../lib/screens/home_screen.dart:21)
  or parent constraints from [`LayoutBuilder`](../lib/screens/home_screen.dart:27),
  rather than checking a hardware type;
- preserve the existing [`SafeArea`](../lib/screens/home_screen.dart:25) and
  account for the persistent shell navigation bar reducing the Home viewport;
- use proportional or bounded layout relationships derived from the baseline,
  not screenshot pixel literals;
- constrain content width on unusually wide windows so the wordmark, status
  badge, and start card do not stretch into unreadable full-width blocks;
- retain scrolling for short-height windows, large text, and accessibility
  font scaling;
- avoid `OrientationBuilder`, `MediaQuery.orientationOf`, and new platform
  orientation configuration;
- preserve a portrait-oriented presentation without adding a portrait lock; and
- verify the top badge, centered mark, wordmark, lower instruction, and retained
  CTA at narrow, baseline, large, and 200%-text-scale constraints.

The current Home `LayoutBuilder` and scroll view are useful starting points, but
the existing centered `Column` should not be assumed to produce the reference
vertical rhythm. The Design-Spec should define the layout relationships before
implementation begins.

## 10. Candidate files for later modification

These are candidates only; no file in this list is approved for implementation
by this analysis artifact.

### Likely UI and token candidates

| File | Candidate responsibility | Boundary |
|---|---|---|
| [`home_screen.dart`](../lib/screens/home_screen.dart) | Replace the Home visual hierarchy, use the logo, add Ready/Preparing presentation only if its data source is approved, preserve settings input and CTA callback. | Primary implementation file. |
| [`app_colors.dart`](../lib/theme/app_colors.dart) | Add only design-confirmed semantic light Home colors, accent colors, and shadow values that do not already exist. | UI-owned token layer; no invented values. |
| [`app_spacing.dart`](../lib/theme/app_spacing.dart) | Add or reconcile approved spacing tokens after the PNG/Markdown discrepancy is resolved. | UI-owned token layer; requires explicit Design-Spec decision. |
| [`app_radii.dart`](../lib/theme/app_radii.dart) | Add or reconcile approved Home badge/card/rail radii. | UI-owned token layer; requires explicit Design-Spec decision. |
| [`app_typography.dart`](../lib/theme/app_typography.dart) | Add approved Home typography roles or font configuration only if exact IBM Plex Sans availability and mappings are confirmed. | UI-owned token layer; currently blocked by font verification. |
| [`accessible_button.dart`](../lib/widgets/accessible_button.dart) | Only if a shared-button change is proven necessary; otherwise leave unchanged and use the existing API. | Shared widget; avoid unrelated visual changes. |
| [`pubspec.yaml`](../pubspec.yaml:43) | Register `assets/logo.png`. | Minimal non-UI prerequisite; only allowed if included in the approved Plan. |

### Likely test and documentation candidates after approval

| File | Candidate responsibility |
|---|---|
| [`widget_test.dart`](../test/widget_test.dart:12) | Preserve existing branding/status/CTA tests and add approved Home visual-state or callback regression assertions. |
| [`semantics_test.dart`](../test/accessibility/semantics_test.dart:115) | Add Home status, wordmark, CTA, and 200% text-scale semantics coverage. |
| [`app_shell_test.dart`](../test/navigation/app_shell_test.dart:90) | Change only if a real Home widget integration assertion is needed; current stub-page navigation tests should remain valid. |
| [`architecture.md`](architecture.md) | Update Home component/folder documentation if the implementation adds a meaningful component or changes the documented Home contract. |
| [`changelog.md`](changelog.md) | Record the completed visual redesign after implementation. |
| [`implementation-progress.md`](implementation-progress.md) | Record the completed Home visual work and verification status after implementation. |
| [`session-log.md`](session-log.md) | Record the implementation session after implementation. |

The analysis artifact itself is the only file created in this stage.

## 11. Files and layers that must remain untouched

The following boundaries apply to this Home-only visual phase:

- [`app_shell.dart`](../lib/navigation/app_shell.dart) must retain the current
  four-tab persistent bottom navigation and Home-to-Detect callback wiring.
- [`settings_service.dart`](../lib/services/settings_service.dart),
  [`AppSettings`](../lib/models/app_settings.dart), and all other models/services
  remain read-only. No runtime state, app-launch initialization, engine
  fallback, TTS, telemetry, camera, inference, correction, or persistence logic
  may be added or changed.
- [`main.dart`](../lib/main.dart) remains untouched. In particular, do not move
  service construction, change theme mode globally, add auto-start logic, or
  configure orientation.
- [`assets/logo.png`](../assets/logo.png) and all design-reference files remain
  untouched. The logo is consumed, not edited.
- Detection, Help, Settings, Logs & Reports, and engine-specific screens remain
  untouched unless a separately approved scope identifies a direct compile or
  contract consequence. Their redesigns are explicitly deferred.
- No new state-management, dependency-injection, navigation, gesture, font, or
  UI component package may be introduced.
- [`pubspec.yaml`](../pubspec.yaml) must not be edited in Analysis. Its only
  identified later prerequisite is the approved registration of the existing
  logo asset.

## 12. Risks and constraints

| Risk / constraint | Impact on Home redesign | Required handling |
|---|---|---|
| Global theme is dark while references are light. | A direct use of theme surfaces/text will not match the reference. | Resolve local semantic-token versus global-theme scope in the Design-Spec; do not silently change every screen. |
| Reference Markdown proposes removing the bottom navigation. | The new Home screenshots omit the bar, but the current task explicitly preserves it. | Keep the current bar and treat the reference content as the Home content area above it. |
| Reference Markdown proposes a literal right-swipe start. | The current task explicitly defers right-swipe behavior. | Do not add gesture handling; retain the accessible callback action. |
| Reference Markdown requires app-launch auto-start and a real Preparing state. | Current Home has no runtime state input and the shell lazily creates Detect. | Do not claim or implement these behaviors in a visual-only change. |
| Current Auto-Start status copy claims detection is already running. | This may be inaccurate when only the setting is known. | Preserve the setting input/listening behavior but resolve truthful wording as a product/design decision. |
| Logo is not registered. | `Image.asset` would fail at runtime until the asset is declared. | Include the minimal `pubspec.yaml` registration only in an approved Plan. |
| IBM Plex Sans files/mappings are absent. | Exact reference typography cannot yet be guaranteed. | Mark font details Needs Verification; do not add a speculative font package or file. |
| PNG and Markdown spacing scales disagree. | Padding, vertical rhythm, card radii, and proportions could diverge. | Resolve explicitly in Design-Spec before adding tokens or implementation values. |
| Shared [`AccessibleButton`](../lib/widgets/accessible_button.dart:8) owns visual defaults. | Changing it could alter Detection controls. | Prefer Home-local styling/composition and preserve shared behavior. |
| Large visual mark and vertical composition consume substantial height. | Small windows and 200% text may overflow. | Keep bounded proportional layout plus scrolling and test constrained heights. |

## 13. Deferred work recorded by this analysis

The following items are outside this feature and must not enter a later Home
implementation implicitly:

1. Home right-swipe-to-start behavior.
2. App-launch camera or ML auto-start.
3. A shared runtime-owned Preparing state.
4. Replacing the persistent bottom navigation with two-finger navigation.
5. Removing or replacing Detection Start, Stop, or Repeat controls.
6. Gesture-only behavior without accessible alternatives.
7. Portrait-lock configuration.
8. Ground-truth-backed accuracy reporting.
9. Help or Logs & Reports redesign.
10. Camera, inference, engine, TTS, telemetry, correction, model, or service
    changes.

## Resolved Open Questions / Decisions

> **Resolution note (2026-09-09):** Each item below was answered by inspecting
> the actual codebase (not assumed) and, where a decision was required, the
> recommended option is chosen with its rationale. Items that remain genuinely
> unresolvable from the repository (font files) stay flagged rather than
> guessed.

### 1. Ready state source — RESOLVED: present the `autoStartDetection` preference

**Codebase confirmation:** The only runtime state source is
[`EngineCoordinator`](../lib/services/engine_coordinator.dart:14), a
`ChangeNotifier` exposing [`DetectionRuntimeState`](../lib/models/detection_runtime_state.dart:4)
(`idle`, `startingCamera`, `loadingModel`, `ready`, `paused`, `recovering`,
`fallback`, `failed`, `disposed`). However, the coordinator is created as a
`late final` field **inside `_EngineDetectionScreenState`**
([`engine_detection_screen.dart:36`](../lib/screens/engine_detection_screen.dart:36)),
scoped entirely to the Detect tab. It is **not** constructed in
[`main.dart`](../lib/main.dart:25) nor passed through
[`AppShell`](../lib/navigation/app_shell.dart:20), and the Detect page is built
lazily only after the tab is first visited
([`AppShellState._ensurePage`](../lib/navigation/app_shell.dart:119)). Home has
no reference to any runtime-ready signal.

**Decision (recommended):** The Home Ready badge is a presentation of the
existing `autoStartDetection` preference — the only signal Home can truthfully
read today. It must **not** claim the camera or ML pipeline is running. A real
runtime-ready badge would require lifting the coordinator up to `AppShell`/
`main` and passing it to Home, which is an architecture change outside this
visual-only scope and is deferred.

### 2. Preparing state source — RESOLVED: defer the real Preparing variant

**Codebase confirmation:** Same finding as #1. No runtime-preparing state is
reachable from Home; the coordinator that would carry it is Detect-scoped and
lazily constructed. The reference's "real Preparing state tied to background
camera/ML init" ([`extracted-design-tokens-screenshot.md`](../design-reference/tokens/extracted-design-tokens-screenshot.md:16))
also depends on app-launch auto-start, which is explicitly deferred by the task.

**Decision (recommended):** Defer the real Preparing variant. Do not fabricate
a Preparing state from the `autoStartDetection` preference, because that would
repeat the same untruthful claim the current status copy makes. If a visual
Preparing placeholder is desired purely for design parity, it must be clearly
non-functional and gated behind the same deferred runtime work — the Design-Spec
should default to omitting it.

### 3. Status wording — RESOLVED: correct the wording to be preference-truthful

**Codebase confirmation:** The current `_StatusCard`
([`home_screen.dart:81`](../lib/screens/home_screen.dart:81)) derives text from
[`autoStartDetection`](../lib/services/settings_service.dart:69). The default in
[`AppSettings`](../lib/models/app_settings.dart:61) is `true`, so the default
copy begins "Detection is already running." Because the Detect page is lazily
constructed ([`app_shell.dart:119`](../lib/navigation/app_shell.dart:119)), that
claim is not backed by any running camera/ML state at Home render time.

**Decision (recommended):** Correct the wording so it states the preference
without claiming runtime truth. Recommended phrasing: when Auto-Start is on,
"Auto-Start is on. Detection will begin when you open Detect."; when off,
"Auto-Start is off. Open Detect and press Start to begin." This preserves the
`settings` input and listener behavior while removing the unsupported "already
running" claim. This is a content correction, not a behavior change.

### 4. CTA treatment — RESOLVED: retain the accessible CTA as the non-gesture action

**Codebase confirmation:** The reference shows a literal "Swipe right to start!"
gesture card ([`extracted-design-tokens-screenshot.md`](../design-reference/tokens/extracted-design-tokens-screenshot.md:115)),
but the task explicitly defers right-swipe behavior and requires preserving the
`onGoToDetection` callback and accessible behavior. The current CTA is the
shared [`AccessibleButton`](../lib/widgets/accessible_button.dart:8), which
supplies label, enabled state, tap action, and a 64×56 minimum target.

**Decision (recommended):** Retain the accessible CTA as the real, non-gesture
action that invokes `onGoToDetection`. It may be visually restyled to sit inside
or below the start/instruction card, but it must remain a real actionable
control. The "Swipe right to start!" copy, if shown, must not imply the swipe is
implemented; the CTA is the accessible equivalent until the gesture follow-up is
approved. Do not change the shared [`AccessibleButton`](../lib/widgets/accessible_button.dart:8)
visual defaults; use Home-local composition or a narrowly scoped Home component.

### 5. Theme scope — RESOLVED: Home uses locally scoped light semantic tokens

**Codebase confirmation:** [`buildEyeCueTheme`](../lib/theme/app_theme.dart:13)
builds a Material 3 **dark** theme, and [`EyeCueApp`](../lib/main.dart:77) forces
`ThemeMode.dark` for both `theme` and `darkTheme`. The reference Home is light
(`#F5F5F5` base, `#0A0A0A` ink). Changing the global theme would alter every
screen and is outside the Home-only boundary.

**Decision (recommended):** Home consumes new light semantic tokens locally
(added to [`app_colors.dart`](../lib/theme/app_colors.dart:1)) while the global
dark theme and persistent navigation remain unchanged. A global theme migration
is deferred to a separate approved feature. This keeps the change Home-scoped
and avoids out-of-scope visual changes on Detection/Settings/Help.

### 6. Token source precedence — RESOLVED: the extracted Markdown is authoritative

**Codebase confirmation:** The extracted Markdown
([`extracted-design-tokens-screenshot.md`](../design-reference/tokens/extracted-design-tokens-screenshot.md:64))
contains the full extracted CSS layer data: the complete color palette with
hex/alpha values, the IBM Plex Sans → Material `TextTheme` role mapping, radii
(`3, 12, 14, 18, 24`), spacing (`6, 8, 12, 16, 20, 24`), shadow definitions, and
screen-specific overrides. The [`design-tokens.png`](../design-reference/tokens/design-tokens.png)
is a visual summary that omits most of these values and shows a coarser spacing
set (`8, 16, 24, 32, 48, 64`).

**Decision (recommended):** The extracted Markdown is the authoritative token
source because it is the complete, machine-extracted CSS/Figma layer data. The
PNG is a visual cross-check only. Where they disagree (spacing scale), the
Markdown's `6, 8, 12, 16, 20, 24` scale governs Home spacing. The Design-Spec
should document this precedence explicitly.

### 7. New token names — RESOLVED: use the reference semantic names; shadows are a theme component

**Codebase confirmation:** The reference already assigns semantic names
(`surface-base`, `surface-card`, `surface-card-96`, `ink`, `ink-muted`,
`ink-subtle`, `accent-cyan`, `accent-cyan-light`, `accent-cyan-dark`,
`warning-amber`, plus washes/borders) ([`extracted-design-tokens-screenshot.md`](../design-reference/tokens/extracted-design-tokens-screenshot.md:66)).
The current [`app_colors.dart`](../lib/theme/app_colors.dart:1) uses a
`k`-prefixed semantic naming convention (e.g. `kScaffoldBackground`, `kAccent`).

**Decision (recommended):** Add the approved light Home colors to
[`app_colors.dart`](../lib/theme/app_colors.dart:1) using the existing
`k`-prefixed convention mapped from the reference semantic names (e.g.
`kHomeSurfaceBase`, `kHomeSurfaceCard`, `kHomeInk`, `kHomeInkMuted`,
`kHomeAccentCyan`, `kHomeAccentCyanLight`, `kHomeAccentCyanDark`,
`kHomeWarningAmber`). Shadows are **not** color tokens; they belong in a theme
component (`BoxShadow` list) defined in the Design-Spec, not in `app_colors.dart`.

### 8. Typography — RESOLVED: use the `google_fonts` package for IBM Plex Sans

**Codebase confirmation:** [`pubspec.yaml`](../pubspec.yaml:43) has **no**
`fonts:` section, no `.ttf`/`.otf` font files exist in the repository, and no
`google_fonts` dependency is declared. The only `fontFamily` in code is
`'monospace'` in the debug overlay
([`debug_overlay.dart`](../lib/widgets/debug_overlay.dart:73)). The reference
lists the exact IBM Plex Sans files/weights as pending input
([`extracted-design-tokens-screenshot.md`](../design-reference/tokens/extracted-design-tokens-screenshot.md:45)).

**MCP confirmation (pub.dev + Context7):** The [`google_fonts`](https://pub.dev/packages/google_fonts)
package (latest **8.2.1**, published by `flutter.dev`, BSD-3-Clause, ~3M
downloads) provides per-family methods for every Google Font, including IBM Plex
Sans. It exposes `GoogleFonts.plexSans(...)` for individual `TextStyle`s and
`GoogleFonts.plexSansTextTheme(...)` to apply the family across a whole
`TextTheme`. It supports both runtime HTTP fetching and **offline asset
bundling** (download the needed weights, place them under an asset folder with
their original Google Fonts filenames, and declare that folder under `assets:`
in `pubspec.yaml` — no `fonts:` section is required). Because EyeCue is an
offline, privacy-preserving app, the offline asset-bundling mode is the correct
choice; runtime HTTP fetching must not be used.

**Decision (recommended):** Resolve the typography blocker by adding
`google_fonts: ^8.2.1` as a dependency and applying IBM Plex Sans through the
package's offline asset-bundling mode. The Design-Spec maps the reference's
Material roles onto `GoogleFonts.plexSansTextTheme(...)` (e.g. `displayLarge`
56px w700 wordmark, `headlineLarge` 32px w700 titles, `titleLarge` 24px w600
actions, `bodyMedium` 18px w400 paragraphs, `labelLarge` 14px w600 buttons) and
bundles the required IBM Plex Sans weights (Regular 400, Medium 500, SemiBold
600, Bold 700) as assets. The wordmark remains live text. This is a new
dependency and asset addition, so it is authorized only in the approved Plan,
not during Analysis. The existing
[`highContrastTextTheme`](../lib/theme/app_typography.dart:13) remains the
fallback for the global dark theme until the light Home theme is applied.

### 9. Logo packaging — RESOLVED: register `assets/logo.png` in the approved Plan

**Codebase confirmation:** [`logo.png`](../assets/logo.png) exists (512×545 RGBA,
mark-only on transparency) but is **not** in the Flutter asset list
([`pubspec.yaml:45`](../pubspec.yaml:45)). `Image.asset` would fail at runtime
until it is declared.

**Decision (recommended):** Add the one-line `- assets/logo.png` registration to
[`pubspec.yaml`](../pubspec.yaml:45) **only** as part of the approved Plan (not
during Analysis). The image is consumed, never edited. The wordmark stays live
text; the logo is the decorative visual mark and should be excluded from the
semantics tree when the adjacent wordmark identifies EyeCue.

### 10. Reference viewport treatment — RESOLVED: reference content sits above the retained nav bar

**Codebase confirmation:** The new screenshots omit the bottom navigation, but
the task explicitly requires retaining the persistent four-tab
[`NavigationBar`](../lib/navigation/app_shell.dart:138). The reference canvas is
390×844 and the PNGs are 1387×3000 (same ~ratio), so the reference is a
proportional composition, not absolute dimensions.

**Decision (recommended):** Treat the reference content as the Home content area
**above** the retained navigation bar. The responsive Design-Spec must account
for the nav bar reducing the Home viewport (via the existing
[`SafeArea`](../lib/screens/home_screen.dart:25) and
[`LayoutBuilder`](../lib/screens/home_screen.dart:27)) and use proportional
relationships, not screenshot pixel literals. Do not remove or restyle the nav
bar in this feature.

### 11. Home test split — RESOLVED: extend the two existing files; no new file

**Codebase confirmation:** [`widget_test.dart`](../test/widget_test.dart:12)
already has a `HomeScreen` group covering branding, status card, CTA, and the
Auto-Start-off state. [`semantics_test.dart`](../test/accessibility/semantics_test.dart:115)
already provides the reusable `scaledApp` (200% text scale) helper
([`semantics_test.dart:54`](../test/accessibility/semantics_test.dart:54)) and
`expectButtonSemantics`/`expectSemanticNode` helpers
([`semantics_test.dart:63`](../test/accessibility/semantics_test.dart:63)).

**Decision (recommended):** Keep visual/state/callback regression in the
`HomeScreen` group of [`widget_test.dart`](../test/widget_test.dart:12), and add
Home status/wordmark/CTA semantics plus 200% text-scale coverage to
[`semantics_test.dart`](../test/accessibility/semantics_test.dart:115) reusing
its existing helpers. No new Home-specific test file is needed unless the
approved Design-Spec creates a testable Home-only component boundary (e.g. a
public status-badge widget), in which case a dedicated file is justified.

## Analysis conclusion

The Home redesign is feasible as a focused UI change in
[`home_screen.dart`](../lib/screens/home_screen.dart:11), with possible
additions to the UI token layer and a minimal approved logo registration in
[`pubspec.yaml`](../pubspec.yaml:43). The existing settings input, listener
behavior, accessible CTA callback, and persistent bottom navigation can be
preserved without touching services, models, camera/ML initialization, or
navigation architecture.

The open questions recorded in the previous version of this document have been
answered against the codebase and resolved with recommended decisions (see
**Resolved Open Questions / Decisions** above):

- The Ready badge presents the `autoStartDetection` preference; the real
  runtime-ready/Preparing state is deferred because the `EngineCoordinator` is
  Detect-scoped and not reachable from Home.
- Status wording is corrected to be preference-truthful rather than claiming
  detection is already running.
- The accessible CTA is retained as the non-gesture action; the swipe is
  deferred.
- Home uses locally scoped light semantic tokens while the global dark theme
  and persistent navigation remain.
- The extracted Markdown is the authoritative token source over the PNG.
- New light colors use the existing `k`-prefixed convention; shadows are a
  theme component, not color tokens.
- `assets/logo.png` is registered only in the approved Plan.
- Reference content sits above the retained navigation bar.
- Home tests extend the existing `widget_test.dart` and `semantics_test.dart`
  files; no new file is required.

The typography item is also resolved: IBM Plex Sans is available through the
`google_fonts` package (confirmed via MCP), which should be added as a
dependency and used in its offline asset-bundling mode so EyeCue stays
offline/privacy-preserving. The Design-Spec maps the reference's Material roles
onto `GoogleFonts.plexSansTextTheme(...)` and bundles the required IBM Plex Sans
weights as assets. This new dependency and asset addition is authorized only in
the approved Plan, not during Analysis.

All Open Questions / Needs Verification items are now resolved with recommended
decisions. The remaining work before a Design-Spec is the Design-Spec itself,
which must turn these decisions into concrete token additions, the light Home
theme, the logo registration, the `google_fonts` dependency, and the Home layout
relationships.
