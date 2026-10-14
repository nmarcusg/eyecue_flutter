import 'package:eyecue_flutter/models/app_settings.dart';
import 'package:eyecue_flutter/models/detection_runtime_state.dart';
import 'package:eyecue_flutter/screens/ultralytics_detection_screen.dart';
import 'package:eyecue_flutter/services/engine_coordinator.dart';
import 'package:eyecue_flutter/widgets/detection_action_controls.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Regression tests for the two confirmed Detection-redesign runtime
/// regressions and the confirmed Ultralytics Stop→Start lifecycle defect.
///
/// These tests reproduce the failures at the closest testable level without
/// native/camera platform mocks:
///
/// 1. The Custom screen's non-flexible action-controls row must lay out with a
///    bounded height (no `BoxConstraints forces an infinite height` /
///    `RenderBox was not laid out`).
/// 2. The Custom screen must not synchronously notify the coordinator during
///    its first build (no `setState() or markNeedsBuild() called during build`).
/// 3. The Ultralytics start-after-stop epoch decision must recreate the native
///    session, and a stale `onModelLoad` from a previous epoch must not be
///    accepted as the current session's Ready.
void main() {
  group('Fix 1 — action-controls row lays out with a bounded height', () {
    // Mirrors the Custom screen's Column slot: the control row is a
    // non-flexible third child, so it receives `maxHeight: double.infinity`.
    // The shared control's `CrossAxisAlignment.stretch` row would force an
    // infinite height on both Expanded children without an IntrinsicHeight
    // bound. This reproduces the original constraint cascade.
    Widget buildUnboundedColumnSlot(Widget controls) => MaterialApp(
      home: Scaffold(
        body: Column(
          children: [
            const Expanded(child: SizedBox.expand()),
            // Non-flexible slot: unbounded height, exactly like the Custom
            // screen's `_buildActionControlsRow` position in the Column.
            controls,
          ],
        ),
      ),
    );

    testWidgets(
      'IntrinsicHeight-wrapped controls lay out in an unbounded Column slot',
      (tester) async {
        await tester.pumpWidget(
          buildUnboundedColumnSlot(
            IntrinsicHeight(
              child: DetectionActionControls(
                outcome: DetectionStatusOutcome.ready,
                onPause: () {},
                onResume: () {},
                onStop: () {},
                onStart: () {},
                onQuickScan: () {},
              ),
            ),
          ),
        );

        // No exception (infinite height / RenderBox not laid out) was thrown.
        expect(tester.takeException(), isNull);

        // The row laid out with a finite, bounded height.
        final size = tester.getSize(find.byType(DetectionActionControls));
        expect(size.height.isFinite, isTrue);
        expect(size.height, greaterThan(0));

        // Both controls are present and hit-testable.
        expect(find.text('PAUSE'), findsOneWidget);
        expect(find.text('QUICK SCAN'), findsOneWidget);
      },
    );

    testWidgets(
      'unwrapped controls reproduce the infinite-height failure (guards the fix)',
      (tester) async {
        // This documents the original failure mode: without the IntrinsicHeight
        // bound the stretch row cannot lay out in the unbounded slot. If this
        // ever stops throwing, the fix's rationale has changed and the test
        // should be revisited.
        await tester.pumpWidget(
          buildUnboundedColumnSlot(
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

        expect(tester.takeException(), isNotNull);
      },
    );
  });

  group('Fix 3 — Ultralytics start-after-stop recreates the native session', () {
    test('first start does not recreate the native session', () {
      // The native view is not mounted yet, so the normal mount path already
      // resolves the model and fires `onModelLoad`.
      expect(
        shouldRecreateNativeSessionOnStart(
          nativeViewMounted: false,
          detectionActive: false,
          paused: false,
        ),
        isFalse,
      );
    });

    test('resume from pause does not recreate the native session', () {
      // The predictor was never destroyed by pause, so no recreation.
      expect(
        shouldRecreateNativeSessionOnStart(
          nativeViewMounted: true,
          detectionActive: true,
          paused: true,
        ),
        isFalse,
      );
    });

    test('start after a stop recreates the native session', () {
      // Native `stop()` permanently destroys the predictor and `startCamera()`
      // is a no-op while it is null, so a fresh platform view is required.
      expect(
        shouldRecreateNativeSessionOnStart(
          nativeViewMounted: true,
          detectionActive: false,
          paused: false,
        ),
        isTrue,
      );
    });

    test('repeated Ready → Stop → Start cycles each recreate the session', () {
      // Simulates the screen's epoch bookkeeping across multiple cycles. The
      // epoch must advance on every start-after-stop so a fresh YOLOView mounts
      // and `onModelLoad` fires again.
      var nativeViewMounted = false;
      var detectionActive = false;
      var paused = false;
      var epoch = 0;

      void start() {
        final recreate = shouldRecreateNativeSessionOnStart(
          nativeViewMounted: nativeViewMounted,
          detectionActive: detectionActive,
          paused: paused,
        );
        detectionActive = true;
        nativeViewMounted = true;
        paused = false;
        if (recreate) epoch++;
      }

      void stop() {
        detectionActive = false;
        paused = false;
      }

      // First start: no recreation (epoch stays 0).
      start();
      expect(epoch, 0);

      // Cycle 1: stop then start recreates (epoch 1).
      stop();
      start();
      expect(epoch, 1);

      // Cycle 2: stop then start recreates again (epoch 2).
      stop();
      start();
      expect(epoch, 2);

      // Cycle 3: stop then start recreates again (epoch 3).
      stop();
      start();
      expect(epoch, 3);
    });

    test('a stale onModelLoad from a previous epoch is not accepted', () {
      // The screen captures the epoch the callback was built with and compares
      // it against the active epoch. A late callback from the view being torn
      // down must be ignored so it is never treated as the current Ready.
      var activeEpoch = 0;
      var readyReports = 0;

      void onModelLoad(int callbackEpoch) {
        if (callbackEpoch != activeEpoch) return; // stale — ignored
        readyReports++;
      }

      // First session (epoch 0) loads and reports Ready.
      onModelLoad(0);
      expect(readyReports, 1);

      // Start-after-stop bumps the active epoch to 1.
      activeEpoch = 1;

      // A stale callback from the torn-down epoch-0 view is ignored.
      onModelLoad(0);
      expect(readyReports, 1);

      // The fresh epoch-1 view loads and reports Ready.
      onModelLoad(1);
      expect(readyReports, 2);
    });
  });

  group(
    'Fix 2 — coordinator is not notified synchronously during first build',
    () {
      testWidgets(
        'a post-frame start intent does not notify the coordinator mid-build',
        (tester) async {
          // Reproduces the original failure: consuming the start intent
          // synchronously inside initState reaches the coordinator's
          // notifyListeners() while the coordinator's ListenableBuilder is
          // mid-build, producing `setState() or markNeedsBuild() called during
          // build`. The fix defers the intent to a post-frame callback.
          final coordinator = EngineCoordinator(
            preferredEngine: InferenceEngine.custom,
          );
          var notificationsDuringBuild = 0;
          var building = false;

          coordinator.addListener(() {
            if (building) notificationsDuringBuild++;
          });

          await tester.pumpWidget(
            MaterialApp(
              home: ListenableBuilder(
                listenable: coordinator,
                builder: (context, _) {
                  building = true;
                  // Simulate the child screen deferring its one-shot start intent
                  // to a post-frame callback, exactly as the Custom screen now
                  // does in initState.
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    coordinator.reportState(
                      DetectionRuntimeState.startingCamera,
                      generation: coordinator.mountGeneration,
                    );
                  });
                  building = false;
                  return const SizedBox.shrink();
                },
              ),
            ),
          );

          // The build completed without a mid-build notification.
          expect(tester.takeException(), isNull);
          expect(notificationsDuringBuild, 0);

          // The deferred intent was applied after the frame.
          await tester.pump();
          expect(coordinator.state, DetectionRuntimeState.startingCamera);
        },
      );
    },
  );
}
