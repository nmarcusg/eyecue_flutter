import 'dart:io';
import 'dart:typed_data';

import 'package:eyecue_flutter/models/tflite_flatbuffer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('scans the metadata-enriched artifact like the base graph', () {
    final base = File('assets/yolov8n_int8_new.tflite').readAsBytesSync();
    final enriched = File(
      'assets/yolov8n_int8_new_metadata.tflite',
    ).readAsBytesSync();

    final baseStructure = scanTfliteModelStructure(Uint8List.fromList(base));
    final enrichedStructure = scanTfliteModelStructure(
      Uint8List.fromList(enriched),
    );

    expect(baseStructure, isNotNull);
    expect(enrichedStructure, isNotNull);
    expect(enrichedStructure!.inputs, baseStructure!.inputs);
    expect(enrichedStructure.outputs, baseStructure.outputs);
    expect(enrichedStructure.tensorTypeCounts, baseStructure.tensorTypeCounts);
    expect(enrichedStructure.tensors.length, baseStructure.tensors.length);
    for (var index = 0; index < baseStructure.tensors.length; index++) {
      final expected = baseStructure.tensors[index];
      final actual = enrichedStructure.tensors[index];
      expect(actual.index, expected.index);
      expect(actual.typeCode, expected.typeCode);
      expect(actual.shape, expected.shape);
      expect(actual.bufferIndex, expected.bufferIndex);
    }
  });
}
