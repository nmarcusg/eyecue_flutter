import 'package:flutter/material.dart';

import '../models/app_settings.dart';
import '../models/detection_correction.dart';
import '../models/detection_info.dart';
import '../services/correction_service.dart';
import '../services/settings_service.dart';
import '../services/telemetry_export_service.dart';
import '../services/telemetry_service.dart';
import '../widgets/accessible_button.dart';
import '../widgets/charts.dart';

/// Logs & Reports — researcher/developer-facing telemetry dashboard.
///
/// Deliberately reached from Settings (not the main navigation) so it does not
/// add cognitive load for visually impaired users, per the thesis. Tabs:
/// Overview, Charts, Logs.
///
/// Honesty rules implemented here:
///  * Accuracy/Precision/Recall/F1/mAP are **not** computed — they require
///    ground-truth labels and are shown as unavailable.
///  * Raw confidence is never labeled as accuracy.
class LogsReportsScreen extends StatefulWidget {
  final TelemetryService telemetry;
  final SettingsService? settings;
  final CorrectionService? corrections;
  final TelemetryExportService? exportService;

  const LogsReportsScreen({
    super.key,
    required this.telemetry,
    this.settings,
    this.corrections,
    this.exportService,
  });

  @override
  State<LogsReportsScreen> createState() => _LogsReportsScreenState();
}

class _LogsReportsScreenState extends State<LogsReportsScreen> {
  late final TelemetryExportService _exportService =
      widget.exportService ?? TelemetryExportService();
  bool _exporting = false;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Logs & Reports'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Overview'),
              Tab(text: 'Charts'),
              Tab(text: 'Logs'),
            ],
          ),
        ),
        body: ListenableBuilder(
          listenable: Listenable.merge([
            widget.telemetry,
            if (widget.corrections != null) widget.corrections!,
          ]),
          builder: (context, _) {
            return TabBarView(
              children: [
                _OverviewTab(
                  exporting: _exporting,
                  onExportJson: () => _export(csv: false),
                  onExportCsv: () => _export(csv: true),
                ),
                const _ChartsTab(),
                const _LogsTab(),
              ],
            );
          },
        ),
      ),
    );
  }

  Future<void> _export({required bool csv}) async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      final file = csv
          ? await _exportService.writeCsv(
              telemetry: widget.telemetry,
              settings: widget.settings?.settings,
            )
          : await _exportService.writeJson(
              telemetry: widget.telemetry,
              settings: widget.settings?.settings,
            );
      if (!mounted) return;
      final filename = file.uri.pathSegments.isEmpty
          ? 'telemetry export'
          : file.uri.pathSegments.last;
      _showMessage('Export saved: $filename');
    } catch (_) {
      if (!mounted) return;
      _showMessage('Export could not be saved. Try again.', isError: true);
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  void _showMessage(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: isError
            ? Theme.of(context).colorScheme.errorContainer
            : null,
        content: Semantics(
          container: true,
          liveRegion: true,
          label: message,
          child: Text(message),
        ),
      ),
    );
  }
}

class _OverviewTab extends StatelessWidget {
  final bool exporting;
  final VoidCallback onExportJson;
  final VoidCallback onExportCsv;

  const _OverviewTab({
    required this.exporting,
    required this.onExportJson,
    required this.onExportCsv,
  });

  @override
  Widget build(BuildContext context) {
    return Builder(
      builder: (context) {
        final telemetry = _of(context);
        final theme = Theme.of(context);
        final duration = telemetry.sessionDuration;
        final hours = duration.inHours;
        final minutes = duration.inMinutes % 60;
        final seconds = duration.inSeconds % 60;
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'Real-Time Performance',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _MetricCard(
                  label: 'Avg FPS',
                  value: _fmt(telemetry.averageInferenceFps),
                ),
                const SizedBox(width: 12),
                _MetricCard(
                  label: 'Avg Latency',
                  value: '${_fmt(telemetry.averageLatencyMs)} ms',
                ),
              ],
            ),
            const SizedBox(height: 24),
            Text(
              'Engine Comparison',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            for (final engine in InferenceEngine.values)
              _EngineSummaryCard(summary: telemetry.summaryFor(engine)),
            const SizedBox(height: 24),
            Text(
              'Session Summary',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            _SummaryRow(
              label: 'Total detections',
              value: '${telemetry.totalDetections}',
            ),
            _SummaryRow(
              label: 'High-priority alerts',
              value: '${telemetry.highPriorityAlerts}',
            ),
            _SummaryRow(
              label: 'Frames processed',
              value: '${telemetry.framesProcessed}',
            ),
            _SummaryRow(
              label: 'Session duration',
              value: '$hours h $minutes m $seconds s',
            ),
            _SummaryRow(
              label: 'Avg confidence',
              value: telemetry.records.isEmpty
                  ? '—'
                  : '${(telemetry.averageConfidence * 100).toStringAsFixed(0)}%',
            ),
            const SizedBox(height: 24),
            _ExportSection(
              exporting: exporting,
              onExportJson: onExportJson,
              onExportCsv: onExportCsv,
            ),
            const SizedBox(height: 24),
            const _CorrectionSummary(),
            const SizedBox(height: 24),
            const _UnavailableNote(
              title: 'Model Evaluation Metrics',
              body:
                  'Accuracy, Precision, Recall, F1, and mAP are not shown because '
                  'they require ground-truth labels (offline evaluation), which a '
                  'live camera feed cannot provide.',
            ),
            const SizedBox(height: 12),
            const _UnavailableNote(
              title: 'Usability (SUS)',
              body:
                  'SUS is collected through a post-test questionnaire with '
                  'participants — it is not derived from runtime data.',
            ),
          ],
        );
      },
    );
  }
}

class _ExportSection extends StatelessWidget {
  final bool exporting;
  final VoidCallback onExportJson;
  final VoidCallback onExportCsv;

  const _ExportSection({
    required this.exporting,
    required this.onExportJson,
    required this.onExportCsv,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: 'Offline telemetry export',
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Offline telemetry export',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              const Text(
                'Save the current image-free session as a versioned JSON or '
                'CSV file. Exports contain no camera frames or device IDs.',
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  AccessibleButton(
                    label: 'Save JSON export',
                    icon: Icons.data_object,
                    onPressed: exporting ? null : onExportJson,
                  ),
                  AccessibleButton(
                    label: 'Save CSV export',
                    icon: Icons.table_chart_outlined,
                    onPressed: exporting ? null : onExportCsv,
                  ),
                ],
              ),
              if (exporting) ...[
                const SizedBox(height: 8),
                const Text('Saving export…'),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _CorrectionSummary extends StatelessWidget {
  const _CorrectionSummary();

  @override
  Widget build(BuildContext context) {
    final corrections = context
        .findAncestorWidgetOfExactType<LogsReportsScreen>()
        ?.corrections
        ?.records;
    if (corrections == null || corrections.isEmpty) {
      return const _UnavailableNote(
        title: 'Correction reports',
        body: 'No correction reports have been recorded in this session.',
      );
    }
    return Semantics(
      container: true,
      label: 'Correction reports, ${corrections.length} recorded',
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Correction reports',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              for (var index = corrections.length - 1; index >= 0; index--)
                _CorrectionSummaryRow(correction: corrections[index]),
            ],
          ),
        ),
      ),
    );
  }
}

class _CorrectionSummaryRow extends StatelessWidget {
  final DetectionCorrection correction;

  const _CorrectionSummaryRow({required this.correction});

  @override
  Widget build(BuildContext context) {
    final feedback = correction.correctedLabel == null
        ? correction.feedback.label
        : '${correction.feedback.label} as ${correction.correctedLabel}';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Semantics(
        container: true,
        label:
            '${correction.detection.label}, $feedback, '
            '${correction.engine.label}, threshold '
            '${correction.confidenceThreshold.toStringAsFixed(2)}',
        child: Text(
          '${correction.detection.label}: $feedback · '
          '${correction.engine.label} · threshold '
          '${correction.confidenceThreshold.toStringAsFixed(2)}',
        ),
      ),
    );
  }
}

class _ChartsTab extends StatelessWidget {
  const _ChartsTab();

  @override
  Widget build(BuildContext context) {
    return Builder(
      builder: (context) {
        final telemetry = _of(context);
        final theme = Theme.of(context);
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'Inference Latency (300 ms benchmark)',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 180,
              child: LatencyChart(samples: telemetry.samples),
            ),
            const SizedBox(height: 24),
            Text(
              'Frames Per Second (15 FPS target)',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(height: 180, child: FpsChart(samples: telemetry.samples)),
            const SizedBox(height: 24),
            Text(
              'Detection Frequency',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 180,
              child: DetectionFrequencyChart(
                buckets: telemetry.detectionFrequencyByMinute(),
              ),
            ),
            const SizedBox(height: 24),
          ],
        );
      },
    );
  }
}

class _LogsTab extends StatelessWidget {
  const _LogsTab();

  @override
  Widget build(BuildContext context) {
    return Builder(
      builder: (context) {
        final telemetry = _of(context);
        final records = telemetry.records;
        if (records.isEmpty) {
          return const Center(child: Text('No detections recorded yet.'));
        }
        return ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: records.length,
          itemBuilder: (context, index) {
            final r = records[records.length - 1 - index]; // newest first
            final time =
                '${r.timestamp.hour.toString().padLeft(2, '0')}:'
                '${r.timestamp.minute.toString().padLeft(2, '0')}:'
                '${r.timestamp.second.toString().padLeft(2, '0')}';
            return ListTile(
              dense: true,
              leading: _PriorityDot(priority: r.priority),
              title: Text(
                '${r.label} — ${(r.confidence * 100).toStringAsFixed(0)}%',
              ),
              subtitle: Text(
                '${r.engine.label} · ${r.position} · '
                '${r.latencyMs.toStringAsFixed(0)} ms',
              ),
              trailing: Text(time),
            );
          },
        );
      },
    );
  }
}

class _EngineSummaryCard extends StatelessWidget {
  final EngineTelemetrySummary summary;

  const _EngineSummaryCard({required this.summary});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasData = summary.sampleCount > 0;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Expanded(
              child: Text(
                summary.engine.label,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            Text(
              hasData
                  ? '${summary.averageInferenceFps.toStringAsFixed(1)} FPS · '
                        '${summary.averageLatencyMs.toStringAsFixed(1)} ms · '
                        '${summary.sampleCount} frames'
                  : 'No samples',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _PriorityDot extends StatelessWidget {
  final ObjectPriority priority;

  const _PriorityDot({required this.priority});

  @override
  Widget build(BuildContext context) {
    final color = switch (priority) {
      ObjectPriority.high => const Color(0xFFEF5350),
      ObjectPriority.medium => const Color(0xFFFFCA28),
      ObjectPriority.low => const Color(0xFF66BB6A),
    };
    return Icon(Icons.circle, color: color, size: 14);
  }
}

class _MetricCard extends StatelessWidget {
  final String label;
  final String value;

  const _MetricCard({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final String label;
  final String value;

  const _SummaryRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: theme.textTheme.bodyLarge),
          Text(
            value,
            style: theme.textTheme.bodyLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _UnavailableNote extends StatelessWidget {
  final String title;
  final String body;

  const _UnavailableNote({required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(body, style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }
}

/// Helper to reach the TelemetryService from a descendant builder without
/// passing it through every private widget.
TelemetryService _of(BuildContext context) =>
    (context.findAncestorWidgetOfExactType<LogsReportsScreen>()!).telemetry;

String _fmt(double v) => v.toStringAsFixed(1);
