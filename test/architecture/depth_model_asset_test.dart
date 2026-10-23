import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:eyecue_flutter/models/model_config.dart';
import 'package:eyecue_flutter/services/monocular_depth_estimator.dart';

/// Guards the bundled depth model wiring.
///
/// MDE used to load the official model id, which the plugin resolved by
/// downloading it on first use. Release manifests declare no `INTERNET`
/// permission, so that download could never succeed on device and depth
/// silently degraded. The model is bundled as an asset now; these checks keep it
/// that way.
void main() {
  const assetPath = 'assets/yolo26n-depth_w8a32.tflite';
  const fourMb = 4 * 1024 * 1024;
  const eightMb = 8 * 1024 * 1024;

  test('depth artifact is vendored and plausibly sized', () {
    final file = File(assetPath);
    expect(file.existsSync(), isTrue, reason: '$assetPath is missing');
    final size = file.lengthSync();
    expect(size, greaterThan(fourMb));
    expect(size, lessThan(eightMb));
  });

  test('depth artifact is a LiteRT flatbuffer, not the detection model', () {
    final bytes = File(assetPath).readAsBytesSync();
    // Every TFLite flatbuffer carries the TFL3 file identifier at offset 4.
    expect(String.fromCharCodes(bytes.sublist(4, 8)), 'TFL3');
    final detection = File(EyeCueModelConfig.modelAssetPath).readAsBytesSync();
    expect(bytes.length, isNot(detection.length));
  });

  test('depth artifact appends a zip metadata entry', () {
    final bytes = File(assetPath).readAsBytesSync();
    // FlatBuffer + appended ZIP entry named metadata.json. The entry is
    // DEFLATED, so a plaintext byte grep cannot see the JSON — these are the
    // structural markers that prove the suffix is there.
    const localHeader = [0x50, 0x4B, 0x03, 0x04];
    const endOfCentralDirectory = [0x50, 0x4B, 0x05, 0x06];

    bool contains(List<int> signature, int from, int to) {
      for (var i = from; i + signature.length <= to; i++) {
        var match = true;
        for (var j = 0; j < signature.length; j++) {
          if (bytes[i + j] != signature[j]) {
            match = false;
            break;
          }
        }
        if (match) return true;
      }
      return false;
    }

    expect(contains(localHeader, 0, bytes.length), isTrue);
    expect(
      contains(endOfCentralDirectory, bytes.length - 64 * 1024, bytes.length),
      isTrue,
    );
  });

  test('pubspec declares the depth asset and the constant matches it', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(pubspec, contains('- $assetPath'));
    expect(EyeCueModelConfig.depthModelAssetPath, assetPath);
  });

  test('estimator defaults to the bundled asset with no network path', () {
    final estimator = MonocularDepthEstimator();
    expect(estimator.modelId, EyeCueModelConfig.depthModelAssetPath);
    estimator.dispose();

    final source = File(
      'lib/services/monocular_depth_estimator.dart',
    ).readAsStringSync();
    expect(source, contains('EyeCueModelConfig.depthModelAssetPath'));
    expect(source, isNot(contains('http://')));
    expect(source, isNot(contains('https://')));
    expect(source, isNot(contains("'yolo26n-depth'")));
  });
}
