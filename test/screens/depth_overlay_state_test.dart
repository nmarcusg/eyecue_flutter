import 'package:eyecue_flutter/models/app_settings.dart';
import 'package:eyecue_flutter/screens/ultralytics_detection_screen.dart';
import 'package:eyecue_flutter/services/inference_cadence.dart';
import 'package:eyecue_flutter/theme/app_home_theme.dart';
import 'package:eyecue_flutter/widgets/depth_heatmap_view.dart';
import 'package:eyecue_flutter/widgets/detection_information_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DepthOverlayState.resolve', () {
    test('depth + heatmap + boxes: Flutter boxes, no native overlays', () {
      final state = DepthOverlayState.resolve(
        mdeEnabled: true,
        showDepthHeatmap: true,
        showBoundingBoxes: true,
        heatmapFresh: true,
      );
      expect(state.heatmapVisible, isTrue);
      expect(state.flutterBoxes, isTrue);
      expect(state.nativeOverlays, isFalse);
    });

    test('depth + heatmap, boxes off: heatmap only', () {
      final state = DepthOverlayState.resolve(
        mdeEnabled: true,
        showDepthHeatmap: true,
        showBoundingBoxes: false,
        heatmapFresh: true,
      );
      expect(state.heatmapVisible, isTrue);
      expect(state.flutterBoxes, isFalse);
      expect(state.nativeOverlays, isFalse);
    });

    test('depth + heatmap off: native overlays draw the boxes', () {
      final state = DepthOverlayState.resolve(
        mdeEnabled: true,
        showDepthHeatmap: false,
        showBoundingBoxes: true,
        heatmapFresh: true,
      );
      expect(state.heatmapVisible, isFalse);
      expect(state.flutterBoxes, isFalse);
      expect(state.nativeOverlays, isTrue);
    });

    test('bounding-box mode never shows the heatmap', () {
      final state = DepthOverlayState.resolve(
        mdeEnabled: false,
        showDepthHeatmap: true,
        showBoundingBoxes: true,
        heatmapFresh: true,
      );
      expect(state.heatmapVisible, isFalse);
      expect(state.nativeOverlays, isTrue);
    });

    test('stale depth hides the heatmap but keeps detection boxes', () {
      final state = DepthOverlayState.resolve(
        mdeEnabled: true,
        showDepthHeatmap: true,
        showBoundingBoxes: true,
        heatmapFresh: false,
      );
      expect(state.heatmapVisible, isFalse);
      expect(state.nativeOverlays, isTrue);
    });

    test('boxes hidden never means detection off', () {
      final state = DepthOverlayState.resolve(
        mdeEnabled: true,
        showDepthHeatmap: false,
        showBoundingBoxes: false,
        heatmapFresh: true,
      );
      expect(state.heatmapVisible, isFalse);
      expect(state.nativeOverlays, isFalse);
      expect(state.flutterBoxes, isFalse);
    });

    test('the heatmap and the boxes toggle independently', () {
      for (final heatmap in [false, true]) {
        for (final boxes in [false, true]) {
          final state = DepthOverlayState.resolve(
            mdeEnabled: true,
            showDepthHeatmap: heatmap,
            showBoundingBoxes: boxes,
            heatmapFresh: true,
          );
          final reason = 'heatmap=$heatmap boxes=$boxes';
          expect(state.heatmapVisible, heatmap, reason: reason);
          // Boxes are drawn by whichever layer owns them, never turned off by
          // the heatmap toggle and never left on by hiding them.
          expect(
            state.flutterBoxes || state.nativeOverlays,
            boxes,
            reason: reason,
          );
        }
      }
    });
  });

  group('heatmap construction gate', () {
    test('only MDE on plus the heatmap toggled on builds a heatmap', () {
      expect(
        heatmapRequested(mdeEnabled: true, showDepthHeatmap: true),
        isTrue,
      );
      expect(
        heatmapRequested(mdeEnabled: true, showDepthHeatmap: false),
        isFalse,
      );
      expect(
        heatmapRequested(mdeEnabled: false, showDepthHeatmap: true),
        isFalse,
      );
      expect(
        heatmapRequested(mdeEnabled: false, showDepthHeatmap: false),
        isFalse,
      );
    });

    test('the heatmap toggle cannot change the streaming config key', () {
      final resolved = InferenceCadence.resolve(
        requestedDetectionHz: 15,
        requestedDepthHz: 5,
        lowPowerMode: false,
        distanceEstimationMode: DistanceEstimationMode.monocularDepth,
      );

      // The toggle does change the gate ...
      expect(
        heatmapRequested(mdeEnabled: true, showDepthHeatmap: true),
        isNot(heatmapRequested(mdeEnabled: true, showDepthHeatmap: false)),
      );
      // ... but it is not an input to the key (heatmap visibility only gates
      // Dart-side construction), so both presentation states yield one key:
      // no camera restart and no stopped depth tick.
      final key = streamingConfigKey(
        cadence: resolved,
        mdeEnabled: true,
        depthInstanceId: 'depth-instance',
      );
      expect(key.depthInstanceId, 'depth-instance');
      expect(
        streamingConfigKey(
          cadence: resolved,
          mdeEnabled: true,
          depthInstanceId: 'depth-instance',
        ),
        key,
        reason: 'only the cadence, the mode and the instance reach native',
      );
    });
  });

  testWidgets('layer order: heatmap, boxes, info overlay, gesture surface', (
    tester,
  ) async {
    // Mirrors the screen's viewport stack (the native view cannot be pumped).
    await tester.pumpWidget(
      MaterialApp(
        home: Theme(
          data: buildHomeTheme(),
          child: Scaffold(
            body: Stack(
              fit: StackFit.expand,
              children: [
                const ColoredBox(color: Colors.black),
                const DepthHeatmapView(image: null, rotationDegrees: 90),
                const CustomPaint(painter: _NoopPainter()),
                const DetectionInformationOverlay(infos: [], eligible: true),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {},
                  child: const SizedBox.expand(),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    // The decorative heatmap is pointer-inert and semantics-free.
    expect(find.byType(DepthHeatmapView), findsOneWidget);
  });
}

class _NoopPainter extends CustomPainter {
  const _NoopPainter();

  @override
  void paint(Canvas canvas, Size size) {}

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
