import 'dart:typed_data';

import 'package:eyecue_flutter/models/tensor_rotation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('rotateInputTensor — NHWC (interleaved)', () {
    // 2×2 RGB image, NHWC layout. Pixel (row, col) carries distinct values so
    // any permutation of the four pixels is detectable.
    //   (0,0)=[1,101,201]  (0,1)=[2,102,202]
    //   (1,0)=[3,103,203]  (1,1)=[4,104,204]
    Float32List nhwc2x2() => Float32List.fromList(<double>[
      1, 101, 201, //
      2, 102, 202, //
      3, 103, 203, //
      4, 104, 204, //
    ]);

    test('identity (0°) leaves the buffer unchanged', () {
      final input = nhwc2x2();
      expect(rotateInputTensor(input, 0, false, 2, 2), isTrue);
      expect(input, nhwc2x2());
    });

    test('90° CW rotates pixel order to [v10, v00, v11, v01]', () {
      final input = nhwc2x2();
      expect(rotateInputTensor(input, 90, false, 2, 2), isTrue);
      expect(
        input,
        Float32List.fromList(<double>[
          3, 103, 203, //
          1, 101, 201, //
          4, 104, 204, //
          2, 102, 202, //
        ]),
      );
    });

    test('180° rotates pixel order to [v11, v10, v01, v00]', () {
      final input = nhwc2x2();
      expect(rotateInputTensor(input, 180, false, 2, 2), isTrue);
      expect(
        input,
        Float32List.fromList(<double>[
          4, 104, 204, //
          3, 103, 203, //
          2, 102, 202, //
          1, 101, 201, //
        ]),
      );
    });

    test('270° rotates pixel order to [v01, v11, v00, v10]', () {
      final input = nhwc2x2();
      expect(rotateInputTensor(input, 270, false, 2, 2), isTrue);
      expect(
        input,
        Float32List.fromList(<double>[
          2, 102, 202, //
          4, 104, 204, //
          1, 101, 201, //
          3, 103, 203, //
        ]),
      );
    });

    test('mirror (no rotation) flips horizontally', () {
      final input = nhwc2x2();
      expect(rotateInputTensor(input, 0, true, 2, 2), isTrue);
      expect(
        input,
        Float32List.fromList(<double>[
          2, 102, 202, //
          1, 101, 201, //
          4, 104, 204, //
          3, 103, 203, //
        ]),
      );
    });

    test('four 90° rotations return the original buffer', () {
      final input = nhwc2x2();
      for (var i = 0; i < 4; i++) {
        rotateInputTensor(input, 90, false, 2, 2);
      }
      expect(input, nhwc2x2());
    });
  });

  group('rotateInputTensor — NCHW (planar)', () {
    // 2×2 RGB image, NCHW layout: three 2×2 planes (R, G, B).
    //   R plane = [1,2,3,4]   G plane = [101,102,103,104]
    //   B plane = [201,202,203,204]
    Float32List nchw2x2() => Float32List.fromList(<double>[
      1, 2, 3, 4, //
      101, 102, 103, 104, //
      201, 202, 203, 204, //
    ]);

    test('90° CW rotates each plane independently', () {
      final input = nchw2x2();
      expect(rotateInputTensor(input, 90, false, 2, 2, isNCHW: true), isTrue);
      expect(
        input,
        Float32List.fromList(<double>[
          3, 1, 4, 2, //
          103, 101, 104, 102, //
          203, 201, 204, 202, //
        ]),
      );
    });

    test('180° rotates each plane to [v11, v10, v01, v00]', () {
      final input = nchw2x2();
      expect(rotateInputTensor(input, 180, false, 2, 2, isNCHW: true), isTrue);
      expect(
        input,
        Float32List.fromList(<double>[
          4, 3, 2, 1, //
          104, 103, 102, 101, //
          204, 203, 202, 201, //
        ]),
      );
    });

    test('NCHW result matches NHWC result under 90° for the same image', () {
      // The same logical image encoded in both layouts must produce the same
      // logical upright image after rotation (same pixel at each (row,col)).
      final nhwc = Float32List.fromList(<double>[
        1, 101, 201, //
        2, 102, 202, //
        3, 103, 203, //
        4, 104, 204, //
      ]);
      final nchw = Float32List.fromList(<double>[
        1, 2, 3, 4, //
        101, 102, 103, 104, //
        201, 202, 203, 204, //
      ]);
      rotateInputTensor(nhwc, 90, false, 2, 2);
      rotateInputTensor(nchw, 90, false, 2, 2, isNCHW: true);

      // Read the NHWC result back as pixels and compare with the NCHW planes.
      final List<List<double>> nhwcPixels = [];
      for (int p = 0; p < 4; p++) {
        nhwcPixels.add([nhwc[p * 3], nhwc[p * 3 + 1], nhwc[p * 3 + 2]]);
      }
      for (int c = 0; c < 3; c++) {
        final plane = nchw.sublist(c * 4, c * 4 + 4);
        final List<double> planePixels = [];
        for (int i = 0; i < 4; i++) {
          planePixels.add(plane[i]);
        }
        for (int p = 0; p < 4; p++) {
          expect(planePixels[p], nhwcPixels[p][c]);
        }
      }
    });

    test('four 90° rotations return the original buffer (NCHW)', () {
      final input = nchw2x2();
      for (var i = 0; i < 4; i++) {
        rotateInputTensor(input, 90, false, 2, 2, isNCHW: true);
      }
      expect(input, nchw2x2());
    });
  });

  group('rotateInputTensor — guards', () {
    test(
      'returns false and leaves buffer intact for non-square model dims',
      () {
        final input = Float32List(12);
        input[0] = 42;
        expect(rotateInputTensor(input, 90, false, 2, 3), isFalse);
        expect(input[0], 42);
      },
    );

    test('returns false for null input', () {
      expect(rotateInputTensor(null, 90, false, 2, 2), isFalse);
    });

    test('returns false when the buffer length does not match H*W*3', () {
      final input = Float32List(11);
      expect(rotateInputTensor(input, 90, false, 2, 2), isFalse);
    });

    test('works on Int8List buffers (quantized input)', () {
      final input = Int8List.fromList(<int>[
        1, 11, 21, //
        2, 12, 22, //
        3, 13, 23, //
        4, 14, 24, //
      ]);
      expect(rotateInputTensor(input, 90, false, 2, 2), isTrue);
      expect(
        input,
        Int8List.fromList(<int>[
          3, 13, 23, //
          1, 11, 21, //
          4, 14, 24, //
          2, 12, 22, //
        ]),
      );
    });
  });
}
