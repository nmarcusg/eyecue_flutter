import 'dart:ui';

import 'package:eyecue_flutter/models/detection.dart';
import 'package:eyecue_flutter/models/detection_info.dart';
import 'package:eyecue_flutter/services/scene_summary_service.dart';
import 'package:eyecue_flutter/services/spatial_analysis_service.dart';
import 'package:flutter_test/flutter_test.dart';

Detection _person({double height = 0.2}) => Detection(
  classId: 0,
  label: 'person',
  confidence: 0.8,
  box: Rect.fromLTWH(0.4, 0.5, 0.2, height),
);

void main() {
  group('metric distance through spatial analysis', () {
    test('meters select the band and the metric label', () {
      final near = SpatialAnalysisService.analyze(_person(), meters: 1.0);
      expect(near.proximity, ProximityBand.near);
      expect(near.distanceSource, DistanceSource.monocularDepth);
      expect(near.estimatedMeters, 1.0);
      expect(near.distanceLabel, 'about 1.0 m');
      // proximityLabel keeps its existing vocabulary.
      expect(near.proximityLabel, 'near');

      final far = SpatialAnalysisService.analyze(_person(), meters: 12.4);
      expect(far.proximity, ProximityBand.far);
      expect(far.distanceLabel, 'about 12 m');
    });

    test('the bbox path is unchanged when meters are absent', () {
      final info = SpatialAnalysisService.analyze(_person(height: 0.5));
      expect(info.proximity, ProximityBand.near);
      expect(info.distanceSource, DistanceSource.boundingBox);
      expect(info.estimatedMeters, isNull);
      expect(info.distanceLabel, isNull);
      expect(info.proximityLabel, 'near');
    });

    test('null entries in the meters list fall back per object', () {
      final infos = SpatialAnalysisService.analyzeAll(
        [_person(), _person(height: 0.1)],
        meters: [2.0, null],
      );
      expect(infos[0].distanceSource, DistanceSource.monocularDepth);
      expect(infos[1].distanceSource, DistanceSource.boundingBox);
      expect(infos[1].proximity, ProximityBand.far);
    });
  });

  group('speech uses the metric phrase when available', () {
    const summary = SceneSummaryService();

    test('alert speaks about N m', () {
      final info = SpatialAnalysisService.analyze(_person(), meters: 3.5);
      expect(summary.alert([info]), contains('about 3.5 m'));
    });

    test('alert keeps the band wording without meters', () {
      final info = SpatialAnalysisService.analyze(_person());
      expect(summary.alert([info]), contains('approximately ahead'));
    });

    test('quick scan speaks about N m', () {
      final info = SpatialAnalysisService.analyze(_person(), meters: 2.0);
      expect(summary.quickScan([info]), contains('about 2.0 m'));
    });
  });
}
