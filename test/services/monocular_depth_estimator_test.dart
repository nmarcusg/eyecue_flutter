import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

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
  int latencyMs = 12,
  int timestamp = 1000,
  String? error,
}) => YOLODepthEvent(
  depthGrid: grid ?? Float32List.fromList([1.0, 2.0, 3.0, 4.0]),
  width: width,
  height: height,
  minDepth: minDepth,
  maxDepth: maxDepth,
  imageWidth: imageWidth,
  imageHeight: imageHeight,
  latencyMs: latencyMs,
  preMs: 1,
  inferenceMs: 8,
  postMs: 3,
  accelerator: 'gpu',
  timestampMs: timestamp,
  error: error,
);

MonocularDepthEstimator _estimator({
  void Function(DepthFrame frame)? onFrame,
}) => MonocularDepthEstimator(
  onFrame: onFrame,
  // Synchronous fake: the real heatmap decode can take ~1 s under load and
  // would make the derivation assertions racy.
  heatmapBuilder: (_) async => null,
);

/// A real (tiny) image, so disposal is observable through `debugDisposed`.
Future<ui.Image> _testImage() {
  final completer = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    Uint8List.fromList(const [255, 0, 0, 255]),
    1,
    1,
    ui.PixelFormat.rgba8888,
    completer.complete,
  );
  return completer.future;
}

/// Counts the releases of an injected model instance.
class _FakeDepthModel implements DepthModelHandle {
  _FakeDepthModel(this.instanceId);

  @override
  final String instanceId;

  int releases = 0;

  @override
  Future<void> dispose() async {
    releases++;
  }
}

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

  test('a native failure marker degrades and builds no frame', () async {
    final estimator = _estimator();

    // The view emits `error` instead of a grid once, then stops ticking.
    _feed(estimator, _event(error: 'inference_failed'));
    await pumpEventQueue();

    expect(estimator.state.value, DepthRunState.degraded);
    expect(estimator.frame.value, isNull);

    // retry() leaves degraded, which is what re-pushes the instance id native-side.
    estimator.retry();
    expect(estimator.state.value, DepthRunState.idle);
    _feed(estimator, _event());
    await pumpEventQueue();
    expect(estimator.frame.value, isNotNull);

    estimator.dispose();
  });

  test('an event arriving during a publish is dropped, not raced', () async {
    final firstPublish = Completer<void>();
    final estimator = MonocularDepthEstimator(
      heatmapBuilder: (_) async {
        await firstPublish.future;
        return null;
      },
    );

    _feed(estimator, _event(timestamp: 1000));
    // Overlaps the first publish: skipped (latest-frame-wins), never queued.
    _feed(estimator, _event(timestamp: 2000));
    firstPublish.complete();
    await pumpEventQueue();

    expect(
      estimator.frame.value?.timestampMs,
      1000,
      reason: 'an older frame must not land after a newer one',
    );

    _feed(estimator, _event(timestamp: 3000));
    await pumpEventQueue();
    expect(estimator.frame.value?.timestampMs, 3000);

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

  group('heatmap gating', () {
    Future<ui.Image> testImage() => _testImage();

    test(
      'a hidden heatmap is never built and the grid still publishes',
      () async {
        var builds = 0;
        final estimator = MonocularDepthEstimator(
          heatmapBuilder: (_) async {
            builds++;
            return testImage();
          },
        )..heatmapEnabled = false;

        _feed(estimator, _event());
        await pumpEventQueue();

        expect(builds, 0, reason: 'a hidden overlay must cost no heatmap');
        final frame = estimator.frame.value!;
        expect(frame.heatmap, isNull);
        expect(frame.grid.values, Float32List.fromList([1.0, 2.0, 3.0, 4.0]));
        expect(estimator.state.value, DepthRunState.ready);

        estimator.dispose();
      },
    );

    test('re-enabling makes the next frame carry a heatmap again', () async {
      var builds = 0;
      final estimator = MonocularDepthEstimator(
        heatmapBuilder: (_) async {
          builds++;
          return testImage();
        },
      )..heatmapEnabled = false;

      _feed(estimator, _event(timestamp: 1000));
      await pumpEventQueue();
      expect(builds, 0);

      estimator.heatmapEnabled = true;
      _feed(estimator, _event(timestamp: 2000));
      await pumpEventQueue();

      expect(builds, 1);
      expect(estimator.frame.value!.timestampMs, 2000);
      expect(estimator.frame.value!.heatmap, isNotNull);

      estimator.dispose();
    });

    test('disabling drops the held image and keeps the grid', () async {
      late ui.Image built;
      final estimator = MonocularDepthEstimator(
        heatmapBuilder: (_) async => built = await testImage(),
      );

      _feed(estimator, _event());
      await pumpEventQueue();
      final grid = estimator.frame.value!.grid;
      expect(estimator.frame.value!.heatmap, isNotNull);
      expect(built.debugDisposed, isFalse);

      estimator.heatmapEnabled = false;
      await pumpEventQueue();

      expect(
        built.debugDisposed,
        isTrue,
        reason: 'the GPU texture is released',
      );
      expect(estimator.frame.value!.heatmap, isNull);
      expect(identical(estimator.frame.value!.grid, grid), isTrue);

      estimator.dispose();
    });

    test('a publish disowned by disabling disposes its image', () async {
      final inFlight = Completer<void>();
      late ui.Image built;
      final estimator = MonocularDepthEstimator(
        heatmapBuilder: (_) async {
          await inFlight.future;
          return built = await testImage();
        },
      );

      _feed(estimator, _event(timestamp: 1000));
      // The overlay disappears while the real builder is still producing the
      // image, so the publish owns a texture nobody asked for any more.
      estimator.heatmapEnabled = false;
      inFlight.complete();
      await pumpEventQueue();

      expect(
        built.debugDisposed,
        isTrue,
        reason: 'a disowned image must not leak its GPU texture',
      );
      expect(estimator.frame.value!.heatmap, isNull);
      expect(estimator.frame.value!.timestampMs, 1000);

      estimator.dispose();
    });

    test('a frame in flight cannot resurrect a degraded state', () async {
      final inFlight = Completer<void>();
      final estimator = MonocularDepthEstimator(
        heatmapBuilder: (_) async {
          await inFlight.future;
          return null;
        },
      );

      _feed(estimator, _event(timestamp: 1000));
      // The native failure lands while the publish is still building.
      _feed(estimator, _event(error: 'inference_failed'));
      expect(estimator.state.value, DepthRunState.degraded);

      inFlight.complete();
      await pumpEventQueue();

      expect(
        estimator.state.value,
        DepthRunState.degraded,
        reason: 'a publish must not re-arm the instance id and clear the latch',
      );

      estimator.retry();
      expect(estimator.state.value, DepthRunState.idle);
      _feed(estimator, _event(timestamp: 3000));
      await pumpEventQueue();
      expect(estimator.state.value, DepthRunState.ready);

      estimator.dispose();
    });
  });

  group('model lifecycle', () {
    test(
      'releaseModel frees the model, clears frame/heatmap and keeps telemetry',
      () async {
        final models = <_FakeDepthModel>[];
        late ui.Image built;
        final estimator = MonocularDepthEstimator(
          modelFactory:
              ({required String modelId, required bool useGpu}) async {
                final model = _FakeDepthModel('depth-${models.length + 1}');
                models.add(model);
                return model;
              },
          heatmapBuilder: (_) async => built = await _testImage(),
        );

        await estimator.prepare();
        expect(estimator.state.value, DepthRunState.ready);
        expect(estimator.instanceId, 'depth-1');

        _feed(estimator, _event(latencyMs: 11));
        await Future<void>.delayed(const Duration(milliseconds: 20));
        _feed(estimator, _event(latencyMs: 14, timestamp: 2000));
        await Future<void>.delayed(const Duration(milliseconds: 20));
        final observed = estimator.observedHz;
        final latency = estimator.lastLatencyMs;
        expect(observed, isNotNull);
        expect(estimator.frame.value!.heatmap, isNotNull);
        expect(built.debugDisposed, isFalse);

        await estimator.releaseModel();

        expect(models.single.releases, 1, reason: 'the interpreter is freed');
        expect(estimator.instanceId, isNull, reason: 'nothing left to tick');
        expect(estimator.state.value, DepthRunState.idle);
        expect(estimator.frame.value, isNull);
        expect(built.debugDisposed, isTrue, reason: 'the texture is freed');
        expect(estimator.observedHz, observed, reason: 'telemetry survives');
        expect(estimator.lastLatencyMs, latency, reason: 'telemetry survives');
        // The notifiers outlive a release, unlike `dispose()`: the state can
        // still be written and still reaches a registered listener.
        var notifications = 0;
        void listener() => notifications++;
        estimator.state.addListener(listener);
        estimator.state.value = DepthRunState.loading;
        expect(notifications, 1, reason: 'the notifier was not disposed');
        estimator.state.removeListener(listener);
        estimator.state.value = DepthRunState.idle;

        await estimator.releaseModel();
        expect(models.single.releases, 1, reason: 'idempotent');
        expect(estimator.state.value, DepthRunState.idle);

        estimator.dispose();
      },
    );

    test('re-arming after a release loads the model exactly once', () async {
      var loads = 0;
      final estimator = MonocularDepthEstimator(
        modelFactory: ({required String modelId, required bool useGpu}) async {
          loads++;
          return _FakeDepthModel('depth-$loads');
        },
        heatmapBuilder: (_) async => null,
      );

      await estimator.prepare();
      expect(loads, 1);
      expect(estimator.instanceId, 'depth-1');

      await estimator.releaseModel();
      expect(estimator.instanceId, isNull);
      expect(estimator.state.value, DepthRunState.idle);

      // Re-enable: `retry()` then the screen's arm, twice over. `prepare()`
      // shares one in-flight load, so the second arm adds nothing.
      estimator.retry();
      expect(estimator.state.value, DepthRunState.idle);
      await Future.wait([estimator.prepare(), estimator.prepare()]);

      expect(loads, 2, reason: 'exactly one reload, not one per arm');
      expect(estimator.state.value, DepthRunState.ready);
      expect(estimator.instanceId, 'depth-2');

      _feed(estimator, _event());
      await pumpEventQueue();
      expect(estimator.state.value, DepthRunState.ready);
      expect(estimator.frame.value, isNotNull);

      estimator.dispose();
    });

    test('a model-load failure recovers through retry + re-arm', () async {
      var loads = 0;
      var failNext = true;
      final estimator = MonocularDepthEstimator(
        modelFactory: ({required String modelId, required bool useGpu}) async {
          loads++;
          if (failNext) throw StateError('depth model did not load');
          return _FakeDepthModel('depth-$loads');
        },
        heatmapBuilder: (_) async => null,
      );

      await estimator.prepare();
      expect(estimator.state.value, DepthRunState.degraded);
      expect(estimator.instanceId, isNull, reason: 'no instance to tick');
      expect(loads, 1);

      // _retryDepth sees a null instance id and therefore re-arms.
      failNext = false;
      estimator.retry();
      expect(estimator.state.value, DepthRunState.idle);
      await estimator.prepare();

      expect(loads, 2);
      expect(estimator.state.value, DepthRunState.ready);
      expect(estimator.instanceId, 'depth-2');

      _feed(estimator, _event());
      await pumpEventQueue();
      expect(estimator.frame.value, isNotNull, reason: 'ticks are running');

      estimator.dispose();
    });

    test('a native failure retries on its instance without a reload', () async {
      var loads = 0;
      final estimator = MonocularDepthEstimator(
        modelFactory: ({required String modelId, required bool useGpu}) async {
          loads++;
          return _FakeDepthModel('depth-$loads');
        },
        heatmapBuilder: (_) async => null,
      );

      await estimator.prepare();
      final id = estimator.instanceId;
      expect(loads, 1);

      _feed(estimator, _event(error: 'inference_failed'));
      await pumpEventQueue();
      expect(estimator.state.value, DepthRunState.degraded);

      // The instance still exists, so _retryDepth skips the arm: the state
      // change alone re-pushes the id and clears the native latch.
      estimator.retry();
      expect(estimator.state.value, DepthRunState.ready);
      expect(estimator.instanceId, id);
      expect(loads, 1, reason: 'a native failure keeps its instance');

      _feed(estimator, _event(timestamp: 5000));
      await pumpEventQueue();
      expect(estimator.frame.value!.timestampMs, 5000);

      estimator.dispose();
    });

    test(
      'a load that finishes after a release is disposed, not adopted',
      () async {
        final gate = Completer<void>();
        var loads = 0;
        final estimator = MonocularDepthEstimator(
          modelFactory:
              ({required String modelId, required bool useGpu}) async {
                loads++;
                await gate.future;
                return _FakeDepthModel('depth-$loads');
              },
          heatmapBuilder: (_) async => null,
        );

        final arming = estimator.prepare();
        await estimator.releaseModel();
        gate.complete();
        await arming;

        expect(loads, 1);
        expect(estimator.instanceId, isNull, reason: 'released stays released');
        expect(estimator.state.value, DepthRunState.idle);

        estimator.dispose();
      },
    );
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
