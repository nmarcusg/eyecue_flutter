// The callback fields intentionally use explicit assignments in the public
// constructor: their private names keep the worker adapter encapsulated while
// still allowing tests to inject a deterministic harness.
// ignore_for_file: prefer_initializing_formals

import 'dart:async';

import '../models/detection_runtime_state.dart';
import '../models/inference_lifecycle_event.dart';
import '../models/inference_recovery_policy.dart';

/// Starts a worker for a reserved generation and returns a typed startup
/// failure when the worker could not be created.
typedef InferenceWorkerSpawner =
    Future<DetectionFailure?> Function(int generation);

/// Stops the currently active worker and releases its ports/resources.
typedef InferenceWorkerStopper = Future<void> Function();

/// Receives lifecycle events in the same order in which the runtime publishes
/// them to the UI and telemetry layers.
typedef InferenceLifecycleEventSink =
    void Function(InferenceLifecycleEvent event);

/// A timer factory makes the retry state machine deterministic in tests while
/// the production service continues to use Dart's normal [Timer].
typedef InferenceLifecycleTimerFactory =
    Timer Function(Duration duration, void Function() callback);

/// Coordinates Custom worker generations and bounded recovery.
///
/// This class deliberately knows nothing about camera frames, ports, or the
/// native interpreter. The production [InferenceService] supplies those
/// operations through [spawnWorker] and [stopWorker], while tests can provide
/// an in-memory worker harness and a deterministic timer factory.
class InferenceWorkerLifecycle {
  InferenceWorkerLifecycle({
    required InferenceWorkerSpawner spawnWorker,
    required InferenceWorkerStopper stopWorker,
    required InferenceLifecycleEventSink onEvent,
    InferenceRecoveryPolicy recoveryPolicy = const InferenceRecoveryPolicy(),
    InferenceLifecycleTimerFactory? createTimer,
  }) : _spawnWorker = spawnWorker,
       _stopWorker = stopWorker,
       _onEvent = onEvent,
       _recoveryPolicy = recoveryPolicy,
       _createTimer = createTimer ?? _defaultTimer;

  final InferenceWorkerSpawner _spawnWorker;
  final InferenceWorkerStopper _stopWorker;
  final InferenceLifecycleEventSink _onEvent;
  final InferenceRecoveryPolicy _recoveryPolicy;
  final InferenceLifecycleTimerFactory _createTimer;

  int _generationCounter = 0;
  int? _activeGeneration;
  Timer? _restartTimer;
  Timer? _healthyTimer;
  bool _disposed = false;
  bool _recoveryPending = false;
  int? _recoveryGeneration;
  int _automaticRestartCount = 0;

  int get generationCounter => _generationCounter;
  int? get activeGeneration => _activeGeneration;
  int get automaticRestartCount => _automaticRestartCount;
  bool get isDisposed => _disposed;
  bool get recoveryPending => _recoveryPending;

  /// Returns true only for messages produced by the currently active worker.
  ///
  /// Result, error, and exit listeners should all use this gate before
  /// mutating service state. It also makes late-message behavior directly
  /// testable without exposing the worker ports.
  bool acceptsGeneration(int generation) =>
      !_disposed && _activeGeneration == generation;

  /// Announces startup and starts the next worker generation.
  Future<void> start({bool emitStarting = true}) async {
    if (_disposed) return;
    if (emitStarting) {
      _emit(
        InferenceLifecycleEvent(
          type: InferenceLifecycleEventType.starting,
          generation: _generationCounter,
        ),
      );
    }
    await _stopCurrentWorker();
    if (_disposed) return;
    await _spawnNextWorker();
  }

  /// Clears automatic-recovery state and stops the current worker before an
  /// explicit user-requested initialization retry.
  Future<void> resetForExplicitRetry() async {
    if (_disposed) return;
    _restartTimer?.cancel();
    _healthyTimer?.cancel();
    _restartTimer = null;
    _healthyTimer = null;
    _recoveryPending = false;
    _recoveryGeneration = null;
    _automaticRestartCount = 0;
    await _stopCurrentWorker();
  }

  void reportWorkerReady(int generation) {
    if (!acceptsGeneration(generation)) return;
    _emit(
      InferenceLifecycleEvent(
        type: InferenceLifecycleEventType.workerReady,
        generation: generation,
      ),
    );
  }

  /// Reports a completed model load. A model load on a replacement
  /// generation is the point at which recovery is considered successful.
  void reportModelLoaded(int generation) {
    if (!acceptsGeneration(generation)) return;
    _emit(
      InferenceLifecycleEvent(
        type: InferenceLifecycleEventType.modelLoaded,
        generation: generation,
      ),
    );
    if (_recoveryPending && _recoveryGeneration != generation) {
      _recoveryPending = false;
      _recoveryGeneration = null;
      _emit(
        InferenceLifecycleEvent(
          type: InferenceLifecycleEventType.recoverySucceeded,
          generation: generation,
          restartAttempt: _automaticRestartCount,
        ),
      );
    }
    _scheduleHealthyReset(generation);
  }

  void reportTransientError(
    int generation,
    DetectionFailure failure, {
    String? detail,
  }) {
    if (!acceptsGeneration(generation)) return;
    _emit(
      InferenceLifecycleEvent(
        type: InferenceLifecycleEventType.transientError,
        generation: generation,
        failure: failure,
        detail: detail,
      ),
    );
  }

  /// Reports an isolate exit through the same bounded-recovery path as other
  /// fatal worker failures. Keeping this named entry point makes the exit
  /// contract explicit for both the production port listener and tests.
  void reportWorkerExit(int generation, DetectionFailure failure) {
    reportFailure(failure, generation: generation);
  }

  /// Reports a fatal worker/runtime failure. Duplicate notifications for the
  /// same generation are intentionally coalesced while its replacement is
  /// pending.
  void reportFailure(DetectionFailure failure, {required int generation}) {
    if (!acceptsGeneration(generation)) return;
    if (_recoveryPending && _recoveryGeneration == generation) return;

    _recoveryPending = true;
    _recoveryGeneration = generation;
    final decision = _recoveryPolicy.onFailure(
      automaticRestartCount: _automaticRestartCount,
      generation: generation,
    );
    _emit(
      InferenceLifecycleEvent(
        type: InferenceLifecycleEventType.recovering,
        generation: generation,
        restartAttempt: decision.attempt,
        failure: failure,
      ),
    );

    final stop = _stopCurrentWorker();
    if (decision.terminal) {
      stop.whenComplete(() {
        if (_disposed) return;
        _recoveryPending = false;
        _recoveryGeneration = null;
        _emit(
          InferenceLifecycleEvent(
            type: InferenceLifecycleEventType.terminalFailure,
            generation: generation,
            restartAttempt: _automaticRestartCount,
            failure: failure,
          ),
        );
      });
      return;
    }

    _automaticRestartCount = decision.attempt;
    stop.then((_) {
      if (_disposed || !_recoveryPending) return;
      final delay = decision.delay ?? Duration.zero;
      _restartTimer?.cancel();
      _restartTimer = _createTimer(delay, () {
        _restartTimer = null;
        if (_disposed || !_recoveryPending) return;
        unawaited(_spawnNextWorker());
      });
    });
  }

  /// Explicitly emits a terminal failure for startup failures that happen
  /// before any worker generation can be activated, such as model loading.
  void reportTerminalFailure(
    DetectionFailure failure, {
    required int generation,
  }) {
    if (_disposed) return;
    _emit(
      InferenceLifecycleEvent(
        type: InferenceLifecycleEventType.terminalFailure,
        generation: generation,
        restartAttempt: _automaticRestartCount,
        failure: failure,
      ),
    );
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _restartTimer?.cancel();
    _healthyTimer?.cancel();
    _restartTimer = null;
    _healthyTimer = null;
    _recoveryPending = false;
    _recoveryGeneration = null;
    _activeGeneration = null;
    unawaited(_stopWorker());
    _emit(
      InferenceLifecycleEvent(
        type: InferenceLifecycleEventType.disposed,
        generation: _generationCounter,
      ),
    );
  }

  Future<void> _stopCurrentWorker() async {
    // Invalidate before awaiting resource cleanup. This is the critical stale
    // message barrier: a late callback cannot start another recovery.
    _activeGeneration = null;
    await _stopWorker();
  }

  Future<void> _spawnNextWorker() async {
    if (_disposed) return;
    final generation = ++_generationCounter;
    _activeGeneration = generation;
    final failure = await _spawnWorker(generation);
    if (failure != null && acceptsGeneration(generation)) {
      reportFailure(failure, generation: generation);
    }
  }

  void _scheduleHealthyReset(int generation) {
    _healthyTimer?.cancel();
    _healthyTimer = _createTimer(_recoveryPolicy.healthyResetDuration, () {
      _healthyTimer = null;
      if (_disposed ||
          !_recoveryPolicy.canResetHealthy(
            activeGeneration: _activeGeneration ?? -1,
            eventGeneration: generation,
          )) {
        return;
      }
      _automaticRestartCount = 0;
    });
  }

  void _emit(InferenceLifecycleEvent event) => _onEvent(event);

  static Timer _defaultTimer(Duration duration, void Function() callback) =>
      Timer(duration, callback);
}
