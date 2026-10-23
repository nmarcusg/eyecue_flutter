import 'package:eyecue_flutter/models/app_settings.dart';
import 'package:eyecue_flutter/screens/ultralytics_detection_screen.dart';
import 'package:eyecue_flutter/services/inference_cadence.dart';
import 'package:flutter_test/flutter_test.dart';

/// Unit tests for the native streaming-config mapping the Ultralytics screen
/// applies from the configurable inference cadence.
///
/// The screen itself cannot be pumped without the native platform view, so the
/// mapping is exercised through the pure helpers it uses.
void main() {
  InferenceCadence cadence({
    int? detectionHz,
    int depthHz = 5,
    bool lowPower = false,
    DistanceEstimationMode mode = DistanceEstimationMode.monocularDepth,
  }) => InferenceCadence.resolve(
    requestedDetectionHz: detectionHz,
    requestedDepthHz: depthHz,
    lowPowerMode: lowPower,
    distanceEstimationMode: mode,
  );

  int? detectorHz(InferenceCadence resolved) => buildStreamingConfig(
    effectiveDetectionHz: resolved.effectiveDetectionHz,
    includeOriginalImage: resolved.depthEnabled,
  ).inferenceFrequency;

  group('buildStreamingConfig', () {
    test('sets only the detector cadence and the analysis-JPEG flag', () {
      final config = buildStreamingConfig(
        effectiveDetectionHz: 15,
        includeOriginalImage: true,
      );

      expect(config.inferenceFrequency, 15);
      expect(config.includeOriginalImage, isTrue);
      expect(config.maxFPS, isNull);
      expect(config.skipFrames, isNull);
      expect(config.throttleInterval, isNull);
      expect(config.analysisResolution, isNull);
    });

    test('leaves bounding-box mode without the analysis JPEG', () {
      final config = buildStreamingConfig(
        effectiveDetectionHz: 15,
        includeOriginalImage: false,
      );

      expect(config.includeOriginalImage, isFalse);
    });
  });

  group('cadence mapping', () {
    test('automatic detector cadence passes null, never 0', () {
      final config = buildStreamingConfig(
        effectiveDetectionHz: cadence().effectiveDetectionHz,
        includeOriginalImage: true,
      );

      expect(config.inferenceFrequency, isNull);
      expect(config.inferenceFrequency, isNot(0));
    });

    test('15 Hz passes through unchanged', () {
      expect(detectorHz(cadence(detectionHz: 15)), 15);
    });

    test('low power caps the detector at 4 Hz', () {
      expect(detectorHz(cadence(detectionHz: 15, lowPower: true)), 4);
      expect(detectorHz(cadence(detectionHz: null, lowPower: true)), 4);
    });

    test('disabling low power restores the stored 15 Hz request', () {
      expect(detectorHz(cadence(detectionHz: 15, lowPower: false)), 15);
    });

    test('bounding-box mode drops the analysis JPEG', () {
      final resolved = cadence(
        detectionHz: 15,
        mode: DistanceEstimationMode.boundingBoxApproximation,
      );
      final config = buildStreamingConfig(
        effectiveDetectionHz: resolved.effectiveDetectionHz,
        includeOriginalImage: resolved.depthEnabled,
      );

      expect(config.includeOriginalImage, isFalse);
      expect(config.inferenceFrequency, 15);
    });

    test('monocular depth mode keeps the analysis JPEG', () {
      final resolved = cadence(detectionHz: 15);
      final config = buildStreamingConfig(
        effectiveDetectionHz: resolved.effectiveDetectionHz,
        includeOriginalImage: resolved.depthEnabled,
      );

      expect(config.includeOriginalImage, isTrue);
    });
  });

  group('streamingConfigKey', () {
    test('changes when the effective detector cadence changes', () {
      final before = streamingConfigKey(
        cadence: cadence(detectionHz: 15),
        mdeEnabled: true,
      );
      final after = streamingConfigKey(
        cadence: cadence(detectionHz: 10),
        mdeEnabled: true,
      );

      expect(before, isNot(equals(after)));
    });

    test('changes when the distance mode changes', () {
      final depthMode = streamingConfigKey(
        cadence: cadence(detectionHz: 15),
        mdeEnabled: true,
      );
      final bboxMode = streamingConfigKey(
        cadence: cadence(
          detectionHz: 15,
          mode: DistanceEstimationMode.boundingBoxApproximation,
        ),
        mdeEnabled: false,
      );

      expect(depthMode.includeOriginalImage, isTrue);
      expect(bboxMode.includeOriginalImage, isFalse);
      expect(depthMode, isNot(equals(bboxMode)));
    });

    test('is unchanged for a depth-target-only change', () {
      final before = streamingConfigKey(
        cadence: cadence(detectionHz: 15, depthHz: 5),
        mdeEnabled: true,
      );
      final after = streamingConfigKey(
        cadence: cadence(detectionHz: 15, depthHz: 9),
        mdeEnabled: true,
      );

      expect(after, equals(before));
    });
  });
}
