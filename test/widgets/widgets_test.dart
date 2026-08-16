import 'package:eyecue_flutter/models/detection.dart';
import 'package:eyecue_flutter/models/detection_info.dart';
import 'package:eyecue_flutter/services/spatial_analysis_service.dart';
import 'package:eyecue_flutter/widgets/accessible_button.dart';
import 'package:eyecue_flutter/widgets/detection_card.dart';
import 'package:eyecue_flutter/widgets/priority_badge.dart';
import 'package:eyecue_flutter/widgets/warning_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  DetectionInfo sampleInfo() {
    final d = Detection(
      classId: 0,
      label: 'person',
      confidence: 0.82,
      box: const Rect.fromLTWH(0.7, 0.1, 0.2, 0.6),
    );
    return SpatialAnalysisService.analyze(d);
  }

  group('PriorityBadge', () {
    testWidgets('renders the priority label', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: PriorityBadge(priority: ObjectPriority.high)),
        ),
      );
      expect(find.text('HIGH'), findsOneWidget);
    });
  });

  group('DetectionCard', () {
    testWidgets('shows class, confidence, position, and approximate proximity',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: DetectionCard(info: sampleInfo())),
        ),
      );
      expect(find.text('person'), findsOneWidget);
      expect(find.text('82% · right · approximately near'), findsOneWidget);
      expect(find.text('HIGH'), findsOneWidget);
    });
  });

  group('WarningBanner', () {
    testWidgets('renders the message', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: WarningBanner(message: 'Adjust your path')),
        ),
      );
      expect(find.text('Adjust your path'), findsOneWidget);
    });
  });

  group('AccessibleButton', () {
    testWidgets('invokes onPressed when enabled', (tester) async {
      var pressed = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AccessibleButton(
              label: 'Start',
              icon: Icons.play_circle,
              onPressed: () => pressed = true,
            ),
          ),
        ),
      );
      await tester.tap(find.text('Start'));
      expect(pressed, isTrue);
    });

    testWidgets('is disabled when onPressed is null', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AccessibleButton(label: 'Pause', icon: Icons.pause),
          ),
        ),
      );
      final button = tester.widget<ElevatedButton>(
        find.byType(ElevatedButton),
      );
      expect(button.onPressed, isNull);
    });
  });
}
