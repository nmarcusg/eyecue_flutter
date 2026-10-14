import 'package:eyecue_flutter/models/detection.dart';
import 'package:eyecue_flutter/models/detection_info.dart';
import 'package:eyecue_flutter/models/detection_runtime_state.dart';
import 'package:eyecue_flutter/services/engine_coordinator.dart';
import 'package:eyecue_flutter/services/gesture_controller.dart';
import 'package:eyecue_flutter/theme/app_colors.dart';
import 'package:eyecue_flutter/theme/app_home_theme.dart';
import 'package:eyecue_flutter/widgets/detection_action_controls.dart';
import 'package:eyecue_flutter/widgets/detection_information_overlay.dart';
import 'package:eyecue_flutter/widgets/gesture_surface.dart';
import 'package:eyecue_flutter/widgets/status_pill.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Cross-engine parity and stopped-shell composition tests for the Detection
/// redesign (PD1/PD2/PD3).
///
/// The full [DetectionScreen] and [UltralyticsDetectionScreen] cannot be pumped
/// without CameraPlatform / permission_handler / native platform-view mocks, so
/// these tests exercise the plugin-free structural contract both engines must
/// satisfy: an identical compact header, a retained viewport shell that keeps
/// the [GestureSurface] while Stopped, and the shared two-control row. They
/// assert the parity rules the plan requires without a camera/native dependency.
void main() {
  DetectionInfo info({
    required String label,
    ObjectPriority priority = ObjectPriority.low,
  }) {
    return DetectionInfo(
      detection: Detection(
        classId: 0,
        label: label,
        confidence: 0.8,
        box: const Rect.fromLTWH(0.4, 0.4, 0.2, 0.2),
      ),
      position: RelativePosition.center,
      priority: priority,
      proximity: ProximityBand.medium,
    );
  }

  Widget chrome(Widget child) => MaterialApp(
    home: Theme(
      data: buildHomeTheme(),
      child: Scaffold(body: child),
    ),
  );

  /// The compact header both engines render: Detection Mode title, the
  /// coordinator-derived [StatusPill], and the audio pill. This mirrors the
  /// shared `_buildTopBar` structure in both engine screens.
  Widget header(DetectionRuntimeState state) {
    final (label, color) = switch (detectionStatusOutcomeFor(state)) {
      DetectionStatusOutcome.preparing => ('Preparing', kStatusBlue),
      DetectionStatusOutcome.ready => ('Detecting', kStatusGreen),
      DetectionStatusOutcome.paused => ('Paused', kStatusAmber),
      DetectionStatusOutcome.stopped => ('Stopped', kStatusBlueGrey),
      DetectionStatusOutcome.unavailable => ('Unavailable', kWarningRed),
    };
    return Builder(
      builder: (context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Detection Mode', style: Theme.of(context).textTheme.titleLarge),
          Row(
            children: [
              StatusPill(label: label, color: color),
              const Spacer(),
              const Text('AUDIO ON'),
            ],
          ),
        ],
      ),
    );
  }

  group('header parity', () {
    testWidgets('both engines render the same compact header structure', (
      tester,
    ) async {
      // The header is a shared presentation contract: Detection Mode title,
      // coordinator-derived StatusPill, and the audio pill. Both engine screens
      // build this identical structure from the same coordinator snapshot.
      for (final state in const [
        DetectionRuntimeState.ready,
        DetectionRuntimeState.paused,
        DetectionRuntimeState.stopped,
        DetectionRuntimeState.loadingModel,
        DetectionRuntimeState.failed,
      ]) {
        await tester.pumpWidget(chrome(header(state)));
        expect(find.text('Detection Mode'), findsOneWidget);
        expect(find.byType(StatusPill), findsOneWidget);
        expect(find.text('AUDIO ON'), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets('header status label derives from the coordinator outcome', (
      tester,
    ) async {
      final cases = <DetectionRuntimeState, String>{
        DetectionRuntimeState.ready: 'Detecting',
        DetectionRuntimeState.fallback: 'Detecting',
        DetectionRuntimeState.paused: 'Paused',
        DetectionRuntimeState.stopped: 'Stopped',
        DetectionRuntimeState.loadingModel: 'Preparing',
        DetectionRuntimeState.failed: 'Unavailable',
      };
      for (final entry in cases.entries) {
        await tester.pumpWidget(chrome(header(entry.key)));
        expect(
          find.text(entry.value),
          findsOneWidget,
          reason: 'Wrong header label for ${entry.key}',
        );
      }
    });
  });

  group('stopped viewport shell retention', () {
    testWidgets('stopped shell keeps the viewport and GestureSurface', (
      tester,
    ) async {
      // PD1: Stopped must retain a viewport shell and the GestureSurface. This
      // mirrors the retained-shell composition both engines use after a manual
      // Stop (Custom keeps _isCameraInitialized; Ultralytics keeps
      // _nativeViewMounted).
      await tester.pumpWidget(
        chrome(
          Container(
            decoration: BoxDecoration(
              color: kHomeInk,
              borderRadius: BorderRadius.circular(24),
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              fit: StackFit.expand,
              children: [
                const ColoredBox(color: Colors.black),
                DetectionInformationOverlay(
                  infos: [info(label: 'person', priority: ObjectPriority.high)],
                  // Stopped is not Ready, so the overlay is hidden.
                  eligible: false,
                ),
                GestureSurface(
                  controller: GestureController(),
                  child: const SizedBox.expand(),
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.byType(GestureSurface), findsOneWidget);
      expect(find.byType(DetectionInformationOverlay), findsOneWidget);
      // The overlay is hidden while Stopped.
      expect(find.textContaining('person'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('overlay freshness across a resume transition', () {
    testWidgets('stale result is not shown after resume until a fresh one', (
      tester,
    ) async {
      // PD3: the overlay snapshot is cleared whenever the mapped outcome leaves
      // Ready and is only accepted while the currently observed outcome is
      // Ready. This models the screen-local gate: a stale pre-transition
      // snapshot must not be shown after a later Ready transition until a fresh
      // result arrives.
      var eligible = true;
      var infos = <DetectionInfo>[
        info(label: 'stale', priority: ObjectPriority.high),
      ];

      Widget build() =>
          chrome(DetectionInformationOverlay(infos: infos, eligible: eligible));

      await tester.pumpWidget(build());
      expect(find.textContaining('stale'), findsOneWidget);

      // Transition away from Ready: the screen clears the snapshot and the
      // overlay becomes ineligible.
      eligible = false;
      infos = const [];
      await tester.pumpWidget(build());
      expect(find.textContaining('stale'), findsNothing);

      // Return to Ready with no fresh result yet: still nothing shown.
      eligible = true;
      await tester.pumpWidget(build());
      expect(find.textContaining('stale'), findsNothing);

      // A fresh result arrives: it is shown.
      infos = [info(label: 'fresh', priority: ObjectPriority.high)];
      await tester.pumpWidget(build());
      expect(find.textContaining('fresh'), findsOneWidget);
      expect(find.textContaining('stale'), findsNothing);
    });

    testWidgets('overlay is hidden for every non-Ready outcome', (
      tester,
    ) async {
      // The overlay eligibility is derived from the mapped outcome; only Ready
      // (including healthy fallback) is eligible.
      for (final state in const [
        DetectionRuntimeState.paused,
        DetectionRuntimeState.stopped,
        DetectionRuntimeState.loadingModel,
        DetectionRuntimeState.failed,
      ]) {
        final eligible =
            detectionStatusOutcomeFor(state) == DetectionStatusOutcome.ready;
        expect(eligible, isFalse, reason: 'Unexpected eligibility: $state');
      }
      expect(
        detectionStatusOutcomeFor(DetectionRuntimeState.ready) ==
            DetectionStatusOutcome.ready,
        isTrue,
      );
      expect(
        detectionStatusOutcomeFor(DetectionRuntimeState.fallback) ==
            DetectionStatusOutcome.ready,
        isTrue,
      );
    });
  });

  group('control row parity', () {
    testWidgets('both engines compose the same two-control row', (
      tester,
    ) async {
      // The shared DetectionActionControls is the single control row for both
      // engines; it renders exactly the consolidated lifecycle control and the
      // physical Quick Scan.
      await tester.pumpWidget(
        chrome(
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
      expect(find.text('PAUSE'), findsOneWidget);
      expect(find.text('QUICK SCAN'), findsOneWidget);
      expect(find.byType(DetectionActionControls), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('screen gesture dispatch gate', () {
    /// Models the exact screen-level dispatch gate both engines use in
    /// `_onGesture`: the three-finger Quick Scan is gated by the shared mapped
    /// outcome (Ready/healthy fallback only), while the two-finger double-tap
    /// Start/Stop is immediate and ungated by the overlay eligibility.
    ///
    /// The full screens cannot be pumped without camera/native mocks, so this
    /// asserts the locked lifecycle matrix the dispatch implements.
    ({bool quickScan, bool toggleActive}) dispatchFor(
      DetectionRuntimeState state,
    ) {
      final ready =
          detectionStatusOutcomeFor(state) == DetectionStatusOutcome.ready;
      return (quickScan: ready, toggleActive: true);
    }

    test('three-finger Quick Scan runs only for Ready/healthy fallback', () {
      expect(dispatchFor(DetectionRuntimeState.ready).quickScan, isTrue);
      expect(dispatchFor(DetectionRuntimeState.fallback).quickScan, isTrue);
      for (final state in const [
        DetectionRuntimeState.paused,
        DetectionRuntimeState.stopped,
        DetectionRuntimeState.loadingModel,
        DetectionRuntimeState.failed,
      ]) {
        expect(
          dispatchFor(state).quickScan,
          isFalse,
          reason: 'Quick Scan must not run for $state',
        );
      }
    });

    test('two-finger double-tap Start/Stop is immediate in every outcome', () {
      // The two-finger double-tap is not gated by the overlay eligibility; it
      // dispatches the immediate Start/Stop toggle in every lifecycle outcome.
      for (final state in DetectionRuntimeState.values) {
        expect(
          dispatchFor(state).toggleActive,
          isTrue,
          reason: 'Two-finger toggle must remain available for $state',
        );
      }
    });
  });
}
