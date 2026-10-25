import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:ultralytics_yolo/ultralytics_yolo.dart';

import '../models/model_config.dart';
import 'depth_distance_service.dart';

/// Lifecycle of the depth model, surfaced to the detection screen so a degraded
/// run can show a non-blocking notice and fall back to the bbox estimator.
enum DepthRunState { idle, loading, ready, degraded }

/// One completed depth inference.
class DepthFrame {
  const DepthFrame({
    required this.grid,
    required this.heatmap,
    required this.timestampMs,
    required this.rotationDegrees,
    required this.uprightWidth,
    required this.uprightHeight,
  });

  /// Block-mean depth grid in metres (`NaN` where a block had no valid sample).
  ///
  /// It covers the same sensor/upright geometry the dense map covered, so
  /// [DepthDistanceService.sensorSpaceBox] mapping stays valid.
  final YOLODepthMap grid;

  /// Colourised, alpha-baked heatmap image in SENSOR orientation.
  final ui.Image? heatmap;

  final int timestampMs;
  final int rotationDegrees;
  final int uprightWidth;
  final int uprightHeight;

  bool isStaleAt(int nowMs) =>
      DepthDistanceService.isStale(timestampMs: timestampMs, nowMs: nowMs);

  /// A geometry change between submit and result makes the map unusable.
  bool matchesGeometry({
    required int rotationDegrees,
    required int uprightWidth,
    required int uprightHeight,
  }) =>
      this.rotationDegrees == rotationDegrees &&
      this.uprightWidth == uprightWidth &&
      this.uprightHeight == uprightHeight;
}

/// Per-stage timings of one native depth event.
///
/// Immutable, and `null` rather than `0` where native reported nothing: a stage
/// nobody measured must not look like a 0 ms one. Last-known like
/// [MonocularDepthEstimator.lastLatencyMs], so it survives
/// [MonocularDepthEstimator.stop] and [MonocularDepthEstimator.releaseModel].
class DepthStageTimings {
  const DepthStageTimings({
    this.preMs,
    this.inferenceMs,
    this.postMs,
    this.accelerator,
    this.droppedTicks,
  });

  final int? preMs;
  final int? inferenceMs;
  final int? postMs;

  /// `gpu`/`cpu` as native resolved it, never the requested policy.
  final String? accelerator;

  /// Cumulative ticks native skipped (interval not elapsed, or an inference
  /// already in flight) since its depth tick last restarted. The drop is
  /// decided natively, so only native can count it.
  final int? droppedTicks;
}

/// A loaded depth model instance: the surface the estimator actually drives.
///
/// The real implementation wraps a plugin [YOLO] instance; tests inject a fake
/// through [MonocularDepthEstimator.modelFactory].
abstract class DepthModelHandle {
  /// Id the native tick must be given to run inference on this instance.
  String get instanceId;

  /// Frees the interpreter (weights + delegate) behind this instance.
  Future<void> dispose();
}

/// Loads a depth model. Defaults to the real plugin path, so production call
/// sites never pass it; tests inject it to count loads and releases.
typedef DepthModelFactory =
    Future<DepthModelHandle> Function({
      required String modelId,
      required bool useGpu,
    });

Future<DepthModelHandle> _loadYoloDepthModel({
  required String modelId,
  required bool useGpu,
}) async {
  final yolo = YOLO(
    modelPath: modelId,
    task: YOLOTask.depth,
    useGpu: useGpu,
    useMultiInstance: true,
  );
  try {
    final ok = await yolo.loadModel();
    if (!ok) throw StateError('depth model did not load');
  } catch (error) {
    // A missing/incompatible bundled asset will not fix itself on retry.
    debugPrint('[Depth] model load failed: $error');
    try {
      await yolo.dispose();
    } catch (_) {}
    rethrow;
  }
  return _YoloDepthModel(yolo);
}

class _YoloDepthModel implements DepthModelHandle {
  _YoloDepthModel(this._yolo);

  final YOLO _yolo;

  @override
  String get instanceId => _yolo.instanceId;

  @override
  Future<void> dispose() => _yolo.dispose();
}

/// Runs the official depth model in a SECOND [YOLO] instance fed by the analysis
/// frame inside the plugin view.
///
/// Transport: the view ticks that instance at the configured depth cadence and
/// emits a compact block-mean grid on the view event channel. No image and no
/// dense float map crosses the platform channel, and cadence, latest-frame-wins
/// and the in-flight guard all live natively. This class only derives frames,
/// heatmaps and metrics from the events.
class MonocularDepthEstimator {
  MonocularDepthEstimator({
    this.onFrame,
    this.heatmapBuilder,
    this.modelId = EyeCueModelConfig.depthModelAssetPath,
    this.modelFactory = _loadYoloDepthModel,
    DepthAccelerator? accelerator,
  }) : _useGpu =
           (accelerator ?? resolveDepthAccelerator(depthAcceleratorDefine))
               .useGpu;

  /// Bundled asset path of the depth model, resolved by the plugin's
  /// `YOLOModelResolver` through the same asset path detection already uses.
  ///
  /// shortcut: the plugin copies an asset once into the documents dir keyed by
  /// filename, and `_copyFlutterAssetToDocuments` returns early when that file
  /// exists. A future model swap must therefore use a NEW filename, or devices
  /// keep loading the stale cached copy.
  final String modelId;
  final void Function(DepthFrame frame)? onFrame;

  /// Test seam: defaults to loading a real [YOLO] depth instance.
  final DepthModelFactory modelFactory;

  static const double _observedHzAlpha = 0.3;

  final ValueNotifier<DepthRunState> state = ValueNotifier(DepthRunState.idle);
  final ValueNotifier<DepthFrame?> frame = ValueNotifier(null);

  /// Whether the next publishes build the display heatmap.
  ///
  /// The heatmap is presentation only: while it is disabled a frame still
  /// carries the grid, so distance estimation is unchanged, but no colour
  /// buffer, decode or GPU texture is produced. Turning it off also drops the
  /// image already held, so a hidden overlay cannot show a stale one.
  bool get heatmapEnabled => _heatmapEnabled;
  set heatmapEnabled(bool enabled) {
    // A dispose during a settings push must not touch the disposed notifiers.
    if (_disposed || _heatmapEnabled == enabled) return;
    _heatmapEnabled = enabled;
    if (!enabled) _dropHeatmap();
  }

  bool _heatmapEnabled = true;

  /// Test seam: defaults to the real colourisation/decode path.
  final Future<ui.Image?> Function(YOLODepthMap map)? heatmapBuilder;

  DepthModelHandle? _yolo;
  Future<void>? _preparing;

  /// The accelerator every load requests. Fixed for the estimator's life: the
  /// policy is a build-time flag, so a reload cannot switch accelerators.
  final bool _useGpu;
  bool _modelLoadFailed = false;
  bool _loggedFirstFrame = false;

  /// Bumped by [releaseModel] so a load that was already in flight when depth
  /// was switched off cannot resurrect the model it was loading.
  int _releaseEpoch = 0;

  int? _lastLatencyMs;
  double? _observedHz;
  int? _lastCompletionMs;
  DepthStageTimings? _stageTimings;
  int? _lastHeatmapBuildMs;

  /// Accelerator of the CURRENT instance, cleared when one is adopted so a
  /// previous session cannot label a fresh instance before its first event.
  String? _reportedAccelerator;
  final Stopwatch _clock = Stopwatch()..start();
  bool _disposed = false;

  /// One publish at a time: an overlapping event is dropped (latest-frame-wins), so an
  /// older frame can never land after a newer one and dispose the newer heatmap.
  bool _publishing = false;

  /// Wall-clock milliseconds of the last native depth inference. Survives [stop].
  int? get lastLatencyMs => _lastLatencyMs;

  /// EMA of the observed native depth event cadence. Survives [stop].
  double? get observedHz => _observedHz;

  /// Stage timings of the last depth event. Survives [stop] and [releaseModel].
  DepthStageTimings? get stageTimings => _stageTimings;

  /// Dart-side milliseconds the last heatmap build took; `null` when no heatmap
  /// was built. Presentation cost only — the grid never depends on it.
  int? get lastHeatmapBuildMs => _lastHeatmapBuildMs;

  /// Accelerator native reported for the loaded instance, and therefore what
  /// the run actually used; null while no model is loaded or before its first
  /// event. Never the requested policy: a GPU request that fell back to CPU
  /// reports `cpu`.
  String? get accelerator => _yolo == null ? null : _reportedAccelerator;

  /// Whether the last model load failed. Cleared by [retry] and [releaseModel].
  bool get modelLoadFailed => _modelLoadFailed;

  /// Instance id the view must tick; null until the model is loaded.
  String? get instanceId => _yolo?.instanceId;

  /// Loads the depth model so [instanceId] can reach the streaming config.
  ///
  /// Concurrent calls share one load. A failed load is reported through [state]
  /// (degraded) and is not retried until [retry]. A [releaseModel] invalidates
  /// the in-flight load, so the next call starts a fresh one instead of joining
  /// the release it was already doomed by.
  Future<void> prepare() {
    final inFlight = _preparing;
    if (inFlight != null) return inFlight;
    late final Future<void> load;
    load = _load().whenComplete(() {
      // A release may already have dropped this slot and started a newer load.
      if (identical(_preparing, load)) _preparing = null;
    });
    return _preparing = load;
  }

  Future<void> _load() async {
    if (_disposed || _modelLoadFailed) return;
    try {
      await _ensureModel(_releaseEpoch);
    } catch (error) {
      debugPrint('[Depth] inference failed: $error');
      // The estimator can be torn down while the factory is still running; a
      // degraded write into a disposed notifier would escape as an error.
      if (!_disposed) _degrade();
    }
  }

  /// Consumes one native depth event and publishes the derived frame.
  ///
  /// Silent while degraded, so a broken depth instance cannot keep producing
  /// work; [retry] re-arms it. A native failure marker degrades without
  /// building a frame: the view has already stopped ticking that instance.
  void onNativeDepth(
    YOLODepthEvent event, {
    required int rotationDegrees,
    required int uprightWidth,
    required int uprightHeight,
  }) {
    if (_disposed || state.value == DepthRunState.degraded) return;
    final error = event.error;
    if (error != null) {
      debugPrint('[Depth] native depth inference failed: $error');
      _degrade();
      return;
    }
    if (event.depthGrid.isEmpty || event.width <= 0 || event.height <= 0) {
      _degrade();
      return;
    }
    if (_publishing) return;
    _recordCompletion(event);
    final grid = YOLODepthMap(
      values: event.depthGrid,
      width: event.width,
      height: event.height,
      minDepth: event.minDepth,
      maxDepth: event.maxDepth,
    );
    _publishing = true;
    unawaited(
      _publish(
        grid,
        timestampMs: event.timestampMs,
        rotationDegrees: rotationDegrees,
        uprightWidth: uprightWidth,
        uprightHeight: uprightHeight,
        releaseEpoch: _releaseEpoch,
      ).whenComplete(() => _publishing = false),
    );
  }

  Future<void> _publish(
    YOLODepthMap grid, {
    required int timestampMs,
    required int rotationDegrees,
    required int uprightWidth,
    required int uprightHeight,
    required int releaseEpoch,
  }) async {
    var heatmap = heatmapEnabled ? await _buildTimedHeatmap(grid) : null;
    // A release landed while the builder ran: this frame belongs to a session
    // that no longer exists, so publishing it would repopulate `frame` and
    // report `ready` with no model behind it.
    if (_disposed || releaseEpoch != _releaseEpoch) {
      heatmap?.dispose();
      return;
    }
    // Disabled while the builder ran: publish the grid without the image.
    if (!heatmapEnabled) {
      heatmap?.dispose();
      heatmap = null;
    }
    final next = DepthFrame(
      grid: grid,
      heatmap: heatmap,
      timestampMs: timestampMs,
      rotationDegrees: rotationDegrees,
      uprightWidth: uprightWidth,
      uprightHeight: uprightHeight,
    );
    final previous = frame.value;
    frame.value = next;
    previous?.heatmap?.dispose();
    if (!_loggedFirstFrame) {
      _loggedFirstFrame = true;
      debugPrint(
        '[Depth] first frame ${grid.width}x${grid.height} '
        'minDepth=${grid.minDepth.toStringAsFixed(2)} '
        'maxDepth=${grid.maxDepth.toStringAsFixed(2)} '
        'in ${_lastLatencyMs ?? 0} ms (useGpu=$_useGpu)',
      );
    }
    // A degrade that landed while this frame was in flight wins: publishing
    // `ready` would re-arm the instance id and clear the native failure latch.
    if (state.value != DepthRunState.degraded) {
      state.value = DepthRunState.ready;
    }
    onFrame?.call(next);
  }

  /// Replaces the current frame with a heatmap-less copy and frees the texture.
  void _dropHeatmap() {
    final previous = frame.value;
    final image = previous?.heatmap;
    if (previous == null || image == null) return;
    frame.value = DepthFrame(
      grid: previous.grid,
      heatmap: null,
      timestampMs: previous.timestampMs,
      rotationDegrees: previous.rotationDegrees,
      uprightWidth: previous.uprightWidth,
      uprightHeight: previous.uprightHeight,
    );
    image.dispose();
  }

  /// Records the native latency, the stage timings and the observed event
  /// cadence (EMA, seeded by the first measured delta).
  void _recordCompletion(YOLODepthEvent event) {
    final now = _clock.elapsedMilliseconds;
    final previous = _lastCompletionMs;
    _lastCompletionMs = now;
    _lastLatencyMs = event.latencyMs;
    final accel = event.accelerator;
    // Log the accelerator native actually reported, once per loaded instance:
    // the first-frame line only carries the requested policy, so an operator
    // could otherwise "confirm" a GPU run that silently fell back to CPU.
    if (accel != null && _reportedAccelerator == null) {
      debugPrint(
        '[Depth] accelerator reported by native: $accel '
        '(requested useGpu=$_useGpu)',
      );
    }
    if (accel != null) _reportedAccelerator = accel;
    _stageTimings = DepthStageTimings(
      preMs: event.preMs,
      inferenceMs: event.inferenceMs,
      postMs: event.postMs,
      accelerator: accel,
      droppedTicks: event.droppedTicks,
    );
    if (previous == null) return;
    final delta = now - previous;
    if (delta <= 0) return;
    final sample = 1000 / delta;
    final ema = _observedHz;
    _observedHz = ema == null
        ? sample
        : ema + (sample - ema) * _observedHzAlpha;
  }

  Future<void> _ensureModel(int epoch) async {
    if (_yolo != null) return;
    await _disposeModel();
    // The estimator can be torn down while the previous model is being freed,
    // and this write would then hit a disposed notifier.
    if (_disposed) return;
    state.value = DepthRunState.loading;
    debugPrint('[Depth] loading model: $modelId (useGpu=$_useGpu)');
    final DepthModelHandle handle;
    try {
      handle = await modelFactory(modelId: modelId, useGpu: _useGpu);
    } catch (error) {
      // A missing/incompatible bundled asset will not fix itself on retry.
      _modelLoadFailed = true;
      rethrow;
    }
    if (_disposed || epoch != _releaseEpoch) {
      // Depth was switched off, or the estimator was torn down, while the model
      // loaded: honour it instead of resurrecting an interpreter nobody asked
      // for. Writing `ready` here would also touch a disposed notifier.
      try {
        await handle.dispose();
      } catch (error) {
        debugPrint('[Depth] dispose failed: $error');
      }
      // Re-park only when no newer load owns the state, so a stale arrival
      // cannot overwrite the ready/degraded a later load established.
      if (!_disposed &&
          _yolo == null &&
          state.value != DepthRunState.degraded) {
        state.value = DepthRunState.idle;
      }
      return;
    }
    _yolo = handle;
    _reportedAccelerator = null;
    state.value = DepthRunState.ready;
  }

  void _degrade() {
    state.value = DepthRunState.degraded;
  }

  /// Marks the end of a live depth session (pause/stop/background).
  ///
  /// Nothing is scheduled on the Dart side any more: the native tick stops as
  /// soon as the streaming config drops the instance id. The model stays loaded.
  void stop() {
    _loggedFirstFrame = false;
  }

  /// Drops the current frame and heatmap image.
  void clearFrame() {
    final previous = frame.value;
    frame.value = null;
    previous?.heatmap?.dispose();
  }

  /// Frees the loaded model when depth is switched off.
  ///
  /// MDE off used to stop only the tick, so the interpreter (5.3 MB of weights
  /// plus its GPU delegate) stayed resident for the rest of the session. This
  /// disposes it, drops the frame and its heatmap texture, clears the
  /// pending/failure state, invalidates any load still in flight, and parks
  /// [state] at [DepthRunState.idle].
  ///
  /// Unlike [dispose] the [ValueNotifier]s survive, so the estimator stays
  /// reusable: [retry] plus a re-arm loads the model again. [stop] is the pause
  /// path and keeps the model; only a disable releases. Telemetry history
  /// ([observedHz], [lastLatencyMs]) is preserved exactly as [stop] preserves
  /// it. Idempotent: with no model loaded it only re-parks the state.
  Future<void> releaseModel() async {
    if (_disposed) return;
    _releaseEpoch++;
    // Drop the in-flight slot: a `prepare()` after this must start its own
    // load, because the one in flight is already doomed by the epoch bump.
    _preparing = null;
    _modelLoadFailed = false;
    stop();
    clearFrame();
    state.value = DepthRunState.idle;
    await _disposeModel();
  }

  /// Re-arms a previously failed model load or a native inference failure (used by
  /// the degraded retry).
  ///
  /// Leaving [DepthRunState.degraded] makes the screen re-push the instance id,
  /// which is also what clears the native failure latch (`depthDisabled`).
  /// A loaded instance keeps its accelerator: a CPU instance stays CPU, so the
  /// retry cannot relabel it as GPU without reloading.
  void retry() {
    if (_disposed) return;
    _modelLoadFailed = false;
    _loggedFirstFrame = false;
    state.value = _yolo == null ? DepthRunState.idle : DepthRunState.ready;
  }

  Future<void> _disposeModel() async {
    final yolo = _yolo;
    _yolo = null;
    if (yolo == null) return;
    try {
      await yolo.dispose();
    } catch (error) {
      debugPrint('[Depth] dispose failed: $error');
    }
  }

  /// Smallest integer stride (1, 2, 4, 8) that keeps the longest side at or
  /// below 320 px. Everything beyond 8 still returns 8.
  static int heatmapStrideFor(int width, int height) {
    final longest = width > height ? width : height;
    for (final stride in const [1, 2, 4, 8]) {
      if (longest / stride <= 320) return stride;
    }
    return 8;
  }

  /// RGBA bytes of the downsampled heatmap. Distance sampling reads the grid
  /// itself; only this display overlay is reduced.
  @visibleForTesting
  static ({int width, int height, Uint8List pixels}) buildHeatmapPixels(
    YOLODepthMap map,
  ) {
    final sourceWidth = map.width;
    final sourceHeight = map.height;
    final stride = heatmapStrideFor(sourceWidth, sourceHeight);
    final width = (sourceWidth / stride).ceil();
    final height = (sourceHeight / stride).ceil();
    final pixels = Uint8List(width * height * 4);
    final min = map.minDepth;
    final max = map.maxDepth;
    final span = max - min;
    for (var y = 0; y < height; y++) {
      final sourceY = y * stride < sourceHeight ? y * stride : sourceHeight - 1;
      final row = y * width;
      for (var x = 0; x < width; x++) {
        final sourceX = x * stride < sourceWidth ? x * stride : sourceWidth - 1;
        final index = sourceY * sourceWidth + sourceX;
        final value = index < map.values.length
            ? map.values[index]
            : double.nan;
        final t = !value.isFinite || span <= 0
            ? 0.0
            : ((value - min) / span).clamp(0.0, 1.0);
        final (r, g, b) = _colourAt(t);
        // Nearest-neighbour is fine: this is a decorative overlay, not a
        // measurement surface.
        final offset = (row + x) * 4;
        pixels[offset] = r;
        pixels[offset + 1] = g;
        pixels[offset + 2] = b;
        pixels[offset + 3] = 140;
      }
    }
    return (width: width, height: height, pixels: pixels);
  }

  Future<ui.Image?> _buildTimedHeatmap(YOLODepthMap map) async {
    final started = _clock.elapsedMilliseconds;
    final image = await (heatmapBuilder ?? _buildHeatmap)(map);
    _lastHeatmapBuildMs = _clock.elapsedMilliseconds - started;
    return image;
  }

  Future<ui.Image?> _buildHeatmap(YOLODepthMap map) async {
    if (map.width <= 0 || map.height <= 0) return null;
    final buffer = buildHeatmapPixels(map);
    final completer = Completer<ui.Image?>();
    ui.decodeImageFromPixels(
      buffer.pixels,
      buffer.width,
      buffer.height,
      ui.PixelFormat.rgba8888,
      completer.complete,
    );
    return completer.future;
  }

  static const _stops = [
    (48, 18, 59),
    (50, 100, 200),
    (40, 190, 140),
    (245, 210, 60),
    (180, 20, 40),
  ];

  static (int, int, int) _colourAt(double t) {
    final scaled = t.clamp(0.0, 1.0) * (_stops.length - 1);
    final index = scaled.floor().clamp(0, _stops.length - 2);
    final local = scaled - index;
    final a = _stops[index];
    final b = _stops[index + 1];
    int mix(int from, int to) => (from + (to - from) * local).round();
    return (mix(a.$1, b.$1), mix(a.$2, b.$2), mix(a.$3, b.$3));
  }

  void dispose() {
    _disposed = true;
    // Same invalidation as [releaseModel]: a load still in flight must land on
    // the epoch mismatch and be disposed, not be adopted by a dead estimator.
    _releaseEpoch++;
    _preparing = null;
    stop();
    clearFrame();
    state.dispose();
    frame.dispose();
    _disposeModel();
  }
}
