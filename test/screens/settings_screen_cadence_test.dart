import 'package:eyecue_flutter/models/app_settings.dart';
import 'package:eyecue_flutter/models/detector_model.dart';
import 'package:eyecue_flutter/services/research_session_service.dart';
import 'package:eyecue_flutter/services/telemetry_service.dart';
import 'package:eyecue_flutter/screens/settings_screen.dart';
import 'package:eyecue_flutter/services/settings_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  SettingsService service() => SettingsService(store: InMemorySettingsStore());

  Future<void> pumpSettings(
    WidgetTester tester,
    SettingsService settings, {
    double textScale = 1,
    ResearchSessionService? researchSessions,
  }) async {
    // Tall surface so every card is built: ListView only builds what is in the
    // viewport. Larger text needs a taller surface for the same reason.
    tester.view.physicalSize = Size(390 * 3, (textScale > 1 ? 8000 : 4000) * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: SettingsScreen(
          settings: settings,
          researchSessions: researchSessions,
          onOpenLogsReports: () {},
        ),
      ),
    );
  }

  testWidgets(
    'alert controls preserve values when metric mode or trial lock disables edits',
    (tester) async {
      final settings = service();
      await settings.setAlertDistances(alertMeters: 3, urgentMeters: 2);
      await pumpSettings(tester, settings);
      expect(find.text('Alert distance: 3.00 m'), findsOneWidget);
      expect(
        tester
            .widget<Slider>(find.byKey(const ValueKey('alert-distance')))
            .onChanged,
        isNotNull,
      );
      await settings.setDistanceEstimationMode(
        DistanceEstimationMode.boundingBoxApproximation,
      );
      await tester.pump();
      expect(
        tester
            .widget<Slider>(find.byKey(const ValueKey('alert-distance')))
            .onChanged,
        isNull,
      );
      expect(settings.alertDistanceMeters, 3);
      await settings.setDistanceEstimationMode(
        DistanceEstimationMode.monocularDepth,
      );
      settings.alertDistancesLocked = () => true;
      await tester.pumpWidget(const SizedBox());
      await pumpSettings(tester, settings, textScale: 2);
      expect(
        tester
            .widget<Slider>(find.byKey(const ValueKey('urgent-distance')))
            .onChanged,
        isNull,
      );
      expect(find.textContaining('Finish the open trial'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'restored trial displays frozen effective distances instead of preferences',
    (tester) async {
      final telemetry = TelemetryService();
      final store = InMemoryResearchSessionStore();
      final initial = ResearchSessionService(
        telemetry: telemetry,
        store: store,
      );
      addTearDown(initial.dispose);
      await initial.start(
        participantCode: 'P-001',
        trialLabel: 'frozen',
        detector: const DetectorModelRef(
          id: 'builtin',
          name: 'Built-in YOLOv8n',
          fingerprint: DetectorModel.builtInFingerprint,
          classCount: 80,
        ),
        settings: const AppSettings(
          alertDistanceMeters: 3,
          urgentDistanceMeters: 1,
        ),
      );
      await initial.pause();
      final restored = ResearchSessionService(
        telemetry: telemetry,
        store: store,
      );
      addTearDown(restored.dispose);
      await restored.load();
      expect(restored.state, ResearchSessionState.paused);
      expect(restored.openTrialAlertConfiguration?['normalMaxMeters'], 3);
      expect(restored.openTrialAlertConfiguration?['urgentBelowMeters'], 1);
      final settings = service();
      expect(settings.alertDistanceMeters, 2);
      expect(settings.urgentDistanceMeters, 1.5);
      await pumpSettings(tester, settings, researchSessions: restored);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('alert-distance')),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(find.text('Alert distance: 3.00 m'), findsOneWidget);
      expect(find.text('Urgent distance: 1.00 m'), findsOneWidget);
      final normal = tester.widget<Slider>(
        find.byKey(const ValueKey('alert-distance')),
      );
      final urgent = tester.widget<Slider>(
        find.byKey(const ValueKey('urgent-distance')),
      );
      expect(normal.value, 3);
      expect(urgent.value, 1);
      expect(normal.onChanged, isNull);
      expect(urgent.onChanged, isNull);
      expect(find.textContaining('Finish the open trial'), findsOneWidget);
    },
  );

  group('SettingsScreen inference cadence', () {
    testWidgets('renders both cadence targets with their units', (
      tester,
    ) async {
      await pumpSettings(tester, service());

      expect(find.text('Inference Cadence'), findsOneWidget);
      expect(find.text('Automatic detector cadence'), findsOneWidget);
      expect(find.text('Detector cadence target: 15 Hz'), findsOneWidget);
      expect(find.text('Depth cadence target: 2 Hz'), findsOneWidget);
      expect(find.textContaining('not a guaranteed rate'), findsOneWidget);
    });

    testWidgets('automatic toggle persists null and the 15 Hz default', (
      tester,
    ) async {
      final settings = service();
      await pumpSettings(tester, settings);
      expect(settings.detectionTargetHz, isNull);

      await tester.tap(find.text('Automatic detector cadence'));
      await tester.pumpAndSettle();
      expect(settings.detectionTargetHz, 15);
      expect(find.text('Target: 15 Hz'), findsOneWidget);

      await tester.tap(find.text('Automatic detector cadence'));
      await tester.pumpAndSettle();
      expect(settings.detectionTargetHz, isNull);
    });

    testWidgets('depth control is disabled in bounding box mode and keeps '
        'its stored value', (tester) async {
      final settings = service();
      await settings.setDepthTargetHz(6);
      await settings.setDistanceEstimationMode(
        DistanceEstimationMode.boundingBoxApproximation,
      );
      await pumpSettings(tester, settings);

      final depthSlider = tester.widget<Slider>(
        find.byKey(const ValueKey('cadenceDepthSlider')),
      );
      expect(depthSlider.onChanged, isNull);
      expect(settings.depthTargetHz, 6);
      expect(find.text('Depth cadence target: 6 Hz'), findsOneWidget);
      expect(
        find.textContaining('Depth inference is off in Bounding box mode'),
        findsOneWidget,
      );
    });

    testWidgets('shows the low power clamp sentence with the caps', (
      tester,
    ) async {
      final settings = service();
      await settings.setDetectionTargetHz(20);
      await settings.setDepthTargetHz(6);
      await settings.setLowPowerMode(true);
      await pumpSettings(tester, settings);

      expect(
        find.text('Low power mode limits detection to 4 Hz and depth to 2 Hz.'),
        findsOneWidget,
      );
    });

    testWidgets('does not show a clamp sentence without low power', (
      tester,
    ) async {
      final settings = service();
      await settings.setDetectionTargetHz(20);
      await settings.setDepthTargetHz(6);
      await pumpSettings(tester, settings);

      expect(find.textContaining('Low power mode limits'), findsNothing);
    });

    testWidgets('lays out at 200% text scale without overflow', (tester) async {
      final settings = service();
      await settings.setDetectionTargetHz(12);
      await settings.setDepthTargetHz(4);
      await pumpSettings(tester, settings, textScale: 2);

      expect(find.text('Detector cadence target: 12 Hz'), findsOneWidget);
      expect(find.text('Depth cadence target: 4 Hz'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('exposes one semantic label per cadence control', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pumpSettings(tester, service());

      expect(
        find.bySemanticsLabel(RegExp('Automatic detector cadence')),
        findsOneWidget,
      );
      // The label-only wrapper was removed: the visible title is the name node
      // and the slider announces its hertz value separately.
      expect(
        find.bySemanticsLabel(RegExp('Detector cadence target: 15 Hz')),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(RegExp('Depth cadence target: 2 Hz')),
        findsOneWidget,
      );
      // No wrapper label duplicates the title in comma form.
      expect(
        find.bySemanticsLabel(RegExp('Detector cadence target, ')),
        findsNothing,
      );
      handle.dispose();
    });
  });
}
