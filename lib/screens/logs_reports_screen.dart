import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemUiOverlayStyle;

import '../models/app_settings.dart';
import '../models/detection_correction.dart';
import '../models/detection_info.dart';
import '../services/correction_service.dart';
import '../services/settings_service.dart';
import '../services/telemetry_export_service.dart';
import '../services/telemetry_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_home_theme.dart';
import '../theme/app_radii.dart';
import '../theme/app_spacing.dart';
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
    // Route-local light theme: reuse the established Home-local light builder
    // for this pushed route only. The global dark theme and the underlying
    // shell navigation bar are unchanged, and popping the route leaves the
    // other tabs untouched.
    return Theme(
      data: buildHomeTheme(),
      // The route uses a light surface, so the status bar icons must be dark to
      // remain visible against it. This AnnotatedRegion is scoped to the pushed
      // route only, matching the existing Settings and Help light routes.
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.dark,
        child: DefaultTabController(
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
        final duration = telemetry.sessionDuration;
        final hours = duration.inHours;
        final minutes = duration.inMinutes % 60;
        final seconds = duration.inSeconds % 60;
        return _BoundedScrollView(
          children: [
            const _SectionHeading('Real-Time Performance'),
            const SizedBox(height: kSpace8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _MetricCard(
                  label: 'Avg FPS',
                  value: _fmt(telemetry.averageInferenceFps),
                ),
                const SizedBox(width: kSpace12),
                _MetricCard(
                  label: 'Avg Latency',
                  value: '${_fmt(telemetry.averageLatencyMs)} ms',
                ),
              ],
            ),
            const SizedBox(height: kSpace24),
            const _SectionHeading('Engine Comparison'),
            const SizedBox(height: kSpace8),
            for (final engine in InferenceEngine.values)
              _EngineSummaryCard(summary: telemetry.summaryFor(engine)),
            const SizedBox(height: kSpace24),
            const _SectionHeading('Session Summary'),
            const SizedBox(height: kSpace8),
            _SummaryCard(
              children: [
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
              ],
            ),
            const SizedBox(height: kSpace24),
            _ExportSection(
              exporting: exporting,
              onExportJson: onExportJson,
              onExportCsv: onExportCsv,
            ),
            const SizedBox(height: kSpace24),
            const _CorrectionSummary(),
            const SizedBox(height: kSpace24),
            const _UnavailableNote(
              title: 'Model Evaluation Metrics',
              body:
                  'Accuracy, Precision, Recall, F1, and mAP are not shown because '
                  'they require ground-truth labels (offline evaluation), which a '
                  'live camera feed cannot provide.',
            ),
            const SizedBox(height: kSpace12),
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
    final theme = Theme.of(context);
    return Semantics(
      container: true,
      label: 'Offline telemetry export',
      child: _LightCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Offline telemetry export',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: kSpace4),
            Text(
              'Save the current image-free session as a versioned JSON or '
              'CSV file. Exports contain no camera frames or device IDs.',
              style: theme.textTheme.bodyMedium?.copyWith(color: kHomeInkMuted),
            ),
            const SizedBox(height: kSpace12),
            Wrap(
              spacing: kSpace8,
              runSpacing: kSpace8,
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
              const SizedBox(height: kSpace8),
              Text(
                'Saving export…',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: kHomeInkMuted,
                ),
              ),
            ],
          ],
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
    final theme = Theme.of(context);
    return Semantics(
      container: true,
      label: 'Correction reports, ${corrections.length} recorded',
      child: _LightCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Correction reports',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: kSpace8),
            for (var index = corrections.length - 1; index >= 0; index--)
              _CorrectionSummaryRow(correction: corrections[index]),
          ],
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
    final theme = Theme.of(context);
    final feedback = correction.correctedLabel == null
        ? correction.feedback.label
        : '${correction.feedback.label} as ${correction.correctedLabel}';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: kSpace4),
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
          style: theme.textTheme.bodyMedium,
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
        return _BoundedScrollView(
          children: [
            _ChartCard(
              title: 'Inference Latency (300 ms benchmark)',
              child: LatencyChart(samples: telemetry.samples),
            ),
            const SizedBox(height: kSpace24),
            _ChartCard(
              title: 'Frames Per Second (15 FPS target)',
              child: FpsChart(samples: telemetry.samples),
            ),
            const SizedBox(height: kSpace24),
            _ChartCard(
              title: 'Detection Frequency',
              child: DetectionFrequencyChart(
                buckets: telemetry.detectionFrequencyByMinute(),
              ),
            ),
            const SizedBox(height: kSpace24),
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
        final theme = Theme.of(context);
        final records = telemetry.records;
        if (records.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(kSpace24),
              child: Text(
                'No detections recorded yet.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: kHomeInkMuted,
                ),
              ),
            ),
          );
        }
        return LayoutBuilder(
          builder: (context, constraints) {
            final boundedWidth = constraints.maxWidth > 480
                ? 480.0
                : constraints.maxWidth;
            return Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: boundedWidth),
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: kSpace8),
                  itemCount: records.length,
                  itemBuilder: (context, index) {
                    final r =
                        records[records.length - 1 - index]; // newest first
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
                      trailing: Text(
                        time,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: kHomeInkMuted,
                        ),
                      ),
                    );
                  },
                ),
              ),
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
    return Container(
      margin: const EdgeInsets.only(bottom: kSpace8),
      padding: const EdgeInsets.all(kSpace12),
      decoration: BoxDecoration(
        color: kHomeSurfaceCard,
        borderRadius: BorderRadius.circular(kRadius14),
        boxShadow: kHomeShadowSoft,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            summary.engine.label,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(width: kSpace8),
          Expanded(
            child: Text(
              hasData
                  ? '${summary.averageInferenceFps.toStringAsFixed(1)} FPS · '
                        '${summary.averageLatencyMs.toStringAsFixed(1)} ms · '
                        '${summary.sampleCount} frames'
                  : 'No samples',
              textAlign: TextAlign.end,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(color: kHomeInkMuted),
            ),
          ),
        ],
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
      ObjectPriority.high => kPriorityHigh,
      ObjectPriority.medium => kPriorityMedium,
      ObjectPriority.low => kPriorityLow,
    };
    final wording = switch (priority) {
      ObjectPriority.high => 'High priority',
      ObjectPriority.medium => 'Medium priority',
      ObjectPriority.low => 'Low priority',
    };
    // The dot is decorative; the priority wording is exposed as a semantic
    // label so priority is never conveyed by color alone.
    return Semantics(
      label: wording,
      child: ExcludeSemantics(
        child: Icon(Icons.circle, color: color, size: 14),
      ),
    );
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
        padding: const EdgeInsets.all(kSpace16),
        decoration: BoxDecoration(
          color: kHomeSurfaceCard,
          borderRadius: BorderRadius.circular(kRadius14),
          boxShadow: kHomeShadowSoft,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: kSpace4),
            Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(color: kHomeInkMuted),
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
      padding: const EdgeInsets.symmetric(vertical: kSpace6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: Text(label, style: theme.textTheme.bodyLarge)),
          const SizedBox(width: kSpace12),
          Text(
            value,
            textAlign: TextAlign.end,
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
      padding: const EdgeInsets.all(kSpace16),
      decoration: BoxDecoration(
        color: kHomeSurfaceCard,
        borderRadius: BorderRadius.circular(kRadius14),
        boxShadow: kHomeShadowSoft,
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
          const SizedBox(height: kSpace4),
          Text(
            body,
            style: theme.textTheme.bodyMedium?.copyWith(color: kHomeInkMuted),
          ),
        ],
      ),
    );
  }
}

/// Centered, bounded, vertically scrollable content column.
///
/// Uses the existing centered bounded secondary-screen precedent: content is
/// capped at ~480 logical pixels on wider windows and contracts to the
/// available width on narrower windows. The bound is derived from constraints,
/// never from a device-type check, orientation branch, or fixed canvas.
class _BoundedScrollView extends StatelessWidget {
  final List<Widget> children;

  const _BoundedScrollView({required this.children});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final contentWidth = constraints.maxWidth;
          final boundedWidth = contentWidth > 480 ? 480.0 : contentWidth;
          return Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: boundedWidth),
              child: ListView(
                padding: const EdgeInsets.symmetric(
                  horizontal: kSpace16,
                  vertical: kSpace16,
                ),
                children: children,
              ),
            ),
          );
        },
      ),
    );
  }
}

/// A light grouped card surface used for Overview sections.
class _LightCard extends StatelessWidget {
  final Widget child;

  const _LightCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(kSpace16),
      decoration: BoxDecoration(
        color: kHomeSurfaceCard,
        borderRadius: BorderRadius.circular(kRadius14),
        boxShadow: kHomeShadowSoft,
      ),
      child: child,
    );
  }
}

/// A section heading, visually distinct from metric labels and tab labels.
class _SectionHeading extends StatelessWidget {
  final String title;

  const _SectionHeading(this.title);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      title,
      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
    );
  }
}

/// A light grouped card wrapping the Session Summary metric rows.
class _SummaryCard extends StatelessWidget {
  final List<Widget> children;

  const _SummaryCard({required this.children});

  @override
  Widget build(BuildContext context) {
    return _LightCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }
}

/// A light chart card: a heading plus the chart drawn inside the existing
/// [kChartHeight] allocation. The chart widget itself owns its data binding,
/// dynamic bounds, benchmark lines, and semantics summary.
class _ChartCard extends StatelessWidget {
  final String title;
  final Widget child;

  const _ChartCard({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _LightCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: kSpace8),
          SizedBox(height: kChartHeight, child: child),
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
