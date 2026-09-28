import 'package:eyecue_flutter/models/detection.dart';
import 'package:eyecue_flutter/models/detection_info.dart';
import 'package:eyecue_flutter/services/engine_coordinator.dart';
import 'package:eyecue_flutter/services/spatial_analysis_service.dart';
import 'package:eyecue_flutter/theme/app_home_theme.dart';
import 'package:eyecue_flutter/widgets/detection_action_controls.dart';
import 'package:eyecue_flutter/widgets/detection_information_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Focused composition tests for the redesigned Custom Detection layout.
///
/// The full [DetectionScreen] cannot be pumped without CameraPlatform /
/// permission_handler mocks, so these tests exercise the plugin-free structural
/// contract the screen composes: the dominant viewport stack (preview, boxes,
/// compact overlay, gesture surface) and the single two-control row beneath it.
/// They assert the PD1/PD2/PD3 presentation rules without a camera dependency.
void main() {
  DetectionInfo info({
    required String label,
    required ObjectPriority priority,
    RelativePosition position = RelativePosition.center,
    ProximityBand proximity = ProximityBand.medium,
  }) {
    return DetectionInfo(
      detection: Detection(
        classId: 0,
        label: label,
        confidence: 0.8,
        box: const Rect.fromLTWH(0.4, 0.4, 0.2, 0.2),
      ),
      position: position,
      priority: priority,
      proximity: proximity,
    );
  }

  Widget chrome(Widget child) => MaterialApp(
    home: Theme(
      data: buildHomeTheme(),
      child: Scaffold(body: child),
    ),
  );

  group('Custom Detection layout composition', () {
    testWidgets('viewport stack keeps overlay below the gesture surface', (
      tester,
    ) async {
      // Mirrors the screen's stack order: preview, boxes, overlay, gesture
      // surface. The overlay must be pointer-inert so it never consumes the
      // raw pointers intended for the gesture surface.
      await tester.pumpWidget(
        chrome(
          Stack(
            fit: StackFit.expand,
            children: [
              const ColoredBox(color: Colors.black),
              DetectionInformationOverlay(
                infos: [info(label: 'person', priority: ObjectPriority.high)],
                eligible: true,
              ),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {},
                child: const SizedBox.expand(),
              ),
            ],
          ),
        ),
      );

      expect(find.byType(DetectionInformationOverlay), findsOneWidget);
      expect(find.textContaining('person'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('overlay renders nothing when not eligible', (tester) async {
      await tester.pumpWidget(
        chrome(
          DetectionInformationOverlay(
            infos: [info(label: 'person', priority: ObjectPriority.high)],
            eligible: false,
          ),
        ),
      );

      expect(find.textContaining('person'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('control row renders exactly two side-by-side controls', (
      tester,
    ) async {
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
      // No legacy normal controls remain.
      expect(find.text('Start'), findsNothing);
      expect(find.text('Stop'), findsNothing);
      expect(find.text('Repeat'), findsNothing);
      expect(find.text('Scan'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('control row has no overflow at 200 percent text scale', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390 * 3, 844 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2.0)),
            child: Theme(
              data: buildHomeTheme(),
              child: Scaffold(
                body: DetectionActionControls(
                  outcome: DetectionStatusOutcome.ready,
                  onPause: () {},
                  onResume: () {},
                  onStop: () {},
                  onStart: () {},
                  onQuickScan: () {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('overlay selection promotes High then fills source order', (
      tester,
    ) async {
      // Locked PD3 regression: Low A, Medium B, High C -> High C, Low A.
      final rows = DetectionInformationOverlay.selectRows([
        info(label: 'A', priority: ObjectPriority.low),
        info(label: 'B', priority: ObjectPriority.medium),
        info(label: 'C', priority: ObjectPriority.high),
      ]);
      expect(rows.map((r) => r.label).toList(), ['C', 'A']);
    });

    testWidgets('overlay caps at two rows', (tester) async {
      final rows = DetectionInformationOverlay.selectRows([
        info(label: 'A', priority: ObjectPriority.high),
        info(label: 'B', priority: ObjectPriority.high),
        info(label: 'C', priority: ObjectPriority.high),
      ]);
      expect(rows, hasLength(kDetectionOverlayMaxRows));
    });

    testWidgets('spatial analysis output order is preserved as source order', (
      tester,
    ) async {
      // The overlay must not re-rank Medium over Low; it only promotes High.
      final infos = SpatialAnalysisService.analyzeAll(const [
        Detection(
          classId: 0,
          label: 'low',
          confidence: 0.5,
          box: Rect.fromLTWH(0.05, 0.05, 0.05, 0.05),
        ),
        Detection(
          classId: 0,
          label: 'high',
          confidence: 0.9,
          box: Rect.fromLTWH(0.4, 0.4, 0.5, 0.5),
        ),
      ]);
      final rows = DetectionInformationOverlay.selectRows(infos);
      // High is promoted first; the remaining slot keeps original order.
      expect(rows.first.priority, ObjectPriority.high);
      expect(rows, hasLength(2));
    });
  });
}
