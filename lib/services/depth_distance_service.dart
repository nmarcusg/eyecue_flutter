import 'dart:typed_data';
import 'dart:ui' show Rect;

import '../models/box_transform.dart';
import '../models/detection_info.dart';
import '../models/model_config.dart';

/// Pure depth→distance helpers shared by the estimator, the detection screen
/// and the tests. Nothing here touches the plugin or any platform channel.
///
/// shortcut: the box-centre median of the inset box is an uncalibrated
/// heuristic — lens calibration and per-device intrinsics are out of scope.
abstract final class DepthDistanceService {
  /// Fraction trimmed from every side of a detection box before sampling.
  static const double insetFraction = 0.12;

  /// Minimum number of usable depth pixels required for an estimate.
  static const int minSamples = 8;

  static const double minValidMeters = 0.1;
  static const double maxValidMeters = 80;

  /// Shrinks [box] by [fraction] of its own size on every side, clamped to a
  /// valid rect. A degenerate box yields a degenerate (empty) rect.
  static Rect insetBox(Rect box, [double fraction = insetFraction]) {
    if (!box.width.isFinite || !box.height.isFinite) return Rect.zero;
    final dx = box.width * fraction;
    final dy = box.height * fraction;
    final left = box.left + dx;
    final top = box.top + dy;
    final right = box.right - dx;
    final bottom = box.bottom - dy;
    if (right <= left || bottom <= top) return Rect.zero;
    return Rect.fromLTRB(left, top, right, bottom);
  }

  /// Maps an upright normalized box into SENSOR space for [rotationDegrees].
  ///
  /// The streamed JPEG (and therefore the depth map) is in sensor orientation,
  /// while detection boxes are normalized to the upright frame.
  static Rect sensorSpaceBox(Rect uprightBox, int rotationDegrees) =>
      BoxTransform.invertRect(uprightBox, rotationDegrees);

  /// Median depth in metres inside [box] (normalized to the map), or `null`
  /// when fewer than [minSamples] valid pixels fall inside it.
  static double? medianDepthInBox({
    required Float32List values,
    required int width,
    required int height,
    required Rect box,
  }) {
    if (width <= 0 || height <= 0 || values.length < width * height) {
      return null;
    }
    if (box.width <= 0 || box.height <= 0) return null;
    final left = (box.left * width).floor().clamp(0, width - 1);
    final right = (box.right * width).ceil().clamp(left + 1, width);
    final top = (box.top * height).floor().clamp(0, height - 1);
    final bottom = (box.bottom * height).ceil().clamp(top + 1, height);

    final samples = <double>[];
    for (var y = top; y < bottom; y++) {
      final row = y * width;
      for (var x = left; x < right; x++) {
        final value = values[row + x];
        if (!value.isFinite) continue;
        if (value < minValidMeters || value > maxValidMeters) continue;
        samples.add(value);
      }
    }
    if (samples.length < minSamples) return null;
    samples.sort();
    final mid = samples.length ~/ 2;
    return samples.length.isOdd
        ? samples[mid]
        : (samples[mid - 1] + samples[mid]) / 2;
  }

  /// Distance band used by alert policy, ranking and speech.
  static ProximityBand bandForMeters(double meters) {
    if (!meters.isFinite) return ProximityBand.far;
    if (meters <= 1.5) return ProximityBand.near;
    if (meters <= 4.0) return ProximityBand.medium;
    return ProximityBand.far;
  }

  /// Metric phrase ("about 3.5 m"): half-metre rounding under 10 m, whole
  /// metres above.
  static String formatMeters(double meters) {
    final rounded = meters < 10 ? (meters * 2).round() / 2 : meters.round();
    final text = rounded == rounded.roundToDouble()
        ? rounded.toStringAsFixed(rounded < 10 ? 1 : 0)
        : rounded.toStringAsFixed(1);
    return 'about $text m';
  }

  /// Whether a depth frame stamped [timestampMs] is stale at [nowMs].
  static bool isStale({
    required int timestampMs,
    required int nowMs,
    int maxAgeMs = EyeCueModelConfig.depthStaleAfterMs,
  }) => nowMs - timestampMs > maxAgeMs;
}

/// Exponential moving average of metric distance, keyed by tracker identity.
class DepthSmoother {
  DepthSmoother({this.alpha = 0.4});

  final double alpha;
  final Map<int, double> _byTrack = {};

  /// Smoothed metres for [trackId]; the first sample is returned unchanged.
  double smooth(int trackId, double meters) {
    final previous = _byTrack[trackId];
    final next = previous == null
        ? meters
        : previous + alpha * (meters - previous);
    _byTrack[trackId] = next;
    return next;
  }

  /// Raw value kept for the last sample, or `null` if the track is unknown.
  double? rawFor(int trackId) => _byTrack[trackId];

  void reset() => _byTrack.clear();
}
