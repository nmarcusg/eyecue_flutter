import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/app_settings.dart';
import '../models/telemetry_export.dart';
import 'telemetry_service.dart';

/// Builds and writes explicit, offline telemetry exports.
class TelemetryExportService {
  TelemetryExportService({DateTime Function()? clock, this._directoryProvider})
    : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;
  final Future<Directory> Function()? _directoryProvider;

  TelemetryExport snapshot({
    required TelemetryService telemetry,
    AppSettings? settings,
  }) {
    return TelemetryExport(
      exportedAt: _clock(),
      appVersion: telemetry.appVersion,
      sessionId: telemetry.sessionId,
      sessionStart: telemetry.sessionStart,
      sessionDurationMs: telemetry.sessionDuration.inMilliseconds,
      settings: settings?.toJson() ?? const {},
      samples: telemetry.samples.map((sample) => sample.toJson()),
      detections: telemetry.records.map((record) => record.toJson()),
      failures: telemetry.failures.map(_failureJson),
      fallbacks: telemetry.fallbacks.map((record) => record.toJson()),
      recoveries: telemetry.recoveries.map((record) => record.toJson()),
      corrections: telemetry.corrections.map((record) => record.toJson()),
    );
  }

  String toJson({required TelemetryService telemetry, AppSettings? settings}) {
    final encoder = const JsonEncoder.withIndent('  ');
    return '${encoder.convert(snapshot(telemetry: telemetry, settings: settings).toJson())}\n';
  }

  String toCsv({required TelemetryService telemetry, AppSettings? settings}) {
    final export = snapshot(telemetry: telemetry, settings: settings);
    final header = [
      'record_type',
      'schema_version',
      'timestamp',
      'app_version',
      'session_id',
      'session_start',
      'session_duration_ms',
      'engine',
      'preferred_engine',
      'active_engine',
      'type',
      'category',
      'safe_message',
      'recoverable',
      'retry_count',
      'fallback_available',
      'reason',
      'generation',
      'restart_attempt',
      'failure_category',
      'class_id',
      'label',
      'confidence',
      'latency_ms',
      'inference_fps',
      'object_count',
      'priority',
      'position',
      'proximity',
      'confidence_threshold',
      'track_id',
      'motion',
      'record_id',
      'feedback',
      'corrected_label',
    ];

    List<Object?> row(Map<String, dynamic> values) => [
      for (final column in header) values[column],
    ];

    final rows = <List<Object?>>[
      row({
        'record_type': 'metadata',
        'schema_version': TelemetryExport.schemaVersion,
        'timestamp': export.exportedAt.toUtc().toIso8601String(),
        'app_version': export.appVersion,
        'session_id': export.sessionId,
        'session_start': export.sessionStart?.toUtc().toIso8601String(),
        'session_duration_ms': export.sessionDurationMs,
      }),
      for (final sample in export.samples)
        row({
          'record_type': 'sample',
          'schema_version': TelemetryExport.schemaVersion,
          'timestamp': sample['timestamp'],
          'engine': sample['engine'],
          'latency_ms': sample['latencyMs'],
          'inference_fps': sample['inferenceFps'],
          'object_count': sample['objectCount'],
          'confidence_threshold': sample['confidenceThreshold'],
        }),
      for (final detection in export.detections)
        row({
          'record_type': 'detection',
          'schema_version': TelemetryExport.schemaVersion,
          'timestamp': detection['timestamp'],
          'engine': detection['engine'],
          'class_id': detection['classId'],
          'label': detection['label'],
          'confidence': detection['confidence'],
          'latency_ms': detection['latencyMs'],
          'priority': detection['priority'],
          'position': detection['position'],
          'proximity': detection['proximity'],
          'confidence_threshold': detection['confidenceThreshold'],
          'track_id': detection['trackId'],
          'motion': detection['motion'],
        }),
      for (final failure in export.failures)
        row({
          'record_type': 'failure',
          'schema_version': TelemetryExport.schemaVersion,
          'timestamp': failure['timestamp'],
          'engine': failure['engine'],
          'category': failure['category'],
          'safe_message': failure['safeMessage'],
          'recoverable': failure['recoverable'],
          'retry_count': failure['retryCount'],
          'fallback_available': failure['fallbackAvailable'],
        }),
      for (final fallback in export.fallbacks)
        row({
          'record_type': 'fallback',
          'schema_version': TelemetryExport.schemaVersion,
          'timestamp': fallback['timestamp'],
          'preferred_engine': fallback['preferredEngine'],
          'active_engine': fallback['activeEngine'],
          'reason': fallback['reason'],
        }),
      for (final recovery in export.recoveries)
        row({
          'record_type': 'recovery',
          'schema_version': TelemetryExport.schemaVersion,
          'timestamp': recovery['timestamp'],
          'engine': recovery['engine'],
          'type': recovery['type'],
          'generation': recovery['generation'],
          'restart_attempt': recovery['restartAttempt'],
          'failure_category': recovery['failureCategory'],
        }),
      for (final correction in export.corrections)
        row({
          'record_type': 'correction',
          'schema_version': TelemetryExport.schemaVersion,
          'timestamp': correction['timestamp'],
          'engine': correction['engine'],
          'record_id': correction['recordId'],
          'session_id': correction['sessionId'],
          'feedback': correction['feedback'],
          'corrected_label': correction['correctedLabel'],
          'confidence_threshold': correction['confidenceThreshold'],
          'class_id': (correction['detection'] as Map?)?['classId'],
          'label': (correction['detection'] as Map?)?['label'],
          'confidence': (correction['detection'] as Map?)?['confidence'],
        }),
    ];
    return '${[_csvRow(header), for (final row in rows) _csvRow(row)].join('\n')}\n';
  }

  Future<File> writeJson({
    required TelemetryService telemetry,
    AppSettings? settings,
    Directory? directory,
  }) async {
    final targetDirectory = directory ?? await _directory();
    await targetDirectory.create(recursive: true);
    final file = File('${targetDirectory.path}/${_fileStem()}-telemetry.json');
    return file
      ..writeAsStringSync(toJson(telemetry: telemetry, settings: settings));
  }

  Future<File> writeCsv({
    required TelemetryService telemetry,
    AppSettings? settings,
    Directory? directory,
  }) async {
    final targetDirectory = directory ?? await _directory();
    await targetDirectory.create(recursive: true);
    final file = File('${targetDirectory.path}/${_fileStem()}-telemetry.csv');
    return file
      ..writeAsStringSync(toCsv(telemetry: telemetry, settings: settings));
  }

  Future<Directory> _directory() =>
      _directoryProvider?.call() ?? getApplicationDocumentsDirectory();

  String _fileStem() {
    final value = _clock().toUtc().toIso8601String();
    return value.replaceAll(RegExp(r'[^0-9]'), '').substring(0, 14);
  }

  static Map<String, dynamic> _failureJson(TelemetryFailureRecord record) {
    final failure = record.failure;
    return {
      'timestamp': failure.timestamp.toUtc().toIso8601String(),
      'category': failure.category.name,
      'safeMessage': failure.safeMessage,
      'recoverable': failure.recoverable,
      'engine': failure.engine?.name,
      'retryCount': failure.retryCount,
      'fallbackAvailable': failure.fallbackAvailable,
    };
  }

  static String _csvRow(Iterable<Object?> values) =>
      values.map(_csvValue).join(',');

  static String _csvValue(Object? value) {
    final text = value?.toString() ?? '';
    return '"${text.replaceAll('"', '""')}"';
  }
}
