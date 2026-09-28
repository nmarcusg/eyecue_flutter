import 'package:eyecue_flutter/models/detection.dart';
import 'package:eyecue_flutter/models/detection_info.dart';
import 'package:eyecue_flutter/widgets/detection_information_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

DetectionInfo info(
  String label, {
  ObjectPriority priority = ObjectPriority.low,
  RelativePosition position = RelativePosition.center,
  ProximityBand proximity = ProximityBand.medium,
}) => DetectionInfo(
  detection: Detection(
    classId: 0,
    label: label,
    confidence: 0.9,
    box: const Rect.fromLTWH(0, 0, 1, 1),
  ),
  position: position,
  priority: priority,
  proximity: proximity,
);

Widget wrap(Widget child) => MaterialApp(
  home: Scaffold(body: SizedBox(width: 360, height: 240, child: child)),
);

void main() {
  group('selection', () {
    test('limits to at most two rows', () {
      final rows = DetectionInformationOverlay.selectRows([
        info('A'),
        info('B'),
        info('C'),
      ]);
      expect(rows.length, 2);
    });

    test('stably promotes High entries preserving source order', () {
      final rows = DetectionInformationOverlay.selectRows([
        info('Low A'),
        info('Medium B', priority: ObjectPriority.medium),
        info('High C', priority: ObjectPriority.high),
      ]);
      expect(rows.map((r) => r.label).toList(), ['High C', 'Low A']);
    });

    test('fills remaining slots from original source order', () {
      final rows = DetectionInformationOverlay.selectRows([
        info('High A', priority: ObjectPriority.high),
        info('Low B'),
        info('Medium C', priority: ObjectPriority.medium),
      ]);
      expect(rows.map((r) => r.label).toList(), ['High A', 'Low B']);
    });

    test('does not invent a Medium-over-Low ranking', () {
      final rows = DetectionInformationOverlay.selectRows([
        info('Low A'),
        info('Medium B', priority: ObjectPriority.medium),
      ]);
      expect(rows.map((r) => r.label).toList(), ['Low A', 'Medium B']);
    });

    test('returns empty for empty input', () {
      expect(DetectionInformationOverlay.selectRows(const []), isEmpty);
    });
  });

  group('rendering', () {
    testWidgets('hidden when not eligible', (tester) async {
      await tester.pumpWidget(
        wrap(
          DetectionInformationOverlay(
            infos: [info('Person', priority: ObjectPriority.high)],
            eligible: false,
          ),
        ),
      );
      expect(find.textContaining('Person'), findsNothing);
    });

    testWidgets('hidden when empty', (tester) async {
      await tester.pumpWidget(
        wrap(const DetectionInformationOverlay(infos: [], eligible: true)),
      );
      expect(find.byType(Container), findsNothing);
    });

    testWidgets('renders at most two rows', (tester) async {
      await tester.pumpWidget(
        wrap(
          DetectionInformationOverlay(
            infos: [info('A'), info('B'), info('C')],
            eligible: true,
          ),
        ),
      );
      expect(find.textContaining('A,'), findsOneWidget);
      expect(find.textContaining('B,'), findsOneWidget);
      expect(find.textContaining('C,'), findsNothing);
    });

    testWidgets('renders the High C, Low A regression case', (tester) async {
      await tester.pumpWidget(
        wrap(
          DetectionInformationOverlay(
            infos: [
              info('Low A'),
              info('Medium B', priority: ObjectPriority.medium),
              info('High C', priority: ObjectPriority.high),
            ],
            eligible: true,
          ),
        ),
      );
      expect(find.textContaining('High C'), findsOneWidget);
      expect(find.textContaining('Low A'), findsOneWidget);
      expect(find.textContaining('Medium B'), findsNothing);
    });

    testWidgets('does not render confidence or metric values', (tester) async {
      await tester.pumpWidget(
        wrap(
          DetectionInformationOverlay(
            infos: [info('Person', priority: ObjectPriority.high)],
            eligible: true,
          ),
        ),
      );
      expect(find.textContaining('percent'), findsNothing);
      expect(find.textContaining('0.9'), findsNothing);
      expect(find.textContaining('priority'), findsNothing);
    });

    testWidgets('is pointer-inert', (tester) async {
      await tester.pumpWidget(
        wrap(
          DetectionInformationOverlay(infos: [info('Person')], eligible: true),
        ),
      );
      expect(
        find.descendant(
          of: find.byType(DetectionInformationOverlay),
          matching: find.byType(IgnorePointer),
        ),
        findsOneWidget,
      );
    });
  });

  group('semantics', () {
    testWidgets('one informational node per row, not a live region', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        wrap(
          DetectionInformationOverlay(
            infos: [
              info(
                'Person',
                priority: ObjectPriority.high,
                position: RelativePosition.left,
                proximity: ProximityBand.near,
              ),
              info('Chair', position: RelativePosition.right),
            ],
            eligible: true,
          ),
        ),
      );
      final node = tester.getSemantics(
        find.textContaining('Person, left, near'),
      );
      expect(node.label, 'Person, left, near');
      expect(node.flagsCollection.isLiveRegion, isFalse);
      expect(node.flagsCollection.isButton, isFalse);
      handle.dispose();
    });
  });
}
