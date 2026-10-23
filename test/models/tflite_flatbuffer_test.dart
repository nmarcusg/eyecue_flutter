import 'dart:io';
import 'dart:typed_data';

import 'package:eyecue_flutter/models/tflite_flatbuffer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('scans the metadata-enriched detection artifact', () {
    final enriched = File(
      'assets/yolov8n_int8_new_metadata.tflite',
    ).readAsBytesSync();

    final structure = scanTfliteModelStructure(Uint8List.fromList(enriched));

    // The trailing ZIP metadata payload must not disturb the graph scan.
    expect(structure, isNotNull);
    expect(structure!.tensors, isNotEmpty);
    expect(structure.inputs, isNotEmpty);
    expect(structure.outputs, isNotEmpty);
    expect(structure.tensorTypeCounts[TfliteFlatTensorType.float32], 2);
    expect(structure.tensorTypeCounts[TfliteFlatTensorType.int32], 90);
    expect(structure.tensorTypeCounts[TfliteFlatTensorType.int8], 356);
  });
}
