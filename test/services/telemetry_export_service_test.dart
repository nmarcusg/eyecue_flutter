import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:eyecue_flutter/models/alert_lifecycle.dart';
import 'package:eyecue_flutter/models/app_settings.dart';
import 'package:eyecue_flutter/models/detection_correction.dart';
import 'package:eyecue_flutter/models/detection_info.dart';
import 'package:eyecue_flutter/models/detection_runtime_state.dart';
import 'package:eyecue_flutter/models/detection.dart';
import 'package:eyecue_flutter/models/detector_model.dart';
import 'package:eyecue_flutter/models/inference_lifecycle_event.dart';
import 'package:eyecue_flutter/models/telemetry_export.dart';
import 'package:eyecue_flutter/services/detector_model_service.dart';
import 'package:eyecue_flutter/services/telemetry_export_service.dart';
import 'package:eyecue_flutter/services/telemetry_service.dart';
import 'package:eyecue_flutter/services/telemetry_upload_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final timestamp = DateTime.utc(2026, 1, 1, 12, 0, 0);
  const engine = InferenceEngine.ultralytics;

  /// The bundled detector's identity, as the detection screen supplies it.
  const builtInRef = DetectorModelRef(
    id: 'builtin',
    name: 'Built-in YOLOv8n',
    fingerprint: DetectorModel.builtInFingerprint,
    classCount: 80,
  );

  /// A researcher import: readable name plus content fingerprint.
  const customRef = DetectorModelRef(
    id: 'custom:0a1b2c3d4e5f',
    name: 'Obstacle Detector v2',
    fingerprint: '0a1b2c3d4e5f6071-4200',
    classCount: 12,
  );

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
      detectorPreMs: 3.5,
      detectorInferenceMs: 28.25,
      detectorPostMs: 4.75,
      depthPreMs: 6,
      depthInferenceMs: 61,
      depthPostMs: 9,
      depthAccelerator: 'gpu',
      depthGridWidth: 96,
      depthGridHeight: 72,
      heatmapBuildMs: 11,
      depthDroppedTicks: 37,
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

    expect(decoded['schemaVersion'], 4);
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
    expect(TelemetryExport.schemaVersion, 4);
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
    expect(sample['requestedDepthHz'], isNull);
    expect(sample['effectiveDepthHz'], isNull);
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
      'requested_depth_hz',
      'effective_depth_hz',
      'depth_observed_hz',
      'depth_latency_ms',
      'depth_status',
      'detector_pre_ms',
      'detector_inference_ms',
      'detector_post_ms',
      'depth_pre_ms',
      'depth_inference_ms',
      'depth_post_ms',
      'depth_accelerator',
      'depth_grid_width',
      'depth_grid_height',
      'heatmap_build_ms',
      'depth_dropped_ticks',
    ]) {
      expect(sampleRow[header.indexOf('"$column"')], '""');
    }

    // The same unknown values are null in JSON, never a fabricated `0`.
    expect(sample['detectorPreMs'], isNull);
    expect(sample['detectorInferenceMs'], isNull);
    expect(sample['depthPreMs'], isNull);
    expect(sample['depthAccelerator'], isNull);
    expect(sample['depthGridWidth'], isNull);
    expect(sample['heatmapBuildMs'], isNull);
    expect(sample['depthDroppedTicks'], isNull);
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

  test(
    'sample rows carry the schema-4 stage timings and depth transport keys',
    () {
      final service = TelemetryExportService(clock: () => timestamp);
      final decoded = jsonDecode(service.toJson(telemetry: telemetry())) as Map;
      final sample = (decoded['samples'] as List).single as Map;

      expect(sample['detectorPreMs'], 3.5);
      expect(sample['detectorInferenceMs'], 28.25);
      expect(sample['detectorPostMs'], 4.75);
      expect(sample['depthPreMs'], 6);
      expect(sample['depthInferenceMs'], 61);
      expect(sample['depthPostMs'], 9);
      expect(sample['depthAccelerator'], 'gpu');
      expect(sample['depthGridWidth'], 96);
      expect(sample['depthGridHeight'], 72);
      expect(sample['heatmapBuildMs'], 11);
      // Cumulative native counter, not a per-sample drop count.
      expect(sample['depthDroppedTicks'], 37);
      // Neither a duplicate of `inferenceFps` nor a Dart-side queue wait is
      // exported: both were constant padding that the ingest bound cannot carry.
      expect(sample.containsKey('detectorObservedFps'), isFalse);
      expect(sample.containsKey('depthQueueWaitMs'), isFalse);

      final lines = service.toCsv(telemetry: telemetry()).split('\n');
      final header = lines.first.split(',');
      final row = lines
          .firstWhere((line) => line.startsWith('"sample"'))
          .split(',');
      int column(String name) => header.indexOf('"$name"');
      expect(row[column('detector_inference_ms')], '"28.25"');
      expect(row[column('depth_accelerator')], '"gpu"');
      expect(row[column('depth_dropped_ticks')], '"37"');
      expect(column('detector_observed_fps'), -1);
      expect(column('depth_queue_wait_ms'), -1);
      expect(row, hasLength(header.length));
    },
  );

  test('tertiary perf keys are thinned to every fifth sample', () {
    final service = TelemetryService(clock: () => timestamp);
    addTearDown(service.dispose);
    service.startSession();
    for (var i = 0; i < 6; i++) {
      service.recordSample(
        latencyMs: 42.5,
        inferenceFps: 15,
        objectCount: 1,
        engine: InferenceEngine.ultralytics,
        detectorPreMs: 3.5,
        depthAccelerator: 'gpu',
        heatmapBuildMs: 11,
        depthDroppedTicks: 37,
      );
    }

    final exporter = TelemetryExportService(clock: () => timestamp);
    final samples =
        (jsonDecode(exporter.toJson(telemetry: service)) as Map)['samples']
            as List;

    // Every fifth sample (0 and 5) carries the tertiary perf keys.
    for (final index in [0, 5]) {
      final sample = samples[index] as Map;
      expect(sample['detectorPreMs'], 3.5);
      expect(sample['depthAccelerator'], 'gpu');
      expect(sample['heatmapBuildMs'], 11);
      expect(sample['depthDroppedTicks'], 37);
    }
    // The samples between them do not: sample N keeps the keys, N+1 does not.
    for (var index = 1; index < 5; index++) {
      final sample = samples[index] as Map;
      expect(sample.containsKey('detectorPreMs'), isFalse);
      expect(sample.containsKey('depthAccelerator'), isFalse);
      expect(sample.containsKey('heatmapBuildMs'), isFalse);
      expect(sample.containsKey('depthDroppedTicks'), isFalse);
    }
    // The core cadence/telemetry fields stay on every sample.
    for (final sample in samples) {
      expect((sample as Map)['latencyMs'], 42.5);
      expect(sample['inferenceFps'], 15);
      expect(sample['timestamp'], isNotNull);
    }
  });

  test(
    'a schema-3 sample without the new keys reads as unknown, never zero',
    () {
      final v3Sample = <String, dynamic>{
        'timestamp': timestamp.toUtc().toIso8601String(),
        'latencyMs': 42.5,
        'inferenceFps': 15.0,
        'objectCount': 1,
        'engine': 'ultralytics',
        'confidenceThreshold': 0.4,
        'depthStatus': 'cpu',
        'depthLatencyMs': 90,
        'depthObservedHz': 1.5,
      };
      final restored = TelemetryExport.fromJson({
        'schemaVersion': 3,
        'exportedAt': timestamp.toUtc().toIso8601String(),
        'appVersion': '1.3.0+5',
        'session': {'id': 'v3-session', 'start': null, 'durationMs': 1000},
        'settings': <String, dynamic>{},
        'samples': [v3Sample],
      });

      for (final key in const [
        'detectorPreMs',
        'detectorInferenceMs',
        'detectorPostMs',
        'depthPreMs',
        'depthInferenceMs',
        'depthPostMs',
        'depthAccelerator',
        'depthGridWidth',
        'depthGridHeight',
        'heatmapBuildMs',
        'depthDroppedTicks',
      ]) {
        expect(
          restored.samples.single[key],
          isNull,
          reason: '$key stays unknown',
        );
      }
      // The old row is carried through untouched: no key is synthesised as `0`.
      expect(restored.toJson()['samples'], [v3Sample]);
      expect(() => jsonEncode(restored.toJson()), returnsNormally);
    },
  );

  test('a worst-case session serialises below the payload ceiling', () async {
    final service = TelemetryService(
      clock: () => timestamp,
      sessionId: 'session-worst-case',
      appVersion: '1.2.3+4',
    );
    addTearDown(service.dispose);
    service.startSession();
    final info = DetectionInfo(
      // Device-shaped: Float32-derived doubles, not tidy literals.
      detection: const Detection(
        classId: 41,
        label: 'a-rather-long-coco-label-name-for-the-worst-case',
        confidence: 0.8700000047683716,
        box: Rect.fromLTWH(
          0.11363636363636363,
          0.22656200000000002,
          0.34545454545454546,
          0.43750000000000006,
        ),
      ),
      position: RelativePosition.left,
      priority: ObjectPriority.medium,
      proximity: ProximityBand.far,
    );
    for (var i = 0; i < 2000; i++) {
      service.recordDetection(
        info,
        42.5,
        engine: InferenceEngine.ultralytics,
        confidenceThreshold: 0.4,
      );
    }
    for (var i = 0; i < 500; i++) {
      service.recordSample(
        latencyMs: 42.5,
        inferenceFps: 15,
        objectCount: 3,
        engine: InferenceEngine.ultralytics,
        confidenceThreshold: 0.4,
        requestedDetectionHz: 8,
        effectiveDetectionHz: 5,
        requestedDepthHz: 4,
        effectiveDepthHz: 2,
        depthObservedHz: 1.5,
        depthLatencyMs: 90,
        depthStatus: 'gpu',
        detectorPreMs: 3.5,
        detectorInferenceMs: 28.25,
        detectorPostMs: 4.75,
        depthPreMs: 6,
        depthInferenceMs: 61,
        depthPostMs: 9,
        depthAccelerator: 'gpu',
        depthGridWidth: 96,
        depthGridHeight: 72,
        heatmapBuildMs: 11,
        depthDroppedTicks: 37,
        lowPowerClamped: true,
        sourceLimited: true,
      );
    }
    for (var i = 0; i < 500; i++) {
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
    }
    service.recordAlertCounters(
      const AlertCounters(dropped: 1, muted: 2, rejectedByReason: {'x': 3}),
    );

    final exporter = TelemetryExportService(clock: () => timestamp);
    final jsonText = exporter.toJson(telemetry: service);
    // The ingest ceiling (2 000 000 bytes) and the 1 500 000-byte target apply
    // to the wire form, so measure the compact encoding, not the indented file
    // export (whose whitespace is presentation only).
    final bytes = utf8.encode(jsonEncode(jsonDecode(jsonText))).length;
    // ignore: avoid_print
    print('worst-case telemetry payload: $bytes UTF-8 bytes (compact)');
    expect(bytes, lessThan(1500000), reason: 'measured $bytes bytes');

    final decoded = jsonDecode(jsonText) as Map;
    expect(decoded['samples'], hasLength(400));
    expect(decoded['detections'], hasLength(2000));
    expect(decoded['alertLifecycle'], hasLength(500));

    final lower = jsonText.toLowerCase();
    for (final token in const [
      'image',
      'images',
      'deviceid',
      'path',
      'utterance',
      'technicaldetail',
      'screenshot',
      'audio',
      'frame',
      'secret',
      'token',
    ]) {
      // `frameNumber` is a pre-existing counter key, not frame content.
      final pattern = token == 'frame'
          ? RegExp('frame(?!number)')
          : RegExp(RegExp.escape(token));
      expect(
        pattern.hasMatch(lower),
        isFalse,
        reason: 'the serialised payload must not carry "$token"',
      );
    }
  });

  test('serialised numbers follow the documented precision contract', () {
    final service = TelemetryService(
      clock: () => timestamp,
      sessionId: 'session-precision',
      appVersion: '1.2.3+4',
    );
    addTearDown(service.dispose);
    service.startSession();
    // Device-shaped values: what a Float32 plugin value divided in double
    // arithmetic actually serialises as (17–19 characters each).
    const box = Rect.fromLTWH(
      0.34545454545454546,
      0.22656200000000002,
      0.11363636363636363,
      0.43750000000000006,
    );
    const detection = Detection(
      classId: 41,
      label: 'cup',
      confidence: 0.8700000047683716,
      box: box,
    );
    final info = DetectionInfo(
      detection: detection,
      position: RelativePosition.left,
      priority: ObjectPriority.medium,
      proximity: ProximityBand.far,
    );
    service.recordDetection(
      info,
      42.519999999999996,
      engine: InferenceEngine.ultralytics,
      confidenceThreshold: 0.40000000000000002,
    );
    service.recordSample(
      latencyMs: 42.519999999999996,
      inferenceFps: 12.499999999999998,
      objectCount: 1,
      engine: InferenceEngine.ultralytics,
      confidenceThreshold: 0.40000000000000002,
      depthObservedHz: 1.7999999999999998,
    );
    service.recordCorrection(
      DetectionCorrection(
        recordId: 'correction-1',
        timestamp: timestamp,
        sessionId: 'session-precision',
        engine: InferenceEngine.ultralytics,
        detection: detection,
        feedback: CorrectionFeedback.correct,
        correctedLabel: 'cup',
        confidenceThreshold: 0.40000000000000002,
      ),
    );

    final exporter = TelemetryExportService(clock: () => timestamp);
    final export = exporter.snapshot(telemetry: service);
    final jsonText = jsonEncode(export.toJson());

    // Contract: boxes 4 dp, scores 3 dp, milliseconds and Hz 1 dp.
    final row = export.detections.single;
    expect(row['confidence'], 0.87);
    expect(row['latencyMs'], 42.5);
    expect(row['confidenceThreshold'], 0.4);
    expect(row['box'], {
      'left': 0.3455,
      'top': 0.2266,
      'width': 0.1136,
      'height': 0.4375,
    });
    final correction = export.corrections.single;
    expect(correction['confidenceThreshold'], 0.4);
    expect((correction['detection'] as Map)['confidence'], 0.87);
    expect((correction['detection'] as Map)['box'], {
      'left': 0.3455,
      'top': 0.2266,
      'width': 0.1136,
      'height': 0.4375,
    });
    final sample = export.samples.single;
    expect(sample['latencyMs'], 42.5);
    expect(sample['inferenceFps'], 12.5);
    expect(sample['depthObservedHz'], 1.8);
    expect(sample['confidenceThreshold'], 0.4);
    expect(
      jsonText,
      isNot(contains('0.34545454545454546')),
      reason: 'no unbounded device double may reach the payload',
    );

    // Rounding is serialisation-only: the stored samples keep full precision,
    // so banding, comparisons and speech text are unaffected.
    final stored = service.records.single;
    expect(stored.box!.left, 0.34545454545454546);
    expect(stored.confidence, 0.8700000047683716);
    expect(stored.latencyMs, 42.519999999999996);
    expect(service.samples.single.inferenceFps, 12.499999999999998);
    expect(stored.box, box, reason: 'the stored Rect is untouched');
  });

  test('exports keep the readable name and fingerprint association', () {
    final service = TelemetryService(
      clock: () => timestamp,
      sessionId: 'session-models',
    );
    addTearDown(service.dispose);
    service.startSession();
    final info = DetectionInfo(
      detection: const Detection(
        classId: 3,
        label: 'cone',
        confidence: 0.8,
        box: Rect.fromLTWH(0.1, 0.1, 0.2, 0.2),
      ),
      position: RelativePosition.center,
      priority: ObjectPriority.medium,
      proximity: ProximityBand.near,
    );
    for (final ref in [builtInRef, customRef]) {
      service.recordDetection(info, 40, engine: engine, detectorModel: ref);
      service.recordSample(
        latencyMs: 40,
        inferenceFps: 10,
        objectCount: 1,
        engine: engine,
        detectorModel: ref,
      );
    }

    final exporter = TelemetryExportService(clock: () => timestamp);
    final decoded =
        jsonDecode(exporter.toJson(telemetry: service)) as Map<String, dynamic>;
    final models = decoded['detectorModels'] as Map;
    expect(models.keys.toSet(), {builtInRef.id, customRef.id});
    expect(models[builtInRef.id], {
      'name': 'Built-in YOLOv8n',
      'fingerprint': DetectorModel.builtInFingerprint,
    });
    expect(models[customRef.id], {
      'name': 'Obstacle Detector v2',
      'fingerprint': customRef.fingerprint,
    });
    // Every row resolves through the table, and no row repeats the name.
    for (final key in ['samples', 'detections']) {
      for (final row in decoded[key] as List) {
        expect(models, contains((row as Map)['detectorModelId']));
        expect(row.containsKey('detectorModelName'), isFalse);
        expect(row.containsKey('detectorModelFingerprint'), isFalse);
      }
    }

    final lines = exporter.toCsv(telemetry: service).split('\n');
    final header = lines.first.split(',');
    int column(String name) => header.indexOf('"$name"');
    for (final name in ['model_id', 'model_name', 'model_fingerprint']) {
      expect(column(name), isNot(-1), reason: 'CSV carries $name');
    }
    final detectionRows = lines
        .where((line) => line.startsWith('"detection"'))
        .map((line) => line.split(','))
        .toList();
    expect(detectionRows, hasLength(2));
    for (final row in detectionRows) {
      final id = row[column('model_id')];
      final model = models[id.substring(1, id.length - 1)] as Map;
      expect(row[column('model_name')], '"${model['name']}"');
      expect(row[column('model_fingerprint')], '"${model['fingerprint']}"');
    }
    expect(detectionRows.first[column('model_name')], '"Built-in YOLOv8n"');
    expect(detectionRows.last[column('model_name')], '"Obstacle Detector v2"');
  });

  group('detector model identity', () {
    const info = DetectionInfo(
      detection: Detection(
        classId: 3,
        label: 'cone',
        confidence: 0.8,
        box: Rect.fromLTWH(0.1, 0.1, 0.2, 0.2),
      ),
      position: RelativePosition.center,
      priority: ObjectPriority.medium,
      proximity: ProximityBand.near,
    );

    /// One detection and one sample recorded under [ref].
    void record(TelemetryService service, DetectorModelRef ref) {
      service.recordDetection(info, 40, engine: engine, detectorModel: ref);
      service.recordSample(
        latencyMs: 40,
        inferenceFps: 10,
        objectCount: 1,
        engine: engine,
        detectorModel: ref,
      );
    }

    /// `[model_name, model_fingerprint]` of every detection row, in order.
    List<List<String>> detectionColumns(String csv) {
      final lines = csv.split('\n');
      final header = lines.first.split(',');
      int column(String name) => header.indexOf('"$name"');
      return [
        for (final line in lines)
          if (line.startsWith('"detection"'))
            [
              line.split(',')[column('model_id')],
              line.split(',')[column('model_name')],
              line.split(',')[column('model_fingerprint')],
            ],
      ];
    }

    test('one graph under two names keeps both names in JSON and CSV', () {
      final service = TelemetryService(
        clock: () => timestamp,
        sessionId: 'session-rename',
      );
      addTearDown(service.dispose);
      service.startSession();
      // Re-importing the same file under a corrected name: same content id and
      // fingerprint, different free-text name.
      const renamed = DetectorModelRef(
        id: 'custom:0a1b2c3d4e5f',
        name: 'Obstacle Detector v2 fixed',
        fingerprint: '0a1b2c3d4e5f6071-4200',
        classCount: 12,
      );
      record(service, customRef);
      record(service, renamed);

      final exporter = TelemetryExportService(clock: () => timestamp);
      final decoded =
          jsonDecode(exporter.toJson(telemetry: service))
              as Map<String, dynamic>;
      final models = (decoded['detectorModels'] as Map).cast<String, dynamic>();
      // One entry per identity, not per id, keyed in first-appearance order.
      expect(models.keys, [customRef.id, '${customRef.id}~2']);
      expect(models[customRef.id], {
        'name': 'Obstacle Detector v2',
        'fingerprint': customRef.fingerprint,
      });
      expect(models['${customRef.id}~2'], {
        'name': renamed.name,
        'fingerprint': renamed.fingerprint,
      });

      // The invariant: every exported row's key resolves to the name and
      // fingerprint that row was recorded with.
      final exported = [
        ...decoded['samples'] as List,
        ...decoded['detections'] as List,
      ];
      final recorded = [
        for (final sample in service.samples)
          (sample.detectorModelName, sample.detectorModelFingerprint),
        for (final record in service.records)
          (record.detectorModelName, record.detectorModelFingerprint),
      ];
      expect(exported, hasLength(recorded.length));
      for (var i = 0; i < exported.length; i++) {
        final key = (exported[i] as Map)['detectorModelId'] as String;
        expect(models[key]['name'], recorded[i].$1, reason: 'row $i name');
        expect(
          models[key]['fingerprint'],
          recorded[i].$2,
          reason: 'row $i fingerprint',
        );
      }

      // The CSV joins the same key, so each row carries its own name.
      final rows = detectionColumns(exporter.toCsv(telemetry: service));
      expect(rows, [
        [
          '"custom:0a1b2c3d4e5f"',
          '"Obstacle Detector v2"',
          '"0a1b2c3d4e5f6071-4200"',
        ],
        [
          '"custom:0a1b2c3d4e5f~2"',
          '"Obstacle Detector v2 fixed"',
          '"0a1b2c3d4e5f6071-4200"',
        ],
      ]);
    });

    test('two graphs sharing a display name stay distinct', () {
      const other = DetectorModelRef(
        id: 'custom:ffffffffffff',
        name: 'Obstacle Detector v2',
        fingerprint: 'ffffffffffff0000-4200',
        classCount: 12,
      );
      final service = TelemetryService(
        clock: () => timestamp,
        sessionId: 'session-same-name',
      );
      addTearDown(service.dispose);
      service.startSession();
      record(service, customRef);
      record(service, other);

      final exporter = TelemetryExportService(clock: () => timestamp);
      final decoded =
          jsonDecode(exporter.toJson(telemetry: service))
              as Map<String, dynamic>;
      final models = (decoded['detectorModels'] as Map).cast<String, dynamic>();
      expect(models.keys, [customRef.id, other.id]);
      expect(
        {for (final model in models.values) model['name']},
        {'Obstacle Detector v2'},
      );
      expect(models[customRef.id]['fingerprint'], customRef.fingerprint);
      expect(models[other.id]['fingerprint'], other.fingerprint);

      final rows = detectionColumns(exporter.toCsv(telemetry: service));
      expect(rows[0][2], '"0a1b2c3d4e5f6071-4200"');
      expect(rows[1][2], '"ffffffffffff0000-4200"');
    });
  });

  test(
    'the populated envelope carries no path, URI, filename or model bytes',
    () {
      final service = telemetry();
      service.recordDetection(
        DetectionInfo(
          detection: const Detection(
            classId: 0,
            label: 'class-0',
            confidence: 0.7,
            box: Rect.fromLTWH(0.1, 0.1, 0.2, 0.2),
          ),
          position: RelativePosition.center,
          priority: ObjectPriority.medium,
          proximity: ProximityBand.near,
        ),
        40,
        engine: engine,
        detectorModel: customRef,
      );
      // A custom model is installed, so the settings block has something it could
      // leak: the local path the app needs on disk.
      const settings = AppSettings(
        inferenceEngine: InferenceEngine.ultralytics,
        detectorModelKind: DetectorModelKind.custom,
        customModelName: 'Obstacle Detector v2',
        customModelFingerprint: '0a1b2c3d4e5f6071-4200',
        customModelClassCount: 12,
      );

      final jsonText = TelemetryExportService(
        clock: () => timestamp,
      ).toJson(telemetry: service, settings: settings);
      final lower = jsonText.toLowerCase();
      for (final token in const [
        '/data/',
        '/storage/',
        '/sdcard',
        'content://',
        'file://',
        '.tflite',
        'eyecue_models',
        'documents/',
        'download',
        'tfl3',
        'primary:',
      ]) {
        expect(
          lower.contains(token),
          isFalse,
          reason: 'the envelope must not carry "$token"',
        );
      }
      // No binary: the payload is text, so nothing below the printable range.
      expect(
        jsonText.codeUnits.where((unit) => unit < 0x20 && unit != 0x0a),
        isEmpty,
        reason: 'model bytes never reach the payload',
      );
      // The readable identity and its fingerprint still made it across.
      final decoded = jsonDecode(jsonText) as Map<String, dynamic>;
      expect(decoded['detectorModels'], contains(customRef.id));
      expect(
        (decoded['settings'] as Map).keys,
        isNot(contains('customModelPath')),
      );
    },
  );

  /// The attributed worst-case upload envelope.
  ///
  /// Every bounded collection at its cap (2 000 detections, 400 retained
  /// samples, 500 alert lifecycle records, 2 000 corrections, 200 failures,
  /// 100 fallbacks, 200 recoveries), every detection and sample attributed, the
  /// longest display name the import screen accepts (40 characters) and a
  /// custom model at [kMaxImportLabels] classes.
  ///
  /// Measured with this fixture: **1 869 537 UTF-8 bytes**, i.e. 130 463 bytes
  /// (6.5 %) of headroom under [TelemetryUploadService.maxUploadBodyBytes]
  /// (2 000 000) and 30 463 bytes under the project's 1 900 000-byte target.
  /// The per-row model cost is already at its floor: a row carries only its
  /// `detectorModels` key (`,"detectorModelId":"builtin"` = 27 bytes, the
  /// custom id form 41), never the name or fingerprint, which live once in the
  /// table. Those 2 400 references total ~81.6 KB — 4.1 % of the guard — so no
  /// key shortening reaches 10 %; only dropping attribution or truncating a
  /// capped collection would, and both are out of bounds.
  test('the attributed worst-case envelope stays under the upload ceiling', () {
    final service = TelemetryService(
      clock: () => timestamp,
      sessionId: 'session-populated',
      appVersion: '1.2.3+4',
    );
    addTearDown(service.dispose);
    service.startSession();
    // An 80-class built-in graph and an import at the maximum accepted class
    // count, both recorded.
    final builtInLabels = [for (var i = 0; i < 80; i++) 'coco-class-$i'];
    final customLabels = [
      for (var i = 0; i < kMaxImportLabels; i++) 'custom-class-$i',
    ];
    // 40 characters: the longest display name the import screen accepts.
    const longName = 'Obstacle Detector v2 corrected import r2';
    const longRef = DetectorModelRef(
      id: 'custom:0a1b2c3d4e5f',
      name: longName,
      fingerprint: '0a1b2c3d4e5f6071-4200',
      classCount: kMaxImportLabels,
    );
    for (var i = 0; i < 2000; i++) {
      final labels = i.isEven ? builtInLabels : customLabels;
      service.recordDetection(
        DetectionInfo(
          detection: Detection(
            classId: i % labels.length,
            label: labels[i % labels.length],
            // Device-shaped: Float32-derived doubles, not tidy literals.
            confidence: 0.8700000047683716,
            box: const Rect.fromLTWH(
              0.11363636363636363,
              0.22656200000000002,
              0.34545454545454546,
              0.43750000000000006,
            ),
          ),
          position: RelativePosition.left,
          priority: ObjectPriority.medium,
          proximity: ProximityBand.far,
        ),
        42.5,
        engine: engine,
        confidenceThreshold: 0.4,
        detectorModel: i.isEven ? builtInRef : longRef,
      );
    }
    for (var i = 0; i < 500; i++) {
      service.recordSample(
        latencyMs: 42.5,
        inferenceFps: 15,
        objectCount: 3,
        engine: engine,
        confidenceThreshold: 0.4,
        requestedDetectionHz: 8,
        effectiveDetectionHz: 5,
        requestedDepthHz: 4,
        effectiveDepthHz: 2,
        depthObservedHz: 1.5,
        depthLatencyMs: 90,
        depthStatus: 'gpu',
        detectorPreMs: 3.5,
        detectorInferenceMs: 28.25,
        detectorPostMs: 4.75,
        depthPreMs: 6,
        depthInferenceMs: 61,
        depthPostMs: 9,
        depthAccelerator: 'gpu',
        depthGridWidth: 96,
        depthGridHeight: 72,
        heatmapBuildMs: 11,
        depthDroppedTicks: 37,
        lowPowerClamped: true,
        sourceLimited: true,
        detectorModel: i.isEven ? builtInRef : longRef,
      );
    }
    for (var i = 0; i < 500; i++) {
      service.recordAlertLifecycle(
        AlertLifecycleRecord(
          origin: AlertOrigin.detection,
          engine: engine,
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
    }
    for (var i = 0; i < 200; i++) {
      service.recordFailure(
        DetectionFailure(
          category: DetectionFailureCategory.inference,
          safeMessage: 'Detection is unavailable.',
          technicalDetail: '/private/path should not upload',
          timestamp: timestamp,
        ),
      );
    }
    for (var i = 0; i < 100; i++) {
      service.recordFallback(
        preferredEngine: engine,
        activeEngine: engine,
        reason: 'unavailable',
      );
    }
    for (var i = 0; i < 200; i++) {
      service.recordRecovery(
        const InferenceLifecycleEvent(
          type: InferenceLifecycleEventType.recovering,
          generation: 1,
        ),
      );
    }
    // The largest collection after detections: 2 000 correction records.
    for (var i = 0; i < 2000; i++) {
      service.recordCorrection(
        DetectionCorrection(
          recordId: 'record-$i',
          timestamp: timestamp,
          sessionId: 'session-populated',
          engine: engine,
          detection: const Detection(
            classId: 0,
            label: 'person',
            confidence: 0.8700000047683716,
            box: Rect.fromLTWH(0.1, 0.2, 0.3, 0.4),
          ),
          feedback: CorrectionFeedback.correct,
          correctedLabel: 'person',
          confidenceThreshold: 0.25,
        ),
      );
    }
    service.recordAlertCounters(
      const AlertCounters(dropped: 1, muted: 2, rejectedByReason: {'x': 3}),
    );

    const settings = AppSettings(
      inferenceEngine: InferenceEngine.ultralytics,
      detectorModelKind: DetectorModelKind.custom,
      customModelName: longName,
      customModelFingerprint: '0a1b2c3d4e5f6071-4200',
      customModelClassCount: kMaxImportLabels,
    );
    final export = TelemetryExportService(
      clock: () => timestamp,
    ).snapshot(telemetry: service, settings: settings);
    // Measured the way the uploader builds its body: the same snapshot, encoded
    // once, compact.
    final body = {
      'ingestionSchemaVersion': 1,
      'submittedAt': timestamp.toUtc().toIso8601String(),
      'consent': {'manualSessionUpload': true},
      'telemetry': export.toJson(),
    };
    final bytes = utf8.encode(jsonEncode(body)).length;
    // ignore: avoid_print
    print('attributed worst-case envelope: $bytes UTF-8 bytes (compact)');
    // The project's own target: this envelope stays under 1 900 000 too.
    expect(bytes, lessThan(1900000), reason: 'measured $bytes bytes');
    expect(
      bytes,
      lessThan(TelemetryUploadService.maxUploadBodyBytes),
      reason: 'measured $bytes bytes against the ingest ceiling',
    );
    // Nothing was truncated to fit: the caps, not the size guard, bound the data.
    expect(export.samples, hasLength(400));
    expect(export.detections, hasLength(2000));
    expect(export.alertLifecycle, hasLength(500));
    expect(export.corrections, hasLength(2000));
    expect(export.failures, hasLength(200));
    expect(export.fallbacks, hasLength(100));
    expect(export.recoveries, hasLength(200));
    // One entry per identity, carrying the name the rows were recorded with.
    expect(export.detectorModels.keys.toSet(), {builtInRef.id, longRef.id});
    expect(export.detectorModels[longRef.id], {
      'name': longName,
      'fingerprint': longRef.fingerprint,
    });
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
    expect(await jsonFile.readAsString(), contains('"schemaVersion": 4'));
    expect(await csvFile.readAsString(), contains('record_type'));
  });
}
