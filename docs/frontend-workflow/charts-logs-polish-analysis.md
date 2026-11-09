# Charts and Logs Polish — Analysis

- **Date:** 2026-11-09
- **Feature slug:** `charts-logs-polish`
- **Stage:** 1 of 4 (analysis). Downstream stages: design-spec → plan → implementation (refinement/post-fix phase).
- **Task type:** UI polish with visual output change — chart axis tick formatting, chart axis label bounds, and Logs & Reports layout geometry. **No logic, service, model, navigation, telemetry or backend change.** Because visual output changes, the design-spec stage applies (`.roo/rules/02-pipeline-stages.md`).
- **Scope discipline:** no code was changed in this stage. No `flutter test`, `flutter analyze`, `dart format` or build was run. Every snippet and line number below was read from the current working tree at the time of writing. Anything not directly confirmed by a file read or a Context7 documentation result is tagged `Needs Verification` per `.roo/rules/01-verification-policy.md`.
- **Read-only inputs for this stage:** [`detection-alignment-charts-analysis.md`](detection-alignment-charts-analysis.md), [`detection-alignment-charts-design-spec.md`](detection-alignment-charts-design-spec.md), [`detection-alignment-charts-plan.md`](detection-alignment-charts-plan.md). They are quoted here, never edited.

---

## 1. What the previous phase shipped (verified in the current tree)

The four items below are the shipped state this phase must not undo. Each is confirmed by reading the current file, not by trusting the plan.

| # | Shipped behaviour | Evidence in the current tree |
|---|---|---|
| P1 | 16 dp Detection gutter (viewport inset inside `Semantics`, action row `kSpace16`) | [`ultralytics_detection_screen.dart`](../../lib/screens/ultralytics_detection_screen.dart:1861) action-row inset; the `ValueKey('detection-viewport')` anchor and `Padding` live inside the `Camera view` node |
| P2 | Heatmap `RotatedBox` + `FittedBox(BoxFit.cover, alignment: center)` | [`depth_heatmap_view.dart`](../../lib/widgets/depth_heatmap_view.dart:1) |
| P3 | `AUDIO ON` content-sized capsule in a 64 × 56 target | [`ultralytics_detection_screen.dart`](../../lib/screens/ultralytics_detection_screen.dart:1904) `_AudioPill` |
| P4 | Chart Y axis: **no** name (`axisNameSize: 0`), `reservedSize: 64`, Y-only `_formatYAxisTick`; axis stroke `kHomeInkMuted`; ticks `labelSmall` in `kHomeInkMuted`; `_ChartCard` title gap `kSpace16`; 15 FPS wording **and** its dashed line removed, 300 ms latency line kept | [`charts.dart:286-311`](../../lib/widgets/charts.dart:286) left axis; [`charts.dart:279-282`](../../lib/widgets/charts.dart:279) `tickStyle`; [`charts.dart:361-367`](../../lib/widgets/charts.dart:361) `_formatYAxisTick`; [`charts.dart:88-99`](../../lib/widgets/charts.dart:88) latency-only `extraLinesData`; [`logs_reports_screen.dart:1795-1805`](../../lib/screens/logs_reports_screen.dart:1795) `_ChartCard`; [`logs_reports_screen.dart:1305`](../../lib/screens/logs_reports_screen.dart:1305) FPS title without the 15 FPS suffix |

**X-axis state carried into this phase (the important one):** the X axis was deliberately left untouched. The plan's step C1.6 ordered *"**Keep** `xName`, `axisNameSize: 22`, `interval: xInterval`, `reservedSize: 22`, `space: 4`, and the `minuteLabels ? … : _formatAxisTick(value, xInterval)` expression byte-identical"* ([`detection-alignment-charts-plan.md:282`](detection-alignment-charts-plan.md:282)), and the shipped code carries a doc comment saying so:

```dart
/// The X axis deliberately keeps [_formatAxisTick]: fractional elapsed-time
/// ticks (`0.5`, `1.5`) carry meaning and are asserted at 200% text scale.
String _formatYAxisTick(double value, double interval) {
```
— [`charts.dart:359-361`](../../lib/widgets/charts.dart:359)

---

## 2. Issue 1 — Charts X axis: tick precision and rightmost-label clipping

### 2.1 Confirmed root cause A: precision comes from an arbitrary interval

Current X configuration ([`charts.dart:312-332`](../../lib/widgets/charts.dart:312)):

```dart
    bottomTitles: AxisTitles(
      axisNameWidget: Text(xName, style: tickStyle, maxLines: 1),
      axisNameSize: 22,
      sideTitles: SideTitles(
        showTitles: true,
        interval: xInterval,
        reservedSize: 22,
        getTitlesWidget: (value, meta) => SideTitleWidget(
          meta: meta,
          space: 4,
          child: Text(
            minuteLabels
                ? '${value.round() + 1}'
                : _formatAxisTick(value, xInterval),
            style: tickStyle,
            maxLines: 1,
            softWrap: false,
          ),
        ),
      ),
    ),
```

The X interval is derived from the **data**, not from a round scale:

| Chart | `xInterval` expression | Line |
|---|---|---|
| `LatencyChart` | `xInterval: maxX / 2` | [`charts.dart:85`](../../lib/widgets/charts.dart:85) |
| `FpsChart` | `xInterval: maxX / 2` | [`charts.dart:176`](../../lib/widgets/charts.dart:176) |
| `DetectionFrequencyChart` | `xInterval: math.max((buckets.length / 4).ceilToDouble(), 1)` | [`charts.dart:251`](../../lib/widgets/charts.dart:251) |

and `maxX` is itself a continuous quantity — the elapsed seconds of the **last sample**:

```dart
    final maxX = math.max(elapsedSeconds.last, 1.0);
```
— [`charts.dart:46`](../../lib/widgets/charts.dart:46) (latency) and [`charts.dart:141`](../../lib/widgets/charts.dart:141) (FPS), where `elapsedSeconds` is `timestamp.difference(firstTime).inMicroseconds / 1000000` ([`charts.dart:40-45`](../../lib/widgets/charts.dart:40)).

`_formatAxisTick` then derives its precision from **both the value and the interval** ([`charts.dart:336-352`](../../lib/widgets/charts.dart:336)):

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

**Consequence:** whenever `maxX / 2` is not a 1-decimal number, *every* X label inherits that many decimals — up to the 6-decimal cap. `elapsedSeconds.last` is real wall-clock elapsed time, so the common case is not round.

Current X tick strings, derived from the datasets the tests actually use:

| Dataset | `maxX` | `xInterval` | X ticks (values) | Rendered strings |
|---|---|---|---|---|
| `samples([30, 40])` (2 samples, 1 s apart) — [`charts_test.dart:107`](../../test/widgets/charts_test.dart:107) | 1.0 | 0.5 | 0, 0.5, 1.0 | `0`, `0.5`, `1` |
| 5 samples at 0/250/500/750/1000 ms — [`charts_test.dart:163`](../../test/widgets/charts_test.dart:163) | 1.0 | 0.5 | 0, 0.5, 1.0 | `0`, `0.5`, `1` |
| 3 samples at 0/1500/3000 ms — [`charts_test.dart:198`](../../test/widgets/charts_test.dart:198) | 3.0 | 1.5 | 0, 1.5, 3.0 | `0`, `1.5`, `3` |
| Irregular 0/2/9 s — [`charts_test.dart:137`](../../test/widgets/charts_test.dart:137) | 9.0 | 4.5 | 0, 4.5, 9.0 | `0`, `4.5`, `9` |
| `DetectionFrequencyChart(buckets: [0, 4, 1])` — [`charts_test.dart:117`](../../test/widgets/charts_test.dart:117) | 2 (bars 0..2) | `ceil(3/4)` = 1 | 0, 1, 2 → minute labels | `1`, `2`, `3` |
| `DetectionFrequencyChart(buckets: List.filled(30, 12))` — [`charts_test.dart:225`](../../test/widgets/charts_test.dart:225) | 29 | `ceil(7.5)` = 8 | 0, 8, 16, 24 → minute labels | `1`, `9`, `17`, `25` |

The precision pathology is not exercised by any existing test because every test dataset happens to produce a 0- or 1-decimal interval. A real recording with an arbitrary `elapsedSeconds.last` (for example 8.3 s) yields `xInterval = 4.15`, hence labels `0`, `4.15`, `8.3`; at 200 % text scale `4.15` is a four-glyph label in a `reservedSize: 22` band. **No test pins the two-decimal X case**, so this defect is currently unguarded. [inferred-from-codebase]

### 2.2 Confirmed root cause B: the rightmost label is centred on the plot's right edge

Geometry, provable from the code without running anything:

- The plot's right edge **is** `maxX` ([`charts.dart:73`](../../lib/widgets/charts.dart:73), [`charts.dart:164`](../../lib/widgets/charts.dart:164)); the bar chart has no `maxX` override so fl_chart derives it from the last bar group ([`charts.dart:236-255`](../../lib/widgets/charts.dart:236)).
- fl_chart includes a title at the maximum data value by default — Context7 confirms `SideTitles.minIncluded = true` and `maxIncluded = true` are the defaults, documented as *"a title for the maximum data value is included independent of the sampling interval"*.
- The title is positioned **centred on its tick**, and the only horizontal reservation in the chart is the **left** gutter (`reservedSize: 64`, [`charts.dart:298`](../../lib/widgets/charts.dart:298)). `rightTitles` is explicitly empty — `rightTitles: const AxisTitles(sideTitles: SideTitles())` ([`charts.dart:285`](../../lib/widgets/charts.dart:285)) — so nothing is reserved on the right.
- Therefore half of the last label lies outside the `LineChart`/`BarChart` box. Nothing in the Logs & Reports tree clips it deliberately either: `_ChartCard` places the chart in a bare `SizedBox(height: kChartHeight, child: child)` ([`logs_reports_screen.dart:1804`](../../lib/screens/logs_reports_screen.dart:1804)) inside `_LightCard`'s `Container` ([`logs_reports_screen.dart:1706`](../../lib/screens/logs_reports_screen.dart:1706)), and a `Container` with only a `BoxDecoration` does not clip. Whatever clipping the user sees is therefore produced by fl_chart's own title layout, not by the app. `Needs Verification` — see NV-1.

**Where the fix belongs (analysis, not decision).** Context7 resolves the API question the plan stage must not guess at:

| API question | Verified answer | Source |
|---|---|---|
| Does `SideTitleWidget` expose `fitInside`? | **Yes.** `SideTitleWidget({…, double space = 8.0, double angle = 0.0, SideTitleFitInsideData fitInside = const SideTitleFitInsideData(enabled: false, distanceFromEdge: 0, parentAxisSize: 0, axisPosition: 0)})`. Documented as *"To force widget to be positioned within its axis bounding box, define fitInside"*. | Context7 `/websites/pub_dev_fl_chart` |
| Does `LineChart` / `LineChartData` expose `clipBehavior`? | **No.** `LineChartData` has `clipData` (`FlClipData` with `top`/`right`/`bottom`/`left`), which clips the **drawn series/grid to the border** — it is not a widget `clipBehavior` and cannot "unclip" a title. | Context7 `/websites/pub_dev_fl_chart` |
| What does `SideTitles` expose? | `showTitles`, `getTitlesWidget`, `reservedSize` (**default 22**), `interval`, `minIncluded` (default true), `maxIncluded` (default true). There is **no alignment property** on `SideTitles`. | Context7 `/websites/pub_dev_fl_chart` |
| What does `TitleMeta` carry? | `axisPosition` (pixel position along the axis), `parentAxisSize`, `axisSide`, `appliedInterval`, `min`, `max`, `formattedValue`. | Context7 `/websites/pub_dev_fl_chart` |

So the realistic candidate mechanisms are:

1. `SideTitleWidget(fitInside: SideTitleFitInsideData(enabled: true, distanceFromEdge: n, parentAxisSize: meta.parentAxisSize, axisPosition: meta.axisPosition))` — the documented way to keep a title inside its axis box; the last label would then be flush inside the right edge instead of centred on it. Requires choosing `n`.
2. `SideTitles(maxIncluded: false)` — drop the maximum-value title entirely; the plot's right edge then has no label to clip, at the cost of losing the end-of-domain label.
3. A rounder `xInterval` that keeps the last tick off the exact right edge (only partially effective: `maxIncluded: true` still forces a label at `maxX`).
4. Right-side headroom in the domain (`maxX` enlarged) — **this would break existing assertions** on `maxX` and on spot x-values ([`charts_test.dart:139-145`](../../test/widgets/charts_test.dart:139)), so it is the costliest option and should be avoided unless the other three are rejected.

**Not a candidate:** adding `clipBehavior` to the chart widget — the property does not exist on `LineChart`/`LineChartData`.

### 2.3 Secondary finding in the same axis: the bottom bands are library defaults

`reservedSize: 22` and `axisNameSize: 22` ([`charts.dart:314`](../../lib/widgets/charts.dart:314), [`charts.dart:318`](../../lib/widgets/charts.dart:318)) are **the fl_chart defaults for `reservedSize`** — they were never sized for the tick type the previous phase introduced. The tick is now `labelSmall` = **14 sp** ([`app_home_theme.dart:89-93`](../../lib/theme/app_home_theme.dart:89)); at 200 % text scale that is a ~34 dp line box in a 22 dp band, so the X tick text (and the X axis name above it, in a second 22 dp band) is vertically over-constrained at 200 %. The previous phase recorded this risk as its NV3 (bottom `axisNameSize` 22 → 36 as an approved fallback) but left the reserve unchanged. This is a **contributing factor to "the rightmost tick does not render cleanly"** and must be considered together with the horizontal clipping. The number is `Needs Verification` — see NV-3.

### 2.4 Supersession statement (explicit)

The prior plan and the shipped code both state that the X formatter must stay byte-identical, and the shipped doc comment says fractional X ticks are asserted at 200 % text scale. **The current instruction supersedes those docs for the X axis only.** The plan/spec files are read-only here; the design-spec stage must record the supersession rather than silently editing them (`.roo/rules/01-verification-policy.md`, "No silent resolution").

### 2.5 Tests that constrain the X formatter (must be re-decided, not ignored)

| Test | file:line | What it pins today |
|---|---|---|
| `sub-second elapsed ticks are accurate and fit narrowly` | [`charts_test.dart:149-182`](../../test/widgets/charts_test.dart:149) | `find.text('0')`, `'0.5'`, `'1'` each `findsWidgets`; tick rects do not overlap; at `textScale: 2, width: 260` |
| `fractional elapsed ticks above one second stay accurate` | [`charts_test.dart:184-217`](../../test/widgets/charts_test.dart:184) | `find.text('0')`, `'1.5'`, `'3'`; rects do not overlap |
| `line-chart X values use elapsed seconds at irregular intervals` | [`charts_test.dart:123-147`](../../test/widgets/charts_test.dart:123) | `minX 0`, `maxX 9`, spot x-values `[0, 2, 9]` |
| `populated charts show named axes and numeric ticks` | [`charts_test.dart:104-121`](../../test/widgets/charts_test.dart:104) | `find.text('Elapsed time (s)')`, `find.text('Minute')`, and `find.text('0')` / `'1'` present |
| `X axis names fit at narrow width and 200% text scale` | [`charts_test.dart:219-232`](../../test/widgets/charts_test.dart:219) | axis-name-only (Y names already gone) |
| `Y ticks are single line and never carry two decimals` | [`charts_test.dart:292-311`](../../test/widgets/charts_test.dart:292) | every `Text` starting with a digit has `maxLines == 1` / `softWrap == false`; `find.textContaining(RegExp(r'\.\d\d'))` is `findsNothing` |
| `an integer Y interval renders integer ticks` | [`charts_test.dart:313-321`](../../test/widgets/charts_test.dart:313) | `10`/`20`/`30`/`40` and `10.0` absent — note the X ticks in that dataset are `0`, `0.5`, `1`, so a stricter X rule must not collide with `find.text('10')` etc. |
| `a fractional Y interval keeps exactly one decimal` | [`charts_test.dart:323-331`](../../test/widgets/charts_test.dart:323) | `find.text('39.8')` |
| `the widest Y tick fits the reserved gutter at 200 percent text scale` | [`charts_test.dart:333-347`](../../test/widgets/charts_test.dart:333) | `width + 4 <= 64` for `39.8` under `wrapThemed(textScale: 2, width: 320)` |
| `chart axes and ticks share the muted ink token` | [`charts_test.dart:349-365`](../../test/widgets/charts_test.dart:349) | border colours == `kHomeInkMuted`; tick style colour + `labelSmall` size |
| `DetectionFrequencyChart` X via `minuteLabels` | [`charts.dart:324`](../../lib/widgets/charts.dart:324) | integer minute labels bypass `_formatAxisTick` entirely — an X-formatter change must not disturb them |

Critical interaction: `find.text('0')` at [`charts_test.dart:110`](../../test/widgets/charts_test.dart:110) / `'1'` at [:120](../../test/widgets/charts_test.dart:120) is satisfied by *either* axis, so tightening the X formatter cannot by itself break them; but a change that removes the `0.5`/`1.5` labels **does** break [:167-169](../../test/widgets/charts_test.dart:167) and [:202-204](../../test/widgets/charts_test.dart:202). Whether those two assertions survive depends on the target format the design-spec settles (NV-4): "at most one decimal" keeps `0.5` and `1.5`; "integer-only" removal does not.

---

## 3. Issue 2 — The model selector truncates `All models (mixed)`

### 3.1 The string source

```dart
/// The explicit "no filter" choice, so an unfiltered summary never reads as one
/// model's performance.
const String _allModelsLabel = 'All models (mixed)';
```
— [`logs_reports_screen.dart:1818-1820`](../../lib/screens/logs_reports_screen.dart:1818)

It is rendered only by the first `DropdownMenuItem` ([`logs_reports_screen.dart:2038-2043`](../../lib/screens/logs_reports_screen.dart:2038)). The field comment at [`logs_reports_screen.dart:85-87`](../../lib/screens/logs_reports_screen.dart:85) documents `null` as *the explicit "All models (mixed)" option*.

### 3.2 Current widget tree (quoted)

```dart
    return _LightCard(
      // The sibling label and the dropdown's own button/expanded annotation
      // merge into a single labelled control node; layout is unchanged.
      child: MergeSemantics(
        child: Row(
          children: [
            Text('Detector model', style: theme.textTheme.bodyLarge),
            const SizedBox(width: kSpace12),
            Expanded(
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String?>(
                  isExpanded: true,
                  value: selected,
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text(
                        _allModelsLabel,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    for (final model in models)
                      DropdownMenuItem<String?>(
                        value: model.key,
                        child: Text(
                          model.label,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: onChanged,
                ),
              ),
            ),
          ],
        ),
      ),
    );
```
— [`logs_reports_screen.dart:2019-2062`](../../lib/screens/logs_reports_screen.dart:2019)

### 3.3 The truncation chain (each link verified in the tree)

1. **`_LightCard` inner padding is 16 dp per side** — `padding: const EdgeInsets.all(kSpace16)` ([`logs_reports_screen.dart:1707`](../../lib/screens/logs_reports_screen.dart:1707)).
2. **`Text('Detector model')` is not flexible.** It is a direct `Row` child with no `Flexible`/`Expanded`/`FittedBox`, so it always consumes its **full intrinsic width** and never yields. At `bodyLarge` = **18 sp** ([`app_home_theme.dart:69-73`](../../lib/theme/app_home_theme.dart:69)) that is ~14 characters ≈ 110 dp at 100 % scale and ≈ 220 dp at 200 %.
3. **`SizedBox(width: kSpace12)`** = 12 dp ([`logs_reports_screen.dart:2031`](../../lib/screens/logs_reports_screen.dart:2031)).
4. **`Expanded` + `DropdownButton(isExpanded: true)`** — `isExpanded` makes the *item area* fill the `Expanded` width, and (Flutter framework behaviour) the selected item is rendered from an `IndexedStack` of **all** items, so one width serves every item; the item `Text`s each carry `overflow: TextOverflow.ellipsis` with no `maxLines`, which is the code path that silently truncates instead of wrapping.
5. **The dropdown's own chrome eats part of that Expanded width** — internal horizontal padding and the trailing expand icon are subtracted before the item `Text` is laid out. There is **no `selectedItemBuilder`**, so the selected value cannot use a wider/different presentation than the menu items.

Net width available to the value text, ignoring the unmeasured dropdown chrome:

`available ≈ cardInnerWidth − labelIntrinsic − 12 − chrome`, where `cardInnerWidth = outerAvailable − 32`.

| Tab / screen | outer available | card inner | label at 100 % (~18 sp) | remainder after label+gap | after ~56 dp of dropdown chrome | `All models (mixed)` needs ≈160 dp at 18 sp |
|---|---|---|---|---|---|---|
| Charts, 390 dp | 390 − 32 = 358 | 326 | ~110 | ~204 | **~148** | **truncated** |
| Logs, 390 dp (current, zero outer padding) | 390 | 358 | ~110 | ~236 | **~180** | fits, barely |
| Charts, 390 dp, 200 % scale | 326 | 326 | ~220 | ~94 | **~38** | severely truncated |

The `100 %`/`200 %` glyph estimates are `[inferred-from-codebase]` arithmetic, not measurements — the qualitative conclusion (the value column is starved, and the label never yields) holds regardless. [inferred-from-codebase]

**Structural cause, stated without metrics:** the selector gives a fixed, non-shrinking `Text` and a 12 dp gap priority over the control it names, and it reserves nothing for the dropdown's icon and padding. At 200 % text scale the value column collapses, and `TextOverflow.ellipsis` converts that into a truncated `All models (mixed)` rather than a visible failure. This also explains why **Issue 2 and Issue 4 interact**: the Logs tab currently has 16 dp more usable width per side only because its list has no horizontal padding (Issue 4).

### 3.4 Tests that constrain the selector

| Test | file:line | What it pins |
|---|---|---|
| `unfiltered summaries are labelled mixed-model data` | [`logs_reports_screen_test.dart:1541-1564`](../../test/screens/logs_reports_screen_test.dart:1541) | `expect(find.text('All models (mixed)'), findsOneWidget);` ([:1563](../../test/screens/logs_reports_screen_test.dart:1563)); also asserted at [:1749](../../test/screens/logs_reports_screen_test.dart:1749). **`find.text` requires the exact `Text` widget to exist with that exact string** — a restructure must keep one `Text` whose `data == 'All models (mixed)'` (or the assertion must change). |
| `filtering to one model names it in the chart cards` | [`logs_reports_screen_test.dart:1566-1591`](../../test/screens/logs_reports_screen_test.dart:1566) | Drives `find.byType(DropdownButton<String?>)` — `first` tap ([:1572](../../test/screens/logs_reports_screen_test.dart:1572)) then `find.text('Obstacle Detector v2').last` ([:1574](../../test/screens/logs_reports_screen_test.dart:1574)). **The widget must remain a `DropdownButton<String?>` reachable by type**, so replacing it with a custom menu breaks this test. |
| model-filter semantics | [`logs_reports_screen_test.dart:2245-2261`](../../test/screens/logs_reports_screen_test.dart:2245) | One merged node whose label **starts with** `Detector model` (`RegExp(r'^Detector model')`), contains the selected value, `isButton == true`, has a `tap` action. Constrains any layout change: the label must remain in the same `MergeSemantics` subtree **and stay first** in traversal order. |
| `Charts has no overflow at 200 percent text scale` | [`logs_reports_screen_test.dart:1314-1326`](../../test/screens/logs_reports_screen_test.dart:1314) | Only asserts `takeException() is null` — a truncated dropdown raises nothing, so **this test cannot catch the defect**. |
| TalkBack merged filter node note | [`known-issues.md`](../../.roo/rules/docs/known-issues.md) TalkBack section | The filter was deliberately made one `MergeSemantics` node; that contract must survive. |

---

## 4. Issue 3 — Logs tab metadata rows wrap unnecessarily

### 4.1 The row builder (quoted)

The populated Logs tab is a `ListView.builder` whose rows are `ListTile`s ([`logs_reports_screen.dart:1412-1434`](../../lib/screens/logs_reports_screen.dart:1412)):

```dart
                    return ListTile(
                      dense: true,
                      leading: _PriorityDot(priority: r.priority),
                      title: Text(
                        '${r.label} — ${(r.confidence * 100).toStringAsFixed(0)}%',
                      ),
                      subtitle: Text(
                        [
                          // The readable model name comes first: it is what the
                          // numbers below belong to.
                          if (r.detectorModelName != null) r.detectorModelName!,
                          r.engine.label,
                          r.position,
                          '${r.latencyMs.toStringAsFixed(0)} ms',
                        ].join(' · '),
                      ),
                      trailing: Text(
                        time,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: kHomeInkMuted,
                        ),
                      ),
                    );
```

### 4.2 Why `58 ms` splits

Three properties of that one `Text` combine:

1. **It is a single `Text` containing spaces**, with **no `maxLines`, no `softWrap`, no `overflow`** — all defaults, i.e. `softWrap: true`, unlimited lines, clip.
2. **Flutter's line breaker breaks at spaces.** The field rendered is `'${r.latencyMs.toStringAsFixed(0)} ms'` ([:1425](../../lib/screens/logs_reports_screen.dart:1425)) — an internal space between the number and the unit. `58 ms` therefore *can* be split into `…58` / `ms`, and the `' · '` separators are themselves break opportunities.
3. **The available width is genuinely short.** Inside the tile: `leading` dot 14 dp + the tile's content gaps, `trailing` time (`HH:MM:SS`, `bodySmall`, roughly 8 glyphs) with the tile's 16 dp end padding, and the tile's own 16 dp start padding. On a 390 dp surface the subtitle box is on the order of 250–260 dp while the joined string `Built-in YOLOv8n · Ultralytics · center · 100 ms` is ~47 characters — already wider than the box at 100 % scale, and several times wider at 200 %.

So the wrap is not a layout accident in one tile: the row is a **single flowing paragraph** carrying four independent metadata fields, and any wrap it takes breaks wherever the width runs out — including between a number and its unit.

### 4.3 Every row shape the same builder renders

The `subtitle` field order is fixed but conditional, so these shapes all flow through the one `Text`:

| Case | Rendered subtitle | Notes |
|---|---|---|
| Named model, all fields | `Built-in YOLOv8n · Ultralytics · center · 100 ms` | asserted at [`logs_reports_screen_test.dart:1530`](../../test/screens/logs_reports_screen_test.dart:1530) |
| Second named model | `Obstacle Detector v2 · Ultralytics · center · 100 ms` | [:1535](../../test/screens/logs_reports_screen_test.dart:1535) |
| No detector model recorded | `Ultralytics · center · 120 ms` | [:714](../../test/screens/logs_reports_screen_test.dart:714) |
| Ambiguous same-named model | `Obstacle Detector v2 · bbbb… · Ultralytics · …` (the `_ModelOption.label` carries a fingerprint suffix, [`logs_reports_screen.dart:1920-1922`](../../lib/screens/logs_reports_screen.dart:1920)) | longest shape → worst wrapping |
| Long imported model name | up to the accepted 40-character display name | see the "long detector display name" fixture at [`logs_reports_screen_test.dart:1996`](../../test/screens/logs_reports_screen_test.dart:1996) |

Two more metadata rows share the **same defect class** but are not the Logs tab and are therefore *not* in scope for this item (listed so the design-spec does not assume the builder is the only culprit):

- `trailing` timestamp — `HH:MM:SS` in `bodySmall`; a single unbreakable token, so it cannot split, but it is fixed-width pressure on the subtitle.
- `title` — `'person — 82%'`; contains a space around the em dash, so it can wrap too at 200 %.

### 4.4 Fix candidates and their differing test impact (analysis, not decision)

| Candidate | Effect on `58 ms` | Test impact |
|---|---|---|
| `softWrap: false, maxLines: 1, overflow: TextOverflow.ellipsis` on the subtitle | Cannot split; long values ellipsize | `find.textContaining('… · 120 ms')` still passes (the string is unchanged); but at 200 % a long model name ends in `…`, so full metadata becomes unreadable → NV-8 |
| Replace the space inside `n ms` (and the ` · ` separators) with non-breaking characters | Cannot split; wraps only where allowed | **Breaks** [`logs_reports_screen_test.dart:714`](../../test/screens/logs_reports_screen_test.dart:714), [:1530](../../test/screens/logs_reports_screen_test.dart:1530), [:1535](../../test/screens/logs_reports_screen_test.dart:1535), [:1832](../../test/screens/logs_reports_screen_test.dart:1832) — `String.contains` will not match an NBSP/word-joiner string |
| `Wrap(spacing: kSpace8)` of one `Text` per field | Each field unbreakable; wraps only between fields | **Breaks the same four `textContaining` assertions** (no single `Text` carries the whole joined string) |
| Keep wrapping but constrain to a 2-line block with `maxLines: 2` | Still splits `58 ms` | Does not solve the stated defect |

The choice is a **product decision** (NV-8) because every option trades truncation against wrapping and carries a different test delta. Nothing here is resolved.

---

## 5. Issue 4 — Logs filter card geometry does not match the Charts tab

### 5.1 The numbers

Both tabs build on the same primitives — `Center` → `ConstrainedBox(maxWidth: 480)` → a vertical list, with cards from `_LightCard` (`padding: EdgeInsets.all(kSpace16)`, radius `kRadius14`, `kHomeSurfaceCard`, `kHomeShadowSoft`). The difference is **which list** each tab uses.

| | Charts tab | Logs tab (populated) | Logs tab (empty) |
|---|---|---|---|
| Container | `_BoundedScrollView` ([`logs_reports_screen.dart:1291`](../../lib/screens/logs_reports_screen.dart:1291)) | raw `LayoutBuilder → Center → ConstrainedBox(480) → ListView.builder` ([`logs_reports_screen.dart:1384-1392`](../../lib/screens/logs_reports_screen.dart:1384)) | `_BoundedScrollView` ([`logs_reports_screen.dart:1364`](../../lib/screens/logs_reports_screen.dart:1364)) |
| List padding **horizontal** | `kSpace16` = **16** ([`logs_reports_screen.dart:1684-1687`](../../lib/screens/logs_reports_screen.dart:1684)) | **0** — `EdgeInsets.symmetric(vertical: kSpace8)` only ([`logs_reports_screen.dart:1395`](../../lib/screens/logs_reports_screen.dart:1395)) | `kSpace16` = **16** |
| List padding **vertical** | `kSpace16` = 16 | `kSpace8` = 8, plus a `kSpace8` bottom gap on the filter row ([`logs_reports_screen.dart:1399`](../../lib/screens/logs_reports_screen.dart:1399)) | 16 |
| `SafeArea` | yes | **no** | yes |
| Filter card outer edges @390 dp | left **16**, right **374** | left **0**, right **390** | left 16, right 374 |
| Filter card width @390 dp | **358** | **390** | 358 |
| Card inner padding | 16 | 16 | 16 |
| Filter **content** inset from screen edge @390 dp | **32** | **16** | 32 |
| Chart card title left @390 dp | **32** | n/a | n/a |
| Card radius / colour | `kRadius14` / `kHomeSurfaceCard` | `kRadius14` / `kHomeSurfaceCard` | same |

**The unambiguous difference:** the Logs tab's filter card is **32 dp wider** than every Charts tab card (16 dp on each side), and its content sits **16 dp closer to the screen edge** than the chart cards' content. The same tab also swaps the vertical rhythm (16 top vs 8 top + 8 gap) and drops the `SafeArea` wrapper.

A second-order consequence that the design-spec must weigh: fixing Issue 4 by adding `kSpace16` to the Logs list **narrows** the Logs filter card by 32 dp, which makes Issue 2's truncation **worse** on the Logs tab. The two fixes are coupled and must be designed together.

### 5.2 Existing coverage

No test asserts any of these rectangles: `test/screens/logs_reports_screen_test.dart` contains no `getRect` / `getSize` assertion (verified by search). The only geometry-adjacent guards are the four 200 % no-overflow tests ([`logs_reports_screen_test.dart:1286`](../../test/screens/logs_reports_screen_test.dart:1286), [:1300](../../test/screens/logs_reports_screen_test.dart:1300), [:1314](../../test/screens/logs_reports_screen_test.dart:1314), [:1328](../../test/screens/logs_reports_screen_test.dart:1328)), which assert only `takeException() is null`.

---

## 6. Classification: implementation bug vs spec gap vs new requirement

Per `.roo/rules/rules-postfix/01-scope.md`, each item is classified before any fix is prescribed. Nothing is resolved by picking the most likely reading.

| Issue | Class | Reasoning |
|---|---|---|
| **1a — X tick precision** | **(c) new requirement, superseding prior docs** | The prior plan ordered the X formatter kept byte-identical ([`detection-alignment-charts-plan.md:282`](detection-alignment-charts-plan.md:282)); the shipped code documents the same intent ([`charts.dart:359-360`](../../lib/widgets/charts.dart:359)). The code **matches** those docs, so this is not an implementation bug. The current instruction to make X ticks concise with ~1 decimal directly contradicts them → new requirement, explicit supersession (§2.4). |
| **1b — rightmost-tick clipping** | **(c) new requirement** | Neither the prior analysis, design-spec nor plan mentions the right edge: the plan's X scope was "byte-identical" and its risk table only covers Y reserve and the bottom axis *name* (NV3). No prior doc is contradicted; this is newly in scope. |
| **1c — bottom `reservedSize`/`axisNameSize` = 22 at 200 %** | **(b) spec gap** | The prior design-spec knew the tick became 14 sp and kept `reservedSize: 22`, then recorded the risk only for the axis *name* (raise `axisNameSize` 22 → 36). The docs are incomplete: they never specified a height budget for the 14 sp tick band itself. The code matches the docs; the **docs** are the weak point. Flag, do not silently patch. |
| **2 — `All models (mixed)` truncation** | **(c) new requirement** (pre-existing latent defect) | `_ModelFilter` existed before this phase and no prior doc states a fit requirement for it; the prior design-spec's §1.2/§1.3 lists `_ModelFilter` only as a *read* context, never as a change site. So the code cannot be "wrong" against a doc. It is a real defect now brought into scope → new requirement. Nothing about label colour, weight or spacing is broken, so (a) does not apply. |
| **3 — Logs metadata row wrapping** | **(c) new requirement** (pre-existing latent defect) | Same reasoning: no prior doc constrains the Logs row. The row is a deliberate design (the model name was deliberately moved first — see the comment at [`logs_reports_screen.dart:1420-1421`](../../lib/screens/logs_reports_screen.dart:1420)), it simply has no wrapping policy. Not (a). |
| **4 — Logs filter card geometry vs Charts** | **(c) new requirement**, with an (a)-flavoured note | No doc states the two tabs must share a gutter, so a doc cannot be violated. But the *implementation* is internally inconsistent: the Charts tab, and the Logs tab's own **empty** state, both use `_BoundedScrollView` (16 dp + `SafeArea`), while the Logs tab's populated state uses a hand-rolled list with zero horizontal padding. The inconsistency is inside one file. Recorded as (c) + flagged as an internal-consistency defect so the design-spec does not treat the current numbers as intentional. |

**No item is class (a).** That is itself a finding: in every case the previous phase did what its docs said, so there is no implementation regression to chase — the work is new requirements plus one doc gap (1c).

---

## 7. File map

### 7.1 UI-owned files (the only folders a fix may touch)

| File | Folder | Needed by | Why |
|---|---|---|---|
| [`lib/widgets/charts.dart`](../../lib/widgets/charts.dart:1) | `lib/widgets/` (UI-owned) | Issue 1 | X formatter, X interval source, bottom `SideTitles`/`SideTitleWidget` (`fitInside`, `reservedSize`, `axisNameSize`) |
| [`lib/screens/logs_reports_screen.dart`](../../lib/screens/logs_reports_screen.dart:1) | `lib/screens/` (UI-owned) | Issues 2, 3, 4 | `_ModelFilter` (2), `_LogsTab` row builder (3), `_LogsTab` list padding (4) |
| [`lib/theme/app_spacing.dart`](../../lib/theme/app_spacing.dart:1) — **only if** a genuinely new value is required | `lib/theme/` (UI-owned) | Issues 1/3/4 **only if** | See §9 — the analysis does **not** justify a new token today |

### 7.2 Minimal file set per issue

| Issue | Minimal change surface |
|---|---|
| 1 | `charts.dart` only (one formatter + bottom-axis block). `_ChartCard`/`kChartHeight` in `logs_reports_screen.dart` only if the reserve must grow (NV-3). |
| 2 | `logs_reports_screen.dart` only, `_ModelFilter.build` (`:2019-2062`). |
| 3 | `logs_reports_screen.dart` only, the `subtitle:` expression (`:1418-1427`) and possibly the `ListTile` flags. |
| 4 | `logs_reports_screen.dart` only, the populated `ListView.builder` (`:1392-1395`). |

Four fixes, two source files, no overlap in edit regions.

### 7.3 Out of scope (must not be touched)

| File / area | Why it looks tempting | Why it is out |
|---|---|---|
| `test/**` | The fixes will invalidate some assertions | `test/` is outside the four UI-owned folders ([`.roo/rules/rules-frontend/01-scope.md`](../../.roo/rules/rules-frontend/01-scope.md)). Changes there must be **explicitly flagged and approved** by the plan stage — the analysis only enumerates them (§8). |
| [`lib/theme/app_home_theme.dart`](../../lib/theme/app_home_theme.dart:1) | Tick type comes from `labelSmall` (14 sp); the selector label from `bodyLarge` (18 sp) | Reading a theme role is not editing a theme. Changing `labelSmall`/`bodyLarge` would move every screen. |
| [`lib/widgets/status_pill.dart`](../../lib/widgets/status_pill.dart:1), [`detection_action_controls.dart`](../../lib/widgets/detection_action_controls.dart:1), [`detection_information_overlay.dart`](../../lib/widgets/detection_information_overlay.dart:1), [`depth_heatmap_view.dart`](../../lib/widgets/depth_heatmap_view.dart:1), [`ultralytics_detection_screen.dart`](../../lib/screens/ultralytics_detection_screen.dart:1) | Previous phase's shipped areas | Preservation list (§11). Out of both scope and necessity. |
| `lib/models/*`, `lib/services/*`, `lib/navigation/*`, `lib/main.dart` | `_ModelOption`/`DetectorModelTable` live in a model/service | The fixes are presentation-only. `_ModelOption`, `_modelOptions`, `_modelClaim` and `_samplesFor` are **private to the screen file** and do not need to change. |
| `plugins/*`, `android/*`, `pubspec.yaml`, `.roo/**`, the three prior pipeline docs | — | Forbidden by this stage's scope. `fl_chart` version must **not** change: the whole axis question is answered within 1.2.0 (Context7). |

---

## 8. Constraint surface — every assertion the fixes touch or must keep passing

### 8.1 Will need editing (the change invalidates them by construction)

| file:line | Assertion | Invalidated by |
|---|---|---|
| [`charts_test.dart:167-169`](../../test/widgets/charts_test.dart:167) | `for (final label in ['0', '0.5', '1']) expect(find.text(label), findsWidgets);` at 200 %, width 260 | Issue 1a **only if** the target format drops fractional X ticks. If the target is "≤1 decimal", `0.5` survives. NV-4 decides. |
| [`charts_test.dart:202-204`](../../test/widgets/charts_test.dart:202) | same for `['0', '1.5', '3']` | Same as above. |
| [`charts_test.dart:170-180`](../../test/widgets/charts_test.dart:170) | tick-rect overlap check | Only if tick *count* changes. |
| [`charts_test.dart:308`](../../test/widgets/charts_test.dart:308) | `find.textContaining(RegExp(r'\.\d\d'))` `findsNothing` | Now also guards X; the assertion text may be re-scoped/renamed, not weakened. |
| [`logs_reports_screen_test.dart:714`](../../test/screens/logs_reports_screen_test.dart:714), [:1530](../../test/screens/logs_reports_screen_test.dart:1530), [:1535](../../test/screens/logs_reports_screen_test.dart:1535), [:1832](../../test/screens/logs_reports_screen_test.dart:1832) | `find.textContaining('… · center · 100 ms')` | Issue 3 **only if** the fix replaces the space/NBSP or splits the subtitle into multiple `Text` widgets. |
| [`logs_reports_screen_test.dart:1563`](../../test/screens/logs_reports_screen_test.dart:1563), [:1749](../../test/screens/logs_reports_screen_test.dart:1749) | `find.text('All models (mixed)')` | Issue 2 **only if** the label stops being one `Text` with that exact `data`. |

### 8.2 Must keep passing unchanged

| file:line | Why it constrains |
|---|---|
| [`charts_test.dart:123-147`](../../test/widgets/charts_test.dart:123) | `minX 0`, `maxX 9`, spot x `[0, 2, 9]` — forbids enlarging the X domain for right-side headroom |
| [`charts_test.dart:104-121`](../../test/widgets/charts_test.dart:104) | X axis names + `find.text('0')`/`'1'` present |
| [`charts_test.dart:219-232`](../../test/widgets/charts_test.dart:219) | X axis names fit at width 360, 200 % |
| [`charts_test.dart:292-311`](../../test/widgets/charts_test.dart:292) | single-line, no two-decimal ticks (now applies to X too) |
| [`charts_test.dart:313-347`](../../test/widgets/charts_test.dart:313) | Y integer ticks, Y `39.8`, Y reserve `width + 4 <= 64` at 200 % |
| [`charts_test.dart:349-391`](../../test/widgets/charts_test.dart:349) | axis/tick colour + `labelSmall` size; FPS has no benchmark line; latency keeps the 300 ms line |
| [`charts_test.dart:57-102`](../../test/widgets/charts_test.dart:57) | empty/high/constant/single bucket datasets raise nothing |
| [`charts_test.dart:234-290`](../../test/widgets/charts_test.dart:234) | chart semantics summaries (mixed-model, latest name) |
| [`semantics_test.dart:342-401`](../../test/accessibility/semantics_test.dart:342) | exact chart summary prefixes (`Latest 50.0 milliseconds`, `5 detections across 2 minutes`) come from `_sampleSummary`, not from the axis formatter — must stay byte-identical |
| [`logs_reports_screen_test.dart:366-375`](../../test/screens/logs_reports_screen_test.dart:366) | `Inference Latency (300 ms benchmark)`, `Frames Per Second`, `Detection Frequency` titles |
| [`logs_reports_screen_test.dart:1566-1591`](../../test/screens/logs_reports_screen_test.dart:1566) | the selector must stay a `DropdownButton<String?>` and every card title must still carry the model claim |
| [`logs_reports_screen_test.dart:2245-2261`](../../test/screens/logs_reports_screen_test.dart:2245) | one merged `Detector model…` node, button flag, tap action |
| [`logs_reports_screen_test.dart:1286-1340`](../../test/screens/logs_reports_screen_test.dart:1286) | four 200 %-scale no-overflow tests (Overview, alert latency, **Charts**, **Logs**), 390 × 844 |
| [`logs_reports_screen_test.dart:705-717`](../../test/screens/logs_reports_screen_test.dart:705) | Logs newest-first row: title `person — 82%`, subtitle content |
| [`logs_reports_screen_test.dart:1541-1564`](../../test/screens/logs_reports_screen_test.dart:1541) | unfiltered mixed-model labelling on Overview + Charts |
| [`logs_reports_screen_test.dart:372`](../../test/screens/logs_reports_screen_test.dart:372) | `Inference Latency (300 ms benchmark)` — the 300 ms benchmark wording survives |

### 8.3 Preservation-list tests (previous phase, must not regress)

[`detection_screen_alignment_test.dart`](../../test/screens/detection_screen_alignment_test.dart:1) (gutter + audio pill), [`depth_heatmap_view_test.dart`](../../test/widgets/depth_heatmap_view_test.dart:23) (cover geometry, `RotatedBox`), [`gesture_navigation_direction_test.dart:250-292`](../../test/screens/gesture_navigation_direction_test.dart:250) (gesture region, no tappables), [:434-461](../../test/screens/gesture_navigation_direction_test.dart:434) and [:564-576](../../test/screens/gesture_navigation_direction_test.dart:564) (audio pill semantics), [:463-480](../../test/screens/gesture_navigation_direction_test.dart:463) (one `Detection` header). None of them import `charts.dart` or the Logs tab, so they are safe by non-overlap — but they must be re-run, not assumed.

---

## 9. Token inventory

| Token | Value | Source | Expressive use in these fixes |
|---|---|---|---|
| `kSpace16` | 16 | [`app_spacing.dart:27-28`](../../lib/theme/app_spacing.dart:27) | Issue 4: the horizontal padding the Logs list needs. Also the existing `_LightCard` padding and `_ChartCard` title gap → **the whole of Issue 4 needs no new value** |
| `kSpace12` | 12 | [`app_spacing.dart:21-22`](../../lib/theme/app_spacing.dart:21) | Issue 2 label→dropdown gap (existing) |
| `kSpace8` | 8 | [`app_spacing.dart:15-16`](../../lib/theme/app_spacing.dart:15) | Logs list vertical padding + filter-row bottom gap (existing); a `Wrap` run spacing for Issue 3 if that option is chosen |
| `kSpace6` | 6 | [`app_spacing.dart:12-13`](../../lib/theme/app_spacing.dart:12) | `_SummaryRow` vertical padding (existing, neighbouring shape) |
| `kRadius14` | 14 | [`app_radii.dart:18-19`](../../lib/theme/app_radii.dart:18) | card radius — unchanged by all four fixes |
| `kRadius20` | 20 | [`app_radii.dart:12-13`](../../lib/theme/app_radii.dart:12) | not used by these areas |
| `kHomeSurfaceCard` | `#FFFFFF` | [`app_colors.dart:75-76`](../../lib/theme/app_colors.dart:75) | card surface — unchanged |
| `kHomeInkMuted` | `#667085` | [`app_colors.dart:84-85`](../../lib/theme/app_colors.dart:84) | axis stroke + tick + trailing timestamp colour — unchanged |
| `labelSmall` | 14 sp w500 (`buildHomeTheme`) | [`app_home_theme.dart:89-93`](../../lib/theme/app_home_theme.dart:89) | chart tick type — unchanged |
| `bodyLarge` | 18 sp w500 | [`app_home_theme.dart:69-73`](../../lib/theme/app_home_theme.dart:69) | `Detector model` label — unchanged (unless the design-spec re-roles it) |
| `kChartHeight` | 180 | [`app_spacing.dart:39-40`](../../lib/theme/app_spacing.dart:39) | chart allocation; **only** touched if the bottom reserve grows (NV-3) |

**Is a new token genuinely needed?** Not for Issues 2, 3 or 4 — `kSpace16`/`kSpace8`/`kSpace12` already express every value, and the previous design-spec explicitly rejected a `kScreenHorizontalInset` alias as "two names for one value with one consumer" ([`detection-alignment-charts-design-spec.md:88`](detection-alignment-charts-design-spec.md:88)). For Issue 1, `reservedSize`/`axisNameSize`/`distanceFromEdge` are **layout metrics inside one private function**, and the prior design-spec recorded them as intentionally local literals ([`detection-alignment-charts-design-spec.md:380`](detection-alignment-charts-design-spec.md:380)); adding a token for a single-consumer axis budget would be the same anti-pattern. **Conclusion: no token file edit is justified by this analysis.** If the design-spec later needs one, that is a new decision that must be flagged.

---

## 10. Observability — what is widget-testable and what is device-only

| Issue | Widget-testable assertions | Device-only |
|---|---|---|
| **1a** X precision | Read the rendered tick `Text` widgets: for the sub-second dataset, assert every bottom-band `Text` matches `^\d+(\.\d)?$` (i.e. ≤1 decimal); extend the existing `find.textContaining(RegExp(r'\.\d\d'))` guard ([:308](../../test/widgets/charts_test.dart:308)) to a dataset that **currently** produces a multi-decimal interval (e.g. elapsed `8.3 s` → `4.15`), which is the regression the suite cannot see today. | Legibility of the actual rendered labels on the Snapdragon 695 / API 33 device; real IBM Plex glyph advances differ from `flutter_test`'s test font. |
| **1b** Rightmost clip | `tester.getRect(find.text(<last label>))` vs `tester.getRect(find.byType(LineChart))`: assert the label's `right <= chart.right` and `left >= chart.left` (symmetric check on the first label). This is mechanical and does not depend on the font. A `Stack` clip does **not** raise, so `takeException()` alone would never catch this — the rect comparison is the only honest assertion. | Whether the label now *looks* flush rather than cramped after `fitInside`, and how `distanceFromEdge` reads. |
| **1c** Bottom band height | Compare `tester.getSize(find.text(<x tick>)).height` against the `reservedSize` used (the same technique already used for Y at [:344-345](../../test/widgets/charts_test.dart:344)). | The chosen reserve at 200 % on device (NV-3). |
| **2** Selector truncation | `tester.renderObject<RenderParagraph>(find.text('All models (mixed)')).didExceedMaxLines` — `true` today, expected `false` after the fix, at both 100 % and 200 %. This is the direct, non-font-dependent signal that ellipsis is being applied. Plus keep the semantic-node assertions ([:2245-2261](../../test/screens/logs_reports_screen_test.dart:2245)). | Whether the resulting layout reads acceptably at 200 % on device. |
| **3** Row wrapping | `tester.widget<Text>(subtitle).softWrap` / `.maxLines`, and the laid-out line count via the `RenderParagraph` line metrics. A concrete guard: at 390 × 844 and 100 % scale the subtitle occupies **one** line for the fixtures in [`logs_reports_screen_test.dart:1523-1539`](../../test/screens/logs_reports_screen_test.dart:1523). | Whether a long imported model name should truncate instead of wrapping — a product judgement (NV-8). |
| **4** Tab geometry | Cross-tab rect comparison inside one test: record `tester.getTopLeft(find.text('Detector model')).dx` on the Logs tab and `tester.getTopLeft(find.text('Inference Latency (300 ms benchmark)')).dx` on the Charts tab, then `expect(a, b)` — both are the first child inside a `_LightCard` with 16 dp padding, so equality proves a shared gutter without reaching into private widgets. Optionally also assert the filter card's own `Container` rect equals the chart card's `Container` rect (via `find.ancestor`). | None — this is pure geometry. |

Not testable in widget tests, for the record: whether the tab-to-tab alignment *looks* right on a physical device (no screenshot path is available in this phase), and any claim about real device font metrics.

---

## 11. Preservation list — explicitly out of bounds for this phase

These shipped areas must be provably untouched. The phase's file map (§7) already excludes them, but they are restated so the design-spec and plan cannot absorb them "while we are in there":

1. **Detection 16 dp gutter** — viewport `Padding` inside `Semantics(label: 'Camera view')`, action-row `kSpace16`, band still edge-to-edge, `GestureSurface` width unchanged (390 on the test surface).
2. **Heatmap geometry** — `FittedBox(fit: cover, alignment: center, clipBehavior: hardEdge)` → `RotatedBox(quarterTurns)` → sensor-sized `SizedBox` → `RawImage(fit: fill)`; `Transform.rotate` absent.
3. **AUDIO ON capsule** — semantics identity/target unchanged: `Semantics(container, excludeSemantics, button, enabled, label, onTap)`, 64 × 56 target, content-sized capsule, no custom actions, `Repeat last alert` remains on the `Camera view` node.
4. **Chart Y axis and benchmark state** — no Y name, `axisNameSize: 0`, `reservedSize: 64`, `_formatYAxisTick` behaviour, `kHomeInkMuted` axis/tick colour, `labelSmall` tick type, `_ChartCard` title gap `kSpace16`, FPS benchmark wording **and** line absent, 300 ms latency line present, `kChartHeight = 180`.

Note also: the two artefacts in §2.1/§2.3 that make Issue 1 possible were *introduced* by the prior phase (14 sp ticks in a 22 dp band). Preserving the Y axis means preserving the good half of that work, not reverting the tick style.

---

## 12. Open Questions / Needs Verification

### 12.1 Findings that are confirmed but must not be over-claimed

- **NV-1 `[inferred-from-codebase]` — the exact clipping mechanism for the rightmost tick is unverified.** The *geometry* is certain (the title is centred at `maxX`, which is the plot's right edge, and `rightTitles` reserves nothing — [`charts.dart:285`](../../lib/widgets/charts.dart:285)). What is **not** confirmed is which render object performs the visible clip: fl_chart's internal title layout was not read in this stage, and Context7 confirms `LineChart`/`LineChartData` expose **no** `clipBehavior` (only `clipData`, which clips drawn content). Do not state "the chart card clips it".
- **NV-2 `[inferred-from-codebase]` — `fitInside` sufficiency is unmeasured.** Context7 confirms the parameter exists and is documented as *"force widget to be positioned within its axis bounding box"*, and that `TitleMeta` supplies `axisPosition`/`parentAxisSize`. Whether it clears the label fully at 200 % text scale, and what `distanceFromEdge` should be, has **not** been verified on device or in a test.
- **NV-3 `[inferred-from-codebase]` — the bottom band values are library defaults, not sizing decisions.** `reservedSize: 22` equals the fl_chart default (Context7). The claim "a 14 sp tick at 200 % needs ~34 dp, so the 22 dp band is too small" is arithmetic, not measurement. Whether to grow `reservedSize`, `axisNameSize`, or `kChartHeight` (180) — and by how much — is unsettled and interacts with NV-10.
- **NV-4 `[product-decision]` — the target X tick format is not settled.** "Concise, ~1 decimal, no redundant precision" leaves open: is it *round to 1 decimal* or *choose a nice interval and print integers*? Does the sub-second case keep `0.5` (which the existing tests assert) or does it round to `0`/`1`? Does `maxX / 2` stay, or become a nice-number interval? The answer decides whether [`charts_test.dart:167-169`](../../test/widgets/charts_test.dart:167) and [:202-204](../../test/widgets/charts_test.dart:202) survive.
- **NV-5 `[product-decision]` — right-edge strategy.** Either keep the maximum-value label and pull it inside (`fitInside`), or drop it (`maxIncluded: false`), or add domain headroom. Headroom is the most expensive: it would break [`charts_test.dart:139-145`](../../test/widgets/charts_test.dart:139). This must be chosen, not assumed.
- **NV-6 `[inferred-from-codebase]` — the dropdown's internal metrics were not verified.** The width arithmetic in §3.3 treats the `DropdownButton`'s internal horizontal padding, expand-icon width and icon gap as ~56 dp. That number is an estimate; the framework source was not read in this stage. The *structural* cause (non-flexible 18 sp label + 12 dp gap + zero allowance for dropdown chrome) does not depend on the estimate.
- **NV-7 `[inferred-from-codebase]` — the `ListTile` subtitle text style was not verified.** Under Material 3, `ListTile` resolves its subtitle to `bodyMedium` (16 sp in `buildHomeTheme()`), not `bodySmall`. This was **not** confirmed from the SDK in this stage. The wrap mechanism in §4.2 does not depend on it.
- **NV-8 `[product-decision]` — the Issue 3 fix trades truncation against wrapping.** `softWrap: false` + ellipsis, non-breaking separators, or a per-field `Wrap` all remove the `58 ms` split, but the last two change the rendered string and therefore break four `find.textContaining` assertions ([`logs_reports_screen_test.dart:714`](../../test/screens/logs_reports_screen_test.dart:714), [:1530](../../test/screens/logs_reports_screen_test.dart:1530), [:1535](../../test/screens/logs_reports_screen_test.dart:1535), [:1832](../../test/screens/logs_reports_screen_test.dart:1832)). Which trade-off is acceptable is a product call, not an analysis call.
- **NV-9 `[product-decision]` — Issue 4's shape.** Adopt `_BoundedScrollView` wholesale for the populated Logs tab (gaining `SafeArea` + 16 dp + the same vertical rhythm), or only add horizontal padding to the existing `ListView.builder` (leaving `SafeArea` and the 8 dp vertical rhythm as-is)? The first is more consistent; the second is a smaller diff. Either way the Logs filter card narrows by 32 dp, which **worsens Issue 2 on the Logs tab** — the two must be designed together.
- **NV-10 `[inferred-from-codebase]` — growing the bottom axis reserve shrinks the plot.** `reservedSize`/`axisNameSize` are consumed **inside** the fixed `kChartHeight = 180` allocation ([`logs_reports_screen.dart:1804`](../../lib/screens/logs_reports_screen.dart:1804)), so a taller bottom band comes out of the plot's height. Whether to accept that or grow `kChartHeight` is undecided.
- **NV-11 `[inferred-from-codebase]` — classification (c) rests on "no doc states a requirement".** Issues 2, 3 and 4 are classified as new requirements because no prior doc constrains them. That was verified by searching the prior design-spec/plan for filter/padding/geometry statements, and by the absence of any rect assertion in `logs_reports_screen_test.dart`. The design-spec should confirm rather than inherit this.
- **NV-12 `[product-decision]` — device verification.** All four fixes are visually observable and must be checked on the physical Android device (Snapdragon 695 / API 33), consistent with [`.roo/rules/rules-frontend/07-verification.md`](../../.roo/rules/rules-frontend/07-verification.md). No screenshot path is available in this phase, so this is a live-app check.

### 12.2 Files an implementer might suspect need touching, and why they do not

| File | Why it looks necessary | Why it is out of scope |
|---|---|---|
| [`lib/screens/logs_reports_screen.dart:1707`](../../lib/screens/logs_reports_screen.dart:1707) `_LightCard` padding | Making the Logs card narrower could be done by changing the shared card padding | That would change **every** card in Overview, Charts and Logs. The defect is the list's padding, not the card's. |
| [`lib/theme/app_home_theme.dart`](../../lib/theme/app_home_theme.dart:89) | Smaller tick/label type would "fix" both fit problems | Changes every screen's typography; a redesign, not a polish fix. |
| [`lib/services/telemetry_service.dart`](../../lib/services/telemetry_service.dart:1) | `RuntimeSample.timestamp` drives `maxX`, so "round the timestamps" looks attractive | Bounds/formatting are presentation concerns; mutating recorded timestamps would corrupt telemetry and exports. `charts.dart` owns the axis. |
| [`test/widgets/charts_test.dart`](../../test/widgets/charts_test.dart:1) `wrap()` helper | A themed helper already exists (`wrapThemed`, [:40-51](../../test/widgets/charts_test.dart:40)) and the X tests use the unthemed `wrap` | The plan stage owns test edits; this stage may not touch them. Note for planning: the X assertions run at the **test font** metrics, not the 14 sp theme size — the same trap the previous phase recorded as its OQ-P2. |

---

*End of analysis. No code, test, theme or doc file other than this one was created or modified.*
