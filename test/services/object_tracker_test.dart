import 'dart:ui';

import 'package:eyecue_flutter/models/detection.dart';
import 'package:eyecue_flutter/models/tracked_detection.dart';
import 'package:eyecue_flutter/services/object_tracker.dart';
import 'package:flutter_test/flutter_test.dart';

Detection detection(Rect box) =>
    Detection(classId: 0, label: 'person', confidence: 0.9, box: box);

void main() {
  final start = DateTime(2026, 1, 1);

  test('small jitter keeps a track stable after confirmation', () {
    final tracker = ObjectTracker();
    tracker.update([detection(const Rect.fromLTWH(0.4, 0.2, 0.2, 0.2))], start);
    tracker.update([
      detection(const Rect.fromLTWH(0.405, 0.2, 0.2, 0.2)),
    ], start.add(const Duration(milliseconds: 100)));
    final tracks = tracker.update([
      detection(const Rect.fromLTWH(0.41, 0.2, 0.2, 0.2)),
    ], start.add(const Duration(milliseconds: 200)));

    expect(tracks.single.motion, MotionState.stable);
    expect(tracks.single.hasConfirmedMotion, isFalse);
  });

  test('sustained growth becomes approaching after evidence', () {
    final tracker = ObjectTracker(growthThreshold: 0.03, smoothing: 1);
    tracker.update([detection(const Rect.fromLTWH(0.4, 0.2, 0.1, 0.1))], start);
    tracker.update([
      detection(const Rect.fromLTWH(0.4, 0.2, 0.13, 0.13)),
    ], start.add(const Duration(milliseconds: 200)));
    final tracks = tracker.update([
      detection(const Rect.fromLTWH(0.4, 0.2, 0.17, 0.17)),
    ], start.add(const Duration(milliseconds: 400)));

    expect(tracks.single.motion, MotionState.approaching);
    expect(tracks.single.hasConfirmedMotion, isTrue);
  });

  test('missed detections expire after the configured bound', () {
    final tracker = ObjectTracker(maxMissedUpdates: 1);
    tracker.update([detection(const Rect.fromLTWH(0.4, 0.2, 0.2, 0.2))], start);
    tracker.update(const [], start.add(const Duration(milliseconds: 100)));
    expect(tracker.activeTracks, isNotEmpty);
    tracker.update(const [], start.add(const Duration(milliseconds: 200)));
    expect(tracker.activeTracks, isEmpty);
  });

  test('reset clears tracks and restarts bounded state', () {
    final tracker = ObjectTracker();
    final first = tracker.update([
      detection(const Rect.fromLTWH(0.4, 0.2, 0.2, 0.2)),
    ], start);
    expect(first.single.trackId, 1);
    tracker.reset();
    final afterReset = tracker.update([
      detection(const Rect.fromLTWH(0.4, 0.2, 0.2, 0.2)),
    ], start.add(const Duration(seconds: 1)));
    expect(afterReset.single.trackId, 1);
  });
}
