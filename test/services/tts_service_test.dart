import 'dart:async';
import 'dart:ui';

import 'package:eyecue_flutter/models/alert_lifecycle.dart';
import 'package:eyecue_flutter/models/app_settings.dart';
import 'package:eyecue_flutter/models/detection.dart';
import 'package:eyecue_flutter/models/detection_info.dart';
import 'package:eyecue_flutter/models/tracked_detection.dart';
import 'package:eyecue_flutter/services/spatial_analysis_service.dart';
import 'package:eyecue_flutter/services/tts_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

enum FakeMode { autoComplete, drop, startOnly, manual }

/// Test double that emulates the platform's signal order.
///
/// `autoComplete` — onStart, onComplete, then result 1.
/// `drop`         — result 0 with no callbacks (the platform refused it).
/// `startOnly`    — onStart, then a pending future resolved by the test.
/// `manual`       — a pending future with no callbacks at all.
class FakeTtsEngine implements TtsEngine {
  final List<String> spoken = [];
  int recoverCalls = 0;
  int stopCalls = 0;
  bool throwOnRecover = false;
  FakeMode mode = FakeMode.autoComplete;

  VoidCallback? _onStart;
  VoidCallback? _onComplete;
  VoidCallback? _onCancel;
  void Function(dynamic)? _onError;
  Completer<int>? _current;

  @override
  Future<void> init() async {}

  @override
  Future<void> recover() async {
    recoverCalls++;
    if (throwOnRecover) throw StateError('recover failed');
  }

  @override
  Future<void> dispose() async {}

  @override
  Future<void> stop() async {
    stopCalls++;
  }

  @override
  void setStartHandler(VoidCallback? callback) => _onStart = callback;

  @override
  void setCompletionHandler(VoidCallback? callback) => _onComplete = callback;

  @override
  void setCancelHandler(VoidCallback? callback) => _onCancel = callback;

  @override
  void setErrorHandler(void Function(dynamic error)? handler) =>
      _onError = handler;

  void emitStart() => _onStart?.call();
  void emitComplete() => _onComplete?.call();
  void emitCancel() => _onCancel?.call();
  void emitError([dynamic error = 'engine error']) => _onError?.call(error);
  void resolveCurrent(int value) => _current?.complete(value);

  @override
  Future<int> speak(String text) {
    spoken.add(text);
    switch (mode) {
      case FakeMode.autoComplete:
        _onStart?.call();
        _onComplete?.call();
        return Future<int>.value(1);
      case FakeMode.drop:
        return Future<int>.value(0);
      case FakeMode.startOnly:
        _onStart?.call();
        return (_current = Completer<int>()).future;
      case FakeMode.manual:
        return (_current = Completer<int>()).future;
    }
  }
}

DetectionInfo info({
  int classId = 0,
  String label = 'person',
  Rect? box,
  double conf = 0.9,
}) {
  return SpatialAnalysisService.analyze(
    Detection(
      classId: classId,
      label: label,
      confidence: conf,
      box: box ?? const Rect.fromLTWH(0.4, 0.2, 0.2, 0.2),
    ),
  );
}

DetectionInfo nearPerson() =>
    info(box: const Rect.fromLTWH(0.3, 0.2, 0.4, 0.5));

TrackedDetection trackOf(
  DetectionInfo source, {
  required int id,
  MotionState motion = MotionState.stable,
}) {
  final detection = source.detection;
  return TrackedDetection(
    detection: detection,
    trackId: id,
    firstSeen: DateTime(2026),
    lastSeen: DateTime(2026),
    smoothedCenter: Offset(detection.box.center.dx, detection.box.center.dy),
    smoothedArea: detection.box.width * detection.box.height,
    smoothedHeight: detection.box.height,
    confidence: detection.confidence,
    hitCount: 3,
    missedUpdateCount: 0,
    motion: motion,
    centerDisplacement: 0,
  );
}

void main() {
  late FakeTtsEngine engine;
  late DateTime now;
  late TtsService tts;

  setUp(() async {
    engine = FakeTtsEngine();
    now = DateTime(2026, 1, 1, 12);
    tts = TtsService(
      engine: engine,
      clock: () => now,
      startConfirmationTimeout: const Duration(milliseconds: 60),
      preemptionConfirmTimeout: const Duration(milliseconds: 40),
      reconciliationTimeout: const Duration(milliseconds: 40),
      callbackQuietPeriod: const Duration(milliseconds: 25),
      maxSettlingDuration: const Duration(milliseconds: 200),
      recoveryTimeout: const Duration(milliseconds: 100),
      preemptionCooldown: Duration.zero,
    );
    await tts.init();
  });

  tearDown(() => tts.dispose());

  group('speak: cooldown only advances on a confirmed start', () {
    test('speaks and reports true on completion', () async {
      expect(await tts.speak('hello'), isTrue);
      expect(engine.spoken, ['hello']);
      expect(tts.isSpeaking, isFalse);
    });

    test('a dropped submission does not advance the cooldown', () async {
      engine.mode = FakeMode.drop;
      expect(await tts.speak('first'), isFalse);
      expect(engine.spoken, ['first']);

      engine.mode = FakeMode.autoComplete;
      expect(await tts.speak('second'), isTrue);
      expect(engine.spoken, ['first', 'second']);
    });

    test('cooldown suppresses a second normal announcement', () async {
      expect(await tts.speak('first'), isTrue);
      expect(await tts.speak('second'), isFalse);
      expect(engine.spoken, ['first']);
    });

    test('user-initiated speech bypasses the normal cooldown', () async {
      expect(await tts.speak('first'), isTrue);
      expect(await tts.speak('urgent', urgent: true), isTrue);
      expect(engine.spoken, ['first', 'urgent']);
    });

    test('muted audio never reaches the engine', () async {
      tts.setAudioEnabled(false);
      expect(await tts.speak('hello'), isFalse);
      expect(engine.spoken, isEmpty);
    });

    test(
      'repeatLast replays the last started utterance after a drop',
      () async {
        expect(await tts.speak('alert'), isTrue);
        engine.mode = FakeMode.drop;
        expect(await tts.speak('ignored'), isFalse);
        engine.mode = FakeMode.autoComplete;
        expect(await tts.repeatLast(), isTrue);
        expect(engine.spoken.last, 'alert');
      },
    );

    test('repeatLast returns false when nothing ever started', () async {
      expect(await tts.repeatLast(), isFalse);
    });
  });

  // Upstream coverage adapted to track-aware suppression and concise urgent
  // phrasing: the original expectations encoded the pre-Workstream-1 policy
  // (label cooldown re-announcement and the long "Alert. ... high priority
  // obstacle ... N objects detected" sentence).
  group('announceDetections upstream-adapted', () {
    test('announces again once the identity state expires', () async {
      final infos = [info(classId: 0, label: 'person')];
      expect(await tts.announceDetections(infos), isTrue);
      now = now.add(const Duration(seconds: 31));
      expect(await tts.announceDetections(infos), isTrue);
      expect(engine.spoken.length, 2);
    });

    test('high-priority primary is chosen and announced concisely', () async {
      final low = info(classId: 79, label: 'toothbrush', conf: 0.99);
      final high = info(
        classId: 0,
        label: 'person',
        box: const Rect.fromLTWH(0.7, 0.1, 0.2, 0.3),
        conf: 0.6,
      );
      expect(await tts.announceDetections([low, high]), isTrue);
      final text = engine.spoken.single;
      expect(text, contains('person'));
      // Urgent safety phrasing is information-first (no long prefix).
      expect(text.startsWith('Alert.'), isFalse);
      expect(text.contains('high priority obstacle'), isFalse);
    });

    test('repeats the last utterance even inside the cooldown', () async {
      await tts.speak('alert');
      now = now.add(const Duration(seconds: 1));
      expect(await tts.repeatLast(), isTrue);
      expect(engine.spoken, ['alert', 'alert']);
    });
  });

  group('speakWayfinding', () {
    test('speaks a wayfinding phrase when idle', () async {
      expect(await tts.speakWayfinding('Settings'), isTrue);
      expect(engine.spoken, ['Settings']);
      expect(tts.lastWayfindingPhrase, 'Settings');
    });

    test('muted audio suppresses wayfinding', () async {
      tts.setAudioEnabled(false);
      expect(await tts.speakWayfinding('Settings'), isFalse);
      expect(engine.spoken, isEmpty);
    });

    test('wayfinding never replaces the Detection replay utterance', () async {
      expect(await tts.speak('person, high priority obstacle'), isTrue);
      now = now.add(const Duration(seconds: 1));
      expect(await tts.speakWayfinding('Settings'), isTrue);
      now = now.add(const Duration(seconds: 1));
      expect(await tts.repeatLast(), isTrue);
      expect(engine.spoken.last, 'person, high priority obstacle');
    });

    test('wayfinding does not arm the Detection cooldown', () async {
      expect(await tts.speakWayfinding('Settings'), isTrue);
      now = now.add(const Duration(milliseconds: 100));
      expect(await tts.speak('person detected'), isTrue);
    });

    test('repeated identical phrases are rate-limited', () async {
      expect(await tts.speakWayfinding('End of navigation'), isTrue);
      now = now.add(const Duration(milliseconds: 500));
      expect(await tts.speakWayfinding('End of navigation'), isFalse);
      now = now.add(const Duration(seconds: 3));
      expect(await tts.speakWayfinding('End of navigation'), isTrue);
    });

    test('a dropped phrase does not arm the anti-repeat rule', () async {
      engine.mode = FakeMode.drop;
      expect(await tts.speakWayfinding('Settings'), isFalse);
      engine.mode = FakeMode.autoComplete;
      expect(await tts.speakWayfinding('Settings'), isTrue);
    });

    test('wayfinding drops while Detection speech is active', () async {
      engine.mode = FakeMode.manual;
      final detection = tts.speak('person detected');
      await pumpEventQueue();
      expect(tts.isSpeaking, isTrue);

      expect(await tts.speakWayfinding('Settings'), isFalse);
      expect(engine.spoken, ['person detected']);

      engine.mode = FakeMode.autoComplete;
      engine.emitStart();
      engine.emitComplete();
      engine.resolveCurrent(1);
      await pumpEventQueue();
      await detection;
    });

    test('a safety alert preempts active wayfinding', () async {
      engine.mode = FakeMode.startOnly;
      final wayfinding = tts.speakWayfinding('Settings');
      await pumpEventQueue();
      expect(engine.spoken, ['Settings']);

      engine.mode = FakeMode.autoComplete;
      final urgent = tts.announceDetections(
        [nearPerson()],
        tracks: [trackOf(nearPerson(), id: 91)],
      );
      await pumpEventQueue();
      expect(engine.stopCalls, 1);

      engine.emitCancel();
      engine.resolveCurrent(0);
      await pumpEventQueue();

      expect(engine.spoken, hasLength(2));
      expect(engine.spoken.last, contains('person'));
      expect(await urgent, isTrue);
      await wayfinding;
    });
  });

  group('arbitration', () {
    test('concurrent requests never overlap and are serialized', () async {
      engine.mode = FakeMode.startOnly;
      final first = tts.speak('first');
      await pumpEventQueue();
      expect(tts.isSpeaking, isTrue);

      final second = tts.speak('second', urgent: true);
      await pumpEventQueue();
      expect(engine.spoken, ['first']);

      engine.mode = FakeMode.autoComplete;
      engine.emitComplete();
      engine.resolveCurrent(1);
      await pumpEventQueue();

      expect(engine.spoken, ['first', 'second']);
      expect(await first, isTrue);
      expect(await second, isTrue);
    });

    test('higher priority replaces a parked lower-priority request', () async {
      engine.mode = FakeMode.startOnly;
      final active = tts.speak('active');
      await pumpEventQueue();

      final parkedLow = tts.speak('low');
      final parkedUrgent = tts.announceDetections(
        [nearPerson()],
        tracks: [trackOf(nearPerson(), id: 1)],
      );
      final rejectedLow = tts.speak('later-low');
      await pumpEventQueue();
      expect(await rejectedLow, isFalse);

      engine.mode = FakeMode.autoComplete;
      engine.emitComplete();
      engine.resolveCurrent(1);
      await pumpEventQueue();

      expect(engine.spoken, hasLength(2));
      expect(engine.spoken.last, contains('person'));
      await active;
      await parkedLow;
      expect(await parkedUrgent, isTrue);
    });

    test(
      'quickScan does not preempt and is played after the active speech',
      () async {
        engine.mode = FakeMode.startOnly;
        final active = tts.speak('status');
        await pumpEventQueue();

        final scan = tts.announceQuickScan([info()]);
        await pumpEventQueue();
        expect(engine.spoken, hasLength(1));
        expect(tts.isSpeaking, isTrue);

        engine.mode = FakeMode.autoComplete;
        engine.emitComplete();
        engine.resolveCurrent(1);
        await pumpEventQueue();

        expect(await scan, isTrue);
        expect(engine.spoken.last, contains('Quick scan'));
        await active;
      },
    );

    test('imminent alert preempts active speech via stop + cancel', () async {
      engine.mode = FakeMode.startOnly;
      final active = tts.speak('status');
      await pumpEventQueue();

      engine.mode = FakeMode.autoComplete;
      final urgent = tts.announceDetections(
        [nearPerson()],
        tracks: [trackOf(nearPerson(), id: 2)],
      );
      await pumpEventQueue();

      // Preemption waits for both cancellation signals.
      expect(engine.spoken, hasLength(1));
      engine.emitCancel();
      engine.resolveCurrent(0);
      await pumpEventQueue();

      expect(engine.spoken, hasLength(2));
      expect(engine.spoken.last, contains('person'));
      expect(await urgent, isTrue);
      await active;
    });

    test(
      'a distinct approaching track preempts an equal-priority warning',
      () async {
        final personA = info(box: const Rect.fromLTWH(0.3, 0.2, 0.4, 0.5));
        final trackA = trackOf(personA, id: 101); // near, stable

        engine.mode = FakeMode.startOnly;
        final active = tts.announceDetections([personA], tracks: [trackA]);
        await pumpEventQueue();
        expect(engine.spoken, hasLength(1));
        expect(tts.isSpeaking, isTrue);

        // A second, distinct obstacle suddenly approaching. Both decisions are
        // AlertPriority.imminent, which previously never preempted.
        final personB = info(box: const Rect.fromLTWH(0.7, 0.2, 0.4, 0.5));
        final trackB = trackOf(
          personB,
          id: 102,
          motion: MotionState.approaching,
        );

        engine.mode = FakeMode.autoComplete;
        final second = tts.announceDetections([personB], tracks: [trackB]);
        await pumpEventQueue();

        // Controlled preemption: the replacement waits for both cancel signals.
        expect(engine.spoken, hasLength(1));
        expect(engine.stopCalls, 1);

        // A repeated frame for the same track arrives after stop was requested
        // but before cancellation is reconciled: no second stop, and only the
        // newest retained request speaks.
        final newest = tts.announceDetections([personB], tracks: [trackB]);
        await pumpEventQueue();
        expect(engine.stopCalls, 1);

        engine.emitCancel();
        engine.resolveCurrent(0);
        await pumpEventQueue();

        expect(engine.spoken, hasLength(2));
        expect(await second, isFalse);
        expect(await newest, isTrue);
        expect(tts.staleDecisionCount, 0);
        expect(tts.policy.hasStateFor('track:101'), isTrue);
        expect(tts.policy.hasStateFor('track:102'), isTrue);

        // Repeated frames for the now-active track never preempt again.
        final repeat = tts.announceDetections([personB], tracks: [trackB]);
        await pumpEventQueue();
        expect(engine.spoken, hasLength(2));
        expect(engine.stopCalls, 1);
        expect(await repeat, isFalse);

        await active;
      },
    );
  });

  group('signal reconciliation', () {
    test('result 0 before onCancel waits for the cancel signal', () async {
      engine.mode = FakeMode.startOnly;
      final active = tts.speak('status');
      await pumpEventQueue();

      engine.mode = FakeMode.autoComplete;
      final next = tts.speak('next', urgent: true);
      await pumpEventQueue();

      engine.resolveCurrent(0);
      await pumpEventQueue();
      expect(engine.spoken, ['status']); // no drain yet

      engine.emitCancel();
      await pumpEventQueue();
      expect(engine.spoken, ['status', 'next']);
      expect(await next, isTrue);
      await active;
    });

    test('onCancel before result 0 waits for the result', () async {
      engine.mode = FakeMode.startOnly;
      final active = tts.speak('status');
      await pumpEventQueue();

      engine.mode = FakeMode.autoComplete;
      final next = tts.speak('next', urgent: true);
      await pumpEventQueue();

      engine.emitCancel();
      await pumpEventQueue();
      expect(engine.spoken, ['status']);

      engine.resolveCurrent(0);
      await pumpEventQueue();
      expect(engine.spoken, ['status', 'next']);
      await next;
      await active;
    });

    test(
      'result 1 before onComplete waits for the completion signal',
      () async {
        engine.mode = FakeMode.manual;
        final active = tts.speak('first');
        await pumpEventQueue();
        engine.emitStart();
        await pumpEventQueue();

        engine.mode = FakeMode.autoComplete;
        final next = tts.speak('next', urgent: true);
        await pumpEventQueue();

        engine.resolveCurrent(1);
        await pumpEventQueue();
        expect(engine.spoken, ['first']);

        engine.emitComplete();
        await pumpEventQueue();
        expect(engine.spoken, ['first', 'next']);
        await next;
        await active;
      },
    );

    test('onComplete before result 1 waits for the result', () async {
      engine.mode = FakeMode.manual;
      final active = tts.speak('first');
      await pumpEventQueue();
      engine.emitStart();
      await pumpEventQueue();

      engine.mode = FakeMode.autoComplete;
      final next = tts.speak('next', urgent: true);
      await pumpEventQueue();

      engine.emitComplete();
      await pumpEventQueue();
      expect(engine.spoken, ['first']);

      engine.resolveCurrent(1);
      await pumpEventQueue();
      expect(engine.spoken, ['first', 'next']);
      await next;
      await active;
    });

    test('late start callback after a drop is an order violation', () async {
      engine.mode = FakeMode.drop;
      expect(await tts.speak('dropped'), isFalse);

      engine.emitStart();
      expect(tts.callbackOrderViolationCount, 1);
      expect(tts.lastUtterance, isNull);
    });
  });

  group('timeouts and recovery', () {
    test('start confirmation timeout fails then recovers to idle', () async {
      engine.mode = FakeMode.manual;
      final pending = tts.speak('silent');
      await pumpEventQueue();
      expect(tts.state, SpeechState.submitted);

      await Future<void>.delayed(const Duration(milliseconds: 250));

      expect(tts.state, SpeechState.idle);
      expect(engine.recoverCalls, 1);
      expect(await pending, isFalse);
    });

    test(
      'a started utterance is not failed by the short start timeout',
      () async {
        engine.mode = FakeMode.startOnly;
        final pending = tts.speak('long utterance');
        await pumpEventQueue();
        expect(tts.state, SpeechState.started);

        await Future<void>.delayed(const Duration(milliseconds: 120));
        expect(tts.state, SpeechState.started);
        expect(engine.recoverCalls, 0);

        engine.mode = FakeMode.autoComplete;
        engine.emitComplete();
        engine.resolveCurrent(1);
        await pumpEventQueue();
        expect(await pending, isTrue);
      },
    );

    test('recovery failure does not retry in a loop', () async {
      engine.throwOnRecover = true;
      engine.mode = FakeMode.manual;
      final pending = tts.speak('silent');
      await pumpEventQueue();

      await Future<void>.delayed(const Duration(milliseconds: 250));

      expect(tts.recoveryFailed, isTrue);
      expect(engine.recoverCalls, 1);
      expect(await pending, isFalse);

      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(engine.recoverCalls, 1);
    });

    test('callbacks during recovery are quarantined', () async {
      final slowEngine = FakeTtsEngine()..mode = FakeMode.manual;
      final slow = TtsService(
        engine: slowEngine,
        clock: () => now,
        startConfirmationTimeout: const Duration(milliseconds: 40),
        callbackQuietPeriod: const Duration(milliseconds: 400),
        maxSettlingDuration: const Duration(milliseconds: 900),
      );
      await slow.init();
      addTearDown(slow.dispose);

      final pending = slow.speak('silent');
      await pumpEventQueue();
      await Future<void>.delayed(const Duration(milliseconds: 80));

      expect(slow.isSettling, isTrue);
      final before = slow.quarantinedCallbackCount;
      slowEngine.emitStart();
      expect(slow.quarantinedCallbackCount, before + 1);

      await Future<void>.delayed(const Duration(milliseconds: 600));
      expect(slow.state, SpeechState.idle);
      expect(await pending, isFalse);
    });
  });

  group('announceDetections policy integration', () {
    test('announces a new object', () async {
      expect(await tts.announceDetections([info()]), isTrue);
      expect(engine.spoken.single, contains('person'));
    });

    test('a stable tracked object is not re-announced', () async {
      final person = info();
      final track = trackOf(person, id: 42);
      expect(await tts.announceDetections([person], tracks: [track]), isTrue);
      now = now.add(const Duration(seconds: 5));
      expect(await tts.announceDetections([person], tracks: [track]), isFalse);
      expect(engine.spoken, hasLength(1));
    });

    test('a different track with the same label is announced', () async {
      final first = info();
      expect(
        await tts.announceDetections([first], tracks: [trackOf(first, id: 1)]),
        isTrue,
      );

      now = now.add(const Duration(seconds: 1));
      final second = info(box: const Rect.fromLTWH(0.7, 0.2, 0.2, 0.2));
      expect(
        await tts.announceDetections(
          [second],
          tracks: [trackOf(second, id: 2)],
        ),
        isTrue,
      );
      expect(engine.spoken, hasLength(2));
    });

    test('urgent phrasing is information-first', () async {
      final person = nearPerson();
      await tts.announceDetections([person], tracks: [trackOf(person, id: 8)]);
      final text = engine.spoken.single;
      expect(text.startsWith('Alert.'), isFalse);
      expect(text.contains('high priority obstacle'), isFalse);
      expect(text, contains('person'));
    });

    test('buildDetectionUtterance keeps detailed wording for exploration', () {
      final text = TtsService.buildDetectionUtterance(info(), 1);
      expect(text, contains('person'));
      expect(text, contains('approximately'));
    });
  });

  group('post-failure policy', () {
    test('a new alert after recovery failure always resolves', () async {
      engine.throwOnRecover = true;
      engine.mode = FakeMode.manual;
      final failed = tts.speak('silent');
      await pumpEventQueue();
      await Future<void>.delayed(const Duration(milliseconds: 250));

      expect(tts.recoveryFailed, isTrue);
      expect(engine.recoverCalls, 1);
      expect(await failed, isFalse);

      // Non-imminent requests are rejected immediately, not left pending.
      expect(await tts.speak('after'), isFalse);
      expect(tts.rejectedAfterRecoveryCount, 1);
      expect(engine.recoverCalls, 1);

      // Exactly one further recovery attempt is allowed, for imminent only.
      final urgent = tts.announceDetections(
        [nearPerson()],
        tracks: [trackOf(nearPerson(), id: 61)],
      );
      await pumpEventQueue();
      await Future<void>.delayed(const Duration(milliseconds: 250));
      expect(await urgent, isFalse);
      expect(engine.recoverCalls, 2);
      expect(tts.recoveryFailed, isTrue);

      final again = tts.announceDetections(
        [nearPerson()],
        tracks: [trackOf(nearPerson(), id: 62)],
      );
      await pumpEventQueue();
      expect(await again, isFalse);
      expect(engine.recoverCalls, 2);
    });
  });

  group('stale decision revalidation', () {
    test('two decisions before the first start produce one warning', () async {
      final person = info();
      final track = trackOf(person, id: 55);

      engine.mode = FakeMode.manual;
      final first = tts.announceDetections([person], tracks: [track]);
      await pumpEventQueue();

      // The policy has not committed yet, so this decision is also "new".
      final second = tts.announceDetections([person], tracks: [track]);
      await pumpEventQueue();

      engine.mode = FakeMode.autoComplete;
      engine.emitStart();
      engine.emitComplete();
      engine.resolveCurrent(1);
      await pumpEventQueue();

      expect(engine.spoken, hasLength(1));
      expect(await first, isTrue);
      expect(await second, isFalse);
      expect(tts.staleDecisionCount, 1);
    });

    test('a pending escalation before first start still speaks', () async {
      final near = nearPerson();

      engine.mode = FakeMode.manual;
      final active = tts.announceDetections(
        [near],
        tracks: [trackOf(near, id: 71)],
      );
      await pumpEventQueue();

      // Pending decision represents an escalation (stable -> approaching)
      // and must survive the first decision's commit.
      final escalated = tts.announceDetections(
        [near],
        tracks: [trackOf(near, id: 71, motion: MotionState.approaching)],
      );
      await pumpEventQueue();

      engine.mode = FakeMode.autoComplete;
      engine.emitStart();
      engine.emitComplete();
      engine.resolveCurrent(1);
      await pumpEventQueue();

      expect(engine.spoken, hasLength(2));
      expect(await active, isTrue);
      expect(await escalated, isTrue);
      expect(tts.staleDecisionCount, 0);
    });
  });

  group('settling timers', () {
    test('callbackQuietPeriod restarts when a callback arrives', () async {
      final localEngine = FakeTtsEngine()..mode = FakeMode.manual;
      final local = TtsService(
        engine: localEngine,
        clock: () => now,
        startConfirmationTimeout: const Duration(milliseconds: 40),
        callbackQuietPeriod: const Duration(milliseconds: 200),
        maxSettlingDuration: const Duration(milliseconds: 2000),
      );
      await local.init();
      addTearDown(local.dispose);

      final pending = local.speak('silent');
      await pumpEventQueue();
      await Future<void>.delayed(const Duration(milliseconds: 70));
      expect(local.isSettling, isTrue);

      await Future<void>.delayed(const Duration(milliseconds: 120));
      localEngine.emitStart(); // restarts the 200 ms quiet window
      await Future<void>.delayed(const Duration(milliseconds: 120));

      expect(local.isSettling, isTrue);
      expect(local.quarantinedCallbackCount, greaterThan(0));

      await Future<void>.delayed(const Duration(milliseconds: 250));
      expect(local.state, SpeechState.idle);
      expect(await pending, isFalse);
    });

    test('maxSettlingDuration caps settling and drains exactly once', () async {
      final localEngine = FakeTtsEngine()..mode = FakeMode.manual;
      final local = TtsService(
        engine: localEngine,
        clock: () => now,
        startConfirmationTimeout: const Duration(milliseconds: 30),
        callbackQuietPeriod: const Duration(milliseconds: 300),
        maxSettlingDuration: const Duration(milliseconds: 150),
      );
      await local.init();
      addTearDown(local.dispose);

      final failed = local.speak('silent');
      await pumpEventQueue();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(local.isSettling, isTrue);

      final queued = local.speak('queued', urgent: true);
      localEngine.mode = FakeMode.autoComplete;
      for (var i = 0; i < 6; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 40));
        localEngine.emitStart(); // keeps restarting the quiet window
      }
      await Future<void>.delayed(const Duration(milliseconds: 120));

      expect(local.quietPeriodCapReached, isTrue);
      expect(
        localEngine.spoken.where((text) => text == 'queued'),
        hasLength(1),
      );
      expect(await queued, isTrue);
      expect(await failed, isFalse);
      expect(local.isSettling, isFalse);
    });
  });

  group('alert lifecycle telemetry', () {
    late List<AlertLifecycleRecord> records;
    late List<AlertCounters> counters;
    late TtsService instrumented;

    setUp(() async {
      records = [];
      counters = [];
      instrumented = TtsService(
        engine: engine,
        clock: () => now,
        onAlertLifecycle: records.add,
        onAlertCounters: counters.add,
        startConfirmationTimeout: const Duration(milliseconds: 60),
        preemptionConfirmTimeout: const Duration(milliseconds: 40),
        reconciliationTimeout: const Duration(milliseconds: 40),
        callbackQuietPeriod: const Duration(milliseconds: 25),
        maxSettlingDuration: const Duration(milliseconds: 200),
        recoveryTimeout: const Duration(milliseconds: 100),
        preemptionCooldown: Duration.zero,
      );
      await instrumented.init();
      addTearDown(instrumented.dispose);
    });

    test('emits exactly one completed record with a confirmed start', () async {
      expect(await instrumented.speak('hello'), isTrue);

      final record = records.single;
      expect(record.origin, AlertOrigin.generic);
      expect(record.engine, isNull);
      expect(record.terminalState, AlertTerminalState.completed);
      expect(record.hadStarted, isTrue);
      expect(record.alertStartedAt, isNotNull);
      expect(record.terminalAt.isBefore(record.submittedAt), isFalse);
      expect(record.alertStartedAt!.isBefore(record.submittedAt), isFalse);
      expect(record.reconciledAt, record.terminalAt);
    });

    test('a dropped submission is a single started-less record', () async {
      engine.mode = FakeMode.drop;
      expect(await instrumented.speak('dropped'), isFalse);

      final record = records.single;
      expect(record.terminalState, AlertTerminalState.dropped);
      expect(record.hadStarted, isFalse);
      expect(record.alertStartedAt, isNull);
      expect(record.reconciledAt, record.terminalAt);
      expect(counters.last.dropped, 1);
    });

    test(
      'a cancellation before any start is counted as before-start',
      () async {
        engine.mode = FakeMode.manual;
        final pending = instrumented.speak('cancel me');
        await pumpEventQueue();

        engine.emitCancel();
        engine.resolveCurrent(0);
        await pumpEventQueue();

        final record = records.single;
        expect(record.terminalState, AlertTerminalState.cancelled);
        expect(record.hadStarted, isFalse);
        expect(record.alertStartedAt, isNull);
        expect(record.reconciledAt, record.terminalAt);
        expect(counters.last.cancelledBeforeStart, 1);
        expect(counters.last.cancelledAfterStart, 0);
        expect(await pending, isFalse);
      },
    );

    test('only detection origin carries the inference engine', () async {
      expect(
        await instrumented.announceDetections([
          nearPerson(),
        ], engine: InferenceEngine.ultralytics),
        isTrue,
      );
      expect(records.single.origin, AlertOrigin.detection);
      expect(records.single.engine, InferenceEngine.ultralytics);

      now = now.add(const Duration(seconds: 5));
      expect(await instrumented.speakWayfinding('Settings'), isTrue);
      expect(records.last.origin, AlertOrigin.wayfinding);
      expect(records.last.engine, isNull);
    });

    test('detection record carries Custom frame timing anchors', () async {
      final analysis = now.subtract(const Duration(milliseconds: 120));
      final started = now.subtract(const Duration(milliseconds: 100));
      final completed = now.subtract(const Duration(milliseconds: 80));
      final received = now.subtract(const Duration(milliseconds: 60));
      final accepted = now.subtract(const Duration(milliseconds: 50));
      final timing = FrameLatency(
        frameNumber: 42,
        analysisReceivedAt: analysis,
        inferenceStartedAt: started,
        inferenceCompletedAt: completed,
        resultReceivedAt: received,
        detectionAcceptedAt: accepted,
      );

      expect(
        await instrumented.announceDetections(
          [nearPerson()],
          engine: InferenceEngine.ultralytics,
          frameLatency: timing,
        ),
        isTrue,
      );

      final record = records.single;
      expect(record.frameNumber, 42);
      expect(record.analysisReceivedAt, analysis);
      expect(record.inferenceStartedAt, started);
      expect(record.inferenceCompletedAt, completed);
      expect(record.resultReceivedAt, received);
      expect(record.detectionAcceptedAt, accepted);
      // requestedAt is the alert-request anchor.
      expect(record.requestedAt, now);

      // Zero-length intervals are valid, so ordering is "not before".
      expect(record.inferenceStartedAt!.isBefore(analysis), isFalse);
      expect(record.inferenceCompletedAt!.isBefore(started), isFalse);
      expect(record.resultReceivedAt!.isBefore(completed), isFalse);
      expect(record.detectionAcceptedAt!.isBefore(received), isFalse);
      expect(record.requestedAt.isBefore(accepted), isFalse);
      expect(record.submittedAt.isBefore(record.requestedAt), isFalse);
      expect(record.alertStartedAt!.isBefore(record.submittedAt), isFalse);
      expect(record.terminalAt.isBefore(record.alertStartedAt!), isFalse);
    });

    test('missing Custom frame timing leaves anchors null', () async {
      expect(
        await instrumented.announceDetections([
          nearPerson(),
        ], engine: InferenceEngine.ultralytics),
        isTrue,
      );

      final record = records.single;
      expect(record.frameNumber, isNull);
      expect(record.analysisReceivedAt, isNull);
      expect(record.inferenceStartedAt, isNull);
      expect(record.inferenceCompletedAt, isNull);
      expect(record.resultReceivedAt, isNull);
      expect(record.detectionAcceptedAt, isNull);
    });

    test('direct app-side anchors fill an Ultralytics record', () async {
      final received = now.subtract(const Duration(milliseconds: 40));
      final accepted = now.subtract(const Duration(milliseconds: 30));
      expect(
        await instrumented.announceDetections(
          [nearPerson()],
          engine: InferenceEngine.ultralytics,
          resultReceivedAt: received,
          detectionAcceptedAt: accepted,
        ),
        isTrue,
      );

      final record = records.single;
      expect(record.origin, AlertOrigin.detection);
      expect(record.engine, InferenceEngine.ultralytics);
      expect(record.frameNumber, isNull);
      expect(record.analysisReceivedAt, isNull);
      expect(record.inferenceStartedAt, isNull);
      expect(record.inferenceCompletedAt, isNull);
      expect(record.resultReceivedAt, received);
      expect(record.detectionAcceptedAt, accepted);
      // Non-strict ordering: equal timestamps are valid.
      expect(record.detectionAcceptedAt!.isBefore(received), isFalse);
      expect(record.requestedAt.isBefore(accepted), isFalse);
      expect(record.alertStartedAt!.isBefore(record.submittedAt), isFalse);
    });

    test('Custom frame anchors win over direct app-side anchors', () async {
      final analysis = now.subtract(const Duration(milliseconds: 120));
      final received = now.subtract(const Duration(milliseconds: 60));
      final accepted = now.subtract(const Duration(milliseconds: 50));
      final timing = FrameLatency(
        frameNumber: 9,
        analysisReceivedAt: analysis,
        resultReceivedAt: received,
        detectionAcceptedAt: accepted,
      );

      expect(
        await instrumented.announceDetections(
          [nearPerson()],
          engine: InferenceEngine.ultralytics,
          frameLatency: timing,
          resultReceivedAt: now,
          detectionAcceptedAt: now,
        ),
        isTrue,
      );

      final record = records.single;
      expect(record.frameNumber, 9);
      expect(record.analysisReceivedAt, analysis);
      expect(record.resultReceivedAt, received);
      expect(record.detectionAcceptedAt, accepted);
    });

    test('quick scan and repeat-last records stay engine-null', () async {
      expect(await instrumented.announceQuickScan([info()]), isTrue);
      expect(records.single.origin, AlertOrigin.quickScan);
      expect(records.single.engine, isNull);

      now = now.add(const Duration(seconds: 5));
      expect(await instrumented.repeatLast(), isTrue);
      expect(records.last.origin, AlertOrigin.repeatLast);
      expect(records.last.engine, isNull);
    });

    test('preemption is counted only once cancellation reconciles', () async {
      engine.mode = FakeMode.startOnly;
      final active = instrumented.speak('status');
      await pumpEventQueue();

      engine.mode = FakeMode.autoComplete;
      final urgent = instrumented.announceDetections(
        [nearPerson()],
        tracks: [trackOf(nearPerson(), id: 21)],
      );
      await pumpEventQueue();

      expect(counters.last.preemptionRequested, 1);
      expect(counters.last.preempted, 0);

      engine.emitCancel();
      engine.resolveCurrent(0);
      await pumpEventQueue();

      final cancelled = records.first;
      expect(cancelled.terminalState, AlertTerminalState.cancelled);
      expect(cancelled.terminalCause, 'preempted');
      expect(cancelled.hadStarted, isTrue);
      expect(cancelled.reconciledAt, cancelled.terminalAt);
      expect(counters.last.preempted, 1);
      expect(counters.last.cancelledAfterStart, 1);

      await urgent;
      await active;
    });

    test('watchdog failure has no reconciliation and no preemption', () async {
      engine.mode = FakeMode.manual;
      final pending = instrumented.speak('silent');
      await pumpEventQueue();
      await Future<void>.delayed(const Duration(milliseconds: 120));

      final record = records.single;
      expect(record.terminalState, AlertTerminalState.failed);
      expect(record.terminalCause, 'startNotConfirmed');
      expect(record.hadStarted, isFalse);
      expect(record.reconciledAt, isNull);
      expect(counters.last.failedBeforeStart, 1);
      expect(counters.last.watchdogRecovery, 1);
      expect(counters.last.preempted, 0);
      expect(await pending, isFalse);
    });

    test('a partial signal pair records a reconciliation timeout', () async {
      engine.mode = FakeMode.manual;
      final pending = instrumented.speak('silent');
      await pumpEventQueue();

      engine.emitStart();
      engine.emitComplete();
      await Future<void>.delayed(const Duration(milliseconds: 120));

      final record = records.single;
      expect(record.terminalState, AlertTerminalState.failed);
      expect(record.terminalCause, 'reconciliationTimeout');
      expect(record.hadStarted, isTrue);
      expect(record.reconciledAt, isNull);
      expect(counters.last.failedAfterStart, 1);
      expect(counters.last.reconciliationTimeout, 1);
      expect(counters.last.watchdogRecovery, 1);
      expect(await pending, isFalse);
    });

    test('a late result after the terminal publishes its counter', () async {
      engine.mode = FakeMode.manual;
      final pending = instrumented.speak('silent');
      await pumpEventQueue();
      await Future<void>.delayed(const Duration(milliseconds: 120));

      expect(counters.last.failedBeforeStart, 1);
      expect(counters.last.lateCallbackIgnored, 0);

      engine.resolveCurrent(0);
      await pumpEventQueue();

      expect(counters.last.lateCallbackIgnored, 1);
      expect(await pending, isFalse);
    });

    test('an engine-error recovery is not a watchdog recovery', () async {
      engine.mode = FakeMode.manual;
      final pending = instrumented.speak('boom');
      await pumpEventQueue();

      engine.emitError();
      await pumpEventQueue();

      final record = records.single;
      expect(record.terminalState, AlertTerminalState.failed);
      expect(record.terminalCause, 'engineError');
      expect(counters.last.watchdogRecovery, 0);
      expect(engine.recoverCalls, greaterThan(0));
      expect(await pending, isFalse);
    });

    test('muted decisions are counted but never recorded', () async {
      instrumented.setAudioEnabled(false);
      expect(await instrumented.speak('hello'), isFalse);
      expect(
        await instrumented.announceDetections([
          nearPerson(),
        ], engine: InferenceEngine.ultralytics),
        isFalse,
      );

      expect(records, isEmpty);
      expect(counters.last.muted, 2);
      expect(counters.last.rejectedByReason['muted'], 2);
    });

    test('same-priority replacement is counted and published once', () async {
      engine.mode = FakeMode.startOnly;
      final active = instrumented.speak('status', urgent: true);
      await pumpEventQueue();
      expect(instrumented.isSpeaking, isTrue);

      final parked = instrumented.speak('parked', urgent: true);
      final newest = instrumented.speak('newest', urgent: true);
      await pumpEventQueue();

      // The displaced pending request is counted exactly once, and the
      // cumulative snapshot is published immediately.
      expect(await parked, isFalse);
      expect(instrumented.supersededCount, 1);
      expect(counters.last.superseded, 1);

      engine.mode = FakeMode.autoComplete;
      engine.emitComplete();
      engine.resolveCurrent(1);
      await pumpEventQueue();

      expect(await newest, isTrue);
      await active;
    });

    test(
      'a watchdog failure after a recovery attempt adds no recovery',
      () async {
        engine.mode = FakeMode.manual;
        final first = instrumented.speak('silent');
        await pumpEventQueue();
        await Future<void>.delayed(const Duration(milliseconds: 120));

        expect(await first, isFalse);
        expect(counters.last.watchdogRecovery, 1);

        // The single recovery attempt is already consumed, so this watchdog
        // failure must not count a second watchdog recovery.
        final second = instrumented.speak('silent again');
        await pumpEventQueue();
        await Future<void>.delayed(const Duration(milliseconds: 120));

        expect(await second, isFalse);
        expect(counters.last.failedBeforeStart, 2);
        expect(counters.last.watchdogRecovery, 1);
        expect(instrumented.recoveryFailed, isTrue);
      },
    );
  });
}
