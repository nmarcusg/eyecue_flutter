import 'package:eyecue_flutter/navigation/app_shell.dart';
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

/// Stub pages so the shell can be tested without a real camera/inference stack.
List<Widget> Function(BuildContext, AppShellState) stubPages() {
  return (context, shell) => [
        // Home stub — includes a "Go to Live Camera" style action.
        Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => shell.goToTab(1),
              child: const Text('PAGE0'),
            ),
          ),
        ),
        const Scaffold(body: Center(child: Text('PAGE1'))),
        const Scaffold(body: Center(child: Text('PAGE2'))),
        const Scaffold(body: Center(child: Text('PAGE3'))),
      ];
}

void main() {
  late SettingsService settings;
  late TtsService tts;
  late TelemetryService telemetry;
  late HapticsService haptics;

  setUp(() {
    settings = SettingsService(store: InMemorySettingsStore());
    tts = TtsService(engine: _FakeTtsEngine());
    telemetry = TelemetryService();
    haptics = HapticsService();
  });

  Widget buildShell() {
    return MaterialApp(
      home: AppShell(
        settings: settings,
        tts: tts,
        telemetry: telemetry,
        haptics: haptics,
        pagesOverride: stubPages(),
      ),
    );
  }

  testWidgets('starts on the Home tab', (tester) async {
    await tester.pumpWidget(buildShell());
    expect(find.text('PAGE0'), findsOneWidget);
    expect(find.text('PAGE1'), findsNothing);
  });

  testWidgets('bottom navigation switches between all four tabs',
      (tester) async {
    await tester.pumpWidget(buildShell());

    for (final label in ['Detect', 'Settings', 'Help', 'Home']) {
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
    }
    // Order above ends back on Home.
    expect(find.text('PAGE0'), findsOneWidget);

    await tester.tap(find.text('Detect'));
    await tester.pumpAndSettle();
    expect(find.text('PAGE1'), findsOneWidget);

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('PAGE2'), findsOneWidget);
  });

  testWidgets('Home CTA navigates to the Detection tab', (tester) async {
    await tester.pumpWidget(buildShell());
    await tester.tap(find.text('PAGE0'));
    await tester.pumpAndSettle();
    expect(find.text('PAGE1'), findsOneWidget);
  });

  testWidgets('settings page keeps its state when switching tabs',
      (tester) async {
    await tester.pumpWidget(buildShell());
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Home'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('PAGE2'), findsOneWidget);
  });
}
