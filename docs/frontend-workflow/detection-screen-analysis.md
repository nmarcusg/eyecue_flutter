# EyeCue — Detection Screen Visual Redesign: Analysis

> **Stage:** Analysis (read-only). No application code, tests, assets,
> `pubspec.yaml`, or other project files were modified to produce this document.
> **Date:** 2026-09-10
> **Task type:** Visual-only frontend redesign (token-consistent restyle).
> **Scope:** Redesign the Detection Screen's visual presentation while preserving
> its existing content and behavior. This is a token-consistent restyle of the
> existing content, **not** a screenshot match and **not** an architecture change.
> **Source-of-truth order:** this prompt → (later) `detection-screen-plan.md` →
> `detection-screen-design-spec.md` → this analysis → general `.roo/rules/`.
> **Vision note:** The design references were inspected with a vision-capable
> model (Gemini `gemini-3.6-flash`) via the supplied API key, because the
> orchestrating model could not process images natively. All visual facts below
> are transcribed from that inspection and are labelled accordingly.

---

## 1. Task type

**Visual-only frontend redesign.** The goal is to restyle the Detection Screen's
visual presentation using the established light visual language and token layer,
while preserving all existing content and runtime behavior.

This task is **not** combined with: camera/inference architecture changes;
gesture changes; TTS/haptics behavior changes; telemetry computation changes;
correction-flow changes; navigation changes; engine-selection/fallback changes;
runtime-state ownership changes; model/service refactoring; portrait-lock
configuration; or new state-management/DI frameworks. No new repository,
ViewModel, use-case, state-management package, or architecture migration is
introduced. The existing project structure, constructor-injection patterns, and
the light-theme pattern established by the completed Home, Help, and Settings
features are reused.

**Critical scope boundary (flagged):** the Detection Screen is the **live camera
surface**. Unlike Home/Help/Settings, its central region is a real-time camera
preview with a detection overlay. A light theme must be applied **around** the
camera viewport, never over it, and the overlay legibility contract (bounding
boxes, labels, warning banner, gesture hint) must be preserved. See §7.

---

## 2. Current Detection behavior and structure

### 2.1 Screen ownership and construction

The Detect tab is built by [`EngineDetectionScreen`](../lib/screens/engine_detection_screen.dart:15),
which owns an [`EngineCoordinator`](../lib/services/engine_coordinator.dart:14)
and switches between two child screens by active engine:

| Active engine | Child screen | File |
|---|---|---|
| `InferenceEngine.custom` | [`DetectionScreen`](../lib/screens/detection_screen.dart:48) | [`detection_screen.dart`](../lib/screens/detection_screen.dart:48) |
| `InferenceEngine.ultralytics` | [`UltralyticsDetectionScreen`](../lib/screens/ultralytics_detection_screen.dart:26) | [`ultralytics_detection_screen.dart`](../lib/screens/ultralytics_detection_screen.dart:26) |

[`EngineDetectionScreen`](../lib/screens/engine_detection_screen.dart:98) wraps the
active child in a `Stack` and overlays a temporary-fallback notice
([`_buildFallbackNotice`](../lib/screens/engine_detection_screen.dart:144)) when
the coordinator reports a one-shot fallback. The Detect tab is constructed by
[`AppShellState._buildPage`](../lib/navigation/app_shell.dart:100) as tab index 1
inside the shell's `IndexedStack`, and inherits the shell's `Scaffold` and
persistent four-tab [`NavigationBar`](../lib/navigation/app_shell.dart:139).

**Both child screens share the same visual composition** (top bar → main area →
fixed-height controls panel) and the same widget vocabulary. The redesign must
cover **both** so the two engines remain visually consistent.

### 2.2 Behavior contract (must be preserved)

| Behavior | Location | Preservation requirement |
|---|---|---|
| Camera lifecycle (permission, `availableCameras`, `CameraController`, YUV420 image stream) | [`detection_screen.dart`](../lib/screens/detection_screen.dart:192) | Unchanged. |
| Frame-dropping busy gate (`_isInferring`) | [`detection_screen.dart`](../lib/screens/detection_screen.dart:643) | Unchanged. |
| Pause / low-power dispatch throttle | [`detection_screen.dart`](../lib/screens/detection_screen.dart:637) | Unchanged. |
| Orientation math (`BoxTransform`) | [`detection_screen.dart`](../lib/screens/detection_screen.dart:663) | Unchanged. |
| Bounding-box overlay math (`applyBoxFit` + `FittedBox`) | [`bounding_box_painter.dart`](../lib/widgets/bounding_box_painter.dart:89) | Unchanged. |
| Thesis gestures (single tap, two-finger double-tap, three-finger tap, swipe-down) | [`detection_screen.dart`](../lib/screens/detection_screen.dart:432), [`ultralytics_detection_screen.dart`](../lib/screens/ultralytics_detection_screen.dart:365) | Unchanged. |
| TTS announcements (start/stop, detections, scan, repeat, mute) | [`detection_screen.dart`](../lib/screens/detection_screen.dart:294) | Unchanged. |
| Haptics (light/medium/heavy ticks) | [`detection_screen.dart`](../lib/screens/detection_screen.dart:295) | Unchanged. |
| Telemetry recording (samples, recovery, failures) | [`detection_screen.dart`](../lib/screens/detection_screen.dart:455) | Unchanged. |
| Correction flow (`showDetectionCorrectionSheet` + snackbar + TTS) | [`detection_screen.dart`](../lib/screens/detection_screen.dart:374) | Unchanged. |
| Runtime-state reporting to the coordinator | [`detection_screen.dart`](../lib/screens/detection_screen.dart:547) | Unchanged. |
| Engine fallback notice | [`engine_detection_screen.dart`](../lib/screens/engine_detection_screen.dart:144) | Unchanged. |
| Navigation (shell tabs, Logs & Reports pushed route) | [`app_shell.dart`](../lib/navigation/app_shell.dart:126) | Unchanged. |

### 2.3 Current structure (both child screens)

```text
Scaffold
└── SafeArea
    └── LayoutBuilder
        └── Column
            ├── _buildTopBar()            // "Detection Mode" title + StatusPill + audio IconButton
            ├── Expanded(_buildMainArea()) // state panel | permission-denied | camera-pending | viewport
            └── SizedBox(height: contentHeight)  // fixed 32% (clamped 200–320)
                └── _buildControlsPanel() // warning banner + detection list + button Wrap + gesture hint
```

The camera viewport ([`_buildViewport`](../lib/screens/detection_screen.dart:957))
is a `Stack` of: `FittedBox`(camera preview) → `CustomPaint`(bounding boxes) →
`_GestureHint` → `GestureSurface`(transparent gesture capture).

### 2.4 Current visual values (hardcoded, to be tokenized)

| Element | Current value | Location |
|---|---|---|
| Status pill colors | `#455A64` stopped, `#F57F17` paused, `#1B5E20` detecting, `#0D47A1` loading | [`detection_screen.dart`](../lib/screens/detection_screen.dart:815), [`ultralytics_detection_screen.dart`](../lib/screens/ultralytics_detection_screen.dart:418) |
| Controls panel background | `theme.colorScheme.surfaceContainerHigh` | [`detection_screen.dart`](../lib/screens/detection_screen.dart:1034) |
| Gesture hint | `Color(0xCC000000)`, radius 20, `Colors.white24` border | [`detection_screen.dart`](../lib/screens/detection_screen.dart:1143) |
| Warning banner | `#B71C1C`, radius 12, white 2px border | [`warning_banner.dart`](../lib/widgets/warning_banner.dart:20) |
| Priority badge | `#B71C1C`/`#F9A825`/`#1B5E20`, radius 6 | [`priority_badge.dart`](../lib/widgets/priority_badge.dart:18) |
| Detection card | `theme.colorScheme.surface`, radius 12 | [`detection_card.dart`](../lib/widgets/detection_card.dart:33) |
| Bounding-box palette | 8-color cycle | [`bounding_box_painter.dart`](../lib/widgets/bounding_box_painter.dart:65) |

Note: several of these values **already exist as tokens** in
[`app_colors.dart`](../lib/theme/app_colors.dart:1) (`kStatusBlueGrey`,
`kStatusAmber`, `kStatusGreen`, `kStatusBlue`, `kWarningRed`, `kMediumAmber`,
`kLowGreen`, `kOverlayBlack`, `kDetectionPalette`) but the widgets currently
hardcode the literals instead of referencing the tokens. This is a
token-consistency gap the redesign should close (see §6).

---

## 3. Direct dependencies only

| Dependency | File | Role for Detection |
|---|---|---|
| Material | `package:flutter/material.dart` | `Scaffold`, `SafeArea`, `LayoutBuilder`, `Column`, `Stack`, `FittedBox`, `CustomPaint`, `IconButton`, `Wrap`, `ListView`, `Card`, `SnackBar` |
| Camera | [`camera`](https://pub.dev/packages/camera) | `CameraController`, `CameraPreview`, `CameraImage` |
| Ultralytics | [`ultralytics_yolo`](https://pub.dev/packages/ultralytics_yolo) | `YOLOView`, `YOLOViewController` |
| Detection model | [`detection.dart`](../lib/models/detection.dart:1) | `Detection` (classId, label, confidence, box) |
| Detection info | [`detection_info.dart`](../lib/models/detection_info.dart:1) | `DetectionInfo`, `ObjectPriority`, `semanticLabel` |
| Runtime state | [`detection_runtime_state.dart`](../lib/models/detection_runtime_state.dart:1) | `DetectionRuntimeState`, `DetectionFailure` |
| Assistive controller | [`assistive_detection_controller.dart`](../lib/services/assistive_detection_controller.dart:1) | Shared post-detection behavior |
| Gesture controller | [`gesture_controller.dart`](../lib/services/gesture_controller.dart:1) | `EyeCueGesture` state machine |
| Theme (global) | [`app_theme.dart`](../lib/theme/app_theme.dart:13) | Dark `buildEyeCueTheme()` currently inherited by Detection |
| Light-theme pattern | [`app_home_theme.dart`](../lib/theme/app_home_theme.dart:50) | `buildHomeTheme()` — established light `ThemeData` + IBM Plex Sans + shadow tokens |
| Tokens | [`app_colors.dart`](../lib/theme/app_colors.dart:1), [`app_spacing.dart`](../lib/theme/app_spacing.dart:1), [`app_radii.dart`](../lib/theme/app_radii.dart:1), [`app_typography.dart`](../lib/theme/app_typography.dart:1) | Semantic color/spacing/radius/type tokens |
| Reference implementations | [`home_screen.dart`](../lib/screens/home_screen.dart:22), [`help_screen.dart`](../lib/screens/help_screen.dart:17), [`settings_screen.dart`](../lib/screens/settings_screen.dart:22) | Light-theme, responsive, accessibility pattern to follow |
| Widgets | [`bounding_box_painter.dart`](../lib/widgets/bounding_box_painter.dart:26), [`gesture_surface.dart`](../lib/widgets/gesture_surface.dart:11), [`detection_card.dart`](../lib/widgets/detection_card.dart:11), [`priority_badge.dart`](../lib/widgets/priority_badge.dart:9), [`warning_banner.dart`](../lib/widgets/warning_banner.dart:4), [`status_pill.dart`](../lib/widgets/status_pill.dart:5), [`detection_state_panel.dart`](../lib/widgets/detection_state_panel.dart:12), [`detection_correction_sheet.dart`](../lib/widgets/detection_correction_sheet.dart:8), [`accessible_button.dart`](../lib/widgets/accessible_button.dart:8) | Detection UI vocabulary |

No unrelated routes or services were inspected. No repository-wide audit was
performed.

---

## 4. Confirmed visual facts from the references

### 4.1 Target Detection reference (`design-reference/screens/detection_screen.png`)

Transcribed from vision inspection. The target is a **light, spacious,
rounded-card** composition:

- **Background:** off-white / ultra-light cool gray (`#F4F5F7`).
- **Header (top-left):** a small uppercase category label `DETECTION MODE`
  (medium gray `#6E6E73`, ~13pt, bold), with a large near-black `LIVE` title
  (~32pt, extra-bold) below it. **Not adopted** — the owner override keeps the
  existing single `Detection Mode` title for cross-screen consistency (see §14
  item 5). This is a factual description of what the target shows, not a
  direction to implement.
- **Header (top-right):** a white stadium pill (`#FFFFFF`, radius ~20, soft
  shadow) containing a cyan dot (`#1AC8ED`) and uppercase `AUDIO ON` text
  (near-black, ~12pt, bold).
- **Camera viewport:** a large vertical rounded rectangle (radius ~28–32),
  solid near-black (`#0A0A0C`), occupying roughly 55–60% of the screen height.
  A `LIVE CAMERA` label (uppercase, medium gray `#8E8E93`, ~12pt) sits inset
  ~16px from the top-left inside the viewport.
- **Detection overlays (inside the viewport):**
  - A cyan (`#1AC8ED`) rounded bounding box (~2px stroke, radius ~16) with a
    filled cyan pill label `PERSON · AHEAD` (dark navy text, ~11pt).
  - An amber (`#F59E0B`) rounded bounding box (~2px stroke, radius ~12) with a
    plain amber `CHAIR` label (no filled pill).
  - A floating dark charcoal transcript bar (`#202022`, radius ~16) near the
    bottom inside edge, with a cyan waveform icon and white text
    `Person ahead · 2.1 m` (~16pt).
- **Bottom action cards (two-column, ~12px gap):**
  - **Left — Pause:** white card (radius ~24, soft shadow), cyan pause glyph,
    uppercase `PAUSE` (~22pt, extra-bold, dark charcoal), secondary
    `HOLD 3 SEC` (medium gray, ~12pt), and a light-cyan progress accent line.
  - **Right — Quick Scan:** solid cyan card (`#1AC8ED`, radius ~24), black
    target/bullseye glyph, uppercase `QUICK SCAN` (~22pt, extra-bold, dark
    navy), secondary `TAP` (dark navy, ~12pt).
- **Color summary:** background `#F4F5F7`; camera `#0A0A0C`; accent cyan
  `#1AC8ED`; amber `#F59E0B`; card white `#FFFFFF`; ink `#111111`/`#081D28`;
  muted `#6E6E73`/`#8E8E93`; transcript bar `#202022`.

### 4.2 Authoritative overrides (from the extracted token/spec markdown)

The extracted token/spec document
([`extracted-design-tokens-screenshot.md`](../design-reference/tokens/extracted-design-tokens-screenshot.md:117))
**contains a Detection Screen section** (Section 3.B) and is authoritative over
the target screenshot. It states:

1. **Camera viewport:** main surface (`surface-dark`, 91.79% width, 64.45%
   height), containing bounding boxes and transcript overlays **relative to the
   viewport, not the screen**.
2. **Action Cards (Constraint):** **Only** render **Pause** (left, 39.74% width)
   and **Quick Scan** (right, 47.95% width). **Do not render Start, Stop, or
   Repeat buttons** on the screen.
3. **Global navigation:** the persistent 4-tab bottom navigation bar is
   described as removed in the design source, with tab navigation via a
   two-finger swipe. **This is overridden by the current task** (navigation must
   be preserved) — see §5 and §13.
4. **Gestures:** Start/Stop via two-finger double-tap; Repeat via one-finger
   swipe-down; no on-screen Start/Stop/Repeat buttons.
5. **Responsiveness:** do not hardcode pixel dimensions; calculate relative
   proportions from the 390×844 baseline.
6. **Theme:** portrait-only, single unified theme, no toggleable dark mode.
7. **System UI:** ignore the OS status bar (clock/battery) in screenshots.

### 4.3 Legacy Detection references (`design-reference/old_screen/`)

**ON state** ([`detection_screen.jpg`](../design-reference/old_screen/detection_screen.jpg)):
dark charcoal background; bold white `Detection Mode` title; green-outlined
`Detecting` status pill; dark circular mute button; live camera feed with a
semi-transparent gesture pill (`Gestures active · Ultralytics engine`); a
performance line (`Ultralytics GPU→CPU · 19.0 FPS · 56.8 ms infer / 62.3 ms
native total`); a red high-priority warning card; `Stop` and `Pause` capsule
buttons; a yellow/black overflow banner; and the dark 4-tab bottom nav.

**OFF state** ([`detection_screen_off.jpg`](../design-reference/old_screen/detection_screen_off.jpg)):
dark background; `Detection Mode` title; `Stopped` status pill; mute button;
blacked-out preview with `Detection is off.` and a yellow `Start Detection`
capsule; a lower control deck (`Start`, `Pause`, `Repeat`, `Correct last
announcement`); a `BOTTOM OVERFLOWED BY 74 PIXELS` banner; and the dark 4-tab
bottom nav.

The legacy references are a useful **inventory of existing concepts** (status
pill, mute, warning banner, controls, gesture hint) but are **not** the target
visual language. They also show the historical overflow bug that the current
fixed-height controls region was introduced to fix.

### 4.4 Established light language (`home_screen.png`, `settings-screen.png`)

The Home and Settings references establish the light palette, strong black
typography, muted secondary text, cyan accent, generous whitespace, and rounded
surfaces that the Detection redesign should reuse. The completed Home, Help, and
Settings implementations ([`home_screen.dart`](../lib/screens/home_screen.dart:22),
[`help_screen.dart`](../lib/screens/help_screen.dart:17),
[`settings_screen.dart`](../lib/screens/settings_screen.dart:22)) are the
concrete reference for how that language is applied in code.

### 4.5 Design-token PNG (`design-reference/tokens/design-tokens.png`)

Per the established Home/Settings precedent, the **extracted token Markdown is
authoritative over the token-summary PNG** where they disagree. The PNG is a
visual cross-check only. The Markdown's finer spacing scale (`6, 8, 12, 16, 20,
24`) and its complete color/radius/shadow definitions govern the Detection
implementation; the PNG's coarser spacing (`8/16/24/32/48/64`) is not used as
new spacing values.

---

## 5. Existing behavior that must remain unchanged

The following are **behavioral contracts**, not visual details:

1. **Both child screens remain constructible with their existing inputs**
   (`settings`, `tts`, `telemetry`, `corrections`, `haptics`,
   `onRuntimeStateChanged`, `onFailure`).
2. **Camera/inference architecture** — persistent isolate, frame-dropping gate,
   pause/low-power throttle, orientation math, and the `applyBoxFit` overlay
   math are unchanged.
3. **Gestures** — the four thesis gestures and their haptic + TTS confirmation
   are unchanged. The `GestureSurface` remains the topmost transparent capture
   layer over the viewport.
4. **TTS / haptics / telemetry / correction flow** — unchanged.
5. **Runtime-state reporting and engine fallback** — unchanged.
6. **Navigation** — the shell's four-tab bottom `NavigationBar` and the pushed
   Logs & Reports route are unchanged. The design source's "remove the bottom
   nav" direction is **overridden** by the current task.
7. **Accessibility contracts** — every interactive control keeps a semantic
   label/role/state/hint and enabled status; the screen must not overflow at
   200% text scale; no color-only meaning; **per-frame detections must not
   become a TalkBack live region** (see §8).
8. **No service/model/engine/camera/TTS/telemetry logic changes.**

---

## 6. Required visual changes

The redesign moves Detection from the current dark, plain composition to the
light, card-based composition, following the Home/Help/Settings pattern:

1. **Light surface scoped to the Detection subtree** via a `Theme(buildHomeTheme())`
   wrapper (the Home/Help/Settings pattern), with dark status-bar icons
   (`AnnotatedRegion<SystemUiOverlayStyle>`) on the light surface. The global
   dark theme and shell navigation bar remain unchanged. **The camera viewport
   itself stays dark** (see §7).
2. **A header** consistent with the light language: the header **keeps the
   existing single `Detection Mode` title** (restyled to the light language) —
   the target's two-line `DETECTION MODE` + `LIVE` treatment is **not adopted**
   (owner override for cross-screen consistency; see §14 item 5). The retained
   status pill and audio mute control are restyled to the light language.
3. **A rounded, dark camera viewport** with the `LIVE CAMERA` label, preserving
   the existing `FittedBox` + `CustomPaint` + `GestureSurface` stack and the
   `applyBoxFit` overlay math.
4. **Token-consistent restyle of the existing widgets** — `StatusPill`,
   `WarningBanner`, `DetectionCard`, `PriorityBadge`, `AccessibleButton`, and
   the gesture hint — replacing hardcoded literals with the existing tokens
   (`kStatus*`, `kWarningRed`, `kMediumAmber`, `kLowGreen`, `kOverlayBlack`,
   `kDetectionPalette`, `kSpace*`, `kRadius*`) where they already exist.
5. **A bottom action region** consistent with the target's two-card treatment,
   **but preserving the existing controls** (see §9 for the Start/Stop/Repeat
   reconciliation).
6. **A detection transcript/overlay treatment** inside the viewport consistent
   with the target, without changing the underlying detection data or the
   bounding-box painter's coordinate math.

---

## 7. Theme reuse vs. generalization (RESOLVED — reuse `buildHomeTheme()` as-is, scoped)

The existing light tokens are **Home-scoped**: `kHome*` in
[`app_colors.dart`](../lib/theme/app_colors.dart:114) and `buildHomeTheme()` in
[`app_home_theme.dart`](../lib/theme/app_home_theme.dart:50). The completed Help
and Settings features already established the precedent of **reusing
`buildHomeTheme()` and the `kHome*` tokens as-is** for a non-Home screen, scoped
to that screen's subtree only.

**Decision (recommended):** Detection reuses `buildHomeTheme()` and the existing
`kHome*`/`kSpace*`/`kRadius*` tokens as-is, scoped to the Detection subtree only.
No rename, no duplication, no new Detection-scoped theme or token, and no
generalization of the light theme into a shared builder. This matches the
established Home/Help/Settings precedent, keeps the change visual-only, and
avoids touching Home/Help/Settings or renaming approved tokens. Any future
generalization into a shared light theme is a separate, explicitly approved task
and is out of scope here.

### 7.1 How a light theme interacts with the live camera preview

This is the key difference from Home/Help/Settings. The camera preview is a
real-time dark surface. The recommended treatment:

- **The light theme applies to the screen chrome** (background, header, cards,
  controls panel), **not to the camera viewport**. The viewport keeps a dark
  surface (`surface-dark` `#0A0A0A`, which is the existing
  [`kHomeInk`](../lib/theme/app_colors.dart:124) token) so the live feed and the
  overlay remain legible.
- **The viewport is a rounded dark card** (radius `kRadius24`) sitting on the
  light background, matching the target's `surface-dark` viewport.
- **The `FittedBox` + `CustomPaint` + `GestureSurface` stack is unchanged**; only
  the surrounding container (rounded clip + dark fill) is added. The overlay math
  is untouched.

### 7.2 Overlay legibility

- **Bounding boxes and labels** are drawn by
  [`BoundingBoxPainter`](../lib/widgets/bounding_box_painter.dart:26) on the dark
  camera surface. The painter's palette and white label text are already
  high-contrast on dark; the redesign must **not** move the overlay onto a light
  surface.
- **The warning banner** ([`warning_banner.dart`](../lib/widgets/warning_banner.dart:4))
  is a high-contrast red surface with white text; it must remain high-contrast
  regardless of the surrounding light chrome.
- **The gesture hint** ([`_GestureHint`](../lib/screens/detection_screen.dart:1135))
  is a semi-transparent black pill with white text over the viewport; it must
  remain legible on the dark viewport.
- **The transcript bar** (target) is a dark charcoal surface with white text
  inside the viewport; if added, it must stay on the dark viewport.

### 7.3 Status-bar icons

The Detection subtree, if given a light surface, must use **dark status-bar
icons** via `AnnotatedRegion<SystemUiOverlayStyle>` (the Home/Help/Settings
pattern). The global dark theme keeps light icons on the other (dark) screens;
this `AnnotatedRegion` is scoped to the Detection subtree only.

### 7.4 Token sufficiency check (RESOLVED)

The light surface (`kHomeSurfaceBase` `#F5F5F5`), card surface
(`kHomeSurfaceCard` `#FFFFFF`), ink (`kHomeInk` `#0A0A0A`), muted ink
(`kHomeInkMuted` `#667085`), cyan accent (`kHomeAccentCyan` `#22C7F2`), cyan
light (`kHomeAccentCyanLight` `#B9EFFF`), and the `kRadius3/14/18/24` radii
already exist. The dark viewport surface reuses `kHomeInk` (`#0A0A0A`), matching
the Settings System Performance card precedent. **No new token is required** for
the core composition.

**New-token decision (RESOLVED — no new tokens):** the target's amber
detection-box color (`#F59E0B`) and the transcript-bar charcoal (`#202022`) are
**not** added to [`app_colors.dart`](../lib/theme/app_colors.dart:1). The
existing token set already covers both needs:

- The amber box treatment is **not adopted** — the painter keeps its existing
  per-class `kDetectionPalette` cycle (see §14 item 2). No amber box token is
  needed.
- The transcript bar is **not added** (see §14 item 3), so no charcoal token is
  needed.
- The existing amber-family tokens (`kMediumAmber` `#F9A825`,
  `kHomeWarningAmber` `#F5B942`) and the dark ink token (`kHomeInk` `#0A0A0A`)
  remain the only amber/dark values in the token layer; none of them equals
  `#F59E0B` or `#202022`, and none is repurposed to stand in for them.

This keeps the change strictly token-consistent and avoids inventing colors that
no adopted design element uses (per the token rule: add a token only when a
value is actually used by UI code).

---

## 8. Accessibility considerations (including the no-live-region rule)

Per [`ui-conventions.md`](ui-conventions.md) and the accessibility rule:

- Every interactive control (status pill, mute button, Start/Stop, Pause/Resume,
  Repeat, Scan, Correct, Report detection, correction sheet controls) must keep a
  semantic label, role, state, hint, and enabled status.
- The screen must remain readable at **200% text scale with no overflow**; the
  layout must scroll or clamp rather than overflow. The current fixed-height
  controls region (`contentHeight` clamped 200–320) is the existing overflow
  mitigation and must be preserved or improved, not removed.
- No color-only meaning: status colors are decorative and the text/semantics
  carry the meaning.
- Decorative icons (mute glyph, gesture-hint icon, card icons) must be excluded
  from the accessibility tree where they duplicate adjacent text.

### 8.1 Preserving the no-live-region rule

The accessibility rule states: *"Do not make per-frame camera detections a
TalkBack live region — EyeCue TTS already announces them. Mark only deliberate
status/fallback/warning changes as live regions."*

Current live regions on Detection:

| Widget | Live region? | Rationale |
|---|---|---|
| [`StatusPill`](../lib/widgets/status_pill.dart:13) | **Yes** (`liveRegion: true`) | Deliberate status change (Detecting/Paused/Stopped). |
| [`WarningBanner`](../lib/widgets/warning_banner.dart:11) | **Yes** (`liveRegion: true`) | Deliberate high-priority warning. |
| [`DetectionStatePanel`](../lib/widgets/detection_state_panel.dart:38) | **Yes** (`liveRegion: true`) | Deliberate runtime/recovery/failure state. |
| [`DetectionCard`](../lib/widgets/detection_card.dart:26) | **No** | Per-frame detection content — correctly not a live region. |
| [`EngineDetectionScreen`](../lib/screens/engine_detection_screen.dart:152) fallback notice | **Yes** (`liveRegion: true`) | Deliberate fallback change. |

**Decision (recommended):** the redesign must **preserve this exact split**. The
restyle must not:
- add `liveRegion: true` to `DetectionCard` or any per-frame detection surface;
- add a live region to the new transcript bar (it updates per frame);
- remove the deliberate live regions from `StatusPill`, `WarningBanner`,
  `DetectionStatePanel`, or the fallback notice.

The existing semantics tests
([`semantics_test.dart`](../test/accessibility/semantics_test.dart:156)) assert
the live-region flags for `StatusPill` and `WarningBanner`; the redesign must
keep those tests passing.

---

## 9. Start/Stop/Repeat reconciliation (RESOLVED — preserve existing controls)

The design source states: *"Only render Pause and Quick Scan as visible action
cards. Do not render Start, Stop, or Repeat buttons."* However, the current task
explicitly requires **preserving existing behavior**, and the current
implementation renders Start/Stop, Pause/Resume, Repeat, Correct, and Scan as
visible `AccessibleButton`s ([`detection_screen.dart`](../lib/screens/detection_screen.dart:1047)).

**Codebase confirmation:** both child screens render the same five-button
`Wrap` — `Stop`/`Start` ([`detection_screen.dart`](../lib/screens/detection_screen.dart:1052),
[`ultralytics_detection_screen.dart`](../lib/screens/ultralytics_detection_screen.dart:640)),
`Resume`/`Pause` ([`detection_screen.dart`](../lib/screens/detection_screen.dart:1059),
[`ultralytics_detection_screen.dart`](../lib/screens/ultralytics_detection_screen.dart:647)),
`Repeat` ([`detection_screen.dart`](../lib/screens/detection_screen.dart:1064),
[`ultralytics_detection_screen.dart`](../lib/screens/ultralytics_detection_screen.dart:652)),
`Correct last announcement` ([`detection_screen.dart`](../lib/screens/detection_screen.dart:1074),
[`ultralytics_detection_screen.dart`](../lib/screens/ultralytics_detection_screen.dart:662)),
and `Scan` ([`detection_screen.dart`](../lib/screens/detection_screen.dart:1083),
[`ultralytics_detection_screen.dart`](../lib/screens/ultralytics_detection_screen.dart:671)).

**Decision (RESOLVED — preserve all controls, restyle visually):** **Preserve the
existing controls.** The design source's "Pause + Quick Scan only" constraint is a
**design-source direction that conflicts with the current task's preservation
requirement**; per the source-of-truth order, the current task instruction wins.
The redesign may **visually restyle** the controls into the target's card
treatment (e.g. a prominent Pause card and a prominent Quick Scan card), but it
must **not remove** Start/Stop, Repeat, or Correct, because:

- Start/Stop is the accessible non-gesture fallback for the two-finger
  double-tap gesture. The accessibility rule
  ([`.roo/rules/rules-frontend/04-accessibility.md`](../.roo/rules/rules-frontend/04-accessibility.md:1))
  requires every interactive control to be usable through TalkBack without
  relying on sight, and the gesture contract must never be the sole interaction —
  removing the visible Start/Stop button would leave the two-finger double-tap as
  the only way to start/stop, which is not a TalkBack-accessible control.
- Repeat is the accessible fallback for the swipe-down gesture (same rule).
- Correct is the accessible entry to the correction flow.

This is a **product decision** (`[product-decision]`) resolved in favour of
preservation: the recommended resolution preserves all controls and applies the
target's visual treatment to them. The design source's constraint is recorded as
**overridden by the current task**, consistent with the navigation override in
§5 and §13.

---

## 10. Spacing-scale reconciliation (RESOLVED — extracted Markdown wins)

| Source | Spacing |
|---|---|
| `design-tokens.png` (visual summary) | `8, 16, 24, 32, 48, 64` |
| `extracted-design-tokens-screenshot.md` (authoritative) | `6, 8, 12, 16, 20, 24` |
| [`app_spacing.dart`](../lib/theme/app_spacing.dart:1) | `1, 2, 3, 4, 6, 8, 10, 12, 14, 16, 18, 20, 24, 32` |

**Decision (recommended):** the extracted Markdown is authoritative over the PNG
(established Home/Settings precedent). Detection uses the existing `kSpace*`
tokens (`kSpace6/8/12/16/20/24`) as logical design values and scales layout
relationships from available constraints. Do **not** copy `32`, `48`, or `64`
from the PNG as new Detection spacing values. The PNG's type sizes are consistent
with the Markdown role mapping and are already reflected in `buildHomeTheme()`.

---

## 11. Responsive-layout considerations

The reference canvas is 390×844 and is a proportional baseline, not a source of
Flutter pixel literals. Follow the Home/Help/Settings responsive pattern
(`SafeArea` + `LayoutBuilder` + bounded/centered width + scrollable body):

- Use the available content width from parent constraints; do not branch on
  device model or hardware type.
- Constrain the content to a bounded/centered width (Home/Help/Settings cap at
  ~480) so cards and text stay readable on wide constraints.
- Preserve the existing fixed-height controls region (or an equivalent
  overflow-safe mechanism) so the camera viewport is never resized by detection
  content — this is the documented fix for the legacy overflow bug.
- Preserve scrolling when the available height is short or text scaling causes
  the content to exceed the viewport; never overflow at 200% text scale.
- The shell's bottom `NavigationBar` remains the navigation surface and reduces
  the available Detection viewport.
- Do not add `OrientationBuilder`, orientation locks, or new platform
  configuration. The extracted token document's portrait-only statement is a
  broader product direction; the current app does not lock orientation, and this
  visual-only task must not introduce an orientation lock or change navigation.

---

## 12. Files and layers that must remain untouched / flagged

### UI-owned candidates (for a later Plan, after approval)

| File | Likely role |
|---|---|
| [`lib/screens/detection_screen.dart`](../lib/screens/detection_screen.dart:48) | Primary redesign target (Custom engine): light `Theme` wrapper, header, dark rounded viewport, restyled controls panel |
| [`lib/screens/ultralytics_detection_screen.dart`](../lib/screens/ultralytics_detection_screen.dart:26) | Primary redesign target (Ultralytics engine): same composition for visual consistency |
| [`lib/screens/engine_detection_screen.dart`](../lib/screens/engine_detection_screen.dart:15) | Fallback-notice restyle only (if needed for light-surface consistency) |
| [`lib/widgets/status_pill.dart`](../lib/widgets/status_pill.dart:5) | Token-consistent restyle (preserve live region) |
| [`lib/widgets/warning_banner.dart`](../lib/widgets/warning_banner.dart:4) | Token-consistent restyle (preserve live region) |
| [`lib/widgets/detection_card.dart`](../lib/widgets/detection_card.dart:11) | Token-consistent restyle (preserve semantics; no live region) |
| [`lib/widgets/priority_badge.dart`](../lib/widgets/priority_badge.dart:9) | Token-consistent restyle |
| [`lib/widgets/accessible_button.dart`](../lib/widgets/accessible_button.dart:8) | Only if a shared-button change is proven necessary; otherwise leave unchanged and use the existing API |
| [`lib/widgets/detection_state_panel.dart`](../lib/widgets/detection_state_panel.dart:12) | Token-consistent restyle (preserve live region) |
| [`lib/widgets/detection_correction_sheet.dart`](../lib/widgets/detection_correction_sheet.dart:8) | Token-consistent restyle (preserve semantics) |
| [`lib/widgets/bounding_box_painter.dart`](../lib/widgets/bounding_box_painter.dart:26) | **Overlay math must not change**; palette sourcing may be reconciled to `kDetectionPalette` (identical 8 colors — see §14 item 2 / §16). The amber box treatment is **not** adopted, so the rendered colors are unchanged. |
| [`lib/widgets/gesture_surface.dart`](../lib/widgets/gesture_surface.dart:11) | **No change** — transparent capture layer |
| [`lib/theme/app_colors.dart`](../lib/theme/app_colors.dart:1) | **No new token** — the amber box (`#F59E0B`) and transcript charcoal (`#202022`) are not adopted (see §7.4 / §14 items 2–3, 7). Existing tokens suffice. |
| [`test/widget_test.dart`](../test/widget_test.dart:12) | Extend with Detection visual/state regression assertions (no new file) |
| [`test/accessibility/semantics_test.dart`](../test/accessibility/semantics_test.dart:119) | Add Detection semantics + 200% text-scale coverage (no new file) |
| [`test/widgets/widgets_test.dart`](../test/widgets/widgets_test.dart:11) | Extend widget-level assertions if a widget's visual contract changes |
| [`docs/architecture.md`](../docs/architecture.md:1) | Doc update (Detection component row / theme section) if a token/theme change lands |
| [`docs/changelog.md`](../docs/changelog.md:1) | Doc update |
| [`docs/implementation-progress.md`](../docs/implementation-progress.md:1) | Doc update |
| [`docs/session-log.md`](../docs/session-log.md:1) | Doc update |
| `.roo/rules/docs/` mirror | Re-copy of root `/docs` after any doc change (per doc-update rule) |

### Files that must remain untouched

- **`lib/models/`** — read-only for UI work.
- **`lib/services/`** — read-only for UI work (camera, inference, engine
  coordinator, assistive controller, TTS, haptics, telemetry, correction,
  gesture, spatial, tracker, scene summary, forensic log).
- **`lib/main.dart`** — only the two pre-approved exceptions (Marionette binding,
  theme consumption) apply; no Detection-related change is expected here.
- **`lib/navigation/app_shell.dart`** — the shell's four-tab `NavigationBar`,
  `IndexedStack`, and Logs & Reports pushed route are unchanged. The Detect page
  construction is in scope only to confirm the `EngineDetectionScreen(...)`
  contract; no navigation, tab, or shell change is allowed.
- **`lib/screens/`** other than the three detection screens — Home, Help,
  Settings, and Logs & Reports are out of scope.
- **`assets/`**, **`pubspec.yaml`** — no asset or dependency change is expected.
- **Camera, inference, engine, TTS, telemetry, correction, gesture, and
  runtime-state behavior** — unchanged.

### Flagged (not a service/model change)

- **`lib/widgets/bounding_box_painter.dart`** — the overlay coordinate math
  (`applyBoxFit`, `_calculateImageRect`, normalized→pixel mapping) is a
  **behavioral contract** and must not change. If the Design-Spec wants the
  target's amber box color, that is a palette/token sourcing change only, and it
  must be flagged explicitly in the Plan. The painter currently hardcodes its own
  `_palette` ([`bounding_box_painter.dart`](../lib/widgets/bounding_box_painter.dart:65))
  that duplicates [`kDetectionPalette`](../lib/theme/app_colors.dart:69); unifying
  them is a token-consistency change, not a visual redesign, and must not alter
  the rendered colors.

---

## 13. Risks and constraints

| Risk / constraint | Impact on Detection redesign | Required handling |
|---|---|---|
| Global theme is dark while references are light. | A direct use of theme surfaces/text will not match the reference. | Scope the light theme to the Detection subtree (Home/Help/Settings pattern); do not change the global theme. |
| The camera viewport is a live dark surface. | A light theme applied over it would break overlay legibility. | Keep the viewport dark (`kHomeInk`/`surface-dark`); apply light chrome only around it. |
| Design source says "remove the bottom nav". | The current task explicitly preserves navigation. | Keep the shell `NavigationBar`; treat the reference content as the Detection content area above it. |
| Design source says "Pause + Quick Scan only". | Removing Start/Stop/Repeat would break the accessible non-gesture fallback. | Preserve all controls; restyle visually (see §9). This is a `[product-decision]`. |
| Per-frame detections must not be a live region. | A new transcript bar or restyled card could accidentally become one. | Preserve the exact live-region split (see §8.1); keep the semantics tests passing. |
| Legacy overflow bug (`BOTTOM OVERFLOWED BY 74/172 PIXELS`). | A new composition could reintroduce overflow. | Preserve the fixed-height controls region (or equivalent) and verify at 200% text scale. |
| Two child screens must stay visually consistent. | Restyling only one engine would create an inconsistent Detect tab. | Apply the same composition to both `DetectionScreen` and `UltralyticsDetectionScreen`. |
| Shared widgets are used elsewhere. | Changing `AccessibleButton`/`StatusPill`/`WarningBanner` defaults could alter other screens. | Prefer additive/token-consistent changes; verify no regression on Home/Help/Settings/Logs & Reports. |
| Bounding-box painter math is a contract. | A palette change could alter rendered colors. | Do not change the coordinate math; flag any palette change explicitly. |
| Token-scope naming. | Detection reuses `kHome*`/`buildHomeTheme()` as-is. | Accepted naming trade-off (established precedent). |
| Doc sync. | Any token/theme or screen change must update root `/docs` and re-copy into `.roo/rules/docs/`. | Follow the doc-update rule in the same change. |

---

## 14. Resolved Open Questions / Decisions

All eight previously-open items are resolved below. Each records the codebase
confirmation (file:line evidence), the chosen decision, and the rationale. The
exact files/lines each item was confirmed against are consolidated in §16.

1. **Start/Stop/Repeat controls — RESOLVED: preserve all controls, restyle
   visually.** Confirmed: both child screens render the same five-button `Wrap` —
   `Stop`/`Start`, `Resume`/`Pause`, `Repeat`, `Correct last announcement`, and
   `Scan` ([`detection_screen.dart`](../lib/screens/detection_screen.dart:1052),
   [`ultralytics_detection_screen.dart`](../lib/screens/ultralytics_detection_screen.dart:640)).
   **Decision:** keep every control; apply the target's card treatment visually.
   **Rationale:** the accessibility rule
   ([`.roo/rules/rules-frontend/04-accessibility.md`](../.roo/rules/rules-frontend/04-accessibility.md:1))
   requires every interactive control to be TalkBack-usable and forbids gestures
   being the sole interaction — Start/Stop is the non-gesture fallback for the
   two-finger double-tap and Repeat is the fallback for swipe-down. The design
   source's "Pause + Quick Scan only" is overridden by the current task's
   preservation requirement (source-of-truth order). See §9.

2. **Amber detection-box color (`#F59E0B`) — RESOLVED: keep the existing
   per-class palette cycle (option a).** Confirmed: [`BoundingBoxPainter`](../lib/widgets/bounding_box_painter.dart:26)
   draws boxes with a per-class palette cycle via `_colorForClass(classId)`
   ([`bounding_box_painter.dart`](../lib/widgets/bounding_box_painter.dart:76))
   over a hardcoded 8-color `_palette`
   ([`bounding_box_painter.dart`](../lib/widgets/bounding_box_painter.dart:65)).
   The painter's input is `List<Detection>`
   ([`bounding_box_painter.dart`](../lib/widgets/bounding_box_painter.dart:27)),
   and [`Detection`](../lib/models/detection.dart:1) carries only
   `classId`/`label`/`confidence`/`box` — **no priority field**. Priority lives on
   [`DetectionInfo`](../lib/models/detection_info.dart:30) (`ObjectPriority`),
   which the painter never receives. **Decision:** keep the palette cycle; do
   **not** adopt a priority-based amber/cyan treatment. **Rationale:** a
   priority-based treatment would require the painter to receive priority data
   (a model/API change to `Detection` or a new painter input), which is outside
   this visual-only task's scope and would change the overlay's rendered colors.
   The palette cycle is already high-contrast on the dark viewport and its
   coordinate math is a behavioral contract (§12). The amber box is a
   design-source detail, not a required behavior.

3. **Transcript bar (`Person ahead · 2.1 m`) — RESOLVED: do not add it.**
   Confirmed: [`DetectionInfo`](../lib/models/detection_info.dart:27) exposes
   `label`, `confidence`, `positionLabel` ("left"/"center"/"right"),
   `proximityLabel` ("near"/"ahead"/"far"), `priority`, and `semanticLabel`
   ([`detection_info.dart`](../lib/models/detection_info.dart:40)) — so the data
   *could* be assembled. [`TtsService`](../lib/services/tts_service.dart:90) does
   expose `lastAnnouncedDetection` (and `lastAnnouncedEngine`), and both screens
   already read it for the correction flow
   ([`detection_screen.dart`](../lib/screens/detection_screen.dart:422),
   [`ultralytics_detection_screen.dart`](../lib/screens/ultralytics_detection_screen.dart:322)).
   **Decision:** do **not** add a transcript bar in this redesign. **Rationale:**
   the existing `DetectionCard` list below the viewport already presents the same
   label/position/proximity information accessibly, and a per-frame transcript
   surface inside the viewport adds a live-region risk (it updates every frame)
   for no new information. If a future task adds it, it must **not** be a live
   region and must reuse `DetectionInfo`/`lastAnnouncedDetection` with **no new
   service** — but that is out of scope here. See §8.1.

4. **`LIVE CAMERA` viewport label — RESOLVED: keep the existing `_GestureHint`
   only; do not add the label.** Confirmed: the Custom screen's `_GestureHint`
   shows `Gestures active on this screen`
   ([`detection_screen.dart`](../lib/screens/detection_screen.dart:1149)) and the
   Ultralytics screen's shows `Gestures active · Ultralytics engine`
   ([`ultralytics_detection_screen.dart`](../lib/screens/ultralytics_detection_screen.dart:727)).
   **Decision:** keep `_GestureHint` (restyled to tokens) and do **not** add a
   separate `LIVE CAMERA` label. **Rationale:** the gesture hint already occupies
   the viewport's inset label position and conveys actionable information; a
   second decorative label would duplicate the viewport's meaning and add a
   decorative element that must be excluded from semantics. Keeping one label
   avoids redundancy and preserves the existing overlay legibility contract (§7.2).

5. **Header title copy — RESOLVED (owner override): keep the existing single
   `Detection Mode` title; do not adopt the two-line `DETECTION MODE` + `LIVE`
   treatment.** Confirmed: both screens currently render a single `Detection Mode`
   title
   ([`detection_screen.dart`](../lib/screens/detection_screen.dart:830),
   [`ultralytics_detection_screen.dart`](../lib/screens/ultralytics_detection_screen.dart:434))
   with a `StatusPill` below it
   ([`detection_screen.dart`](../lib/screens/detection_screen.dart:836),
   [`ultralytics_detection_screen.dart`](../lib/screens/ultralytics_detection_screen.dart:445)).
   The `StatusPill` is a **live region** (`liveRegion: true`,
   [`status_pill.dart`](../lib/widgets/status_pill.dart:15)) and is asserted by
   the semantics tests ([`semantics_test.dart`](../test/accessibility/semantics_test.dart:156)).
   **Decision (`[product-decision]` resolved by the project owner):** keep the
   existing single `Detection Mode` title (restyled to the light language) and
   **do not adopt** the target's two-line `DETECTION MODE` + `LIVE` treatment.
   **Keep the status pill** as its own separate live-region element (unchanged
   from the original decision). **Rationale:** consistency across the other
   screens — Home/Help/Settings use a single screen title, so the Detection
   header should match. The status pill remains a deliberate live region that
   must be preserved (§8.1), so it stays as its own element. The Ultralytics
   screen's performance line and error text remain below the pill.

6. **Audio control treatment — RESOLVED: restyle into the target's pill
   treatment, preserving semantics and toggle behavior.** Confirmed: both screens
   use a circular `IconButton` with a tooltip and a 56×56 minimum size
   ([`detection_screen.dart`](../lib/screens/detection_screen.dart:844),
   [`ultralytics_detection_screen.dart`](../lib/screens/ultralytics_detection_screen.dart:476)),
   toggling `_settings.audioEnabled` via `_toggleAudio`. **Decision:** restyle the
   control into the target's white `AUDIO ON` pill (cyan dot + uppercase label),
   **preserving** the toggle behavior, the tooltip, the enabled/disabled state,
   and a ≥48dp touch target. **Rationale:** the pill matches the target and the
   light language; the semantics/toggle contract is unchanged, so this is a
   visual-only restyle. The pill must expose a semantic label/role/state (e.g.
   "Audio guidance, on/off") and keep the existing tooltip text.

7. **New tokens — RESOLVED: add no new tokens.** Confirmed: the existing token
   set already covers the adopted composition. `kMediumAmber` is `#F9A825`
   ([`app_colors.dart`](../lib/theme/app_colors.dart:33)), `kHomeWarningAmber` is
   `#F5B942` ([`app_colors.dart`](../lib/theme/app_colors.dart:142)), and
   `kHomeInk` is `#0A0A0A` ([`app_colors.dart`](../lib/theme/app_colors.dart:124))
   — **none equals** the target's amber box `#F59E0B` or transcript charcoal
   `#202022`. **Decision:** do **not** add `#F59E0B` or `#202022` to
   [`app_colors.dart`](../lib/theme/app_colors.dart:1). **Rationale:** the amber
   box treatment is not adopted (item 2) and the transcript bar is not added
   (item 3), so neither value is used by any adopted UI element. The token rule
   says to add a token only when a value is actually used by UI code; inventing
   unused tokens would violate it. See §7.4.

8. **Physical-device verification — RESOLVED: a Code-stage step, not an
   Analysis/Design-Spec deliverable.** Confirmed: the verification policy
   ([`.roo/rules/rules-frontend/07-verification.md`](../.roo/rules/rules-frontend/07-verification.md:1))
   requires UI changes to be verified on a **physical Android device** (not an
   emulator or web target), with `flutter analyze` (0 issues) and `flutter test`
   after each change, and no RenderFlex overflows/exceptions in logcat. The
   development workflow ([`docs/development-workflow.md`](development-workflow.md:1))
   places device verification in the implementation/verification phase.
   **Decision:** device verification is performed at the **Code stage**; the
   Analysis and Design-Spec stages do not require a device. **Rationale:** the
   camera viewport and overlay legibility can only be confirmed on-device, so the
   Code stage must run the app on the attached physical device and confirm no
   regressions. Whether a device is attached at implementation time is confirmed
   then, not now.

---

## 15. Deferred / out-of-scope work

The following items are outside this feature and must not enter a later Detection
implementation implicitly:

1. Removing the persistent bottom navigation or switching to two-finger tab
   navigation.
2. Removing Start/Stop/Repeat/Correct controls (see §9).
3. App-launch camera/ML auto-start changes.
4. A shared runtime-owned Preparing/Ready state on Detection.
5. Portrait-lock configuration.
6. Ground-truth-backed accuracy reporting.
7. Camera, inference, engine, TTS, telemetry, correction, model, or service
   changes.
8. Bounding-box coordinate-math changes.
9. Generalizing the light theme into a shared builder (a separate approved task).
10. Home, Help, Settings, or Logs & Reports redesign.

---

## 16. Verification evidence

Every resolution in §14 was confirmed against the actual codebase (read-only).
The exact files/lines are listed below, followed by the shared-widget usage
inventory and the test-coverage gap.

### 16.1 Per-item confirmation sources

| Item | Confirmed against |
|---|---|
| 1. Controls preserved | [`detection_screen.dart`](../lib/screens/detection_screen.dart:1052) (Stop/Start), [`:1059`](../lib/screens/detection_screen.dart:1059) (Resume/Pause), [`:1064`](../lib/screens/detection_screen.dart:1064) (Repeat), [`:1074`](../lib/screens/detection_screen.dart:1074) (Correct), [`:1083`](../lib/screens/detection_screen.dart:1083) (Scan); [`ultralytics_detection_screen.dart`](../lib/screens/ultralytics_detection_screen.dart:640) (same five); accessibility rule [`.roo/rules/rules-frontend/04-accessibility.md`](../.roo/rules/rules-frontend/04-accessibility.md:1) |
| 2. Palette cycle kept | [`bounding_box_painter.dart`](../lib/widgets/bounding_box_painter.dart:65) (`_palette`), [`:76`](../lib/widgets/bounding_box_painter.dart:76) (`_colorForClass`), [`:27`](../lib/widgets/bounding_box_painter.dart:27) (`List<Detection>` input); [`detection.dart`](../lib/models/detection.dart:1) (no priority field); [`detection_info.dart`](../lib/models/detection_info.dart:30) (`ObjectPriority` on `DetectionInfo` only) |
| 3. No transcript bar | [`detection_info.dart`](../lib/models/detection_info.dart:40) (`label`/`confidence`/`positionLabel`/`proximityLabel`/`priority`/`semanticLabel`); [`tts_service.dart`](../lib/services/tts_service.dart:90) (`lastAnnouncedDetection`); [`detection_screen.dart`](../lib/screens/detection_screen.dart:422) and [`ultralytics_detection_screen.dart`](../lib/screens/ultralytics_detection_screen.dart:322) (existing reads) |
| 4. Keep `_GestureHint` | [`detection_screen.dart`](../lib/screens/detection_screen.dart:1149) (`Gestures active on this screen`); [`ultralytics_detection_screen.dart`](../lib/screens/ultralytics_detection_screen.dart:727) (`Gestures active · Ultralytics engine`) |
| 5. Single `Detection Mode` title + pill (owner override) | [`detection_screen.dart`](../lib/screens/detection_screen.dart:830) (title) / [`:836`](../lib/screens/detection_screen.dart:836) (pill); [`ultralytics_detection_screen.dart`](../lib/screens/ultralytics_detection_screen.dart:434) (title) / [`:445`](../lib/screens/ultralytics_detection_screen.dart:445) (pill); [`status_pill.dart`](../lib/widgets/status_pill.dart:15) (`liveRegion: true`); [`semantics_test.dart`](../test/accessibility/semantics_test.dart:156) (live-region assertion). **Owner override:** the target's two-line `DETECTION MODE` + `LIVE` header is **not adopted** — the existing single `Detection Mode` title is kept for cross-screen consistency (Home/Help/Settings use a single screen title). The status pill is preserved as its own live-region element. |
| 6. Audio pill restyle | [`detection_screen.dart`](../lib/screens/detection_screen.dart:844) (`IconButton`, tooltip, 56×56); [`ultralytics_detection_screen.dart`](../lib/screens/ultralytics_detection_screen.dart:476) (same) |
| 7. No new tokens | [`app_colors.dart`](../lib/theme/app_colors.dart:33) (`kMediumAmber` `#F9A825`), [`:142`](../lib/theme/app_colors.dart:142) (`kHomeWarningAmber` `#F5B942`), [`:124`](../lib/theme/app_colors.dart:124) (`kHomeInk` `#0A0A0A`) — none equals `#F59E0B`/`#202022` |
| 8. Device verification at Code stage | [`.roo/rules/rules-frontend/07-verification.md`](../.roo/rules/rules-frontend/07-verification.md:1); [`docs/development-workflow.md`](development-workflow.md:1) |

### 16.2 Shared-widget usage inventory (regression risk)

Every usage site of each Detection widget, found by searching the codebase for
the class name. This determines whether restyling a shared widget risks
regressions on other screens.

| Widget | Usage sites | Other-screen risk |
|---|---|---|
| [`StatusPill`](../lib/widgets/status_pill.dart:5) | [`detection_screen.dart`](../lib/screens/detection_screen.dart:836), [`ultralytics_detection_screen.dart`](../lib/screens/ultralytics_detection_screen.dart:445) | **Detection-only** — no other screen uses it. |
| [`WarningBanner`](../lib/widgets/warning_banner.dart:4) | [`detection_screen.dart`](../lib/screens/detection_screen.dart:1043), [`ultralytics_detection_screen.dart`](../lib/screens/ultralytics_detection_screen.dart:632) | **Detection-only.** |
| [`DetectionCard`](../lib/widgets/detection_card.dart:11) | [`detection_screen.dart`](../lib/screens/detection_screen.dart:1124), [`ultralytics_detection_screen.dart`](../lib/screens/ultralytics_detection_screen.dart:702) | **Detection-only.** |
| [`PriorityBadge`](../lib/widgets/priority_badge.dart:9) | [`detection_card.dart`](../lib/widgets/detection_card.dart:71) (inside `DetectionCard`) | **Detection-only** (reached only via `DetectionCard`). |
| [`AccessibleButton`](../lib/widgets/accessible_button.dart:8) | [`detection_screen.dart`](../lib/screens/detection_screen.dart:903) (permission), [`:910`](../lib/screens/detection_screen.dart:910) (retry), [`:945`](../lib/screens/detection_screen.dart:945) (start), [`:1052`](../lib/screens/detection_screen.dart:1052) (controls); [`ultralytics_detection_screen.dart`](../lib/screens/ultralytics_detection_screen.dart:570), [`:577`](../lib/screens/ultralytics_detection_screen.dart:577), [`:609`](../lib/screens/ultralytics_detection_screen.dart:609), [`:640`](../lib/screens/ultralytics_detection_screen.dart:640); [`engine_detection_screen.dart`](../lib/screens/engine_detection_screen.dart:185) (fallback notice); [`detection_state_panel.dart`](../lib/widgets/detection_state_panel.dart:72) (panel actions); [`detection_correction_sheet.dart`](../lib/widgets/detection_correction_sheet.dart:80) (sheet actions); [`home_screen.dart`](../lib/screens/home_screen.dart:243) (Home CTA); [`logs_reports_screen.dart`](../lib/screens/logs_reports_screen.dart:285) (export buttons) | **SHARED — used by Home and Logs & Reports too.** Changing its defaults risks regressions on those screens; prefer additive/token-consistent changes or leave its API unchanged. |
| [`DetectionStatePanel`](../lib/widgets/detection_state_panel.dart:12) | [`detection_screen.dart`](../lib/screens/detection_screen.dart:863), [`ultralytics_detection_screen.dart`](../lib/screens/ultralytics_detection_screen.dart:497) | **Detection-only.** |
| [`DetectionCorrectionSheet`](../lib/widgets/detection_correction_sheet.dart:8) | [`detection_screen.dart`](../lib/screens/detection_screen.dart:377) (via `showDetectionCorrectionSheet`), [`ultralytics_detection_screen.dart`](../lib/screens/ultralytics_detection_screen.dart:277) (via `showDetectionCorrectionSheet`) | **Detection-only.** |
| [`BoundingBoxPainter`](../lib/widgets/bounding_box_painter.dart:26) | [`detection_screen.dart`](../lib/screens/detection_screen.dart:992) only | **Detection-only** (Custom engine). The Ultralytics screen uses the native overlay, not this painter. |

**Key finding:** `AccessibleButton` is the only Detection widget shared with
non-Detection screens (Home, Logs & Reports, and the engine-fallback notice).
All other Detection widgets are used exclusively by the two detection screens,
so restyling them carries no cross-screen regression risk. Any change to
`AccessibleButton` must be additive/token-consistent and verified against Home
and Logs & Reports.

### 16.3 Painter palette duplication (confirmed)

[`BoundingBoxPainter._palette`](../lib/widgets/bounding_box_painter.dart:65) and
[`kDetectionPalette`](../lib/theme/app_colors.dart:69) are **byte-identical** —
the same eight colors in the same order:

| # | Painter `_palette` | `kDetectionPalette` |
|---|---|---|
| 0 | `0xFF00E676` green | `0xFF00E676` green |
| 1 | `0xFFFF9100` orange | `0xFFFF9100` orange |
| 2 | `0xFF00B0FF` light blue | `0xFF00B0FF` light blue |
| 3 | `0xFFFFD600` yellow | `0xFFFFD600` yellow |
| 4 | `0xFFFF1744` red | `0xFFFF1744` red |
| 5 | `0xFFD500F9` purple | `0xFFD500F9` purple |
| 6 | `0xFF76FF03` lime | `0xFF76FF03` lime |
| 7 | `0xFF00E5FF` cyan | `0xFF00E5FF` cyan |

The painter is used **only** in [`detection_screen.dart`](../lib/screens/detection_screen.dart:992)
(the Custom engine). Unifying the painter's `_palette` with `kDetectionPalette`
is a token-consistency change that renders identical colors; it must not alter
the coordinate math.

### 16.4 Test-coverage gap (confirmed)

| Test file | Detection coverage |
|---|---|
| [`test/widget_test.dart`](../test/widget_test.dart:12) | Home/Settings/Help screen smoke tests only — **no Detection screen test**. |
| [`test/accessibility/semantics_test.dart`](../test/accessibility/semantics_test.dart:119) | Widget-level semantics for `AccessibleButton`, `StatusPill`, `WarningBanner`, and detection cards — **not** the Detection screen. |
| [`test/widgets/widgets_test.dart`](../test/widgets/widgets_test.dart:11) | `PriorityBadge`, `DetectionCard`, `WarningBanner`, `AccessibleButton` in isolation — **not** the Detection screen. |
| [`test/widgets/detection_correction_sheet_test.dart`](../test/widgets/detection_correction_sheet_test.dart:1) | The correction sheet in isolation — **not** the Detection screen. |

**Confirmed gap:** there is **no Detection screen widget test** — a codebase
search for `DetectionScreen`/`UltralyticsDetectionScreen`/`EngineDetectionScreen`
across `test/` returns **zero** results. The redesign should add Detection
screen visual/state regression assertions (extending the existing files, no new
file) and Detection semantics + 200% text-scale coverage, per §12.

### 16.5 `DetectionInfo` fields (confirmed)

[`DetectionInfo`](../lib/models/detection_info.dart:27) exposes exactly:

| Member | Type | Source |
|---|---|---|
| `detection` | `Detection` | constructor |
| `position` | `RelativePosition` (`left`/`center`/`right`) | constructor |
| `priority` | `ObjectPriority` (`high`/`medium`/`low`) | constructor |
| `proximity` | `ProximityBand` (`near`/`medium`/`far`) | constructor |
| `label` | `String` | `detection.label` |
| `confidence` | `double` | `detection.confidence` |
| `positionLabel` | `String` ("left"/"center"/"right") | derived |
| `proximityLabel` | `String` ("near"/"ahead"/"far") | derived |
| `semanticLabel` | `String` | derived |

This confirms the transcript-bar data (label + position + proximity) is
available from `DetectionInfo` without a new service — but the bar is not added
(§14 item 3).

---

## Analysis conclusion

The Detection redesign is feasible as a focused UI change in
[`detection_screen.dart`](../lib/screens/detection_screen.dart:48) and
[`ultralytics_detection_screen.dart`](../lib/screens/ultralytics_detection_screen.dart:26),
with token-consistent restyling of the shared Detection widgets and possible
additions to the UI token layer. The existing camera/inference architecture,
gestures, TTS, haptics, telemetry, correction flow, runtime-state reporting,
engine fallback, and navigation can be preserved without touching services,
models, or navigation architecture.

The three explicitly requested resolutions are recorded:

- **Theme reuse vs. generalization (§7):** reuse `buildHomeTheme()` and the
  `kHome*` tokens **as-is**, scoped to the Detection subtree only. The light
  theme applies to the screen chrome, **not** the camera viewport; the viewport
  stays dark (`kHomeInk`/`surface-dark`) so the live feed and overlay remain
  legible; the subtree uses dark status-bar icons via
  `AnnotatedRegion<SystemUiOverlayStyle>`.
- **Spacing-scale reconciliation (§10):** the extracted token Markdown is
  authoritative over the PNG; Detection uses the existing `kSpace*` tokens and
  does not adopt the PNG's `32/48/64`.
- **No-live-region accessibility rule (§8.1):** the exact live-region split is
  preserved — `StatusPill`, `WarningBanner`, `DetectionStatePanel`, and the
  fallback notice stay live regions; `DetectionCard` and any new per-frame
  transcript surface must **not** become live regions.

All eight previously-open items are now resolved (§14), with the codebase
evidence consolidated in §16. The Design-Spec can proceed from these decisions
without further product input: preserve all controls, keep the painter's palette
cycle, do not add a transcript bar or a `LIVE CAMERA` label, **keep the existing
single `Detection Mode` title (owner override — the target's two-line
`DETECTION MODE` + `LIVE` header is not adopted, for cross-screen consistency)
while keeping the status pill**, restyle the audio control into a pill, add
no new tokens, and perform physical-device verification at the Code stage. The
analysis artifact itself is the only file created in this stage.