import 'package:eyecue_flutter/models/detection.dart';
import 'package:eyecue_flutter/services/ultralytics_detection_adapter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ultralytics_yolo/ultralytics_yolo.dart';

/// A streaming payload with the same keys/shape the native Android side emits.
Map<String, dynamic> _streamPayload() => {
  'detections': [
    {
      'classIndex': 0,
      'className': 'person',
      'confidence': 0.91,
      'boundingBox': {
        'left': 10.0,
        'top': 20.0,
        'right': 110.0,
        'bottom': 220.0,
      },
      'normalizedBox': {'left': 0.1, 'top': 0.2, 'right': 0.6, 'bottom': 0.8},
    },
    {
      'classIndex': 2,
      'className': 'car',
      'confidence': 0.55,
      'boundingBox': {'left': 5.0, 'top': 8.0, 'right': 60.0, 'bottom': 90.0},
      'normalizedBox': {'left': 0.05, 'top': 0.08, 'right': 0.3, 'bottom': 0.5},
    },
  ],
  'imageWidth': 640,
  'imageHeight': 480,
  'frameNumber': 7,
  'timestamp': 1234567890,
  'processingTimeMs': 31.5,
  'preMs': 4.0,
  'inferenceMs': 21.5,
  'postMs': 6.0,
  'fps': 18.25,
};

void main() {
  test('streaming payload yields the same detections as the onResult path', () {
    final payload = _streamPayload();
    // Old path: YOLOView._parseDetectionResults produced YOLOResult objects and
    // the adapter converted them.
    final legacy = (payload['detections'] as List)
        .cast<Map<dynamic, dynamic>>()
        .map(YOLOResult.fromMap)
        .toList(growable: false);
    final legacyDetections = UltralyticsDetectionAdapter.convert(legacy, const [
      'person',
      'bicycle',
      'car',
    ]);

    // New path: the single streaming callback parses YOLODetectionResults.
    final streaming = YOLODetectionResults.fromMap(payload).detections;
    final streamingDetections = UltralyticsDetectionAdapter.convert(
      streaming,
      const ['person', 'bicycle', 'car'],
    );

    expect(streamingDetections.length, 2);
    for (var i = 0; i < legacyDetections.length; i++) {
      expect(streamingDetections[i], legacyDetections[i]);
    }
    // Labels still resolve through the bundled label list.
    expect(streamingDetections[1].label, 'car');
  });

  test('streaming payload carries the metrics the old callback received', () {
    final metrics = YOLOPerformanceMetrics.fromMap(_streamPayload());
    expect(metrics.inferenceMs, 21.5);
    expect(metrics.fps, 18.25);
    expect(metrics.processingTimeMs, 31.5);
  });

  test('a payload without detections converts to an empty list', () {
    final results = YOLODetectionResults.fromMap({'imageWidth': 640});
    expect(results.detections, isEmpty);
    expect(
      UltralyticsDetectionAdapter.convert(results.detections, const []),
      <Detection>[],
    );
  });
}
