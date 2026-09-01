import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show DeviceOrientation;
import 'package:permission_handler/permission_handler.dart';

import '../models/box_transform.dart';
import '../models/app_settings.dart';
import '../models/detection.dart';
import '../models/detection_info.dart';
import '../services/forensic_log.dart';
import '../services/gesture_controller.dart';
import '../services/haptics_service.dart';
import '../services/inference_isolate.dart';
import '../services/settings_service.dart';
import '../services/spatial_analysis_service.dart';
import '../services/telemetry_service.dart';
import '../services/tts_service.dart';
import '../widgets/accessible_button.dart';
import '../widgets/bounding_box_painter.dart';
import '../widgets/detection_card.dart';
import '../widgets/gesture_surface.dart';
import '../widgets/status_pill.dart';
import '../widgets/warning_banner.dart';

/// Detection — the core assistive screen.
///
/// Reuses the validated camera/inference pipeline (persistent isolate,
/// YUV420 → TFLite → NMS → bounding boxes) and layers the assistive product on
/// top of it:
///
/// * live camera preview + bounding-box overlay (unchanged math),
/// * spatial + priority interpretation via [SpatialAnalysisService],
/// * audio announcements via [TtsService] (start/stop, detections, scan,
///   repeat), with an audio mute toggle,
/// * thesis gesture vocabulary via [GestureController]/[GestureSurface],
/// * visible high-contrast controls as a fallback,
/// * runtime telemetry pushed to [TelemetryService] for Logs & Reports.
///
/// Developer telemetry (FPS/latency/model info) is intentionally NOT on this
/// primary screen — it lives in Logs & Reports.
class DetectionScreen extends StatefulWidget {
  final SettingsService settings;
  final TtsService tts;
  final TelemetryService telemetry;
  final HapticsService haptics;

  const DetectionScreen({
    super.key,
    required this.settings,
    required this.tts,
    required this.telemetry,
    required this.haptics,
  });

  @override
  State<DetectionScreen> createState() => _DetectionScreenState();
}

class _DetectionScreenState extends State<DetectionScreen> {
  // -------------------------------------------------------------------------
  // Injected services
  // -------------------------------------------------------------------------
  late final SettingsService _settings = widget.settings;
  late final TtsService _tts = widget.tts;
  late final TelemetryService _telemetry = widget.telemetry;
  late final HapticsService _haptics = widget.haptics;
  final InferenceService _inferenceService = InferenceService();

  // -------------------------------------------------------------------------
  // Camera / inference state (preserved from the validated pipeline)
  // -------------------------------------------------------------------------
  CameraController? _cameraController;
  bool _isCameraInitialized = false;
  bool _isInferring = false; // The frame-dropping gate

  /// Whether detection mode is running (camera streaming + inference).
  bool _detectionActive = false;

  /// Whether frame inference is paused (camera preview stays live).
  bool _paused = false;

  bool _permissionDenied = false;

  // Detection results from the inference isolate.
  List<Detection> _detections = [];
  List<DetectionInfo> _detectionInfo = [];

  double _imageWidth = 0.0;
  double _imageHeight = 0.0;
  CameraLensDirection _lensDirection = CameraLensDirection.back;
  int _sensorOrientation = 0;
  int _rotationDegrees = 0;
  int _uprightWidth = 0;
  int _uprightHeight = 0;

  // Performance tracking.
  int _frameCount = 0;
  int _droppedFrameCount = 0;
  int _processedFrameCount = 0;
  double _lastLatencyMs = 0.0;
  final List<double> _recentLatencies = [];
  static const int _maxRecentLatencies = 60;
  DateTime _lastFpsTick = DateTime.now();
  int _framesSinceLastTick = 0;
  double _cameraFps = 0.0;
  Timer? _perfTimer;
  DateTime _lastDispatchAt = DateTime.fromMillisecondsSinceEpoch(0);

  // -------------------------------------------------------------------------
  // Assistive layer
  // -------------------------------------------------------------------------
  late final GestureController _gestureController = GestureController(
    onGesture: _onGesture,
  );

  @override
  void initState() {
    super.initState();
    _tts.setAudioEnabled(_settings.audioEnabled);
    debugPrint('[Camera] DetectionScreen initState()');
    // 1. Initialize the inference isolate first (creates stream controller).
    _inferenceService.initIsolate();
    // 2. Subscribe to results stream.
    _setupInferenceListener();
    // 3. Camera OR temporary test-image mode.
    if (InferenceService.useTestImage) {
      debugPrint('[Camera] TEMPORARY test-image mode — skipping camera');
      _detectionActive = true;
      _inferenceService.runTestImage();
    } else if (_settings.autoStartDetection) {
      _setupCamera();
    }
    // 4. Start periodic performance logging.
    _startPerformanceLogger();
  }

  @override
  void dispose() {
    debugPrint('[Camera] DetectionScreen dispose()');
    _perfTimer?.cancel();
    _cameraController?.stopImageStream();
    _cameraController?.dispose();
    _inferenceService.dispose();
    _gestureController.reset();
    super.dispose();
  }

  // -------------------------------------------------------------------------
  // Camera setup
  // -------------------------------------------------------------------------
  Future<void> _setupCamera() async {
    debugPrint('[Camera] _setupCamera() — requesting permission…');

    var status = await Permission.camera.status;
    if (!status.isGranted) {
      status = await Permission.camera.request();
    }
    if (!status.isGranted) {
      debugPrint('[Error] Camera permission denied — cannot proceed');
      if (mounted) {
        setState(() {
          _permissionDenied = true;
          _detectionActive = false;
        });
      }
      return;
    }

    final cameras = await availableCameras();
    if (cameras.isEmpty) {
      debugPrint('[Error] No cameras available on this device');
      if (mounted) {
        setState(() => _detectionActive = false);
      }
      return;
    }

    final selectedCamera = cameras[0]; // Back camera
    _cameraController = CameraController(
      selectedCamera,
      ResolutionPreset.low, // CRITICAL: saves ISP bandwidth and memory
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );
    _lensDirection = selectedCamera.lensDirection;
    _sensorOrientation = selectedCamera.sensorOrientation;

    await _cameraController!.initialize();

    _cameraController!.startImageStream(_processCameraImage);

    if (mounted) {
      setState(() {
        _isCameraInitialized = true;
        _detectionActive = true;
        _permissionDenied = false;
      });
    }
    debugPrint('[Camera] Camera initialized — detection active');
  }

  Future<void> _startDetection() async {
    await _haptics.mediumTick();
    if (!_isCameraInitialized || _cameraController == null) {
      await _setupCamera();
      if (mounted && _detectionActive) {
        await _tts.speak('Detection started', urgent: true);
      }
      return;
    }
    try {
      await _cameraController!.startImageStream(_processCameraImage);
    } catch (e) {
      debugPrint('[Error] startImageStream: $e');
    }
    if (mounted) {
      setState(() {
        _detectionActive = true;
        _paused = false;
      });
    }
    await _tts.speak('Detection started', urgent: true);
  }

  Future<void> _stopDetection() async {
    await _haptics.mediumTick();
    try {
      await _cameraController?.stopImageStream();
    } catch (e) {
      debugPrint('[Error] stopImageStream: $e');
    }
    if (mounted) {
      setState(() {
        _detectionActive = false;
        _paused = false;
        _detections = [];
        _detectionInfo = [];
      });
    }
    await _tts.speak('Detection stopped', urgent: true);
  }

  void _toggleDetectionActive() {
    if (_detectionActive) {
      _stopDetection();
    } else {
      _startDetection();
    }
  }

  Future<void> _pauseDetection() async {
    await _haptics.lightTick();
    if (mounted) setState(() => _paused = true);
    await _tts.speak('Detection paused', urgent: true);
  }

  Future<void> _resumeDetection() async {
    await _haptics.lightTick();
    if (mounted) setState(() => _paused = false);
    await _tts.speak('Detection resumed', urgent: true);
  }

  void _togglePaused() {
    if (!_detectionActive) return; // pause/resume only meaningful when active
    if (_paused) {
      _resumeDetection();
    } else {
      _pauseDetection();
    }
  }

  Future<void> _quickScan() async {
    await _haptics.heavyTick();
    final infos = _detectionInfo;
    if (infos.isEmpty) {
      await _tts.speak('Quick scan. No objects detected.', urgent: true);
      return;
    }
    final parts = infos
        .take(4)
        .map(
          (d) =>
              '${d.label} on your ${d.positionLabel}, approximately ${d.proximityLabel}',
        )
        .join('. ');
    await _tts.speak('Quick scan. $parts.', urgent: true);
  }

  Future<void> _repeatAlert() async {
    await _haptics.mediumTick();
    await _tts.repeatLast();
  }

  void _toggleAudio() {
    final next = !_settings.audioEnabled;
    _settings.setAudioEnabled(next);
    _tts.setAudioEnabled(next);
    if (next) _tts.speak('Audio on', urgent: true);
  }

  void _onGesture(EyeCueGesture gesture) {
    switch (gesture) {
      case EyeCueGesture.singleTap:
        _togglePaused();
      case EyeCueGesture.twoFingerDoubleTap:
        _toggleDetectionActive();
      case EyeCueGesture.threeFingerTap:
        _quickScan();
      case EyeCueGesture.swipeDown:
        _repeatAlert();
    }
  }

  // -------------------------------------------------------------------------
  // Inference listener
  // -------------------------------------------------------------------------
  void _setupInferenceListener() {
    _inferenceService.resultsStream.listen((detections) {
      if (mounted) {
        setState(() {
          _detections = detections;
          _detectionInfo = SpatialAnalysisService.analyzeAll(detections);
        });
      }
      _lastLatencyMs = _inferenceService.lastLatencyMs;

      // Rolling latency window for summaries.
      _recentLatencies.add(_lastLatencyMs);
      if (_recentLatencies.length > _maxRecentLatencies) {
        _recentLatencies.removeAt(0);
      }

      // Telemetry for Logs & Reports.
      _telemetry.recordSample(
        latencyMs: _lastLatencyMs,
        inferenceFps: _averageFps(),
        objectCount: detections.length,
        engine: InferenceEngine.custom,
      );
      for (final info in _detectionInfo) {
        _telemetry.recordDetection(
          info,
          _lastLatencyMs,
          engine: InferenceEngine.custom,
        );
      }

      // Audio announcement (cooldown + de-duplication handled inside TtsService).
      _tts.announceDetections(_detectionInfo);

      // Release the lock so the next frame can be processed.
      _isInferring = false;
    });

    _inferenceService.errorStream.listen((error) {
      debugPrint('[Camera] Inference error — releasing busy gate: $error');
      if (_isInferring) {
        _isInferring = false;
      }
    });
  }

  // -------------------------------------------------------------------------
  // Per-frame camera image processing (validated pipeline, + pause/low-power)
  // -------------------------------------------------------------------------
  void _processCameraImage(CameraImage image) {
    _frameCount++;
    _framesSinceLastTick++;

    if (_frameCount == 1) {
      final planes = image.planes
          .map(
            (p) => (
              len: p.bytes.length,
              rowStride: p.bytesPerRow,
              pixelStride: p.bytesPerPixel,
              planeWidth: p.width ?? 0,
              planeHeight: p.height ?? 0,
              firstByte: p.bytes.isEmpty ? -1 : p.bytes[0],
              lastByte: p.bytes.isEmpty ? -1 : p.bytes[p.bytes.length - 1],
            ),
          )
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

    // FPS estimation.
    final now = DateTime.now();
    final elapsed = now.difference(_lastFpsTick).inMilliseconds;
    if (elapsed >= 1000) {
      _cameraFps = _framesSinceLastTick * 1000.0 / elapsed;
      _framesSinceLastTick = 0;
      _lastFpsTick = now;
    }

    // PAUSE: keep the preview live but stop inference.
    if (_paused) {
      _droppedFrameCount++;
      return;
    }

    // FRAME DROPPING GATE.
    if (_isInferring) {
      _droppedFrameCount++;
      return;
    }

    // LOW POWER MODE: explicit minimum interval between dispatches.
    if (_settings.lowPowerMode) {
      if (now.difference(_lastDispatchAt) < const Duration(milliseconds: 250)) {
        _droppedFrameCount++;
        return;
      }
      _lastDispatchAt = now;
    }

    _isInferring = true;
    _processedFrameCount++;

    _imageWidth = image.width.toDouble();
    _imageHeight = image.height.toDouble();

    // --- Orientation (device-independent, metadata-driven) ---
    final DeviceOrientation deviceOrientation =
        _cameraController!.value.deviceOrientation;
    final int deviceDegrees = BoxTransform.deviceDegreesFor(deviceOrientation);
    final bool isFront = _lensDirection == CameraLensDirection.front;
    _rotationDegrees = BoxTransform.displayRotationDegrees(
      sensorOrientation: _sensorOrientation,
      deviceDegrees: deviceDegrees,
      isFront: isFront,
    );
    final upright = BoxTransform.uprightDims(
      w: image.width,
      h: image.height,
      rotationDegrees: _rotationDegrees,
    );
    _uprightWidth = upright.w;
    _uprightHeight = upright.h;

    final planes = image.planes;
    final yPlane = planes[0].bytes;
    final uPlane = planes[1].bytes;
    final vPlane = planes.length >= 3 ? planes[2].bytes : planes[1].bytes;

    final dispatched = _inferenceService.processFrame(
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
      rotationDegrees: _rotationDegrees,
      mirror: isFront,
      sensorOrientation: _sensorOrientation,
      deviceDegrees: deviceDegrees,
      lensFacing: isFront ? 'front' : 'back',
    );
    if (!dispatched) {
      _isInferring = false;
      _droppedFrameCount++;
    }
  }

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

  // -------------------------------------------------------------------------
  // Performance logger
  // -------------------------------------------------------------------------
  void _startPerformanceLogger() {
    _perfTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (_recentLatencies.isEmpty) return;
      final avg =
          _recentLatencies.reduce((a, b) => a + b) / _recentLatencies.length;
      debugPrint('─────────────────────────────────────────');
      debugPrint('[Performance] 5-second Summary');
      debugPrint(
        '[Performance]   Camera FPS      : ${_cameraFps.toStringAsFixed(1)}',
      );
      debugPrint(
        '[Performance]   Inference FPS   : ${(1000.0 / avg).toStringAsFixed(1)}',
      );
      debugPrint(
        '[Performance]   Avg Latency     : ${avg.toStringAsFixed(1)} ms',
      );
      debugPrint('[Performance]   Frames Processed: $_processedFrameCount');
      debugPrint('[Performance]   Detection Count : ${_detections.length}');
      debugPrint('─────────────────────────────────────────');
    });
  }

  double _averageFps() {
    if (_recentLatencies.isEmpty) return 0;
    final avg =
        _recentLatencies.reduce((a, b) => a + b) / _recentLatencies.length;
    return avg > 0 ? 1000.0 / avg : 0;
  }

  // -------------------------------------------------------------------------
  // Derived UI state
  // -------------------------------------------------------------------------
  String? get _warningMessage {
    final high = _detectionInfo
        .where((d) => d.priority == ObjectPriority.high)
        .toList();
    if (high.isEmpty) return null;
    if (high.length == 1) {
      return 'High-priority obstacle detected: ${high.first.label}. '
          'Please adjust your path.';
    }
    return 'High-priority obstacles detected. Please adjust your path.';
  }

  // -------------------------------------------------------------------------
  // UI
  // -------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final bool testMode = InferenceService.useTestImage;
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Fixed, pre-allocated region for ALL dynamic detection content
            // (warning banner, cards). Derived from the available screen
            // height — never from the detection count — so the camera
            // viewport above stays exactly the same size whether there are
            // 0, 1, or many detections. The content region scrolls internally.
            final double contentHeight = (constraints.maxHeight * 0.32).clamp(
              200.0,
              320.0,
            );
            return Column(
              children: [
                _buildTopBar(context),
                Expanded(child: _buildMainArea(context, testMode)),
                SizedBox(
                  height: contentHeight,
                  child: _buildControlsPanel(context),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildTopBar(BuildContext context) {
    final theme = Theme.of(context);
    final (String label, Color color) = !_detectionActive
        ? ('Stopped', const Color(0xFF455A64))
        : _paused
        ? ('Paused', const Color(0xFFF57F17))
        : ('Detecting', const Color(0xFF1B5E20));

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Detection Mode',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                StatusPill(label: label, color: color),
              ],
            ),
          ),
          ListenableBuilder(
            listenable: Listenable.merge([_settings, _tts]),
            builder: (context, _) {
              final on = _settings.audioEnabled;
              return IconButton(
                tooltip: on ? 'Mute audio guidance' : 'Unmute audio guidance',
                onPressed: _toggleAudio,
                iconSize: 32,
                style: IconButton.styleFrom(
                  minimumSize: const Size(56, 56),
                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                ),
                icon: Icon(on ? Icons.volume_up : Icons.volume_off),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildMainArea(BuildContext context, bool testMode) {
    if (_permissionDenied) {
      return _buildPermissionDenied(context);
    }
    if (!testMode && !_isCameraInitialized) {
      return _buildCameraPending(context);
    }
    return _buildViewport(context, testMode);
  }

  Widget _buildPermissionDenied(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.no_photography, size: 72),
            const SizedBox(height: 16),
            Text(
              'Camera permission is required.',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'EyeCue needs the camera to detect objects. Allow camera access '
              'in Settings to continue.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            AccessibleButton(
              label: 'Open Settings',
              icon: Icons.settings,
              prominent: true,
              onPressed: () => openAppSettings(),
            ),
            const SizedBox(height: 12),
            AccessibleButton(
              label: 'Retry',
              icon: Icons.refresh,
              onPressed: () {
                setState(() => _permissionDenied = false);
                _setupCamera();
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCameraPending(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'Detection is off.',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Press Start below, or use a two-finger double tap on the preview.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 20),
            AccessibleButton(
              label: 'Start Detection',
              icon: Icons.play_circle,
              prominent: true,
              onPressed: _startDetection,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildViewport(BuildContext context, bool testMode) {
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
          : (_cameraController?.value.previewSize ?? const Size(1, 1));
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        return Stack(
          fit: StackFit.expand,
          children: [
            // Live feed, contained (never stretched/warped/cropped).
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
            // Bounding boxes — same contain fit, so boxes align with the feed.
            CustomPaint(
              painter: BoundingBoxPainter(
                detections: _detections,
                imageSize: frameSize,
                fit: BoxFit.contain,
              ),
              size: Size.infinite,
            ),
            // Gesture hint.
            const Align(
              alignment: Alignment.bottomCenter,
              child: _GestureHint(),
            ),
            // Thesis gesture capture layer (transparent, topmost).
            GestureSurface(
              controller: _gestureController,
              child: const SizedBox.expand(),
            ),
          ],
        );
      },
    );
  }

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

  /// The bottom content region. Its total height is fixed by the outer
  /// [SizedBox]; only what is inside scrolls, so the camera viewport is never
  /// resized by detection content.
  Widget _buildControlsPanel(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      color: theme.colorScheme.surfaceContainerHigh,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          child: Column(
            children: [
              // Warning banner lives BELOW the camera, in the fixed region.
              if (_warningMessage != null)
                WarningBanner(message: _warningMessage!),
              // Scrollable detection content — adapts inside its own space.
              Expanded(child: _buildDetectionList(context)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  AccessibleButton(
                    label: _detectionActive ? 'Stop' : 'Start',
                    icon: _detectionActive
                        ? Icons.stop_circle
                        : Icons.play_circle,
                    onPressed: _toggleDetectionActive,
                  ),
                  AccessibleButton(
                    label: _paused ? 'Resume' : 'Pause',
                    icon: _paused ? Icons.play_arrow : Icons.pause,
                    onPressed: _detectionActive ? _togglePaused : null,
                  ),
                  AccessibleButton(
                    label: 'Repeat',
                    icon: Icons.replay,
                    onPressed: _repeatAlert,
                  ),
                  AccessibleButton(
                    label: 'Scan',
                    icon: Icons.wifi_tethering,
                    onPressed: _quickScan,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Gestures: 2-finger double-tap start/stop · single tap pause/'
                'resume · 3-finger scan · swipe down repeat',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetectionList(BuildContext context) {
    final theme = Theme.of(context);
    if (_detectionInfo.isEmpty) {
      return Center(
        child: Text(
          _isCameraInitialized
              ? 'Point the camera at your surroundings.'
              : 'Detection is off.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }
    // Always scrollable so any number of detections stays inside the region.
    return ListView.builder(
      itemCount: _detectionInfo.length,
      itemBuilder: (context, i) => DetectionCard(
        info: _detectionInfo[i],
        highlight: _detectionInfo[i].priority == ObjectPriority.high,
      ),
    );
  }
}

class _GestureHint extends StatelessWidget {
  const _GestureHint();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xCC000000),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white24),
      ),
      child: const Text(
        'Gestures active on this screen',
        style: TextStyle(color: Colors.white, fontSize: 12),
      ),
    );
  }
}
