import 'package:flutter/material.dart';

import '../models/detection_info.dart';
import '../theme/app_colors.dart';
import '../theme/app_radii.dart';
import '../theme/app_spacing.dart';

/// Small high-contrast badge showing an object's priority tier.
///
/// HIGH = red, MEDIUM = amber, LOW = green. Text colors are chosen for
/// contrast on each background.
class PriorityBadge extends StatelessWidget {
  final ObjectPriority priority;
  final bool large;

  const PriorityBadge({super.key, required this.priority, this.large = false});

  @override
  Widget build(BuildContext context) {
    final (Color bg, Color fg, String label) = switch (priority) {
      ObjectPriority.high => (kWarningRed, Colors.white, 'HIGH'),
      ObjectPriority.medium => (kMediumAmber, kOnAmberDark, 'MEDIUM'),
      ObjectPriority.low => (kLowGreen, Colors.white, 'LOW'),
    };
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: large ? kSpace14 : kSpace10,
        vertical: large ? kSpace8 : kSpace4,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(kRadius6),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: fg,
          fontWeight: FontWeight.w800,
          fontSize: large ? 14 : 12,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}
