import 'package:eyecue_flutter/models/app_settings.dart';
import 'package:eyecue_flutter/navigation/app_shell.dart';
import 'package:eyecue_flutter/screens/settings_screen.dart';
import 'package:eyecue_flutter/services/gesture_controller.dart';
import 'package:eyecue_flutter/services/haptics_service.dart';
import 'package:eyecue_flutter/services/settings_service.dart';
import 'package:eyecue_flutter/services/telemetry_service.dart';
import 'package:eyecue_flutter/services/tts_service.dart';
import 'package:eyecue_flutter/widgets/gesture_surface.dart';
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
  late List<String> hapticCalls;

  setUp(() {
    settings = SettingsService(store: InMemorySettingsStore());
    tts = TtsService(engine: _FakeTtsEngine());
    telemetry = TelemetryService();
    hapticCalls = [];
    haptics = HapticsService(
      light: () async => hapticCalls.add('light'),
      medium: () async => hapticCalls.add('medium'),
      heavy: () async => hapticCalls.add('heavy'),
    );
  });

  Widget buildShell({bool accessibleNavigation = false}) {
    return MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(accessibleNavigation: accessibleNavigation),
        child: AppShell(
          settings: settings,
          tts: tts,
          telemetry: telemetry,
          haptics: haptics,
          pagesOverride: stubPages(),
        ),
      ),
    );
  }

  /// Performs a one-finger horizontal drag across the shell body.
  ///
  /// Uses an explicit multi-step gesture so the horizontal recognizer passes
  /// its slop and receives incremental updates before the pointer lifts.
  Future<void> swipeBody(WidgetTester tester, double dx) async {
    final center = tester.getCenter(find.byType(IndexedStack));
    final gesture = await tester.startGesture(center);
    const steps = 8;
    for (var i = 0; i < steps; i++) {
      await gesture.moveBy(Offset(dx / steps, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pumpAndSettle();
  }

  testWidgets('starts on the Home tab', (tester) async {
    await tester.pumpWidget(buildShell());
    expect(find.text('PAGE0'), findsOneWidget);
    expect(find.text('PAGE1'), findsNothing);
  });

  testWidgets('bottom navigation switches between all four tabs', (
    tester,
  ) async {
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

  testWidgets('settings page keeps its state when switching tabs', (
    tester,
  ) async {
    await tester.pumpWidget(buildShell());
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Home'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('PAGE2'), findsOneWidget);
  });

  group('one-finger horizontal navigation', () {
    // Product Decision 2: a left swipe advances to the next tab and a right
    // swipe returns to the previous tab.
    testWidgets('a left swipe moves one tab toward Help', (tester) async {
      await tester.pumpWidget(buildShell());
      await swipeBody(tester, -200);
      expect(find.text('PAGE1'), findsOneWidget);
    });

    testWidgets('a right swipe moves one tab toward Home', (tester) async {
      await tester.pumpWidget(buildShell());
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      await swipeBody(tester, 200);
      expect(find.text('PAGE1'), findsOneWidget);
    });

    testWidgets('a short swipe does not navigate', (tester) async {
      await tester.pumpWidget(buildShell());
      await swipeBody(tester, 30);
      expect(find.text('PAGE0'), findsOneWidget);
    });

    testWidgets('Home-right stays on Home and emits boundary feedback', (
      tester,
    ) async {
      await tester.pumpWidget(buildShell());
      await swipeBody(tester, 200);
      expect(find.text('PAGE0'), findsOneWidget);
      expect(hapticCalls, ['medium']);
    });

    testWidgets('Help-left stays on Help and emits boundary feedback', (
      tester,
    ) async {
      await tester.pumpWidget(buildShell());
      await tester.tap(find.text('Help'));
      await tester.pumpAndSettle();
      await swipeBody(tester, -200);
      expect(find.text('PAGE3'), findsOneWidget);
      expect(hapticCalls, ['medium']);
    });

    testWidgets('a successful swipe emits a light tick', (tester) async {
      await tester.pumpWidget(buildShell());
      await swipeBody(tester, -200);
      expect(hapticCalls, ['light']);
    });

    testWidgets('bar taps and CTA emit no gesture feedback', (tester) async {
      await tester.pumpWidget(buildShell());
      await tester.tap(find.text('Detect'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Home'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('PAGE0')); // Home CTA → Detect
      await tester.pumpAndSettle();
      expect(hapticCalls, isEmpty);
    });

    testWidgets('a second pointer invalidates the whole sequence', (
      tester,
    ) async {
      await tester.pumpWidget(buildShell());
      final center = tester.getCenter(find.byType(IndexedStack));
      final first = await tester.startGesture(center);
      await first.moveBy(const Offset(-60, 0));
      await tester.pump(const Duration(milliseconds: 16));
      final second = await tester.startGesture(center + const Offset(0, 40));
      await first.moveBy(const Offset(-60, 0));
      await tester.pump(const Duration(milliseconds: 16));
      await first.up();
      await second.up();
      await tester.pumpAndSettle();
      expect(find.text('PAGE0'), findsOneWidget);
    });

    testWidgets('cached Detection page is preserved across navigation', (
      tester,
    ) async {
      await tester.pumpWidget(buildShell());
      await tester.tap(find.text('Detect'));
      await tester.pumpAndSettle();
      // Detection owns horizontal navigation inside its own viewport, so the
      // shell recognizer intentionally does not commit on the Detection tab.
      // Leave Detection via the visible bar, then return with a shell swipe.
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      await swipeBody(tester, 200); // right swipe → previous tab (Detect)
      expect(find.text('PAGE1'), findsOneWidget);
    });

    testWidgets(
      'the shell does not commit a horizontal swipe on the Detection tab',
      (tester) async {
        await tester.pumpWidget(buildShell());
        await tester.tap(find.text('Detect'));
        await tester.pumpAndSettle();
        // Detection's own GestureSurface owns this gesture; the shell must not
        // also commit, or one physical swipe would move two primary tabs.
        await swipeBody(tester, -200);
        expect(find.text('PAGE1'), findsOneWidget);
        expect(hapticCalls, isEmpty);
      },
    );
  });

  group('Detection owns horizontal navigation (single tab change)', () {
    /// Builds the shell with a Detection stub that mirrors the real engine
    /// wiring: a raw [GestureSurface] over the viewport feeding a
    /// [GestureController] whose horizontal intents call the shell's
    /// `navigateRelative` — exactly what both real engines do.
    ///
    /// This reproduces the duplicate-navigation risk without a camera/native
    /// dependency: the raw `Listener` does not compete in the gesture arena,
    /// so if the shell recognizer also claimed the swipe the tab would move
    /// twice.
    Widget buildShellWithDetectionSurface() {
      return MaterialApp(
        home: AppShell(
          settings: settings,
          tts: tts,
          telemetry: telemetry,
          haptics: haptics,
          pagesOverride: (context, shell) => [
            const Scaffold(body: Center(child: Text('PAGE0'))),
            Scaffold(
              body: GestureSurface(
                controller: GestureController(
                  onGesture: (gesture) {
                    final direction = switch (gesture) {
                      EyeCueGesture.swipeLeft => 1,
                      EyeCueGesture.swipeRight => -1,
                      _ => null,
                    };
                    if (direction != null) {
                      shell.navigateRelative(direction);
                    }
                  },
                ),
                child: const Center(child: Text('PAGE1')),
              ),
            ),
            const Scaffold(body: Center(child: Text('PAGE2'))),
            const Scaffold(body: Center(child: Text('PAGE3'))),
          ],
        ),
      );
    }

    testWidgets('a left swipe inside Detection moves exactly one tab', (
      tester,
    ) async {
      await tester.pumpWidget(buildShellWithDetectionSurface());
      await tester.tap(find.text('Detect'));
      await tester.pumpAndSettle();
      expect(find.text('PAGE1'), findsOneWidget);

      // One physical swipe inside the Detection viewport. Detection's surface
      // must move exactly one tab (Detect → Settings), never two.
      await swipeBody(tester, -200);

      expect(find.text('PAGE2'), findsOneWidget);
      expect(find.text('PAGE3'), findsNothing);
      expect(find.text('PAGE1'), findsNothing);
      // Exactly one gesture-origin navigation feedback.
      expect(hapticCalls, ['light']);
    });

    testWidgets('a right swipe inside Detection moves exactly one tab', (
      tester,
    ) async {
      await tester.pumpWidget(buildShellWithDetectionSurface());
      await tester.tap(find.text('Detect'));
      await tester.pumpAndSettle();

      // Right swipe returns to Home (Detect → Home), exactly one tab.
      await swipeBody(tester, 200);

      expect(find.text('PAGE0'), findsOneWidget);
      expect(find.text('PAGE1'), findsNothing);
      expect(hapticCalls, ['light']);
    });
  });

  group('effective bar visibility', () {
    testWidgets('visible by default', (tester) async {
      await tester.pumpWidget(buildShell());
      expect(find.byType(NavigationBar), findsOneWidget);
    });

    testWidgets('hidden when the preference is set', (tester) async {
      await settings.setHideBottomNavigation(true);
      await tester.pumpWidget(buildShell());
      expect(find.byType(NavigationBar), findsNothing);
    });

    testWidgets('forced visible while accessibility navigation is active', (
      tester,
    ) async {
      await settings.setHideBottomNavigation(true);
      await tester.pumpWidget(buildShell(accessibleNavigation: true));
      expect(find.byType(NavigationBar), findsOneWidget);
    });

    testWidgets('accessibility override does not mutate the preference', (
      tester,
    ) async {
      await settings.setHideBottomNavigation(true);
      await tester.pumpWidget(buildShell(accessibleNavigation: true));
      expect(settings.hideBottomNavigation, isTrue);
    });
  });

  group('Settings slider ownership under the shell gesture layer', () {
    /// Builds the shell with the real [SettingsScreen] as the Settings tab so
    /// the real Material [Slider] sits beneath the shell's horizontal
    /// recognizer. The other tabs stay as stubs (no camera/inference needed).
    Widget buildShellWithRealSettings() {
      return MaterialApp(
        home: AppShell(
          settings: settings,
          tts: tts,
          telemetry: telemetry,
          haptics: haptics,
          pagesOverride: (context, shell) => [
            const Scaffold(body: Center(child: Text('PAGE0'))),
            const Scaffold(body: Center(child: Text('PAGE1'))),
            SettingsScreen(settings: settings, onOpenLogsReports: () {}),
            const Scaffold(body: Center(child: Text('PAGE3'))),
          ],
        ),
      );
    }

    testWidgets(
      'dragging the real Slider changes its value and does not navigate',
      (tester) async {
        // Tall surface so the Settings ListView lays out the Slider.
        tester.view.physicalSize = const Size(390 * 3, 2400 * 3);
        tester.view.devicePixelRatio = 3.0;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(buildShellWithRealSettings());
        await tester.tap(find.text('Settings'));
        await tester.pumpAndSettle();

        final sliderFinder = find.byType(Slider);
        expect(sliderFinder, findsOneWidget);

        // The Settings ListView is long; scroll the real Slider into view so
        // the drag actually hit-tests it.
        await tester.ensureVisible(sliderFinder);
        await tester.pumpAndSettle();

        final before = tester.widget<Slider>(sliderFinder).value;
        expect(before, AppSettings.defaultDetectionConfidence);

        // Drag the real Slider horizontally. The Slider's own horizontal
        // recognizer must win the arena against the shell ancestor.
        await tester.drag(sliderFinder, const Offset(120, 0));
        await tester.pumpAndSettle();

        final after = tester.widget<Slider>(sliderFinder).value;
        expect(after, isNot(before));
        // The shell must remain on Settings (index 2) — no primary navigation.
        expect(find.byType(SettingsScreen), findsOneWidget);
        expect(find.text('PAGE1'), findsNothing);
        expect(find.text('PAGE3'), findsNothing);
        // The persisted value follows the slider's end callback.
        expect(settings.detectionConfidence, after);
      },
    );
  });
}
