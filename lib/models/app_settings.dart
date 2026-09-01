enum InferenceEngine {
  custom,
  ultralytics;

  String get label => switch (this) {
    InferenceEngine.custom => 'Custom EyeCue',
    InferenceEngine.ultralytics => 'Ultralytics',
  };

  String get description => switch (this) {
    InferenceEngine.custom =>
      'EyeCue Dart preprocessing, parsing, and XNNPACK/CPU path',
    InferenceEngine.ultralytics => 'Native CameraX and LiteRT GPU-to-CPU path',
  };
}

/// User-configurable application settings, persisted by `SettingsService`.
///
/// All values have safe defaults so a missing/corrupt settings file never
/// breaks startup.
class AppSettings {
  final bool vibrationFeedback;
  final bool autoStartDetection;
  final bool lowPowerMode;
  final bool audioEnabled;
  final InferenceEngine inferenceEngine;

  const AppSettings({
    this.vibrationFeedback = true,
    this.autoStartDetection = true,
    this.lowPowerMode = false,
    this.audioEnabled = true,
    this.inferenceEngine = InferenceEngine.custom,
  });

  AppSettings copyWith({
    bool? vibrationFeedback,
    bool? autoStartDetection,
    bool? lowPowerMode,
    bool? audioEnabled,
    InferenceEngine? inferenceEngine,
  }) {
    return AppSettings(
      vibrationFeedback: vibrationFeedback ?? this.vibrationFeedback,
      autoStartDetection: autoStartDetection ?? this.autoStartDetection,
      lowPowerMode: lowPowerMode ?? this.lowPowerMode,
      audioEnabled: audioEnabled ?? this.audioEnabled,
      inferenceEngine: inferenceEngine ?? this.inferenceEngine,
    );
  }

  Map<String, dynamic> toJson() => {
    'vibrationFeedback': vibrationFeedback,
    'autoStartDetection': autoStartDetection,
    'lowPowerMode': lowPowerMode,
    'audioEnabled': audioEnabled,
    'inferenceEngine': inferenceEngine.name,
  };

  factory AppSettings.fromJson(Map<String, dynamic> json) => AppSettings(
    vibrationFeedback: json['vibrationFeedback'] as bool? ?? true,
    autoStartDetection: json['autoStartDetection'] as bool? ?? true,
    lowPowerMode: json['lowPowerMode'] as bool? ?? false,
    audioEnabled: json['audioEnabled'] as bool? ?? true,
    inferenceEngine: InferenceEngine.values.firstWhere(
      (engine) => engine.name == json['inferenceEngine'],
      orElse: () => InferenceEngine.custom,
    ),
  );

  @override
  bool operator ==(Object other) =>
      other is AppSettings &&
      other.vibrationFeedback == vibrationFeedback &&
      other.autoStartDetection == autoStartDetection &&
      other.lowPowerMode == lowPowerMode &&
      other.audioEnabled == audioEnabled &&
      other.inferenceEngine == inferenceEngine;

  @override
  int get hashCode => Object.hash(
    vibrationFeedback,
    autoStartDetection,
    lowPowerMode,
    audioEnabled,
    inferenceEngine,
  );
}
