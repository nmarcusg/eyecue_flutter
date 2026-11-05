import 'package:flutter/foundation.dart';

import '../models/alert_lifecycle.dart';
import '../models/app_settings.dart';
import '../models/detection_correction.dart';
import '../models/detection_info.dart';
import '../models/detection.dart';
import '../models/detector_model.dart';
import '../models/tracked_detection.dart';
import 'correction_service.dart';
import 'depth_distance_service.dart';
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
    this.priorityResolver,
    this.detectorModel,
  }) : tracker = tracker ?? ObjectTracker(),
       super();

  final InferenceEngine engine;
  final TtsService tts;
  final TelemetryService telemetry;
  final ObjectTracker tracker;
  final CorrectionService? corrections;
  final double confidenceThreshold;

  /// Overrides the default COCO class-id priority (see
  /// [SpatialAnalysisService.analyze]). Null keeps the built-in policy; the
  /// detection screen replaces it when the active model is a custom one.
  ObjectPriority Function(Detection)? priorityResolver;

  /// The detector active at record time, stamped on every recorded row so a
  /// later rename or switch cannot relabel history. Null until the detection
  /// screen supplies it.
  DetectorModelRef? detectorModel;

  final DepthSmoother _displaySmoother = DepthSmoother();
  _DetectionContext? _context;
  int? _depthRevision;
  List<Detection> _rawDetections = const [];
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
    Duration? monotonicReceivedAt,
    String? session,
    String? model,
    String? camera,
    List<double?>? meters,
    int? depthRevision,
  }) {
    // Acceptance anchor: entry, before spatial analysis or tracking work.
    final acceptedAt = DateTime.now();
    final timing = frameLatency?.withDetectionAcceptedAt(acceptedAt);
    _rawDetections = List.unmodifiable(detections);
    _tracks = tracker.update(detections, timestamp);
    _depthRevision = depthRevision;
    _detections = _analyze(meters, depthRevision);
    _context =
        resultReceivedAt != null &&
            monotonicReceivedAt != null &&
            session != null &&
            model != null &&
            camera != null
        ? _DetectionContext(
            resultReceivedAt,
            monotonicReceivedAt,
            session,
            model,
            camera,
          )
        : null;
    if (resultReceivedAt != null &&
        monotonicReceivedAt != null &&
        session != null &&
        model != null &&
        camera != null) {
      tts.updateDetectionObservation(
        detections: _detections,
        receivedAt: resultReceivedAt,
        monotonicReceivedAt: monotonicReceivedAt,
        session: session,
        model: model,
        camera: camera,
        tracks: _tracks,
        detectorKind: detectorModel?.id == 'builtin'
            ? DetectorModelKind.builtIn
            : (detectorModel == null
                  ? DetectorModelKind.builtIn
                  : DetectorModelKind.custom),
        detectorIdentity: detectorModel?.fingerprint,
      );
    } else if (resultReceivedAt != null) {
      tts.updateDetectionObservation(
        detections: _detections,
        receivedAt: resultReceivedAt,
        monotonicReceivedAt: Duration.zero,
        session: session ?? '',
        model: model ?? '',
        camera: camera ?? '',
      );
    }
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
        detectorModel: detectorModel,
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
        detectorKind: detectorModel?.id == 'builtin'
            ? DetectorModelKind.builtIn
            : (detectorModel == null
                  ? DetectorModelKind.builtIn
                  : DetectorModelKind.custom),
        detectorIdentity: detectorModel?.fingerprint,
        session: session,
        model: model,
        camera: camera,
      );
    }
    notifyListeners();
    return _detections;
  }

  /// Consumes new numerical depth without creating a detector observation.
  /// Original receipt/context and tracker hit counts remain unchanged.
  bool reevaluateDepth({
    required List<double?>? meters,
    required int depthRevision,
    required String session,
    required String model,
    required String camera,
  }) {
    final context = _context;
    if (context == null ||
        _rawDetections.isEmpty ||
        _depthRevision == depthRevision ||
        context.session != session ||
        context.model != model ||
        context.camera != camera) {
      return false;
    }
    final age = tts.monotonicNow - context.monotonicReceivedAt;
    if (age < Duration.zero || age > tts.maxDetectionAge) return false;
    _depthRevision = depthRevision;
    _detections = _analyze(meters, depthRevision);
    tts.updateDetectionObservation(
      detections: _detections,
      receivedAt: context.receivedAt,
      monotonicReceivedAt: context.monotonicReceivedAt,
      session: context.session,
      model: context.model,
      camera: context.camera,
      tracks: _tracks,
      detectorKind: _detectorKind,
      detectorIdentity: detectorModel?.fingerprint,
    );
    tts.announceDetections(
      _detections,
      tracks: _tracks,
      engine: engine,
      resultReceivedAt: context.receivedAt,
      detectorKind: _detectorKind,
      detectorIdentity: detectorModel?.fingerprint,
      session: context.session,
      model: context.model,
      camera: context.camera,
    );
    notifyListeners();
    return true;
  }

  DetectorModelKind get _detectorKind =>
      detectorModel == null || detectorModel?.id == 'builtin'
      ? DetectorModelKind.builtIn
      : DetectorModelKind.custom;

  List<DetectionInfo> _analyze(List<double?>? meters, int? revision) {
    _displaySmoother.retainTracks(tracker.activeTracks.map((t) => t.trackId));
    final infos = SpatialAnalysisService.analyzeAll(
      _rawDetections,
      meters: meters,
      priorityResolver: priorityResolver,
    );
    return [for (final info in infos) _withDisplayDistance(info, revision)];
  }

  DetectionInfo _withDisplayDistance(DetectionInfo info, int? revision) {
    final raw = info.estimatedMeters;
    if (raw == null || revision == null) return info;
    TrackedDetection? matched;
    for (final track in _tracks) {
      if (_sameDetection(track.detection, info.detection)) {
        matched = track;
        break;
      }
    }
    if (matched == null) return info;
    return DetectionInfo(
      detection: info.detection,
      position: info.position,
      priority: info.priority,
      proximity: info.proximity,
      estimatedMeters: raw,
      distanceSource: info.distanceSource,
      distanceLabel: info.distanceLabel,
      displayMeters: _displaySmoother.smooth(
        matched.trackId,
        raw,
        observationRevision: revision,
      ),
    );
  }

  void recordMetrics({
    required double latencyMs,
    required double inferenceFps,
    CadenceSample? cadence,
  }) {
    telemetry.recordSample(
      latencyMs: latencyMs,
      inferenceFps: inferenceFps,
      objectCount: _detections.length,
      engine: engine,
      confidenceThreshold: confidenceThreshold,
      requestedDetectionHz: cadence?.requestedDetectionHz,
      detectionCadenceAutomatic: cadence?.detectionCadenceAutomatic ?? false,
      effectiveDetectionHz: cadence?.effectiveDetectionHz,
      requestedDepthHz: cadence?.requestedDepthHz,
      effectiveDepthHz: cadence?.effectiveDepthHz,
      depthObservedHz: cadence?.depthObservedHz,
      depthLatencyMs: cadence?.depthLatencyMs,
      depthStatus: cadence?.depthStatus,
      detectorPreMs: cadence?.detectorPreMs,
      detectorInferenceMs: cadence?.detectorInferenceMs,
      detectorPostMs: cadence?.detectorPostMs,
      depthPreMs: cadence?.depthPreMs,
      depthInferenceMs: cadence?.depthInferenceMs,
      depthPostMs: cadence?.depthPostMs,
      depthAccelerator: cadence?.depthAccelerator,
      depthGridWidth: cadence?.depthGridWidth,
      depthGridHeight: cadence?.depthGridHeight,
      heatmapBuildMs: cadence?.heatmapBuildMs,
      depthDroppedTicks: cadence?.depthDroppedTicks,
      lowPowerClamped: cadence?.lowPowerClamped ?? false,
      sourceLimited: cadence?.sourceLimited ?? false,
      detectorModel: detectorModel,
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

  void reset({String reason = 'session reset'}) {
    tts.invalidateAutomaticDetection(reason: reason);
    tts.policy.resetAutomaticHistory();
    tracker.reset();
    _displaySmoother.reset();
    _context = null;
    _depthRevision = null;
    _rawDetections = const [];
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

class _DetectionContext {
  const _DetectionContext(
    this.receivedAt,
    this.monotonicReceivedAt,
    this.session,
    this.model,
    this.camera,
  );
  final DateTime receivedAt;
  final Duration monotonicReceivedAt;
  final String session;
  final String model;
  final String camera;
}
