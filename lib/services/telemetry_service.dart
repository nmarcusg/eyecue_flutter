import 'dart:async';

import 'package:flutter/foundation.dart';
import 'dart:ui' show Rect;

import '../models/alert_lifecycle.dart';
import '../models/app_settings.dart';
import '../models/detection_correction.dart';
import '../models/detection_info.dart';
import '../models/detection_runtime_state.dart';
import '../models/inference_lifecycle_event.dart';
import '../models/tracked_detection.dart';

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
  };
}

/// One latency/FPS sample point (used by the charts).
class RuntimeSample {
  final DateTime timestamp;
  final double latencyMs;
  final double inferenceFps;
  final int objectCount;
  final InferenceEngine engine;
  final double confidenceThreshold;

  const RuntimeSample({
    required this.timestamp,
    required this.latencyMs,
    required this.inferenceFps,
    required this.objectCount,
    required this.engine,
    this.confidenceThreshold = 0.25,
  });

  Map<String, dynamic> toJson() => {
    'timestamp': timestamp.toUtc().toIso8601String(),
    'latencyMs': latencyMs,
    'inferenceFps': inferenceFps,
    'objectCount': objectCount,
    'engine': engine.name,
    'confidenceThreshold': confidenceThreshold,
  };
}

/// A typed runtime failure retained for the export without exposing exception
/// text as the primary user-facing message.
class TelemetryFailureRecord {
  final DetectionFailure failure;

  const TelemetryFailureRecord(this.failure);

  Map<String, dynamic> toJson() => failure.toJson();
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
class TelemetryService extends ChangeNotifier {
  TelemetryService({
    DateTime Function()? clock,
    String? sessionId,
    this.appVersion = '1.0.0+1',
  }) : _clock = clock ?? DateTime.now,
       sessionId =
           sessionId ?? 'session-${DateTime.now().microsecondsSinceEpoch}';

  final DateTime Function() _clock;
  final String sessionId;
  final String appVersion;
  final List<TelemetryRecord> _records = [];
  final List<RuntimeSample> _samples = [];
  final List<TelemetryFailureRecord> _failures = [];
  final List<EngineFallbackRecord> _fallbacks = [];
  final List<InferenceRecoveryRecord> _recoveries = [];
  final List<DetectionCorrection> _corrections = [];
  final List<AlertLifecycleRecord> _alertRecords = [];

  static const int _maxRecords = 2000;
  static const int _maxSamples = 500;
  static const int _maxAlertRecords = 500;
  static const Duration _counterPublishWindow = Duration(milliseconds: 250);

  AlertCounters _alertCounters = const AlertCounters();
  Timer? _counterNotifyTimer;

  DateTime? _sessionStart;
  int _highPriorityAlerts = 0;
  int _framesProcessed = 0;

  DateTime? get sessionStart => _sessionStart;

  Duration get sessionDuration => _sessionStart == null
      ? Duration.zero
      : _clock().difference(_sessionStart!);

  List<TelemetryRecord> get records => List.unmodifiable(_records);
  List<RuntimeSample> get samples => List.unmodifiable(_samples);
  List<TelemetryFailureRecord> get failures => List.unmodifiable(_failures);
  List<EngineFallbackRecord> get fallbacks => List.unmodifiable(_fallbacks);
  List<InferenceRecoveryRecord> get recoveries =>
      List.unmodifiable(_recoveries);
  List<DetectionCorrection> get corrections => List.unmodifiable(_corrections);
  List<AlertLifecycleRecord> get alertRecords =>
      List.unmodifiable(_alertRecords);

  /// Latest cumulative scheduler snapshot; replaced, never accumulated.
  AlertCounters get alertCounters => _alertCounters;

  int get totalDetections => _records.length;
  int get highPriorityAlerts => _highPriorityAlerts;
  int get framesProcessed => _framesProcessed;

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
  }) {
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
      ),
    );
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
      ),
    );
    if (_samples.length > _maxSamples) {
      _samples.removeRange(0, _samples.length - _maxSamples);
    }
    notifyListeners();
  }

  void recordFailure(DetectionFailure failure) {
    _failures.add(TelemetryFailureRecord(failure));
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
    if (_recoveries.length > 200) {
      _recoveries.removeRange(0, _recoveries.length - 200);
    }
    notifyListeners();
  }

  void recordCorrection(DetectionCorrection correction) {
    _corrections.add(correction);
    if (_corrections.length > 2000) {
      _corrections.removeRange(0, _corrections.length - 2000);
    }
    notifyListeners();
  }

  /// One terminal alert delta. Bounded so a long session stays image-free and
  /// small.
  void recordAlertLifecycle(AlertLifecycleRecord record) {
    _alertRecords.add(record);
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
  /// Engine-null, non-detection, missing-start, and negative intervals are
  /// excluded rather than displayed.
  AlertLatencySummary alertSubmittedToStartedSummary(InferenceEngine engine) {
    final durations = <double>[];
    for (final record in _alertRecords) {
      if (record.origin != AlertOrigin.detection) continue;
      if (record.engine != engine) continue;
      final startedAt = record.alertStartedAt;
      if (startedAt == null) continue;
      final ms =
          startedAt.difference(record.submittedAt).inMicroseconds / 1000.0;
      if (ms < 0) continue;
      durations.add(ms);
    }
    return AlertLatencySummary.fromDurations(engine, durations);
  }

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
  List<int> detectionFrequencyByMinute() {
    if (_records.isEmpty) return const [];
    final first = _records.first.timestamp;
    final buckets = <int>[];
    for (final r in _records) {
      final minute = r.timestamp.difference(first).inMinutes;
      while (buckets.length <= minute) {
        buckets.add(0);
      }
      buckets[minute]++;
    }
    return buckets;
  }
}
