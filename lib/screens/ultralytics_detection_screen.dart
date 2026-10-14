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
import '../services/engine_coordinator.dart';
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
import '../widgets/detection_action_controls.dart';
import '../widgets/detection_correction_sheet.dart';
import '../widgets/detection_information_overlay.dart';
import '../widgets/detection_state_panel.dart';
import '../widgets/gesture_surface.dart';
import '../widgets/status_pill.dart';

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

/// Decides whether a Start request must recreate the native detection session.
///
/// Native `YOLOView.stop()` permanently destroys the predictor (it closes and
/// nulls `predictor`, clears the predictor cache, and nulls the callbacks), and
/// `startCamera()` early-returns while `predictor == null`. The plugin's own
/// comment confirms `stop()` is not reversible by `start()`. The only path to
/// Ready is the native `onModelLoad` callback, which fires on `YOLOView`
/// mount/model resolution and therefore never re-fires after a stop.
///
/// A fresh platform view must therefore be mounted on a start-after-stop. This
/// pure helper returns `true` exactly when the native session must be recreated
/// (a start after a stop), and `false` for a first start (the view is already
/// mounting) or a resume from pause (the predictor is still alive). It is pure
/// so the epoch decision is unit-testable without a native/camera dependency.
bool shouldRecreateNativeSessionOnStart({
  required bool nativeViewMounted,
  required bool detectionActive,
  required bool paused,
}) {
  // First start: the native view is not mounted yet, so the normal mount path
  // already resolves the model and fires `onModelLoad`.
  if (!nativeViewMounted) return false;
  // Resume from pause: the predictor was never destroyed, so no recreation.
  if (detectionActive && paused) return false;
  // Start after a stop: the predictor is gone and must be recreated.
  return true;
}

class UltralyticsDetectionScreen extends StatefulWidget {
  final SettingsService settings;
  final TtsService tts;
  final TelemetryService telemetry;
  final CorrectionService? corrections;
  final HapticsService haptics;

  /// The single app-shell-owned Detection lifecycle/status source.
  ///
  /// The engine reports lifecycle/failure facts to it and renders its visible
  /// status pill and state panel from this snapshot. It never derives visible
  /// lifecycle status from engine-local booleans.
  final EngineCoordinator coordinator;

  /// The one-shot start request issued by the app-shell-owned coordinator.
  ///
  /// The engine consumes it exactly once by comparing its token with the token
  /// it last consumed. A silent launch intent must not produce start haptics or
  /// speech; an entry intent uses the existing start route.
  final StartIntent? startIntent;

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
    required this.coordinator,
    this.startIntent,
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

  /// The underlying assistive/correction detection state.
  ///
  /// PD1 removes the normal visible card list, but the assistive layer's
  /// analysis output is retained as the source for correction context and
  /// telemetry. The compact overlay renders [_overlayInfos] instead, which is
  /// the presentation-only snapshot gated on the mapped Ready outcome.
  // ignore: unused_field
  List<DetectionInfo> _detectionInfo = const [];

  /// The presentation-only snapshot rendered by [DetectionInformationOverlay].
  ///
  /// This is deliberately separate from [_detectionInfo] (the underlying
  /// assistive/correction state). The overlay snapshot is cleared synchronously
  /// whenever the mapped coordinator outcome leaves Ready and is only accepted
  /// while the currently observed mapped outcome is Ready.
  ///
  /// PD3 freshness limitation (see plan §13): this presentation-local gate
  /// prevents *known historical* rows from remaining visible after a
  /// non-Ready transition, but it cannot prove that an asynchronous native
  /// result produced before a transition will never arrive after a later Ready
  /// transition. The native `onResult` callback delivers a bare
  /// `List<YOLOResult>` with no screen/session epoch, so a late pre-transition
  /// callback is indistinguishable from a valid new Ready callback here. A
  /// strict guarantee requires a narrow cross-layer result envelope
  /// (correlating the native streaming frame/timestamp metadata with converted
  /// results, or a screen-to-native session bridge) and explicit approval
  /// before touching the adapter/native boundary.
  List<DetectionInfo> _overlayInfos = const [];

  bool _detectionActive = false;

  /// Whether the native YOLOView shell has been mounted at least once.
  ///
  /// PD1 stopped-shell parity: once true, the native viewport shell and the
  /// viewport GestureSurface are retained after a manual Stop instead of being
  /// replaced by [_buildCameraPending]. This keeps the viewport layout, gesture
  /// handling, and horizontal navigation reachable while stopped.
  bool _nativeViewMounted = false;

  /// Local native-view epoch.
  ///
  /// Included in the [YOLOView] key so a start-after-stop mounts a *fresh*
  /// platform view. Native `stop()` permanently destroys the predictor and
  /// `startCamera()` early-returns while it is null, so the only way to reach
  /// Ready again is to remount the view and let `_resolveModel()` run and fire
  /// `onModelLoad` once more. Bumped only when a start-after-stop requires a
  /// new native session (see [shouldRecreateNativeSessionOnStart]).
  int _nativeViewEpoch = 0;

  /// The epoch whose `onModelLoad` is allowed to publish Ready.
  ///
  /// A stale `onModelLoad` from a previous epoch (e.g. a late callback from the
  /// view being torn down) must never be treated as the current session's
  /// Ready. The callback captures the epoch it was built with and is ignored
  /// unless it matches this field.
  int _activeNativeEpoch = 0;

  /// Guards against duplicate/overlapping start attempts.
  ///
  /// Set synchronously at the top of [_startDetection] before any `await`, so a
  /// second Start (button, gesture, or start intent) cannot begin a second
  /// native session while the first is still being established.
  bool _startInFlight = false;

  /// Whether the first fresh native result of the current session was logged.
  ///
  /// Reset on each start so the diagnostic fires once per session rather than
  /// once per frame.
  bool _firstResultLogged = false;

  bool _paused = false;
  bool _permissionDenied = false;
  bool _starting = false;
  bool _lastLowPowerMode = false;
  String? _modelError;
  DetectionRuntimeState _runtimeState = DetectionRuntimeState.idle;

  /// The most recent native inference latency in milliseconds.
  ///
  /// PD1 removes the visible developer metrics, but this value is still passed
  /// to the shared assistive layer for telemetry, so it is retained.
  double _inferenceMs = 0;

  /// The start-intent token this engine has already consumed. Guards against
  /// acting on the same request twice (e.g. across rebuilds).
  int? _consumedStartIntentToken;

  YOLOStreamingConfig get _streamingConfig => YOLOStreamingConfig(
    inferenceFrequency: _settings.lowPowerMode ? 4 : null,
  );

  @override
  void initState() {
    super.initState();
    _lastLowPowerMode = _settings.lowPowerMode;
    _settings.addListener(_handleSettingsChanged);
    _loadLabels();
    // The engine no longer reads the Auto-start preference directly. It acts
    // only on the shared start intent issued by the app-shell coordinator.
    if (widget.startIntent != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _consumeStartIntent(widget.startIntent);
      });
    }
  }

  @override
  void didUpdateWidget(covariant UltralyticsDetectionScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.startIntent?.token != oldWidget.startIntent?.token) {
      _consumeStartIntent(widget.startIntent);
    }
  }

  /// Consumes a shared start intent exactly once.
  ///
  /// A silent launch intent starts without start haptics or speech; an entry
  /// intent uses the existing start route. An already-consumed token is
  /// ignored, and the existing `_starting`/`_detectionActive` guard in
  /// [_startDetection] prevents a duplicate start.
  void _consumeStartIntent(StartIntent? intent) {
    if (intent == null) return;
    if (_consumedStartIntentToken == intent.token) return;
    _consumedStartIntentToken = intent.token;
    if (intent.origin == StartIntentOrigin.launch) {
      _startDetection(announce: false, haptic: false);
    } else {
      _startDetection();
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
    // Duplicate/overlapping start guard. `_startInFlight` is set synchronously
    // before any `await` so a second Start cannot begin a second native session
    // while the first is still being established.
    if (_startInFlight || _starting || _detectionActive) return;
    _startInFlight = true;
    debugPrint(
      '[Ultralytics] Start requested — coordinator=${widget.coordinator.state} '
      'local(active=$_detectionActive paused=$_paused '
      'mounted=$_nativeViewMounted epoch=$_nativeViewEpoch)',
    );
    try {
      if (haptic) await _haptics.mediumTick();
      if (mounted) setState(() => _starting = true);
      if (!await _ensureCameraPermission()) return;
      if (!mounted) return;

      // A start after a stop must recreate the native session: native `stop()`
      // permanently destroys the predictor and `startCamera()` is a no-op while
      // it is null, so the only path back to Ready is a fresh platform view
      // whose `_resolveModel()` fires `onModelLoad` again. A first start or a
      // resume from pause must NOT bump the epoch.
      final recreate = shouldRecreateNativeSessionOnStart(
        nativeViewMounted: _nativeViewMounted,
        detectionActive: _detectionActive,
        paused: _paused,
      );
      setState(() {
        _detectionActive = true;
        // The native YOLOView shell is now (or will be) mounted; retain it after
        // a later manual Stop for PD1 stopped-shell parity.
        _nativeViewMounted = true;
        _paused = false;
        _starting = false;
        _modelError = null;
        // Re-arm the once-per-session first-result diagnostic.
        _firstResultLogged = false;
        if (recreate) {
          _nativeViewEpoch++;
          _activeNativeEpoch = _nativeViewEpoch;
        }
      });
      if (recreate) {
        debugPrint(
          '[Ultralytics] Native session reinit requested — new epoch '
          '$_nativeViewEpoch (fresh YOLOView mount)',
        );
      }
      // Keep the coordinator at Preparing until native detection is genuinely
      // operational; Ready is published only from the epoch-guarded
      // `onModelLoad` callback.
      _setRuntimeState(DetectionRuntimeState.loadingModel);
      if (announce) await _tts.speak('Detection started', urgent: true);
    } finally {
      _startInFlight = false;
    }
  }

  Future<void> _stopDetection() async {
    debugPrint(
      '[Ultralytics] Stop requested — coordinator=${widget.coordinator.state} '
      'local(active=$_detectionActive paused=$_paused epoch=$_nativeViewEpoch)',
    );
    await _haptics.mediumTick();
    // The native controller may stop internally, but the native YOLOView shell
    // and the viewport GestureSurface remain mounted (see [_buildMainArea]) so
    // the stopped screen keeps its layout, gesture handling, and horizontal
    // navigation. PD1 stopped-shell parity with the Custom screen.
    //
    // Native `stop()` permanently destroys the predictor; the retained shell is
    // therefore a visual/gesture shell only. A later Start recreates the native
    // session by bumping [_nativeViewEpoch] (see [_startDetection]).
    await _controller.stop();
    if (!mounted) return;
    setState(() {
      _detectionActive = false;
      _paused = false;
      _detectionInfo = const [];
      // PD3: clear the displayed overlay snapshot immediately on stop.
      _overlayInfos = const [];
      _inferenceMs = 0;
    });
    // Publish an explicit shared Stopped state (not idle) so a retained-session
    // tab leave/return does not auto-restart.
    _setRuntimeState(DetectionRuntimeState.stopped);
    debugPrint('[Ultralytics] Stop teardown complete — coordinator=stopped');
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
    if (!_firstResultLogged) {
      _firstResultLogged = true;
      debugPrint(
        '[Ultralytics] First fresh result received — epoch $_nativeViewEpoch '
        '(${results.length} raw results)',
      );
    }
    final detections = UltralyticsDetectionAdapter.convert(results, _labels);
    final infos = _assistive.updateDetections(
      detections,
      latencyMs: _inferenceMs,
    );
    // PD3: accept a new overlay snapshot only while the currently observed
    // mapped coordinator outcome is Ready (healthy fallback maps to Ready).
    // This is a presentation-local gate; see the [_overlayInfos] doc comment
    // for the residual delayed-result freshness limitation.
    final overlayEligible = _overlayEligible;
    if (mounted) {
      setState(() {
        _detectionInfo = infos;
        if (overlayEligible) {
          _overlayInfos = infos;
        }
      });
    }
  }

  void _handleMetrics(YOLOPerformanceMetrics metrics) {
    if (!_detectionActive || _paused) return;
    final inferenceMs = metrics.inferenceMs > 0
        ? metrics.inferenceMs
        : metrics.processingTimeMs;
    // PD1: the visible developer metrics are removed, but the metric values are
    // still recorded for telemetry (Logs & Reports) and the latest inference
    // latency is retained for the shared assistive layer.
    if (mounted) {
      setState(() => _inferenceMs = inferenceMs);
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

  /// Retained correction-capture path.
  ///
  /// PD1 removes the normal visible correction/report affordance, but the
  /// correction service, persistence, and sheet infrastructure remain in
  /// scope to preserve. This method is intentionally kept (not deleted) so the
  /// supporting system stays wired; it is currently unreferenced from the
  /// normal layout.
  // ignore: unused_element
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

  /// Retained correction-context accessor for the correction-capture path.
  ///
  /// Kept alongside [_reportCorrection] so the correction infrastructure stays
  /// wired even though PD1 removes its normal visible trigger.
  // ignore: unused_element
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
    setState(() {
      _runtimeState = state;
      // PD3: clear the displayed overlay snapshot synchronously whenever the
      // mapped outcome leaves Ready. The coordinator snapshot is the single
      // source of the visible lifecycle, so this uses the same mapping.
      if (detectionStatusOutcomeFor(state) != DetectionStatusOutcome.ready) {
        _overlayInfos = const [];
      }
    });
    debugPrint(
      '[Ultralytics] Child lifecycle report emitted — state=$state '
      'epoch=$_nativeViewEpoch',
    );
    widget.onRuntimeStateChanged?.call(state, null);
    debugPrint(
      '[Ultralytics] Coordinator accepted lifecycle report — '
      'coordinator=${widget.coordinator.state} '
      'mapped=${detectionStatusOutcomeFor(widget.coordinator.state)}',
    );
  }

  void _reportFailure(DetectionFailure failure) {
    if (!mounted) return;
    setState(() {
      _runtimeState = DetectionRuntimeState.failed;
      _starting = false;
      _detectionActive = false;
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
        // PD2: the three-finger Quick Scan gesture is gated by the shared
        // mapped outcome — Ready (including healthy fallback) only. It does
        // nothing for Paused, Stopped, Preparing, or Unavailable. The gate
        // lives here in screen dispatch, so GestureController is unchanged.
        if (_overlayEligible) _quickScan();
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

  /// Maps the shared coordinator snapshot to the visible status pill.
  ///
  /// This is the single user-facing lifecycle mapping shared with Home and the
  /// Custom engine; it never reads engine-local booleans.
  (String, Color) _sharedStatusPresentation(DetectionRuntimeState state) =>
      switch (detectionStatusOutcomeFor(state)) {
        DetectionStatusOutcome.preparing => ('Preparing', kStatusBlue),
        DetectionStatusOutcome.ready => ('Detecting', kStatusGreen),
        DetectionStatusOutcome.paused => ('Paused', kStatusAmber),
        DetectionStatusOutcome.stopped => ('Stopped', kStatusBlueGrey),
        DetectionStatusOutcome.unavailable => ('Unavailable', kWarningRed),
      };

  /// Whether the compact information overlay is eligible to render.
  ///
  /// Eligible only for the mapped Ready outcome, which includes a healthy
  /// temporary fallback. Every other visible lifecycle outcome hides it.
  bool get _overlayEligible =>
      detectionStatusOutcomeFor(widget.coordinator.state) ==
      DetectionStatusOutcome.ready;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: buildHomeTheme(),
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.dark,
        child: Scaffold(
          body: SafeArea(
            child: Column(
              children: [
                _buildTopBar(context),
                // The viewport is the only flexible region; the control row
                // below derives its height from its content and the minimum
                // touch targets rather than a fixed percentage allocation.
                Expanded(child: _buildMainArea(context)),
                _buildActionControlsRow(context),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar(BuildContext context) {
    final theme = Theme.of(context);
    // The visible status pill renders the shared coordinator snapshot, never
    // engine-local booleans. Local flags remain only for native controller and
    // inference mechanics.
    final (label, color) = _sharedStatusPresentation(widget.coordinator.state);
    return Padding(
      padding: const EdgeInsets.fromLTRB(kSpace16, kSpace16, kSpace16, kSpace8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // The header uses the ink token so it stays legible against the
          // light Detection surface. No other header element or behavior
          // changes.
          Text(
            'Detection Mode',
            style: theme.textTheme.titleLarge?.copyWith(color: kHomeInk),
          ),
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
          // PD1: the visible developer metrics (FPS, inference latency, native
          // total time) are removed from the normal UI. Metric collection in
          // [_handleMetrics] is preserved so Logs & Reports is unaffected.
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
    // The visible lifecycle/status panel renders the shared coordinator
    // snapshot, never engine-local runtime state.
    final sharedState = widget.coordinator.state;
    if (sharedState == DetectionRuntimeState.failed) {
      return DetectionStatePanel(
        state: sharedState,
        failure: widget.coordinator.failure,
        onRetry: _retryRuntime,
        onStop: _stopDetection,
      );
    }
    if (_permissionDenied) return _buildPermissionDenied(context);
    // PD1 stopped-shell parity: once the native view has been mounted (i.e.
    // detection has been started at least once), the native YOLOView shell and
    // the viewport GestureSurface are retained even after a manual Stop. The
    // native controller may stop internally, but the shell stays mounted so the
    // viewport layout, gesture handling, and horizontal navigation remain
    // reachable. Only a never-started screen falls back to the pending surface.
    //
    // Residual limitation (Needs Verification [external-runtime]): the retained
    // native texture after stop may render frozen, cleared, or inactive on a
    // physical device. This must be observed on the target device; the shell is
    // retained regardless so gesture/layout ownership is preserved.
    if (!_detectionActive && !_nativeViewMounted) {
      return _buildCameraPending(context);
    }
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
            // The epoch is part of the key so a start-after-stop mounts a fresh
            // platform view. Native `stop()` permanently destroys the predictor
            // and `startCamera()` is a no-op while it is null, so remounting is
            // the only way `_resolveModel()` runs and `onModelLoad` fires again.
            key: ValueKey('ultralytics-native-$_nativeViewEpoch'),
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
              // Ignore a stale `onModelLoad` from a previous epoch (e.g. a late
              // callback from the view being torn down) so it is never treated
              // as the current session's Ready.
              if (_nativeViewEpoch != _activeNativeEpoch) {
                debugPrint(
                  '[Ultralytics] Ignoring stale onModelLoad — callback epoch '
                  '$_nativeViewEpoch != active $_activeNativeEpoch',
                );
                return;
              }
              debugPrint(
                '[Ultralytics] Native model loaded — epoch $_nativeViewEpoch; '
                'reporting Ready',
              );
              if (mounted) {
                setState(() {
                  _modelError = null;
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
          // Compact current-information overlay (PD3). Pointer-inert, so it
          // never consumes raw pointers intended for the gesture surface.
          DetectionInformationOverlay(
            infos: _overlayInfos,
            eligible: _overlayEligible,
          ),
          // Thesis gesture capture layer (transparent, topmost).
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

  /// The single non-scrolling, side-by-side physical-control row.
  ///
  /// The left lifecycle control is driven only by the coordinator-derived
  /// outcome; the right control is the tap-only physical Quick Scan. The row
  /// sits outside the viewport stack so it never participates in viewport
  /// gesture recognition.
  Widget _buildActionControlsRow(BuildContext context) {
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
          // IntrinsicHeight bounds the row's cross-axis height so the shared
          // control's `CrossAxisAlignment.stretch` row can lay out inside the
          // non-flexible Column slot without an unbounded-height constraint.
          child: IntrinsicHeight(
            child: DetectionActionControls(
              outcome: detectionStatusOutcomeFor(widget.coordinator.state),
              onPause: _pauseDetection,
              onResume: _resumeDetection,
              onStop: _stopDetection,
              onStart: _startDetection,
              onQuickScan: _quickScan,
            ),
          ),
        ),
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
