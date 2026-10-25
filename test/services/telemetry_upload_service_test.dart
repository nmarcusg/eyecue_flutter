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
import 'package:flutter/foundation.dart';
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

  // A well-formed study token: 44 token-safe characters (the server floor is
  // 43, i.e. 256 random bits base64url-encoded).
  const testToken = 'q3Yd0n4N0m8Lw2Xc9Vb6Tz1Rf5Jk7Hp0Sg4Da2Em6Ui8';

  const metadata = ResearchSessionMetadata(
    participantCode: 'P-001',
    studyScenario: 'indoor-obstacle-course',
    uploadToken: testToken,
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
    // Codes answered directly …
    for (final error in const [
      'unauthorized',
      'unsupported_schema_version',
      'database_write_failed',
      'server_configuration_error',
      'invalid_upload_token',
      'rate_limited',
    ]) {
      expect(source, contains("error: '$error'"), reason: error);
    }
    // … and the ones answered through the attempt-recording helper.
    for (final entry in const {
      'payload_too_large': 413,
      'invalid_json': 400,
      'invalid_telemetry_payload': 400,
    }.entries) {
      expect(
        source,
        contains("reject('${entry.key}', ${entry.value}"),
        reason: entry.key,
      );
    }
    // The consume statuses are mapped in validate.js — the file `node --test`
    // exercises — and index.ts only passes the mapped code/status pair through.
    for (final error in const [
      'missing_upload_token',
      'invalid_upload_token',
      'expired_upload_token',
      'revoked_upload_token',
      'upload_token_exhausted',
      'participant_mismatch',
    ]) {
      expect(validator, contains("error: '$error'"), reason: error);
    }
    // The study token is read from a header, hashed, and checked by the two
    // RPCs — never stored or echoed.
    expect(source, contains('readUploadTokenHeader(request.headers)'));
    expect(source, contains('isValidUploadTokenShape(uploadToken)'));
    expect(source, contains('sha256Hex(uploadToken)'));
    expect(source, contains("'consume_research_upload_token'"));
    expect(source, contains("'research_ingest_rate_limited'"));
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
        uploadToken: testToken,
      ).isValid,
      isFalse,
    );
  });

  group('the study upload token', () {
    test('travels as a header and never in the body', () async {
      final localTelemetry = telemetry();
      populateEveryRecordType(localTelemetry);

      final request = await capturedUpload(localTelemetry);

      expect(
        TelemetryUploadService.uploadTokenHeaderName,
        'X-Eyecue-Upload-Token',
      );
      expect(
        request.headers[TelemetryUploadService.uploadTokenHeaderName],
        testToken,
      );
      // The publishable key still identifies the client; the token authorises.
      expect(request.headers['apikey'], 'publishable-key');
      // Not in the payload, at any depth or inside any string.
      expect(request.body, isNot(contains(testToken)));
      expect((jsonDecode(request.body) as Map<String, dynamic>)['study'], {
        'participantCode': 'P-001',
        'studyScenario': 'indoor-obstacle-course',
      });
    });

    test('is never serialised or stringified with the metadata', () {
      expect(metadata.toJson().keys, ['participantCode', 'studyScenario']);
      expect(jsonEncode(metadata.toJson()), isNot(contains(testToken)));
      // An accidental log of the object must not leak the credential.
      expect(metadata.toString(), isNot(contains(testToken)));
      expect(metadata.toString(), contains('P-001'));
    });

    test('a malformed token is refused locally and nothing is sent', () async {
      for (final token in [
        '',
        'short',
        ' $testToken',
        '$testToken ',
        '$testToken=',
        'a'.padRight(129, 'a'),
        testToken.replaceFirst('q', '+'),
      ]) {
        var sends = 0;
        final localTelemetry = telemetry();
        populateEveryRecordType(localTelemetry);
        final result =
            await TelemetryUploadService(
              configuration: const TelemetryUploadConfiguration(
                ingestUrl:
                    'https://example.supabase.co/functions/v1/ingest-telemetry',
                publishableKey: 'publishable-key',
              ),
              exportService: TelemetryExportService(clock: () => now),
              clock: () => now,
              sender: (_) async {
                sends++;
                return const TelemetryUploadResponse(201);
              },
            ).upload(
              telemetry: localTelemetry,
              metadata: ResearchSessionMetadata(
                participantCode: 'P-001',
                studyScenario: 'lab',
                uploadToken: token,
              ),
            );

        expect(result.isSuccess, isFalse, reason: 'length ${token.length}');
        expect(result.errorMessage, contains('study upload token'));
        expect(result.errorMessage, contains('local export'));
        expect(sends, 0, reason: 'nothing may be sent for a malformed token');
        // The session survives every refusal.
        expect(localTelemetry.totalDetections, 1);
        expect(localTelemetry.samples, hasLength(1));
        expect(localTelemetry.alertRecords, hasLength(1));
        if (token.isNotEmpty) {
          expect(result.errorMessage, isNot(contains(token)));
        }
      }
    });

    test('the client shape check matches the server range', () {
      ResearchSessionMetadata withToken(String token) =>
          ResearchSessionMetadata(
            participantCode: 'P-001',
            studyScenario: 'lab',
            uploadToken: token,
          );
      expect(withToken('a'.padRight(42, 'a')).hasValidUploadToken, isFalse);
      expect(withToken('a'.padRight(43, 'a')).hasValidUploadToken, isTrue);
      expect(withToken('a'.padRight(64, 'a')).hasValidUploadToken, isTrue);
      expect(withToken('a'.padRight(128, 'a')).hasValidUploadToken, isTrue);
      expect(withToken('a'.padRight(129, 'a')).hasValidUploadToken, isFalse);
      expect(withToken('$testToken=').hasValidUploadToken, isFalse);
      expect(withToken(' $testToken').hasValidUploadToken, isFalse);
      expect(withToken('').hasValidUploadToken, isFalse);
    });

    group('each refusal code has its own message', () {
      Future<TelemetryUploadResult> answer(
        int status,
        String body, {
        TelemetryService? session,
      }) => TelemetryUploadService(
        configuration: const TelemetryUploadConfiguration(
          ingestUrl:
              'https://example.supabase.co/functions/v1/ingest-telemetry',
          publishableKey: 'publishable-key',
        ),
        exportService: TelemetryExportService(clock: () => now),
        clock: () => now,
        sender: (_) async => TelemetryUploadResponse(status, body),
      ).upload(telemetry: session ?? telemetry(), metadata: metadata);

      const codes = {
        'missing_upload_token': 401,
        'invalid_upload_token': 401,
        'expired_upload_token': 401,
        'revoked_upload_token': 401,
        'upload_token_exhausted': 403,
        'participant_mismatch': 403,
        'rate_limited': 429,
      };

      test('every token code maps to one distinct message', () async {
        final messages = <String>[];
        for (final entry in codes.entries) {
          final result = await answer(entry.value, '{"error":"${entry.key}"}');
          expect(result.isSuccess, isFalse, reason: entry.key);
          final message = result.errorMessage!;
          expect(messages, isNot(contains(message)), reason: entry.key);
          messages.add(message);
          expect(message, contains('local export'), reason: entry.key);
          expect(message, isNot(contains(testToken)), reason: entry.key);
          // Never folded into the generic authorisation sentence.
          expect(message, isNot(contains('not authorised')), reason: entry.key);
        }
        expect(messages, hasLength(codes.length));
      });

      test('each message names the action the researcher must take', () async {
        expect(
          (await answer(401, '{"error":"missing_upload_token"}')).errorMessage,
          contains('No study upload token was sent'),
        );
        expect(
          (await answer(401, '{"error":"invalid_upload_token"}')).errorMessage,
          contains('did not recognise'),
        );
        expect(
          (await answer(401, '{"error":"expired_upload_token"}')).errorMessage,
          contains('has expired'),
        );
        expect(
          (await answer(401, '{"error":"revoked_upload_token"}')).errorMessage,
          contains('has been revoked'),
        );
        expect(
          (await answer(
            403,
            '{"error":"upload_token_exhausted"}',
          )).errorMessage,
          contains('no uploads left'),
        );
        expect(
          (await answer(403, '{"error":"participant_mismatch"}')).errorMessage,
          contains('different participant code'),
        );
        expect(
          (await answer(429, '{"error":"rate_limited"}')).errorMessage,
          contains('Too many upload attempts'),
        );
      });

      test('a plain-text body still finds the code', () async {
        expect(
          (await answer(401, 'expired_upload_token')).errorMessage,
          contains('has expired'),
        );
        expect(
          (await answer(403, 'upload_token_exhausted')).errorMessage,
          contains('no uploads left'),
        );
      });

      test('a body with no token code keeps the generic answer', () async {
        expect(
          (await answer(401, '{"error":"unauthorized"}')).errorMessage,
          contains('not authorised'),
        );
        expect(
          (await answer(403, '{"error":"nonsense"}')).errorMessage,
          contains('not authorised'),
        );
      });

      test('a token refusal leaves the local session intact', () async {
        final localTelemetry = telemetry();
        populateEveryRecordType(localTelemetry);

        final result = await answer(
          403,
          '{"error":"upload_token_exhausted"}',
          session: localTelemetry,
        );

        expect(result.isSuccess, isFalse);
        expect(localTelemetry.totalDetections, 1);
        expect(localTelemetry.samples, hasLength(1));
        expect(localTelemetry.failures, hasLength(1));
        expect(localTelemetry.alertRecords, hasLength(1));
      });
    });
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

  group('ingest endpoint validation', () {
    TelemetryEndpointStatus statusOf(
      String url, {
      String key = 'publishable-key',
      bool debugMode = false,
    }) => validateTelemetryEndpoint(
      ingestUrl: url,
      publishableKey: key,
      debugMode: debugMode,
    );

    test('a Supabase function HTTPS URL is accepted', () {
      expect(
        statusOf('https://example.supabase.co/functions/v1/ingest-telemetry'),
        TelemetryEndpointStatus.valid,
      );
      // Only scheme and host are constrained: port and query are allowed.
      expect(
        statusOf(
          'https://example.supabase.co:8443/functions/v1/ingest-telemetry'
          '?study=1',
        ),
        TelemetryEndpointStatus.valid,
      );
      // Scheme and host are case-insensitive in a URI.
      expect(
        statusOf('HTTPS://Example.SUPABASE.co/ingest'),
        TelemetryEndpointStatus.valid,
      );
    });

    test('a production http endpoint is rejected in release and in debug', () {
      const url = 'http://example.com/functions/v1/ingest-telemetry';
      expect(statusOf(url), TelemetryEndpointStatus.insecureScheme);
      // The loopback exception is host-scoped, not scheme-scoped.
      expect(
        statusOf(url, debugMode: true),
        TelemetryEndpointStatus.insecureScheme,
      );
    });

    test('every non-https scheme is rejected', () {
      for (final url in [
        'ftp://example.com/ingest',
        'javascript:alert(1)',
        'file:///data/local/tmp/ingest',
        'ws://example.com/ingest',
        'custom-ingest://example.com/ingest',
      ]) {
        expect(
          statusOf(url),
          TelemetryEndpointStatus.insecureScheme,
          reason: url,
        );
      }
    });

    test('a malformed address is reported, never repaired', () {
      for (final url in [
        'not a url at all',
        // A scheme-less host is not an absolute URL.
        'example.com/functions/v1/ingest-telemetry',
        // Padding is reported rather than trimmed into a working URL.
        ' https://example.supabase.co/ingest',
      ]) {
        expect(statusOf(url), TelemetryEndpointStatus.malformed, reason: url);
      }
      expect(
        statusOf('https://example.supabase.co/ingest', key: ' publishable-key'),
        TelemetryEndpointStatus.malformed,
      );
    });

    test('a missing host is rejected', () {
      expect(statusOf('https://'), TelemetryEndpointStatus.missingHost);
      expect(
        statusOf('https:///functions/v1/ingest-telemetry'),
        TelemetryEndpointStatus.missingHost,
      );
    });

    test('an address with embedded credentials is rejected', () {
      expect(
        statusOf('https://researcher:secret@example.supabase.co/ingest'),
        TelemetryEndpointStatus.hasCredentials,
      );
      expect(
        statusOf('https://researcher@example.supabase.co/ingest'),
        TelemetryEndpointStatus.hasCredentials,
      );
    });

    test('loopback http is accepted in debug and rejected in release', () {
      for (final host in ['localhost', '127.0.0.1', '[::1]']) {
        final url = 'http://$host:54321/functions/v1/ingest-telemetry';
        expect(
          statusOf(url, debugMode: true),
          TelemetryEndpointStatus.valid,
          reason: url,
        );
        expect(
          statusOf(url),
          TelemetryEndpointStatus.insecureScheme,
          reason: url,
        );
      }
    });

    test('a non-DNS host shape and an out-of-range port are tolerated', () {
      // Pinned, not accidental: `validateTelemetryEndpoint` carries a
      // `shortcut:` comment saying exactly this. The endpoint is a
      // maintainer-set --dart-define, so a host typo surfaces as "could not be
      // reached" on the first request rather than as a validation message.
      for (final url in [
        // Dart percent-encodes the space: the host becomes `exam%20ple.com`.
        'https://exam ple.com/functions/v1/ingest-telemetry',
        'https://.com/functions/v1/ingest-telemetry',
        'https://example..com/functions/v1/ingest-telemetry',
        'https://example.supabase.co:99999/functions/v1/ingest-telemetry',
      ]) {
        expect(statusOf(url), TelemetryEndpointStatus.valid, reason: url);
      }
    });

    test('nothing supplied is its own status', () {
      expect(statusOf(''), TelemetryEndpointStatus.notConfigured);
      expect(
        statusOf('https://example.supabase.co/ingest', key: ''),
        TelemetryEndpointStatus.notConfigured,
      );
    });

    test('each failing status names the problem and the export fallback', () {
      for (final status in TelemetryEndpointStatus.values) {
        final message = telemetryEndpointMessage(status);
        if (status == TelemetryEndpointStatus.valid) {
          expect(message, isNull);
          continue;
        }
        expect(message, isNotNull, reason: '$status');
        if (status != TelemetryEndpointStatus.notConfigured) {
          expect(message, contains('Save a local export'), reason: '$status');
        }
      }
      expect(
        telemetryEndpointMessage(TelemetryEndpointStatus.notConfigured),
        contains('not been configured'),
      );
      expect(
        telemetryEndpointMessage(TelemetryEndpointStatus.insecureScheme),
        contains('HTTPS'),
      );
      expect(
        telemetryEndpointMessage(TelemetryEndpointStatus.malformed),
        contains('not a valid HTTPS address'),
      );
      expect(
        telemetryEndpointMessage(TelemetryEndpointStatus.missingHost),
        contains('does not name a server'),
      );
      expect(
        telemetryEndpointMessage(TelemetryEndpointStatus.hasCredentials),
        contains('embedded username or password'),
      );
    });

    test('no message repeats the endpoint, the key, or either credential', () {
      const url =
          'https://researcher:secret@example.supabase.co/functions/v1/'
          'ingest-telemetry';
      const key = 'sb_publishable_abc123';
      final status = validateTelemetryEndpoint(
        ingestUrl: url,
        publishableKey: key,
      );
      expect(status, TelemetryEndpointStatus.hasCredentials);
      final message = telemetryEndpointMessage(status)!;
      for (final leak in [
        'example.supabase.co',
        'researcher',
        'secret',
        key,
        'http://',
        'https://',
      ]) {
        expect(message, isNot(contains(leak)), reason: leak);
      }
    });
  });

  group('an endpoint this build may not use is refused before sending', () {
    /// Runs one real upload against [ingestUrl] with a sender that only counts
    /// calls, so "was it sent?" and "did the session survive?" are observable.
    Future<
      ({TelemetryUploadResult result, int sends, TelemetryService session})
    >
    uploadWith({required String ingestUrl, bool debugMode = false}) async {
      var sends = 0;
      final session = telemetry();
      populateEveryRecordType(session);
      final service = TelemetryUploadService(
        configuration: TelemetryUploadConfiguration(
          ingestUrl: ingestUrl,
          publishableKey: 'publishable-key',
        ),
        exportService: TelemetryExportService(clock: () => now),
        clock: () => now,
        debugMode: debugMode,
        sender: (_) async {
          sends++;
          return const TelemetryUploadResponse(201);
        },
      );

      final result = await service.upload(
        telemetry: session,
        metadata: metadata,
      );
      return (result: result, sends: sends, session: session);
    }

    test(
      'an http endpoint fails with the insecure message and no request',
      () async {
        final outcome = await uploadWith(
          ingestUrl: 'http://example.com/functions/v1/ingest-telemetry',
        );

        expect(outcome.result.isSuccess, isFalse);
        expect(
          outcome.result.errorMessage,
          contains('requires an HTTPS address'),
        );
        expect(outcome.result.errorMessage, contains('Save a local export'));
        expect(outcome.sends, 0);
        expect(outcome.session.totalDetections, 1);
        expect(outcome.session.samples, hasLength(1));
        expect(outcome.session.alertRecords, hasLength(1));
      },
    );

    test(
      'credentials, a missing host and a malformed address fail distinctly',
      () async {
        final withCredentials = await uploadWith(
          ingestUrl: 'https://researcher:secret@example.supabase.co/ingest',
        );
        final noHost = await uploadWith(
          ingestUrl: 'https:///functions/v1/ingest-telemetry',
        );
        final malformed = await uploadWith(
          ingestUrl: 'example.com/functions/v1/ingest-telemetry',
        );

        expect(
          withCredentials.result.errorMessage,
          contains('embedded username or password'),
        );
        expect(noHost.result.errorMessage, contains('does not name a server'));
        expect(
          malformed.result.errorMessage,
          contains('not a valid HTTPS address'),
        );
        for (final outcome in [withCredentials, noHost, malformed]) {
          expect(outcome.sends, 0);
          expect(outcome.session.totalDetections, 1);
          expect(outcome.session.samples, hasLength(1));
          expect(outcome.session.alertRecords, hasLength(1));
        }
      },
    );

    test(
      'debugMode false refuses loopback http even where kDebugMode is true',
      () async {
        // `flutter test` runs with kDebugMode true, so the default (`kDebugMode`)
        // would accept loopback http here. The field is the release decision and
        // it must win — otherwise this exception silently becomes a debug-only
        // hole in a release build.
        expect(
          kDebugMode,
          isTrue,
          reason: 'precondition: tests run in debug mode',
        );
        expect(
          validateTelemetryEndpoint(
            ingestUrl: 'http://localhost:54321/functions/v1/ingest-telemetry',
            publishableKey: 'publishable-key',
          ),
          TelemetryEndpointStatus.valid,
          reason: 'the parameter default really is kDebugMode',
        );

        var sends = 0;
        final session = telemetry();
        populateEveryRecordType(session);
        final result = await TelemetryUploadService(
          configuration: const TelemetryUploadConfiguration(
            ingestUrl: 'http://localhost:54321/functions/v1/ingest-telemetry',
            publishableKey: 'publishable-key',
          ),
          debugMode: false,
          exportService: TelemetryExportService(clock: () => now),
          clock: () => now,
          sender: (_) async {
            sends++;
            return const TelemetryUploadResponse(201);
          },
        ).upload(telemetry: session, metadata: metadata);

        expect(result.isSuccess, isFalse);
        expect(result.errorMessage, contains('requires an HTTPS address'));
        expect(sends, 0);
        expect(session.totalDetections, 1);
      },
    );

    test('the debug loopback exception sends, and only in debug', () async {
      final debug = await uploadWith(
        ingestUrl: 'http://localhost:54321/functions/v1/ingest-telemetry',
        debugMode: true,
      );
      expect(debug.result.isSuccess, isTrue);
      expect(debug.sends, 1);

      final release = await uploadWith(
        ingestUrl: 'http://localhost:54321/functions/v1/ingest-telemetry',
      );
      expect(release.result.isSuccess, isFalse);
      expect(
        release.result.errorMessage,
        contains('requires an HTTPS address'),
      );
      expect(release.sends, 0);
      expect(release.session.totalDetections, 1);
    });
  });
}
