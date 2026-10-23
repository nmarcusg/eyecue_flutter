import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards the single-engine architecture.
///
/// The Custom EyeCue engine, its Dart/TFLite runtime and the Gradle workaround
/// that existed only to run both engines in one APK are gone. These tokens must
/// never come back; anything that reintroduces a second engine fails here.
void main() {
  const forbidden = [
    'InferenceEngine.custom',
    'tflite_flutter',
    'inference_isolate',
    'inference_worker_lifecycle',
    'forensic_log',
    'tensor_rotation',
    'png_encoder',
    'classicLiteRt',
    'Custom EyeCue',
  ];

  final roots = ['lib', 'test', 'android'];
  final thisFile = File(
    'test/architecture/no_custom_engine_test.dart',
  ).absolute.path;

  Iterable<File> sourceFiles() sync* {
    for (final root in roots) {
      final dir = Directory(root);
      if (!dir.existsSync()) continue;
      for (final entity in dir.listSync(recursive: true)) {
        if (entity is! File) continue;
        if (entity.absolute.path == thisFile) continue;
        if (!entity.path.endsWith('.dart') &&
            !entity.path.endsWith('.kts') &&
            !entity.path.endsWith('.gradle') &&
            !entity.path.endsWith('.xml')) {
          continue;
        }
        yield entity;
      }
    }
    final pubspec = File('pubspec.yaml');
    if (pubspec.existsSync()) yield pubspec;
  }

  test('no Custom EyeCue engine or tflite_flutter reference remains', () {
    final hits = <String>[];
    for (final file in sourceFiles()) {
      final text = file.readAsStringSync();
      for (final token in forbidden) {
        if (text.contains(token)) hits.add('${file.path}: $token');
      }
    }
    expect(hits, isEmpty, reason: hits.join('\n'));
  });

  test('only the two runtime model assets are vendored', () {
    final assets =
        Directory('assets')
            .listSync()
            .whereType<File>()
            .map((file) => file.uri.pathSegments.last)
            .where((name) => name.endsWith('.tflite'))
            .toList()
          ..sort();
    expect(assets, [
      'yolo26n-depth_w8a32.tflite',
      'yolov8n_int8_new_metadata.tflite',
    ]);
  });
}
