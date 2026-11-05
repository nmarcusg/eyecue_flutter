import 'dart:ui';

import 'package:eyecue_flutter/models/app_settings.dart';
import 'package:eyecue_flutter/models/detection.dart';
import 'package:eyecue_flutter/services/assistive_detection_controller.dart';
import 'package:eyecue_flutter/services/telemetry_service.dart';
import 'package:eyecue_flutter/services/tts_service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'tts_service_test.dart' show FakeTtsEngine, FakeMode;

void main() {
  const person = Detection(
    classId: 0,
    label: 'person',
    confidence: 0.9,
    box: Rect.fromLTWH(0.3, 0.2, 0.4, 0.5),
  );
  late FakeTtsEngine engine;
  late TtsService tts;
  late TelemetryService telemetry;
  late AssistiveDetectionController controller;
  late Duration monotonic;
  final wall = DateTime.utc(2026, 11, 5);

  setUp(() async {
    monotonic = const Duration(seconds: 10);
    engine = FakeTtsEngine();
    tts = TtsService(
      engine: engine,
      monotonicClock: () => monotonic,
      clock: () => wall.add(monotonic),
    );
    await tts.init();
    telemetry = TelemetryService();
    controller = AssistiveDetectionController(
      engine: InferenceEngine.ultralytics,
      tts: tts,
      telemetry: telemetry,
    );
  });
  tearDown(() {
    controller.dispose();
    tts.dispose();
    telemetry.dispose();
  });

  void observe(double? metres, int revision, {bool announce = true}) {
    controller.updateDetections(
      [person],
      meters: [metres],
      depthRevision: revision,
      timestamp: wall.add(monotonic),
      resultReceivedAt: wall.add(monotonic),
      monotonicReceivedAt: monotonic,
      session: 'session',
      model: 'model',
      camera: 'camera',
      announce: announce,
    );
  }

  bool depth(
    double? metres,
    int revision, {
    String session = 'session',
    String model = 'model',
    String camera = 'camera',
  }) => controller.reevaluateDepth(
    meters: [metres],
    depthRevision: revision,
    session: session,
    model: model,
    camera: camera,
  );

  test(
    'first new close depth speaks immediately despite far display history',
    () {
      observe(5, 1);
      expect(engine.spoken, isEmpty);
      monotonic += const Duration(milliseconds: 100);
      expect(depth(1, 2), isTrue);
      expect(controller.detections.single.estimatedMeters, 1);
      expect(controller.detections.single.displayMeters, closeTo(3.4, 1e-9));
      expect(
        engine.spoken,
        hasLength(1),
        reason: 'no extra result or EMA wait',
      );
      expect(engine.spoken.single, contains('person'));
      expect(engine.spoken.single, isNot(contains('3.4')));
    },
  );

  test(
    'display advances only once per observation at different detector rates',
    () {
      observe(5, 1, announce: false);
      observe(1, 2, announce: false);
      for (var i = 0; i < 20; i++) {
        monotonic += const Duration(milliseconds: 10);
        observe(1, 2, announce: false);
        expect(controller.detections.single.displayMeters, closeTo(3.4, 1e-9));
      }
      observe(1, 3, announce: false);
      expect(controller.detections.single.displayMeters, closeTo(2.44, 1e-9));
    },
  );

  test('new depth retains detector receipt, hit count and telemetry rows', () {
    observe(5, 1);
    final track = controller.tracks.single;
    final rows = telemetry.totalDetections;
    monotonic += const Duration(milliseconds: 100);
    expect(depth(1, 2), isTrue);
    expect(controller.tracks.single.hitCount, track.hitCount);
    expect(controller.tracks.single.lastSeen, track.lastSeen);
    expect(controller.tracks.single.trackId, track.trackId);
    expect(telemetry.totalDetections, rows);
    expect(tts.lastAutomaticStartAge, const Duration(milliseconds: 100));
    expect(
      depth(1, 2),
      isFalse,
      reason: 'image repaint is not another observation',
    );
  });

  test(
    'stale or mismatched contexts cannot consume depth or resurrect speech',
    () {
      observe(5, 1);
      expect(depth(1, 2, session: 'other'), isFalse);
      expect(depth(1, 2, model: 'other'), isFalse);
      expect(depth(1, 2, camera: 'other'), isFalse);
      monotonic += const Duration(milliseconds: 501);
      expect(depth(1, 2), isFalse);
      expect(engine.spoken, isEmpty);
      expect(controller.detections.single.estimatedMeters, 5);
    },
  );

  test(
    'depth reevaluation does not refresh the 500 ms detector freshness bound',
    () {
      observe(5, 1);
      monotonic += const Duration(milliseconds: 400);
      expect(depth(4, 2), isTrue);
      monotonic += const Duration(milliseconds: 101);
      expect(depth(1, 3), isFalse);
      expect(engine.spoken, isEmpty);
    },
  );

  test('reset and empty accepted results invalidate cached depth targets', () {
    observe(5, 1);
    controller.reset();
    expect(depth(1, 2), isFalse);
    observe(5, 3);
    controller.updateDetections(
      [],
      resultReceivedAt: wall.add(monotonic),
      monotonicReceivedAt: monotonic,
      session: 'session',
      model: 'model',
      camera: 'camera',
    );
    expect(depth(1, 4), isFalse);
    expect(engine.spoken, isEmpty);
  });

  test(
    'far retreat invalidates a queued close claim despite lingering display EMA',
    () async {
      engine.mode = FakeMode.startOnly;
      final busy = tts.speak('busy', urgent: true);
      await Future<void>.delayed(Duration.zero);
      observe(1.8, 1);
      expect(engine.spoken, ['busy']);
      monotonic += const Duration(milliseconds: 50);
      expect(depth(5, 2), isTrue);
      expect(controller.detections.single.displayMeters, lessThan(5));
      engine.emitComplete();
      engine.resolveCurrent(1);
      await busy;
      await pumpEventQueue();
      expect(engine.spoken, [
        'busy',
      ], reason: 'new far evidence must win at drain');
      expect(tts.automaticDiscardCount, greaterThan(0));
    },
  );
}
