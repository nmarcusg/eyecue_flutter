import 'package:eyecue_flutter/services/telemetry_service.dart';
import 'package:eyecue_flutter/widgets/charts.dart';
import 'package:eyecue_flutter/models/app_settings.dart';
import 'package:eyecue_flutter/theme/app_colors.dart';
import 'package:eyecue_flutter/theme/app_home_theme.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

List<RuntimeSample> samples(List<double> latencies, {List<double>? fps}) {
  final f = fps ?? List.filled(latencies.length, 15.0);
  return [
    for (var i = 0; i < latencies.length; i++)
      RuntimeSample(
        timestamp: DateTime(2026, 1, 1).add(Duration(seconds: i)),
        latencyMs: latencies[i],
        inferenceFps: f[i],
        objectCount: 1,
        engine: InferenceEngine.ultralytics,
      ),
  ];
}

Widget wrap(Widget child, {double textScale = 1, double width = 360}) =>
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: Scaffold(
          body: Center(
            child: SizedBox(width: width, height: 180, child: child),
          ),
        ),
      ),
    );

/// Same surface as [wrap], but under the real app theme so `labelSmall`
/// resolves to the 14 sp the charts actually render with. `wrap()` alone
/// uses a bare MaterialApp (Material's default tick size), which cannot guard
/// the shipped tick size.
Widget wrapThemed(Widget child, {double textScale = 1, double width = 360}) =>
    MaterialApp(
      theme: buildHomeTheme(),
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: Scaffold(
          body: Center(
            child: SizedBox(width: width, height: 180, child: child),
          ),
        ),
      ),
    );

/// Three samples 4.15 s apart, so `maxX / 2` is not a one-decimal number:
/// this is the dataset that used to render `4.15` on the X axis.
List<RuntimeSample> wallClockSamples() {
  final first = DateTime.utc(2026);
  return [
    for (final offset in [0, 4150, 8300])
      RuntimeSample(
        timestamp: first.add(Duration(milliseconds: offset)),
        latencyMs: 30,
        inferenceFps: 12,
        objectCount: 1,
        engine: InferenceEngine.ultralytics,
      ),
  ];
}

/// Regression tests: every chart must stay inside its allocated box (no
/// exceptions/overflows) regardless of the dataset, including empty, very
/// high, constant, and single-value data.
void main() {
  testWidgets('LatencyChart shows placeholder for empty data', (tester) async {
    await tester.pumpWidget(wrap(LatencyChart(samples: const [])));
    expect(tester.takeException(), isNull);
    expect(find.text('No data available yet'), findsOneWidget);
  });

  testWidgets('LatencyChart keeps very high values inside the chart', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(LatencyChart(samples: samples([30, 5000, 120, 900]))),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('LatencyChart handles constant values without collapsing', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(LatencyChart(samples: samples([30, 30, 30, 30]))),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('FpsChart handles high and low FPS inside the chart', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(FpsChart(samples: samples([10, 10, 10], fps: [5, 45, 12]))),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('DetectionFrequencyChart handles many buckets', (tester) async {
    await tester.pumpWidget(
      wrap(DetectionFrequencyChart(buckets: [0, 1, 5, 2, 50, 3, 4])),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('DetectionFrequencyChart handles a single low bucket', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(DetectionFrequencyChart(buckets: const [1])));
    expect(tester.takeException(), isNull);
  });

  testWidgets('populated charts show named axes and numeric ticks', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(LatencyChart(samples: samples([30, 40]))));
    expect(find.text('Elapsed time (s)'), findsOneWidget);
    expect(find.text('Latency (ms)'), findsNothing);
    expect(find.text('0'), findsWidgets);

    await tester.pumpWidget(wrap(FpsChart(samples: samples([30, 40]))));
    expect(find.text('Elapsed time (s)'), findsOneWidget);
    expect(find.text('FPS'), findsNothing);
    expect(find.text('0'), findsWidgets);

    await tester.pumpWidget(wrap(DetectionFrequencyChart(buckets: [0, 4, 1])));
    expect(find.text('Minute'), findsOneWidget);
    expect(find.text('Detections'), findsNothing);
    expect(find.text('1'), findsWidgets);
  });

  testWidgets(
    'line-chart X values use elapsed seconds at irregular intervals',
    (tester) async {
      final first = DateTime.utc(2026);
      final irregular = [
        for (final offset in [0, 2, 9])
          RuntimeSample(
            timestamp: first.add(Duration(seconds: offset)),
            latencyMs: 30,
            inferenceFps: 12,
            objectCount: 1,
            engine: InferenceEngine.ultralytics,
          ),
      ];
      await tester.pumpWidget(wrap(LatencyChart(samples: irregular)));
      final chart = tester.widget<LineChart>(find.byType(LineChart));
      expect(chart.data.minX, 0);
      expect(chart.data.maxX, 9);
      expect(chart.data.lineBarsData.single.spots.map((spot) => spot.x), [
        0,
        2,
        9,
      ]);
    },
  );

  testWidgets('sub-second elapsed ticks are accurate and fit narrowly', (
    tester,
  ) async {
    final first = DateTime.utc(2026);
    final subSecond = [
      for (final offset in [0, 250, 500, 750, 1000])
        RuntimeSample(
          timestamp: first.add(Duration(milliseconds: offset)),
          latencyMs: 30,
          inferenceFps: 12,
          objectCount: 1,
          engine: InferenceEngine.ultralytics,
        ),
    ];
    await tester.pumpWidget(
      wrap(LatencyChart(samples: subSecond), textScale: 2, width: 260),
    );

    for (final label in ['0', '0.5', '1']) {
      expect(find.text(label), findsWidgets);
    }
    final tickRects = [
      for (final label in ['0', '0.5', '1'])
        find
            .text(label)
            .evaluate()
            .map((element) => tester.getRect(find.byWidget(element.widget)))
            .reduce((a, b) => a.top > b.top ? a : b),
    ];
    for (var i = 1; i < tickRects.length; i++) {
      expect(tickRects[i - 1].overlaps(tickRects[i]), isFalse);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('fractional elapsed ticks above one second stay accurate', (
    tester,
  ) async {
    final first = DateTime.utc(2026);
    final threeSeconds = [
      for (final offset in [0, 1500, 3000])
        RuntimeSample(
          timestamp: first.add(Duration(milliseconds: offset)),
          latencyMs: 30,
          inferenceFps: 12,
          objectCount: 1,
          engine: InferenceEngine.ultralytics,
        ),
    ];
    await tester.pumpWidget(
      wrap(LatencyChart(samples: threeSeconds), textScale: 2, width: 260),
    );

    for (final label in ['0', '1.5', '3']) {
      expect(find.text(label), findsWidgets);
    }
    final tickRects = [
      for (final label in ['0', '1.5', '3'])
        find
            .text(label)
            .evaluate()
            .map((element) => tester.getRect(find.byWidget(element.widget)))
            .reduce((a, b) => a.top > b.top ? a : b),
    ];
    for (var i = 1; i < tickRects.length; i++) {
      expect(tickRects[i - 1].overlaps(tickRects[i]), isFalse);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('X axis names fit at narrow width and 200% text scale', (
    tester,
  ) async {
    final charts = [
      (LatencyChart(samples: samples([30, 40])), 'Elapsed time (s)'),
      (FpsChart(samples: samples([30, 40])), 'Elapsed time (s)'),
      (DetectionFrequencyChart(buckets: List.filled(30, 12)), 'Minute'),
    ];
    for (final (chart, xAxis) in charts) {
      await tester.pumpWidget(wrap(chart, textScale: 2));
      expect(find.text(xAxis), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('the chart summary calls two same-named graphs mixed', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final twoGraphs = [
      for (var i = 0; i < 2; i++)
        RuntimeSample(
          timestamp: DateTime(2026, 1, 1).add(Duration(seconds: i)),
          latencyMs: 30,
          inferenceFps: 12,
          objectCount: 1,
          engine: InferenceEngine.ultralytics,
          // One display name, two graph identities.
          detectorModelId: 'custom:00000000000$i',
          detectorModelName: 'Obstacle Detector v2',
        ),
    ];
    await tester.pumpWidget(wrap(FpsChart(samples: twoGraphs)));
    expect(find.bySemanticsLabel(RegExp('mixed-model data')), findsOneWidget);
    handle.dispose();
  });

  testWidgets('the chart summary names one identity by its latest name', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final renamedGraph = [
      RuntimeSample(
        timestamp: DateTime(2026, 1, 1),
        latencyMs: 30,
        inferenceFps: 12,
        objectCount: 1,
        engine: InferenceEngine.ultralytics,
        detectorModelId: 'custom:000000000001',
        detectorModelName: 'Obstacle Detector v2',
      ),
      RuntimeSample(
        timestamp: DateTime(2026, 1, 1, 0, 0, 1),
        latencyMs: 30,
        inferenceFps: 12,
        objectCount: 1,
        engine: InferenceEngine.ultralytics,
        // The same graph, renamed mid-session: one identity, not two models.
        detectorModelId: 'custom:000000000001',
        detectorModelName: 'Obstacle Detector v2 fixed',
      ),
    ];
    await tester.pumpWidget(wrap(FpsChart(samples: renamedGraph)));
    expect(
      find.bySemanticsLabel(
        RegExp('detector model Obstacle Detector v2 fixed'),
      ),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel(RegExp('mixed-model data')), findsNothing);
    handle.dispose();
  });

  testWidgets('Y ticks are single line and never carry two decimals', (
    tester,
  ) async {
    final charts = [
      LatencyChart(samples: samples([30, 58])),
      FpsChart(samples: samples([30, 40])),
      DetectionFrequencyChart(buckets: const [0, 4, 1]),
    ];
    for (final chart in charts) {
      await tester.pumpWidget(wrap(chart));
      for (final text in tester.widgetList<Text>(find.byType(Text))) {
        final data = text.data;
        if (data == null || !RegExp(r'^\d').hasMatch(data)) continue;
        expect(text.maxLines, 1, reason: data);
        expect(text.softWrap, isFalse, reason: data);
      }
      expect(find.textContaining(RegExp(r'\.\d\d')), findsNothing);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('an integer Y interval renders integer ticks', (tester) async {
    await tester.pumpWidget(wrap(LatencyChart(samples: samples([25]))));
    // dataMax 25 -> maxY 40, interval 10.
    for (final label in ['10', '20', '30', '40']) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    expect(find.text('10.0'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a fractional Y interval keeps exactly one decimal', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(LatencyChart(samples: samples([30, 58]))));
    // dataMax 58 -> maxY 79.6, interval 19.9.
    expect(find.text('39.8'), findsOneWidget);
    expect(find.textContaining(RegExp(r'\.\d\d')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the widest Y tick fits the reserved gutter at 200 percent '
      'text scale', (tester) async {
    await tester.pumpWidget(
      wrapThemed(
        LatencyChart(samples: samples([30, 58])),
        textScale: 2,
        width: 320,
      ),
    );
    // 4 dp is `SideTitleWidget.space`; 64 is the left `reservedSize`. This is
    // the assertion that fails if the reserve is too small.
    final width = tester.getRect(find.text('39.8')).width;
    expect(width + 4, lessThanOrEqualTo(64));
    expect(tester.takeException(), isNull);
  });

  testWidgets('chart axes and ticks share the muted ink token', (tester) async {
    await tester.pumpWidget(
      wrapThemed(LatencyChart(samples: samples([30, 58]))),
    );
    final chart = tester.widget<LineChart>(find.byType(LineChart));
    final border = chart.data.borderData.border;
    expect(border.left.color, kHomeInkMuted);
    expect(border.bottom.color, kHomeInkMuted);

    final tick = tester.widget<Text>(find.text('39.8'));
    expect(tick.style?.color, kHomeInkMuted);
    final labelSmallSize = Theme.of(
      tester.element(find.byType(LineChart)),
    ).textTheme.labelSmall!.fontSize;
    expect(tick.style?.fontSize, labelSmallSize);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the FPS chart draws no benchmark line and the latency chart '
      'keeps its 300 ms line', (tester) async {
    await tester.pumpWidget(wrap(FpsChart(samples: samples([30, 40]))));
    expect(
      tester
          .widget<LineChart>(find.byType(LineChart))
          .data
          .extraLinesData
          .horizontalLines,
      isEmpty,
    );

    // dataMax 420 -> maxY 514, so the 300 ms line fits.
    await tester.pumpWidget(wrap(LatencyChart(samples: samples([400, 420]))));
    final lines = tester
        .widget<LineChart>(find.byType(LineChart))
        .data
        .extraLinesData
        .horizontalLines;
    expect(lines, hasLength(1));
    expect(lines.single.y, 300);
    expect(lines.single.color, Colors.redAccent);
    expect(lines.single.dashArray, [6, 4]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('X ticks carry at most one decimal on a wall-clock interval', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(LatencyChart(samples: wallClockSamples())));

    // maxX 8.3, xInterval 4.15: the deleted interval-driven formatter printed
    // `4.15`, which is a four-glyph label in the bottom band at 200 % scale.
    expect(find.text('4.15'), findsNothing);
    expect(find.text('4.2'), findsOneWidget);
    expect(find.text('8.3'), findsOneWidget);
    expect(find.textContaining(RegExp(r'\.\d\d')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the rightmost X tick stays inside the chart box', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(LatencyChart(samples: wallClockSamples()), width: 320),
    );
    // `SideTitleWidget` captures the child size in a post-frame callback and
    // only then applies the clamp, so the settled frame is the second one.
    await tester.pump();

    // A clipped title never throws, so containment is the honest assertion.
    final chartRect = tester.getRect(find.byType(LineChart));
    final lastRect = tester.getRect(find.text('8.3'));
    expect(lastRect.right, lessThanOrEqualTo(chartRect.right));
    expect(lastRect.left, greaterThanOrEqualTo(chartRect.left));

    // `0` is on both axes; keep only the bottom-most (X) tick, as the
    // neighbouring X tests do.
    final zeroRect = find
        .text('0')
        .evaluate()
        .map((element) => tester.getRect(find.byWidget(element.widget)))
        .reduce((a, b) => a.top > b.top ? a : b);
    expect(zeroRect.left, greaterThanOrEqualTo(chartRect.left));
    expect(tester.takeException(), isNull);
  });

  testWidgets('X ticks fit the raised bottom band at 200 percent text scale', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrapThemed(
        LatencyChart(samples: samples([30, 40])),
        textScale: 2,
        width: 320,
      ),
    );
    // 36 is the bottom `reservedSize`; this fails if the 14 sp tick's real
    // line box outgrows the band the P2 arithmetic sized.
    expect(tester.getSize(find.text('0.5')).height, lessThanOrEqualTo(36));
    expect(tester.takeException(), isNull);
  });
}
