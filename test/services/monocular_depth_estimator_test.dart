import 'dart:async';
import 'dart:typed_data';

import 'package:eyecue_flutter/services/monocular_depth_estimator.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ultralytics_yolo/ultralytics_yolo.dart';

Map<String, dynamic> _depthResult() => {
  'depthMap': {
    'values': <num>[1.0, 2.0, 3.0, 4.0],
    'width': 2,
    'height': 2,
    'minDepth': 1.0,
    'maxDepth': 4.0,
  },
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('latest frame wins and at most one frame is queued', () async {
    final gate = Completer<void>();
    final seen = <int>[];
    final estimator = MonocularDepthEstimator(
      minIntervalMs: 10,
      // Synchronous fake: the real heatmap decode (decodeImageFromPixels) can
      // take ~1 s under load and would make the cadence assertion racy.
      heatmapBuilder: (_) async => null,
      predictor: (jpeg, useGpu) async {
        seen.add(jpeg.first);
        await gate.future;
        return _depthResult();
      },
    );

    void submit(int marker) => estimator.submitFrame(
      Uint8List.fromList([marker]),
      uprightWidth: 640,
      uprightHeight: 480,
      rotationDegrees: 90,
      timestampMs: 0,
    );

    submit(1);
    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(estimator.debugRunning, isTrue);
    expect(seen, [1]);

    submit(2);
    submit(3);
    submit(4);
    expect(estimator.debugPendingFrames, lessThanOrEqualTo(1));

    gate.complete();
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(seen, [1, 4]);
    expect(estimator.debugPendingFrames, 0);
    expect(estimator.frame.value?.rotationDegrees, 90);
    expect(estimator.frame.value?.heatmap, isNull);
    expect(estimator.state.value, DepthRunState.ready);

    estimator.dispose();
  });

  test('a failing predictor degrades instead of throwing', () async {
    final estimator = MonocularDepthEstimator(
      minIntervalMs: 10,
      predictor: (jpeg, useGpu) async => throw StateError('offline'),
    );
    estimator.submitFrame(
      Uint8List.fromList([1]),
      uprightWidth: 640,
      uprightHeight: 480,
      rotationDegrees: 0,
      timestampMs: 0,
    );
    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(estimator.state.value, DepthRunState.degraded);
    expect(estimator.frame.value, isNull);
    estimator.dispose();
  });

  test('frame staleness and geometry matching are explicit', () {
    final frame = DepthFrame(
      map: YOLODepthMap(
        values: Float32List(4),
        width: 2,
        height: 2,
        minDepth: 0,
        maxDepth: 1,
      ),
      heatmap: null,
      timestampMs: 1000,
      rotationDegrees: 90,
      uprightWidth: 480,
      uprightHeight: 640,
    );
    expect(frame.isStaleAt(2000), isFalse);
    expect(frame.isStaleAt(2001), isTrue);
    expect(
      frame.matchesGeometry(
        rotationDegrees: 90,
        uprightWidth: 480,
        uprightHeight: 640,
      ),
      isTrue,
    );
    expect(
      frame.matchesGeometry(
        rotationDegrees: 0,
        uprightWidth: 480,
        uprightHeight: 640,
      ),
      isFalse,
    );
  });

  test('heatmap stride keeps the longest side at or below 320 px', () {
    expect(MonocularDepthEstimator.heatmapStrideFor(640, 480), 2);
    expect(MonocularDepthEstimator.heatmapStrideFor(320, 240), 1);
    expect(MonocularDepthEstimator.heatmapStrideFor(1280, 960), 4);
    expect(MonocularDepthEstimator.heatmapStrideFor(2560, 1920), 8);
  });

  test('heatmap buffer uses the downsampled grid', () {
    final map = YOLODepthMap(
      values: Float32List(640 * 480),
      width: 640,
      height: 480,
      minDepth: 0,
      maxDepth: 1,
    );
    final buffer = MonocularDepthEstimator.buildHeatmapPixels(map);
    const stride = 2;
    expect(buffer.width, (640 / stride).ceil());
    expect(buffer.height, (480 / stride).ceil());
    expect(buffer.pixels.length, buffer.width * buffer.height * 4);
  });
}
