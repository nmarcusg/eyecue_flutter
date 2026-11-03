import 'dart:ui' as ui;

import 'package:eyecue_flutter/models/detection.dart';
import 'package:eyecue_flutter/widgets/bounding_box_painter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'long labels stay inside the viewport at a thin left-edge box',
    () async {
      const viewport = ui.Size(120, 80);
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder)..translate(10, 10);
      final painter = BoundingBoxPainter(
        imageSize: viewport,
        detections: [
          Detection(
            classId: 0,
            label: 'very-long-detection-label-' * 8,
            confidence: 0.9,
            box: const ui.Rect.fromLTWH(0, 0.5, 0.01, 0.25),
          ),
        ],
      );

      painter.paint(canvas, viewport);
      final picture = recorder.endRecording();
      final image = await picture.toImage(140, 100);
      final bytes = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!;

      // The translated viewport is [10, 130]×[10, 90]. The box starts below
      // this label band, so outside pixels here can only be clipped label ink.
      for (var y = 30; y < 48; y++) {
        for (var x = 0; x < 10; x++) {
          expect(bytes.getUint8((y * 140 + x) * 4 + 3), 0);
        }
        for (var x = 130; x < 140; x++) {
          expect(bytes.getUint8((y * 140 + x) * 4 + 3), 0);
        }
      }
      expect(bytes.getUint8((40 * 140 + 20) * 4 + 3), greaterThan(0));
      var whiteTextPixels = 0;
      for (var y = 20; y < 48; y++) {
        for (var x = 10; x < 130; x++) {
          final offset = (y * 140 + x) * 4;
          if (bytes.getUint8(offset) > 240 &&
              bytes.getUint8(offset + 1) > 240 &&
              bytes.getUint8(offset + 2) > 240 &&
              bytes.getUint8(offset + 3) > 0) {
            whiteTextPixels++;
          }
        }
      }
      expect(whiteTextPixels, greaterThan(0));
      image.dispose();
      picture.dispose();
    },
  );
}
