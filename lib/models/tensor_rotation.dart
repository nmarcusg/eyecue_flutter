import 'dart:typed_data';

/// Rotates (and optionally X-mirrors, for the front camera) a square RGB image
/// tensor in place so the model sees the scene UPRIGHT.
///
/// The input is always square (e.g. 640×640), so 90°/180°/270° are lossless
/// transposes (no resampling). Mirroring is applied in the upright space,
/// matching the front-camera preview. This is the ONLY code that changes what
/// pixels the model sees; converter/parser/NMS are untouched.
///
/// Supports both tensor layouts:
/// * **NHWC** (interleaved `[R, G, B, R, G, B, ...]` — `isNCHW: false`), and
/// * **NCHW** (planar `[R plane, G plane, B plane]` — `isNCHW: true`).
///
/// Returns `true` when the buffer was rotated/mirrored, `false` when skipped
/// (null input, non-square model dims, or length mismatch).
bool rotateInputTensor(
  dynamic input,
  int degrees,
  bool mirror,
  int modelH,
  int modelW, {
  bool isNCHW = false,
}) {
  if (input == null) return false;
  if (modelH != modelW || modelH <= 0) return false;
  final int hw = modelH * modelW;
  final int n = hw * 3;
  if (n <= 0 || _inputLen(input) != n) return false;

  final dynamic tmp = _cloneInput(input);
  final int w = modelW;
  final int r = ((degrees % 360) + 360) % 360;
  for (int row = 0; row < modelH; row++) {
    for (int col = 0; col < w; col++) {
      int dr = row;
      int dc = col;
      switch (r) {
        case 90:
          dr = col;
          dc = w - 1 - row;
          break;
        case 180:
          dr = modelH - 1 - row;
          dc = w - 1 - col;
          break;
        case 270:
          dr = modelH - 1 - col;
          dc = row;
          break;
        default:
          break;
      }
      if (mirror) dc = w - 1 - dc;

      if (isNCHW) {
        // NCHW layout: [C, H, W] — each channel is its own plane.
        for (int c = 0; c < 3; c++) {
          input[c * hw + dr * w + dc] = tmp[c * hw + row * w + col];
        }
      } else {
        // NHWC layout: interleaved [R, G, B, R, G, B, ...].
        final int si = (row * w + col) * 3;
        final int di = (dr * w + dc) * 3;
        input[di] = tmp[si];
        input[di + 1] = tmp[si + 1];
        input[di + 2] = tmp[si + 2];
      }
    }
  }
  return true;
}

int _inputLen(dynamic input) {
  if (input is Float32List) return input.length;
  if (input is Float64List) return input.length;
  if (input is Int8List) return input.length;
  if (input is Uint8List) return input.length;
  if (input is Int16List) return input.length;
  return 0;
}

dynamic _cloneInput(dynamic input) {
  if (input is Float32List) return Float32List.fromList(input);
  if (input is Float64List) return Float64List.fromList(input);
  if (input is Int8List) return Int8List.fromList(input);
  if (input is Uint8List) return Uint8List.fromList(input);
  if (input is Int16List) return Int16List.fromList(input);
  return input;
}
