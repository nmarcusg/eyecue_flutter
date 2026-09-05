import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;

import '../models/model_metadata.dart';

/// ===========================================================================
/// TEMPORARY FORENSIC PROBE — DO NOT SHIP.
///
/// One-off diagnostics for the "Objects: 0" investigation. It ONLY reads
/// buffers and logs; it never changes inference behavior.
///
/// To remove: delete this file, remove the `InferenceProbe.*` calls from
/// `inference_isolate.dart`, and drop the import.
///
/// Coverage (per the investigation brief):
///   phase1 – model loading metadata cross-check
///   phase2 – preprocessing (one frame)
///   phase3 – raw output tensor stats (one frame)
///   phase4 – per-anchor parser probe (one frame)
///   phase5 – threshold sweep (one frame)
///   phase6 – decoded-box sanity (one frame)
///   phase7 – layout cross-check A vs B (one frame)
///   phase8 – per-frame latency / max-confidence correlation (every frame)
/// ===========================================================================
class InferenceProbe {
  /// Master switch: flip to false (or delete the file) to silence all probes.
  /// NOTE: replaced by the file-based [ForensicLog] — disabled.
  static const bool enabled = false;

  static bool _frame1Done = false;

  /// True while frame-1 probes (phase2–phase7) should still run.
  static bool get shouldRunFrame1Probes => enabled && !_frame1Done;

  /// Call once after phase2–phase7 have all run for the first frame.
  static void markFrame1Done() => _frame1Done = true;

  // -------------------------------------------------------------------------
  // PHASE 1 — model loading
  // -------------------------------------------------------------------------
  static void phase1(ModelMetadata m, {required int labelCount}) {
    debugPrint('━━━ [Probe P1] MODEL LOADING ━━━');
    debugPrint('[Probe P1] model=${m.modelName}');
    debugPrint(
      '[Probe P1] inputType=${m.inputType} inputShape=${m.inputShape} '
      'inputScale=${m.inputScale} inputZeroPoint=${m.inputZeroPoint}',
    );
    debugPrint(
      '[Probe P1] outputType=${m.outputType} outputShape=${m.outputShape} '
      'outputScale=${m.outputScale} outputZeroPoint=${m.outputZeroPoint}',
    );
    debugPrint(
      '[Probe P1] inputQuantized=${m.inputQuantized} '
      'outputQuantized=${m.outputQuantized}',
    );
    debugPrint('[Probe P1] modelType=${m.modelType.label}');
    debugPrint('[Probe P1] internalTensorTypes=${m.internalTensorTypeCounts}');
    debugPrint(
      '[Probe P1] classes=${m.classes} anchors=${m.anchors} '
      'labelsInFile=$labelCount',
    );
    debugPrint('━━━ [Probe P1] END ━━━');
  }

  // -------------------------------------------------------------------------
  // PHASE 2 — preprocessing (one frame only)
  // -------------------------------------------------------------------------
  static void phase2({
    required int srcWidth,
    required int srcHeight,
    required int dstHeight,
    required int dstWidth,
    required int frameNumber,
    required dynamic inputBuffer,
    required ModelMetadata m,
  }) {
    final int length = _len(inputBuffer);
    double minV = double.infinity;
    double maxV = -double.infinity;
    double sum = 0;
    final first20 = <double>[];
    final limit = length < 20 ? length : 20;
    for (int i = 0; i < length; i++) {
      final v = _at(inputBuffer, i);
      if (v < minV) minV = v;
      if (v > maxV) maxV = v;
      sum += v;
      if (i < limit) first20.add(v);
    }
    final mean = length == 0 ? double.nan : sum / length;

    debugPrint('━━━ [Probe P2] PREPROCESSING (frame $frameNumber) ━━━');
    debugPrint(
      '[Probe P2] src=${srcWidth}x$srcHeight dst=${dstWidth}x$dstHeight '
      'bufferType=${inputBuffer.runtimeType}',
    );
    debugPrint(
      '[Probe P2] bufferLen=$length expected=${ModelMetadata.elementCount(m.inputShape)}',
    );
    debugPrint('[Probe P2] min=$minV max=$maxV mean=$mean');
    debugPrint(
      '[Probe P2] first20=${first20.take(20).map((v) => v.toStringAsFixed(4)).join(', ')}',
    );
    // Channel ordering: for NHWC interleaved RGB the first 3 values are
    // [R, G, B] of pixel 0; log whether values fall in [0,1] (normalized) or
    // [0,255] (raw) to confirm the normalization path.
    debugPrint(
      '[Probe P2] normalization: first3=${first20.take(3).map((v) => v.toStringAsFixed(4)).join(",")} '
      '(in [0,1] => normalized; in [0,255] => NOT normalized)',
    );
    debugPrint(
      '[Probe P2] requiresInputQuantization=${m.requiresInputQuantization} '
      'inputScale=${m.inputScale} inputZeroPoint=${m.inputZeroPoint}',
    );
    debugPrint('━━━ [Probe P2] END ━━━');
  }

  // -------------------------------------------------------------------------
  // PHASE 3 — raw output tensor (one frame, before parsing)
  // -------------------------------------------------------------------------
  static void phase3(List output, ModelMetadata m, int frameNumber) {
    double minV = double.infinity;
    double maxV = -double.infinity;
    double sum = 0;
    int nanCount = 0;
    int infCount = 0;
    final top = <_TopEntry>[];
    for (int i = 0; i < output.length; i++) {
      final v = output[i].toDouble();
      if (v.isNaN) {
        nanCount++;
        continue;
      }
      if (v.isInfinite) {
        infCount++;
        continue;
      }
      if (v < minV) minV = v;
      if (v > maxV) maxV = v;
      sum += v;
      _insertTop(top, v, i, 20);
    }
    final mean = output.isEmpty ? double.nan : sum / output.length;

    debugPrint('━━━ [Probe P3] RAW OUTPUT TENSOR (frame $frameNumber) ━━━');
    debugPrint(
      '[Probe P3] outLen=${output.length} '
      'expected=${ModelMetadata.elementCount(m.outputShape)} type=${output.runtimeType}',
    );
    debugPrint(
      '[Probe P3] min=$minV max=$maxV mean=$mean nan=$nanCount inf=$infCount',
    );
    debugPrint('[Probe P3] allZero=${maxV == 0.0}');
    debugPrint(
      '[Probe P3] top20=${top.map((e) => '${e.value.toStringAsFixed(4)}@${e.index}').join(', ')}',
    );
    debugPrint(
      '[Probe P3] top20%0-640px: if indices < 8400 => row 0 (x box); 84-167 => row1 etc.',
    );
    debugPrint('━━━ [Probe P3] END ━━━');
  }

  // -------------------------------------------------------------------------
  // PHASE 4 — parser probe: first anchors (one frame)
  // -------------------------------------------------------------------------
  static void phase4(List output, ModelMetadata m, int frameNumber) {
    final numBoxes = m.anchors;
    final numClasses = m.classes;
    final dequant = m.requiresOutputDequantization;

    debugPrint('━━━ [Probe P4] PARSER PROBE (frame $frameNumber) ━━━');
    final anchors = <int>[0, 1, 10, 100, 1000, numBoxes - 1];
    for (final a in anchors) {
      if (a < 0 || a >= numBoxes) continue;
      final cx = _outVal(output, 0 * numBoxes + a, dequant, m);
      final cy = _outVal(output, 1 * numBoxes + a, dequant, m);
      final w = _outVal(output, 2 * numBoxes + a, dequant, m);
      final h = _outVal(output, 3 * numBoxes + a, dequant, m);
      final best = _maxClass(output, a, numBoxes, numClasses, dequant, m);
      final top3 = _topClasses(output, a, numBoxes, numClasses, dequant, m, 3);
      debugPrint(
        '[Probe P4] anchor=$a bbox=[cx=$cx cy=$cy w=$w h=$h] '
        'top3=${top3.map((e) => 'cls${e.cls}:${e.score.toStringAsFixed(4)}').join(", ")} '
        'bestCls=${best.cls} bestScore=${best.score.toStringAsFixed(4)}',
      );
    }

    // Global best across the whole tensor (layout A = current parser).
    var gBest = -double.infinity;
    int gAnchor = -1;
    int gCls = -1;
    for (int a = 0; a < numBoxes; a++) {
      final b = _maxClass(output, a, numBoxes, numClasses, dequant, m);
      if (b.score > gBest) {
        gBest = b.score;
        gAnchor = a;
        gCls = b.cls;
      }
    }
    debugPrint(
      '[Probe P4] GLOBAL bestScore=${gBest.toStringAsFixed(4)} '
      'anchor=$gAnchor class=$gCls (label="${gCls >= 0 && gCls < 80 ? 'n/a' : 'n/a'}")',
    );
    debugPrint('━━━ [Probe P4] END ━━━');
  }

  // -------------------------------------------------------------------------
  // PHASE 5 — threshold sweep (one frame) — does NOT change production.
  // -------------------------------------------------------------------------
  static void phase5(List output, ModelMetadata m, int frameNumber) {
    final numBoxes = m.anchors;
    final numClasses = m.classes;
    final dequant = m.requiresOutputDequantization;
    const thresholds = [0.01, 0.05, 0.10, 0.20, 0.30, 0.40, 0.50, 0.60];

    // Layout A (current parser): score = out[(4+c)*N + a]
    // Layout B (anchors-major): score = out[a*(4+nc) + (4+c)]
    final countsA = <double, int>{};
    final countsB = <double, int>{};
    double maxA = -double.infinity;
    double maxB = -double.infinity;
    for (int a = 0; a < numBoxes; a++) {
      double bestA = -double.infinity;
      double bestB = -double.infinity;
      for (int c = 0; c < numClasses; c++) {
        final vA = _outVal(output, (4 + c) * numBoxes + a, dequant, m);
        if (vA > bestA) bestA = vA;
        final idxB = a * (4 + numClasses) + (4 + c);
        if (idxB < output.length) {
          final vB = _outVal(output, idxB, dequant, m);
          if (vB > bestB) bestB = vB;
        }
      }
      if (bestA > maxA) maxA = bestA;
      if (bestB > maxB) maxB = bestB;
      for (final t in thresholds) {
        if (bestA > t) countsA[t] = (countsA[t] ?? 0) + 1;
        if (bestB > t) countsB[t] = (countsB[t] ?? 0) + 1;
      }
    }

    debugPrint('━━━ [Probe P5] THRESHOLD SWEEP (frame $frameNumber) ━━━');
    debugPrint(
      '[Probe P5] layoutA (features-major, current parser): max=${maxA.toStringAsFixed(4)} '
      'counts=${countsA.entries.map((e) => '>${e.key}:${e.value}').join(' ')}',
    );
    debugPrint(
      '[Probe P5] layoutB (anchors-major [1,N,4+nc]):         max=${maxB.toStringAsFixed(4)} '
      'counts=${countsB.entries.map((e) => '>${e.key}:${e.value}').join(' ')}',
    );
    debugPrint(
      '[Probe P5] production threshold=0.50 → layoutA count=${countsA[0.50] ?? 0}',
    );
    debugPrint('━━━ [Probe P5] END ━━━');
  }

  // -------------------------------------------------------------------------
  // PHASE 6 — decoded-box sanity (one frame)
  // -------------------------------------------------------------------------
  static void phase6(List output, ModelMetadata m, int frameNumber) {
    final numBoxes = m.anchors;
    final numClasses = m.classes;
    final dequant = m.requiresOutputDequantization;

    debugPrint('━━━ [Probe P6] DECODED BOXES (frame $frameNumber) ━━━');
    int shown = 0;
    for (int a = 0; a < numBoxes && shown < 20; a++) {
      final best = _maxClass(output, a, numBoxes, numClasses, dequant, m);
      if (best.score <= 0.25) continue; // only meaningful anchors
      final cx = _outVal(output, 0 * numBoxes + a, dequant, m);
      final cy = _outVal(output, 1 * numBoxes + a, dequant, m);
      final w = _outVal(output, 2 * numBoxes + a, dequant, m);
      final h = _outVal(output, 3 * numBoxes + a, dequant, m);
      final bad = <String>[];
      if (w < 0) bad.add('negW');
      if (h < 0) bad.add('negH');
      if (cx.isNaN || cy.isNaN || w.isNaN || h.isNaN) bad.add('NaN');
      if (cx.isInfinite || cy.isInfinite || w.isInfinite || h.isInfinite) {
        bad.add('Inf');
      }
      if (cx < 0 || cx > 640 || cy < 0 || cy > 640) bad.add('outXy');
      if (w > 640 || h > 640) bad.add('outWh');
      debugPrint(
        '[Probe P6] anchor=$a score=${best.score.toStringAsFixed(4)} '
        'box=[cx=$cx cy=$cy w=$w h=$h] issues=${bad.isEmpty ? 'none' : bad.join(",")} '
        '(pixel-space expected: 0..640; normalized would be 0..1)',
      );
      shown++;
    }
    debugPrint('━━━ [Probe P6] END ━━━');
  }

  // -------------------------------------------------------------------------
  // PHASE 7 — layout cross-check (one frame) — folded into phase5.
  // -------------------------------------------------------------------------
  static void phase7(List output, ModelMetadata m, int frameNumber) {
    debugPrint(
      '[Probe P7] Layout evidence: outputShape=${m.outputShape}. '
      'Features-major [1,4+nc,N] implies score(anchor a, class c) = out[(4+c)*N+a]. '
      'See phase5 sweep for A-vs-B maxima.',
    );
  }

  // -------------------------------------------------------------------------
  // PHASE 8 — per-frame latency / max-confidence correlation (every frame)
  // -------------------------------------------------------------------------
  static void phase8({
    required int frameNumber,
    required double latencyMs,
    required int detectionCount,
    required List output,
    required ModelMetadata m,
  }) {
    if (!enabled) return;
    final numBoxes = m.anchors;
    final numClasses = m.classes;
    final dequant = m.requiresOutputDequantization;

    double maxConf = -double.infinity;
    for (int a = 0; a < numBoxes; a++) {
      final best = _maxClass(output, a, numBoxes, numClasses, dequant, m);
      if (best.score > maxConf) maxConf = best.score;
    }
    debugPrint(
      '[Probe P8] frame=$frameNumber latency=${latencyMs.toStringAsFixed(1)}ms '
      'maxConf=${maxConf.toStringAsFixed(4)} detections=$detectionCount',
    );
  }

  // -------------------------------------------------------------------------
  // Helpers
  // -------------------------------------------------------------------------
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
    if (buf is TypedData) return buf.lengthInBytes ~/ _elementSize(buf);
    if (buf is List) return buf.length;
    return 0;
  }

  static int _elementSize(dynamic buf) {
    if (buf is Float32List) return 4;
    if (buf is Float64List) return 8;
    if (buf is Int8List) return 1;
    if (buf is Uint8List) return 1;
    if (buf is Int16List) return 2;
    return 1;
  }

  static double _outVal(List out, int index, bool dequant, ModelMetadata m) {
    if (index < 0 || index >= out.length) return double.nan;
    final v = out[index].toDouble();
    return dequant ? (v - m.outputZeroPoint) * m.outputScale : v;
  }

  static ({double score, int cls}) _maxClass(
    List out,
    int anchor,
    int numBoxes,
    int numClasses,
    bool dequant,
    ModelMetadata m,
  ) {
    double best = -double.infinity;
    int bestCls = -1;
    for (int c = 0; c < numClasses; c++) {
      final v = _outVal(out, (4 + c) * numBoxes + anchor, dequant, m);
      if (v > best) {
        best = v;
        bestCls = c;
      }
    }
    return (score: best, cls: bestCls);
  }

  static List<({int cls, double score})> _topClasses(
    List out,
    int anchor,
    int numBoxes,
    int numClasses,
    bool dequant,
    ModelMetadata m,
    int n,
  ) {
    final entries = <({int cls, double score})>[];
    for (int c = 0; c < numClasses; c++) {
      entries.add((
        cls: c,
        score: _outVal(out, (4 + c) * numBoxes + anchor, dequant, m),
      ));
    }
    entries.sort((a, b) => b.score.compareTo(a.score));
    return entries.take(n).toList();
  }

  static void _insertTop(List<_TopEntry> top, double value, int index, int n) {
    top.add(_TopEntry(value, index));
    if (top.length > n) {
      top.sort((a, b) => b.value.compareTo(a.value));
      if (top.length > n) top.removeLast();
    }
  }
}

class _TopEntry {
  final double value;
  final int index;
  _TopEntry(this.value, this.index);
}
