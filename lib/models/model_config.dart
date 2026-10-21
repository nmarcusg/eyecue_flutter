abstract final class EyeCueModelConfig {
  /// Metadata-enriched copy of the validated graph. The packager preserves the
  /// base FlatBuffer byte-for-byte and appends the Ultralytics label payload.
  static const modelAssetPath = 'assets/yolov8n_int8_new_metadata.tflite';
  static const baseModelAssetPath = 'assets/yolov8n_int8_new.tflite';
  static const labelsAssetPath = 'assets/labels.txt';
  static const defaultConfidenceThreshold = 0.25;

  /// Backward-compatible alias for engine code that still uses the validated
  /// default as a compile-time constant.
  static const confidenceThreshold = defaultConfidenceThreshold;
  static const nmsIouThreshold = 0.45;

  /// Official Ultralytics depth model ID. Downloaded by the plugin on first use
  /// into `<documents>/mobile-standard-v1/`.
  static const depthModelId = 'yolo26n-depth';

  /// Minimum gap between depth inferences; detection keeps its own cadence.
  static const depthMinIntervalMs = 500;

  /// A depth map older than this is stale: boxes fall back to bbox distance and
  /// the heatmap is hidden.
  static const depthStaleAfterMs = 1000;

  /// The validated range shared by the Custom parser and Ultralytics native
  /// engine. Values are applied at engine restart/reload, not per frame.
  static const minConfidenceThreshold = 0.10;
  static const maxConfidenceThreshold = 0.75;

  static double normalizeConfidenceThreshold(double value) {
    if (!value.isFinite) return defaultConfidenceThreshold;
    final clamped = value.clamp(minConfidenceThreshold, maxConfidenceThreshold);
    return (clamped / 0.05).round() * 0.05;
  }
}
