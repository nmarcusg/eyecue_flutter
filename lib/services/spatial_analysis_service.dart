import 'dart:ui' show Rect;

import '../models/detection.dart';
import '../models/detection_info.dart';
import 'depth_distance_service.dart';

/// Converts raw detections into user-facing spatial and priority information.
///
/// Pure and deterministic — it never touches the inference pipeline.
///
/// * **Position** is derived from the normalized box center-X relative to the
///   frame (real geometry, not fabricated).
/// * **Priority** is a static class-based classification (thesis: obstacles
///   are classified by importance).
/// * **Proximity** is an *approximate* heuristic based on bounding-box height.
///   It is intentionally labeled as approximate and is **not** a calibrated
///   distance estimator.
class SpatialAnalysisService {
  const SpatialAnalysisService._();

  /// COCO class IDs treated as HIGH priority (people and vehicles — the most
  /// common navigation hazards).
  static const Set<int> highPriorityClasses = {
    0, // person
    1, // bicycle
    2, // car
    3, // motorcycle
    5, // bus
    7, // truck
    8, // boat
    9, // traffic light
    10, // fire hydrant
    11, // stop sign
    12, // parking meter
    13, // bench
  };

  /// COCO class IDs treated as MEDIUM priority (large static obstacles and
  /// objects likely to be encountered while navigating indoors).
  static const Set<int> mediumPriorityClasses = {
    6, // train
    14, // bird
    15, // cat
    16, // dog
    17, // horse
    18, // sheep
    19, // cow
    21, // elephant
    24, // backpack
    28, // suitcase
    32, // sports ball
    36, // skateboard
    39, // bottle
    40, // wine glass
    41, // cup
    44, // bowl
    45, // banana
    49, // orange
    53, // pizza
    56, // chair
    57, // couch
    58, // potted plant
    60, // dining table
    62, // tv
    63, // laptop
    67, // cell phone
    70, // oven
    71, // toaster
    72, // sink
    73, // refrigerator
    74, // book
    75, // clock
    76, // vase
  };

  /// Everything not explicitly listed defaults to LOW priority.

  static ObjectPriority priorityFor(int classId) {
    if (highPriorityClasses.contains(classId)) return ObjectPriority.high;
    if (mediumPriorityClasses.contains(classId)) return ObjectPriority.medium;
    return ObjectPriority.low;
  }

  /// Horizontal position from the normalized box center-X:
  /// `< 1/3 → left`, `> 2/3 → right`, otherwise `center`.
  static RelativePosition positionFor(Rect box) {
    final cx = box.left + box.width / 2;
    if (cx < 1 / 3) return RelativePosition.left;
    if (cx > 2 / 3) return RelativePosition.right;
    return RelativePosition.center;
  }

  /// Approximate proximity band from normalized box height.
  ///
  /// Heuristic thresholds (not calibrated): `>= 0.45 → near`,
  /// `0.18–0.45 → medium`, `< 0.18 → far`.
  static ProximityBand proximityFor(Rect box) {
    final h = box.height;
    if (h >= 0.45) return ProximityBand.near;
    if (h >= 0.18) return ProximityBand.medium;
    return ProximityBand.far;
  }

  /// [meters] is an optional metric distance from the depth model. When absent
  /// the bounding-box heuristic is used unchanged.
  ///
  /// [priorityResolver] overrides the default COCO class-id priority for models
  /// whose class ids mean something else (a custom detector). Omitted means the
  /// unchanged built-in policy.
  static DetectionInfo analyze(
    Detection d, {
    double? meters,
    ObjectPriority Function(Detection)? priorityResolver,
  }) => DetectionInfo(
    detection: d,
    position: positionFor(d.box),
    priority: priorityResolver?.call(d) ?? priorityFor(d.classId),
    proximity: meters == null || !meters.isFinite
        ? proximityFor(d.box)
        : DepthDistanceService.bandForMeters(meters),
    estimatedMeters: meters == null || !meters.isFinite ? null : meters,
    distanceSource: meters == null || !meters.isFinite
        ? DistanceSource.boundingBox
        : DistanceSource.monocularDepth,
    distanceLabel: meters == null || !meters.isFinite
        ? null
        : DepthDistanceService.formatMeters(meters),
  );

  /// [meters] is index-aligned with [detections]; missing entries fall back to
  /// the bounding-box heuristic.
  static List<DetectionInfo> analyzeAll(
    List<Detection> detections, {
    List<double?>? meters,
    ObjectPriority Function(Detection)? priorityResolver,
  }) => [
    for (var i = 0; i < detections.length; i++)
      analyze(
        detections[i],
        meters: meters != null && i < meters.length ? meters[i] : null,
        priorityResolver: priorityResolver,
      ),
  ];
}
