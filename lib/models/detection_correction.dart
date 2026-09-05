import 'detection.dart';
import 'app_settings.dart';

/// First-level feedback choices for a detection annotation.
enum CorrectionFeedback { correct, incorrect, unsure }

extension CorrectionFeedbackX on CorrectionFeedback {
  String get label => switch (this) {
    CorrectionFeedback.correct => 'Correct',
    CorrectionFeedback.incorrect => 'Incorrect',
    CorrectionFeedback.unsure => 'Unsure',
  };
}

/// Versioned, image-free research annotation linked to its original detection.
class DetectionCorrection {
  static const int schemaVersion = 1;

  final String recordId;
  final DateTime timestamp;
  final String sessionId;
  final InferenceEngine engine;
  final Detection detection;
  final CorrectionFeedback feedback;
  final String? correctedLabel;
  final double confidenceThreshold;

  const DetectionCorrection({
    required this.recordId,
    required this.timestamp,
    required this.sessionId,
    required this.engine,
    required this.detection,
    required this.feedback,
    required this.correctedLabel,
    required this.confidenceThreshold,
  });

  Map<String, dynamic> toJson() => {
    'schemaVersion': schemaVersion,
    'recordId': recordId,
    'timestamp': timestamp.toUtc().toIso8601String(),
    'sessionId': sessionId,
    'engine': engine.name,
    'detection': detection.toJson(),
    'feedback': feedback.name,
    'correctedLabel': correctedLabel,
    'confidenceThreshold': confidenceThreshold,
  };

  factory DetectionCorrection.fromJson(Map<String, dynamic> json) {
    final engineName = json['engine'];
    final feedbackName = json['feedback'];
    return DetectionCorrection(
      recordId: json['recordId'] as String? ?? '',
      timestamp:
          DateTime.tryParse(json['timestamp'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      sessionId: json['sessionId'] as String? ?? '',
      engine: InferenceEngine.values.firstWhere(
        (value) => value.name == engineName,
        orElse: () => InferenceEngine.ultralytics,
      ),
      detection: Detection.fromJson(
        (json['detection'] as Map<dynamic, dynamic>? ?? {})
            .cast<String, dynamic>(),
      ),
      feedback: CorrectionFeedback.values.firstWhere(
        (value) => value.name == feedbackName,
        orElse: () => CorrectionFeedback.unsure,
      ),
      correctedLabel: json['correctedLabel'] as String?,
      confidenceThreshold:
          (json['confidenceThreshold'] as num?)?.toDouble() ?? 0.25,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is DetectionCorrection &&
      other.recordId == recordId &&
      other.timestamp == timestamp &&
      other.sessionId == sessionId &&
      other.engine == engine &&
      other.detection == detection &&
      other.feedback == feedback &&
      other.correctedLabel == correctedLabel &&
      other.confidenceThreshold == confidenceThreshold;

  @override
  int get hashCode => Object.hash(
    recordId,
    timestamp,
    sessionId,
    engine,
    detection,
    feedback,
    correctedLabel,
    confidenceThreshold,
  );
}
