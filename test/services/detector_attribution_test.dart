import 'dart:ui';

import 'package:eyecue_flutter/models/app_settings.dart';
import 'package:eyecue_flutter/models/detection.dart';
import 'package:eyecue_flutter/models/detection_info.dart';
import 'package:eyecue_flutter/models/detector_model.dart';
import 'package:eyecue_flutter/services/assistive_detection_controller.dart';
import 'package:eyecue_flutter/services/telemetry_service.dart';
import 'package:eyecue_flutter/services/tts_service.dart';
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
  final timestamp = DateTime.utc(2026, 1, 1, 12, 0, 0);

  /// The bundled detector, resolved through the same `ref` the screen uses.
  DetectorModel builtInModel() =>
      DetectorModel.builtIn(List.generate(80, (index) => 'coco-$index'));

  /// A researcher-imported graph. The path is what must never be recorded.
  DetectorModel customModel({
    String name = 'Obstacle Detector v2',
    String fingerprint = '0a1b2c3d4e5f6071-4200',
  }) => DetectorModel(
    kind: DetectorModelKind.custom,
    displayName: name,
    fingerprint: fingerprint,
    labels: List.generate(12, (index) => 'class-$index'),
    fileSizeBytes: 4200,
    path: '/data/user/0/com.eyecue/documents/eyecue_models/$fingerprint.tflite',
  );

  List<Detection> cup() => const [
    Detection(
      classId: 41,
      label: 'cup',
      confidence: 0.9,
      box: Rect.fromLTWH(0.3, 0.2, 0.4, 0.5),
    ),
  ];

  DetectionInfo cupInfo() => DetectionInfo(
    detection: cup().single,
    position: RelativePosition.left,
    priority: ObjectPriority.medium,
    proximity: ProximityBand.far,
  );

  late TtsService tts;
  late TelemetryService telemetry;
  late AssistiveDetectionController controller;

  setUp(() async {
    tts = TtsService(engine: _AutoTtsEngine());
    await tts.init();
    addTearDown(tts.dispose);
    telemetry = TelemetryService(
      clock: () => timestamp,
      sessionId: 'session-attribution',
    );
    addTearDown(telemetry.dispose);
    controller = AssistiveDetectionController(
      engine: InferenceEngine.ultralytics,
      tts: tts,
      telemetry: telemetry,
      detectorModel: builtInModel().ref,
    );
    addTearDown(controller.dispose);
  });

  group('detector attribution', () {
    test('a switch never relabels the rows written before it', () {
      controller.updateDetections(cup(), latencyMs: 12.5);
      controller.recordMetrics(latencyMs: 12.5, inferenceFps: 15);
      final before = telemetry.records.single;
      final beforeSample = telemetry.samples.single;

      // Snapshot every attributed field before the model changes.
      final oldId = before.detectorModelId;
      final oldName = before.detectorModelName;
      final oldFingerprint = before.detectorModelFingerprint;
      expect(oldId, 'builtin');
      expect(oldName, 'Built-in YOLOv8n');
      expect(oldFingerprint, DetectorModel.builtInFingerprint);
      expect(beforeSample.detectorModelId, oldId);
      expect(beforeSample.detectorModelName, oldName);
      expect(beforeSample.detectorModelFingerprint, oldFingerprint);

      controller.detectorModel = customModel().ref;
      controller.updateDetections(cup(), latencyMs: 40);
      controller.recordMetrics(latencyMs: 40, inferenceFps: 9);

      // New rows carry the replacement.
      final after = telemetry.records.last;
      final afterSample = telemetry.samples.last;
      expect(after.detectorModelId, 'custom:0a1b2c3d4e5f');
      expect(after.detectorModelName, 'Obstacle Detector v2');
      expect(after.detectorModelFingerprint, '0a1b2c3d4e5f6071-4200');
      expect(afterSample.detectorModelId, after.detectorModelId);
      expect(afterSample.detectorModelName, after.detectorModelName);
      expect(
        afterSample.detectorModelFingerprint,
        after.detectorModelFingerprint,
      );

      // The earlier rows are untouched — including the readable name.
      expect(telemetry.records, hasLength(2));
      expect(telemetry.records.first.detectorModelId, oldId);
      expect(telemetry.records.first.detectorModelName, oldName);
      expect(telemetry.records.first.detectorModelFingerprint, oldFingerprint);
      expect(telemetry.samples.first.detectorModelId, oldId);
      expect(telemetry.samples.first.detectorModelName, oldName);
      expect(telemetry.samples.first.detectorModelFingerprint, oldFingerprint);
    });

    test('two graphs sharing a display name stay distinguishable', () {
      final first = customModel(fingerprint: '0a1b2c3d4e5f6071-4200');
      final second = customModel(fingerprint: 'ffeeddccbbaa9988-4300');
      expect(first.displayName, second.displayName);

      controller.detectorModel = first.ref;
      controller.updateDetections(cup(), latencyMs: 30);
      controller.detectorModel = second.ref;
      controller.updateDetections(cup(), latencyMs: 31);

      final rows = telemetry.records;
      expect(rows.map((row) => row.detectorModelName).toSet(), {
        first.displayName,
      });
      expect(rows.map((row) => row.detectorModelId).toSet(), {
        'custom:0a1b2c3d4e5f',
        'custom:ffeeddccbbaa',
      });
      expect(rows.map((row) => row.detectorModelFingerprint).toSet(), {
        '0a1b2c3d4e5f6071-4200',
        'ffeeddccbbaa9988-4300',
      });
    });

    test('a row written without attribution stays valid and unattributed', () {
      telemetry.recordDetection(
        // Same call shape the pre-U3 writers used: no ref supplied.
        cupInfo(),
        10,
        engine: InferenceEngine.ultralytics,
      );
      telemetry.recordSample(
        latencyMs: 10,
        inferenceFps: 15,
        objectCount: 1,
        engine: InferenceEngine.ultralytics,
      );

      final record = telemetry.records.single;
      final sample = telemetry.samples.single;
      expect(record.detectorModelId, isNull);
      expect(record.detectorModelName, isNull);
      expect(record.detectorModelFingerprint, isNull);
      expect(sample.detectorModelId, isNull);
      // An unattributed row serialises without three empty keys.
      expect(record.toJson().containsKey('detectorModelId'), isFalse);
      expect(sample.toJson().containsKey('detectorModelId'), isFalse);
    });
  });
}
