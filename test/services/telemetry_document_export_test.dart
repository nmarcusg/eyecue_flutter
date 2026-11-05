import 'dart:convert';
import 'dart:io';

import 'package:eyecue_flutter/models/alert_lifecycle.dart';
import 'package:eyecue_flutter/models/app_settings.dart';
import 'package:eyecue_flutter/models/detection_info.dart';
import 'package:eyecue_flutter/models/research_session.dart';
import 'package:eyecue_flutter/services/document_export_service.dart';
import 'package:eyecue_flutter/services/telemetry_export_service.dart';
import 'package:eyecue_flutter/services/telemetry_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _Destination extends DocumentExportService {
  bool cancelled = false;
  bool fail = false;
  File? source;
  String? mimeType;
  String? contents;

  @override
  Future<String?> save({required File source, required String mimeType}) async {
    this.source = source;
    this.mimeType = mimeType;
    contents = await source.readAsString();
    if (fail) throw PlatformException(code: 'write_failed');
    return cancelled
        ? null
        : 'chosen-name.${mimeType == 'text/csv' ? 'csv' : 'json'}';
  }
}

void main() {
  late Directory root;
  late Directory cache;
  late File retained;
  late _Destination destination;
  late TelemetryExportService exporter;
  final now = DateTime.utc(2026, 11, 5);
  ResearchSession trial(int count) => ResearchSession(
    id: 'trial-id',
    participantCode: 'p1',
    trialLabel: 'indoor',
    detectors: const [],
    wallClockStart: now,
    wallClockEnd: now,
    intervals: const [],
    activeDurationMs: 1000,
    totalDetections: count,
    highPriorityAlerts: count,
    framesProcessed: count,
    records: [
      for (var i = 0; i < count; i++)
        TelemetryRecord(
          timestamp: now.add(Duration(milliseconds: i)),
          classId: 0,
          label: 'a-person-with-a-custom-class-label-for-offline-research',
          confidence: .9,
          latencyMs: 50,
          priority: ObjectPriority.high,
          position: 'center',
          proximity: ProximityBand.near,
          box: const Rect.fromLTWH(.3, .2, .4, .5),
          engine: InferenceEngine.ultralytics,
        ),
    ],
    samples: const [],
    failures: const [],
    fallbacks: const [],
    recoveries: const [],
    corrections: const [],
    alertRecords: const [],
    alertCounters: const AlertCounters(),
    appVersion: '1.0.0-study',
    alertConfiguration: const AppSettings(
      alertDistanceMeters: 3,
      urgentDistanceMeters: 1,
    ).alertConfiguration,
  );
  setUp(() async {
    root = await Directory.systemTemp.createTemp('eyecue-document-test');
    cache = await Directory('${root.path}/cache').create();
    retained = await File(
      '${root.path}/retained-trial.json',
    ).writeAsString('original trial');
    destination = _Destination();
    exporter = TelemetryExportService(
      clock: () => now,
      documentExporter: destination,
      temporaryDirectoryProvider: () async => cache,
    );
  });
  tearDown(() async => root.delete(recursive: true));

  test(
    'full 10000-row trial exports above upload cap without loss or reattribution',
    () async {
      final session = trial(10000);
      final before = session.toJson();
      final name = await exporter.saveJson(
        telemetry: session,
        settings: const AppSettings(),
        stemSuffix: '-${session.id}',
      );
      expect(name, 'chosen-name.json');
      expect(destination.mimeType, 'application/json');
      expect(utf8.encode(destination.contents!).length, greaterThan(2000000));
      final body = jsonDecode(destination.contents!) as Map;
      expect(body['detections'], hasLength(10000));
      expect(body['session']['id'], 'trial-id');
      expect(body['settings']['alertConfiguration']['normalMaxMeters'], 3);
      expect(session.toJson(), before);
      expect(await retained.readAsString(), 'original trial');
      expect(await destination.source!.exists(), false);
      expect(await cache.list().toList(), isEmpty);
    },
  );

  test('CSV is offered as a document with all available trial rows', () async {
    await exporter.saveCsv(telemetry: trial(2100));
    expect(destination.mimeType, 'text/csv');
    expect(
      destination.contents!
          .split('\n')
          .where((line) => line.startsWith('"detection",')),
      hasLength(2100),
    );
    expect(destination.contents, contains('freshSpatialMedian-v1'));
    expect(await retained.exists(), true);
    expect(await cache.list().toList(), isEmpty);
  });

  test(
    'cancelling Save as cleans only staging and preserves internal data',
    () async {
      destination.cancelled = true;
      expect(await exporter.saveJson(telemetry: trial(1)), isNull);
      expect(await retained.readAsString(), 'original trial');
      expect(await cache.list().toList(), isEmpty);
    },
  );

  test(
    'provider failure preserves the trial and permits another destination',
    () async {
      destination.fail = true;
      final session = trial(10);
      await expectLater(
        exporter.saveJson(telemetry: session),
        throwsA(isA<PlatformException>()),
      );
      expect(session.records, hasLength(10));
      expect(await retained.readAsString(), 'original trial');
      expect(await cache.list().toList(), isEmpty);
      destination.fail = false;
      expect(await exporter.saveJson(telemetry: session), 'chosen-name.json');
    },
  );
}
