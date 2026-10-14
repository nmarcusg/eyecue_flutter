import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_radii.dart';
import '../theme/app_spacing.dart';

/// High-contrast banner shown when a high-priority obstacle is detected.
class WarningBanner extends StatelessWidget {
  final String message;

  const WarningBanner({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      liveRegion: true,
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
