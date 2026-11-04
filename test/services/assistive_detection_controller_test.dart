import 'dart:async';
import 'dart:ui';

import 'package:eyecue_flutter/models/alert_lifecycle.dart';
import 'package:eyecue_flutter/models/app_settings.dart';
import 'package:eyecue_flutter/models/detection.dart';
import 'package:eyecue_flutter/models/detector_model.dart';
import 'package:eyecue_flutter/services/assistive_detection_controller.dart';
import 'package:eyecue_flutter/services/telemetry_service.dart';
import 'package:eyecue_flutter/services/tts_service.dart';
import 'package:flutter_test/flutter_test.dart';

class _QueuedTtsEngine extends TtsEngine {
  final List<String> spoken = [];
  VoidCallback? _onStart;
  VoidCallback? _onComplete;
  Completer<int>? _current;

  @override
  Future<void> init() async {}

  @override
  Future<int> speak(String text) {
    spoken.add(text);
    _onStart?.call();
    _current = Completer<int>();
    return _current!.future;
  }

  void finishCurrent() {
    _onComplete?.call();
    _current!.complete(1);
  }

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}

  @override
  void setStartHandler(VoidCallback? callback) => _onStart = callback;

  @override
  void setCompletionHandler(VoidCallback? callback) => _onComplete = callback;
}

/// Minimal engine that confirms start and completion immediately.
class _AutoTtsEngine extends TtsEngine {
  VoidCallback? _onStart;
  VoidCallback? _onComplete;

  @override
  Future<void> init() async {}

  @override
  Future<int> speak(String text) {
    _onStart?.call();
    _onComplete?.call();
    return Future<int>.value(1);
  }

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}

  @override
  void setStartHandler(VoidCallback? callback) => _onStart = callback;

  @override
  void setCompletionHandler(VoidCallback? callback) => _onComplete = callback;
}

void main() {
  late List<AlertLifecycleRecord> records;
  late TtsService tts;
  late AssistiveDetectionController controller;

  setUp(() async {
    records = [];
    tts = TtsService(engine: _AutoTtsEngine(), onAlertLifecycle: records.add);
    await tts.init();
    addTearDown(tts.dispose);
    controller = AssistiveDetectionController(
      engine: InferenceEngine.ultralytics,
      tts: tts,
      telemetry: TelemetryService(),
    );
  });

  List<Detection> nearPerson() => const [
    Detection(
      classId: 0,
      label: 'person',
      confidence: 0.9,
      box: Rect.fromLTWH(0.3, 0.2, 0.4, 0.5),
    ),
  ];

  FrameLatency frameLatency() {
    final received = DateTime.utc(2026, 1, 1, 12);
    return FrameLatency(
      frameNumber: 7,
      analysisReceivedAt: received.subtract(const Duration(milliseconds: 40)),
      inferenceStartedAt: received.subtract(const Duration(milliseconds: 30)),
      inferenceCompletedAt: received.subtract(const Duration(milliseconds: 10)),
      resultReceivedAt: received,
    );
  }

  test(
    'accepted frame timing reaches one detection lifecycle record',
    () async {
      final timing = frameLatency();
      controller.updateDetections(
        nearPerson(),
        frameLatency: timing,
        resultReceivedAt: timing.resultReceivedAt,
        monotonicReceivedAt: Duration.zero,
        session: 'test-session',
        model: 'test-model',
        camera: 'test-camera',
      );
      await pumpEventQueue();

      final record = records.single;
      expect(record.origin, AlertOrigin.detection);
      expect(record.engine, InferenceEngine.ultralytics);
      expect(record.frameNumber, 7);
      expect(record.analysisReceivedAt, timing.analysisReceivedAt);
      expect(record.inferenceStartedAt, timing.inferenceStartedAt);
      expect(record.inferenceCompletedAt, timing.inferenceCompletedAt);
      expect(record.resultReceivedAt, timing.resultReceivedAt);
      expect(record.detectionAcceptedAt, isNotNull);
      expect(
        record.resultReceivedAt!.isBefore(record.analysisReceivedAt!),
        isFalse,
      );
      expect(record.alertStartedAt!.isBefore(record.submittedAt), isFalse);
    },
  );

  test('missing frame timing leaves record anchors null', () async {
    controller.updateDetections(nearPerson());
    await pumpEventQueue();

    final record = records.single;
    expect(record.frameNumber, isNull);
    expect(record.analysisReceivedAt, isNull);
    expect(record.inferenceStartedAt, isNull);
    expect(record.inferenceCompletedAt, isNull);
    expect(record.resultReceivedAt, isNull);
    expect(record.detectionAcceptedAt, isNull);
  });

  test(
    'app-side result receipt reaches the record without frame anchors',
    () async {
      controller = AssistiveDetectionController(
        engine: InferenceEngine.ultralytics,
        tts: tts,
        telemetry: TelemetryService(),
      );
      final received = DateTime.utc(2026, 1, 1, 12);
      controller.updateDetections(
        nearPerson(),
        resultReceivedAt: received,
        monotonicReceivedAt: Duration.zero,
        session: 'test-session',
        model: 'test-model',
        camera: 'test-camera',
      );
      await pumpEventQueue();

      final record = records.single;
      expect(record.origin, AlertOrigin.detection);
      expect(record.engine, InferenceEngine.ultralytics);
      expect(record.frameNumber, isNull);
      expect(record.analysisReceivedAt, isNull);
      expect(record.inferenceStartedAt, isNull);
      expect(record.inferenceCompletedAt, isNull);
      expect(record.resultReceivedAt, received);
      expect(record.detectionAcceptedAt, isNotNull);
      // Equal timestamps are valid, so ordering is "not before".
      expect(record.detectionAcceptedAt!.isBefore(received), isFalse);
      expect(record.requestedAt.isBefore(record.detectionAcceptedAt!), isFalse);
    },
  );

  test(
    'production receipt clock domain allows current automatic speech to start',
    () async {
      var monotonic = const Duration(seconds: 420);
      final clockDomainTts = TtsService(
        engine: _AutoTtsEngine(),
        monotonicClock: () => monotonic,
        onAlertLifecycle: records.add,
      );
      await clockDomainTts.init();
      addTearDown(clockDomainTts.dispose);
      final productionController = AssistiveDetectionController(
        engine: InferenceEngine.ultralytics,
        tts: clockDomainTts,
        telemetry: TelemetryService(),
      );

      productionController.updateDetections(
        nearPerson(),
        resultReceivedAt: DateTime.utc(2026, 1, 1, 12),
        monotonicReceivedAt: clockDomainTts.monotonicNow,
        session: '3:7',
        model: 'model-fingerprint',
        camera: 'native-view-3',
      );
      monotonic += const Duration(milliseconds: 20);
      await pumpEventQueue();

      expect(records, hasLength(1));
      expect(records.single.origin, AlertOrigin.detection);
      expect(records.single.alertStartedAt, isNotNull);
    },
  );

  test('built-in controller identity preserves a queued fresh alert', () async {
    final queuedEngine = _QueuedTtsEngine();
    final queuedTts = TtsService(engine: queuedEngine);
    await queuedTts.init();
    addTearDown(queuedTts.dispose);
    final productionController = AssistiveDetectionController(
      engine: InferenceEngine.ultralytics,
      tts: queuedTts,
      telemetry: TelemetryService(),
      detectorModel: DetectorModel.builtIn(const []).ref,
    );

    final busy = queuedTts.speak('busy', urgent: true);
    await Future<void>.delayed(Duration.zero);
    expect(queuedEngine.spoken, hasLength(1));

    productionController.updateDetections(
      nearPerson(),
      resultReceivedAt: DateTime.utc(2026, 1, 1, 12),
      monotonicReceivedAt: queuedTts.monotonicNow,
      session: 'builtin-session',
      model: 'builtin-model',
      camera: 'builtin-camera',
    );
    await Future<void>.delayed(Duration.zero);
    expect(queuedEngine.spoken, hasLength(1));

    queuedEngine.finishCurrent();
    await busy;
    await pumpEventQueue();
    expect(queuedEngine.spoken, hasLength(2));
    expect(queuedEngine.spoken.last, contains('person'));
    productionController.dispose();
  });

  test('empty detections create no alert record', () async {
    controller.updateDetections(
      const [],
      frameLatency: frameLatency(),
      resultReceivedAt: frameLatency().resultReceivedAt,
      monotonicReceivedAt: Duration.zero,
      session: 'test-session',
      model: 'test-model',
      camera: 'test-camera',
    );
    await pumpEventQueue();

    expect(records, isEmpty);
    expect(controller.detections, isEmpty);
    expect(controller.tracks, isEmpty);
  });

  test(
    'latest accepted detections are current visible set, even with retained tracks',
    () {
      controller.updateDetections(
        nearPerson(),
        announce: false,
        timestamp: DateTime.utc(2026, 1, 1),
      );
      expect(controller.detections, hasLength(1));
      controller.updateDetections(
        const [],
        announce: false,
        timestamp: DateTime.utc(
          2026,
          1,
          1,
        ).add(const Duration(milliseconds: 30)),
      );
      expect(controller.tracker.activeTracks, hasLength(1));
      expect(controller.detections, isEmpty);
      expect(controller.tracks, isEmpty);
    },
  );
}
