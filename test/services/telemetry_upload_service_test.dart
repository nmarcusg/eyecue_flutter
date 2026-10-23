import 'dart:convert';

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
      expect(payload['consent'], {'manualSessionUpload': true});
      expect(payload['study'], metadata.toJson());
      final export = payload['telemetry'] as Map<String, dynamic>;
      expect(export['schemaVersion'], 3);
      expect(export.containsKey('images'), isFalse);
      expect(export.containsKey('deviceId'), isFalse);
    },
  );

  test('upload is unavailable without build-time configuration', () async {
    final service = TelemetryUploadService(
      configuration: const TelemetryUploadConfiguration(
        ingestUrl: '',
        publishableKey: '',
      ),
    );

    final result = await service.upload(
      telemetry: telemetry(),
      metadata: metadata,
    );

    expect(result.isSuccess, isFalse);
    expect(result.errorMessage, contains('not been configured'));
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
