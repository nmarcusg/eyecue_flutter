import 'package:eyecue_flutter/screens/help_screen.dart';
import 'package:eyecue_flutter/widgets/safety_disclosure.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Help-screen safety disclosure: permanent copy, wording, and large-text
/// behaviour.
void main() {
  Future<void> pumpHelp(
    WidgetTester tester, {
    double textScale = 1.0,
    double height = 1600,
  }) async {
    tester.view.physicalSize = Size(390 * 3, height * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
          child: const HelpScreen(),
        ),
      ),
    );
  }

  group('Help safety section', () {
    testWidgets('renders the heading and all five points in order', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      try {
        await pumpHelp(tester);

        final heading = find.text(kSafetyDisclosureTitle);
        expect(heading, findsOneWidget);
        // The heading is exposed as a real semantic header.
        final node = tester.getSemantics(heading);
        expect(node.getSemanticsData().flagsCollection.isHeader, isTrue);

        var previousY = tester.getTopLeft(heading).dy;
        for (final point in kSafetyDisclosurePoints) {
          final finder = find.textContaining(point);
          expect(finder, findsOneWidget, reason: 'Missing disclosure point');
          final y = tester.getTopLeft(finder).dy;
          expect(
            y,
            greaterThan(previousY),
            reason: 'Disclosure point is out of order: $point',
          );
          previousY = y;
        }
      } finally {
        handle.dispose();
      }
    });

    testWidgets('offers no competing safety surface in Help', (tester) async {
      await pumpHelp(tester);
      // One heading, one copy of each point: nothing is duplicated on the
      // permanent Help surface.
      expect(find.text(kSafetyDisclosureTitle), findsOneWidget);
      expect(find.byType(SafetyDisclosureCard), findsOneWidget);
    });

    testWidgets('is complete and legible at 200 percent text scale', (
      tester,
    ) async {
      // A tall scroll surface builds the whole section, so every point can be
      // inspected for clipping rather than being skipped by the viewport.
      await pumpHelp(tester, textScale: 2.0);
      await tester.pump();
      expect(tester.takeException(), isNull);
      for (final point in kSafetyDisclosurePoints) {
        expect(
          find.textContaining(point),
          findsOneWidget,
          reason: 'Point missing or clipped at 200% text scale',
        );
      }
    });
  });

  group('first-use dialog', () {
    testWidgets('carries the whole disclosure at 200 percent text scale', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2.0)),
            child: Scaffold(
              body: Builder(
                builder: (context) => Center(
                  child: TextButton(
                    onPressed: () => showDialog<void>(
                      context: context,
                      barrierDismissible: false,
                      builder: (_) =>
                          SafetyDisclosureDialog(onAcknowledge: () {}),
                    ),
                    child: const Text('show'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('show'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text(kSafetyDisclosureTitle), findsOneWidget);
      for (final point in kSafetyDisclosurePoints) {
        expect(find.textContaining(point), findsOneWidget);
      }
      expect(find.text('I understand'), findsOneWidget);
    });
  });

  group('safety wording', () {
    test('states every required point and prohibition', () {
      final text = [
        kSafetyDisclosureTitle,
        ...kSafetyDisclosurePoints,
      ].join(' ').toLowerCase();
      for (final required in const [
        // 1 experimental research and assistive
        'experimental research and assistive',
        // 2 delayed, inaccurate or incomplete
        'delayed, inaccurate or incomplete',
        // 3 does not replace a primary mobility aid
        'does not replace',
        'white cane',
        'guide dog',
        'orientation and mobility',
        'situational awareness',
        // 4 not the sole means
        'do not rely on eyecue as the only way',
        // 5 stop using it
        'stop using eyecue',
        'unsafe or distracting',
      ]) {
        expect(text, contains(required), reason: 'Missing: $required');
      }
    });

    test('makes no certification, proof or safety-guarantee claim', () {
      final text = kSafetyDisclosurePoints.join(' ').toLowerCase();
      for (final forbidden in const [
        'clinically proven',
        'certified medical device',
        'guarantees safety',
        'guaranteed safe',
        'replaces a white cane',
        'replaces a guide dog',
        'safe to use independently',
      ]) {
        expect(text, isNot(contains(forbidden)), reason: forbidden);
      }
    });
  });
}
