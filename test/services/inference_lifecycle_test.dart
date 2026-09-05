import 'dart:async';

import 'package:eyecue_flutter/models/detection_runtime_state.dart';
import 'package:eyecue_flutter/models/inference_lifecycle_event.dart';
import 'package:eyecue_flutter/services/inference_worker_lifecycle.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('InferenceWorkerLifecycle', () {
    test('a worker exit causes exactly one immediate respawn', () async {
      final harness = _LifecycleHarness();

      await harness.lifecycle.start();
      expect(harness.spawnedGenerations, [1]);

      harness.lifecycle.reportWorkerExit(1, harness.failure());
      // A port error and an exit notification can both describe the same
      // failure. The generation is invalidated before cleanup completes, so
      // the duplicate must not schedule a second replacement.
      harness.lifecycle.reportWorkerExit(1, harness.failure());
      await harness.flushAsyncWork();

      expect(
        harness.eventsOf(InferenceLifecycleEventType.recovering),
        hasLength(1),
      );
      expect(harness.restartTimers, hasLength(1));
      expect(harness.restartTimers.single.duration, Duration.zero);

      harness.fireRestart(Duration.zero);
      await harness.flushAsyncWork();

      expect(harness.spawnedGenerations, [1, 2]);
      expect(harness.lifecycle.activeGeneration, 2);
    });

    test(
      'late results and errors from an old generation are ignored',
      () async {
        final harness = _LifecycleHarness();
        await harness.lifecycle.start();

        harness.lifecycle.reportWorkerExit(1, harness.failure());
        await harness.flushAsyncWork();
        harness.fireRestart(Duration.zero);
        await harness.flushAsyncWork();

        expect(harness.lifecycle.activeGeneration, 2);
        expect(harness.lifecycle.acceptsGeneration(1), isFalse);
        expect(harness.lifecycle.acceptsGeneration(2), isTrue);

        harness.lifecycle.reportWorkerReady(1);
        harness.lifecycle.reportModelLoaded(1);
        harness.lifecycle.reportTransientError(1, harness.failure());
        harness.lifecycle.reportWorkerExit(1, harness.failure());

        expect(
          harness.events,
          isNot(
            contains(
              predicate<InferenceLifecycleEvent>(
                (event) =>
                    event.generation == 1 &&
                    event.type != InferenceLifecycleEventType.recovering,
              ),
            ),
          ),
        );
        expect(
          harness.eventsOf(InferenceLifecycleEventType.recovering),
          hasLength(1),
        );
      },
    );

    test('recovery releases the busy gate before scheduling a retry', () async {
      var busy = true;
      bool? busyWhenRecovering;
      final harness = _LifecycleHarness(
        onEvent: (event) {
          if (event.type == InferenceLifecycleEventType.recovering) {
            busyWhenRecovering = busy;
            busy = false;
          }
        },
      );

      await harness.lifecycle.start();
      harness.lifecycle.reportWorkerExit(1, harness.failure());

      expect(busyWhenRecovering, isTrue);
      expect(busy, isFalse);
      expect(harness.spawnedGenerations, [1]);

      await harness.flushAsyncWork();
      expect(harness.restartTimers.single.duration, Duration.zero);
    });

    test(
      'the second restart is delayed after the first restart fails',
      () async {
        final harness = _LifecycleHarness();
        await harness.lifecycle.start();

        harness.lifecycle.reportFailure(harness.failure(), generation: 1);
        await harness.flushAsyncWork();
        harness.fireRestart(Duration.zero);
        await harness.flushAsyncWork();
        expect(harness.spawnedGenerations, [1, 2]);

        harness.lifecycle.reportWorkerExit(2, harness.failure());
        await harness.flushAsyncWork();

        expect(harness.spawnedGenerations, [1, 2]);
        expect(harness.restartTimers, hasLength(1));
        expect(
          harness.restartTimers.single.duration,
          const Duration(milliseconds: 300),
        );

        harness.fireRestart(const Duration(milliseconds: 300));
        await harness.flushAsyncWork();
        expect(harness.spawnedGenerations, [1, 2, 3]);
      },
    );

    test('two failed restarts terminate without an infinite loop', () async {
      final harness = _LifecycleHarness(
        spawnFailures: {2: harnessFailure(), 3: harnessFailure()},
      );
      await harness.lifecycle.start();

      harness.lifecycle.reportWorkerExit(1, harness.failure());
      await harness.flushAsyncWork();
      harness.fireRestart(Duration.zero);
      await harness.flushAsyncWork();

      expect(harness.spawnedGenerations, [1, 2]);
      expect(
        harness.restartTimers.single.duration,
        const Duration(milliseconds: 300),
      );

      harness.fireRestart(const Duration(milliseconds: 300));
      await harness.flushAsyncWork();

      expect(harness.spawnedGenerations, [1, 2, 3]);
      expect(
        harness.eventsOf(InferenceLifecycleEventType.terminalFailure),
        hasLength(1),
      );
      expect(harness.restartTimers, isEmpty);

      // Firing every remaining timer and flushing async work must not create a
      // fourth generation after the retry budget is exhausted.
      harness.fireAllTimers();
      await harness.flushAsyncWork();
      expect(harness.spawnedGenerations, [1, 2, 3]);
    });

    test('dispose during backoff prevents the scheduled restart', () async {
      final harness = _LifecycleHarness();
      await harness.lifecycle.start();
      harness.lifecycle.reportFailure(harness.failure(), generation: 1);
      await harness.flushAsyncWork();
      expect(harness.restartTimers.single.duration, Duration.zero);

      harness.fireRestart(Duration.zero);
      await harness.flushAsyncWork();
      harness.lifecycle.reportWorkerExit(2, harness.failure());
      await harness.flushAsyncWork();
      expect(
        harness.restartTimers.single.duration,
        const Duration(milliseconds: 300),
      );

      harness.lifecycle.dispose();
      harness.fireAllTimers();
      await harness.flushAsyncWork();

      expect(harness.spawnedGenerations, [1, 2]);
      expect(harness.lifecycle.isDisposed, isTrue);
      expect(harness.lifecycle.activeGeneration, isNull);
      expect(
        harness.eventsOf(InferenceLifecycleEventType.disposed),
        hasLength(1),
      );
    });

    test(
      'successful replacement returns to ready and healthy operation resets budget',
      () async {
        var state = DetectionRuntimeState.idle;
        final harness = _LifecycleHarness(
          onEvent: (event) {
            switch (event.type) {
              case InferenceLifecycleEventType.recovering:
                state = DetectionRuntimeState.recovering;
              case InferenceLifecycleEventType.recoverySucceeded:
                state = DetectionRuntimeState.ready;
              default:
                break;
            }
          },
        );
        await harness.lifecycle.start();

        harness.lifecycle.reportWorkerExit(1, harness.failure());
        await harness.flushAsyncWork();
        harness.fireRestart(Duration.zero);
        await harness.flushAsyncWork();
        expect(harness.lifecycle.automaticRestartCount, 1);

        harness.lifecycle.reportModelLoaded(2);
        expect(state, DetectionRuntimeState.ready);
        expect(
          harness.eventsOf(InferenceLifecycleEventType.recoverySucceeded),
          hasLength(1),
        );

        harness.fireHealthyReset();
        expect(harness.lifecycle.automaticRestartCount, 0);

        harness.lifecycle.reportWorkerExit(2, harness.failure());
        expect(
          harness.events
              .where(
                (event) => event.type == InferenceLifecycleEventType.recovering,
              )
              .last
              .restartAttempt,
          1,
        );
      },
    );
  });
}

DetectionFailure harnessFailure() => DetectionFailure(
  category: DetectionFailureCategory.workerExited,
  safeMessage: 'The detection worker stopped unexpectedly.',
  timestamp: DateTime.utc(2026, 1, 1),
);

class _LifecycleHarness {
  _LifecycleHarness({
    Map<int, DetectionFailure>? spawnFailures,
    void Function(InferenceLifecycleEvent event)? onEvent,
  }) : _spawnFailures = spawnFailures ?? <int, DetectionFailure>{} {
    lifecycle = InferenceWorkerLifecycle(
      spawnWorker: (generation) async {
        spawnedGenerations.add(generation);
        return _spawnFailures[generation];
      },
      stopWorker: () async {
        stopCount++;
      },
      onEvent: (event) {
        events.add(event);
        onEvent?.call(event);
      },
      createTimer: (duration, callback) {
        final timer = _TestTimer(duration, callback);
        timers.add(timer);
        return timer;
      },
    );
  }

  final Map<int, DetectionFailure> _spawnFailures;
  late final InferenceWorkerLifecycle lifecycle;
  final List<int> spawnedGenerations = <int>[];
  final List<InferenceLifecycleEvent> events = <InferenceLifecycleEvent>[];
  final List<_TestTimer> timers = <_TestTimer>[];
  int stopCount = 0;

  DetectionFailure failure() => harnessFailure();

  List<_TestTimer> get restartTimers => timers
      .where(
        (timer) =>
            timer.isActive &&
            timer.duration <= const Duration(milliseconds: 300),
      )
      .toList();

  List<InferenceLifecycleEvent> eventsOf(InferenceLifecycleEventType type) =>
      events.where((event) => event.type == type).toList();

  void fireRestart(Duration duration) {
    final timer = timers.firstWhere(
      (candidate) => candidate.isActive && candidate.duration == duration,
    );
    timer.fire();
  }

  void fireHealthyReset() {
    final timer = timers.firstWhere(
      (candidate) =>
          candidate.isActive &&
          candidate.duration == const Duration(seconds: 10),
    );
    timer.fire();
  }

  void fireAllTimers() {
    for (final timer in timers.toList()) {
      timer.fire();
    }
  }

  Future<void> flushAsyncWork() async {
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
  }
}

class _TestTimer implements Timer {
  _TestTimer(this.duration, this._callback);

  final Duration duration;
  final void Function() _callback;
  bool _cancelled = false;
  bool _fired = false;

  @override
  void cancel() => _cancelled = true;

  @override
  bool get isActive => !_cancelled && !_fired;

  @override
  int get tick => _fired ? 1 : 0;

  void fire() {
    if (!isActive) return;
    _fired = true;
    _callback();
  }
}
