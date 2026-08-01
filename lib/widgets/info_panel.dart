import 'package:flutter/material.dart';

/// A single chronological detection-history entry (newest first).
class DetectionHistoryEntry {
  final String label;
  final double confidence;
  final DateTime time;

  const DetectionHistoryEntry({
    required this.label,
    required this.confidence,
    required this.time,
  });
}

/// Live runtime metrics shown in the "Metrics" tab.
///
/// Values that are not currently instrumented are rendered as "—" rather than
/// inventing numbers.
class MetricsPanel extends StatelessWidget {
  final double cameraFps;
  final double averageFps;
  final double inferenceMs;
  final int objectsDetected;
  final double? highestConfidence;
  final double? lowestConfidence;
  final double? averageConfidence;
  final String cameraResolution;
  final String previewResolution;
  final String modelInputResolution;
  final String aspectRatio;
  final String modelName;
  final String inferenceBackend;
  final String quantization;
  final String threadCount;
  final String memoryUsage;

  const MetricsPanel({
    super.key,
    required this.cameraFps,
    required this.averageFps,
    required this.inferenceMs,
    required this.objectsDetected,
    required this.highestConfidence,
    required this.lowestConfidence,
    required this.averageConfidence,
    required this.cameraResolution,
    required this.previewResolution,
    required this.modelInputResolution,
    required this.aspectRatio,
    required this.modelName,
    required this.inferenceBackend,
    required this.quantization,
    required this.threadCount,
    required this.memoryUsage,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final sections = <(String, List<(String, String)>)>[
      ('Performance', [
        ('FPS', cameraFps.toStringAsFixed(1)),
        ('Avg FPS', averageFps.toStringAsFixed(1)),
        ('Inference (ms)', inferenceMs.toStringAsFixed(1)),
        ('End-to-end (ms)', inferenceMs.toStringAsFixed(1)),
        ('Preprocess (ms)', '—'),
        ('Postprocess (ms)', '—'),
      ]),
      ('Detection', [
        ('Objects', objectsDetected.toString()),
        ('Highest conf', _pct(highestConfidence)),
        ('Lowest conf', _pct(lowestConfidence)),
        ('Average conf', _pct(averageConfidence)),
      ]),
      ('Camera', [
        ('Camera res', cameraResolution),
        ('Preview res', previewResolution),
        ('Model input', modelInputResolution),
        ('Aspect ratio', aspectRatio),
      ]),
      ('Model', [
        ('Name', modelName),
        ('Backend', inferenceBackend),
        ('Quantization', quantization),
        ('Threads', threadCount),
      ]),
      ('Memory', [
        ('RAM usage', memoryUsage),
      ]),
    ];

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      children: [
        for (final section in sections) ...[
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 4),
            child: Text(
              section.$1,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.primary,
              ),
            ),
          ),
          for (final row in section.$2) _metricRow(theme, row.$1, row.$2),
        ],
      ],
    );
  }

  Widget _metricRow(ThemeData theme, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 150,
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _pct(double? v) =>
      v == null ? '—' : '${(v * 100).toStringAsFixed(1)}%';
}

/// Chronological detection history shown in the "Detections" tab.
///
/// Newest entries are rendered at the top.
class DetectionsPanel extends StatelessWidget {
  final List<DetectionHistoryEntry> entries;

  const DetectionsPanel({super.key, required this.entries});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (entries.isEmpty) {
      return Center(
        child: Text(
          'No detections yet',
          style: theme.textTheme.bodyLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    final now = DateTime.now();
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: entries.length,
      itemBuilder: (context, index) {
        final e = entries[index];
        return ListTile(
          dense: true,
          leading: const Icon(Icons.adjust, color: Colors.green),
          title: Text(
            e.label,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          subtitle: Text(_relativeAge(e.time, now)),
          trailing: Text(
            '${(e.confidence * 100).toStringAsFixed(0)}%',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.primary,
            ),
          ),
        );
      },
    );
  }

  static String _relativeAge(DateTime time, DateTime now) {
    final seconds = now.difference(time).inSeconds;
    if (seconds < 1) return 'Just now';
    if (seconds < 60) return '$seconds second${seconds == 1 ? '' : 's'} ago';
    final minutes = (seconds / 60).floor();
    if (minutes < 60) return '$minutes minute${minutes == 1 ? '' : 's'} ago';
    final hours = (minutes / 60).floor();
    return '$hours hour${hours == 1 ? '' : 's'} ago';
  }
}
