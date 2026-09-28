import 'dart:async';
import 'dart:ui';

import 'package:eyecue_flutter/models/detection.dart';
import 'package:eyecue_flutter/models/detection_info.dart';
import 'package:eyecue_flutter/services/spatial_analysis_service.dart';
import 'package:eyecue_flutter/services/tts_service.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeTtsEngine implements TtsEngine {
  final List<String> spoken = [];
  bool inited = false;
  int initCount = 0;

  @override
  Future<void> init() async {
    inited = true;
    initCount++;
  }

  @override
  Future<void> speak(String text) async {
    spoken.add(text);
  }

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}
}

/// A TTS engine whose `speak` blocks until [gate] completes, so a test can
/// observe the service while Detection speech is genuinely in flight.
class _GatedTtsEngine implements TtsEngine {
  _GatedTtsEngine(this.gate);

  final Completer<void> gate;
  final List<String> spoken = [];

  @override
  Future<void> init() async {}

  @override
  Future<void> speak(String text) async {
    spoken.add(text);
    await gate.future;
  }

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}
}

DetectionInfo info({
  required int classId,
  required String label,
  Rect? box,
  double conf = 0.9,
}) {
  final d = Detection(
    classId: classId,
    label: label,
    confidence: conf,
    box: box ?? const Rect.fromLTWH(0.1, 0.1, 0.2, 0.2),
  );
  return SpatialAnalysisService.analyze(d);
}

void main() {
  late FakeTtsEngine engine;
  late DateTime now;
  late TtsService tts;

  setUp(() {
    engine = FakeTtsEngine();
    now = DateTime(2026, 1, 1, 12, 0, 0);
    tts = TtsService(engine: engine, clock: () => now);
  });

  group('speak cooldown', () {
    test('speaks when within no recent announcement', () async {
      expect(await tts.speak('hello'), isTrue);
      expect(engine.spoken, ['hello']);
    });

    test('cooldown suppresses a second non-urgent announcement', () async {
      await tts.speak('first');
      now = now.add(const Duration(seconds: 1)); // inside 3s cooldown
      expect(await tts.speak('second'), isFalse);
      expect(engine.spoken, ['first']);
    });

    test('urgent bypasses the normal cooldown', () async {
      await tts.speak('first');
      now = now.add(const Duration(seconds: 1));
      expect(await tts.speak('urgent', urgent: true), isTrue);
      expect(engine.spoken, ['first', 'urgent']);
    });

    test('speaks again after the cooldown elapses', () async {
      await tts.speak('first');
      now = now.add(const Duration(seconds: 4));
      expect(await tts.speak('second'), isTrue);
      expect(engine.spoken, ['first', 'second']);
    });
  });

  group('mute', () {
    test('muted service never sends text to the engine', () async {
      tts.setAudioEnabled(false);
      expect(await tts.speak('hello'), isFalse);
      expect(engine.spoken, isEmpty);
    });
  });

  group('announceDetections de-duplication', () {
    test('announces a new object', () async {
      final infos = [info(classId: 0, label: 'person')];
      expect(await tts.announceDetections(infos), isTrue);
      expect(engine.spoken.single, contains('person'));
    });

    test(
      'does not re-announce the same label within the same-label cooldown',
      () async {
        final infos = [info(classId: 0, label: 'person')];
        await tts.announceDetections(infos);
        now = now.add(const Duration(seconds: 2));
        // Different confidence, same label → still de-duplicated.
        final again = [info(classId: 0, label: 'person', conf: 0.95)];
        expect(await tts.announceDetections(again), isFalse);
        expect(engine.spoken.length, 1);
      },
    );

    test('announces again once the same-label cooldown elapses', () async {
      final infos = [info(classId: 0, label: 'person')];
      await tts.announceDetections(infos);
      now = now.add(const Duration(seconds: 7));
      expect(await tts.announceDetections(infos), isTrue);
      expect(engine.spoken.length, 2);
    });

    test(
      'high-priority primary is selected and marked in the utterance',
      () async {
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
        expect(text, contains('high priority obstacle'));
        expect(text, contains('2 objects detected'));
      },
    );
  });

  group('speakWayfinding', () {
    test('speaks a wayfinding phrase when idle', () async {
      expect(await tts.speakWayfinding('Settings'), isTrue);
      expect(engine.spoken, ['Settings']);
    });

    test('muted audio suppresses wayfinding', () async {
      tts.setAudioEnabled(false);
      expect(await tts.speakWayfinding('Settings'), isFalse);
      expect(engine.spoken, isEmpty);
    });

    test('wayfinding never replaces the Detection replay utterance', () async {
      await tts.speak('person, high priority obstacle');
      now = now.add(const Duration(seconds: 1));
      await tts.speakWayfinding('Settings');
      // repeatLast must still replay the Detection alert, not the destination.
      now = now.add(const Duration(seconds: 1));
      expect(await tts.repeatLast(), isTrue);
      expect(engine.spoken.last, 'person, high priority obstacle');
    });

    test('repeated boundary phrase applies the anti-repeat rule', () async {
      expect(await tts.speakWayfinding('End of navigation'), isTrue);
      now = now.add(const Duration(milliseconds: 500));
      expect(await tts.speakWayfinding('End of navigation'), isFalse);
      now = now.add(const Duration(seconds: 3));
      expect(await tts.speakWayfinding('End of navigation'), isTrue);
    });

    test('wayfinding drops while Detection speech is active', () async {
      final gate = Completer<void>();
      final slowEngine = _GatedTtsEngine(gate);
      final slowTts = TtsService(engine: slowEngine, clock: () => now);
      final detection = slowTts.speak('person detected');
      // Detection speech is now in flight.
      expect(await slowTts.speakWayfinding('Settings'), isFalse);
      expect(slowEngine.spoken, ['person detected']);
      gate.complete();
      await detection;
    });
  });

  group('repeatLast', () {
    test('repeats the last utterance even inside the cooldown', () async {
      await tts.speak('alert');
      now = now.add(const Duration(seconds: 1));
      expect(await tts.repeatLast(), isTrue);
      expect(engine.spoken, ['alert', 'alert']);
    });

    test('does nothing when nothing has been spoken yet', () async {
      expect(await tts.repeatLast(), isFalse);
    });
  });

  group('buildDetectionUtterance', () {
    test('includes position and approximate proximity', () {
      final text = TtsService.buildDetectionUtterance(
        info(classId: 2, label: 'car'),
        1,
      );
      expect(text, contains('car'));
      expect(text, contains('approximately'));
    });
  });
}
