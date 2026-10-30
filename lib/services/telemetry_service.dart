import 'dart:async';

import 'package:flutter/foundation.dart';
import 'dart:ui' show Rect;

import '../models/alert_lifecycle.dart';
import '../models/app_settings.dart';
import '../models/detection_correction.dart';
import '../models/detection_info.dart';
import '../models/detection_runtime_state.dart';
import '../models/inference_lifecycle_event.dart';
import '../models/detector_model.dart';
import '../models/tracked_detection.dart';

/// The read-only surface export and upload need from one trial's telemetry.
///
/// Satisfied by the live [TelemetryService] and by a frozen
/// `ResearchSession`, so the same export code can serialise either: a live
/// buffer or an immutable finished trial.
abstract class TelemetrySource {
  String get sessionId;
  DateTime? get sessionStart;
  Duration get sessionDuration;
  List<TelemetryRecord> get records;
  List<RuntimeSample> get samples;
  List<TelemetryFailureRecord> get failures;
  List<EngineFallbackRecord> get fallbacks;
  List<InferenceRecoveryRecord> get recoveries;
  List<DetectionCorrection> get corrections;
  List<AlertLifecycleRecord> get alertRecords;
  AlertCounters get alertCounters;
  int get totalDetections;
  int get highPriorityAlerts;
  int get framesProcessed;
  String get appVersion;

  /// True when this source's row lists are known to be incomplete, so a
  /// consumer never reads a missing row as "nothing happened". The live buffer
  /// is never incomplete; a trial restored from a legacy draft is.
  bool get rowsIncomplete;
}

/// Receives every row as it is written, before the capped ring can evict it.
///
/// No queue and no stream: a subscriber is called synchronously and copies what
/// it owns. More than one consumer can subscribe, so a second trial service can
/// never take another trial's rows.
abstract interface class TelemetrySink {
  void onDetection(TelemetryRecord record);
  void onSample(RuntimeSample sample);
  void onFailure(TelemetryFailureRecord record);
  void onFallback(EngineFallbackRecord record);
  void onRecovery(InferenceRecoveryRecord record);
  void onCorrection(DetectionCorrection correction);
  void onAlertLifecycle(AlertLifecycleRecord record);
}

/// Stored JSON enum lookup: an unknown or missing name falls back instead of
/// throwing, so one odd restored row cannot cost the whole trial.
T _enumOr<T extends Enum>(List<T> values, Object? name, T fallback) =>
    values.firstWhere((value) => value.name == name, orElse: () => fallback);

DateTime? _dateOrNull(Object? value) =>
    value is String ? DateTime.tryParse(value) : null;

DateTime _dateOrEpoch(Object? value) =>
    _dateOrNull(value) ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

/// One recorded detection event (used by the Logs tab and aggregates).
class TelemetryRecord {
  final DateTime timestamp;
  final int classId;
  final String label;
  final double confidence;
  final double latencyMs;
  final ObjectPriority priority;
  final String position;
  final ProximityBand? proximity;
  final Rect? box;
  final InferenceEngine engine;
  final double confidenceThreshold;
  final int? trackId;
  final MotionState? motion;

  /// Detector identity captured when the row was written (`builtin` or
  /// `custom:<12 hex>`), so a later rename or switch cannot relabel history.
  /// Null on rows recorded before model attribution existed.
  final String? detectorModelId;

  /// The readable model name at record time. Never re-derived from settings.
  final String? detectorModelName;

  /// Content fingerprint of the graph, so two files with the same name stay
  /// distinguishable.
  final String? detectorModelFingerprint;

  const TelemetryRecord({
    required this.timestamp,
    this.classId = -1,
    required this.label,
    required this.confidence,
    required this.latencyMs,
    required this.priority,
    required this.position,
    this.proximity,
    this.box,
    required this.engine,
    this.confidenceThreshold = 0.25,
    this.trackId,
    this.motion,
    this.detectorModelId,
    this.detectorModelName,
    this.detectorModelFingerprint,
  });

  Map<String, dynamic> toJson() => {
    'timestamp': timestamp.toUtc().toIso8601String(),
    'classId': classId,
    'label': label,
    'confidence': confidence,
    'latencyMs': latencyMs,
    'priority': priority.name,
    'position': position,
    'proximity': proximity?.name,
    'box': box == null
        ? null
        : {
            'left': box!.left,
            'top': box!.top,
            'width': box!.width,
            'height': box!.height,
          },
    'engine': engine.name,
    'confidenceThreshold': confidenceThreshold,
    'trackId': trackId,
    'motion': motion?.name,
    // Attribution is written only when known: an unattributed old row stays
    // free of three empty keys.
    if (detectorModelId != null) 'detectorModelId': detectorModelId,
    if (detectorModelName != null) 'detectorModelName': detectorModelName,
    if (detectorModelFingerprint != null)
      'detectorModelFingerprint': detectorModelFingerprint,
  };

  /// Inverse of [toJson], so a frozen trial survives a restart unchanged.
  factory TelemetryRecord.fromJson(Map<String, dynamic> json) {
    final box = json['box'];
    return TelemetryRecord(
      timestamp: _dateOrEpoch(json['timestamp']),
      classId: (json['classId'] as num?)?.toInt() ?? -1,
      label: json['label'] as String? ?? '',
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0,
      latencyMs: (json['latencyMs'] as num?)?.toDouble() ?? 0,
      priority: _enumOr(
        ObjectPriority.values,
        json['priority'],
        ObjectPriority.low,
      ),
      position: json['position'] as String? ?? '',
      proximity: json['proximity'] == null
          ? null
          : _enumOr(
              ProximityBand.values,
              json['proximity'],
              ProximityBand.near,
            ),
      box: box is Map
          ? Rect.fromLTWH(
              (box['left'] as num?)?.toDouble() ?? 0,
              (box['top'] as num?)?.toDouble() ?? 0,
              (box['width'] as num?)?.toDouble() ?? 0,
              (box['height'] as num?)?.toDouble() ?? 0,
            )
          : null,
      engine: _enumOr(
        InferenceEngine.values,
        json['engine'],
        InferenceEngine.ultralytics,
      ),
      confidenceThreshold:
          (json['confidenceThreshold'] as num?)?.toDouble() ?? 0.25,
      trackId: (json['trackId'] as num?)?.toInt(),
      motion: json['motion'] == null
          ? null
          : _enumOr(MotionState.values, json['motion'], MotionState.unknown),
      detectorModelId: json['detectorModelId'] as String?,
      detectorModelName: json['detectorModelName'] as String?,
      detectorModelFingerprint: json['detectorModelFingerprint'] as String?,
    );
  }
}

/// One latency/FPS sample point (used by the charts).
class RuntimeSample {
  final DateTime timestamp;
  final double latencyMs;

  /// Detector observed FPS: the native inference rate, as the plugin reported
  /// it. `0` means "not reported" — the plugin cannot distinguish 0 from
  /// unreported, so the raw value is kept rather than duplicated in a nullable
  /// key that would only ever repeat the same number.
  final double inferenceFps;
  final int objectCount;
  final InferenceEngine engine;
  final double confidenceThreshold;

  /// Stored detector target; `null` means Automatic.
  final int? requestedDetectionHz;

  /// Whether the detector target is Automatic rather than a stored number.
  final bool detectionCadenceAutomatic;

  /// Cadence the detector may actually run at; `null` means uncapped.
  final int? effectiveDetectionHz;

  /// Stored depth target; `null` when no cadence data was supplied.
  final int? requestedDepthHz;

  /// Depth cadence allowed at sample time; `null` when unknown.
  final int? effectiveDepthHz;

  /// Observed depth completion cadence; `null` while no frame is measured.
  final double? depthObservedHz;

  /// Wall-clock milliseconds of the last depth inference; `null` when absent.
  final int? depthLatencyMs;

  /// `disabled`, `loading`, `gpu`, `cpu`, or `degraded`; `null` when absent.
  final String? depthStatus;

  /// Detector stages as native reported them; `null` when a stage was not
  /// measured. [inferenceFps] keeps the plugin's raw (possibly defaulted)
  /// value, so these stay nullable instead of inheriting its `0`.
  final double? detectorPreMs;
  final double? detectorInferenceMs;
  final double? detectorPostMs;

  /// Depth stages of the last completed native depth event.
  final int? depthPreMs;
  final int? depthInferenceMs;
  final int? depthPostMs;

  /// Accelerator native resolved (`gpu`/`cpu`); `null` while unknown. Distinct
  /// from [depthStatus], which folds in `disabled`/`loading`/`degraded`.
  final String? depthAccelerator;

  /// Size of the block-mean grid the last frame carried.
  final int? depthGridWidth;
  final int? depthGridHeight;

  /// Dart-side cost of building the display heatmap; `null` when none was built.
  final int? heatmapBuildMs;

  /// Cumulative native count of skipped depth ticks. A per-interval delta is
  /// derived by differencing consecutive samples; it is not a per-sample drop
  /// count and not a dropped-frame count.
  final int? depthDroppedTicks;
  final bool lowPowerClamped;
  final bool sourceLimited;

  /// Detector identity at sample time — see [TelemetryRecord.detectorModelId].
  /// Depth timings are never attributed to it.
  final String? detectorModelId;
  final String? detectorModelName;
  final String? detectorModelFingerprint;

  const RuntimeSample({
    required this.timestamp,
    required this.latencyMs,
    required this.inferenceFps,
    required this.objectCount,
    required this.engine,
    this.confidenceThreshold = 0.25,
    this.requestedDetectionHz,
    this.detectionCadenceAutomatic = false,
    this.effectiveDetectionHz,
    this.requestedDepthHz,
    this.effectiveDepthHz,
    this.depthObservedHz,
    this.depthLatencyMs,
    this.depthStatus,
    this.detectorPreMs,
    this.detectorInferenceMs,
    this.detectorPostMs,
    this.depthPreMs,
    this.depthInferenceMs,
    this.depthPostMs,
    this.depthAccelerator,
    this.depthGridWidth,
    this.depthGridHeight,
    this.heatmapBuildMs,
    this.depthDroppedTicks,
    this.lowPowerClamped = false,
    this.sourceLimited = false,
    this.detectorModelId,
    this.detectorModelName,
    this.detectorModelFingerprint,
  });

  Map<String, dynamic> toJson() => {
    'timestamp': timestamp.toUtc().toIso8601String(),
    'latencyMs': latencyMs,
    'inferenceFps': inferenceFps,
    'objectCount': objectCount,
    'engine': engine.name,
    'confidenceThreshold': confidenceThreshold,
    'requestedDetectionHz': requestedDetectionHz,
    'detectionCadenceAutomatic': detectionCadenceAutomatic,
    'effectiveDetectionHz': effectiveDetectionHz,
    'requestedDepthHz': requestedDepthHz,
    'effectiveDepthHz': effectiveDepthHz,
    'depthObservedHz': depthObservedHz,
    'depthLatencyMs': depthLatencyMs,
    'depthStatus': depthStatus,
    // Measurements are written only when measured: an unknown stays absent
    // (never `0`), which also stops 400 samples of `null` padding the payload.
    if (detectorPreMs != null) 'detectorPreMs': detectorPreMs,
    if (detectorInferenceMs != null) 'detectorInferenceMs': detectorInferenceMs,
    if (detectorPostMs != null) 'detectorPostMs': detectorPostMs,
    if (depthPreMs != null) 'depthPreMs': depthPreMs,
    if (depthInferenceMs != null) 'depthInferenceMs': depthInferenceMs,
    if (depthPostMs != null) 'depthPostMs': depthPostMs,
    if (depthAccelerator != null) 'depthAccelerator': depthAccelerator,
    if (depthGridWidth != null) 'depthGridWidth': depthGridWidth,
    if (depthGridHeight != null) 'depthGridHeight': depthGridHeight,
    if (heatmapBuildMs != null) 'heatmapBuildMs': heatmapBuildMs,
    if (depthDroppedTicks != null) 'depthDroppedTicks': depthDroppedTicks,
    'lowPowerClamped': lowPowerClamped,
    'sourceLimited': sourceLimited,
    if (detectorModelId != null) 'detectorModelId': detectorModelId,
    if (detectorModelName != null) 'detectorModelName': detectorModelName,
    if (detectorModelFingerprint != null)
      'detectorModelFingerprint': detectorModelFingerprint,
  };

  /// Inverse of [toJson]. Optional keys that were absent stay `null`, never
  /// `0`, exactly as the export contract documents.
  factory RuntimeSample.fromJson(Map<String, dynamic> json) => RuntimeSample(
    timestamp: _dateOrEpoch(json['timestamp']),
    latencyMs: (json['latencyMs'] as num?)?.toDouble() ?? 0,
    inferenceFps: (json['inferenceFps'] as num?)?.toDouble() ?? 0,
    objectCount: (json['objectCount'] as num?)?.toInt() ?? 0,
    engine: _enumOr(
      InferenceEngine.values,
      json['engine'],
      InferenceEngine.ultralytics,
    ),
    confidenceThreshold:
        (json['confidenceThreshold'] as num?)?.toDouble() ?? 0.25,
    requestedDetectionHz: (json['requestedDetectionHz'] as num?)?.toInt(),
    detectionCadenceAutomatic: json['detectionCadenceAutomatic'] == true,
    effectiveDetectionHz: (json['effectiveDetectionHz'] as num?)?.toInt(),
    requestedDepthHz: (json['requestedDepthHz'] as num?)?.toInt(),
    effectiveDepthHz: (json['effectiveDepthHz'] as num?)?.toInt(),
    depthObservedHz: (json['depthObservedHz'] as num?)?.toDouble(),
    depthLatencyMs: (json['depthLatencyMs'] as num?)?.toInt(),
    depthStatus: json['depthStatus'] as String?,
    detectorPreMs: (json['detectorPreMs'] as num?)?.toDouble(),
    detectorInferenceMs: (json['detectorInferenceMs'] as num?)?.toDouble(),
    detectorPostMs: (json['detectorPostMs'] as num?)?.toDouble(),
    depthPreMs: (json['depthPreMs'] as num?)?.toInt(),
    depthInferenceMs: (json['depthInferenceMs'] as num?)?.toInt(),
    depthPostMs: (json['depthPostMs'] as num?)?.toInt(),
    depthAccelerator: json['depthAccelerator'] as String?,
    depthGridWidth: (json['depthGridWidth'] as num?)?.toInt(),
    depthGridHeight: (json['depthGridHeight'] as num?)?.toInt(),
    heatmapBuildMs: (json['heatmapBuildMs'] as num?)?.toInt(),
    depthDroppedTicks: (json['depthDroppedTicks'] as num?)?.toInt(),
    lowPowerClamped: json['lowPowerClamped'] == true,
    sourceLimited: json['sourceLimited'] == true,
    detectorModelId: json['detectorModelId'] as String?,
    detectorModelName: json['detectorModelName'] as String?,
    detectorModelFingerprint: json['detectorModelFingerprint'] as String?,
  );
}

/// Inference cadence configuration at sample time.
///
/// Passed from the detection screen to the telemetry service so a sample can
/// explain the cadence that was actually in force. It is a value object, not a
/// new layer: every field is copied into [RuntimeSample].
class CadenceSample {
  final int? requestedDetectionHz;
  final bool detectionCadenceAutomatic;
  final int? effectiveDetectionHz;
  final int? requestedDepthHz;
  final int? effectiveDepthHz;
  final double? depthObservedHz;
  final int? depthLatencyMs;
  final String? depthStatus;
  final double? detectorPreMs;
  final double? detectorInferenceMs;
  final double? detectorPostMs;
  final int? depthPreMs;
  final int? depthInferenceMs;
  final int? depthPostMs;
  final String? depthAccelerator;
  final int? depthGridWidth;
  final int? depthGridHeight;
  final int? heatmapBuildMs;
  final int? depthDroppedTicks;
  final bool lowPowerClamped;
  final bool sourceLimited;

  const CadenceSample({
    this.requestedDetectionHz,
    this.detectionCadenceAutomatic = false,
    this.effectiveDetectionHz,
    this.requestedDepthHz,
    this.effectiveDepthHz,
    this.depthObservedHz,
    this.depthLatencyMs,
    this.depthStatus,
    this.detectorPreMs,
    this.detectorInferenceMs,
    this.detectorPostMs,
    this.depthPreMs,
    this.depthInferenceMs,
    this.depthPostMs,
    this.depthAccelerator,
    this.depthGridWidth,
    this.depthGridHeight,
    this.heatmapBuildMs,
    this.depthDroppedTicks,
    this.lowPowerClamped = false,
    this.sourceLimited = false,
  });
}

/// A typed runtime failure retained for the export without exposing exception
/// text as the primary user-facing message.
class TelemetryFailureRecord {
  final DetectionFailure failure;

  const TelemetryFailureRecord(this.failure);

  Map<String, dynamic> toJson() => failure.toJson();

  factory TelemetryFailureRecord.fromJson(Map<String, dynamic> json) =>
      TelemetryFailureRecord(DetectionFailure.fromJson(json));
}

class EngineFallbackRecord {
  final DateTime timestamp;
  final InferenceEngine preferredEngine;
  final InferenceEngine activeEngine;
  final String reason;

  const EngineFallbackRecord({
    required this.timestamp,
    required this.preferredEngine,
    required this.activeEngine,
    required this.reason,
  });

  Map<String, dynamic> toJson() => {
    'timestamp': timestamp.toUtc().toIso8601String(),
    'preferredEngine': preferredEngine.name,
    'activeEngine': activeEngine.name,
    'reason': reason,
  };

  factory EngineFallbackRecord.fromJson(Map<String, dynamic> json) =>
      EngineFallbackRecord(
        timestamp: _dateOrEpoch(json['timestamp']),
        preferredEngine: _enumOr(
          InferenceEngine.values,
          json['preferredEngine'],
          InferenceEngine.ultralytics,
        ),
        activeEngine: _enumOr(
          InferenceEngine.values,
          json['activeEngine'],
          InferenceEngine.ultralytics,
        ),
        reason: json['reason'] as String? ?? '',
      );
}

/// One bounded Custom-worker recovery event. It contains lifecycle metadata
/// only; model inputs, camera frames, and internal exception text are excluded.
class InferenceRecoveryRecord {
  final DateTime timestamp;
  final InferenceLifecycleEventType type;
  final int generation;
  final int restartAttempt;
  final DetectionFailureCategory? failureCategory;
  final InferenceEngine engine;

  const InferenceRecoveryRecord({
    required this.timestamp,
    required this.type,
    required this.generation,
    required this.restartAttempt,
    required this.failureCategory,
    required this.engine,
  });

  Map<String, dynamic> toJson() => {
    'timestamp': timestamp.toUtc().toIso8601String(),
    'type': type.name,
    'generation': generation,
    'restartAttempt': restartAttempt,
    'failureCategory': failureCategory?.name,
    'engine': engine.name,
  };

  factory InferenceRecoveryRecord.fromJson(Map<String, dynamic> json) =>
      InferenceRecoveryRecord(
        timestamp: _dateOrEpoch(json['timestamp']),
        type: _enumOr(
          InferenceLifecycleEventType.values,
          json['type'],
          InferenceLifecycleEventType.transientError,
        ),
        generation: (json['generation'] as num?)?.toInt() ?? 0,
        restartAttempt: (json['restartAttempt'] as num?)?.toInt() ?? 0,
        failureCategory: json['failureCategory'] == null
            ? null
            : _enumOr(
                DetectionFailureCategory.values,
                json['failureCategory'],
                DetectionFailureCategory.unknown,
              ),
        engine: _enumOr(
          InferenceEngine.values,
          json['engine'],
          InferenceEngine.ultralytics,
        ),
      );
}

class EngineTelemetrySummary {
  final InferenceEngine engine;
  final int sampleCount;
  final double averageLatencyMs;
  final double averageInferenceFps;

  const EngineTelemetrySummary({
    required this.engine,
    required this.sampleCount,
    required this.averageLatencyMs,
    required this.averageInferenceFps,
  });
}

/// Aggregates runtime telemetry for the Logs & Reports screen.
///
/// The Detection screen is the source of truth and feeds this service; the
/// Logs & Reports screen reads it. This service deliberately does **not**
/// compute model accuracy (accuracy/precision/recall/mAP) — that requires
/// ground-truth labels and is out of scope for a live camera feed.
class TelemetryService extends ChangeNotifier implements TelemetrySource {
  TelemetryService({
    DateTime Function()? clock,
    String? sessionId,
    this.appVersion = '1.0.0+1',
  }) : _clock = clock ?? DateTime.now,
       sessionId =
           sessionId ?? 'session-${DateTime.now().microsecondsSinceEpoch}';

  final DateTime Function() _clock;
  @override
  final String sessionId;
  @override
  final String appVersion;
  final List<TelemetryRecord> _records = [];
  final List<RuntimeSample> _samples = [];
  final List<TelemetryFailureRecord> _failures = [];
  final List<EngineFallbackRecord> _fallbacks = [];
  final List<InferenceRecoveryRecord> _recoveries = [];
  final List<DetectionCorrection> _corrections = [];
  final List<AlertLifecycleRecord> _alertRecords = [];

  /// Capture subscribers, called synchronously from each writer before the ring
  /// is trimmed. Empty by default, and nothing here reads the rows back.
  ///
  /// Replace-on-change instead of in-place mutation, so a subscriber that
  /// unsubscribes while a write is being delivered cannot break the loop.
  List<TelemetrySink> _sinks = const [];

  void subscribe(TelemetrySink sink) {
    if (_sinks.contains(sink)) return;
    _sinks = [..._sinks, sink];
  }

  void unsubscribe(TelemetrySink sink) {
    if (!_sinks.contains(sink)) return;
    _sinks = [
      for (final existing in _sinks)
        if (existing != sink) existing,
    ];
  }

  void _dispatch(void Function(TelemetrySink sink) deliver) {
    for (final sink in _sinks) {
      try {
        deliver(sink);
      } catch (_) {
        // Capture must not interfere with operational telemetry or other sinks.
      }
    }
  }

  static const int _maxRecords = 2000;

  /// 400, not 500: with every other collection at its cap the 500-sample
  /// envelope measured 1,921,180 bytes after the perf keys were thinned (see
  /// `TelemetryExportService.perfSampleStride`), above the 1,900,000-byte
  /// target. The sample count was the only remaining lever that truncates
  /// nothing — each sample is ~430 bytes, and the other collections are
  /// already capped records. 400 samples ≈ 13 minutes at 0.5 Hz, and with the
  /// N=5 thinning still 80 perf points.
  static const int _maxSamples = 400;
  static const int _maxAlertRecords = 500;
  static const Duration _counterPublishWindow = Duration(milliseconds: 250);

  AlertCounters _alertCounters = const AlertCounters();
  Timer? _counterNotifyTimer;

  DateTime? _sessionStart;
  int _highPriorityAlerts = 0;
  int _framesProcessed = 0;
  int _detectionCount = 0;

  @override
  DateTime? get sessionStart => _sessionStart;

  @override
  Duration get sessionDuration => _sessionStart == null
      ? Duration.zero
      : _clock().difference(_sessionStart!);

  @override
  List<TelemetryRecord> get records => List.unmodifiable(_records);
  @override
  List<RuntimeSample> get samples => List.unmodifiable(_samples);
  @override
  List<TelemetryFailureRecord> get failures => List.unmodifiable(_failures);
  @override
  List<EngineFallbackRecord> get fallbacks => List.unmodifiable(_fallbacks);
  @override
  List<InferenceRecoveryRecord> get recoveries =>
      List.unmodifiable(_recoveries);
  @override
  List<DetectionCorrection> get corrections => List.unmodifiable(_corrections);
  @override
  List<AlertLifecycleRecord> get alertRecords =>
      List.unmodifiable(_alertRecords);

  /// Latest cumulative scheduler snapshot; replaced, never accumulated.
  @override
  AlertCounters get alertCounters => _alertCounters;

  /// Detections recorded in this session, never decremented.
  ///
  /// [totalDetections] counts the capped record buffer, so it stops growing once
  /// eviction starts; trial deltas need the count of what actually happened.
  int get detectionCount => _detectionCount;

  @override
  int get totalDetections => _records.length;
  @override
  int get highPriorityAlerts => _highPriorityAlerts;
  @override
  int get framesProcessed => _framesProcessed;
  @override
  bool get rowsIncomplete => false;

  void startSession() {
    _sessionStart ??= _clock();
    notifyListeners();
  }

  void recordDetection(
    DetectionInfo info,
    double latencyMs, {
    required InferenceEngine engine,
    double confidenceThreshold = 0.25,
    TrackedDetection? track,
    DetectorModelRef? detectorModel,
  }) {
    _detectionCount++;
    _records.add(
      TelemetryRecord(
        timestamp: _clock(),
        classId: info.detection.classId,
        label: info.label,
        confidence: info.confidence,
        latencyMs: latencyMs,
        priority: info.priority,
        position: info.positionLabel,
        proximity: info.proximity,
        box: info.detection.box,
        engine: engine,
        confidenceThreshold: confidenceThreshold,
        trackId: track?.trackId,
        motion: track?.motion,
        detectorModelId: detectorModel?.id,
        detectorModelName: detectorModel?.name,
        detectorModelFingerprint: detectorModel?.fingerprint,
      ),
    );
    // Each subscriber's copy is taken before the cap can evict the row.
    _dispatch((sink) => sink.onDetection(_records.last));
    if (_records.length > _maxRecords) {
      _records.removeRange(0, _records.length - _maxRecords);
    }
    if (info.priority == ObjectPriority.high) {
      _highPriorityAlerts++;
    }
    notifyListeners();
  }

  void recordSample({
    required double latencyMs,
    required double inferenceFps,
    required int objectCount,
    required InferenceEngine engine,
    double confidenceThreshold = 0.25,
    int? requestedDetectionHz,
    bool detectionCadenceAutomatic = false,
    int? effectiveDetectionHz,
    int? requestedDepthHz,
    int? effectiveDepthHz,
    double? depthObservedHz,
    int? depthLatencyMs,
    String? depthStatus,
    double? detectorPreMs,
    double? detectorInferenceMs,
    double? detectorPostMs,
    int? depthPreMs,
    int? depthInferenceMs,
    int? depthPostMs,
    String? depthAccelerator,
    int? depthGridWidth,
    int? depthGridHeight,
    int? heatmapBuildMs,
    int? depthDroppedTicks,
    bool lowPowerClamped = false,
    bool sourceLimited = false,
    DetectorModelRef? detectorModel,
  }) {
    _framesProcessed++;
    _samples.add(
      RuntimeSample(
        timestamp: _clock(),
        latencyMs: latencyMs,
        inferenceFps: inferenceFps,
        objectCount: objectCount,
        engine: engine,
        confidenceThreshold: confidenceThreshold,
        requestedDetectionHz: requestedDetectionHz,
        detectionCadenceAutomatic: detectionCadenceAutomatic,
        effectiveDetectionHz: effectiveDetectionHz,
        requestedDepthHz: requestedDepthHz,
        effectiveDepthHz: effectiveDepthHz,
        depthObservedHz: depthObservedHz,
        depthLatencyMs: depthLatencyMs,
        depthStatus: depthStatus,
        detectorPreMs: detectorPreMs,
        detectorInferenceMs: detectorInferenceMs,
        detectorPostMs: detectorPostMs,
        depthPreMs: depthPreMs,
        depthInferenceMs: depthInferenceMs,
        depthPostMs: depthPostMs,
        depthAccelerator: depthAccelerator,
        depthGridWidth: depthGridWidth,
        depthGridHeight: depthGridHeight,
        heatmapBuildMs: heatmapBuildMs,
        depthDroppedTicks: depthDroppedTicks,
        lowPowerClamped: lowPowerClamped,
        sourceLimited: sourceLimited,
        detectorModelId: detectorModel?.id,
        detectorModelName: detectorModel?.name,
        detectorModelFingerprint: detectorModel?.fingerprint,
      ),
    );
    _dispatch((sink) => sink.onSample(_samples.last));
    if (_samples.length > _maxSamples) {
      _samples.removeRange(0, _samples.length - _maxSamples);
    }
    notifyListeners();
  }

  void recordFailure(DetectionFailure failure) {
    _failures.add(TelemetryFailureRecord(failure));
    _dispatch((sink) => sink.onFailure(_failures.last));
    if (_failures.length > 200) {
      _failures.removeRange(0, _failures.length - 200);
    }
    notifyListeners();
  }

  void recordFallback({
    required InferenceEngine preferredEngine,
    required InferenceEngine activeEngine,
    required String reason,
  }) {
    _fallbacks.add(
      EngineFallbackRecord(
        timestamp: _clock(),
        preferredEngine: preferredEngine,
        activeEngine: activeEngine,
        reason: reason,
      ),
    );
    _dispatch((sink) => sink.onFallback(_fallbacks.last));
    if (_fallbacks.length > 100) {
      _fallbacks.removeRange(0, _fallbacks.length - 100);
    }
    notifyListeners();
  }

  void recordRecovery(InferenceLifecycleEvent event) {
    switch (event.type) {
      case InferenceLifecycleEventType.recovering:
      case InferenceLifecycleEventType.recoverySucceeded:
      case InferenceLifecycleEventType.terminalFailure:
        break;
      case InferenceLifecycleEventType.starting:
      case InferenceLifecycleEventType.workerReady:
      case InferenceLifecycleEventType.modelLoaded:
      case InferenceLifecycleEventType.transientError:
      case InferenceLifecycleEventType.workerFailure:
      case InferenceLifecycleEventType.disposed:
        return;
    }
    _recoveries.add(
      InferenceRecoveryRecord(
        timestamp: _clock(),
        type: event.type,
        generation: event.generation,
        restartAttempt: event.restartAttempt,
        failureCategory: event.failure?.category,
        engine: event.engine,
      ),
    );
    _dispatch((sink) => sink.onRecovery(_recoveries.last));
    if (_recoveries.length > 200) {
      _recoveries.removeRange(0, _recoveries.length - 200);
    }
    notifyListeners();
  }

  void recordCorrection(DetectionCorrection correction) {
    _corrections.add(correction);
    _dispatch((sink) => sink.onCorrection(_corrections.last));
    if (_corrections.length > 2000) {
      _corrections.removeRange(0, _corrections.length - 2000);
    }
    notifyListeners();
  }

  /// One terminal alert delta. Bounded so a long session stays image-free and
  /// small.
  void recordAlertLifecycle(AlertLifecycleRecord record) {
    _alertRecords.add(record);
    _dispatch((sink) => sink.onAlertLifecycle(_alertRecords.last));
    if (_alertRecords.length > _maxAlertRecords) {
      _alertRecords.removeRange(0, _alertRecords.length - _maxAlertRecords);
    }
    notifyListeners();
  }

  /// Replaces the cumulative snapshot. Rejection counters change on the
  /// inference hot path, so listener notification is limited to one trailing
  /// publication per fixed window instead of once per frame; [alertCounters] is
  /// current immediately and listeners read that latest snapshot when notified.
  void recordAlertCounters(AlertCounters counters) {
    _alertCounters = counters;
    _counterNotifyTimer ??= Timer(_counterPublishWindow, () {
      _counterNotifyTimer = null;
      notifyListeners();
    });
  }

  /// Detection-origin submitted -> confirmed start distribution for [engine].
  ///
  /// Preserved public entry point; delegates to the common interval helper.
  AlertLatencySummary alertSubmittedToStartedSummary(InferenceEngine engine) =>
      alertLatencySummary(engine, AlertLatencyInterval.submittedToStarted);

  /// One required detection-origin interval distribution for [engine].
  ///
  /// Non-detection origins, engine-null records, missing endpoints, and
  /// negative intervals are excluded rather than displayed. Zero-duration
  /// intervals are valid samples.
  AlertLatencySummary alertLatencySummary(
    InferenceEngine engine,
    AlertLatencyInterval interval,
  ) => alertLatencySummaryFor(_alertRecords, engine, interval);

  @override
  void dispose() {
    _counterNotifyTimer?.cancel();
    _counterNotifyTimer = null;
    super.dispose();
  }

  double get averageLatencyMs {
    if (_samples.isEmpty) return 0;
    return _samples.map((s) => s.latencyMs).reduce((a, b) => a + b) /
        _samples.length;
  }

  double get averageInferenceFps {
    if (_samples.isEmpty) return 0;
    return _samples.map((s) => s.inferenceFps).reduce((a, b) => a + b) /
        _samples.length;
  }

  double get averageConfidence {
    if (_records.isEmpty) return 0;
    return _records.map((r) => r.confidence).reduce((a, b) => a + b) /
        _records.length;
  }

  EngineTelemetrySummary summaryFor(InferenceEngine engine) {
    final engineSamples = _samples.where((sample) => sample.engine == engine);
    if (engineSamples.isEmpty) {
      return EngineTelemetrySummary(
        engine: engine,
        sampleCount: 0,
        averageLatencyMs: 0,
        averageInferenceFps: 0,
      );
    }
    var count = 0;
    var latencyTotal = 0.0;
    var fpsTotal = 0.0;
    for (final sample in engineSamples) {
      count++;
      latencyTotal += sample.latencyMs;
      fpsTotal += sample.inferenceFps;
    }
    return EngineTelemetrySummary(
      engine: engine,
      sampleCount: count,
      averageLatencyMs: latencyTotal / count,
      averageInferenceFps: fpsTotal / count,
    );
  }

  /// Detection counts bucketed per whole minute from the first record —
  /// used by the Detection Frequency bar chart.
  ///
  /// [include] applies the screen's model filter before bucketing, so a
  /// filtered chart is not drawn from every model's detections.
  List<int> detectionFrequencyByMinute({
    bool Function(TelemetryRecord record)? include,
  }) {
    final records = include == null
        ? _records
        : _records.where(include).toList(growable: false);
    if (records.isEmpty) return const [];
    final first = records.first.timestamp;
    final buckets = <int>[];
    for (final r in records) {
      final minute = r.timestamp.difference(first).inMinutes;
      while (buckets.length <= minute) {
        buckets.add(0);
      }
      buckets[minute]++;
    }
    return buckets;
  }
}

/// One required detection-origin interval distribution over any alert-record
/// list — the same rule for the live buffer and a frozen trial.
AlertLatencySummary alertLatencySummaryFor(
  Iterable<AlertLifecycleRecord> records,
  InferenceEngine engine,
  AlertLatencyInterval interval,
) {
  final durations = <double>[];
  for (final record in records) {
    if (record.origin != AlertOrigin.detection) continue;
    if (record.engine != engine) continue;
    final start = switch (interval) {
      AlertLatencyInterval.receivedToAccepted ||
      AlertLatencyInterval.receivedToStarted => record.resultReceivedAt,
      AlertLatencyInterval.acceptedToStarted => record.detectionAcceptedAt,
      AlertLatencyInterval.submittedToStarted => record.submittedAt,
    };
    final end = interval == AlertLatencyInterval.receivedToAccepted
        ? record.detectionAcceptedAt
        : record.alertStartedAt;
    if (start == null || end == null) continue;
    final ms = end.difference(start).inMicroseconds / 1000.0;
    if (ms < 0) continue;
    durations.add(ms);
  }
  return AlertLatencySummary.fromDurations(engine, durations);
}
