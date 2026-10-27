import 'detector_model.dart';

/// The one detection engine. Kept as an enum because telemetry records and
/// persisted settings carry the value as a stable discriminator.
enum InferenceEngine {
  ultralytics;

  String get label => 'Ultralytics';

  String get description =>
      'Recommended. Uses the native CameraX and LiteRT GPU-to-CPU path.';

  bool get isRecommended => true;
}

/// How object distance is estimated.
///
/// [monocularDepth] runs the depth model and reports metric estimates.
/// [boundingBoxApproximation] stops depth inference entirely and keeps the
/// original box-height heuristic.
enum DistanceEstimationMode {
  monocularDepth(
    'Depth estimate',
    'Estimate distance in metres with the depth model. Slower but metric.',
  ),
  boundingBoxApproximation(
    'Bounding box',
    'Approximate distance from box size only. Lightest option.',
  );

  final String label;
  final String description;

  const DistanceEstimationMode(this.label, this.description);
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
  // Incremented 1 -> 2 when `detectionConfidence` was added, 2 -> 3 when
  // `hideBottomNavigation` was added, 3 -> 4 when the distance/overlay fields
  // were added, 4 -> 5 when the inference cadence targets were added, 5 -> 6
  // when the first-use safety acknowledgement was added, and 6 -> 7 when the
  // detector model selection was added: the established convention is that a
  // new persisted field bumps the schema version. The parser is field-tolerant
  // and has no migration branch, so this is a marker only; older JSON that
  // lacks the fields still parses with the safe default (built-in detector).
  static const int currentSchemaVersion = 7;
  static const double defaultDetectionConfidence = 0.25;
  static const double minDetectionConfidence = 0.10;
  static const double maxDetectionConfidence = 0.75;

  /// Requested detector cadence bounds. `null` means Automatic (the previous
  /// uncapped native behaviour).
  static const int minDetectionTargetHz = 1;
  static const int maxDetectionTargetHz = 30;

  /// Requested depth cadence bounds. A target, not a guaranteed rate.
  static const int defaultDepthTargetHz = 2;
  static const int minDepthTargetHz = 2;
  static const int maxDepthTargetHz = 10;

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

  /// Whether native bounding-box overlays are drawn while the depth heatmap is
  /// hidden. When the heatmap is visible, boxes are painted in Flutter instead.
  final bool showBoundingBoxes;

  /// Whether the depth heatmap is drawn when [distanceEstimationMode] is
  /// [DistanceEstimationMode.monocularDepth].
  final bool showDepthHeatmap;

  final DistanceEstimationMode distanceEstimationMode;

  /// Requested detector cadence in Hz. `null` means Automatic, which keeps the
  /// previous uncapped native cadence.
  final int? detectionTargetHz;

  /// Requested depth cadence in Hz. A target, not a guaranteed rate.
  final int depthTargetHz;

  /// Whether the user has explicitly acknowledged the first-use safety
  /// disclosure. `false` means the acknowledgement has not been shown yet.
  final bool safetyAcknowledged;

  /// Selected detector graph. Older persisted JSON has no value and means the
  /// bundled [DetectorModelKind.builtIn] detector.
  final DetectorModelKind detectorModelKind;

  /// Researcher-provided display name of the imported custom model. Never a raw
  /// filename. Only meaningful when [detectorModelKind] is custom.
  final String? customModelName;

  /// Content-derived fingerprint of the imported graph.
  final String? customModelFingerprint;

  /// Absolute path of the app-owned copy. Local only: exports must strip it.
  final String? customModelPath;

  /// Class count of the imported graph. Labels themselves are **not** persisted
  /// here (settings reach exported study data); they live in the model sidecar.
  final int? customModelClassCount;

  final int schemaVersion;

  const AppSettings({
    this.vibrationFeedback = true,
    this.autoStartDetection = true,
    this.lowPowerMode = false,
    this.audioEnabled = true,
    this.inferenceEngine = InferenceEngine.ultralytics,
    this.detectionConfidence = defaultDetectionConfidence,
    this.hideBottomNavigation = false,
    this.showBoundingBoxes = true,
    this.showDepthHeatmap = true,
    this.distanceEstimationMode = DistanceEstimationMode.monocularDepth,
    this.detectionTargetHz,
    this.depthTargetHz = defaultDepthTargetHz,
    this.safetyAcknowledged = false,
    this.detectorModelKind = DetectorModelKind.builtIn,
    this.customModelName,
    this.customModelFingerprint,
    this.customModelPath,
    this.customModelClassCount,
    this.schemaVersion = currentSchemaVersion,
  });

  /// Sentinel so [copyWith] can distinguish "leave the detection target
  /// unchanged" from "set it back to Automatic (`null`)".
  static const Object _unset = Object();

  AppSettings copyWith({
    bool? vibrationFeedback,
    bool? autoStartDetection,
    bool? lowPowerMode,
    bool? audioEnabled,
    InferenceEngine? inferenceEngine,
    double? detectionConfidence,
    bool? hideBottomNavigation,
    bool? showBoundingBoxes,
    bool? showDepthHeatmap,
    DistanceEstimationMode? distanceEstimationMode,
    Object? detectionTargetHz = _unset,
    int? depthTargetHz,
    bool? safetyAcknowledged,
    DetectorModelKind? detectorModelKind,
    Object? customModelName = _unset,
    Object? customModelFingerprint = _unset,
    Object? customModelPath = _unset,
    Object? customModelClassCount = _unset,
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
      showBoundingBoxes: showBoundingBoxes ?? this.showBoundingBoxes,
      showDepthHeatmap: showDepthHeatmap ?? this.showDepthHeatmap,
      distanceEstimationMode:
          distanceEstimationMode ?? this.distanceEstimationMode,
      detectionTargetHz: identical(detectionTargetHz, _unset)
          ? this.detectionTargetHz
          : normalizeDetectionTargetHz(detectionTargetHz),
      depthTargetHz: depthTargetHz == null
          ? this.depthTargetHz
          : normalizeDepthTargetHz(depthTargetHz),
      safetyAcknowledged: safetyAcknowledged ?? this.safetyAcknowledged,
      detectorModelKind: detectorModelKind ?? this.detectorModelKind,
      customModelName: identical(customModelName, _unset)
          ? this.customModelName
          : customModelName as String?,
      customModelFingerprint: identical(customModelFingerprint, _unset)
          ? this.customModelFingerprint
          : customModelFingerprint as String?,
      customModelPath: identical(customModelPath, _unset)
          ? this.customModelPath
          : customModelPath as String?,
      customModelClassCount: identical(customModelClassCount, _unset)
          ? this.customModelClassCount
          : customModelClassCount as int?,
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
    'showBoundingBoxes': showBoundingBoxes,
    'showDepthHeatmap': showDepthHeatmap,
    'distanceEstimationMode': distanceEstimationMode.name,
    'detectionTargetHz': detectionTargetHz,
    'depthTargetHz': depthTargetHz,
    'safetyAcknowledged': safetyAcknowledged,
    'detectorModelKind': detectorModelKind.name,
    'customModelName': customModelName,
    'customModelFingerprint': customModelFingerprint,
    'customModelPath': customModelPath,
    'customModelClassCount': customModelClassCount,
  };

  /// Parses old and partially written settings without allowing one malformed
  /// field to discard every other valid preference. Missing or unknown engine
  /// values (including the removed Custom engine) use Ultralytics.
  factory AppSettings.fromJson(Map<String, dynamic> json) {
    final engineName = json['inferenceEngine'];
    final engine = engineName is String
        ? InferenceEngine.values.firstWhere(
            (candidate) => candidate.name == engineName,
            orElse: () => InferenceEngine.ultralytics,
          )
        : InferenceEngine.ultralytics;
    final confidence = json['detectionConfidence'];
    final modeName = json['distanceEstimationMode'];
    final mode = modeName is String
        ? DistanceEstimationMode.values.firstWhere(
            (candidate) => candidate.name == modeName,
            orElse: () => DistanceEstimationMode.monocularDepth,
          )
        : DistanceEstimationMode.monocularDepth;
    // Older persisted JSON has no detector fields at all; anything naming a
    // custom model without its full identity is treated as the built-in choice
    // so settings can never claim a model that cannot be resolved.
    final kindName = json['detectorModelKind'];
    final customName = _stringOrNull(json['customModelName']);
    final customFingerprint = _stringOrNull(json['customModelFingerprint']);
    final customPath = _stringOrNull(json['customModelPath']);
    final customClassCount = json['customModelClassCount'];
    final customComplete =
        customName != null &&
        customFingerprint != null &&
        customPath != null &&
        customClassCount is int &&
        customClassCount > 0;
    final parsedKind = kindName is String
        ? DetectorModelKind.values.firstWhere(
            (candidate) => candidate.name == kindName,
            orElse: () => DetectorModelKind.builtIn,
          )
        : DetectorModelKind.builtIn;
    final kind = parsedKind == DetectorModelKind.custom && !customComplete
        ? DetectorModelKind.builtIn
        : parsedKind;
    final usesCustom = kind == DetectorModelKind.custom;
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
      showBoundingBoxes: _boolOr(json['showBoundingBoxes'], true),
      showDepthHeatmap: _boolOr(json['showDepthHeatmap'], true),
      distanceEstimationMode: mode,
      detectionTargetHz: normalizeDetectionTargetHz(json['detectionTargetHz']),
      depthTargetHz: normalizeDepthTargetHz(json['depthTargetHz']),
      // Older persisted JSON lacks the field, so an upgrading user sees the
      // first-use disclosure once.
      safetyAcknowledged: _boolOr(json['safetyAcknowledged'], false),
      detectorModelKind: kind,
      customModelName: usesCustom ? customName : null,
      customModelFingerprint: usesCustom ? customFingerprint : null,
      customModelPath: usesCustom ? customPath : null,
      customModelClassCount: usesCustom ? customClassCount as int : null,
      schemaVersion: currentSchemaVersion,
    );
  }

  DetectionSensitivityPreset? get sensitivityPreset =>
      DetectionSensitivityPreset.fromThreshold(detectionConfidence);

  static bool _boolOr(Object? value, bool fallback) =>
      value is bool ? value : fallback;

  static String? _stringOrNull(Object? value) =>
      value is String && value.trim().isNotEmpty ? value.trim() : null;

  /// Keeps persisted and runtime values within the supported advanced-slider
  /// range and on its 0.05 step grid. NaN and infinity use the default.
  static double normalizeDetectionConfidence(double value) {
    if (!value.isFinite) return defaultDetectionConfidence;
    final clamped = value.clamp(minDetectionConfidence, maxDetectionConfidence);
    return (clamped / 0.05).round() * 0.05;
  }

  /// Normalizes a persisted/requested detector cadence. Anything that is not a
  /// finite positive number means Automatic (`null`); the rest is rounded and
  /// clamped to the supported slider range.
  static int? normalizeDetectionTargetHz(Object? value) {
    if (value is! num || !value.isFinite || value <= 0) return null;
    return value.round().clamp(minDetectionTargetHz, maxDetectionTargetHz);
  }

  /// Normalizes a persisted/requested depth cadence. Non-numeric or non-finite
  /// input falls back to the default; the rest is rounded and clamped.
  static int normalizeDepthTargetHz(Object? value) {
    if (value is! num || !value.isFinite) return defaultDepthTargetHz;
    return value.round().clamp(minDepthTargetHz, maxDepthTargetHz);
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
      other.hideBottomNavigation == hideBottomNavigation &&
      other.showBoundingBoxes == showBoundingBoxes &&
      other.showDepthHeatmap == showDepthHeatmap &&
      other.distanceEstimationMode == distanceEstimationMode &&
      other.detectionTargetHz == detectionTargetHz &&
      other.depthTargetHz == depthTargetHz &&
      other.safetyAcknowledged == safetyAcknowledged &&
      other.detectorModelKind == detectorModelKind &&
      other.customModelName == customModelName &&
      other.customModelFingerprint == customModelFingerprint &&
      other.customModelPath == customModelPath &&
      other.customModelClassCount == customModelClassCount;

  @override
  int get hashCode => Object.hash(
    vibrationFeedback,
    autoStartDetection,
    lowPowerMode,
    audioEnabled,
    inferenceEngine,
    detectionConfidence,
    hideBottomNavigation,
    showBoundingBoxes,
    showDepthHeatmap,
    distanceEstimationMode,
    detectionTargetHz,
    depthTargetHz,
    safetyAcknowledged,
    detectorModelKind,
    customModelName,
    customModelFingerprint,
    customModelPath,
    customModelClassCount,
  );
}
