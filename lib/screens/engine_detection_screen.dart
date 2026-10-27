import 'package:flutter/material.dart';

import '../models/detection_runtime_state.dart';
import '../services/correction_service.dart';
import '../services/detector_model_service.dart';
import '../services/engine_coordinator.dart';
import '../services/haptics_service.dart';
import '../services/settings_service.dart';
import '../services/telemetry_service.dart';
import '../services/tts_service.dart';
import 'ultralytics_detection_screen.dart';

class EngineDetectionScreen extends StatefulWidget {
  final SettingsService settings;
  final TtsService tts;
  final TelemetryService telemetry;
  final CorrectionService? corrections;
  final HapticsService haptics;

  /// The researcher's detector selection, forwarded to the mounted engine.
  final DetectorModelService? detectorModel;

  /// The single app-shell-owned Detection lifecycle/status source.
  ///
  /// The shell owns this instance for the shell lifetime; this screen forwards
  /// engine lifecycle/failure facts to it and delivers its start intent to the
  /// mounted engine. It never constructs or disposes a coordinator.
  final EngineCoordinator coordinator;

  /// Requests one relative primary-tab move from the shell.
  ///
  /// `-1` moves one tab toward Home, `+1` one tab toward Help. The shell owns
  /// boundary handling and wayfinding feedback; this screen only forwards the
  /// gesture intent. The callback must have stable identity for the cached
  /// page lifetime so ordinary navigation never remounts the engine.
  final void Function(int direction)? onNavigateRelative;

  const EngineDetectionScreen({
    super.key,
    required this.settings,
    required this.tts,
    required this.telemetry,
    this.corrections,
    required this.haptics,
    required this.coordinator,
    this.detectorModel,
    this.onNavigateRelative,
  });

  @override
  State<EngineDetectionScreen> createState() => _EngineDetectionScreenState();
}

class _EngineDetectionScreenState extends State<EngineDetectionScreen> {
  EngineCoordinator get _coordinator => widget.coordinator;
  late double _lastDetectionConfidence = widget.settings.detectionConfidence;

  @override
  void initState() {
    super.initState();
    widget.settings.addListener(_handleSettingsChanged);
  }

  @override
  void dispose() {
    widget.settings.removeListener(_handleSettingsChanged);
    super.dispose();
  }

  void _handleSettingsChanged() {
    final confidence = widget.settings.detectionConfidence;
    if (confidence != _lastDetectionConfidence) {
      _lastDetectionConfidence = confidence;
      _coordinator.restartActiveEngine();
    }
  }

  void _reportState(
    DetectionRuntimeState state,
    int mountGeneration,
    int? sourceGeneration,
  ) {
    if (state == DetectionRuntimeState.ready) {
      _coordinator.reportReady(
        generation: mountGeneration,
        sourceGeneration: sourceGeneration,
      );
    } else {
      _coordinator.reportState(
        state,
        generation: mountGeneration,
        sourceGeneration: sourceGeneration,
      );
    }
  }

  void _reportFailure(
    DetectionFailure failure,
    int mountGeneration,
    int? sourceGeneration,
  ) {
    _coordinator.reportFailure(
      failure,
      generation: mountGeneration,
      sourceGeneration: sourceGeneration,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _coordinator,
      builder: (context, _) {
        final generation = _coordinator.mountGeneration;
        final startIntent = _coordinator.pendingStartIntent;
        return UltralyticsDetectionScreen(
          key: ValueKey('ultralytics-$generation'),
          settings: widget.settings,
          tts: widget.tts,
          telemetry: widget.telemetry,
          corrections: widget.corrections,
          haptics: widget.haptics,
          coordinator: _coordinator,
          detectorModel: widget.detectorModel,
          startIntent: startIntent,
          onNavigateRelative: widget.onNavigateRelative,
          onRuntimeStateChanged: (state, sourceGeneration) =>
              _reportState(state, generation, sourceGeneration),
          onFailure: (failure, sourceGeneration) =>
              _reportFailure(failure, generation, sourceGeneration),
        );
      },
    );
  }
}
