import 'package:flutter/material.dart';

import '../models/detection_info.dart';

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
      ObjectPriority.high => (const Color(0xFFB71C1C), Colors.white, 'HIGH'),
      ObjectPriority.medium => (
          const Color(0xFFF9A825),
          const Color(0xFF1A1A1A),
          'MEDIUM',
        ),
      ObjectPriority.low => (const Color(0xFF1B5E20), Colors.white, 'LOW'),
    };
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: large ? 14 : 10,
        vertical: large ? 8 : 4,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
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
