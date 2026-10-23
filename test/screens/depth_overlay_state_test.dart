import 'package:eyecue_flutter/screens/ultralytics_detection_screen.dart';
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
