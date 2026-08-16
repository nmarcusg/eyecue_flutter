import 'package:eyecue_flutter/screens/help_screen.dart';
import 'package:eyecue_flutter/screens/home_screen.dart';
import 'package:eyecue_flutter/screens/settings_screen.dart';
import 'package:eyecue_flutter/services/settings_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Lightweight screen smoke tests (no camera / platform plugins involved).
void main() {
  SettingsService settings() => SettingsService(store: InMemorySettingsStore());

  group('HomeScreen', () {
    testWidgets('renders branding, status card, and Go to Live Camera CTA',
        (tester) async {
      var wentToDetection = false;
      await tester.pumpWidget(
        MaterialApp(
          home: HomeScreen(
            settings: settings(),
            onGoToDetection: () => wentToDetection = true,
          ),
        ),
      );

      expect(find.text('EyeCue'), findsOneWidget);
      expect(
        find.text('Smart navigation assistance for visually impaired users.'),
        findsOneWidget,
      );
      expect(find.text('Go to Live Camera'), findsOneWidget);
      expect(find.textContaining('Detection is already running'), findsOneWidget);

      await tester.tap(find.text('Go to Live Camera'));
      expect(wentToDetection, isTrue);
    });

    testWidgets('reflects Auto-Start off', (tester) async {
      final s = settings();
      await s.setAutoStartDetection(false);
      await tester.pumpWidget(
        MaterialApp(home: HomeScreen(settings: s, onGoToDetection: () {})),
      );
      expect(find.textContaining('Auto-Start is off'), findsOneWidget);
    });
  });

  group('SettingsScreen', () {
    testWidgets('shows all thesis settings and the Logs & Reports entry',
        (tester) async {
      var openedLogs = false;
      await tester.pumpWidget(
        MaterialApp(
          home: SettingsScreen(
            settings: settings(),
            onOpenLogsReports: () => openedLogs = true,
          ),
        ),
      );

      expect(find.text('Vibration Feedback'), findsOneWidget);
      expect(find.text('Auto-Start on Open'), findsOneWidget);
      expect(find.text('Low Power Mode'), findsOneWidget);
      expect(find.text('Audio / Voice Guidance'), findsOneWidget);
      expect(find.text('View Logs & Reports'), findsOneWidget);

      await tester.tap(find.text('View Logs & Reports'));
      expect(openedLogs, isTrue);
    });

    testWidgets('toggling a setting updates the service', (tester) async {
      final s = settings();
      await tester.pumpWidget(
        MaterialApp(home: SettingsScreen(settings: s, onOpenLogsReports: () {})),
      );

      expect(s.lowPowerMode, isFalse);
      await tester.tap(find.text('Low Power Mode'));
      await tester.pumpAndSettle();
      expect(s.lowPowerMode, isTrue);
    });
  });

  group('HelpScreen', () {
    testWidgets('explains how it works and the gestures', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: HelpScreen()));
      expect(find.text('How It Works'), findsOneWidget);
      expect(find.text('Gesture Controls'), findsOneWidget);
      expect(find.text('Gesture Confirmation'), findsOneWidget);
      expect(find.textContaining('Two-finger double tap'), findsOneWidget);
      expect(find.textContaining('Single tap'), findsWidgets);
      expect(find.textContaining('Three-finger tap'), findsOneWidget);
      expect(find.textContaining('swipe down'), findsOneWidget);
    });
  });
}
