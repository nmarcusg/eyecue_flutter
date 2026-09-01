import 'dart:ui';

import 'package:eyecue_flutter/services/ultralytics_detection_adapter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ultralytics_yolo/ultralytics_yolo.dart';

void main() {
  test('maps Ultralytics results to EyeCue detections and COCO labels', () {
    final result = YOLOResult(
      classIndex: 1,
      className: 'class 1',
      confidence: 0.8,
      boundingBox: const Rect.fromLTWH(10, 20, 30, 40),
      normalizedBox: const Rect.fromLTWH(0.1, 0.2, 0.3, 0.4),
    );

    final detections = UltralyticsDetectionAdapter.convert(
      [result],
      const ['person', 'bicycle'],
    );

    expect(detections, hasLength(1));
    expect(detections.single.classId, 1);
    expect(detections.single.label, 'bicycle');
    expect(detections.single.confidence, 0.8);
    expect(detections.single.box, const Rect.fromLTWH(0.1, 0.2, 0.3, 0.4));
  });

  test('clamps normalized boxes and falls back to plugin label', () {
    final result = YOLOResult(
      classIndex: 99,
      className: 'custom object',
      confidence: 0.5,
      boundingBox: Rect.zero,
      normalizedBox: const Rect.fromLTRB(-0.2, -0.1, 1.4, 1.2),
    );

    final detection = UltralyticsDetectionAdapter.convert([
      result,
    ], const []).single;
    expect(detection.label, 'custom object');
    expect(detection.box, const Rect.fromLTRB(0, 0, 1, 1));
  });
}
