import 'package:flutter/material.dart';

import '../models/detection_info.dart';
import 'priority_badge.dart';

/// One user-facing object card in the Detection screen's object stream.
///
/// Shows the object class, confidence, relative position and approximate
/// proximity, plus a priority badge. Proximity is explicitly phrased as
/// "approximately …" because it is a box-size heuristic, not a measurement.
class DetectionCard extends StatelessWidget {
  final DetectionInfo info;
  final bool highlight;
  final VoidCallback? onReport;

  const DetectionCard({
    super.key,
    required this.info,
    this.highlight = false,
    this.onReport,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      container: true,
      label: info.semanticLabel,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: highlight
                ? theme.colorScheme.error
                : theme.colorScheme.outlineVariant,
            width: highlight ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: ExcludeSemantics(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          info.label,
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${(info.confidence * 100).toStringAsFixed(0)}% · '
                          '${info.positionLabel} · approximately ${info.proximityLabel}',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                ExcludeSemantics(child: PriorityBadge(priority: info.priority)),
              ],
            ),
            if (onReport != null)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: onReport,
                  icon: const Icon(Icons.flag_outlined, size: 18),
                  label: const Text('Report detection'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
