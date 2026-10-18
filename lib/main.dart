import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:marionette_flutter/marionette_flutter.dart';

import 'models/model_config.dart';
import 'navigation/app_shell.dart';
import 'services/correction_service.dart';
import 'services/haptics_service.dart';
import 'services/settings_service.dart';
import 'services/telemetry_service.dart';
import 'services/tts_service.dart';
import 'theme/app_theme.dart';

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
  final labels = await _loadLabels();
  final corrections = CorrectionService(labels: labels);
  final haptics = HapticsService(isEnabled: () => settings.vibrationFeedback);

  await settings.load();
  await tts.init();
  telemetry.startSession();

  runApp(
    EyeCueApp(
      settings: settings,
      tts: tts,
      telemetry: telemetry,
      corrections: corrections,
      haptics: haptics,
    ),
  );
}

Future<List<String>> _loadLabels() async {
  try {
    final text = await rootBundle.loadString(EyeCueModelConfig.labelsAssetPath);
    return text
        .split('\n')
        .map((label) => label.trim())
        .where((label) => label.isNotEmpty)
        .toList(growable: false);
  } catch (error) {
    debugPrint('[Startup] Unable to load correction labels: $error');
    return const [];
  }
}

class EyeCueApp extends StatelessWidget {
  final SettingsService settings;
  final TtsService tts;
  final TelemetryService telemetry;
  final CorrectionService? corrections;
  final HapticsService haptics;

  const EyeCueApp({
    super.key,
    required this.settings,
    required this.tts,
    required this.telemetry,
    this.corrections,
    required this.haptics,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'EyeCue',
      debugShowCheckedModeBanner: false,
      theme: buildEyeCueTheme(),
      darkTheme: buildEyeCueTheme(),
      themeMode: ThemeMode.dark,
      home: AppShell(
        settings: settings,
        tts: tts,
        telemetry: telemetry,
        corrections: corrections,
        haptics: haptics,
      ),
    );
  }
}
