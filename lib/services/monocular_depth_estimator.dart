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
    required this.map,
    required this.heatmap,
    required this.timestampMs,
    required this.rotationDegrees,
    required this.uprightWidth,
    required this.uprightHeight,
  });

  final YOLODepthMap map;

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

/// Raw single-image predictor seam so the scheduler is unit-testable without
/// natives.
typedef DepthPredictor =
    Future<Map<String, dynamic>> Function(Uint8List jpeg, bool useGpu);

/// Runs the official depth model in a SECOND [YOLO] instance fed by the JPEG
/// frames the detection stream delivers.
///
/// cadence: latest-frame-wins with a single pending slot, one in-flight
/// request, and a 500 ms timer that only starts a predict while idle.
class MonocularDepthEstimator {
  MonocularDepthEstimator({
    this.onFrame,
    DepthPredictor? predictor,
    this.modelId = EyeCueModelConfig.depthModelId,
    this.minIntervalMs = EyeCueModelConfig.depthMinIntervalMs,
  }) : _predict = predictor;

  final String modelId;
  final int minIntervalMs;
  final void Function(DepthFrame frame)? onFrame;

  final ValueNotifier<DepthRunState> state = ValueNotifier(DepthRunState.idle);
  final ValueNotifier<DepthFrame?> frame = ValueNotifier(null);

  final DepthPredictor? _predict;

  YOLO? _yolo;
  bool _useGpu = true;
  bool _modelLoadFailed = false;

  Timer? _timer;
  Uint8List? _pendingJpeg;
  int _pendingTimestampMs = 0;
  int _pendingRotation = 0;
  int _pendingWidth = 0;
  int _pendingHeight = 0;
  bool _running = false;
  bool _disposed = false;

  /// Number of queued frames. Never exceeds one by design.
  @visibleForTesting
  int get debugPendingFrames => _pendingJpeg == null ? 0 : 1;

  @visibleForTesting
  bool get debugRunning => _running;

  /// Offers the newest analysis frame. Older pending frames are dropped.
  void submitFrame(
    Uint8List jpeg, {
    required int uprightWidth,
    required int uprightHeight,
    required int rotationDegrees,
    required int timestampMs,
  }) {
    if (_disposed || _modelLoadFailed) return;
    if (jpeg.isEmpty || uprightWidth <= 0 || uprightHeight <= 0) return;
    // The slot is replaced as a unit, so a queued frame is always paired with
    // the geometry it was submitted with.
    _pendingJpeg = jpeg;
    _pendingTimestampMs = timestampMs;
    _pendingRotation = rotationDegrees;
    _pendingWidth = uprightWidth;
    _pendingHeight = uprightHeight;
    _ensureTimer();
  }

  void _ensureTimer() {
    _timer ??= Timer.periodic(
      Duration(milliseconds: minIntervalMs),
      (_) => _drain(),
    );
  }

  Future<void> _drain() async {
    if (_disposed || _running) return;
    final jpeg = _pendingJpeg;
    if (jpeg == null) return;
    final rotation = _pendingRotation;
    final width = _pendingWidth;
    final height = _pendingHeight;
    final submittedAt = _pendingTimestampMs;
    _pendingJpeg = null;
    _running = true;
    try {
      final result = await _run(jpeg);
      if (_disposed) return;
      final depthMap = YOLODetectionResults.fromMap(result).depthMap;
      if (depthMap == null || depthMap.values.isEmpty) {
        _degrade();
        return;
      }
      final heatmap = await _buildHeatmap(depthMap);
      if (_disposed) {
        heatmap?.dispose();
        return;
      }
      final next = DepthFrame(
        map: depthMap,
        heatmap: heatmap,
        timestampMs: submittedAt,
        rotationDegrees: rotation,
        uprightWidth: width,
        uprightHeight: height,
      );
      final previous = frame.value;
      frame.value = next;
      previous?.heatmap?.dispose();
      state.value = DepthRunState.ready;
      onFrame?.call(next);
    } catch (error) {
      debugPrint('[Depth] inference failed: $error');
      _degrade();
    } finally {
      _running = false;
    }
  }

  /// Runs the predictor once, retrying once on CPU when the GPU instance
  /// fails.
  Future<Map<String, dynamic>> _run(Uint8List jpeg) async {
    if (_predict != null) return _predict(jpeg, _useGpu);
    try {
      return await _ensureModel(_useGpu).then((yolo) => yolo.predict(jpeg));
    } catch (error) {
      if (!_useGpu) rethrow;
      debugPrint('[Depth] GPU run failed ($error); retrying on CPU');
      _useGpu = false;
      await _disposeModel();
      return _ensureModel(false).then((yolo) => yolo.predict(jpeg));
    }
  }

  Future<YOLO> _ensureModel(bool useGpu) async {
    final existing = _yolo;
    if (existing != null && _useGpu == useGpu) return existing;
    await _disposeModel();
    state.value = DepthRunState.loading;
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
      // Usually the first-use download failed (offline). Never retry blindly.
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

  /// Clears queued work (pause/stop/background). The model stays loaded.
  void stop() {
    _timer?.cancel();
    _timer = null;
    _pendingJpeg = null;
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

  Future<ui.Image?> _buildHeatmap(YOLODepthMap map) async {
    final width = map.width;
    final height = map.height;
    if (width <= 0 || height <= 0) return null;
    final pixels = Uint8List(width * height * 4);
    final min = map.minDepth;
    final max = map.maxDepth;
    final span = max - min;
    for (var i = 0; i < width * height; i++) {
      final value = i < map.values.length ? map.values[i] : double.nan;
      final t = !value.isFinite || span <= 0
          ? 0.0
          : ((value - min) / span).clamp(0.0, 1.0);
      final (r, g, b) = _colourAt(t);
      final offset = i * 4;
      pixels[offset] = r;
      pixels[offset + 1] = g;
      pixels[offset + 2] = b;
      pixels[offset + 3] = 140;
    }
    final completer = Completer<ui.Image?>();
    ui.decodeImageFromPixels(
      pixels,
      width,
      height,
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
