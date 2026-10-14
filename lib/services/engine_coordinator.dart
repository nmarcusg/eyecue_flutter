import 'package:flutter/foundation.dart';

import '../models/app_settings.dart';
import '../models/detection_runtime_state.dart';
import 'telemetry_service.dart';

/// The five user-facing Detection lifecycle outcomes.
///
/// Home, Custom Detection, and Ultralytics Detection all select one of these
/// from the same coordinator snapshot. This is presentation logic, not a second
/// lifecycle model: no renderer may read `autoStartDetection`, local camera
/// booleans, engine-specific flags, or detection results to choose one.
enum DetectionStatusOutcome { preparing, ready, paused, stopped, unavailable }

/// Maps a shared [DetectionRuntimeState] to the single user-facing outcome.
///
/// A healthy temporary [DetectionRuntimeState.fallback] maps to [ready] because
/// it represents an active engine that reached healthy readiness; it is not a
/// fifth status. [DetectionRuntimeState.disposed] has no user-visible mapping
/// during normal retained-session operation and is treated as [preparing] only
/// so the mapping stays total; no status surface is expected to observe it.
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

/// A one-shot, monotonic request to start the currently selected engine.
///
/// The coordinator owns the token; a mounted engine consumes it exactly once
/// by matching [token] against the value it last consumed. This prevents a
/// pre-mount request from being lost and lets each engine ignore an
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

/// Coordinates the selected engine without changing the persisted setting.
///
/// Ultralytics is the recommended engine. A terminal failure in that engine may
/// activate Custom once for the current session, while permission denial is
/// kept as a user decision and never triggers an engine switch. The coordinator
/// is intentionally independent of camera objects; screens report lifecycle
/// events and are mounted/unmounted by [EngineDetectionScreen].
///
/// The coordinator is the single user-facing Detection lifecycle/status source
/// for Home, Custom Detection, and Ultralytics Detection. It is owned by the
/// app shell for the shell lifetime and injected into Home and Engine
/// Detection. Engine-local booleans may remain for camera/controller/inference
/// mechanics, but no screen derives visible lifecycle status from them.
class EngineCoordinator extends ChangeNotifier {
  EngineCoordinator({required InferenceEngine preferredEngine, this.telemetry})
    : _preferredEngine = preferredEngine,
      _activeEngine = preferredEngine;

  final TelemetryService? telemetry;

  InferenceEngine _preferredEngine;
  InferenceEngine _activeEngine;
  DetectionRuntimeState _state = DetectionRuntimeState.idle;
  DetectionFailure? _failure;
  String? _fallbackReason;
  bool _canRetryPreferred = false;
  bool _temporaryFallback = false;
  bool _fallbackNoticeVisible = false;
  int _automaticFallbackCount = 0;
  int _mountGeneration = 0;
  final Map<int, int> _latestWorkerGenerationByMount = {};
  bool _disposed = false;

  /// Monotonic counter for issued start intents. Zero means no intent has ever
  /// been issued.
  int _startIntentToken = 0;

  /// The most recently issued start intent, or null when none is pending.
  StartIntent? _pendingStartIntent;

  InferenceEngine get preferredEngine => _preferredEngine;
  InferenceEngine get activeEngine => _activeEngine;
  DetectionRuntimeState get state => _state;
  DetectionFailure? get failure => _failure;
  int get mountGeneration => _mountGeneration;
  bool get fallbackNoticeVisible =>
      _temporaryFallback && _fallbackNoticeVisible;

  /// The most recently issued start intent, or null when none is pending.
  ///
  /// Engines observe this and consume it once by comparing [StartIntent.token]
  /// with the token they last consumed.
  StartIntent? get pendingStartIntent => _pendingStartIntent;

  EngineRuntimeSelection get selection => EngineRuntimeSelection(
    preferredEngine: _preferredEngine,
    activeEngine: _activeEngine,
    fallbackReason: _fallbackReason,
    canRetryPreferred: _canRetryPreferred,
    isTemporaryFallback: _temporaryFallback,
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
  /// entry start. Paused, stopped, busy, ready, fallback, and failed states
  /// reject it: resume, start, retry, and fallback remain explicit
  /// Detection-local actions.
  bool get acceptsEntryStart => _state == DetectionRuntimeState.idle;

  /// Requests an entry start only when the current state is initial idle.
  ///
  /// Returns the issued intent, or null when the state does not accept an
  /// automatic entry start.
  StartIntent? requestEntryStartIfIdle() {
    if (_disposed || !acceptsEntryStart) return null;
    return requestStart(StartIntentOrigin.entry);
  }

  /// Applies an explicit user preference change. This is the only operation
  /// that changes the preferred engine; temporary fallback never does.
  void setPreferredEngine(InferenceEngine engine) {
    if (_disposed || _preferredEngine == engine) return;
    _preferredEngine = engine;
    _activeEngine = engine;
    _automaticFallbackCount = 0;
    _failure = null;
    _fallbackReason = null;
    _canRetryPreferred = false;
    _temporaryFallback = false;
    _fallbackNoticeVisible = false;
    _remount();
    _publish(DetectionRuntimeState.idle);
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
    _publish(
      _temporaryFallback
          ? DetectionRuntimeState.fallback
          : DetectionRuntimeState.ready,
    );
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

  /// Reports a typed failure and returns whether the active engine should be
  /// remounted. The first eligible preferred-Ultralytics failure activates
  /// Custom exactly once.
  bool reportFailure(
    DetectionFailure failure, {
    int? generation,
    int? sourceGeneration,
  }) {
    if (_disposed) return false;
    if (!_acceptsGeneration(generation, sourceGeneration)) return false;
    _failure = failure;
    telemetry?.recordFailure(failure);

    if (failure.category == DetectionFailureCategory.permissionDenied) {
      _canRetryPreferred = failure.recoverable;
      _publish(DetectionRuntimeState.failed);
      return false;
    }

    final canFallback =
        _preferredEngine == InferenceEngine.ultralytics &&
        _activeEngine == InferenceEngine.ultralytics &&
        _automaticFallbackCount == 0 &&
        _isFallbackEligible(failure.category);
    if (canFallback) {
      _automaticFallbackCount++;
      _activeEngine = InferenceEngine.custom;
      _fallbackReason = failure.userMessage;
      _canRetryPreferred = true;
      _temporaryFallback = true;
      _fallbackNoticeVisible = true;
      telemetry?.recordFallback(
        preferredEngine: _preferredEngine,
        activeEngine: _activeEngine,
        reason: failure.userMessage,
      );
      _remount();
      _publish(DetectionRuntimeState.fallback);
      return true;
    }

    _canRetryPreferred = failure.recoverable;
    _publish(DetectionRuntimeState.failed);
    return false;
  }

  /// Explicitly returns to the persisted preferred engine. The caller should
  /// remount the screen; automatic fallback is not attempted again until the
  /// next fresh session or an explicit preference change.
  bool retryPreferred() {
    if (_disposed || !_canRetryPreferred) return false;
    _activeEngine = _preferredEngine;
    _failure = null;
    _fallbackReason = null;
    _canRetryPreferred = false;
    _temporaryFallback = false;
    _fallbackNoticeVisible = false;
    _remount();
    _publish(DetectionRuntimeState.startingCamera);
    return true;
  }

  /// Recreates the active engine without changing the preferred engine or
  /// fallback budget. This is used for settings that are applied to a newly
  /// mounted camera/model instance, such as detection confidence.
  bool restartActiveEngine() {
    if (_disposed) return false;
    _failure = null;
    _remount();
    _publish(
      _temporaryFallback
          ? DetectionRuntimeState.fallback
          : DetectionRuntimeState.startingCamera,
    );
    return true;
  }

  /// Keeps Custom active after the user has acknowledged the fallback.
  bool useCustomForNow() {
    if (_disposed) return false;
    if (_activeEngine == InferenceEngine.custom) {
      _failure = null;
      _canRetryPreferred = true;
      _temporaryFallback = true;
      _fallbackReason ??= 'The recommended engine is unavailable.';
      _fallbackNoticeVisible = false;
      _publish(DetectionRuntimeState.fallback);
      return true;
    }
    _activeEngine = InferenceEngine.custom;
    _failure = null;
    _fallbackReason ??= 'The recommended engine is unavailable.';
    _canRetryPreferred = true;
    _temporaryFallback = true;
    _fallbackNoticeVisible = false;
    _remount();
    _publish(DetectionRuntimeState.fallback);
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

  /// Acknowledges the fallback explanation without changing the active or
  /// persisted engine selection.
  void acknowledgeFallback() {
    if (_disposed || !_fallbackNoticeVisible) return;
    _fallbackNoticeVisible = false;
    notifyListeners();
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

  static bool _isFallbackEligible(DetectionFailureCategory category) =>
      switch (category) {
        DetectionFailureCategory.modelLoading ||
        DetectionFailureCategory.cameraInitialization ||
        DetectionFailureCategory.cameraBind ||
        DetectionFailureCategory.nativeInitialization ||
        DetectionFailureCategory.inference ||
        DetectionFailureCategory.workerExited ||
        DetectionFailureCategory.timeout => true,
        DetectionFailureCategory.permissionDenied ||
        DetectionFailureCategory.unavailable ||
        DetectionFailureCategory.unknown => false,
      };

  void _remount() {
    _mountGeneration++;
    _latestWorkerGenerationByMount.clear();
  }

  /// [generation] identifies the mounted child screen. [sourceGeneration]
  /// identifies a Custom inference worker within that screen. They are
  /// deliberately independent: remounting can reuse worker generation values,
  /// and a worker restart must not be treated as a new child mount.
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
