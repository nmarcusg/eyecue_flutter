import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../models/app_settings.dart';
import '../models/detection_info.dart';
import '../models/tracked_detection.dart';
import 'alert_policy.dart';
import 'scene_summary_service.dart';

/// Abstraction over the platform text-to-speech engine so tests can run
/// without the real `flutter_tts` plugin.
///
/// `flutter_tts` provides no utterance identifier. Correlation is therefore a
/// property of strict serialization in [TtsService] (exactly one utterance in
/// flight) plus signal-pair reconciliation, never of callback matching.
abstract class TtsEngine {
  Future<void> init();

  /// Best-effort restart after a stuck platform state.
  Future<void> recover() => init();

  /// Platform result: `1` when the utterance completed, `0` when it was
  /// cancelled or dropped. This never signals "started"; only [onStart] does.
  Future<int> speak(String text);

  Future<void> stop();
  Future<void> dispose();

  // Lifecycle callbacks. Default no-ops keep test doubles small; the real
  // engine overrides them.
  void setStartHandler(VoidCallback? callback) {}
  void setCompletionHandler(VoidCallback? callback) {}
  void setCancelHandler(VoidCallback? callback) {}
  void setErrorHandler(void Function(dynamic error)? handler) {}
}

/// Real TTS engine backed by [FlutterTts] (Android).
class FlutterTtsEngine implements TtsEngine {
  FlutterTtsEngine({this.language = 'en-US'});

  final String language;
  final FlutterTts _tts = FlutterTts();
  bool _initialized = false;

  @override
  void setStartHandler(VoidCallback? callback) {
    _tts.setStartHandler(() => callback?.call());
  }

  @override
  void setCompletionHandler(VoidCallback? callback) {
    _tts.setCompletionHandler(() => callback?.call());
  }

  @override
  void setCancelHandler(VoidCallback? callback) {
    _tts.setCancelHandler(() => callback?.call());
  }

  @override
  void setErrorHandler(void Function(dynamic error)? handler) {
    _tts.setErrorHandler((dynamic message) => handler?.call(message));
  }

  @override
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    await _tts.awaitSpeakCompletion(true);
    await _tts.setLanguage(language);
    await _tts.setSpeechRate(0.5);
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.0);
  }

  @override
  Future<void> recover() async {
    _initialized = false;
    try {
      await _tts.stop();
    } catch (error) {
      debugPrint('[Tts] stop during recovery failed: $error');
    }
    await init();
  }

  @override
  Future<int> speak(String text) async {
    await init();
    final result = await _tts.speak(text);
    return result == 1 ? 1 : 0;
  }

  @override
  Future<void> stop() => _tts.stop();

  @override
  Future<void> dispose() async {
    try {
      await _tts.stop();
    } catch (error) {
      debugPrint('[Tts] stop during dispose failed: $error');
    }
  }
}

/// Lifecycle state of the announcement scheduler.
enum SpeechState {
  idle,
  submitted,
  started,
  completed,
  cancelled,
  dropped,
  failed,
  recovering,
  settling,
}

enum _CancelCause {
  preempted,
  startNotConfirmed,
  completionNotConfirmed,
  reconciliationTimeout,
  engineError,
}

/// Serialized, de-duplicated audio announcements for the assistive UI.
///
/// Design rules (safety-critical):
/// * Exactly one utterance is ever in flight, because the platform gives no
///   utterance identifiers.
/// * [AlertPolicy.decide] is read-only; accepted-alert history is written only
///   from a confirmed start signal.
/// * A single reconciler is the only code path that drains the pending slot and
///   calls [TtsEngine.speak].
/// * After a timeout the engine is recovered and a quiet period quarantines
///   residual callbacks before anything is re-submitted.
class TtsService extends ChangeNotifier {
  TtsService({
    required this.engine,
    DateTime Function()? clock,
    this.announcementCooldown = const Duration(seconds: 3),
    this.sameLabelCooldown = const Duration(seconds: 6),
    this.wayfindingRepeatCooldown = const Duration(seconds: 2),
    this.startConfirmationTimeout = const Duration(milliseconds: 1000),
    this.preemptionConfirmTimeout = const Duration(milliseconds: 250),
    this.reconciliationTimeout = const Duration(milliseconds: 400),
    this.callbackQuietPeriod = const Duration(milliseconds: 300),
    this.maxSettlingDuration = const Duration(milliseconds: 1800),
    this.recoveryTimeout = const Duration(seconds: 2),
    this.preemptionCooldown = const Duration(milliseconds: 1500),
    AlertPolicy? policy,
  }) : _clock = clock ?? DateTime.now,
       policy = policy ?? AlertPolicy(clock: clock ?? DateTime.now);

  final TtsEngine engine;
  final AlertPolicy policy;
  final SceneSummaryService summaryService = const SceneSummaryService();

  /// Minimum gap between accepted non-urgent utterances.
  final Duration announcementCooldown;

  /// Retained for backwards compatibility with callers/tests. Label-based
  /// suppression is no longer used for tracked objects.
  final Duration sameLabelCooldown;

  /// Minimum gap before the same wayfinding phrase is spoken again.
  ///
  /// Wayfinding keeps its own anti-repeat rule so it never shares (or delays)
  /// the Detection announcement cooldown, and it never writes [lastUtterance],
  /// which is the Detection utterance replayed by [repeatLast].
  final Duration wayfindingRepeatCooldown;

  /// Applies only while waiting for the first start signal.
  final Duration startConfirmationTimeout;

  /// Applies while waiting for both cancellation signals.
  final Duration preemptionConfirmTimeout;

  /// Applies when one terminal signal arrived but its partner is missing.
  final Duration reconciliationTimeout;

  /// Quarantine window after `engine.recover()` returns.
  final Duration callbackQuietPeriod;

  /// Hard cap on settling; guarantees recovery cannot wait forever.
  final Duration maxSettlingDuration;

  final Duration recoveryTimeout;
  final Duration preemptionCooldown;

  final DateTime Function() _clock;

  // -- Observable state -------------------------------------------------------
  bool _audioEnabled = true;
  bool get audioEnabled => _audioEnabled;

  String? _lastUtterance;
  String? get lastUtterance => _lastUtterance;

  DetectionInfo? _lastAnnouncedDetection;
  DetectionInfo? get lastAnnouncedDetection => _lastAnnouncedDetection;

  InferenceEngine? _lastAnnouncedEngine;
  InferenceEngine? get lastAnnouncedEngine => _lastAnnouncedEngine;

  SpeechState _state = SpeechState.idle;
  SpeechState get state => _state;

  bool get isSpeaking => _active != null;
  bool get isRecovering => _recovering;
  bool get isSettling => _settling;
  bool get recoveryFailed => _recoveryFailed;
  bool get quietPeriodCapReached => _quietPeriodCapReached;
  int get recoveryAttempts => _recoveryAttempts;
  int get lateCallbackCount => _lateCallbacks;
  int get quarantinedCallbackCount => _quarantinedCallbacks;
  int get callbackOrderViolationCount => _orderViolations;
  int get supersededCount => _superseded;
  int get staleDecisionCount => _staleDecisions;
  int get rejectedAfterRecoveryCount => _rejectedAfterRecovery;
  String? get lastWayfindingPhrase => _lastWayfindingPhrase;

  // -- Scheduler internals ----------------------------------------------------
  _Submission? _active;
  _SpeechRequest? _pending;
  int _nextId = 0;

  bool _recovering = false;
  bool _settling = false;
  bool _recoveryFailed = false;
  bool _quietPeriodCapReached = false;
  int _recoveryAttempts = 0;
  int _lateCallbacks = 0;
  int _quarantinedCallbacks = 0;
  int _orderViolations = 0;
  int _superseded = 0;
  int _staleDecisions = 0;
  int _rejectedAfterRecovery = 0;
  int _postFailureRecoveries = 0;
  static const int _maxPostFailureRecoveries = 1;
  SpeechState? _lastTerminalState;
  bool _disposed = false;

  Timer? _quietTimer;
  Timer? _settleCapTimer;
  DateTime? _lastAnnouncementAt;
  DateTime? _lastPreemptionAt;

  /// Wayfinding anti-repeat state, committed only from a confirmed start and
  /// kept deliberately separate from Detection cooldown/replay state.
  String? _lastWayfindingPhrase;
  DateTime? _lastWayfindingAt;

  bool get _quarantining => _recovering || _settling;

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  Future<void> init() async {
    engine.setStartHandler(_handleStart);
    engine.setCompletionHandler(_handleComplete);
    engine.setCancelHandler(_handleCancel);
    engine.setErrorHandler(_handleError);
    await engine.init();
  }

  void setAudioEnabled(bool value) {
    if (_audioEnabled == value) return;
    _audioEnabled = value;
    notifyListeners();
  }

  /// Speaks a plain message (status, correction confirmation, audio toggle).
  ///
  /// [urgent] messages are user-initiated: they never preempt a safety alert;
  /// they wait in the single pending slot instead.
  Future<bool> speak(String text, {bool urgent = false}) {
    if (!_audioEnabled) return Future<bool>.value(false);
    final now = _clock();
    if (!urgent && _lastAnnouncementAt != null) {
      if (now.difference(_lastAnnouncementAt!) < announcementCooldown) {
        return Future<bool>.value(false);
      }
    }
    return _submit(
      _SpeechRequest(
        text: text,
        priority: urgent ? AlertPriority.userInitiated : AlertPriority.normal,
        createdAt: now,
        validity: const Duration(seconds: 10),
      ),
    );
  }

  /// Best-effort wayfinding speech for primary navigation feedback.
  ///
  /// Wayfinding is advisory, so it is integrated with the serialized scheduler
  /// without ever contending with safety speech:
  /// * accepted only while the scheduler is genuinely idle (no active
  ///   utterance, no parked request, no recovery/settling);
  /// * dropped (`false`) rather than parked behind Detection speech;
  /// * anti-repeat history is committed only from a confirmed start;
  /// * it never writes [lastUtterance] or the Detection cooldown, so
  ///   [repeatLast] keeps replaying the last Detection alert.
  ///
  /// Any incoming Detection/safety announcement may preempt active wayfinding
  /// through the normal serialized stop/cancel/reconcile path.
  Future<bool> speakWayfinding(String phrase) {
    if (_disposed || !_audioEnabled) return Future<bool>.value(false);
    if (_active != null ||
        _pending != null ||
        _quarantining ||
        _recoveryFailed) {
      return Future<bool>.value(false);
    }
    final now = _clock();
    final last = _lastWayfindingAt;
    if (last != null &&
        _lastWayfindingPhrase == phrase &&
        now.difference(last) < wayfindingRepeatCooldown) {
      return Future<bool>.value(false);
    }
    return _submit(
      _SpeechRequest(
        text: phrase,
        priority: AlertPriority.normal,
        createdAt: now,
        validity: const Duration(seconds: 10),
        wayfinding: true,
      ),
    );
  }

  /// Announces the current detection set through the risk policy.
  Future<bool> announceDetections(
    List<DetectionInfo> detections, {
    bool force = false,
    List<TrackedDetection> tracks = const [],
    InferenceEngine? engine,
  }) {
    if (detections.isEmpty) return Future<bool>.value(false);
    final now = _clock();
    final decision = policy.decide(
      detections: detections,
      tracks: tracks,
      now: now,
      audioEnabled: _audioEnabled,
      force: force,
    );
    if (!decision.announce) return Future<bool>.value(false);
    return _submit(
      _SpeechRequest(
        text: decision.text,
        priority: decision.priority,
        createdAt: now,
        validity: decision.validity,
        decision: decision,
        engine: engine,
      ),
    );
  }

  Future<bool> announceQuickScan(
    List<DetectionInfo> detections, {
    List<TrackedDetection> tracks = const [],
  }) {
    if (!_audioEnabled) return Future<bool>.value(false);
    return _submit(
      _SpeechRequest(
        text: summaryService.quickScan(detections, tracks: tracks),
        priority: AlertPriority.userInitiated,
        createdAt: _clock(),
        validity: const Duration(milliseconds: 1500),
      ),
    );
  }

  /// Replays the most recent utterance that actually started.
  Future<bool> repeatLast() {
    final text = _lastUtterance;
    if (text == null || !_audioEnabled) return Future<bool>.value(false);
    return _submit(
      _SpeechRequest(
        text: text,
        priority: AlertPriority.userInitiated,
        createdAt: _clock(),
        validity: const Duration(seconds: 10),
      ),
    );
  }

  Future<void> stop() async {
    final active = _active;
    if (active != null) active.stopRequested = true;
    await engine.stop();
  }

  /// Builds the spoken phrase for one object, e.g.
  /// "Person, high priority obstacle, on your left, approximately near."
  static String buildDetectionUtterance(DetectionInfo info, int totalCount) {
    final sb = StringBuffer(info.label);
    if (info.priority == ObjectPriority.high) {
      sb.write(', high priority obstacle');
    }
    sb.write(', on your ${info.positionLabel}');
    sb.write(', approximately ${info.proximityLabel}');
    if (totalCount > 1) {
      sb.write('. $totalCount objects detected');
    }
    return sb.toString();
  }

  @override
  void dispose() {
    _disposed = true;
    _quietTimer?.cancel();
    _settleCapTimer?.cancel();
    final active = _active;
    if (active != null) _cancelTimers(active);
    final pending = _pending;
    if (pending != null && !pending.done.isCompleted) {
      pending.done.complete(false);
    }
    _pending = null;
    engine.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Submission + arbitration
  // ---------------------------------------------------------------------------

  Future<bool> _submit(_SpeechRequest request) {
    if (_disposed) return Future<bool>.value(false);

    if (_recoveryFailed) {
      // Bounded post-failure policy: only a new imminent safety request may
      // trigger one further recovery attempt. Everything else is rejected
      // immediately so no caller future is ever left pending.
      final canRetry =
          request.priority == AlertPriority.imminent &&
          _postFailureRecoveries < _maxPostFailureRecoveries;
      if (!canRetry) {
        _rejectedAfterRecovery++;
        if (!request.done.isCompleted) request.done.complete(false);
        return request.done.future;
      }
      _postFailureRecoveries++;
      _recoveryFailed = false;
      _recoveryAttempts = 0;
      _offer(request);
      unawaited(_enterRecovery());
      return request.done.future;
    }

    if (_quarantining) {
      _offer(request);
      return request.done.future;
    }

    final active = _active;
    if (active != null) {
      _offer(request);
      if (_shouldPreempt(request, active)) {
        unawaited(_preempt(active));
      }
      return request.done.future;
    }

    _start(request);
    return request.done.future;
  }

  bool _preemptEligible(_SpeechRequest request) =>
      request.decision?.preemptEligible ?? false;

  /// Semantic preemption arbitration.
  ///
  /// Priority alone is insufficient: two distinct obstacles can both be
  /// `imminent`, and the second must not wait behind the first. A strictly
  /// higher priority always wins; at equal `imminent` priority only a
  /// **distinct-track** obstacle that is approaching may preempt, and only when
  /// the active warning is not already an approaching threat. This is not a
  /// general `>=` comparison: identical decisions and same-track repeats never
  /// preempt, and the preemption cooldown still applies.
  bool _shouldPreempt(_SpeechRequest incoming, _Submission active) {
    if (active.preemptionRequested || active.terminal != null) return false;

    // Advisory wayfinding must never delay Detection or safety speech, so any
    // incoming Detection decision may interrupt it. This is a targeted rule,
    // not a general equal-priority comparison.
    if (active.request.wayfinding && incoming.decision != null) return true;

    if (!_preemptEligible(incoming)) return false;

    if (incoming.priority.index > active.priority.index) return true;

    if (incoming.priority != AlertPriority.imminent ||
        active.priority != AlertPriority.imminent) {
      return false;
    }

    final incomingDecision = incoming.decision;
    final activeDecision = active.request.decision;
    if (incomingDecision == null || activeDecision == null) return false;

    if (incomingDecision.suppressionKey == activeDecision.suppressionKey) {
      return false;
    }

    final incomingTrack = incomingDecision.trackId;
    final activeTrack = activeDecision.trackId;
    if (incomingTrack == null ||
        activeTrack == null ||
        incomingTrack == activeTrack) {
      return false;
    }

    if (incomingDecision.motion != MotionState.approaching) return false;
    return activeDecision.motion != MotionState.approaching;
  }

  /// Offers into the single pending slot using the normative rules:
  /// higher priority replaces lower, newest replaces oldest within the same
  /// priority, and lower priority never replaces a higher-priority request.
  void _offer(_SpeechRequest request) {
    final pending = _pending;
    if (pending == null) {
      _pending = request;
      return;
    }
    if (request.priority.index > pending.priority.index) {
      _superseded++;
      if (!pending.done.isCompleted) pending.done.complete(false);
      _pending = request;
      return;
    }
    if (request.priority.index == pending.priority.index) {
      if (!pending.done.isCompleted) pending.done.complete(false);
      _pending = request;
      return;
    }
    _superseded++;
    if (!request.done.isCompleted) request.done.complete(false);
  }

  /// Controlled preemption. The incoming request is already in the pending
  /// slot; this method only stops the active utterance and lets the reconciler
  /// submit the replacement once both cancellation signals are reconciled.
  Future<void> _preempt(_Submission active) async {
    if (active.preemptionRequested || active.terminal != null) return;
    final last = _lastPreemptionAt;
    final now = _clock();
    if (last != null && now.difference(last) < preemptionCooldown) return;
    _lastPreemptionAt = now;
    active.preemptionRequested = true;
    active.stopRequested = true;

    active.preemptionTimer = Timer(preemptionConfirmTimeout, () {
      if (identical(_active, active) && active.terminal == null) {
        _fail(active, _CancelCause.reconciliationTimeout);
      }
    });
    try {
      await engine.stop();
    } catch (error) {
      _fail(active, _CancelCause.engineError);
    }
  }

  void _start(_SpeechRequest request) {
    final submission = _Submission(
      id: ++_nextId,
      request: request,
      submittedAt: _clock(),
    );
    _active = submission;
    _lastTerminalState = null;
    _state = SpeechState.submitted;
    _notify();

    submission.startTimer = Timer(startConfirmationTimeout, () {
      if (identical(_active, submission) &&
          !submission.didStart &&
          submission.terminal == null) {
        _fail(submission, _CancelCause.startNotConfirmed);
      }
    });

    engine
        .speak(request.text)
        .then((value) {
          if (submission.terminal != null) {
            _lateCallbacks++;
            return;
          }
          submission.resultValue = value;
          _reconcile(submission);
        })
        .catchError((Object error) {
          if (submission.terminal == null) {
            _fail(submission, _CancelCause.engineError);
          }
          return 0;
        });
  }

  // ---------------------------------------------------------------------------
  // Lifecycle callbacks (no utterance ids: quarantine while unsettled)
  // ---------------------------------------------------------------------------

  void _handleStart() {
    if (_quarantining) {
      _quarantinedCallbacks++;
      _restartQuietPeriod();
      return;
    }
    final active = _active;
    if (active == null) {
      // A start callback after a dropped or cancelled terminal belongs to an
      // utterance that never (or no longer) owns the engine. It must never
      // resurrect history.
      if (_lastTerminalState == SpeechState.dropped ||
          _lastTerminalState == SpeechState.cancelled) {
        _orderViolations++;
      } else {
        _lateCallbacks++;
      }
      return;
    }
    if (active.terminal != null) {
      _orderViolations++;
      return;
    }
    if (active.didStart) return;

    active.didStart = true;
    active.startedAt = _clock();
    active.startTimer?.cancel();
    active.completionTimer = Timer(
      _completionBudget(active.request.text),
      () => _fail(active, _CancelCause.completionNotConfirmed),
    );

    if (active.request.wayfinding) {
      // Advisory navigation feedback: commit only its own anti-repeat state.
      // It must never touch Detection cooldown/history or repeatLast.
      _lastWayfindingPhrase = active.request.text;
      _lastWayfindingAt = active.startedAt;
    } else {
      final decision = active.request.decision;
      if (decision != null) {
        policy.commitStarted(decision, active.startedAt!);
      }
      // Cooldown is committed only from a confirmed start event.
      if (active.priority == AlertPriority.normal) {
        _lastAnnouncementAt = active.startedAt;
      }
      _lastUtterance = active.request.text;
      if (decision?.target != null) {
        _lastAnnouncedDetection = decision!.target;
        _lastAnnouncedEngine = active.request.engine;
      }
    }
    _recoveryAttempts = 0;
    _postFailureRecoveries = 0;
    _state = SpeechState.started;
    _notify();
    _reconcile(active);
  }

  void _handleComplete() {
    if (_quarantining) {
      _quarantinedCallbacks++;
      _restartQuietPeriod();
      return;
    }
    final active = _active;
    if (active == null || active.terminal != null) {
      _lateCallbacks++;
      return;
    }
    active.onCompleteSeen = true;
    _reconcile(active);
  }

  void _handleCancel() {
    if (_quarantining) {
      _quarantinedCallbacks++;
      _restartQuietPeriod();
      return;
    }
    final active = _active;
    if (active == null || active.terminal != null) {
      _lateCallbacks++;
      return;
    }
    active.onCancelSeen = true;
    _reconcile(active);
  }

  void _handleError(dynamic error) {
    if (_quarantining) {
      _quarantinedCallbacks++;
      _restartQuietPeriod();
      return;
    }
    final active = _active;
    if (active == null || active.terminal != null) {
      _lateCallbacks++;
      return;
    }
    _fail(active, _CancelCause.engineError);
  }

  // ---------------------------------------------------------------------------
  // Reconciliation: the only path that drains the pending slot
  // ---------------------------------------------------------------------------

  void _reconcile(_Submission submission) {
    if (submission.terminal != null) return;
    final result = submission.resultValue;

    // Dropped: the platform refused the submission outright.
    if (result == 0 &&
        !submission.didStart &&
        !submission.stopRequested &&
        !submission.onCancelSeen) {
      _terminal(submission, SpeechState.dropped, null);
      return;
    }

    final completedPair = submission.onCompleteSeen && result == 1;
    final cancelledPair = submission.onCancelSeen && result == 0;

    if (completedPair) {
      _terminal(submission, SpeechState.completed, null);
      return;
    }
    if (cancelledPair) {
      _terminal(
        submission,
        SpeechState.cancelled,
        submission.preemptionRequested
            ? _CancelCause.preempted
            : _CancelCause.engineError,
      );
      return;
    }

    final partial =
        (submission.onCompleteSeen && result == null) ||
        (result == 1 && !submission.onCompleteSeen) ||
        (submission.onCancelSeen && result == null) ||
        (result == 0 && !submission.onCancelSeen);
    if (partial) {
      submission.reconcileTimer ??= Timer(reconciliationTimeout, () {
        if (submission.terminal == null) {
          _fail(submission, _CancelCause.reconciliationTimeout);
        }
      });
    }
  }

  void _terminal(
    _Submission submission,
    SpeechState terminal,
    _CancelCause? cause, {
    bool drain = true,
  }) {
    if (submission.terminal != null) return;
    submission.terminal = terminal;
    submission.finishedAt = _clock();
    _cancelTimers(submission);

    final decision = submission.request.decision;
    if (decision != null) {
      switch (terminal) {
        case SpeechState.completed:
          policy.commitCompleted(decision, submission.finishedAt!);
        case SpeechState.cancelled:
          policy.commitCancelled(
            decision,
            submission.finishedAt!,
            hadStarted: submission.didStart,
            cause: (cause ?? _CancelCause.engineError).name,
          );
        case SpeechState.failed:
          policy.commitCancelled(
            decision,
            submission.finishedAt!,
            hadStarted: submission.didStart,
            cause: (cause ?? _CancelCause.engineError).name,
          );
        case SpeechState.dropped:
        case SpeechState.idle:
        case SpeechState.submitted:
        case SpeechState.started:
        case SpeechState.recovering:
        case SpeechState.settling:
          break;
      }
    }

    _lastTerminalState = terminal;
    _state = terminal;
    if (identical(_active, submission)) _active = null;
    if (!submission.request.done.isCompleted) {
      submission.request.done.complete(submission.didStart);
    }
    _notify();

    if (drain) _drain();
  }

  void _fail(_Submission submission, _CancelCause cause) {
    if (submission.terminal != null) return;
    _terminal(submission, SpeechState.failed, cause, drain: false);
    unawaited(_enterRecovery());
  }

  void _drain() {
    if (_disposed || _quarantining || _recoveryFailed) return;
    if (_active != null) return;
    final next = _pending;
    if (next == null) {
      if (_state != SpeechState.idle) {
        _state = SpeechState.idle;
        _notify();
      }
      return;
    }
    _pending = null;
    final decision = next.decision;
    if (decision != null && !policy.shouldSpeakPending(decision, _clock())) {
      // Newer accepted state already covers this parked decision; speaking it
      // now would double-announce the same object. A decision that still
      // represents an escalation is retained.
      _staleDecisions++;
      if (!next.done.isCompleted) next.done.complete(false);
      _drain();
      return;
    }
    if (!next.isCurrent(_clock())) {
      _superseded++;
      if (!next.done.isCompleted) next.done.complete(false);
      _drain();
      return;
    }
    _start(next);
  }

  // ---------------------------------------------------------------------------
  // Recovery + quiet period
  // ---------------------------------------------------------------------------

  Future<void> _enterRecovery() async {
    if (_disposed) return;
    if (_recovering || _settling) return;
    if (_recoveryAttempts >= 1) {
      _recoveryFailed = true;
      _state = SpeechState.failed;
      _failPending();
      _notify();
      return;
    }
    _recoveryAttempts++;
    _recovering = true;
    _state = SpeechState.recovering;
    _notify();

    var recovered = false;
    try {
      await engine.recover().timeout(recoveryTimeout);
      recovered = true;
    } catch (error) {
      debugPrint('[Tts] Engine recovery failed: $error');
    }

    if (_disposed) return;

    if (!recovered) {
      _recovering = false;
      _recoveryFailed = true;
      _state = SpeechState.failed;
      _failPending();
      _notify();
      return;
    }

    _recovering = false;
    _settling = true;
    _state = SpeechState.settling;
    _quietPeriodCapReached = false;
    _settleCapTimer?.cancel();
    _settleCapTimer = Timer(maxSettlingDuration, () {
      _quietPeriodCapReached = true;
      _finishSettling();
    });
    _restartQuietPeriod();
    _notify();
  }

  void _restartQuietPeriod() {
    if (!_settling) return;
    _quietTimer?.cancel();
    _quietTimer = Timer(callbackQuietPeriod, _finishSettling);
  }

  void _finishSettling() {
    if (!_settling) return;
    _settling = false;
    _quietTimer?.cancel();
    _quietTimer = null;
    _settleCapTimer?.cancel();
    _settleCapTimer = null;
    _state = SpeechState.idle;
    _notify();
    _drain();
  }

  void _failPending() {
    final pending = _pending;
    _pending = null;
    if (pending != null && !pending.done.isCompleted) {
      pending.done.complete(false);
    }
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  Duration _completionBudget(String text) {
    final ms = (2500 + text.length * 60).clamp(3000, 15000);
    return Duration(milliseconds: ms);
  }

  void _cancelTimers(_Submission submission) {
    submission.startTimer?.cancel();
    submission.completionTimer?.cancel();
    submission.reconcileTimer?.cancel();
    submission.preemptionTimer?.cancel();
  }

  void _notify() {
    if (_disposed) return;
    notifyListeners();
  }
}

class _SpeechRequest {
  final String text;
  final AlertPriority priority;
  final DateTime createdAt;
  final Duration validity;
  final AlertDecision? decision;
  final InferenceEngine? engine;

  /// True for advisory navigation feedback. Wayfinding never contributes to
  /// Detection cooldown/history or the repeat-last utterance.
  final bool wayfinding;
  final Completer<bool> done = Completer<bool>();

  _SpeechRequest({
    required this.text,
    required this.priority,
    required this.createdAt,
    required this.validity,
    this.decision,
    this.engine,
    this.wayfinding = false,
  });

  bool isCurrent(DateTime now) => now.difference(createdAt) <= validity;
}

class _Submission {
  final int id;
  final _SpeechRequest request;
  final DateTime submittedAt;

  bool didStart = false;
  bool onCompleteSeen = false;
  bool onCancelSeen = false;
  bool stopRequested = false;
  bool preemptionRequested = false;
  int? resultValue;
  DateTime? startedAt;
  DateTime? finishedAt;
  SpeechState? terminal;

  Timer? startTimer;
  Timer? completionTimer;
  Timer? reconcileTimer;
  Timer? preemptionTimer;

  _Submission({
    required this.id,
    required this.request,
    required this.submittedAt,
  });

  AlertPriority get priority => request.priority;
}
