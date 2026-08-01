import 'dart:ui';

class Detection {
  final int classId;
  final String label;
  final double confidence;
  final Rect box; // x, y, w, h normalized (0.0 to 1.0)

  Detection({
    required this.classId,
    required this.label,
    required this.confidence,
    required this.box,
  });
}