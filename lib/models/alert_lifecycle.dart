import 'app_settings.dart';

/// What produced one spoken alert.
///
/// Only [AlertOrigin.detection] requests may carry an inference engine;
/// wayfinding, quick-scan, repeat-last, and generic speech always stay
/// engine-null so they can never enter engine-specific latency summaries.
enum AlertOrigin { detection, generic, wayfinding, quickScan, repeatLast }

/// Terminal outcome of one submitted utterance.
enum AlertTerminalState { completed, cancelled, dropped, failed }

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
  };
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
