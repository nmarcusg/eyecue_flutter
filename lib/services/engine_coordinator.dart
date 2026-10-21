import 'package:flutter/foundation.dart';

import '../models/app_settings.dart';
import '../models/detection_runtime_state.dart';
import 'telemetry_service.dart';

/// The five user-facing Detection lifecycle outcomes.
///
/// Home and the Detection screen select one of these from the same coordinator
/// snapshot. This is presentation logic, not a second lifecycle model: no
/// renderer may read `autoStartDetection`, local camera booleans, engine-specific
/// flags, or detection results to choose one.
enum DetectionStatusOutcome { preparing, ready, paused, stopped, unavailable }

/// Maps a shared [DetectionRuntimeState] to the single user-facing outcome.
///
/// [DetectionRuntimeState.disposed] has no user-visible mapping during normal
/// retained-session operation and is treated as [preparing] only so the mapping
/// stays total; no status surface is expected to observe it.
DetectionStatusOutcome detectionStatusOutcomeFor(DetectionRuntimeState state) =>
    switch (state) {
      DetectionRuntimeState.idle => DetectionStatusOutcome.preparing,
      DetectionRuntimeState.requestingPermission ||
      DetectionRuntimeState.startingCamera ||
      DetectionRuntimeState.loadingModel ||
      DetectionRuntimeState.recovering => DetectionStatusOutcome.preparing,
      DetectionRuntimeState.ready ||
      DetectionRuntimeState.fallback => DetectionStatusOutcome.ready,
      DetectionRuntimeState.paused => DetectionStatusOutcome.paused,
      DetectionRuntimeState.stopped => DetectionStatusOutcome.stopped,
      DetectionRuntimeState.failed => DetectionStatusOutcome.unavailable,
      DetectionRuntimeState.disposed => DetectionStatusOutcome.preparing,
    };

/// The origin of a one-shot start request.
///
/// A silent launch request is issued once at shell startup when the persisted
/// Auto-start preference is on; it must not produce start haptics or speech.
/// A user-entry request is issued when the user intentionally navigates into
/// Detection from the initial [DetectionRuntimeState.idle] state.
enum StartIntentOrigin { launch, entry }

/// A one-shot, monotonic request to start the selected engine.
///
/// The coordinator owns the token; the mounted engine consumes it exactly once
/// by matching [token] against the value it last consumed. This prevents a
/// pre-mount request from being lost and lets the engine ignore an
/// already-consumed request.
class StartIntent {
  const StartIntent({required this.token, required this.origin});

  /// Monotonic token; strictly increases for every issued intent.
  final int token;

  /// Whether this request came from silent launch or intentional user entry.
  final StartIntentOrigin origin;

  @override
  String toString() => 'StartIntent(token: $token, origin: ${origin.name})';
}

/// Owns the single Detection lifecycle/status snapshot for Home and Detection.
///
/// There is one engine, so this is a lifecycle coordinator rather than an
/// engine selector: screens report lifecycle/failure facts and the shell injects
/// the instance into Home and the Detection screen.
class EngineCoordinator extends ChangeNotifier {
  EngineCoordinator({
    InferenceEngine preferredEngine = InferenceEngine.ultralytics,
    this.telemetry,
  }) : _engine = preferredEngine;

  final TelemetryService? telemetry;

  final InferenceEngine _engine;
  DetectionRuntimeState _state = DetectionRuntimeState.idle;
  DetectionFailure? _failure;
  int _mountGeneration = 0;
  final Map<int, int> _latestWorkerGenerationByMount = {};
  bool _disposed = false;

  /// Monotonic counter for issued start intents. Zero means no intent has ever
  /// been issued.
  int _startIntentToken = 0;

  /// The most recently issued start intent, or null when none is pending.
  StartIntent? _pendingStartIntent;

  InferenceEngine get preferredEngine => _engine;
  InferenceEngine get activeEngine => _engine;
  DetectionRuntimeState get state => _state;
  DetectionFailure? get failure => _failure;
  int get mountGeneration => _mountGeneration;

  /// The most recently issued start intent, or null when none is pending.
  StartIntent? get pendingStartIntent => _pendingStartIntent;

  EngineRuntimeSelection get selection => EngineRuntimeSelection(
    preferredEngine: _engine,
    activeEngine: _engine,
    fallbackReason: null,
    canRetryPreferred: false,
    isTemporaryFallback: false,
  );

  /// Issues a one-shot start intent and returns it.
  ///
  /// This is a narrow command handshake, not persistent state. It is used for
  /// the silent launch request (Auto-start ON) and for an intentional entry
  /// into Detection from the initial [DetectionRuntimeState.idle] state.
  StartIntent requestStart(StartIntentOrigin origin) {
    final intent = StartIntent(token: ++_startIntentToken, origin: origin);
    _pendingStartIntent = intent;
    notifyListeners();
    return intent;
  }

  /// Whether an automatic entry start should be issued for the current state.
  ///
  /// Only the initial [DetectionRuntimeState.idle] state accepts an automatic
  /// entry start. Paused, stopped, busy, ready, and failed states reject it:
  /// resume, start, and retry remain explicit Detection-local actions.
  bool get acceptsEntryStart => _state == DetectionRuntimeState.idle;

  /// Requests an entry start only when the current state is initial idle.
  ///
  /// Returns the issued intent, or null when the state does not accept an
  /// automatic entry start.
  StartIntent? requestEntryStartIfIdle() {
    if (_disposed || !acceptsEntryStart) return null;
    return requestStart(StartIntentOrigin.entry);
  }

  void reportState(
    DetectionRuntimeState state, {
    int? generation,
    int? sourceGeneration,
  }) {
    if (_disposed) return;
    if (!_acceptsGeneration(generation, sourceGeneration)) return;
    if (_state == state && state != DetectionRuntimeState.recovering) return;
    _state = state;
    notifyListeners();
  }

  void reportReady({int? generation, int? sourceGeneration}) {
    if (_disposed) return;
    if (!_acceptsGeneration(generation, sourceGeneration)) return;
    _failure = null;
    _publish(DetectionRuntimeState.ready);
  }

  void reportPaused({int? generation, int? sourceGeneration}) => reportState(
    DetectionRuntimeState.paused,
    generation: generation,
    sourceGeneration: sourceGeneration,
  );

  /// Publishes an explicit manual stop.
  ///
  /// This is distinct from [DetectionRuntimeState.idle] (never started) and
  /// [DetectionRuntimeState.disposed] (coordinator teardown). It preserves the
  /// no-auto-restart latch for normal tab leave/return in the retained current
  /// session without writing any setting.
  void reportStopped({int? generation, int? sourceGeneration}) => reportState(
    DetectionRuntimeState.stopped,
    generation: generation,
    sourceGeneration: sourceGeneration,
  );

  /// Reports a typed failure. There is no second engine to fall back to, so the
  /// caller keeps the failure surfaced and retries explicitly.
  bool reportFailure(
    DetectionFailure failure, {
    int? generation,
    int? sourceGeneration,
  }) {
    if (_disposed) return false;
    if (!_acceptsGeneration(generation, sourceGeneration)) return false;
    _failure = failure;
    telemetry?.recordFailure(failure);
    _publish(DetectionRuntimeState.failed);
    return false;
  }

  /// Recreates the active engine without changing the selection. This is used
  /// for settings that are applied to a newly mounted camera/model instance,
  /// such as detection confidence.
  bool restartActiveEngine() {
    if (_disposed) return false;
    _failure = null;
    _remount();
    _publish(DetectionRuntimeState.startingCamera);
    return true;
  }

  /// Publishes an explicit manual stop for the current session.
  ///
  /// This is the coordinator-level stop used by the shell/engines. It is
  /// distinct from [DetectionRuntimeState.idle] so a retained-session tab
  /// leave/return does not auto-restart a deliberately stopped session.
  void stop() {
    if (_disposed) return;
    _failure = null;
    _publish(DetectionRuntimeState.stopped);
  }

  void disposeCoordinator() {
    if (_disposed) return;
    _disposed = true;
    _state = DetectionRuntimeState.disposed;
    super.dispose();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _state = DetectionRuntimeState.disposed;
    super.dispose();
  }

  void _remount() {
    _mountGeneration++;
    _latestWorkerGenerationByMount.clear();
  }

  /// [generation] identifies the mounted child screen. [sourceGeneration]
  /// identifies a native worker within that screen. They are deliberately
  /// independent: remounting can reuse worker generation values, and a worker
  /// restart must not be treated as a new child mount.
  bool _acceptsGeneration(int? generation, int? sourceGeneration) {
    if (generation != null && generation != _mountGeneration) return false;
    if (sourceGeneration == null) return true;

    final mount = generation ?? _mountGeneration;
    final latest = _latestWorkerGenerationByMount[mount];
    if (latest != null && sourceGeneration < latest) return false;
    _latestWorkerGenerationByMount[mount] = sourceGeneration;
    return true;
  }

  void _publish(DetectionRuntimeState next) {
    _state = next;
    notifyListeners();
  }
}
