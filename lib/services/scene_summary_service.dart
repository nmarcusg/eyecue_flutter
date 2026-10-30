import '../models/detection_info.dart';
import '../models/tracked_detection.dart';

/// Builds deterministic, cautious utterances from normalized detections.
///
/// This service has no TTS dependency, so the same wording can be used for
/// speech, Semantics, logs, and tests by both inference engines.
class SceneSummaryService {
  const SceneSummaryService({
    this.maxQuickScanItems = 4,
    this.maxPhraseLength = 240,
  });

  final int maxQuickScanItems;
  final int maxPhraseLength;

  String alert(
    Iterable<DetectionInfo> detections, {
    Iterable<TrackedDetection> tracks = const [],
  }) {
    final allDetections = detections.toList(growable: false);
    final candidates = rankCandidates(allDetections, tracks: tracks);
    if (candidates.isEmpty) return 'Alert. No objects detected.';
    final info = candidates.first.info;
    final motion = _confirmedMotion(candidates.first.track);
    final priority = info.priority == ObjectPriority.high
        ? ', high priority obstacle'
        : '';
    final movement = motion == null ? '' : ' and appears to be $motion';
    final count = allDetections.length > 1
        ? ' ${allDetections.length} objects detected.'
        : '.';
    return _limit(
      'Alert. ${info.label}$priority, on your ${info.positionLabel}, '
      '${info.distanceLabel ?? 'approximately ${info.proximityLabel}'}'
      '$movement.$count',
    );
  }

  String quickScan(
    Iterable<DetectionInfo> detections, {
    Iterable<TrackedDetection> tracks = const [],
  }) {
    final ranked = rankCandidates(detections, tracks: tracks);
    if (ranked.isEmpty) return 'Quick scan. No objects detected.';

    final groups = <RelativePosition, List<RankedCandidate>>{
      RelativePosition.left: [],
      RelativePosition.center: [],
      RelativePosition.right: [],
    };
    for (final candidate in ranked.take(maxQuickScanItems)) {
      groups[candidate.info.position]!.add(candidate);
    }

    final parts = <String>[];
    for (final position in RelativePosition.values) {
      final inPosition = groups[position]!;
      if (inPosition.isEmpty) continue;
      final labels = <String>[];
      for (final candidate in inPosition) {
        final movement = _confirmedMotion(candidate.track);
        labels.add(
          '${candidate.info.label}, '
          '${candidate.info.distanceLabel ?? 'approximately ${candidate.info.proximityLabel}'}'
          '${movement == null ? '' : ', appears to be $movement'}',
        );
      }
      final positionLabel = switch (position) {
        RelativePosition.left => 'left',
        RelativePosition.center => 'center',
        RelativePosition.right => 'right',
      };
      parts.add('${labels.join('; ')} on your $positionLabel');
    }
    return _limit('Quick scan. ${parts.join('. ')}.');
  }

  /// Short, information-first phrase for an immediate safety alert.
  ///
  /// Urgent speech must convey the hazard before the qualifiers, so it never
  /// begins with "Alert." or "high priority obstacle". Detailed wording stays
  /// available through [alert] and [quickScan].
  String urgentAlert(DetectionInfo info, {TrackedDetection? track}) {
    final motion = _confirmedMotion(track);
    final position = info.position == RelativePosition.center
        ? ''
        : ', ${info.positionLabel}';
    if (info.proximity == ProximityBand.near) {
      return _limit('${info.label} very close$position.');
    }
    if (motion == 'approaching') {
      return _limit(
        '${info.label} approaching${position.isEmpty ? ' ahead' : position}.',
      );
    }
    return _limit('${info.label}${position.isEmpty ? ' ahead' : position}.');
  }

  /// Single authoritative ranking used by both alert suppression and speech.
  ///
  /// Ordering: priority, then motion, then proximity, then confidence, then
  /// label. Callers must not implement their own ordering.
  List<RankedCandidate> rankCandidates(
    Iterable<DetectionInfo> detections, {
    Iterable<TrackedDetection> tracks = const [],
  }) {
    final tracksByDetection = <Object, TrackedDetection>{};
    for (final track in tracks) {
      tracksByDetection[_detectionKey(track.detection)] = track;
    }
    final candidates = detections
        .map(
          (info) => RankedCandidate(
            info,
            tracksByDetection[_detectionKey(info.detection)],
          ),
        )
        .toList();
    candidates.sort((a, b) {
      final priority = _priorityRank(
        b.info.priority,
      ).compareTo(_priorityRank(a.info.priority));
      if (priority != 0) return priority;
      final motion = _motionRank(
        b.track?.motion,
      ).compareTo(_motionRank(a.track?.motion));
      if (motion != 0) return motion;
      final proximity = _proximityRank(
        a.info.proximity,
      ).compareTo(_proximityRank(b.info.proximity));
      if (proximity != 0) return proximity;
      final confidence = b.info.confidence.compareTo(a.info.confidence);
      if (confidence != 0) return confidence;
      final label = a.info.label.compareTo(b.info.label);
      if (label != 0) return label;
      return a.info.detection.classId.compareTo(b.info.detection.classId);
    });
    return candidates;
  }

  String _limit(String text) {
    if (text.length <= maxPhraseLength) return text;
    final cut = text.substring(0, maxPhraseLength).trimRight();
    final boundary = cut.lastIndexOf(' ');
    return '${(boundary > 0 ? cut.substring(0, boundary) : cut)}.';
  }

  static Object _detectionKey(dynamic detection) => (
    detection.classId,
    detection.box.left,
    detection.box.top,
    detection.box.width,
    detection.box.height,
  );

  static int _priorityRank(ObjectPriority priority) => switch (priority) {
    ObjectPriority.high => 3,
    ObjectPriority.medium => 2,
    ObjectPriority.low => 1,
  };

  static int _proximityRank(ProximityBand proximity) => switch (proximity) {
    ProximityBand.near => 0,
    ProximityBand.medium => 1,
    ProximityBand.far => 2,
  };

  static int _motionRank(MotionState? motion) => switch (motion) {
    MotionState.approaching => 2,
    MotionState.movingAway => 1,
    MotionState.stable => 0,
    MotionState.unknown || null => -1,
  };

  static String? _confirmedMotion(TrackedDetection? track) {
    if (track == null || !track.hasConfirmedMotion) return null;
    return track.motion == MotionState.approaching
        ? 'approaching'
        : 'moving away';
  }
}

/// A detection paired with the track that matched it, when one exists.
class RankedCandidate {
  final DetectionInfo info;
  final TrackedDetection? track;

  const RankedCandidate(this.info, this.track);
}
