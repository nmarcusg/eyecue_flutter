import 'dart:ui';

import 'package:eyecue_flutter/models/detection.dart';
import 'package:eyecue_flutter/models/detection_info.dart';
import 'package:eyecue_flutter/services/scene_summary_service.dart';
import 'package:eyecue_flutter/services/spatial_analysis_service.dart';
import 'package:flutter_test/flutter_test.dart';

DetectionInfo detection({
  required int classId,
  required String label,
  Rect box = const Rect.fromLTWH(0.4, 0.1, 0.2, 0.2),
  double confidence = 0.8,
}) {
  return SpatialAnalysisService.analyze(
    Detection(classId: classId, label: label, confidence: confidence, box: box),
  );
}

void main() {
  const service = SceneSummaryService();

  test('empty scenes use a safe deterministic message', () {
    expect(service.alert(const []), 'Alert. No objects detected.');
    expect(service.quickScan(const []), 'Quick scan. No objects detected.');
  });

  test('alerts prioritize high-priority objects and retain legacy wording', () {
    final text = service.alert([
      detection(classId: 79, label: 'toothbrush', confidence: 0.99),
      detection(
        classId: 0,
        label: 'person',
        box: const Rect.fromLTWH(0.7, 0.1, 0.2, 0.3),
      ),
    ]);

    expect(text, startsWith('Alert. person'));
    expect(text, contains('high priority obstacle'));
    expect(text, contains('2 objects detected'));
  });

  test('quick scans are spatially ordered and bounded', () {
    final detections = [
      detection(
        classId: 2,
        label: 'car',
        box: const Rect.fromLTWH(0.75, 0.1, 0.15, 0.2),
      ),
      detection(
        classId: 0,
        label: 'person',
        box: const Rect.fromLTWH(0.42, 0.1, 0.15, 0.2),
      ),
      detection(
        classId: 39,
        label: 'bottle',
        box: const Rect.fromLTWH(0.05, 0.1, 0.15, 0.2),
      ),
    ];

    final text = service.quickScan(detections);
    expect(text.indexOf('bottle'), lessThan(text.indexOf('person')));
    expect(text.indexOf('person'), lessThan(text.indexOf('car')));
    expect(text, contains('approximately'));
    expect(text.length, lessThanOrEqualTo(240));
  });

  test('alert ordering is independent of input order', () {
    final person = detection(classId: 0, label: 'person');
    final car = detection(classId: 2, label: 'car');
    expect(service.alert([person, car]), service.alert([car, person]));
  });
}
