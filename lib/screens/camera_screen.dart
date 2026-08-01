import 'dart:async';
import 'dart:math' as math;
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show DeviceOrientation;
import 'package:permission_handler/permission_handler.dart';
import '../models/box_transform.dart';
import '../models/detection.dart';
import '../models/model_metadata.dart';
import '../services/forensic_log.dart';
import '../services/inference_isolate.dart';
import '../widgets/bounding_box_painter.dart';
import '../widgets/info_panel.dart';

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  CameraController? _cameraController;
  bool _isCameraInitialized = false;
  bool _isInferring = false; // The frame-dropping gate

  /// The camera preview is displayed in a strict 3:4 portrait box anchored to
  /// the top. The feed itself is contained (BoxFit.contain) inside it — never
  /// stretched, warped, or cropped. The painter uses the same fit.
  static const double _previewAspect = 3 / 4;

  /// Minimum height reserved for the bottom information panel.
  static const double _minPanelHeight = 260;

  /// Maximum number of detection-history entries kept.
  static const int _maxHistoryEntries = 50;

  // Our persistent inference service
  final InferenceService _inferenceService = InferenceService();

  /// Chronological detection history (newest first).
  final List<DetectionHistoryEntry> _history = [];

  /// Refreshes relative timestamps in the detection history.
  Timer? _ageTimer;

  // Detection results from the inference isolate.
  List<Detection> _detections = [];

  // Stored camera image dimensions from the last processed frame.
  // These are the raw sensor dimensions (e.g. 640×480) that the model
  // operates on, needed for coordinate transformation.
  double _imageWidth = 0.0;
  double _imageHeight = 0.0;

  // Camera lens direction for front-camera mirroring.
  CameraLensDirection _lensDirection = CameraLensDirection.back;

  // Orientation metadata (device-independent, all metadata-driven).
  int _sensorOrientation = 0;
  int _rotationDegrees = 0; // sensor → upright display rotation (per frame)

  /// Upright (display) dimensions of the latest frame — what the preview and
  /// the painter share. Set per frame; sensor dims with W/H swapped when the
  /// rotation is a quarter turn.
  int _uprightWidth = 0;
  int _uprightHeight = 0;

  // ---------------------------------------------------------------------------
  // Performance tracking
  // ---------------------------------------------------------------------------
  int _frameCount = 0;          // Total frames received from camera
  int _droppedFrameCount = 0;   // Frames skipped because inference was busy
  int _processedFrameCount = 0; // Frames actually sent to isolate
  double _lastLatencyMs = 0.0;  // Latest inference latency from isolate

  // Track inference latencies for the periodic summary
  final List<double> _recentLatencies = [];
  static const int _maxRecentLatencies = 60; // Rolling window for stats

  // FPS estimation
  DateTime _lastFpsTick = DateTime.now();
  int _framesSinceLastTick = 0;
  double _cameraFps = 0.0;

  // Periodic performance logger
  Timer? _perfTimer;

  // Camera resolution for logging
  Size? _cameraResolution;
  String? _imageFormatLabel;

  @override
  void initState() {
    super.initState();
    debugPrint('[Camera] CameraScreen initState()');
    // 1. Initialize the inference isolate first (creates stream controller)
    _inferenceService.initIsolate();
    // 2. Subscribe to results stream (controller is now ready)
    _setupInferenceListener();
    // 3. Camera OR temporary test-image mode
    if (InferenceService.useTestImage) {
      debugPrint('[Camera] TEMPORARY test-image mode — skipping camera');
      _inferenceService.runTestImage();
    } else {
      _setupCamera();
    }
    // 4. Start periodic performance logging
    _startPerformanceLogger();

    // 5. Keep detection-history relative ages fresh.
    _ageTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  // ---------------------------------------------------------------------------
  // Camera setup
  // ---------------------------------------------------------------------------
  Future<void> _setupCamera() async {
    debugPrint('[Camera] _setupCamera() — requesting permission…');

    // 1. Request Permission
    var status = await Permission.camera.status;
    debugPrint('[Camera] Camera permission status: $status');
    if (!status.isGranted) {
      status = await Permission.camera.request();
      debugPrint('[Camera] Camera permission after request: $status');
    }
    if (!status.isGranted) {
      debugPrint('[Error] Camera permission denied — cannot proceed');
      // Handle permission denial in UI
      if (mounted) {
        setState(() {
          _isCameraInitialized = false;
        });
      }
      return;
    }

    // 2. Get available cameras
    final cameras = await availableCameras();
    if (cameras.isEmpty) {
      debugPrint('[Error] No cameras available on this device');
      return;
    }

    final selectedCamera = cameras[0]; // Back camera
    debugPrint('[Camera] Selected camera: ${selectedCamera.name}');
    debugPrint('[Camera]   Lens direction: ${selectedCamera.lensDirection}');
    debugPrint('[Camera]   Sensor orientation: ${selectedCamera.sensorOrientation}°');

    // 3. Initialize CameraController
    _cameraController = CameraController(
      selectedCamera,
      ResolutionPreset.low, // CRITICAL: Saves ISP bandwidth and memory
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.yuv420, // Native Android format
    );

    // Store lens direction for front-camera horizontal mirroring.
    _lensDirection = selectedCamera.lensDirection;
    _sensorOrientation = selectedCamera.sensorOrientation;

    await _cameraController!.initialize();

    // Log the actual resolution and format being used
    final value = _cameraController!.value;
    _cameraResolution = value.previewSize;
    _imageFormatLabel = 'yuv420'; // Configured statically at controller creation
    debugPrint('[Camera] Initialized successfully');
    debugPrint('[Camera]   Preview size: ${value.previewSize?.width}x${value.previewSize?.height}');
    debugPrint('[Camera]   Image format: $_imageFormatLabel (configured)');
    debugPrint('[Camera]   Aspect ratio: ${value.aspectRatio}');
    debugPrint('[Camera]   Streaming active: true');

    // 4. Start the image stream
    _cameraController!.startImageStream(_processCameraImage);
    debugPrint('[Camera] Image stream started');

    if (mounted) {
      setState(() {
        _isCameraInitialized = true;
      });
    }
  }

  // ---------------------------------------------------------------------------
  // Inference listener
  // ---------------------------------------------------------------------------
  void _setupInferenceListener() {
    debugPrint('[Camera] Setting up inference result listener');
    // Listen for results coming back from the Isolate
    _inferenceService.resultsStream.listen((detections) {
      if (mounted) {
        setState(() {
          _detections = detections;
        });
      }
      // Capture latency from the service
      _lastLatencyMs = _inferenceService.lastLatencyMs;

      // Track latency for periodic summary
      _recentLatencies.add(_lastLatencyMs);
      if (_recentLatencies.length > _maxRecentLatencies) {
        _recentLatencies.removeAt(0);
      }

      // Append the highest-confidence detection to the history (newest first).
      if (detections.isNotEmpty) {
        Detection? best;
        for (final d in detections) {
          if (best == null || d.confidence > best.confidence) best = d;
        }
        _history.insert(
          0,
          DetectionHistoryEntry(
            label: best!.label,
            confidence: best.confidence,
            time: DateTime.now(),
          ),
        );
        if (_history.length > _maxHistoryEntries) {
          _history.removeRange(_maxHistoryEntries, _history.length);
        }
      }

      // Release the lock so the next frame can be processed
      _isInferring = false;
    });

    // Recover the busy gate if the isolate reports an error (no result will
    // ever arrive for the offending frame). Without this, every subsequent
    // frame would be dropped forever.
    _inferenceService.errorStream.listen((error) {
      debugPrint('[Camera] Inference error — releasing busy gate: $error');
      if (_isInferring) {
        _isInferring = false;
      }
    });
  }

  // ---------------------------------------------------------------------------
  // Per-frame camera image processing
  // ---------------------------------------------------------------------------
  void _processCameraImage(CameraImage image) {
    _frameCount++;
    _framesSinceLastTick++;

    // Forensic camera.txt (one-shot on the first frame). Includes the plane's
    // own width/height (logical chroma size) and first/last raw bytes so the
    // I420-vs-NV12/NV21 classification is based on real metadata, not guesses.
    if (_frameCount == 1) {
      final planes = image.planes
          .map((p) => (
                len: p.bytes.length,
                rowStride: p.bytesPerRow,
                pixelStride: p.bytesPerPixel,
                planeWidth: p.width ?? 0,
                planeHeight: p.height ?? 0,
                firstByte: p.bytes.isEmpty ? -1 : p.bytes[0],
                lastByte:
                    p.bytes.isEmpty ? -1 : p.bytes[p.bytes.length - 1],
              ))
          .toList();
      ForensicLog.recordCamera(
        formatRaw: (image.format.raw is int) ? image.format.raw as int : -1,
        formatGroup: image.format.group.toString(),
        width: image.width,
        height: image.height,
        planes: planes,
        inferredFormat: _inferCameraFormat(image),
        sensorOrientation: _sensorOrientation,
        lensDirection: _lensDirection.name,
      );
    }

    // FPS calculation (per-second)
    final now = DateTime.now();
    final elapsed = now.difference(_lastFpsTick).inMilliseconds;
    if (elapsed >= 1000) {
      _cameraFps = _framesSinceLastTick * 1000.0 / elapsed;
      _framesSinceLastTick = 0;
      _lastFpsTick = now;
    }

    // FRAME DROPPING LOGIC
    // If the Isolate is still busy processing the last frame, drop this one.
    if (_isInferring) {
      _droppedFrameCount++;
      // Log drops only periodically to avoid console spam
      if (_droppedFrameCount % 30 == 1) {
        debugPrint('[Camera] Frame #$_frameCount DROPPED '
            '(total dropped: $_droppedFrameCount, inference busy)');
      }
      return;
    }

    _isInferring = true;
    _processedFrameCount++;

    // Log frame receipt periodically (every 30th frame to avoid spam)
    if (_frameCount % 30 == 1 || _frameCount <= 5) {
      debugPrint('[Camera] Frame #$_frameCount '
          '| Resolution: ${image.width}x${image.height} '
          '| Format: ${image.format.raw} '
          '| Planes: ${image.planes.length} '
          '| Dropped: false');
    }

    // Store the raw camera image dimensions for coordinate mapping.
    // These are the sensor-native dimensions before any rotation or
    // scaling — exactly what the model sees after the YUV→RGB stretch.
    _imageWidth = image.width.toDouble();
    _imageHeight = image.height.toDouble();

    // --- Orientation (device-independent, metadata-driven) ---
    // Same source as CameraPreview's own rotation (controller.value.
    // deviceOrientation), so the painter and the preview always agree.
    // The DeviceOrientation → degrees mapping uses the plugin's own
    // (counter-clockwise) convention via BoxTransform. No hardcoded angles.
    final DeviceOrientation deviceOrientation =
        _cameraController!.value.deviceOrientation;
    final int deviceDegrees =
        BoxTransform.deviceDegreesFor(deviceOrientation);
    final bool isFront = _lensDirection == CameraLensDirection.front;
    _rotationDegrees = BoxTransform.displayRotationDegrees(
      sensorOrientation: _sensorOrientation,
      deviceDegrees: deviceDegrees,
      isFront: isFront,
    );
    final upright =
        BoxTransform.uprightDims(w: image.width, h: image.height, rotationDegrees: _rotationDegrees);
    _uprightWidth = upright.w;
    _uprightHeight = upright.h;

    // Extract bytes from the camera image planes.
    // YUV_420_888 is either 3 planes (planar I420) or 2 planes (semi-planar
    // NV21/NV12, where plane[1] holds the interleaved chroma).
    final planes = image.planes;
    final yPlane = planes[0].bytes;
    final uPlane = planes[1].bytes;
    final vPlane = planes.length >= 3 ? planes[2].bytes : planes[1].bytes;

    // Send the data + real plane geometry to the persistent isolate so the
    // converter can honor rowStride (padding) and pixelStride (interleave).
    _inferenceService.processFrame(
      yPlane: yPlane,
      uPlane: uPlane,
      vPlane: vPlane,
      width: image.width,
      height: image.height,
      cameraFps: _cameraFps,
      droppedFrames: _droppedFrameCount,
      yRowStride: planes[0].bytesPerRow,
      yPixelStride: planes[0].bytesPerPixel ?? 1,
      uRowStride: planes[1].bytesPerRow,
      uPixelStride: planes[1].bytesPerPixel ?? 1,
      vRowStride: planes.length >= 3
          ? planes[2].bytesPerRow
          : planes[1].bytesPerRow,
      vPixelStride: planes.length >= 3
          ? (planes[2].bytesPerPixel ?? 1)
          : (planes[1].bytesPerPixel ?? 1),
      // Orientation metadata (see BoxTransform).
      rotationDegrees: _rotationDegrees,
      mirror: isFront,
      sensorOrientation: _sensorOrientation,
      deviceDegrees: deviceDegrees,
      lensFacing: isFront ? 'front' : 'back',
    );
  }

  /// Infers the YUV sub-format from the plane layout (mirrors the forensic
  /// format detection). Returns I420 / NV21 / NV12 / UNKNOWN.
  String _inferCameraFormat(CameraImage image) {
    final n = image.planes.length;
    if (n >= 3) {
      final p1 = image.planes[1].bytesPerPixel ?? 1;
      final p2 = image.planes[2].bytesPerPixel ?? 1;
      if (p1 == 1 && p2 == 1) return 'I420 (planar)';
      if (p1 == 2 || p2 == 2) {
        return 'NV12 (semi-planar, U-led — YUV_420_888 contract)';
      }
      return 'YUV_420_888 (unknown layout)';
    }
    if (n == 2) return 'NV21/NV12 (semi-planar, 2 planes)';
    return 'UNKNOWN ($n planes)';
  }

  // ---------------------------------------------------------------------------
  // Periodic performance logger (every 5 seconds)
  // ---------------------------------------------------------------------------
  void _startPerformanceLogger() {
    _perfTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (_recentLatencies.isEmpty) return;

      final avgLatency = _recentLatencies.reduce((a, b) => a + b) /
          _recentLatencies.length;
      final longestLatency =
          _recentLatencies.reduce((a, b) => a > b ? a : b);
      final shortestLatency =
          _recentLatencies.reduce((a, b) => a < b ? a : b);

      // Estimate inference FPS: 1000ms / avgLatency
      final inferenceFps =
          avgLatency > 0 ? (1000.0 / avgLatency).toStringAsFixed(1) : 'N/A';

      debugPrint('─────────────────────────────────────────');
      debugPrint('[Performance] 5-second Summary');
      debugPrint('[Performance]   Camera FPS      : ${_cameraFps.toStringAsFixed(1)}');
      debugPrint('[Performance]   Inference FPS   : $inferenceFps');
      debugPrint('[Performance]   Avg Latency     : ${avgLatency.toStringAsFixed(1)} ms');
      debugPrint('[Performance]   Longest Latency : ${longestLatency.toStringAsFixed(1)} ms');
      debugPrint('[Performance]   Shortest Latency: ${shortestLatency.toStringAsFixed(1)} ms');
      debugPrint('[Performance]   Frames Received : $_frameCount');
      debugPrint('[Performance]   Frames Dropped  : $_droppedFrameCount');
      debugPrint('[Performance]   Frames Processed: $_processedFrameCount');
      debugPrint('[Performance]   Detection Count : ${_detections.length}');
      debugPrint('─────────────────────────────────────────');
    });
  }

  @override
  void dispose() {
    debugPrint('[Camera] CameraScreen dispose()');
    _perfTimer?.cancel();
    _ageTimer?.cancel();
    _cameraController?.stopImageStream();
    _cameraController?.dispose();
    _inferenceService.dispose();
    super.dispose();
  }

  /// Average inference FPS over the recent-latency window.
  double _averageFps() {
    if (_recentLatencies.isEmpty) return 0;
    final avg =
        _recentLatencies.reduce((a, b) => a + b) / _recentLatencies.length;
    return avg > 0 ? 1000.0 / avg : 0;
  }

  /// (highest, lowest, average) confidence of the current detections.
  (double?, double?, double?) _confidenceStats() {
    if (_detections.isEmpty) return (null, null, null);
    double hi = 0, lo = 1, sum = 0;
    for (final d in _detections) {
      if (d.confidence > hi) hi = d.confidence;
      if (d.confidence < lo) lo = d.confidence;
      sum += d.confidence;
    }
    return (hi, lo, sum / _detections.length);
  }

  String get _cameraResolutionLabel {
    if (InferenceService.useTestImage) {
      final tw = _inferenceService.testImageWidth;
      final th = _inferenceService.testImageHeight;
      if (tw > 0 && th > 0) return '$tw×$th (test image)';
    }
    if (_imageWidth > 0 && _imageHeight > 0) {
      return '${_imageWidth.toInt()}×${_imageHeight.toInt()}';
    }
    final s = _cameraResolution;
    return s != null ? '${s.width.toInt()}×${s.height.toInt()}' : '—';
  }

  /// TEMPORARY (Phase F): renders the known-good asset image in test mode.
  /// Falls back to a dark placeholder until the service has decoded it.
  /// Nearest-neighbor (`FilterQuality.none`) matches the pipeline's
  /// nearest-neighbor resize, so the preview reflects exactly what the model
  /// sees.
  Widget _buildTestImagePreview() {
    final bytes = _inferenceService.testImageAssetBytes;
    if (bytes == null) {
      return const ColoredBox(color: Colors.black87);
    }
    return Image.memory(
      bytes,
      fit: BoxFit.fill,
      gaplessPlayback: true,
      filterQuality: FilterQuality.none,
    );
  }

  String _modelInputResolution(ModelMetadata? m) {
    final shape = m?.inputShape;
    if (shape != null && shape.length >= 3) {
      return '${shape[1]}×${shape[2]}';
    }
    return '—';
  }

  @override
  Widget build(BuildContext context) {
    final bool testMode = InferenceService.useTestImage;

    if (!testMode && (!_isCameraInitialized || _cameraController == null)) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    // Frame dimensions at their native aspect ratio (the inference input).
    // These drive both the preview widget and the overlay transform.
    //   - camera: the UPRIGHT (display) size — W/H swapped when the sensor
    //     frame is rotated a quarter turn — so the preview box and the painter
    //     share one coordinate space (the model already outputs upright boxes).
    //   - test image: the decoded asset dimensions (rotation is always 0)
    final Size frameSize;
    if (testMode) {
      final tw = _inferenceService.testImageWidth;
      final th = _inferenceService.testImageHeight;
      frameSize = (tw > 0 && th > 0)
          ? Size(tw.toDouble(), th.toDouble())
          : const Size(1, 1);
    } else if (_uprightWidth > 0 && _uprightHeight > 0) {
      frameSize = Size(_uprightWidth.toDouble(), _uprightHeight.toDouble());
    } else {
      frameSize = _imageWidth > 0 && _imageHeight > 0
          ? Size(_imageWidth, _imageHeight)
          : (_cameraController!.value.previewSize ?? const Size(1, 1));
    }

    final ModelMetadata? metadata = _inferenceService.modelMetadata;
    final (double?, double?, double?) confStats = _confidenceStats();

    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Strict 3:4 portrait preview, anchored to the top. Room for the
            // bottom panel is reserved so it is never squeezed out.
            final double maxPreviewHeight =
                math.max(0.0, constraints.maxHeight - _minPanelHeight);
            final double previewWidth = math
                .min(constraints.maxWidth, maxPreviewHeight * _previewAspect)
                .clamp(0.0, constraints.maxWidth);
            final double previewHeight = previewWidth / _previewAspect;

            return Column(
              children: [
                // ---- Camera preview (strict 3:4, anchored top) ----
                SizedBox(
                  width: previewWidth,
                  height: previewHeight,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // Feed contained inside the 3:4 box: full frame always
                      // visible, never stretched/warped/cropped.
                      FittedBox(
                        fit: BoxFit.contain,
                        clipBehavior: Clip.hardEdge,
                        child: SizedBox(
                          width: frameSize.width,
                          height: frameSize.height,
                          child: testMode
                              ? _buildTestImagePreview()
                              : CameraPreview(_cameraController!),
                        ),
                      ),
                      // Bounding boxes — the canvas is exactly the preview
                      // box; the painter uses the same contain fit, so boxes
                      // align with the rendered feed (no magic offsets).
                      CustomPaint(
                        painter: BoundingBoxPainter(
                          detections: _detections,
                          imageSize: frameSize,
                          fit: BoxFit.contain,
                        ),
                        size: Size.infinite,
                      ),
                    ],
                  ),
                ),

                // ---- Bottom information panel (permanent, never floats) ----
                Expanded(
                  child: DefaultTabController(
                    length: 2,
                    child: Column(
                      children: [
                        const TabBar(
                          tabs: [
                            Tab(text: 'Metrics'),
                            Tab(text: 'Detections'),
                          ],
                        ),
                        Expanded(
                          child: TabBarView(
                            children: [
                              MetricsPanel(
                                cameraFps: _cameraFps,
                                averageFps: _averageFps(),
                                inferenceMs: _lastLatencyMs,
                                objectsDetected: _detections.length,
                                highestConfidence: confStats.$1,
                                lowestConfidence: confStats.$2,
                                averageConfidence: confStats.$3,
                                cameraResolution: _cameraResolutionLabel,
                                previewResolution:
                                    '${previewWidth.round()}×${previewHeight.round()}',
                                modelInputResolution:
                                    _modelInputResolution(metadata),
                                aspectRatio:
                                    '3:4 preview / ${frameSize.width.toStringAsFixed(0)}:${frameSize.height.toStringAsFixed(0)} feed',
                                modelName: metadata?.modelName ?? '—',
                                inferenceBackend: 'CPU (XNNPACK disabled)',
                                quantization: metadata?.modelType.label ?? '—',
                                threadCount: '4',
                                memoryUsage: '—',
                              ),
                              DetectionsPanel(entries: _history),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
