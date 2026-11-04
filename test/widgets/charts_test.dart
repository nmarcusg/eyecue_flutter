import 'package:eyecue_flutter/services/telemetry_service.dart';
import 'package:eyecue_flutter/widgets/charts.dart';
import 'package:eyecue_flutter/models/app_settings.dart';
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
    expect(find.text('Latency (ms)'), findsOneWidget);
    expect(find.text('0'), findsWidgets);

    await tester.pumpWidget(wrap(FpsChart(samples: samples([30, 40]))));
    expect(find.text('Elapsed time (s)'), findsOneWidget);
    expect(find.text('FPS'), findsOneWidget);
    expect(find.text('0'), findsWidgets);

    await tester.pumpWidget(wrap(DetectionFrequencyChart(buckets: [0, 4, 1])));
    expect(find.text('Minute'), findsOneWidget);
    expect(find.text('Detections'), findsOneWidget);
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

  testWidgets('axis labels fit at narrow width and 200% text scale', (
    tester,
  ) async {
    final charts = [
      (
        LatencyChart(samples: samples([30, 40])),
        'Elapsed time (s)',
        'Latency (ms)',
      ),
      (FpsChart(samples: samples([30, 40])), 'Elapsed time (s)', 'FPS'),
      (
        DetectionFrequencyChart(buckets: List.filled(30, 12)),
        'Minute',
        'Detections',
      ),
    ];
    for (final (chart, xAxis, yAxis) in charts) {
      await tester.pumpWidget(wrap(chart, textScale: 2));
      expect(find.text(xAxis), findsOneWidget);
      expect(find.text(yAxis), findsOneWidget);
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
}
