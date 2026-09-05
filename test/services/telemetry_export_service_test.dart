import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:eyecue_flutter/models/app_settings.dart';
import 'package:eyecue_flutter/models/detection_correction.dart';
import 'package:eyecue_flutter/models/detection_info.dart';
import 'package:eyecue_flutter/models/detection_runtime_state.dart';
import 'package:eyecue_flutter/models/detection.dart';
import 'package:eyecue_flutter/models/inference_lifecycle_event.dart';
import 'package:eyecue_flutter/models/telemetry_export.dart';
import 'package:eyecue_flutter/services/telemetry_export_service.dart';
import 'package:eyecue_flutter/services/telemetry_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final timestamp = DateTime.utc(2026, 1, 1, 12, 0, 0);

  TelemetryService telemetry() {
    final service = TelemetryService(
      clock: () => timestamp,
      sessionId: 'session-test',
      appVersion: '1.2.3+4',
    );
    service.startSession();
    final info = DetectionInfo(
      detection: const Detection(
        classId: 41,
        label: 'cup, "blue"',
        confidence: 0.875,
        box: Rect.fromLTWH(0.1, 0.2, 0.3, 0.4),
      ),
      position: RelativePosition.left,
      priority: ObjectPriority.medium,
      proximity: ProximityBand.far,
    );
    service.recordDetection(
      info,
      42.5,
      engine: InferenceEngine.ultralytics,
      confidenceThreshold: 0.4,
    );
    service.recordSample(
      latencyMs: 42.5,
      inferenceFps: 15,
      objectCount: 1,
      engine: InferenceEngine.ultralytics,
      confidenceThreshold: 0.4,
    );
    service.recordFailure(
      DetectionFailure(
        category: DetectionFailureCategory.modelLoading,
        safeMessage: 'The model could not be loaded.',
        technicalDetail: '/private/path should not export',
        engine: InferenceEngine.ultralytics,
        retryCount: 2,
        timestamp: timestamp,
        fallbackAvailable: true,
      ),
    );
    service.recordFallback(
      preferredEngine: InferenceEngine.ultralytics,
      activeEngine: InferenceEngine.custom,
      reason: 'Native engine unavailable, use Custom.',
    );
    service.recordRecovery(
      InferenceLifecycleEvent(
        type: InferenceLifecycleEventType.recovering,
        generation: 3,
        restartAttempt: 1,
        failure: DetectionFailure(
          category: DetectionFailureCategory.workerExited,
          safeMessage: 'The detection worker stopped unexpectedly.',
          technicalDetail: 'internal detail must not export',
          engine: InferenceEngine.custom,
          timestamp: timestamp,
        ),
      ),
    );
    service.recordCorrection(
      DetectionCorrection(
        recordId: 'correction-1',
        timestamp: timestamp,
        sessionId: 'session-test',
        engine: InferenceEngine.ultralytics,
        detection: info.detection,
        feedback: CorrectionFeedback.incorrect,
        correctedLabel: 'bottle',
        confidenceThreshold: 0.4,
      ),
    );
    return service;
  }

  test('JSON contains the versioned image-free export contract', () {
    final service = TelemetryExportService(clock: () => timestamp);
    final jsonText = service.toJson(
      telemetry: telemetry(),
      settings: const AppSettings(
        inferenceEngine: InferenceEngine.ultralytics,
        detectionConfidence: 0.4,
      ),
    );
    final decoded = jsonDecode(jsonText) as Map<String, dynamic>;
    final session = decoded['session'] as Map<String, dynamic>;
    final failure = (decoded['failures'] as List).single as Map;

    expect(decoded['schemaVersion'], 1);
    expect(decoded['appVersion'], '1.2.3+4');
    expect(session['id'], 'session-test');
    expect(decoded['settings']['detectionConfidence'], 0.4);
    expect((decoded['detections'] as List).single['engine'], 'ultralytics');
    expect((decoded['corrections'] as List).single['confidenceThreshold'], 0.4);
    expect(failure['safeMessage'], 'The model could not be loaded.');
    expect(failure.containsKey('technicalDetail'), isFalse);
    expect((decoded['recoveries'] as List).single['type'], 'recovering');
    expect(
      (decoded['recoveries'] as List).single.containsKey('technicalDetail'),
      isFalse,
    );
    expect(jsonText, endsWith('\n'));
  });

  test('JSON export round-trips through the immutable DTO', () {
    final service = TelemetryExportService(clock: () => timestamp);
    final original = service.snapshot(telemetry: telemetry());
    final decoded =
        jsonDecode(jsonEncode(original.toJson())) as Map<String, dynamic>;
    final restored = TelemetryExport.fromJson(decoded);

    expect(restored.appVersion, original.appVersion);
    expect(restored.sessionId, original.sessionId);
    expect(restored.samples, hasLength(1));
    expect(restored.detections, hasLength(1));
    expect(restored.failures, hasLength(1));
    expect(restored.fallbacks, hasLength(1));
    expect(restored.recoveries, hasLength(1));
    expect(restored.corrections, hasLength(1));
  });

  test('CSV quotes punctuation, quotes, and Unicode safely', () {
    final service = TelemetryExportService(clock: () => timestamp);
    final csv = service.toCsv(telemetry: telemetry());

    expect(csv.split('\n').first, contains('record_type'));
    expect(csv.split('\n').first, contains('confidence_threshold'));
    expect(csv.split('\n').first, isNot(contains('field_1')));
    expect(csv, contains('"cup, ""blue"""'));
    expect(csv, contains('"Native engine unavailable, use Custom."'));
    expect(csv, isNot(contains('/private/path should not export')));
  });

  test('writes JSON and CSV to an explicitly supplied directory', () async {
    final directory = await Directory.systemTemp.createTemp('eyecue-export-');
    addTearDown(() => directory.delete(recursive: true));
    final exporter = TelemetryExportService(clock: () => timestamp);

    final jsonFile = await exporter.writeJson(
      telemetry: telemetry(),
      directory: directory,
    );
    final csvFile = await exporter.writeCsv(
      telemetry: telemetry(),
      directory: directory,
    );

    expect(await jsonFile.exists(), isTrue);
    expect(await csvFile.exists(), isTrue);
    expect(await jsonFile.readAsString(), contains('"schemaVersion": 1'));
    expect(await csvFile.readAsString(), contains('record_type'));
  });
}
