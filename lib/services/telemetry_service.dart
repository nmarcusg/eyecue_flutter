import 'package:flutter/foundation.dart';

import '../models/detection_info.dart';

/// One recorded detection event (used by the Logs tab and aggregates).
class TelemetryRecord {
  final DateTime timestamp;
  final String label;
  final double confidence;
  final double latencyMs;
  final ObjectPriority priority;
  final String position;

  const TelemetryRecord({
    required this.timestamp,
    required this.label,
    required this.confidence,
    required this.latencyMs,
    required this.priority,
    required this.position,
  });
}

/// One latency/FPS sample point (used by the charts).
class RuntimeSample {
  final DateTime timestamp;
  final double latencyMs;
  final double inferenceFps;
  final int objectCount;

  const RuntimeSample({
    required this.timestamp,
    required this.latencyMs,
    required this.inferenceFps,
    required this.objectCount,
  });
}

/// Aggregates runtime telemetry for the Logs & Reports screen.
///
/// The Detection screen is the source of truth and feeds this service; the
/// Logs & Reports screen reads it. This service deliberately does **not**
/// compute model accuracy (accuracy/precision/recall/mAP) — that requires
/// ground-truth labels and is out of scope for a live camera feed.
class TelemetryService extends ChangeNotifier {
  TelemetryService({DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;
  final List<TelemetryRecord> _records = [];
  final List<RuntimeSample> _samples = [];

  static const int _maxRecords = 2000;
  static const int _maxSamples = 500;

  DateTime? _sessionStart;
  int _highPriorityAlerts = 0;
  int _framesProcessed = 0;

  DateTime? get sessionStart => _sessionStart;

  Duration get sessionDuration =>
      _sessionStart == null ? Duration.zero : _clock().difference(_sessionStart!);

  List<TelemetryRecord> get records => List.unmodifiable(_records);
  List<RuntimeSample> get samples => List.unmodifiable(_samples);

  int get totalDetections => _records.length;
  int get highPriorityAlerts => _highPriorityAlerts;
  int get framesProcessed => _framesProcessed;

  void startSession() {
    _sessionStart ??= _clock();
    notifyListeners();
  }

  void recordDetection(DetectionInfo info, double latencyMs) {
    _records.add(TelemetryRecord(
      timestamp: _clock(),
      label: info.label,
      confidence: info.confidence,
      latencyMs: latencyMs,
      priority: info.priority,
      position: info.positionLabel,
    ));
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
  }) {
    _framesProcessed++;
    _samples.add(RuntimeSample(
      timestamp: _clock(),
      latencyMs: latencyMs,
      inferenceFps: inferenceFps,
      objectCount: objectCount,
    ));
    if (_samples.length > _maxSamples) {
      _samples.removeRange(0, _samples.length - _maxSamples);
    }
    notifyListeners();
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
