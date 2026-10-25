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
      detection: const Detection(
        classId: 41,
        label: 'a-rather-long-coco-label-name-for-the-worst-case',
        confidence: 0.875,
        box: Rect.fromLTWH(0.123456, 0.234567, 0.334567, 0.434567),
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
