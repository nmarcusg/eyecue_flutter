import 'dart:typed_data';

import 'package:eyecue_flutter/services/monocular_depth_estimator.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ultralytics_yolo/ultralytics_yolo.dart';

/// A native depth event with the payload shape the Android view emits.
YOLODepthEvent _event({
  Float32List? grid,
  int width = 2,
  int height = 2,
  double minDepth = 1.0,
  double maxDepth = 4.0,
  int imageWidth = 640,
  int imageHeight = 480,
  int rotationDegrees = 90,
  int latencyMs = 12,
  int timestamp = 1000,
}) => YOLODepthEvent(
  depthGrid: grid ?? Float32List.fromList([1.0, 2.0, 3.0, 4.0]),
  width: width,
  height: height,
  minDepth: minDepth,
  maxDepth: maxDepth,
  imageWidth: imageWidth,
  imageHeight: imageHeight,
  rotationDegrees: rotationDegrees,
  latencyMs: latencyMs,
  preMs: 1,
  inferenceMs: 8,
  postMs: 3,
  accelerator: 'gpu',
  timestampMs: timestamp,
);

MonocularDepthEstimator _estimator({
  void Function(DepthFrame frame)? onFrame,
}) => MonocularDepthEstimator(
  onFrame: onFrame,
  // Synchronous fake: the real heatmap decode can take ~1 s under load and
  // would make the derivation assertions racy.
  heatmapBuilder: (_) async => null,
);

void _feed(
  MonocularDepthEstimator estimator,
  YOLODepthEvent event, {
  int rotationDegrees = 90,
  int uprightWidth = 640,
  int uprightHeight = 480,
}) => estimator.onNativeDepth(
  event,
  rotationDegrees: rotationDegrees,
  uprightWidth: uprightWidth,
  uprightHeight: uprightHeight,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'an event publishes a frame carrying the grid and the live geometry',
    () async {
      final published = <DepthFrame>[];
      final estimator = _estimator(onFrame: published.add);

      _feed(estimator, _event(timestamp: 1234));
      await pumpEventQueue();

      final frame = estimator.frame.value;
      expect(frame, isNotNull);
      expect(frame!.grid.width, 2);
      expect(frame.grid.height, 2);
      expect(frame.grid.values, Float32List.fromList([1.0, 2.0, 3.0, 4.0]));
      expect(frame.timestampMs, 1234);
      expect(frame.rotationDegrees, 90);
      expect(frame.uprightWidth, 640);
      expect(frame.uprightHeight, 480);
      expect(
        frame.matchesGeometry(
          rotationDegrees: 90,
          uprightWidth: 640,
          uprightHeight: 480,
        ),
        isTrue,
      );
      expect(
        frame.matchesGeometry(
          rotationDegrees: 0,
          uprightWidth: 640,
          uprightHeight: 480,
        ),
        isFalse,
      );
      expect(
        frame.matchesGeometry(
          rotationDegrees: 90,
          uprightWidth: 480,
          uprightHeight: 640,
        ),
        isFalse,
      );
      expect(estimator.state.value, DepthRunState.ready);
      expect(published, hasLength(1));

      estimator.dispose();
    },
  );

  test('min/max depth propagate to the frame unchanged', () async {
    final estimator = _estimator();

    _feed(estimator, _event(minDepth: 0.4, maxDepth: 63.5));
    await pumpEventQueue();

    expect(estimator.frame.value?.grid.minDepth, 0.4);
    expect(estimator.frame.value?.grid.maxDepth, 63.5);

    estimator.dispose();
  });

  test('NaN blocks stay NaN so they are never sampled as metres', () async {
    final estimator = _estimator();
    final grid = Float32List.fromList([1.0, double.nan, 3.0, double.nan]);

    _feed(estimator, _event(grid: grid));
    await pumpEventQueue();

    final values = estimator.frame.value!.grid.values;
    expect(values[0], 1.0);
    expect(values[1].isNaN, isTrue);
    expect(values[2], 3.0);
    expect(values[3].isNaN, isTrue);

    estimator.dispose();
  });

  test('a frame goes stale one tick after depthStaleAfterMs', () async {
    final estimator = _estimator();

    _feed(estimator, _event(timestamp: 1000));
    await pumpEventQueue();

    final frame = estimator.frame.value!;
    expect(frame.isStaleAt(2000), isFalse);
    expect(frame.isStaleAt(2001), isTrue);

    estimator.dispose();
  });

  test('a degraded estimator ignores further events until retry', () async {
    final estimator = _estimator();

    // An empty grid means the native side produced nothing usable.
    _feed(estimator, _event(grid: Float32List(0), width: 0, height: 0));
    await pumpEventQueue();

    expect(estimator.state.value, DepthRunState.degraded);
    expect(estimator.frame.value, isNull);

    _feed(estimator, _event());
    await pumpEventQueue();
    expect(estimator.frame.value, isNull, reason: 'silent while degraded');

    estimator.retry();
    expect(estimator.state.value, DepthRunState.idle);
    _feed(estimator, _event());
    await pumpEventQueue();
    expect(estimator.frame.value, isNotNull);

    estimator.dispose();
  });

  test('observed Hz is an EMA over the native event cadence', () async {
    final estimator = _estimator();

    expect(estimator.observedHz, isNull);
    expect(estimator.lastLatencyMs, isNull);

    _feed(estimator, _event(latencyMs: 11));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    // The first event has no previous timestamp to measure a delta from.
    expect(estimator.observedHz, isNull);
    expect(estimator.lastLatencyMs, 11);

    _feed(estimator, _event(latencyMs: 14));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(estimator.observedHz, isNotNull);
    expect(estimator.observedHz!, greaterThan(0));
    expect(estimator.lastLatencyMs, 14);

    final observed = estimator.observedHz;
    final latency = estimator.lastLatencyMs;
    estimator.stop();
    expect(estimator.observedHz, observed);
    expect(estimator.lastLatencyMs, latency);

    estimator.dispose();
  });

  test('clearFrame drops the heatmap and the frame', () async {
    final estimator = _estimator();

    _feed(estimator, _event());
    await pumpEventQueue();
    expect(estimator.frame.value, isNotNull);

    estimator.clearFrame();
    expect(estimator.frame.value, isNull);

    estimator.dispose();
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
