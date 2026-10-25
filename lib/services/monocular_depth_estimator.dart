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
  });

  /// Bundled asset path of the depth model, resolved by the plugin's
  /// `YOLOModelResolver` through the same asset path detection already uses.
  ///
  /// shortcut: the plugin copies an asset once into the documents dir keyed by
  /// filename, and `_copyFlutterAssetToDocuments` returns early when that file
  /// exists. A future model swap must therefore use a NEW filename, or devices
  /// keep loading the stale cached copy.
  final String modelId;
  final void Function(DepthFrame frame)? onFrame;

  static const double _observedHzAlpha = 0.3;

  final ValueNotifier<DepthRunState> state = ValueNotifier(DepthRunState.idle);
  final ValueNotifier<DepthFrame?> frame = ValueNotifier(null);

  /// Test seam: defaults to the real colourisation/decode path.
  final Future<ui.Image?> Function(YOLODepthMap map)? heatmapBuilder;

  YOLO? _yolo;
  Future<void>? _preparing;
  bool _useGpu = true;
  bool _modelLoadFailed = false;
  bool _loggedFirstFrame = false;

  int? _lastLatencyMs;
  double? _observedHz;
  int? _lastCompletionMs;
  final Stopwatch _clock = Stopwatch()..start();
  bool _disposed = false;

  /// Wall-clock milliseconds of the last native depth inference. Survives [stop].
  int? get lastLatencyMs => _lastLatencyMs;

  /// EMA of the observed native depth event cadence. Survives [stop].
  double? get observedHz => _observedHz;

  /// Accelerator of a loaded model instance; null while none exists.
  String? get accelerator => _yolo == null ? null : (_useGpu ? 'gpu' : 'cpu');

  /// Instance id the view must tick; null until the model is loaded.
  String? get instanceId => _yolo?.instanceId;

  /// Loads the depth model so [instanceId] can reach the streaming config.
  ///
  /// Concurrent calls share one load. A failed load is reported through [state]
  /// (degraded) and is not retried until [retry].
  Future<void> prepare() => _preparing ??= _load().whenComplete(() {
    _preparing = null;
  });

  Future<void> _load() async {
    if (_disposed || _modelLoadFailed) return;
    try {
      await _ensureModel(_useGpu);
    } catch (error) {
      debugPrint('[Depth] inference failed: $error');
      _degrade();
    }
  }

  /// Consumes one native depth event and publishes the derived frame.
  ///
  /// Silent while degraded, so a broken depth instance cannot keep producing
  /// work; [retry] re-arms it.
  void onNativeDepth(
    YOLODepthEvent event, {
    required int rotationDegrees,
    required int uprightWidth,
    required int uprightHeight,
  }) {
    if (_disposed || state.value == DepthRunState.degraded) return;
    if (event.depthGrid.isEmpty || event.width <= 0 || event.height <= 0) {
      _degrade();
      return;
    }
    _recordCompletion(event.latencyMs);
    final grid = YOLODepthMap(
      values: event.depthGrid,
      width: event.width,
      height: event.height,
      minDepth: event.minDepth,
      maxDepth: event.maxDepth,
    );
    unawaited(
      _publish(
        grid,
        timestampMs: event.timestampMs,
        rotationDegrees: rotationDegrees,
        uprightWidth: uprightWidth,
        uprightHeight: uprightHeight,
      ),
    );
  }

  Future<void> _publish(
    YOLODepthMap grid, {
    required int timestampMs,
    required int rotationDegrees,
    required int uprightWidth,
    required int uprightHeight,
  }) async {
    final heatmap = await (heatmapBuilder ?? _buildHeatmap)(grid);
    if (_disposed) {
      heatmap?.dispose();
      return;
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
    state.value = DepthRunState.ready;
    onFrame?.call(next);
  }

  /// Records the native latency and the observed event cadence (EMA, seeded by
  /// the first measured delta). Bounded storage: two ints and one double.
  void _recordCompletion(int latencyMs) {
    final now = _clock.elapsedMilliseconds;
    final previous = _lastCompletionMs;
    _lastCompletionMs = now;
    _lastLatencyMs = latencyMs;
    if (previous == null) return;
    final delta = now - previous;
    if (delta <= 0) return;
    final sample = 1000 / delta;
    final ema = _observedHz;
    _observedHz = ema == null
        ? sample
        : ema + (sample - ema) * _observedHzAlpha;
  }

  Future<YOLO> _ensureModel(bool useGpu) async {
    final existing = _yolo;
    if (existing != null && _useGpu == useGpu) return existing;
    await _disposeModel();
    state.value = DepthRunState.loading;
    debugPrint('[Depth] loading model: $modelId (useGpu=$useGpu)');
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
      _modelLoadFailed = true;
      try {
        await yolo.dispose();
      } catch (_) {}
      rethrow;
    }
    _yolo = yolo;
    _useGpu = useGpu;
    state.value = DepthRunState.ready;
    return yolo;
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

  /// Re-arms a previously failed model load (used by the degraded retry).
  ///
  /// A loaded instance keeps its accelerator: a CPU instance stays CPU, so the
  /// retry cannot relabel it as GPU without reloading.
  void retry() {
    _modelLoadFailed = false;
    _loggedFirstFrame = false;
    if (_yolo == null) _useGpu = true;
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
    stop();
    clearFrame();
    state.dispose();
    frame.dispose();
    _disposeModel();
  }
}
