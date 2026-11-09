# Charts and Logs Polish — Design Spec

- **Date:** 2026-11-09
- **Feature slug:** `charts-logs-polish`
- **Stage:** 2 of 4 (design-spec). Downstream: plan → implementation, in the refinement/post-fix phase. Source-of-truth order for the implementation stage: plan → **this file** → [`charts-logs-polish-analysis.md`](charts-logs-polish-analysis.md).
- **Inputs:** [`charts-logs-polish-analysis.md`](charts-logs-polish-analysis.md) (Stage 1 — confirmed root causes, constraint surface, token inventory, tests that constrain each fix) and [`detection-alignment-charts-plan.md`](detection-alignment-charts-plan.md) (the previously shipped phase, skimmed only for what must be preserved). Both are read-only here; nothing in either is edited.
- **Task type:** UI polish/refinement with visual output change. Therefore this design-spec stage applies (`.roo/rules/02-pipeline-stages.md`). **No** logic, service, model, navigation, telemetry or backend change.
- **Scope discipline:** no code was changed in this stage. No `flutter test`, `flutter analyze`, `dart format` or build was run, and no test or analyzer result is claimed. Every current-state citation below was read from the working tree at the time of writing; every fl_chart API claim was confirmed through Context7 against the published `fl_chart` documentation (1.2.0 generation). Anything not confirmed by a file read, a Context7 result, or one of the four settled decisions is tagged per `.roo/rules/01-verification-policy.md`.

---

## 1. Scope boundary

### 1.1 In scope — the only production files this phase may modify

| File | Folder | Issue | Why |
|---|---|---|---|
| [`lib/widgets/charts.dart`](../../lib/widgets/charts.dart:1) | `lib/widgets/` (UI-owned) | 1 | X tick format, X interval-independent precision, bottom-title fit and bottom band height |
| [`lib/screens/logs_reports_screen.dart`](../../lib/screens/logs_reports_screen.dart:1) | `lib/screens/` (UI-owned) | 2, 3, 4 | `_ModelFilter` layout, Logs row subtitle, populated Logs list padding |

### 1.2 Out of scope — explicitly not touched

Per the analysis file map ([`charts-logs-polish-analysis.md`](charts-logs-polish-analysis.md) §7.3) and the preservation list (§11 there):

`lib/widgets/bounding_box_painter.dart` · `lib/widgets/status_pill.dart` · `lib/widgets/depth_heatmap_view.dart` · `lib/widgets/detection_information_overlay.dart` · `lib/widgets/detection_action_controls.dart` · `lib/screens/ultralytics_detection_screen.dart` · all of `lib/theme/` (no token is added, `kChartHeight` is not edited) · `lib/models/` · `lib/services/` · `lib/navigation/` · `lib/main.dart` · `plugins/` · `android/` · `pubspec.yaml` (the `fl_chart` version must not change — the whole axis question is answerable inside 1.2.0) · `.roo/` · the three prior phase documents.

`test/` is outside the four UI-owned folders. This phase **must** edit assertions because it changes the rendered strings and geometry those assertions name; every such edit is enumerated in §10 and is an explicitly flagged, approved consequence, not a silent expansion.

---

## 2. Preservation contract

The following shipped behaviour is the baseline this phase must not regress. Each item is cited from the tree, not from the prior plan.

| # | Behaviour that must survive | Anchor |
|---|---|---|
| P1 | Detection 16 dp gutter (viewport `Padding` inside the `Camera view` semantics node, action row `kSpace16`) | [`ultralytics_detection_screen.dart`](../../lib/screens/ultralytics_detection_screen.dart:1861) |
| P2 | Heatmap `RotatedBox` + `FittedBox(BoxFit.cover, alignment: center)` | [`depth_heatmap_view.dart`](../../lib/widgets/depth_heatmap_view.dart:24) |
| P3 | `AUDIO ON` content-sized capsule inside its 64 × 56 target | [`ultralytics_detection_screen.dart`](../../lib/screens/ultralytics_detection_screen.dart:1904) |
| P4 | Y axis: no name (`axisNameSize: 0`), `reservedSize: 64`, `_formatYAxisTick`, `kHomeInkMuted` axis + tick ink, `labelSmall` tick type, `_ChartCard` title gap `kSpace16`, FPS benchmark wording **and** line absent, 300 ms latency line present, `kChartHeight = 180` | [`charts.dart:286-311`](../../lib/widgets/charts.dart:286), [`charts.dart:354-367`](../../lib/widgets/charts.dart:354), [`logs_reports_screen.dart:1795-1804`](../../lib/screens/logs_reports_screen.dart:1795) |

Also preserved by construction: the chart semantics summaries (`_sampleSummary`, `_engineSummary`) and the bar chart's integer minute labels, which **bypass** the X formatter through the `minuteLabels` branch ([`charts.dart:323-325`](../../lib/widgets/charts.dart:323)).

---

## 3. Decision index

| # | Decision | Tag | Evidence |
|---|---|---|---|
| **D1** | X ticks use a new value-only formatter: at most **1 decimal**, trailing `.0` stripped, no thousands separators, applied **only** to the X axis of `LatencyChart`, `FpsChart` and `DetectionFrequencyChart`'s non-minute branch. Interval still `maxX / 2`. **Domain headroom rejected.** The prior phase's "X formatter byte-identical" instruction is explicitly superseded. | `[product-decision]` (settled decision 1) + code arithmetic | Settled decision 1; analysis §2.1/§2.4/§2.5; the `math.max(elapsedSeconds.last, 1.0)` floor at [`charts.dart:46`](../../lib/widgets/charts.dart:46)/[:141](../../lib/widgets/charts.dart:141) proves `xInterval >= 0.5`, so 1 decimal can never merge adjacent ticks |
| **D2a** | Rightmost tick kept and pulled inside with `SideTitleWidget(fitInside: SideTitleFitInsideData(enabled: true, distanceFromEdge: 4, parentAxisSize: meta.parentAxisSize, axisPosition: meta.axisPosition))`. **Zero plot-width cost.** `maxIncluded: false` and a right reserved gutter rejected. | `[product-decision]` (settled decision 1) + Context7-verified | Context7 `SideTitleWidget` constructor and `TitleMeta` field list, §5.3 below; analysis §2.2 |
| **D2b** | Bottom bands raised from the library defaults 22 / 22 to `reservedSize: 36` and `axisNameSize: 36` for the 14 sp `labelSmall` tick; plot height cost paid inside the unchanged `kChartHeight: 180`. | `[inferred-from-codebase]` + arithmetic (analysis §2.3 records the 22 dp values as a spec gap, its classification 1c) | §5.4 below |
| **D3** | `_ModelFilter` becomes a `Column`: the `Detector model` label above a full-card-width `DropdownButton<String?>(isExpanded: true)`, with `maxLines: 1` on every item `Text`. `MergeSemantics` and the label-first order are kept. | `[product-decision]` (settled decision 2) | §6 below; analysis §3.3 |
| **D4** | The Logs subtitle keeps **one** `Text`; the space inside the number+unit pair becomes a non-breaking space (`\u00A0`), and the ` · ` separators stay breakable. No ellipsis, no `maxLines`, no per-field `Wrap`. | `[product-decision]` (settled decision 3) | §7 below; analysis §4.2/§4.4 |
| **D5** | The populated Logs list gains `horizontal: kSpace16` and keeps `vertical: kSpace8`. `SafeArea` is **not** added (out of scope). | `[product-decision]` (settled decision 4) + `[inferred-from-codebase]` for the SafeArea call | §8 below; analysis §5.1 |

---

## 4. Issue 1a — Charts X tick precision

**Classification (from analysis §6):** (c) new requirement, superseding prior docs. Stated here because the shipped code itself carries the superseded instruction.

### 4.1 Current state (cited)

The X tick string is produced by `_formatAxisTick(value, xInterval)` ([`charts.dart:325`](../../lib/widgets/charts.dart:325)). That function derives its precision from **both** the value and the interval ([`charts.dart:336-352`](../../lib/widgets/charts.dart:336)):

```dart
String _formatAxisTick(double value, double interval) {
  var precision = 0;
  var scaledValue = value;
  var scaledInterval = interval;
  while (precision < 6 &&
      ((scaledValue - scaledValue.round()).abs() > 1e-8 ||
          (scaledInterval - scaledInterval.round()).abs() > 1e-8)) {
    scaledValue *= 10;
    scaledInterval *= 10;
    precision++;
  }
  if (precision == 0) return value.toStringAsFixed(0);
  return value
      .toStringAsFixed(precision)
      .replaceFirst(RegExp(r'0+$'), '')
      .replaceFirst(RegExp(r'\.$'), '');
}
```

`xInterval` is `maxX / 2` ([`charts.dart:85`](../../lib/widgets/charts.dart:85), [`charts.dart:176`](../../lib/widgets/charts.dart:176)) and `maxX` is wall-clock elapsed seconds ([`charts.dart:40-46`](../../lib/widgets/charts.dart:40)). A last sample at 8.3 s therefore yields ticks `0`, `4.15`, `8.3` — a two-decimal label in a 22 dp band at 200 % text scale.

`_formatAxisTick` has exactly two call sites: the Y axis was moved to `_formatYAxisTick` in the previous phase, so **X is its only caller** ([`charts.dart:325`](../../lib/widgets/charts.dart:325)). Verified by reading the file: `_formatYAxisTick` is used at [:303](../../lib/widgets/charts.dart:303).

### 4.2 Supersession statement

The prior plan ordered the X formatter kept byte-identical ([`detection-alignment-charts-plan.md:282`](detection-alignment-charts-plan.md:282)) and the shipped doc comment records the same intent ([`charts.dart:359-360`](../../lib/widgets/charts.dart:359)). **This phase supersedes that instruction for the X axis only.** The prior documents are not edited; this section is the record (`.roo/rules/01-verification-policy.md`, "No silent resolution"). The Y axis keeps `_formatYAxisTick` unchanged.

### 4.3 Target state

```dart
/// X ticks read at most one decimal.
///
/// Precision is a property of the axis, not of the interval: the elapsed-time
/// axis has at most three ticks, so the interval is never so small that one
/// decimal would merge two labels (the line charts floor `maxX` at 1.0, which
/// floors the interval at 0.5). `toStringAsFixed` never emits thousands
/// separators, and a trailing `.0` is stripped so `3.0` reads `3`.
String _formatXAxisTick(double value) {
  final text = value.toStringAsFixed(1);
  return text.endsWith('.0') ? text.substring(0, text.length - 2) : text;
}
```

- The X call site becomes `_formatXAxisTick(value)`; the `minuteLabels` branch (`'${value.round() + 1}'`) is untouched, so the bucket chart's X ticks stay integers.
- `_formatAxisTick` is **deleted** (not left dead): after the X call site moves it has no caller, so keeping it would be an unused private element and `flutter analyze` would not be clean.
- The doc comment on `_formatYAxisTick` ([`charts.dart:354-360`](../../lib/widgets/charts.dart:354)) currently says *"The X axis deliberately keeps [_formatAxisTick] …"*. It must be rewritten (the symbol it references no longer exists) to say the X axis now uses `_formatXAxisTick`.

Worked outputs, all from the formatter rule above:

| Dataset | `maxX` | `xInterval` | tick values | labels after D1 | labels today |
|---|---|---|---|---|---|
| `samples([30, 40])` | 1.0 | 0.5 | 0, 0.5, 1.0 | `0`, `0.5`, `1` | identical |
| 5 samples at 0/250/500/750/1000 ms | 1.0 | 0.5 | 0, 0.5, 1.0 | `0`, `0.5`, `1` | identical |
| 3 samples at 0/1500/3000 ms | 3.0 | 1.5 | 0, 1.5, 3.0 | `0`, `1.5`, `3` | identical |
| irregular 0/2/9 s | 9.0 | 4.5 | 0, 4.5, 9.0 | `0`, `4.5`, `9` | identical |
| **0/4150/8300 ms** | 8.3 | 4.15 | 0, 4.15, 8.3 | `0`, `4.2`, `8.3` | `0`, `4.15`, `8.3` |

The last row is the regression the current suite cannot see; it is the dataset the new test uses.

### 4.4 Acceptance criteria

1. Every X tick `Text` for a wall-clock dataset matches `^\d+(\.\d)?$` — at most one decimal, no thousands separator.
2. The existing labels `0` / `0.5` / `1` (sub-second) and `0` / `1.5` / `3` (three seconds) are **unchanged**, so the 200 %-scale assertions at [`charts_test.dart:167-169`](../../test/widgets/charts_test.dart:167) and [:202-204](../../test/widgets/charts_test.dart:202) are untouched — no assertion is relaxed or re-pinned.
3. `minX`/`maxX` and every spot x-value are unchanged (no domain headroom), so [`charts_test.dart:139-145`](../../test/widgets/charts_test.dart:139) stays green.
4. `DetectionFrequencyChart` X ticks remain the integer minute labels (`1`, `2`, `3`, …, `25`) produced by the `minuteLabels` branch.

### 4.5 Proving tests

- New: `X ticks carry at most one decimal on a wall-clock interval` (§11, T1).
- Unchanged and re-run: [`charts_test.dart:104-121`](../../test/widgets/charts_test.dart:104), [:123-147](../../test/widgets/charts_test.dart:123), [:149-182](../../test/widgets/charts_test.dart:149), [:184-217](../../test/widgets/charts_test.dart:184), [:292-311](../../test/widgets/charts_test.dart:292), [:313-321](../../test/widgets/charts_test.dart:313).

---

## 5. Issues 1b and 1c — Rightmost tick, and the bottom band height

### 5.1 Current state (cited)

- The plot's right edge **is** `maxX` ([`charts.dart:73`](../../lib/widgets/charts.dart:73), [:164](../../lib/widgets/charts.dart:164)); the bar chart lets fl_chart derive it from the last group ([`charts.dart:236-255`](../../lib/widgets/charts.dart:236)).
- The X title is centred on its tick, and `minIncluded`/`maxIncluded` default to `true`, so a label exists exactly at the plot's right edge.
- The only horizontal reservation is the **left** gutter (`reservedSize: 64`); `rightTitles` is `const AxisTitles(sideTitles: SideTitles())` ([`charts.dart:285`](../../lib/widgets/charts.dart:285)), reserving nothing. Half of the last label therefore falls outside the chart box.
- `_ChartCard` puts the chart in a bare `SizedBox(height: kChartHeight, child: child)` ([`logs_reports_screen.dart:1804`](../../lib/screens/logs_reports_screen.dart:1804)) inside `_LightCard`'s `Container`, whose only decoration is a `BoxDecoration` — **no clip is configured by the app**.
- The bottom bands are library defaults: `axisNameSize: 22` ([`charts.dart:314`](../../lib/widgets/charts.dart:314)) and `reservedSize: 22` ([`charts.dart:318`](../../lib/widgets/charts.dart:318)) are the fl_chart `SideTitles.reservedSize` default. The tick type is `labelSmall` = 14 sp under the Home theme ([`app_home_theme.dart:89-93`](../../lib/theme/app_home_theme.dart:89)).

### 5.2 Context7 evidence gathered for this stage

| API question | Verified answer | Source |
|---|---|---|
| `SideTitleWidget` constructor | `SideTitleWidget({Key? key, required Widget child, required TitleMeta meta, double space = 8.0, double angle = 0.0, SideTitleFitInsideData fitInside = const SideTitleFitInsideData(enabled: false, distanceFromEdge: 0, parentAxisSize: 0, axisPosition: 0)})` | Context7 `/websites/pub_dev_fl_chart`, class page for `SideTitleWidget` |
| `fitInside` purpose | *"Force child widget to be positioned inside its corresponding axis bounding box."* | Context7, `SideTitleFitInsideData` class page |
| `SideTitleFitInsideData` constructor | `SideTitleFitInsideData({required bool enabled, required double axisPosition, required double parentAxisSize, required double distanceFromEdge})` — all four required, `const` | Context7, `SideTitleFitInsideData` class page |
| `TitleMeta` fields | `min`, `max`, `parentAxisSize` (*parent axis max width/height*), `axisPosition` (*the position in pixel applied to this drawing title along its axis*), `appliedInterval`, `sideTitles`, `formattedValue`, `axisSide`, `rotationQuarterTurns` | Context7, `TitleMeta` class page |
| `SideTitles` fields | `showTitles`, `getTitlesWidget`, `reservedSize` (default 22), `interval`, `minIncluded` (default true), `maxIncluded` (default true). **No alignment property.** | Context7, analysis §2.2 already recorded this |
| `LineChart`/`LineChartData` `clipBehavior` | **Does not exist**; only `clipData` (`FlClipData`), which clips drawn content, not a title | Context7, analysis §2.2 |

`TitleMeta` exposes `parentAxisSize` and `axisPosition`, so option (i) can be built from the `meta` the callback already receives — no new plumbing.

### 5.3 D2a — target: keep the tick, pull it inside

```dart
        getTitlesWidget: (value, meta) => SideTitleWidget(
          meta: meta,
          space: 4,
          fitInside: SideTitleFitInsideData(
            enabled: true,
            distanceFromEdge: 4,
            parentAxisSize: meta.parentAxisSize,
            axisPosition: meta.axisPosition,
          ),
          child: Text(/* … */),
        ),
```

Why this option and not the others:

| Option | Plot-width cost | Behaviour | Verdict |
|---|---|---|---|
| (i) `fitInside` | **0 dp** — no reservation is added; only the last label's own box is shifted left inside the axis box | keeps the end-of-domain label, does not touch `maxX`, does not touch the first/middle label (their centred boxes are already inside the axis box) | **adopted** |
| (ii) right-side reserved gutter | −(half the widest X label) ≈ −20 dp at 100 %, ≈ −34 dp at 200 % — i.e. the plot loses 8–18 % of its width, and an empty gutter is drawn | keeps the label but renders nothing in the space | rejected: pays width to hold its own label |
| (iii) `maxIncluded: false` | 0 dp | **removes** the rightmost label instead of showing it | rejected: settles "the rightmost tick must not clip" by deleting the tick |
| (iv) domain headroom | 0 dp of box width, but changes `maxX` and every spot mapping | breaks [`charts_test.dart:139-145`](../../test/widgets/charts_test.dart:139) | rejected (analysis §2.2) |

**Plot-width arithmetic after the fix** (chart box = card inner width; plot = box − 64 left reserve; no right reserve added):

| Surface width | Card width | Chart box | Plot width today | Plot width after | Δ |
|---|---|---|---|---|---|
| 320 dp | 288 | 256 | 192 | **192** | 0 |
| 360 dp | 328 | 296 | 232 | **232** | 0 |
| 390 dp | 358 | 326 | 262 | **262** | 0 |

**200 %-scale overlap arithmetic** (existing assertions, which must survive unchanged). In `flutter_test` the glyph advance is ≈ 0.5 em, and `wrap()` ([`charts_test.dart:24-34`](../../test/widgets/charts_test.dart:24)) uses a bare `MaterialApp`, so the tick font is Material's default `labelSmall` (11 sp → 22 px at 200 %):

| Case | plot x-range (width 260) | tick widths | before | after `fitInside` |
|---|---|---|---|---|
| sub-second, `0.5` | ticks at 64 / 162 / 260 | `0`=11, `0.5`=33, `1`=11 | `1` spans 254.5–265.5 (**5.5 px outside**) | `1` clamped to 245–256; `0.5` at 145.5–178.5 — **no overlap** |
| themed 14 sp variant (`wrapThemed`) | same | `0`=28, `0.5`=84, `1`=28 | `1` spans 246–274 (14 px outside) | `1` clamped to 228–256; `0.5` at 120–204 — **no overlap** |

Only the tick whose box would cross an edge moves; `0` at x = 64 and `0.5` at mid-plot stay centred. `[inferred-from-codebase]` — the clamp arithmetic is derived from the documented purpose of `fitInside`, not from a run; see NV-2.

### 5.4 D2b — target: size the bottom bands for the 14 sp tick

```dart
    bottomTitles: AxisTitles(
      axisNameWidget: Text(xName, style: tickStyle, maxLines: 1),
      // Layout metric, not a design token. labelSmall is 14 sp; at 2.0 text
      // scale one line box is ~33.6 dp, so the 22 dp fl_chart default could not
      // hold it. 36 dp leaves ~2.4 dp of slack. The cost comes out of the fixed
      // kChartHeight, which is not edited.
      axisNameSize: 36,
      sideTitles: SideTitles(
        showTitles: true,
        interval: xInterval,
        reservedSize: 36,
        getTitlesWidget: (value, meta) => SideTitleWidget(/* … */),
      ),
    ),
```

Arithmetic: `14 sp × 1.2 line-height × 2.0 text scale ≈ 33.6 dp` per band → **36 dp** with ~2.4 dp slack. Both bands carry the same 14 sp style (the axis name `Text` and the tick `Text` both use `tickStyle`), so raising only one would leave the other over-constrained; the analysis records them as one spec gap (classification 1c, [`charts-logs-polish-analysis.md`](charts-logs-polish-analysis.md) §2.3).

Cost against `kChartHeight: 180`:

| | Bands | Plot height | Card height |
|---|---|---|---|
| today | 22 + 22 = 44 | 136 | 180 |
| after | 36 + 36 = 72 | **108** | 180 (unchanged) |

The plot loses 28 dp of height (≈ 21 % of the plot, ≈ 16 % of the card). `kChartHeight` is **not** raised: it is a token in [`lib/theme/app_spacing.dart`](../../lib/theme/app_spacing.dart:39), and `lib/theme/` is out of scope for this phase. The consequence — a shorter plot — is accepted and recorded as a device gate (NV-6).

### 5.5 Acceptance criteria

1. For a wall-clock dataset, the last X label's `Rect` lies fully inside the `LineChart` widget's `Rect` (right edge ≤ chart right edge, left edge ≥ chart left edge).
2. No existing tick-rect assertion changes: the sub-second and three-second overlap checks still pass, with `0`/`0.5`/`1` and `0`/`1.5`/`3` as the labels.
3. Plot width is byte-identical to today at 320/360/390 dp (no reserve added on the right).
4. The X tick and the X axis name each have ≥ 36 dp of vertical band at 200 % text scale; no chart raises an exception.
5. `maxX`, `minX`, every spot, `rightTitles` (still empty) and `topTitles` (still empty) are unchanged.

### 5.6 Proving tests

- New: `the rightmost X tick stays inside the chart box` (§11, T2) and the bottom-band guard (§11, T3, conditional — see NV-6).
- Unchanged and re-run: [`charts_test.dart:149-182`](../../test/widgets/charts_test.dart:149), [:184-217](../../test/widgets/charts_test.dart:184), [:219-232](../../test/widgets/charts_test.dart:219), [:333-347](../../test/widgets/charts_test.dart:333), [:349-365](../../test/widgets/charts_test.dart:349), and the Logs & Reports `Charts has no overflow at 200 percent text scale` ([`logs_reports_screen_test.dart:1314-1326`](../../test/screens/logs_reports_screen_test.dart:1314)).

---

## 6. Issue 2 — `All models (mixed)` truncates

### 6.1 Current state (cited)

`_ModelFilter.build` ([`logs_reports_screen.dart:2019-2062`](../../lib/screens/logs_reports_screen.dart:2019)) is a `_LightCard` → `MergeSemantics` → `Row[Text('Detector model', bodyLarge), SizedBox(kSpace12), Expanded(DropdownButtonHideUnderline(DropdownButton<String?>(isExpanded: true, …)))]`. Each item `Text` carries `overflow: TextOverflow.ellipsis` with **no `maxLines`**.

Structural cause (analysis §3.3): the `Detector model` label is not flexible, so an 18 sp label plus a 12 dp gap is taken out of the single row before the dropdown's own chrome (expand icon + padding) is subtracted; the `Expanded` value column is what is left. `TextOverflow.ellipsis` turns the resulting shortage into a truncated value rather than a visible failure, which is why `Charts has no overflow at 200 percent text scale` cannot catch it.

### 6.2 Target state — `Detector model` above, full-width dropdown

```dart
    return _LightCard(
      // The label and the dropdown still merge into one labelled control node,
      // and the label is still first so the merged label starts with it.
      child: MergeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Detector model', style: theme.textTheme.bodyLarge),
            const SizedBox(height: kSpace8),
            DropdownButtonHideUnderline(
              child: DropdownButton<String?>(
                isExpanded: true,
                value: selected,
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text(
                      _allModelsLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  for (final model in models)
                    DropdownMenuItem<String?>(
                      value: model.key,
                      child: Text(
                        model.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: onChanged,
              ),
            ),
          ],
        ),
      ),
    );
```

Exact values: `kSpace8` (8 dp) replaces the former horizontal `kSpace12` gap as a vertical gap; `bodyLarge` (18 sp w500) label unchanged; the dropdown text keeps inheriting the framework default (`titleMedium` = 18 sp w600 under `buildHomeTheme()`); card padding stays `_LightCard`'s 16 dp.

Why this shape:

- The value never competes with the label again: the value's available width goes from `cardInner − label − 12 − chrome` to `cardInner − chrome`.
- `maxLines: 1` is added because it is what makes truncation *measurable*: with `maxLines: null` the ellipsis path is ambiguous and `RenderParagraph.didExceedMaxLines` is not a reliable signal. With `maxLines: 1` + `ellipsis`, `didExceedMaxLines == false` means "the whole value was laid out".
- `CrossAxisAlignment.stretch` guarantees the dropdown receives the full card width regardless of how `isExpanded` resolves inside a `Column`; the label `Text` is left-aligned by default, so the visible label is unchanged.

Width arithmetic at 390 dp after the D5 fix (card 358, inner 326):

| | Current Row (Charts today) | After Column (both tabs) |
|---|---|---|
| label + gap consumed | ~110 dp at 18 sp (100 %) | 0 — the label is on its own line |
| value available before chrome | ~148 dp | **~270–286 dp** |
| `All models (mixed)` needs at 18 sp | ~160 dp | same |

Glyph estimates are `[inferred-from-codebase]` arithmetic (analysis §3.3 records the same caveat); the structural conclusion does not depend on them.

### 6.3 Contracts that must survive, and how

| Contract | Anchor | How it survives |
|---|---|---|
| One merged semantics node whose label **starts with** `Detector model`, contains the selected value, `isButton`, has `tap` | [`logs_reports_screen_test.dart:2252-2261`](../../test/screens/logs_reports_screen_test.dart:2252) | `MergeSemantics` still wraps the whole subtree; the label `Text` is still the **first** child in traversal order; the `DropdownButton` still supplies the button flag and tap action |
| `DropdownButton<String?>` findable by type (`find.byType(DropdownButton<String?>).first` / `.tap`) | [:1572](../../test/screens/logs_reports_screen_test.dart:1572), [:1724](../../test/screens/logs_reports_screen_test.dart:1724), [:1778](../../test/screens/logs_reports_screen_test.dart:1778), [:1811](../../test/screens/logs_reports_screen_test.dart:1811), [:1824](../../test/screens/logs_reports_screen_test.dart:1824), [:2245](../../test/screens/logs_reports_screen_test.dart:2245) | the widget type and its generic argument are unchanged; it is still the first `DropdownButton<String?>` in the tree |
| `find.text('All models (mixed)')` is `findsOneWidget` | [:1563](../../test/screens/logs_reports_screen_test.dart:1563), [:1749](../../test/screens/logs_reports_screen_test.dart:1749) | the label is still one `Text` whose `data` is `_allModelsLabel`; no wrapping widget is introduced around it |
| Menu item taps by text (`find.text('Built-in YOLOv8n').last`) | [:1826](../../test/screens/logs_reports_screen_test.dart:1826), [:1574](../../test/screens/logs_reports_screen_test.dart:1574) | item construction is unchanged apart from `maxLines` |
| The four 200 %-scale no-overflow tests (Overview, Alert Latency, Charts, Logs) | [:1286-1340](../../test/screens/logs_reports_screen_test.dart:1286) | a taller card and an ellipsised value raise nothing; `takeException()` stays null |

### 6.4 Acceptance criteria

1. At 390 dp and 100 % text scale, `RenderParagraph.didExceedMaxLines` for the `All models (mixed)` item `Text` is **false** on both the Charts and the Logs tab.
2. The merged semantics node contract of §6.3 still holds (one node, label starts with `Detector model`, button flag, tap action).
3. The selector is still a `DropdownButton<String?>`; selection still filters charts and the log list.
4. No layout exception at 200 % text scale on either tab.
5. Visible label text, weight and role are unchanged; only its position (above vs beside) and the gap (8 dp vertical vs 12 dp horizontal) change.

### 6.5 Proving tests

- New: `the model filter shows All models mixed whole` and the cross-tab gutter check (§11, T5/T6).
- Unchanged and re-run: every row of §6.3 plus `filtering to one model names it in the chart cards` ([:1566-1591](../../test/screens/logs_reports_screen_test.dart:1566)) and `the log list filters to one model but keeps the filter` ([:1817-1836](../../test/screens/logs_reports_screen_test.dart:1817)).

### 6.6 Known residual

At 200 % text scale on a 390 dp surface the value may still ellipsise by a small margin, because the dropdown's icon and padding are not scalable. Truncation there is **visual only**: the merged semantics node carries the full string, so a screen-reader user is never given a partial value. Whether to shrink the value (for example `FittedBox(scaleDown)`) rather than ellipsise it at 200 % is left as a device gate, not silently decided — NV-4.

---

## 7. Issue 3 — Logs metadata rows wrap inside `58 ms`

### 7.1 Current state (cited)

The populated Logs row's subtitle is **one** `Text` built by `[...].join(' · ')` ([`logs_reports_screen.dart:1418-1427`](../../lib/screens/logs_reports_screen.dart:1418)) with default `softWrap: true`, no `maxLines`, no `overflow`. One field is `'${r.latencyMs.toStringAsFixed(0)} ms'` ([:1425](../../lib/screens/logs_reports_screen.dart:1425)) — an internal space, i.e. a legal line-break opportunity. Flutter's line breaker therefore splits `58` / `ms` when the width runs out.

### 7.2 Candidates and their test impact (from analysis §4.4)

| Candidate | Effect on `58 ms` | Metadata visibility | Test delta |
|---|---|---|---|
| `softWrap: false` + `maxLines: 1` + ellipsis | no split | **hidden** — long model names vanish behind `…` | 0 assertion edits |
| per-field `Wrap(spacing: kSpace8)` | no split | preserved | 4 assertions break (no single `Text` holds the joined string) + separators disappear |
| **non-breaking space inside number+unit** | no split | preserved | 4 assertions break (the separator string changes) |
| `maxLines: 2` only | still splits | preserved | 0 | 

### 7.3 D4 — target state

Keep one `Text`; make only the number+unit pair unbreakable:

```dart
                      subtitle: Text(
                        [
                          // The readable model name comes first: it is what the
                          // numbers below belong to.
                          if (r.detectorModelName != null) r.detectorModelName!,
                          r.engine.label,
                          r.position,
                          // Non-breaking space keeps the number and its unit on
                          // one line. The ` · ` separators stay breakable so a
                          // long model name wraps between fields, never inside a
                          // value.
                          '${r.latencyMs.toStringAsFixed(0)}\u00A0ms',
                        ].join(' · '),
                      ),
```

Why the non-breaking space over the per-field `Wrap`:

- It is the smallest diff that satisfies the settled decision ("values such as `58 ms` must stay together").
- It keeps the ` · ` visual language that the row already has and that four assertions describe.
- It cannot hide metadata: the separators remain break opportunities, so a row with a long model name wraps **at a field boundary** instead of dropping text — which is the settled decision's second half ("rows must not wrap unnecessarily" = wrap only when it is necessary, never inside a value).

Explicitly rejected: an ellipsis that hides metadata (settled decision 3 forbids silently hiding values).

The `title` line `'person — 82%'` ([`:1416`](../../lib/screens/logs_reports_screen.dart:1416)) and the `trailing` timestamp are **not** in scope: the decision names metadata *values* (the subtitle), and neither of those carries a number+unit pair.

### 7.4 Acceptance criteria

1. No rendered Logs subtitle contains a normal space between a digit run and `ms` — i.e. `rb'(\d) ms'` never matches a subtitle `Text.data`.
2. `58 ms` / `100 ms` / `120 ms` are laid out as one unbroken run at every width the tests exercise (100 % and 200 % scale).
3. No part of the subtitle is clipped or ellipsised: the `Text` keeps `softWrap: true`, `maxLines` unset and no `overflow`.
4. Field order is unchanged (model name first, then engine, position, latency).

### 7.5 Proving tests

- Edited: the four `textContaining` assertions listed in §10 (they name the joined string).
- New: `a log row keeps the latency number and unit together` (§11, T7).

---

## 8. Issue 4 — Logs filter-card geometry must match Charts

### 8.1 Current state (cited)

| | Charts tab | Logs tab (populated) |
|---|---|---|
| Container | `_BoundedScrollView` ([`logs_reports_screen.dart:1291`](../../lib/screens/logs_reports_screen.dart:1291)) → `SafeArea` → `LayoutBuilder` → `Center` → `ConstrainedBox(480)` → `ListView` | `LayoutBuilder` → `Center` → `ConstrainedBox(480)` → `ListView.builder` ([`logs_reports_screen.dart:1384-1392`](../../lib/screens/logs_reports_screen.dart:1384)) — no `SafeArea` |
| List padding | `EdgeInsets.symmetric(horizontal: kSpace16, vertical: kSpace16)` ([:1684-1687](../../lib/screens/logs_reports_screen.dart:1684)) | `EdgeInsets.symmetric(vertical: kSpace8)` — **horizontal 0** ([:1395](../../lib/screens/logs_reports_screen.dart:1395)) |

At 390 dp: Charts card left 16 / right 374 / width **358** / content left **32**; Logs card left 0 / right 390 / width **390** / content left **16**.

### 8.2 D5 — target state

```dart
                  itemCount: records.length + 1,
                  // Horizontal inset matches every Charts card so both tabs
                  // share one gutter; the vertical rhythm is unchanged.
                  padding: const EdgeInsets.symmetric(
                    horizontal: kSpace16,
                    vertical: kSpace8,
                  ),
```

- `horizontal: kSpace16` — the same token the Charts list and `_LightCard` use.
- `vertical: kSpace8` **kept**, and the filter row's own `EdgeInsets.only(bottom: kSpace8)` ([:1399](../../lib/screens/logs_reports_screen.dart:1399)) kept, so the vertical rhythm is untouched.
- `SafeArea` is **not** added. Justification from the code, not preference: `SafeArea` insets the **top/bottom/left/right** parts of the window; the horizontal difference in scope is 0 for this app's portrait surface, and the populated Logs list is the only one of the four states without it — adding it would change vertical insets in the same step as a horizontal-alignment fix, i.e. widen the diff for no horizontal benefit. Recorded as `[inferred-from-codebase]`, and as an open item (NV-5).

Geometry after the fix:

| Surface | Charts card | Logs card (populated) after | Equal? |
|---|---|---|---|
| 390 dp | left 16, right 374, width 358, inner 326 | left 16, right 374, width 358, inner 326 | **yes** |
| 320 dp | left 16, right 304, width 288, inner 256 | left 16, right 304, width 288, inner 256 | **yes** |
| 600 dp (bounded) | card 448, inner 416 | card 448, inner 416 | **yes** |

### 8.3 Coupling with Issue 2 (must be designed together)

This fix narrows the Logs filter card by **32 dp** (16 dp per side). Applied alone it would make Issue 2's truncation **worse** on the Logs tab. D3 (§6) is therefore not optional: it must land in the same phase, and the acceptance for Issue 2 is evaluated against the **post-D5** width (326 dp inner at 390 dp), not today's 358 dp. Order: D5 first (the narrower card is the real constraint), then D3 measured against it.

### 8.4 Acceptance criteria

1. At 390 dp and 320 dp, the populated Logs filter card's horizontal extent equals the Charts filter card's horizontal extent.
2. The Logs list keeps its 8 dp vertical rhythm and its `kSpace8` filter-row gap.
3. Charts, Logs-empty and Logs-populated now share one gutter; Logs-empty is unchanged (it already used `_BoundedScrollView`).
4. No test that asserts the Logs rows' presence or order changes.

### 8.5 Proving tests

- New: `the Logs filter card shares the Charts gutter` (§11, T6) — a same-test cross-tab comparison, because no existing test asserts any rectangle (analysis §5.2).
- Unchanged and re-run: `Logs has no overflow at 200 percent text scale` ([:1328-1340](../../test/screens/logs_reports_screen_test.dart:1328)), `populated logs render a newest-first row` ([:705-717](../../test/screens/logs_reports_screen_test.dart:705)).

---

## 9. Token table

### 9.1 Used (all existing)

| Token | Value | Source | Used by |
|---|---|---|---|
| `kSpace16` | 16 | [`app_spacing.dart:27`](../../lib/theme/app_spacing.dart:27) | D5 horizontal list inset (and the unchanged `_LightCard` padding) |
| `kSpace8` | 8 | [`app_spacing.dart:15`](../../lib/theme/app_spacing.dart:15) | D3 label→dropdown vertical gap; D5 vertical inset (unchanged) |
| `kRadius14` | 14 | [`app_radii.dart:18`](../../lib/theme/app_radii.dart:18) | card radius — unchanged |
| `kHomeSurfaceCard` | `#FFFFFF` | [`app_colors.dart:75`](../../lib/theme/app_colors.dart:75) | card surface — unchanged |
| `kHomeInkMuted` | `#667085` | [`app_colors.dart:84`](../../lib/theme/app_colors.dart:84) | axis stroke + tick ink — unchanged |
| `labelSmall` | 14 sp w500 | [`app_home_theme.dart:89`](../../lib/theme/app_home_theme.dart:89) | chart tick type — unchanged |
| `bodyLarge` | 18 sp w500 | [`app_home_theme.dart:69`](../../lib/theme/app_home_theme.dart:69) | `Detector model` label — unchanged |
| `kChartHeight` | 180 | [`app_spacing.dart:39`](../../lib/theme/app_spacing.dart:39) | chart allocation — **not edited**; D2b's cost is paid inside it |

### 9.2 Not added

No new token, and **no theme file is edited**.

- `reservedSize: 36`, `axisNameSize: 36`, `distanceFromEdge: 4`, `space: 4` are layout metrics inside one private function; the prior design-spec already recorded them as intentionally local literals ([`detection-alignment-charts-design-spec.md:380`](detection-alignment-charts-design-spec.md:380)), and adding a token for a single-consumer axis budget is the same anti-pattern.
- D3, D4 and D5 are expressed entirely with `kSpace8` / `kSpace16` and no new value.
- A non-breaking space is a character, not a token.

---

## 10. Test-impact table

### 10.1 Assertions that must be edited (4 — all from D4)

| file:line | Current assertion | Required change |
|---|---|---|
| [`logs_reports_screen_test.dart:714`](../../test/screens/logs_reports_screen_test.dart:714) | `find.textContaining('Ultralytics · center · 120 ms')` | `find.textContaining('Ultralytics · center · 120\u00A0ms')` |
| [`logs_reports_screen_test.dart:1530`](../../test/screens/logs_reports_screen_test.dart:1530) | `find.textContaining('Built-in YOLOv8n · Ultralytics · center · 100 ms')` | `… 'center · 100\u00A0ms'` |
| [`logs_reports_screen_test.dart:1535`](../../test/screens/logs_reports_screen_test.dart:1535) | `find.textContaining('Obstacle Detector v2 · Ultralytics · center · 100 ms')` | `… 'center · 100\u00A0ms'` |
| [`logs_reports_screen_test.dart:1832`](../../test/screens/logs_reports_screen_test.dart:1832) | `find.textContaining('Built-in YOLOv8n · Ultralytics · center · 100 ms')` | `… 'center · 100\u00A0ms'` |

A repository-wide search for `center · ` in `test/` returns exactly these four sites, so no other assertion carries the joined subtitle string. `find.textContaining('Obstacle Detector v2 · ')` at [:1835](../../test/screens/logs_reports_screen_test.dart:1835) is unaffected (no number+unit pair).

### 10.2 Assertions that must **not** change (and why they survive)

| file:line | Assertion | Why it survives |
|---|---|---|
| [`charts_test.dart:167-169`](../../test/widgets/charts_test.dart:167) | `['0','0.5','1']` each `findsWidgets` at 200 %, width 260 | D1 keeps one decimal, so `0.5` is still produced; `maxX`/interval unchanged |
| [`charts_test.dart:202-204`](../../test/widgets/charts_test.dart:202) | `['0','1.5','3']` | same |
| [`charts_test.dart:170-180`](../../test/widgets/charts_test.dart:170), [:205-215](../../test/widgets/charts_test.dart:205) | tick rects do not overlap | tick count and values unchanged; `fitInside` only shifts the last label inward (§5.3 arithmetic) |
| [`charts_test.dart:308`](../../test/widgets/charts_test.dart:308) | `find.textContaining(RegExp(r'\.\d\d'))` `findsNothing` | D1 guarantees ≤ 1 decimal on X as well; the assertion now guards both axes and is not weakened |
| [`charts_test.dart:139-145`](../../test/widgets/charts_test.dart:139) | `minX 0`, `maxX 9`, spots `[0,2,9]` | no domain headroom was adopted |
| [`charts_test.dart:316-319`](../../test/widgets/charts_test.dart:316) | `10`/`20`/`30`/`40` `findsOneWidget`, `10.0` absent | X ticks there are `0`/`0.5`/`1`; no collision with Y integers |
| [`charts_test.dart:328`](../../test/widgets/charts_test.dart:328), [:344-345](../../test/widgets/charts_test.dart:344) | `39.8`, `width + 4 <= 64` | Y axis untouched |
| [`charts_test.dart:358-363`](../../test/widgets/charts_test.dart:358) | tick colour + `labelSmall` size | `tickStyle` untouched |
| [`logs_reports_screen_test.dart:1563`](../../test/screens/logs_reports_screen_test.dart:1563), [:1749](../../test/screens/logs_reports_screen_test.dart:1749) | `find.text('All models (mixed)')` `findsOneWidget` | still exactly one `Text` with that `data` |
| [`logs_reports_screen_test.dart:1572`](../../test/screens/logs_reports_screen_test.dart:1572), [:1824](../../test/screens/logs_reports_screen_test.dart:1824), [:2245](../../test/screens/logs_reports_screen_test.dart:2245) | `find.byType(DropdownButton<String?>).first` | same widget type and generic |
| [`logs_reports_screen_test.dart:2252-2261`](../../test/screens/logs_reports_screen_test.dart:2252) | one merged node, `^Detector model`, button, tap | `MergeSemantics` + label-first order retained |
| [`logs_reports_screen_test.dart:1314-1326`](../../test/screens/logs_reports_screen_test.dart:1314), [:1328-1340](../../test/screens/logs_reports_screen_test.dart:1328) | 200 % no overflow (Charts, Logs) | ellipsis/`Wrap`-free changes raise nothing; taller card is inside scrolling lists |
| [`logs_reports_screen_test.dart:711`](../../test/screens/logs_reports_screen_test.dart:711) | `find.text('person — 82%')` | title untouched |
| [`semantics_test.dart:342-401`](../../test/accessibility/semantics_test.dart:342) | chart summary prefixes | `_sampleSummary` / `_engineSummary` untouched |

### 10.3 Preservation-list suites to re-run (must not regress)

[`detection_screen_alignment_test.dart`](../../test/screens/detection_screen_alignment_test.dart:1), [`depth_heatmap_view_test.dart`](../../test/widgets/depth_heatmap_view_test.dart:23), [`gesture_navigation_direction_test.dart`](../../test/screens/gesture_navigation_direction_test.dart:250). None imports `charts.dart` or the Logs tab, so they are safe by non-overlap — but they must be run, not assumed.

---

## 11. New assertions required

| # | Test (new) | File | Assertion |
|---|---|---|---|
| **T1** | `X ticks carry at most one decimal on a wall-clock interval` | `test/widgets/charts_test.dart` | dataset 0/4150/8300 ms → `find.text('4.2')` `findsOneWidget`; `find.text('4.15')` `findsNothing`; `find.text('8.3')` `findsOneWidget`; `find.textContaining(RegExp(r'\.\d\d'))` `findsNothing` |
| **T2** | `the rightmost X tick stays inside the chart box` | `test/widgets/charts_test.dart` | same dataset at width 320 → `chartRect = getRect(find.byType(LineChart))`, `lastRect = getRect(find.text('8.3'))`; `lastRect.right <= chartRect.right`; `lastRect.left >= chartRect.left`; the bottom-most `0` label also satisfies `left >= chartRect.left` |
| **T3** | `X ticks fit the raised bottom band at 200 percent text scale` | `test/widgets/charts_test.dart` | `wrapThemed(LatencyChart(samples([30, 40])), textScale: 2, width: 320)`; `getSize(find.text('0.5')).height <= 36` — conditional, see NV-6 |
| **T5** | `the model filter shows All models mixed whole` | `test/screens/logs_reports_screen_test.dart` | on Charts at 390 dp / 100 %: `paintedParagraph(tester, find.text('All models (mixed)')).didExceedMaxLines` `isFalse`; repeat for the Logs tab |
| **T6** | `the Logs filter card shares the Charts gutter` | `test/screens/logs_reports_screen_test.dart` | in one test: `getTopLeft(find.text('Detector model')).dx` on Logs equals `getTopLeft(<the Inference Latency card title>).dx` on Charts; both cards are the first child of a 16 dp `_LightCard`, so equality proves a shared gutter |
| **T7** | `a log row keeps the latency number and unit together` | `test/screens/logs_reports_screen_test.dart` | every rendered row subtitle `Text.data` matches neither `RegExp(r'\d ms')`; for the `Ultralytics · center · 120 ms` fixture the subtitle is one laid-out line (`computeLineMetrics().length == 1`, API name NV-7) |

T5 must be added inside the group that already defines the local `paintedParagraph` helper ([`logs_reports_screen_test.dart:1367`](../../test/screens/logs_reports_screen_test.dart:1367)) — that helper is local to its group, so a test outside it cannot call it.

---

## 12. Risks

| # | Risk | Likelihood | Mitigation |
|---|---|---|---|
| R1 | `fitInside` shifts more than the last label, so an existing tick-rect assertion fails | low | the overlap assertions are kept as-is and re-run first; the arithmetic in §5.3 shows interior ticks stay centred |
| R2 | Raising both bottom bands to 36 makes the plot feel short on device | medium | accepted and stated (plot 108 of 180); device gate NV-6; reverting `axisNameSize` to 22 is a one-line rollback |
| R3 | D5 alone (narrower Logs card) makes Issue 2 worse if D3 is deferred | medium | D3 is ordered **after** D5 and evaluated against the post-D5 width (§8.3); the two land in the same phase |
| R4 | A non-breaking space looks like a stray gap in some font | low | `\u00A0` renders at normal space width in IBM Plex; device gate NV-8 |
| R5 | The estimator of "All models (mixed) needs ~160 dp" is arithmetic, not measurement | medium | acceptance is the font-independent `didExceedMaxLines == false`, not a width number |
| R6 | `_formatAxisTick` deletion leaves a dangling doc reference | low | the `_formatYAxisTick` doc comment is rewritten in the same step; `flutter analyze` catches any residue |
| R7 | The test font's advance makes a width assertion pass that would fail on device | medium | T5 asserts *overflow*, not width; the device check is a separate gate (NV-9) |
| R8 | Bar chart minute labels accidentally routed through the new formatter | very low | the `minuteLabels` branch is untouched and is asserted by [`charts_test.dart:117-121`](../../test/widgets/charts_test.dart:117) |

**Rollback:** each change is a single, independently revertible block — P1/P2 in `charts.dart`, P3/P4/P5 in `logs_reports_screen.dart`. No data, setting, telemetry or persistence schema is touched, so rollback has no migration cost.

---

## 13. Open Questions / Needs Verification

### 13.1 Confirmed but must not be over-claimed

- **NV-1 `[inferred-from-codebase]` — which render object performs the *visible* clip is still unverified.** The geometry is certain (the title is centred on `maxX`, which is the plot's right edge; `rightTitles` reserves nothing). What is not confirmed is whether fl_chart clips title children or lets them paint outside the box. The design therefore does not claim "the card clips it"; it fixes the geometry (`fitInside`) and lets T2 assert containment.
- **NV-2 `[inferred-from-codebase]` — `fitInside` clamp behaviour is documented, not measured.** Context7 confirms the parameter and its purpose and that `TitleMeta` supplies `axisPosition`/`parentAxisSize`. The claim that interior ticks are not shifted is derived from that purpose, not from a run.
- **NV-3 `[inferred-from-codebase]` — the 1.2 line-height factor in the 33.6 dp arithmetic is an assumption.** IBM Plex Sans metrics are not pinned by `buildHomeTheme()`. If the real line box is taller, 36 dp may still be tight at 200 %; the measured value should replace the estimate if T3 disagrees.
- **NV-6 `[product-decision]` — the 108 dp plot height is a trade accepted here, not measured on device.** Whether a 28 dp shorter plot still reads acceptably at 200 % text scale is a device judgement; T3 is the mechanical guard, the device pass is the real one. If it reads badly, the fallback is to keep `reservedSize: 36` and revert `axisNameSize` to 22 (plot 122 dp) and record the axis name as over-constrained.
- **NV-7 `[inferred-from-codebase]` — the exact API for counting laid-out lines.** `RenderParagraph.computeLineMetrics()` is believed to exist; if it is unavailable, T7 falls back to comparing `tester.getSize(subtitleFinder).height` against a one-line bound. This must be confirmed at implementation time, not assumed.

### 13.2 Product / device decisions

- **NV-4 `[product-decision]` — 200 % behaviour of the model selector.** D3 guarantees full display at 100 %; at 200 % on 390 dp the value may still ellipsise because the dropdown icon and padding do not scale. Options if the device check rejects it: accept (semantics always carries the full string), or shrink the value with `FittedBox(scaleDown)` (full text, smaller type at large text scale). Needs a decision from Luke after the device pass. **Decided 2026-11-09: accepted as-is** — no `FittedBox` and no type-role change; recorded as non-blocking polish.
- **NV-5 `[inferred-from-codebase]` — `SafeArea` is deliberately left out of D5.** It does not change left/right insets for a portrait phone surface, so it cannot affect the alignment this phase fixes; adding it is a separate vertical-geometry change. If Luke wants the populated Logs state to match the other three states structurally, that is a separate, larger step.
- **NV-8 `[product-decision]` — does a non-breaking space read correctly on device?** It should render at normal space width in IBM Plex Sans, but this is confirmed only by looking at the device.
- **NV-9 `[product-decision]` — the device-only gates, all of which no widget test can substitute for** (Snapdragon 695 / API 33, per `.roo/rules/rules-frontend/07-verification.md`):
  1. X label legibility at 100 % and 200 % with real glyph advances.
  2. The rightmost tick's appearance after `fitInside` — flush rather than cramped.
  3. `All models (mixed)` rendered whole at 100 %, and the accepted-or-not 200 % behaviour (NV-4).
  4. Metadata row single-line behaviour per field, including a long imported model name at 200 %.
  5. Cross-tab visual parity of the Logs and Charts filter cards.

  **Status (2026-11-09): all five gates and NV-8 were confirmed on the target
  Android device** in the device-verification pass — X labels legible at 100 % and
  200 %, the clamped rightmost tick flush inside the plot, `All models (mixed)`
  rendered whole (the 200 % case accepted per NV-4), metadata rows staying on one
  line, and matching Logs/Charts filter cards. X ticks for very large elapsed
  domains (6+ character values) were **not** separately exercised and still rely
  on the reserved 36 dp band — a non-blocking note, not a defect.
- **NV-10 `[product-decision]` — whether to record the new device gates in [`known-issues.md`](../../docs/known-issues.md).** If the implementation stage adds them there, the `.roo/rules/docs/` allow-list re-copy rule applies (`known-issues.md` is allow-listed). This phase does not require it.

### 13.3 Files an implementer might suspect, and why they are out of scope

| File | Why it looks necessary | Why it is not |
|---|---|---|
| [`lib/theme/app_spacing.dart`](../../lib/theme/app_spacing.dart:1) (`kChartHeight`) | restoring the 136 dp plot after D2b | `lib/theme/` is out of scope; the card height change would ripple to every chart card and is a separate decision |
| [`lib/theme/app_home_theme.dart`](../../lib/theme/app_home_theme.dart:64) | dropping `titleMedium` to 16 sp would fit `All models (mixed)` at 200 % | changes every screen's typography — a redesign, not a polish fix |
| [`lib/screens/logs_reports_screen.dart:1707`](../../lib/screens/logs_reports_screen.dart:1707) `_LightCard` padding | narrowing the Logs card | would change every card in Overview, Charts and Logs; the defect is the list's padding |
| [`lib/services/telemetry_service.dart`](../../lib/services/telemetry_service.dart:1) | `RuntimeSample.timestamp` drives `maxX` | presentation concern; mutating recorded timestamps would corrupt telemetry and exports |
| [`test/widgets/charts_test.dart:24`](../../test/widgets/charts_test.dart:24) `wrap()` helper | adding a theme so ticks are 14 sp | a themed helper already exists ([`wrapThemed`, :40](../../test/widgets/charts_test.dart:40)); new tests choose the right helper explicitly rather than changing an existing one |

---

*End of design spec. No code, test, theme or doc file other than this one was created or modified.*
