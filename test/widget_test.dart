import 'package:eyecue_flutter/models/app_settings.dart';
import 'package:eyecue_flutter/models/detection_runtime_state.dart';
import 'package:eyecue_flutter/screens/help_screen.dart';
import 'package:eyecue_flutter/screens/home_screen.dart';
import 'package:eyecue_flutter/screens/settings_screen.dart';
import 'package:eyecue_flutter/services/engine_coordinator.dart';
import 'package:eyecue_flutter/services/settings_service.dart';
import 'package:eyecue_flutter/services/telemetry_service.dart';
import 'package:eyecue_flutter/theme/app_colors.dart';
import 'package:eyecue_flutter/theme/app_home_theme.dart';
import 'package:eyecue_flutter/widgets/accessible_button.dart';
import 'package:eyecue_flutter/widgets/detection_action_controls.dart';
import 'package:eyecue_flutter/widgets/status_pill.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Lightweight screen smoke tests (no camera / platform plugins involved).
void main() {
  SettingsService settings() => SettingsService(store: InMemorySettingsStore());

  EngineCoordinator coordinator() =>
      EngineCoordinator(preferredEngine: InferenceEngine.ultralytics);

  group('HomeScreen', () {
    Widget homeApp(EngineCoordinator c) => MaterialApp(
      home: HomeScreen(settings: settings(), coordinator: c),
    );

    testWidgets('renders branding and the initial Preparing state', (
      tester,
    ) async {
      await tester.pumpWidget(homeApp(coordinator()));

      // Live wordmark is present.
      expect(find.text('EyeCue'), findsOneWidget);
      // Initial idle -> Preparing with the finalized Auto-start-OFF copy.
      expect(find.text('PREPARING'), findsOneWidget);
      expect(find.text('Swipe left to start!'), findsOneWidget);
      expect(find.text('Detection begins immediately.'), findsOneWidget);
      // The CTA is removed and not replaced.
      expect(find.text('Go to Live Camera'), findsNothing);
      expect(find.byType(AccessibleButton), findsNothing);
    });

    testWidgets('renders Ready from the shared snapshot', (tester) async {
      final c = coordinator();
      c.reportReady();
      await tester.pumpWidget(homeApp(c));

      expect(find.text('READY'), findsOneWidget);
      expect(find.text('Ready when you are'), findsOneWidget);
      expect(find.text('Detection is ready.'), findsOneWidget);
    });

    testWidgets('renders Preparing during active initialization', (
      tester,
    ) async {
      final c = coordinator();
      c.reportState(DetectionRuntimeState.loadingModel);
      await tester.pumpWidget(homeApp(c));

      expect(find.text('PREPARING'), findsOneWidget);
      expect(find.text('Getting things ready'), findsOneWidget);
      expect(find.text('Detection is preparing.'), findsOneWidget);
    });

    testWidgets('renders Paused from the shared snapshot', (tester) async {
      final c = coordinator();
      c.reportPaused();
      await tester.pumpWidget(homeApp(c));

      expect(find.text('PAUSED'), findsOneWidget);
      expect(find.text('Detection is paused'), findsOneWidget);
      expect(find.text('Open Detect to resume.'), findsOneWidget);
    });

    testWidgets('renders Stopped from the shared snapshot', (tester) async {
      final c = coordinator();
      c.reportStopped();
      await tester.pumpWidget(homeApp(c));

      expect(find.text('STOPPED'), findsOneWidget);
      expect(find.text('Detection is stopped'), findsOneWidget);
      expect(find.text('Open Detect to start again.'), findsOneWidget);
    });

    testWidgets('renders Unavailable with the shared safe message', (
      tester,
    ) async {
      final c = coordinator();
      c.reportFailure(
        DetectionFailure(
          category: DetectionFailureCategory.permissionDenied,
          safeMessage: 'Camera permission is required to detect objects.',
          timestamp: DateTime(2026, 1, 1),
        ),
      );
      await tester.pumpWidget(homeApp(c));

      expect(find.text('UNAVAILABLE'), findsOneWidget);
      expect(find.text('Detection needs attention'), findsOneWidget);
      expect(
        find.text('Camera permission is required to detect objects.'),
        findsOneWidget,
      );
    });

    testWidgets('updates the presentation when the shared state changes', (
      tester,
    ) async {
      final c = coordinator();
      await tester.pumpWidget(homeApp(c));

      expect(find.text('PREPARING'), findsOneWidget);
      expect(find.text('READY'), findsNothing);

      c.reportReady();
      await tester.pumpAndSettle();

      expect(find.text('READY'), findsOneWidget);
      expect(find.text('PREPARING'), findsNothing);
    });

    testWidgets('normal layout is fixed and non-scrollable', (tester) async {
      // The visual redesign replaced the scroll container with a fixed layout.
      await tester.pumpWidget(homeApp(coordinator()));

      expect(find.byType(CustomScrollView), findsNothing);
      expect(find.byType(SliverFillRemaining), findsNothing);
      expect(find.byType(ListView), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('SettingsScreen', () {
    // The Settings body is a scrollable ListView of four cards, so use a tall
    // phone-sized surface so all cards are built and visible (ListView builds
    // only the children in the viewport).
    Future<void> pumpSettings(
      WidgetTester tester, {
      required SettingsService service,
      VoidCallback? onOpenLogsReports,
      TelemetryService? telemetry,
    }) async {
      tester.view.physicalSize = const Size(390 * 3, 2000 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: SettingsScreen(
            settings: service,
            onOpenLogsReports: onOpenLogsReports ?? () {},
            telemetry: telemetry,
          ),
        ),
      );
    }

    testWidgets('shows all thesis settings and the Logs & Reports entry', (
      tester,
    ) async {
      var openedLogs = false;
      await pumpSettings(
        tester,
        service: settings(),
        onOpenLogsReports: () => openedLogs = true,
      );

      expect(find.text('Vibration Feedback'), findsOneWidget);
      expect(find.text('Auto-Start on Open'), findsOneWidget);
      expect(find.text('Low Power Mode'), findsOneWidget);
      expect(find.text('Custom EyeCue'), findsOneWidget);
      expect(find.text('Ultralytics'), findsOneWidget);
      expect(find.text('Audio / Voice Guidance'), findsOneWidget);
      expect(find.text('View Logs & Reports'), findsOneWidget);

      // Test-only scope exception: the navigation feature added the "Hide
      // Bottom Navigation" switch to the Preferences card, which pushes the
      // Logs & Reports entry below the viewport. Scroll it into view before
      // tapping; no production behavior is asserted differently here.
      await tester.ensureVisible(find.text('View Logs & Reports'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('View Logs & Reports'));
      expect(openedLogs, isTrue);
    });

    testWidgets('shows the screen title and all four card headings', (
      tester,
    ) async {
      await pumpSettings(tester, service: settings());

      expect(find.text('Settings'), findsOneWidget);
      expect(find.text('Preferences'), findsOneWidget);
      expect(find.text('Audio Guidance'), findsOneWidget);
      expect(find.text('Engine & Sensitivity'), findsOneWidget);
      expect(find.text('System Performance'), findsOneWidget);
    });

    testWidgets('applies the light Home theme to the Settings subtree', (
      tester,
    ) async {
      await pumpSettings(tester, service: settings());

      final theme = Theme.of(tester.element(find.text('Preferences')));
      expect(theme.brightness, Brightness.light);
      expect(theme.scaffoldBackgroundColor, kHomeSurfaceBase);
    });

    testWidgets(
      'app-bar title uses the Detection Mode titleLarge + ink style',
      (tester) async {
        await pumpSettings(tester, service: settings());

        final title = tester.widget<Text>(find.text('Settings'));
        final context = tester.element(find.text('Settings'));
        final expected = Theme.of(
          context,
        ).textTheme.titleLarge?.copyWith(color: kHomeInk);
        expect(title.style?.fontSize, expected?.fontSize);
        expect(title.style?.fontWeight, expected?.fontWeight);
        expect(title.style?.color, kHomeInk);
      },
    );

    testWidgets('parent section titles align with their child rows', (
      tester,
    ) async {
      await pumpSettings(tester, service: settings());

      // The parent heading and its first child row must share the same leading
      // edge (the child ListTile contentPadding is kSpace16, so the heading is
      // inset by the same token).
      final parentLeft = tester.getTopLeft(find.text('Preferences')).dx;
      final childLeft = tester.getTopLeft(find.text('Vibration Feedback')).dx;
      expect(childLeft, parentLeft);

      final audioParentLeft = tester.getTopLeft(find.text('Audio Guidance')).dx;
      final audioChildLeft = tester
          .getTopLeft(find.text('Audio / Voice Guidance'))
          .dx;
      expect(audioChildLeft, audioParentLeft);
    });

    testWidgets('Custom EyeCue aligns with the parent title and only its '
        'sensitivity sub-options are indented', (tester) async {
      await pumpSettings(tester, service: settings());

      // The Custom EyeCue option is a direct child row, so its text leading
      // edge matches the parent section title's leading edge (kSpace16).
      final parentLeft = tester
          .getTopLeft(find.text('Engine & Sensitivity'))
          .dx;
      final customLeft = tester.getTopLeft(find.text('Custom EyeCue')).dx;
      expect(customLeft, parentLeft);

      // The sensitivity presets are sub-options of Custom EyeCue, so their
      // text is indented to the right of the parent row.
      final moreDetectionsLeft = tester
          .getTopLeft(find.text('More detections'))
          .dx;
      expect(moreDetectionsLeft, greaterThan(customLeft));

      // The sub-option radios stay vertically aligned with each other.
      final balancedLeft = tester.getTopLeft(find.text('Balanced')).dx;
      final fewerFalseAlertsLeft = tester
          .getTopLeft(find.text('Fewer false alerts'))
          .dx;
      expect(balancedLeft, moreDetectionsLeft);
      expect(fewerFalseAlertsLeft, moreDetectionsLeft);
    });

    testWidgets('removes the decorative section and row icons', (tester) async {
      // The visual redesign removed the decorative card/row icons; the
      // headings and labels alone carry the meaning.
      await pumpSettings(tester, service: settings());

      expect(find.byIcon(Icons.tune_rounded), findsNothing);
      expect(find.byIcon(Icons.volume_up), findsNothing);
      expect(find.byIcon(Icons.memory_rounded), findsNothing);
      expect(find.byIcon(Icons.bar_chart_rounded), findsNothing);
      expect(find.byIcon(Icons.vibration), findsNothing);
      expect(find.byIcon(Icons.autorenew), findsNothing);
      expect(find.byIcon(Icons.battery_saver), findsNothing);
      // The retained System Performance chevron remains.
      expect(find.byIcon(Icons.chevron_right), findsOneWidget);
    });

    testWidgets('System Performance shows — placeholders without telemetry', (
      tester,
    ) async {
      await pumpSettings(tester, service: settings());

      expect(find.text('Avg FPS'), findsOneWidget);
      expect(find.text('Avg latency (MS)'), findsOneWidget);
      expect(find.text('Avg confidence'), findsOneWidget);
      expect(find.text('—'), findsNWidgets(3));
    });

    testWidgets('System Performance shows labeled averages with telemetry', (
      tester,
    ) async {
      final telemetry = TelemetryService();
      telemetry.recordSample(
        latencyMs: 120,
        inferenceFps: 8,
        objectCount: 1,
        engine: InferenceEngine.ultralytics,
      );
      await pumpSettings(tester, service: settings(), telemetry: telemetry);

      expect(find.text('Avg FPS'), findsOneWidget);
      expect(find.text('Avg latency (MS)'), findsOneWidget);
      expect(find.text('Avg confidence'), findsOneWidget);
      expect(find.text('8.0'), findsOneWidget);
      expect(find.text('120.0'), findsOneWidget);
      // No fabricated accuracy/precision/recall/F1/mAP metric.
      expect(find.textContaining('%ACC'), findsNothing);
      expect(find.textContaining('Accuracy'), findsNothing);
    });

    testWidgets('toggling a setting updates the service', (tester) async {
      final s = settings();
      await pumpSettings(tester, service: s);

      expect(s.lowPowerMode, isFalse);
      await tester.tap(find.text('Low Power Mode'));
      await tester.pumpAndSettle();
      expect(s.lowPowerMode, isTrue);
    });
  });

  group('HelpScreen', () {
    // The Help body is a scrollable ListView, so use a tall phone-sized surface
    // so all four cards are built and visible (ListView builds only the
    // children in the viewport).
    Future<void> pumpHelp(WidgetTester tester) async {
      tester.view.physicalSize = const Size(390 * 3, 1600 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const MaterialApp(home: HelpScreen()));
    }

    testWidgets('explains how it works and the gestures', (tester) async {
      await pumpHelp(tester);
      expect(find.text('How It Works'), findsOneWidget);
      expect(find.text('Gesture Controls'), findsOneWidget);
      expect(find.text('Gesture Confirmation'), findsOneWidget);
      expect(find.textContaining('Two-finger double tap'), findsOneWidget);
      expect(find.textContaining('Single tap'), findsWidgets);
      expect(find.textContaining('Three-finger tap'), findsOneWidget);
      expect(find.textContaining('swipe down'), findsOneWidget);
    });

    testWidgets('shows the screen title and all four section titles', (
      tester,
    ) async {
      await pumpHelp(tester);
      expect(find.text('Help & Gestures'), findsOneWidget);
      expect(find.text('How It Works'), findsOneWidget);
      expect(find.text('Gesture Controls'), findsOneWidget);
      expect(find.text('Gesture Confirmation'), findsOneWidget);
      expect(find.text('Best Use Tip (Android)'), findsOneWidget);
    });

    testWidgets(
      'app-bar title uses the Detection Mode titleLarge + ink style',
      (tester) async {
        await pumpHelp(tester);

        final title = tester.widget<Text>(find.text('Help & Gestures'));
        final context = tester.element(find.text('Help & Gestures'));
        final expected = Theme.of(
          context,
        ).textTheme.titleLarge?.copyWith(color: kHomeInk);
        expect(title.style?.fontSize, expected?.fontSize);
        expect(title.style?.fontWeight, expected?.fontWeight);
        expect(title.style?.color, kHomeInk);
      },
    );

    testWidgets('removes the decorative section icons', (tester) async {
      // The visual redesign removed the decorative section icons; the section
      // titles alone carry the meaning.
      await pumpHelp(tester);
      expect(find.byIcon(Icons.timeline_rounded), findsNothing);
      expect(find.byIcon(Icons.touch_app_rounded), findsNothing);
      expect(find.byIcon(Icons.vibration_rounded), findsNothing);
      expect(find.byIcon(Icons.phone_android_rounded), findsNothing);
    });

    testWidgets('preserves the full body copy verbatim', (tester) async {
      await pumpHelp(tester);
      // How It Works numbered steps + the on-device note.
      expect(find.textContaining('1. Open EyeCue.'), findsOneWidget);
      expect(
        find.textContaining('EyeCue runs entirely on your device'),
        findsOneWidget,
      );
      // Gesture Controls bullets.
      expect(
        find.textContaining('Two-finger double tap — start or exit'),
        findsOneWidget,
      );
      expect(
        find.textContaining('One-finger swipe down — repeat the most recent'),
        findsOneWidget,
      );
      // Gesture Confirmation prose.
      expect(
        find.textContaining('Every gesture gives instant feedback'),
        findsOneWidget,
      );
      // Best Use Tip (Android) bullets.
      expect(
        find.textContaining('Mount or carry the phone at chest height'),
        findsOneWidget,
      );
      expect(
        find.textContaining('In Low Power Mode detection runs at a slower'),
        findsOneWidget,
      );
    });

    testWidgets('applies the light Home theme to the Help subtree', (
      tester,
    ) async {
      await pumpHelp(tester);
      // Read the theme from inside the Help subtree (the Scaffold is below the
      // Help-local Theme wrapper), confirming the light buildHomeTheme() is
      // applied to the Help content rather than the surrounding app theme.
      final context = tester.element(find.byType(Scaffold));
      final theme = Theme.of(context);
      expect(theme.brightness, Brightness.light);
      // buildHomeTheme() uses the light #F5F5F5 content surface.
      expect(theme.scaffoldBackgroundColor, const Color(0xFFF5F5F5));
    });
  });

  // The full DetectionScreen cannot be pumped without CameraPlatform /
  // permission_handler mocks (see docs/detection-screen-plan.md §6.1), so the
  // visual/state contract is covered by pumping the plugin-free subtrees that
  // the screen composes: the header title, the StatusPill, the audio pill, and
  // the single two-control row (DetectionActionControls).
  group('DetectionScreen', () {
    Widget detectionChrome(Widget child) {
      return MaterialApp(
        home: Theme(
          data: buildHomeTheme(),
          child: Scaffold(body: child),
        ),
      );
    }

    testWidgets('renders the single Detection Mode title', (tester) async {
      await tester.pumpWidget(
        detectionChrome(
          Builder(
            builder: (context) => Text(
              'Detection Mode',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: kHomeInk,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      );

      expect(find.text('Detection Mode'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders a StatusPill with a valid status label', (
      tester,
    ) async {
      await tester.pumpWidget(
        detectionChrome(
          const StatusPill(label: 'Detecting', color: kStatusGreen),
        ),
      );

      expect(find.byType(StatusPill), findsOneWidget);
      expect(
        const ['Stopped', 'Paused', 'Detecting'].contains('Detecting'),
        isTrue,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders exactly two normal physical controls in one row', (
      tester,
    ) async {
      await tester.pumpWidget(
        detectionChrome(
          DetectionActionControls(
            outcome: DetectionStatusOutcome.ready,
            onPause: () {},
            onResume: () {},
            onStop: () {},
            onStart: () {},
            onQuickScan: () {},
          ),
        ),
      );

      // The consolidated lifecycle control plus the physical Quick Scan.
      expect(find.text('PAUSE'), findsOneWidget);
      expect(find.text('QUICK SCAN'), findsOneWidget);
      // The removed normal controls are gone.
      expect(find.text('Start'), findsNothing);
      expect(find.text('Stop'), findsNothing);
      expect(find.text('Resume'), findsNothing);
      expect(find.text('Repeat'), findsNothing);
      expect(find.text('Correct last announcement'), findsNothing);
      expect(find.text('Scan'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders the AUDIO ON pill', (tester) async {
      await tester.pumpWidget(
        detectionChrome(
          Builder(
            builder: (context) => Semantics(
              button: true,
              enabled: true,
              label: 'Audio guidance, on',
              child: Text(
                'AUDIO ON',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: kHomeInk,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ),
        ),
      );

      expect(find.text('AUDIO ON'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
