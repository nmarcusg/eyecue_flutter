import 'dart:ui';

import 'package:eyecue_flutter/models/app_settings.dart';
import 'package:eyecue_flutter/models/detection.dart';
import 'package:eyecue_flutter/models/detection_correction.dart';
import 'package:eyecue_flutter/services/correction_service.dart';
import 'package:eyecue_flutter/services/spatial_analysis_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final info = SpatialAnalysisService.analyze(
    const Detection(
      classId: 0,
      label: 'person',
      confidence: 0.8,
      box: Rect.fromLTWH(0.1, 0.1, 0.2, 0.3),
    ),
  );

  test('correction records round-trip with engine and threshold', () {
    final record = DetectionCorrection(
      recordId: 'correction-1',
      timestamp: DateTime.utc(2026, 1, 1),
      sessionId: 'session-1',
      engine: InferenceEngine.ultralytics,
      detection: info.detection,
      feedback: CorrectionFeedback.incorrect,
      correctedLabel: 'bicycle',
      confidenceThreshold: 0.4,
    );

    expect(DetectionCorrection.fromJson(record.toJson()), record);
  });

  test('service rejects corrected labels outside the shared label list', () {
    final service = CorrectionService(
      labels: const ['person', 'bicycle'],
      sessionId: 'session-1',
      clock: () => DateTime.utc(2026, 1, 1),
    );

    expect(
      () => service.add(
        info: info,
        feedback: CorrectionFeedback.incorrect,
        engine: InferenceEngine.ultralytics,
        correctedLabel: 'not-a-label',
        confidenceThreshold: 0.25,
      ),
      throwsArgumentError,
    );
  });

  test('correct and unsure annotations preserve the source detection', () {
    final service = CorrectionService(
      labels: const ['person', 'bicycle'],
      sessionId: 'session-1',
    );
    final correct = service.add(
      info: info,
      feedback: CorrectionFeedback.correct,
      engine: InferenceEngine.ultralytics,
      confidenceThreshold: 0.25,
    );
    final unsure = service.add(
      info: info,
      feedback: CorrectionFeedback.unsure,
      engine: InferenceEngine.ultralytics,
      confidenceThreshold: 0.25,
    );

    expect(correct.feedback, CorrectionFeedback.correct);
    expect(unsure.feedback, CorrectionFeedback.unsure);
    expect(correct.detection, info.detection);
    expect(service.records, hasLength(2));
  });
}
