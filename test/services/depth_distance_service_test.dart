import 'dart:typed_data';
import 'dart:ui';

import 'package:eyecue_flutter/models/box_transform.dart';
import 'package:eyecue_flutter/models/detection_info.dart';
import 'package:eyecue_flutter/services/depth_distance_service.dart';
import 'package:flutter_test/flutter_test.dart';

Float32List _uniformMap({
  required int width,
  required int height,
  double value = 2.0,
}) => Float32List(width * height)..fillRange(0, width * height, value);

void main() {
  group('insetBox', () {
    test('trims 12 percent of each side', () {
      final inset = DepthDistanceService.insetBox(
        const Rect.fromLTWH(0.2, 0.2, 0.4, 0.4),
      );
      expect(inset.left, closeTo(0.248, 1e-9));
      expect(inset.top, closeTo(0.248, 1e-9));
      expect(inset.width, closeTo(0.304, 1e-9));
      expect(inset.height, closeTo(0.304, 1e-9));
    });

    test('degenerate box yields an empty rect', () {
      expect(
        DepthDistanceService.insetBox(const Rect.fromLTWH(0.5, 0.5, 0, 0)),
        Rect.zero,
      );
    });
  });

  group('medianDepthInBox', () {
    test('returns the median and ignores invalid samples', () {
      const width = 10;
      const height = 10;
      final values = _uniformMap(width: width, height: height, value: 3.0);
      // Fill one included row with noise: invalid lows/highs and NaNs.
      for (var x = 0; x < width; x++) {
        values[width + x] = switch (x % 3) {
          0 => 0.0,
          1 => 200.0,
          _ => double.nan,
        };
      }
      final median = DepthDistanceService.medianDepthInBox(
        values: values,
        width: width,
        height: height,
        box: const Rect.fromLTWH(0, 0, 1, 1),
      );
      expect(median, 3.0);
    });

    test('needs at least 8 samples', () {
      final values = _uniformMap(width: 10, height: 10);
      final tooSmall = DepthDistanceService.medianDepthInBox(
        values: values,
        width: 10,
        height: 10,
        box: const Rect.fromLTWH(0, 0, 0.2, 0.2),
      );
      expect(tooSmall, isNull);
    });

    test('rejects all-invalid regions', () {
      final values = Float32List(100)..fillRange(0, 100, 0.0);
      expect(
        DepthDistanceService.medianDepthInBox(
          values: values,
          width: 10,
          height: 10,
          box: const Rect.fromLTWH(0, 0, 1, 1),
        ),
        isNull,
      );
    });

    test('even sample counts average the two middle values', () {
      final values = Float32List(8)..fillRange(0, 8, 1.0);
      values[0] = 1.0;
      values[1] = 2.0;
      values[2] = 1.0;
      values[3] = 2.0;
      values[4] = 1.0;
      values[5] = 2.0;
      values[6] = 1.0;
      values[7] = 2.0;
      expect(
        DepthDistanceService.medianDepthInBox(
          values: values,
          width: 4,
          height: 2,
          box: const Rect.fromLTWH(0, 0, 1, 1),
        ),
        1.5,
      );
    });
  });

  group('rotation mapping', () {
    const box = Rect.fromLTWH(0.1, 0.2, 0.3, 0.4);

    for (final degrees in [0, 90, 180, 270]) {
      test('upright→sensor round-trips at $degrees degrees', () {
        final sensor = DepthDistanceService.sensorSpaceBox(box, degrees);
        final back = BoxTransform.rotateRect(sensor, degrees);
        expect(back.left, closeTo(box.left, 1e-9));
        expect(back.top, closeTo(box.top, 1e-9));
        expect(back.width, closeTo(box.width, 1e-9));
        expect(back.height, closeTo(box.height, 1e-9));
      });
    }

    test('a quarter turn transposes the upright dimensions', () {
      expect(BoxTransform.uprightDims(w: 640, h: 480, rotationDegrees: 90), (
        w: 480,
        h: 640,
      ));
      expect(BoxTransform.uprightDims(w: 640, h: 480, rotationDegrees: 180), (
        w: 640,
        h: 480,
      ));
    });
  });

  group('bands and staleness', () {
    test('meters map onto the existing band vocabulary', () {
      expect(DepthDistanceService.bandForMeters(1.0), ProximityBand.near);
      expect(DepthDistanceService.bandForMeters(1.5), ProximityBand.near);
      expect(DepthDistanceService.bandForMeters(2.0), ProximityBand.medium);
      expect(DepthDistanceService.bandForMeters(4.0), ProximityBand.medium);
      expect(DepthDistanceService.bandForMeters(4.1), ProximityBand.far);
      expect(DepthDistanceService.bandForMeters(double.nan), ProximityBand.far);
    });

    test('frames older than 1000 ms are stale', () {
      expect(
        DepthDistanceService.isStale(timestampMs: 0, nowMs: 1000),
        isFalse,
      );
      expect(DepthDistanceService.isStale(timestampMs: 0, nowMs: 1001), isTrue);
    });

    test('metric phrase uses half-metre rounding under 10 m', () {
      expect(DepthDistanceService.formatMeters(3.26), 'about 3.5 m');
      expect(DepthDistanceService.formatMeters(3.0), 'about 3.0 m');
      expect(DepthDistanceService.formatMeters(12.4), 'about 12 m');
    });
  });

  group('DepthSmoother', () {
    test('applies EMA per track and keeps tracks independent', () {
      final smoother = DepthSmoother();
      expect(smoother.smooth(1, 4.0), 4.0);
      expect(smoother.smooth(1, 6.0), closeTo(4.8, 1e-9));
      expect(smoother.smooth(2, 2.0), 2.0);
      expect(smoother.smooth(1, 6.0), closeTo(5.28, 1e-9));
    });

    test('reset clears every track', () {
      final smoother = DepthSmoother();
      smoother.smooth(7, 5.0);
      smoother.reset();
      expect(smoother.rawFor(7), isNull);
      expect(smoother.smooth(7, 1.0), 1.0);
    });
  });
}
