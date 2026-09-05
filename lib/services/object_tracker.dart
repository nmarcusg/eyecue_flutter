import 'dart:math' as math;
import 'dart:ui';

import '../models/detection.dart';
import '../models/tracked_detection.dart';

/// Pure, bounded, engine-independent association of normalized detections.
///
/// The tracker only sees post-NMS [Detection] objects. It uses class-aware
/// IoU/center matching and timestamped box geometry; it never copies camera
/// frames or participates in inference.
class ObjectTracker {
  ObjectTracker({
    DateTime Function()? clock,
    this.minHits = 3,
    this.minTrackAge = const Duration(milliseconds: 200),
    this.maxMissedUpdates = 4,
    this.matchIouThreshold = 0.05,
    this.maxCenterDistance = 0.22,
    this.smoothing = 0.5,
    this.growthThreshold = 0.08,
    this.hysteresisHits = 2,
    this.maxTracks = 64,
  }) : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;
  final int minHits;
  final Duration minTrackAge;
  final int maxMissedUpdates;
  final double matchIouThreshold;
  final double maxCenterDistance;
  final double smoothing;
  final double growthThreshold;
  final int hysteresisHits;
  final int maxTracks;

  final List<_Track> _tracks = [];
  int _nextTrackId = 1;

  List<TrackedDetection> get activeTracks =>
      List.unmodifiable(_tracks.map((track) => track.snapshot()));

  /// Associates the current post-NMS set with existing tracks.
  List<TrackedDetection> update(
    List<Detection> detections, [
    DateTime? timestamp,
  ]) {
    final now = timestamp ?? _clock();
    final matchedTrackIds = <int>{};
    final matchedDetectionIndexes = <int>{};
    final assignments = <({int detectionIndex, _Track track})>[];
    final observedTrackIds = <int>{};

    // Greedy global ordering prefers stronger geometric matches. Matching is
    // class-aware, so two different COCO classes can never swap tracks.
    final candidates = <({double score, int detectionIndex, _Track track})>[];
    for (
      var detectionIndex = 0;
      detectionIndex < detections.length;
      detectionIndex++
    ) {
      final detection = detections[detectionIndex];
      for (final track in _tracks) {
        if (track.classId != detection.classId ||
            matchedTrackIds.contains(track.id)) {
          continue;
        }
        final iou = _iou(track.box, detection.box);
        final distance = _centerDistance(track.center, _center(detection.box));
        if (iou >= matchIouThreshold || distance <= maxCenterDistance) {
          // Higher IoU wins; for weak overlap, the center-distance term makes
          // crossing same-class objects less likely to swap immediately.
          candidates.add((
            score: iou * 2.0 - distance,
            detectionIndex: detectionIndex,
            track: track,
          ));
        }
      }
    }
    candidates.sort((a, b) {
      final score = b.score.compareTo(a.score);
      if (score != 0) return score;
      final track = a.track.id.compareTo(b.track.id);
      return track != 0 ? track : a.detectionIndex.compareTo(b.detectionIndex);
    });
    for (final candidate in candidates) {
      if (matchedTrackIds.contains(candidate.track.id) ||
          matchedDetectionIndexes.contains(candidate.detectionIndex)) {
        continue;
      }
      matchedTrackIds.add(candidate.track.id);
      matchedDetectionIndexes.add(candidate.detectionIndex);
      assignments.add((
        detectionIndex: candidate.detectionIndex,
        track: candidate.track,
      ));
    }

    for (final assignment in assignments) {
      assignment.track.update(detections[assignment.detectionIndex], now, this);
      observedTrackIds.add(assignment.track.id);
    }

    for (final track in _tracks) {
      if (!matchedTrackIds.contains(track.id)) track.missedUpdates++;
    }

    for (var i = 0; i < detections.length; i++) {
      if (matchedDetectionIndexes.contains(i)) continue;
      final track = _Track(_nextTrackId++, detections[i], now);
      _tracks.add(track);
      observedTrackIds.add(track.id);
    }

    _tracks.removeWhere((track) => track.missedUpdates > maxMissedUpdates);
    if (_tracks.length > maxTracks) {
      _tracks.sort((a, b) {
        final missed = a.missedUpdates.compareTo(b.missedUpdates);
        if (missed != 0) return missed;
        return b.lastSeen.compareTo(a.lastSeen);
      });
      _tracks.removeRange(maxTracks, _tracks.length);
    }

    // Return only detections observed in this update. Stale tracks remain
    // internally for a bounded number of misses but are not re-announced.
    return _tracks
        .where((track) => observedTrackIds.contains(track.id))
        .map((track) => track.snapshot())
        .toList()
      ..sort((a, b) => a.trackId.compareTo(b.trackId));
  }

  void reset() {
    _tracks.clear();
    _nextTrackId = 1;
  }

  static Offset _center(Rect box) => Offset(box.center.dx, box.center.dy);

  static double _centerDistance(Offset a, Offset b) =>
      math.sqrt(math.pow(a.dx - b.dx, 2) + math.pow(a.dy - b.dy, 2));

  static double _iou(Rect a, Rect b) {
    final intersection = a.intersect(b);
    if (intersection.isEmpty) return 0;
    final union =
        a.width * a.height +
        b.width * b.height -
        intersection.width * intersection.height;
    return union <= 0 ? 0 : intersection.width * intersection.height / union;
  }
}

class _Track {
  _Track(this.id, Detection detection, this.firstSeen)
    : classId = detection.classId,
      label = detection.label,
      box = detection.box,
      center = ObjectTracker._center(detection.box),
      smoothedArea = _area(detection.box),
      smoothedHeight = detection.box.height,
      confidence = detection.confidence,
      detection = detection {
    lastSeen = firstSeen;
  }

  final int id;
  final int classId;
  final String label;
  final DateTime firstSeen;
  Detection detection;
  Rect box;
  Offset center;
  double smoothedArea;
  double smoothedHeight;
  double confidence;
  DateTime lastSeen = DateTime.fromMillisecondsSinceEpoch(0);
  int hitCount = 1;
  int missedUpdates = 0;
  int growthEvidence = 0;
  int shrinkEvidence = 0;
  MotionState motion = MotionState.unknown;
  double centerDisplacement = 0;

  void update(Detection next, DateTime timestamp, ObjectTracker config) {
    final previousCenter = center;
    final previousArea = smoothedArea;
    final previousHeight = smoothedHeight;
    final alpha = config.smoothing.clamp(0.05, 1.0).toDouble();
    detection = next;
    box = next.box;
    final nextCenter = ObjectTracker._center(next.box);
    center = Offset(
      previousCenter.dx + (nextCenter.dx - previousCenter.dx) * alpha,
      previousCenter.dy + (nextCenter.dy - previousCenter.dy) * alpha,
    );
    smoothedArea = previousArea + (_area(next.box) - previousArea) * alpha;
    smoothedHeight =
        previousHeight + (next.box.height - previousHeight) * alpha;
    confidence = confidence + (next.confidence - confidence) * alpha;
    centerDisplacement = ObjectTracker._centerDistance(
      previousCenter,
      nextCenter,
    );
    lastSeen = timestamp;
    hitCount++;
    missedUpdates = 0;

    final areaRatio = previousArea <= 0 ? 1.0 : smoothedArea / previousArea;
    final heightRatio = previousHeight <= 0
        ? 1.0
        : smoothedHeight / previousHeight;
    final growth = math.max(areaRatio, heightRatio);
    final shrink = math.min(areaRatio, heightRatio);
    if (growth > 1.0 + config.growthThreshold) {
      growthEvidence++;
      shrinkEvidence = 0;
    } else if (shrink < 1.0 - config.growthThreshold) {
      shrinkEvidence++;
      growthEvidence = 0;
    } else {
      growthEvidence = math.max(0, growthEvidence - 1);
      shrinkEvidence = math.max(0, shrinkEvidence - 1);
    }

    final age = timestamp.difference(firstSeen);
    final enoughEvidence =
        hitCount >= config.minHits && age >= config.minTrackAge;
    if (!enoughEvidence) {
      motion = MotionState.unknown;
    } else if (growthEvidence >= config.hysteresisHits) {
      motion = MotionState.approaching;
    } else if (shrinkEvidence >= config.hysteresisHits) {
      motion = MotionState.movingAway;
    } else {
      motion = MotionState.stable;
    }
  }

  TrackedDetection snapshot() => TrackedDetection(
    detection: detection,
    trackId: id,
    firstSeen: firstSeen,
    lastSeen: lastSeen,
    smoothedCenter: center,
    smoothedArea: smoothedArea,
    smoothedHeight: smoothedHeight,
    confidence: confidence,
    hitCount: hitCount,
    missedUpdateCount: missedUpdates,
    motion: motion,
    centerDisplacement: centerDisplacement,
  );

  static double _area(Rect box) => math.max(0, box.width * box.height);
}
