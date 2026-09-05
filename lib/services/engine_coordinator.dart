import 'package:flutter/foundation.dart';

import '../models/app_settings.dart';
import '../models/detection_runtime_state.dart';
import 'telemetry_service.dart';

/// Coordinates the selected engine without changing the persisted setting.
///
/// Ultralytics is the recommended engine. A terminal failure in that engine may
/// activate Custom once for the current session, while permission denial is
/// kept as a user decision and never triggers an engine switch. The coordinator
/// is intentionally independent of camera objects; screens report lifecycle
/// events and are mounted/unmounted by [EngineDetectionScreen].
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

  InferenceEngine get preferredEngine => _preferredEngine;
  InferenceEngine get activeEngine => _activeEngine;
  DetectionRuntimeState get state => _state;
  DetectionFailure? get failure => _failure;
  int get mountGeneration => _mountGeneration;
  bool get fallbackNoticeVisible =>
      _temporaryFallback && _fallbackNoticeVisible;
  EngineRuntimeSelection get selection => EngineRuntimeSelection(
    preferredEngine: _preferredEngine,
    activeEngine: _activeEngine,
    fallbackReason: _fallbackReason,
    canRetryPreferred: _canRetryPreferred,
    isTemporaryFallback: _temporaryFallback,
  );

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

  void stop() {
    if (_disposed) return;
    _failure = null;
    _publish(DetectionRuntimeState.idle);
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
