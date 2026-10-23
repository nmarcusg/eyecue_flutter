import 'dart:collection';

import 'alert_lifecycle.dart';

/// Immutable, machine-readable snapshot of one EyeCue telemetry export.
///
/// The export is deliberately image-free. Camera frames, forensic PNGs, device
/// identifiers, and internal file paths are not part of this contract.
class TelemetryExport {
  static const int schemaVersion = 3;

  final DateTime exportedAt;
  final String appVersion;
  final String sessionId;
  final DateTime? sessionStart;
  final int sessionDurationMs;
  final Map<String, dynamic> settings;
  final List<Map<String, dynamic>> samples;
  final List<Map<String, dynamic>> detections;
  final List<Map<String, dynamic>> failures;
  final List<Map<String, dynamic>> fallbacks;
  final List<Map<String, dynamic>> recoveries;
  final List<Map<String, dynamic>> corrections;
  final List<Map<String, dynamic>> alertLifecycle;
  final Map<String, dynamic> alertCounters;
  final List<Map<String, dynamic>> alertSummaries;

  TelemetryExport({
    required this.exportedAt,
    required this.appVersion,
    required this.sessionId,
    required this.sessionStart,
    required this.sessionDurationMs,
    required Map<String, dynamic> settings,
    required Iterable<Map<String, dynamic>> samples,
    required Iterable<Map<String, dynamic>> detections,
    required Iterable<Map<String, dynamic>> failures,
    required Iterable<Map<String, dynamic>> fallbacks,
    required Iterable<Map<String, dynamic>> recoveries,
    required Iterable<Map<String, dynamic>> corrections,
    required Iterable<Map<String, dynamic>> alertLifecycle,
    required Map<String, dynamic> alertCounters,
    required Iterable<Map<String, dynamic>> alertSummaries,
  }) : settings = UnmodifiableMapView(Map<String, dynamic>.from(settings)),
       samples = List.unmodifiable(
         samples.map(
           (row) => UnmodifiableMapView(Map<String, dynamic>.from(row)),
         ),
       ),
       detections = List.unmodifiable(
         detections.map(
           (row) => UnmodifiableMapView(Map<String, dynamic>.from(row)),
         ),
       ),
       failures = List.unmodifiable(
         failures.map(
           (row) => UnmodifiableMapView(Map<String, dynamic>.from(row)),
         ),
       ),
       fallbacks = List.unmodifiable(
         fallbacks.map(
           (row) => UnmodifiableMapView(Map<String, dynamic>.from(row)),
         ),
       ),
       recoveries = List.unmodifiable(
         recoveries.map(
           (row) => UnmodifiableMapView(Map<String, dynamic>.from(row)),
         ),
       ),
       corrections = List.unmodifiable(
         corrections.map(
           (row) => UnmodifiableMapView(Map<String, dynamic>.from(row)),
         ),
       ),
       alertLifecycle = List.unmodifiable(
         alertLifecycle.map(
           (row) => UnmodifiableMapView(Map<String, dynamic>.from(row)),
         ),
       ),
       alertCounters = UnmodifiableMapView(
         Map<String, dynamic>.from(alertCounters),
       ),
       alertSummaries = List.unmodifiable(
         alertSummaries.map(
           (row) => UnmodifiableMapView(Map<String, dynamic>.from(row)),
         ),
       );

  Map<String, dynamic> toJson() => {
    'schemaVersion': schemaVersion,
    'appVersion': appVersion,
    'exportedAt': exportedAt.toUtc().toIso8601String(),
    'session': {
      'id': sessionId,
      'start': sessionStart?.toUtc().toIso8601String(),
      'durationMs': sessionDurationMs,
    },
    'settings': settings,
    'samples': samples,
    'detections': detections,
    'failures': failures,
    'fallbacks': fallbacks,
    'recoveries': recoveries,
    'corrections': corrections,
    'alertLifecycle': alertLifecycle,
    'alertCounters': alertCounters,
    'alertSummaries': alertSummaries,
  };

  factory TelemetryExport.fromJson(Map<String, dynamic> json) {
    final session = (json['session'] as Map<dynamic, dynamic>? ?? {})
        .cast<String, dynamic>();
    List<Map<String, dynamic>> rows(String key) {
      final raw = json[key] as List<dynamic>? ?? const [];
      return [
        for (final row in raw)
          if (row is Map) row.cast<String, dynamic>(),
      ];
    }

    return TelemetryExport(
      exportedAt:
          DateTime.tryParse(json['exportedAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      appVersion: json['appVersion'] as String? ?? '',
      sessionId: session['id'] as String? ?? '',
      sessionStart: DateTime.tryParse(session['start'] as String? ?? ''),
      sessionDurationMs: (session['durationMs'] as num?)?.toInt() ?? 0,
      settings: (json['settings'] as Map<dynamic, dynamic>? ?? {})
          .cast<String, dynamic>(),
      samples: rows('samples'),
      detections: rows('detections'),
      failures: rows('failures'),
      fallbacks: rows('fallbacks'),
      recoveries: rows('recoveries'),
      corrections: rows('corrections'),
      // Schema v1 has no alert payloads; missing keys default to empty
      // collections and zero/default counters.
      alertLifecycle: rows('alertLifecycle'),
      alertCounters: json['alertCounters'] is Map
          ? (json['alertCounters'] as Map).cast<String, dynamic>()
          : const AlertCounters().toJson(),
      alertSummaries: rows('alertSummaries'),
    );
  }
}
