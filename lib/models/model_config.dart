abstract final class EyeCueModelConfig {
  /// Metadata-enriched copy of the validated graph. The packager preserves the
  /// base FlatBuffer byte-for-byte and appends the Ultralytics label payload.
  static const modelAssetPath = 'assets/yolov8n_int8_new_metadata.tflite';
  static const labelsAssetPath = 'assets/labels.txt';
  static const defaultConfidenceThreshold = 0.25;

  /// Backward-compatible alias for engine code that still uses the validated
  /// default as a compile-time constant.
  static const confidenceThreshold = defaultConfidenceThreshold;
  static const nmsIouThreshold = 0.45;

  /// Bundled official Ultralytics depth model (id `yolo26n-depth`, w8a32 LiteRT
  /// export, release v0.6.6). Bundled rather than downloaded so MDE works
  /// offline; the app's `INTERNET` permission exists only for the optional
  /// manual telemetry upload.
  static const depthModelAssetPath = 'assets/yolo26n-depth_w8a32.tflite';

  /// Minimum gap between depth inferences; detection keeps its own cadence.
  ///
  /// The gap is enforced natively by the view's depth tick, not by a Dart timer.
  static const depthMinIntervalMs = 500;

  /// Longest side of the block-mean depth grid the native transport emits.
  /// 96 × 96 × 4 bytes ≈ 37 KB per depth event, versus a dense map of hundreds
  /// of KB.
  static const depthGridMaxDim = 96;

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
