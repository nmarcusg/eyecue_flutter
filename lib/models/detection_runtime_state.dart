import 'app_settings.dart';

/// Lifecycle state shared by both camera/inference engines.
enum DetectionRuntimeState {
  idle,
  requestingPermission,
  startingCamera,
  loadingModel,
  ready,
  paused,
  recovering,
  fallback,
  failed,
  disposed,
}

extension DetectionRuntimeStateX on DetectionRuntimeState {
  String get label => switch (this) {
    DetectionRuntimeState.idle => 'Idle',
    DetectionRuntimeState.requestingPermission => 'Requesting camera access',
    DetectionRuntimeState.startingCamera => 'Starting camera',
    DetectionRuntimeState.loadingModel => 'Loading detection model',
    DetectionRuntimeState.ready => 'Ready',
    DetectionRuntimeState.paused => 'Paused',
    DetectionRuntimeState.recovering => 'Recovering',
    DetectionRuntimeState.fallback => 'Temporary fallback',
    DetectionRuntimeState.failed => 'Detection unavailable',
    DetectionRuntimeState.disposed => 'Stopped',
  };

  bool get isBusy => switch (this) {
    DetectionRuntimeState.requestingPermission ||
    DetectionRuntimeState.startingCamera ||
    DetectionRuntimeState.loadingModel ||
    DetectionRuntimeState.recovering => true,
    _ => false,
  };
}

/// Stable categories used for recovery, fallback policy, and export data.
enum DetectionFailureCategory {
  permissionDenied,
  cameraInitialization,
  cameraBind,
  modelLoading,
  nativeInitialization,
  workerExited,
  inference,
  timeout,
  unavailable,
  unknown,
}

extension DetectionFailureCategoryX on DetectionFailureCategory {
  String get label => switch (this) {
    DetectionFailureCategory.permissionDenied => 'Permission denied',
    DetectionFailureCategory.cameraInitialization => 'Camera initialization',
    DetectionFailureCategory.cameraBind => 'Camera binding',
    DetectionFailureCategory.modelLoading => 'Model loading',
    DetectionFailureCategory.nativeInitialization => 'Engine initialization',
    DetectionFailureCategory.workerExited => 'Inference worker stopped',
    DetectionFailureCategory.inference => 'Inference failure',
    DetectionFailureCategory.timeout => 'Startup timeout',
    DetectionFailureCategory.unavailable => 'Unavailable',
    DetectionFailureCategory.unknown => 'Unknown failure',
  };
}

/// A user-safe failure record. Technical details are retained for logs but are
/// never required to be shown as the primary message in the UI.
class DetectionFailure {
  final DetectionFailureCategory category;
  final String safeMessage;
  final String technicalDetail;
  final bool recoverable;
  final InferenceEngine? engine;
  final int retryCount;
  final DateTime timestamp;
  final bool fallbackAvailable;

  const DetectionFailure({
    required this.category,
    required this.safeMessage,
    this.technicalDetail = '',
    this.recoverable = true,
    this.engine,
    this.retryCount = 0,
    required this.timestamp,
    this.fallbackAvailable = false,
  });

  String get userMessage => safeMessage;

  Map<String, dynamic> toJson() => {
    'category': category.name,
    'safeMessage': safeMessage,
    'technicalDetail': technicalDetail,
    'recoverable': recoverable,
    'engine': engine?.name,
    'retryCount': retryCount,
    'timestamp': timestamp.toUtc().toIso8601String(),
    'fallbackAvailable': fallbackAvailable,
  };

  factory DetectionFailure.fromJson(Map<String, dynamic> json) {
    final categoryName = json['category'];
    final engineName = json['engine'];
    return DetectionFailure(
      category: DetectionFailureCategory.values.firstWhere(
        (value) => value.name == categoryName,
        orElse: () => DetectionFailureCategory.unknown,
      ),
      safeMessage:
          json['safeMessage'] as String? ?? 'Detection is unavailable.',
      technicalDetail: json['technicalDetail'] as String? ?? '',
      recoverable: json['recoverable'] as bool? ?? true,
      engine: engineName is String
          ? InferenceEngine.values.firstWhere(
              (value) => value.name == engineName,
              orElse: () => InferenceEngine.ultralytics,
            )
          : null,
      retryCount: (json['retryCount'] as num?)?.toInt() ?? 0,
      timestamp:
          DateTime.tryParse(json['timestamp'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      fallbackAvailable: json['fallbackAvailable'] as bool? ?? false,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is DetectionFailure &&
      other.category == category &&
      other.safeMessage == safeMessage &&
      other.technicalDetail == technicalDetail &&
      other.recoverable == recoverable &&
      other.engine == engine &&
      other.retryCount == retryCount &&
      other.timestamp == timestamp &&
      other.fallbackAvailable == fallbackAvailable;

  @override
  int get hashCode => Object.hash(
    category,
    safeMessage,
    technicalDetail,
    recoverable,
    engine,
    retryCount,
    timestamp,
    fallbackAvailable,
  );
}

/// Preferred and currently active engine are intentionally separate. A
/// temporary fallback must never mutate the persisted preference.
class EngineRuntimeSelection {
  final InferenceEngine preferredEngine;
  final InferenceEngine activeEngine;
  final String? fallbackReason;
  final bool canRetryPreferred;
  final bool isTemporaryFallback;

  const EngineRuntimeSelection({
    required this.preferredEngine,
    required this.activeEngine,
    this.fallbackReason,
    this.canRetryPreferred = false,
    this.isTemporaryFallback = false,
  });

  Map<String, dynamic> toJson() => {
    'preferredEngine': preferredEngine.name,
    'activeEngine': activeEngine.name,
    'fallbackReason': fallbackReason,
    'canRetryPreferred': canRetryPreferred,
    'isTemporaryFallback': isTemporaryFallback,
  };

  @override
  String toString() =>
      'EngineRuntimeSelection(preferred: ${preferredEngine.name}, '
      'active: ${activeEngine.name}, temporary: $isTemporaryFallback)';
}
