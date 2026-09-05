import 'package:flutter/foundation.dart';

import '../models/app_settings.dart';
import '../models/detection_correction.dart';
import '../models/detection_info.dart';

/// Stores explicit, bounded, image-free detection annotations for export.
class CorrectionService extends ChangeNotifier {
  CorrectionService({
    Iterable<String> labels = const [],
    DateTime Function()? clock,
    String? sessionId,
  }) : _labels = Set.unmodifiable(labels),
       _clock = clock ?? DateTime.now,
       _sessionId =
           sessionId ?? 'session-${DateTime.now().microsecondsSinceEpoch}';

  final Set<String> _labels;
  final DateTime Function() _clock;
  final String _sessionId;
  final List<DetectionCorrection> _records = [];
  int _nextId = 1;

  String get sessionId => _sessionId;
  List<String> get labels => _labels.toList(growable: false);
  List<DetectionCorrection> get records => List.unmodifiable(_records);

  DetectionCorrection add({
    required DetectionInfo info,
    required CorrectionFeedback feedback,
    required InferenceEngine engine,
    required double confidenceThreshold,
    String? correctedLabel,
  }) {
    final normalizedLabel = correctedLabel?.trim();
    if (feedback == CorrectionFeedback.incorrect &&
        normalizedLabel != null &&
        normalizedLabel.isNotEmpty &&
        !_labels.contains(normalizedLabel)) {
      throw ArgumentError.value(
        correctedLabel,
        'correctedLabel',
        'The corrected label must be present in the shared label list.',
      );
    }
    final record = DetectionCorrection(
      recordId: 'correction-${_nextId++}',
      timestamp: _clock(),
      sessionId: _sessionId,
      engine: engine,
      detection: info.detection,
      feedback: feedback,
      correctedLabel: feedback == CorrectionFeedback.incorrect
          ? (normalizedLabel?.isEmpty ?? true ? null : normalizedLabel)
          : null,
      confidenceThreshold: confidenceThreshold,
    );
    _records.add(record);
    notifyListeners();
    return record;
  }

  /// Convenience method used by tests and importers when a serialized record
  /// has already passed validation.
  void addRecord(DetectionCorrection record) {
    if (record.feedback == CorrectionFeedback.incorrect &&
        record.correctedLabel != null &&
        !_labels.contains(record.correctedLabel)) {
      throw ArgumentError.value(record.correctedLabel, 'correctedLabel');
    }
    _records.add(record);
    notifyListeners();
  }

  void clear() {
    if (_records.isEmpty) return;
    _records.clear();
    notifyListeners();
  }
}
