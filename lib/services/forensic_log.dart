import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint, kReleaseMode;
import 'package:path_provider/path_provider.dart';

import '../models/model_metadata.dart';
import '../models/png_encoder.dart';

/// ===========================================================================
/// ForensicLog — structured, file-based diagnostics for the inference pipeline.
///
/// Writes timestamped text logs and PNG image dumps into
/// `<application_documents>/debug/run_YYYYMMDD_HHMMSS/` so the pipeline can be
/// diagnosed offline without relying on logcat. Writes, flushes, and directory
/// creation happen only in debug/profile builds; release builds gate all file
/// I/O off via [enabled].
///
/// Files:
///   summary.txt       auto-generated diagnosis (every 50 frames + on close)
///   camera.txt        CameraImage geometry + inferred format (once)
///   preprocess.txt    RGB / resize / normalization statistics (frame 1)
///   tensor.txt        input tensor immediately before run() (frame 1)
///   output.txt        raw output tensor statistics (frame 1)
///   parser.txt        pre/post-threshold detections (frame 1)
///   performance.txt   per-frame latency / fps / confidence
///   errors.txt        exceptions raised by the instrumentation itself
///   frame_*.png       first-frame image dumps
///
/// Design rules:
///   * Never affects inference behavior — every write is try/catch-guarded.
///   * When diagnostics are enabled, every append flushes synchronously so a
///     crash cannot lose logs.
///   * Everything is removable (delete this file + its call sites).
/// ===========================================================================
class ForensicLog {
  /// Master switch — disabled in release builds; debug and profile builds keep
  /// file logging.
  static const bool enabled = !kReleaseMode;

  /// Whether to write first-frame PNG image dumps.
  static const bool dumpImages = true;

  /// Auto-write summary.txt every N processed frames.
  static const int summaryEveryFrames = 50;

  static String? _runDir;
  static bool _finalized = false;

  /// Run directory path (`.../debug/run_YYYYMMDD_HHMMSS`). Resolved lazily so
  /// loggers work even if [init] was not awaited in time.
  static String get runDir => _runDir ?? 'debug_run';

  static String get runDirName => _runDir == null
      ? 'debug_run'
      : _runDir!.split(Platform.pathSeparator).last;

  static final ForensicLogger camera = ForensicLogger('camera.txt');
  static final ForensicLogger preprocess = ForensicLogger('preprocess.txt');
  static final ForensicLogger tensor = ForensicLogger('tensor.txt');
  static final ForensicLogger output = ForensicLogger('output.txt');
  static final ForensicLogger parser = ForensicLogger('parser.txt');
  static final ForensicLogger performance = ForensicLogger('performance.txt');
  static final ForensicLogger errors = ForensicLogger('errors.txt');
  static final ForensicLogger summary = ForensicLogger('summary.txt');

  /// Accumulated statistics for the auto-generated diagnosis.
  static final _Summary _s = _Summary();

  /// -----------------------------------------------------------------------
  /// Lifecycle
  /// -----------------------------------------------------------------------

  /// Creates `<documents>/debug/run_<timestamp>/` and clears all channels.
  /// Returns the run directory path, or null if disabled/failed.
  static Future<String?> init() async {
    if (!enabled) return null;
    try {
      final docs = await getApplicationDocumentsDirectory();
      final debugDir = Directory('${docs.path}${Platform.pathSeparator}debug');
      if (!debugDir.existsSync()) {
        debugDir.createSync(recursive: true);
      }
      final run = Directory(
        '${debugDir.path}${Platform.pathSeparator}run_${_timestamp()}',
      );
      run.createSync(recursive: true);
      _runDir = run.path;
      debugPrint('[Forensic] run dir: ${run.path}');
      for (final l in [
        camera,
        preprocess,
        tensor,
        output,
        parser,
        performance,
        errors,
        summary,
      ]) {
        l.clear();
      }
      return _runDir;
    } catch (e) {
      debugPrint('[Forensic] init failed: $e');
      return null;
    }
  }

  /// Sets the run directory from inside the inference isolate (the path is
  /// passed across the isolate boundary as a plain string).
  static void setRunDir(String dir) {
    if (!enabled) return;
    _runDir = dir;
    debugPrint('[Forensic] isolate run dir: $dir');
  }

  /// Writes a final summary and closes all channels (call on app teardown).
  static void finalize() {
    if (!enabled || _finalized) return;
    _finalized = true;
    _writeSummary();
    for (final l in [
      camera,
      preprocess,
      tensor,
      output,
      parser,
      performance,
      errors,
      summary,
    ]) {
      l.close();
    }
    debugPrint('[Forensic] finalized run $runDirName');
  }

  /// Auto-diagnosis hook — call once per processed frame.
  static void tickProcessedFrame() {
    if (!enabled) return;
    _s.frames++;
    if (_s.frames % summaryEveryFrames == 0) {
      _writeSummary();
    }
  }

  // -------------------------------------------------------------------------
  // camera.txt (main isolate, once)
  // -------------------------------------------------------------------------
  static void recordCamera({
    required int formatRaw,
    required String formatGroup,
    required int width,
    required int height,
    required List<
      ({
        int len,
        int rowStride,
        int? pixelStride,
        int planeWidth,
        int planeHeight,
        int firstByte,
        int lastByte,
      })
    >
    planes,
    required String inferredFormat,
    int sensorOrientation = -1,
    String lensDirection = '',
  }) {
    if (sensorOrientation >= 0) {
      camera.append(
        'Sensor orientation: $sensorOrientation°  Lens: $lensDirection',
      );
    }
    _s.cameraFormat = inferredFormat;
    // The converter supports planar I420 (pixelStride 1) and semi-planar
    // NV12/NV21 (pixelStride 2, interleaved) using real rowStride/pixelStride.
    final layoutSupported =
        planes.length >= 2 &&
        ((planes[1].pixelStride ?? 1) == 1 ||
            (planes[1].pixelStride ?? 1) == 2);
    _s.cameraMismatch = !layoutSupported;
    _s.cameraPass = layoutSupported;

    camera.append('=== Camera ===');
    camera.append('Format raw: $formatRaw  group: $formatGroup');
    camera.append('Size: ${width}x$height  planes: ${planes.length}');
    for (int i = 0; i < planes.length; i++) {
      final p = planes[i];
      camera.append(
        'Plane$i: rowStride=${p.rowStride} '
        'pixelStride=${p.pixelStride ?? "n/a"} length=${p.len} '
        'planeSize=${p.planeWidth}x${p.planeHeight} '
        'firstByte=${p.firstByte} lastByte=${p.lastByte}',
      );
    }
    camera.append('Inferred format: $inferredFormat');
    // Definite layout classification from real plane metadata (not guessing).
    final String layout;
    if (planes.length >= 3) {
      final c1 = planes[1].pixelStride ?? 1;
      final c2 = planes[2].pixelStride ?? 1;
      if (c1 == 1 && c2 == 1) {
        layout = 'PLANAR I420 (chroma pixelStride==1, U/V separate buffers)';
      } else if (c1 == 2 || c2 == 2) {
        final sameLen = planes[1].len == planes[2].len;
        final sameBytes = planes[1].firstByte == planes[2].firstByte;
        layout =
            'SEMI-PLANAR interleaved (chroma pixelStride==2). '
            'plane1==plane2 buffer -> lenSame:$sameLen firstByteSame:$sameBytes '
            '(NV12 = U-led / NV21 = V-led; order NOT decided by geometry)';
      } else {
        layout = 'UNKNOWN layout (chroma pixelStrides $c1/$c2)';
      }
    } else {
      layout = '2-plane semi-planar (plane[1] = shared interleaved chroma)';
    }
    camera.append('Layout (from metadata): $layout');
    camera.append(
      'Converter support: I420 planar + NV12/NV21 semi-planar '
      '(rowStride/pixelStride aware)',
    );
    camera.append('Mismatch: ${layoutSupported ? "NO (handled)" : "YES"}');
  }

  // -------------------------------------------------------------------------
  // preprocess.txt (inference isolate, frame 1)
  // -------------------------------------------------------------------------
  static void recordPreprocess({
    required dynamic input,
    required ModelMetadata m,
    required bool isNCHW,
    required int frame,
    required int srcWidth,
    required int srcHeight,
    required int dstWidth,
    required int dstHeight,
  }) {
    final n = _len(input);
    final stats = List.generate(3, (_) => _Stats());
    for (int i = 0; i < n; i++) {
      final v = _at(input, i);
      int c;
      if (isNCHW) {
        c = i ~/ (n ~/ 3);
      } else {
        c = i % 3;
      }
      if (c >= 0 && c < 3) stats[c].add(v);
    }

    preprocess.append('=== Preprocess (frame $frame) ===');
    preprocess.append(
      'Source: ${srcWidth}x$srcHeight  Target: ${dstWidth}x$dstHeight',
    );
    preprocess.append('Layout: ${isNCHW ? "NCHW" : "NHWC"}');
    preprocess.append('--- RGB statistics (post YUV→RGB, normalized) ---');
    const names = ['R', 'G', 'B'];
    for (int c = 0; c < 3; c++) {
      preprocess.append(
        '$names[c]: min=${_f(stats[c].min)} max=${_f(stats[c].max)} '
        'mean=${_f(stats[c].mean)} std=${_f(stats[c].std)}',
      );
    }
    final means = stats.map((s) => s.mean).toList();
    final spread = means.reduce(math.max) - means.reduce(math.min);
    final allZero = stats.every((s) => s.max == 0);
    final allOne = stats.every(
      (s) => (s.min - 1).abs() < 1e-9 && (s.max - 1).abs() < 1e-9,
    );
    preprocess.append(
      'channelSpread=${_f4(spread)} allZero=$allZero allOne=$allOne',
    );

    // Resize stage (same buffer in this fused implementation).
    preprocess.append('--- After resize ---');
    final resized = _Stats();
    for (int i = 0; i < n; i++) {
      resized.add(_at(input, i));
    }
    preprocess.append(
      'resized ${srcWidth}x$srcHeight → $dstWidth x $dstHeight '
      'min=${_f(resized.min)} max=${_f(resized.max)} mean=${_f(resized.mean)}',
    );

    // Normalization stage.
    preprocess.append('--- After normalization ---');
    int neg = 0;
    int aboveOne = 0;
    final norm = _Stats();
    for (int i = 0; i < n; i++) {
      final v = _at(input, i);
      norm.add(v);
      if (v < 0) neg++;
      if (v > 1.0) aboveOne++;
    }
    preprocess.append(
      'min=${_f(norm.min)} max=${_f(norm.max)} '
      'mean=${_f(norm.mean)} std=${_f(norm.std)}',
    );
    preprocess.append(
      'allZero=${norm.max == 0} allOne=${(norm.min - norm.max).abs() < 1e-9} '
      'containsNaN=$_containsNan(input) containsInf=$_containsInf(input) '
      'negatives=$neg (>1)=$aboveOne',
    );

    _s.preprocessPass = !(allZero || allOne || norm.max > 1.0 || norm.max == 0);
  }

  // -------------------------------------------------------------------------
  // tensor.txt (inference isolate, frame 1, immediately before run())
  // -------------------------------------------------------------------------
  static void recordTensor({
    required dynamic input,
    required ModelMetadata m,
    required int frame,
  }) {
    final n = _len(input);
    final expected = ModelMetadata.elementCount(m.inputShape);
    final s = _Stats();
    final first = <double>[];
    final last = <double>[];
    final sample = <double>[];
    final sampleIdx = _sampleIndices(n, 32);
    for (int i = 0; i < n; i++) {
      final v = _at(input, i);
      s.add(v);
      if (i < 64) first.add(v);
      if (i >= n - 64) last.add(v);
      if (sampleIdx.contains(i)) sample.add(v);
    }

    tensor.append('=== Input tensor before run() (frame $frame) ===');
    tensor.append('inputShape=${m.inputShape} dtype=${m.inputType}');
    tensor.append('expectedLen=$expected actualLen=$n');
    tensor.append(
      'min=${_f(s.min)} max=${_f(s.max)} mean=${_f(s.mean)} std=${_f(s.std)}',
    );
    tensor.append('first64=${_fmt(first)}');
    tensor.append('last64=${_fmt(last)}');
    tensor.append('sample32=${_fmt(sample)}');
    if (m.requiresInputQuantization) {
      tensor.append(
        'inputScale=${m.inputScale} inputZeroPoint=${m.inputZeroPoint}',
      );
    }
    _s.tensorPass = !(s.max == 0 || s.max.isNaN || s.max.isInfinite);
  }

  // -------------------------------------------------------------------------
  // output.txt (inference isolate, frame 1, immediately after run())
  // -------------------------------------------------------------------------
  static void recordOutput({
    required List parseable,
    required ModelMetadata m,
    required int frame,
    required List<String> labels,
  }) {
    final s = _Stats();
    int nan = 0;
    int inf = 0;
    final top = <_Top>{};
    for (int i = 0; i < parseable.length; i++) {
      final v = parseable[i].toDouble();
      if (v.isNaN) {
        nan++;
        continue;
      }
      if (v.isInfinite) {
        inf++;
        continue;
      }
      s.add(v);
      _pushTop(top, v, i);
    }
    final allZero = s.max == 0;

    // Per-anchor max class scores for distribution + top-20 confidences.
    final numBoxes = m.anchors;
    final numClasses = m.classes;
    final dequant = m.requiresOutputDequantization;
    final maxes = Float64List(numBoxes);
    final topConf = <({int anchor, int cls, double score})>[];
    for (int a = 0; a < numBoxes; a++) {
      double best = -double.infinity;
      int bestCls = -1;
      for (int c = 0; c < numClasses; c++) {
        final v = _val(parseable, (4 + c) * numBoxes + a, dequant, m);
        if (v > best) {
          best = v;
          bestCls = c;
        }
      }
      maxes[a] = best;
      if (best >= 0) {
        topConf.add((anchor: a, cls: bestCls, score: best));
      }
    }
    topConf.sort((x, y) => y.score.compareTo(x.score));
    final sorted = List<double>.of(maxes)..sort();
    final p50 = sorted[numBoxes ~/ 2];
    final p95 = sorted[((numBoxes - 1) * 0.95).round()];
    final p99 = sorted[((numBoxes - 1) * 0.99).round()];
    final maxConf = maxes.isEmpty ? 0.0 : maxes.reduce(math.max);

    const thresholds = [0.01, 0.05, 0.10, 0.25, 0.50];
    final counts = <String, int>{};
    for (final t in thresholds) {
      var cnt = 0;
      for (int a = 0; a < numBoxes; a++) {
        if (maxes[a] > t) cnt++;
      }
      counts['>$t'] = cnt;
    }

    output.append('=== Output tensor (frame $frame) ===');
    output.append('outputShape=${m.outputShape} dtype=${m.outputType}');
    output.append(
      'min=${_f(s.min)} max=${_f(s.max)} mean=${_f(s.mean)} std=${_f(s.std)}',
    );
    output.append('containsNaN=$nan containsInf=$inf allZero=$allZero');
    output.append('--- Top 20 confidences ---');
    for (int i = 0; i < topConf.length && i < 20; i++) {
      final e = topConf[i];
      final label = (e.cls >= 0 && e.cls < labels.length)
          ? labels[e.cls]
          : 'class_${e.cls}';
      output.append('anchor ${e.anchor}  $label  ${_f4(e.score)}');
    }
    output.append('p50=${_f4(p50)} p95=${_f4(p95)} p99=${_f4(p99)}');
    output.append(
      'counts: ${counts.entries.map((e) => '${e.key}:${e.value}').join(' ')}',
    );

    // Update summary state.
    _s.maxConf = maxConf;
    _s.p99 = p99;
    _s.distribution = maxConf < 0.5 ? 'FLAT' : 'HEALTHY';
    _s.outputPass = maxConf >= 0.5 && !allZero && nan == 0 && inf == 0;
    if (topConf.isNotEmpty) {
      final top = topConf.first;
      _s.topClass = (top.cls >= 0 && top.cls < labels.length)
          ? labels[top.cls]
          : 'class_${top.cls}';
    }
  }

  // -------------------------------------------------------------------------
  // parser.txt (inference isolate, frame 1)
  // -------------------------------------------------------------------------
  static void recordParser({
    required List parseable,
    required ModelMetadata m,
    required int frame,
    required List<String> labels,
    required int detectionsAfterThreshold,
  }) {
    final numBoxes = m.anchors;
    final numClasses = m.classes;
    final dequant = m.requiresOutputDequantization;

    // Top 20 BEFORE any threshold.
    final entries = <({int anchor, int cls, double score})>[];
    for (int a = 0; a < numBoxes; a++) {
      for (int c = 0; c < numClasses; c++) {
        entries.add((
          anchor: a,
          cls: c,
          score: _val(parseable, (4 + c) * numBoxes + a, dequant, m),
        ));
      }
    }
    entries.sort((x, y) => y.score.compareTo(x.score));

    parser.append('=== Parser (frame $frame) ===');
    parser.append('--- Top 20 BEFORE thresholding ---');
    for (int i = 0; i < entries.length && i < 20; i++) {
      final e = entries[i];
      final label = (e.cls >= 0 && e.cls < labels.length)
          ? labels[e.cls]
          : 'class_${e.cls}';
      final cx = _val(parseable, 0 * numBoxes + e.anchor, dequant, m);
      final cy = _val(parseable, 1 * numBoxes + e.anchor, dequant, m);
      final w = _val(parseable, 2 * numBoxes + e.anchor, dequant, m);
      final h = _val(parseable, 3 * numBoxes + e.anchor, dequant, m);
      parser.append(
        'anchor ${e.anchor}  $label  ${_f4(e.score)}  '
        'rawBox=[cx=${_f4(cx)} cy=${_f4(cy)} w=${_f4(w)} h=${_f4(h)}]  '
        'decodedBox=[${_f4(cx - w / 2)},${_f4(cy - h / 2)},${_f4(w)},${_f4(h)}]',
      );
    }
    parser.append(
      'detections after threshold(0.25)+NMS: $detectionsAfterThreshold',
    );
  }

  // -------------------------------------------------------------------------
  // performance.txt — orientation diagnostics (inference isolate, every frame)
  // -------------------------------------------------------------------------
  static void recordOrientation({
    required int frame,
    required int sensorOrientation,
    required int deviceDegrees,
    required int rotationDegrees,
    required bool mirror,
    required String lensFacing,
    required int inW,
    required int inH,
    required int outW,
    required int outH,
  }) {
    if (!enabled) return;
    performance.append(
      'orientation frame=$frame sensor=$sensorOrientation '
      'device=$deviceDegrees rot=$rotationDegrees mirror=$mirror '
      'lens=$lensFacing in=${inW}x$inH out=${outW}x$outH',
    );
  }

  // -------------------------------------------------------------------------
  // performance.txt (inference isolate, every frame)
  // -------------------------------------------------------------------------
  static void recordPerformance({
    required int frame,
    required double latencyMs,
    required double cameraFps,
    required int droppedFrames,
    required int queueDepth,
    required int detections,
    required List parseable,
    required ModelMetadata m,
    double yMean = -1,
  }) {
    final maxConf = _maxConfidence(parseable, m);
    final inferenceFps = latencyMs > 0 ? 1000.0 / latencyMs : 0.0;
    performance.append(
      'frame=$frame latency=${_f1(latencyMs)}ms '
      'cameraFps=${_f1(cameraFps)} inferenceFps=${_f1(inferenceFps)} '
      'queueDepth=$queueDepth droppedFrames=$droppedFrames '
      'maxConf=${_f4(maxConf)} detections=$detections'
      '${yMean >= 0 ? ' yMean=${_f1(yMean)}' : ''}',
    );

    // Track global max confidence for the summary.
    if (maxConf > _s.globalMaxConf) _s.globalMaxConf = maxConf;
    _s.lastLatencyMs = latencyMs;
    _s.droppedFrames = droppedFrames;
    _s.detections = detections;
  }

  /// Maximum per-anchor class confidence (same indexing as the parser).
  static double _maxConfidence(List parseable, ModelMetadata m) {
    final numBoxes = m.anchors;
    final numClasses = m.classes;
    final dequant = m.requiresOutputDequantization;
    double best = -double.infinity;
    for (int a = 0; a < numBoxes; a++) {
      for (int c = 0; c < numClasses; c++) {
        final v = _val(parseable, (4 + c) * numBoxes + a, dequant, m);
        if (v > best) best = v;
      }
    }
    return best;
  }

  // -------------------------------------------------------------------------
  // errors.txt
  // -------------------------------------------------------------------------
  static void recordError(String where, Object e, StackTrace? st) {
    errors.append('[ERROR] $where: $e');
    if (st != null) {
      final lines = st.toString().split('\n');
      for (int i = 0; i < lines.length && i < 8; i++) {
        errors.append('  ${lines[i]}');
      }
    }
  }

  // -------------------------------------------------------------------------
  // Summary (auto-generated)
  // -------------------------------------------------------------------------
  static void _writeSummary() {
    summary.clear();
    final b = StringBuffer();
    b.writeln('======== SUMMARY ========');
    b.writeln('Run: $runDirName');
    b.writeln('Frames processed: ${_s.frames}');
    b.writeln(
      'Last latency: ${_f1(_s.lastLatencyMs)}ms  Dropped: ${_s.droppedFrames}',
    );
    b.writeln();
    b.writeln('Camera');
    b.writeln('  Detected format: ${_s.cameraFormat ?? "UNKNOWN"}');
    b.writeln('  Converter assumption: I420');
    b.writeln('  Mismatch: ${_s.cameraMismatch ?? false ? "YES" : "NO"}');
    b.writeln('  Status: ${_s.cameraPass == false ? "FAIL" : "PASS"}');
    b.writeln();
    b.writeln('Input');
    b.writeln('  Status: ${_s.preprocessPass == false ? "FAIL" : "PASS"}');
    b.writeln();
    b.writeln('Tensor');
    b.writeln('  Status: ${_s.tensorPass == false ? "FAIL" : "PASS"}');
    b.writeln();
    b.writeln('Output');
    b.writeln('  Status: ${_s.outputPass == false ? "FAIL" : "PASS"}');
    b.writeln('  Max confidence: ${_f4(_s.maxConf)}');
    b.writeln('  P99: ${_f4(_s.p99)}');
    b.writeln('  Top class: ${_s.topClass ?? "n/a"}');
    b.writeln('  Distribution: ${_s.distribution}');
    b.writeln();
    b.writeln('Likely root causes');
    for (final cause in _diagnose()) {
      b.writeln('  ${cause.index}. ${cause.text}');
      b.writeln('    Confidence: ${cause.confidence}%');
    }
    b.writeln('=========================');
    summary.append(b.toString());
  }

  static List<({int index, String text, int confidence})> _diagnose() {
    final causes = <({int index, String text, int confidence})>[];
    var idx = 1;

    if (_s.cameraMismatch == true) {
      causes.add((
        index: idx++,
        text: 'Camera preprocessing mismatch (YUV format/layout)',
        confidence: 45,
      ));
    } else if (_s.preprocessPass == false) {
      causes.add((
        index: idx++,
        text: 'Degenerate preprocessed input (black/constant/wrong scale)',
        confidence: 30,
      ));
    }

    if (_s.outputPass == false) {
      causes.add((
        index: idx++,
        text: _s.distribution == 'FLAT'
            ? 'Flat output (input-side problem or output readback)'
            : 'Output health issue (NaN/Inf/allZero)',
        confidence: _s.cameraMismatch == true ? 25 : 35,
      ));
    } else {
      causes.add((
        index: idx++,
        text: 'No confirmed failure — output healthy, check thresholds/boxes',
        confidence: 10,
      ));
    }

    if (idx == 1) {
      causes.add((
        index: idx++,
        text: 'Parser / layout (residual — previously verified correct)',
        confidence: 10,
      ));
    }

    return causes;
  }

  // -------------------------------------------------------------------------
  // planes raw-statistics (inference isolate, on dumped frames)
  // -------------------------------------------------------------------------
  static void recordPlaneStats({
    required Uint8List y,
    required Uint8List u,
    required Uint8List v,
    required int frame,
    required int yRowStride,
    required int yPixelStride,
    required int uRowStride,
    required int uPixelStride,
    required int vRowStride,
    required int vPixelStride,
  }) {
    if (!enabled) return;
    preprocess.append('--- Raw plane stats (frame $frame) ---');
    preprocess.append('Y: ${_planeSummary(y)}');
    preprocess.append('U: ${_planeSummary(u)}');
    preprocess.append('V: ${_planeSummary(v)}');
    preprocess.append(
      'geometry: y=[row:$yRowStride pix:$yPixelStride] '
      'u=[row:$uRowStride pix:$uPixelStride] v=[row:$vRowStride pix:$vPixelStride]',
    );
    final uSpread = _spreadAround(u, 128);
    final vSpread = _spreadAround(v, 128);
    preprocess.append(
      'chroma content: U std-around-128=${_f1(uSpread)} '
      'V std-around-128=${_f1(vSpread)}  (>10 => real color; ~0 => flat chroma)',
    );
    preprocess.append('luma: ${_lumaNote(y)}');
  }

  static String _planeSummary(Uint8List b) {
    if (b.isEmpty) return 'len=0';
    final step = math.max(1, b.length ~/ 100000);
    int minV = 255, maxV = 0, zeros = 0;
    double sum = 0;
    int n = 0;
    for (int i = 0; i < b.length; i += step) {
      final v = b[i];
      if (v < minV) minV = v;
      if (v > maxV) maxV = v;
      if (v == 0) zeros++;
      sum += v;
      n++;
    }
    final first = b.sublist(0, math.min(16, b.length));
    return 'len=${b.length} min=$minV max=$maxV mean=${_f1(sum / n)} '
        '%zero=${(100 * zeros / n).toStringAsFixed(1)} first='
        '${first.map((v) => v.toString()).join(',')}';
  }

  static double _spreadAround(Uint8List b, int center) {
    if (b.isEmpty) return 0;
    final step = math.max(1, b.length ~/ 50000);
    double s = 0;
    int n = 0;
    for (int i = 0; i < b.length; i += step) {
      final d = b[i] - center;
      s += d * d;
      n++;
    }
    return n == 0 ? 0 : math.sqrt(s / n);
  }

  static String _lumaNote(Uint8List b) {
    if (b.isEmpty) return 'empty';
    int minV = 255, maxV = 0;
    final step = math.max(1, b.length ~/ 50000);
    for (int i = 0; i < b.length; i += step) {
      final v = b[i];
      if (v < minV) minV = v;
      if (v > maxV) maxV = v;
    }
    if (maxV <= 16) return 'Y NEARLY BLACK (max=$maxV)';
    if (minV >= 16 && maxV <= 235) {
      return 'LIMITED range [16..235] (washed-out under full-range math)';
    }
    return 'FULL range [0..255]';
  }

  // -------------------------------------------------------------------------
  // Image dumps (frame 1 or first bright frame)
  // -------------------------------------------------------------------------
  static void dumpFrameImages({
    required Uint8List yPlane,
    required Uint8List uPlane,
    required Uint8List vPlane,
    required int srcWidth,
    required int srcHeight,
    required dynamic inputBuffer,
    required int dstWidth,
    required int dstHeight,
    required bool isNCHW,
    int yRowStride = 0,
    int yPixelStride = 1,
    int uRowStride = 0,
    int uPixelStride = 1,
    int vRowStride = 0,
    int vPixelStride = 1,
  }) {
    if (!enabled || !dumpImages) return;

    // frame_original.png — raw luma (Y plane) as grayscale.
    _writePng(
      'frame_original.png',
      _grayRgba(yPlane, srcWidth, srcHeight),
      srcWidth,
      srcHeight,
    );

    // frame_rgb.png — YUV→RGB at camera resolution (dump-only, same math).
    final rgb = _yuvToRgbRgba(
      yPlane,
      uPlane,
      vPlane,
      srcWidth,
      srcHeight,
      yRowStride: yRowStride,
      yPixelStride: yPixelStride,
      uRowStride: uRowStride,
      uPixelStride: uPixelStride,
      vRowStride: vRowStride,
      vPixelStride: vPixelStride,
    );
    _writePng('frame_rgb.png', rgb, srcWidth, srcHeight);

    // frame_rgb_nv21.png — same planes, V-led (NV21) interpretation. If THIS
    // looks correct and frame_rgb.png is color-swapped, the device is NV21
    // (converter currently assumes NV12/U-led).
    final rgbNv21 = _yuvToRgbRgba(
      yPlane,
      uPlane,
      vPlane,
      srcWidth,
      srcHeight,
      yRowStride: yRowStride,
      yPixelStride: yPixelStride,
      uRowStride: uRowStride,
      uPixelStride: uPixelStride,
      vRowStride: vRowStride,
      vPixelStride: vPixelStride,
      swapUV: true,
    );
    _writePng('frame_rgb_nv21.png', rgbNv21, srcWidth, srcHeight);

    // frame_resized.png — nearest-neighbor resize of the camera-res RGB.
    final resized = _resizeRgba(rgb, srcWidth, srcHeight, dstWidth, dstHeight);
    _writePng('frame_resized.png', resized, dstWidth, dstHeight);

    // frame_model_input.png — exactly what the model receives (normalized →
    // visualized back to 8-bit).
    final modelRgba = _modelInputRgba(inputBuffer, dstWidth, dstHeight, isNCHW);
    _writePng('frame_model_input.png', modelRgba, dstWidth, dstHeight);

    debugPrint('[Forensic] image dumps written to $runDirName');
  }

  static void _writePng(String name, Uint8List rgba, int w, int h) {
    try {
      final png = PngEncoder.encode(rgba: rgba, width: w, height: h);
      File(
        '$runDir${Platform.pathSeparator}$name',
      ).writeAsBytesSync(png, flush: true);
    } catch (e) {
      recordError('dump $name', e, null);
    }
  }

  static Uint8List _grayRgba(Uint8List y, int w, int h) {
    final rgba = Uint8List(w * h * 4);
    for (int i = 0; i < w * h; i++) {
      final v = y[i % y.length];
      final o = i * 4;
      rgba[o] = v;
      rgba[o + 1] = v;
      rgba[o + 2] = v;
      rgba[o + 3] = 255;
    }
    return rgba;
  }

  static Uint8List _yuvToRgbRgba(
    Uint8List y,
    Uint8List u,
    Uint8List v,
    int w,
    int h, {
    int yRowStride = 0,
    int yPixelStride = 1,
    int uRowStride = 0,
    int uPixelStride = 1,
    int vRowStride = 0,
    int vPixelStride = 1,
    bool swapUV = false,
  }) {
    final int yRow = yRowStride > 0 ? yRowStride : w;
    final int uRow = uRowStride > 0 ? uRowStride : (w + 1) ~/ 2;
    final bool planar = uPixelStride == 1 && vPixelStride == 1;

    final rgba = Uint8List(w * h * 4);
    for (int py = 0; py < h; py++) {
      for (int px = 0; px < w; px++) {
        final yi = py * w + px;
        final yv = y[(py * yRow + px * yPixelStride).clamp(0, y.length - 1)];
        final int cx = px ~/ 2;
        final int cy = py ~/ 2;
        final int uv_;
        final int vv;
        if (planar) {
          final idx = cx + uRow * cy;
          uv_ = u[idx.clamp(0, u.length - 1)] - 128;
          vv = v[idx.clamp(0, v.length - 1)] - 128;
        } else {
          final base = cx * uPixelStride + uRow * cy;
          if (swapUV) {
            // NV21 (V-led) interpretation: even index = V, odd index = U.
            vv = u[base.clamp(0, u.length - 1)] - 128;
            uv_ = u[(base + 1).clamp(0, u.length - 1)] - 128;
          } else {
            // NV12 (U-led) interpretation (YUV_420_888 contract).
            uv_ = u[base.clamp(0, u.length - 1)] - 128;
            vv = u[(base + 1).clamp(0, u.length - 1)] - 128;
          }
        }
        final r = (yv + vv * 1.402).round().clamp(0, 255);
        final g = (yv - uv_ * 0.344 - vv * 0.714).round().clamp(0, 255);
        final b = (yv + uv_ * 1.772).round().clamp(0, 255);
        final o = yi * 4;
        rgba[o] = r;
        rgba[o + 1] = g;
        rgba[o + 2] = b;
        rgba[o + 3] = 255;
      }
    }
    return rgba;
  }

  static Uint8List _resizeRgba(
    Uint8List rgba,
    int srcW,
    int srcH,
    int dstW,
    int dstH,
  ) {
    final out = Uint8List(dstW * dstH * 4);
    for (int y = 0; y < dstH; y++) {
      final sy = (y * srcH / dstH).round().clamp(0, srcH - 1);
      for (int x = 0; x < dstW; x++) {
        final sx = (x * srcW / dstW).round().clamp(0, srcW - 1);
        final si = (sy * srcW + sx) * 4;
        final oi = (y * dstW + x) * 4;
        out.setRange(oi, oi + 4, rgba, si);
      }
    }
    return out;
  }

  static Uint8List _modelInputRgba(dynamic buf, int w, int h, bool isNCHW) {
    final rgba = Uint8List(w * h * 4);
    for (int i = 0; i < w * h; i++) {
      int r, g, b;
      if (isNCHW) {
        r = (_at(buf, i) * 255).round().clamp(0, 255);
        g = (_at(buf, w * h + i) * 255).round().clamp(0, 255);
        b = (_at(buf, 2 * w * h + i) * 255).round().clamp(0, 255);
      } else {
        r = (_at(buf, i * 3) * 255).round().clamp(0, 255);
        g = (_at(buf, i * 3 + 1) * 255).round().clamp(0, 255);
        b = (_at(buf, i * 3 + 2) * 255).round().clamp(0, 255);
      }
      final o = i * 4;
      rgba[o] = r;
      rgba[o + 1] = g;
      rgba[o + 2] = b;
      rgba[o + 3] = 255;
    }
    return rgba;
  }

  // -------------------------------------------------------------------------
  // Small helpers
  // -------------------------------------------------------------------------
  static double _val(List out, int index, bool dequant, ModelMetadata m) {
    if (index < 0 || index >= out.length) return double.nan;
    final v = out[index].toDouble();
    return dequant ? (v - m.outputZeroPoint) * m.outputScale : v;
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

  static bool _containsNan(dynamic buf) {
    final n = _len(buf);
    for (int i = 0; i < n; i++) {
      if (_at(buf, i).isNaN) return true;
    }
    return false;
  }

  static bool _containsInf(dynamic buf) {
    final n = _len(buf);
    for (int i = 0; i < n; i++) {
      if (_at(buf, i).isInfinite) return true;
    }
    return false;
  }

  static Set<int> _sampleIndices(int n, int count) {
    if (n <= count) return Set.of(List.generate(n, (i) => i));
    final rng = math.Random(42);
    final out = <int>{};
    while (out.length < count) {
      out.add(rng.nextInt(n));
    }
    return out;
  }

  static void _pushTop(Set<_Top> top, double value, int index) {
    if (top.length < 20) {
      top.add(_Top(value, index));
      return;
    }
    final min = top.reduce((a, b) => a.value < b.value ? a : b);
    if (value > min.value) {
      top.remove(min);
      top.add(_Top(value, index));
    }
  }

  static String _fmt(List<double> values) =>
      values.map((v) => v.toStringAsFixed(3)).join(', ');

  static String _f(double v) =>
      v.isFinite ? v.toStringAsFixed(4) : v.toString();
  static String _f4(double v) =>
      v.isFinite ? v.toStringAsFixed(4) : v.toString();
  static String _f1(double v) =>
      v.isFinite ? v.toStringAsFixed(1) : v.toString();

  static String _timestamp() {
    final now = DateTime.now();
    String p(int v) => v.toString().padLeft(2, '0');
    return '${now.year}${p(now.month)}${p(now.day)}_'
        '${p(now.hour)}${p(now.minute)}${p(now.second)}';
  }
}

/// A single file channel. All writes are synchronous (flush per append) and
/// failure-proof.
class ForensicLogger {
  final String fileName;
  bool _closed = false;

  ForensicLogger(this.fileName);

  File get _file =>
      File('${ForensicLog.runDir}${Platform.pathSeparator}$fileName');

  void clear() {
    if (!ForensicLog.enabled || _closed) return;
    try {
      _file.writeAsStringSync('');
    } catch (_) {}
  }

  void append(String line) {
    if (!ForensicLog.enabled || _closed) return;
    try {
      _file.writeAsStringSync('$line\n', mode: FileMode.append, flush: true);
    } catch (_) {}
  }

  void close() {
    _closed = true;
  }
}

/// Accumulated statistics used by the auto-generated diagnosis.
class _Summary {
  int frames = 0;
  String? cameraFormat;
  bool? cameraMismatch;
  bool? cameraPass;
  bool preprocessPass = true;
  bool tensorPass = true;
  bool outputPass = true;
  double maxConf = 0.0;
  double p99 = 0.0;
  double globalMaxConf = 0.0;
  double lastLatencyMs = 0.0;
  int droppedFrames = 0;
  int detections = 0;
  String? topClass;
  String distribution = 'UNKNOWN';
}

class _Top {
  final double value;
  final int index;
  _Top(this.value, this.index);
}

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
