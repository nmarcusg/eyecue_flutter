import 'package:eyecue_flutter/models/app_settings.dart';
import 'package:eyecue_flutter/services/settings_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SettingsService', () {
    test('defaults are applied when no persisted settings exist', () async {
      final service = SettingsService(store: InMemorySettingsStore());
      await service.load();
      expect(service.vibrationFeedback, isTrue);
      expect(service.autoStartDetection, isTrue);
      expect(service.lowPowerMode, isFalse);
      expect(service.audioEnabled, isTrue);
      expect(service.inferenceEngine, InferenceEngine.custom);
    });

    test('setters update values and notify listeners', () async {
      final service = SettingsService(store: InMemorySettingsStore());
      var notified = 0;
      service.addListener(() => notified++);
      await service.setLowPowerMode(true);
      await service.setAudioEnabled(false);
      expect(service.lowPowerMode, isTrue);
      expect(service.audioEnabled, isFalse);
      expect(notified, 2);
    });

    test('values persist and reload from the store', () async {
      final store = InMemorySettingsStore();
      final service = SettingsService(store: store);
      await service.load();
      await service.setVibrationFeedback(false);
      await service.setAutoStartDetection(false);
      await service.setInferenceEngine(InferenceEngine.ultralytics);

      final reloaded = SettingsService(store: store);
      await reloaded.load();
      expect(reloaded.vibrationFeedback, isFalse);
      expect(reloaded.autoStartDetection, isFalse);
      expect(reloaded.inferenceEngine, InferenceEngine.ultralytics);
    });

    test('corrupt persisted JSON falls back to defaults', () async {
      final store = InMemorySettingsStore()..contents = '{not valid json';
      final service = SettingsService(store: store);
      await service.load();
      expect(service.vibrationFeedback, isTrue);
    });
  });

  group('AppSettings', () {
    test('copyWith preserves unchanged fields', () {
      const a = AppSettings(lowPowerMode: true);
      final b = a.copyWith(audioEnabled: false);
      expect(b.lowPowerMode, isTrue);
      expect(b.audioEnabled, isFalse);
      expect(b.vibrationFeedback, isTrue);
    });

    test('toJson / fromJson round-trip', () {
      const a = AppSettings(
        vibrationFeedback: false,
        autoStartDetection: false,
        inferenceEngine: InferenceEngine.ultralytics,
      );
      final b = AppSettings.fromJson(a.toJson());
      expect(b, a);
    });

    test('unknown persisted engine falls back to custom', () {
      final settings = AppSettings.fromJson({
        'inferenceEngine': 'missing-engine',
      });
      expect(settings.inferenceEngine, InferenceEngine.custom);
    });
  });
}
