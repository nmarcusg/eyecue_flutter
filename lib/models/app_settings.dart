enum InferenceEngine {
  custom,
  ultralytics;

  String get label => switch (this) {
    InferenceEngine.custom => 'Custom EyeCue',
    InferenceEngine.ultralytics => 'Ultralytics',
  };

  String get description => switch (this) {
    InferenceEngine.custom =>
      'Advanced / compatibility fallback. Uses the EyeCue Dart preprocessing, '
          'parsing, and XNNPACK/CPU path.',
    InferenceEngine.ultralytics =>
      'Recommended. Uses the native CameraX and LiteRT GPU-to-CPU path.',
  };

  bool get isRecommended => this == InferenceEngine.ultralytics;
}

/// Plain-language confidence presets exposed by the settings screen.
enum DetectionSensitivityPreset {
  moreDetections(
    0.15,
    'More detections',
    'Find more objects, with more alerts.',
  ),
  balanced(
    0.25,
    'Balanced',
    'The default balance of detections and false alerts.',
  ),
  fewerFalseAlerts(
    0.40,
    'Fewer false alerts',
    'Announce fewer objects when confidence is lower.',
  );

  final double threshold;
  final String label;
  final String description;

  const DetectionSensitivityPreset(
    this.threshold,
    this.label,
    this.description,
  );

  static DetectionSensitivityPreset? fromThreshold(double threshold) {
    for (final preset in values) {
      if ((preset.threshold - threshold).abs() < 0.001) return preset;
    }
    return null;
  }
}

/// User-configurable application settings, persisted by `SettingsService`.
///
/// All values have safe defaults so a missing/corrupt settings file never
/// breaks startup.
class AppSettings {
  // Incremented 1 -> 2 when `detectionConfidence` was added and 2 -> 3 when
  // `hideBottomNavigation` was added: the established convention is that a new
  // persisted field bumps the schema version. The parser is field-tolerant and
  // has no migration branch, so this is a marker only; older JSON that lacks
  // the field still parses with the safe default.
  static const int currentSchemaVersion = 3;
  static const double defaultDetectionConfidence = 0.25;
  static const double minDetectionConfidence = 0.10;
  static const double maxDetectionConfidence = 0.75;

  final bool vibrationFeedback;
  final bool autoStartDetection;
  final bool lowPowerMode;
  final bool audioEnabled;
  final InferenceEngine inferenceEngine;
  final double detectionConfidence;

  /// Persisted preference for hiding the primary bottom navigation bar.
  ///
  /// This is the *user preference* only. The effective bar visibility also
  /// depends on the accessibility-navigation state, which is never written
  /// back here (see `AppShellState`).
  final bool hideBottomNavigation;
  final int schemaVersion;

  const AppSettings({
    this.vibrationFeedback = true,
    this.autoStartDetection = true,
    this.lowPowerMode = false,
    this.audioEnabled = true,
    this.inferenceEngine = InferenceEngine.ultralytics,
    this.detectionConfidence = defaultDetectionConfidence,
    this.hideBottomNavigation = false,
    this.schemaVersion = currentSchemaVersion,
  });

  AppSettings copyWith({
    bool? vibrationFeedback,
    bool? autoStartDetection,
    bool? lowPowerMode,
    bool? audioEnabled,
    InferenceEngine? inferenceEngine,
    double? detectionConfidence,
    bool? hideBottomNavigation,
  }) {
    return AppSettings(
      vibrationFeedback: vibrationFeedback ?? this.vibrationFeedback,
      autoStartDetection: autoStartDetection ?? this.autoStartDetection,
      lowPowerMode: lowPowerMode ?? this.lowPowerMode,
      audioEnabled: audioEnabled ?? this.audioEnabled,
      inferenceEngine: inferenceEngine ?? this.inferenceEngine,
      detectionConfidence: detectionConfidence == null
          ? this.detectionConfidence
          : normalizeDetectionConfidence(detectionConfidence),
      hideBottomNavigation: hideBottomNavigation ?? this.hideBottomNavigation,
    );
  }

  Map<String, dynamic> toJson() => {
    'schemaVersion': currentSchemaVersion,
    'vibrationFeedback': vibrationFeedback,
    'autoStartDetection': autoStartDetection,
    'lowPowerMode': lowPowerMode,
    'audioEnabled': audioEnabled,
    'inferenceEngine': inferenceEngine.name,
    'detectionConfidence': detectionConfidence,
    'hideBottomNavigation': hideBottomNavigation,
  };

  /// Parses old and partially written settings without allowing one malformed
  /// field to discard every other valid preference. Missing engine values use
  /// the new-install default (Ultralytics); an explicit legacy Custom value is
  /// preserved.
  factory AppSettings.fromJson(Map<String, dynamic> json) {
    final engineName = json['inferenceEngine'];
    final engine = engineName is String
        ? InferenceEngine.values.firstWhere(
            (candidate) => candidate.name == engineName,
            orElse: () => InferenceEngine.ultralytics,
          )
        : InferenceEngine.ultralytics;
    final confidence = json['detectionConfidence'];
    return AppSettings(
      vibrationFeedback: _boolOr(json['vibrationFeedback'], true),
      autoStartDetection: _boolOr(json['autoStartDetection'], true),
      lowPowerMode: _boolOr(json['lowPowerMode'], false),
      audioEnabled: _boolOr(json['audioEnabled'], true),
      inferenceEngine: engine,
      detectionConfidence: confidence is num
          ? normalizeDetectionConfidence(confidence.toDouble())
          : defaultDetectionConfidence,
      // Older persisted JSON lacks this field; default to a visible bar so
      // upgrading users keep the navigation bar they already had.
      hideBottomNavigation: _boolOr(json['hideBottomNavigation'], false),
      schemaVersion: currentSchemaVersion,
    );
  }

  DetectionSensitivityPreset? get sensitivityPreset =>
      DetectionSensitivityPreset.fromThreshold(detectionConfidence);

  static bool _boolOr(Object? value, bool fallback) =>
      value is bool ? value : fallback;

  /// Keeps persisted and runtime values within the supported advanced-slider
  /// range and on its 0.05 step grid. NaN and infinity use the default.
  static double normalizeDetectionConfidence(double value) {
    if (!value.isFinite) return defaultDetectionConfidence;
    final clamped = value.clamp(minDetectionConfidence, maxDetectionConfidence);
    return (clamped / 0.05).round() * 0.05;
  }

  @override
  bool operator ==(Object other) =>
      other is AppSettings &&
      other.vibrationFeedback == vibrationFeedback &&
      other.autoStartDetection == autoStartDetection &&
      other.lowPowerMode == lowPowerMode &&
      other.audioEnabled == audioEnabled &&
      other.inferenceEngine == inferenceEngine &&
      other.detectionConfidence == detectionConfidence &&
      other.hideBottomNavigation == hideBottomNavigation;

  @override
  int get hashCode => Object.hash(
    vibrationFeedback,
    autoStartDetection,
    lowPowerMode,
    audioEnabled,
    inferenceEngine,
    detectionConfidence,
    hideBottomNavigation,
  );
}
