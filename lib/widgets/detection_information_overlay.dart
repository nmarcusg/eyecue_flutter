import 'package:flutter/material.dart';

import '../models/detection_info.dart';
import '../theme/app_colors.dart';
import '../theme/app_radii.dart';
import '../theme/app_spacing.dart';

/// The maximum number of informational rows the overlay may display.
const int kDetectionOverlayMaxRows = 2;

/// Compact, current-information overlay rendered inside the Detection viewport.
///
/// The overlay displays at most [kDetectionOverlayMaxRows] informational rows
/// selected from the supplied [infos]. Selection stably promotes High-priority
/// entries in their existing relative order, then fills any remaining row from
/// the original source order. It never introduces a Medium-over-Low ranking.
///
/// The overlay is pointer-inert so it cannot consume raw pointers intended for
/// the viewport gesture surface, and each visible row exposes exactly one
/// manual, non-live informational semantic node containing only the label plus
/// the already-derived qualitative position/proximity.
class DetectionInformationOverlay extends StatelessWidget {
  const DetectionInformationOverlay({
    super.key,
    required this.infos,
    required this.eligible,
  });

  /// The already-current detection information in canonical source order.
  final List<DetectionInfo> infos;

  /// Whether the overlay is eligible to render. When false the overlay renders
  /// nothing, regardless of [infos].
  final bool eligible;

  /// Selects the rows to display using the locked PD3 selection rule.
  ///
  /// High-priority entries are promoted first in their existing relative order,
  /// then the remaining slots are filled from the original source order.
  static List<DetectionInfo> selectRows(List<DetectionInfo> infos) {
    if (infos.isEmpty) return const [];
    final selected = <DetectionInfo>[];
    for (final info in infos) {
      if (info.priority == ObjectPriority.high) {
        selected.add(info);
        if (selected.length == kDetectionOverlayMaxRows) return selected;
      }
    }
    for (final info in infos) {
      if (selected.contains(info)) continue;
      selected.add(info);
      if (selected.length == kDetectionOverlayMaxRows) break;
    }
    return selected;
  }

  @override
  Widget build(BuildContext context) {
    if (!eligible) return const SizedBox.shrink();
    final rows = selectRows(infos);
    if (rows.isEmpty) return const SizedBox.shrink();

    return IgnorePointer(
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Container(
          margin: const EdgeInsets.all(kSpace12),
          padding: const EdgeInsets.symmetric(
            horizontal: kSpace12,
            vertical: kSpace8,
          ),
          decoration: BoxDecoration(
            color: kOverlayBlack,
            borderRadius: BorderRadius.circular(kRadius12),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < rows.length; i++) ...[
                if (i > 0) const SizedBox(height: kSpace4),
                _DetectionOverlayRow(info: rows[i]),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// A single informational overlay row.
///
/// Exposes exactly one manual, non-live semantic node containing only the
/// label plus qualitative position/proximity. High priority is a visual amber
/// distinction only and is never repeated in the spoken label.
class _DetectionOverlayRow extends StatelessWidget {
  const _DetectionOverlayRow({required this.info});

  final DetectionInfo info;

  @override
  Widget build(BuildContext context) {
    final isHigh = info.priority == ObjectPriority.high;
    final accent = isHigh ? kHomeWarningAmber : kHomeAccentCyan;
    final label =
        '${info.label}, ${info.positionLabel}, ${info.proximityLabel}';

    return Semantics(
      container: true,
      label: label,
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: kSpace4,
              height: kSpace16,
              decoration: BoxDecoration(
                color: accent,
                borderRadius: BorderRadius.circular(kRadius3),
              ),
            ),
            const SizedBox(width: kSpace8),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: isHigh ? kHomeWarningAmber : kOnAccentWhite,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
