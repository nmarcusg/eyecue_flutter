import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/app_settings.dart';

/// Minimal storage abstraction so [SettingsService] can be unit-tested without
/// platform channels.
abstract class SettingsStore {
  Future<String?> read();
  Future<void> write(String contents);
}

/// File-backed [SettingsStore] that persists settings as JSON under the
/// application documents directory (Android).
class FileSettingsStore implements SettingsStore {
  File? _file;

  Future<File> _settingsFile() async {
    if (_file != null) return _file!;
    final dir = await getApplicationDocumentsDirectory();
    _file = File('${dir.path}/eyecue_settings.json');
    return _file!;
  }

  @override
  Future<String?> read() async {
    try {
      final f = await _settingsFile();
      if (!await f.exists()) return null;
      return await f.readAsString();
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> write(String contents) async {
    final f = await _settingsFile();
    await f.writeAsString(contents, flush: true);
  }
}

/// In-memory [SettingsStore] used by tests.
class InMemorySettingsStore implements SettingsStore {
  String? contents;

  @override
  Future<String?> read() async => contents;

  @override
  Future<void> write(String c) async => contents = c;
}

/// Loads/saves [AppSettings] and notifies listeners when values change.
///
/// A plain `ChangeNotifier` — deliberately no state-management framework.
class SettingsService extends ChangeNotifier {
  SettingsService({SettingsStore? store})
    : _store = store ?? FileSettingsStore();

  final SettingsStore _store;
  AppSettings _settings = const AppSettings();

  AppSettings get settings => _settings;
  bool get vibrationFeedback => _settings.vibrationFeedback;
  bool get autoStartDetection => _settings.autoStartDetection;
  bool get lowPowerMode => _settings.lowPowerMode;
  bool get audioEnabled => _settings.audioEnabled;
  InferenceEngine get inferenceEngine => _settings.inferenceEngine;

  /// Loads persisted settings. Safe to call once at startup; on any failure
  /// (missing/corrupt file) the defaults are kept.
  Future<void> load() async {
    try {
      final raw = await _store.read();
      if (raw == null) return;
      final json = jsonDecode(raw) as Map<String, dynamic>;
      _settings = AppSettings.fromJson(json);
    } catch (_) {
      // Corrupt or missing settings → keep defaults.
    }
    notifyListeners();
  }

  Future<void> setVibrationFeedback(bool value) =>
      _update(_settings.copyWith(vibrationFeedback: value));

  Future<void> setAutoStartDetection(bool value) =>
      _update(_settings.copyWith(autoStartDetection: value));

  Future<void> setLowPowerMode(bool value) =>
      _update(_settings.copyWith(lowPowerMode: value));

  Future<void> setAudioEnabled(bool value) =>
      _update(_settings.copyWith(audioEnabled: value));

  Future<void> setInferenceEngine(InferenceEngine value) =>
      _update(_settings.copyWith(inferenceEngine: value));

  Future<void> _update(AppSettings next) async {
    if (next == _settings) return;
    _settings = next;
    notifyListeners();
    try {
      await _store.write(jsonEncode(next.toJson()));
    } catch (_) {
      // A persistence failure must not break the running session.
    }
  }
}
