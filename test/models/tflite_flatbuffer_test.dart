import 'dart:io';
import 'dart:typed_data';

import 'package:eyecue_flutter/models/tflite_flatbuffer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('scans the metadata-enriched detection artifact', () {
    final enriched = File(
      'assets/eyecue_v8_campus_only_w8a32.tflite',
    ).readAsBytesSync();

    final structure = scanTfliteModelStructure(Uint8List.fromList(enriched));

    // The trailing ZIP metadata payload must not disturb the graph scan.
    expect(structure, isNotNull);
    expect(structure!.tensors, isNotEmpty);
    expect(structure.inputs, isNotEmpty);
    expect(structure.outputs, isNotEmpty);
    expect(structure.inputTensors.single.shape, [1, 3, 640, 640]);
    expect(structure.outputTensors.single.shape, [1, 18, 8400]);
    expect(File('assets/labels.txt').readAsLinesSync(), [
      'bench',
      'bicycle',
      'car',
      'cat',
      'chair',
      'door',
      'fan',
      'hand-rails',
      'person',
      'pole',
      'stairs',
      'table',
      'trash_bin',
      'warning_marker',
    ]);
    expect(structure.tensorTypeCounts[TfliteFlatTensorType.float32], 325);
    expect(structure.tensorTypeCounts[TfliteFlatTensorType.int32], 26);
    expect(structure.tensorTypeCounts[TfliteFlatTensorType.int8], 64);
  });
}
