// Development utility: validates the pure-Dart TFLite flatbuffer scanner
// (and float16 conversion) against the bundled model files.
//
// Run: dart run tool/validate_flatbuffer.dart
//
// Expected output for assets/yolov8n.tflite:
//   FLOAT32: 324, INT32: 23, INT8: 62  (409 tensors)
// Expected output for assets/yolov8n_int8.tflite:
//   FLOAT32: 324, INT32: 25, INT8: 62  (411 tensors)
// Expected output for assets/yolov8n_int8_new.tflite:
//   FLOAT32: 2, INT32: 90, INT8: 356  (448 tensors)
import 'dart:io';
import 'dart:typed_data';

import 'package:eyecue_flutter/models/tflite_flatbuffer.dart';

void main() {
  var failed = false;

  final cases = <String, Map<int, int>>{
    'assets/yolov8n.tflite': {
      TfliteFlatTensorType.float32: 324,
      TfliteFlatTensorType.int32: 23,
      TfliteFlatTensorType.int8: 62,
    },
    'assets/yolov8n_int8.tflite': {
      TfliteFlatTensorType.float32: 324,
      TfliteFlatTensorType.int32: 25,
      TfliteFlatTensorType.int8: 62,
    },
    'assets/yolov8n_int8_new.tflite': {
      TfliteFlatTensorType.float32: 2,
      TfliteFlatTensorType.int32: 90,
      TfliteFlatTensorType.int8: 356,
    },
  };

  for (final entry in cases.entries) {
    final bytes = File(entry.key).readAsBytesSync();
    final counts = scanTfliteTensorTypeCounts(bytes);
    stdout.writeln('$entry.key -> $counts');
    if (counts == null) {
      stdout.writeln('  FAIL: scan returned null');
      failed = true;
      continue;
    }
    final ok =
        counts.length == entry.value.length &&
        counts.entries.every((e) => entry.value[e.key] == e.value);
    if (!ok) {
      stdout.writeln('  FAIL: expected ${entry.value}');
      failed = true;
    } else {
      stdout.writeln('  OK');
    }
  }

  // float16 roundtrip sanity checks.
  final values = Float32List.fromList([
    0.0,
    -0.0,
    1.0,
    -1.0,
    0.5,
    65504.0,
    0.00006103515625, // 2^-14 (max subnormal)
    0.000000059604644775390625, // 2^-24 (min subnormal)
    3.4028234663852886e38, // overflow -> inf
    double.infinity, double.nan,
  ]);
  final roundtrip = float16BytesToFloat32List(
    float32ListToFloat16Bytes(values),
  );
  stdout.writeln('\nfloat16 roundtrip:');
  for (var i = 0; i < values.length; i++) {
    final orig = values[i];
    final back = roundtrip[i];
    // IEEE half cannot represent float32 max — overflow to ±Inf is correct.
    final overflowToInf =
        (orig == 3.4028234663852886e38) && (back == double.infinity);
    final match =
        (orig == back) ||
        (orig.isNaN && back.isNaN) ||
        (orig == double.infinity && back == double.infinity) ||
        (orig == 0.0 && back == 0.0) || // handles ±0
        overflowToInf;
    stdout.writeln('  $orig -> $back ${match ? 'OK' : 'FAIL'}');
    if (!match) failed = true;
  }

  if (failed) {
    stdout.writeln('\nVALIDATION FAILED');
    exitCode = 1;
  } else {
    stdout.writeln('\nALL VALIDATIONS PASSED');
  }
}
