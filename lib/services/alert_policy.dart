import '../models/detection_info.dart';
import '../models/tracked_detection.dart';
import 'scene_summary_service.dart';

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
    DateTime Function()? clock,
    this.summary = const SceneSummaryService(),
    this.minEscalationGap = const Duration(milliseconds: 300),
    this.heightGrowthThreshold = 0.12,
    this.validity = const Duration(milliseconds: 1500),
    this.maxKeys = 64,
    this.stateTtl = const Duration(seconds: 30),
  }) : _clock = clock ?? DateTime.now;

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

  final DateTime Function() _clock;

  final Map<String, _KeyState> _states = {};
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
    if (ranked.isEmpty) {
      return _rejection(
        AlertReason.suppressedNoCandidates,
        RiskLevel.low,
        '',
        now,
        null,
      );
    }

    if (force) {
      final primary = ranked.first;
      return _accept(
        primary,
        _keyFor(primary),
        _riskFor(primary),
        AlertPriority.userInitiated,
        AlertReason.forced,
        now,
        preemptEligible: false,
      );
    }

    // Only a candidate that independently qualifies (new identity, or a risk
    // escalation for that identity) may be announced. A suppressed primary
    // never causes a lower-risk substitute to be announced on its own.
    for (final candidate in ranked) {
      final key = _keyFor(candidate);
      final state = _liveState(key, now);
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
        );
      }
      if (_escalated(candidate, state, risk, now)) {
        return _accept(
          candidate,
          key,
          risk,
          _priorityFor(candidate, risk),
          AlertReason.riskEscalation,
          now,
          preemptEligible: _preemptEligible(candidate, risk, escalated: true),
          basedOnStartedAt: state.lastStartedAt,
        );
      }
    }

    final primary = ranked.first;
    return _rejection(
      AlertReason.suppressedSameObject,
      _riskFor(primary),
      _keyFor(primary),
      now,
      primary.info,
      trackId: primary.track?.trackId,
      height: _heightOf(primary),
    );
  }

  /// Phase 2 (confirmed start): the only writer of suppression history.
  void commitStarted(AlertDecision decision, DateTime startedAt) {
    if (!decision.announce) return;
    _states[decision.suppressionKey] = _KeyState(
      lastStartedAt: startedAt,
      lastRisk: decision.risk,
      lastHeight: decision.height,
      lastMotion: decision.motion,
      lastProximity: decision.proximity,
      wasCentre: decision.position == RelativePosition.center,
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

    final state = _liveState(decision.suppressionKey, now);
    if (state == null) return true;
    if (state.lastStartedAt == decision.basedOnStartedAt) return true;
    return _escalationOver(decision, state);
  }

  /// Drops accepted-alert state older than [stateTtl].
  void pruneExpired(DateTime now) => _pruneExpired(now);

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

  String _keyFor(RankedCandidate candidate) => candidate.track != null
      ? 'track:${candidate.track!.trackId}'
      : 'label:${candidate.info.label}';

  RiskLevel _riskFor(RankedCandidate candidate) {
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
    if (risk == RiskLevel.imminent) return AlertPriority.imminent;
    if (risk == RiskLevel.high ||
        candidate.info.priority == ObjectPriority.high) {
      return AlertPriority.urgentEscalation;
    }
    return AlertPriority.normal;
  }

  /// Preemption is limited to imminent risk, or an escalation to approaching
  /// for a high-priority object in the near band or centre corridor.
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

  bool _escalated(
    RankedCandidate candidate,
    _KeyState state,
    RiskLevel risk,
    DateTime now,
  ) {
    if (now.difference(state.lastStartedAt) < minEscalationGap) return false;
    if (risk.index > state.lastRisk.index) return true;
    if (candidate.track?.motion == MotionState.approaching &&
        state.lastMotion != MotionState.approaching) {
      return true;
    }
    final height = _heightOf(candidate);
    if (state.lastHeight > 0 &&
        height > state.lastHeight * (1 + heightGrowthThreshold)) {
      return true;
    }
    return candidate.info.position == RelativePosition.center &&
        !state.wasCentre;
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
  }) {
    final urgent = priority.index >= AlertPriority.urgentEscalation.index;
    final text = urgent
        ? summary.urgentAlert(candidate.info, track: candidate.track)
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

  const _KeyState({
    required this.lastStartedAt,
    required this.lastRisk,
    required this.lastHeight,
    required this.lastMotion,
    required this.lastProximity,
    required this.wasCentre,
  });
}
