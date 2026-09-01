import 'package:flutter/material.dart';

import '../models/app_settings.dart';
import '../services/haptics_service.dart';
import '../services/settings_service.dart';
import '../services/telemetry_service.dart';
import '../services/tts_service.dart';
import 'detection_screen.dart';
import 'ultralytics_detection_screen.dart';

class EngineDetectionScreen extends StatelessWidget {
  final SettingsService settings;
  final TtsService tts;
  final TelemetryService telemetry;
  final HapticsService haptics;

  const EngineDetectionScreen({
    super.key,
    required this.settings,
    required this.tts,
    required this.telemetry,
    required this.haptics,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) {
        return switch (settings.inferenceEngine) {
          InferenceEngine.custom => DetectionScreen(
            key: const ValueKey(InferenceEngine.custom),
            settings: settings,
            tts: tts,
            telemetry: telemetry,
            haptics: haptics,
          ),
          InferenceEngine.ultralytics => UltralyticsDetectionScreen(
            key: const ValueKey(InferenceEngine.ultralytics),
            settings: settings,
            tts: tts,
            telemetry: telemetry,
            haptics: haptics,
          ),
        };
      },
    );
  }
}
