import 'package:eyecue_flutter/models/inference_recovery_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const policy = InferenceRecoveryPolicy();

  test('restarts immediately on the first failure', () {
    final decision = policy.onFailure(automaticRestartCount: 0, generation: 7);

    expect(decision.terminal, isFalse);
    expect(decision.generation, 7);
    expect(decision.attempt, 1);
    expect(decision.delay, Duration.zero);
  });

  test('delays the second retry and then terminates', () {
    final second = policy.onFailure(automaticRestartCount: 1, generation: 8);
    final terminal = policy.onFailure(automaticRestartCount: 2, generation: 8);

    expect(second.attempt, 2);
    expect(second.delay, const Duration(milliseconds: 300));
    expect(second.terminal, isFalse);
    expect(terminal.attempt, 3);
    expect(terminal.delay, isNull);
    expect(terminal.terminal, isTrue);
  });

  test('healthy reset is generation-safe', () {
    expect(
      policy.canResetHealthy(activeGeneration: 3, eventGeneration: 3),
      isTrue,
    );
    expect(
      policy.canResetHealthy(activeGeneration: 3, eventGeneration: 2),
      isFalse,
    );
  });
}
