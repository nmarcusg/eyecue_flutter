import 'dart:ui' as ui;

import 'package:eyecue_flutter/widgets/depth_heatmap_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pumpView(WidgetTester tester, Widget child) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: Center(child: child)),
    ),
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
    await pumpView(tester, DepthHeatmapView(image: image, rotationDegrees: 90));

    expect(find.byType(RawImage), findsOneWidget);
    expect(find.byType(IgnorePointer), findsWidgets);
    expect(find.byType(ClipRect), findsWidgets);
    final fitted = tester.widget<FittedBox>(find.byType(FittedBox).first);
    expect(fitted.fit, BoxFit.cover);
    expect(fitted.alignment, Alignment.center);
    expect(fitted.clipBehavior, Clip.hardEdge);

    // The paint-only rotation is gone; the rotation now happens in layout.
    // Scoped to the heatmap subtree: the MaterialApp harness has its own
    // framework Transforms, none of which belong to this widget.
    expect(
      find.descendant(
        of: find.byType(DepthHeatmapView),
        matching: find.byType(Transform),
      ),
      findsNothing,
    );
    final rotated = tester.widget<RotatedBox>(find.byType(RotatedBox));
    expect(rotated.quarterTurns, 1);
    // Layout size of the rotated box: transposed, upright.
    expect(tester.getSize(find.byType(RotatedBox)), const Size(20, 40));
    // The child keeps the true SENSOR aspect: no stretch before rotation.
    final inner = tester.widget<SizedBox>(
      find
          .descendant(
            of: find.byType(RotatedBox),
            matching: find.byType(SizedBox),
          )
          .first,
    );
    expect(inner.width, 40);
    expect(inner.height, 20);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cover fit centres the rotated image and crops the overflow', (
    tester,
  ) async {
    final ui.Image image = (await tester.runAsync(
      () => createTestImage(width: 40, height: 20),
    ))!;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 100,
              height: 100,
              child: DepthHeatmapView(image: image, rotationDegrees: 90),
            ),
          ),
        ),
      ),
    );

    final box = tester.getRect(
      find.byType(FittedBox).first,
    ); // 100 x 100, painted
    final child = tester.getRect(find.byType(RotatedBox)); // scaled + centred
    // Cover: the child fills the box and overflows the cropped axis.
    expect(child.width, greaterThanOrEqualTo(box.width - 0.5));
    expect(child.height, greaterThanOrEqualTo(box.height - 0.5));
    expect(
      child.width > box.width + 0.5 || child.height > box.height + 0.5,
      isTrue,
    );
    // Centred on both axes.
    expect(child.center.dx, closeTo(box.center.dx, 0.5));
    expect(child.center.dy, closeTo(box.center.dy, 0.5));
    // Aspect preserved: 20 x 40 upright, scaled.
    expect(child.width / child.height, closeTo(20 / 40, 0.01));
    expect(tester.takeException(), isNull);
  });

  testWidgets('quarter turns map every rotation including negatives', (
    tester,
  ) async {
    final ui.Image image = (await tester.runAsync(
      () => createTestImage(width: 40, height: 20),
    ))!;
    for (final ({int degrees, int quarterTurns}) c in [
      (degrees: 0, quarterTurns: 0),
      (degrees: 90, quarterTurns: 1),
      (degrees: 180, quarterTurns: 2),
      (degrees: 270, quarterTurns: 3),
      (degrees: -90, quarterTurns: 3),
    ]) {
      await pumpView(
        tester,
        DepthHeatmapView(image: image, rotationDegrees: c.degrees),
      );
      expect(
        tester.widget<RotatedBox>(find.byType(RotatedBox)).quarterTurns,
        c.quarterTurns,
        reason: '${c.degrees} degrees',
      );
      expect(
        find.descendant(
          of: find.byType(DepthHeatmapView),
          matching: find.byType(Transform),
        ),
        findsNothing,
        reason: '${c.degrees} degrees',
      );
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('is excluded from semantics', (tester) async {
    final handle = tester.ensureSemantics();
    final ui.Image image = (await tester.runAsync(
      () => createTestImage(width: 20, height: 20),
    ))!;
    await pumpView(tester, DepthHeatmapView(image: image, rotationDegrees: 0));
    expect(find.byType(ExcludeSemantics), findsWidgets);
    handle.dispose();
  });
}
