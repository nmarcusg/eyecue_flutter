import 'dart:async';

import 'package:camera/camera.dart' show CameraLensDirection, availableCameras;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle, SystemUiOverlayStyle;
import 'package:permission_handler/permission_handler.dart';
import 'package:ultralytics_yolo/ultralytics_yolo.dart';

import '../models/app_settings.dart';
import '../models/box_transform.dart';
import '../models/detection.dart';
import '../models/detection_info.dart';
import '../models/detection_runtime_state.dart';
import '../models/detector_model.dart';
import '../models/detector_stage_timings.dart';
import '../models/model_config.dart';
import '../models/tracked_detection.dart';
import '../services/assistive_detection_controller.dart';
import '../services/correction_service.dart';
import '../services/depth_distance_service.dart';
import '../services/detector_model_service.dart';
import '../services/engine_coordinator.dart';
import '../services/gesture_controller.dart';
import '../services/haptics_service.dart';
import '../services/inference_cadence.dart';
import '../services/monocular_depth_estimator.dart';
import '../services/settings_service.dart';
import '../services/telemetry_service.dart';
import '../services/tts_service.dart';
import '../services/ultralytics_detection_adapter.dart';
import '../theme/app_colors.dart';
import '../theme/app_home_theme.dart';
import '../theme/app_radii.dart';
import '../theme/app_spacing.dart';
import '../widgets/accessible_button.dart';
import '../widgets/bounding_box_painter.dart';
import '../widgets/depth_heatmap_view.dart';
import '../widgets/detection_action_controls.dart';
import '../widgets/detection_correction_sheet.dart';
import '../widgets/detection_information_overlay.dart';
import '../widgets/detection_state_panel.dart';
import '../widgets/gesture_surface.dart';
import '../widgets/status_pill.dart';
import '../widgets/warning_banner.dart';

/// Non-blocking notice shown when the depth model cannot provide estimates.
const String kDepthDegradedMessage =
    'Depth estimate unavailable. Distance uses the bounding box instead.';

/// Shown after the selected detector changed, until the next Start.
const String kModelChangedMessage =
    'Detector model changed. Detection is stopped — press Start to use the '
    'new model.';

/// Presentation flags for the viewport overlay layers.
///
/// Exactly one of the two box renderers is active at a time: native overlays
/// while the heatmap is hidden, Flutter-painted boxes while it is visible (so
/// labels stay above the heatmap).
class DepthOverlayState {
  const DepthOverlayState({
    required this.heatmapVisible,
    required this.flutterBoxes,
    required this.nativeOverlays,
  });

  final bool heatmapVisible;
  final bool flutterBoxes;
  final bool nativeOverlays;

  static DepthOverlayState resolve({
    required bool mdeEnabled,
    required bool showDepthHeatmap,
    required bool showBoundingBoxes,
    required bool heatmapFresh,
  }) {
    final heatmapVisible = mdeEnabled && showDepthHeatmap && heatmapFresh;
    return DepthOverlayState(
      heatmapVisible: heatmapVisible,
      flutterBoxes: heatmapVisible && showBoundingBoxes,
      nativeOverlays: showBoundingBoxes && !heatmapVisible,
    );
  }
}

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
/// Ready is the first valid inference payload from the mounted native view.
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

/// Builds the native streaming config for a resolved cadence.
///
/// `inferenceFrequency` is the detector target in Hz (`null` = Automatic). The depth
/// target reaches native as an instance id plus a tick interval; no image flag is set
/// any more, so no analysis frame crosses the platform channel. Pure so the cadence
/// mapping is testable without a platform view.
@visibleForTesting
YOLOStreamingConfig buildStreamingConfig({
  required int? effectiveDetectionHz,
  required String? depthInstanceId,
  required int? depthIntervalMs,
}) => YOLOStreamingConfig(
  inferenceFrequency: effectiveDetectionHz,
  depthInstanceId: depthInstanceId,
  depthIntervalMs: depthIntervalMs,
  depthMaxDim: EyeCueModelConfig.depthGridMaxDim,
);

/// The subset of the streaming config that changes native behaviour.
///
/// Only these values justify a live `setStreamingConfig`; an overlay-only change must
/// not touch the native view. The depth target is included because it now reaches
/// native (the instance to tick and how often).
@visibleForTesting
({int? hz, String? depthInstanceId, int? depthIntervalMs}) streamingConfigKey({
  required InferenceCadence cadence,
  required bool mdeEnabled,
  required String? depthInstanceId,
}) => (
  hz: cadence.effectiveDetectionHz,
  depthInstanceId: mdeEnabled ? depthInstanceId : null,
  depthIntervalMs: mdeEnabled ? cadence.depthInterval?.inMilliseconds : null,
);

/// Whether a heatmap should be constructed at all: MDE on and the overlay on.
///
/// Pure so the presentation→construction gate is testable without a camera. It
/// deliberately ignores staleness: freshness only decides whether the map is
/// shown, and gating construction on it would need the very frame the gate
/// governs (a hidden heatmap would then never be rebuilt).
@visibleForTesting
bool heatmapRequested({
  required bool mdeEnabled,
  required bool showDepthHeatmap,
}) => mdeEnabled && showDepthHeatmap;

/// Depth status recorded with a telemetry sample.
///
/// `disabled` wins when depth work is off; the model state then decides
/// `degraded`/`loading`; a loaded model reports `gpu` or `cpu`. Pure so the
/// mapping is testable without native models.
String depthStatusFor({
  required bool mdeEnabled,
  required DepthRunState state,
  required String? accelerator,
}) {
  if (!mdeEnabled) return 'disabled';
  if (state == DepthRunState.degraded) return 'degraded';
  if (state == DepthRunState.loading) return 'loading';
  final accel = accelerator;
  // No model instance yet, so the accelerator is not known.
  if (accel == null) return 'loading';
  return accel == 'gpu' ? 'gpu' : 'cpu';
}

/// Whether a depth retry has to re-arm the model load.
///
/// A load failure leaves no instance at all, so `retry()` alone would only drop
/// the banner and leave depth dead with no further affordance. A native
/// inference failure keeps its instance, so the state change alone re-pushes the
/// instance id and clears the native latch. Pure so the decision is testable
/// without a camera or a model.
@visibleForTesting
bool depthNeedsReload({
  required String? instanceId,
  required bool modelLoadFailed,
}) => instanceId == null || modelLoadFailed;

class UltralyticsDetectionScreen extends StatefulWidget {
  final SettingsService settings;
  final TtsService tts;
  final TelemetryService telemetry;
  final CorrectionService? corrections;
  final HapticsService haptics;

  /// The researcher's detector selection.
  ///
  /// When absent, the built-in asset path and label list are used, so the
  /// engine's pre-selection behaviour is unchanged for widget tests.
  final DetectorModelService? detectorModel;

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
  final Duration readinessTimeout;

  const UltralyticsDetectionScreen({
    super.key,
    required this.settings,
    required this.tts,
    required this.telemetry,
    this.corrections,
    required this.haptics,
    required this.coordinator,
    this.detectorModel,
    this.startIntent,
    this.onNavigateRelative,
    this.onRuntimeStateChanged,
    this.onFailure,
    this.readinessTimeout = const Duration(seconds: 30),
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
        // A custom model decides priority by its own label text, never by a
        // COCO class id.
        priorityResolver: (d) =>
            priorityForClass(_modelKind, d.classId, d.label),
        // Rows carry the model active when they were recorded, so switching or
        // renaming later cannot relabel history.
        detectorModel: widget.detectorModel?.current.ref,
      );

  late final GestureController _gestureController = GestureController(
    onGesture: _onGesture,
  );

  /// Asset label list. Used only when no [DetectorModelService] was supplied.
  List<String> _assetLabels = const [];

  /// The active model's own label list — never the built-in one for a custom
  /// model.
  List<String> get _labels =>
      widget.detectorModel?.current.labels ?? _assetLabels;

  DetectorModelKind get _modelKind =>
      widget.detectorModel?.current.kind ?? DetectorModelKind.builtIn;

  String get _modelPath =>
      widget.detectorModel?.current.path ?? EyeCueModelConfig.modelAssetPath;

  /// True after the selected model changed and before the next Start, so the UI
  /// can state that detection has to be started again.
  bool _modelChangeNotice = false;

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
  /// PD1 stopped-shell parity: once true, the native viewport shell is retained
  /// after a manual Stop instead of being replaced by [_buildCameraPending].
  /// This keeps the viewport layout and horizontal navigation reachable while
  /// stopped.
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

  /// The epoch whose native-view callbacks still belong to the live session.
  ///
  /// The callback captures the epoch it was built with and is ignored unless it
  /// matches this field.
  int _activeNativeEpoch = 0;
  Timer? _readinessTimer;
  bool _pausedWhileLoading = false;

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

  /// Streaming values last applied to the native view.
  ///
  /// Only a change here (effective detector Hz, or the depth instance and
  /// interval) warrants a live `setStreamingConfig`.
  ({int? hz, String? depthInstanceId, int? depthIntervalMs})?
  _lastStreamingConfigKey;
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

  // --- Monocular depth (MDE) ------------------------------------------------
  //
  // MDE is a SECOND model instance run natively on the analysis frame the view
  // already decoded for detection. It never blocks detection: sampling uses the
  // latest fresh grid and falls back to the bounding-box estimator whenever the
  // grid is missing, stale or mismatched.

  final MonocularDepthEstimator _depth = MonocularDepthEstimator();

  /// Native depth events, on the same view event channel as zoom/lens/focus.
  StreamSubscription<YOLODepthEvent>? _depthEventSub;
  final DepthSmoother _depthSmoother = DepthSmoother();

  /// Latest detection boxes, retained so the Flutter box layer and the depth
  /// sampler both read the same frame.
  List<Detection> _latestDetections = const [];

  /// Tracks from the previous assistive frame, used to key EMA smoothing.
  List<TrackedDetection> _lastTracks = const [];

  int _uprightWidth = 0;
  int _uprightHeight = 0;
  int _rotationDegrees = 0;
  bool _rotationResolved = false;
  bool _rotationFailed = false;
  DistanceEstimationMode _lastDistanceMode =
      DistanceEstimationMode.monocularDepth;
  bool _overlaysShown = true;
  Timer? _freshnessTimer;

  bool get _mdeEnabled =>
      _settings.distanceEstimationMode == DistanceEstimationMode.monocularDepth;

  DepthFrame? get _depthFrame => _depth.frame.value;

  /// Whether the current depth map is fresh and matches the live geometry.
  bool get _depthFresh {
    final frame = _depthFrame;
    if (frame == null || !_rotationResolved) return false;
    return !frame.isStaleAt(DateTime.now().millisecondsSinceEpoch) &&
        frame.matchesGeometry(
          rotationDegrees: _rotationDegrees,
          uprightWidth: _uprightWidth,
          uprightHeight: _uprightHeight,
        );
  }

  DepthOverlayState get _overlayState => DepthOverlayState.resolve(
    mdeEnabled: _mdeEnabled,
    showDepthHeatmap: _settings.showDepthHeatmap,
    showBoundingBoxes: _settings.showBoundingBoxes,
    heatmapFresh: _depthFresh && _depthFrame?.heatmap != null,
  );

  bool get _heatmapVisible => _overlayState.heatmapVisible;

  bool get _depthDegraded =>
      _mdeEnabled &&
      (_depth.state.value == DepthRunState.degraded || _rotationFailed);

  /// Effective inference cadence, derived on read so it cannot drift from the
  /// stored settings.
  InferenceCadence get _cadence => InferenceCadence.resolve(
    requestedDetectionHz: _settings.detectionTargetHz,
    requestedDepthHz: _settings.depthTargetHz,
    lowPowerMode: _settings.lowPowerMode,
    distanceEstimationMode: _settings.distanceEstimationMode,
  );

  /// The instance the native tick may run, or null when it must not run.
  ///
  /// Null while MDE is off (no depth work) and while degraded (the instance is
  /// known to be failing, so ticking it would only burn CPU/GPU).
  String? get _depthInstanceId =>
      _mdeEnabled && _depth.state.value != DepthRunState.degraded
      ? _depth.instanceId
      : null;

  YOLOStreamingConfig get _streamingConfig => buildStreamingConfig(
    effectiveDetectionHz: _cadence.effectiveDetectionHz,
    depthInstanceId: _depthInstanceId,
    depthIntervalMs: _mdeEnabled
        ? _cadence.depthInterval?.inMilliseconds
        : null,
  );

  /// Pushes the streaming config when, and only when, a native-relevant value
  /// changed.
  void _syncStreamingConfig() {
    final key = streamingConfigKey(
      cadence: _cadence,
      mdeEnabled: _mdeEnabled,
      depthInstanceId: _depthInstanceId,
    );
    if (key == _lastStreamingConfigKey) return;
    _lastStreamingConfigKey = key;
    _controller.setStreamingConfig(_streamingConfig);
  }

  /// Builds heatmaps only while the overlay is on screen.
  ///
  /// Presentation-only: the depth tick, its cadence and the streaming-config key
  /// are untouched, so toggling the heatmap never restarts the camera or stops
  /// depth inference. While it is off a frame carries the grid alone, which
  /// keeps distance estimation and the box layer working.
  void _syncHeatmapGate() {
    _depth.heatmapEnabled = heatmapRequested(
      mdeEnabled: _mdeEnabled,
      showDepthHeatmap: _settings.showDepthHeatmap,
    );
  }

  /// Loads the depth model (once) so its instance id can reach the native tick,
  /// then re-syncs the config. Bounding-box mode passes a null instance, which
  /// stops the tick immediately.
  void _armDepth() {
    if (_mdeEnabled && _cadence.depthInterval != null) {
      unawaited(_depth.prepare());
    }
    _syncStreamingConfig();
  }

  @override
  void initState() {
    super.initState();
    _lastStreamingConfigKey = streamingConfigKey(
      cadence: _cadence,
      mdeEnabled: _mdeEnabled,
      depthInstanceId: _depthInstanceId,
    );
    _lastDistanceMode = _settings.distanceEstimationMode;
    _syncHeatmapGate();
    _settings.addListener(_handleSettingsChanged);
    _depth.frame.addListener(_handleDepthFrame);
    _depth.state.addListener(_handleDepthStateChanged);
    _depthEventSub = _controller.depthEvents.listen(_handleDepthEvent);
    widget.detectorModel?.addListener(_handleDetectorModelChanged);
    if (widget.detectorModel == null) _loadLabels();
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
    _readinessTimer?.cancel();
    _pausedWhileLoading = false;
    _settings.removeListener(_handleSettingsChanged);
    widget.detectorModel?.removeListener(_handleDetectorModelChanged);
    _freshnessTimer?.cancel();
    _depthEventSub?.cancel();
    _depth.frame.removeListener(_handleDepthFrame);
    _depth.state.removeListener(_handleDepthStateChanged);
    _depth.dispose();
    _gestureController.reset();
    _controller.dispose();
    _assistive.dispose();
    super.dispose();
  }

  /// A new depth map only changes presentation (heatmap + which box layer is
  /// used); detection frames pick the map up on their own cadence.
  void _handleDepthFrame() {
    _applyOverlayVisibility();
    if (mounted) setState(() {});
  }

  void _handleDepthStateChanged() {
    // The instance id exists only once the model is loaded, and it has to reach
    // native before any depth tick can run (and must leave it on degrade).
    _syncStreamingConfig();
    if (mounted) setState(() {});
  }

  /// Native depth event → depth frame. Silent unless a live map can be used.
  void _handleDepthEvent(YOLODepthEvent event) {
    // A failure must land even inside the pause/stop window: the native view latches its
    // failure flag on it, so a dropped event would leave depth silently dead with no
    // degraded state and no retry affordance once the camera resumes.
    if (event.error == null &&
        (!_detectionActive || _paused || !_mdeEnabled || !_rotationResolved)) {
      return;
    }
    _depth.onNativeDepth(
      event,
      rotationDegrees: _rotationDegrees,
      uprightWidth: _uprightWidth,
      uprightHeight: _uprightHeight,
    );
  }

  /// Native overlays render boxes only while the heatmap is hidden; otherwise
  /// Flutter paints them above the heatmap.
  void _applyOverlayVisibility() {
    final show = _overlayState.nativeOverlays;
    if (_overlaysShown == show) return;
    _overlaysShown = show;
    _controller.setShowOverlays(show);
  }

  /// Resolves the sensor→upright rotation once per session from the camera
  /// metadata. Failure forces the degraded path (bbox distance, no heatmap).
  Future<void> _resolveRotation() async {
    if (_rotationResolved) return;
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) throw StateError('no cameras available');
      final camera = cameras.firstWhere(
        (candidate) => candidate.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      // The plugin owns preview rotation and exposes no angle to Dart, so the
      // device angle is approximated from the current orientation. A 180°
      // turn is not observable here; only portrait-only use is calibrated.
      final landscape =
          mounted &&
          MediaQuery.maybeOf(context)?.orientation == Orientation.landscape;
      _rotationDegrees = BoxTransform.displayRotationDegrees(
        sensorOrientation: camera.sensorOrientation,
        deviceDegrees: landscape ? 90 : 0,
        isFront: camera.lensDirection == CameraLensDirection.front,
      );
      _rotationResolved = true;
      _rotationFailed = false;
      debugPrint('[Depth] Display rotation resolved: $_rotationDegrees°');
    } catch (error) {
      debugPrint('[Depth] Camera metadata unavailable: $error');
      _rotationFailed = true;
    }
    if (mounted) setState(() {});
  }

  /// Runs only while a live depth map can go stale (detection active, not
  /// paused, MDE on).
  void _startFreshnessTimer() {
    _freshnessTimer?.cancel();
    _freshnessTimer = null;
    if (!_detectionActive || _paused || !_mdeEnabled) return;
    _freshnessTimer = Timer.periodic(
      const Duration(milliseconds: 500),
      (_) => _refreshOverlayFreshness(),
    );
  }

  /// Hides a heatmap whose map went stale while no detection frame arrived to
  /// rebuild the viewport for it.
  void _refreshOverlayFreshness() {
    final before = _heatmapVisible;
    _applyOverlayVisibility();
    if (before != _heatmapVisible && mounted) setState(() {});
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
      if (mounted) setState(() => _assetLabels = labels);
    } catch (error) {
      debugPrint('[Ultralytics] Unable to load labels: $error');
    }
  }

  void _handleSettingsChanged() {
    final modeChanged = _settings.distanceEstimationMode != _lastDistanceMode;
    _lastDistanceMode = _settings.distanceEstimationMode;
    _syncHeatmapGate();
    if (modeChanged && !_mdeEnabled) {
      // Bounding-box mode stops depth inference entirely and releases the
      // interpreter, so its weights and delegate do not stay resident.
      // `releaseModel()` already stops the tick and clears the frame.
      _depthSmoother.reset();
      unawaited(_depth.releaseModel());
    } else if (modeChanged) {
      _depth.retry();
      _resolveRotation();
    }
    _armDepth();
    _startFreshnessTimer();
    _applyOverlayVisibility();
    if (mounted) setState(() {});
  }

  /// The switch boundary: a selected-model change is a deliberate stop.
  ///
  /// Nothing is auto-started here. The next Start remounts the native view, so
  /// the replacement session loads the selected file (see [_startDetection]).
  Future<void> _handleDetectorModelChanged() async {
    if (_detectionActive) await _stopDetection();
    // Reject every callback captured under the previous view, including a late
    // payload from the superseded session.
    _activeNativeEpoch++;
    // The previous model's interpretation must not carry over: detections,
    // tracks, announced context and correction records all belong to it.
    widget.corrections?.clear();
    _assistive.reset();
    // New rows carry the replacement; already recorded rows keep the identity
    // they were written with.
    _assistive.detectorModel = widget.detectorModel?.current.ref;
    _firstResultLogged = false;
    if (!mounted) return;
    setState(() {
      _latestDetections = const [];
      _overlayInfos = const [];
      _detectionInfo = const [];
      _lastTracks = const [];
      _modelChangeNotice = true;
    });
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
      // it is null, so the path back to Ready is a fresh platform view whose
      // first inference payload proves the new session is operational. A first
      // start or a resume from pause must NOT bump the epoch.
      final recreate = shouldRecreateNativeSessionOnStart(
        nativeViewMounted: _nativeViewMounted,
        detectionActive: _detectionActive,
        paused: _paused,
      );
      setState(() {
        _detectionActive = true;
        _pausedWhileLoading = false;
        // The native YOLOView shell is now (or will be) mounted; retain it after
        // a later manual Stop for PD1 stopped-shell parity.
        _nativeViewMounted = true;
        _paused = false;
        _starting = false;
        _modelError = null;
        _modelChangeNotice = false;
        // Re-arm the once-per-session first-result diagnostic.
        _firstResultLogged = false;
        if (recreate) {
          _nativeViewEpoch++;
        }
        _activeNativeEpoch = _nativeViewEpoch;
      });
      if (recreate) {
        debugPrint(
          '[Ultralytics] Native session reinit requested — new epoch '
          '$_nativeViewEpoch (fresh YOLOView mount)',
        );
      }
      // Model resolution is not proof that the native detector is operational.
      _setRuntimeState(DetectionRuntimeState.loadingModel);
      _armReadinessTimeout(_activeNativeEpoch);
      if (_mdeEnabled) {
        await _resolveRotation();
        _depth.retry();
      }
      _armDepth();
      _startFreshnessTimer();
      _applyOverlayVisibility();
      if (announce) await _tts.speak('Detection started', urgent: true);
    } finally {
      _startInFlight = false;
    }
  }

  Future<void> _stopDetection() async {
    _readinessTimer?.cancel();
    _pausedWhileLoading = false;
    _activeNativeEpoch++;
    debugPrint(
      '[Ultralytics] Stop requested — coordinator=${widget.coordinator.state} '
      'local(active=$_detectionActive paused=$_paused epoch=$_nativeViewEpoch)',
    );
    await _haptics.mediumTick();
    // The native controller may stop internally, but the native YOLOView shell
    // remains mounted (see [_buildMainArea]) so the stopped screen keeps its
    // layout and horizontal navigation. PD1 stopped-shell parity with the
    // Custom screen.
    //
    // Native `stop()` permanently destroys the predictor; the retained shell is
    // therefore a visual/gesture shell only. A later Start recreates the native
    // session by bumping [_nativeViewEpoch] (see [_startDetection]).
    await _controller.stop();
    _freshnessTimer?.cancel();
    _depth.stop();
    _depth.clearFrame();
    _depthSmoother.reset();
    if (!mounted) return;
    setState(() {
      _detectionActive = false;
      _paused = false;
      _detectionInfo = const [];
      _latestDetections = const [];
      _lastTracks = const [];
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
    _pausedWhileLoading = _runtimeState == DetectionRuntimeState.loadingModel;
    _readinessTimer?.cancel();
    await _haptics.lightTick();
    await _controller.pause();
    // Stop the depth cadence and drop queued frames while paused.
    _depth.stop();
    if (mounted) setState(() => _paused = true);
    _startFreshnessTimer();
    _setRuntimeState(DetectionRuntimeState.paused);
    await _tts.speak('Detection paused', urgent: true);
  }

  Future<void> _resumeDetection() async {
    if (!_detectionActive || !_paused) return;
    await _haptics.lightTick();
    await _controller.resume();
    if (mounted) setState(() => _paused = false);
    _startFreshnessTimer();
    if (_pausedWhileLoading) {
      _pausedWhileLoading = false;
      _setRuntimeState(DetectionRuntimeState.loadingModel);
      _armReadinessTimeout(_activeNativeEpoch);
    } else {
      _setRuntimeState(DetectionRuntimeState.ready);
    }
    await _tts.speak('Detection resumed', urgent: true);
  }

  void _togglePaused() {
    if (_paused) {
      _resumeDetection();
    } else {
      _pauseDetection();
    }
  }

  /// Single entry point for the native stream payload.
  ///
  /// `YOLOView` calls either `onStreamingData` OR `onResult` +
  /// `onPerformanceMetrics`; the streaming payload carries the detections,
  /// metrics and (MDE only) the analysis JPEG, so this replaces both callbacks.
  void _handleStreamingData(
    Map<String, dynamic> data, {
    required int callbackEpoch,
  }) {
    if (!_detectionActive || _paused) return;
    if (callbackEpoch != _nativeViewEpoch ||
        callbackEpoch != _activeNativeEpoch) {
      return;
    }
    // App-side receipt anchor: this callback is the first observable point.
    // Pre-result anchors stay unavailable here; metrics are never correlated.
    final resultReceivedAt = DateTime.now();
    final results = YOLODetectionResults.fromMap(data).detections;
    if (_runtimeState == DetectionRuntimeState.loadingModel) {
      _pausedWhileLoading = false;
      _readinessTimer?.cancel();
      _setRuntimeState(DetectionRuntimeState.ready);
    }
    if (!_firstResultLogged) {
      _firstResultLogged = true;
      debugPrint(
        '[Ultralytics] First fresh result received — epoch $_nativeViewEpoch '
        '(${results.length} raw results)',
      );
    }
    final detections = UltralyticsDetectionAdapter.convert(results, _labels);
    final width = data['imageWidth'];
    final height = data['imageHeight'];
    if (width is num && height is num) {
      _uprightWidth = width.toInt();
      _uprightHeight = height.toInt();
    }
    _latestDetections = detections;
    final meters = _metersFor(detections);
    final infos = _assistive.updateDetections(
      detections,
      latencyMs: _inferenceMs,
      resultReceivedAt: resultReceivedAt,
      meters: meters,
    );
    // Track identity for the next frame's EMA smoothing.
    _lastTracks = _assistive.tracks;
    // PD3: accept a new overlay snapshot only while the currently observed
    // mapped coordinator outcome is Ready (healthy fallback maps to Ready).
    // This is a presentation-local gate; see the [_overlayInfos] doc comment
    // for the residual delayed-result freshness limitation.
    final overlayEligible = _overlayEligible;
    _applyOverlayVisibility();
    if (mounted) {
      setState(() {
        _detectionInfo = infos;
        if (overlayEligible) {
          _overlayInfos = infos;
        }
      });
    }
    _handleMetrics(YOLOPerformanceMetrics.fromMap(data));
  }

  /// Metric distance per detection, index-aligned; `null` entries fall back to
  /// the bounding-box heuristic.
  List<double?>? _metersFor(List<Detection> detections) {
    if (!_mdeEnabled) return null;
    final frame = _depthFrame;
    if (frame == null || !_depthFresh) return null;
    return [
      for (final detection in detections)
        _smoothedMeters(detection, _sampleMeters(frame.grid, detection)),
    ];
  }

  double? _sampleMeters(YOLODepthMap map, Detection detection) {
    final inset = DepthDistanceService.insetBox(detection.box);
    if (inset.isEmpty) return null;
    final sensorBox = DepthDistanceService.sensorSpaceBox(
      inset,
      _rotationDegrees,
    );
    return DepthDistanceService.medianDepthInBox(
      values: map.values,
      width: map.width,
      height: map.height,
      box: sensorBox,
    );
  }

  /// EMA smoothing keyed by the previous frame's tracker identity. Raw depth
  /// values are never overwritten; only the reported estimate is smoothed.
  double? _smoothedMeters(Detection detection, double? raw) {
    if (raw == null) return null;
    final trackId = _trackIdFor(detection);
    if (trackId == null) return raw;
    return _depthSmoother.smooth(trackId, raw);
  }

  int? _trackIdFor(Detection detection) {
    final center = detection.box.center;
    int? bestId;
    var bestDistance = double.infinity;
    for (final track in _lastTracks) {
      if (track.classId != detection.classId) continue;
      final delta = track.box.center - center;
      final distance = delta.distanceSquared;
      if (distance < bestDistance) {
        bestDistance = distance;
        bestId = track.trackId;
      }
    }
    // 0.2 normalized distance (~20% of the frame) is the identity window.
    return bestDistance <= 0.04 ? bestId : null;
  }

  /// Retry after a depth failure.
  ///
  /// [depthNeedsReload] decides whether the model has to be re-armed; it is read
  /// before `retry()` because that clears the load-failure flag. `prepare()`
  /// shares one in-flight load, so repeated taps cannot spawn duplicate loads.
  void _retryDepth() {
    final needsReload = depthNeedsReload(
      instanceId: _depth.instanceId,
      modelLoadFailed: _depth.modelLoadFailed,
    );
    _depth.retry();
    _resolveRotation();
    if (needsReload) _armDepth();
    if (mounted) setState(() {});
  }

  void _handleMetrics(YOLOPerformanceMetrics metrics) {
    if (!_detectionActive || _paused) return;
    // Stage timings as typed values with null for "not reported", so a missing
    // stage cannot be read as a 0 ms one. Processing time is the total the
    // payload always carries, hence the fallback for the latency below.
    final timings = DetectorStageTimings.fromMetrics(metrics);
    final inferenceMs = timings.inferenceMs ?? metrics.processingTimeMs;
    // PD1: the visible developer metrics are removed, but the metric values are
    // still recorded for telemetry (Logs & Reports) and the latest inference
    // latency is retained for the shared assistive layer.
    if (mounted) {
      setState(() => _inferenceMs = inferenceMs);
    }
    final mdeEnabled = _mdeEnabled;
    final cadence = _cadence;
    // Depth measurements are exported only while depth is on, exactly like
    // `depthObservedHz`/`depthLatencyMs`: a released estimator keeps its
    // last-known values, and those must not be read as current.
    final depthTimings = mdeEnabled ? _depth.stageTimings : null;
    final depthGrid = mdeEnabled ? _depth.frame.value?.grid : null;
    _assistive.recordMetrics(
      latencyMs: inferenceMs,
      inferenceFps: metrics.fps,
      cadence: CadenceSample(
        requestedDetectionHz: cadence.requestedDetectionHz,
        detectionCadenceAutomatic: cadence.requestedDetectionHz == null,
        effectiveDetectionHz: cadence.effectiveDetectionHz,
        requestedDepthHz: cadence.requestedDepthHz,
        effectiveDepthHz: cadence.effectiveDepthHz,
        depthObservedHz: mdeEnabled ? _depth.observedHz : null,
        depthLatencyMs: mdeEnabled ? _depth.lastLatencyMs : null,
        depthStatus: depthStatusFor(
          mdeEnabled: mdeEnabled,
          state: _depth.state.value,
          accelerator: _depth.accelerator,
        ),
        detectorPreMs: timings.preMs,
        detectorInferenceMs: timings.inferenceMs,
        detectorPostMs: timings.postMs,
        depthPreMs: depthTimings?.preMs,
        depthInferenceMs: depthTimings?.inferenceMs,
        depthPostMs: depthTimings?.postMs,
        depthAccelerator: mdeEnabled ? _depth.accelerator : null,
        depthGridWidth: depthGrid?.width,
        depthGridHeight: depthGrid?.height,
        heatmapBuildMs: mdeEnabled ? _depth.lastHeatmapBuildMs : null,
        depthDroppedTicks: depthTimings?.droppedTicks,
        lowPowerClamped: _cadence.lowPowerClamped,
        sourceLimited: _cadence.sourceLimited,
      ),
    );
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
    // The shared label list belongs to the built-in model; offering it against
    // a custom model's detections would record invented COCO names.
    if (_modelKind != DetectorModelKind.builtIn) return;
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
    if (_modelKind != DetectorModelKind.builtIn) return null;
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
    _readinessTimer?.cancel();
    _pausedWhileLoading = false;
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

  void _armReadinessTimeout(int epoch) {
    _readinessTimer?.cancel();
    _readinessTimer = Timer(widget.readinessTimeout, () {
      if (!mounted ||
          !_detectionActive ||
          _paused ||
          epoch != _nativeViewEpoch ||
          epoch != _activeNativeEpoch ||
          _runtimeState != DetectionRuntimeState.loadingModel) {
        return;
      }
      _reportFailure(
        DetectionFailure(
          category: DetectionFailureCategory.modelLoading,
          safeMessage:
              'The detection engine did not produce its first result in time.',
          technicalDetail:
              'No inference payload within ${widget.readinessTimeout}.',
          engine: InferenceEngine.ultralytics,
          timestamp: DateTime.now(),
          fallbackAvailable: true,
        ),
      );
    });
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
                // Non-blocking depth notice. It is a sibling of the flexible
                // area, like the top bar and the control row, so it sits outside
                // the gesture region and its Retry tap is never also classified
                // as a single tap.
                if (_showsLiveViewport && _depthDegraded) ...[
                  WarningBanner(message: kDepthDegradedMessage),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: kSpace16),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: AccessibleButton(
                        label: 'Retry depth estimate',
                        icon: Icons.refresh,
                        onPressed: _retryDepth,
                      ),
                    ),
                  ),
                ],
                // A model change is a stop: state the required next action
                // instead of silently returning to a stopped viewport.
                if (_modelChangeNotice)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      kSpace16,
                      0,
                      kSpace16,
                      kSpace8,
                    ),
                    child: Semantics(
                      container: true,
                      liveRegion: true,
                      label: kModelChangedMessage,
                      child: ExcludeSemantics(
                        child: Text(
                          kModelChangedMessage,
                          style: Theme.of(
                            context,
                          ).textTheme.bodySmall?.copyWith(color: kHomeInk),
                        ),
                      ),
                    ),
                  ),
                // The viewport is the only flexible region; the control row
                // below derives its height from its content and the minimum
                // touch targets rather than a fixed percentage allocation.
                //
                // In the live state the gesture region is this whole flexible
                // area, not just the camera viewport: thesis gestures must work
                // wherever the user swipes on Detection. The top bar (audio
                // pill), the depth notice and the action controls row stay
                // outside it, and the state panels are outside it too, so their
                // taps are never also classified as a full-screen gesture.
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

  /// Whether the main area currently shows the live camera viewport.
  ///
  /// Only this state has a camera to swipe, so only this state keeps the
  /// gesture region. The failed, permission-denied and camera-pending panels
  /// render their buttons outside the [GestureSurface].
  bool get _showsLiveViewport =>
      widget.coordinator.state != DetectionRuntimeState.failed &&
      !_permissionDenied &&
      (_detectionActive || _nativeViewMounted);

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
    // detection has been started at least once), the native YOLOView shell is
    // retained even after a manual Stop. The native controller may stop
    // internally, but the shell stays mounted so the viewport layout and
    // horizontal navigation remain reachable. Only a never-started screen falls
    // back to the pending surface.
    //
    // Residual limitation (Needs Verification [external-runtime]): the retained
    // native texture after stop may render frozen, cleared, or inactive on a
    // physical device. This must be observed on the target device; the shell is
    // retained regardless so gesture/layout ownership is preserved.
    // The failed and permission-denied panels returned above, so the only
    // remaining non-live state is a never-started screen.
    if (!_showsLiveViewport) return _buildCameraPending(context);
    // Rounded dark card around the native YOLOView. When the depth heatmap is
    // hidden the native overlay draws boxes as before; when it is visible the
    // native overlay is turned off and boxes are painted in Flutter above the
    // heatmap so labels stay legible.
    final callbackEpoch = _nativeViewEpoch;
    final viewport = Container(
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
            // the only way to receive results from a fresh native session.
            key: ValueKey('ultralytics-native-$_nativeViewEpoch'),
            modelPath: _modelPath,
            task: YOLOTask.detect,
            controller: _controller,
            confidenceThreshold: _settings.detectionConfidence,
            iouThreshold: EyeCueModelConfig.nmsIouThreshold,
            useGpu: true,
            streamingConfig: _streamingConfig,
            onStreamingData: (data) =>
                _handleStreamingData(data, callbackEpoch: callbackEpoch),
            onModelLoad: (_, _) {
              if (!mounted ||
                  !_detectionActive ||
                  callbackEpoch != _nativeViewEpoch ||
                  callbackEpoch != _activeNativeEpoch) {
                debugPrint(
                  '[Ultralytics] Ignoring stale onModelLoad — callback epoch '
                  '$callbackEpoch != active $_activeNativeEpoch',
                );
                return;
              }
              debugPrint(
                '[Ultralytics] Model path resolved — epoch $callbackEpoch; '
                'waiting for first inference payload',
              );
              if (mounted) {
                setState(() {
                  _modelError = null;
                });
              }
            },
            onModelError: (error, _, _) {
              if (!mounted ||
                  !_detectionActive ||
                  callbackEpoch != _nativeViewEpoch ||
                  callbackEpoch != _activeNativeEpoch) {
                return;
              }
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
          // Depth heatmap (decorative, pointer-inert) sits directly above the
          // native preview and below every box/label layer.
          if (_heatmapVisible)
            DepthHeatmapView(
              image: _depthFrame?.heatmap,
              rotationDegrees: _rotationDegrees,
            ),
          // Flutter box layer, drawn above the heatmap so labels stay readable.
          if (_overlayState.flutterBoxes)
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: BoundingBoxPainter(
                    detections: _latestDetections,
                    imageSize: Size(
                      _uprightWidth.toDouble(),
                      _uprightHeight.toDouble(),
                    ),
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            ),
          // Compact current-information overlay (PD3). Pointer-inert, so it
          // never consumes raw pointers intended for the gesture surface.
          DetectionInformationOverlay(
            infos: _overlayInfos,
            eligible: _overlayEligible,
          ),
        ],
      ),
    );
    // Only the live branch is inside the gesture surface. A swipe works over
    // the live viewport only; the non-live panels and the depth notice are
    // outside it.
    return GestureSurface(controller: _gestureController, child: viewport);
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
