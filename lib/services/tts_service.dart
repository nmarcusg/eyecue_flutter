import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../models/app_settings.dart';
import '../models/detection_info.dart';
import '../models/tracked_detection.dart';
import 'scene_summary_service.dart';

/// Abstraction over the platform text-to-speech engine so tests can run
/// without the real `flutter_tts` plugin.
abstract class TtsEngine {
  Future<void> init();
  Future<void> speak(String text);
  Future<void> stop();
  Future<void> dispose();
}

/// Real TTS engine backed by [FlutterTts] (Android).
class FlutterTtsEngine implements TtsEngine {
  FlutterTtsEngine({this.language = 'en-US'});

  final String language;
  final FlutterTts _tts = FlutterTts();
  bool _initialized = false;

  @override
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    await _tts.awaitSpeakCompletion(true);
    await _tts.setLanguage(language);
    await _tts.setSpeechRate(0.5);
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.0);
  }

  @override
  Future<void> speak(String text) async {
    await init();
    await _tts.speak(text);
  }

  @override
  Future<void> stop() => _tts.stop();

  @override
  Future<void> dispose() async {
    await _tts.stop();
  }
}

/// Scheduled, de-duplicated audio announcements for the assistive UI.
///
/// All speech scheduling lives here — never inside widgets. Behavior:
///
/// * **Audio enabled/muted** state.
/// * **Cooldown** so we never speak on every frame.
/// * **De-duplication**: the same object label is not re-announced too soon.
/// * **Urgent** (high-priority) announcements bypass the standard cooldown
///   (but still respect a small minimum gap) so obstacles are heard promptly.
/// * **repeatLast()** to re-play the most recent alert (swipe-down gesture).
class TtsService extends ChangeNotifier {
  TtsService({
    required this.engine,
    DateTime Function()? clock,
    this.announcementCooldown = const Duration(seconds: 3),
    this.sameLabelCooldown = const Duration(seconds: 6),
  }) : _clock = clock ?? DateTime.now;

  final TtsEngine engine;

  /// Minimum gap between non-urgent announcements.
  final Duration announcementCooldown;

  /// Minimum gap before the same object label is announced again.
  final Duration sameLabelCooldown;

  final DateTime Function() _clock;
  final SceneSummaryService summaryService = const SceneSummaryService();

  bool _audioEnabled = true;
  bool get audioEnabled => _audioEnabled;

  String? _lastUtterance;
  String? get lastUtterance => _lastUtterance;

  DetectionInfo? _lastAnnouncedDetection;
  DetectionInfo? get lastAnnouncedDetection => _lastAnnouncedDetection;

  InferenceEngine? _lastAnnouncedEngine;
  InferenceEngine? get lastAnnouncedEngine => _lastAnnouncedEngine;

  DateTime? _lastAnnouncementAt;
  DateTime? _lastLabelAt;
  String? _lastLabel;
  bool _speaking = false;
  bool get isSpeaking => _speaking;

  Future<void> init() => engine.init();

  void setAudioEnabled(bool value) {
    if (_audioEnabled == value) return;
    _audioEnabled = value;
    notifyListeners();
  }

  /// Core speak path with cooldown + de-duplication.
  ///
  /// Returns `true` if the utterance was actually sent to the engine.
  Future<bool> speak(String text, {bool urgent = false}) async {
    if (!_audioEnabled) return false;
    final now = _clock();
    final last = _lastAnnouncementAt;
    if (last != null) {
      final since = now.difference(last);
      if (!urgent && since < announcementCooldown) return false;
      if (urgent && since < const Duration(milliseconds: 500)) return false;
    }
    _lastUtterance = text;
    _lastAnnouncementAt = now;
    _speaking = true;
    notifyListeners();
    try {
      await engine.speak(text);
    } finally {
      _speaking = false;
      notifyListeners();
    }
    return true;
  }

  /// Announces the current detection set without flooding. Selects the most
  /// important object (highest priority, then nearest) and speaks one line.
  Future<bool> announceDetections(
    List<DetectionInfo> detections, {
    bool force = false,
    List<TrackedDetection> tracks = const [],
    InferenceEngine? engine,
  }) async {
    if (detections.isEmpty) return false;
    final primary = _selectPrimary(detections);
    final now = _clock();
    if (!force &&
        primary.detection.label == _lastLabel &&
        _lastLabelAt != null &&
        now.difference(_lastLabelAt!) < sameLabelCooldown) {
      return false; // Same object already announced recently.
    }
    _lastLabel = primary.detection.label;
    _lastLabelAt = now;
    final urgent = primary.priority == ObjectPriority.high;
    final announced = await speak(
      summaryService.alert(detections, tracks: tracks),
      urgent: urgent,
    );
    if (announced) {
      _lastAnnouncedDetection = primary;
      _lastAnnouncedEngine = engine;
      notifyListeners();
    }
    return announced;
  }

  Future<bool> announceQuickScan(
    List<DetectionInfo> detections, {
    List<TrackedDetection> tracks = const [],
  }) =>
      speak(summaryService.quickScan(detections, tracks: tracks), urgent: true);

  /// Builds the spoken phrase for one object, e.g.
  /// "Person, high priority obstacle, on your left, approximately near."
  static String buildDetectionUtterance(DetectionInfo info, int totalCount) {
    final sb = StringBuffer(info.label);
    if (info.priority == ObjectPriority.high) {
      sb.write(', high priority obstacle');
    }
    sb.write(', on your ${info.positionLabel}');
    sb.write(', approximately ${info.proximityLabel}');
    if (totalCount > 1) {
      sb.write('. $totalCount objects detected');
    }
    return sb.toString();
  }

  /// The object most important to announce: highest priority, then nearest.
  static DetectionInfo _selectPrimary(List<DetectionInfo> detections) {
    DetectionInfo? best;
    for (final d in detections) {
      if (best == null) {
        best = d;
        continue;
      }
      if (_rank(d.priority) > _rank(best.priority)) {
        best = d;
        continue;
      }
      if (_rank(d.priority) == _rank(best.priority) &&
          _proximityRank(d.proximity) < _proximityRank(best.proximity)) {
        best = d;
      }
    }
    return best!;
  }

  static int _rank(ObjectPriority p) => switch (p) {
    ObjectPriority.high => 2,
    ObjectPriority.medium => 1,
    ObjectPriority.low => 0,
  };

  static int _proximityRank(ProximityBand p) => switch (p) {
    ProximityBand.near => 0,
    ProximityBand.medium => 1,
    ProximityBand.far => 2,
  };

  /// Replays the most recent announcement (swipe-down gesture).
  Future<bool> repeatLast() async {
    final text = _lastUtterance;
    if (text == null) return false;
    return speak(text, urgent: true);
  }

  Future<void> stop() => engine.stop();

  @override
  void dispose() {
    engine.dispose();
    super.dispose();
  }
}
