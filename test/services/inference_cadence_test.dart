import 'package:eyecue_flutter/models/app_settings.dart';
import 'package:eyecue_flutter/services/inference_cadence.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('InferenceCadence.resolve', () {
    test('automatic detector cadence stays uncapped without low power', () {
      final cadence = InferenceCadence.resolve(
        requestedDetectionHz: null,
        requestedDepthHz: 5,
        lowPowerMode: false,
        distanceEstimationMode: DistanceEstimationMode.monocularDepth,
      );
      expect(cadence.requestedDetectionHz, isNull);
      expect(cadence.effectiveDetectionHz, isNull);
      expect(cadence.effectiveDepthHz, 5);
      expect(cadence.depthEnabled, isTrue);
      expect(cadence.lowPowerClamped, isFalse);
      expect(cadence.sourceLimited, isFalse);
    });

    test('numeric targets pass through when nothing caps them', () {
      final cadence = InferenceCadence.resolve(
        requestedDetectionHz: 15,
        requestedDepthHz: 5,
        lowPowerMode: false,
        distanceEstimationMode: DistanceEstimationMode.monocularDepth,
      );
      expect(cadence.effectiveDetectionHz, 15);
      expect(cadence.effectiveDepthHz, 5);
      expect(cadence.lowPowerClamped, isFalse);
      expect(cadence.sourceLimited, isFalse);
    });

    test('low power caps a fast detector and a fast depth target', () {
      final cadence = InferenceCadence.resolve(
        requestedDetectionHz: 20,
        requestedDepthHz: 6,
        lowPowerMode: true,
        distanceEstimationMode: DistanceEstimationMode.monocularDepth,
      );
      expect(
        cadence.effectiveDetectionHz,
        InferenceCadence.lowPowerDetectionCapHz,
      );
      expect(cadence.effectiveDepthHz, InferenceCadence.lowPowerDepthCapHz);
      expect(cadence.lowPowerClamped, isTrue);
    });

    test('low power reports no clamp when both targets already fit', () {
      final cadence = InferenceCadence.resolve(
        requestedDetectionHz: 3,
        requestedDepthHz: 2,
        lowPowerMode: true,
        distanceEstimationMode: DistanceEstimationMode.monocularDepth,
      );
      expect(cadence.effectiveDetectionHz, 3);
      expect(cadence.effectiveDepthHz, 2);
      expect(cadence.lowPowerClamped, isFalse);
    });

    test('low power caps automatic detection at the low power rate', () {
      final cadence = InferenceCadence.resolve(
        requestedDetectionHz: null,
        requestedDepthHz: 2,
        lowPowerMode: true,
        distanceEstimationMode: DistanceEstimationMode.monocularDepth,
      );
      expect(cadence.effectiveDetectionHz, 4);
      expect(cadence.lowPowerClamped, isTrue);
    });

    test('low power clamps depth alone when only depth is too fast', () {
      final cadence = InferenceCadence.resolve(
        requestedDetectionHz: 3,
        requestedDepthHz: 6,
        lowPowerMode: true,
        distanceEstimationMode: DistanceEstimationMode.monocularDepth,
      );
      expect(cadence.effectiveDetectionHz, 3);
      expect(cadence.effectiveDepthHz, 2);
      expect(cadence.lowPowerClamped, isTrue);
    });

    test('a numeric detector cadence source-limits a faster depth target', () {
      final cadence = InferenceCadence.resolve(
        requestedDetectionHz: 3,
        requestedDepthHz: 6,
        lowPowerMode: false,
        distanceEstimationMode: DistanceEstimationMode.monocularDepth,
      );
      expect(cadence.effectiveDepthHz, 3);
      expect(cadence.sourceLimited, isTrue);
      expect(cadence.lowPowerClamped, isFalse);
    });

    test('bounding box mode disables depth without clamping its target', () {
      final cadence = InferenceCadence.resolve(
        requestedDetectionHz: 3,
        requestedDepthHz: 6,
        lowPowerMode: true,
        distanceEstimationMode: DistanceEstimationMode.boundingBoxApproximation,
      );
      expect(cadence.depthEnabled, isFalse);
      expect(cadence.effectiveDepthHz, 0);
      expect(cadence.sourceLimited, isFalse);
      // Low power only lowered detection here (3 Hz stays), so no clamp.
      expect(cadence.lowPowerClamped, isFalse);
    });
  });

  group('InferenceCadence.depthInterval', () {
    InferenceCadence cadenceFor({
      required int depthHz,
      int? detectionHz,
      bool lowPower = false,
      DistanceEstimationMode mode = DistanceEstimationMode.monocularDepth,
    }) => InferenceCadence.resolve(
      requestedDetectionHz: detectionHz,
      requestedDepthHz: depthHz,
      lowPowerMode: lowPower,
      distanceEstimationMode: mode,
    );

    test('2 Hz schedules every 500 ms', () {
      expect(
        cadenceFor(depthHz: 2).depthInterval,
        const Duration(milliseconds: 500),
      );
    });

    test('3 Hz schedules every 333 ms', () {
      expect(
        cadenceFor(depthHz: 3).depthInterval,
        const Duration(milliseconds: 333),
      );
    });

    test('10 Hz schedules every 100 ms', () {
      expect(
        cadenceFor(depthHz: 10).depthInterval,
        const Duration(milliseconds: 100),
      );
    });

    test('a mode without depth work has no interval', () {
      expect(
        cadenceFor(
          depthHz: 6,
          mode: DistanceEstimationMode.boundingBoxApproximation,
        ).depthInterval,
        isNull,
      );
    });

    test('a low power clamp flows into the interval', () {
      final cadence = cadenceFor(depthHz: 10, lowPower: true);
      expect(cadence.effectiveDepthHz, InferenceCadence.lowPowerDepthCapHz);
      expect(cadence.depthInterval, const Duration(milliseconds: 500));
    });

    test('a source-limited target flows into the interval', () {
      final cadence = cadenceFor(depthHz: 10, detectionHz: 3);
      expect(cadence.sourceLimited, isTrue);
      expect(cadence.depthInterval, const Duration(milliseconds: 333));
    });
  });
}
