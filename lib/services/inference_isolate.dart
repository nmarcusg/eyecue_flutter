import 'dart:async';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Rect;
import 'dart:ui' show ImageByteFormat, instantiateImageCodec;
import 'package:flutter/foundation.dart' show ValueNotifier, debugPrint;
import 'package:flutter/services.dart' show rootBundle;
import 'package:tflite_flutter/tflite_flutter.dart';
import '../models/box_transform.dart';
import '../models/detection.dart';
import '../models/model_metadata.dart';
import '../models/model_config.dart';
import '../models/tensor_rotation.dart';
import '../models/tflite_flatbuffer.dart';
import 'forensic_log.dart'; // Structured file-based forensic logging
import 'input_probe.dart'; // TEMPORARY input-pipeline probe (test-image converter)

/// ---------------------------------------------------------------------------
/// InferenceService
///
/// Spawns a single persistent background isolate at startup. The isolate
/// holds the TFLite interpreter in memory forever, reuses pre-allocated
/// buffers, and processes camera frames on demand.
///
/// The isolate is **self-describing**: immediately after the interpreter is
/// created it introspects the runtime tensors (shapes, datatypes, quantization
/// params) plus the model buffer's internal tensor precision, and exposes a
/// [ModelMetadata] snapshot. All preprocessing/post-processing decisions are
/// driven by that metadata — nothing is hardcoded.
/// ---------------------------------------------------------------------------
class InferenceService {
  /// The asset path that is bundled and loaded at startup. The *reported*
  /// model name is derived from this path at runtime (basename); the runtime
  /// interpreter remains the single source of truth for everything else.
  static const String _modelAssetPath = EyeCueModelConfig.modelAssetPath;

  Isolate? _isolate;
  SendPort? _sendPort;
  ReceivePort? _receivePort;
  StreamSubscription<dynamic>? _receiveSubscription;
  bool _disposed = false;

  late StreamController<List<Detection>> _resultsController;
  Stream<List<Detection>> get resultsStream => _resultsController.stream;

  /// Stream of human-readable isolate error messages (for busy-gate recovery).
  final StreamController<String> _errorController =
      StreamController.broadcast();
  Stream<String> get errorStream => _errorController.stream;

  /// Runtime model metadata, populated when the isolate reports `model_loaded`.
  ModelMetadata? _modelMetadata;
  ModelMetadata? get modelMetadata => _modelMetadata;

  /// Reactive notifier so the UI (debug overlay) can react to metadata arrival.
  final ValueNotifier<ModelMetadata?> _metadataNotifier =
      ValueNotifier<ModelMetadata?>(null);
  ValueNotifier<ModelMetadata?> get metadataNotifier => _metadataNotifier;

  /// Per-frame inference latency in milliseconds, updated each time a
  /// result arrives from the isolate. Used by the debug overlay.
  double _lastLatencyMs = 0.0;
  double get lastLatencyMs => _lastLatencyMs;

  /// Frame number of the most recently processed result.
  int _lastFrameNumber = 0;
  int get lastFrameNumber => _lastFrameNumber;

  /// Counter for frames sent to the isolate (monotonically increasing).
  int _sentFrameCount = 0;

  /// TEMPORARY (Phase F): decoded test-image display data for the painter.
  /// Populated by [runTestImage]; only meaningful when [useTestImage].
  int _testImageWidth = 0;
  int _testImageHeight = 0;
  Uint8List? _testImageAssetBytes;
  int get testImageWidth => _testImageWidth;
  int get testImageHeight => _testImageHeight;
  Uint8List? get testImageAssetBytes => _testImageAssetBytes;

  /// TEMPORARY debug mode (Phase F): run ONE inference on a known-good RGB
  /// asset image instead of the camera stream, to isolate camera acquisition
  /// from the rest of the pipeline. The asset image is converted to I420 YUV
  /// planes (the same interface `CameraImage` exposes) and pushed through the
  /// EXACT same `processFrame()` path the camera uses (YUV→RGB → resize →
  /// normalize → run → parser → NMS → painter). Flip to `false` to restore the
  /// camera stream. Remove together with `assets/test_image.jpg`, its pubspec
  /// entry, and `InputProbe.rgbaToI420`.
  static const bool useTestImage = false;
  static const String testImageAsset = 'assets/test_image.jpg';

  /// Confidence threshold applied BEFORE Non-Maximum Suppression. Standard
  /// YOLOv8 inference uses conf 0.25 + NMS IoU 0.45 (the graph already
  /// sigmoids class scores to [0,1]).
  static const double kConfThreshold = EyeCueModelConfig.confidenceThreshold;

  /// IoU threshold for class-wise Non-Maximum Suppression.
  static const double kNmsIouThreshold = EyeCueModelConfig.nmsIouThreshold;

  final Completer<void> _ready = Completer<void>();
  Future<void> get _whenReady => _ready.future;

  Future<void> initIsolate() async {
    debugPrint('[Service] InferenceService.initIsolate() — spawning isolate…');
    _resultsController = StreamController.broadcast();
    final receivePort = ReceivePort();
    _receivePort = receivePort;

    // Create the forensic run directory (file-based diagnostics).
    final String? runDir = await ForensicLog.init();
    if (_disposed) {
      ForensicLog.finalize();
      receivePort.close();
      return;
    }

    final modelBytes = await _loadModel();
    if (_disposed) return;
    final labels = await _loadLabels();
    if (_disposed) return;

    final isolate = await Isolate.spawn(_isolateEntryPoint, [
      receivePort.sendPort,
      modelBytes,
      labels,
      _modelAssetPath,
      runDir,
    ]);
    if (_disposed) {
      isolate.kill(priority: Isolate.immediate);
      receivePort.close();
      return;
    }
    _isolate = isolate;

    _receiveSubscription = receivePort.listen((dynamic message) {
      if (_disposed) return;
      if (message is SendPort) {
        // --- Handshake: isolate is ready ---
        _sendPort = message;
        if (!_ready.isCompleted) {
          _ready.complete();
        }
        debugPrint('[Service] Isolate handshake complete — sendPort received');
      } else if (message is Map<String, dynamic> &&
          message['type'] == 'result') {
        // --- Inference result with metadata ---
        final detections = (message['detections'] as List).cast<Detection>();
        _lastLatencyMs = (message['latencyMs'] as num).toDouble();
        _lastFrameNumber = message['frameNumber'] as int;
        if (!_resultsController.isClosed) {
          _resultsController.add(detections);
        }
      } else if (message is Map<String, dynamic> &&
          message['type'] == 'error') {
        // --- Error from isolate ---
        debugPrint(
          '[Error] Isolate error: ${message['error']}\n'
          '${message['stackTrace']}',
        );
        if (!_errorController.isClosed) {
          _errorController.add(message['error'].toString());
        }
      } else if (message is Map<String, dynamic> &&
          message['type'] == 'model_loaded') {
        // --- Runtime model metadata from the isolate ---
        final metadata = ModelMetadata.fromJsonMap(
          (message['metadata'] as Map).cast<String, dynamic>(),
        );
        _modelMetadata = metadata;
        _metadataNotifier.value = metadata;
        debugPrint('[Service] Isolate reports model loaded successfully');
        _logModelSummary(metadata);
      }
    });
  }

  Future<Uint8List> _loadModel() async {
    debugPrint('[Model] Loading model from $_modelAssetPath…');
    try {
      final byteData = await rootBundle.load(_modelAssetPath);
      final bytes = byteData.buffer.asUint8List();
      debugPrint('[Model] Model loaded: ${bytes.length} bytes');
      return bytes;
    } catch (e, stack) {
      debugPrint('[Error] Failed to load model: $e');
      debugPrint('[Error] Stack: $stack');
      rethrow;
    }
  }

  Future<List<String>> _loadLabels() async {
    debugPrint('[Model] Loading labels from assets/labels.txt…');
    try {
      final byteData = await rootBundle.load(EyeCueModelConfig.labelsAssetPath);
      final text = String.fromCharCodes(byteData.buffer.asUint8List());
      final labels = text
          .split('\n')
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .toList();
      debugPrint('[Model] Labels loaded: ${labels.length} classes');
      return labels;
    } catch (e, stack) {
      debugPrint('[Error] Failed to load labels: $e');
      debugPrint('[Error] Stack: $stack');
      rethrow;
    }
  }

  bool processFrame({
    required Uint8List yPlane,
    required Uint8List uPlane,
    required Uint8List vPlane,
    required int width,
    required int height,
    double cameraFps = 0.0,
    int droppedFrames = 0,
    // Plane geometry (bytesPerRow / bytesPerPixel). 0/1 fall back to the
    // legacy tightly-packed assumptions inside the converter.
    int yRowStride = 0,
    int yPixelStride = 1,
    int uRowStride = 0,
    int uPixelStride = 1,
    int vRowStride = 0,
    int vPixelStride = 1,
    // Orientation metadata (device-independent; all derived from
    // CameraDescription.sensorOrientation + current device orientation + lens
    // direction by the caller). Defaults keep the static-image path at
    // rotation 0 / no mirror — i.e. the identity transform.
    int rotationDegrees = 0,
    bool mirror = false,
    int sensorOrientation = -1,
    int deviceDegrees = 0,
    String lensFacing = 'back',
  }) {
    final sendPort = _sendPort;
    if (_disposed || sendPort == null) return false;
    _sentFrameCount++;
    sendPort.send({
      'y': yPlane,
      'u': uPlane,
      'v': vPlane,
      'width': width,
      'height': height,
      'frameNumber': _sentFrameCount,
      // For forensic performance logging only — does not affect inference.
      'cameraFps': cameraFps,
      'droppedFrames': droppedFrames,
      // Plane geometry for the converter (padding + interleave aware).
      'yRowStride': yRowStride,
      'yPixelStride': yPixelStride,
      'uRowStride': uRowStride,
      'uPixelStride': uPixelStride,
      'vRowStride': vRowStride,
      'vPixelStride': vPixelStride,
      // Orientation (see BoxTransform).
      'rotationDegrees': rotationDegrees,
      'mirror': mirror,
      'sensorOrientation': sensorOrientation,
      'deviceDegrees': deviceDegrees,
      'lensFacing': lensFacing,
    });
    return true;
  }

  /// TEMPORARY (Phase F): decode a known-good RGB asset image, convert it to
  /// I420 YUV planes (the same interface `CameraImage` exposes), and push it
  /// through the EXACT same `processFrame()` path as the camera. Everything
  /// downstream — `_convertYUV420toRGB`, resize, normalization,
  /// `interpreter.run()`, `_parseYolov8Output` (threshold + NMS) — is reused
  /// byte-for-byte. The only difference is the image source.
  ///
  /// The decoded asset bytes + dimensions are also exposed for the camera
  /// screen so the test image can be displayed with boxes overlaid exactly as
  /// the camera preview would.
  Future<void> runTestImage() async {
    debugPrint('[Service] runTestImage() — loading $testImageAsset');
    try {
      await _whenReady;
      final byteData = await rootBundle.load(testImageAsset);
      final assetBytes = byteData.buffer.asUint8List();

      final codec = await instantiateImageCodec(assetBytes);
      final frame = await codec.getNextFrame();
      final image = frame.image;
      final w = image.width;
      final h = image.height;
      final rgbaData = await image.toByteData(format: ImageByteFormat.rawRgba);
      image.dispose();
      codec.dispose();
      final rgba = rgbaData!.buffer.asUint8List();
      debugPrint(
        '[Service] Test image decoded: ${w}x$h rgba=${rgba.length} bytes',
      );

      // Expose display data for the screen (image + dims for the painter).
      _testImageWidth = w;
      _testImageHeight = h;
      _testImageAssetBytes = assetBytes;

      // Source adapter: RGB → I420 planes (the same YUV_420_888 interface the
      // camera produces). NO preprocessing is duplicated here.
      final planes = InputProbe.rgbaToI420(rgba, w, h);
      debugPrint(
        '[Service] Test image → I420 planes: '
        'y=${planes.y.length} u=${planes.u.length} v=${planes.v.length}',
      );

      // Same entry point as the camera — identical pipeline after this call.
      processFrame(
        yPlane: planes.y,
        uPlane: planes.u,
        vPlane: planes.v,
        width: w,
        height: h,
        cameraFps: 0.0,
        droppedFrames: 0,
        // Tightly packed I420 (rowStride == width, pixelStride == 1).
        yRowStride: w,
        yPixelStride: 1,
        uRowStride: (w + 1) ~/ 2,
        uPixelStride: 1,
        vRowStride: (w + 1) ~/ 2,
        vPixelStride: 1,
      );
      debugPrint(
        '[Service] Test image sent via processFrame() — '
        'pipeline identical to camera stream',
      );
    } catch (e, stack) {
      debugPrint('[Error] Test image failed: $e');
      debugPrint('[Error] Stack: $stack');
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    debugPrint('[Service] InferenceService.dispose() — killing isolate');
    ForensicLog.finalize();
    _receiveSubscription?.cancel();
    _receivePort?.close();
    _isolate?.kill(priority: Isolate.immediate);
    if (!_resultsController.isClosed) _resultsController.close();
    if (!_errorController.isClosed) _errorController.close();
    _metadataNotifier.dispose();
    debugPrint('[Service] InferenceService disposed');
  }

  // =========================================================================
  // ISOLATE ENTRY POINT
  // =========================================================================
  static void _isolateEntryPoint(List<dynamic> args) {
    final SendPort mainSendPort = args[0] as SendPort;
    final Uint8List modelBytes = args[1] as Uint8List;
    final List<String> labels = (args[2] as List<dynamic>).cast<String>();
    final String modelName =
        (args.length > 3 ? args[3] as String : 'unknown.tflite')
            .split('/')
            .last;
    if (args.length > 4 && args[4] is String) {
      ForensicLog.setRunDir(args[4] as String);
    }

    final isolateReceivePort = ReceivePort();
    mainSendPort.send(isolateReceivePort.sendPort);

    // --- 1. Create interpreter (explicit XNNPACK first) ---
    // Null options through the public API are ABI-safe. Do not instantiate
    // XNNPackDelegateOptions: its generated layout is stale in version 0.12.1.
    //
    // The delegate is deliberately retained in this scope for the lifetime of
    // the interpreter. The native binding documents that the caller owns the
    // delegate and must keep it alive while the interpreter uses it.
    Interpreter? interpreter;
    XNNPackDelegate? xnnDelegate;
    try {
      debugPrint(
        '[Model] Creating explicit XNNPACK delegate (native null-options)',
      );
      xnnDelegate = XNNPackDelegate();
      debugPrint('[Model] Explicit XNNPACK delegate created');
      final options = InterpreterOptions()
        ..threads = 4
        ..addDelegate(xnnDelegate);
      try {
        interpreter = Interpreter.fromBuffer(modelBytes, options: options);
      } finally {
        options.delete();
      }
      debugPrint(
        '[Model] Interpreter created successfully (threads=4, explicit XNNPACK)',
      );
    } catch (e, stack) {
      debugPrint('[Warn] XNNPACK interpreter setup failed: $e');
      debugPrint('[Warn] Stack: $stack');

      // A failed interpreter construction does not transfer ownership of the
      // delegate. Delete it before retrying with the stable CPU path.
      try {
        interpreter?.close();
      } catch (closeError) {
        debugPrint(
          '[Warn] Failed to close partial XNNPACK interpreter: $closeError',
        );
      }
      try {
        xnnDelegate?.delete();
      } catch (deleteError) {
        debugPrint('[Warn] Failed to delete XNNPACK delegate: $deleteError');
      }
      xnnDelegate = null;
      interpreter = null;

      try {
        final fallbackOptions = InterpreterOptions()..threads = 4;
        try {
          interpreter = Interpreter.fromBuffer(
            modelBytes,
            options: fallbackOptions,
          );
        } finally {
          fallbackOptions.delete();
        }
        debugPrint(
          '[Model] Interpreter created successfully (threads=4, CPU fallback)',
        );
      } catch (fallbackError, fallbackStack) {
        debugPrint(
          '[Error] CPU fallback interpreter creation failed: $fallbackError',
        );
        debugPrint('[Error] Stack: $fallbackStack');
        mainSendPort.send({
          'type': 'error',
          'error': 'Interpreter creation failed: $fallbackError',
          'stackTrace': fallbackStack.toString(),
        });
        return; // Cannot proceed without an interpreter
      }
    }

    // --- 2. Runtime model introspection (single source of truth) ---
    final ModelMetadata metadata;
    try {
      metadata = ModelMetadata.inspect(
        modelName: modelName,
        inputTensor: interpreter.getInputTensor(0),
        outputTensor: interpreter.getOutputTensor(0),
        modelBytes: modelBytes,
      );
    } catch (e, stack) {
      debugPrint('[Error] Failed to introspect model metadata: $e');
      debugPrint('[Error] Stack: $stack');
      try {
        interpreter.close();
      } catch (closeError) {
        debugPrint(
          '[Warn] Failed to close interpreter after introspection error: $closeError',
        );
      }
      try {
        xnnDelegate?.delete();
      } catch (deleteError) {
        debugPrint('[Warn] Failed to delete XNNPACK delegate: $deleteError');
      }
      mainSendPort.send({
        'type': 'error',
        'error': 'Model introspection failed: $e',
        'stackTrace': stack.toString(),
      });
      return;
    }

    // --- 3. Startup diagnostic report ---
    _logModelStartupReport(metadata);

    // Notify main isolate (full metadata + legacy string fields).
    mainSendPort.send({
      'type': 'model_loaded',
      'metadata': metadata.toJsonMap(),
      'inputShape': metadata.inputShape.toString(),
      'inputType': metadata.inputType.toString(),
      'outputShape': metadata.outputShape.toString(),
      'outputType': metadata.outputType.toString(),
    });

    // Determine NHWC vs NCHW from shape.
    // NHWC: [1, H, W, 3]  → shape[3] == 3
    // NCHW: [1, 3, H, W]  → shape[1] == 3
    final bool isNCHW =
        (metadata.inputShape.length == 4 && metadata.inputShape[1] == 3);
    final int modelH = isNCHW ? metadata.inputShape[2] : metadata.inputShape[1];
    final int modelW = isNCHW ? metadata.inputShape[3] : metadata.inputShape[2];

    // --- 4. Allocate buffers with the CORRECT dtype (from runtime metadata) ---
    final dynamic inputBuffer = _allocateInputBuffer(metadata);
    final dynamic outputBuffer = _allocateOutputBuffer(metadata);

    // --- 5. Frame processing loop ---
    var frame1Logged = false;
    var brightFrameDumped = false;
    var receivedCount = 0;
    var processedCount = 0;
    var xnnpackFallbackAttempted = false;
    isolateReceivePort.listen((dynamic data) {
      try {
        receivedCount++;
        if (data is Map<String, dynamic>) {
          // NOTE: the test image arrives here via the NORMAL frame message
          // (processFrame) — the same code path as the camera. There is no
          // separate test-image branch; the only difference is the source.
          final Uint8List yBytes = data['y'] as Uint8List;
          final Uint8List uBytes = data['u'] as Uint8List;
          final Uint8List vBytes = data['v'] as Uint8List;
          final int srcWidth = data['width'] as int;
          final int srcHeight = data['height'] as int;
          final int frameNumber = (data['frameNumber'] as int?) ?? 0;
          final int yRowStride = (data['yRowStride'] as int?) ?? 0;
          final int yPixelStride = (data['yPixelStride'] as int?) ?? 1;
          final int uRowStride = (data['uRowStride'] as int?) ?? 0;
          final int uPixelStride = (data['uPixelStride'] as int?) ?? 1;
          final int vRowStride = (data['vRowStride'] as int?) ?? 0;
          final int vPixelStride = (data['vPixelStride'] as int?) ?? 1;

          // -- YUV420 → RGB (dynamically typed, metadata-driven) --
          _convertYUV420toRGB(
            yBytes,
            uBytes,
            vBytes,
            srcWidth,
            srcHeight,
            modelH,
            modelW,
            isNCHW,
            inputBuffer,
            metadata,
            yRowStride: yRowStride,
            yPixelStride: yPixelStride,
            uRowStride: uRowStride,
            uPixelStride: uPixelStride,
            vRowStride: vRowStride,
            vPixelStride: vPixelStride,
          );

          // -- Orientation: rotate + mirror the input tensor to UPRIGHT --
          // The model/parser/NMS code is unchanged; this is the single
          // canonical orientation step. Reading the sensor frame unrotated in
          // portrait would show the model a 90°-rotated scene (proven: 0
          // detections). Rotating the 640×640 NHWC tensor to upright makes
          // the model see the physical scene upright, so portrait detection
          // quality matches landscape. Boxes after NMS are then already in
          // upright space and the painter consumes them directly.
          final int rotationDegrees = (data['rotationDegrees'] as int?) ?? 0;
          final bool mirror = (data['mirror'] as bool?) ?? false;
          if (rotationDegrees != 0 || mirror) {
            _rotateInputBuffer(
              inputBuffer,
              rotationDegrees,
              mirror,
              modelH,
              modelW,
              isNCHW,
            );
          }
          final uprightDims = BoxTransform.uprightDims(
            w: srcWidth,
            h: srcHeight,
            rotationDegrees: rotationDegrees,
          );
          _safeForensic(
            () => ForensicLog.recordOrientation(
              frame: frameNumber,
              sensorOrientation: (data['sensorOrientation'] as int?) ?? -1,
              deviceDegrees: (data['deviceDegrees'] as int?) ?? 0,
              rotationDegrees: rotationDegrees,
              mirror: mirror,
              lensFacing: (data['lensFacing'] as String?) ?? 'back',
              inW: srcWidth,
              inH: srcHeight,
              outW: uprightDims.w,
              outH: uprightDims.h,
            ),
            'orientation',
          );

          // -- Forensic logging (frame 1 + first "bright" frame) --
          // Frame-1 dumps are frequently unusable: in prior camera runs the
          // frame-1 input was near-black (lens covered / auto-exposure not yet
          // settled / phone on table). To analyze a REAL scene we also dump the
          // FIRST frame whose input tensor is non-trivial (mean > 0.1) — this
          // is when the user is actually pointing the camera at objects.
          final bool isFrame1 = !frame1Logged;
          final bool isBright = _inputMean(inputBuffer, metadata) > 0.1;
          final bool dumpNow = isFrame1 || (isBright && !brightFrameDumped);
          if (dumpNow && !isFrame1) brightFrameDumped = true;
          if (dumpNow) {
            _safeForensic(() {
              ForensicLog.recordPreprocess(
                input: inputBuffer,
                m: metadata,
                isNCHW: isNCHW,
                frame: frameNumber,
                srcWidth: srcWidth,
                srcHeight: srcHeight,
                dstWidth: modelW,
                dstHeight: modelH,
              );
              ForensicLog.recordTensor(
                input: inputBuffer,
                m: metadata,
                frame: frameNumber,
              );
              ForensicLog.recordPlaneStats(
                y: yBytes,
                u: uBytes,
                v: vBytes,
                frame: frameNumber,
                yRowStride: yRowStride,
                yPixelStride: yPixelStride,
                uRowStride: uRowStride,
                uPixelStride: uPixelStride,
                vRowStride: vRowStride,
                vPixelStride: vPixelStride,
              );
              ForensicLog.dumpFrameImages(
                yPlane: yBytes,
                uPlane: uBytes,
                vPlane: vBytes,
                srcWidth: srcWidth,
                srcHeight: srcHeight,
                inputBuffer: inputBuffer,
                dstWidth: modelW,
                dstHeight: modelH,
                isNCHW: isNCHW,
                yRowStride: yRowStride,
                yPixelStride: yPixelStride,
                uRowStride: uRowStride,
                uPixelStride: uPixelStride,
                vRowStride: vRowStride,
                vPixelStride: vPixelStride,
              );
            }, 'preprocess/tensor/planes/dump');
          }

          // -- INFERENCE (timed) --
          // Raw bytes are passed directly (ByteBuffer): tflite_flutter skips
          // shape inference/resizing for ByteBuffer input and copies bytes
          // verbatim. No reshape is required — the buffer already has the
          // exact row-major element count of the model input.
          final inputForRun = _prepareInputForRun(inputBuffer, metadata);

          var backend = xnnDelegate == null ? 'CPU' : 'XNNPACK';
          var stopwatch = Stopwatch()..start();
          try {
            interpreter!.run(inputForRun, outputBuffer.buffer);
          } catch (e) {
            // A Dart-level delegate invocation failure can be recovered by
            // replacing the interpreter with the CPU path. A native SIGSEGV
            // cannot be caught here; the device-specific XNNPACK crash risk
            // remains an on-device validation concern.
            var recoveredOnCpu = false;
            if (xnnDelegate != null && !xnnpackFallbackAttempted) {
              xnnpackFallbackAttempted = true;
              stopwatch.stop();
              debugPrint('[Warn] XNNPACK invocation failed: $e');
              debugPrint(
                '[Warn] Retrying this frame and subsequent frames on CPU',
              );
              try {
                interpreter!.close();
              } catch (closeError) {
                debugPrint(
                  '[Warn] Failed to close XNNPACK interpreter: $closeError',
                );
              }
              try {
                xnnDelegate!.delete();
              } catch (deleteError) {
                debugPrint(
                  '[Warn] Failed to delete XNNPACK delegate: $deleteError',
                );
              }
              xnnDelegate = null;
              try {
                final fallbackOptions = InterpreterOptions()..threads = 4;
                try {
                  interpreter = Interpreter.fromBuffer(
                    modelBytes,
                    options: fallbackOptions,
                  );
                } finally {
                  fallbackOptions.delete();
                }
                debugPrint(
                  '[Model] CPU fallback activated after XNNPACK invocation failure',
                );
                backend = 'CPU-fallback';
                stopwatch = Stopwatch()..start();
                interpreter!.run(inputForRun, outputBuffer.buffer);
                recoveredOnCpu = true;
              } catch (fallbackError, fallbackStack) {
                debugPrint(
                  '[Error] CPU fallback after XNNPACK invocation failed: '
                  '$fallbackError',
                );
                debugPrint('[Error] Stack: $fallbackStack');
                mainSendPort.send({
                  'type': 'error',
                  'error':
                      'CPU fallback after XNNPACK failure failed: '
                      '$fallbackError',
                  'stackTrace': fallbackStack.toString(),
                });
                return;
              }
            }
            if (!recoveredOnCpu) {
              stopwatch.stop();
              rethrow;
            }
          }
          stopwatch.stop();
          final double latencyMs = stopwatch.elapsedMicroseconds / 1000.0;
          debugPrint(
            '[Inference] Frame #$frameNumber completed | '
            'backend=$backend | '
            'duration=${latencyMs.toStringAsFixed(1)} ms',
          );

          // -- POST-PROCESS: Argmax per box (metadata-driven dequantization) --
          final parseableOutput = _outputForParser(outputBuffer, metadata);

          if (dumpNow) {
            _safeForensic(
              () => ForensicLog.recordOutput(
                parseable: parseableOutput,
                m: metadata,
                frame: frameNumber,
                labels: labels,
              ),
              'output',
            );
          }

          final parsed = _parseYolov8Output(
            parseableOutput,
            metadata.anchors,
            metadata.classes,
            kConfThreshold, // confidence threshold (pre-NMS)
            labels,
            metadata.requiresOutputDequantization,
            metadata.outputScale,
            metadata.outputZeroPoint,
          );
          final detections = parsed.detections;
          final preNmsCount = parsed.preNmsCount;

          // --- Detection logging (classes, confidences, boxes, pre/post-NMS) ---
          _logDetections(
            detections,
            frameNumber,
            latencyMs,
            modelH,
            modelW,
            isNCHW: isNCHW,
            preNmsCount: preNmsCount,
          );

          // -- Forensic logging (every frame + parser on dumped frames) --
          // Per-frame raw-luma mean makes input brightness over time visible
          // (is the camera black the whole time, or does it recover?).
          final double yMean = _yPlaneMean(
            yBytes,
            yRowStride > 0 ? yRowStride : srcWidth,
            srcWidth,
            srcHeight,
          );
          _safeForensic(
            () => ForensicLog.recordPerformance(
              frame: frameNumber,
              latencyMs: latencyMs,
              cameraFps: (data['cameraFps'] as num?)?.toDouble() ?? 0.0,
              droppedFrames: (data['droppedFrames'] as int?) ?? 0,
              queueDepth: receivedCount - processedCount,
              detections: detections.length,
              parseable: parseableOutput,
              m: metadata,
              yMean: yMean,
            ),
            'performance',
          );
          _safeForensic(ForensicLog.tickProcessedFrame, 'summary-tick');
          if (dumpNow) {
            _safeForensic(
              () => ForensicLog.recordParser(
                parseable: parseableOutput,
                m: metadata,
                frame: frameNumber,
                labels: labels,
                // After confidence threshold, BEFORE NMS (exact pre-NMS count).
                detectionsAfterThreshold: preNmsCount,
              ),
              'parser',
            );
          }
          if (isFrame1) frame1Logged = true;
          processedCount++;

          // Send result with metadata back to main isolate
          mainSendPort.send({
            'type': 'result',
            'detections': detections,
            'latencyMs': latencyMs,
            'frameNumber': frameNumber,
          });
        }
      } catch (e, stack) {
        debugPrint('[Error] Exception in isolate frame loop: $e');
        debugPrint('[Error] Stack: $stack');
        _safeForensic(
          () => ForensicLog.recordError('frame-loop', e, stack),
          'error',
        );
        try {
          mainSendPort.send({
            'type': 'error',
            'error': e.toString(),
            'stackTrace': stack.toString(),
          });
        } catch (_) {
          // Main isolate may have died; nothing more we can do
        }
      }
    });
  }

  /// Runs a forensic-logging closure and swallows any failure so diagnostics
  /// can never break inference. Failures are recorded in errors.txt.
  static void _safeForensic(void Function() fn, String where) {
    try {
      fn();
    } catch (e, st) {
      debugPrint('[Forensic] error in $where: $e');
      try {
        ForensicLog.recordError(where, e, st);
      } catch (_) {
        // Logging failed too — nothing more we can do.
      }
    }
  }

  // =========================================================================
  // Dtype-aware buffer allocation (driven by runtime metadata)
  // =========================================================================

  /// Allocates the input buffer as the exact typed list matching the model's
  /// input tensor type. FLOAT16 keeps a Float32List (normalized floats) which
  /// is converted to half bytes at the run boundary.
  static dynamic _allocateInputBuffer(ModelMetadata metadata) {
    final int count = ModelMetadata.elementCount(metadata.inputShape);
    switch (metadata.inputType) {
      case TensorType.float32:
        return Float32List(count);
      case TensorType.float64:
        return Float64List(count);
      case TensorType.float16:
        return Float32List(count); // normalized floats; converted before run
      case TensorType.int8:
        return Int8List(count);
      case TensorType.uint8:
        return Uint8List(count);
      case TensorType.int16:
        return Int16List(count);
      default:
        throw UnsupportedError(
          'Input tensor type ${metadata.inputType} is not supported',
        );
    }
  }

  /// Allocates the output buffer as the exact typed list matching the model's
  /// output tensor type. FLOAT16 keeps raw half bytes (2 bytes/element).
  static dynamic _allocateOutputBuffer(ModelMetadata metadata) {
    final int count = ModelMetadata.elementCount(metadata.outputShape);
    switch (metadata.outputType) {
      case TensorType.float32:
        return Float32List(count);
      case TensorType.float64:
        return Float64List(count);
      case TensorType.float16:
        return Uint8List(count * 2); // raw half bytes; converted for parser
      case TensorType.int8:
        return Int8List(count);
      case TensorType.uint8:
        return Uint8List(count);
      case TensorType.int16:
        return Int16List(count);
      default:
        throw UnsupportedError(
          'Output tensor type ${metadata.outputType} is not supported',
        );
    }
  }

  /// Returns the raw [ByteBuffer] to hand to `interpreter.run()`. For FLOAT16
  /// input the normalized Float32List is converted to half-precision bytes.
  static ByteBuffer _prepareInputForRun(
    dynamic inputBuffer,
    ModelMetadata metadata,
  ) {
    if (metadata.inputType == TensorType.float16) {
      return float32ListToFloat16Bytes(inputBuffer as Float32List).buffer;
    }
    return (inputBuffer as TypedData).buffer;
  }

  /// Returns the buffer in a form the parser can read (always a [List]).
  /// FLOAT16 output bytes are expanded to Float32List first.
  static List _outputForParser(dynamic outputBuffer, ModelMetadata metadata) {
    if (metadata.outputType == TensorType.float16) {
      return float16BytesToFloat32List(outputBuffer as Uint8List);
    }
    return outputBuffer as List;
  }

  // =========================================================================
  // Debug: Log detection details
  // =========================================================================
  /// Subsampled mean of the input tensor (normalized [0,1]). Used ONLY as a
  /// log-only trigger to decide whether a frame is "bright" enough to dump
  /// full forensics (frame-1 dumps are often black while the lens is covered /
  /// auto-exposure settles).
  static double _inputMean(dynamic input, ModelMetadata metadata) {
    final int n;
    if (input is Float32List) {
      n = input.length;
    } else if (input is Float64List) {
      n = input.length;
    } else if (input is Int8List) {
      n = input.length;
    } else if (input is Uint8List) {
      n = input.length;
    } else if (input is Int16List) {
      n = input.length;
    } else {
      return 0;
    }
    if (n == 0) return 0;
    final step = math.max(1, n ~/ 4096);
    double sum = 0;
    int cnt = 0;
    for (int i = 0; i < n; i += step) {
      final v = input[i].toDouble();
      if (v.isFinite) {
        sum += v;
        cnt++;
      }
    }
    return cnt == 0 ? 0 : sum / cnt;
  }

  /// Subsampled mean of the raw Y-luma plane (stride-aware). Logged per frame
  /// in performance.txt so input brightness over time is visible (log-only).
  static double _yPlaneMean(Uint8List y, int rowStride, int w, int h) {
    final row = rowStride > 0 ? rowStride : w;
    double sum = 0;
    int cnt = 0;
    for (int yy = 0; yy < h; yy += 8) {
      for (int xx = 0; xx < w; xx += 8) {
        final idx = yy * row + xx;
        if (idx >= 0 && idx < y.length) {
          sum += y[idx];
          cnt++;
        }
      }
    }
    return cnt == 0 ? 0 : sum / cnt;
  }

  /// Rotates (and optionally X-mirrors, for the front camera) the input tensor
  /// in place so the model sees the scene UPRIGHT. Layout-aware: delegates to
  /// [rotateInputTensor], which handles both NHWC (interleaved) and NCHW
  /// (planar) square tensors. This is the ONLY code that changes what pixels
  /// the model sees; converter/parser/NMS are untouched.
  static void _rotateInputBuffer(
    dynamic input,
    int degrees,
    bool mirror,
    int modelH,
    int modelW,
    bool isNCHW,
  ) {
    if (modelH != modelW || modelH <= 0) {
      debugPrint(
        '[Orient] Input not square ($modelH×$modelW) — '
        'orientation rotation skipped',
      );
      return;
    }
    rotateInputTensor(input, degrees, mirror, modelH, modelW, isNCHW: isNCHW);
  }

  static void _logDetections(
    List<Detection> detections,
    int frameNumber,
    double latencyMs,
    int modelH,
    int modelW, {
    required bool isNCHW,
    int preNmsCount = -1,
  }) {
    final String nmsSummary = preNmsCount >= 0
        ? 'candidates(before NMS)=$preNmsCount → after NMS=${detections.length}'
        : 'after NMS=${detections.length}';
    if (detections.isEmpty) {
      debugPrint('[Detection] Frame #$frameNumber | Objects: 0 ($nmsSummary)');
      return;
    }

    final buf = StringBuffer();
    buf.writeln(
      '[Detection] Frame #$frameNumber | Objects: ${detections.length} '
      '($nmsSummary)',
    );
    for (int i = 0; i < detections.length; i++) {
      final d = detections[i];
      buf.writeln('  ${i + 1}.');
      buf.writeln('     Label     : ${d.label}');
      buf.writeln(
        '     Confidence: ${(d.confidence * 100).toStringAsFixed(1)}%',
      );
      buf.writeln('     Box (norm):');
      buf.writeln('       left  =${d.box.left.toStringAsFixed(3)}');
      buf.writeln('       top   =${d.box.top.toStringAsFixed(3)}');
      buf.writeln('       width =${d.box.width.toStringAsFixed(3)}');
      buf.writeln('       height=${d.box.height.toStringAsFixed(3)}');
    }
    buf.write(
      '[Inference]  Frame #$frameNumber | Duration: ${latencyMs.toStringAsFixed(1)} ms | '
      'Input: ${isNCHW ? '[1,3,$modelH,$modelW]' : '[1,$modelH,$modelW,3]'}',
    );

    debugPrint(buf.toString());
  }

  // =========================================================================
  // YUV420 → RGB (dynamically typed, metadata-driven)
  //
  // Supports:
  //   * chroma layouts: planar I420 (pixelStride 1) and semi-planar NV12/NV21
  //     (pixelStride 2, interleaved chroma — per the YUV_420_888 contract
  //     plane[1] carries the first chroma component (U) at even indices and
  //     plane[2] is the same buffer shifted by one byte);
  //   * padding-aware sampling via the real per-plane rowStride/pixelStride
  //     (bytesPerRow / bytesPerPixel);
  //   * NHWC (interleaved RGB) and NCHW (planar RGB) layouts;
  //   * float (normalized [0,1]) and quantized (int8/uint8/int16, via the
  //     model's input scale/zeroPoint) input tensors.
  //
  // Resize (nearest-neighbor) and normalization math are unchanged.
  // =========================================================================
  static void _convertYUV420toRGB(
    Uint8List yPlane,
    Uint8List uPlane,
    Uint8List vPlane,
    int srcWidth,
    int srcHeight,
    int dstHeight,
    int dstWidth,
    bool isNCHW,
    dynamic output,
    ModelMetadata metadata, {
    int yRowStride = 0,
    int yPixelStride = 1,
    int uRowStride = 0,
    int uPixelStride = 1,
    int vRowStride = 0,
    int vPixelStride = 1,
  }) {
    // Fall back to legacy tightly-packed assumptions when geometry is absent.
    final int yRow = yRowStride > 0 ? yRowStride : srcWidth;
    final int uRow = uRowStride > 0 ? uRowStride : (srcWidth + 1) ~/ 2;

    // Chroma layout: planar when both chroma planes are 1-byte-per-sample;
    // otherwise semi-planar interleaved (U and V at adjacent bytes).
    // 4:2:0 chroma planes share the same rowStride, so uRow is used for both.
    final bool planarChroma = uPixelStride == 1 && vPixelStride == 1;
    final int chromaRowStride = uRow;

    final bool isFloatBuffer = output is Float32List || output is Float64List;
    final bool isInt8Buffer = output is Int8List;
    final bool isUint8Buffer = output is Uint8List;
    final bool isInt16Buffer = output is Int16List;

    int pixelIndex = 0;

    for (int y = 0; y < dstHeight; y++) {
      final int srcY = (y * srcHeight / dstHeight).round().clamp(
        0,
        srcHeight - 1,
      );

      for (int x = 0; x < dstWidth; x++) {
        final int srcX = (x * srcWidth / dstWidth).round().clamp(
          0,
          srcWidth - 1,
        );

        // Y sample — honor the real rowStride (padding-aware).
        final int yVal =
            yPlane[(srcY * yRow + srcX * yPixelStride).clamp(
              0,
              yPlane.length - 1,
            )];

        // Chroma sample at (srcX/2, srcY/2).
        final int cx = srcX ~/ 2;
        final int cy = srcY ~/ 2;
        final int uVal;
        final int vVal;
        if (planarChroma) {
          // Planar I420: separate U and V planes, tightly packed.
          final int idx = cx + chromaRowStride * cy;
          uVal = uPlane[idx.clamp(0, uPlane.length - 1)] - 128;
          vVal = vPlane[idx.clamp(0, vPlane.length - 1)] - 128;
        } else {
          // Semi-planar interleaved chroma (NV12/NV21). Per the YUV_420_888
          // contract, plane[1] is U-led: U at even indices, V at odd indices
          // of the shared chroma buffer. (A genuine NV21 device would place V
          // first — swap the two reads to support it.)
          final int base = cx * uPixelStride + chromaRowStride * cy;
          uVal = uPlane[base.clamp(0, uPlane.length - 1)] - 128;
          vVal = uPlane[(base + 1).clamp(0, uPlane.length - 1)] - 128;
        }

        final int r = (yVal + vVal * 1.402).round().clamp(0, 255);
        final int g = (yVal - uVal * 0.344 - vVal * 0.714).round().clamp(
          0,
          255,
        );
        final int b = (yVal + uVal * 1.772).round().clamp(0, 255);

        if (isNCHW) {
          // NCHW layout: [R plane, G plane, B plane]
          final int rIdx = 0 * dstHeight * dstWidth + y * dstWidth + x;
          final int gIdx = 1 * dstHeight * dstWidth + y * dstWidth + x;
          final int bIdx = 2 * dstHeight * dstWidth + y * dstWidth + x;

          _writeChannel(
            output,
            rIdx,
            r,
            metadata,
            isFloatBuffer,
            isInt8Buffer,
            isUint8Buffer,
            isInt16Buffer,
          );
          _writeChannel(
            output,
            gIdx,
            g,
            metadata,
            isFloatBuffer,
            isInt8Buffer,
            isUint8Buffer,
            isInt16Buffer,
          );
          _writeChannel(
            output,
            bIdx,
            b,
            metadata,
            isFloatBuffer,
            isInt8Buffer,
            isUint8Buffer,
            isInt16Buffer,
          );
        } else {
          // NHWC layout: interleaved [R, G, B, R, G, B, ...]
          _writeChannel(
            output,
            pixelIndex++,
            r,
            metadata,
            isFloatBuffer,
            isInt8Buffer,
            isUint8Buffer,
            isInt16Buffer,
          );
          _writeChannel(
            output,
            pixelIndex++,
            g,
            metadata,
            isFloatBuffer,
            isInt8Buffer,
            isUint8Buffer,
            isInt16Buffer,
          );
          _writeChannel(
            output,
            pixelIndex++,
            b,
            metadata,
            isFloatBuffer,
            isInt8Buffer,
            isUint8Buffer,
            isInt16Buffer,
          );
        }
      }
    }
  }

  /// Writes one RGB channel into the typed input buffer:
  /// * float buffer → normalized [0,1]
  /// * int8/uint8/int16 buffer → quantized using input scale/zeroPoint
  static void _writeChannel(
    dynamic output,
    int index,
    int rgb,
    ModelMetadata metadata,
    bool isFloatBuffer,
    bool isInt8Buffer,
    bool isUint8Buffer,
    bool isInt16Buffer,
  ) {
    if (isFloatBuffer) {
      output[index] = rgb / 255.0;
    } else if (isInt8Buffer) {
      output[index] = _quantize(
        rgb / 255.0,
        metadata.inputScale,
        metadata.inputZeroPoint,
        -128,
        127,
      );
    } else if (isUint8Buffer) {
      output[index] = _quantize(
        rgb / 255.0,
        metadata.inputScale,
        metadata.inputZeroPoint,
        0,
        255,
      );
    } else if (isInt16Buffer) {
      output[index] = _quantize(
        rgb / 255.0,
        metadata.inputScale,
        metadata.inputZeroPoint,
        -32768,
        32767,
      );
    } else {
      throw UnsupportedError(
        'Input buffer type ${output.runtimeType} is not supported',
      );
    }
  }

  /// Quantizes a normalized [0,1] value using the model's input
  /// scale/zeroPoint: q = round(v / scale) + zeroPoint.
  static int _quantize(
    double normalized,
    double scale,
    int zeroPoint,
    int min,
    int max,
  ) {
    // Guard against a degenerate scale (should never happen for a quantized
    // input, but never divide by zero).
    final s = scale > 0 ? scale : 1.0 / 255.0;
    return (normalized / s + zeroPoint).round().clamp(min, max).toInt();
  }

  // =========================================================================
  // YOLOv8 Output Parser
  //
  // Always operates on floating-point confidence values. When the output
  // tensor is quantized (INT8/UINT8/INT16) the raw integers are dequantized
  // with the model's output scale/zeroPoint before parsing.
  // =========================================================================
  static ({List<Detection> detections, int preNmsCount}) _parseYolov8Output(
    List outputBuffer,
    int numBoxes,
    int numClasses,
    double confThreshold,
    List<String> labels,
    bool requiresDequantization,
    double outputScale,
    int outputZeroPoint,
  ) {
    // Stage 1 — collect every anchor whose best class score clears the
    // (pre-NMS) confidence threshold. Box rows (0..3) are already decoded and
    // normalized to [0,1] by the exported graph (grid + stride + /640).
    final List<Detection> candidates = [];
    final bool isQuantized = requiresDequantization;

    for (int i = 0; i < numBoxes; i++) {
      double maxConf = 0.0;
      int maxClassId = -1;

      for (int j = 4; j < 4 + numClasses; j++) {
        double conf = outputBuffer[j * numBoxes + i].toDouble();
        if (isQuantized) {
          conf = (conf - outputZeroPoint) * outputScale;
        }
        if (conf > maxConf) {
          maxConf = conf;
          maxClassId = j - 4;
        }
      }

      if (maxConf > confThreshold && maxClassId >= 0) {
        double cx = outputBuffer[0 * numBoxes + i].toDouble();
        double cy = outputBuffer[1 * numBoxes + i].toDouble();
        double w = outputBuffer[2 * numBoxes + i].toDouble();
        double h = outputBuffer[3 * numBoxes + i].toDouble();

        if (isQuantized) {
          cx = (cx - outputZeroPoint) * outputScale;
          cy = (cy - outputZeroPoint) * outputScale;
          w = (w - outputZeroPoint) * outputScale;
          h = (h - outputZeroPoint) * outputScale;
        }

        final double left = (cx - w / 2).clamp(0.0, 1.0);
        final double top = (cy - h / 2).clamp(0.0, 1.0);
        final double rw = w.clamp(0.0, 1.0);
        final double rh = h.clamp(0.0, 1.0);
        if (rw <= 0 || rh <= 0) continue; // degenerate box — skip

        final String label = (maxClassId < labels.length)
            ? labels[maxClassId]
            : 'class_$maxClassId';

        candidates.add(
          Detection(
            classId: maxClassId,
            label: label,
            confidence: maxConf,
            box: Rect.fromLTWH(left, top, rw, rh),
          ),
        );
      }
    }

    // Stage 2 — class-wise Non-Maximum Suppression. Without it every object
    // fires many overlapping anchors, which renders as a jumble of boxes that
    // do not correspond to distinct objects.
    candidates.sort((a, b) => b.confidence.compareTo(a.confidence));
    final List<Detection> detections = [];
    for (final c in candidates) {
      var suppressed = false;
      for (final k in detections) {
        if (k.classId == c.classId && _iou(k.box, c.box) > kNmsIouThreshold) {
          suppressed = true;
          break;
        }
      }
      if (!suppressed) detections.add(c);
    }

    // Purely additive: exposes the pre-NMS candidate count (computed above)
    // so callers can log "before NMS" vs "after NMS". No logic changed — same
    // threshold, same argmax, same NMS.
    return (detections: detections, preNmsCount: candidates.length);
  }

  /// Intersection-over-Union of two normalized boxes.
  static double _iou(Rect a, Rect b) {
    final ix = math.max(
      0.0,
      math.min(a.right, b.right) - math.max(a.left, b.left),
    );
    final iy = math.max(
      0.0,
      math.min(a.bottom, b.bottom) - math.max(a.top, b.top),
    );
    final inter = ix * iy;
    final union = a.width * a.height + b.width * b.height - inter;
    return union <= 0 ? 0.0 : inter / union;
  }

  // =========================================================================
  // Startup diagnostics
  // =========================================================================

  /// Compact single-line summary logged on the main isolate when metadata
  /// arrives (`[Model]` prefixed).
  static void _logModelSummary(ModelMetadata m) {
    debugPrint('═══════════════════════════════════════');
    debugPrint('[Model] Runtime model introspection');
    debugPrint('[Model]   Model        : ${m.modelName}');
    debugPrint('[Model]   Detected type: ${m.modelType.label}');
    debugPrint(
      '[Model]   Input  shape : ${m.inputShape}  type: ${m.inputType}',
    );
    debugPrint(
      '[Model]   Output shape : ${m.outputShape}  type: ${m.outputType}',
    );
    debugPrint(
      '[Model]   Input  scale : ${m.inputScale}  zeroPt: ${m.inputZeroPoint}',
    );
    debugPrint(
      '[Model]   Output scale : ${m.outputScale}  zeroPt: ${m.outputZeroPoint}',
    );
    debugPrint('[Model]   Classes      : ${m.classes}  Anchors: ${m.anchors}');
    debugPrint(
      '[Model]   In quantized : ${m.inputQuantized}  Out quantized: ${m.outputQuantized}',
    );
    debugPrint('[Model]   Needs in-quant : ${m.requiresInputQuantization}');
    debugPrint(
      '[Model]   Needs out-dequant: ${m.requiresOutputDequantization}',
    );
    debugPrint(
      '[Model]   Internal tensor types: ${m.internalTensorTypeCounts}',
    );
    debugPrint('═══════════════════════════════════════');
  }

  /// Full structured startup report printed inside the isolate.
  static void _logModelStartupReport(ModelMetadata m) {
    debugPrint('==========================');
    debugPrint('MODEL INFORMATION');
    debugPrint('==========================');
    debugPrint('');
    debugPrint('Model:');
    debugPrint(m.modelName);
    debugPrint('');
    debugPrint('Detected Model Type:');
    debugPrint(m.modelType.label);
    debugPrint('');
    debugPrint('Input');
    debugPrint(m.inputType.toString());
    debugPrint(m.inputShape.join('×'));
    debugPrint('');
    debugPrint('Output');
    debugPrint(m.outputType.toString());
    debugPrint(m.outputShape.join('×'));
    debugPrint('');
    debugPrint('Quantization');
    debugPrint('');
    debugPrint('Input:');
    debugPrint(m.inputQuantized ? 'Yes' : 'No');
    debugPrint('');
    debugPrint('Output:');
    debugPrint(m.outputQuantized ? 'Yes' : 'No');
    debugPrint('');
    debugPrint('Inference Path');
    debugPrint('');
    if (m.requiresInputQuantization) {
      debugPrint('Quantized preprocessing');
      debugPrint('Input quantization: Yes');
      debugPrint('  scale    : ${m.inputScale}');
      debugPrint('  zeroPoint: ${m.inputZeroPoint}');
    } else {
      debugPrint('Float preprocessing');
      debugPrint('No input quantization');
    }
    if (m.requiresOutputDequantization) {
      debugPrint('Output dequantization: Yes');
      debugPrint('  scale    : ${m.outputScale}');
      debugPrint('  zeroPoint: ${m.outputZeroPoint}');
    } else {
      debugPrint('No output dequantization');
    }
    debugPrint('==========================');
  }
}
