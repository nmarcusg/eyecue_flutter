import 'package:eyecue_flutter/models/app_settings.dart';
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
        home: SettingsScreen(settings: settings, onOpenLogsReports: () {}),
      ),
    );
  }

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
      expect(
        find.bySemanticsLabel(RegExp('Detector cadence target, 15 Hz')),
        findsWidgets,
      );
      expect(
        find.bySemanticsLabel(RegExp('Depth cadence target, 2 Hz')),
        findsWidgets,
      );
      handle.dispose();
    });
  });
}
