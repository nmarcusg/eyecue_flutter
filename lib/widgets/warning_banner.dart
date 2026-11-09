import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_radii.dart';
import '../theme/app_spacing.dart';

/// High-contrast banner shown when a high-priority obstacle is detected.
class WarningBanner extends StatelessWidget {
  final String message;

  /// Whether this banner announces itself as a live region.
  ///
  /// Defaults to `true` so every existing call site keeps today's behaviour.
  /// The safety dialog passes `false` so its lead line does not compete with
  /// the disclosure on entry.
  final bool liveRegion;

  const WarningBanner({
    super.key,
    required this.message,
    this.liveRegion = true,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      liveRegion: liveRegion,
      label: 'Warning. $message',
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.all(kSpace12),
        padding: const EdgeInsets.symmetric(
          horizontal: kSpace16,
          vertical: kSpace14,
        ),
        decoration: BoxDecoration(
          color: kWarningRed,
          borderRadius: BorderRadius.circular(kRadius12),
          border: Border.all(color: Colors.white, width: 2),
        ),
        child: Row(
          children: [
            const ExcludeSemantics(
              child: Icon(
                Icons.warning_amber_rounded,
                color: Colors.white,
                size: 28,
              ),
            ),
            const SizedBox(width: kSpace12),
            Expanded(
              child: ExcludeSemantics(
                child: Text(
                  message,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
