import 'package:eyecue_flutter/main.dart';
import 'package:eyecue_flutter/services/haptics_service.dart';
import 'package:eyecue_flutter/services/settings_service.dart';
import 'package:eyecue_flutter/services/telemetry_service.dart';
import 'package:eyecue_flutter/services/tts_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeTtsEngine implements TtsEngine {
  @override
  Future<void> dispose() async {}
  @override
  Future<void> init() async {}
  @override
  Future<void> speak(String text) async {}
  @override
  Future<void> stop() async {}
}

/// Regression test for the startup theme crash:
/// `TextTheme.apply(fontSizeFactor:)` asserted because the default M3
/// TextTheme is color-only (fontSize == null). EyeCue now supplies an explicit
/// high-contrast TextTheme with concrete font sizes, so the app must build and
/// render the Home screen without throwing.
void main() {
  testWidgets('EyeCueApp builds the theme and renders the Home screen', (
    tester,
  ) async {
    final app = EyeCueApp(
      settings: SettingsService(store: InMemorySettingsStore()),
      tts: TtsService(engine: _FakeTtsEngine()),
      telemetry: TelemetryService(),
      haptics: HapticsService(),
    );

    await tester.pumpWidget(app);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('EyeCue'), findsOneWidget);
    expect(find.text('Go to Live Camera'), findsOneWidget);

    // The concrete text theme must be in effect (no null-fontSize assertion).
    // The Home screen now applies a Home-local light theme, so the `EyeCue`
    // wordmark resolves to the light ink color rather than the global dark
    // theme's white text. The global dark theme itself is unchanged.
    final context = tester.element(find.text('EyeCue'));
    final bodyMedium = Theme.of(context).textTheme.bodyMedium;
    expect(bodyMedium?.fontSize, isNotNull);
    expect(bodyMedium?.color, const Color(0xFF0A0A0A));
  });
}
