import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../services/telemetry_service.dart';

/// Shared chart styling so all charts stay high-contrast and consistent.
const Color _axisColor = Color(0xFFBDBDBD);
const Color _lineColor = Color(0xFFFFC107);

/// Maximum latency considered "reasonable" to still draw the 300 ms
/// benchmark line; above this the line would push the scale so high that
/// normal data would be crushed. When the data is much smaller than 300 ms
/// the benchmark line is simply omitted (it would be off-scale anyway).
const double _latencyBenchmarkMs = 300.0;
const double _fpsBenchmark = 15.0;

/// Inference latency over time. The Y scale adapts to the actual data
/// (with headroom, never clamped above), so every point stays inside the
/// allocated chart. The fixed 300 ms benchmark line is only drawn when it
/// actually fits within the computed scale.
class LatencyChart extends StatelessWidget {
  final List<RuntimeSample> samples;

  const LatencyChart({super.key, required this.samples});

  @override
  Widget build(BuildContext context) {
    if (samples.isEmpty) {
      return Semantics(
        label: 'Inference latency chart. No data available yet.',
        child: ExcludeSemantics(child: _NoData()),
      );
    }
    final spots = <FlSpot>[
      for (var i = 0; i < samples.length; i++)
        FlSpot(i.toDouble(), samples[i].latencyMs),
    ];
    final dataMax = samples
        .map((s) => s.latencyMs)
        .reduce((a, b) => a > b ? a : b);
    // Dynamic upper bound: 20% headroom + 10 ms, with a floor so very low or
    // constant data never collapses the scale. No upper clamp — unusually high
    // values always fit.
    final maxY = math.max(dataMax * 1.2 + 10.0, 40.0);
    final showBenchmark = maxY >= _latencyBenchmarkMs;
    final summary = _sampleSummary(
      samples.map((sample) => sample.latencyMs),
      unit: 'milliseconds',
      engine: _engineSummary(samples),
    );
    return Semantics(
      container: true,
      label: 'Inference latency chart. $summary',
      child: ExcludeSemantics(
        child: LineChart(
          LineChartData(
            minY: 0,
            maxY: maxY,
            gridData: FlGridData(show: true, drawVerticalLine: false),
            borderData: FlBorderData(
              show: true,
              border: const Border(
                left: BorderSide(color: _axisColor),
                bottom: BorderSide(color: _axisColor),
              ),
            ),
            titlesData: const FlTitlesData(show: false),
            extraLinesData: ExtraLinesData(
              horizontalLines: showBenchmark
                  ? [
                      HorizontalLine(
                        y: _latencyBenchmarkMs,
                        color: Colors.redAccent,
                        strokeWidth: 1.5,
                        dashArray: [6, 4],
                      ),
                    ]
                  : const [],
            ),
            lineBarsData: [
              LineChartBarData(
                spots: spots,
                isCurved: false,
                color: _lineColor,
                barWidth: 2,
                dotData: const FlDotData(show: false),
              ),
            ],
            lineTouchData: const LineTouchData(enabled: false),
          ),
        ),
      ),
    );
  }
}

/// Effective inference FPS over time. Same dynamic-scaling approach; the
/// 15 FPS target line is drawn only when it fits the computed scale.
class FpsChart extends StatelessWidget {
  final List<RuntimeSample> samples;

  const FpsChart({super.key, required this.samples});

  @override
  Widget build(BuildContext context) {
    if (samples.isEmpty) {
      return Semantics(
        label: 'Frames per second chart. No data available yet.',
        child: ExcludeSemantics(child: _NoData()),
      );
    }
    final spots = <FlSpot>[
      for (var i = 0; i < samples.length; i++)
        FlSpot(i.toDouble(), samples[i].inferenceFps),
    ];
    final dataMax = samples
        .map((s) => s.inferenceFps)
        .reduce((a, b) => a > b ? a : b);
    final maxY = math.max(dataMax * 1.2 + 2.0, 2.0);
    final showBenchmark = maxY >= _fpsBenchmark;
    final summary = _sampleSummary(
      samples.map((sample) => sample.inferenceFps),
      unit: 'frames per second',
      engine: _engineSummary(samples),
    );
    return Semantics(
      container: true,
      label: 'Frames per second chart. $summary',
      child: ExcludeSemantics(
        child: LineChart(
          LineChartData(
            minY: 0,
            maxY: maxY,
            gridData: FlGridData(show: true, drawVerticalLine: false),
            borderData: FlBorderData(
              show: true,
              border: const Border(
                left: BorderSide(color: _axisColor),
                bottom: BorderSide(color: _axisColor),
              ),
            ),
            titlesData: const FlTitlesData(show: false),
            extraLinesData: ExtraLinesData(
              horizontalLines: showBenchmark
                  ? [
                      HorizontalLine(
                        y: _fpsBenchmark,
                        color: Colors.greenAccent,
                        strokeWidth: 1.5,
                        dashArray: [6, 4],
                      ),
                    ]
                  : const [],
            ),
            lineBarsData: [
              LineChartBarData(
                spots: spots,
                isCurved: false,
                color: _lineColor,
                barWidth: 2,
                dotData: const FlDotData(show: false),
              ),
            ],
            lineTouchData: const LineTouchData(enabled: false),
          ),
        ),
      ),
    );
  }
}

/// Detection event frequency bucketed per minute (bar chart). An explicit,
/// data-driven `maxY` is required so bars render inside the plot area
/// (fl_chart defaults `maxY` to 0, which would draw every bar outside it).
class DetectionFrequencyChart extends StatelessWidget {
  final List<int> buckets;

  const DetectionFrequencyChart({super.key, required this.buckets});

  @override
  Widget build(BuildContext context) {
    if (buckets.isEmpty) {
      return Semantics(
        label: 'Detection frequency chart. No data available yet.',
        child: ExcludeSemantics(child: _NoData()),
      );
    }
    final maxBucket = buckets.reduce((a, b) => a > b ? a : b).toDouble();
    // Headroom above the tallest bar; floor of 1 keeps a single low bucket
    // (or constant values) visible instead of collapsing the scale.
    final maxY = math.max(maxBucket * 1.2 + 1.0, 1.0);
    final groups = <BarChartGroupData>[
      for (var i = 0; i < buckets.length; i++)
        BarChartGroupData(
          x: i,
          barRods: [
            BarChartRodData(
              toY: buckets[i].toDouble(),
              color: _lineColor,
              width: 14,
            ),
          ],
        ),
    ];
    final total = buckets.fold<int>(0, (sum, value) => sum + value);
    return Semantics(
      container: true,
      label:
          'Detection frequency chart. $total detections across '
          '${buckets.length} minutes.',
      child: ExcludeSemantics(
        child: BarChart(
          BarChartData(
            minY: 0,
            maxY: maxY,
            gridData: FlGridData(show: true, drawVerticalLine: false),
            borderData: FlBorderData(
              show: true,
              border: const Border(
                left: BorderSide(color: _axisColor),
                bottom: BorderSide(color: _axisColor),
              ),
            ),
            titlesData: const FlTitlesData(show: false),
            barGroups: groups,
            barTouchData: const BarTouchData(enabled: false),
          ),
        ),
      ),
    );
  }
}

String _engineSummary(List<RuntimeSample> samples) {
  final engines = samples.map((sample) => sample.engine.label).toSet();
  final engineText = engines.isEmpty ? 'no engine' : engines.join(', ');
  // Counted by graph identity, not by name: two same-named graphs are still
  // two models, and one graph renamed mid-session is still one model.
  final namesById = <String, String?>{};
  for (final sample in samples) {
    final id = sample.detectorModelId;
    if (id == null) continue;
    final name = sample.detectorModelName;
    // The latest recorded name wins, so a renamed graph shows its current name.
    if (name != null || !namesById.containsKey(id)) namesById[id] = name;
  }
  final models = namesById.values.whereType<String>().toSet();
  if (models.isEmpty) return engineText;
  final mixed = namesById.length > 1;
  // A chart drawn from more than one detector never claims one model's data.
  return '$engineText; detector model ${models.join(', ')}'
      '${mixed ? ' (mixed-model data)' : ''}';
}

String _sampleSummary(
  Iterable<double> values, {
  required String unit,
  required String engine,
}) {
  final list = values.toList(growable: false);
  final latest = list.last;
  final min = list.reduce(math.min);
  final max = list.reduce(math.max);
  final average = list.reduce((a, b) => a + b) / list.length;
  return 'Latest ${latest.toStringAsFixed(1)} $unit; average '
      '${average.toStringAsFixed(1)}; minimum ${min.toStringAsFixed(1)}; '
      'maximum ${max.toStringAsFixed(1)}; ${list.length} samples; engine $engine.';
}

class _NoData extends StatelessWidget {
  const _NoData();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Text(
        'No data available yet',
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
