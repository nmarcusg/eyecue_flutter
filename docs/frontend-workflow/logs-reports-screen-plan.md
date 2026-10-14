# Logs & Reports Screen Implementation Plan

**Task type:** visual-only restyle of the existing pushed Logs & Reports route;
no architecture, telemetry, export, correction, navigation, or API changes.

## Source of truth and scope

This plan follows the design specification first and the analysis second:

- [`logs-reports-screen-design-spec.md`](logs-reports-screen-design-spec.md:1)
- [`logs-reports-screen-analysis.md`](logs-reports-screen-analysis.md:1)

The implementation must restyle the existing route in place while preserving
the current Overview → Charts → Logs composition, section order, content,
service bindings, interactions, and accessibility contracts. The absence of a
current Logs & Reports target export is an explicit constraint: legacy images
remain context only, and no screenshot-matched layout or unconfirmed motif may
be invented.

## Files in implementation scope

### Primary UI file

- [`logs_reports_screen.dart`](../lib/screens/logs_reports_screen.dart:16) —
  apply the route-local light theme, centered bounded shell, surfaces,
  typography hierarchy, spacing, cards, tabs, Overview presentation, empty
  states, export presentation, correction presentation, unavailable-state
  presentation, and Logs layout while retaining the existing state and data
  flow.

### Conditional chart UI file

- [`charts.dart`](../lib/widgets/charts.dart:537) — modify only if the
  screen-level composition cannot provide the required light chart surface or
  chart styling. Any change must remain visual-only and preserve chart data
  binding, dynamic bounds, conditional benchmark lines, semantics summaries,
  touch-disabled behavior, and the existing [`kChartHeight`](logs-reports-screen-analysis.md:267)
  allocation.

### Verification files justified by the source documents

- [`charts_test.dart`](../test/widgets/charts_test.dart:1) — retain and, only
  if chart presentation changes affect existing expectations, extend the
  existing chart-bound and chart-summary regression coverage without changing
  the chart algorithms.
- A direct Logs screen-focused widget test file under [`test/`](../test/) — add
  only if the implementation stage confirms the exact test location. The
  analysis and design specification recommend coverage for the real screen,
  route-local theme scope, all tabs, exports, correction states, unavailable
  states, Logs priority semantics, and 200% text scale/no-overflow. The exact
  filename is **Needs Verification [inferred-from-codebase]** because no
  existing Logs-specific test file was identified by the source documents.

The following files are explicitly not implementation targets:

- [`app_shell.dart`](../lib/navigation/app_shell.dart:77) — route push,
  underlying navigation, and back behavior remain unchanged.
- [`app_home_theme.dart`](../lib/theme/app_home_theme.dart:50),
  [`app_colors.dart`](../lib/theme/app_colors.dart:79),
  [`app_spacing.dart`](../lib/theme/app_spacing.dart:95),
  [`app_radii.dart`](../lib/theme/app_radii.dart:94), and
  [`app_typography.dart`](../lib/theme/app_typography.dart:96) — consume the
  existing theme and token layer; do not generalize, rename, or add tokens for
  this route.
- [`telemetry_service.dart`](../lib/services/telemetry_service.dart:305),
  [`telemetry_export_service.dart`](../lib/services/telemetry_export_service.dart:236),
  [`correction_service.dart`](../lib/services/correction_service.dart:215),
  [`telemetry_export.dart`](../lib/models/telemetry_export.dart:1), and other
  model/service files — remain read-only.

## Implementation sequence

### 1. Preserve the route shell and add only local light styling

1. Keep [`openLogsReports()`](../lib/navigation/app_shell.dart:77) and the
   pushed-route ownership unchanged.
2. At the root of [`LogsReportsScreen`](../lib/screens/logs_reports_screen.dart:23),
   scope the existing [`buildHomeTheme()`](../lib/theme/app_home_theme.dart:50)
   locally to this route. Do not move the builder, rename it, replace global
   theme ownership, or wrap the underlying navigation shell.
3. Apply the same local dark status-bar icon treatment used by the existing
   light Settings and Help routes. Keep the overlay styling bounded to the
   pushed route so popping it leaves the underlying shell unchanged.
4. Retain the existing [`DefaultTabController`](../lib/screens/logs_reports_screen.dart:48),
   [`ListenableBuilder`](../lib/screens/logs_reports_screen.dart:61),
   AppBar/TabBar/TabBarView relationship, and telemetry/correction listeners.
   The only visual changes at this step are theme, surface, text, indicator,
   and spacing presentation.

### 2. Establish the centered bounded secondary-screen layout

1. Use the existing centered bounded secondary-screen precedent: approximately
   480 logical pixels on wider windows, contracting to the available width on
   narrower windows.
2. Implement the bound through available constraints, not a device-type check,
   orientation-name branch, fixed 390 × 844 canvas, or screenshot-sized
   positioning. Keep the content centered when extra width is available.
3. Keep Overview and Charts vertically scrollable and keep the Logs list
   independently scrollable where its existing content requires it.
4. Use the existing spacing scale of 6, 8, 12, 16, 20, and 24 for revised
   relationships. Prefer token equivalents from [`app_spacing.dart`](../lib/theme/app_spacing.dart:95)
   for screen padding, section gaps, card gaps, row spacing, and control gaps.
   Preserve existing 14 and 4 relationships where changing them would alter a
   content grouping; do not introduce 32, 48, or 64 solely from the reference
   PNG.
5. Use existing radius roles 3, 12, 14, 18, and 24 from
   [`app_radii.dart`](../lib/theme/app_radii.dart:94). Select the mapping by
   component hierarchy rather than by copying the legacy dark screen.

### 3. Restyle the route surfaces and typography hierarchy

1. Use the established light vocabulary through the existing token/theme
   files: near-white route base, white grouped cards, near-black primary ink,
   muted and subtle ink for supporting copy, cyan for selected/action emphasis,
   and existing semantic state colors for warning, success, critical, info,
   and disabled states.
2. Do not place raw color, spacing, radius, font-size, weight, or letter-
   spacing literals in the redesigned UI. Consume the existing IBM Plex Sans
   Regular, Medium, Semibold, and Bold roles from [`app_typography.dart`](../lib/theme/app_typography.dart:96)
   through the route-local theme.
3. Make the route title distinct from tab labels, section headings distinct
   from metric labels, and primary metric values prominent without adding an
   eyebrow, logo, wordmark, status badge, cyan rail, introductory paragraph,
   pale-cyan card, or near-black performance card solely to imitate Home or
   Settings.
4. Allow explanatory copy, unavailable reasons, chart summaries, correction
   details, export copy, and log metadata to wrap. Do not use truncation that
   hides existing meaning.

### 4. Restyle the Overview tab without changing its content

Retain this exact section order: Real-Time Performance, Engine Comparison,
Session Summary, Offline telemetry export, Correction reports, Model Evaluation
Metrics, and Usability.

#### Performance and engine comparison

- Present Avg FPS and Avg Latency as prominent values in a readable light-card
  grouping. Keep one-decimal formatting, retain the `ms` suffix, and preserve
  empty values as `0.0` and `0.0 ms`.
- Keep one Engine Comparison summary per existing engine value. Preserve
  `No samples` for empty summaries and limit populated summaries to average
  FPS, average latency, and sample count.
- Use a flexible arrangement that may stack when width or text scale requires
  it. Do not introduce an engine selector or new comparison calculation.

#### Session summary

- Present Total detections, High-priority alerts, Frames processed, Session
  duration, and Avg confidence as readable grouped metrics.
- Keep every existing label, value source, formatting rule, cumulative versus
  retained-record meaning, and no-data behavior.
- Keep Avg confidence explicitly labeled as confidence. Never make it resemble
  Accuracy or relabel it as an evaluation result.

#### Export presentation

- Keep the semantic container label `Offline telemetry export`, its existing
  versioned/image-free/no-camera-frame/no-device-ID copy, and the accessible
  actions `Save JSON export` and `Save CSV export`.
- Restyle the actions with existing light-theme button tokens and spacing only.
  Let them stack or share a row according to available constraints and text
  scale; do not add an action, schema control, filter, or date range.
- Preserve the local busy guard: both actions are disabled while writing and
  `Saving export…` remains visible.
- Preserve the existing live-region SnackBar success filename and failure
  message `Export could not be saved. Try again.` with its error-container
  semantics. Do not replace feedback with decorative status-only UI.

#### Correction reports

- Keep Correction reports in its existing Overview position and display-only
  role. Use a readable light grouped-card treatment.
- Preserve the supplied correction service as the data source, newest-first
  order, record count semantic label, detection label, feedback, optional
  corrected label, engine, and confidence threshold.
- Preserve the exact empty text `No correction reports have been recorded in
  this session.`
- Do not add edit, delete, filtering, sorting, or correction-creation actions.

#### Unavailable evaluation and usability states

- Keep Model Evaluation Metrics and Usability as explicit unavailable content,
  not empty telemetry cards.
- Preserve the reasons: Accuracy, Precision, Recall, F1, and mAP require
  ground-truth labels from offline evaluation; SUS requires a post-test
  participant questionnaire.
- Use a subdued light card or explanatory callout only to improve hierarchy.
  Do not fabricate values, calculate new metrics, or substitute confidence for
  accuracy.

### 5. Restyle the Charts tab while preserving chart behavior

1. Keep exactly three chart regions in the existing order: latency, frames per
   second, and detection frequency.
2. Keep each existing telemetry binding and algorithm unchanged, including
   dynamic Y scaling/headroom, conditional 300 ms and 15 FPS benchmark lines,
   whole-minute frequency bucketing from the first retained record, and
   data-driven maximum Y.
3. Keep the existing [`kChartHeight`](logs-reports-screen-analysis.md:267)
   allocation of 180 logical pixels. Any visual treatment must draw inside
   that allocation and must not create overflow.
4. Use the local light surface and existing chart/theme tokens for chart cards,
   lines, bars, grid lines, benchmark lines, headings, supporting text, and
   empty presentation. Do not carry forward the legacy yellow/orange-on-dark
   palette as an assumed target and do not invent a new inline chart palette.
5. Preserve chart-drawing exclusion from the semantics tree, one textual
   summary per chart containing the existing latest/average/minimum/maximum/
   sample-count/engine information, and the exact empty text `No data available
   yet.`
6. Keep touch interaction, axis labels, and legends disabled or hidden. The
   visual result must not imply chart gestures, axis interaction, legend
   interaction, filtering, or date-range controls.

### 6. Restyle the Logs tab while preserving row meaning

1. Preserve the centered empty state `No detections recorded yet.` when there
   are no records. Use tokenized breathing room and muted supporting ink
   without adding unconfirmed decoration.
2. Preserve the newest-first scrolling list and every existing row field:
   compact priority dot, detection label, confidence percentage, engine,
   spatial position, latency in milliseconds, and trailing local-time
   `HH:mm:ss` timestamp.
3. Use light grouped rows, dividers, or card treatment only as visual choices
   within the existing composition. Do not add filter controls, engine
   grouping, pagination, export controls, or row actions.
4. Keep the compact priority dot visible. Ensure the row semantic description
   still includes High, Medium, or Low priority wording so color is not the
   only priority cue. Do not turn per-frame detections into a live region.

### 7. Preserve accessibility and responsive contracts

- Preserve labels, roles, states, values, hints, enabled status, live regions,
  chart exclusions, textual chart alternatives, correction count semantics, and
  export feedback semantics.
- Maintain usable touch targets and readable contrast through the existing
  light theme. Exact contrast ratios, focus-ring appearance, keyboard traversal,
  and TalkBack wording are not to be invented where the source documents do
  not confirm them.
- Validate that 200% text scale reflows metric summaries, export copy,
  unavailable reasons, chart summaries, correction records, and Logs rows
  without clipping, overlap, or RenderFlex overflow.

## Verification plan for the later implementation stage

1. Run the direct Logs-focused widget coverage recommended by the source
   documents, including route-local light-theme scope, all three tabs, empty and
   populated states, export busy/success/failure behavior, corrections,
   unavailable metrics, Logs priority wording, and 200% text scale/no-overflow.
2. Retain the existing [`charts_test.dart`](../test/widgets/charts_test.dart:1)
   algorithm, bound, and summary-semantic coverage. Add only presentation
   assertions justified by an actual chart visual change.
3. Run static analysis and the full Flutter test suite in the implementation
   stage; this plan does not claim either has run.
4. Verify on the required physical Android device: push and pop the route,
   confirm the underlying shell is unchanged, inspect all tabs and states,
   exercise both export actions and busy feedback, inspect corrections and
   unavailable metrics, check large text and accessibility behavior, and
   confirm no RenderFlex overflow or logcat exception.
5. Compare supported available widths using constraint-driven resizing rather
   than a fixed reference canvas. Confirm centered bounded content, stacking and
   wrapping behavior, independent scrolling, and chart allocation safety.

## Explicit non-goals

- No changes to route ownership, bottom navigation, back navigation, or the
  underlying shell.
- No service/model edits, telemetry retention or aggregation changes, new
  calculations, data-binding changes, inference-engine changes, or camera work.
- No filters, sorting, date ranges, engine-selection state, pagination, chart
  gestures, legends, axis labels, row actions, new correction mutation, or
  export-schema changes.
- No dependency additions, API changes, second light-theme builder, token
  renaming, or unrelated refactors.
- No current target export will be fabricated, and no legacy Logs & Reports
  image will be treated as the redesign target.

## Open Questions / Needs Verification

- **Exact Logs composition — Needs Verification [design-verified]:** no current
  target export confirms title treatment, card grouping, chart contrast, row
  treatment, motif assignment, or exact spacing relationships.
- **Theme motif assignment — Needs Verification [design-verified]:** confirm
  during visual QA whether any pale-cyan, dark-surface, cyan-rail, eyebrow,
  status-badge, logo, or wordmark treatment belongs on this route. None is
  authorized by imitation alone.
- **Typography mapping and radius mapping — Needs Verification
  [design-verified]:** IBM Plex Sans roles and radius roles are confirmed, but
  the absent target does not confirm exact component-to-role assignments.
- **Centered bound and responsive arrangement — Needs Verification
  [inferred-from-codebase]:** validate the approximately 480 logical-pixel
  content bound, any metric/export stacking threshold, and all supported
  available widths on the physical device. No breakpoint or device branch is
  confirmed.
- **Light chart treatment — Needs Verification [design-verified]:** confirm
  line/bar colors, grid and benchmark contrast, card grouping, heading
  treatment, padding, and empty-state alignment while retaining
  [`kChartHeight`](logs-reports-screen-analysis.md:267), algorithms, bindings,
  and semantics.
- **Logs row treatment — Needs Verification [design-verified]:** confirm card
  versus divider treatment, metadata spacing, timestamp emphasis, and priority
  token mapping while retaining all row fields and priority wording.
- **Direct screen-test filename — Needs Verification [inferred-from-codebase]:**
  the source documents recommend a dedicated Logs screen-focused widget test,
  but do not confirm the exact test path or whether a new test directory is
  preferred.
- **Accessibility and physical-device QA — Needs Verification
  [inferred-from-codebase]:** validate TalkBack announcements, live-region
  behavior, focus behavior, route push/pop, all tab states, export states,
  large text, no overflow, and logcat cleanliness after implementation.
- **Static/test status — Needs Verification [inferred-from-codebase]:** this
  plan-only stage did not run static analysis or tests.
