import 'package:eyecue_flutter/models/detection.dart';
import 'package:eyecue_flutter/models/detection_correction.dart';
import 'package:eyecue_flutter/services/spatial_analysis_service.dart';
import 'package:eyecue_flutter/widgets/detection_correction_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final info = SpatialAnalysisService.analyze(
    const Detection(
      classId: 0,
      label: 'person',
      confidence: 0.82,
      box: Rect.fromLTWH(0.1, 0.1, 0.2, 0.3),
    ),
  );

  Future<_SheetHandle> openSheet(WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: SizedBox.shrink())),
    );
    final result = showDetectionCorrectionSheet(
      context: tester.element(find.byType(Scaffold)),
      info: info,
      labels: const ['person', 'bicycle', 'traffic light'],
    );
    await tester.pumpAndSettle();
    return _SheetHandle(result);
  }

  testWidgets('returns correct, incorrect, and unsure outcomes', (
    tester,
  ) async {
    var handle = await openSheet(tester);
    await tester.tap(find.text('Correct'));
    await tester.pumpAndSettle();
    expect((await handle.result)?.feedback, CorrectionFeedback.correct);

    handle = await openSheet(tester);
    await tester.tap(find.text('Incorrect'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Back'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Unsure'));
    await tester.pumpAndSettle();
    expect((await handle.result)?.feedback, CorrectionFeedback.unsure);
  });

  testWidgets('searches and returns an optional corrected label', (
    tester,
  ) async {
    final handle = await openSheet(tester);
    await tester.tap(find.text('Incorrect'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'bicy');
    await tester.pumpAndSettle();
    expect(find.text('bicycle'), findsOneWidget);
    await tester.tap(find.text('bicycle'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save incorrect report as bicycle'));
    await tester.pumpAndSettle();

    final selection = await handle.result;
    expect(selection?.feedback, CorrectionFeedback.incorrect);
    expect(selection?.correctedLabel, 'bicycle');
  });

  testWidgets('cancelling the sheet returns no correction', (tester) async {
    final handle = await openSheet(tester);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(await handle.result, isNull);
  });
}

class _SheetHandle {
  final Future<DetectionCorrectionSelection?> result;

  const _SheetHandle(this.result);
}
