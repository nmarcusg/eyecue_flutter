import 'dart:ui';

import 'package:eyecue_flutter/models/detection.dart';
import 'package:eyecue_flutter/models/detection_info.dart';
import 'package:eyecue_flutter/models/detector_model.dart';
import 'package:eyecue_flutter/services/spatial_analysis_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Detection det({
    required int classId,
    String label = 'object',
    double conf = 0.9,
    required Rect box,
  }) {
    return Detection(
      classId: classId,
      label: label,
      confidence: conf,
      box: box,
    );
  }

  group('positionFor', () {
    test('classifies left / center / right from box center X', () {
      expect(
        SpatialAnalysisService.positionFor(Rect.fromLTWH(0.0, 0.0, 0.1, 0.2)),
        RelativePosition.left,
      );
      expect(
        SpatialAnalysisService.positionFor(Rect.fromLTWH(0.45, 0.1, 0.1, 0.2)),
        RelativePosition.center,
      );
      expect(
        SpatialAnalysisService.positionFor(Rect.fromLTWH(0.85, 0.1, 0.1, 0.2)),
        RelativePosition.right,
      );
    });
  });

  group('proximityFor', () {
    test('larger boxes are classified nearer (approximate heuristic)', () {
      expect(
        SpatialAnalysisService.proximityFor(Rect.fromLTWH(0.2, 0.3, 0.3, 0.6)),
        ProximityBand.near,
      );
      expect(
        SpatialAnalysisService.proximityFor(Rect.fromLTWH(0.2, 0.3, 0.3, 0.3)),
        ProximityBand.medium,
      );
      expect(
        SpatialAnalysisService.proximityFor(Rect.fromLTWH(0.2, 0.3, 0.3, 0.1)),
        ProximityBand.far,
      );
    });
  });

  group('priorityFor', () {
    test('people and vehicles are HIGH priority', () {
      expect(
        SpatialAnalysisService.priorityFor(0),
        ObjectPriority.high,
      ); // person
      expect(SpatialAnalysisService.priorityFor(2), ObjectPriority.high); // car
      expect(SpatialAnalysisService.priorityFor(5), ObjectPriority.high); // bus
    });

    test('furniture is MEDIUM priority', () {
      expect(
        SpatialAnalysisService.priorityFor(56),
        ObjectPriority.medium,
      ); // chair
      expect(
        SpatialAnalysisService.priorityFor(73),
        ObjectPriority.medium,
      ); // refrigerator
    });

    test('unlisted classes default to LOW priority', () {
      expect(
        SpatialAnalysisService.priorityFor(77),
        ObjectPriority.low,
      ); // teddy bear
      expect(
        SpatialAnalysisService.priorityFor(79),
        ObjectPriority.low,
      ); // toothbrush
    });
  });

  group('analyze', () {
    test('produces DetectionInfo with all fields', () {
      final d = det(
        classId: 0,
        label: 'person',
        box: Rect.fromLTWH(0.8, 0.2, 0.15, 0.5),
      );
      final info = SpatialAnalysisService.analyze(d);
      expect(info.label, 'person');
      expect(info.position, RelativePosition.right);
      expect(info.priority, ObjectPriority.high);
      expect(info.proximity, ProximityBand.near);
      expect(info.positionLabel, 'right');
      expect(info.proximityLabel, 'near');
    });

    test('priorityResolver replaces the COCO class-id policy per model', () {
      ObjectPriority custom(Detection d) =>
          priorityForClass(DetectorModelKind.custom, d.classId, d.label);
      final mug = det(
        classId: 0,
        label: 'mug',
        box: Rect.fromLTWH(0.1, 0.1, 0.2, 0.2),
      );
      final person = det(
        classId: 0,
        label: 'person',
        box: Rect.fromLTWH(0.1, 0.1, 0.2, 0.2),
      );

      // Without a resolver the COCO id still decides (unchanged callers).
      expect(SpatialAnalysisService.analyze(mug).priority, ObjectPriority.high);
      // A custom model's class 0 is judged by its label only.
      expect(
        SpatialAnalysisService.analyze(mug, priorityResolver: custom).priority,
        ObjectPriority.low,
      );
      expect(
        SpatialAnalysisService.analyze(
          person,
          priorityResolver: custom,
        ).priority,
        ObjectPriority.high,
      );
    });

    test('same resolver works through analyzeAll', () {
      final infos = SpatialAnalysisService.analyzeAll(
        [
          det(classId: 0, label: 'mug', box: Rect.fromLTWH(0.1, 0.1, 0.2, 0.2)),
          det(
            classId: 3,
            label: 'chair',
            box: Rect.fromLTWH(0.5, 0.5, 0.2, 0.2),
          ),
        ],
        priorityResolver: (d) =>
            priorityForClass(DetectorModelKind.custom, d.classId, d.label),
      );
      expect(infos[0].priority, ObjectPriority.low);
      expect(infos[1].priority, ObjectPriority.medium);
    });

    test('analyzeAll maps every detection', () {
      final dets = [
        det(
          classId: 0,
          label: 'person',
          box: Rect.fromLTWH(0.1, 0.1, 0.2, 0.2),
        ),
        det(
          classId: 56,
          label: 'chair',
          box: Rect.fromLTWH(0.5, 0.5, 0.2, 0.2),
        ),
      ];
      final infos = SpatialAnalysisService.analyzeAll(dets);
      expect(infos.length, 2);
      expect(infos[0].priority, ObjectPriority.high);
      expect(infos[1].priority, ObjectPriority.medium);
    });
  });
}
