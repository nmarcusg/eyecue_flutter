import 'package:flutter/foundation.dart';

import '../models/alert_lifecycle.dart';
import '../models/app_settings.dart';
import '../models/detection_correction.dart';
import '../models/detection_info.dart';
import '../models/detection.dart';
import '../models/tracked_detection.dart';
import 'correction_service.dart';
import 'object_tracker.dart';
import 'spatial_analysis_service.dart';
import 'telemetry_service.dart';
import 'tts_service.dart';

/// Shared post-inference assistive layer.
///
/// Engine-specific camera and inference code ends at [updateDetections]. From
/// that point onward both engines use the same spatial analysis, tracking,
/// telemetry, summaries, and speech policy. No camera frame or tensor buffer
/// crosses this boundary.
class AssistiveDetectionController extends ChangeNotifier {
  AssistiveDetectionController({
    required this.engine,
    required this.tts,
    required this.telemetry,
    ObjectTracker? tracker,
    this.corrections,
    this.confidenceThreshold = 0.25,
  }) : tracker = tracker ?? ObjectTracker(),
       super();

  final InferenceEngine engine;
  final TtsService tts;
  final TelemetryService telemetry;
  final ObjectTracker tracker;
  final CorrectionService? corrections;
  final double confidenceThreshold;

  List<DetectionInfo> _detections = const [];
  List<TrackedDetection> _tracks = const [];

  List<DetectionInfo> get detections => List.unmodifiable(_detections);
  List<TrackedDetection> get tracks => List.unmodifiable(_tracks);

  /// Accepts normalized post-NMS results from either engine.
  ///
  /// [frameLatency] is Custom frame timing. [resultReceivedAt] is the optional
  /// app-side receipt anchor for engines that expose no pre-result timing.
  ///
  /// [meters] is optional, index-aligned metric distance from the depth model.
  List<DetectionInfo> updateDetections(
    List<Detection> detections, {
    double latencyMs = 0,
    bool announce = true,
    DateTime? timestamp,
    FrameLatency? frameLatency,
    DateTime? resultReceivedAt,
    List<double?>? meters,
  }) {
    // Acceptance anchor: entry, before spatial analysis or tracking work.
    final acceptedAt = DateTime.now();
    final timing = frameLatency?.withDetectionAcceptedAt(acceptedAt);
    _detections = SpatialAnalysisService.analyzeAll(detections, meters: meters);
    _tracks = tracker.update(detections, timestamp);
    for (final info in _detections) {
      TrackedDetection? track;
      for (final candidate in _tracks) {
        if (_sameDetection(candidate.detection, info.detection)) {
          track = candidate;
          break;
        }
      }
      telemetry.recordDetection(
        info,
        latencyMs,
        engine: engine,
        confidenceThreshold: confidenceThreshold,
        track: track,
      );
    }
    if (announce) {
      // Deliberately not awaited: frames must never block on speech. The
      // TtsService scheduler is internally serialized (one utterance in
      // flight, one pending slot), so concurrent frame results cannot race
      // announcement decisions.
      tts.announceDetections(
        _detections,
        tracks: _tracks,
        engine: engine,
        frameLatency: timing,
        resultReceivedAt: resultReceivedAt,
        // Direct acceptance anchor only for calls that carry a result receipt;
        // everything else stays timing-less rather than inventing an anchor.
        detectionAcceptedAt: resultReceivedAt == null ? null : acceptedAt,
      );
    }
    notifyListeners();
    return _detections;
  }

  void recordMetrics({
    required double latencyMs,
    required double inferenceFps,
  }) {
    telemetry.recordSample(
      latencyMs: latencyMs,
      inferenceFps: inferenceFps,
      objectCount: _detections.length,
      engine: engine,
      confidenceThreshold: confidenceThreshold,
    );
  }

  Future<bool> quickScan() =>
      tts.announceQuickScan(_detections, tracks: _tracks);

  DetectionCorrection? addCorrection({
    required DetectionInfo info,
    required CorrectionFeedback feedback,
    String? correctedLabel,
  }) {
    final service = corrections;
    if (service == null) return null;
    final correction = service.add(
      info: info,
      feedback: feedback,
      engine: engine,
      confidenceThreshold: confidenceThreshold,
      correctedLabel: correctedLabel,
    );
    telemetry.recordCorrection(correction);
    return correction;
  }

  void reset() {
    tracker.reset();
    _detections = const [];
    _tracks = const [];
    notifyListeners();
  }

  static bool _sameDetection(Detection a, Detection b) =>
      a.classId == b.classId &&
      a.box.left == b.box.left &&
      a.box.top == b.box.top &&
      a.box.width == b.box.width &&
      a.box.height == b.box.height;
}
