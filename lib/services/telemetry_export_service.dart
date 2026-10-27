import 'dart:convert';
import 'dart:io';
import 'dart:ui' show Rect;

import 'package:path_provider/path_provider.dart';

import '../models/alert_lifecycle.dart';
import '../models/app_settings.dart';
import '../models/detection_correction.dart';
import '../models/telemetry_export.dart';
import 'telemetry_service.dart';

/// Builds and writes explicit, offline telemetry exports.
class TelemetryExportService {
  TelemetryExportService({DateTime Function()? clock, this._directoryProvider})
    : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;
  final Future<Directory> Function()? _directoryProvider;

  /// Every [perfSampleStride]th sample keeps the tertiary detector/depth cost
  /// keys; the core cadence and telemetry keys stay on every sample.
  ///
  /// These costs move slowly, so repeating them on all 400 retained samples was
  /// redundant and pushed the worst-case upload past the 2 MB ingest bound.
  /// Thinning loses no record: on the other samples the keys are absent (never
  /// truncated, never `0`), which the data dictionary documents.
  static const int perfSampleStride = 5;

  static const Set<String> _perfKeys = {
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
  };

  /// Keys that belong to the export's `detectorModels` table, not to a row.
  ///
  /// A row keeps the short id, so 2 400 rows do not repeat the same name and
  /// fingerprint that the table already carries once.
  static const Set<String> _rowModelKeys = {
    'detectorModelName',
    'detectorModelFingerprint',
  };

  /// A row carries only the short id, so the readable name and the graph
  /// fingerprint are joined back from the export's table when a CSV needs them.
  static Object? _modelField(
    Map<String, Map<String, dynamic>> models,
    Object? id,
    String key,
  ) {
    if (id is! String) return null;
    return models[id]?[key];
  }

  /// Serialisation-only precision contract.
  ///
  /// On device a box coordinate is a Float32 plugin value divided in double
  /// arithmetic (`0.34545454545454546`), so every detection-bearing record
  /// carries four 17–19-character decimals — ~260 KB across a worst-case
  /// envelope, more than the ingest limit can absorb. Rounding happens here,
  /// in the serialised output only: the stored samples are never mutated, so
  /// band classification, in-app comparisons and speech text still read the
  /// full value. Boxes keep 4 dp (~0.1 px of a 1080 px frame), scores 3 dp,
  /// latency/Hz 1 dp, and the sub-millisecond stage timings 2 dp (1 dp would
  /// round a 4.75 ms stage to 4.8).
  static const int _boxDecimals = 4;
  static const int _scoreDecimals = 3;
  static const int _msDecimals = 1;
  static const int _stageDecimals = 2;

  static const Map<String, int> _samplePrecision = {
    'latencyMs': _msDecimals,
    'inferenceFps': _msDecimals,
    'detectorPreMs': _stageDecimals,
    'detectorInferenceMs': _stageDecimals,
    'detectorPostMs': _stageDecimals,
    'depthObservedHz': _msDecimals,
    'confidenceThreshold': _scoreDecimals,
  };

  static double _round(double value, int places) =>
      double.parse(value.toStringAsFixed(places));

  static Map<String, double> _boxJson(Rect box) => {
    'left': _round(box.left, _boxDecimals),
    'top': _round(box.top, _boxDecimals),
    'width': _round(box.width, _boxDecimals),
    'height': _round(box.height, _boxDecimals),
  };

  static Map<String, dynamic> _detectionJson(TelemetryRecord record) {
    final json = record.toJson()
      ..removeWhere((key, _) => _rowModelKeys.contains(key));
    json['confidence'] = _round(record.confidence, _scoreDecimals);
    json['latencyMs'] = _round(record.latencyMs, _msDecimals);
    json['confidenceThreshold'] = _round(
      record.confidenceThreshold,
      _scoreDecimals,
    );
    final box = record.box;
    if (box != null) json['box'] = _boxJson(box);
    return json;
  }

  static Map<String, dynamic> _correctionJson(DetectionCorrection record) {
    final json = record.toJson();
    json['confidenceThreshold'] = _round(
      record.confidenceThreshold,
      _scoreDecimals,
    );
    final detection = record.detection;
    json['detection'] = {
      ...detection.toJson(),
      'confidence': _round(detection.confidence, _scoreDecimals),
      'box': _boxJson(detection.box),
    };
    return json;
  }

  /// Per-sample JSON with the perf keys dropped on the samples that do not fall
  /// on the [perfSampleStride]. An absent perf key means "not sampled here",
  /// not `0`.
  static Iterable<Map<String, dynamic>> _sampleJson(
    Iterable<RuntimeSample> samples,
  ) sync* {
    var index = 0;
    for (final sample in samples) {
      final json = sample.toJson()
        ..removeWhere((key, _) => _rowModelKeys.contains(key));
      for (final entry in _samplePrecision.entries) {
        final value = json[entry.key];
        if (value is num) {
          json[entry.key] = _round(value.toDouble(), entry.value);
        }
      }
      if (index++ % perfSampleStride != 0) {
        json.removeWhere((key, _) => _perfKeys.contains(key));
      }
      yield json;
    }
  }

  /// `{id: {name, fingerprint}}` for the models the rows were recorded with.
  ///
  /// Read from the stored rows, never from the current settings, so a later
  /// rename or switch cannot relabel history. Rows themselves carry only the id
  /// (see [_rowModelKeys]), so this table is where the readable name lives.
  static Map<String, Map<String, dynamic>> _detectorModels(
    Iterable<TelemetryRecord> records,
    Iterable<RuntimeSample> samples,
  ) {
    final models = <String, Map<String, dynamic>>{};
    void add(String? id, String? name, String? fingerprint) {
      if (id == null) return;
      models.putIfAbsent(id, () => {'name': name, 'fingerprint': fingerprint});
    }

    for (final record in records) {
      add(
        record.detectorModelId,
        record.detectorModelName,
        record.detectorModelFingerprint,
      );
    }
    for (final sample in samples) {
      add(
        sample.detectorModelId,
        sample.detectorModelName,
        sample.detectorModelFingerprint,
      );
    }
    return models;
  }

  TelemetryExport snapshot({
    required TelemetryService telemetry,
    AppSettings? settings,
  }) {
    final samples = _sampleJson(telemetry.samples).toList();
    final detections = telemetry.records.map(_detectionJson).toList();
    return TelemetryExport(
      exportedAt: _clock(),
      appVersion: telemetry.appVersion,
      sessionId: telemetry.sessionId,
      sessionStart: telemetry.sessionStart,
      sessionDurationMs: telemetry.sessionDuration.inMilliseconds,
      settings: settings?.toJson() ?? const {},
      detectorModels: _detectorModels(telemetry.records, telemetry.samples),
      samples: samples,
      detections: detections,
      failures: telemetry.failures.map(_failureJson),
      fallbacks: telemetry.fallbacks.map((record) => record.toJson()),
      recoveries: telemetry.recoveries.map((record) => record.toJson()),
      corrections: telemetry.corrections.map(_correctionJson),
      alertLifecycle: telemetry.alertRecords.map((record) => record.toJson()),
      alertCounters: telemetry.alertCounters.toJson(),
      alertSummaries: [
        for (final engine in InferenceEngine.values)
          for (final interval in AlertLatencyInterval.values)
            _summaryJson(
              telemetry.alertLatencySummary(engine, interval),
              interval,
            ),
      ],
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
      'model_id',
      'model_name',
      'model_fingerprint',
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
      'origin',
      'requested_at',
      'submitted_at',
      'alert_started_at',
      'terminal_at',
      'terminal_state',
      'terminal_cause',
      'had_started',
      'reconciled_at',
      'frame_number',
      'analysis_received_at',
      'inference_started_at',
      'inference_completed_at',
      'result_received_at',
      'detection_accepted_at',
      'interval',
      'p50_ms',
      'p95_ms',
      'max_ms',
      'sample_count',
      'counter_name',
      'counter_value',
      'requested_detection_hz',
      'detection_cadence_automatic',
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
      'low_power_clamped',
      'source_limited',
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
          'model_id': sample['detectorModelId'],
          'model_name': _modelField(
            export.detectorModels,
            sample['detectorModelId'],
            'name',
          ),
          'model_fingerprint': _modelField(
            export.detectorModels,
            sample['detectorModelId'],
            'fingerprint',
          ),
          'latency_ms': sample['latencyMs'],
          'inference_fps': sample['inferenceFps'],
          'object_count': sample['objectCount'],
          'confidence_threshold': sample['confidenceThreshold'],
          // Missing cadence keys stay empty/null, never a fabricated `0`.
          'requested_detection_hz': sample['requestedDetectionHz'],
          'detection_cadence_automatic': sample['detectionCadenceAutomatic'],
          'effective_detection_hz': sample['effectiveDetectionHz'],
          'requested_depth_hz': sample['requestedDepthHz'],
          'effective_depth_hz': sample['effectiveDepthHz'],
          'depth_observed_hz': sample['depthObservedHz'],
          'depth_latency_ms': sample['depthLatencyMs'],
          'depth_status': sample['depthStatus'],
          // Schema-4 stages, read from a possibly schema-3 row: a missing key
          // stays empty (unknown), never a fabricated `0`.
          'detector_pre_ms': sample['detectorPreMs'],
          'detector_inference_ms': sample['detectorInferenceMs'],
          'detector_post_ms': sample['detectorPostMs'],
          'depth_pre_ms': sample['depthPreMs'],
          'depth_inference_ms': sample['depthInferenceMs'],
          'depth_post_ms': sample['depthPostMs'],
          'depth_accelerator': sample['depthAccelerator'],
          'depth_grid_width': sample['depthGridWidth'],
          'depth_grid_height': sample['depthGridHeight'],
          'heatmap_build_ms': sample['heatmapBuildMs'],
          'depth_dropped_ticks': sample['depthDroppedTicks'],
          'low_power_clamped': sample['lowPowerClamped'],
          'source_limited': sample['sourceLimited'],
        }),
      for (final detection in export.detections)
        row({
          'record_type': 'detection',
          'schema_version': TelemetryExport.schemaVersion,
          'timestamp': detection['timestamp'],
          'engine': detection['engine'],
          'model_id': detection['detectorModelId'],
          'model_name': _modelField(
            export.detectorModels,
            detection['detectorModelId'],
            'name',
          ),
          'model_fingerprint': _modelField(
            export.detectorModels,
            detection['detectorModelId'],
            'fingerprint',
          ),
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
      for (final lifecycle in export.alertLifecycle)
        row({
          'record_type': 'alert_lifecycle',
          'schema_version': TelemetryExport.schemaVersion,
          'timestamp': lifecycle['terminalAt'],
          'engine': lifecycle['engine'],
          'origin': lifecycle['origin'],
          'requested_at': lifecycle['requestedAt'],
          'submitted_at': lifecycle['submittedAt'],
          'alert_started_at': lifecycle['alertStartedAt'],
          'terminal_at': lifecycle['terminalAt'],
          'terminal_state': lifecycle['terminalState'],
          'terminal_cause': lifecycle['terminalCause'],
          'had_started': lifecycle['hadStarted'],
          'reconciled_at': lifecycle['reconciledAt'],
          'frame_number': lifecycle['frameNumber'],
          'analysis_received_at': lifecycle['analysisReceivedAt'],
          'inference_started_at': lifecycle['inferenceStartedAt'],
          'inference_completed_at': lifecycle['inferenceCompletedAt'],
          'result_received_at': lifecycle['resultReceivedAt'],
          'detection_accepted_at': lifecycle['detectionAcceptedAt'],
        }),
      for (final entry in export.alertCounters.entries)
        if (entry.key != 'rejectedByReason')
          row({
            'record_type': 'alert_counter',
            'schema_version': TelemetryExport.schemaVersion,
            'counter_name': entry.key,
            'counter_value': entry.value,
          }),
      // Rejected-by-reason is a nested map; one stable key/value row per reason
      // avoids exporting an internal map's toString().
      for (final entry
          in (export.alertCounters['rejectedByReason'] as Map? ?? const {})
              .entries)
        row({
          'record_type': 'alert_counter',
          'schema_version': TelemetryExport.schemaVersion,
          'counter_name': 'rejectedByReason',
          'reason': entry.key,
          'counter_value': entry.value,
        }),
      for (final summary in export.alertSummaries)
        row({
          'record_type': 'alert_summary',
          'schema_version': TelemetryExport.schemaVersion,
          'engine': summary['engine'],
          'interval': summary['interval'],
          'label': summary['label'],
          'p50_ms': summary['p50Ms'],
          'p95_ms': summary['p95Ms'],
          'max_ms': summary['maxMs'],
          'sample_count': summary['sampleCount'],
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

  static Map<String, dynamic> _summaryJson(
    AlertLatencySummary summary,
    AlertLatencyInterval interval,
  ) => {
    'engine': summary.engine.name,
    'interval': interval.name,
    'label': interval.label(summary.engine),
    'p50Ms': _round(summary.p50Ms, _msDecimals),
    'p95Ms': _round(summary.p95Ms, _msDecimals),
    'maxMs': _round(summary.maxMs, _msDecimals),
    'sampleCount': summary.sampleCount,
  };

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
