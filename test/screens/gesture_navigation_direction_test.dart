import 'dart:ui' show SemanticsAction;

import 'package:eyecue_flutter/models/app_settings.dart';
import 'package:eyecue_flutter/models/detection_runtime_state.dart';
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
import 'package:eyecue_flutter/widgets/detection_information_overlay.dart';
import 'package:eyecue_flutter/widgets/gesture_surface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart'
    show CustomSemanticsAction, SemanticsNode;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Fake engine that models the real lifecycle signal order so `TtsService`
/// never leaves a start-confirmation timer pending, and records every spoken
/// phrase so a pause announcement is observable.
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

/// Every user-facing (labelled) custom semantic action in the whole tree.
///
/// `hintOverrides` registers anonymous overriding actions, so only entries with
/// a non-null label are user-facing.
List<String> labelledCustomActions(WidgetTester tester) {
  // Walk from the test view's own pipeline owner: the deprecated single
  // `RendererBinding.pipelineOwner` is not the semantics host in multi-view
  // tests, and the root owner has no semantics owner of its own.
  final root = tester
      .binding
      .renderViews
      .first
      .owner!
      .semanticsOwner!
      .rootSemanticsNode!;
  final labels = <String>[];
  void walk(SemanticsNode node) {
    final data = node.getSemanticsData();
    for (final id in data.customSemanticsActionIds ?? const <int>[]) {
      final label = CustomSemanticsAction.getAction(id)?.label;
      if (label != null) labels.add(label);
    }
    node.visitChildren((child) {
      walk(child);
      return true;
    });
  }

  walk(root);
  return labels;
}

/// Locks in Product Decision 2 for the Detection engine:
/// a left swipe advances to the next tab (`+1`) and a right swipe returns to
/// the previous tab (`-1`).
///
/// The pure `relativeDirectionForGesture` mapping is tested without a
/// camera/native dependency; the widget group below pumps the real screen to pin
/// where the gesture region is (the live viewport branch only) and the
/// commit-on-release contract.
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
    ///
    /// The camera channel reports no cameras: no native platform view is
    /// involved, and the unresolved display rotation makes the depth estimator
    /// report degraded, which is the state that shows the Retry affordance.
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
    ///
    /// [accessibleNavigation] mirrors TalkBack owning lifecycle announcements.
    Future<void> pumpScreen(
      WidgetTester tester, {
      bool permissionGranted = true,
      bool accessibleNavigation = false,
    }) async {
      mockPlatformChannels(permissionGranted: permissionGranted);
      tester.view.physicalSize = const Size(390 * 3, 844 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              final screen = UltralyticsDetectionScreen(
                settings: settings,
                tts: tts,
                telemetry: TelemetryService(),
                haptics: haptics,
                coordinator: coordinator,
                onNavigateRelative: directions.add,
              );
              if (!accessibleNavigation) return screen;
              return MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(accessibleNavigation: true),
                child: screen,
              );
            },
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
      'the gesture region covers the whole main area, only while live',
      (tester) async {
        // Never started: no camera to swipe, so there is no gesture region and
        // every panel button (Start, Retry, Stop, Open Settings) is outside it.
        await pumpScreen(tester);
        expect(find.text('Start Detection'), findsOneWidget);
        expect(find.byType(GestureSurface), findsNothing);

        await startSession(tester);
        final surface = tester.getRect(find.byType(GestureSurface));
        final controls = tester.getRect(find.byType(DetectionActionControls));
        // The region is everything between the top bar and the control row, so a
        // swipe anywhere on the working area is a Detection gesture.
        expect(surface.top, lessThan(controls.top - 400));
        expect(surface.bottom, lessThanOrEqualTo(controls.top));
        expect(surface.width, 390);
      },
    );

    testWidgets('the live subtree holds no button or tappable', (tester) async {
      // The placement fix only holds while nothing interactive sits inside the
      // surface: an inner button would compete with the raw Listener and turn
      // its taps into tap→pause classification.
      await pumpScreen(tester);
      await startSession(tester);
      final surface = find.byType(GestureSurface);
      expect(surface, findsOneWidget);
      expect(
        find.descendant(
          of: surface,
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is GestureDetector ||
                widget is InkWell ||
                widget is ButtonStyleButton ||
                widget is IconButton ||
                widget is FloatingActionButton,
          ),
        ),
        findsNothing,
      );
    });

    testWidgets('a swipe in the live main area navigates exactly once, on '
        'release', (tester) async {
      await pumpScreen(tester);
      await startSession(tester);
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
      await startSession(tester);
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
      await startSession(tester);
      final controls = tester.getRect(find.byType(DetectionActionControls));
      await swipe(tester, Offset(320, controls.center.dy), -260);
      expect(directions, isEmpty);
    });

    testWidgets('a second pointer invalidates a Detection sequence', (
      tester,
    ) async {
      await pumpScreen(tester);
      await startSession(tester);
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

    testWidgets('tapping Start Detection starts the session and never pauses '
        'it', (tester) async {
      await pumpScreen(tester);
      await tester.tap(find.text('Start Detection'));
      await tester.pump();
      // Past the single-tap confirmation window: a tap classified by the
      // gesture region would have paused the session by now.
      await tester.pump(const Duration(milliseconds: 400));

      expect(ttsEngine.spoken, ['Detection started']);
      expect(coordinator.state, isNot(DetectionRuntimeState.paused));
      expect(hapticCalls, ['medium'], reason: 'no light pause tick');
      expect(find.byType(GestureSurface), findsOneWidget);
    });

    testWidgets('tapping Retry depth estimate keeps the live session running', (
      tester,
    ) async {
      await pumpScreen(tester);
      await startSession(tester);

      final retry = find.text('Retry depth estimate');
      expect(
        find.text(kDepthDegradedMessage),
        findsOneWidget,
        reason: 'the degraded depth notice is the state under test',
      );
      await tester.tap(retry);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(ttsEngine.spoken, ['Detection started']); // never "paused"
      expect(coordinator.state, isNot(DetectionRuntimeState.paused));
      expect(hapticCalls, ['medium'], reason: 'no light pause tick');
      expect(find.byType(GestureSurface), findsOneWidget);
    });

    testWidgets('a tap or swipe on a panel button is never a gesture', (
      tester,
    ) async {
      // Permission denied: the panel's own buttons own their pointers.
      await pumpScreen(tester, permissionGranted: false);
      await tester.tap(find.text('Start Detection'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull);
      expect(find.text('Camera permission is required.'), findsOneWidget);
      expect(find.byType(GestureSurface), findsNothing);
      expect(ttsEngine.spoken, isEmpty); // no start, and no pause announcement

      for (final label in [
        'Open app permission settings',
        'Retry camera access',
      ]) {
        await tester.tap(find.text(label));
        await tester.pump(const Duration(milliseconds: 400));
        expect(directions, isEmpty, reason: '$label tap is not a swipe');
        expect(
          ttsEngine.spoken,
          isEmpty,
          reason: '$label tap is not a single tap',
        );
      }

      await swipe(
        tester,
        tester.getCenter(find.text('Retry camera access')),
        -260,
      );
      expect(directions, isEmpty);
      await swipe(
        tester,
        tester.getCenter(find.text('Open app permission settings')),
        260,
      );
      expect(directions, isEmpty);
    });

    testWidgets('the audio pill is one mute node with no custom action', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      try {
        await pumpScreen(tester);
        await startSession(tester);
        final pill = find.semantics.byLabel('Audio guidance, on');
        final nodes = pill.evaluate().toList();
        expect(nodes, hasLength(1), reason: 'the pill must be a single stop');
        final data = nodes.single.getSemanticsData();
        expect(data.flagsCollection.isButton, isTrue);
        expect(data.hasAction(SemanticsAction.tap), isTrue);

        // Repeat moved to the camera view, so the pill exposes no labelled
        // custom action of its own while the camera-view action exists.
        final pillLabels = (data.customSemanticsActionIds ?? const <int>[])
            .map(CustomSemanticsAction.getAction)
            .whereType<CustomSemanticsAction>()
            .map((action) => action.label)
            .whereType<String>()
            .toList();
        expect(pillLabels, isEmpty);
        expect(labelledCustomActions(tester), ['Repeat last alert']);
      } finally {
        handle.dispose();
      }
    });

    testWidgets('the header exposes one Detection heading node', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      try {
        await pumpScreen(tester);
        final heading = find.semantics.byLabel('Detection').evaluate().toList();
        expect(heading, hasLength(1));
        expect(
          heading.single.getSemanticsData().flagsCollection.isHeader,
          isTrue,
        );
        // The visible string is unchanged.
        expect(find.text('Detection Mode'), findsOneWidget);
      } finally {
        handle.dispose();
      }
    });

    testWidgets('accessibility navigation owns the start announcement', (
      tester,
    ) async {
      await pumpScreen(tester, accessibleNavigation: true);
      await tester.tap(find.text('Start Detection'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(ttsEngine.spoken, isEmpty);
      // The transition itself still happened.
      expect(hapticCalls, ['medium']);
      expect(find.byType(GestureSurface), findsOneWidget);
    });

    testWidgets('accessibility navigation owns pause and resume '
        'announcements', (tester) async {
      await pumpScreen(tester, accessibleNavigation: true);
      await tester.tap(find.text('Start Detection'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(ttsEngine.spoken, isEmpty);

      // A single tap on the live viewport pauses, past the confirmation window.
      await tester.tapAt(tester.getCenter(find.byType(GestureSurface)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(ttsEngine.spoken, isEmpty, reason: 'no lifecycle pause speech');

      // A second single tap resumes.
      await tester.tapAt(tester.getCenter(find.byType(GestureSurface)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(ttsEngine.spoken, isEmpty, reason: 'no lifecycle resume speech');
    });

    test('only the four lifecycle utterances are gated', () {
      // The pure gate covers start/stop/pause/resume and nothing else.
      expect(kLifecycleUtterances, [
        'Detection started',
        'Detection stopped',
        'Detection paused',
        'Detection resumed',
      ]);
      for (final utterance in kLifecycleUtterances) {
        expect(
          shouldSpeakLifecycleUtterance(utterance, accessibleNavigation: true),
          isFalse,
          reason: '$utterance must stay silent under TalkBack',
        );
        expect(
          shouldSpeakLifecycleUtterance(utterance, accessibleNavigation: false),
          isTrue,
          reason: '$utterance speaks when EyeCue owns the announcement',
        );
      }
      // Domain speech is never gated.
      for (final utterance in const [
        'Audio on',
        'Quick scan. Nothing detected.',
        'Person ahead, close.',
      ]) {
        expect(
          shouldSpeakLifecycleUtterance(utterance, accessibleNavigation: true),
          isTrue,
          reason: '$utterance is domain speech and must still speak',
        );
      }
    });

    testWidgets('domain speech still plays under accessibility navigation', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      try {
        await pumpScreen(tester, accessibleNavigation: true);
        await tester.tap(find.text('Start Detection'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        expect(ttsEngine.spoken, isEmpty);

        // Unmuting is not lifecycle speech and must still be spoken: the first
        // tap mutes silently, the second tap unmutes with `Audio on`.
        tester.semantics.performAction(
          find.semantics.byLabel('Audio guidance, on'),
          SemanticsAction.tap,
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        tester.semantics.performAction(
          find.semantics.byLabel('Audio guidance, off'),
          SemanticsAction.tap,
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        expect(ttsEngine.spoken, contains('Audio on'));
        expect(ttsEngine.spoken, isNot(contains('Detection started')));
      } finally {
        handle.dispose();
      }
    });

    testWidgets('the camera view is one non-live node hosting Repeat', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      try {
        await pumpScreen(tester);
        await startSession(tester);

        final nodes = find.semantics.byLabel('Camera view').evaluate().toList();
        expect(nodes, hasLength(1));
        final data = nodes.single.getSemanticsData();
        expect(data.flagsCollection.isLiveRegion, isFalse);
        // The label is exactly the static container label: nothing from the
        // overlay or the native preview merged into it, so the overlay rows
        // stay their own nodes under `explicitChildNodes`.
        expect(data.label, 'Camera view');
        expect(find.byType(DetectionInformationOverlay), findsOneWidget);

        // Exactly one user-facing custom action exists on the whole screen.
        expect(labelledCustomActions(tester), ['Repeat last alert']);
      } finally {
        handle.dispose();
      }
    });

    testWidgets('a successful Repeat still replays the last alert', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      try {
        await pumpScreen(tester);
        await startSession(tester);
        await tts.speak('Obstacle ahead');
        expect(tts.lastUtterance, 'Obstacle ahead');

        final spokenBefore = ttsEngine.spoken.length;
        hapticCalls.clear();
        tester.semantics.performAction(
          find.semantics.byLabel('Camera view'),
          SemanticsAction.customAction,
          args: _repeatActionId(tester),
        );
        await tester.pump();

        expect(hapticCalls, ['medium']);
        expect(ttsEngine.spoken, hasLength(spokenBefore + 1));
        expect(ttsEngine.spoken.last, 'Obstacle ahead');
      } finally {
        handle.dispose();
      }
    });

    testWidgets('a Repeat with audio off reports a distinct failure', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      try {
        await pumpScreen(tester);
        await startSession(tester);
        tts.setAudioEnabled(false);
        final spokenBefore = ttsEngine.spoken.length;
        hapticCalls.clear();

        tester.semantics.performAction(
          find.semantics.byLabel('Camera view'),
          SemanticsAction.customAction,
          args: _repeatActionId(tester),
        );
        await tester.pump();

        expect(hapticCalls, [
          'heavy',
        ], reason: 'distinct from the success tick');
        expect(
          ttsEngine.spoken,
          hasLength(spokenBefore),
          reason: 'never speaks',
        );
        final notice = find.semantics.byLabel('Audio guidance is off');
        expect(notice.evaluate(), hasLength(1));
        expect(
          notice
              .evaluate()
              .single
              .getSemanticsData()
              .flagsCollection
              .isLiveRegion,
          isTrue,
        );
      } finally {
        handle.dispose();
      }
    });

    testWidgets('a Repeat with nothing cached reports a generic failure', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      try {
        // Accessibility navigation keeps the lifecycle silent, so no utterance
        // has ever started.
        await pumpScreen(tester, accessibleNavigation: true);
        await tester.tap(find.text('Start Detection'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        expect(tts.lastUtterance, isNull);
        hapticCalls.clear();

        tester.semantics.performAction(
          find.semantics.byLabel('Camera view'),
          SemanticsAction.customAction,
          args: _repeatActionId(tester),
        );
        await tester.pump();

        expect(hapticCalls, ['heavy']);
        expect(ttsEngine.spoken, isEmpty);
        expect(
          find.semantics.byLabel('Nothing to repeat yet').evaluate(),
          hasLength(1),
        );
      } finally {
        handle.dispose();
      }
    });
  });
}

/// The custom-action id of `Repeat last alert` on the camera-view node.
int _repeatActionId(WidgetTester tester) {
  final data = find.semantics
      .byLabel('Camera view')
      .evaluate()
      .single
      .getSemanticsData();
  return (data.customSemanticsActionIds ?? const <int>[]).firstWhere(
    (id) => CustomSemanticsAction.getAction(id)?.label == 'Repeat last alert',
  );
}
