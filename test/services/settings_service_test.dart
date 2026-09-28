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
      expect(service.inferenceEngine, InferenceEngine.ultralytics);
      expect(service.detectionConfidence, 0.25);
      expect(service.hideBottomNavigation, isFalse);
    });

    test('hideBottomNavigation setter notifies and persists', () async {
      final store = InMemorySettingsStore();
      final service = SettingsService(store: store);
      var notified = 0;
      service.addListener(() => notified++);
      await service.setHideBottomNavigation(true);
      expect(service.hideBottomNavigation, isTrue);
      expect(notified, 1);

      final reloaded = SettingsService(store: store);
      await reloaded.load();
      expect(reloaded.hideBottomNavigation, isTrue);
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
      await service.setDetectionConfidence(0.4);

      final reloaded = SettingsService(store: store);
      await reloaded.load();
      expect(reloaded.vibrationFeedback, isFalse);
      expect(reloaded.autoStartDetection, isFalse);
      expect(reloaded.inferenceEngine, InferenceEngine.ultralytics);
      expect(reloaded.detectionConfidence, 0.4);
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

    test('missing hideBottomNavigation parses to a visible bar', () {
      final settings = AppSettings.fromJson({'schemaVersion': 1});
      expect(settings.hideBottomNavigation, isFalse);
    });

    test('hideBottomNavigation round-trips through JSON', () {
      const a = AppSettings(hideBottomNavigation: true);
      final b = AppSettings.fromJson(a.toJson());
      expect(b.hideBottomNavigation, isTrue);
      expect(b, a);
    });

    test('unknown persisted engine falls back to the recommended default', () {
      final settings = AppSettings.fromJson({
        'inferenceEngine': 'missing-engine',
      });
      expect(settings.inferenceEngine, InferenceEngine.ultralytics);
    });

    test('explicit custom engine remains custom after migration', () {
      final settings = AppSettings.fromJson({
        'schemaVersion': 1,
        'inferenceEngine': 'custom',
      });
      expect(settings.inferenceEngine, InferenceEngine.custom);
    });

    test('confidence values are clamped and quantized', () {
      expect(
        AppSettings.fromJson({'detectionConfidence': 0.01}).detectionConfidence,
        0.1,
      );
      expect(
        AppSettings.fromJson({'detectionConfidence': 0.43}).detectionConfidence,
        0.45,
      );
      expect(
        AppSettings.fromJson({'detectionConfidence': 2.0}).detectionConfidence,
        0.75,
      );
    });
  });
}
