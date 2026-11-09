import 'package:flutter/material.dart';

import '../theme/app_radii.dart';
import '../theme/app_spacing.dart';

/// Compact, high-contrast status indicator pill (e.g. "Detecting", "Paused",
/// "Stopped", "Idle").
class StatusPill extends StatelessWidget {
  final String label;
  final Color color;

  /// Whether this pill announces itself as a live region.
  ///
  /// Defaults to `true` so every existing call site keeps today's behaviour.
  /// Callers turn it off only when another surface is the single automatic
  /// announcer for the same transition (for example the failure panel).
  final bool liveRegion;

  const StatusPill({
    super.key,
    required this.label,
    required this.color,
    this.liveRegion = true,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      liveRegion: liveRegion,
      label: 'Detection status: $label',
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: kSpace12,
          vertical: kSpace6,
        ),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(kRadius20),
          border: Border.all(color: Colors.white, width: 1.5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ExcludeSemantics(
              child: Icon(Icons.circle, color: Colors.white, size: 10),
            ),
            const SizedBox(width: kSpace6),
            ExcludeSemantics(
              child: Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
