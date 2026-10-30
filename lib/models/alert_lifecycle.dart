import 'app_settings.dart';

/// What produced one spoken alert.
///
/// Only [AlertOrigin.detection] requests may carry an inference engine;
/// wayfinding, quick-scan, repeat-last, and generic speech always stay
/// engine-null so they can never enter engine-specific latency summaries.
enum AlertOrigin { detection, generic, wayfinding, quickScan, repeatLast }

/// Terminal outcome of one submitted utterance.
enum AlertTerminalState { completed, cancelled, dropped, failed }

/// Immutable timing snapshot for one accepted Custom camera frame.
///
/// The Custom pipeline keeps exactly one frame outstanding, so one snapshot is
/// installed immediately before its result is published and consumed once by
/// the matching listener. Timestamps that were never observed stay null.
class FrameLatency {
  final int frameNumber;
  final DateTime analysisReceivedAt;
  final DateTime? inferenceStartedAt;
  final DateTime? inferenceCompletedAt;
  final DateTime? resultReceivedAt;

  /// Filled in when the result is accepted, before spatial/tracking work.
  final DateTime? detectionAcceptedAt;

  const FrameLatency({
    required this.frameNumber,
    required this.analysisReceivedAt,
    this.inferenceStartedAt,
    this.inferenceCompletedAt,
    this.resultReceivedAt,
    this.detectionAcceptedAt,
  });

  FrameLatency withDetectionAcceptedAt(DateTime value) => FrameLatency(
    frameNumber: frameNumber,
    analysisReceivedAt: analysisReceivedAt,
    inferenceStartedAt: inferenceStartedAt,
    inferenceCompletedAt: inferenceCompletedAt,
    resultReceivedAt: resultReceivedAt,
    detectionAcceptedAt: value,
  );
}

/// Consume-once holder for the one outstanding Custom frame snapshot.
///
/// Install immediately before publishing a result; [take] clears. Every
/// stale-risk path must [clear] so a prior frame/generation can never pair
/// with a later result.
class FrameLatencySlot {
  FrameLatency? _value;

  void install(FrameLatency latency) => _value = latency;

  FrameLatency? take() {
    final value = _value;
    _value = null;
    return value;
  }

  void clear() => _value = null;
}

/// One terminal TTS submission as an event delta.
///
/// Contains timing and outcome metadata only: no utterance text, image, box,
/// device identifier, internal path, or exception detail.
class AlertLifecycleRecord {
  final AlertOrigin origin;
  final InferenceEngine? engine;
  final DateTime requestedAt;
  final DateTime submittedAt;
  final DateTime? alertStartedAt;
  final DateTime terminalAt;
  final AlertTerminalState terminalState;
  final String? terminalCause;
  final bool hadStarted;
  final DateTime? reconciledAt;

  /// Custom frame anchors. Null for non-Custom or timing-less requests.
  final int? frameNumber;
  final DateTime? analysisReceivedAt;
  final DateTime? inferenceStartedAt;
  final DateTime? inferenceCompletedAt;
  final DateTime? resultReceivedAt;
  final DateTime? detectionAcceptedAt;

  const AlertLifecycleRecord({
    required this.origin,
    required this.engine,
    required this.requestedAt,
    required this.submittedAt,
    required this.alertStartedAt,
    required this.terminalAt,
    required this.terminalState,
    required this.terminalCause,
    required this.hadStarted,
    required this.reconciledAt,
    this.frameNumber,
    this.analysisReceivedAt,
    this.inferenceStartedAt,
    this.inferenceCompletedAt,
    this.resultReceivedAt,
    this.detectionAcceptedAt,
  });

  Map<String, dynamic> toJson() => {
    'origin': origin.name,
    'engine': engine?.name,
    'requestedAt': requestedAt.toUtc().toIso8601String(),
    'submittedAt': submittedAt.toUtc().toIso8601String(),
    'alertStartedAt': alertStartedAt?.toUtc().toIso8601String(),
    'terminalAt': terminalAt.toUtc().toIso8601String(),
    'terminalState': terminalState.name,
    'terminalCause': terminalCause,
    'hadStarted': hadStarted,
    'reconciledAt': reconciledAt?.toUtc().toIso8601String(),
    'frameNumber': frameNumber,
    'analysisReceivedAt': analysisReceivedAt?.toUtc().toIso8601String(),
    'inferenceStartedAt': inferenceStartedAt?.toUtc().toIso8601String(),
    'inferenceCompletedAt': inferenceCompletedAt?.toUtc().toIso8601String(),
    'resultReceivedAt': resultReceivedAt?.toUtc().toIso8601String(),
    'detectionAcceptedAt': detectionAcceptedAt?.toUtc().toIso8601String(),
  };

  /// Inverse of [toJson], so a frozen trial restores identical rows.
  factory AlertLifecycleRecord.fromJson(Map<String, dynamic> json) {
    DateTime? date(Object? value) =>
        value is String ? DateTime.tryParse(value) : null;
    T pick<T extends Enum>(List<T> values, Object? name, T fallback) => values
        .firstWhere((value) => value.name == name, orElse: () => fallback);
    final engineName = json['engine'];
    return AlertLifecycleRecord(
      origin: pick(AlertOrigin.values, json['origin'], AlertOrigin.detection),
      engine: engineName == null
          ? null
          : pick(
              InferenceEngine.values,
              engineName,
              InferenceEngine.ultralytics,
            ),
      requestedAt:
          date(json['requestedAt']) ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      submittedAt:
          date(json['submittedAt']) ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      alertStartedAt: date(json['alertStartedAt']),
      terminalAt:
          date(json['terminalAt']) ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      terminalState: pick(
        AlertTerminalState.values,
        json['terminalState'],
        AlertTerminalState.completed,
      ),
      terminalCause: json['terminalCause'] as String?,
      hadStarted: json['hadStarted'] == true,
      reconciledAt: date(json['reconciledAt']),
      frameNumber: (json['frameNumber'] as num?)?.toInt(),
      analysisReceivedAt: date(json['analysisReceivedAt']),
      inferenceStartedAt: date(json['inferenceStartedAt']),
      inferenceCompletedAt: date(json['inferenceCompletedAt']),
      resultReceivedAt: date(json['resultReceivedAt']),
      detectionAcceptedAt: date(json['detectionAcceptedAt']),
    );
  }
}

/// Immutable cumulative scheduler counters.
///
/// Telemetry replaces its stored snapshot with each new value; totals must
/// never be added twice.
class AlertCounters {
  final int dropped;
  final int cancelledBeforeStart;
  final int cancelledAfterStart;
  final int failedBeforeStart;
  final int failedAfterStart;
  final int reconciliationTimeout;
  final int watchdogRecovery;
  final int quietPeriodCapReached;
  final int recoveryFailed;
  final int quarantinedCallback;
  final int lateCallbackIgnored;
  final int callbackOrderViolation;
  final int preemptionRequested;
  final int preempted;
  final int superseded;
  final int muted;
  final int staleDecision;
  final int rejectedAfterRecovery;
  final Map<String, int> rejectedByReason;

  const AlertCounters({
    this.dropped = 0,
    this.cancelledBeforeStart = 0,
    this.cancelledAfterStart = 0,
    this.failedBeforeStart = 0,
    this.failedAfterStart = 0,
    this.reconciliationTimeout = 0,
    this.watchdogRecovery = 0,
    this.quietPeriodCapReached = 0,
    this.recoveryFailed = 0,
    this.quarantinedCallback = 0,
    this.lateCallbackIgnored = 0,
    this.callbackOrderViolation = 0,
    this.preemptionRequested = 0,
    this.preempted = 0,
    this.superseded = 0,
    this.muted = 0,
    this.staleDecision = 0,
    this.rejectedAfterRecovery = 0,
    this.rejectedByReason = const {},
  });

  Map<String, dynamic> toJson() => {
    'dropped': dropped,
    'cancelledBeforeStart': cancelledBeforeStart,
    'cancelledAfterStart': cancelledAfterStart,
    'failedBeforeStart': failedBeforeStart,
    'failedAfterStart': failedAfterStart,
    'reconciliationTimeout': reconciliationTimeout,
    'watchdogRecovery': watchdogRecovery,
    'quietPeriodCapReached': quietPeriodCapReached,
    'recoveryFailed': recoveryFailed,
    'quarantinedCallback': quarantinedCallback,
    'lateCallbackIgnored': lateCallbackIgnored,
    'callbackOrderViolation': callbackOrderViolation,
    'preemptionRequested': preemptionRequested,
    'preempted': preempted,
    'superseded': superseded,
    'muted': muted,
    'staleDecision': staleDecision,
    'rejectedAfterRecovery': rejectedAfterRecovery,
    'rejectedByReason': rejectedByReason,
  };

  /// Inverse of [toJson]; a missing counter stays `0`, as it was written.
  factory AlertCounters.fromJson(Map<String, dynamic> json) {
    int count(String key) => (json[key] as num?)?.toInt() ?? 0;
    return AlertCounters(
      dropped: count('dropped'),
      cancelledBeforeStart: count('cancelledBeforeStart'),
      cancelledAfterStart: count('cancelledAfterStart'),
      failedBeforeStart: count('failedBeforeStart'),
      failedAfterStart: count('failedAfterStart'),
      reconciliationTimeout: count('reconciliationTimeout'),
      watchdogRecovery: count('watchdogRecovery'),
      quietPeriodCapReached: count('quietPeriodCapReached'),
      recoveryFailed: count('recoveryFailed'),
      quarantinedCallback: count('quarantinedCallback'),
      lateCallbackIgnored: count('lateCallbackIgnored'),
      callbackOrderViolation: count('callbackOrderViolation'),
      preemptionRequested: count('preemptionRequested'),
      preempted: count('preempted'),
      superseded: count('superseded'),
      muted: count('muted'),
      staleDecision: count('staleDecision'),
      rejectedAfterRecovery: count('rejectedAfterRecovery'),
      rejectedByReason: {
        for (final entry
            in (json['rejectedByReason'] as Map? ?? const {}).entries)
          '${entry.key}': (entry.value as num?)?.toInt() ?? 0,
      },
    );
  }
}

/// Stable identity of one required alert-latency interval.
///
/// The start anchor for the "received" intervals is the app-side result
/// receipt, which is the first observable point for the native engine.
enum AlertLatencyInterval {
  receivedToAccepted,
  acceptedToStarted,
  submittedToStarted,
  receivedToStarted;

  String label(InferenceEngine engine) => switch (this) {
    AlertLatencyInterval.receivedToAccepted =>
      'Result received → detection accepted',
    AlertLatencyInterval.acceptedToStarted =>
      'Detection accepted → alert started',
    AlertLatencyInterval.submittedToStarted =>
      'Alert submitted → alert started',
    AlertLatencyInterval.receivedToStarted =>
      'Result received → alert started (app-side / post-inference)',
  };
}

/// Nearest-rank distribution for one alert interval.
///
/// Percentiles, max, and count are computed with nearest rank; callers pass
/// only already-validated (present, non-negative) durations.
class AlertLatencySummary {
  final InferenceEngine engine;
  final int sampleCount;
  final double p50Ms;
  final double p95Ms;
  final double maxMs;

  const AlertLatencySummary({
    required this.engine,
    required this.sampleCount,
    required this.p50Ms,
    required this.p95Ms,
    required this.maxMs,
  });

  static AlertLatencySummary fromDurations(
    InferenceEngine engine,
    List<double> durationsMs,
  ) {
    if (durationsMs.isEmpty) {
      return AlertLatencySummary(
        engine: engine,
        sampleCount: 0,
        p50Ms: 0,
        p95Ms: 0,
        maxMs: 0,
      );
    }
    final sorted = [...durationsMs]..sort();
    return AlertLatencySummary(
      engine: engine,
      sampleCount: sorted.length,
      p50Ms: _nearestRank(sorted, 50),
      p95Ms: _nearestRank(sorted, 95),
      maxMs: sorted.last,
    );
  }

  static double _nearestRank(List<double> sorted, int percentile) {
    final rank = (percentile / 100 * sorted.length).ceil();
    // rank is always 1..sorted.length for 0 < percentile <= 100.
    return sorted[rank - 1];
  }
}
