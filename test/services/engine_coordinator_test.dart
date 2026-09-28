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
      fallbackAvailable: true,
    );
  }

  test(
    'eligible Ultralytics failure falls back once without changing preference',
    () {
      final telemetry = TelemetryService(clock: () => timestamp);
      final coordinator = EngineCoordinator(
        preferredEngine: InferenceEngine.ultralytics,
        telemetry: telemetry,
      );

      expect(coordinator.reportFailure(failure()), isTrue);
      expect(coordinator.preferredEngine, InferenceEngine.ultralytics);
      expect(coordinator.activeEngine, InferenceEngine.custom);
      expect(coordinator.state, DetectionRuntimeState.fallback);
      expect(coordinator.selection.isTemporaryFallback, isTrue);
      expect(telemetry.fallbacks, hasLength(1));

      expect(coordinator.reportFailure(failure()), isFalse);
      expect(coordinator.state, DetectionRuntimeState.failed);
    },
  );

  test('permission denial never switches engines', () {
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

  test('explicit retry remounts the preferred engine', () {
    final coordinator = EngineCoordinator(
      preferredEngine: InferenceEngine.ultralytics,
    );
    coordinator.reportFailure(failure());
    final generation = coordinator.mountGeneration;

    expect(coordinator.retryPreferred(), isTrue);
    expect(coordinator.activeEngine, InferenceEngine.ultralytics);
    expect(coordinator.mountGeneration, greaterThan(generation));
    expect(coordinator.state, DetectionRuntimeState.startingCamera);
  });

  test('explicit preference changes reset temporary fallback state', () {
    final coordinator = EngineCoordinator(
      preferredEngine: InferenceEngine.ultralytics,
    );
    coordinator.reportFailure(failure());

    coordinator.setPreferredEngine(InferenceEngine.custom);
    expect(coordinator.preferredEngine, InferenceEngine.custom);
    expect(coordinator.activeEngine, InferenceEngine.custom);
    expect(coordinator.selection.isTemporaryFallback, isFalse);
    expect(coordinator.selection.canRetryPreferred, isFalse);
  });

  test('callbacks from an old mount generation are ignored', () {
    final coordinator = EngineCoordinator(
      preferredEngine: InferenceEngine.ultralytics,
    );
    final initialGeneration = coordinator.mountGeneration;

    expect(
      coordinator.reportFailure(failure(), generation: initialGeneration),
      isTrue,
    );
    final fallbackGeneration = coordinator.mountGeneration;
    expect(fallbackGeneration, greaterThan(initialGeneration));

    coordinator.reportReady(generation: initialGeneration);
    expect(coordinator.state, DetectionRuntimeState.fallback);
    expect(coordinator.activeEngine, InferenceEngine.custom);

    expect(coordinator.retryPreferred(), isTrue);
    final retryGeneration = coordinator.mountGeneration;
    expect(retryGeneration, greaterThan(fallbackGeneration));

    coordinator.reportFailure(failure(), generation: fallbackGeneration);
    expect(coordinator.state, DetectionRuntimeState.startingCamera);

    coordinator.reportReady(generation: retryGeneration);
    expect(coordinator.state, DetectionRuntimeState.ready);
  });

  test('older Custom worker generations cannot update the current mount', () {
    final coordinator = EngineCoordinator(
      preferredEngine: InferenceEngine.custom,
    );
    final mountGeneration = coordinator.mountGeneration;

    coordinator.reportState(
      DetectionRuntimeState.recovering,
      generation: mountGeneration,
      sourceGeneration: 4,
    );
    coordinator.reportReady(generation: mountGeneration, sourceGeneration: 5);
    expect(coordinator.state, DetectionRuntimeState.ready);

    coordinator.reportState(
      DetectionRuntimeState.recovering,
      generation: mountGeneration,
      sourceGeneration: 4,
    );
    expect(coordinator.state, DetectionRuntimeState.ready);

    expect(
      coordinator.reportFailure(
        failure(),
        generation: mountGeneration,
        sourceGeneration: 4,
      ),
      isFalse,
    );
    expect(coordinator.state, DetectionRuntimeState.ready);
  });

  test('worker generation is scoped to its mounted child generation', () {
    final coordinator = EngineCoordinator(
      preferredEngine: InferenceEngine.custom,
    );
    final oldMount = coordinator.mountGeneration;

    coordinator.reportReady(generation: oldMount, sourceGeneration: 9);
    expect(coordinator.restartActiveEngine(), isTrue);
    final newMount = coordinator.mountGeneration;

    // A new worker starts its own generation sequence after a remount. The
    // lower value must be accepted rather than compared with the old mount.
    coordinator.reportState(
      DetectionRuntimeState.loadingModel,
      generation: newMount,
      sourceGeneration: 0,
    );
    expect(coordinator.state, DetectionRuntimeState.loadingModel);
  });

  group('start intent', () {
    test(
      'a silent launch intent is observable by the first mounted engine',
      () {
        final coordinator = EngineCoordinator(
          preferredEngine: InferenceEngine.ultralytics,
        );
        expect(coordinator.pendingStartIntent, isNull);

        final intent = coordinator.requestStart(StartIntentOrigin.launch);
        expect(intent.origin, StartIntentOrigin.launch);
        expect(coordinator.pendingStartIntent?.token, intent.token);
      },
    );

    test('one manual entry request is observable when the state is idle', () {
      final coordinator = EngineCoordinator(
        preferredEngine: InferenceEngine.custom,
      );
      expect(coordinator.acceptsEntryStart, isTrue);

      final intent = coordinator.requestEntryStartIfIdle();
      expect(intent, isNotNull);
      expect(intent!.origin, StartIntentOrigin.entry);
    });

    test('start-intent tokens are monotonic', () {
      final coordinator = EngineCoordinator(
        preferredEngine: InferenceEngine.custom,
      );
      final first = coordinator.requestStart(StartIntentOrigin.launch);
      final second = coordinator.requestStart(StartIntentOrigin.entry);
      expect(second.token, greaterThan(first.token));
      expect(coordinator.pendingStartIntent?.token, second.token);
    });

    test('navigation into busy, ready, fallback, paused, stopped, and failed '
        'state does not create a second automatic request', () {
      for (final state in const [
        DetectionRuntimeState.requestingPermission,
        DetectionRuntimeState.startingCamera,
        DetectionRuntimeState.loadingModel,
        DetectionRuntimeState.recovering,
        DetectionRuntimeState.ready,
        DetectionRuntimeState.fallback,
        DetectionRuntimeState.paused,
        DetectionRuntimeState.stopped,
        DetectionRuntimeState.failed,
      ]) {
        final coordinator = EngineCoordinator(
          preferredEngine: InferenceEngine.custom,
        );
        coordinator.reportState(state);
        expect(
          coordinator.acceptsEntryStart,
          isFalse,
          reason: 'Entry start must be rejected in $state',
        );
        expect(
          coordinator.requestEntryStartIfIdle(),
          isNull,
          reason: 'No entry intent may be issued in $state',
        );
      }
    });

    test(
      'explicit local transitions do not change the persisted preference',
      () {
        final coordinator = EngineCoordinator(
          preferredEngine: InferenceEngine.custom,
        );
        coordinator.reportPaused();
        expect(coordinator.state, DetectionRuntimeState.paused);
        coordinator.reportReady();
        expect(coordinator.state, DetectionRuntimeState.ready);
        coordinator.reportStopped();
        expect(coordinator.state, DetectionRuntimeState.stopped);
        expect(coordinator.preferredEngine, InferenceEngine.custom);
      },
    );
  });

  group('stopped state', () {
    test('stopped stays distinct from idle and disposed', () {
      final coordinator = EngineCoordinator(
        preferredEngine: InferenceEngine.custom,
      );
      expect(coordinator.state, DetectionRuntimeState.idle);

      coordinator.reportStopped();
      expect(coordinator.state, DetectionRuntimeState.stopped);
      expect(coordinator.state, isNot(DetectionRuntimeState.idle));
      expect(coordinator.state, isNot(DetectionRuntimeState.disposed));

      // A stopped session rejects an automatic entry start.
      expect(coordinator.acceptsEntryStart, isFalse);
    });

    test('coordinator stop publishes stopped, not idle', () {
      final coordinator = EngineCoordinator(
        preferredEngine: InferenceEngine.custom,
      );
      coordinator.reportReady();
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
      for (final state in const [
        DetectionRuntimeState.requestingPermission,
        DetectionRuntimeState.startingCamera,
        DetectionRuntimeState.loadingModel,
        DetectionRuntimeState.recovering,
      ]) {
        expect(
          detectionStatusOutcomeFor(state),
          DetectionStatusOutcome.preparing,
          reason: '$state must map to Preparing',
        );
      }
      expect(
        detectionStatusOutcomeFor(DetectionRuntimeState.ready),
        DetectionStatusOutcome.ready,
      );
      // A healthy temporary fallback is Ready, not a fifth status.
      expect(
        detectionStatusOutcomeFor(DetectionRuntimeState.fallback),
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
