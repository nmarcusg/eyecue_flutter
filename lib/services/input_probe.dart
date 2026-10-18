import 'dart:math' as math;
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart' show debugPrint;

import '../models/model_metadata.dart';

/// ===========================================================================
/// TEMPORARY INPUT-PIPELINE FORENSIC PROBE — DO NOT SHIP.
///
/// Logs are prefixed `[InputProbe]`. It ONLY reads buffers/images and logs;
/// it never changes inference behavior.
///
/// Coverage (per the investigation brief):
///   phaseA – CameraImage plane geometry + format inference (main isolate)
///   phaseB – per-channel R/G/B stats after YUV→RGB (inference isolate)
///   phaseC – resize validation
///   phaseD – normalization validation
///   phaseE – input tensor validation immediately before interpreter.run()
///   phaseF – known-image cross-check (test-image mode)
///   phaseG – top-20 confidence inspection
///   phaseH – confidence distribution (max/mean/median/p95/p99/counts)
///
/// To remove: delete this file, drop the `InputProbe.*` calls and the
/// `useTestImage` flag in the service/screen, and remove the import.
/// ===========================================================================
class InputProbe {
  /// Master switch: flip to false (or delete the file) to silence all probes.
  /// NOTE: replaced by the file-based [ForensicLog] — disabled.
  static const bool enabled = false;

  // Phase A runs on the MAIN isolate (where CameraImage is available).
  static bool _phaseADone = false;

  // Phases B–H run on the INFERENCE isolate.
  static bool _frame1Done = false;

  static bool get shouldRunFrame1Probes => enabled && !_frame1Done;

  static void markFrame1Done() => _frame1Done = true;

  // -------------------------------------------------------------------------
  // PHASE A — CameraImage validation (main isolate, once)
  // -------------------------------------------------------------------------
  static void phaseA(CameraImage image) {
    if (!enabled || _phaseADone) return;
    _phaseADone = true;

    debugPrint('━━━ [InputProbe A] CAMERA IMAGE ━━━');
    debugPrint(
      '[InputProbe A] formatRaw=${image.format.raw} '
      'formatGroup=${image.format.group}',
    );
    debugPrint(
      '[InputProbe A] width=${image.width} height=${image.height} '
      'planes=${image.planes.length}',
    );
    for (int i = 0; i < image.planes.length; i++) {
      final p = image.planes[i];
      debugPrint(
        '[InputProbe A] plane[$i] bytesLen=${p.bytes.length} '
        'rowStride(bytesPerRow)=${p.bytesPerRow} '
        'pixelStride(bytesPerPixel)=${p.bytesPerPixel} '
        'planeW=${p.width} planeH=${p.height}',
      );
    }
    debugPrint('[InputProbe A] inferredFormat=${_inferFormat(image)}');
    debugPrint('━━━ [InputProbe A] END ━━━');
  }

  static String _inferFormat(CameraImage image) {
    final n = image.planes.length;
    if (n == 3) {
      final p1 = image.planes[1].bytesPerPixel ?? 1;
      final p2 = image.planes[2].bytesPerPixel ?? 1;
      if (p1 == 1 && p2 == 1) return 'I420 (3 planar planes, U/V 1-byte)';
      if (p1 == 2 || p2 == 2) return 'YUV_420_888 semi-planar (NV21/NV12-like)';
      return 'YUV_420_888 (3 planes, unknown layout)';
    }
    if (n == 2) return 'YUV_420_888 semi-planar (NV21 or NV12, 2 planes)';
    return 'UNKNOWN ($n planes)';
  }

  // -------------------------------------------------------------------------
  // PHASE B — per-channel R/G/B stats after YUV→RGB (inference isolate)
  // -------------------------------------------------------------------------
  static void phaseB(dynamic input, ModelMetadata m, bool isNCHW, int frame) {
    final n = _len(input);
    if (n == 0) return;
    final stats = List.generate(3, (_) => _Stats());
    for (int i = 0; i < n; i++) {
      final v = _at(input, i);
      int c;
      if (isNCHW) {
        c = i ~/ (n ~/ 3); // planar: block 0=R, 1=G, 2=B
      } else {
        c = i % 3; // interleaved NHWC
      }
      if (c >= 0 && c < 3) stats[c].add(v);
    }

    debugPrint(
      '━━━ [InputProbe B] RGB CHANNEL STATS (frame $frame, '
      'layout=${isNCHW ? "NCHW" : "NHWC"}) ━━━',
    );
    const names = ['R', 'G', 'B'];
    for (int c = 0; c < 3; c++) {
      debugPrint(
        '[InputProbe B] $names[c] min=${stats[c].min.toStringAsFixed(4)} '
        'max=${stats[c].max.toStringAsFixed(4)} '
        'mean=${stats[c].mean.toStringAsFixed(4)} '
        'std=${stats[c].std.toStringAsFixed(4)}',
      );
    }
    // Channel health checks.
    final means = stats.map((s) => s.mean).toList();
    final maxMean = means.reduce(math.max);
    final minMean = means.reduce(math.min);
    if ((maxMean - minMean).abs() < 1e-3) {
      debugPrint(
        '[InputProbe B] ⚠️ ALL CHANNELS NEARLY IDENTICAL '
        '(mean range ${(maxMean - minMean).toStringAsExponential(1)}) — '
        'image has no color information',
      );
    }
    if (minMean < 1e-4 && maxMean < 1e-2) {
      debugPrint('[InputProbe B] ⚠️ ALL CHANNELS ~0 — image is near-black');
    }
    if (maxMean > 0.99) {
      debugPrint(
        '[InputProbe B] ⚠️ ALL CHANNELS ~1 — image is near-white/saturated',
      );
    }
    debugPrint('━━━ [InputProbe B] END ━━━');
  }

  // -------------------------------------------------------------------------
  // PHASE C — resize validation
  // -------------------------------------------------------------------------
  static void phaseC({
    required int srcWidth,
    required int srcHeight,
    required int dstHeight,
    required int dstWidth,
    required dynamic input,
    required ModelMetadata m,
  }) {
    final n = _len(input);
    final _Stats s = _Stats();
    for (int i = 0; i < n; i++) {
      s.add(_at(input, i));
    }
    debugPrint('━━━ [InputProbe C] RESIZE ━━━');
    debugPrint(
      '[InputProbe C] src=${srcWidth}x$srcHeight → '
      'dst=${dstWidth}x$dstHeight expectedTensor=${m.inputShape.join("x")}',
    );
    debugPrint(
      '[InputProbe C] resizedRGB min=${s.min.toStringAsFixed(4)} '
      'max=${s.max.toStringAsFixed(4)} mean=${s.mean.toStringAsFixed(4)}',
    );
    debugPrint('━━━ [InputProbe C] END ━━━');
  }

  // -------------------------------------------------------------------------
  // PHASE D — normalization validation
  // -------------------------------------------------------------------------
  static void phaseD(dynamic input, ModelMetadata m) {
    final n = _len(input);
    final _Stats s = _Stats();
    int neg = 0;
    int aboveOne = 0;
    for (int i = 0; i < n; i++) {
      final v = _at(input, i);
      s.add(v);
      if (v < 0) neg++;
      if (v > 1.0) aboveOne++;
    }
    debugPrint('━━━ [InputProbe D] NORMALIZATION ━━━');
    debugPrint(
      '[InputProbe D] min=${s.min.toStringAsFixed(6)} '
      'max=${s.max.toStringAsFixed(6)} mean=${s.mean.toStringAsFixed(4)} '
      'std=${s.std.toStringAsFixed(4)}',
    );
    debugPrint('[InputProbe D] negatives=$neg (>1)=$aboveOne of $n');
    if (s.max == 0) {
      debugPrint('[InputProbe D] ⚠️ ALL ZERO');
    } else if ((s.min - s.max).abs() < 1e-9) {
      debugPrint('[InputProbe D] ⚠️ ALL ONE (constant)');
    }
    if (s.max > 1.0) {
      debugPrint('[InputProbe D] ⚠️ VALUES > 1 — normalization is NOT [0,1]');
    }
    if (s.mean < 0.2 || s.mean > 0.8) {
      debugPrint(
        '[InputProbe D] ⚠️ mean=${s.mean.toStringAsFixed(3)} outside '
        'expected ~0.3–0.7 (typical natural image)',
      );
    }
    debugPrint('━━━ [InputProbe D] END ━━━');
  }

  // -------------------------------------------------------------------------
  // PHASE E — input tensor immediately before interpreter.run()
  // -------------------------------------------------------------------------
  static void phaseE(dynamic input, ModelMetadata m, int frame) {
    final n = _len(input);
    final expected = ModelMetadata.elementCount(m.inputShape);
    final _Stats s = _Stats();
    final first = <double>[];
    final last = <double>[];
    final randomIdx = _randomIndices(n, 32).toSet();
    final randomVals = <double>[];
    final seen = <int>[];
    for (int i = 0; i < n; i++) {
      final v = _at(input, i);
      s.add(v);
      if (i < 32) first.add(v);
      if (i >= n - 32) last.add(v);
      if (randomIdx.contains(i)) {
        randomVals.add(v);
        seen.add(i);
      }
    }

    debugPrint(
      '━━━ [InputProbe E] INPUT TENSOR BEFORE run() (frame $frame) ━━━',
    );
    debugPrint(
      '[InputProbe E] dtype=${input.runtimeType} len=$n expected=$expected',
    );
    debugPrint(
      '[InputProbe E] min=${s.min.toStringAsFixed(6)} '
      'max=${s.max.toStringAsFixed(6)} mean=${s.mean.toStringAsFixed(4)}',
    );
    debugPrint('[InputProbe E] first32=${_fmt(first)}');
    debugPrint('[InputProbe E] last32=${_fmt(last)}');
    debugPrint(
      '[InputProbe E] sample32=${_fmt(randomVals)} (indices=${seen.take(8).join(",")}…)',
    );
    if (m.requiresInputQuantization) {
      debugPrint(
        '[InputProbe E] inputScale=${m.inputScale} '
        'inputZeroPoint=${m.inputZeroPoint}',
      );
      final ints = <int>{};
      for (int i = 0; i < n; i++) {
        ints.add(_at(input, i).round());
      }
      var lo = 0;
      var hi = 0;
      for (final v in ints) {
        if (v < lo) lo = v;
        if (v > hi) hi = v;
      }
      debugPrint(
        '[InputProbe E] integerRangeUsed=[$lo, $hi] distinct=${ints.length}',
      );
    }
    debugPrint('━━━ [InputProbe E] END ━━━');
  }

  // -------------------------------------------------------------------------
  // PHASE F — known-image cross-check (isolate, after test-image inference)
  // -------------------------------------------------------------------------
  static void phaseFReport(
    List output,
    ModelMetadata m,
    List<String> labels, {
    required double latencyMs,
    required int detectionCount,
  }) {
    final top = _topK(output, m, labels, 20);
    debugPrint('━━━ [InputProbe F] KNOWN-IMAGE RESULT ━━━');
    debugPrint(
      '[InputProbe F] latency=${latencyMs.toStringAsFixed(1)}ms '
      'detections=$detectionCount (threshold 0.5)',
    );
    for (final e in top) {
      debugPrint(
        '[InputProbe F] anchor ${e.anchor}  ${e.label}  '
        '${e.score.toStringAsFixed(4)}',
      );
    }
    debugPrint('━━━ [InputProbe F] END ━━━');
  }

  // -------------------------------------------------------------------------
  // PHASE G — top-k output inspection
  // -------------------------------------------------------------------------
  static void phaseG(
    List output,
    ModelMetadata m,
    List<String> labels,
    int frame,
  ) {
    final top = _topK(output, m, labels, 20);
    debugPrint('━━━ [InputProbe G] TOP-20 CONFIDENCES (frame $frame) ━━━');
    for (final e in top) {
      debugPrint(
        '[InputProbe G] anchor ${e.anchor}  ${e.label}  '
        '${e.score.toStringAsFixed(4)}',
      );
    }
    debugPrint('━━━ [InputProbe G] END ━━━');
  }

  // -------------------------------------------------------------------------
  // PHASE H — confidence distribution (per-anchor max class score)
  // -------------------------------------------------------------------------
  static void phaseH(List output, ModelMetadata m, int frame) {
    final numBoxes = m.anchors;
    final numClasses = m.classes;
    final dequant = m.requiresOutputDequantization;

    // Per-anchor max class score distribution.
    final maxes = Float64List(numBoxes);
    double maxV = -double.infinity;
    double sum = 0;
    for (int a = 0; a < numBoxes; a++) {
      double best = -double.infinity;
      for (int c = 0; c < numClasses; c++) {
        final v = _val(output, (4 + c) * numBoxes + a, dequant, m);
        if (v > best) best = v;
      }
      maxes[a] = best;
      if (best > maxV) maxV = best;
      sum += best;
    }
    final mean = sum / numBoxes;
    final sorted = List<double>.of(maxes)..sort();
    final median = sorted[numBoxes ~/ 2];
    final p95 = sorted[((numBoxes - 1) * 0.95).round()];
    final p99 = sorted[((numBoxes - 1) * 0.99).round()];

    const thresholds = [0.01, 0.05, 0.10, 0.25, 0.50];
    final counts = <double, int>{};
    for (final t in thresholds) {
      var cnt = 0;
      for (int a = 0; a < numBoxes; a++) {
        if (maxes[a] > t) cnt++;
      }
      counts[t] = cnt;
    }

    debugPrint('━━━ [InputProbe H] CONFIDENCE DISTRIBUTION (frame $frame) ━━━');
    debugPrint(
      '[InputProbe H] max=${maxV.toStringAsFixed(4)} '
      'mean=${mean.toStringAsFixed(4)} median=${median.toStringAsFixed(4)} '
      'p95=${p95.toStringAsFixed(4)} p99=${p99.toStringAsFixed(4)}',
    );
    debugPrint(
      '[InputProbe H] counts: '
      '${counts.entries.map((e) => '>${e.key}:${e.value}').join(' ')}',
    );
    debugPrint(
      '[InputProbe H] verdict: ${maxV < 0.5 ? "FLAT/LOW — input-side problem" : "HEALTHY — parser would detect"}',
    );
    debugPrint('━━━ [InputProbe H] END ━━━');
  }

  // -------------------------------------------------------------------------
  // Helpers
  // -------------------------------------------------------------------------
  static double _val(List out, int index, bool dequant, ModelMetadata m) {
    if (index < 0 || index >= out.length) return double.nan;
    final v = out[index].toDouble();
    return dequant ? (v - m.outputZeroPoint) * m.outputScale : v;
  }

  static List<({int anchor, int cls, double score, String label})> _topK(
    List output,
    ModelMetadata m,
    List<String> labels,
    int k,
  ) {
    final numBoxes = m.anchors;
    final numClasses = m.classes;
    final dequant = m.requiresOutputDequantization;
    final entries = <({int anchor, int cls, double score})>[];
    for (int a = 0; a < numBoxes; a++) {
      for (int c = 0; c < numClasses; c++) {
        entries.add((
          anchor: a,
          cls: c,
          score: _val(output, (4 + c) * numBoxes + a, dequant, m),
        ));
      }
    }
    entries.sort((x, y) => y.score.compareTo(x.score));
    return entries.take(k).map((e) {
      final label = (e.cls >= 0 && e.cls < labels.length)
          ? labels[e.cls]
          : 'class_${e.cls}';
      return (anchor: e.anchor, cls: e.cls, score: e.score, label: label);
    }).toList();
  }

  static String _fmt(List<double> values) =>
      values.map((v) => v.toStringAsFixed(3)).join(', ');

  static List<int> _randomIndices(int n, int count) {
    if (n <= count) return List.generate(n, (i) => i);
    final rng = math.Random(42);
    final out = <int>{};
    while (out.length < count) {
      out.add(rng.nextInt(n));
    }
    return out.toList()..sort();
  }

  static double _at(dynamic buf, int i) {
    if (buf is Float32List) return buf[i].toDouble();
    if (buf is Float64List) return buf[i].toDouble();
    if (buf is Int8List) return buf[i].toDouble();
    if (buf is Uint8List) return buf[i].toDouble();
    if (buf is Int16List) return buf[i].toDouble();
    if (buf is List) return buf[i].toDouble();
    return 0;
  }

  static int _len(dynamic buf) {
    if (buf is Float32List) return buf.length;
    if (buf is Float64List) return buf.length;
    if (buf is Int8List) return buf.length;
    if (buf is Uint8List) return buf.length;
    if (buf is Int16List) return buf.length;
    if (buf is List) return buf.length;
    return 0;
  }
}

/// Streaming min/max/mean/std accumulator.
class _Stats {
  double min = double.infinity;
  double max = -double.infinity;
  double _sum = 0;
  double _sumSq = 0;
  int _n = 0;

  void add(double v) {
    if (v.isNaN || v.isInfinite) return;
    if (v < min) min = v;
    if (v > max) max = v;
    _sum += v;
    _sumSq += v * v;
    _n++;
  }

  double get mean => _n == 0 ? double.nan : _sum / _n;
  double get std {
    if (_n < 2) return 0;
    final m = mean;
    return math.sqrt((_sumSq / _n - m * m).abs());
  }
}
