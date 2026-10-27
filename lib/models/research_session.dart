import '../services/telemetry_service.dart';
import 'alert_lifecycle.dart';
import 'detection_correction.dart';
import 'detector_model.dart';

/// One recorded active interval of a trial.
///
/// [end] is null only while the trial is still running; a finished session
/// stores closed intervals only. Pause time is the gap between two intervals,
/// so it is never counted as active recording.
class ResearchInterval {
  final DateTime start;
  final DateTime? end;

  const ResearchInterval(this.start, [this.end]);

  bool get isClosed => end != null;

  Duration get duration => (end ?? start).difference(start);

  /// Timestamp membership is how rows are attributed to a trial — not list
  /// index, which telemetry's own cap/eviction would corrupt.
  bool contains(DateTime timestamp) =>
      !timestamp.isBefore(start) && (end == null || !timestamp.isAfter(end!));

  ResearchInterval closedAt(DateTime value) => ResearchInterval(start, value);

  Map<String, dynamic> toJson() => {
    'start': start.toUtc().toIso8601String(),
    'end': end?.toUtc().toIso8601String(),
  };

  factory ResearchInterval.fromJson(Map<String, dynamic> json) =>
      ResearchInterval(
        _dateOrEpoch(json['start']),
        json['end'] == null ? null : _dateOrNull(json['end']),
      );
}

DateTime? _dateOrNull(Object? value) =>
    value is String ? DateTime.tryParse(value) : null;

DateTime _dateOrEpoch(Object? value) =>
    _dateOrNull(value) ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

/// An immutable finished respondent trial.
///
/// Every list is frozen at [ResearchSessionService.finish]: later inference, a
/// model change or a second finish cannot alter it. It satisfies
/// [TelemetrySource] so the export and upload code consume it exactly as it
/// consumes the live telemetry buffer — the trial [id] becomes the envelope's
/// `session.id`, which is the server's `client_session_id`.
class ResearchSession implements TelemetrySource {
  /// Stored-file schema. Additive fields only; unknown keys are ignored on read.
  static const int schemaVersion = 1;

  final String id;
  final String participantCode;
  final String trialLabel;

  /// The detector active at Start and at each later model boundary, in order.
  final List<DetectorModelRef> detectors;

  final DateTime wallClockStart;
  final DateTime wallClockEnd;
  final List<ResearchInterval> intervals;

  /// Sum of closed interval durations: recorded time, excluding pauses.
  final int activeDurationMs;

  /// Interval-delta counters: increments during a pause are excluded.
  @override
  final int totalDetections;
  @override
  final int highPriorityAlerts;
  @override
  final int framesProcessed;

  @override
  final List<TelemetryRecord> records;
  @override
  final List<RuntimeSample> samples;
  @override
  final List<TelemetryFailureRecord> failures;
  @override
  final List<EngineFallbackRecord> fallbacks;
  @override
  final List<InferenceRecoveryRecord> recoveries;
  @override
  final List<DetectionCorrection> corrections;
  @override
  final List<AlertLifecycleRecord> alertRecords;
  @override
  final AlertCounters alertCounters;

  /// True when this trial was restored from a draft that stored counters but no
  /// rows: its measurements are absent rather than zero. Carried into the stored
  /// file and the export so nothing claims complete logs.
  @override
  final bool rowsIncomplete;

  @override
  final String appVersion;

  ResearchSession({
    required this.id,
    required this.participantCode,
    required this.trialLabel,
    required List<DetectorModelRef> detectors,
    required this.wallClockStart,
    required this.wallClockEnd,
    required List<ResearchInterval> intervals,
    required this.activeDurationMs,
    required this.totalDetections,
    required this.highPriorityAlerts,
    required this.framesProcessed,
    required List<TelemetryRecord> records,
    required List<RuntimeSample> samples,
    required List<TelemetryFailureRecord> failures,
    required List<EngineFallbackRecord> fallbacks,
    required List<InferenceRecoveryRecord> recoveries,
    required List<DetectionCorrection> corrections,
    required List<AlertLifecycleRecord> alertRecords,
    required this.alertCounters,
    required this.appVersion,
    this.rowsIncomplete = false,
  }) : detectors = List.unmodifiable(detectors),
       intervals = List.unmodifiable(intervals),
       records = List.unmodifiable(records),
       samples = List.unmodifiable(samples),
       failures = List.unmodifiable(failures),
       fallbacks = List.unmodifiable(fallbacks),
       recoveries = List.unmodifiable(recoveries),
       corrections = List.unmodifiable(corrections),
       alertRecords = List.unmodifiable(alertRecords);

  @override
  String get sessionId => id;

  @override
  DateTime get sessionStart => wallClockStart;

  /// The recorded (active) duration, never the wall-clock span: the two differ
  /// by every pause.
  @override
  Duration get sessionDuration => Duration(milliseconds: activeDurationMs);

  Duration get wallClockDuration => wallClockEnd.difference(wallClockStart);

  String get detectorName => detectors.isEmpty
      ? 'Unknown detector'
      : detectors.map((detector) => detector.name).toSet().join(' → ');

  /// Detection rows per detector identity, so a trial that spans a model change
  /// keeps its per-model parts.
  Map<String, int> get detectionsByDetector =>
      _countByDetector(records.map((record) => record.detectorModelId));

  Map<String, int> get samplesByDetector =>
      _countByDetector(samples.map((sample) => sample.detectorModelId));

  static Map<String, int> _countByDetector(Iterable<String?> ids) {
    final counts = <String, int>{};
    for (final id in ids) {
      counts.update(
        id ?? 'unattributed',
        (count) => count + 1,
        ifAbsent: () => 1,
      );
    }
    return counts;
  }

  Map<String, dynamic> toJson() => {
    'schemaVersion': schemaVersion,
    'id': id,
    'participantCode': participantCode,
    'trialLabel': trialLabel,
    'detectors': [
      for (final detector in detectors)
        {
          'id': detector.id,
          'name': detector.name,
          'fingerprint': detector.fingerprint,
          'classCount': detector.classCount,
        },
    ],
    'wallClockStart': wallClockStart.toUtc().toIso8601String(),
    'wallClockEnd': wallClockEnd.toUtc().toIso8601String(),
    'intervals': [for (final interval in intervals) interval.toJson()],
    'activeDurationMs': activeDurationMs,
    'totalDetections': totalDetections,
    'highPriorityAlerts': highPriorityAlerts,
    'framesProcessed': framesProcessed,
    'appVersion': appVersion,
    if (rowsIncomplete) 'rowsIncomplete': true,
    'alertCounters': alertCounters.toJson(),
    'records': [for (final record in records) record.toJson()],
    'samples': [for (final sample in samples) sample.toJson()],
    'failures': [for (final failure in failures) failure.toJson()],
    'fallbacks': [for (final fallback in fallbacks) fallback.toJson()],
    'recoveries': [for (final recovery in recoveries) recovery.toJson()],
    'corrections': [for (final correction in corrections) correction.toJson()],
    'alertRecords': [for (final record in alertRecords) record.toJson()],
  };

  factory ResearchSession.fromJson(Map<String, dynamic> json) {
    Map<String, dynamic> asMap(Object? value) => value is Map
        ? value.cast<String, dynamic>()
        : const <String, dynamic>{};
    List<Map<String, dynamic>> asMaps(Object? value) => value is List
        ? [
            for (final entry in value)
              if (entry is Map) entry.cast<String, dynamic>(),
          ]
        : const [];
    return ResearchSession(
      id: json['id'] as String? ?? '',
      participantCode: json['participantCode'] as String? ?? '',
      trialLabel: json['trialLabel'] as String? ?? '',
      detectors: [
        for (final entry in asMaps(json['detectors']))
          DetectorModelRef(
            id: entry['id'] as String? ?? 'builtin',
            name: entry['name'] as String? ?? '',
            fingerprint: entry['fingerprint'] as String? ?? '',
            classCount: (entry['classCount'] as num?)?.toInt() ?? 0,
          ),
      ],
      wallClockStart: _dateOrEpoch(json['wallClockStart']),
      wallClockEnd: _dateOrEpoch(json['wallClockEnd']),
      intervals: [
        for (final entry in asMaps(json['intervals']))
          ResearchInterval.fromJson(entry),
      ],
      activeDurationMs: (json['activeDurationMs'] as num?)?.toInt() ?? 0,
      totalDetections: (json['totalDetections'] as num?)?.toInt() ?? 0,
      highPriorityAlerts: (json['highPriorityAlerts'] as num?)?.toInt() ?? 0,
      framesProcessed: (json['framesProcessed'] as num?)?.toInt() ?? 0,
      records: [
        for (final entry in asMaps(json['records']))
          TelemetryRecord.fromJson(entry),
      ],
      samples: [
        for (final entry in asMaps(json['samples']))
          RuntimeSample.fromJson(entry),
      ],
      failures: [
        for (final entry in asMaps(json['failures']))
          TelemetryFailureRecord.fromJson(entry),
      ],
      fallbacks: [
        for (final entry in asMaps(json['fallbacks']))
          EngineFallbackRecord.fromJson(entry),
      ],
      recoveries: [
        for (final entry in asMaps(json['recoveries']))
          InferenceRecoveryRecord.fromJson(entry),
      ],
      corrections: [
        for (final entry in asMaps(json['corrections']))
          DetectionCorrection.fromJson(entry),
      ],
      alertRecords: [
        for (final entry in asMaps(json['alertRecords']))
          AlertLifecycleRecord.fromJson(entry),
      ],
      alertCounters: AlertCounters.fromJson(asMap(json['alertCounters'])),
      appVersion: json['appVersion'] as String? ?? '',
      rowsIncomplete: json['rowsIncomplete'] == true,
    );
  }
}
