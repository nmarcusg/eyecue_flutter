import 'dart:math' as math;
import 'dart:typed_data';

import 'package:eyecue_flutter/models/detection.dart';
import 'package:eyecue_flutter/models/model_config.dart';
import 'package:eyecue_flutter/services/ultralytics_detection_adapter.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ultralytics_yolo/ultralytics_yolo.dart';

/// A native depth event with the exact keys the Android view emits.
///
/// `imageWidth`/`imageHeight` are the analysed analysis-bitmap dims in sensor
/// orientation, i.e. the grid's source.
Map<String, dynamic> _depthEvent({
  int width = 96,
  int height = 54,
  int imageWidth = 640,
  int imageHeight = 360,
}) => {
  'type': 'depth',
  'depthGrid': Float32List.fromList(List<double>.filled(width * height, 2.5)),
  'width': width,
  'height': height,
  'minDepth': 0.5,
  'maxDepth': 12.0,
  'imageWidth': imageWidth,
  'imageHeight': imageHeight,
  'latencyMs': 41,
  'preMs': 6,
  'inferenceMs': 30,
  'postMs': 5,
  'accelerator': 'gpu',
  'droppedTicks': 7,
  'timestamp': 1234567890,
};

const _depthEventKeys = {
  'depthGrid',
  'width',
  'height',
  'minDepth',
  'maxDepth',
  'imageWidth',
  'imageHeight',
  'latencyMs',
  'preMs',
  'inferenceMs',
  'postMs',
  'accelerator',
  'droppedTicks',
  'timestamp',
};

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

  group('native depth event contract', () {
    test('parses exactly the native key set', () {
      final event = YOLODepthEvent.fromMap(_depthEvent());

      expect(event.toMap().keys.toSet(), _depthEventKeys);
      // `type` is the channel routing discriminator, not part of the payload.
      expect(event.toMap().containsKey('type'), isFalse);
      // The detector frame's rotation is not part of the depth payload any more:
      // the grid is described by the analysed bitmap's own dims.
      expect(event.toMap().containsKey('rotationDegrees'), isFalse);
      expect(event.width, 96);
      expect(event.height, 54);
      expect(event.minDepth, 0.5);
      expect(event.maxDepth, 12.0);
      expect(event.imageWidth, 640);
      expect(event.imageHeight, 360);
      expect(event.latencyMs, 41);
      expect(event.preMs, 6);
      expect(event.inferenceMs, 30);
      expect(event.postMs, 5);
      expect(event.accelerator, 'gpu');
      expect(event.droppedTicks, 7);
      expect(event.timestampMs, 1234567890);
      expect(event.error, isNull);
    });

    test('absent stage fields parse as null, never 0', () {
      final payload = _depthEvent()
        ..remove('preMs')
        ..remove('inferenceMs')
        ..remove('postMs')
        ..remove('accelerator')
        ..remove('droppedTicks');

      final event = YOLODepthEvent.fromMap(payload);

      expect(event.preMs, isNull);
      expect(event.inferenceMs, isNull);
      expect(event.postMs, isNull);
      expect(event.accelerator, isNull);
      expect(event.droppedTicks, isNull);
      // The key set is unchanged: an unreported stage is present as null.
      expect(event.toMap().keys.toSet(), _depthEventKeys);
      expect(event.toMap()['inferenceMs'], isNull);
    });

    /// Payload-shape check: the grid is the crop scaled so its LONGEST side is
    /// `depthMaxDim` and its short side keeps the crop's aspect ratio. This is
    /// the regression guard for the always-96x96 bug (per-axis scaling).
    void expectAspectCorrectGrid({
      required int imageWidth,
      required int imageHeight,
      required int width,
      required int height,
    }) {
      const maxDim = EyeCueModelConfig.depthGridMaxDim;
      final event = YOLODepthEvent.fromMap(
        _depthEvent(
          width: width,
          height: height,
          imageWidth: imageWidth,
          imageHeight: imageHeight,
        ),
      );

      expect(event.depthGrid.length, width * height);
      expect(
        math.max(event.width, event.height),
        maxDim,
        reason: 'the longest side is capped at depthMaxDim',
      );
      expect(
        math.min(event.width, event.height),
        lessThan(maxDim),
        reason: 'a non-square crop must not become a square grid',
      );
      expect(
        event.width / event.height,
        closeTo(imageWidth / imageHeight, 0.1),
        reason: 'the grid keeps the crop aspect ratio within rounding',
      );

      // Whole-event bound: the grid cap plus the handful of scalar keys. A dense
      // 640x480 float map would be 1 228 800 bytes, so this is the payload win.
      final encoded = const StandardMessageCodec().encodeMessage({
        'type': 'depth',
        ...event.toMap(),
      });
      expect(
        encoded!.lengthInBytes,
        lessThanOrEqualTo(maxDim * maxDim * 4 + 2048),
        reason: 'serialized depth event stays bounded',
      );
    }

    // Primary case: the production analysis stream is 4:3 — nothing sets
    // `analysisResolution`, CameraX yields 640x480 and `ImageUtils.toBitmap` never
    // rotates — so 640x480 -> 96x72 is the grid the app really emits. A 16:9 or
    // 9:16 crop is the one family where per-axis scaling and single-scale scaling
    // agree, so only a 4:3 case can catch the regression.
    test('a 640x480 analysis frame yields a 96x72 grid', () {
      expectAspectCorrectGrid(
        imageWidth: 640,
        imageHeight: 480,
        width: 96,
        height: 72,
      );
    });

    // Secondary (hypothetical crop): a 16:9 analysis buffer, kept because it is the
    // shape any future `analysisResolution` change could reintroduce.
    test('a 640x360 analysis frame yields a 96x54 grid', () {
      expectAspectCorrectGrid(
        imageWidth: 640,
        imageHeight: 360,
        width: 96,
        height: 54,
      );
    });

    test('a failure marker degrades without a grid', () {
      final event = YOLODepthEvent.fromMap({
        'type': 'depth',
        'error': 'inference_failed',
        'timestamp': 1234567890,
      });

      expect(event.error, 'inference_failed');
      expect(event.depthGrid, isEmpty);
      // The failure payload carries no grid and no frame fields; the parsed event
      // only adds the `error` marker to the frame key set.
      expect(event.toMap().keys.toSet(), {..._depthEventKeys, 'error'});
      expect(event.toMap()['depthGrid'], isEmpty);
    });

    test('a dense values map or an originalImage is never accepted', () {
      final payload = _depthEvent()
        ..['values'] = Float32List(640 * 480)
        ..['originalImage'] = Uint8List(1024);

      final event = YOLODepthEvent.fromMap(payload);

      expect(event.toMap().containsKey('values'), isFalse);
      expect(event.toMap().containsKey('originalImage'), isFalse);
      expect(event.toMap().keys.toSet(), _depthEventKeys);
    });
  });
}
