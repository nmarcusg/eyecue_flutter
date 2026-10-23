import 'package:eyecue_flutter/models/app_settings.dart';
import 'package:eyecue_flutter/services/settings_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Distance/overlay settings', () {
    test('defaults enable depth estimation and both overlays', () async {
      final service = SettingsService(store: InMemorySettingsStore());
      await service.load();
      expect(
        service.distanceEstimationMode,
        DistanceEstimationMode.monocularDepth,
      );
      expect(service.showBoundingBoxes, isTrue);
      expect(service.showDepthHeatmap, isTrue);
      expect(AppSettings.currentSchemaVersion, 4);
    });

    test('setters persist every new field', () async {
      final store = InMemorySettingsStore();
      final service = SettingsService(store: store);
      await service.setShowBoundingBoxes(false);
      await service.setShowDepthHeatmap(false);
      await service.setDistanceEstimationMode(
        DistanceEstimationMode.boundingBoxApproximation,
      );

      final reloaded = SettingsService(store: store);
      await reloaded.load();
      expect(reloaded.showBoundingBoxes, isFalse);
      expect(reloaded.showDepthHeatmap, isFalse);
      expect(
        reloaded.distanceEstimationMode,
        DistanceEstimationMode.boundingBoxApproximation,
      );
    });

    test('older JSON without the new fields parses to the defaults', () {
      final settings = AppSettings.fromJson({'schemaVersion': 3});
      expect(
        settings.distanceEstimationMode,
        DistanceEstimationMode.monocularDepth,
      );
      expect(settings.showBoundingBoxes, isTrue);
      expect(settings.showDepthHeatmap, isTrue);
    });

    test('an unknown persisted mode falls back to depth estimation', () {
      final settings = AppSettings.fromJson({
        'distanceEstimationMode': 'lidar',
      });
      expect(
        settings.distanceEstimationMode,
        DistanceEstimationMode.monocularDepth,
      );
    });

    test('copyWith and equality cover the new fields', () {
      const base = AppSettings();
      final next = base.copyWith(
        showBoundingBoxes: false,
        distanceEstimationMode: DistanceEstimationMode.boundingBoxApproximation,
      );
      expect(next.showBoundingBoxes, isFalse);
      expect(next.showDepthHeatmap, isTrue);
      expect(next, isNot(base));
      expect(AppSettings.fromJson(next.toJson()), next);
    });
  });
}
