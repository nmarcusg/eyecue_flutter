import 'package:ultralytics_yolo/ultralytics_yolo.dart';

/// Per-stage detector timings from the native streaming payload.
///
/// [YOLOPerformanceMetrics] defaults a missing number to `0`, and the native map
/// omits these keys unless `includeProcessingTimeMs`/`includeFps` are enabled.
/// Every value is therefore `null` unless it is a real measurement: a stage
/// nobody measured must never look like a 0 ms one.
class DetectorStageTimings {
  const DetectorStageTimings({
    this.preMs,
    this.inferenceMs,
    this.postMs,
    this.fps,
  });

  factory DetectorStageTimings.fromMetrics(YOLOPerformanceMetrics metrics) =>
      DetectorStageTimings(
        preMs: _measured(metrics.preMs),
        inferenceMs: _measured(metrics.inferenceMs),
        postMs: _measured(metrics.postMs),
        fps: _measured(metrics.fps),
      );

  /// Preprocessing (letterbox + normalization) time.
  final double? preMs;

  /// Model inference time.
  final double? inferenceMs;

  /// Postprocessing (decode + NMS) time.
  final double? postMs;

  /// Native inference rate, not the camera rate.
  final double? fps;

  static double? _measured(double value) => value > 0 ? value : null;
}
