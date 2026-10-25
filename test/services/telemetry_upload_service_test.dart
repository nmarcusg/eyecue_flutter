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

  // On device these are Float32-derived doubles (the plugin divides a float
  // `xywh` by the image size, then Dart subtracts `right - left`), so they
  // serialise as 17–19-character decimals. Tidy literals understated the
  // envelope by ~74 B per detection-bearing record.
  DetectionInfo detInfo(String label, int classId) =>
      SpatialAnalysisService.analyze(
        Detection(
          classId: classId,
          label: label,
          confidence: 0.8700000047683716,
          box: const Rect.fromLTWH(
            0.11363636363636363,
            0.22656200000000002,
            0.34545454545454546,
            0.43750000000000006,
          ),
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

  // Mirrors the server-side set in
  // `supabase/functions/ingest-telemetry/validate.js`; the client envelope must
  // stay free of every one of them. `frameNumber` is deliberately absent — it is
  // an allowed counter, not a frame.
  const forbiddenKeys = {
    'image',
    'images',
    'screenshot',
    'screenshots',
    'frame',
    'frames',
    'audio',
    'utterance',
    'path',
    'paths',
    'deviceId',
    'technicalDetail',
    'serviceRole',
    'secret',
    'secrets',
    'token',
    'tokens',
    'apiKey',
    'password',
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

    // Measured 1,850,400 bytes with every collection at its cap, every schema-4
    // sample key populated and device-shaped (Float32-derived) box/confidence
    // doubles: 149,600 bytes of headroom under the ingest's 2,000,000-byte limit
    // and 49,600 under the 1,900,000 target. With the same fixture but tidy
    // 2-decimal literals it read 1,878,480 bytes; with device-shaped numbers and
    // no serialisation rounding it was 2,018,480 bytes, i.e. refused.
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

  test('the Edge Function delegates envelope and schema gating', () {
    final source = File(
      'supabase/functions/ingest-telemetry/index.ts',
    ).readAsStringSync();
    final validator = File(
      'supabase/functions/ingest-telemetry/validate.js',
    ).readAsStringSync();

    // Auth and the machine-readable error catalogue are unchanged.
    expect(source, contains("from './validate.js'"));
    expect(source, contains('validateEnvelope(body)'));
    expect(source, contains('isBodyTooLarge'));
    expect(source, contains('publishableKeys.default'));
    for (final error in const [
      'unauthorized',
      'payload_too_large',
      'invalid_telemetry_payload',
      'unsupported_schema_version',
      'database_write_failed',
      'server_configuration_error',
    ]) {
      expect(source, contains("error: '$error'"), reason: error);
    }
    // Idempotency: one row per session, a replay only reports it.
    expect(
      source,
      contains("onConflict: 'participant_code,client_session_id'"),
    );
    expect(source, contains('ignoreDuplicates: true'));
    expect(source, contains('duplicated: true'));
    // Schema gating is a membership test, so a re-exported schema-3 payload
    // stamped 4 is still accepted: the row shape is never inferred from the
    // header. A literal comparison would reject those exports.
    expect(validator, contains('SUPPORTED_SCHEMA_VERSIONS = [3, 4]'));
    expect(source, isNot(contains('schemaVersion ===')));
    // The whole telemetry object is stored as JSONB, so schema 3 needs no
    // migration.
    expect(source, contains('payload: envelope.telemetry'));
    // The forbidden-key list lives in the validator, matched by exact name.
    expect(validator, contains("'screenshots'"));
    expect(validator, contains("'technicalDetail'"));
    expect(validator, contains("ALLOWED_KEYS = new Set(['frameNumber'])"));
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

  group('a non-2xx answer maps to a distinct, actionable failure', () {
    Future<TelemetryUploadResult> uploadAnswering(
      int statusCode, {
      String? body,
      TelemetryService? localTelemetry,
    }) {
      final service = localTelemetry ?? telemetry();
      return TelemetryUploadService(
        configuration: const TelemetryUploadConfiguration(
          ingestUrl:
              'https://example.supabase.co/functions/v1/ingest-telemetry',
          publishableKey: 'publishable-key',
        ),
        exportService: TelemetryExportService(clock: () => now),
        clock: () => now,
        sender: (_) async => TelemetryUploadResponse(statusCode, body),
      ).upload(telemetry: service, metadata: metadata);
    }

    test('401 and 403 report an authorisation failure', () async {
      for (final status in const [401, 403]) {
        final result = await uploadAnswering(status);
        expect(result.isSuccess, isFalse, reason: 'status $status');
        expect(result.errorMessage, contains('not authorised'));
        expect(result.errorMessage, contains('local export'));
      }
    });

    test('400 unsupported_schema_version reports a format mismatch', () async {
      final result = await uploadAnswering(
        400,
        body: '{"error":"unsupported_schema_version","supported":[3,4]}',
      );
      expect(result.isSuccess, isFalse);
      expect(
        result.errorMessage,
        contains('telemetry format the research server does not accept'),
      );
    });

    test('a plain-text 400 body still finds the schema code', () async {
      final result = await uploadAnswering(
        400,
        body: 'unsupported_schema_version',
      );
      expect(
        result.errorMessage,
        contains('telemetry format the research server does not accept'),
      );
    });

    test(
      '400 invalid_telemetry_payload reports a validation failure',
      () async {
        final result = await uploadAnswering(
          400,
          body: '{"error":"invalid_telemetry_payload"}',
        );
        expect(result.isSuccess, isFalse);
        expect(
          result.errorMessage,
          contains('rejected this session as invalid'),
        );
        expect(
          result.errorMessage,
          isNot(
            contains('telemetry format the research server does not accept'),
          ),
        );
      },
    );

    test('413 reuses the local size message', () async {
      final result = await uploadAnswering(
        413,
        body: '{"error":"payload_too_large"}',
      );
      expect(result.isSuccess, isFalse);
      expect(result.errorMessage, contains('too large to upload'));
      expect(result.errorMessage, contains('local export'));
    });

    test('5xx reports a server failure and keeps the session', () async {
      final localTelemetry = telemetry();
      populateEveryRecordType(localTelemetry);
      final result = await uploadAnswering(
        500,
        body: '{"error":"database_write_failed"}',
        localTelemetry: localTelemetry,
      );
      expect(result.isSuccess, isFalse);
      expect(result.errorMessage, contains('server could not accept'));
      expect(localTelemetry.totalDetections, 1);
      expect(localTelemetry.samples, hasLength(1));
      expect(localTelemetry.alertRecords, hasLength(1));
    });

    test('a 200 duplicated replay is a distinct, non-error state', () async {
      final localTelemetry = telemetry();
      populateEveryRecordType(localTelemetry);

      final result = await uploadAnswering(
        200,
        body: '{"accepted":true,"duplicated":true}',
        localTelemetry: localTelemetry,
      );

      // Success-like: the session is in the database …
      expect(result.isSuccess, isTrue);
      expect(result.errorMessage, isNull);
      // … but nothing was stored on this attempt, so it must not read as one.
      expect(result.isAlreadyUploaded, isTrue);
      expect(result.message, contains('already uploaded earlier'));
      expect(result.message, contains('was not stored again'));
      expect(result.message, contains('local export'));
      expect(localTelemetry.totalDetections, 1);
      expect(localTelemetry.samples, hasLength(1));
      expect(localTelemetry.alertRecords, hasLength(1));
    });

    test('a 201 first write is the plain success', () async {
      final localTelemetry = telemetry();
      populateEveryRecordType(localTelemetry);

      final result = await uploadAnswering(
        201,
        body: '{"accepted":true}',
        localTelemetry: localTelemetry,
      );

      expect(result.isSuccess, isTrue);
      expect(result.isAlreadyUploaded, isFalse);
      expect(result.message, isNull);
      expect(localTelemetry.totalDetections, 1);
      expect(localTelemetry.samples, hasLength(1));
    });

    test(
      'a 2xx body without the duplicated flag stays a plain success',
      () async {
        final result = await uploadAnswering(200, body: 'not json');

        expect(result.isSuccess, isTrue);
        expect(result.isAlreadyUploaded, isFalse);
      },
    );
  });

  group('the response read is clamped at 4 KiB', () {
    Future<String> readAsSingleChunk(List<int> bytes) =>
        TelemetryUploadService.readClampedBody(Stream<List<int>>.value(bytes));

    // The clamp runs on the default sender, so the body it produces is fed back
    // through the injected sender to prove the decision still parses.
    Future<TelemetryUploadResult> uploadClampedBody(String body) async {
      final clamped = await readAsSingleChunk(utf8.encode(body));
      return TelemetryUploadService(
        configuration: const TelemetryUploadConfiguration(
          ingestUrl:
              'https://example.supabase.co/functions/v1/ingest-telemetry',
          publishableKey: 'publishable-key',
        ),
        exportService: TelemetryExportService(clock: () => now),
        clock: () => now,
        sender: (_) async => TelemetryUploadResponse(200, clamped),
      ).upload(telemetry: telemetry(), metadata: metadata);
    }

    test('one oversized chunk is truncated at 4096 B', () async {
      final padding = 'x'.padRight(10000, 'x');
      final clamped = await readAsSingleChunk(
        utf8.encode('{"accepted":true}$padding'),
      );

      expect(utf8.encode(clamped), hasLength(4096));
      expect(clamped, isNot(contains(padding)));
    });

    test('a codepoint split by the clamp does not throw', () async {
      // 4095 ASCII bytes then a 3-byte `€`: the 4096-byte cut lands mid-sequence.
      final bytes = utf8.encode('${'x'.padRight(4095, 'x')}€');
      expect(bytes, hasLength(4098));

      final clamped = await readAsSingleChunk(bytes);

      expect(clamped, endsWith('\uFFFD'));
      expect(clamped.substring(0, 4095), 'x'.padRight(4095, 'x'));
    });

    test('a duplicated prefix survives the clamp', () async {
      // Valid JSON over the cap, so the clamp cuts inside the padding string:
      // the replay flag survives in the prefix even though the body no longer
      // parses as a whole.
      final result = await uploadClampedBody(
        '{"accepted":true,"duplicated":true,"detail":"'
        '${'x'.padRight(10000, 'x')}"}',
      );

      expect(result.isSuccess, isTrue);
      expect(result.isAlreadyUploaded, isTrue);
      expect(result.message, contains('already uploaded earlier'));
    });
  });
}
