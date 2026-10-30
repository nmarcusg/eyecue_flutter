import 'package:eyecue_flutter/models/app_settings.dart';
import 'package:eyecue_flutter/models/model_config.dart';
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
    depthInstanceId: resolved.depthEnabled ? 'depth-instance' : null,
    depthIntervalMs: resolved.depthInterval?.inMilliseconds,
  ).inferenceFrequency;

  group('buildStreamingConfig', () {
    test('sets the detector cadence and the native depth target only', () {
      final config = buildStreamingConfig(
        effectiveDetectionHz: 15,
        depthInstanceId: 'yolo_depth_1',
        depthIntervalMs: 500,
      );

      expect(config.inferenceFrequency, 15);
      expect(config.depthInstanceId, 'yolo_depth_1');
      expect(config.depthIntervalMs, 500);
      expect(config.depthMaxDim, EyeCueModelConfig.depthGridMaxDim);
      expect(config.includeOriginalImage, isFalse);
      expect(config.maxFPS, isNull);
      expect(config.skipFrames, isNull);
      expect(config.throttleInterval, isNull);
      expect(config.analysisResolution, isNull);
    });

    test('never asks the view for the analysis frame', () {
      final config = buildStreamingConfig(
        effectiveDetectionHz: null,
        depthInstanceId: 'depth-instance',
        depthIntervalMs: 200,
      );

      expect(config.includeOriginalImage, isFalse);
    });

    test('bounding-box mode passes no depth instance', () {
      final resolved = cadence(
        detectionHz: 15,
        mode: DistanceEstimationMode.boundingBoxApproximation,
      );
      final config = buildStreamingConfig(
        effectiveDetectionHz: resolved.effectiveDetectionHz,
        depthInstanceId: resolved.depthEnabled ? 'depth-instance' : null,
        depthIntervalMs: resolved.depthInterval?.inMilliseconds,
      );

      expect(resolved.depthEnabled, isFalse);
      expect(config.depthInstanceId, isNull);
      expect(config.depthIntervalMs, isNull);
      expect(config.inferenceFrequency, 15);
    });
  });

  group('cadence mapping', () {
    test('automatic detector cadence passes null, never 0', () {
      final config = buildStreamingConfig(
        effectiveDetectionHz: cadence().effectiveDetectionHz,
        depthInstanceId: 'depth-instance',
        depthIntervalMs: null,
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

    test('the resolved depth target becomes the native tick interval', () {
      final resolved = cadence(detectionHz: 15, depthHz: 2);
      final config = buildStreamingConfig(
        effectiveDetectionHz: resolved.effectiveDetectionHz,
        depthInstanceId: 'depth-instance',
        depthIntervalMs: resolved.depthInterval?.inMilliseconds,
      );

      expect(config.depthIntervalMs, 500);
    });
  });

  group('streamingConfigKey', () {
    test('changes when the effective detector cadence changes', () {
      final before = streamingConfigKey(
        cadence: cadence(detectionHz: 15),
        mdeEnabled: true,
        depthInstanceId: 'depth-instance',
      );
      final after = streamingConfigKey(
        cadence: cadence(detectionHz: 10),
        mdeEnabled: true,
        depthInstanceId: 'depth-instance',
      );

      expect(before, isNot(equals(after)));
    });

    test('changes when the distance mode changes', () {
      final depthMode = streamingConfigKey(
        cadence: cadence(detectionHz: 15),
        mdeEnabled: true,
        depthInstanceId: 'depth-instance',
      );
      final bboxMode = streamingConfigKey(
        cadence: cadence(
          detectionHz: 15,
          mode: DistanceEstimationMode.boundingBoxApproximation,
        ),
        mdeEnabled: false,
        depthInstanceId: null,
      );

      expect(depthMode.depthInstanceId, 'depth-instance');
      expect(bboxMode.depthInstanceId, isNull);
      expect(depthMode, isNot(equals(bboxMode)));
    });

    test(
      'changes when the depth target changes, because it reaches native',
      () {
        final before = streamingConfigKey(
          cadence: cadence(detectionHz: 15, depthHz: 2),
          mdeEnabled: true,
          depthInstanceId: 'depth-instance',
        );
        final after = streamingConfigKey(
          cadence: cadence(detectionHz: 15, depthHz: 5),
          mdeEnabled: true,
          depthInstanceId: 'depth-instance',
        );

        expect(before.depthIntervalMs, 500);
        expect(after.depthIntervalMs, 200);
        expect(before, isNot(equals(after)));
      },
    );

    test('changes when the depth instance id arrives after model load', () {
      final before = streamingConfigKey(
        cadence: cadence(detectionHz: 15),
        mdeEnabled: true,
        depthInstanceId: null,
      );
      final after = streamingConfigKey(
        cadence: cadence(detectionHz: 15),
        mdeEnabled: true,
        depthInstanceId: 'depth-instance',
      );

      expect(before, isNot(equals(after)));
    });

    test(
      'is stable for identical inputs, so overlay-only changes are inert',
      () {
        final first = streamingConfigKey(
          cadence: cadence(detectionHz: 15),
          mdeEnabled: true,
          depthInstanceId: 'depth-instance',
        );
        final second = streamingConfigKey(
          cadence: cadence(detectionHz: 15),
          mdeEnabled: true,
          depthInstanceId: 'depth-instance',
        );

        expect(second, equals(first));
      },
    );
  });
}
