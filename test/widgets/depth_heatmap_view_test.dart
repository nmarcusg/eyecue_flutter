import 'dart:ui' as ui;

import 'package:eyecue_flutter/widgets/depth_heatmap_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pumpView(WidgetTester tester, Widget child) => tester.pumpWidget(
    MaterialApp(home: Scaffold(body: Center(child: child))),
  );

  testWidgets('renders nothing without a depth image', (tester) async {
    await pumpView(
      tester,
      const DepthHeatmapView(image: null, rotationDegrees: 0),
    );
    expect(find.byType(RawImage), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('rotates and centre-crops the depth image', (tester) async {
    final ui.Image image = (await tester.runAsync(
      () => createTestImage(width: 40, height: 20),
    ))!;
    await pumpView(
      tester,
      DepthHeatmapView(image: image, rotationDegrees: 90),
    );

    expect(find.byType(RawImage), findsOneWidget);
    expect(find.byType(IgnorePointer), findsWidgets);
    expect(find.byType(ClipRect), findsWidgets);
    final fitted = tester.widget<FittedBox>(find.byType(FittedBox).first);
    expect(fitted.fit, BoxFit.cover);
    expect(tester.takeException(), isNull);

    // A quarter turn transposes the upright box the image is fitted into.
    final sized = tester.widget<SizedBox>(
      find
          .descendant(
            of: find.byType(FittedBox),
            matching: find.byType(SizedBox),
          )
          .first,
    );
    expect(sized.width, 20);
    expect(sized.height, 40);
  });

  testWidgets('is excluded from semantics', (tester) async {
    final handle = tester.ensureSemantics();
    final ui.Image image = (await tester.runAsync(
      () => createTestImage(width: 20, height: 20),
    ))!;
    await pumpView(
      tester,
      DepthHeatmapView(image: image, rotationDegrees: 0),
    );
    expect(find.byType(ExcludeSemantics), findsWidgets);
    handle.dispose();
  });
}
