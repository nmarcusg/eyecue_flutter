import 'dart:ui';

import 'package:eyecue_flutter/models/alert_lifecycle.dart';
import 'package:eyecue_flutter/models/app_settings.dart';
import 'package:eyecue_flutter/models/detection.dart';
import 'package:eyecue_flutter/services/assistive_detection_controller.dart';
import 'package:eyecue_flutter/services/telemetry_service.dart';
import 'package:eyecue_flutter/services/tts_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

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
      engine: InferenceEngine.custom,
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
      controller.updateDetections(nearPerson(), frameLatency: timing);
      await pumpEventQueue();

      final record = records.single;
      expect(record.origin, AlertOrigin.detection);
      expect(record.engine, InferenceEngine.custom);
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
      controller.updateDetections(nearPerson(), resultReceivedAt: received);
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

  test('empty detections create no alert record', () async {
    controller.updateDetections(const [], frameLatency: frameLatency());
    await pumpEventQueue();

    expect(records, isEmpty);
  });
}
