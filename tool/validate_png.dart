// Development utility: validates the pure-Dart PNG encoder.
//
// Run: dart run tool/validate_png.dart
// Writes build/validate_test.png, then you can verify with any PNG tool
// (e.g. `python3 -c "from PIL import Image; Image.open('build/validate_test.png').show()"`).
import 'dart:io';
import 'dart:typed_data';

import 'package:eyecue_flutter/models/png_encoder.dart';

void main() {
  // 4x2 test image: red, green, blue, white | black, gray, yellow, cyan
  final w = 4, h = 2;
  final rgba = Uint8List(w * h * 4);
  void setPx(int x, int y, int r, int g, int b) {
    final o = (y * w + x) * 4;
    rgba[o] = r;
    rgba[o + 1] = g;
    rgba[o + 2] = b;
    rgba[o + 3] = 255;
  }

  setPx(0, 0, 255, 0, 0);
  setPx(1, 0, 0, 255, 0);
  setPx(2, 0, 0, 0, 255);
  setPx(3, 0, 255, 255, 255);
  setPx(0, 1, 0, 0, 0);
  setPx(1, 1, 128, 128, 128);
  setPx(2, 1, 255, 255, 0);
  setPx(3, 1, 0, 255, 255);

  final png = PngEncoder.encode(rgba: rgba, width: w, height: h);

  // 1. Signature check.
  const sig = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
  final okSig =
      png.length >= 8 &&
      List.generate(8, (i) => png[i]).join(',') == sig.join(',');
  stdout.writeln('signature: ${okSig ? "OK" : "FAIL"}');

  // 2. Chunk walk: length + type + data + crc verification.
  var pos = 8;
  var ok = true;
  var sawIHDR = false, sawIDAT = false, sawIEND = false;
  final bd = ByteData.sublistView(png);
  while (pos + 8 <= png.length) {
    final len = bd.getUint32(pos, Endian.big);
    final type = String.fromCharCodes(png.sublist(pos + 4, pos + 8));
    final dataStart = pos + 8;
    final dataEnd = dataStart + len;
    final crcStored = bd.getUint32(dataEnd, Endian.big);
    final crcCalc = _crc32(png.sublist(pos + 4, dataEnd));
    if (crcStored != crcCalc) {
      stdout.writeln('chunk $type CRC FAIL (stored=$crcStored calc=$crcCalc)');
      ok = false;
    }
    if (type == 'IHDR') sawIHDR = true;
    if (type == 'IDAT') sawIDAT = true;
    if (type == 'IEND') sawIEND = true;
    stdout.writeln(
      'chunk $type len=$len crc=${crcStored == crcCalc ? "OK" : "FAIL"}',
    );
    pos = dataEnd + 4;
  }
  if (!(sawIHDR && sawIDAT && sawIEND)) ok = false;
  stdout.writeln(
    'chunks (IHDR/IDAT/IEND): ${sawIHDR && sawIDAT && sawIEND ? "OK" : "FAIL"}',
  );

  // 3. Size sanity: expected IHDR dims.
  final wRead = ByteData.sublistView(png).getUint32(16, Endian.big);
  final hRead = ByteData.sublistView(png).getUint32(20, Endian.big);
  stdout.writeln('dims: ${wRead}x$hRead (expect ${w}x$h)');

  File('build/validate_test.png')
    ..createSync(recursive: true)
    ..writeAsBytesSync(png);
  stdout.writeln('wrote build/validate_test.png (${png.length} bytes)');

  if (ok && okSig) {
    stdout.writeln('PNG VALIDATION PASSED');
  } else {
    stdout.writeln('PNG VALIDATION FAILED');
    exitCode = 1;
  }
}

int _crc32(List<int> bytes) {
  int crc = 0xFFFFFFFF;
  for (final b in bytes) {
    crc ^= b;
    for (int i = 0; i < 8; i++) {
      crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xEDB88320 : crc >> 1;
    }
  }
  return (crc ^ 0xFFFFFFFF) & 0xFFFFFFFF;
}
