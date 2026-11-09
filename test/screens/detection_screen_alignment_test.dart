import 'package:eyecue_flutter/models/app_settings.dart';
import 'package:eyecue_flutter/screens/ultralytics_detection_screen.dart';
import 'package:eyecue_flutter/services/engine_coordinator.dart';
import 'package:eyecue_flutter/services/haptics_service.dart';
import 'package:eyecue_flutter/services/settings_service.dart';
import 'package:eyecue_flutter/services/telemetry_service.dart';
import 'package:eyecue_flutter/services/tts_service.dart';
import 'package:eyecue_flutter/theme/app_colors.dart';
import 'package:eyecue_flutter/widgets/detection_action_controls.dart';
import 'package:eyecue_flutter/widgets/gesture_surface.dart';
import 'package:eyecue_flutter/widgets/status_pill.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Fake engine that models the real lifecycle signal order so `TtsService`
/// never leaves a start-confirmation timer pending, and records every spoken
/// phrase so the audio toggle is observable.
///
/// Duplicated from `gesture_navigation_direction_test.dart` because those
/// helpers are file-private; sharing them would mean editing an unrelated test
/// file. This file covers only the geometry that suite does not assert.
class _FakeTtsEngine implements TtsEngine {
  final List<String> spoken = [];
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
    spoken.add(text);
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

/// Pins the one shared 16 dp Detection gutter and the audio-pill target /
/// capsule separation.
///
/// The gutter is applied *inside* `GestureSurface` and inside the `Camera view`
/// semantics node, so the gesture region stays the whole flexible area and the
/// `Repeat last alert` action stays reachable. Those invariants are asserted by
/// `gesture_navigation_direction_test.dart`; this file asserts the geometry it
/// does not cover.
void main() {
  group('Detection screen alignment', () {
    late SettingsService settings;
    late TtsService tts;
    late _FakeTtsEngine ttsEngine;
    late HapticsService haptics;
    late List<String> hapticCalls;
    late List<int> directions;
    late EngineCoordinator coordinator;

    setUp(() async {
      settings = SettingsService(store: InMemorySettingsStore());
      ttsEngine = _FakeTtsEngine();
      tts = TtsService(engine: ttsEngine);
      await tts.init();
      hapticCalls = [];
      haptics = HapticsService(
        light: () async => hapticCalls.add('light'),
        medium: () async => hapticCalls.add('medium'),
        heavy: () async => hapticCalls.add('heavy'),
      );
      directions = [];
      coordinator = EngineCoordinator(
        preferredEngine: InferenceEngine.ultralytics,
      );
    });

    tearDown(() => tts.dispose());

    /// Answers the two platform channels the screen touches on start.
    void mockPlatformChannels({bool permissionGranted = true}) {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        const MethodChannel('flutter.baseflow.com/permissions/methods'),
        (call) async {
          if (call.method == 'checkPermissionStatus') {
            return permissionGranted ? 1 : 0;
          }
          if (call.method == 'requestPermissions') {
            return <int, int>{1: permissionGranted ? 1 : 0};
          }
          return null;
        },
      );
      messenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/camera'),
        (call) async => <Object?>[],
      );
    }

    /// Pumps the real screen on a phone-sized surface.
    Future<void> pumpScreen(WidgetTester tester) async {
      mockPlatformChannels();
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
            coordinator: coordinator,
            onNavigateRelative: directions.add,
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));
      expect(tester.takeException(), isNull);
    }

    /// Starts a live session from the never-started screen.
    Future<void> startSession(WidgetTester tester) async {
      await tester.tap(find.text('Start Detection'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull);
      expect(hapticCalls, ['medium'], reason: 'start is not a tap gesture');
      // The start haptic belongs to the start, not to anything below.
      hapticCalls.clear();
    }

    testWidgets('header, viewport and action cards share one 16 dp gutter', (
      tester,
    ) async {
      await pumpScreen(tester);
      await startSession(tester);

      expect(tester.getTopLeft(find.text('Detection Mode')).dx, 16);

      final viewport = tester.getRect(
        find.byKey(const ValueKey('detection-viewport')),
      );
      expect(viewport.left, 16);
      expect(viewport.right, 374);

      final controls = tester.getRect(find.byType(DetectionActionControls));
      expect(controls.left, 16);
      expect(controls.right, 374);

      // The gesture region itself is untouched: still the whole flexible area.
      expect(tester.getRect(find.byType(GestureSurface)).width, 390);

      // The action-row band is still painted edge-to-edge behind the cards.
      expect(
        find.byWidgetPredicate(
          (widget) => widget is Container && widget.color == kHomeSurfaceBase,
        ),
        findsWidgets,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('the audio pill keeps a 64 by 56 target with a content-sized '
        'capsule', (tester) async {
      await pumpScreen(tester);
      await startSession(tester);

      final target = tester.getSize(
        find.byKey(const ValueKey('audio-pill-target')),
      );
      expect(target.height, 56);
      expect(target.width, greaterThanOrEqualTo(64));

      final capsule = tester.getSize(
        find.byKey(const ValueKey('audio-pill-capsule')),
      );
      expect(capsule.height, lessThan(56));

      final pill = tester.getSize(find.byType(StatusPill));
      // StatusPill carries `Border.all(width: 1.5)`, i.e. exactly 3 dp of extra
      // height that the deliberately borderless capsule does not add
      // (design-spec §3.3.3 / OQ12). The measured delta in this harness is
      // 3.0 dp, so the tolerance is the pill's border width; the answer is to
      // record it, never to restyle the device-verified status pill.
      expect(
        (capsule.height - pill.height).abs(),
        lessThanOrEqualTo(3),
        reason: 'capsule=$capsule pill=$pill',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('a tap in the target margin toggles mute exactly once and is '
        'not a gesture', (tester) async {
      await pumpScreen(tester);
      await startSession(tester);
      expect(settings.audioEnabled, isTrue);

      final capsuleRect = tester.getRect(
        find.byKey(const ValueKey('audio-pill-capsule')),
      );
      final targetRect = tester.getRect(
        find.byKey(const ValueKey('audio-pill-target')),
      );
      expect(targetRect.bottom - capsuleRect.bottom, greaterThanOrEqualTo(2));

      await tester.tapAt(Offset(capsuleRect.center.dx, capsuleRect.bottom + 4));
      await tester.pump();
      expect(settings.audioEnabled, isFalse);
      expect(directions, isEmpty);
      // A `singleTap` classification would have produced a wayfinding haptic
      // and/or a pause; neither may happen for a pill tap.
      expect(hapticCalls, isEmpty);

      await tester.tapAt(capsuleRect.center);
      await tester.pump();
      expect(settings.audioEnabled, isTrue);
      expect(ttsEngine.spoken, contains('Audio on'));
      expect(hapticCalls, isEmpty);
      expect(tester.takeException(), isNull);
    });
  });
}
