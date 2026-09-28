import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle, SystemUiOverlayStyle;
import 'package:permission_handler/permission_handler.dart';
import 'package:ultralytics_yolo/ultralytics_yolo.dart';

import '../models/app_settings.dart';
import '../models/detection_info.dart';
import '../models/detection_runtime_state.dart';
import '../models/model_config.dart';
import '../services/assistive_detection_controller.dart';
import '../services/correction_service.dart';
import '../services/gesture_controller.dart';
import '../services/haptics_service.dart';
import '../services/settings_service.dart';
import '../services/telemetry_service.dart';
import '../services/tts_service.dart';
import '../services/ultralytics_detection_adapter.dart';
import '../theme/app_colors.dart';
import '../theme/app_home_theme.dart';
import '../theme/app_radii.dart';
import '../theme/app_spacing.dart';
import '../widgets/accessible_button.dart';
import '../widgets/detection_card.dart';
import '../widgets/detection_correction_sheet.dart';
import '../widgets/detection_state_panel.dart';
import '../widgets/gesture_surface.dart';
import '../widgets/status_pill.dart';
import '../widgets/warning_banner.dart';

/// Maps a horizontal gesture intent to a relative primary-tab direction.
///
/// Product Decision 2: a left swipe advances to the next tab (`+1`) and a
/// right swipe returns to the previous tab (`-1`). Returns `null` for any
/// non-horizontal gesture. Pure so both Detection engines can be tested
/// without a camera/native dependency.
int? relativeDirectionForGesture(EyeCueGesture gesture) {
  return switch (gesture) {
    EyeCueGesture.swipeLeft => 1,
    EyeCueGesture.swipeRight => -1,
    _ => null,
  };
}

class UltralyticsDetectionScreen extends StatefulWidget {
  final SettingsService settings;
  final TtsService tts;
  final TelemetryService telemetry;
  final CorrectionService? corrections;
  final HapticsService haptics;

  /// Requests one relative primary-tab move from the shell (`-1` toward Home,
  /// `+1` toward Help). The shell owns boundary handling and feedback.
  final void Function(int direction)? onNavigateRelative;

  /// Native callbacks do not have a Dart worker generation. The coordinator
  /// receives null for this source-generation field and relies on the mounted
  /// child generation instead.
  final void Function(DetectionRuntimeState state, int? sourceGeneration)?
  onRuntimeStateChanged;
  final void Function(DetectionFailure failure, int? sourceGeneration)?
  onFailure;

  const UltralyticsDetectionScreen({
    super.key,
    required this.settings,
    required this.tts,
    required this.telemetry,
    this.corrections,
    required this.haptics,
    this.onNavigateRelative,
    this.onRuntimeStateChanged,
    this.onFailure,
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
  late final AssistiveDetectionController _assistive =
      AssistiveDetectionController(
        engine: InferenceEngine.ultralytics,
        tts: _tts,
        telemetry: _telemetry,
        corrections: widget.corrections,
        confidenceThreshold: _settings.detectionConfidence,
      );

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
  DetectionRuntimeState _runtimeState = DetectionRuntimeState.idle;
  DetectionFailure? _failure;
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
    _assistive.dispose();
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
    _setRuntimeState(DetectionRuntimeState.requestingPermission);
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
    _reportFailure(
      DetectionFailure(
        category: DetectionFailureCategory.permissionDenied,
        safeMessage:
            'Camera permission is required to detect objects. Allow camera access in Settings.',
        technicalDetail: 'Camera permission status: $status',
        engine: InferenceEngine.ultralytics,
        timestamp: DateTime.now(),
      ),
    );
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
      _failure = null;
    });
    _setRuntimeState(DetectionRuntimeState.loadingModel);
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
    _setRuntimeState(DetectionRuntimeState.idle);
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
    _setRuntimeState(DetectionRuntimeState.paused);
    await _tts.speak('Detection paused', urgent: true);
  }

  Future<void> _resumeDetection() async {
    if (!_detectionActive || !_paused) return;
    await _haptics.lightTick();
    await _controller.resume();
    if (mounted) setState(() => _paused = false);
    _setRuntimeState(DetectionRuntimeState.ready);
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
    final infos = _assistive.updateDetections(
      detections,
      latencyMs: _inferenceMs,
    );
    if (mounted) setState(() => _detectionInfo = infos);
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
    _assistive.recordMetrics(latencyMs: inferenceMs, inferenceFps: metrics.fps);
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
    if (_tts.lastAnnouncedEngine != InferenceEngine.ultralytics) return null;
    return _tts.lastAnnouncedDetection;
  }

  void _toggleAudio() {
    final enabled = !_settings.audioEnabled;
    _settings.setAudioEnabled(enabled);
    _tts.setAudioEnabled(enabled);
    if (enabled) _tts.speak('Audio on', urgent: true);
  }

  void _setRuntimeState(DetectionRuntimeState state) {
    if (!mounted || _runtimeState == state) return;
    setState(() => _runtimeState = state);
    widget.onRuntimeStateChanged?.call(state, null);
  }

  void _reportFailure(DetectionFailure failure) {
    if (!mounted) return;
    setState(() {
      _failure = failure;
      _runtimeState = DetectionRuntimeState.failed;
      _starting = false;
      _detectionActive = false;
      _modelLoaded = false;
      _modelError = failure.userMessage;
    });
    if (widget.onFailure != null) {
      widget.onFailure!(failure, null);
    } else {
      _telemetry.recordFailure(failure);
    }
  }

  void _retryRuntime() {
    if (!mounted) return;
    setState(() {
      _failure = null;
      _modelError = null;
      _permissionDenied = false;
    });
    _startDetection();
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
      case EyeCueGesture.swipeLeft:
      case EyeCueGesture.swipeRight:
        final direction = relativeDirectionForGesture(gesture);
        if (direction != null) {
          widget.onNavigateRelative?.call(direction);
        }
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
    return Theme(
      data: buildHomeTheme(),
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.dark,
        child: Scaffold(
          body: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final contentHeight = (constraints.maxHeight * 0.32).clamp(
                  260.0,
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
        ),
      ),
    );
  }

  Widget _buildTopBar(BuildContext context) {
    final theme = Theme.of(context);
    final (label, color) = !_detectionActive
        ? ('Stopped', kStatusBlueGrey)
        : _paused
        ? ('Paused', kStatusAmber)
        : !_modelLoaded
        ? ('Loading', kStatusBlue)
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
                  final enabled = _settings.audioEnabled;
                  return _AudioPill(
                    on: enabled,
                    onPressed: _toggleAudio,
                    tooltip: enabled
                        ? 'Mute audio guidance'
                        : 'Unmute audio guidance',
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: kSpace4),
          Wrap(
            spacing: kSpace8,
            runSpacing: kSpace4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
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
              style: theme.textTheme.bodySmall?.copyWith(color: kHomeInkMuted),
            ),
          if (_modelError != null)
            Text(
              _modelError!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(color: kWarningRed),
            ),
        ],
      ),
    );
  }

  Widget _buildMainArea(BuildContext context) {
    if (_runtimeState == DetectionRuntimeState.failed) {
      return DetectionStatePanel(
        state: _runtimeState,
        failure: _failure,
        onRetry: _retryRuntime,
        onStop: _stopDetection,
      );
    }
    if (_permissionDenied) return _buildPermissionDenied(context);
    if (!_detectionActive) return _buildCameraPending(context);
    // Rounded dark card around the native YOLOView. The native overlay is
    // unchanged; only the surrounding container (dark fill + rounded clip) is
    // added so the light chrome never sits over the camera surface.
    return Container(
      decoration: BoxDecoration(
        color: kHomeInk,
        borderRadius: BorderRadius.circular(kRadius24),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          YOLOView(
            modelPath: EyeCueModelConfig.modelAssetPath,
            task: YOLOTask.detect,
            controller: _controller,
            confidenceThreshold: _settings.detectionConfidence,
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
                  _failure = null;
                });
              }
              _setRuntimeState(DetectionRuntimeState.ready);
            },
            onModelError: (error, _, _) {
              _reportFailure(
                DetectionFailure(
                  category: DetectionFailureCategory.modelLoading,
                  safeMessage:
                      'The recommended detection engine could not load its model.',
                  technicalDetail: '$error',
                  engine: InferenceEngine.ultralytics,
                  timestamp: DateTime.now(),
                  fallbackAvailable: true,
                ),
              );
            },
          ),
          const Align(alignment: Alignment.bottomCenter, child: _GestureHint()),
          GestureSurface(
            controller: _gestureController,
            child: const SizedBox.expand(),
          ),
        ],
      ),
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
                if (_warningMessage != null)
                  WarningBanner(message: _warningMessage!),
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
        onReport: widget.corrections == null
            ? null
            : () => _reportCorrection(_detectionInfo[index]),
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
        'Gestures active · Ultralytics engine',
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
