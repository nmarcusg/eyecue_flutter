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

void _submit(MonocularDepthEstimator estimator, int marker) =>
    estimator.submitFrame(
      Uint8List.fromList([marker]),
      uprightWidth: 640,
      uprightHeight: 480,
      rotationDegrees: 90,
      timestampMs: 0,
    );

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

  // Cadence tests drive the estimator's own periodic timer through
  // `testWidgets`, whose fake clock is deterministic without adding a
  // (undeclared) fake_async dev dependency. Metric values are asserted in a
  // real-time test because they are measured with a real `Stopwatch`, whose
  // deltas collapse to zero under a fake clock.
  group('configure', () {
    testWidgets('re-arms exactly one timer at the new interval', (
      tester,
    ) async {
      final calls = <int>[];
      var next = 0;
      late final MonocularDepthEstimator estimator;
      estimator = MonocularDepthEstimator(
        minIntervalMs: 100,
        heatmapBuilder: (_) async => null,
        // Queues the next frame so each timer tick can drain one.
        onFrame: (_) => _submit(estimator, ++next),
        predictor: (jpeg, useGpu) async {
          calls.add(jpeg.first);
          return _depthResult();
        },
      );

      _submit(estimator, ++next);
      await tester.pump(const Duration(milliseconds: 100));
      expect(calls, [1]);
      expect(estimator.debugTimerActive, isTrue);

      estimator.configure(minIntervalMs: 300);
      expect(estimator.debugMinIntervalMs, 300);
      expect(estimator.debugTimerActive, isTrue);

      // The old 100 ms timer would have fired twice in here.
      await tester.pump(const Duration(milliseconds: 200));
      expect(calls, [1]);
      await tester.pump(const Duration(milliseconds: 100));
      expect(calls, [1, 2]);

      estimator.dispose();
    });

    testWidgets('a same-value configure leaves the timer phase alone', (
      tester,
    ) async {
      final calls = <int>[];
      final estimator = MonocularDepthEstimator(
        minIntervalMs: 100,
        heatmapBuilder: (_) async => null,
        predictor: (jpeg, useGpu) async {
          calls.add(jpeg.first);
          return _depthResult();
        },
      );

      _submit(estimator, 1);
      await tester.pump(const Duration(milliseconds: 50));
      expect(calls, isEmpty);

      estimator.configure(minIntervalMs: 100);
      expect(estimator.debugMinIntervalMs, 100);

      // A re-armed timer would not fire before t=150; the original fires at 100.
      await tester.pump(const Duration(milliseconds: 50));
      expect(calls, [1]);

      estimator.dispose();
    });

    testWidgets('out-of-range intervals are clamped', (tester) async {
      final estimator = MonocularDepthEstimator(minIntervalMs: 100);

      estimator.configure(minIntervalMs: 0);
      expect(
        estimator.debugMinIntervalMs,
        MonocularDepthEstimator.minIntervalFloorMs,
      );
      estimator.configure(minIntervalMs: 999999);
      expect(
        estimator.debugMinIntervalMs,
        MonocularDepthEstimator.minIntervalCeilingMs,
      );
      expect(estimator.debugTimerActive, isFalse);

      estimator.dispose();
    });

    testWidgets(
      'reconfiguring mid-flight keeps one request and one pending frame',
      (tester) async {
        final gate = Completer<void>();
        final calls = <int>[];
        final estimator = MonocularDepthEstimator(
          minIntervalMs: 100,
          heatmapBuilder: (_) async => null,
          predictor: (jpeg, useGpu) async {
            calls.add(jpeg.first);
            await gate.future;
            return _depthResult();
          },
        );

        _submit(estimator, 1);
        await tester.pump(const Duration(milliseconds: 100));
        expect(estimator.debugRunning, isTrue);
        expect(calls, [1]);

        _submit(estimator, 2);
        _submit(estimator, 3);
        expect(estimator.debugPendingFrames, 1);

        estimator.configure(minIntervalMs: 50);
        await tester.pump(const Duration(milliseconds: 300));
        expect(calls, [1]);
        expect(estimator.debugRunning, isTrue);
        expect(estimator.debugPendingFrames, 1);

        gate.complete();
        await tester.pump();
        expect(estimator.debugRunning, isFalse);
        await tester.pump(const Duration(milliseconds: 50));
        expect(calls, [1, 3]);
        expect(estimator.debugPendingFrames, 0);

        estimator.dispose();
      },
    );

    testWidgets('stop() ends all scheduled work', (tester) async {
      final calls = <int>[];
      var next = 0;
      late final MonocularDepthEstimator estimator;
      estimator = MonocularDepthEstimator(
        minIntervalMs: 100,
        heatmapBuilder: (_) async => null,
        onFrame: (_) => _submit(estimator, ++next),
        predictor: (jpeg, useGpu) async {
          calls.add(jpeg.first);
          return _depthResult();
        },
      );

      _submit(estimator, ++next);
      await tester.pump(const Duration(milliseconds: 100));
      expect(calls, [1]);

      _submit(estimator, ++next);
      estimator.stop();
      expect(estimator.debugTimerActive, isFalse);
      expect(estimator.debugPendingFrames, 0);

      await tester.pump(const Duration(seconds: 1));
      expect(calls, [1]);

      estimator.dispose();
    });
  });

  test('completion metrics are observed and survive stop()', () async {
    final estimator = MonocularDepthEstimator(
      minIntervalMs: 20,
      heatmapBuilder: (_) async => null,
      predictor: (jpeg, useGpu) async {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        return _depthResult();
      },
    );

    expect(estimator.lastLatencyMs, isNull);
    expect(estimator.observedHz, isNull);
    // No model instance is loaded by the predictor seam.
    expect(estimator.accelerator, isNull);

    _submit(estimator, 1);
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(estimator.lastLatencyMs, greaterThanOrEqualTo(5));
    // The first completion has no previous timestamp to measure a delta from.
    expect(estimator.observedHz, isNull);

    _submit(estimator, 2);
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(estimator.observedHz, isNotNull);
    expect(estimator.observedHz!, greaterThan(0));

    final observed = estimator.observedHz;
    final latency = estimator.lastLatencyMs;
    estimator.stop();
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(estimator.observedHz, observed);
    expect(estimator.lastLatencyMs, latency);

    estimator.dispose();
  });
}
