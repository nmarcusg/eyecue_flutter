import 'dart:convert' show ascii;
import 'dart:io' show zlib;
import 'dart:typed_data';

/// Pure-Dart PNG encoder (RGBA, 8-bit, no interlace).
///
/// Isolate-safe — no `dart:ui` dependency. Used by the forensic image dumps.
class PngEncoder {
  const PngEncoder._();

  /// Encodes [rgba] (width*height*4 bytes, R,G,B,A order) as a PNG file.
  static Uint8List encode({
    required Uint8List rgba,
    required int width,
    required int height,
  }) {
    final out = BytesBuilder();
    // PNG signature.
    out.add(const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);

    // IHDR.
    final ihdr = ByteData(13)
      ..setUint32(0, width, Endian.big)
      ..setUint32(4, height, Endian.big)
      ..setUint8(8, 8) // bit depth
      ..setUint8(9, 6) // color type: RGBA
      ..setUint8(10, 0) // compression
      ..setUint8(11, 0) // filter
      ..setUint8(12, 0); // interlace
    _chunk(out, 'IHDR', ihdr.buffer.asUint8List());

    // IDAT: one filter byte (None) per scanline + RGBA bytes, zlib-compressed.
    final stride = width * 4;
    final raw = Uint8List(height * (stride + 1));
    for (int y = 0; y < height; y++) {
      final rowStart = y * (stride + 1);
      raw[rowStart] = 0; // filter: None
      raw.setRange(rowStart + 1, rowStart + 1 + stride, rgba, y * stride);
    }
    _chunk(out, 'IDAT', zlib.encode(raw));

    _chunk(out, 'IEND', Uint8List(0));
    return out.toBytes();
  }

  static void _chunk(BytesBuilder out, String type, List<int> data) {
    final len = ByteData(4)..setUint32(0, data.length, Endian.big);
    out.add(len.buffer.asUint8List());
    final typeBytes = ascii.encode(type);
    out.add(typeBytes);
    out.add(data);
    final crc = _crc32([...typeBytes, ...data]);
    final crcBytes = ByteData(4)..setUint32(0, crc, Endian.big);
    out.add(crcBytes.buffer.asUint8List());
  }

  static int _crc32(List<int> bytes) {
    int crc = 0xFFFFFFFF;
    for (final b in bytes) {
      crc ^= b;
      for (int i = 0; i < 8; i++) {
        crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xEDB88320 : crc >> 1;
      }
    }
    return (crc ^ 0xFFFFFFFF) & 0xFFFFFFFF;
  }
}
