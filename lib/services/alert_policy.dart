import '../models/detection_info.dart';
import '../models/detector_model.dart';
import '../models/tracked_detection.dart';
import 'scene_summary_service.dart';

/// Shared automatic-alert distance thresholds; these require on-device validation
/// and do not imply calibrated ground-truth distance.
class AutomaticDistanceAlertConfig {
  const AutomaticDistanceAlertConfig({
    this.normalMaxMeters = 2.0,
    this.urgentBelowMeters = 1.5,
    this.hysteresisMeters = 0.3,
  });

  final double normalMaxMeters;
  final double urgentBelowMeters;
  final double hysteresisMeters;
}

/// Why an alert was or was not requested.
enum AlertReason {
  newTrack,
  newLabelFallback,
  riskEscalation,
  forced,
  suppressedSameObject,
  suppressedNoCandidates,
  muted,
}

/// Coarse risk tier used for escalation detection and priority selection.
enum RiskLevel { low, medium, high, imminent }

/// Speech priority. Ordering is normative: higher index wins arbitration.
enum AlertPriority { normal, userInitiated, urgentEscalation, imminent }

/// Result of [AlertPolicy.decide]. Immutable: deciding never mutates history.
class AlertDecision {
  final bool announce;
  final AlertReason reason;
  final RiskLevel risk;
  final AlertPriority priority;
  final String text;
  final String suppressionKey;
  final int? trackId;
  final DetectionInfo? target;
  final double height;
  final MotionState? motion;
  final ProximityBand? proximity;
  final RelativePosition? position;
  final bool preemptEligible;
  final DateTime createdAt;
  final Duration validity;

  /// Accepted-alert timestamp this decision was derived from (`null` when the
  /// identity was new). Used to reject a parked decision that was invalidated
  /// by a later `commitStarted` before it could be spoken.
  final DateTime? basedOnStartedAt;
  final String? detectorIdentity;
  final double? metricMeters;

  const AlertDecision({
    required this.announce,
    required this.reason,
    required this.risk,
    required this.priority,
    required this.text,
    required this.suppressionKey,
    required this.createdAt,
    required this.validity,
    this.trackId,
    this.target,
    this.height = 0,
    this.motion,
    this.proximity,
    this.position,
    this.preemptEligible = false,
    this.basedOnStartedAt,
    this.detectorIdentity,
    this.metricMeters,
  });

  /// A pending request older than [validity] is no longer worth speaking.
  bool isCurrent(DateTime now) => now.difference(createdAt) <= validity;

  AlertDecision asRejected(AlertReason why) => AlertDecision(
    announce: false,
    reason: why,
    risk: risk,
    priority: priority,
    text: text,
    suppressionKey: suppressionKey,
    trackId: trackId,
    target: target,
    height: height,
    motion: motion,
    proximity: proximity,
    position: position,
    preemptEligible: false,
    createdAt: createdAt,
    validity: validity,
    basedOnStartedAt: basedOnStartedAt,
    detectorIdentity: detectorIdentity,
    metricMeters: metricMeters,
  );
}

/// Deterministic, synchronous, **stateful** alert policy.
///
/// [decide] is read-only with respect to accepted-alert history. Only
/// [commitStarted] writes it, and only a confirmed start event may do so.
/// [commitCompleted] and [commitCancelled] never arm or extend suppression.
///
/// Track identity is preferred; label identity is an explicitly weaker fallback
/// used only when no track is available.
class AlertPolicy {
  AlertPolicy({
    this.summary = const SceneSummaryService(),
    this.minEscalationGap = const Duration(milliseconds: 300),
    this.heightGrowthThreshold = 0.12,
    this.validity = const Duration(milliseconds: 1500),
    this.maxKeys = 64,
    this.stateTtl = const Duration(seconds: 30),
    this.distanceConfig = const AutomaticDistanceAlertConfig(),
  });

  final SceneSummaryService summary;

  /// Minimum gap between accepted alerts for one object before an escalation
  /// may fire again. Prevents one frame burst from re-alerting repeatedly.
  final Duration minEscalationGap;

  /// Relative smoothed-height growth that counts as "approaching".
  final double heightGrowthThreshold;

  /// How long a decided alert stays worth speaking while parked.
  final Duration validity;

  /// Bounded identity cache, mirroring `ObjectTracker.maxTracks`.
  final int maxKeys;

  /// How long an accepted identity stays suppressed without being refreshed.
  final Duration stateTtl;
  final AutomaticDistanceAlertConfig distanceConfig;

  final Map<String, _KeyState> _states = {};
  final Set<String> _rearmedKeys = {};
  final Set<String> _urgentRearmedKeys = {};
  String? _lastStartedUtterance;
  DateTime? _lastCompletedAt;
  int _cancelledAfterStartCount = 0;

  String? get lastStartedUtterance => _lastStartedUtterance;
  DateTime? get lastCompletedAt => _lastCompletedAt;
  int get cancelledAfterStartCount => _cancelledAfterStartCount;

  /// Phase 1: read-only decision. Never mutates [decide]'s history.
  AlertDecision decide({
    required List<DetectionInfo> detections,
    required List<TrackedDetection> tracks,
    required DateTime now,
    required bool audioEnabled,
    DetectorModelKind detectorKind = DetectorModelKind.builtIn,
    String? detectorIdentity,
    double? metricMeters,
    bool force = false,
  }) {
    if (!audioEnabled) {
      return _rejection(
        AlertReason.muted,
        RiskLevel.low,
        '',
        now,
        detections.isEmpty ? null : detections.first,
      );
    }
    final ranked = summary.rankCandidates(detections, tracks: tracks);
    final candidates = force
        ? ranked
        : (ranked.where(_automaticAlertAllowed).toList()
            ..sort(_compareAutomatic));
    if (candidates.isEmpty) {
      final rejected = ranked.isEmpty ? null : ranked.first;
      return _rejection(
        AlertReason.suppressedNoCandidates,
        rejected == null ? RiskLevel.low : _riskFor(rejected),
        '',
        now,
        rejected?.info,
        trackId: rejected?.track?.trackId,
      );
    }

    if (force) {
      final primary = candidates.first;
      return _accept(
        primary,
        _keyFor(
          primary,
          detectorKind == DetectorModelKind.custom ? detectorIdentity : null,
        ),
        _riskFor(primary),
        AlertPriority.userInitiated,
        AlertReason.forced,
        now,
        preemptEligible: false,
        detectorIdentity: detectorIdentity,
      );
    }

    // Only a candidate that independently qualifies (new identity, or a risk
    // escalation for that identity) may be announced. A suppressed primary
    // never causes a lower-risk substitute to be announced on its own.
    for (final candidate in candidates) {
      final key = _keyFor(
        candidate,
        detectorKind == DetectorModelKind.custom ? detectorIdentity : null,
      );
      final meters = _validMetric(candidate.info);
      final rearmed =
          _rearmedKeys.contains(key) ||
          (_urgentRearmedKeys.contains(key) &&
              meters != null &&
              meters < distanceConfig.urgentBelowMeters);
      final state = rearmed ? null : _liveState(key, now);
      final risk = _riskFor(candidate);
      if (state == null) {
        return _accept(
          candidate,
          key,
          risk,
          _priorityFor(candidate, risk),
          candidate.track == null
              ? AlertReason.newLabelFallback
              : AlertReason.newTrack,
          now,
          preemptEligible: _preemptEligible(candidate, risk, escalated: false),
          detectorIdentity: detectorIdentity,
        );
      }
      if (_escalated(candidate, state, now)) {
        return _accept(
          candidate,
          key,
          risk,
          _priorityFor(candidate, risk),
          AlertReason.riskEscalation,
          now,
          preemptEligible: _preemptEligible(candidate, risk, escalated: true),
          basedOnStartedAt: state.lastStartedAt,
          detectorIdentity: detectorIdentity,
        );
      }
    }

    final primary = candidates.first;
    return _rejection(
      AlertReason.suppressedSameObject,
      _riskFor(primary),
      _keyFor(
        primary,
        detectorKind == DetectorModelKind.custom ? detectorIdentity : null,
      ),
      now,
      primary.info,
      trackId: primary.track?.trackId,
      height: _heightOf(primary),
    );
  }

  /// Phase 2 (confirmed start): the only writer of suppression history.
  void commitStarted(AlertDecision decision, DateTime startedAt) {
    if (!decision.announce) return;
    _rearmedKeys.remove(decision.suppressionKey);
    _urgentRearmedKeys.remove(decision.suppressionKey);
    _states[decision.suppressionKey] = _KeyState(
      lastStartedAt: startedAt,
      lastRisk: decision.risk,
      lastHeight: decision.height,
      lastMotion: decision.motion,
      lastProximity: decision.proximity,
      wasCentre: decision.position == RelativePosition.center,
      lastMetricMeters: decision.metricMeters,
    );
    _lastStartedUtterance = decision.text;
    _pruneExpired(startedAt);
    _evictOldestIfNeeded();
  }

  /// Revalidates a parked decision against the live accepted state.
  ///
  /// A decision is only discarded when newer accepted state already covers it.
  /// It stays eligible when no live state exists (never accepted, or expired by
  /// [stateTtl]), when the state is unchanged, or when it still represents a
  /// genuine escalation beyond that state. Forced decisions are always kept.
  bool shouldSpeakPending(AlertDecision decision, DateTime now) {
    if (!decision.announce) return false;
    if (decision.reason == AlertReason.forced) return true;
    if (_rearmedKeys.contains(decision.suppressionKey) ||
        (_urgentRearmedKeys.contains(decision.suppressionKey) &&
            decision.metricMeters != null &&
            decision.metricMeters! < distanceConfig.urgentBelowMeters)) {
      return true;
    }
    final state = _liveState(decision.suppressionKey, now);
    if (state == null) return true;
    if (state.lastStartedAt == decision.basedOnStartedAt) return true;
    return _escalationOver(decision, state);
  }

  /// Drops accepted-alert state older than [stateTtl].
  void pruneExpired(DateTime now) => _pruneExpired(now);

  /// Records retreat beyond the hysteresis band without changing speech history.
  void observeDetections({
    required List<DetectionInfo> detections,
    required List<TrackedDetection> tracks,
    required DetectorModelKind detectorKind,
    String? detectorIdentity,
  }) {
    for (final candidate in summary.rankCandidates(
      detections,
      tracks: tracks,
    )) {
      final meters = _validMetric(candidate.info);
      if (meters != null) {
        final key = _keyFor(
          candidate,
          detectorKind == DetectorModelKind.custom ? detectorIdentity : null,
        );
        if (_states.containsKey(key)) {
          if (meters >
              distanceConfig.normalMaxMeters +
                  distanceConfig.hysteresisMeters) {
            _rearmedKeys.add(key);
          }
          if (meters >=
              distanceConfig.urgentBelowMeters +
                  distanceConfig.hysteresisMeters) {
            _urgentRearmedKeys.add(key);
          }
        }
      }
    }
  }

  /// Clears suppression for targets absent from the newest accepted result.
  void clearForDetector(String? detectorIdentity) {
    bool matches(String key) =>
        detectorIdentity == null || key.startsWith('$detectorIdentity|');
    _states.removeWhere((key, _) => matches(key));
    _rearmedKeys.removeWhere(matches);
    _urgentRearmedKeys.removeWhere(matches);
  }

  void commitCompleted(AlertDecision decision, DateTime completedAt) {
    _lastCompletedAt = completedAt;
  }

  /// Bookkeeping only: speech that was already audible keeps the history that
  /// [commitStarted] wrote. Nothing is erased and nothing is extended.
  void commitCancelled(
    AlertDecision decision,
    DateTime cancelledAt, {
    required bool hadStarted,
    required String cause,
  }) {
    if (hadStarted) _cancelledAfterStartCount++;
  }

  /// Test/diagnostic accessors. Never used to make decisions.
  bool hasStateFor(String key) => _states.containsKey(key);
  RiskLevel? lastRiskFor(String key) => _states[key]?.lastRisk;
  DateTime? lastStartedAtFor(String key) => _states[key]?.lastStartedAt;

  // ---------------------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------------------

  String _keyFor(RankedCandidate candidate, [String? detectorIdentity]) {
    final identity = candidate.track != null
        ? 'track:${candidate.track!.trackId}'
        : 'label:${candidate.info.label}';
    return detectorIdentity == null ? identity : '$detectorIdentity|$identity';
  }

  bool _automaticAlertAllowed(RankedCandidate candidate) {
    final info = candidate.info;
    final meters = _validMetric(info);
    if (meters != null) {
      return info.position == RelativePosition.center &&
          meters <= distanceConfig.normalMaxMeters;
    }
    return info.position == RelativePosition.center &&
        info.proximity == ProximityBand.near;
  }

  double? _validMetric(DetectionInfo info) {
    final meters = info.estimatedMeters;
    if (info.distanceSource != DistanceSource.monocularDepth ||
        meters == null ||
        !meters.isFinite ||
        meters < 0.1 ||
        meters > 80) {
      return null;
    }
    return meters;
  }

  int _compareAutomatic(RankedCandidate a, RankedCandidate b) {
    int urgent(RankedCandidate c) {
      final meters = _validMetric(c.info);
      return meters != null &&
              c.info.position == RelativePosition.center &&
              meters < distanceConfig.urgentBelowMeters
          ? 1
          : 0;
    }

    final escalation = urgent(b).compareTo(urgent(a));
    if (escalation != 0) return escalation;
    final center = (b.info.position == RelativePosition.center ? 1 : 0)
        .compareTo(a.info.position == RelativePosition.center ? 1 : 0);
    if (center != 0) return center;
    final priority = a.info.priority.index.compareTo(b.info.priority.index);
    if (priority != 0) return priority;
    final distance = (_validMetric(a.info) ?? double.infinity).compareTo(
      _validMetric(b.info) ?? double.infinity,
    );
    if (distance != 0) return distance;
    final confidence = b.info.confidence.compareTo(a.info.confidence);
    if (confidence != 0) return confidence;
    final label = a.info.label.compareTo(b.info.label);
    if (label != 0) return label;
    return a.info.detection.classId.compareTo(b.info.detection.classId);
  }

  RiskLevel _riskFor(RankedCandidate candidate) {
    final meters = _validMetric(candidate.info);
    if (meters != null && candidate.info.position == RelativePosition.center) {
      return meters < distanceConfig.urgentBelowMeters
          ? RiskLevel.imminent
          : RiskLevel.high;
    }
    final approaching = candidate.track?.motion == MotionState.approaching;
    if (candidate.info.proximity == ProximityBand.near || approaching) {
      return RiskLevel.imminent;
    }
    if (candidate.info.proximity == ProximityBand.medium ||
        candidate.info.position == RelativePosition.center) {
      return RiskLevel.high;
    }
    return RiskLevel.medium;
  }

  AlertPriority _priorityFor(RankedCandidate candidate, RiskLevel risk) {
    final meters = _validMetric(candidate.info);
    if (meters != null && candidate.info.position == RelativePosition.center) {
      return meters < distanceConfig.urgentBelowMeters
          ? AlertPriority.imminent
          : AlertPriority.normal;
    }
    if (risk == RiskLevel.imminent) return AlertPriority.imminent;
    if (risk == RiskLevel.high ||
        candidate.info.priority == ObjectPriority.high) {
      return AlertPriority.urgentEscalation;
    }
    return AlertPriority.normal;
  }

  /// Imminent evidence may preempt through the existing bounded scheduler.
  bool _preemptEligible(
    RankedCandidate candidate,
    RiskLevel risk, {
    required bool escalated,
  }) {
    if (risk == RiskLevel.imminent) return true;
    return escalated &&
        candidate.info.priority == ObjectPriority.high &&
        candidate.track?.motion == MotionState.approaching &&
        (candidate.info.proximity == ProximityBand.near ||
            candidate.info.position == RelativePosition.center);
  }

  bool _escalated(RankedCandidate candidate, _KeyState state, DateTime now) {
    if (now.difference(state.lastStartedAt) < minEscalationGap) return false;
    final meters = _validMetric(candidate.info);
    if (meters != null) {
      final prior = state.lastMetricMeters;
      if (prior == null) return false;
      return (prior >
                  distanceConfig.normalMaxMeters +
                      distanceConfig.hysteresisMeters &&
              meters <= distanceConfig.normalMaxMeters) ||
          (prior >= distanceConfig.urgentBelowMeters &&
              meters < distanceConfig.urgentBelowMeters);
    }
    if (candidate.info.distanceSource == DistanceSource.monocularDepth) {
      return false;
    }
    // Bounded near/center geometry can still report a relative trend, but never
    // turns that estimate into metric-distance wording.
    if (_riskFor(candidate).index > state.lastRisk.index) return true;
    if (candidate.track?.motion == MotionState.approaching &&
        state.lastMotion != MotionState.approaching) {
      return true;
    }
    return state.lastHeight > 0 &&
        candidate.track?.smoothedHeight != null &&
        candidate.track!.smoothedHeight >
            state.lastHeight * (1 + heightGrowthThreshold);
  }

  double _heightOf(RankedCandidate candidate) =>
      candidate.track?.smoothedHeight ?? candidate.info.detection.box.height;

  /// True when [decision] still represents an escalation beyond [state].
  bool _escalationOver(AlertDecision decision, _KeyState state) {
    if (decision.risk.index > state.lastRisk.index) return true;
    if (decision.motion == MotionState.approaching &&
        state.lastMotion != MotionState.approaching) {
      return true;
    }
    final proximity = decision.proximity;
    final acceptedProximity = state.lastProximity;
    if (proximity != null &&
        acceptedProximity != null &&
        proximity.index < acceptedProximity.index) {
      return true;
    }
    if (decision.position == RelativePosition.center && !state.wasCentre) {
      return true;
    }
    return state.lastHeight > 0 &&
        decision.height > state.lastHeight * (1 + heightGrowthThreshold);
  }

  /// Returns `null` when the identity's state has outlived [stateTtl]; a stale
  /// identity is treated as unseen so it can be announced again.
  _KeyState? _liveState(String key, DateTime now) {
    final state = _states[key];
    if (state == null) return null;
    return now.difference(state.lastStartedAt) <= stateTtl ? state : null;
  }

  void _pruneExpired(DateTime now) {
    _states.removeWhere(
      (_, state) => now.difference(state.lastStartedAt) > stateTtl,
    );
    _rearmedKeys.removeWhere((key) => !_states.containsKey(key));
    _urgentRearmedKeys.removeWhere((key) => !_states.containsKey(key));
  }

  AlertDecision _accept(
    RankedCandidate candidate,
    String key,
    RiskLevel risk,
    AlertPriority priority,
    AlertReason reason,
    DateTime now, {
    required bool preemptEligible,
    DateTime? basedOnStartedAt,
    String? detectorIdentity,
  }) {
    final urgent = priority.index >= AlertPriority.urgentEscalation.index;
    final text = urgent
        ? summary.urgentAlert(
            candidate.info,
            urgentBelowMeters: distanceConfig.urgentBelowMeters,
            track: candidate.track,
          )
        : summary.alert([
            candidate.info,
          ], tracks: candidate.track == null ? const [] : [candidate.track!]);
    return AlertDecision(
      announce: true,
      reason: reason,
      risk: risk,
      priority: priority,
      text: text,
      suppressionKey: key,
      trackId: candidate.track?.trackId,
      target: candidate.info,
      height: _heightOf(candidate),
      motion: candidate.track?.motion,
      proximity: candidate.info.proximity,
      position: candidate.info.position,
      preemptEligible: preemptEligible,
      createdAt: now,
      validity: validity,
      basedOnStartedAt: basedOnStartedAt,
      detectorIdentity: detectorIdentity,
      metricMeters: _validMetric(candidate.info),
    );
  }

  AlertDecision _rejection(
    AlertReason reason,
    RiskLevel risk,
    String key,
    DateTime now,
    DetectionInfo? target, {
    int? trackId,
    double height = 0,
  }) => AlertDecision(
    announce: false,
    reason: reason,
    risk: risk,
    priority: AlertPriority.normal,
    text: '',
    suppressionKey: key,
    trackId: trackId,
    target: target,
    height: height,
    createdAt: now,
    validity: validity,
  );

  void _evictOldestIfNeeded() {
    while (_states.length > maxKeys) {
      final oldest = _states.entries.reduce(
        (a, b) => a.value.lastStartedAt.isBefore(b.value.lastStartedAt) ? a : b,
      );
      _states.remove(oldest.key);
      _rearmedKeys.remove(oldest.key);
      _urgentRearmedKeys.remove(oldest.key);
    }
  }
}

class _KeyState {
  final DateTime lastStartedAt;
  final RiskLevel lastRisk;
  final double lastHeight;
  final MotionState? lastMotion;
  final ProximityBand? lastProximity;
  final bool wasCentre;
  final double? lastMetricMeters;

  const _KeyState({
    required this.lastStartedAt,
    required this.lastRisk,
    required this.lastHeight,
    required this.lastMotion,
    required this.lastProximity,
    required this.wasCentre,
    this.lastMetricMeters,
  });
}
