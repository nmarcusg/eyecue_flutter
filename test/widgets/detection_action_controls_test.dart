import 'dart:ui' show SemanticsAction, Tristate;

import 'package:eyecue_flutter/services/engine_coordinator.dart';
import 'package:eyecue_flutter/theme/app_colors.dart';
import 'package:eyecue_flutter/theme/app_home_theme.dart';
import 'package:eyecue_flutter/widgets/detection_action_controls.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

/// Wraps the controls in a minimal light-theme scaffold sized like the
/// Detection control row.
Widget wrap(Widget child) => MaterialApp(
  home: Scaffold(
    body: Center(child: SizedBox(width: 360, height: 96, child: child)),
  ),
);

/// A harness that records every dispatched callback.
class Recorder {
  int pause = 0;
  int resume = 0;
  int stop = 0;
  int start = 0;
  int scan = 0;
}

Widget buildControls(
  DetectionStatusOutcome outcome,
  Recorder recorder, {
  Key? key,
}) => wrap(
  DetectionActionControls(
    key: key,
    outcome: outcome,
    onPause: () => recorder.pause++,
    onResume: () => recorder.resume++,
    onStop: () => recorder.stop++,
    onStart: () => recorder.start++,
    onQuickScan: () => recorder.scan++,
  ),
);

/// The center of the left (lifecycle) control.
Offset lifecycleCenter(WidgetTester tester) {
  final finder = find.text(_primaryLabelFor(tester));
  return tester.getCenter(finder);
}

String _primaryLabelFor(WidgetTester tester) {
  for (final label in const [
    'PAUSE',
    'RESUME',
    'START',
    'PREPARING',
    'UNAVAILABLE',
  ]) {
    if (find.text(label).evaluate().isNotEmpty) return label;
  }
  return '';
}

void main() {
  group('layout', () {
    testWidgets('renders exactly two controls in one row', (tester) async {
      await tester.pumpWidget(
        buildControls(DetectionStatusOutcome.ready, Recorder()),
      );
      expect(find.byType(Row), findsWidgets);
      expect(find.text('PAUSE'), findsOneWidget);
      expect(find.text('QUICK SCAN'), findsOneWidget);
      // Exactly two interactive controls: one lifecycle Listener and one
      // Quick Scan GestureDetector.
      expect(find.byType(DetectionActionControls), findsOneWidget);
      expect(find.byType(GestureDetector), findsOneWidget);
    });
  });

  group('label and enabled state per coordinator outcome', () {
    testWidgets('ready shows PAUSE with hold instruction', (tester) async {
      await tester.pumpWidget(
        buildControls(DetectionStatusOutcome.ready, Recorder()),
      );
      expect(find.text('PAUSE'), findsOneWidget);
      expect(find.text(kHoldInstruction), findsOneWidget);
    });

    testWidgets('paused shows RESUME with hold instruction', (tester) async {
      await tester.pumpWidget(
        buildControls(DetectionStatusOutcome.paused, Recorder()),
      );
      expect(find.text('RESUME'), findsOneWidget);
      expect(find.text(kHoldInstruction), findsOneWidget);
    });

    testWidgets('stopped shows START with hold-to-start instruction', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildControls(DetectionStatusOutcome.stopped, Recorder()),
      );
      expect(find.text('START'), findsOneWidget);
      expect(find.text(kHoldToStartInstruction), findsOneWidget);
    });

    testWidgets('preparing shows disabled PREPARING with no secondary', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildControls(DetectionStatusOutcome.preparing, Recorder()),
      );
      expect(find.text('PREPARING'), findsOneWidget);
      expect(find.text(kHoldInstruction), findsNothing);
      expect(find.text(kHoldToStartInstruction), findsNothing);
    });

    testWidgets('unavailable shows disabled UNAVAILABLE with no secondary', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildControls(DetectionStatusOutcome.unavailable, Recorder()),
      );
      expect(find.text('UNAVAILABLE'), findsOneWidget);
      expect(find.text(kHoldInstruction), findsNothing);
    });
  });

  group('tap behavior', () {
    testWidgets('tap Pause dispatches onPause', (tester) async {
      final recorder = Recorder();
      await tester.pumpWidget(
        buildControls(DetectionStatusOutcome.ready, recorder),
      );
      await tester.tap(find.text('PAUSE'));
      await tester.pump();
      expect(recorder.pause, 1);
      expect(recorder.stop, 0);
    });

    testWidgets('tap Resume dispatches onResume', (tester) async {
      final recorder = Recorder();
      await tester.pumpWidget(
        buildControls(DetectionStatusOutcome.paused, recorder),
      );
      await tester.tap(find.text('RESUME'));
      await tester.pump();
      expect(recorder.resume, 1);
      expect(recorder.stop, 0);
    });

    testWidgets('stopped tap is a no-op', (tester) async {
      final recorder = Recorder();
      await tester.pumpWidget(
        buildControls(DetectionStatusOutcome.stopped, recorder),
      );
      await tester.tap(find.text('START'));
      await tester.pump();
      expect(recorder.start, 0);
      expect(recorder.pause, 0);
      expect(recorder.resume, 0);
      expect(recorder.stop, 0);
    });

    testWidgets('preparing tap is a no-op', (tester) async {
      final recorder = Recorder();
      await tester.pumpWidget(
        buildControls(DetectionStatusOutcome.preparing, recorder),
      );
      await tester.tap(find.text('PREPARING'));
      await tester.pump();
      expect(recorder.pause, 0);
      expect(recorder.stop, 0);
    });

    testWidgets('unavailable tap is a no-op', (tester) async {
      final recorder = Recorder();
      await tester.pumpWidget(
        buildControls(DetectionStatusOutcome.unavailable, recorder),
      );
      await tester.tap(find.text('UNAVAILABLE'));
      await tester.pump();
      expect(recorder.pause, 0);
      expect(recorder.resume, 0);
      expect(recorder.stop, 0);
      expect(recorder.start, 0);
    });
  });

  group('three-second hold', () {
    testWidgets('three-second hold on ready dispatches Stop once', (
      tester,
    ) async {
      final recorder = Recorder();
      await tester.pumpWidget(
        buildControls(DetectionStatusOutcome.ready, recorder),
      );
      final gesture = await tester.startGesture(lifecycleCenter(tester));
      await tester.pump(kLifecycleHoldDuration);
      await tester.pump();
      expect(recorder.stop, 1);
      expect(recorder.pause, 0);
      await gesture.up();
      await tester.pump();
      // No duplicate dispatch after release.
      expect(recorder.stop, 1);
    });

    testWidgets('three-second hold on stopped dispatches Start once', (
      tester,
    ) async {
      final recorder = Recorder();
      await tester.pumpWidget(
        buildControls(DetectionStatusOutcome.stopped, recorder),
      );
      final gesture = await tester.startGesture(lifecycleCenter(tester));
      await tester.pump(kLifecycleHoldDuration);
      await tester.pump();
      expect(recorder.start, 1);
      await gesture.up();
      await tester.pump();
      expect(recorder.start, 1);
    });

    testWidgets('progress begins at pointer down and spans three seconds', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildControls(DetectionStatusOutcome.ready, Recorder()),
      );
      final gesture = await tester.startGesture(lifecycleCenter(tester));
      await tester.pump();
      // Progress container is present immediately at pointer down.
      expect(find.byType(FractionallySizedBox), findsOneWidget);
      final start = tester
          .widget<FractionallySizedBox>(find.byType(FractionallySizedBox))
          .widthFactor;
      expect(start, 0);
      // Halfway through the hold, progress is roughly half.
      await tester.pump(const Duration(milliseconds: 1500));
      final mid = tester
          .widget<FractionallySizedBox>(find.byType(FractionallySizedBox))
          .widthFactor!;
      expect(mid, greaterThan(0.3));
      expect(mid, lessThan(0.7));
      await gesture.up();
      await tester.pump();
    });

    testWidgets('KEEP HOLDING appears at kLongPressTimeout without reset', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildControls(DetectionStatusOutcome.ready, Recorder()),
      );
      final gesture = await tester.startGesture(lifecycleCenter(tester));
      await tester.pump();
      expect(find.text(kHoldInstruction), findsOneWidget);
      await tester.pump(kLongPressTimeout);
      expect(find.text(kKeepHoldingInstruction), findsOneWidget);
      // Progress did not reset to zero at the classification boundary.
      final progress = tester
          .widget<FractionallySizedBox>(find.byType(FractionallySizedBox))
          .widthFactor!;
      expect(progress, greaterThan(0));
      await gesture.up();
      await tester.pump();
    });

    testWidgets('early release before kLongPressTimeout is a tap', (
      tester,
    ) async {
      final recorder = Recorder();
      await tester.pumpWidget(
        buildControls(DetectionStatusOutcome.ready, recorder),
      );
      final gesture = await tester.startGesture(lifecycleCenter(tester));
      await tester.pump(const Duration(milliseconds: 100));
      await gesture.up();
      await tester.pump();
      expect(recorder.pause, 1);
      expect(recorder.stop, 0);
    });

    testWidgets('cancelled hold at/after timeout does not become a tap', (
      tester,
    ) async {
      final recorder = Recorder();
      await tester.pumpWidget(
        buildControls(DetectionStatusOutcome.ready, recorder),
      );
      final gesture = await tester.startGesture(lifecycleCenter(tester));
      await tester.pump(kLongPressTimeout);
      await tester.pump(const Duration(milliseconds: 200));
      await gesture.up();
      await tester.pump();
      expect(recorder.pause, 0);
      expect(recorder.stop, 0);
    });

    testWidgets('progress resets after an early release', (tester) async {
      await tester.pumpWidget(
        buildControls(DetectionStatusOutcome.ready, Recorder()),
      );
      final gesture = await tester.startGesture(lifecycleCenter(tester));
      await tester.pump(const Duration(milliseconds: 100));
      await gesture.up();
      await tester.pump();
      expect(find.byType(FractionallySizedBox), findsNothing);
    });

    testWidgets('pointer cancel dispatches no action', (tester) async {
      final recorder = Recorder();
      await tester.pumpWidget(
        buildControls(DetectionStatusOutcome.ready, recorder),
      );
      final gesture = await tester.startGesture(lifecycleCenter(tester));
      await tester.pump(const Duration(milliseconds: 100));
      await gesture.cancel();
      await tester.pump();
      expect(recorder.pause, 0);
      expect(recorder.stop, 0);
    });

    testWidgets('outcome change cancels an in-progress hold', (tester) async {
      final recorder = Recorder();
      await tester.pumpWidget(
        buildControls(DetectionStatusOutcome.ready, recorder),
      );
      final gesture = await tester.startGesture(lifecycleCenter(tester));
      await tester.pump(const Duration(milliseconds: 100));
      // Rebuild with a different outcome mid-hold.
      await tester.pumpWidget(
        buildControls(DetectionStatusOutcome.paused, recorder),
      );
      await tester.pump();
      await gesture.up();
      await tester.pump();
      expect(recorder.pause, 0);
      expect(recorder.stop, 0);
      expect(recorder.resume, 0);
    });
  });

  group('quick scan gating', () {
    testWidgets('quick scan enabled for ready', (tester) async {
      final recorder = Recorder();
      await tester.pumpWidget(
        buildControls(DetectionStatusOutcome.ready, recorder),
      );
      await tester.tap(find.text('QUICK SCAN'));
      await tester.pump();
      expect(recorder.scan, 1);
    });

    testWidgets('quick scan disabled for paused', (tester) async {
      final recorder = Recorder();
      await tester.pumpWidget(
        buildControls(DetectionStatusOutcome.paused, recorder),
      );
      await tester.tap(find.text('QUICK SCAN'));
      await tester.pump();
      expect(recorder.scan, 0);
    });

    testWidgets('quick scan disabled for stopped', (tester) async {
      final recorder = Recorder();
      await tester.pumpWidget(
        buildControls(DetectionStatusOutcome.stopped, recorder),
      );
      await tester.tap(find.text('QUICK SCAN'));
      await tester.pump();
      expect(recorder.scan, 0);
    });

    testWidgets('quick scan disabled for preparing', (tester) async {
      final recorder = Recorder();
      await tester.pumpWidget(
        buildControls(DetectionStatusOutcome.preparing, recorder),
      );
      await tester.tap(find.text('QUICK SCAN'));
      await tester.pump();
      expect(recorder.scan, 0);
    });

    testWidgets('quick scan disabled for unavailable', (tester) async {
      final recorder = Recorder();
      await tester.pumpWidget(
        buildControls(DetectionStatusOutcome.unavailable, recorder),
      );
      await tester.tap(find.text('QUICK SCAN'));
      await tester.pump();
      expect(recorder.scan, 0);
    });

    testWidgets('quick scan disabled during an active hold', (tester) async {
      final recorder = Recorder();
      await tester.pumpWidget(
        buildControls(DetectionStatusOutcome.ready, recorder),
      );
      final gesture = await tester.startGesture(lifecycleCenter(tester));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.text('QUICK SCAN'));
      await tester.pump();
      expect(recorder.scan, 0);
      await gesture.up();
      await tester.pump();
    });
  });

  group('TalkBack semantics', () {
    /// Finds the single semantic node whose label matches [label].
    SemanticsNode nodeFor(WidgetTester tester, String label) {
      final nodes = find.semantics.byLabel(label).evaluate().toList();
      expect(nodes, isNotEmpty, reason: 'No semantic node labelled: $label');
      return nodes.first;
    }

    testWidgets('ready lifecycle control is an enabled button with hold hint', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        buildControls(DetectionStatusOutcome.ready, Recorder()),
      );
      final node = nodeFor(tester, 'PAUSE');
      final data = node.getSemanticsData();
      expect(data.flagsCollection.isButton, isTrue);
      expect(data.flagsCollection.isEnabled, Tristate.isTrue);
      expect(data.hasAction(SemanticsAction.tap), isTrue);
      expect(node.hint, contains('Hold for three seconds to stop'));
      handle.dispose();
    });

    testWidgets('stopped control stays actionable with a hold-only hint', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        buildControls(DetectionStatusOutcome.stopped, Recorder()),
      );
      final node = nodeFor(tester, 'START');
      final data = node.getSemanticsData();
      // The stopped tap is a no-op, but the control must remain semantically
      // actionable because the three-second hold starts detection.
      expect(data.flagsCollection.isButton, isTrue);
      expect(data.flagsCollection.isEnabled, Tristate.isTrue);
      expect(data.hasAction(SemanticsAction.tap), isTrue);
      expect(node.hint, contains('Hold for three seconds to start'));
      handle.dispose();
    });

    testWidgets('preparing control is a disabled button with a reason', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        buildControls(DetectionStatusOutcome.preparing, Recorder()),
      );
      final node = nodeFor(tester, 'PREPARING');
      final data = node.getSemanticsData();
      expect(data.flagsCollection.isButton, isTrue);
      expect(data.flagsCollection.isEnabled, Tristate.isFalse);
      expect(data.hasAction(SemanticsAction.tap), isFalse);
      expect(node.hint, 'Detection is preparing');
      handle.dispose();
    });

    testWidgets('unavailable control is a disabled button with a reason', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        buildControls(DetectionStatusOutcome.unavailable, Recorder()),
      );
      final node = nodeFor(tester, 'UNAVAILABLE');
      final data = node.getSemanticsData();
      expect(data.flagsCollection.isButton, isTrue);
      expect(data.flagsCollection.isEnabled, Tristate.isFalse);
      expect(data.hasAction(SemanticsAction.tap), isFalse);
      expect(node.hint, 'Detection is unavailable');
      handle.dispose();
    });

    testWidgets('quick scan exposes an enabled button when ready', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        buildControls(DetectionStatusOutcome.ready, Recorder()),
      );
      final node = nodeFor(tester, 'QUICK SCAN');
      final data = node.getSemanticsData();
      expect(data.flagsCollection.isButton, isTrue);
      expect(data.flagsCollection.isEnabled, Tristate.isTrue);
      expect(data.hasAction(SemanticsAction.tap), isTrue);
      handle.dispose();
    });

    testWidgets('quick scan disabled semantics explain the Ready-only gate', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        buildControls(DetectionStatusOutcome.paused, Recorder()),
      );
      final node = nodeFor(tester, 'QUICK SCAN');
      final data = node.getSemanticsData();
      expect(data.flagsCollection.isButton, isTrue);
      expect(data.flagsCollection.isEnabled, Tristate.isFalse);
      expect(data.hasAction(SemanticsAction.tap), isFalse);
      // The disabled state is not conveyed by color alone.
      expect(node.hint, contains('available only while detection is ready'));
      handle.dispose();
    });

    testWidgets('TalkBack semantic tap on ready dispatches Pause', (
      tester,
    ) async {
      // A screen-reader double-tap invokes the semantic onTap directly, with no
      // pointer-down. It must reach the same mapped tap behavior as a physical
      // tap, otherwise the control is unusable through TalkBack.
      final handle = tester.ensureSemantics();
      final recorder = Recorder();
      await tester.pumpWidget(
        buildControls(DetectionStatusOutcome.ready, recorder),
      );
      tester.semantics.performAction(
        find.semantics.byLabel('PAUSE'),
        SemanticsAction.tap,
      );
      await tester.pump();
      expect(recorder.pause, 1);
      expect(recorder.stop, 0);
      handle.dispose();
    });

    testWidgets('TalkBack semantic tap on paused dispatches Resume', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final recorder = Recorder();
      await tester.pumpWidget(
        buildControls(DetectionStatusOutcome.paused, recorder),
      );
      tester.semantics.performAction(
        find.semantics.byLabel('RESUME'),
        SemanticsAction.tap,
      );
      await tester.pump();
      expect(recorder.resume, 1);
      expect(recorder.stop, 0);
      handle.dispose();
    });

    testWidgets('TalkBack semantic tap on stopped is a no-op', (tester) async {
      final handle = tester.ensureSemantics();
      final recorder = Recorder();
      await tester.pumpWidget(
        buildControls(DetectionStatusOutcome.stopped, recorder),
      );
      tester.semantics.performAction(
        find.semantics.byLabel('START'),
        SemanticsAction.tap,
      );
      await tester.pump();
      expect(recorder.start, 0);
      expect(recorder.pause, 0);
      expect(recorder.resume, 0);
      expect(recorder.stop, 0);
      handle.dispose();
    });
  });

  group('visual treatment', () {
    /// The decorated container that paints the given control surface.
    BoxDecoration decorationFor(WidgetTester tester, String label) {
      final container = tester.widget<Container>(
        find
            .ancestor(of: find.text(label), matching: find.byType(Container))
            .first,
      );
      return container.decoration! as BoxDecoration;
    }

    testWidgets('lifecycle control uses surface-card with the soft shadow', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildControls(DetectionStatusOutcome.ready, Recorder()),
      );
      final decoration = decorationFor(tester, 'PAUSE');
      expect(decoration.color, kHomeSurfaceCard);
      expect(decoration.boxShadow, kHomeShadowSoft);
    });

    testWidgets('quick scan control uses accent-cyan with the soft shadow', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildControls(DetectionStatusOutcome.ready, Recorder()),
      );
      final decoration = decorationFor(tester, 'QUICK SCAN');
      expect(decoration.color, kHomeAccentCyan);
      expect(decoration.boxShadow, kHomeShadowSoft);
    });

    testWidgets(
      'disabled lifecycle control keeps the surface at reduced alpha',
      (tester) async {
        await tester.pumpWidget(
          buildControls(DetectionStatusOutcome.preparing, Recorder()),
        );
        final decoration = decorationFor(tester, 'PREPARING');
        expect(decoration.color, kHomeSurfaceCard.withValues(alpha: 0.5));
        expect(decoration.boxShadow, kHomeShadowSoft);
      },
    );
  });

  group('state icons and alignment', () {
    /// The icon rendered inside the lifecycle control for [label].
    IconData lifecycleIcon(WidgetTester tester, String label) {
      final icon = tester.widget<Icon>(
        find.descendant(
          of: find
              .ancestor(of: find.text(label), matching: find.byType(Column))
              .first,
          matching: find.byType(Icon),
        ),
      );
      return icon.icon!;
    }

    testWidgets('lifecycle icon reflects each outcome', (tester) async {
      await tester.pumpWidget(
        buildControls(DetectionStatusOutcome.ready, Recorder()),
      );
      expect(lifecycleIcon(tester, 'PAUSE'), Icons.pause);

      await tester.pumpWidget(
        buildControls(DetectionStatusOutcome.paused, Recorder()),
      );
      expect(lifecycleIcon(tester, 'RESUME'), Icons.play_arrow);

      await tester.pumpWidget(
        buildControls(DetectionStatusOutcome.stopped, Recorder()),
      );
      expect(lifecycleIcon(tester, 'START'), Icons.play_arrow);

      await tester.pumpWidget(
        buildControls(DetectionStatusOutcome.preparing, Recorder()),
      );
      expect(lifecycleIcon(tester, 'PREPARING'), Icons.hourglass_top);

      await tester.pumpWidget(
        buildControls(DetectionStatusOutcome.unavailable, Recorder()),
      );
      expect(lifecycleIcon(tester, 'UNAVAILABLE'), Icons.error_outline);
    });

    testWidgets('quick scan renders its own icon and TAP hint', (tester) async {
      await tester.pumpWidget(
        buildControls(DetectionStatusOutcome.ready, Recorder()),
      );
      expect(find.text('TAP'), findsOneWidget);
      expect(
        find.descendant(
          of: find.ancestor(
            of: find.text('QUICK SCAN'),
            matching: find.byType(Column),
          ),
          matching: find.byIcon(Icons.center_focus_strong),
        ),
        findsOneWidget,
      );
    });

    testWidgets('control text is left aligned, not centered', (tester) async {
      await tester.pumpWidget(
        buildControls(DetectionStatusOutcome.ready, Recorder()),
      );
      final pause = tester.widget<Text>(find.text('PAUSE'));
      expect(pause.textAlign, TextAlign.left);
      final scan = tester.widget<Text>(find.text('QUICK SCAN'));
      expect(scan.textAlign, TextAlign.left);
    });
  });
}
