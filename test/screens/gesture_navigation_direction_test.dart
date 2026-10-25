import 'package:eyecue_flutter/models/app_settings.dart';
import 'package:eyecue_flutter/screens/ultralytics_detection_screen.dart'
    as detection_engine;
import 'package:eyecue_flutter/screens/ultralytics_detection_screen.dart';
import 'package:eyecue_flutter/services/engine_coordinator.dart';
import 'package:eyecue_flutter/services/gesture_controller.dart';
import 'package:eyecue_flutter/services/haptics_service.dart';
import 'package:eyecue_flutter/services/settings_service.dart';
import 'package:eyecue_flutter/services/telemetry_service.dart';
import 'package:eyecue_flutter/services/tts_service.dart';
import 'package:eyecue_flutter/widgets/detection_action_controls.dart';
import 'package:eyecue_flutter/widgets/gesture_surface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Fake engine that models the real lifecycle signal order so `TtsService`
/// never leaves a start-confirmation timer pending.
class _FakeTtsEngine implements TtsEngine {
  VoidCallback? _onStart;
  VoidCallback? _onComplete;

  @override
  Future<void> dispose() async {}

  @override
  Future<void> init() async {}

  @override
  Future<void> recover() async {}

  @override
  Future<int> speak(String text) async {
    _onStart?.call();
    _onComplete?.call();
    return 1;
  }

  @override
  Future<void> stop() async {}

  @override
  void setStartHandler(VoidCallback? callback) => _onStart = callback;

  @override
  void setCompletionHandler(VoidCallback? callback) => _onComplete = callback;

  @override
  void setCancelHandler(VoidCallback? callback) {}

  @override
  void setErrorHandler(void Function(dynamic error)? handler) {}
}

/// Locks in Product Decision 2 for the Detection engine:
/// a left swipe advances to the next tab (`+1`) and a right swipe returns to
/// the previous tab (`-1`).
///
/// The pure `relativeDirectionForGesture` mapping is tested without a
/// camera/native dependency; the widget group below pumps the real screen (the
/// never-started screen renders no platform view) to pin the gesture region and
/// the commit-on-release contract.
void main() {
  group('Detection gesture → direction', () {
    test('a left swipe advances to the next tab', () {
      expect(
        detection_engine.relativeDirectionForGesture(EyeCueGesture.swipeLeft),
        1,
      );
    });

    test('a right swipe returns to the previous tab', () {
      expect(
        detection_engine.relativeDirectionForGesture(EyeCueGesture.swipeRight),
        -1,
      );
    });

    test('non-horizontal gestures map to no navigation', () {
      for (final gesture in [
        EyeCueGesture.singleTap,
        EyeCueGesture.twoFingerDoubleTap,
        EyeCueGesture.threeFingerTap,
        EyeCueGesture.swipeDown,
      ]) {
        expect(detection_engine.relativeDirectionForGesture(gesture), isNull);
      }
    });
  });

  group('Detection gesture region and commit-on-release', () {
    late SettingsService settings;
    late TtsService tts;
    late HapticsService haptics;
    late List<int> directions;

    setUp(() async {
      settings = SettingsService(store: InMemorySettingsStore());
      tts = TtsService(engine: _FakeTtsEngine());
      await tts.init();
      haptics = HapticsService(
        light: () async {},
        medium: () async {},
        heavy: () async {},
      );
      directions = [];
    });

    tearDown(() => tts.dispose());

    /// Pumps the real screen on a phone-sized surface. The never-started screen
    /// renders no native platform view, so this needs no plugin mocks.
    Future<void> pumpScreen(WidgetTester tester) async {
      tester.view.physicalSize = const Size(390 * 3, 844 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: UltralyticsDetectionScreen(
            settings: settings,
            tts: tts,
            telemetry: TelemetryService(),
            haptics: haptics,
            coordinator: EngineCoordinator(
              preferredEngine: InferenceEngine.ultralytics,
            ),
            onNavigateRelative: directions.add,
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));
      expect(tester.takeException(), isNull);
    }

    /// One horizontal drag of [totalDx] split into `steps` equal moves.
    Future<void> swipe(
      WidgetTester tester,
      Offset start,
      double totalDx, {
      int steps = 8,
    }) async {
      final gesture = await tester.startGesture(start);
      for (var i = 0; i < steps; i++) {
        await gesture.moveBy(Offset(totalDx / steps, 0));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 350));
    }

    testWidgets(
      'the gesture surface covers the whole main area, not just a viewport',
      (tester) async {
        await pumpScreen(tester);
        final surface = tester.getRect(find.byType(GestureSurface));
        final controls = tester.getRect(find.byType(DetectionActionControls));
        // The region is everything between the top bar and the control row, so
        // a swipe anywhere on the working area is a Detection gesture.
        expect(surface.top, lessThan(controls.top - 400));
        expect(surface.bottom, lessThanOrEqualTo(controls.top));
        expect(surface.width, 390);
      },
    );

    testWidgets('a swipe in the main area navigates exactly once, on release', (
      tester,
    ) async {
      await pumpScreen(tester);
      final surface = tester.getRect(find.byType(GestureSurface));

      final gesture = await tester.startGesture(Offset(320, surface.center.dy));
      for (var i = 0; i < 8; i++) {
        await gesture.moveBy(const Offset(-30, 0));
        await tester.pump(const Duration(milliseconds: 16));
        expect(directions, isEmpty); // never before the finger lifts
      }
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 350));
      expect(directions, [1]); // left swipe advances exactly one tab
    });

    testWidgets('a long swipe and a fast swipe each navigate exactly once', (
      tester,
    ) async {
      await pumpScreen(tester);
      final surface = tester.getRect(find.byType(GestureSurface));

      await swipe(tester, Offset(360, surface.center.dy), -300, steps: 20);
      expect(directions, [1]);

      directions.clear();
      await swipe(tester, Offset(60, surface.center.dy), 280, steps: 1);
      expect(directions, [-1]);
    });

    testWidgets('a swipe starting on the action controls row does not '
        'navigate', (tester) async {
      await pumpScreen(tester);
      final controls = tester.getRect(find.byType(DetectionActionControls));
      await swipe(tester, Offset(320, controls.center.dy), -260);
      expect(directions, isEmpty);
    });

    testWidgets('a second pointer invalidates a Detection sequence', (
      tester,
    ) async {
      await pumpScreen(tester);
      final surface = tester.getRect(find.byType(GestureSurface));
      final y = surface.center.dy;

      final first = await tester.startGesture(Offset(320, y));
      await first.moveBy(const Offset(-40, 0));
      await tester.pump(const Duration(milliseconds: 16));
      final second = await tester.startGesture(Offset(320, y + 60));
      await tester.pump(const Duration(milliseconds: 16));
      await first.moveBy(const Offset(-240, 0));
      await tester.pump(const Duration(milliseconds: 16));
      await first.up();
      await second.up();
      await tester.pump(const Duration(milliseconds: 350));
      expect(directions, isEmpty);
    });
  });
}
