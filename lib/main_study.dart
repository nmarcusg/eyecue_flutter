import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:marionette_flutter/marionette_flutter.dart';

import 'app.dart';
import 'screens/logs_reports_screen.dart';
import 'services/correction_service.dart';
import 'services/detector_model_service.dart';
import 'services/haptics_service.dart';
import 'services/research_session_service.dart';
import 'services/settings_service.dart';
import 'services/telemetry_service.dart';
import 'services/tts_service.dart';

Future<void> main() async {
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
  final researchSessions = ResearchSessionService(telemetry: telemetry);
  await researchSessions.load();
  researchSessions.watchDetectorModel(
    detectorModels,
    () => detectorModels.current.ref,
  );
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
      researchSessions: researchSessions,
      logsReportsBuilder: () => LogsReportsScreen(
        telemetry: telemetry,
        settings: settings,
        corrections: corrections,
        researchSessions: researchSessions,
        detectorModel: detectorModels,
      ),
    ),
  );
}
