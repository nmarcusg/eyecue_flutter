# Logs & Reports Screen Analysis

**Task type:** visual-only restyle, no architecture change.

## Scope and source boundary

This analysis covers a token-consistent visual layout-consistency redesign of
the existing researcher/developer-facing Logs & Reports screen. The redesign
may change surfaces, typography, spacing, responsive layout consistency, and
chart presentation, but it must retain the existing composition, section order,
content, data binding, and interaction boundaries.
It must not add filtering, sorting, date ranges, engine-selection state, chart
interaction, pagination, new telemetry calculations, correction mutation, or a
new export schema.

The current implementation is in
[`logs_reports_screen.dart`](../lib/screens/logs_reports_screen.dart). The
findings below are based on the confirmed repository and visual-reference
findings supplied for this task. This document is an analysis-stage artifact;
it is not a design spec, implementation plan, or code change.

## 1. Confirmed visual facts

### 1.1 The intended Logs & Reports target is not available

There is no current Logs & Reports target export, including no current light
target export. The current
[`design-reference/screens/`](../design-reference/screens/) directory contains
references for detection, home, preparing, and settings, but no Logs & Reports
reference. The only Logs & Reports images are legacy exports under
[`design-reference/old_screen/logs_reports_screen/`](../design-reference/old_screen/logs_reports_screen/):

- [`logs_reports_screen.jpg`](../design-reference/old_screen/logs_reports_screen/logs_reports_screen.jpg)
- [`logs_reports_screen_charts.jpg`](../design-reference/old_screen/logs_reports_screen/logs_reports_screen_charts.jpg)
- [`logs_reports_screen_logs.jpg`](../design-reference/old_screen/logs_reports_screen/logs_reports_screen_logs.jpg)

These legacy images are reference context only. They must not be treated as
the intended redesign target. Exact Logs-specific pixel composition remains a
design-reference gap, but the product direction is settled: use the light
secondary-screen language and retain the existing composition, section order,
content, data binding, and interaction boundaries rather than inventing a
replacement structure.

### 1.2 Established light visual language

The confirmed light references are
[`settings-screen.png`](../design-reference/screens/settings-screen.png) and
[`home_screen.png`](../design-reference/screens/home_screen.png). Their
established language is:

- near-white background;
- near-black primary text;
- muted slate blue-gray secondary copy;
- bright cyan accent;
- large bold headings and generous whitespace;
- large rounded cards, including white grouped cards, pale-cyan cards, and a
  near-black performance card;
- a rounded white status badge with a cyan dot;
- centered black logo/wordmark treatment;
- a small uppercase eyebrow label;
- an oversized screen title;
- a large introductory paragraph; and
- prominent metric values.

The visual language is spacious and editorial rather than dashboard-dense.
The existence of these patterns does not confirm that every pattern belongs on
Logs & Reports. In particular, this analysis does not assign the status badge,
logo/wordmark, eyebrow, or introductory copy to the screen because no target
Logs & Reports export confirms those placements.

### 1.3 Authoritative token evidence

The exact token evidence is in
[`extracted-design-tokens-screenshot.md`](../design-reference/tokens/extracted-design-tokens-screenshot.md),
which is authoritative over the token-summary PNG for exact values. Confirmed
values are:

| Role | Confirmed value |
|---|---|
| Base surface | `#F5F5F5` |
| Card surface | `#FFFFFF` |
| Dark surface / primary ink | `#0A0A0A` |
| Muted ink | `#667085` |
| Subtle ink | `#99A5AA` |
| Cyan accent | `#22C7F2` |
| Light cyan rail | `#B9EFFF` |
| Dark cyan | `#087A9E` |
| Amber warning | `#F5B942` |
| Success | `#32D583` |
| Warning | `#F5B942` |
| Critical | `#FF5C5C` |
| Info | `#4DA3FF` |
| Disabled | `#667085` |
| Radius roles | `3`, `12`, `14`, `18`, `24` |
| Spacing evidence | `6`, `8`, `12`, `16`, `20`, `24` |
| Typography | IBM Plex Sans Regular, Medium, Semibold, and Bold |

The reference canvas is 390 by 844 in portrait. Device status-bar artifacts
must not be recreated in the app UI. The reference canvas is evidence of the
reference format, not a reason to implement a fixed-width or screenshot-sized
Logs & Reports layout.

### 1.4 Legacy screen evidence is contextual only

The legacy screen shows a dark near-black surface, cream/white type, an amber
selected tab, a back arrow with a Logs & Reports title, and Overview, Charts,
and Logs tabs. Its Overview contains Real-Time Performance, Engine Comparison,
Session Summary, Offline telemetry export, Correction reports, Model
Evaluation Metrics, and Usability. It uses compact two-column metric cards,
dark rounded cards, right-aligned numbers, and separate export buttons.

The legacy Charts image shows separate latency, FPS, and detection-frequency
sections with yellow/orange lines, a yellow frequency bar, dashed grid lines,
a green dashed FPS target line, and benchmark/target values in headings. The
legacy Logs image shows a scrolling event list with colored circular markers,
two-line event content, and right-aligned local-time timestamps. The marker
categories are yellow, red, and green.

These observations establish historical context only. They do not establish
the styling, density, section order, chart colors, or layout for the visual
redesign.

### 1.5 Chart-specific target evidence is missing

There is no current light chart export. Light chart colors, card treatment,
grid-line contrast, empty states, and responsive chart sizing are not
confirmed. No redesign may claim that the legacy yellow/orange chart palette,
dark chart cards, or any newly invented light palette is the intended result.

## 2. Existing behavior that must remain unchanged

### 2.1 Navigation and route ownership

Logs & Reports is not a bottom-navigation tab. The shell’s
[`openLogsReports()`](../lib/navigation/app_shell.dart:77) method pushes the
screen through a `MaterialPageRoute`, and the shell remains beneath it. The
four-tab navigation bar is not replaced by the pushed route. A later visual
change should therefore keep route ownership in
[`app_shell.dart`](../lib/navigation/app_shell.dart) unchanged.

The parent-confirmed direction is that Logs & Reports uses the established
light secondary-screen language rather than the inherited dark route. The
later implementation should reuse [`buildHomeTheme()`](../lib/theme/app_home_theme.dart:50)
locally at the pushed route root and add scoped dark status-bar styling
consistent with Settings and Help. This local scope must not generalize or
rename the Home theme or tokens, and [`app_shell.dart`](../lib/navigation/app_shell.dart)
remains unchanged. The stale architecture wording that describes the light
builder as scoped only to Home and Help is documentation debt, not a Logs
implementation blocker.

The route receives shared telemetry, settings, and optional correction
services. It does not pass an explicit export service; the screen constructs
its default exporter internally. A visual redesign must not change that
dependency flow merely to restyle the screen.

### 2.2 Tab structure and state updates

The screen currently uses
[`DefaultTabController`](../lib/screens/logs_reports_screen.dart:48) for three
tabs: Overview, Charts, and Logs. Its body uses
[`ListenableBuilder`](../lib/screens/logs_reports_screen.dart:61) with telemetry
and, when supplied, corrections. This keeps the displayed values current as
the underlying services change.

The existing `AppBar`/`TabBar`/`TabBarView` arrangement remains unchanged:
Overview, Charts, and Logs stay the only tabs. The visual restyle should use
the light theme’s indicator and tab colors. It must not add a bottom
navigation bar, filtering, legends, or engine-specific tab state. Each tab
view remains independently scrollable where its existing content requires it.

Export state is local to the screen. The busy state disables both export
actions while an export is pending. There is no local filtering, sorting,
date-range state, engine-selector state, chart-interaction state, or
persistence state to preserve or redesign.

### 2.3 Overview content and semantics

The redesign must retain the following content, data sources, formatting, and
meaning:

1. **Real-Time Performance**
   - Avg FPS comes from the telemetry service’s average inference FPS.
   - Avg Latency comes from average latency and includes the `ms` suffix.
   - Both use one-decimal formatting.
   - With no samples, the values remain `0.0` and `0.0 ms`; they must not be
     changed to an em dash or another empty-state value.

2. **Engine Comparison**
   - One summary remains present for each inference-engine value.
   - An empty engine summary remains `No samples`.
   - A populated summary continues to show average FPS, average latency, and
     sample count.

3. **Session Summary**
   - Total detections remains the retained detection-record count.
   - High-priority alerts remains cumulative.
   - Frames processed remains the cumulative sample count.
   - Session duration remains the clock difference from session start,
     formatted as hours, minutes, and seconds.
    - Avg confidence remains explicitly labeled as confidence and displays an
      em dash only when there are no detection records.
    - Existing em-dash and other no-data behavior remains exactly as currently
      applicable; visual work must not normalize all empty values to one
      replacement placeholder.

4. **Offline telemetry export**
   - The semantic container remains labeled `Offline telemetry export`.
   - The existing accessible actions remain `Save JSON export` and
     `Save CSV export`.
   - Supporting copy continues to state that exports are versioned, image-free,
     and contain no camera frames or device IDs.
   - While writing, both actions remain disabled and `Saving export…` remains
     visible.

5. **Correction reports**
    - The section remains in its current Overview position and remains
      display-only.
    - The display reads correction records from the supplied correction service,
      not from a telemetry correction list.
   - Null or empty data remains
     `No correction reports have been recorded in this session.`
   - Populated records remain newest first and retain detection label,
     feedback, optional corrected label, engine, and confidence threshold.
   - The group continues to expose a semantic label containing the number of
     records.
    - New mutation, filtering, or correction actions are not added; correction
      creation stays in the existing correction sheet and correction service.

6. **Unavailable metrics**
   - Accuracy, Precision, Recall, F1, and mAP remain explicitly unavailable
     because they require ground-truth labels from offline evaluation.
   - SUS remains explicitly unavailable because it requires a post-test
     participant questionnaire.
   - A raw confidence value must never be relabeled as accuracy.

### 2.4 Export behavior and contract

The existing export flow retains its busy guard, local exporting state, JSON or
CSV writer selection, optional settings snapshot, and success/failure feedback.
The shared exporter continues to include the session, retained samples,
detections, failures, fallbacks, recoveries, and corrections supplied by the
existing services.

Successful writes continue to show a SnackBar containing the filename. Failed
writes continue to show `Export could not be saved. Try again.` with the
error-container background. Both messages remain wrapped in a live-region
semantic container. The immutable, image-free, schema-version-1 export
contract remains unchanged. Existing service tests for JSON round-tripping,
CSV quoting, safe-message filtering, and explicit-directory writes remain
applicable.

### 2.5 Charts behavior and semantics

The Charts tab retains three chart regions:

- latency;
- frames per second; and
- detection frequency.

Each region currently receives its existing telemetry data. Latency retains
dynamic Y scaling with headroom and a 300 ms benchmark line only when the
computed scale can contain it. FPS retains dynamic Y scaling and a 15 FPS
benchmark line only when it fits. Detection frequency continues to bucket
records by whole minute from the first currently retained record and uses a
data-driven maximum Y.

The current chart height is 180 logical pixels and is represented by
`kChartHeight`. Any later visual sizing change must keep each chart inside its
allocated bounds and must not change the data-driven scaling rules.

The chart drawing remains excluded from the semantics tree. Each chart
continues to expose one textual summary containing latest, average, minimum,
maximum, sample count, and engine where applicable. Empty charts continue to
expose `No data available yet.`. Touch interaction, axis labels, and legends
remain intentionally disabled or hidden. There is no chart touch interaction,
axis interaction, or legend interaction to add.

The existing chart-bound tests and chart-summary semantics tests remain
regression requirements. The current chart rendering and empty-state
presentation are not evidence of an exact target composition. Charts may be
restyled only with existing light/theme/chart tokens; exact card grouping and
contrast remain visual QA items, not product blockers.

### 2.6 Logs behavior and accessibility constraint

The Logs tab retains its centered empty state, `No detections recorded yet.`,
when there are no records. With records, it remains a newest-first scrolling
list. Each row continues to show:

- a colored priority dot;
- label and confidence percentage;
- engine, spatial position, and latency in milliseconds; and
- a trailing local-time `HH:mm:ss` timestamp.

There is no user-facing filter, engine grouping, pagination, export control,
or row action to preserve.

The compact priority dot remains in the visible composition. The row semantic
description should additionally include the priority wording — High, Medium,
or Low — so priority is not conveyed by color alone. This does not change the
visible row composition or add a filtering/action surface. A dedicated
screen-level semantics test is recommended for the resulting Logs rows in
addition to the existing reusable-widget semantics coverage.

### 2.7 Telemetry semantics

The following data semantics are fixed and must not be altered by visual work:

- detection records retain at most 2,000 entries;
- runtime samples retain at most 500 entries;
- total detections, average confidence, and frequency buckets operate on the
  currently retained detection records;
- average latency and FPS operate on currently retained samples;
- frames processed and high-priority-alert count are cumulative and do not
  decrease when retained lists are trimmed;
- per-engine summaries use retained samples for the selected engine only;
- detection-frequency buckets begin with the first currently retained record,
  which may be later than the original session start after trimming; and
- retained detection records preserve engine, confidence threshold, spatial
  position, optional proximity, optional tracking or motion, and normalized
  box data for export even when the Logs tab displays only a subset.

## 3. Required visual changes

The later implementation should restyle the existing content without
reinterpreting it. Because the target Logs & Reports export is missing, these
requirements define boundaries and confirmed visual language rather than a
pixel-level layout.

### 3.1 Use the established token layer

All new or changed colors, spacing, radii, and typography must use the
existing UI token layer in
[`app_colors.dart`](../lib/theme/app_colors.dart),
[`app_spacing.dart`](../lib/theme/app_spacing.dart),
[`app_radii.dart`](../lib/theme/app_radii.dart),
[`app_typography.dart`](../lib/theme/app_typography.dart), and
[`app_home_theme.dart`](../lib/theme/app_home_theme.dart). Do not introduce
inline color, spacing, radius, or type literals to approximate an absent
reference.

The confirmed light values provide a palette and role vocabulary for a later
restyle: near-white base surface, white cards, black ink, muted and subtle
ink, cyan accents, pale-cyan supporting surfaces, dark cyan, amber warning,
and the confirmed system colors. The exact assignment of those roles to
individual Logs & Reports sections is not confirmed without a target export.

### 3.2 Preserve content while changing hierarchy and density

The existing sections, metric values, export actions, correction records,
unavailable notes, charts, and logs remain. Visual work may establish a more
spacious editorial hierarchy using the confirmed IBM Plex Sans roles, larger
headings, prominent metric values, rounded cards, and clearer secondary copy.
It must not add new content merely to imitate Home or Settings, and it must
not infer a new section order from the legacy screen.

The final composition should remain scrollable for content-heavy Overview and
Charts views. Responsive behavior should be constraint-based, using bounded
content and available width rather than a branch for the 390 by 844 reference
canvas.

### 3.3 Keep charts legible without inventing chart design

If charts are visually restyled, the later implementation may change their
surface, contrast, line, bar, grid, and empty-state presentation using the
existing light/theme/chart tokens. It must preserve chart data binding, dynamic
bounds, benchmark-line conditions, allocated-box safety, and one summary per
chart. No legacy chart palette is the default target; exact card grouping and
contrast remain visual QA items.

### 3.4 Keep priority and status information perceivable

The visual treatment must retain a non-color cue for meaningful state where
the current contract already provides text or semantics. Priority must not be
communicated less clearly than the current dot-only visual treatment. Export
busy, success, and failure states must remain available through their current
text and live-region semantics, not color alone.

### 3.5 Preserve truthful unavailable states

The Model Evaluation Metrics and Usability sections remain explicit
unavailable-state content, not empty telemetry cards and not fabricated
metrics. Their explanatory reasons remain visible: ground-truth labels are
required for Accuracy, Precision, Recall, F1, and mAP; a post-test participant
questionnaire is required for SUS. A later light-card or callout treatment may
improve visual hierarchy, but it must retain those exact truth conditions and
must not substitute average confidence for accuracy.

## 4. Ambiguities

### 4.1 Missing target composition

No current Logs & Reports target export exists. Legacy exports remain reference
context only, so exact Logs-specific pixel composition — including precise
card grouping, chart contrast, and title treatment — remains a
design-reference gap. This does not leave the light-versus-dark direction or
the existing composition open: the parent decision is light secondary-screen
language, with the existing section order, content, data binding, and
interaction boundaries retained. Do not derive a replacement structure from
the legacy images.

### 4.2 Motif assignment and exact visual QA

The missing target does not confirm whether Home/Settings motifs such as an
eyebrow, status badge, logo, wordmark, cyan rail, pale-cyan card, or
near-black performance-card treatment belong on Logs & Reports. These are
visual QA details rather than product decisions; no motif should be added
merely to imitate another screen. Exact chart card grouping and contrast are
similarly visual QA items.

## 5. Items needing verification

### 5.1 Theme reuse versus generalization — resolved direction

The technical reuse-versus-generalization question is resolved in favor of
local reuse for the pushed light route:

1. Wrap the root of
   [`LogsReportsScreen`](../lib/screens/logs_reports_screen.dart:23) with a
   locally scoped `Theme` whose data comes from
   [`buildHomeTheme()`](../lib/theme/app_home_theme.dart:50).
2. Add a local `AnnotatedRegion<SystemUiOverlayStyle>` with dark status-bar
   styling consistent with the existing Settings/Help pattern.
3. Keep the local theme inside the pushed route. It must not wrap or recolor
   the underlying shell `NavigationBar`, and popping the route must leave the
   other tabs unchanged.
4. Do not generalize or rename the existing Home-local builder or `kHome*`
   tokens. Do not add another light-theme builder, change global theme
   ownership, edit [`app_shell.dart`](../lib/navigation/app_shell.dart), or
   edit theme-token files for this Logs-only redesign.

The architecture summary’s stale wording that scopes the light builder only to
Home and Help, despite its confirmed Settings use, is documentation debt to be
reconciled separately and is not a Logs implementation blocker.

### 5.2 Spacing-scale reconciliation — resolved token direction

The current Logs layout uses raw values that already have project token
equivalents: 16 for screen padding, 8, 12, and 24 for section/card gaps, 14
for export and correction-card inner padding, 4 for correction-row padding, 6
for summary-row padding, 16 for metric-card padding, 12 for metric-card and
unavailable-note radii, 180 for chart height, and 8 for the Logs list’s
vertical padding.

The later redesign should use the existing token layer and prefer the
authoritative extracted reference spacing scale of 6, 8, 12, 16, 20, and 24
for newly designed relationships. The token-summary PNG’s 32, 48, and 64
values must not be introduced solely from screenshot evidence. Existing 14
and 4 tokens may remain where preserving an existing content relationship is
necessary; mapping those relationships to 12, 6, or 8 is a visual choice that
requires the target composition to confirm it. The 180 chart-height token is
the current bounded chart allocation and should remain the baseline until a
confirmed chart design says otherwise.

This resolves the reconciliation principle: tokenized existing values first,
the extracted Markdown scale for new light-composition relationships, no
screenshot-pixel positioning, and no new scale values based only on the PNG.
Existing 14/4 relationships remain where they preserve current content
behavior, and `kChartHeight` remains the 180 logical-pixel chart allocation.
Exact spacing relationships remain a later visual QA item because the target
export is unavailable.

### 5.3 Responsive sizing

Recommend the existing approximately 480 logical-pixel centered bounded
content area used by the current Settings/Help responsive precedent, with
constraint-driven sizing and independently scrollable tab views. This is a
codebase-derived recommendation, not a target-export fact. Do not add a
device-type or fixed-screenshot-width branch. **Needs Verification
[inferred-from-codebase]:** confirm the resulting layout on the required
physical device and supported width conditions.

### 5.4 Light chart treatment

The chart data and semantics are confirmed. Restyle charts only with existing
light/theme/chart tokens while preserving dynamic bounds, conditional
benchmark lines, empty states, semantics summaries, and allocated-box safety.
Exact card grouping and contrast remain visual QA items because no light target
export exists; do not carry forward the legacy palette as a target.

### 5.5 Large-text and direct screen coverage

The current screen has no direct 200 percent text-scale or no-overflow test.
Recommend a dedicated Logs screen-focused widget test file covering real screen
content, route/light-theme scope, all tabs, exports, correction states,
unavailable metrics, Logs states, priority semantics, and 200 percent
text-scale/no-overflow behavior. Keep chart algorithm and bound tests in the
existing [`charts_test.dart`](../test/widgets/charts_test.dart). **Needs
Verification [inferred-from-codebase]:** implement and validate this coverage
in a later stage; no claim is made that it currently exists or has run.

### 5.6 Device verification

The project’s UI verification policy requires a physical Android device, with
checks for interaction, visual regressions, RenderFlex overflows, and logcat
exceptions, in addition to static analysis and the test suite. **Needs
Verification [inferred-from-codebase]:** complete physical-device validation
of the redesigned Logs route, including route push/pop, tabs, exports, chart
states, correction states, Logs states, large text, and accessibility behavior.

The current repository has 153 declared `test`/`testWidgets` calls, and 153 is
the latest documented passing count; 127 references are stale. The claim that
all 153 pass remains **Needs Verification [inferred-from-codebase]** because
the suite was not run in this analysis pass. Verify with the project’s later
static-analysis and test commands.

## 6. Deferred / out-of-scope work

The following are explicitly outside this visual-only redesign:

- changing route ownership, bottom-navigation behavior, or back navigation;
- changing telemetry retention, aggregation, sampling, or frequency-bucket
  semantics;
- adding filters, sorting, date-range controls, engine selectors, pagination,
  row actions, chart gestures, legends, or axis labels;
- changing the export schema, export contents, safe-message filtering, file
  writing, or default exporter construction;
- adding correction creation or changing correction persistence;
- adding new accuracy, precision, recall, F1, mAP, SUS, or other evaluation
  calculations;
- treating confidence as accuracy or replacing truthful unavailable states
  with inferred values;
- changing the custom or Ultralytics inference engines, camera path, service
  architecture, models, or data bindings;
- changing read-only service/model files, including
  [`telemetry_service.dart`](../lib/services/telemetry_service.dart),
  [`telemetry_export_service.dart`](../lib/services/telemetry_export_service.dart),
  [`correction_service.dart`](../lib/services/correction_service.dart),
  [`telemetry_export.dart`](../lib/models/telemetry_export.dart),
  [`app_settings.dart`](../lib/models/app_settings.dart), or detection and
  correction models;
- generalizing the light-theme builder or renaming existing light tokens;
- using the legacy Logs & Reports exports as the redesign target;
- inventing a missing target export or a screenshot-matched fixed layout; and
- modifying files outside the analysis artifact during this Analysis stage.

Potential later implementation files are limited to the existing UI and test
boundaries: [`logs_reports_screen.dart`](../lib/screens/logs_reports_screen.dart)
for the screen composition and local theme scope;
[`charts.dart`](../lib/widgets/charts.dart) only if chart visuals or chart
allocation are actually redesigned; [`charts_test.dart`](../test/widgets/charts_test.dart)
for retained or extended chart-bound coverage; a semantics test location for
direct Logs coverage; and a screen-focused widget test location if approved.
[`app_shell.dart`](../lib/navigation/app_shell.dart) should remain unchanged
unless a separate, explicitly approved dependency-injection change is
introduced. Theme and service files should remain read-only for this visual
request unless confirmed design evidence requires a new token.

## Open Questions / Needs Verification

- **Exact Logs visual composition:** No current Logs & Reports target export
  exists. Exact pixel-level title treatment, motif assignment, card grouping,
  chart contrast, and other screenshot-specific relationships remain a
  design-reference gap. **Needs Verification [design-verified].** Legacy exports
  remain reference context only.
- **Spacing and responsive QA:** The recommended centered bounded content area is
  approximately 480 logical pixels, derived from Settings/Help precedent, and
  new relationships should use the extracted 6/8/12/16/20/24 scale while
  preserving existing 14/4 relationships where required. **Needs Verification
  [inferred-from-codebase]:** validate the resulting layout across supported
  widths and confirm exact spacing during visual QA.
- **Light chart QA:** Chart behavior is fixed, but exact light card grouping,
  contrast, grid treatment, and benchmark-line presentation remain to be
  checked against the implemented light-token treatment. **Needs Verification
  [design-verified].**
- **Dedicated Logs screen tests:** Add and run a screen-focused widget test
  file covering real content, route/light-theme scope, all tabs, exports,
  correction states, unavailable metrics, Logs states, priority semantics, and
  200 percent text scale/no-overflow. Keep chart algorithms and bounds in
  existing chart tests. **Needs Verification [inferred-from-codebase].**
- **Test execution:** The repository has 153 declared `test`/`testWidgets`
  calls and 153 is the latest documented passing count; 127 references are
  stale. The claim that all 153 pass remains **Needs Verification
  [inferred-from-codebase]** because this analysis pass did not run the suite.
- **Physical-device validation:** The required later checks include running on
  the physical Android device, confirming route push/pop, light route styling,
  all tabs, exports, correction and unavailable states, Logs priority
  semantics, 200 percent text scale, no RenderFlex overflow, and no logcat
  exceptions. No Flutter app was connected, so no MCP runtime result was
  observed. **Needs Verification [inferred-from-codebase].**
