import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:eyecue_flutter/models/alert_lifecycle.dart';
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
      requestedDetectionHz: 8,
      effectiveDetectionHz: 5,
      requestedDepthHz: 4,
      effectiveDepthHz: 2,
      depthObservedHz: 1.5,
      depthLatencyMs: 90,
      depthStatus: 'gpu',
      lowPowerClamped: true,
      sourceLimited: true,
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
      activeEngine: InferenceEngine.ultralytics,
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
          engine: InferenceEngine.ultralytics,
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
    service.recordAlertLifecycle(
      AlertLifecycleRecord(
        origin: AlertOrigin.detection,
        engine: InferenceEngine.ultralytics,
        requestedAt: timestamp,
        submittedAt: timestamp.add(const Duration(milliseconds: 100)),
        alertStartedAt: timestamp.add(const Duration(milliseconds: 150)),
        terminalAt: timestamp.add(const Duration(seconds: 1)),
        terminalState: AlertTerminalState.completed,
        terminalCause: null,
        hadStarted: true,
        reconciledAt: timestamp.add(const Duration(seconds: 1)),
        frameNumber: 7,
        resultReceivedAt: timestamp.add(const Duration(milliseconds: 80)),
        detectionAcceptedAt: timestamp.add(const Duration(milliseconds: 90)),
      ),
    );
    service.recordAlertCounters(
      const AlertCounters(
        dropped: 1,
        muted: 2,
        rejectedByReason: {'lowConfidence': 3},
      ),
    );
    addTearDown(service.dispose);
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

    expect(decoded['schemaVersion'], 3);
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

    final lifecycle = (decoded['alertLifecycle'] as List).single as Map;
    expect(lifecycle['engine'], 'ultralytics');
    expect(lifecycle['terminalState'], 'completed');
    final counters = decoded['alertCounters'] as Map<String, dynamic>;
    expect(counters['dropped'], 1);
    expect((counters['rejectedByReason'] as Map)['lowConfidence'], 3);
    final summaries = decoded['alertSummaries'] as List;
    expect(summaries, hasLength(4));
    expect(
      (summaries.first as Map).keys,
      containsAll([
        'engine',
        'interval',
        'label',
        'p50Ms',
        'p95Ms',
        'maxMs',
        'sampleCount',
      ]),
    );
    // The new lifecycle payload stays image-free and detail-free.
    for (final key in [
      'box',
      'image',
      'technicalDetail',
      'utterance',
      'deviceId',
      'path',
    ]) {
      expect(lifecycle.containsKey(key), isFalse);
    }
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
    expect(restored.alertLifecycle, hasLength(1));
    expect(restored.alertCounters['dropped'], 1);
    expect(restored.alertSummaries, hasLength(4));
  });

  test('schema-v1 JSON parses with safe empty alert defaults', () {
    final restored = TelemetryExport.fromJson({
      'schemaVersion': 1,
      'exportedAt': timestamp.toUtc().toIso8601String(),
      'appVersion': '1.0.0+1',
      'session': {
        'id': 'legacy-session',
        'start': timestamp.toUtc().toIso8601String(),
        'durationMs': 0,
      },
      'settings': <String, dynamic>{},
      'samples': <dynamic>[],
      'detections': <dynamic>[],
      'failures': <dynamic>[],
      'fallbacks': <dynamic>[],
      'recoveries': <dynamic>[],
      'corrections': <dynamic>[],
    });

    expect(restored.sessionId, 'legacy-session');
    expect(restored.alertLifecycle, isEmpty);
    expect(restored.alertSummaries, isEmpty);
    expect(restored.alertCounters['dropped'], 0);
    expect(restored.alertCounters['rejectedByReason'], isEmpty);
    expect(TelemetryExport.schemaVersion, 3);
  });

  test('schema-v2 JSON round-trips alert payloads exactly', () {
    final service = TelemetryExportService(clock: () => timestamp);
    final original = service.snapshot(telemetry: telemetry());
    final restored = TelemetryExport.fromJson(
      jsonDecode(jsonEncode(original.toJson())) as Map<String, dynamic>,
    );

    expect(restored.toJson(), original.toJson());
  });

  test('CSV adds lifecycle, counter, and summary rows without loss', () {
    final service = TelemetryExportService(clock: () => timestamp);
    final csv = service.toCsv(telemetry: telemetry());
    final header = csv.split('\n').first;

    for (final column in [
      'origin',
      'terminal_state',
      'analysis_received_at',
      'p50_ms',
      'p95_ms',
      'max_ms',
      'sample_count',
      'counter_name',
      'counter_value',
    ]) {
      expect(header, contains(column));
    }
    expect(csv, contains('"alert_lifecycle"'));
    expect(csv, contains('"alert_counter"'));
    expect(csv, contains('"alert_summary"'));
    expect(csv, contains('"rejectedByReason"'));
    expect(csv, contains('"lowConfidence"'));
    expect(csv, contains('app-side / post-inference'));
    // Existing row types remain present alongside the additive rows.
    expect(csv, contains('"detection"'));
    expect(csv, contains('"sample"'));
    expect(csv, contains('"correction"'));
    // Privacy: no exception detail or internal paths in the alert payloads.
    expect(csv, isNot(contains('technicalDetail')));
    expect(csv, isNot(contains('/private/path')));
    expect(csv, isNot(contains('internal detail')));
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

  test('sample JSON rows carry the ten inference cadence keys', () {
    final service = TelemetryExportService(clock: () => timestamp);
    final decoded = jsonDecode(service.toJson(telemetry: telemetry())) as Map;
    final sample = (decoded['samples'] as List).single as Map;

    expect(sample['requestedDetectionHz'], 8);
    expect(sample['detectionCadenceAutomatic'], isFalse);
    expect(sample['effectiveDetectionHz'], 5);
    expect(sample['requestedDepthHz'], 4);
    expect(sample['effectiveDepthHz'], 2);
    expect(sample['depthObservedHz'], 1.5);
    expect(sample['depthLatencyMs'], 90);
    expect(sample['depthStatus'], 'gpu');
    expect(sample['lowPowerClamped'], isTrue);
    expect(sample['sourceLimited'], isTrue);
  });

  test('automatic and unobserved cadence values stay null, never zero', () {
    final service = TelemetryService(
      clock: () => timestamp,
      sessionId: 'automatic-session',
    );
    addTearDown(service.dispose);
    service.recordSample(
      latencyMs: 10,
      inferenceFps: 5,
      objectCount: 0,
      engine: InferenceEngine.ultralytics,
      detectionCadenceAutomatic: true,
    );

    final exporter = TelemetryExportService(clock: () => timestamp);
    final decoded = jsonDecode(exporter.toJson(telemetry: service)) as Map;
    final sample = (decoded['samples'] as List).single as Map;

    expect(sample['requestedDetectionHz'], isNull);
    expect(sample['detectionCadenceAutomatic'], isTrue);
    expect(sample['effectiveDetectionHz'], isNull);
    expect(sample['depthObservedHz'], isNull);
    expect(sample['depthLatencyMs'], isNull);
    expect(sample['depthStatus'], isNull);

    // The same absent values are empty CSV cells, not zeros.
    final header = exporter
        .toCsv(telemetry: service)
        .split('\n')
        .first
        .split(',');
    final sampleRow = exporter
        .toCsv(telemetry: service)
        .split('\n')
        .firstWhere((line) => line.startsWith('"sample"'))
        .split(',');
    for (final column in [
      'requested_detection_hz',
      'effective_detection_hz',
      'depth_observed_hz',
      'depth_latency_ms',
      'depth_status',
    ]) {
      expect(sampleRow[header.indexOf('"$column"')], '""');
    }
  });

  test('CSV appends cadence columns and keeps rows aligned', () {
    final service = TelemetryExportService(clock: () => timestamp);
    final lines = service.toCsv(telemetry: telemetry()).split('\n');
    final header = lines.first.split(',');
    final sampleRow = lines
        .firstWhere((line) => line.startsWith('"sample"'))
        .split(',');
    int column(String name) => header.indexOf('"$name"');

    for (final name in [
      'requested_detection_hz',
      'detection_cadence_automatic',
      'effective_detection_hz',
      'requested_depth_hz',
      'effective_depth_hz',
      'depth_observed_hz',
      'depth_latency_ms',
      'depth_status',
      'low_power_clamped',
      'source_limited',
    ]) {
      expect(column(name), isNot(-1));
    }
    expect(sampleRow, hasLength(header.length));
    expect(sampleRow[column('requested_detection_hz')], '"8"');
    expect(sampleRow[column('detection_cadence_automatic')], '"false"');
    expect(sampleRow[column('effective_depth_hz')], '"2"');
    expect(sampleRow[column('depth_status')], '"gpu"');
    expect(sampleRow[column('low_power_clamped')], '"true"');

    // Other record types leave every cadence column empty.
    final failureRow = lines
        .firstWhere((line) => line.startsWith('"failure"'))
        .split(',');
    expect(failureRow, hasLength(header.length));
    expect(failureRow[column('requested_detection_hz')], '""');
    expect(failureRow[column('depth_status')], '""');
  });

  test('a v2-shaped sample without cadence keys exports cleanly', () {
    final v2Sample = <String, dynamic>{
      'timestamp': timestamp.toUtc().toIso8601String(),
      'latencyMs': 42.5,
      'inferenceFps': 15.0,
      'objectCount': 1,
      'engine': 'ultralytics',
      'confidenceThreshold': 0.4,
    };
    final restored = TelemetryExport.fromJson({
      'schemaVersion': 2,
      'exportedAt': timestamp.toUtc().toIso8601String(),
      'appVersion': '2.0.0+2',
      'session': {'id': 'v2-session', 'start': null, 'durationMs': 0},
      'settings': <String, dynamic>{},
      'samples': [v2Sample],
    });

    expect(restored.samples.single['requestedDetectionHz'], isNull);
    expect(restored.samples.single['depthStatus'], isNull);
    // Unchanged rows re-serialize without synthesizing cadence values.
    expect(restored.toJson()['samples'], [v2Sample]);
    expect(() => jsonEncode(restored.toJson()), returnsNormally);
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
    expect(await jsonFile.readAsString(), contains('"schemaVersion": 3'));
    expect(await csvFile.readAsString(), contains('record_type'));
  });
}
