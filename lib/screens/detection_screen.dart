import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show DeviceOrientation, SystemUiOverlayStyle;
import 'package:permission_handler/permission_handler.dart';

import '../models/box_transform.dart';
import '../models/app_settings.dart';
import '../models/detection.dart';
import '../models/detection_info.dart';
import '../models/detection_runtime_state.dart';
import '../models/inference_lifecycle_event.dart';
import '../services/assistive_detection_controller.dart';
import '../services/correction_service.dart';
import '../services/forensic_log.dart';
import '../services/gesture_controller.dart';
import '../services/haptics_service.dart';
import '../services/inference_isolate.dart';
import '../services/settings_service.dart';
import '../services/telemetry_service.dart';
import '../services/tts_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_home_theme.dart';
import '../theme/app_radii.dart';
import '../theme/app_spacing.dart';
import '../widgets/accessible_button.dart';
import '../widgets/bounding_box_painter.dart';
import '../widgets/detection_card.dart';
import '../widgets/detection_correction_sheet.dart';
import '../widgets/detection_state_panel.dart';
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
  final CorrectionService? corrections;
  final HapticsService haptics;

  /// Reports a state together with the Custom worker generation that produced
  /// it. Camera-only states have a null source generation.
  final void Function(DetectionRuntimeState state, int? sourceGeneration)?
  onRuntimeStateChanged;

  /// Reports a failure together with the Custom worker generation that
  /// produced it, when the failure originated in the isolate.
  final void Function(DetectionFailure failure, int? sourceGeneration)?
  onFailure;

  const DetectionScreen({
    super.key,
    required this.settings,
    required this.tts,
    required this.telemetry,
    this.corrections,
    required this.haptics,
    this.onRuntimeStateChanged,
    this.onFailure,
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
  late final InferenceService _inferenceService = InferenceService(
    confidenceThreshold: _settings.detectionConfidence,
  );
  late final AssistiveDetectionController _assistive =
      AssistiveDetectionController(
        engine: InferenceEngine.custom,
        tts: _tts,
        telemetry: _telemetry,
        corrections: widget.corrections,
        confidenceThreshold: _settings.detectionConfidence,
      );

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
  DetectionRuntimeState _runtimeState = DetectionRuntimeState.idle;
  DetectionFailure? _failure;
  StreamSubscription<List<Detection>>? _resultsSubscription;
  StreamSubscription<String>? _errorSubscription;
  StreamSubscription<InferenceLifecycleEvent>? _lifecycleSubscription;

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
  DetectionRuntimeState? _lastReportedRuntimeState;
  int? _lastReportedWorkerGeneration;

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
    // Subscribe before initialization so no worker lifecycle event is missed.
    _setupInferenceListener();
    _inferenceService.initIsolate();
    // Camera OR temporary test-image mode.
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
    _resultsSubscription?.cancel();
    _errorSubscription?.cancel();
    _lifecycleSubscription?.cancel();
    _cameraController?.stopImageStream();
    _cameraController?.dispose();
    _inferenceService.dispose();
    _assistive.dispose();
    _gestureController.reset();
    super.dispose();
  }

  // -------------------------------------------------------------------------
  // Camera setup
  // -------------------------------------------------------------------------
  Future<void> _setupCamera() async {
    debugPrint('[Camera] _setupCamera() — requesting permission…');
    _setRuntimeState(DetectionRuntimeState.requestingPermission);

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
      _reportFailure(
        DetectionFailure(
          category: DetectionFailureCategory.permissionDenied,
          safeMessage:
              'Camera permission is required to detect objects. Allow camera access in Settings.',
          technicalDetail: 'Camera permission status: $status',
          engine: InferenceEngine.custom,
          timestamp: DateTime.now(),
        ),
      );
      return;
    }

    _setRuntimeState(DetectionRuntimeState.startingCamera);
    late final List<CameraDescription> cameras;
    try {
      cameras = await availableCameras();
    } catch (error, stack) {
      _reportFailure(
        DetectionFailure(
          category: DetectionFailureCategory.cameraInitialization,
          safeMessage: 'The camera could not be initialized.',
          technicalDetail: '$error\n$stack',
          engine: InferenceEngine.custom,
          timestamp: DateTime.now(),
        ),
      );
      return;
    }
    if (cameras.isEmpty) {
      debugPrint('[Error] No cameras available on this device');
      if (mounted) {
        setState(() => _detectionActive = false);
      }
      _reportFailure(
        DetectionFailure(
          category: DetectionFailureCategory.unavailable,
          safeMessage: 'No camera is available on this device.',
          technicalDetail: 'availableCameras returned an empty list',
          recoverable: false,
          engine: InferenceEngine.custom,
          timestamp: DateTime.now(),
        ),
      );
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

    try {
      await _cameraController!.initialize();
      await _cameraController!.startImageStream(_processCameraImage);
    } catch (error, stack) {
      await _cameraController?.dispose();
      _cameraController = null;
      _reportFailure(
        DetectionFailure(
          category: DetectionFailureCategory.cameraInitialization,
          safeMessage: 'The camera could not be initialized.',
          technicalDetail: '$error\n$stack',
          engine: InferenceEngine.custom,
          timestamp: DateTime.now(),
        ),
      );
      return;
    }

    if (mounted) {
      setState(() {
        _isCameraInitialized = true;
        _detectionActive = true;
        _permissionDenied = false;
      });
    }
    _setRuntimeState(DetectionRuntimeState.ready);
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
    await _assistive.quickScan();
  }

  Future<void> _repeatAlert() async {
    await _haptics.mediumTick();
    await _tts.repeatLast();
  }

  Future<void> _reportCorrection(DetectionInfo info) async {
    final corrections = widget.corrections;
    if (corrections == null || !mounted) return;
    final selection = await showDetectionCorrectionSheet(
      context: context,
      info: info,
      labels: corrections.labels,
    );
    if (!mounted || selection == null) return;

    try {
      final record = _assistive.addCorrection(
        info: info,
        feedback: selection.feedback,
        correctedLabel: selection.correctedLabel,
      );
      if (record == null) return;
      final message = selection.confirmationMessage;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Semantics(
            container: true,
            liveRegion: true,
            label: message,
            child: Text(message),
          ),
        ),
      );
      await _tts.speak(message, urgent: true);
    } on ArgumentError {
      if (!mounted) return;
      const message = 'Correction could not be saved.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Semantics(
            container: true,
            liveRegion: true,
            label: message,
            child: Text(message),
          ),
        ),
      );
    }
  }

  DetectionInfo? get _lastCorrectableDetection {
    if (widget.corrections == null) return null;
    if (_tts.lastAnnouncedEngine != InferenceEngine.custom) return null;
    return _tts.lastAnnouncedDetection;
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
    _resultsSubscription = _inferenceService.resultsStream.listen((detections) {
      final latencyMs = _inferenceService.lastLatencyMs;
      final infos = _assistive.updateDetections(
        detections,
        latencyMs: latencyMs,
      );
      _assistive.recordMetrics(
        latencyMs: latencyMs,
        inferenceFps: _averageFps(),
      );
      if (mounted) {
        setState(() {
          _detections = detections;
          _detectionInfo = infos;
        });
      }
      _lastLatencyMs = latencyMs;

      // Rolling latency window for summaries.
      _recentLatencies.add(_lastLatencyMs);
      if (_recentLatencies.length > _maxRecentLatencies) {
        _recentLatencies.removeAt(0);
      }

      // Release the lock so the next frame can be processed.
      _isInferring = false;
    });

    _errorSubscription = _inferenceService.errorStream.listen((error) {
      debugPrint('[Camera] Inference error — releasing busy gate: $error');
      if (_isInferring) {
        _isInferring = false;
      }
    });
    _lifecycleSubscription = _inferenceService.lifecycleStream.listen(
      _handleInferenceLifecycle,
    );
  }

  void _handleInferenceLifecycle(InferenceLifecycleEvent event) {
    if (!mounted) return;
    _telemetry.recordRecovery(event);
    switch (event.type) {
      case InferenceLifecycleEventType.starting:
        _setRuntimeState(
          DetectionRuntimeState.loadingModel,
          sourceGeneration: event.generation,
        );
      case InferenceLifecycleEventType.workerReady:
        if (_runtimeState == DetectionRuntimeState.loadingModel) {
          _setRuntimeState(
            DetectionRuntimeState.ready,
            sourceGeneration: event.generation,
          );
        }
      case InferenceLifecycleEventType.modelLoaded:
        if (_detectionActive || InferenceService.useTestImage) {
          _setRuntimeState(
            DetectionRuntimeState.ready,
            sourceGeneration: event.generation,
          );
        } else {
          _setRuntimeState(
            DetectionRuntimeState.idle,
            sourceGeneration: event.generation,
          );
        }
      case InferenceLifecycleEventType.transientError:
        _isInferring = false;
      case InferenceLifecycleEventType.recovering:
        _isInferring = false;
        _setRuntimeState(
          DetectionRuntimeState.recovering,
          sourceGeneration: event.generation,
        );
      case InferenceLifecycleEventType.workerFailure:
        _isInferring = false;
        _setRuntimeState(
          DetectionRuntimeState.recovering,
          sourceGeneration: event.generation,
        );
      case InferenceLifecycleEventType.recoverySucceeded:
        _isInferring = false;
        _setRuntimeState(
          DetectionRuntimeState.ready,
          sourceGeneration: event.generation,
        );
      case InferenceLifecycleEventType.terminalFailure:
        _isInferring = false;
        final failure = event.failure;
        if (failure != null) {
          _reportFailure(failure, sourceGeneration: event.generation);
        }
      case InferenceLifecycleEventType.disposed:
        break;
    }
  }

  void _setRuntimeState(DetectionRuntimeState state, {int? sourceGeneration}) {
    if (!mounted) return;
    final stateChanged = _runtimeState != state;
    if (stateChanged) {
      setState(() => _runtimeState = state);
    }
    final sourceChanged = _lastReportedWorkerGeneration != sourceGeneration;
    if (stateChanged || sourceChanged || _lastReportedRuntimeState != state) {
      _lastReportedRuntimeState = state;
      _lastReportedWorkerGeneration = sourceGeneration;
      widget.onRuntimeStateChanged?.call(state, sourceGeneration);
    }
  }

  void _reportFailure(DetectionFailure failure, {int? sourceGeneration}) {
    if (!mounted) return;
    setState(() {
      _failure = failure;
      _runtimeState = DetectionRuntimeState.failed;
      _detectionActive = false;
    });
    if (widget.onFailure != null) {
      widget.onFailure!(failure, sourceGeneration);
    } else {
      _telemetry.recordFailure(failure);
    }
  }

  Future<void> _retryRuntime() async {
    if (!mounted) return;
    setState(() {
      _failure = null;
      _permissionDenied = false;
    });
    _setRuntimeState(DetectionRuntimeState.loadingModel);
    await _inferenceService.retryInitialization(
      confidenceThreshold: _settings.detectionConfidence,
    );
    if (!mounted) return;

    if (_isCameraInitialized && _cameraController != null) {
      await _startDetection();
    } else {
      await _setupCamera();
    }
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
    return Theme(
      data: buildHomeTheme(),
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.dark,
        child: Scaffold(
          body: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                // Fixed, pre-allocated region for ALL dynamic detection content
                // (warning banner, cards). Derived from the available screen
                // height — never from the detection count — so the camera
                // viewport above stays exactly the same size whether there are
                // 0, 1, or many detections. The content region scrolls
                // internally.
                final double contentHeight = (constraints.maxHeight * 0.32)
                    .clamp(260.0, 320.0);
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
        ),
      ),
    );
  }

  Widget _buildTopBar(BuildContext context) {
    final theme = Theme.of(context);
    final (String label, Color color) = !_detectionActive
        ? ('Stopped', kStatusBlueGrey)
        : _paused
        ? ('Paused', kStatusAmber)
        : ('Detecting', kStatusGreen);

    return Padding(
      padding: const EdgeInsets.fromLTRB(kSpace16, kSpace16, kSpace16, kSpace8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Detection Mode', style: theme.textTheme.titleLarge),
          const SizedBox(height: kSpace4),
          Row(
            children: [
              StatusPill(label: label, color: color),
              const Spacer(),
              ListenableBuilder(
                listenable: Listenable.merge([_settings, _tts]),
                builder: (context, _) {
                  final on = _settings.audioEnabled;
                  return _AudioPill(
                    on: on,
                    onPressed: _toggleAudio,
                    tooltip: on
                        ? 'Mute audio guidance'
                        : 'Unmute audio guidance',
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMainArea(BuildContext context, bool testMode) {
    if (_runtimeState.isBusy || _runtimeState == DetectionRuntimeState.failed) {
      return DetectionStatePanel(
        state: _runtimeState,
        failure: _failure,
        onRetry: _retryRuntime,
        onStop: _stopDetection,
      );
    }
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
        // Rounded dark card around the live feed. The viewport stack itself is
        // unchanged; only the surrounding container (dark fill + rounded clip)
        // is added so the light chrome never sits over the camera surface.
        return Container(
          decoration: BoxDecoration(
            color: kHomeInk,
            borderRadius: BorderRadius.circular(kRadius24),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
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
          ),
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
      color: kHomeSurfaceBase,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            kSpace12,
            kSpace8,
            kSpace12,
            kSpace12,
          ),
          // The whole panel scrolls so the fixed-height region can never
          // overflow, regardless of text scale or how many controls wrap.
          child: SingleChildScrollView(
            child: Column(
              children: [
                // Warning banner lives BELOW the camera, in the fixed region.
                if (_warningMessage != null)
                  WarningBanner(message: _warningMessage!),
                // Detection content — bounded so it scrolls internally and the
                // panel itself can still scroll when the controls wrap.
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 160),
                  child: _buildDetectionList(context),
                ),
                const SizedBox(height: kSpace6),
                Wrap(
                  spacing: kSpace8,
                  runSpacing: kSpace8,
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
                      prominent: true,
                      onPressed: _detectionActive ? _togglePaused : null,
                    ),
                    AccessibleButton(
                      label: 'Repeat',
                      icon: Icons.replay,
                      onPressed: _repeatAlert,
                    ),
                    if (widget.corrections != null)
                      ListenableBuilder(
                        listenable: _tts,
                        builder: (context, _) {
                          final last = _lastCorrectableDetection;
                          return AccessibleButton(
                            label: 'Correct last announcement',
                            icon: Icons.flag_outlined,
                            onPressed: last == null
                                ? null
                                : () => _reportCorrection(last),
                          );
                        },
                      ),
                    AccessibleButton(
                      label: 'Scan',
                      icon: Icons.wifi_tethering,
                      prominent: true,
                      onPressed: _quickScan,
                    ),
                  ],
                ),
                const SizedBox(height: kSpace8),
                Text(
                  'Gestures: 2-finger double-tap start/stop · single tap pause/'
                  'resume · 3-finger scan · swipe down repeat',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: kHomeInkMuted,
                  ),
                ),
              ],
            ),
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
        onReport: widget.corrections == null
            ? null
            : () => _reportCorrection(_detectionInfo[i]),
      ),
    );
  }
}

class _GestureHint extends StatelessWidget {
  const _GestureHint();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: kSpace10),
      padding: const EdgeInsets.symmetric(
        horizontal: kSpace14,
        vertical: kSpace8,
      ),
      decoration: BoxDecoration(
        color: kOverlayBlack,
        borderRadius: BorderRadius.circular(kRadius20),
        border: Border.all(color: Colors.white24),
      ),
      child: const Text(
        'Gestures active on this screen',
        style: TextStyle(color: Colors.white, fontSize: 12),
      ),
    );
  }
}

/// Inline audio-guidance toggle pill (screen-only helper).
///
/// Restyles the previous circular mute [IconButton] into the light-language
/// `AUDIO ON` / `AUDIO OFF` capsule while preserving the toggle behavior, the
/// tooltip text, the enabled state, and a ≥48dp touch target.
class _AudioPill extends StatelessWidget {
  final bool on;
  final VoidCallback onPressed;
  final String tooltip;

  const _AudioPill({
    required this.on,
    required this.onPressed,
    required this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      enabled: true,
      label: 'Audio guidance, ${on ? 'on' : 'off'}',
      child: Tooltip(
        message: tooltip,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minWidth: kMinTouchWidth,
            minHeight: kMinTouchHeight,
          ),
          child: Material(
            color: kHomeSurfaceCard,
            elevation: 0,
            borderRadius: BorderRadius.circular(kRadius20),
            child: InkWell(
              onTap: onPressed,
              borderRadius: BorderRadius.circular(kRadius20),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: kSpace12,
                  vertical: kSpace6,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(kRadius20),
                  boxShadow: kHomeShadowSoft,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ExcludeSemantics(
                      child: Container(
                        width: kSpace8,
                        height: kSpace8,
                        decoration: BoxDecoration(
                          color: on ? kHomeAccentCyan : kHomeInkMuted,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                    const SizedBox(width: kSpace8),
                    ExcludeSemantics(
                      child: Text(
                        on ? 'AUDIO ON' : 'AUDIO OFF',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: kHomeInk,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
