import 'package:eyecue_flutter/services/telemetry_service.dart';
import 'package:eyecue_flutter/widgets/charts.dart';
import 'package:eyecue_flutter/models/app_settings.dart';
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
        engine: InferenceEngine.custom,
      ),
  ];
}

Widget wrap(Widget child) => MaterialApp(
  home: Scaffold(
    body: Center(child: SizedBox(width: 360, height: 180, child: child)),
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
}
