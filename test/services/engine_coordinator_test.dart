import 'package:eyecue_flutter/models/app_settings.dart';
import 'package:eyecue_flutter/models/detection_runtime_state.dart';
import 'package:eyecue_flutter/services/engine_coordinator.dart';
import 'package:eyecue_flutter/services/telemetry_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final timestamp = DateTime.utc(2026, 1, 1);

  DetectionFailure failure({
    DetectionFailureCategory category =
        DetectionFailureCategory.nativeInitialization,
  }) {
    return DetectionFailure(
      category: category,
      safeMessage: 'The engine could not start.',
      technicalDetail: 'test detail',
      engine: InferenceEngine.ultralytics,
      timestamp: timestamp,
      fallbackAvailable: false,
    );
  }

  test('a failure is surfaced and never switches to a second engine', () {
    final telemetry = TelemetryService(clock: () => timestamp);
    final coordinator = EngineCoordinator(
      preferredEngine: InferenceEngine.ultralytics,
      telemetry: telemetry,
    );

    expect(coordinator.reportFailure(failure()), isFalse);
    expect(coordinator.activeEngine, InferenceEngine.ultralytics);
    expect(coordinator.state, DetectionRuntimeState.failed);
    expect(coordinator.selection.isTemporaryFallback, isFalse);
    expect(telemetry.failures, hasLength(1));
  });

  test('permission denial keeps the single engine and fails', () {
    final coordinator = EngineCoordinator(
      preferredEngine: InferenceEngine.ultralytics,
    );
    final permissionFailure = failure(
      category: DetectionFailureCategory.permissionDenied,
    );

    expect(coordinator.reportFailure(permissionFailure), isFalse);
    expect(coordinator.activeEngine, InferenceEngine.ultralytics);
    expect(coordinator.state, DetectionRuntimeState.failed);
  });

  test('restarting the engine remounts without changing selection', () {
    final coordinator = EngineCoordinator(
      preferredEngine: InferenceEngine.ultralytics,
    );
    final before = coordinator.mountGeneration;

    expect(coordinator.restartActiveEngine(), isTrue);
    expect(coordinator.mountGeneration, before + 1);
    expect(coordinator.activeEngine, InferenceEngine.ultralytics);
    expect(coordinator.state, DetectionRuntimeState.startingCamera);
  });

  test('callbacks from an old mount generation are ignored', () {
    final coordinator = EngineCoordinator(
      preferredEngine: InferenceEngine.ultralytics,
    );
    final staleGeneration = coordinator.mountGeneration;
    coordinator.restartActiveEngine();

    coordinator.reportReady(generation: staleGeneration);
    expect(coordinator.state, isNot(DetectionRuntimeState.ready));

    coordinator.reportReady(generation: coordinator.mountGeneration);
    expect(coordinator.state, DetectionRuntimeState.ready);
  });

  group('start intent', () {
    test('a launch intent is observable exactly once', () {
      final coordinator = EngineCoordinator(
        preferredEngine: InferenceEngine.ultralytics,
      );
      final intent = coordinator.requestStart(StartIntentOrigin.launch);
      expect(coordinator.pendingStartIntent, intent);
      expect(intent.origin, StartIntentOrigin.launch);
    });

    test('one manual entry request is observable when the state is idle', () {
      final coordinator = EngineCoordinator(
        preferredEngine: InferenceEngine.ultralytics,
      );
      final intent = coordinator.requestEntryStartIfIdle();
      expect(intent, isNotNull);
      expect(intent!.origin, StartIntentOrigin.entry);
    });

    test('start-intent tokens are monotonic', () {
      final coordinator = EngineCoordinator(
        preferredEngine: InferenceEngine.ultralytics,
      );
      final first = coordinator.requestStart(StartIntentOrigin.launch);
      final second = coordinator.requestStart(StartIntentOrigin.entry);
      expect(second.token, greaterThan(first.token));
    });

    test('navigation into busy, ready, paused, stopped, and failed states '
        'does not issue an entry start', () {
      for (final state in [
        DetectionRuntimeState.loadingModel,
        DetectionRuntimeState.ready,
        DetectionRuntimeState.paused,
        DetectionRuntimeState.stopped,
        DetectionRuntimeState.failed,
      ]) {
        final coordinator = EngineCoordinator(
          preferredEngine: InferenceEngine.ultralytics,
        );
        coordinator.reportState(state);
        expect(coordinator.requestEntryStartIfIdle(), isNull);
      }
    });
  });

  group('stopped state', () {
    test('stopped stays distinct from idle and disposed', () {
      final coordinator = EngineCoordinator(
        preferredEngine: InferenceEngine.ultralytics,
      );
      coordinator.reportStopped();
      expect(coordinator.state, DetectionRuntimeState.stopped);
      expect(coordinator.state, isNot(DetectionRuntimeState.idle));

      coordinator.disposeCoordinator();
      expect(coordinator.state, DetectionRuntimeState.disposed);
    });

    test('coordinator stop publishes stopped, not idle', () {
      final coordinator = EngineCoordinator(
        preferredEngine: InferenceEngine.ultralytics,
      );
      coordinator.reportState(DetectionRuntimeState.ready);
      coordinator.stop();
      expect(coordinator.state, DetectionRuntimeState.stopped);
    });
  });

  group('shared status mapping', () {
    test('maps every shared state to the five user-facing outcomes', () {
      expect(
        detectionStatusOutcomeFor(DetectionRuntimeState.idle),
        DetectionStatusOutcome.preparing,
      );
      expect(
        detectionStatusOutcomeFor(DetectionRuntimeState.ready),
        DetectionStatusOutcome.ready,
      );
      expect(
        detectionStatusOutcomeFor(DetectionRuntimeState.paused),
        DetectionStatusOutcome.paused,
      );
      expect(
        detectionStatusOutcomeFor(DetectionRuntimeState.stopped),
        DetectionStatusOutcome.stopped,
      );
      expect(
        detectionStatusOutcomeFor(DetectionRuntimeState.failed),
        DetectionStatusOutcome.unavailable,
      );
    });
  });
}
