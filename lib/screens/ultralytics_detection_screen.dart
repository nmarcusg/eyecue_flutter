import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:permission_handler/permission_handler.dart';
import 'package:ultralytics_yolo/ultralytics_yolo.dart';

import '../models/app_settings.dart';
import '../models/detection_info.dart';
import '../models/model_config.dart';
import '../services/gesture_controller.dart';
import '../services/haptics_service.dart';
import '../services/settings_service.dart';
import '../services/spatial_analysis_service.dart';
import '../services/telemetry_service.dart';
import '../services/tts_service.dart';
import '../services/ultralytics_detection_adapter.dart';
import '../widgets/accessible_button.dart';
import '../widgets/detection_card.dart';
import '../widgets/gesture_surface.dart';
import '../widgets/status_pill.dart';
import '../widgets/warning_banner.dart';

class UltralyticsDetectionScreen extends StatefulWidget {
  final SettingsService settings;
  final TtsService tts;
  final TelemetryService telemetry;
  final HapticsService haptics;

  const UltralyticsDetectionScreen({
    super.key,
    required this.settings,
    required this.tts,
    required this.telemetry,
    required this.haptics,
  });

  @override
  State<UltralyticsDetectionScreen> createState() =>
      _UltralyticsDetectionScreenState();
}

class _UltralyticsDetectionScreenState
    extends State<UltralyticsDetectionScreen> {
  late final SettingsService _settings = widget.settings;
  late final TtsService _tts = widget.tts;
  late final TelemetryService _telemetry = widget.telemetry;
  late final HapticsService _haptics = widget.haptics;
  final YOLOViewController _controller = YOLOViewController();

  late final GestureController _gestureController = GestureController(
    onGesture: _onGesture,
  );

  List<String> _labels = const [];
  List<DetectionInfo> _detectionInfo = const [];
  bool _detectionActive = false;
  bool _paused = false;
  bool _permissionDenied = false;
  bool _starting = false;
  bool _modelLoaded = false;
  bool _lastLowPowerMode = false;
  String? _modelError;
  double _fps = 0;
  double _inferenceMs = 0;
  double _processingMs = 0;

  YOLOStreamingConfig get _streamingConfig => YOLOStreamingConfig(
    inferenceFrequency: _settings.lowPowerMode ? 4 : null,
  );

  @override
  void initState() {
    super.initState();
    _lastLowPowerMode = _settings.lowPowerMode;
    _settings.addListener(_handleSettingsChanged);
    _loadLabels();
    if (_settings.autoStartDetection) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _startDetection(announce: false, haptic: false);
      });
    }
  }

  @override
  void dispose() {
    _settings.removeListener(_handleSettingsChanged);
    _gestureController.reset();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadLabels() async {
    try {
      final text = await rootBundle.loadString(
        EyeCueModelConfig.labelsAssetPath,
      );
      final labels = text
          .split('\n')
          .map((label) => label.trim())
          .where((label) => label.isNotEmpty)
          .toList(growable: false);
      if (mounted) setState(() => _labels = labels);
    } catch (error) {
      debugPrint('[Ultralytics] Unable to load labels: $error');
    }
  }

  void _handleSettingsChanged() {
    if (_settings.lowPowerMode == _lastLowPowerMode) return;
    _lastLowPowerMode = _settings.lowPowerMode;
    _controller.setStreamingConfig(_streamingConfig);
  }

  Future<bool> _ensureCameraPermission() async {
    var status = await Permission.camera.status;
    if (!status.isGranted) status = await Permission.camera.request();
    if (status.isGranted) {
      if (mounted) setState(() => _permissionDenied = false);
      return true;
    }
    if (mounted) {
      setState(() {
        _permissionDenied = true;
        _starting = false;
      });
    }
    return false;
  }

  Future<void> _startDetection({
    bool announce = true,
    bool haptic = true,
  }) async {
    if (_starting || _detectionActive) return;
    if (haptic) await _haptics.mediumTick();
    if (mounted) setState(() => _starting = true);
    if (!await _ensureCameraPermission()) return;
    if (!mounted) return;
    setState(() {
      _detectionActive = true;
      _paused = false;
      _starting = false;
      _modelLoaded = false;
      _modelError = null;
    });
    if (announce) await _tts.speak('Detection started', urgent: true);
  }

  Future<void> _stopDetection() async {
    await _haptics.mediumTick();
    await _controller.stop();
    if (!mounted) return;
    setState(() {
      _detectionActive = false;
      _paused = false;
      _modelLoaded = false;
      _detectionInfo = const [];
      _fps = 0;
      _inferenceMs = 0;
      _processingMs = 0;
    });
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
    if (!_detectionActive || _paused) return;
    await _haptics.lightTick();
    await _controller.pause();
    if (mounted) setState(() => _paused = true);
    await _tts.speak('Detection paused', urgent: true);
  }

  Future<void> _resumeDetection() async {
    if (!_detectionActive || !_paused) return;
    await _haptics.lightTick();
    await _controller.resume();
    if (mounted) setState(() => _paused = false);
    await _tts.speak('Detection resumed', urgent: true);
  }

  void _togglePaused() {
    if (_paused) {
      _resumeDetection();
    } else {
      _pauseDetection();
    }
  }

  void _handleResults(List<YOLOResult> results) {
    if (!_detectionActive || _paused) return;
    final detections = UltralyticsDetectionAdapter.convert(results, _labels);
    final infos = SpatialAnalysisService.analyzeAll(detections);
    if (mounted) setState(() => _detectionInfo = infos);
    for (final info in infos) {
      _telemetry.recordDetection(
        info,
        _inferenceMs,
        engine: InferenceEngine.ultralytics,
      );
    }
    _tts.announceDetections(infos);
  }

  void _handleMetrics(YOLOPerformanceMetrics metrics) {
    if (!_detectionActive || _paused) return;
    final inferenceMs = metrics.inferenceMs > 0
        ? metrics.inferenceMs
        : metrics.processingTimeMs;
    if (mounted) {
      setState(() {
        _fps = metrics.fps;
        _inferenceMs = inferenceMs;
        _processingMs = metrics.processingTimeMs;
      });
    }
    _telemetry.recordSample(
      latencyMs: inferenceMs,
      inferenceFps: metrics.fps,
      objectCount: _detectionInfo.length,
      engine: InferenceEngine.ultralytics,
    );
  }

  Future<void> _quickScan() async {
    await _haptics.heavyTick();
    if (_detectionInfo.isEmpty) {
      await _tts.speak('Quick scan. No objects detected.', urgent: true);
      return;
    }
    final description = _detectionInfo
        .take(4)
        .map(
          (info) =>
              '${info.label} on your ${info.positionLabel}, '
              'approximately ${info.proximityLabel}',
        )
        .join('. ');
    await _tts.speak('Quick scan. $description.', urgent: true);
  }

  Future<void> _repeatAlert() async {
    await _haptics.mediumTick();
    await _tts.repeatLast();
  }

  void _toggleAudio() {
    final enabled = !_settings.audioEnabled;
    _settings.setAudioEnabled(enabled);
    _tts.setAudioEnabled(enabled);
    if (enabled) _tts.speak('Audio on', urgent: true);
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

  String? get _warningMessage {
    final high = _detectionInfo
        .where((info) => info.priority == ObjectPriority.high)
        .toList();
    if (high.isEmpty) return null;
    if (high.length == 1) {
      return 'High-priority obstacle detected: ${high.first.label}. '
          'Please adjust your path.';
    }
    return 'High-priority obstacles detected. Please adjust your path.';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final contentHeight = (constraints.maxHeight * 0.32).clamp(
              200.0,
              320.0,
            );
            return Column(
              children: [
                _buildTopBar(context),
                Expanded(child: _buildMainArea(context)),
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
    final (label, color) = !_detectionActive
        ? ('Stopped', const Color(0xFF455A64))
        : _paused
        ? ('Paused', const Color(0xFFF57F17))
        : !_modelLoaded
        ? ('Loading', const Color(0xFF0D47A1))
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
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    StatusPill(label: label, color: color),
                    Text(
                      'Ultralytics GPU→CPU · ${_fps.toStringAsFixed(1)} FPS · '
                      '${_inferenceMs.toStringAsFixed(1)} ms infer',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
                if (_processingMs > 0)
                  Text(
                    '${_processingMs.toStringAsFixed(1)} ms native total',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                if (_modelError != null)
                  Text(
                    _modelError!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
              ],
            ),
          ),
          ListenableBuilder(
            listenable: Listenable.merge([_settings, _tts]),
            builder: (context, _) {
              final enabled = _settings.audioEnabled;
              return IconButton(
                tooltip: enabled
                    ? 'Mute audio guidance'
                    : 'Unmute audio guidance',
                onPressed: _toggleAudio,
                iconSize: 32,
                style: IconButton.styleFrom(
                  minimumSize: const Size(56, 56),
                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                ),
                icon: Icon(enabled ? Icons.volume_up : Icons.volume_off),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildMainArea(BuildContext context) {
    if (_permissionDenied) return _buildPermissionDenied(context);
    if (!_detectionActive) return _buildCameraPending(context);
    return Stack(
      fit: StackFit.expand,
      children: [
        YOLOView(
          modelPath: EyeCueModelConfig.modelAssetPath,
          task: YOLOTask.detect,
          controller: _controller,
          confidenceThreshold: EyeCueModelConfig.confidenceThreshold,
          iouThreshold: EyeCueModelConfig.nmsIouThreshold,
          useGpu: true,
          streamingConfig: _streamingConfig,
          onResult: _handleResults,
          onPerformanceMetrics: _handleMetrics,
          onModelLoad: (_, _) {
            if (mounted) {
              setState(() {
                _modelLoaded = true;
                _modelError = null;
              });
            }
          },
          onModelError: (error, _, _) {
            if (mounted) {
              setState(() => _modelError = 'Model error: $error');
            }
          },
        ),
        const Align(alignment: Alignment.bottomCenter, child: _GestureHint()),
        GestureSurface(
          controller: _gestureController,
          child: const SizedBox.expand(),
        ),
      ],
    );
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
            const SizedBox(height: 20),
            AccessibleButton(
              label: 'Open Settings',
              icon: Icons.settings,
              prominent: true,
              onPressed: openAppSettings,
            ),
            const SizedBox(height: 12),
            AccessibleButton(
              label: 'Retry',
              icon: Icons.refresh,
              onPressed: _startDetection,
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
              _starting ? 'Starting detection…' : 'Detection is off.',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Ultralytics mode uses the same model and thresholds as the '
              'custom EyeCue mode.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            AccessibleButton(
              label: 'Start Detection',
              icon: Icons.play_circle,
              prominent: true,
              onPressed: _starting ? null : _startDetection,
            ),
          ],
        ),
      ),
    );
  }

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
              if (_warningMessage != null)
                WarningBanner(message: _warningMessage!),
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
          _detectionActive
              ? 'Point the camera at your surroundings.'
              : 'Detection is off.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }
    return ListView.builder(
      itemCount: _detectionInfo.length,
      itemBuilder: (context, index) => DetectionCard(
        info: _detectionInfo[index],
        highlight: _detectionInfo[index].priority == ObjectPriority.high,
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
        'Gestures active · Ultralytics engine',
        style: TextStyle(color: Colors.white, fontSize: 12),
      ),
    );
  }
}
