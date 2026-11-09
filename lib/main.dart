import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:marionette_flutter/marionette_flutter.dart';

import 'app.dart';
export 'app.dart' show EyeCueApp;
import 'services/correction_service.dart';
import 'services/detector_model_service.dart';
import 'services/haptics_service.dart';
import 'services/settings_service.dart';
import 'services/telemetry_service.dart';
import 'services/tts_service.dart';

Future<void> main() async {
  // Marionette (runtime inspection for AI agents) is a debug-only tool. It
  // must never run in release builds, so the binding is only swapped in
  // debug mode; release builds use the standard Flutter binding.
  if (kDebugMode) {
    MarionetteBinding.ensureInitialized();
  } else {
    WidgetsFlutterBinding.ensureInitialized();
  }

  final settings = SettingsService();
  final telemetry = TelemetryService();
  final tts = TtsService(
    engine: FlutterTtsEngine(),
    onAlertLifecycle: telemetry.recordAlertLifecycle,
    onAlertCounters: telemetry.recordAlertCounters,
  );
  final labels = await loadLabels();
  final corrections = CorrectionService(labels: labels);
  final haptics = HapticsService(isEnabled: () => settings.vibrationFeedback);

  await settings.load();
  final detectorModels = DetectorModelService(
    settings,
    builtInLabelsLoader: () async => labels,
  );
  await detectorModels.load();
  await tts.init();
  telemetry.startSession();

  runApp(
    EyeCueApp(
      settings: settings,
      tts: tts,
      telemetry: telemetry,
      corrections: corrections,
      haptics: haptics,
      detectorModel: detectorModels,
      researchSessions: null,
      logsReportsBuilder: null,
    ),
  );
}
