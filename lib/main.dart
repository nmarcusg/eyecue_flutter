import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import 'models/model_config.dart';
import 'navigation/app_shell.dart';
import 'services/correction_service.dart';
import 'services/haptics_service.dart';
import 'services/settings_service.dart';
import 'services/telemetry_service.dart';
import 'services/tts_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final settings = SettingsService();
  final tts = TtsService(engine: FlutterTtsEngine());
  final telemetry = TelemetryService();
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
      theme: _buildTheme(),
      darkTheme: _buildTheme(),
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

  /// High-contrast, dark-mode-friendly, accessibility-first theme.
  ThemeData _buildTheme() {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFFFFC107),
        brightness: Brightness.dark,
      ),
    );
    return base.copyWith(
      scaffoldBackgroundColor: const Color(0xFF121212),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF1E1E1E),
        centerTitle: false,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: const Color(0xFF1E1E1E),
        indicatorColor: const Color(0xFF3E2C00),
      ),
      // Explicit concrete font sizes are required here: the default M3
      // TextTheme is color-only (fontSize == null; geometry is merged per
      // locale at render time), so TextTheme.apply(fontSizeFactor:) would
      // assert. These are the M3 sizes scaled ~1.12x for high-contrast
      // readability, all in white.
      textTheme: _highContrastTextTheme(),
    );
  }

  /// Concrete high-contrast typography (white text, scaled for readability).
  TextTheme _highContrastTextTheme() {
    const white = Colors.white;
    return const TextTheme(
      displayLarge: TextStyle(fontSize: 64, color: white),
      displayMedium: TextStyle(fontSize: 50, color: white),
      displaySmall: TextStyle(fontSize: 40, color: white),
      headlineLarge: TextStyle(
        fontSize: 36,
        color: white,
        fontWeight: FontWeight.w600,
      ),
      headlineMedium: TextStyle(
        fontSize: 31,
        color: white,
        fontWeight: FontWeight.w600,
      ),
      headlineSmall: TextStyle(
        fontSize: 27,
        color: white,
        fontWeight: FontWeight.w600,
      ),
      titleLarge: TextStyle(
        fontSize: 25,
        color: white,
        fontWeight: FontWeight.w700,
      ),
      titleMedium: TextStyle(
        fontSize: 18,
        color: white,
        fontWeight: FontWeight.w600,
      ),
      titleSmall: TextStyle(
        fontSize: 16,
        color: white,
        fontWeight: FontWeight.w600,
      ),
      bodyLarge: TextStyle(fontSize: 18, color: white),
      bodyMedium: TextStyle(fontSize: 16, color: white),
      bodySmall: TextStyle(fontSize: 13, color: white),
      labelLarge: TextStyle(
        fontSize: 16,
        color: white,
        fontWeight: FontWeight.w700,
      ),
      labelMedium: TextStyle(
        fontSize: 13,
        color: white,
        fontWeight: FontWeight.w600,
      ),
      labelSmall: TextStyle(
        fontSize: 12,
        color: white,
        fontWeight: FontWeight.w500,
      ),
    );
  }
}
