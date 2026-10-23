import 'detection.dart';

/// Priority tier assigned to a detected object.
///
/// The thesis describes detected objects being classified by importance so
/// that high-priority obstacles (persons, vehicles, doors) can be called out
/// and can raise an audio alarm. The classification itself lives in
/// `SpatialAnalysisService`; this enum is the user-facing contract.
enum ObjectPriority { high, medium, low }

/// User-facing horizontal position of a detected object relative to the user.
enum RelativePosition { left, center, right }

/// Which estimator produced [DetectionInfo.estimatedMeters].
enum DistanceSource { monocularDepth, boundingBox }

/// Approximate proximity band derived from detection geometry.
///
/// This is an *estimate* based on bounding-box height (a larger, lower box is
/// assumed to be nearer). It is **not** a calibrated distance measurement and
/// is always presented to the user as "approximately near/ahead/far".
enum ProximityBand { near, medium, far }

/// User-facing detection information assembled by [SpatialAnalysisService]:
/// the raw [Detection] plus spatial interpretation and priority classification.
///
/// This is deliberately kept separate from the inference model and from the
/// widgets, so screens never perform spatial reasoning themselves and the
/// vision pipeline stays untouched.
class DetectionInfo {
  final Detection detection;
  final RelativePosition position;
  final ObjectPriority priority;
  final ProximityBand proximity;

  /// Metric distance when the depth model produced one; `null` for the
  /// bounding-box heuristic.
  final double? estimatedMeters;

  /// Which estimator produced [estimatedMeters].
  final DistanceSource distanceSource;

  /// Spoken/display phrase ("about 3.5 m") when a metric estimate exists.
  final String? distanceLabel;

  const DetectionInfo({
    required this.detection,
    required this.position,
    required this.priority,
    required this.proximity,
    this.estimatedMeters,
    this.distanceSource = DistanceSource.boundingBox,
    this.distanceLabel,
  });

  String get label => detection.label;
  double get confidence => detection.confidence;

  /// Human-readable position phrase ("left" / "center" / "right").
  String get positionLabel => switch (position) {
    RelativePosition.left => 'left',
    RelativePosition.center => 'center',
    RelativePosition.right => 'right',
  };

  /// Human-readable approximate proximity phrase.
  String get proximityLabel => switch (proximity) {
    ProximityBand.near => 'near',
    ProximityBand.medium => 'ahead',
    ProximityBand.far => 'far',
  };

  String get semanticLabel =>
      '$label, ${(confidence * 100).toStringAsFixed(0)} percent confidence, '
      'on your $positionLabel, approximately $proximityLabel, '
      '${priority.name} priority';

  Map<String, dynamic> toJson() => {
    'detection': detection.toJson(),
    'position': position.name,
    'priority': priority.name,
    'proximity': proximity.name,
  };
}
