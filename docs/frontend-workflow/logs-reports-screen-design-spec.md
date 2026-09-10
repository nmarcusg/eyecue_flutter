# Logs & Reports Screen Design Specification

**Task type:** visual-only, token-consistent restyle of the existing Logs & Reports route. This document is a design specification only. It does not authorize code changes, a new information architecture, a plan, or implementation of behavior.

## 1. Source boundary and design intent

**Analysis cross-reference:** [`logs-reports-screen-analysis.md`](logs-reports-screen-analysis.md:5)

The sole source of truth for the current screen, its composition, its files, and
its behavior is [`logs-reports-screen-analysis.md`](logs-reports-screen-analysis.md:16).
The redesign applies the established light secondary-screen language already
confirmed for Home, Help, and Settings, while retaining the current Logs &
Reports structure and interaction boundaries.

No current Logs & Reports target export exists. The legacy images listed by the
analysis are contextual only and are not a target for this redesign
([`logs_reports_screen.jpg`](../design-reference/old_screen/logs_reports_screen/logs_reports_screen.jpg),
[`logs_reports_screen_charts.jpg`](../design-reference/old_screen/logs_reports_screen/logs_reports_screen_charts.jpg),
and [`logs_reports_screen_logs.jpg`](../design-reference/old_screen/logs_reports_screen/logs_reports_screen_logs.jpg)). Exact pixel composition,
section-specific motif assignment, and screenshot-matched values are therefore
**Needs Verification [design-verified]:** there is no current Logs & Reports
export against which those details can be confirmed.

## 2. Scope, goals, and invariants

**Analysis cross-reference:** [`logs-reports-screen-analysis.md`](logs-reports-screen-analysis.md:7)

### 2.1 In scope

The visual restyle may change:

- route-local surfaces and contrast;
- typography hierarchy using the existing IBM Plex Sans roles;
- spacing and density using the existing token layer;
- card treatment and visual grouping without changing section order;
- Overview, Charts, and Logs tab styling;
- chart surface, line, bar, grid, and empty-state presentation without changing
  chart calculations or data binding;
- visual presentation of export actions, correction records, unavailable
  metrics, and empty states; and
- constraint-based responsive sizing within the existing secondary-screen
  composition.

### 2.2 Invariants

The following are not redesign decisions and must remain unchanged:

- the existing Overview → Charts → Logs composition and section order;
- the pushed-route ownership and existing back-navigation behavior;
- the three tabs and their state updates;
- telemetry data sources, retention, aggregation, formatting, and semantics;
- export writers, schema, contents, busy guard, feedback, and live-region
  behavior;
- chart data binding, dynamic bounds, benchmark-line conditions, allocated
  bounds, and textual summaries;
- correction data source, newest-first ordering, display-only presentation, and
  correction creation flow;
- the Logs empty state, newest-first scrolling list, row content, and priority
  meaning; and
- the existing accessibility labels, states, values, hints, enabled states,
  live regions, chart exclusions, and textual alternatives.

Adding filtering, sorting, date ranges, engine-selection state, pagination,
chart gestures, legends, axis labels, row actions, new telemetry calculations,
correction mutation, or a new export schema is out of scope. These boundaries
are confirmed by the analysis of [`logs_reports_screen.dart`](../lib/screens/logs_reports_screen.dart:16),
[`app_shell.dart`](../lib/navigation/app_shell.dart:77),
[`telemetry_service.dart`](../lib/services/telemetry_service.dart:305),
[`telemetry_export_service.dart`](../lib/services/telemetry_export_service.dart:236),
and [`correction_service.dart`](../lib/services/correction_service.dart:215).

## 3. Route shell and local light theme

**Analysis cross-reference:** [`logs-reports-screen-analysis.md`](logs-reports-screen-analysis.md:132)

### 3.1 Route ownership

Logs & Reports remains a pushed secondary route. The shell's existing
[`openLogsReports()`](../lib/navigation/app_shell.dart:77) behavior, the
underlying four-tab navigation bar, and back navigation remain unchanged. The
redesign must not make Logs & Reports a bottom-navigation destination or alter
the shell beneath the route.

### 3.2 Local theme treatment

The route should use a locally scoped light theme at the root of
[`LogsReportsScreen`](../lib/screens/logs_reports_screen.dart:23), sourced from
the existing [`buildHomeTheme()`](../lib/theme/app_home_theme.dart:50). This is
local reuse of an established builder, not a generalization of theme ownership.
The redesign must not rename or replace the Home theme, create a second light
theme builder, or change the global theme arrangement.

The pushed route should also use the local dark status-bar icon treatment already
used by the light Settings and Help routes. The local scope must end at the
route: it must not recolor or wrap the underlying shell, and popping the route
must leave the other tabs unchanged. The analysis resolves this as the required
theme direction; the exact status-bar transition behavior on every supported
window configuration is **Needs Verification [inferred-from-codebase]** during
later device validation.

### 3.3 Base surface and contrast

Use the established light visual vocabulary:

| Visual role | Existing confirmed token value | Logs & Reports treatment |
|---|---:|---|
| Base surface | `#F5F5F5` | Route background and open breathing space. |
| Card surface | `#FFFFFF` | Default grouped content surface. |
| Primary ink / dark surface | `#0A0A0A` | Primary text and any dark treatment only where semantically appropriate. |
| Muted ink | `#667085` | Secondary descriptions, supporting metadata, and subdued empty-state copy. |
| Subtle ink | `#99A5AA` | Low-emphasis supporting details where the existing theme provides that role. |
| Cyan accent | `#22C7F2` | Selected-state and action emphasis using the existing semantic token. |
| Light cyan rail/surface | `#B9EFFF` | Optional supporting emphasis only when the section role warrants it. |
| Dark cyan | `#087A9E` | Accent contrast where required by the existing token vocabulary. |
| Amber, success, warning, critical, info, disabled | Existing confirmed system tokens | Preserve the meaning of current state and priority feedback. |

The values above are confirmed palette evidence, not permission to introduce
inline literals. The token assignment to each individual Logs & Reports section,
including whether to use a pale-cyan card or a near-black performance card, is
**Needs Verification [design-verified]** because no current Logs target export
confirms that motif assignment.

## 4. Typography and visual hierarchy

**Analysis cross-reference:** [`logs-reports-screen-analysis.md`](logs-reports-screen-analysis.md:44)

Use the existing IBM Plex Sans Regular, Medium, Semibold, and Bold roles from
[`app_typography.dart`](../lib/theme/app_typography.dart:96), as consumed by
[`app_home_theme.dart`](../lib/theme/app_home_theme.dart:50). Do not add a new
font family or introduce ad hoc font sizes, weights, or letter spacing.

The visual hierarchy should be more spacious and editorial than the historical
dense dashboard treatment:

1. Keep the route title clearly distinct from tab labels.
2. Keep section headings distinct from metric labels and supporting copy.
3. Give primary metric values visual prominence while preserving their existing
   labels and formatting.
4. Use muted and subtle ink for explanatory copy and metadata without reducing
   contrast below the active light-theme roles.
5. Allow text to wrap rather than truncating export explanations, correction
   details, unavailable-metric reasons, chart summaries, or log-row metadata.

The analysis confirms that large bold headings, generous whitespace, prominent
metric values, a small uppercase eyebrow, and large introductory copy are part
of the established light language, but it does not assign every motif to Logs &
Reports. Whether the route receives an eyebrow, an oversized title treatment,
introductory copy, logo/wordmark, or status badge beyond its current content is
**Needs Verification [design-verified]**. No such content may be added solely to
imitate Home or Settings.

## 5. Spacing, radii, and bounded layout

**Analysis cross-reference:** [`logs-reports-screen-analysis.md`](logs-reports-screen-analysis.md:330)

All changed spacing, radii, and typography must come from the existing token
files [`app_spacing.dart`](../lib/theme/app_spacing.dart:95),
[`app_radii.dart`](../lib/theme/app_radii.dart:94),
[`app_colors.dart`](../lib/theme/app_colors.dart:79),
[`app_typography.dart`](../lib/theme/app_typography.dart:96), and
[`app_home_theme.dart`](../lib/theme/app_home_theme.dart:50). Do not add raw
layout literals to approximate an unavailable screenshot.

### 5.1 Spacing scale

Use the authoritative extracted spacing scale **6 / 8 / 12 / 16 / 20 / 24** for
new or revised relationships. The scale is confirmed by the analysis at
[`logs-reports-screen-analysis.md`](logs-reports-screen-analysis.md:94).

Preserve existing relationships when changing spacing would alter content
behavior or established grouping. In particular, the existing 14 and 4 values
may remain where the analysis identifies them as content relationships; mapping
them to 12, 6, or 8 is a visual choice and is **Needs Verification
[design-verified]** without a target export. Do not introduce 32, 48, or 64
solely from the token-summary PNG.

The exact gap between every Logs-specific section, card, row, and control is
**Needs Verification [design-verified]**. Select relationships from the
confirmed scale during visual QA while preserving the existing section order and
content density boundaries.

### 5.2 Radii and card treatment

Use the existing radius roles **3 / 12 / 14 / 18 / 24** from
[`app_radii.dart`](../lib/theme/app_radii.dart:94). Prefer rounded white grouped
cards on the light base surface for readable sections and preserve any existing
content grouping. Cards should have clear internal padding and enough separation
to prevent metric, export, correction, unavailable-state, chart, and log content
from reading as one undifferentiated block.

The exact radius-to-component mapping and whether any section uses a pale-cyan or
near-black surface are **Needs Verification [design-verified]**. The design must
not infer those assignments from the legacy dark exports.

### 5.3 Centered bounded content

Use the existing centered, bounded secondary-screen width pattern: the analysis
identifies an approximately **480 logical-pixel** content area from the current
Settings and Help responsive precedent. Keep the content centered on wider
windows and allow it to contract within the available width on narrower windows.
This is a codebase-derived recommendation, not a Logs target-export fact, and is
**Needs Verification [inferred-from-codebase]** across supported widths and on
the required physical Android device.

Do not create a fixed 390 × 844 layout, device-type branches, or screenshot-sized
positioning. Content-heavy Overview and Charts views remain scrollable, and the
Logs view remains independently scrollable where its existing list requires it.

## 6. Overview visual specification

**Analysis cross-reference:** [`logs-reports-screen-analysis.md`](logs-reports-screen-analysis.md:176)

Retain the existing Overview content and order: Real-Time Performance, Engine
Comparison, Session Summary, Offline telemetry export, Correction reports, Model
Evaluation Metrics, and Usability. The specification changes visual hierarchy
only; it does not rename, add, remove, reorder, or reinterpret these sections.

### 6.1 Performance and engine summaries

- Present Avg FPS and Avg Latency as prominent values within a clear light-card
  grouping. Avg Latency retains the `ms` suffix and both values retain one-decimal
  formatting.
- Preserve the empty performance values of `0.0` and `0.0 ms`; do not restyle
  them into an em dash or another no-data placeholder.
- Keep one Engine Comparison summary for each existing inference-engine value.
  Empty summaries remain `No samples`.
- Keep populated engine summaries limited to average FPS, average latency, and
  sample count.

The exact arrangement of the two performance values and per-engine summaries,
including whether they are a two-column or stacked layout at a given width, is
**Needs Verification [design-verified]**. The visual treatment must not imply a
new engine-selection control or a new comparison calculation.

### 6.2 Session Summary

Use a readable metric-card or grouped-card treatment for Total detections,
High-priority alerts, Frames processed, Session duration, and Avg confidence.
Keep each existing label attached to its existing value and preserve the current
formatting and no-data behavior. Avg confidence must remain explicitly labeled
as confidence and may display an em dash only when there are no detection
records.

The screen must not present confidence as accuracy. The visual prominence of a
confidence value must not make it resemble an accuracy metric. The exact card
grid, label/value alignment, and responsive stacking behavior are **Needs
Verification [design-verified]** because the target composition is unavailable.

### 6.3 Offline telemetry export

Keep the semantic container labeled `Offline telemetry export`. Present the
existing supporting copy as readable secondary text, retaining that exports are
versioned, image-free, and contain no camera frames or device IDs.

Retain the two accessible actions `Save JSON export` and `Save CSV export`.
They may receive clearer light-theme button treatment and spacing, but no new
export action or schema control may appear. While writing, both actions remain
disabled and `Saving export…` remains visible. Success and failure feedback
remain the existing live-region SnackBar states and are not replaced by a
decorative status treatment.

Whether the two actions are stacked or arranged in a row at a particular width,
and the precise button/card styling, are **Needs Verification
[design-verified]**. The arrangement must remain usable under large text and
available-width constraints.

### 6.4 Correction reports

Keep Correction reports in its current Overview position as a display-only
section. Use a light grouped-card treatment that makes the record count,
newest-first ordering, detection label, feedback, optional corrected label,
engine, and confidence threshold easy to scan without adding mutation controls.

For null or empty data, retain the exact message `No correction reports have
been recorded in this session.`. Keep the existing semantic group label
containing the number of records. Correction creation continues to occur only
through the existing correction flow and service; the redesign adds no edit,
delete, filter, or sort action.

The exact row density, divider treatment, and corrected-label emphasis are
**Needs Verification [design-verified]** because no current Logs target export
confirms them.

### 6.5 Unavailable evaluation and usability metrics

Keep Model Evaluation Metrics and Usability as explicit unavailable-state
content, not as empty telemetry cards. Accuracy, Precision, Recall, F1, and mAP
remain unavailable because ground-truth labels from offline evaluation are
required. SUS remains unavailable because a post-test participant questionnaire
is required.

A visual callout, subdued card, or explanatory note may improve hierarchy using
existing light-theme tokens, but it must preserve the reasons above verbatim in
meaning. It must not fabricate values, infer evaluation results from telemetry,
or relabel average confidence as accuracy. Exact callout surface, iconography,
and placement are **Needs Verification [design-verified]**.

## 7. Charts visual specification

**Analysis cross-reference:** [`logs-reports-screen-analysis.md`](logs-reports-screen-analysis.md:254)

Retain exactly three chart regions in the Charts tab, in the existing order:

1. latency;
2. frames per second; and
3. detection frequency.

Each chart continues to receive its current telemetry data and retains its
current dynamic behavior:

- latency keeps dynamic Y scaling with headroom and shows the 300 ms benchmark
  line only when the computed scale can contain it;
- FPS keeps dynamic Y scaling and shows the 15 FPS benchmark line only when it
  fits; and
- detection frequency continues whole-minute bucketing from the first currently
  retained record and uses a data-driven maximum Y.

The existing chart allocation remains **180 logical pixels** through the
existing [`kChartHeight`](logs-reports-screen-analysis.md:267) value. Restyling
must keep drawing inside that allocation and must not change the data-driven
scaling rules.

### 7.1 Light chart treatment

Use the light secondary-screen surface and existing chart/theme tokens for chart
cards, lines, bars, grid lines, benchmark lines, and supporting text. The intent
is a legible light presentation that visually belongs with the route's white
cards and near-white base surface, not a reproduction of the historical dark
charts or their yellow/orange palette.

The exact light line colors, bar color, grid contrast, benchmark-line contrast,
card grouping, padding, and chart heading treatment are **Needs Verification
[design-verified]** because no current light chart export exists. No new chart
palette or chart token may be invented inline.

### 7.2 Empty and semantic states

Empty charts continue to expose `No data available yet.`. The visible empty
state may be given a calm, centered light-card treatment with muted supporting
ink, but its text and meaning must remain unchanged. Exact alignment, vertical
placement, and empty-state decoration are **Needs Verification
[design-verified]**.

The chart drawing remains excluded from the semantics tree. Each chart continues
to expose one textual summary containing latest, average, minimum, maximum,
sample count, and engine where applicable. Touch interaction, axis labels, and
legends remain disabled or hidden. No visual affordance may imply that chart
touch, axis, legend, filtering, or date-range interaction is available.

## 8. Logs visual specification

**Analysis cross-reference:** [`logs-reports-screen-analysis.md`](docs/logs-reports-screen-analysis.md:284)

When there are no records, retain the centered empty state `No detections
recorded yet.`. The empty state may use the light route surface, a readable
muted-ink treatment, and tokenized vertical breathing room; exact decoration,
alignment offset, and card usage are **Needs Verification [design-verified]**.

When records exist, retain the newest-first scrolling list. Every row continues
to show:

- the compact colored priority dot;
- the detection label and confidence percentage;
- engine, spatial position, and latency in milliseconds; and
- the trailing local-time `HH:mm:ss` timestamp.

The compact dot remains visible, but priority must not be conveyed by color
alone. The row's semantic description continues to include High, Medium, or Low
priority wording. This preserves the existing accessibility constraint without
adding a visible filter, grouping, pagination, export control, or row action.

The exact row card/divider treatment, metadata spacing, timestamp color, and
priority-dot token mapping are **Needs Verification [design-verified]**. The
visual treatment must maintain legibility in both empty and populated states.

## 9. Responsive behavior and text scaling

**Analysis cross-reference:** [`logs-reports-screen-analysis.md`](logs-reports-screen-analysis.md:357)

Responsive behavior is constraint-based and follows the existing centered
bounded secondary-screen precedent. The layout should:

- center content within the approximately 480 logical-pixel recommended bound
  on wider windows;
- use the available width below that bound without horizontal overflow;
- preserve vertical scrolling for content-heavy Overview and Charts views;
- retain independent Logs scrolling for the newest-first record list;
- allow metric summaries and export actions to stack when available width or
  text scale requires it; and
- avoid device-type, orientation-name, or fixed reference-canvas branches.

No breakpoint, minimum content width, exact column threshold, or tablet/desktop
arrangement is confirmed by the analysis. Those values are **Needs Verification
[inferred-from-codebase]** and must be selected only after constraint-based
visual QA. The 390 × 844 reference canvas is evidence of reference format, not a
fixed implementation size.

The design must respect large-text scaling. Export explanations, unavailable
metric reasons, chart summaries, correction records, and Logs rows must wrap or
reflow rather than clip or overlap. A direct Logs screen-focused widget test for
200 percent text scale and no overflow is recommended by the analysis but does
not currently exist; its implementation and result are **Needs Verification
[inferred-from-codebase]**.

## 10. Accessibility and state presentation

**Analysis cross-reference:** [`logs-reports-screen-analysis.md`](logs-reports-screen-analysis.md:271)

The redesign preserves the current accessibility contracts rather than treating
visual styling as a substitute for semantics:

- chart drawing remains excluded from the semantics tree;
- each chart retains one textual summary with latest, average, minimum, maximum,
  sample count, and engine where applicable;
- empty charts retain `No data available yet.`;
- Logs rows retain their visible priority dot and include High, Medium, or Low
  in the row semantic description;
- export actions retain their accessible names, enabled/disabled state, busy
  text, and live-region feedback;
- correction reports retain the group semantic label containing the record count;
- unavailable evaluation and usability states retain explanatory text rather
  than color-only or fabricated values; and
- no per-frame detection output becomes a live region.

Color, contrast, and surface changes must never be the sole carrier of priority,
busy, success, failure, unavailable, or empty-state meaning. Minimum touch
targets, enabled status, state, value, role, hint, and label behavior remain
those of the existing accessible controls. Any exact contrast ratio, focus-ring
appearance, keyboard traversal detail, or TalkBack announcement wording not
confirmed in the analysis is **Needs Verification [inferred-from-codebase]** and
must not be invented in this document.

## 11. Export, correction, and telemetry contract preservation

**Analysis cross-reference:** [`logs-reports-screen-analysis.md`](logs-reports-screen-analysis.md:236)

Visual changes must not alter the existing service contracts or data semantics:

- export remains local to the screen with its existing busy guard, JSON/CSV
  selection, optional settings snapshot, success/failure feedback, safe-message
  filtering, explicit-directory behavior, and immutable image-free schema
  version 1;
- successful export continues to show the filename in a SnackBar;
- failed export continues to show `Export could not be saved. Try again.` with
  the error-container background and live-region semantics;
- correction records continue to come from the supplied correction service,
  remain newest first, and remain display-only on this screen;
- detection records, runtime samples, cumulative counters, per-engine summaries,
  and detection-frequency buckets retain the analysis-confirmed retention and
  aggregation rules; and
- confidence remains a confidence measure and never becomes an accuracy
  measure.

The specification does not define new export copy, new telemetry labels, a new
correction status, or a new evaluation metric. Any copy change beyond the
confirmed existing strings and their visual hierarchy is **Needs Verification
[design-verified]**.

## 12. Verification criteria for a later implementation

**Analysis cross-reference:** [`logs-reports-screen-analysis.md`](logs-reports-screen-analysis.md:481)

The later implementation should be considered visually conformant only when it
demonstrates all of the following without changing the contracts above:

1. The pushed Logs & Reports route uses the local light secondary-screen theme,
   while the underlying shell remains unchanged after push and pop.
2. Overview, Charts, and Logs remain the only tabs and retain their current
   order, scroll behavior, content, and state updates.
3. Overview preserves telemetry formatting, empty values, export states,
   correction ordering, unavailable metric reasons, and confidence labeling.
4. Charts preserve all three regions, data binding, dynamic bounds, conditional
   benchmark lines, the [`kChartHeight`](logs-reports-screen-analysis.md:267)
   allocation, empty text, and summary semantics.
5. Logs preserves centered empty content, newest-first rows, all row fields,
   local timestamps, visible priority dots, and priority wording in semantics.
6. The layout remains readable within the centered bounded width pattern and
   does not introduce horizontal overflow at supported available widths.
7. Large text can reflow Overview, Charts, and Logs content without clipping or
   RenderFlex overflow.
8. Export and correction interactions remain behaviorally identical, including
   disabled busy state and live-region success/failure feedback.
9. Physical Android-device verification checks route push/pop, all tabs, export
   states, chart states, correction states, Logs states, large text,
   accessibility behavior, RenderFlex overflows, and logcat exceptions.
10. Static analysis and the test suite are run in the later implementation stage;
    this design-spec stage makes no claim that they have been run.

The analysis recommends a direct Logs screen-focused widget test covering real
content, route-local theme scope, all tabs, exports, correction states,
unavailable metrics, Logs states, priority semantics, and 200 percent text
scale/no-overflow. Existing chart algorithm and bound coverage remains in
[`charts_test.dart`](../test/widgets/charts_test.dart:1). Test creation and
execution are **Needs Verification [inferred-from-codebase]** and are not part
of this document-only stage.

## 13. Out-of-scope decisions

**Analysis cross-reference:** [`logs-reports-screen-analysis.md`](logs-reports-screen-analysis.md:507)

This specification does not authorize:

- changes to [`app_shell.dart`](../lib/navigation/app_shell.dart:77), route
  ownership, bottom navigation, or back navigation;
- edits to model or service layers, including
  [`telemetry_service.dart`](../lib/services/telemetry_service.dart:305),
  [`telemetry_export_service.dart`](../lib/services/telemetry_export_service.dart:236),
  [`correction_service.dart`](../lib/services/correction_service.dart:215), or
  the existing model contracts;
- changes to inference engines, camera behavior, telemetry retention, sampling,
  aggregation, or data binding;
- new filters, sorting, date ranges, engine selectors, pagination, chart
  gestures, legends, axis labels, or row actions;
- new accuracy, Precision, Recall, F1, mAP, SUS, or other calculations;
- replacing unavailable states with inferred or fabricated values;
- changing export schema, export contents, file writing, or exporter
  construction;
- correction creation or correction persistence changes;
- generalizing or renaming the light-theme builder or its existing tokens;
- using the legacy Logs & Reports images as the redesign target; or
- inventing a current target export or fixed screenshot-matched layout.

The only screen-specific existing UI component identified for the composition is
[`logs_reports_screen.dart`](../lib/screens/logs_reports_screen.dart:16). The
analysis identifies [`charts.dart`](../lib/widgets/charts.dart:537) only as a
possible chart-visual boundary and [`charts_test.dart`](../test/widgets/charts_test.dart:541)
as retained chart-bound coverage. Their later use remains conditional on an
approved visual change and is not an implementation instruction here.

## Open Questions / Needs Verification

**Analysis cross-reference:** [`logs-reports-screen-analysis.md`](logs-reports-screen-analysis.md:549)

- **Exact Logs composition — Needs Verification [design-verified]:** no current
  Logs & Reports target export exists. Confirm title treatment, section-specific
  card grouping, chart contrast, row treatment, spacing relationships, and any
  Logs-specific motifs during visual QA. Legacy exports remain contextual only.
- **Light motif assignment — Needs Verification [design-verified]:** confirm
  whether any existing Home/Settings motifs such as an eyebrow, status badge,
  pale-cyan surface, cyan rail, logo/wordmark, or near-black performance card
  belong on Logs & Reports. Do not add them by imitation.
- **Exact typography scale and mapping — Needs Verification [design-verified]:**
  IBM Plex Sans roles are confirmed, but the absent target does not confirm exact
  title, section-heading, metric, metadata, tab, or empty-state sizes.
- **Exact spacing and radius mapping — Needs Verification [design-verified]:**
  use the confirmed 6/8/12/16/20/24 spacing scale and 3/12/14/18/24 radius
  roles, preserving existing 14/4 relationships where required, but validate
  each section and component relationship visually.
- **Centered bounded width QA — Needs Verification [inferred-from-codebase]:**
  validate the approximately 480 logical-pixel centered content bound across
  supported available widths and on the physical Android device.
- **Responsive arrangement — Needs Verification [inferred-from-codebase]:**
  confirm when metric cards and export actions stack or share a row, without
  changing the Overview content order or introducing a fixed-width branch.
- **Light chart treatment — Needs Verification [design-verified]:** confirm
  light chart card grouping, line/bar colors, grid contrast, benchmark-line
  contrast, heading treatment, and empty-state alignment. Preserve chart
  algorithms, data binding, summaries, and the [`kChartHeight`](logs-reports-screen-analysis.md:267)
  allocation regardless of the visual result.
- **Logs row treatment — Needs Verification [design-verified]:** confirm card or
  divider use, metadata spacing, timestamp emphasis, and priority-dot token
  mapping while retaining all existing row fields and priority semantics.
- **Accessibility QA — Needs Verification [inferred-from-codebase]:** validate
  TalkBack labels, roles, states, values, hints, enabled status, live-region
  behavior, chart summary announcements, priority wording, and focus behavior
  after the visual restyle.
- **Large-text/no-overflow coverage — Needs Verification [inferred-from-codebase]:**
  create and run the direct Logs screen-focused widget test at 200 percent text
  scale; retain chart algorithm and bounds coverage in
  [`charts_test.dart`](../test/widgets/charts_test.dart:1).
- **Physical-device verification — Needs Verification [inferred-from-codebase]:**
  run the required physical Android checks for route push/pop, light route
  styling, all tabs, exports, chart states, correction states, Logs states,
  large text, accessibility, RenderFlex overflow, and logcat exceptions.
- **Static/test status — Needs Verification [inferred-from-codebase]:** this
  document-only Design-Spec stage did not run [`flutter analyze`](../pubspec.yaml:1)
  or [`flutter test`](../pubspec.yaml:1), and makes no claim about their later
  results.
