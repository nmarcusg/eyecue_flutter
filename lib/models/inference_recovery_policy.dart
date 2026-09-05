/// Pure policy for bounded Custom-worker recovery.
///
/// Keeping the retry decision separate from Isolate/Timer APIs makes the
/// safety contract unit-testable without a camera, native runtime, or model.
class InferenceRecoveryPolicy {
  static const int defaultMaxAutomaticRestarts = 2;
  static const Duration defaultSecondRestartDelay = Duration(milliseconds: 300);
  static const Duration defaultHealthyResetDuration = Duration(seconds: 10);

  final int maxAutomaticRestarts;
  final Duration secondRestartDelay;
  final Duration healthyResetDuration;

  const InferenceRecoveryPolicy({
    this.maxAutomaticRestarts = defaultMaxAutomaticRestarts,
    this.secondRestartDelay = defaultSecondRestartDelay,
    this.healthyResetDuration = defaultHealthyResetDuration,
  });

  RecoveryDecision onFailure({
    required int automaticRestartCount,
    required int generation,
  }) {
    final attempt = automaticRestartCount + 1;
    if (attempt > maxAutomaticRestarts) {
      return RecoveryDecision.terminal(
        generation: generation,
        attempt: attempt,
      );
    }
    return RecoveryDecision.restart(
      generation: generation,
      attempt: attempt,
      delay: attempt == 1 ? Duration.zero : secondRestartDelay,
    );
  }

  bool canResetHealthy({
    required int activeGeneration,
    required int eventGeneration,
  }) => activeGeneration == eventGeneration;
}

class RecoveryDecision {
  final int generation;
  final int attempt;
  final Duration? delay;
  final bool terminal;

  const RecoveryDecision._({
    required this.generation,
    required this.attempt,
    required this.delay,
    required this.terminal,
  });

  const RecoveryDecision.restart({
    required int generation,
    required int attempt,
    required Duration delay,
  }) : this._(
         generation: generation,
         attempt: attempt,
         delay: delay,
         terminal: false,
       );

  const RecoveryDecision.terminal({
    required int generation,
    required int attempt,
  }) : this._(
         generation: generation,
         attempt: attempt,
         delay: null,
         terminal: true,
       );
}
