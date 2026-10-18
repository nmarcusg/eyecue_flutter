# EyeCue — Detection Screen Visual Redesign: Plan

> **Stage:** Plan only. No application code, tests, assets, `pubspec.yaml`, or
> other project files are changed by this document. This plan is the
> implementation contract for the Code stage.
>
> **Task type:** Visual-only frontend redesign (token-consistent restyle) of the
> Detection Screen. Not a screenshot match, not an architecture change.
>
> **Date:** 2026-09-10
>
> **WS4 retirement notice (2026-10-19):** `InferenceService.useTestImage` and the
> static-image diagnostic path referenced in this plan were removed in WS4. Those
> planning assumptions are retired; the remainder of this plan is point-in-time
> design evidence.
>
> **Source-of-truth order:** current prompt → this plan →
> [`detection-screen-design-spec.md`](detection-screen-design-spec.md:1) →
> [`detection-screen-analysis.md`](detection-screen-analysis.md:1) → general
> `.roo/rules/`.
>
> **Required inputs (both read in full):**
> - [`detection-screen-analysis.md`](detection-screen-analysis.md:1) — source of
>   truth for scope and resolved decisions.
> - [`detection-screen-design-spec.md`](detection-screen-design-spec.md:1) — the
>   visual specification.
>
> **Vision note:** The design references were inspected with a vision-capable
> model (Gemini) during the Analysis and Design-Spec stages; the transcribed
> visual facts live in
> [`detection-screen-analysis.md`](detection-screen-analysis.md:147) §4 and
> [`detection-screen-design-spec.md`](detection-screen-design-spec.md:17). No
> fresh vision pass was required for this Plan stage — every decision below is
> grounded in the two input documents plus direct read-only inspection of the
> referenced source files.

---

## 1. Scope and invariants

**Analysis cross-reference:** [`detection-screen-analysis.md`](detection-screen-analysis.md:19)
(§1 task type), [`detection-screen-analysis.md`](detection-screen-analysis.md:254)
(§5 behavior contract); [`detection-screen-design-spec.md`](detection-screen-design-spec.md:36)
(§1 scope and invariants).

This plan restyles the visual presentation of the two Detection child screens
while preserving all existing content and runtime behavior:

- [`DetectionScreen`](lib/screens/detection_screen.dart:48) (Custom engine)
- [`UltralyticsDetectionScreen`](lib/screens/ultralytics_detection_screen.dart:26) (Ultralytics engine)

Both are wrapped by [`EngineDetectionScreen`](lib/screens/engine_detection_screen.dart:15).

### 1.1 Preserved contracts (must not change)

| Contract | Required behavior |
|---|---|
| Constructors | Both child screens remain constructible with their existing inputs (`settings`, `tts`, `telemetry`, `corrections`, `haptics`, `onRuntimeStateChanged`, `onFailure`). |
| Camera/inference | Persistent isolate, frame-dropping gate ([`_isInferring`](lib/screens/detection_screen.dart:643)), pause/low-power throttle ([`detection_screen.dart`](lib/screens/detection_screen.dart:637)), orientation math ([`BoxTransform`](lib/models/box_transform.dart:1)), and the `applyBoxFit` overlay math ([`bounding_box_painter.dart`](lib/widgets/bounding_box_painter.dart:89)) are unchanged. |
| Gestures | The four thesis gestures and their haptic + TTS confirmation are unchanged. [`GestureSurface`](lib/widgets/gesture_surface.dart:11) remains the topmost transparent capture layer. |
| TTS / haptics / telemetry / correction | Unchanged. |
| Runtime-state reporting and engine fallback | Unchanged. |
| Navigation | The shell's four-tab [`NavigationBar`](lib/navigation/app_shell.dart:139) and the pushed Logs & Reports route are unchanged. |
| Accessibility | Every interactive control keeps a semantic label/role/state/hint and enabled status; no overflow at 200% text scale; no color-only meaning; per-frame detections must not become a TalkBack live region. |
| Services / models | No service/model/engine/camera/TTS/telemetry logic changes. |

### 1.2 Theme decision (reuse, do not generalize)

Detection reuses [`buildHomeTheme()`](lib/theme/app_home_theme.dart:50) and the
existing `kHome*` / `kSpace*` / `kRadius*` tokens **as-is**, scoped to the
Detection subtree only — the precedent already established by Help and Settings
([`detection-screen-analysis.md`](detection-screen-analysis.md:312) §7). No
rename, no duplication, no new Detection-scoped theme, and no generalization of
the light theme into a shared builder.

- Wrap the Detection subtree in `Theme(data: buildHomeTheme(), child: ...)`.
- The global dark [`buildEyeCueTheme()`](lib/theme/app_theme.dart:13) and the
  shell [`NavigationBar`](lib/navigation/app_shell.dart:139) remain unchanged.
- The light surface must not leak into Home, Help, Settings, Logs & Reports, or
  the shell navigation bar.
- The subtree uses dark status-bar icons via
  `AnnotatedRegion<SystemUiOverlayStyle>` (the Home/Help/Settings pattern,
  [`detection-screen-analysis.md`](detection-screen-analysis.md:362) §7.3).
- The camera viewport stays dark ([`kHomeInk`](lib/theme/app_colors.dart:124)
  `#0A0A0A`); the light theme applies to the screen chrome only
  ([`detection-screen-analysis.md`](detection-screen-analysis.md:330) §7.1).

### 1.3 No new tokens

No new token is added to [`app_colors.dart`](lib/theme/app_colors.dart:1). The
target's amber box (`#F59E0B`) and transcript charcoal (`#202022`) are not
adopted ([`detection-screen-analysis.md`](detection-screen-analysis.md:717) §14
item 7; [`detection-screen-design-spec.md`](detection-screen-design-spec.md:117)
§2.4).

---

## 2. Resolved Design-Spec open items

The Design-Spec's §12 open items 2a, 3, 5, 6, and 7 are resolved below into
concrete, file-level steps. Items 2, 4, and 8 remain Code-stage/product
decisions and are carried into §8.

### 2.1 Item 2a — Home `_StatusBadge` extraction: **DO NOT extract**

**Decision:** Keep the standalone `AUDIO ON` pill, built inline in each
detection screen. Do **not** extract
[`_StatusBadge`](lib/screens/home_screen.dart:146) into a public
`lib/widgets/` widget.

**Codebase confirmation (read-only):**
[`_StatusBadge`](lib/screens/home_screen.dart:146) is a private `_`-prefixed
widget colocated in [`home_screen.dart`](lib/screens/home_screen.dart:146). It
is a **non-interactive semantic container** — `Semantics` + `ExcludeSemantics`
with no tap target, no enabled/disabled state, and no tooltip
([`home_screen.dart`](lib/screens/home_screen.dart:162)). Its treatment is a
capsule (`kRadius24`) with a `kSpace8` dot, uppercase `labelMedium` with
`letterSpacing: 0.5`, surface
[`kHomeSurfaceCard96`](lib/theme/app_colors.dart:121), and shadow
[`kHomeShadowSoft`](lib/theme/app_home_theme.dart:18)
([`home_screen.dart`](lib/screens/home_screen.dart:166)).

**Rationale for not extracting:**
1. Extraction adds a new file under `lib/widgets/` and a structural change that
   the Home design-spec explicitly decided against
   ([`detection-screen-design-spec.md`](detection-screen-design-spec.md:209)
   §3.3.1).
2. It requires **adding interaction** (optional `onTap`/`enabled`/`tooltip`/
   semantics) to a status display — a behavioral change beyond a pure restyle.
3. It forces a token reconciliation (`kHomeSurfaceCard96` vs
   `kHomeSurfaceCard`; `kRadius24` vs `kRadius20`) that would change Home's
   rendered output, violating the "do not change visual output" token rule.
4. The standalone pill is sufficient on its own
   ([`detection-screen-design-spec.md`](detection-screen-design-spec.md:271)
   §3.3.1 "Default if extraction is not adopted").

**Consequence:** [`home_screen.dart`](lib/screens/home_screen.dart:1) is **not**
modified by this plan. The `AUDIO ON` pill is implemented inline in both
detection screens (§4.3).

### 2.2 Item 3 — Controls card treatment: **keep the `Wrap`, restyle, preserve all five**

**Decision:** Keep the existing five-button `Wrap` in both screens and restyle
it visually. Do **not** reduce to the target's literal two-card layout.

**Codebase confirmation (read-only):** both screens render the same five-button
`Wrap` ([`detection_screen.dart`](lib/screens/detection_screen.dart:1047),
[`ultralytics_detection_screen.dart`](lib/screens/ultralytics_detection_screen.dart:635)):
`Stop`/`Start` ([`detection_screen.dart`](lib/screens/detection_screen.dart:1052)),
`Resume`/`Pause` ([`detection_screen.dart`](lib/screens/detection_screen.dart:1059)),
`Repeat` ([`detection_screen.dart`](lib/screens/detection_screen.dart:1064)),
`Correct last announcement` ([`detection_screen.dart`](lib/screens/detection_screen.dart:1074)),
and `Scan` ([`detection_screen.dart`](lib/screens/detection_screen.dart:1083)).

**Final treatment:**
- Keep the `Wrap` with `spacing: kSpace8` / `runSpacing: kSpace8` and
  `alignment: WrapAlignment.center`
  ([`detection_screen.dart`](lib/screens/detection_screen.dart:1047)).
- Use the existing [`AccessibleButton`](lib/widgets/accessible_button.dart:8)
  API (`label`, `icon`, `onPressed`, `prominent`) — **no API change** (§2.4).
- Apply `prominent: true` to **Pause/Resume** and **Scan** to give them the
  target's emphasized card treatment; the remaining controls keep the default
  treatment ([`detection-screen-design-spec.md`](detection-screen-design-spec.md:576)
  §6.2).
- **Preserve** the disabled state of Pause/Resume when detection is inactive
  (`onPressed: _detectionActive ? _togglePaused : null`,
  [`detection_screen.dart`](lib/screens/detection_screen.dart:1062)) and the
  conditional Correct button when `corrections != null`
  ([`detection_screen.dart`](lib/screens/detection_screen.dart:1069)).
- The exact two-card proportions (Pause ~39.74%, Quick Scan ~47.95%) **cannot**
  be applied literally with five controls; implement a proportional, wrapping
  card treatment from the 390×844 baseline and confirm on-device
  ([`detection-screen-design-spec.md`](detection-screen-design-spec.md:594)
  §6.2).

### 2.3 Item 5 — Painter palette unification: **DEFER**

**Decision:** Leave [`BoundingBoxPainter._palette`](lib/widgets/bounding_box_painter.dart:65)
as-is in this restyle. Do **not** unify it with
[`kDetectionPalette`](lib/theme/app_colors.dart:69) now.

**Codebase confirmation (read-only):** the painter's `_palette`
([`bounding_box_painter.dart`](lib/widgets/bounding_box_painter.dart:65)) and
[`kDetectionPalette`](lib/theme/app_colors.dart:69) are byte-identical — the
same eight colors in the same order
([`detection-screen-analysis.md`](detection-screen-analysis.md:810) §16.3).

**Rationale for deferring:**
1. Unifying renders **identical colors**, so it produces no visual change — it
   is a token-consistency refactor, not part of this visual redesign.
2. It touches a file whose coordinate math is a **behavioral contract**
   ([`detection-screen-analysis.md`](detection-screen-analysis.md:581) §12);
   deferring keeps the restyle strictly visual and avoids any risk to the
   overlay math.
3. The painter is used only by the Custom engine
   ([`detection_screen.dart`](lib/screens/detection_screen.dart:992)), so
   deferral has no cross-screen impact.

**Consequence:** [`bounding_box_painter.dart`](lib/widgets/bounding_box_painter.dart:1)
is **not** modified by this plan. The palette unification is recorded as
deferred work in §8.

### 2.4 Item 6 — `AccessibleButton`: **NO change** (resolved)

**Decision:** Leave [`AccessibleButton`](lib/widgets/accessible_button.dart:8)
unchanged. The existing `prominent` flag suffices for the target's emphasized
card treatment.

**Codebase confirmation (read-only):**
[`AccessibleButton`](lib/widgets/accessible_button.dart:8) is the **only**
Detection widget shared with non-Detection screens — Home
([`home_screen.dart`](lib/screens/home_screen.dart:243)), Logs & Reports
([`logs_reports_screen.dart`](lib/screens/logs_reports_screen.dart:285)), and
the engine-fallback notice
([`engine_detection_screen.dart`](lib/screens/engine_detection_screen.dart:185))
([`detection-screen-analysis.md`](detection-screen-analysis.md:798) §16.2). Its
`prominent` flag already switches between
`theme.colorScheme.primary` and `theme.colorScheme.surfaceContainerHighest`
([`accessible_button.dart`](lib/widgets/accessible_button.dart:44)).

**Resolved `prominent` rendering under `buildHomeTheme()` (read-only):**
[`buildHomeTheme()`](lib/theme/app_home_theme.dart:50) builds a light
`ColorScheme.fromSeed(seedColor: kHomeAccentCyan, brightness: light)`
([`app_home_theme.dart`](lib/theme/app_home_theme.dart:56)). The seed is
[`kHomeAccentCyan`](lib/theme/app_colors.dart:133) `#22C7F2`, so
`colorScheme.primary` resolves to a cyan-family tone and `onPrimary` to a
contrasting dark tone. `prominent: true` therefore renders a **cyan-filled
button with dark ink** ([`accessible_button.dart`](lib/widgets/accessible_button.dart:44)),
which matches the target's emphasized cyan `QUICK SCAN` card treatment. The
non-prominent default renders `surfaceContainerHighest` with `onSurface`
([`accessible_button.dart`](lib/widgets/accessible_button.dart:46)) — a light
neutral card, matching the target's white `PAUSE` card. The button also enforces
a `Size(64, 56)` minimum and `18/14` padding
([`accessible_button.dart`](lib/widgets/accessible_button.dart:42)), satisfying
the ≥48dp touch target.

**Conclusion:** `prominent` is **sufficient** — no change to the shared widget
is needed. The exact `primary`/`onPrimary` hex values are derived from the
Material 3 seed algorithm and are **Needs Verification** `[inferred-from-codebase]`
until confirmed on-device; the qualitative cyan-fill/dark-ink result is
confirmed by the seed token.

**Rationale:** leaving its API and defaults unchanged avoids cross-screen
regressions on Home and Logs & Reports. The `prominent` flag is sufficient to
emphasize Pause/Resume and Scan (§2.2).

**Consequence:** [`accessible_button.dart`](lib/widgets/accessible_button.dart:1)
is **not** modified by this plan.

### 2.5 Item 7 — Test assertions (extend existing files, no new file)

**Decision:** Add Detection-screen coverage by **extending the existing test
files** — no new test file. The analysis confirms there is currently **no
Detection screen widget test**
([`detection-screen-analysis.md`](detection-screen-analysis.md:832) §16.4).

The exact assertions are specified in §6.

---

## 3. File-level change plan

Every file below traces back to the Design-Spec §9.1 in-scope list or the
analysis §12 UI-owned candidates. No speculative refactors are included.

### 3.1 Files to modify

| # | File | Change | Traces to |
|---|---|---|---|
| 1 | [`lib/screens/detection_screen.dart`](lib/screens/detection_screen.dart:48) | Light `Theme` wrapper + `AnnotatedRegion`; header restyle; dark rounded viewport container; controls-panel restyle; `_GestureHint` token restyle; inline `AUDIO ON` pill | Spec §2, §3, §4, §5.5, §6 |
| 2 | [`lib/screens/ultralytics_detection_screen.dart`](lib/screens/ultralytics_detection_screen.dart:26) | Same composition for visual consistency | Spec §1, §2, §3, §4, §5.5, §6 |
| 3 | [`lib/screens/engine_detection_screen.dart`](lib/screens/engine_detection_screen.dart:15) | Fallback-notice restyle only, if needed for light-surface consistency | Spec §9.1 |
| 4 | [`lib/widgets/status_pill.dart`](lib/widgets/status_pill.dart:5) | Token-consistent restyle (preserve live region) | Spec §5.1 |
| 5 | [`lib/widgets/warning_banner.dart`](lib/widgets/warning_banner.dart:4) | Token-consistent restyle (preserve live region) | Spec §5.2 |
| 6 | [`lib/widgets/detection_card.dart`](lib/widgets/detection_card.dart:11) | Token-consistent restyle (preserve semantics; no live region) | Spec §5.3 |
| 7 | [`lib/widgets/priority_badge.dart`](lib/widgets/priority_badge.dart:9) | Token-consistent restyle | Spec §5.4 |
| 8 | [`lib/widgets/detection_state_panel.dart`](lib/widgets/detection_state_panel.dart:12) | Token-consistent restyle (preserve live region) | Spec §5.8 |
| 9 | [`lib/widgets/detection_correction_sheet.dart`](lib/widgets/detection_correction_sheet.dart:8) | Token-consistent restyle (preserve semantics) | Spec §5.9 |
| 10 | [`test/widget_test.dart`](test/widget_test.dart:12) | Add Detection screen visual/state regression group | Spec §9.1, §12 item 7 |
| 11 | [`test/accessibility/semantics_test.dart`](test/accessibility/semantics_test.dart:119) | Add Detection semantics + 200% text-scale coverage | Spec §9.1, §12 item 7 |
| 12 | [`test/widgets/widgets_test.dart`](test/widgets/widgets_test.dart:11) | Extend only if a widget's visual contract changes | Spec §9.1 |
| 13 | [`docs/architecture.md`](docs/architecture.md:1) | Doc update (Detection component row / theme section) | Doc-update rule |
| 14 | [`docs/changelog.md`](docs/changelog.md:1) | Doc update | Doc-update rule |
| 15 | [`docs/implementation-progress.md`](docs/implementation-progress.md:1) | Doc update | Doc-update rule |
| 16 | [`docs/session-log.md`](docs/session-log.md:1) | Doc update | Doc-update rule |
| 17 | `.roo/rules/docs/` mirror | Re-copy allow-listed files after any root `/docs` change | Doc-update rule |

### 3.2 Files explicitly NOT modified

| File | Reason |
|---|---|
| [`lib/widgets/accessible_button.dart`](lib/widgets/accessible_button.dart:8) | Shared with Home/Logs & Reports; `prominent` suffices (§2.4). |
| [`lib/widgets/bounding_box_painter.dart`](lib/widgets/bounding_box_painter.dart:26) | Palette unification deferred; coordinate math is a contract (§2.3). |
| [`lib/widgets/gesture_surface.dart`](lib/widgets/gesture_surface.dart:11) | Transparent capture layer — no change (Spec §5.11). |
| [`lib/screens/home_screen.dart`](lib/screens/home_screen.dart:1) | `_StatusBadge` extraction not adopted (§2.1). |
| [`lib/theme/app_colors.dart`](lib/theme/app_colors.dart:1) | No new token (§1.3). |
| `lib/models/` | Read-only for UI work. |
| `lib/services/` | Read-only for UI work. |
| [`lib/main.dart`](lib/main.dart:1) | Only the two pre-approved exceptions apply; no Detection change expected. |
| [`lib/navigation/app_shell.dart`](lib/navigation/app_shell.dart:1) | Navigation unchanged. |
| `assets/`, `pubspec.yaml` | No asset or dependency change. |

---

## 4. Implementation steps

Steps are ordered for incremental, verifiable edits. Each step is a single
well-defined outcome. Per the implementation-stage rule, edits are made
incrementally in small chunks — never by rewriting an entire file.

### 4.1 Step 1 — Light theme scoping (both screens)

**Files:** [`detection_screen.dart`](lib/screens/detection_screen.dart:782),
[`ultralytics_detection_screen.dart`](lib/screens/ultralytics_detection_screen.dart:392).

- Wrap the `Scaffold` body in `Theme(data: buildHomeTheme(), child: ...)`.
- Wrap the subtree in `AnnotatedRegion<SystemUiOverlayStyle>` with
  `SystemUiOverlayStyle.dark` (dark status-bar icons on the light surface).
- Import [`app_home_theme.dart`](lib/theme/app_home_theme.dart:1) and
  [`app_colors.dart`](lib/theme/app_colors.dart:1) / `app_spacing.dart` /
  `app_radii.dart` as needed.
- Do **not** change the `Scaffold` → `SafeArea` → `LayoutBuilder` → `Column`
  structure ([`detection_screen.dart`](lib/screens/detection_screen.dart:784)).

### 4.2 Step 2 — Header restyle (both screens)

**Files:** [`detection_screen.dart`](lib/screens/detection_screen.dart:813),
[`ultralytics_detection_screen.dart`](lib/screens/ultralytics_detection_screen.dart:434).

- Keep the single `Detection Mode` title
  ([`detection_screen.dart`](lib/screens/detection_screen.dart:830)); restyle to
  the light `TextTheme` (`titleLarge`, `kHomeInk`) with `FontWeight.w800`
  retained.
- Replace the header padding `EdgeInsets.fromLTRB(16, 8, 8, 8)`
  ([`detection_screen.dart`](lib/screens/detection_screen.dart:822)) with
  `kSpace16` / `kSpace8`.
- Keep the [`StatusPill`](lib/widgets/status_pill.dart:5) as its own live-region
  element ([`detection_screen.dart`](lib/screens/detection_screen.dart:836)).
- Keep the Ultralytics performance line and error text below the pill
  ([`ultralytics_detection_screen.dart`](lib/screens/ultralytics_detection_screen.dart:446)).

### 4.3 Step 3 — Audio control → inline `AUDIO ON` pill (both screens)

**Files:** [`detection_screen.dart`](lib/screens/detection_screen.dart:840),
[`ultralytics_detection_screen.dart`](lib/screens/ultralytics_detection_screen.dart:476).

Replace the circular `IconButton`
([`detection_screen.dart`](lib/screens/detection_screen.dart:844)) with an
inline pill widget (a private `_AudioPill` helper colocated in each screen file,
per the naming convention for screen-only helpers):

- Surface [`kHomeSurfaceCard`](lib/theme/app_colors.dart:118); radius
  [`kRadius20`](lib/theme/app_radii.dart:22); shadow
  [`kHomeShadowSoft`](lib/theme/app_home_theme.dart:18).
- Leading dot: [`kHomeAccentCyan`](lib/theme/app_colors.dart:133) when on,
  [`kHomeInkMuted`](lib/theme/app_colors.dart:127) when off; `kSpace8` diameter.
- Uppercase label `AUDIO ON` / `AUDIO OFF` in
  [`kHomeInk`](lib/theme/app_colors.dart:124), `labelMedium`, `letterSpacing: 0.5`.

**Resolved geometry (recommended, from the 390×844 baseline):** the target's
exact pill metrics were not measurable from the design source, so the plan
adopts the in-codebase Home `_StatusBadge` treatment as the concrete reference
([`home_screen.dart`](lib/screens/home_screen.dart:166)) and scales it
proportionally. Recommended values, all from existing tokens:

| Property | Recommended value | Token / source |
|---|---|---|
| Pill height | `kSpace8` vertical padding + `labelMedium` line box (≈36–40dp) | [`home_screen.dart`](lib/screens/home_screen.dart:167) |
| Horizontal padding | `kSpace16` | [`home_screen.dart`](lib/screens/home_screen.dart:168) |
| Dot diameter | `kSpace8` | [`home_screen.dart`](lib/screens/home_screen.dart:180) |
| Dot-to-label gap | `kSpace8` | [`home_screen.dart`](lib/screens/home_screen.dart:187) |
| Label letter-spacing | `0.5` | [`home_screen.dart`](lib/screens/home_screen.dart:192) |
| Radius | `kRadius20` (this plan's adopted token, §2.1) | [`app_radii.dart`](lib/theme/app_radii.dart:22) |

The pill is wrapped in a ≥48dp touch target
([`kMinTouchWidth`](lib/theme/app_spacing.dart:52) /
[`kMinTouchHeight`](lib/theme/app_spacing.dart:55)) so the visual capsule may be
shorter than the tappable area. **On-device confirmation remains the final
check** — the proportional values are a reasoned starting point, not a measured
match.
- **Preserve** the toggle behavior (`_toggleAudio`,
  [`detection_screen.dart`](lib/screens/detection_screen.dart:425)), the tooltip
  text (`Mute audio guidance` / `Unmute audio guidance`), the enabled/disabled
  state, and a ≥48dp touch target
  ([`kMinTouchWidth`](lib/theme/app_spacing.dart:52) /
  [`kMinTouchHeight`](lib/theme/app_spacing.dart:55)).
- Expose a semantic label/role/state (e.g. "Audio guidance, on/off") and keep
  the existing tooltip text.
- Wrap in `ListenableBuilder(listenable: Listenable.merge([_settings, _tts]))`
  as today ([`detection_screen.dart`](lib/screens/detection_screen.dart:840)).

### 4.4 Step 4 — Dark rounded camera viewport (both screens)

**Files:** [`detection_screen.dart`](lib/screens/detection_screen.dart:957),
[`ultralytics_detection_screen.dart`](lib/screens/ultralytics_detection_screen.dart:506).

- Add a surrounding container: dark fill
  [`kHomeInk`](lib/theme/app_colors.dart:124), radius
  [`kRadius24`](lib/theme/app_radii.dart:34), clipped.
- **Resolved radius decision:** keep [`kRadius24`](lib/theme/app_radii.dart:34).
  The fresh vision pass estimated the target's viewport radius at ~28px
  ([`detection-screen-analysis.md`](detection-screen-analysis.md:164) §4.1), but
  that is a **vision approximation, not an authoritative token value** — it is
  not a measured design token and the analysis's own range (~28–32) is
  non-specific. `kRadius24` is the adopted, existing token
  ([`detection-screen-analysis.md`](detection-screen-analysis.md:340) §7.1) and
  the design-token rule forbids inventing a new value for an unmeasured
  estimate. The 4px difference is within vision-estimate error and is not
  visually material at this scale. Confirm the visual result on-device; if the
  on-device result reads as too tight, that is a **product decision** to revisit
  (and would require adding a token), not a silent change.
- **Preserve the viewport stack exactly**
  ([`detection_screen.dart`](lib/screens/detection_screen.dart:979)):
  `FittedBox` → `CustomPaint`(`BoundingBoxPainter`) → `_GestureHint` →
  [`GestureSurface`](lib/widgets/gesture_surface.dart:11).
- Do **not** change the `applyBoxFit` overlay math
  ([`bounding_box_painter.dart`](lib/widgets/bounding_box_painter.dart:89)).
- Do **not** add a `LIVE CAMERA` label
  ([`detection-screen-analysis.md`](detection-screen-analysis.md:669) §14 item 4).
- The Ultralytics `YOLOView` native overlay is unchanged.

### 4.5 Step 5 — `_GestureHint` token restyle (both screens)

**Files:** [`detection_screen.dart`](lib/screens/detection_screen.dart:1135),
[`ultralytics_detection_screen.dart`](lib/screens/ultralytics_detection_screen.dart:713).

- Replace `Color(0xCC000000)`
  ([`detection_screen.dart`](lib/screens/detection_screen.dart:1144)) with
  [`kOverlayBlack`](lib/theme/app_colors.dart:51).
- Replace radius `20` ([`detection_screen.dart`](lib/screens/detection_screen.dart:1145))
  with [`kRadius20`](lib/theme/app_radii.dart:22).
- Replace padding/margin with `kSpace14` / `kSpace8` / `kSpace10`.
- **Preserve** the white text, the `Colors.white24` border, the position (bottom
  center), and the existing copy.

### 4.6 Step 6 — Controls panel restyle (both screens)

**Files:** [`detection_screen.dart`](lib/screens/detection_screen.dart:1031),
[`ultralytics_detection_screen.dart`](lib/screens/ultralytics_detection_screen.dart:624).

- Replace `theme.colorScheme.surfaceContainerHigh`
  ([`detection_screen.dart`](lib/screens/detection_screen.dart:1034)) with
  [`kHomeSurfaceBase`](lib/theme/app_colors.dart:115).
- Replace padding `EdgeInsets.fromLTRB(12, 8, 12, 12)`
  ([`detection_screen.dart`](lib/screens/detection_screen.dart:1038)) with
  `kSpace12` / `kSpace8`.
- Apply the controls treatment from §2.2 (keep the `Wrap`, `prominent` on
  Pause/Resume and Scan).
- Restyle the gesture-hint text color from `theme.colorScheme.onSurfaceVariant`
  to [`kHomeInkMuted`](lib/theme/app_colors.dart:127)
  ([`detection_screen.dart`](lib/screens/detection_screen.dart:1095)).
- **Preserve** the fixed-height region
  ([`detection_screen.dart`](lib/screens/detection_screen.dart:793)) and the
  internal `ListView` scroll
  ([`detection_screen.dart`](lib/screens/detection_screen.dart:1122)).

### 4.7 Step 7 — Widget token restyle

Apply the token substitutions specified in the Design-Spec §5:

- [`status_pill.dart`](lib/widgets/status_pill.dart:5) — status colors from
  `kStatus*` tokens; radius `kRadius20`; padding `kSpace12`/`kSpace6`; preserve
  `liveRegion: true` and `ExcludeSemantics` (Spec §5.1).
- [`warning_banner.dart`](lib/widgets/warning_banner.dart:4) — `kWarningRed`;
  radius `kRadius12`; padding `kSpace16`/`kSpace14`/`kSpace12`; preserve
  `liveRegion: true` and the white 2px border (Spec §5.2).
- [`detection_card.dart`](lib/widgets/detection_card.dart:11) —
  `kHomeSurfaceCard`; radius `kRadius12`; margins/padding
  `kSpace4`/`kSpace12`/`kSpace14`; highlight border `kWarningRed`; secondary
  text `kHomeInkMuted`; preserve the `Semantics` label and the **absence** of
  `liveRegion` (Spec §5.3).
- [`priority_badge.dart`](lib/widgets/priority_badge.dart:9) — HIGH
  `kWarningRed`, MEDIUM `kMediumAmber`, LOW `kLowGreen`; MEDIUM foreground
  `kOnAmberDark`; radius `kRadius6`; padding
  `kSpace14`/`kSpace10`/`kSpace8`/`kSpace4`; preserve the text labels
  (Spec §5.4).
- [`detection_state_panel.dart`](lib/widgets/detection_state_panel.dart:12) —
  `kHomeSurfaceCard`, `kRadius24`, `kHomeShadowSoft`; padding
  `kSpace24`/`kSpace20`/`kSpace12`/`kSpace8`; preserve `liveRegion: true`
  (Spec §5.8).
- [`detection_correction_sheet.dart`](lib/widgets/detection_correction_sheet.dart:8)
  — `kHomeSurfaceCard`, `kHomeInk`/`kHomeInkMuted`; padding
  `kSpace20`/`kSpace12`/`kSpace16`/`kSpace8`; preserve the `Semantics` label
  and the correction flow (Spec §5.9).

### 4.8 Step 8 — Engine fallback notice (conditional)

**File:** [`engine_detection_screen.dart`](lib/screens/engine_detection_screen.dart:144).

- Restyle [`_buildFallbackNotice`](lib/screens/engine_detection_screen.dart:144)
  only if needed for light-surface consistency.
- **Preserve** `liveRegion: true`
  ([`engine_detection_screen.dart`](lib/screens/engine_detection_screen.dart:152)).

### 4.9 Step 9 — Tests

See §6 for the exact assertions.

### 4.10 Step 10 — Documentation

Per the doc-update rule, update root `/docs` first, then re-copy only the
allow-listed files into `.roo/rules/docs/`:

- [`docs/architecture.md`](docs/architecture.md:1) — Detection component row /
  theme section.
- [`docs/changelog.md`](docs/changelog.md:1).
- [`docs/implementation-progress.md`](docs/implementation-progress.md:1).
- [`docs/session-log.md`](docs/session-log.md:1).

---

## 5. Accessibility requirements

**Analysis cross-reference:** [`detection-screen-analysis.md`](detection-screen-analysis.md:400)
(§8), [`detection-screen-analysis.md`](detection-screen-analysis.md:416) (§8.1);
[`detection-screen-design-spec.md`](detection-screen-design-spec.md:629) (§7).

### 5.1 Preserve the exact live-region split

| Widget | Live region? | Action |
|---|---|---|
| [`StatusPill`](lib/widgets/status_pill.dart:13) | **Yes** | Preserve `liveRegion: true`. |
| [`WarningBanner`](lib/widgets/warning_banner.dart:11) | **Yes** | Preserve `liveRegion: true`. |
| [`DetectionStatePanel`](lib/widgets/detection_state_panel.dart:38) | **Yes** | Preserve `liveRegion: true`. |
| [`DetectionCard`](lib/widgets/detection_card.dart:26) | **No** | Must **not** become a live region. |
| [`EngineDetectionScreen`](lib/screens/engine_detection_screen.dart:152) fallback notice | **Yes** | Preserve `liveRegion: true`. |

The restyle must **not** add `liveRegion: true` to
[`DetectionCard`](lib/widgets/detection_card.dart:11) or any per-frame surface,
and must **not** remove the deliberate live regions.

### 5.2 Semantic labels, roles, states, hints

Every interactive control keeps a semantic label, role, state, hint, and enabled
status ([`detection-screen-design-spec.md`](detection-screen-design-spec.md:665)
§7.2). The new audio pill exposes a label/role/state plus the existing tooltip
(§4.3).

### 5.3 Decorative elements excluded

Decorative icons (mute glyph, gesture-hint icon, card icons, status dot) stay
excluded from the accessibility tree via the existing `ExcludeSemantics`
wrappers ([`detection-screen-design-spec.md`](detection-screen-design-spec.md:683)
§7.3).

### 5.4 200% text scale with no overflow

The screen must remain readable at 200% text scale with no overflow. The
fixed-height controls region (`contentHeight` clamped 200–320,
[`detection_screen.dart`](lib/screens/detection_screen.dart:793)) is preserved
or improved, never removed
([`detection-screen-design-spec.md`](detection-screen-design-spec.md:690) §7.4).

### 5.5 No color-only meaning

Status colors are decorative; text/semantics carry the meaning. The
[`PriorityBadge`](lib/widgets/priority_badge.dart:9) keeps its HIGH/MEDIUM/LOW
text labels ([`detection-screen-design-spec.md`](detection-screen-design-spec.md:698)
§7.5).

---

## 6. Test plan (exact assertions)

**Analysis cross-reference:** [`detection-screen-analysis.md`](detection-screen-analysis.md:832)
(§16.4 test-coverage gap); [`detection-screen-design-spec.md`](detection-screen-design-spec.md:925)
(§12 item 7).

No new test file is created. Coverage is added by extending the existing files.

### 6.1 [`test/widget_test.dart`](test/widget_test.dart:12) — Detection visual/state regression

Add a `group('DetectionScreen', ...)` with a test-mode construction that avoids
camera/platform plugins. Assertions:

1. **Title present:** `find.text('Detection Mode')` finds one widget.
2. **Status pill present:** `find.byType(StatusPill)` finds one widget, and its
   `label` is one of `Stopped` / `Paused` / `Detecting`.
3. **All five controls present:** `find.text('Start')` or `find.text('Stop')`,
   `find.text('Pause')` or `find.text('Resume')`, `find.text('Repeat')`,
   `find.text('Correct last announcement')` (when `corrections != null`), and
   `find.text('Scan')` each find one widget.
4. **Audio pill present:** `find.text('AUDIO ON')` or `find.text('AUDIO OFF')`
   finds one widget.
5. **No overflow at default scale:** pump at the default text scale and assert
   `tester.takeException()` is null.

**Resolved test-mode construction (read-only, file:line evidence):**

`InferenceService.useTestImage` is a `static const bool = false`
([`inference_isolate.dart`](lib/services/inference_isolate.dart:136)) — a
**compile-time constant**, so it cannot be flipped at test runtime. The
`testMode` branch in [`detection_screen.dart`](lib/screens/detection_screen.dart:783)
reads that constant, and `initState` gates camera setup on it
([`detection_screen.dart`](lib/screens/detection_screen.dart:163)): when
`useTestImage` is true it skips `_setupCamera()` and calls
`_inferenceService.runTestImage()` instead. Because the flag is `const false`,
the shipped code path always takes the camera branch.

The screen **cannot** be pumped as-is in a widget test without platform mocks:

1. `initState` unconditionally calls `_inferenceService.initIsolate()`
   ([`detection_screen.dart`](lib/screens/detection_screen.dart:161)), which
   loads the model/labels via `rootBundle` and spawns a real isolate
   ([`inference_isolate.dart`](lib/services/inference_isolate.dart:184)) — not
   available in a plain widget test.
2. With `autoStartDetection` defaulting on, `_setupCamera()` runs
   ([`detection_screen.dart`](lib/screens/detection_screen.dart:167)), calling
   `Permission.camera.status` ([`detection_screen.dart`](lib/screens/detection_screen.dart:196))
   and `availableCameras()` ([`detection_screen.dart`](lib/screens/detection_screen.dart:224))
   — both platform channels.
3. `_startPerformanceLogger()` starts a `Timer.periodic`
   ([`detection_screen.dart`](lib/screens/detection_screen.dart:735)), which
   must be disposed or the test will report a pending timer.

The existing suite has **no** camera/permission/platform mock pattern: a search
of `test/` for `CameraPlatform`, `MethodChannel`, `setMockMethodCallHandler`,
`TestDefaultBinaryMessenger`, `permission_handler`, or `useTestImage` returns
**zero** matches. Existing screen tests avoid plugins entirely by pumping
screens that take only injected services — e.g. `SettingsScreen`
([`widget_test.dart`](test/widget_test.dart:118)) and `LogsReportsScreen`
([`logs_reports_screen_test.dart`](test/screens/logs_reports_screen_test.dart:136))
— and by injecting fakes via constructor (e.g. `_FakeExportService`
([`logs_reports_screen_test.dart`](test/screens/logs_reports_screen_test.dart:20))).

**Conclusion:** pumping the full `DetectionScreen` requires **additional
stubbing** beyond injected service fakes — specifically a `CameraPlatform` mock
and a `permission_handler` channel mock, plus isolate/`rootBundle` handling —
and the suite has no established pattern for these. The recommended approach is
therefore to **not** pump the full screen. Instead:

- Cover the **visual/state contract** by pumping the extracted, plugin-free
  subtrees directly (the inline `_AudioPill`, `StatusPill`, `WarningBanner`,
  `DetectionCard`, `DetectionStatePanel`, and the controls `Wrap` of
  `AccessibleButton`s) — the same pattern the existing widget/semantics tests
  already use ([`semantics_test.dart`](test/accessibility/semantics_test.dart:54)
  `appWithBody`).
- If a full-screen pump is still desired, it must first add a
  `CameraPlatform`/`permission_handler` mock helper — which is **new test
  infrastructure** and should be flagged as such, not assumed to exist.

This is a **conflict with §6.1's original wording** ("pump the Detection screen
in a widget test"): the screen cannot be pumped without new platform mocks, so
the assertions in §6.1 items 1–5 should be applied to the plugin-free subtrees
rather than the whole screen. The 200% text-scale assertion in §6.2 item 4
should likewise target the representative subtree, not the full screen.

### 6.2 [`test/accessibility/semantics_test.dart`](test/accessibility/semantics_test.dart:119) — Detection semantics + 200% text scale

Extend the existing `group('button and status semantics', ...)` and
`group('detection semantics', ...)` groups:

1. **Audio pill semantics:** pump the audio pill and assert it exposes a
   semantic node with a label matching `Audio guidance` and an enabled state
   (mirroring the existing `expectButtonSemantics` helper pattern at
   [`semantics_test.dart`](test/accessibility/semantics_test.dart:121)).
2. **`DetectionCard` is NOT a live region:** pump a `DetectionCard` and assert
   `expectSemanticNode(info.semanticLabel).getSemanticsData().flagsCollection.isLiveRegion`
   is `false` — extending the existing assertion at
   [`semantics_test.dart`](test/accessibility/semantics_test.dart:180).
3. **`StatusPill` / `WarningBanner` remain live regions:** keep the existing
   assertion at [`semantics_test.dart`](test/accessibility/semantics_test.dart:156)
   passing unchanged.
4. **200% text scale, no overflow:** pump the Detection screen (or its
   representative subtree) inside a `MediaQuery` with
   `textScaler: TextScaler.linear(2.0)` and assert `tester.takeException()` is
   null and no `RenderFlex` overflow is reported.

### 6.3 [`test/widgets/widgets_test.dart`](test/widgets/widgets_test.dart:11) — conditional

Extend only if a widget's **visual contract** changes. Token sourcing
(replacing a literal with an existing token of the same value) is **not** a
contract change, so this file is expected to need **no** change. If a widget's
rendered structure changes (e.g. the audio pill replaces the `IconButton`), add
a focused assertion for that widget.

### 6.4 Test gate

- `flutter analyze` → **0 issues**.
- `flutter test` → **passing** (current suite: 133 passing as of 2026-09-09;
  the new Detection assertions extend it).

---

## 7. Verification (Code stage)

**Analysis cross-reference:** [`detection-screen-analysis.md`](detection-screen-analysis.md:730)
(§14 item 8); [`detection-screen-design-spec.md`](detection-screen-design-spec.md:831)
(§11).

Physical-device verification is a **Code-stage step**, not a Plan deliverable.
Per the verification rule
([`.roo/rules/rules-frontend/07-verification.md`](.roo/rules/rules-frontend/07-verification.md:1)):

**Resolved device-availability decision (item 8):** device verification is a
**Code-stage gate that must be satisfied before the change is considered
complete**. If no physical Android device is attached at implementation time,
the Code stage must **flag it explicitly** (state that on-device verification
could not be performed and why) rather than silently skipping the step or
claiming completion. The change may be implemented and statically verified
(`flutter analyze` / `flutter test`) without a device, but it must not be
reported as fully verified until the on-device checks below pass.

- Run the app on the attached **physical Android device** (not an emulator or
  web target) for visual and interactive checks.
- Confirm no regressions in existing functionality and no RenderFlex overflows
  or exceptions in logcat.
- Run `flutter analyze` (0 issues) and `flutter test` after each change.
- Confirm the camera viewport and overlay legibility on-device.
- Confirm the light chrome does not leak into Home, Help, Settings, Logs &
  Reports, or the shell navigation bar.

---

## 8. Open Questions / Needs Verification

The Plan-stage open items have been resolved by direct read-only inspection of
the referenced source files. Resolved values were moved into the sections they
belong to:

| Item | Resolution | Moved to |
|---|---|---|
| Item 2 — Audio pill geometry | Recommended proportional values from the Home `_StatusBadge` reference; on-device confirmation is the final check | §4.3 |
| Item 4 — Viewport radius | Keep `kRadius24`; the ~28px vision estimate is not authoritative | §4.4 |
| Item 8 — Device availability | Device verification is a Code-stage gate; flag if no device is attached | §7 |
| Test-mode construction | `useTestImage` is `const false`; the full screen needs new `CameraPlatform`/`permission_handler` mocks — pump plugin-free subtrees instead | §6.1 |
| `AccessibleButton` `prominent` | Sufficient — renders a cyan-filled/dark-ink button under `buildHomeTheme()`; no widget change | §2.4 |

**Genuinely unresolved items (carried forward):**

1. **Deferred — Painter palette unification** `[inferred-from-codebase]` — the
   unification of [`BoundingBoxPainter._palette`](lib/widgets/bounding_box_painter.dart:65)
   with [`kDetectionPalette`](lib/theme/app_colors.dart:69) is **deferred** by
   this plan (§2.3). It renders identical colors and touches a
   behavioral-contract file, so it is out of scope for this visual restyle. It
   remains a candidate for a separate, explicitly approved token-consistency
   task.

2. **Deferred — Home `_StatusBadge` extraction** `[inferred-from-codebase]` —
   extraction into a public `lib/widgets/` widget is **not adopted** by this
   plan (§2.1). If a future task wants a shared interactive status/audio pill,
   it must reconcile the surface (`kHomeSurfaceCard` vs `kHomeSurfaceCard96`)
   and radius (`kRadius20` vs `kRadius24`) and be explicitly approved.

3. **On-device visual confirmation** `[design-verified]` — the audio-pill
   geometry (§4.3), the `kRadius24` viewport radius (§4.4), and the
   `prominent` button rendering (§2.4) are all reasoned from tokens and the
   in-codebase Home reference, but their final visual result is confirmed only
   on a physical Android device. This is the Code-stage gate in §7, not a
   Plan-stage blocker.

---

## Plan conclusion

This plan resolves the Design-Spec's open items 2a, 3, 5, 6, and 7 into
concrete, file-level steps:

- **Item 2a:** do **not** extract the Home `_StatusBadge`; keep the standalone
  `AUDIO ON` pill (§2.1).
- **Item 3:** keep the existing five-button `Wrap`, restyle it, and use the
  `prominent` flag on Pause/Resume and Scan (§2.2).
- **Item 5:** **defer** the painter palette unification (§2.3).
- **Item 6:** make **no** change to `AccessibleButton`; the `prominent` flag
  suffices (§2.4).
- **Item 7:** extend the existing test files with the exact assertions in §6.

Every file listed for modification traces back to the Design-Spec §9.1 in-scope
list or the analysis §12 UI-owned candidates. No speculative refactors are
included.

The Plan-stage open items are now resolved: the audio-pill geometry (§4.3), the
viewport radius (§4.4), the device-availability gate (§7), the test-mode
construction (§6.1), and the `AccessibleButton` `prominent` result (§2.4) are
all answered from direct read-only inspection. Only the two deferred items
(painter palette unification, Home `_StatusBadge` extraction) and the on-device
visual confirmation remain in §8.

**No code, tests, assets, or `pubspec.yaml` changes are made by this stage.**
The next stage is Code, after explicit approval.