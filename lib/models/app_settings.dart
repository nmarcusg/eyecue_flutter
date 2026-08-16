/// User-configurable application settings, persisted by `SettingsService`.
///
/// All values have safe defaults so a missing/corrupt settings file never
/// breaks startup.
class AppSettings {
  final bool vibrationFeedback;
  final bool autoStartDetection;
  final bool lowPowerMode;
  final bool audioEnabled;

  const AppSettings({
    this.vibrationFeedback = true,
    this.autoStartDetection = true,
    this.lowPowerMode = false,
    this.audioEnabled = true,
  });

  AppSettings copyWith({
    bool? vibrationFeedback,
    bool? autoStartDetection,
    bool? lowPowerMode,
    bool? audioEnabled,
  }) {
    return AppSettings(
      vibrationFeedback: vibrationFeedback ?? this.vibrationFeedback,
      autoStartDetection: autoStartDetection ?? this.autoStartDetection,
      lowPowerMode: lowPowerMode ?? this.lowPowerMode,
      audioEnabled: audioEnabled ?? this.audioEnabled,
    );
  }

  Map<String, dynamic> toJson() => {
        'vibrationFeedback': vibrationFeedback,
        'autoStartDetection': autoStartDetection,
        'lowPowerMode': lowPowerMode,
        'audioEnabled': audioEnabled,
      };

  factory AppSettings.fromJson(Map<String, dynamic> json) => AppSettings(
        vibrationFeedback: json['vibrationFeedback'] as bool? ?? true,
        autoStartDetection: json['autoStartDetection'] as bool? ?? true,
        lowPowerMode: json['lowPowerMode'] as bool? ?? false,
        audioEnabled: json['audioEnabled'] as bool? ?? true,
      );

  @override
  bool operator ==(Object other) =>
      other is AppSettings &&
      other.vibrationFeedback == vibrationFeedback &&
      other.autoStartDetection == autoStartDetection &&
      other.lowPowerMode == lowPowerMode &&
      other.audioEnabled == audioEnabled;

  @override
  int get hashCode =>
      Object.hash(vibrationFeedback, autoStartDetection, lowPowerMode, audioEnabled);
}
