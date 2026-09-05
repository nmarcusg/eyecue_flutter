import 'package:flutter/material.dart';

import '../models/app_settings.dart';
import '../models/detection_runtime_state.dart';
import '../services/correction_service.dart';
import '../services/engine_coordinator.dart';
import '../services/haptics_service.dart';
import '../services/settings_service.dart';
import '../services/telemetry_service.dart';
import '../services/tts_service.dart';
import '../widgets/accessible_button.dart';
import 'detection_screen.dart';
import 'ultralytics_detection_screen.dart';

class EngineDetectionScreen extends StatefulWidget {
  final SettingsService settings;
  final TtsService tts;
  final TelemetryService telemetry;
  final CorrectionService? corrections;
  final HapticsService haptics;

  const EngineDetectionScreen({
    super.key,
    required this.settings,
    required this.tts,
    required this.telemetry,
    this.corrections,
    required this.haptics,
  });

  @override
  State<EngineDetectionScreen> createState() => _EngineDetectionScreenState();
}

class _EngineDetectionScreenState extends State<EngineDetectionScreen> {
  late final EngineCoordinator _coordinator = EngineCoordinator(
    preferredEngine: widget.settings.inferenceEngine,
    telemetry: widget.telemetry,
  );
  late double _lastDetectionConfidence = widget.settings.detectionConfidence;

  @override
  void initState() {
    super.initState();
    widget.settings.addListener(_handleSettingsChanged);
  }

  @override
  void dispose() {
    widget.settings.removeListener(_handleSettingsChanged);
    _coordinator.disposeCoordinator();
    super.dispose();
  }

  void _handleSettingsChanged() {
    if (_coordinator.preferredEngine != widget.settings.inferenceEngine) {
      _coordinator.setPreferredEngine(widget.settings.inferenceEngine);
    }
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
        final selection = _coordinator.selection;
        final generation = _coordinator.mountGeneration;
        final child = switch (selection.activeEngine) {
          InferenceEngine.custom => DetectionScreen(
            key: ValueKey('custom-$generation'),
            settings: widget.settings,
            tts: widget.tts,
            telemetry: widget.telemetry,
            corrections: widget.corrections,
            haptics: widget.haptics,
            onRuntimeStateChanged: (state, sourceGeneration) =>
                _reportState(state, generation, sourceGeneration),
            onFailure: (failure, sourceGeneration) =>
                _reportFailure(failure, generation, sourceGeneration),
          ),
          InferenceEngine.ultralytics => UltralyticsDetectionScreen(
            key: ValueKey('ultralytics-$generation'),
            settings: widget.settings,
            tts: widget.tts,
            telemetry: widget.telemetry,
            corrections: widget.corrections,
            haptics: widget.haptics,
            onRuntimeStateChanged: (state, sourceGeneration) =>
                _reportState(state, generation, sourceGeneration),
            onFailure: (failure, sourceGeneration) =>
                _reportFailure(failure, generation, sourceGeneration),
          ),
        };

        return Stack(
          fit: StackFit.expand,
          children: [
            child,
            if (selection.isTemporaryFallback &&
                _coordinator.fallbackNoticeVisible)
              _buildFallbackNotice(context, selection.fallbackReason),
          ],
        );
      },
    );
  }

  Widget _buildFallbackNotice(BuildContext context, String? reason) {
    final theme = Theme.of(context);
    return Positioned(
      top: 8,
      left: 12,
      right: 12,
      child: SafeArea(
        bottom: false,
        child: Semantics(
          container: true,
          liveRegion: true,
          label:
              'Temporary fallback. Custom EyeCue is active because '
              '${reason ?? 'the recommended engine is unavailable.'}',
          child: Card(
            color: theme.colorScheme.tertiaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Temporary fallback active',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: theme.colorScheme.onTertiaryContainer,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Custom EyeCue is active. ${reason ?? 'The recommended engine is unavailable.'}',
                    style: TextStyle(
                      color: theme.colorScheme.onTertiaryContainer,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      AccessibleButton(
                        label: 'Retry Ultralytics',
                        icon: Icons.refresh,
                        onPressed: _coordinator.retryPreferred,
                      ),
                      AccessibleButton(
                        label: 'Use Custom for now',
                        icon: Icons.check,
                        onPressed: _coordinator.useCustomForNow,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
