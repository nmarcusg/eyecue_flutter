import 'dart:io';
import 'dart:ui' show Rect;

import 'package:eyecue_flutter/models/app_settings.dart';
import 'package:eyecue_flutter/models/detection.dart';
import 'package:eyecue_flutter/models/detector_model.dart';
import 'package:eyecue_flutter/services/assistive_detection_controller.dart';
import 'package:eyecue_flutter/services/detector_model_service.dart';
import 'package:eyecue_flutter/services/research_session_service.dart';
import 'package:eyecue_flutter/services/settings_service.dart';
import 'package:eyecue_flutter/services/telemetry_export_service.dart';
import 'package:eyecue_flutter/services/telemetry_service.dart';
import 'package:eyecue_flutter/services/tts_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// Cross-unit regression coverage for one identity rule: every recorded row,
/// every trial summary and every export keeps the model that produced it, and
/// no exported byte names a file.

const String _assetPath = 'assets/yolov8n_int8_new_metadata.tflite';

/// Confirms start and completion immediately, so a test never waits on speech.
class _QuietTtsEngine extends TtsEngine {
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
  /// The bundled detector, resolved through the same `ref` the screen uses.
  DetectorModel builtInModel() =>
      DetectorModel.builtIn(List.generate(80, (index) => 'class$index'));

  /// A researcher-imported graph. Its path is what must never be exported.
  DetectorModel customModel({
    String name = 'Obstacle Detector v2',
    String fingerprint = '0a1b2c3d4e5f6071-4200',
  }) => DetectorModel(
    kind: DetectorModelKind.custom,
    displayName: name,
    fingerprint: fingerprint,
    labels: const ['cone', 'mug'],
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

  test('built-in → custom → built-in keeps each record\'s identity', () async {
    final tts = TtsService(engine: _QuietTtsEngine());
    await tts.init();
    addTearDown(tts.dispose);
    final now = DateTime.utc(2026, 3, 1, 9);
    final telemetry = TelemetryService(
      clock: () => now,
      sessionId: 'session-cross-unit',
    );
    addTearDown(telemetry.dispose);
    final builtIn = builtInModel();
    final custom = customModel();
    final controller = AssistiveDetectionController(
      engine: InferenceEngine.ultralytics,
      tts: tts,
      telemetry: telemetry,
      detectorModel: builtIn.ref,
    );
    addTearDown(controller.dispose);

    controller.updateDetections(cup(), latencyMs: 10);
    controller.detectorModel = custom.ref;
    controller.updateDetections(cup(), latencyMs: 20);
    controller.detectorModel = builtIn.ref;
    controller.updateDetections(cup(), latencyMs: 30);

    final rows = telemetry.records;
    expect(rows, hasLength(3));
    expect(rows.map((row) => row.detectorModelId), [
      'builtin',
      custom.ref.id,
      'builtin',
    ]);
    expect(rows.map((row) => row.detectorModelName), [
      'Built-in YOLOv8n',
      'Obstacle Detector v2',
      'Built-in YOLOv8n',
    ]);

    // The export keeps one dictionary entry per identity and every row
    // resolves through it to the name it was recorded with.
    final export = TelemetryExportService(
      clock: () => now,
    ).snapshot(telemetry: telemetry);
    expect(export.detectorModels.keys, ['builtin', custom.ref.id]);
    expect(export.detectorModels['builtin']!['name'], 'Built-in YOLOv8n');
    expect(
      export.detectorModels[custom.ref.id]!['name'],
      'Obstacle Detector v2',
    );
    expect(export.detections.map((row) => row['detectorModelId']), [
      'builtin',
      custom.ref.id,
      'builtin',
    ]);
    for (final row in export.detections) {
      expect(
        export.detectorModels.containsKey(row['detectorModelId']),
        isTrue,
        reason: 'Row does not resolve through detectorModels: $row',
      );
    }
  });

  test(
    'a trial spanning a model change exports every row against its model',
    () async {
      var now = DateTime.utc(2026, 3, 1, 10);
      final tts = TtsService(engine: _QuietTtsEngine());
      await tts.init();
      addTearDown(tts.dispose);
      final telemetry = TelemetryService(
        clock: () => now,
        sessionId: 'session-trial',
      );
      addTearDown(telemetry.dispose);
      telemetry.startSession();
      final builtIn = builtInModel();
      final custom = customModel();
      final controller = AssistiveDetectionController(
        engine: InferenceEngine.ultralytics,
        tts: tts,
        telemetry: telemetry,
        detectorModel: builtIn.ref,
      );
      addTearDown(controller.dispose);
      final sessions = ResearchSessionService(
        telemetry: telemetry,
        store: InMemoryResearchSessionStore(),
        clock: () => now,
      );
      addTearDown(sessions.dispose);

      await sessions.start(
        participantCode: 'P-001',
        trialLabel: 'trial-1',
        detector: builtIn.ref,
      );
      controller.updateDetections(cup(), latencyMs: 10);
      now = now.add(const Duration(seconds: 2));

      // The researcher changes models mid-trial: logging pauses at the boundary.
      await sessions.noteDetectorChange(custom.ref);
      expect(sessions.state, ResearchSessionState.paused);
      now = now.add(const Duration(seconds: 1));
      controller.detectorModel = custom.ref;
      // Setup inference after the swap belongs to no interval.
      controller.updateDetections(cup(), latencyMs: 20);
      now = now.add(const Duration(seconds: 1));

      await sessions.resume();
      now = now.add(const Duration(seconds: 1));
      controller.updateDetections(cup(), latencyMs: 30);
      now = now.add(const Duration(seconds: 2));

      final session = (await sessions.finish())!.session;
      expect(session.detectors.map((detector) => detector.id), [
        'builtin',
        custom.ref.id,
      ]);
      expect(session.records.map((record) => record.detectorModelId), [
        'builtin',
        custom.ref.id,
      ]);

      final export = TelemetryExportService(
        clock: () => now,
      ).snapshot(telemetry: session);
      expect(export.detectorModels.keys, ['builtin', custom.ref.id]);
      expect(export.detections, hasLength(2));
      for (final row in export.detections) {
        expect(
          export.detectorModels.containsKey(row['detectorModelId']),
          isTrue,
          reason: 'Frozen trial row does not resolve: $row',
        );
      }
      expect(export.detections.last['detectorModelId'], custom.ref.id);
      expect(
        export.detectorModels[custom.ref.id]!['name'],
        'Obstacle Detector v2',
      );
    },
  );

  test(
    'an imported model exports its readable name and no file details',
    () async {
      final dir = Directory.systemTemp.createTempSync('eyecue-cross-unit');
      addTearDown(() {
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      });

      // A real import through the production path: validate, stage, commit.
      final settings = SettingsService(store: InMemorySettingsStore());
      final bytes = File(_assetPath).readAsBytesSync();
      final fingerprint = tfliteFingerprint(bytes);
      final coco = List<String>.generate(80, (index) => 'class$index');
      final source = File('${dir.path}/picked.tflite')..writeAsBytesSync(bytes);
      final service = DetectorModelService(
        settings,
        builtInLabelsLoader: () async => coco,
        inspect: (path) async => {'task': 'detect', 'labels': coco},
        modelsDirectory: () async => Directory('${dir.path}/eyecue_models'),
        fingerprintReader: (file) async => fingerprint,
      );
      addTearDown(service.dispose);
      await settings.load();
      await service.load();
      final imported = await service.importFromPath(
        source.path,
        displayName: 'Obstacle Detector v2',
      );
      expect(imported.ok, isTrue);
      expect(service.current.isCustom, isTrue);

      final now = DateTime.utc(2026, 3, 1, 11);
      final tts = TtsService(engine: _QuietTtsEngine());
      await tts.init();
      addTearDown(tts.dispose);
      final telemetry = TelemetryService(
        clock: () => now,
        sessionId: 'session-custom',
      );
      addTearDown(telemetry.dispose);
      telemetry.startSession();
      final controller = AssistiveDetectionController(
        engine: InferenceEngine.ultralytics,
        tts: tts,
        telemetry: telemetry,
        detectorModel: service.current.ref,
      );
      addTearDown(controller.dispose);
      controller.updateDetections(cup(), latencyMs: 12);

      final exporter = TelemetryExportService(clock: () => now);
      final json = exporter.toJson(telemetry: telemetry);
      final csv = exporter.toCsv(telemetry: telemetry);
      final modelPath = service.current.path;

      // No path, URI or file name crosses the boundary in either format.
      for (final body in [json, csv]) {
        expect(body.contains(modelPath), isFalse);
        expect(body.contains(dir.path), isFalse);
        expect(body.contains('.tflite'), isFalse);
        expect(body.contains('file://'), isFalse);
      }

      // The readable name is what the dictionary and the CSV column carry.
      final export = exporter.snapshot(telemetry: telemetry);
      expect(export.detectorModels, hasLength(1));
      expect(
        export.detectorModels.values.single['name'],
        'Obstacle Detector v2',
      );
      expect(csv, contains('"Obstacle Detector v2"'));
      expect(csv, contains('"${service.current.ref.id}"'));
    },
  );
}
