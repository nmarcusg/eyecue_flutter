import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import 'models/model_config.dart';
import 'navigation/app_shell.dart';
import 'services/correction_service.dart';
import 'services/detector_model_service.dart';
import 'services/haptics_service.dart';
import 'services/research_session_service.dart';
import 'services/settings_service.dart';
import 'services/telemetry_service.dart';
import 'services/tts_service.dart';
import 'theme/app_theme.dart';

Future<List<String>> loadLabels() async {
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
  final DetectorModelService? detectorModel;
  final ResearchSessionService? researchSessions;
  final Widget Function()? logsReportsBuilder;

  const EyeCueApp({
    super.key,
    required this.settings,
    required this.tts,
    required this.telemetry,
    this.corrections,
    required this.haptics,
    this.detectorModel,
    this.researchSessions,
    this.logsReportsBuilder,
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
        detectorModel: detectorModel,
        researchSessions: researchSessions,
        logsReportsBuilder: logsReportsBuilder,
      ),
    );
  }
}
