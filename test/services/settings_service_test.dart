import 'package:eyecue_flutter/models/app_settings.dart';
import 'package:eyecue_flutter/models/detector_model.dart';
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

    test('cadence targets default to Automatic and 2 Hz', () async {
      final service = SettingsService(store: InMemorySettingsStore());
      await service.load();
      expect(service.detectionTargetHz, isNull);
      expect(service.depthTargetHz, AppSettings.defaultDepthTargetHz);
      // Bumped 6 -> 7 when the detector model selection was added.
      expect(AppSettings.currentSchemaVersion, 7);
    });

    test('detector selection defaults to the built-in model', () async {
      final service = SettingsService(store: InMemorySettingsStore());
      await service.load();
      expect(service.detectorModelKind, DetectorModelKind.builtIn);
      expect(service.customModelPath, isNull);
    });

    test('setDetectorModel persists a custom choice and clears it', () async {
      final store = InMemorySettingsStore();
      final service = SettingsService(store: store);
      await service.setDetectorModel(
        kind: DetectorModelKind.custom,
        name: 'Obstacle Detector v2',
        fingerprint: '0123456789abcdef-1234',
        path: '/data/app/eyecue_models/0123456789abcdef-1234.tflite',
        classCount: 3,
      );

      final reloaded = SettingsService(store: store);
      await reloaded.load();
      expect(reloaded.detectorModelKind, DetectorModelKind.custom);
      expect(reloaded.customModelName, 'Obstacle Detector v2');
      expect(reloaded.customModelFingerprint, '0123456789abcdef-1234');
      expect(reloaded.customModelClassCount, 3);

      await reloaded.setDetectorModel(kind: DetectorModelKind.builtIn);
      expect(reloaded.customModelName, isNull);
      expect(reloaded.customModelFingerprint, isNull);
      expect(reloaded.customModelPath, isNull);
      expect(reloaded.customModelClassCount, isNull);
    });

    test(
      'safety acknowledgement defaults to unacknowledged and persists',
      () async {
        final store = InMemorySettingsStore();
        final service = SettingsService(store: store);
        await service.load();
        expect(service.safetyAcknowledged, isFalse);

        var notified = 0;
        service.addListener(() => notified++);
        await service.setSafetyAcknowledged(true);
        expect(service.safetyAcknowledged, isTrue);
        expect(notified, 1);

        final reloaded = SettingsService(store: store);
        await reloaded.load();
        expect(reloaded.safetyAcknowledged, isTrue);
      },
    );

    test('cadence setters update, notify and persist', () async {
      final store = InMemorySettingsStore();
      final service = SettingsService(store: store);
      var notified = 0;
      service.addListener(() => notified++);
      await service.setDetectionTargetHz(12);
      await service.setDepthTargetHz(6);
      expect(service.detectionTargetHz, 12);
      expect(service.depthTargetHz, 6);
      expect(notified, 2);

      final reloaded = SettingsService(store: store);
      await reloaded.load();
      expect(reloaded.detectionTargetHz, 12);
      expect(reloaded.depthTargetHz, 6);
    });

    test('detection target persists back to Automatic (null)', () async {
      final store = InMemorySettingsStore();
      final service = SettingsService(store: store);
      await service.setDetectionTargetHz(8);
      await service.setDetectionTargetHz(null);
      expect(service.detectionTargetHz, isNull);

      final reloaded = SettingsService(store: store);
      await reloaded.load();
      expect(reloaded.detectionTargetHz, isNull);
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

    test('a legacy custom engine value migrates to the single engine', () {
      final settings = AppSettings.fromJson({
        'schemaVersion': 1,
        'inferenceEngine': 'custom',
      });
      expect(settings.inferenceEngine, InferenceEngine.ultralytics);
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

    test('cadence targets round-trip through JSON', () {
      const a = AppSettings(detectionTargetHz: 7, depthTargetHz: 4);
      expect(AppSettings.fromJson(a.toJson()), a);
    });

    test('copyWith clears the detection target without touching the rest', () {
      const a = AppSettings(detectionTargetHz: 9, depthTargetHz: 3);
      final cleared = a.copyWith(detectionTargetHz: null);
      expect(cleared.detectionTargetHz, isNull);
      expect(cleared.depthTargetHz, 3);
      // Other copyWith calls must not resurrect the cleared value.
      final unchanged = cleared.copyWith(audioEnabled: false);
      expect(unchanged.detectionTargetHz, isNull);
      expect(unchanged.depthTargetHz, 3);
    });

    test('legacy and invalid cadence JSON normalizes safely', () {
      expect(AppSettings.fromJson({}).detectionTargetHz, isNull);
      expect(AppSettings.fromJson({}).depthTargetHz, 2);
      expect(
        AppSettings.fromJson({
          'schemaVersion': 4,
          'detectionTargetHz': 31,
        }).detectionTargetHz,
        30,
      );
      expect(
        AppSettings.fromJson({'detectionTargetHz': 12.4}).detectionTargetHz,
        12,
      );
      expect(
        AppSettings.fromJson({'detectionTargetHz': 0}).detectionTargetHz,
        isNull,
      );
      expect(
        AppSettings.fromJson({'detectionTargetHz': -3}).detectionTargetHz,
        isNull,
      );
      expect(
        AppSettings.fromJson({'detectionTargetHz': '12'}).detectionTargetHz,
        isNull,
      );
      expect(
        AppSettings.fromJson({
          'detectionTargetHz': double.infinity,
        }).detectionTargetHz,
        isNull,
      );
      expect(AppSettings.fromJson({'depthTargetHz': 1}).depthTargetHz, 2);
      expect(AppSettings.fromJson({'depthTargetHz': 99}).depthTargetHz, 10);
      expect(AppSettings.fromJson({'depthTargetHz': 5.6}).depthTargetHz, 6);
      expect(
        AppSettings.fromJson({'depthTargetHz': double.nan}).depthTargetHz,
        2,
      );
    });

    test('public normalizers round and clamp', () {
      expect(AppSettings.normalizeDetectionTargetHz(null), isNull);
      expect(AppSettings.normalizeDetectionTargetHz(2.6), 3);
      expect(AppSettings.normalizeDetectionTargetHz(30.4), 30);
      expect(AppSettings.normalizeDepthTargetHz(null), 2);
      expect(AppSettings.normalizeDepthTargetHz(10.6), 10);
    });
  });
}
