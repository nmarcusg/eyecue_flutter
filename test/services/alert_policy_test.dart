import 'dart:ui';

import 'package:eyecue_flutter/models/detection.dart';
import 'package:eyecue_flutter/models/detection_info.dart';
import 'package:eyecue_flutter/models/detector_model.dart';
import 'package:eyecue_flutter/models/tracked_detection.dart';
import 'package:eyecue_flutter/services/alert_policy.dart';
import 'package:eyecue_flutter/services/spatial_analysis_service.dart';
import 'package:flutter_test/flutter_test.dart';

DetectionInfo info({
  int classId = 0,
  String label = 'person',
  Rect? box,
  double conf = 0.9,
}) {
  return SpatialAnalysisService.analyze(
    Detection(
      classId: classId,
      label: label,
      confidence: conf,
      box: box ?? const Rect.fromLTWH(0.3, 0.2, 0.4, 0.5),
    ),
  );
}

DetectionInfo metricInfo(
  double meters, {
  String label = 'person',
  int classId = 0,
}) => SpatialAnalysisService.analyze(
  Detection(
    classId: classId,
    label: label,
    confidence: 0.9,
    box: const Rect.fromLTWH(0.4, 0.2, 0.2, 0.2),
  ),
  meters: meters,
);

TrackedDetection trackOf(
  DetectionInfo source, {
  required int id,
  MotionState motion = MotionState.stable,
  double? smoothedHeight,
}) {
  final detection = source.detection;
  return TrackedDetection(
    detection: detection,
    trackId: id,
    firstSeen: DateTime(2026),
    lastSeen: DateTime(2026),
    smoothedCenter: Offset(detection.box.center.dx, detection.box.center.dy),
    smoothedArea: detection.box.width * detection.box.height,
    smoothedHeight: smoothedHeight ?? detection.box.height,
    confidence: detection.confidence,
    hitCount: 3,
    missedUpdateCount: 0,
    motion: motion,
    centerDisplacement: 0,
  );
}

void main() {
  late DateTime now;
  late AlertPolicy policy;

  setUp(() {
    now = DateTime(2026, 1, 1, 12);
    policy = AlertPolicy();
  });

  AlertDecision decide(
    List<DetectionInfo> detections, {
    List<TrackedDetection> tracks = const [],
    bool audioEnabled = true,
    bool force = false,
  }) => policy.decide(
    detections: detections,
    tracks: tracks,
    now: now,
    audioEnabled: audioEnabled,
    force: force,
  );

  group('decide is read-only', () {
    test('no state is written until commitStarted', () {
      final primary = info();
      final track = trackOf(primary, id: 7);
      for (var i = 0; i < 100; i++) {
        final decision = decide([primary], tracks: [track]);
        expect(decision.announce, isTrue);
      }
      expect(policy.hasStateFor('track:7'), isFalse);
      expect(policy.lastStartedUtterance, isNull);
      expect(policy.lastStartedAtFor('track:7'), isNull);
    });
  });

  group('commit lifecycle', () {
    test('commitStarted arms history', () {
      final primary = info();
      final track = trackOf(primary, id: 3);
      final decision = decide([primary], tracks: [track]);
      policy.commitStarted(decision, now);

      expect(policy.hasStateFor('track:3'), isTrue);
      expect(policy.lastStartedAtFor('track:3'), now);
      expect(policy.lastStartedUtterance, decision.text);

      now = now.add(const Duration(seconds: 2));
      policy.commitCompleted(decision, now);
      expect(policy.lastStartedAtFor('track:3'), DateTime(2026, 1, 1, 12));
      expect(policy.lastCompletedAt, now);
    });

    test('commitCancelled before start arms nothing', () {
      final primary = info();
      final track = trackOf(primary, id: 4);
      final decision = decide([primary], tracks: [track]);
      policy.commitCancelled(
        decision,
        now,
        hadStarted: false,
        cause: 'startNotConfirmed',
      );
      expect(policy.hasStateFor('track:4'), isFalse);
      expect(policy.cancelledAfterStartCount, 0);
    });

    test('commitCancelled after start preserves history', () {
      final primary = info();
      final track = trackOf(primary, id: 5);
      final decision = decide([primary], tracks: [track]);
      policy.commitStarted(decision, now);
      final armedAt = policy.lastStartedAtFor('track:5');

      now = now.add(const Duration(seconds: 1));
      policy.commitCancelled(
        decision,
        now,
        hadStarted: true,
        cause: 'preempted',
      );

      expect(policy.lastStartedAtFor('track:5'), armedAt);
      expect(policy.cancelledAfterStartCount, 1);
    });
  });

  group('identity', () {
    test('a new track announces even when the label was just announced', () {
      final first = info();
      final firstTrack = trackOf(first, id: 1);
      policy.commitStarted(decide([first], tracks: [firstTrack]), now);

      now = now.add(const Duration(milliseconds: 500));
      final secondBox = const Rect.fromLTWH(0.5, 0.2, 0.2, 0.5);
      final second = info(box: secondBox);
      final secondTrack = trackOf(second, id: 2);

      final decision = decide([second], tracks: [secondTrack]);
      expect(decision.announce, isTrue);
      expect(decision.reason, AlertReason.newTrack);
      expect(decision.suppressionKey, 'track:2');
    });

    test('the same stable track is suppressed', () {
      final primary = info();
      final track = trackOf(primary, id: 9);
      policy.commitStarted(decide([primary], tracks: [track]), now);

      now = now.add(const Duration(seconds: 5));
      final decision = decide([primary], tracks: [track]);
      expect(decision.announce, isFalse);
      expect(decision.reason, AlertReason.suppressedSameObject);
    });

    test(
      'a suppressed primary does not announce a non-qualifying substitute',
      () {
        final person = info();
        final personTrack = trackOf(person, id: 21);
        final bottle = info(
          classId: 39,
          label: 'bottle',
          box: const Rect.fromLTWH(0.05, 0.6, 0.1, 0.12),
        );
        final bottleTrack = trackOf(bottle, id: 22);

        policy.commitStarted(decide([person], tracks: [personTrack]), now);
        policy.commitStarted(decide([bottle], tracks: [bottleTrack]), now);

        now = now.add(const Duration(seconds: 2));
        final decision = decide(
          [person, bottle],
          tracks: [personTrack, bottleTrack],
        );
        expect(decision.announce, isFalse);
        expect(decision.reason, AlertReason.suppressedSameObject);
        expect(decision.suppressionKey, 'track:21');
      },
    );

    test('falls back to label identity when no track exists', () {
      final primary = info();
      final decision = decide([primary]);
      expect(decision.suppressionKey, 'label:person');
      expect(decision.reason, AlertReason.newLabelFallback);
    });
  });

  group('risk escalation', () {
    test('proximity band increase re-alerts once', () {
      final medium = metricInfo(1.7);
      final track = trackOf(medium, id: 11);
      policy.commitStarted(decide([medium], tracks: [track]), now);

      now = now.add(const Duration(seconds: 1));
      final near = metricInfo(1.4);
      final nearTrack = trackOf(near, id: 11);

      final escalated = decide([near], tracks: [nearTrack]);
      expect(escalated.announce, isTrue);
      expect(escalated.reason, AlertReason.riskEscalation);

      policy.commitStarted(escalated, now);
      now = now.add(const Duration(seconds: 1));
      expect(decide([near], tracks: [nearTrack]).announce, isFalse);
    });

    test('motion approaching re-alerts', () {
      final primary = info(box: const Rect.fromLTWH(0.3, 0.2, 0.4, 0.5));
      policy.commitStarted(
        decide([primary], tracks: [trackOf(primary, id: 12)]),
        now,
      );

      now = now.add(const Duration(seconds: 1));
      final decision = decide(
        [primary],
        tracks: [trackOf(primary, id: 12, motion: MotionState.approaching)],
      );
      expect(decision.announce, isTrue);
      expect(decision.reason, AlertReason.riskEscalation);
      expect(decision.priority, AlertPriority.imminent);
    });

    test('off-centre geometry fallback is ineligible', () {
      final side = info(box: const Rect.fromLTWH(0.05, 0.2, 0.2, 0.5));
      final decision = decide([side], tracks: [trackOf(side, id: 13)]);
      expect(decision.announce, isFalse);
      expect(decision.reason, AlertReason.suppressedNoCandidates);
    });

    test('substantial size growth re-alerts', () {
      final small = info(box: const Rect.fromLTWH(0.3, 0.2, 0.4, 0.5));
      policy.commitStarted(
        decide([small], tracks: [trackOf(small, id: 14)]),
        now,
      );

      now = now.add(const Duration(seconds: 1));
      final grown = info(box: const Rect.fromLTWH(0.3, 0.2, 0.4, 0.5));
      final decision = decide(
        [grown],
        tracks: [trackOf(grown, id: 14, smoothedHeight: 0.7)],
      );
      expect(decision.announce, isTrue);
      expect(decision.reason, AlertReason.riskEscalation);
    });

    test('minEscalationGap prevents an immediate second escalation', () {
      final medium = metricInfo(1.7);
      policy.commitStarted(
        decide([medium], tracks: [trackOf(medium, id: 15)]),
        now,
      );

      now = now.add(const Duration(milliseconds: 50));
      final near = metricInfo(1.4);
      final decision = decide([near], tracks: [trackOf(near, id: 15)]);
      expect(decision.announce, isFalse);
    });
  });

  group('priority and gating', () {
    test('custom detector metric alert uses center-path thresholds', () {
      final decision = policy.decide(
        detections: [metricInfo(1.2)],
        tracks: const [],
        now: now,
        audioEnabled: true,
        detectorKind: DetectorModelKind.custom,
        detectorIdentity: 'fingerprint-a',
      );
      expect(decision.announce, isTrue);
      expect(decision.priority, AlertPriority.imminent);
      expect(decision.suppressionKey, startsWith('fingerprint-a|'));
    });

    test('custom metric beyond two metres and side metric do not alert', () {
      final far = policy.decide(
        detections: [metricInfo(2.2)],
        tracks: const [],
        now: now,
        audioEnabled: true,
        detectorKind: DetectorModelKind.custom,
        detectorIdentity: 'custom-a',
      );
      expect(far.announce, isFalse);

      final side = SpatialAnalysisService.analyze(
        Detection(
          classId: 0,
          label: 'person',
          confidence: .9,
          box: const Rect.fromLTWH(.05, .2, .2, .2),
        ),
        meters: 1.0,
      );
      expect(
        policy
            .decide(
              detections: [side],
              tracks: const [],
              now: now,
              audioEnabled: true,
              detectorKind: DetectorModelKind.custom,
              detectorIdentity: 'custom-a',
            )
            .announce,
        isFalse,
      );
    });

    test('fresh five metre metric suppresses both detector kinds', () {
      for (final detector in DetectorModelKind.values) {
        final decision = policy.decide(
          detections: [metricInfo(5.0)],
          tracks: const [],
          now: now,
          audioEnabled: true,
          detectorKind: detector,
          detectorIdentity: 'detector-${detector.name}',
        );
        expect(decision.announce, isFalse);
        expect(decision.reason, AlertReason.suppressedNoCandidates);
      }
    });

    test('invalid metric depth never falls through to bounding geometry', () {
      final raw = info(box: const Rect.fromLTWH(0.3, 0.2, 0.4, 0.5));
      final invalidDepth = DetectionInfo(
        detection: raw.detection,
        position: raw.position,
        priority: raw.priority,
        proximity: raw.proximity,
        estimatedMeters: double.nan,
        distanceSource: DistanceSource.monocularDepth,
        distanceLabel: 'about 1.0 m',
      );
      for (final detector in DetectorModelKind.values) {
        final decision = policy.decide(
          detections: [invalidDepth],
          tracks: const [],
          now: now,
          audioEnabled: true,
          detectorKind: detector,
          detectorIdentity: 'detector-${detector.name}',
        );
        expect(decision.announce, isFalse);
      }
    });

    test('fallback requires bounded near and center geometry', () {
      final nearCenter = info(box: const Rect.fromLTWH(0.3, 0.2, 0.4, 0.5));
      expect(decide([nearCenter]).announce, isTrue);
      final mediumCenter = info(box: const Rect.fromLTWH(0.4, 0.2, 0.2, 0.3));
      expect(decide([mediumCenter]).announce, isFalse);
      final nearSide = info(box: const Rect.fromLTWH(0.05, 0.2, 0.2, 0.5));
      expect(decide([nearSide]).announce, isFalse);
    });

    test('custom decisions do not inherit another detector identity state', () {
      final person = metricInfo(1.8);
      final first = policy.decide(
        detections: [person],
        tracks: const [],
        now: now,
        audioEnabled: true,
        detectorKind: DetectorModelKind.custom,
        detectorIdentity: 'custom-a',
      );
      policy.commitStarted(first, now);
      now = now.add(const Duration(seconds: 1));
      final switched = policy.decide(
        detections: [person],
        tracks: const [],
        now: now,
        audioEnabled: true,
        detectorKind: DetectorModelKind.custom,
        detectorIdentity: 'custom-b',
      );
      expect(switched.announce, isTrue);
    });

    test(
      'shared metric threshold escalates at 1.7 to 1.4 and rearms after retreat',
      () {
        final detector = DetectorModelKind.builtIn;
        final first = policy.decide(
          detections: [metricInfo(1.7, label: 'chair', classId: 56)],
          tracks: const [],
          now: now,
          audioEnabled: true,
          detectorKind: detector,
          detectorIdentity: 'builtin-yolov8n-int8-metadata',
        );
        expect(first.announce, isTrue);
        expect(first.priority, AlertPriority.normal);
        policy.commitStarted(first, now);

        now = now.add(const Duration(seconds: 1));
        final urgent = policy.decide(
          detections: [metricInfo(1.4, label: 'chair', classId: 56)],
          tracks: const [],
          now: now,
          audioEnabled: true,
          detectorKind: detector,
          detectorIdentity: 'builtin-yolov8n-int8-metadata',
        );
        expect(urgent.announce, isTrue);
        expect(urgent.priority, AlertPriority.imminent);
        policy.commitStarted(urgent, now);

        policy.observeDetections(
          detections: [metricInfo(2.4, label: 'chair', classId: 56)],
          tracks: const [],
          detectorKind: detector,
          detectorIdentity: 'builtin-yolov8n-int8-metadata',
        );
        now = now.add(const Duration(seconds: 1));
        final rearmed = policy.decide(
          detections: [metricInfo(1.9, label: 'chair', classId: 56)],
          tracks: const [],
          now: now,
          audioEnabled: true,
          detectorKind: detector,
          detectorIdentity: 'builtin-yolov8n-int8-metadata',
        );
        expect(rearmed.announce, isTrue);
      },
    );

    test('near person is imminent and preemption-eligible', () {
      final near = info(box: const Rect.fromLTWH(0.3, 0.2, 0.4, 0.5));
      final decision = decide([near], tracks: [trackOf(near, id: 21)]);
      expect(decision.priority, AlertPriority.imminent);
      expect(decision.preemptEligible, isTrue);
    });

    test('far low-priority object is a normal announcement', () {
      final far = info(
        classId: 79,
        label: 'toothbrush',
        box: const Rect.fromLTWH(0.05, 0.5, 0.05, 0.05),
      );
      final decision = decide([far], tracks: [trackOf(far, id: 22)]);
      expect(decision.priority, AlertPriority.normal);
      expect(decision.preemptEligible, isFalse);
    });

    test('muted audio produces no announcement', () {
      final primary = info();
      final decision = decide([primary], audioEnabled: false);
      expect(decision.announce, isFalse);
      expect(decision.reason, AlertReason.muted);
    });

    test('empty detections produce no announcement', () {
      final decision = decide(const []);
      expect(decision.announce, isFalse);
      expect(decision.reason, AlertReason.suppressedNoCandidates);
    });

    test('force announces as a user-initiated request', () {
      final primary = info();
      final track = trackOf(primary, id: 23);
      policy.commitStarted(decide([primary], tracks: [track]), now);

      now = now.add(const Duration(seconds: 1));
      final decision = decide([primary], tracks: [track], force: true);
      expect(decision.announce, isTrue);
      expect(decision.reason, AlertReason.forced);
      expect(decision.priority, AlertPriority.userInitiated);
    });

    test('identity cache is bounded', () {
      final bounded = AlertPolicy(maxKeys: 2);
      for (var id = 1; id <= 3; id++) {
        final primary = info(
          box: Rect.fromLTWH(0.3 + id * 0.01, 0.2, 0.4, 0.5),
        );
        final decision = bounded.decide(
          detections: [primary],
          tracks: [trackOf(primary, id: id)],
          now: now,
          audioEnabled: true,
        );
        bounded.commitStarted(decision, now);
        now = now.add(const Duration(seconds: 1));
      }
      expect(bounded.hasStateFor('track:1'), isFalse);
      expect(bounded.hasStateFor('track:3'), isTrue);
    });
  });

  group('state expiry', () {
    test('expired track state becomes eligible again', () {
      final primary = info();
      final track = trackOf(primary, id: 41);
      policy.commitStarted(decide([primary], tracks: [track]), now);

      now = now.add(const Duration(seconds: 31));
      final decision = decide([primary], tracks: [track]);
      expect(decision.announce, isTrue);
      expect(decision.reason, AlertReason.newTrack);
    });

    test('expired label-fallback state becomes eligible again', () {
      final primary = info();
      policy.commitStarted(decide([primary]), now);

      now = now.add(const Duration(seconds: 31));
      final decision = decide([primary]);
      expect(decision.announce, isTrue);
      expect(decision.reason, AlertReason.newLabelFallback);
    });

    test('pruneExpired drops stale entries', () {
      final primary = info();
      final track = trackOf(primary, id: 42);
      policy.commitStarted(decide([primary], tracks: [track]), now);

      policy.pruneExpired(now.add(const Duration(seconds: 31)));
      expect(policy.hasStateFor('track:42'), isFalse);
    });
  });

  group('accepted motion', () {
    test('near-stable to near-approaching re-alerts once', () {
      final near = info(box: const Rect.fromLTWH(0.3, 0.2, 0.4, 0.5));
      policy.commitStarted(
        decide([near], tracks: [trackOf(near, id: 31)]),
        now,
      );

      now = now.add(const Duration(seconds: 1));
      final approaching = decide(
        [near],
        tracks: [trackOf(near, id: 31, motion: MotionState.approaching)],
      );
      expect(approaching.announce, isTrue);
      expect(approaching.reason, AlertReason.riskEscalation);
      expect(approaching.risk, RiskLevel.imminent);

      policy.commitStarted(approaching, now);
      now = now.add(const Duration(seconds: 1));
      final again = decide(
        [near],
        tracks: [trackOf(near, id: 31, motion: MotionState.approaching)],
      );
      expect(again.announce, isFalse);
    });

    test('approaching is not re-announced when already accepted', () {
      final near = info(box: const Rect.fromLTWH(0.3, 0.2, 0.4, 0.5));
      final track = trackOf(near, id: 32, motion: MotionState.approaching);
      policy.commitStarted(decide([near], tracks: [track]), now);

      now = now.add(const Duration(seconds: 1));
      expect(decide([near], tracks: [track]).announce, isFalse);
    });
  });

  group('decision versioning', () {
    test('a decision is superseded once its identity is committed', () {
      final primary = info();
      final track = trackOf(primary, id: 51);
      final first = decide([primary], tracks: [track]);
      expect(first.basedOnStartedAt, isNull);

      final second = decide([primary], tracks: [track]);
      expect(second.announce, isTrue);
      expect(policy.shouldSpeakPending(second, now), isTrue);

      policy.commitStarted(first, now);
      expect(policy.shouldSpeakPending(second, now), isFalse);
      expect(policy.shouldSpeakPending(first, now), isFalse);
    });

    test('pending higher-risk decision survives a lower-risk commit', () {
      // Off-centre and far, so the corridor rule does not raise the risk.
      final far = info(box: const Rect.fromLTWH(0.02, 0.5, 0.1, 0.12));
      final lower = decide([far], tracks: [trackOf(far, id: 81)]);
      expect(lower.risk, RiskLevel.medium);

      final near = info(box: const Rect.fromLTWH(0.3, 0.2, 0.4, 0.5));
      final higher = decide([near], tracks: [trackOf(near, id: 81)]);
      expect(higher.risk, RiskLevel.imminent);

      policy.commitStarted(lower, now);
      expect(policy.shouldSpeakPending(higher, now), isTrue);
    });

    test('pending equal or lower-risk decision is discarded', () {
      final mediumBand = info(box: const Rect.fromLTWH(0.4, 0.2, 0.2, 0.25));
      final track = trackOf(mediumBand, id: 82);
      final committed = decide([mediumBand], tracks: [track]);
      final equal = decide([mediumBand], tracks: [track]);

      final farInfo = info(box: const Rect.fromLTWH(0.02, 0.5, 0.1, 0.12));
      final lower = decide([farInfo], tracks: [trackOf(farInfo, id: 82)]);
      expect(lower.risk, RiskLevel.medium);

      policy.commitStarted(committed, now);
      expect(policy.shouldSpeakPending(equal, now), isFalse);
      expect(policy.shouldSpeakPending(lower, now), isFalse);
    });

    test('a decision created after TTL expiry stays eligible while parked', () {
      final primary = info();
      final track = trackOf(primary, id: 83);
      policy.commitStarted(decide([primary], tracks: [track]), now);

      now = now.add(const Duration(seconds: 31));
      final pending = decide([primary], tracks: [track]);
      expect(pending.announce, isTrue);
      expect(pending.reason, AlertReason.newTrack);
      expect(policy.shouldSpeakPending(pending, now), isTrue);
    });
  });
}
