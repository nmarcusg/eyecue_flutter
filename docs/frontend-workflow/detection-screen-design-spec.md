# EyeCue — Detection Screen Design Specification

> **Stage:** Design-Spec only. No application code, tests, assets, dependency
> declarations, or navigation behavior are changed by this document.
>
> **Task type:** Visual-only Detection-screen redesign (token-consistent restyle).
> This is a restyle of the existing content, **not** a screenshot match and
> **not** an architecture change.
>
> **Source of truth:** The approved [`detection-screen-analysis.md`](detection-screen-analysis.md:1),
> especially its **Resolved Open Questions / Decisions** section (§14), is the
> source of truth for this specification. The extracted token Markdown
> ([`extracted-design-tokens-screenshot.md`](../design-reference/tokens/extracted-design-tokens-screenshot.md:48))
> is authoritative over the token-summary PNG, as resolved in
> [`detection-screen-analysis.md`](detection-screen-analysis.md:492).
>
> **Vision note:** The design references were inspected with a vision-capable
> model (Gemini) during the Analysis stage; the transcribed visual facts live in
> [`detection-screen-analysis.md`](detection-screen-analysis.md:147) (§4). A
> **fresh Gemini vision pass was subsequently run in this stage** against
> [`detection_screen.png`](../design-reference/screens/detection_screen.png) and
> [`design-tokens.png`](../design-reference/tokens/design-tokens.png); it
> confirmed the design source's visual facts (two-card controls row, dark rounded
> viewport, white `AUDIO ON` pill, cyan/amber bounding boxes, in-viewport
> transcript banner, `LIVE CAMERA` label, two-line `DETECTION MODE` + `LIVE`
> header). The vision pass's color/typography estimates are approximate and are
> **not** authoritative — the extracted token Markdown
> ([`extracted-design-tokens-screenshot.md`](../design-reference/tokens/extracted-design-tokens-screenshot.md:48))
> remains the source of truth for token values. Every visual fact below is
> therefore either (a) transcribed from the analysis file's confirmed facts,
> (b) confirmed against the token files, (c) confirmed by the fresh vision pass,
> or (d) explicitly marked **Needs Verification**.

---

## 1. Scope, invariants, and implementation boundary

**Analysis cross-reference:** [`detection-screen-analysis.md`](detection-screen-analysis.md:19)
(§1 task type), [`detection-screen-analysis.md`](detection-screen-analysis.md:43) (§2 current
structure), and [`detection-screen-analysis.md`](detection-screen-analysis.md:254) (§5 behavior
contract).

This specification defines the visual hierarchy, light-theme scoping, token
usage, component restyle, responsive relationships, and accessibility
expectations for the two Detection child screens:

- [`DetectionScreen`](../lib/screens/detection_screen.dart:48) (Custom engine)
- [`UltralyticsDetectionScreen`](../lib/screens/ultralytics_detection_screen.dart:26) (Ultralytics engine)

Both are wrapped by [`EngineDetectionScreen`](../lib/screens/engine_detection_screen.dart:15),
which owns the [`EngineCoordinator`](../lib/services/engine_coordinator.dart:14) and the
temporary-fallback notice ([`_buildFallbackNotice`](../lib/screens/engine_detection_screen.dart:144)).

The implementation must preserve these contracts (from
[`detection-screen-analysis.md`](detection-screen-analysis.md:68) §2.2 and
[`detection-screen-analysis.md`](detection-screen-analysis.md:254) §5):

| Contract | Required behavior |
|---|---|
| [`DetectionScreen`](../lib/screens/detection_screen.dart:48) / [`UltralyticsDetectionScreen`](../lib/screens/ultralytics_detection_screen.dart:26) constructors | Remain constructible with their existing inputs (`settings`, `tts`, `telemetry`, `corrections`, `haptics`, `onRuntimeStateChanged`, `onFailure`). |
| Camera/inference architecture | Persistent isolate, frame-dropping gate ([`_isInferring`](../lib/screens/detection_screen.dart:643)), pause/low-power throttle ([`detection_screen.dart`](../lib/screens/detection_screen.dart:637)), orientation math ([`BoxTransform`](../lib/models/box_transform.dart:1)), and the `applyBoxFit` overlay math ([`bounding_box_painter.dart`](../lib/widgets/bounding_box_painter.dart:89)) are unchanged. |
| Gestures | The four thesis gestures and their haptic + TTS confirmation are unchanged. [`GestureSurface`](../lib/widgets/gesture_surface.dart:11) remains the topmost transparent capture layer over the viewport. |
| TTS / haptics / telemetry / correction flow | Unchanged. |
| Runtime-state reporting and engine fallback | Unchanged. |
| Navigation | The shell's four-tab [`NavigationBar`](../lib/navigation/app_shell.dart:139) and the pushed Logs & Reports route are unchanged. The design source's "remove the bottom nav" direction is **overridden** by the current task. |
| Accessibility contracts | Every interactive control keeps a semantic label/role/state/hint and enabled status; the screen must not overflow at 200% text scale; no color-only meaning; per-frame detections must not become a TalkBack live region (§7). |
| Services / models | No service/model/engine/camera/TTS/telemetry logic changes. |

The primary implementation files are
[`detection_screen.dart`](../lib/screens/detection_screen.dart:48) and
[`ultralytics_detection_screen.dart`](../lib/screens/ultralytics_detection_screen.dart:26),
with token-consistent restyling of the shared Detection widgets listed in §5.
No new token is added (§4.4).

---

## 2. Light theme scoping

**Analysis cross-reference:** [`detection-screen-analysis.md`](detection-screen-analysis.md:312)
(§7 theme reuse), [`detection-screen-analysis.md`](detection-screen-analysis.md:330) (§7.1
light theme vs. camera), and [`detection-screen-analysis.md`](detection-screen-analysis.md:362)
(§7.3 status-bar icons).

### 2.1 Reuse `buildHomeTheme()` as-is, scoped to the Detection subtree

Detection reuses [`buildHomeTheme()`](../lib/theme/app_home_theme.dart:50) and the existing
`kHome*` / `kSpace*` / `kRadius*` tokens **as-is**, scoped to the Detection subtree
only — the same precedent already established by Help and Settings
([`detection-screen-analysis.md`](detection-screen-analysis.md:312) §7). No rename, no
duplication, no new Detection-scoped theme, and no generalization of the light
theme into a shared builder.

- Wrap the Detection subtree in a `Theme(data: buildHomeTheme(), child: ...)`.
- The global dark [`buildEyeCueTheme()`](../lib/theme/app_theme.dart:13) and the shell
  [`NavigationBar`](../lib/navigation/app_shell.dart:139) remain unchanged.
- The light surface must not leak into Home, Help, Settings, Logs & Reports, or
  the shell navigation bar.

### 2.2 Dark status-bar icons

The Detection subtree, given a light surface, must use **dark status-bar icons**
via `AnnotatedRegion<SystemUiOverlayStyle>` (the Home/Help/Settings pattern,
[`detection-screen-analysis.md`](detection-screen-analysis.md:362) §7.3). This
`AnnotatedRegion` is scoped to the Detection subtree only; the global dark theme
keeps light icons on the other (dark) screens.

### 2.3 The camera viewport stays dark

The light theme applies to the screen **chrome** (background, header, cards,
controls panel), **not** to the camera viewport
([`detection-screen-analysis.md`](detection-screen-analysis.md:330) §7.1). The viewport
keeps a dark surface — `surface-dark` `#0A0A0A`, which is the existing
[`kHomeInk`](../lib/theme/app_colors.dart:124) token — so the live feed and the
overlay remain legible. This matches the Settings System Performance card
precedent.

### 2.4 Token sufficiency (no new tokens)

**Analysis cross-reference:** [`detection-screen-analysis.md`](detection-screen-analysis.md:369)
(§7.4) and [`detection-screen-analysis.md`](detection-screen-analysis.md:717) (§14 item 7).

The light surface ([`kHomeSurfaceBase`](../lib/theme/app_colors.dart:115) `#F5F5F5`), card
surface ([`kHomeSurfaceCard`](../lib/theme/app_colors.dart:118) `#FFFFFF`), ink
([`kHomeInk`](../lib/theme/app_colors.dart:124) `#0A0A0A`), muted ink
([`kHomeInkMuted`](../lib/theme/app_colors.dart:127) `#667085`), cyan accent
([`kHomeAccentCyan`](../lib/theme/app_colors.dart:133) `#22C7F2`), cyan light
([`kHomeAccentCyanLight`](../lib/theme/app_colors.dart:136) `#B9EFFF`), and the
[`kRadius3/14/18/24`](../lib/theme/app_radii.dart:25) radii already exist. **No new
token is required.**

The target's amber detection-box color (`#F59E0B`) and the transcript-bar
charcoal (`#202022`) are **not** added to
[`app_colors.dart`](../lib/theme/app_colors.dart:1) — the amber box treatment is not
adopted (§5.6) and the transcript bar is not added (§5.7), so neither value is
used by any adopted UI element.

---

## 3. Header

**Analysis cross-reference:** [`detection-screen-analysis.md`](detection-screen-analysis.md:682)
(§14 item 5 owner override) and [`detection-screen-analysis.md`](detection-screen-analysis.md:704)
(§14 item 6 audio pill).

### 3.1 Title — keep the existing single `Detection Mode` title

Both screens currently render a single `Detection Mode` title
([`detection_screen.dart`](../lib/screens/detection_screen.dart:830),
[`ultralytics_detection_screen.dart`](../lib/screens/ultralytics_detection_screen.dart:434)).
The target's two-line `DETECTION MODE` + `LIVE` treatment is **not adopted**
(owner override for cross-screen consistency — Home/Help/Settings use a single
screen title; [`detection-screen-analysis.md`](detection-screen-analysis.md:682) §14 item 5).

- Keep the single `Detection Mode` title, restyled to the light language.
- Use the light `TextTheme` from [`buildHomeTheme()`](../lib/theme/app_home_theme.dart:50)
  (`titleLarge`, 24px w600, [`kHomeInk`](../lib/theme/app_colors.dart:124)) with the
  existing `FontWeight.w800` emphasis retained.
- The header padding currently uses `EdgeInsets.fromLTRB(16, 8, 8, 8)`
  ([`detection_screen.dart`](../lib/screens/detection_screen.dart:822)); restyle to the
  token scale ([`kSpace16`](../lib/theme/app_spacing.dart:34) / [`kSpace8`](../lib/theme/app_spacing.dart:22)).

### 3.2 Status pill — retained, live region preserved

The [`StatusPill`](../lib/widgets/status_pill.dart:5) stays as its own separate
live-region element ([`detection-screen-analysis.md`](detection-screen-analysis.md:682)
§14 item 5). It is asserted by the semantics tests
([`semantics_test.dart`](../test/accessibility/semantics_test.dart:156)).

- Keep `liveRegion: true` ([`status_pill.dart`](../lib/widgets/status_pill.dart:15)).
- Keep the existing status labels and colors, sourced from tokens (§5.1).
- The Ultralytics screen's performance line and error text remain below the pill
  ([`ultralytics_detection_screen.dart`](../lib/screens/ultralytics_detection_screen.dart:446)).

### 3.3 Audio control — restyle into the white `AUDIO ON` pill

**Analysis cross-reference:** [`detection-screen-analysis.md`](detection-screen-analysis.md:704)
(§14 item 6).

Both screens currently use a circular `IconButton` with a tooltip and a 56×56
minimum size ([`detection_screen.dart`](../lib/screens/detection_screen.dart:844),
[`ultralytics_detection_screen.dart`](../lib/screens/ultralytics_detection_screen.dart:476)),
toggling `_settings.audioEnabled` via `_toggleAudio`.

Restyle the control into the target's white `AUDIO ON` pill (cyan dot +
uppercase label), **preserving**:

- the toggle behavior ([`_toggleAudio`](../lib/screens/detection_screen.dart:425)),
- the tooltip text (`Mute audio guidance` / `Unmute audio guidance`),
- the enabled/disabled state,
- a ≥48dp touch target ([`kMinTouchWidth`](../lib/theme/app_spacing.dart:52) /
  [`kMinTouchHeight`](../lib/theme/app_spacing.dart:55)).

The pill must expose a semantic label/role/state (e.g. "Audio guidance, on/off")
and keep the existing tooltip text. Pill surface uses
[`kHomeSurfaceCard`](../lib/theme/app_colors.dart:118) with
[`kHomeShadowSoft`](../lib/theme/app_home_theme.dart:18); the dot uses
[`kHomeAccentCyan`](../lib/theme/app_colors.dart:133) when on and
[`kHomeInkMuted`](../lib/theme/app_colors.dart:127) when off; the label uses
[`kHomeInk`](../lib/theme/app_colors.dart:124). Radius
[`kRadius20`](../lib/theme/app_radii.dart:22) (stadium).

> **Confirmed by fresh vision pass** `[design-verified]`: the white `AUDIO ON`
> pill is a capsule with a leading solid cyan dot and an uppercase label, as
> described above. The **exact** pill height, horizontal padding, dot diameter,
> and label letter-spacing remain **Needs Verification** — the vision pass
> confirmed the treatment but not pixel geometry. Implement proportionally from
> the 390×844 baseline and confirm on-device.

#### 3.3.1 Reuse of the Home `READY` status pill — assessed, not reusable as-is

**Question raised:** can the Home screen's `READY` status pill be reused for the
`AUDIO ON` pill instead of building a new pill?

**Finding — the Home `READY` badge is a private, non-interactive widget.**
The Home badge is [`_StatusBadge`](../lib/screens/home_screen.dart:146), a
**private `_`-prefixed widget colocated inside
[`home_screen.dart`](../lib/screens/home_screen.dart:146)** — it is **not** a
public reusable widget in `lib/widgets/`. The Home design-spec §10 explicitly
decided against extracting it: *"The design does not justify a new public
reusable widget. Keep screen-only helpers private to
[`home_screen.dart`](../lib/screens/home_screen.dart:81), following the existing
`_StatusCard` convention."* It is also a **non-interactive semantic container**
([`home_screen.dart`](../lib/screens/home_screen.dart:143)): it renders
`Semantics` + `ExcludeSemantics` with no tap target, no enabled/disabled state,
and no tooltip.

**Visual treatment — close match.** The Home badge's treatment is a capsule
(`kRadius24`) with a leading dot (`kSpace8` diameter), an uppercase label
(`labelMedium`, `letterSpacing: 0.5`), surface
[`kHomeSurfaceCard96`](../lib/theme/app_colors.dart:121), and shadow
[`kHomeShadowSoft`](../lib/theme/app_home_theme.dart:18)
([`home_screen.dart`](../lib/screens/home_screen.dart:166)). This is
**structurally the same treatment** as the target `AUDIO ON` pill (capsule,
leading dot, uppercase label, white surface, soft shadow). The only token
differences are the surface (`kHomeSurfaceCard96` 96% white vs. the spec's
[`kHomeSurfaceCard`](../lib/theme/app_colors.dart:118) opaque white) and the
radius ([`kRadius24`](../lib/theme/app_radii.dart:34) vs. the spec's
[`kRadius20`](../lib/theme/app_radii.dart:22) stadium).

**Decision — cannot be reused as-is; reuse requires extraction + interaction.**
The Home `READY` pill **cannot** be reused as-is for the `AUDIO ON` control,
because:

1. It is **private** to [`home_screen.dart`](../lib/screens/home_screen.dart:146)
   and therefore not importable by the Detection screens. Reuse requires
   **extracting it into a public widget in `lib/widgets/`** — a structural change
   that must be flagged, not silently assumed.
2. It is **non-interactive** (a status display). The audio control needs a tap
   target, an enabled/disabled state, a tooltip, and a TalkBack
   label/role/state. Reuse requires **adding interaction** to the extracted
   widget — a behavioral change beyond a pure restyle.

**Reuse approach (if the Plan stage chooses to extract).** Extraction is
**viable** because the visual treatment already matches. If adopted, the Plan
stage would:

- Extract the badge into a new public widget in `lib/widgets/` (e.g.
  `status_badge.dart`), following the one-public-widget-per-file convention
  ([`.roo/rules/rules-frontend/02-naming-convention.md`](../.roo/rules/rules-frontend/02-naming-convention.md:1)).
- Make it **interactive-capable** (optional `onTap`, `enabled`, `tooltip`,
  semantic label/role/state) while keeping the Home usage non-interactive.
- Update [`home_screen.dart`](../lib/screens/home_screen.dart:146) to consume the
  extracted widget (Home is a UI-owned file, so this is in scope for UI work).
- Reconcile the token differences: the spec's `AUDIO ON` pill uses
  [`kHomeSurfaceCard`](../lib/theme/app_colors.dart:118) and
  [`kRadius20`](../lib/theme/app_radii.dart:22); the Home badge uses
  [`kHomeSurfaceCard96`](../lib/theme/app_colors.dart:121) and
  [`kRadius24`](../lib/theme/app_radii.dart:34). A shared widget must pick one
  treatment; this is a **Plan-stage decision** and is flagged in §12.

**Default if extraction is not adopted.** The standalone `AUDIO ON` pill spec
above (surface [`kHomeSurfaceCard`](../lib/theme/app_colors.dart:118), radius
[`kRadius20`](../lib/theme/app_radii.dart:22)) remains the fallback and is
sufficient on its own. Extraction is an optional consolidation, not a
requirement.

> **Needs Verification** `[inferred-from-codebase]`: whether to extract the Home
> badge into a shared interactive widget or keep the standalone `AUDIO ON` pill
> is a **Plan-stage decision**. Extraction touches
> [`home_screen.dart`](../lib/screens/home_screen.dart:146) (UI-owned, in scope)
> and adds a new file under `lib/widgets/`; it must be explicitly approved rather
> than assumed. The visual treatment match is confirmed from the code, but the
> shared-widget token reconciliation (surface/radius) is unresolved.

---

## 4. Camera viewport

**Analysis cross-reference:** [`detection-screen-analysis.md`](detection-screen-analysis.md:330)
(§7.1), [`detection-screen-analysis.md`](detection-screen-analysis.md:346) (§7.2 overlay
legibility), and [`detection-screen-analysis.md`](detection-screen-analysis.md:669) (§14 item 4).

### 4.1 Rounded dark card

The viewport becomes a rounded dark card (radius
[`kRadius24`](../lib/theme/app_radii.dart:34)) sitting on the light background,
matching the target's `surface-dark` viewport
([`detection-screen-analysis.md`](detection-screen-analysis.md:330) §7.1). The dark fill
uses [`kHomeInk`](../lib/theme/app_colors.dart:124) (`#0A0A0A`).

### 4.2 Preserve the viewport stack unchanged

The existing stack in [`_buildViewport`](../lib/screens/detection_screen.dart:957) is
preserved exactly:

1. `FittedBox`(camera preview) — [`detection_screen.dart`](../lib/screens/detection_screen.dart:979)
2. `CustomPaint`([`BoundingBoxPainter`](../lib/widgets/bounding_box_painter.dart:26)) — [`detection_screen.dart`](../lib/screens/detection_screen.dart:991)
3. `_GestureHint` — [`detection_screen.dart`](../lib/screens/detection_screen.dart:1000)
4. [`GestureSurface`](../lib/widgets/gesture_surface.dart:11) (transparent, topmost) — [`detection_screen.dart`](../lib/screens/detection_screen.dart:1005)

Only the surrounding container (rounded clip + dark fill) is added. The
`applyBoxFit` overlay math ([`bounding_box_painter.dart`](../lib/widgets/bounding_box_painter.dart:89))
is untouched.

The Ultralytics screen's viewport stack
([`ultralytics_detection_screen.dart`](../lib/screens/ultralytics_detection_screen.dart:506))
receives the same rounded dark-card container; its `YOLOView` native overlay is
unchanged.

### 4.3 `LIVE CAMERA` label — not adopted

The target's `LIVE CAMERA` label is **not adopted**
([`detection-screen-analysis.md`](detection-screen-analysis.md:669) §14 item 4). Keep the
existing `_GestureHint` only:

- Custom: `Gestures active on this screen`
  ([`detection_screen.dart`](../lib/screens/detection_screen.dart:1149)).
- Ultralytics: `Gestures active · Ultralytics engine`
  ([`ultralytics_detection_screen.dart`](../lib/screens/ultralytics_detection_screen.dart:727)).

The gesture hint is restyled to tokens (§5.5) but keeps its position (bottom
center, inset) and its legibility on the dark viewport.

### 4.4 Overlay legibility contract

**Analysis cross-reference:** [`detection-screen-analysis.md`](detection-screen-analysis.md:346)
(§7.2).

- Bounding boxes and labels are drawn by
  [`BoundingBoxPainter`](../lib/widgets/bounding_box_painter.dart:26) on the dark camera
  surface. The painter's palette and white label text are already high-contrast
  on dark; the overlay must **not** move onto a light surface.
- The warning banner ([`warning_banner.dart`](../lib/widgets/warning_banner.dart:4)) is a
  high-contrast red surface with white text; it must remain high-contrast
  regardless of the surrounding light chrome.
- The gesture hint ([`_GestureHint`](../lib/screens/detection_screen.dart:1135)) is a
  semi-transparent black pill with white text over the viewport; it must remain
  legible on the dark viewport.

---

## 5. Widget restyle (token-consistent)

**Analysis cross-reference:** [`detection-screen-analysis.md`](detection-screen-analysis.md:280)
(§6 required visual changes) and [`detection-screen-analysis.md`](detection-screen-analysis.md:786)
(§16.2 shared-widget usage inventory).

Each widget below is restyled to reference existing tokens instead of hardcoded
literals. **No new tokens** are introduced (§2.4). The shared-widget usage
inventory ([`detection-screen-analysis.md`](detection-screen-analysis.md:786) §16.2) confirms
that every Detection widget except [`AccessibleButton`](../lib/widgets/accessible_button.dart:8)
is used **only** by the two detection screens, so restyling them carries no
cross-screen regression risk.

### 5.1 `StatusPill`

**File:** [`status_pill.dart`](../lib/widgets/status_pill.dart:5) · **Usage:** Detection-only
([`detection-screen-analysis.md`](detection-screen-analysis.md:794) §16.2).

- Replace the hardcoded status colors passed from the screens
  ([`detection_screen.dart`](../lib/screens/detection_screen.dart:815),
  [`ultralytics_detection_screen.dart`](../lib/screens/ultralytics_detection_screen.dart:418))
  with the existing tokens:
  - Stopped → [`kStatusBlueGrey`](../lib/theme/app_colors.dart:45) (`#455A64`)
  - Paused → [`kStatusAmber`](../lib/theme/app_colors.dart:42) (`#F57F17`)
  - Detecting → [`kStatusGreen`](../lib/theme/app_colors.dart:39) (`#1B5E20`)
  - Loading → [`kStatusBlue`](../lib/theme/app_colors.dart:48) (`#0D47A1`)
- Replace the hardcoded radius `20` ([`status_pill.dart`](../lib/widgets/status_pill.dart:21))
  with [`kRadius20`](../lib/theme/app_radii.dart:22).
- Replace the hardcoded padding `EdgeInsets.symmetric(horizontal: 12, vertical: 6)`
  ([`status_pill.dart`](../lib/widgets/status_pill.dart:18)) with
  [`kSpace12`](../lib/theme/app_spacing.dart:28) / [`kSpace6`](../lib/theme/app_spacing.dart:19).
- **Preserve** `liveRegion: true` ([`status_pill.dart`](../lib/widgets/status_pill.dart:15)),
  the `ExcludeSemantics` on the dot and label, and the white border/text.

### 5.2 `WarningBanner`

**File:** [`warning_banner.dart`](../lib/widgets/warning_banner.dart:4) · **Usage:** Detection-only
([`detection-screen-analysis.md`](detection-screen-analysis.md:795) §16.2).

- Replace the hardcoded `Color(0xFFB71C1C)` ([`warning_banner.dart`](../lib/widgets/warning_banner.dart:20))
  with [`kWarningRed`](../lib/theme/app_colors.dart:30).
- Replace the hardcoded radius `12` ([`warning_banner.dart`](../lib/widgets/warning_banner.dart:21))
  with [`kRadius12`](../lib/theme/app_radii.dart:16).
- Replace the hardcoded padding/margins with
  [`kSpace16`](../lib/theme/app_spacing.dart:34) / [`kSpace14`](../lib/theme/app_spacing.dart:31) /
  [`kSpace12`](../lib/theme/app_spacing.dart:28).
- **Preserve** `liveRegion: true` ([`warning_banner.dart`](../lib/widgets/warning_banner.dart:13)),
  the white 2px border, the white text, and the `ExcludeSemantics` on the icon
  and text. The banner must remain high-contrast regardless of the light chrome
  (§4.4).

### 5.3 `DetectionCard`

**File:** [`detection_card.dart`](../lib/widgets/detection_card.dart:11) · **Usage:** Detection-only
([`detection-screen-analysis.md`](detection-screen-analysis.md:796) §16.2).

- Replace `theme.colorScheme.surface` ([`detection_card.dart`](../lib/widgets/detection_card.dart:33))
  with [`kHomeSurfaceCard`](../lib/theme/app_colors.dart:118) so the card reads as a
  light card on the light chrome.
- Replace the hardcoded radius `12` ([`detection_card.dart`](../lib/widgets/detection_card.dart:34))
  with [`kRadius12`](../lib/theme/app_radii.dart:16).
- Replace the hardcoded margins/padding with
  [`kSpace4`](../lib/theme/app_spacing.dart:16) / [`kSpace12`](../lib/theme/app_spacing.dart:28) /
  [`kSpace14`](../lib/theme/app_spacing.dart:31).
- Replace the highlight border color (`theme.colorScheme.error`) with
  [`kWarningRed`](../lib/theme/app_colors.dart:30) and the non-highlight border with
  [`kHomeInkMuted`](../lib/theme/app_colors.dart:127) at reduced opacity (or the light
  theme's `outlineVariant`).
- Replace the secondary text color (`theme.colorScheme.onSurfaceVariant`) with
  [`kHomeInkMuted`](../lib/theme/app_colors.dart:127).
- **Preserve** the `Semantics` label (`info.semanticLabel`) and the **absence**
  of `liveRegion` ([`detection_card.dart`](../lib/widgets/detection_card.dart:26)) — this is
  a per-frame detection surface and must **not** become a live region (§7.1).
- **Preserve** the `onReport` `TextButton.icon` and its `Report detection` label.

### 5.4 `PriorityBadge`

**File:** [`priority_badge.dart`](../lib/widgets/priority_badge.dart:9) · **Usage:** Detection-only
(reached via `DetectionCard`, [`detection-screen-analysis.md`](detection-screen-analysis.md:797) §16.2).

- Replace the hardcoded colors ([`priority_badge.dart`](../lib/widgets/priority_badge.dart:18)):
  - HIGH → [`kWarningRed`](../lib/theme/app_colors.dart:30) (`#B71C1C`)
  - MEDIUM → [`kMediumAmber`](../lib/theme/app_colors.dart:33) (`#F9A825`)
  - LOW → [`kLowGreen`](../lib/theme/app_colors.dart:36) (`#1B5E20`)
- Replace the MEDIUM foreground `Color(0xFF1A1A1A)` with
  [`kOnAmberDark`](../lib/theme/app_colors.dart:57).
- Replace the hardcoded radius `6` ([`priority_badge.dart`](../lib/widgets/priority_badge.dart:33))
  with [`kRadius6`](../lib/theme/app_radii.dart:10).
- Replace the hardcoded padding with
  [`kSpace14`](../lib/theme/app_spacing.dart:31) / [`kSpace10`](../lib/theme/app_spacing.dart:25) /
  [`kSpace8`](../lib/theme/app_spacing.dart:22) / [`kSpace4`](../lib/theme/app_spacing.dart:16).
- **Preserve** the HIGH/MEDIUM/LOW text labels (no color-only meaning).

### 5.5 `_GestureHint` (both screens)

**Files:** [`detection_screen.dart`](../lib/screens/detection_screen.dart:1135),
[`ultralytics_detection_screen.dart`](../lib/screens/ultralytics_detection_screen.dart:713).

- Replace the hardcoded `Color(0xCC000000)` ([`detection_screen.dart`](../lib/screens/detection_screen.dart:1144))
  with [`kOverlayBlack`](../lib/theme/app_colors.dart:51).
- Replace the hardcoded radius `20` ([`detection_screen.dart`](../lib/screens/detection_screen.dart:1145))
  with [`kRadius20`](../lib/theme/app_radii.dart:22).
- Replace the hardcoded padding/margin with
  [`kSpace14`](../lib/theme/app_spacing.dart:31) / [`kSpace8`](../lib/theme/app_spacing.dart:22) /
  [`kSpace10`](../lib/theme/app_spacing.dart:25).
- **Preserve** the white text, the `Colors.white24` border, the position (bottom
  center), and the existing copy (§4.3).

### 5.6 `BoundingBoxPainter` — palette sourcing only, no math change

**File:** [`bounding_box_painter.dart`](../lib/widgets/bounding_box_painter.dart:26) · **Usage:** Custom engine only
([`detection-screen-analysis.md`](detection-screen-analysis.md:801) §16.2).

- The painter's hardcoded `_palette` ([`bounding_box_painter.dart`](../lib/widgets/bounding_box_painter.dart:65))
  is **byte-identical** to [`kDetectionPalette`](../lib/theme/app_colors.dart:69)
  ([`detection-screen-analysis.md`](detection-screen-analysis.md:810) §16.3). Unifying them is a
  token-consistency change that renders identical colors.
- The amber box treatment is **not adopted**
  ([`detection-screen-analysis.md`](detection-screen-analysis.md:631) §14 item 2); the painter keeps
  its per-class palette cycle.
- **The coordinate math must not change** — `applyBoxFit`,
  `_calculateImageRect`, and the normalized→pixel mapping
  ([`bounding_box_painter.dart`](../lib/widgets/bounding_box_painter.dart:89)) are a behavioral
  contract ([`detection-screen-analysis.md`](detection-screen-analysis.md:581) §12).

> **Needs Verification** `[inferred-from-codebase]`: whether the palette
> unification is included in this restyle or deferred is a Plan-stage decision.
> Either way the rendered colors are unchanged.

### 5.7 Transcript bar — not added

**Analysis cross-reference:** [`detection-screen-analysis.md`](detection-screen-analysis.md:651)
(§14 item 3).

The target's floating transcript bar (`Person ahead · 2.1 m`) is **not added**.
The existing [`DetectionCard`](../lib/widgets/detection_card.dart:11) list below the
viewport already presents the same label/position/proximity information
accessibly, and a per-frame transcript surface inside the viewport adds a
live-region risk for no new information.

### 5.8 `DetectionStatePanel`

**File:** [`detection_state_panel.dart`](../lib/widgets/detection_state_panel.dart:12) · **Usage:** Detection-only
([`detection-screen-analysis.md`](detection-screen-analysis.md:799) §16.2).

- Restyle the `Card` ([`detection_state_panel.dart`](../lib/widgets/detection_state_panel.dart:42))
  to the light language: surface [`kHomeSurfaceCard`](../lib/theme/app_colors.dart:118),
  radius [`kRadius24`](../lib/theme/app_radii.dart:34), shadow
  [`kHomeShadowSoft`](../lib/theme/app_home_theme.dart:18).
- Replace the hardcoded margins/padding with
  [`kSpace24`](../lib/theme/app_spacing.dart:43) / [`kSpace20`](../lib/theme/app_spacing.dart:40) /
  [`kSpace12`](../lib/theme/app_spacing.dart:28) / [`kSpace8`](../lib/theme/app_spacing.dart:22).
- **Preserve** `liveRegion: true` ([`detection_state_panel.dart`](../lib/widgets/detection_state_panel.dart:40)),
  the `ExcludeSemantics` on the icon/title/message, the `_iconFor` mapping, the
  `_defaultMessage` mapping, and the action buttons.

### 5.9 `DetectionCorrectionSheet`

**File:** [`detection_correction_sheet.dart`](../lib/widgets/detection_correction_sheet.dart:8) · **Usage:** Detection-only
([`detection-screen-analysis.md`](detection-screen-analysis.md:800) §16.2).

- Restyle the sheet to the light language: surface
  [`kHomeSurfaceCard`](../lib/theme/app_colors.dart:118), text
  [`kHomeInk`](../lib/theme/app_colors.dart:124) / [`kHomeInkMuted`](../lib/theme/app_colors.dart:127).
- Replace the hardcoded padding with
  [`kSpace20`](../lib/theme/app_spacing.dart:40) / [`kSpace12`](../lib/theme/app_spacing.dart:28) /
  [`kSpace16`](../lib/theme/app_spacing.dart:34) / [`kSpace8`](../lib/theme/app_spacing.dart:22).
- **Preserve** the `Semantics` label (`widget.info.semanticLabel`), the
  `ExcludeSemantics` on the detected-label text, the correction flow
  (`_select` / `_complete`), the label search, and the `showDetectionCorrectionSheet`
  entry point ([`detection_correction_sheet.dart`](../lib/widgets/detection_correction_sheet.dart:153)).

### 5.10 `AccessibleButton` — shared, prefer no API change

**File:** [`accessible_button.dart`](../lib/widgets/accessible_button.dart:8) · **Usage:** **SHARED**
([`detection-screen-analysis.md`](detection-screen-analysis.md:798) §16.2).

[`AccessibleButton`](../lib/widgets/accessible_button.dart:8) is the **only** Detection
widget shared with non-Detection screens — Home
([`home_screen.dart`](../lib/screens/home_screen.dart:243)), Logs & Reports
([`logs_reports_screen.dart`](../lib/screens/logs_reports_screen.dart:285)), and the
engine-fallback notice ([`engine_detection_screen.dart`](../lib/screens/engine_detection_screen.dart:185)).

- **Prefer leaving its API unchanged** and using the existing `prominent` flag.
- Any change must be additive/token-consistent and verified against Home and
  Logs & Reports ([`detection-screen-analysis.md`](detection-screen-analysis.md:803) §16.2).
- **Preserve** the `Semantics` (button, label, enabled, hint, onTap) and the
  `ExcludeSemantics` wrapper ([`accessible_button.dart`](../lib/widgets/accessible_button.dart:27)).

### 5.11 `GestureSurface` — no change

**File:** [`gesture_surface.dart`](../lib/widgets/gesture_surface.dart:11) · **Usage:** Detection-only.

No change. It remains the transparent, topmost capture layer over the viewport
([`detection-screen-analysis.md`](detection-screen-analysis.md:550) §12).

---

## 6. Controls

**Analysis cross-reference:** [`detection-screen-analysis.md`](detection-screen-analysis.md:446)
(§9 Start/Stop/Repeat reconciliation) and [`detection-screen-analysis.md`](detection-screen-analysis.md:617)
(§14 item 1).

### 6.1 Preserve all five controls

Both child screens render the same five-button `Wrap`
([`detection_screen.dart`](../lib/screens/detection_screen.dart:1047),
[`ultralytics_detection_screen.dart`](../lib/screens/ultralytics_detection_screen.dart:635)):

| Control | Custom | Ultralytics | Preserve |
|---|---|---|---|
| Stop / Start | [`detection_screen.dart`](../lib/screens/detection_screen.dart:1052) | [`ultralytics_detection_screen.dart`](../lib/screens/ultralytics_detection_screen.dart:640) | Yes |
| Resume / Pause | [`detection_screen.dart`](../lib/screens/detection_screen.dart:1059) | [`ultralytics_detection_screen.dart`](../lib/screens/ultralytics_detection_screen.dart:647) | Yes |
| Repeat | [`detection_screen.dart`](../lib/screens/detection_screen.dart:1064) | [`ultralytics_detection_screen.dart`](../lib/screens/ultralytics_detection_screen.dart:652) | Yes |
| Correct last announcement | [`detection_screen.dart`](../lib/screens/detection_screen.dart:1074) | [`ultralytics_detection_screen.dart`](../lib/screens/ultralytics_detection_screen.dart:662) | Yes |
| Scan | [`detection_screen.dart`](../lib/screens/detection_screen.dart:1083) | [`ultralytics_detection_screen.dart`](../lib/screens/ultralytics_detection_screen.dart:671) | Yes |

The design source's "Pause + Quick Scan only" constraint is **overridden** by
the current task's preservation requirement
([`detection-screen-analysis.md`](detection-screen-analysis.md:466) §9). Start/Stop is the
accessible non-gesture fallback for the two-finger double-tap; Repeat is the
fallback for swipe-down; Correct is the accessible entry to the correction flow.

### 6.2 Visual treatment

The controls may be **visually restyled** into the target's card treatment
(e.g. a prominent Pause card and a prominent Quick Scan card), but they must
**not be removed** ([`detection-screen-analysis.md`](detection-screen-analysis.md:466) §9).

- Keep the existing `Wrap` layout
  ([`detection_screen.dart`](../lib/screens/detection_screen.dart:1047)) with
  [`kSpace8`](../lib/theme/app_spacing.dart:22) spacing/runSpacing.
- Use the existing [`AccessibleButton`](../lib/widgets/accessible_button.dart:8) API
  (`label`, `icon`, `onPressed`, `prominent`) — do not change its API (§5.10).
- The `prominent` flag may be used to give Pause/Resume and Scan the target's
  emphasized card treatment; the remaining controls keep the default treatment.
- **Preserve** the disabled state of Pause/Resume when detection is inactive
  ([`detection_screen.dart`](../lib/screens/detection_screen.dart:1062)) and the
  conditional Correct button when `corrections != null`
  ([`detection_screen.dart`](../lib/screens/detection_screen.dart:1069)).

> **Confirmed by fresh vision pass** `[design-verified]`: the design source's
> controls row is exactly two cards — a white `PAUSE` card (left, with a
> `HOLD 3 SEC` subtitle and a progress track) and a cyan `QUICK SCAN` card
> (right, with a `TAP` subtitle). The extracted token Markdown records the
> proportions as Pause ~39.74% width and Quick Scan ~47.95% width
> ([`extracted-design-tokens-screenshot.md`](../design-reference/tokens/extracted-design-tokens-screenshot.md:119)).
> Because all five controls are preserved, the exact two-card proportions cannot
> be applied literally; implement a proportional, wrapping card treatment from
> the 390×844 baseline and confirm on-device.

### 6.3 Controls panel container

The controls panel currently uses `theme.colorScheme.surfaceContainerHigh`
([`detection_screen.dart`](../lib/screens/detection_screen.dart:1034),
[`ultralytics_detection_screen.dart`](../lib/screens/ultralytics_detection_screen.dart:624)).

- Restyle the panel background to the light surface
  ([`kHomeSurfaceBase`](../lib/theme/app_colors.dart:115)) so it reads as light chrome
  around the dark viewport.
- Replace the hardcoded padding `EdgeInsets.fromLTRB(12, 8, 12, 12)`
  ([`detection_screen.dart`](../lib/screens/detection_screen.dart:1038)) with
  [`kSpace12`](../lib/theme/app_spacing.dart:28) / [`kSpace8`](../lib/theme/app_spacing.dart:22).
- **Preserve** the fixed-height region (§8.3) and the internal `ListView` scroll
  ([`detection_screen.dart`](../lib/screens/detection_screen.dart:1122)).

### 6.4 Gesture hint text

The Custom screen's controls panel ends with a gesture-hint text line
([`detection_screen.dart`](../lib/screens/detection_screen.dart:1091)). Restyle its
color from `theme.colorScheme.onSurfaceVariant` to
[`kHomeInkMuted`](../lib/theme/app_colors.dart:127). The Ultralytics screen does not
render this line ([`ultralytics_detection_screen.dart`](../lib/screens/ultralytics_detection_screen.dart:621)).

---

## 7. Accessibility

**Analysis cross-reference:** [`detection-screen-analysis.md`](detection-screen-analysis.md:400)
(§8 accessibility) and [`detection-screen-analysis.md`](detection-screen-analysis.md:416) (§8.1
no-live-region rule).

### 7.1 Preserve the exact live-region split

The accessibility rule states: *"Do not make per-frame camera detections a
TalkBack live region — EyeCue TTS already announces them. Mark only deliberate
status/fallback/warning changes as live regions."*

| Widget | Live region? | Rationale |
|---|---|---|
| [`StatusPill`](../lib/widgets/status_pill.dart:13) | **Yes** (`liveRegion: true`) | Deliberate status change (Detecting/Paused/Stopped). |
| [`WarningBanner`](../lib/widgets/warning_banner.dart:11) | **Yes** (`liveRegion: true`) | Deliberate high-priority warning. |
| [`DetectionStatePanel`](../lib/widgets/detection_state_panel.dart:38) | **Yes** (`liveRegion: true`) | Deliberate runtime/recovery/failure state. |
| [`DetectionCard`](../lib/widgets/detection_card.dart:26) | **No** | Per-frame detection content — correctly not a live region. |
| [`EngineDetectionScreen`](../lib/screens/engine_detection_screen.dart:152) fallback notice | **Yes** (`liveRegion: true`) | Deliberate fallback change. |

The restyle must **not**:

- add `liveRegion: true` to [`DetectionCard`](../lib/widgets/detection_card.dart:11) or any
  per-frame detection surface;
- add a live region to any new per-frame surface (the transcript bar is not
  added — §5.7);
- remove the deliberate live regions from [`StatusPill`](../lib/widgets/status_pill.dart:5),
  [`WarningBanner`](../lib/widgets/warning_banner.dart:4),
  [`DetectionStatePanel`](../lib/widgets/detection_state_panel.dart:12), or the fallback
  notice.

The existing semantics tests
([`semantics_test.dart`](../test/accessibility/semantics_test.dart:156)) assert the
live-region flags for `StatusPill` and `WarningBanner`; the redesign must keep
those tests passing.

### 7.2 Semantic labels, roles, states, and hints

Every interactive control must keep a semantic label, role, state, hint, and
enabled status ([`detection-screen-analysis.md`](detection-screen-analysis.md:400) §8):

- [`AccessibleButton`](../lib/widgets/accessible_button.dart:8) — `button`, `label`,
  `enabled`, `hint`, `onTap` ([`accessible_button.dart`](../lib/widgets/accessible_button.dart:27)).
- [`StatusPill`](../lib/widgets/status_pill.dart:5) — `label: 'Detection status: $label'`
  ([`status_pill.dart`](../lib/widgets/status_pill.dart:16)).
- [`WarningBanner`](../lib/widgets/warning_banner.dart:4) — `label: 'Warning. $message'`
  ([`warning_banner.dart`](../lib/widgets/warning_banner.dart:14)).
- [`DetectionStatePanel`](../lib/widgets/detection_state_panel.dart:12) — `label: '$title. $message'`
  ([`detection_state_panel.dart`](../lib/widgets/detection_state_panel.dart:41)).
- [`DetectionCard`](../lib/widgets/detection_card.dart:11) — `label: info.semanticLabel`
  ([`detection_card.dart`](../lib/widgets/detection_card.dart:28)).
- The audio pill (§3.3) — a semantic label/role/state (e.g. "Audio guidance,
  on/off") plus the existing tooltip.

### 7.3 Decorative elements excluded from the accessibility tree

Decorative icons (mute glyph, gesture-hint icon, card icons, status dot) must be
excluded from the accessibility tree where they duplicate adjacent text
([`detection-screen-analysis.md`](detection-screen-analysis.md:413) §8). The existing
`ExcludeSemantics` wrappers must be preserved.

### 7.4 200% text scale with no overflow

The screen must remain readable at **200% text scale with no overflow**
([`detection-screen-analysis.md`](detection-screen-analysis.md:407) §8). The layout must
scroll or clamp rather than overflow. The current fixed-height controls region
(`contentHeight` clamped 200–320) is the existing overflow mitigation and must be
preserved or improved, not removed (§8.3).

### 7.5 No color-only meaning

Status colors are decorative; the text/semantics carry the meaning
([`detection-screen-analysis.md`](detection-screen-analysis.md:411) §8). The
[`PriorityBadge`](../lib/widgets/priority_badge.dart:9) keeps its HIGH/MEDIUM/LOW text
labels (§5.4).

---

## 8. Responsive layout

**Analysis cross-reference:** [`detection-screen-analysis.md`](detection-screen-analysis.md:509)
(§11 responsive-layout considerations).

### 8.1 Proportional baseline

The reference canvas is 390×844 and is a proportional baseline, not a source of
Flutter pixel literals. Follow the Home/Help/Settings responsive pattern
(`SafeArea` + `LayoutBuilder` + bounded/centered width + scrollable body).

- Use the available content width from parent constraints; do not branch on
  device model or hardware type.
- Constrain the content to a bounded/centered width (Home/Help/Settings cap at
  ~480) so cards and text stay readable on wide constraints.

### 8.2 Existing layout structure preserved

Both screens already use `Scaffold` → `SafeArea` → `LayoutBuilder` → `Column`
([`detection_screen.dart`](../lib/screens/detection_screen.dart:784),
[`ultralytics_detection_screen.dart`](../lib/screens/ultralytics_detection_screen.dart:392)).
This structure is preserved; only the visual treatment changes.

### 8.3 Fixed-height controls region preserved

The fixed-height controls region
([`detection_screen.dart`](../lib/screens/detection_screen.dart:793),
[`ultralytics_detection_screen.dart`](../lib/screens/ultralytics_detection_screen.dart:396))
is preserved:

```text
contentHeight = (constraints.maxHeight * 0.32).clamp(200.0, 320.0)
```

This is the documented fix for the legacy overflow bug
([`detection-screen-analysis.md`](detection-screen-analysis.md:602) §13). The camera
viewport must never be resized by detection content.

### 8.4 No orientation lock

Do not add `OrientationBuilder`, orientation locks, or new platform
configuration ([`detection-screen-analysis.md`](detection-screen-analysis.md:526) §11). The
extracted token document's portrait-only statement is a broader product
direction; the current app does not lock orientation, and this visual-only task
must not introduce an orientation lock or change navigation.

### 8.5 Shell navigation retained

The shell's bottom [`NavigationBar`](../lib/navigation/app_shell.dart:139) remains the
navigation surface and reduces the available Detection viewport
([`detection-screen-analysis.md`](detection-screen-analysis.md:524) §11). The design
source's "remove the bottom nav" direction is **overridden** by the current task
([`detection-screen-analysis.md`](detection-screen-analysis.md:269) §5 item 6).

---

## 9. Files in scope

**Analysis cross-reference:** [`detection-screen-analysis.md`](detection-screen-analysis.md:533)
(§12 files and layers).

### 9.1 UI-owned files (for a later Plan, after approval)

| File | Role |
|---|---|
| [`lib/screens/detection_screen.dart`](../lib/screens/detection_screen.dart:48) | Primary redesign target (Custom engine): light `Theme` wrapper, header, dark rounded viewport, restyled controls panel. |
| [`lib/screens/ultralytics_detection_screen.dart`](../lib/screens/ultralytics_detection_screen.dart:26) | Primary redesign target (Ultralytics engine): same composition for visual consistency. |
| [`lib/screens/engine_detection_screen.dart`](../lib/screens/engine_detection_screen.dart:15) | Fallback-notice restyle only (if needed for light-surface consistency). |
| [`lib/widgets/status_pill.dart`](../lib/widgets/status_pill.dart:5) | Token-consistent restyle (preserve live region). |
| [`lib/widgets/warning_banner.dart`](../lib/widgets/warning_banner.dart:4) | Token-consistent restyle (preserve live region). |
| [`lib/widgets/detection_card.dart`](../lib/widgets/detection_card.dart:11) | Token-consistent restyle (preserve semantics; no live region). |
| [`lib/widgets/priority_badge.dart`](../lib/widgets/priority_badge.dart:9) | Token-consistent restyle. |
| [`lib/widgets/detection_state_panel.dart`](../lib/widgets/detection_state_panel.dart:12) | Token-consistent restyle (preserve live region). |
| [`lib/widgets/detection_correction_sheet.dart`](../lib/widgets/detection_correction_sheet.dart:8) | Token-consistent restyle (preserve semantics). |
| [`lib/widgets/bounding_box_painter.dart`](../lib/widgets/bounding_box_painter.dart:26) | Palette sourcing only; **overlay math must not change** (§5.6). |
| [`lib/widgets/accessible_button.dart`](../lib/widgets/accessible_button.dart:8) | Only if a shared-button change is proven necessary; otherwise leave unchanged (§5.10). |
| [`lib/widgets/gesture_surface.dart`](../lib/widgets/gesture_surface.dart:11) | **No change** (§5.11). |
| [`lib/theme/app_colors.dart`](../lib/theme/app_colors.dart:1) | **No new token** (§2.4). |
| [`test/widget_test.dart`](../test/widget_test.dart:12) | Extend with Detection visual/state regression assertions (no new file). |
| [`test/accessibility/semantics_test.dart`](../test/accessibility/semantics_test.dart:119) | Add Detection semantics + 200% text-scale coverage (no new file). |
| [`test/widgets/widgets_test.dart`](../test/widgets/widgets_test.dart:11) | Extend widget-level assertions if a widget's visual contract changes. |
| [`docs/architecture.md`](architecture.md:1) | Doc update (Detection component row / theme section) if a token/theme change lands. |
| [`docs/changelog.md`](changelog.md:1) | Doc update. |
| [`docs/implementation-progress.md`](implementation-progress.md:1) | Doc update. |
| [`docs/session-log.md`](session-log.md:1) | Doc update. |
| `.roo/rules/docs/` mirror | Re-copy of root `/docs` after any doc change (per doc-update rule). |

### 9.2 Files that must remain untouched

- **`lib/models/`** — read-only for UI work.
- **`lib/services/`** — read-only for UI work.
- **`lib/main.dart`** — only the two pre-approved exceptions (Marionette binding,
  theme consumption) apply; no Detection-related change is expected here.
- **`lib/navigation/app_shell.dart`** — the shell's four-tab `NavigationBar`,
  `IndexedStack`, and Logs & Reports pushed route are unchanged.
- **`lib/screens/`** other than the three detection screens — Home, Help,
  Settings, and Logs & Reports are out of scope.
- **`assets/`**, **`pubspec.yaml`** — no asset or dependency change is expected.
- **Camera, inference, engine, TTS, telemetry, correction, gesture, and
  runtime-state behavior** — unchanged.

---

## 10. Risks and constraints

**Analysis cross-reference:** [`detection-screen-analysis.md`](detection-screen-analysis.md:593)
(§13 risks and constraints).

| Risk / constraint | Required handling |
|---|---|
| Global theme is dark while references are light. | Scope the light theme to the Detection subtree; do not change the global theme (§2.1). |
| The camera viewport is a live dark surface. | Keep the viewport dark ([`kHomeInk`](../lib/theme/app_colors.dart:124)); apply light chrome only around it (§2.3). |
| Design source says "remove the bottom nav". | Keep the shell [`NavigationBar`](../lib/navigation/app_shell.dart:139) (§8.5). |
| Design source says "Pause + Quick Scan only". | Preserve all controls; restyle visually (§6.1). |
| Per-frame detections must not be a live region. | Preserve the exact live-region split (§7.1); keep the semantics tests passing. |
| Legacy overflow bug. | Preserve the fixed-height controls region and verify at 200% text scale (§8.3). |
| Two child screens must stay visually consistent. | Apply the same composition to both screens (§1). |
| Shared widgets are used elsewhere. | [`AccessibleButton`](../lib/widgets/accessible_button.dart:8) is shared; prefer additive/token-consistent changes and verify Home/Logs & Reports (§5.10). |
| Bounding-box painter math is a contract. | Do not change the coordinate math; flag any palette change explicitly (§5.6). |
| Token-scope naming. | Detection reuses `kHome*`/`buildHomeTheme()` as-is (accepted naming trade-off). |
| Doc sync. | Any token/theme or screen change must update root `/docs` and re-copy into `.roo/rules/docs/`. |

---

## 11. Verification

**Analysis cross-reference:** [`detection-screen-analysis.md`](detection-screen-analysis.md:730)
(§14 item 8).

Physical-device verification is a **Code-stage step**, not a Design-Spec
deliverable ([`detection-screen-analysis.md`](detection-screen-analysis.md:730) §14 item 8).
Per the verification rule
([`.roo/rules/rules-frontend/07-verification.md`](../.roo/rules/rules-frontend/07-verification.md:1)):

- Run the app on the attached **physical Android device** (not an emulator or web
  target) for visual and interactive checks.
- Confirm no regressions in existing functionality and no RenderFlex overflows
  or exceptions in logcat.
- Run `flutter analyze` (0 issues) and `flutter test` after each change.
- Confirm the camera viewport and overlay legibility on-device.

---

## 12. Open Questions / Needs Verification

The following items could not be fully confirmed from the design source, the
analysis file, or the token files in this stage. Each is tagged with its source
of uncertainty per the verification policy.

1. **Vision re-inspection — RESOLVED** `[design-verified]` — a fresh Gemini
   vision pass was run in this stage against
   [`detection_screen.png`](../design-reference/screens/detection_screen.png) and
   [`design-tokens.png`](../design-reference/tokens/design-tokens.png). It
   confirmed the design source's visual facts: a two-card controls row (white
   `PAUSE` + cyan `QUICK SCAN`), a dark rounded camera viewport, a white
   `AUDIO ON` capsule pill with a cyan dot, cyan/amber bounding boxes, an
   in-viewport dark transcript banner with a waveform icon, a `LIVE CAMERA`
   label, and a two-line `DETECTION MODE` + `LIVE` header. The vision pass's
   color and typography estimates are approximate and are **not** authoritative;
   the extracted token Markdown
   ([`extracted-design-tokens-screenshot.md`](../design-reference/tokens/extracted-design-tokens-screenshot.md:48))
   remains the source of truth for token values. No visual fact in this spec was
   contradicted by the vision pass.

2. **Audio pill exact geometry** `[design-verified]` — the white `AUDIO ON` pill's
   **treatment** (capsule, leading cyan dot, uppercase label) is now confirmed by
   the fresh vision pass. Its exact height, horizontal padding, dot diameter, and
   label letter-spacing remain unmeasured. Implement proportionally from the
   390×844 baseline and confirm on-device (§3.3). The Home `READY` badge
   ([`_StatusBadge`](../lib/screens/home_screen.dart:146)) supplies a concrete
   in-codebase reference for the treatment — capsule, `kSpace8` dot, uppercase
   `labelMedium` with `letterSpacing: 0.5`, `kSpace16`/`kSpace8` padding — but its
   surface (`kHomeSurfaceCard96`) and radius (`kRadius24`) differ from this spec's
   `kHomeSurfaceCard` / `kRadius20` (§3.3.1).

2a. **Home `READY` pill reuse for the `AUDIO ON` pill** `[inferred-from-codebase]`
   — the Home `READY` badge **cannot be reused as-is**: it is a **private**
   `_StatusBadge` colocated in [`home_screen.dart`](../lib/screens/home_screen.dart:146)
   (not a public `lib/widgets/` widget) and is **non-interactive** (a status
   display with no tap target, enabled/disabled state, or tooltip). Its visual
   treatment closely matches the target `AUDIO ON` pill, so reuse is **viable only
   after extraction** into a public `lib/widgets/` widget **plus** added
   interaction (optional `onTap`/`enabled`/`tooltip`/semantics). Whether to
   extract-and-share or keep the standalone `AUDIO ON` pill is a **Plan-stage
   decision**; extraction touches [`home_screen.dart`](../lib/screens/home_screen.dart:146)
   (UI-owned, in scope) and adds a new widget file, and must be explicitly
   approved rather than assumed. The shared-widget token reconciliation (surface
   `kHomeSurfaceCard` vs. `kHomeSurfaceCard96`; radius `kRadius20` vs.
   `kRadius24`) is unresolved (§3.3.1).

3. **Controls card treatment proportions** `[design-verified]` — the design
   source's two-card treatment (Pause ~39.74% width, Quick Scan ~47.95% width) is
   confirmed by the fresh vision pass and recorded in the extracted token Markdown
   ([`extracted-design-tokens-screenshot.md`](../design-reference/tokens/extracted-design-tokens-screenshot.md:119)).
   Because all five controls are preserved, the exact two-card proportions cannot
   be applied literally; the final wrapping card treatment is a Plan-stage
   decision (§6.2).

4. **Viewport corner radius** `[design-verified]` — the fresh vision pass
   estimates the target's viewport radius at ~28px, consistent with the analysis's
   ~28–32 range ([`detection-screen-analysis.md`](detection-screen-analysis.md:164) §4.1).
   The adopted token remains [`kRadius24`](../lib/theme/app_radii.dart:34) per the
   resolved decision ([`detection-screen-analysis.md`](detection-screen-analysis.md:340) §7.1);
   the ~28px estimate is a vision approximation, not an authoritative token value.
   Confirm the visual result on-device.

5. **Bounding-box palette unification** `[inferred-from-codebase]` — whether the
   painter's `_palette` is unified with
   [`kDetectionPalette`](../lib/theme/app_colors.dart:69) in this restyle or deferred
   is a Plan-stage decision. Either way the rendered colors are unchanged
   (§5.6).

6. **`AccessibleButton` change necessity** `[inferred-from-codebase]` — whether
   the shared [`AccessibleButton`](../lib/widgets/accessible_button.dart:8) needs any
   change to achieve the target's card treatment, or whether the existing
   `prominent` flag suffices, is a Plan-stage decision. Any change must be
   verified against Home and Logs & Reports (§5.10).

7. **Detection screen test coverage** `[inferred-from-codebase]` — the analysis
   confirms there is currently **no Detection screen widget test**
   ([`detection-screen-analysis.md`](detection-screen-analysis.md:832) §16.4). The
   redesign should add Detection screen visual/state regression assertions and
   Detection semantics + 200% text-scale coverage by extending the existing test
   files (no new file). The exact assertions are a Plan-stage decision.

8. **Physical device availability** `[product-decision]` — whether a physical
   Android device is attached at implementation time is confirmed at the Code
   stage, not now ([`detection-screen-analysis.md`](detection-screen-analysis.md:730)
   §14 item 8).

---

## Design-Spec conclusion

This specification defines a token-consistent visual restyle of the Detection
Screen for both [`DetectionScreen`](../lib/screens/detection_screen.dart:48) and
[`UltralyticsDetectionScreen`](../lib/screens/ultralytics_detection_screen.dart:26),
preserving all existing behavior. It reuses
[`buildHomeTheme()`](../lib/theme/app_home_theme.dart:50) and the `kHome*` tokens
as-is, scoped to the Detection subtree, with the camera viewport kept dark
([`kHomeInk`](../lib/theme/app_colors.dart:124)). It restyles the shared Detection
widgets to reference existing tokens, preserves all five controls, preserves the
exact live-region split, and adds no new tokens. Every section cross-references
the approved [`detection-screen-analysis.md`](detection-screen-analysis.md:1), and
all unconfirmable items are listed in §12.
