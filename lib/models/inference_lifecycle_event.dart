import 'app_settings.dart';
import 'detection_runtime_state.dart';

/// Lifecycle events emitted by the Custom inference worker.
///
/// Events carry the worker generation that produced them. Consumers can use
/// that value to ignore late messages from a worker that has already been
/// replaced.
enum InferenceLifecycleEventType {
  starting,
  workerReady,
  modelLoaded,
  transientError,
  workerFailure,
  recovering,
  recoverySucceeded,
  terminalFailure,
  disposed,
}

class InferenceLifecycleEvent {
  final InferenceLifecycleEventType type;
  final int generation;
  final int restartAttempt;
  final DetectionFailure? failure;
  final String? detail;
  final InferenceEngine engine;

  const InferenceLifecycleEvent({
    required this.type,
    required this.generation,
    this.restartAttempt = 0,
    this.failure,
    this.detail,
    this.engine = InferenceEngine.ultralytics,
  });

  bool get isTerminal => type == InferenceLifecycleEventType.terminalFailure;

  Map<String, dynamic> toJson() => {
    'type': type.name,
    'generation': generation,
    'restartAttempt': restartAttempt,
    'failure': failure?.toJson(),
    'detail': detail,
    'engine': engine.name,
  };
}
