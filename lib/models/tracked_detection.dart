import 'dart:ui';

import 'detection.dart';

/// Conservative motion estimate derived from timestamped bounding boxes.
enum MotionState { unknown, stable, approaching, movingAway }

extension MotionStateX on MotionState {
  String get label => switch (this) {
    MotionState.unknown => 'unknown',
    MotionState.stable => 'stable',
    MotionState.approaching => 'approaching',
    MotionState.movingAway => 'moving away',
  };
}

/// A normalized detection associated with a short-lived object track.
///
/// Motion is an estimate of relative box growth/shrinkage. It is deliberately
/// not a calibrated distance, speed, or identity claim.
class TrackedDetection {
  final Detection detection;
  final int trackId;
  final DateTime firstSeen;
  final DateTime lastSeen;
  final Offset smoothedCenter;
  final double smoothedArea;
  final double smoothedHeight;
  final double confidence;
  final int hitCount;
  final int missedUpdateCount;
  final MotionState motion;
  final double centerDisplacement;

  const TrackedDetection({
    required this.detection,
    required this.trackId,
    required this.firstSeen,
    required this.lastSeen,
    required this.smoothedCenter,
    required this.smoothedArea,
    required this.smoothedHeight,
    required this.confidence,
    required this.hitCount,
    required this.missedUpdateCount,
    required this.motion,
    required this.centerDisplacement,
  });

  int get classId => detection.classId;
  String get label => detection.label;
  Rect get box => detection.box;
  bool get hasConfirmedMotion =>
      motion == MotionState.approaching || motion == MotionState.movingAway;

  Map<String, dynamic> toJson() => {
    'trackId': trackId,
    'firstSeen': firstSeen.toUtc().toIso8601String(),
    'lastSeen': lastSeen.toUtc().toIso8601String(),
    'smoothedCenter': {'x': smoothedCenter.dx, 'y': smoothedCenter.dy},
    'smoothedArea': smoothedArea,
    'smoothedHeight': smoothedHeight,
    'confidence': confidence,
    'hitCount': hitCount,
    'missedUpdateCount': missedUpdateCount,
    'motion': motion.name,
    'centerDisplacement': centerDisplacement,
    'detection': {
      'classId': detection.classId,
      'label': detection.label,
      'confidence': detection.confidence,
      'box': {
        'left': detection.box.left,
        'top': detection.box.top,
        'width': detection.box.width,
        'height': detection.box.height,
      },
    },
  };
}
