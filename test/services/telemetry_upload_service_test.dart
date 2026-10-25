import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:eyecue_flutter/models/alert_lifecycle.dart';
import 'package:eyecue_flutter/models/app_settings.dart';
import 'package:eyecue_flutter/models/detection.dart';
import 'package:eyecue_flutter/models/detection_correction.dart';
import 'package:eyecue_flutter/models/detection_info.dart';
import 'package:eyecue_flutter/models/detection_runtime_state.dart';
import 'package:eyecue_flutter/models/inference_lifecycle_event.dart';
import 'package:eyecue_flutter/services/spatial_analysis_service.dart';
import 'package:eyecue_flutter/services/telemetry_export_service.dart';
import 'package:eyecue_flutter/services/telemetry_service.dart';
import 'package:eyecue_flutter/services/telemetry_upload_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime.utc(2026, 10, 20, 12);

  TelemetryService telemetry() {
    final service = TelemetryService(
      clock: () => now,
      sessionId: 'session-upload-test',
    );
    service.startSession();
    addTearDown(service.dispose);
    return service;
  }

  const metadata = ResearchSessionMetadata(
    participantCode: 'P-001',
    studyScenario: 'indoor-obstacle-course',
  );

  DetectionInfo detInfo(String label, int classId) =>
      SpatialAnalysisService.analyze(
        Detection(
          classId: classId,
          label: label,
          confidence: 0.87,
          box: const Rect.fromLTWH(0.11, 0.22, 0.33, 0.44),
        ),
      );

  AlertLifecycleRecord alertRecord() => AlertLifecycleRecord(
    origin: AlertOrigin.detection,
    engine: InferenceEngine.ultralytics,
    requestedAt: now,
    submittedAt: now,
    alertStartedAt: now,
    terminalAt: now.add(const Duration(milliseconds: 800)),
    terminalState: AlertTerminalState.completed,
    terminalCause: null,
    hadStarted: true,
    reconciledAt: now.add(const Duration(milliseconds: 900)),
    frameNumber: 4242,
    analysisReceivedAt: now,
    inferenceStartedAt: now,
    inferenceCompletedAt: now,
    resultReceivedAt: now,
    detectionAcceptedAt: now,
  );

  /// Captures the request the configured upload service would send.
  Future<TelemetryUploadRequest> capturedUpload(
    TelemetryService service, {
    AppSettings? settings,
  }) async {
    TelemetryUploadRequest? captured;
    await TelemetryUploadService(
      configuration: const TelemetryUploadConfiguration(
        ingestUrl: 'https://example.supabase.co/functions/v1/ingest-telemetry',
        publishableKey: 'publishable-key',
      ),
      exportService: TelemetryExportService(clock: () => now),
      clock: () => now,
      sender: (request) async {
        captured = request;
        return const TelemetryUploadResponse(201);
      },
    ).upload(telemetry: service, metadata: metadata, settings: settings);
    return captured!;
  }

  void populateEveryRecordType(TelemetryService service) {
    service.recordDetection(
      detInfo('traffic light', 9),
      42.5,
      engine: InferenceEngine.ultralytics,
    );
    service.recordSample(
      latencyMs: 42.5,
      inferenceFps: 12.5,
      objectCount: 2,
      engine: InferenceEngine.ultralytics,
      requestedDetectionHz: 10,
      effectiveDetectionHz: 10,
      requestedDepthHz: 2,
      effectiveDepthHz: 2,
      depthObservedHz: 1.8,
      depthLatencyMs: 520,
      depthStatus: 'gpu',
      sourceLimited: true,
    );
    service.recordFailure(
      DetectionFailure(
        category: DetectionFailureCategory.inference,
        safeMessage: 'Detection is unavailable.',
        technicalDetail: '/private/path should not upload',
        timestamp: now,
      ),
    );
    service.recordFallback(
      preferredEngine: InferenceEngine.ultralytics,
      activeEngine: InferenceEngine.ultralytics,
      reason: 'unavailable',
    );
    service.recordRecovery(
      const InferenceLifecycleEvent(
        type: InferenceLifecycleEventType.recovering,
        generation: 1,
      ),
    );
    service.recordCorrection(
      DetectionCorrection(
        recordId: 'record-1',
        timestamp: now,
        sessionId: 'session-upload-test',
        engine: InferenceEngine.ultralytics,
        detection: detInfo('person', 0).detection,
        feedback: CorrectionFeedback.correct,
        correctedLabel: 'person',
        confidenceThreshold: 0.25,
      ),
    );
    service.recordAlertLifecycle(alertRecord());
    service.recordAlertCounters(
      const AlertCounters(dropped: 1, rejectedByReason: {'cooldown': 2}),
    );
  }

  const forbiddenKeys = {
    'image',
    'images',
    'deviceId',
    'technicalDetail',
    'path',
    'utterance',
  };

  void expectNoForbiddenKeys(Object? value) {
    if (value is Map) {
      for (final entry in value.entries) {
        expect(
          forbiddenKeys,
          isNot(contains(entry.key)),
          reason: 'forbidden key "${entry.key}" reached the upload envelope',
        );
        expectNoForbiddenKeys(entry.value);
      }
    } else if (value is List) {
      for (final item in value) {
        expectNoForbiddenKeys(item);
      }
    }
  }

  test(
    'manual upload wraps the existing image-free telemetry export',
    () async {
      TelemetryUploadRequest? captured;
      final service = TelemetryUploadService(
        configuration: const TelemetryUploadConfiguration(
          ingestUrl:
              'https://example.supabase.co/functions/v1/ingest-telemetry',
          publishableKey: 'publishable-key',
        ),
        exportService: TelemetryExportService(clock: () => now),
        clock: () => now,
        sender: (request) async {
          captured = request;
          return const TelemetryUploadResponse(201);
        },
      );

      final result = await service.upload(
        telemetry: telemetry(),
        metadata: metadata,
      );

      expect(result.isSuccess, isTrue);
      expect(captured!.headers['apikey'], 'publishable-key');
      final payload = jsonDecode(captured!.body) as Map<String, dynamic>;
      expect(payload['ingestionSchemaVersion'], 1);
      expect(payload['submittedAt'], now.toUtc().toIso8601String());
      expect(payload['consent'], {'manualSessionUpload': true});
      expect(payload['study'], metadata.toJson());
      final export = payload['telemetry'] as Map<String, dynamic>;
      expect(export['schemaVersion'], 4);
      expect(export.containsKey('images'), isFalse);
      expect(export.containsKey('deviceId'), isFalse);
    },
  );

  test('upload is unavailable without build-time configuration', () async {
    final localTelemetry = telemetry();
    populateEveryRecordType(localTelemetry);
    final service = TelemetryUploadService(
      configuration: const TelemetryUploadConfiguration(
        ingestUrl: '',
        publishableKey: '',
      ),
    );

    final result = await service.upload(
      telemetry: localTelemetry,
      metadata: metadata,
    );

    expect(result.isSuccess, isFalse);
    expect(result.errorMessage, contains('not been configured'));
    expect(localTelemetry.totalDetections, 1);
    expect(localTelemetry.samples.length, 1);
    expect(localTelemetry.alertRecords.length, 1);
  });

  test('a rejected upload leaves local telemetry intact', () async {
    final localTelemetry = telemetry();
    populateEveryRecordType(localTelemetry);
    final service = TelemetryUploadService(
      configuration: const TelemetryUploadConfiguration(
        ingestUrl: 'https://example.supabase.co/functions/v1/ingest-telemetry',
        publishableKey: 'publishable-key',
      ),
      sender: (_) async => const TelemetryUploadResponse(503),
    );

    final result = await service.upload(
      telemetry: localTelemetry,
      metadata: metadata,
    );

    expect(result.isSuccess, isFalse);
    expect(localTelemetry.totalDetections, 1);
    expect(localTelemetry.samples.length, 1);
    expect(localTelemetry.failures.length, 1);
    expect(localTelemetry.alertRecords.length, 1);
    expect(localTelemetry.records.single.label, 'traffic light');
  });

  test('cadence sample fields travel inside the schema-4 payload', () async {
    final localTelemetry = telemetry();
    populateEveryRecordType(localTelemetry);

    final request = await capturedUpload(localTelemetry);
    final export =
        (jsonDecode(request.body) as Map<String, dynamic>)['telemetry']
            as Map<String, dynamic>;

    expect(export['schemaVersion'], 4);
    final sample = (export['samples'] as List).single as Map<String, dynamic>;
    expect(
      sample.keys,
      containsAll(const [
        'requestedDetectionHz',
        'detectionCadenceAutomatic',
        'effectiveDetectionHz',
        'requestedDepthHz',
        'effectiveDepthHz',
        'depthObservedHz',
        'depthLatencyMs',
        'depthStatus',
        'lowPowerClamped',
        'sourceLimited',
      ]),
    );
    expect(sample['requestedDetectionHz'], 10);
    expect(sample['depthStatus'], 'gpu');
    expect(sample['sourceLimited'], isTrue);
  });

  test('a fully populated envelope contains no forbidden keys', () async {
    final localTelemetry = telemetry();
    populateEveryRecordType(localTelemetry);

    final request = await capturedUpload(localTelemetry);

    expectNoForbiddenKeys(jsonDecode(request.body));
    expect(request.body, isNot(contains('/private/path')));
  });

  test('application source carries no Supabase secret', () {
    final sources = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'));

    for (final file in sources) {
      final text = file.readAsStringSync();
      for (final forbidden in ['service_role', 'SUPABASE_SECRET']) {
        expect(
          text,
          isNot(contains(forbidden)),
          reason: '${file.path} must not contain $forbidden',
        );
      }
      expect(
        text,
        isNot(contains(RegExp(r'sb_secret_[A-Za-z0-9]'))),
        reason: '${file.path} must not contain a secret key literal',
      );
    }
  });

  test('a worst-case envelope stays under the 2 MB ingestion cap', () async {
    final localTelemetry = telemetry();
    // Fill every bounded collection to its cap.
    for (var i = 0; i < 2000; i++) {
      localTelemetry.recordDetection(
        detInfo('traffic light', 9),
        42.5,
        engine: InferenceEngine.ultralytics,
      );
    }
    for (var i = 0; i < 500; i++) {
      localTelemetry.recordSample(
        latencyMs: 42.5,
        inferenceFps: 12.5,
        objectCount: 25,
        engine: InferenceEngine.ultralytics,
        requestedDetectionHz: 10,
        effectiveDetectionHz: 10,
        requestedDepthHz: 2,
        effectiveDepthHz: 2,
        depthObservedHz: 1.8,
        depthLatencyMs: 520,
        depthStatus: 'gpu',
        // Every schema-4 sample key populated, at its realistic maximum: the
        // envelope must be measured with the fields the app really emits.
        detectorPreMs: 4.75,
        detectorInferenceMs: 32.125,
        detectorPostMs: 4.75,
        depthPreMs: 6,
        depthInferenceMs: 520,
        depthPostMs: 7,
        depthAccelerator: 'gpu',
        depthGridWidth: 48,
        depthGridHeight: 72,
        heatmapBuildMs: 11,
        depthDroppedTicks: 37,
        lowPowerClamped: true,
        sourceLimited: true,
      );
    }
    for (var i = 0; i < 500; i++) {
      localTelemetry.recordAlertLifecycle(alertRecord());
    }
    for (var i = 0; i < 200; i++) {
      localTelemetry.recordFailure(
        DetectionFailure(
          category: DetectionFailureCategory.inference,
          safeMessage: 'Detection is unavailable.',
          technicalDetail: '/private/path should not upload',
          timestamp: now,
        ),
      );
    }
    for (var i = 0; i < 100; i++) {
      localTelemetry.recordFallback(
        preferredEngine: InferenceEngine.ultralytics,
        activeEngine: InferenceEngine.ultralytics,
        reason: 'unavailable',
      );
    }
    for (var i = 0; i < 200; i++) {
      localTelemetry.recordRecovery(
        const InferenceLifecycleEvent(
          type: InferenceLifecycleEventType.recovering,
          generation: 1,
        ),
      );
    }
    for (var i = 0; i < 2000; i++) {
      localTelemetry.recordCorrection(
        DetectionCorrection(
          recordId: 'record-$i',
          timestamp: now,
          sessionId: 'session-upload-test',
          engine: InferenceEngine.ultralytics,
          detection: detInfo('person', 0).detection,
          feedback: CorrectionFeedback.correct,
          correctedLabel: 'person',
          confidenceThreshold: 0.25,
        ),
      );
    }
    localTelemetry.recordAlertCounters(
      const AlertCounters(dropped: 1, rejectedByReason: {'cooldown': 2}),
    );

    final request = await capturedUpload(localTelemetry);
    final bytes = utf8.encode(request.body).length;
    // ignore: avoid_print
    print('worst-case upload envelope: $bytes UTF-8 bytes');

    // Measured 1,878,480 bytes with every collection at its cap and every
    // schema-4 sample key populated: 121,520 bytes of headroom under the
    // ingest's 2,000,000-byte limit and under the 1,900,000 target. The same
    // shape measured 2,027,180 bytes before the fix (≈2,040,680 counting the
    // `detectorObservedFps` duplicate that was then removed), i.e. rejected.
    expect(bytes, lessThan(1900000), reason: 'measured $bytes bytes');

    final samples =
        ((jsonDecode(request.body) as Map)['telemetry'] as Map)['samples']
            as List;
    // The tertiary perf keys are thinned to every fifth sample; the core
    // cadence fields stay on every sample.
    expect((samples[0] as Map)['detectorPreMs'], 4.75);
    expect((samples[5] as Map)['detectorPreMs'], 4.75);
    expect((samples[1] as Map).containsKey('detectorPreMs'), isFalse);
    expect((samples[1] as Map)['latencyMs'], 42.5);
    expect((samples[1] as Map)['inferenceFps'], 12.5);
  });

  test('an oversized envelope fails locally and keeps the session', () async {
    final localTelemetry = telemetry();
    populateEveryRecordType(localTelemetry);
    final samplesBefore = localTelemetry.samples.length;
    var sent = false;

    final result = await TelemetryUploadService(
      configuration: const TelemetryUploadConfiguration(
        ingestUrl: 'https://example.supabase.co/functions/v1/ingest-telemetry',
        publishableKey: 'publishable-key',
      ),
      exportService: TelemetryExportService(clock: () => now),
      clock: () => now,
      // The wire bound is 2,000,000; a small one drives the same branch.
      maxBodyBytes: 512,
      sender: (request) async {
        sent = true;
        return const TelemetryUploadResponse(201);
      },
    ).upload(telemetry: localTelemetry, metadata: metadata);

    expect(result.isSuccess, isFalse);
    expect(result.errorMessage, contains('too large to upload'));
    expect(result.errorMessage, contains('local export'));
    // The server never sees an over-cap body...
    expect(sent, isFalse);
    // ...and nothing is truncated, so the session still exports in full.
    expect(localTelemetry.samples, hasLength(samplesBefore));
    expect(localTelemetry.totalDetections, 1);
  });

  test('the local size guard uses the ingest byte limit', () {
    expect(TelemetryUploadService.maxUploadBodyBytes, 2000000);
  });

  test('the Edge Function still accepts numeric schema-3 payloads', () {
    final source = File(
      'supabase/functions/ingest-telemetry/index.ts',
    ).readAsStringSync();

    expect(source, contains('body.ingestionSchemaVersion !== 1'));
    expect(source, contains('consent.manualSessionUpload !== true'));
    expect(
      source,
      contains(
        "['image', 'images', 'deviceId', 'technicalDetail', 'path', 'utterance']",
      ),
    );
    expect(source, contains("typeof telemetry.schemaVersion !== 'number'"));
    // The numeric-type guard is the only permitted schemaVersion comparison.
    // Any literal comparison would start requiring an exact schema and reject
    // the older exports that must still parse.
    final withoutTypeGuard = source.replaceAll(
      "typeof telemetry.schemaVersion !== 'number'",
      '',
    );
    expect(
      withoutTypeGuard,
      isNot(matches(RegExp(r'\bschemaVersion\s*(===|!==|==|!=)'))),
      reason: 'the Edge Function must not require an exact telemetry schema',
    );
    // The whole telemetry object is stored as JSONB, so schema 3 needs no
    // migration.
    expect(source, contains('payload: telemetry'));
  });

  test('metadata excludes unsafe participant identifiers', () {
    expect(metadata.isValid, isTrue);
    expect(
      const ResearchSessionMetadata(
        participantCode: 'person@example.com',
        studyScenario: 'lab',
      ).isValid,
      isFalse,
    );
  });
}
