import 'package:eyecue_flutter/screens/help_screen.dart';
import 'package:eyecue_flutter/widgets/safety_disclosure.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/semantics.dart' show SemanticsNode;
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

  testWidgets('privacy link appears for EyeCue and is hidden for Study', (
    tester,
  ) async {
    const channel = MethodChannel('plugins.flutter.io/url_launcher');
    MethodCall? launched;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      launched = call;
      return true;
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );
    await tester.pumpWidget(const MaterialApp(home: HelpScreen()));
    await tester.scrollUntilVisible(find.text('Privacy policy'), 400);
    expect(find.text('Privacy policy'), findsOneWidget);
    await tester.tap(find.text('Privacy policy'));
    await tester.pump();
    expect(launched?.method, 'launch');
    expect(
      launched?.arguments['url'],
      'https://nmarcusg.github.io/eyecue_flutter/',
    );
    await tester.pumpWidget(
      const MaterialApp(home: HelpScreen(showPrivacyPolicy: false)),
    );
    expect(find.text('Privacy policy'), findsNothing);
  });

  group('privacy link launch failures', () {
    const channel = MethodChannel('plugins.flutter.io/url_launcher');

    Future<void> tapPrivacyLink(WidgetTester tester) async {
      await tester.pumpWidget(const MaterialApp(home: HelpScreen()));
      await tester.scrollUntilVisible(find.text('Privacy policy'), 400);
      await tester.tap(find.text('Privacy policy'));
      await tester.pumpAndSettle();
    }

    void mockLaunch(WidgetTester tester, Future<bool> Function() outcome) {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        (_) => outcome(),
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
    }

    const noBrowserMessage =
        'Unable to open the privacy policy. Check your browser and connection.';

    testWidgets('shows the fallback message when the launch returns false', (
      tester,
    ) async {
      mockLaunch(tester, () async => false);
      await tapPrivacyLink(tester);
      expect(find.text(noBrowserMessage), findsOneWidget);
    });

    testWidgets('shows the fallback message when the launch throws', (
      tester,
    ) async {
      mockLaunch(
        tester,
        () async => throw PlatformException(code: 'ACTIVITY_NOT_FOUND'),
      );
      await tapPrivacyLink(tester);
      expect(find.text(noBrowserMessage), findsOneWidget);
    });
  });

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

  group('reading granularity', () {
    testWidgets('Gesture Controls exposes one node per bullet', (tester) async {
      final handle = tester.ensureSemantics();
      try {
        await pumpHelp(tester);
        const bullets = [
          '• Two-finger double tap — start or exit detection mode.',
          '• Single tap — pause or resume detection.',
          '• Three-finger tap — quick environmental scan.',
          '• One-finger swipe down — repeat the most recent audio alert.',
        ];
        for (final bullet in bullets) {
          expect(
            find.semantics.byLabel(bullet).evaluate(),
            hasLength(1),
            reason: 'Missing or duplicated item node: $bullet',
          );
        }
        // The title remains the group's single header.
        final title = find.semantics.byLabel('Gesture Controls').evaluate();
        expect(title, hasLength(1));
        expect(
          title.single.getSemanticsData().flagsCollection.isHeader,
          isTrue,
        );
      } finally {
        handle.dispose();
      }
    });

    testWidgets('Best Use Tip exposes one node per bullet', (tester) async {
      final handle = tester.ensureSemantics();
      try {
        await pumpHelp(tester);
        const bullets = [
          '• Mount or carry the phone at chest height for the best view.',
          '• Use earphones so audio cues are easy to hear.',
          '• Keep the camera lens clean and pointed ahead.',
          '• In Low Power Mode detection runs at a slower rate to save '
              'battery.',
        ];
        for (final bullet in bullets) {
          expect(
            find.semantics.byLabel(bullet).evaluate(),
            hasLength(1),
            reason: 'Missing or duplicated item node: $bullet',
          );
        }
        final title = find.semantics
            .byLabel('Best Use Tip (Android)')
            .evaluate();
        expect(title, hasLength(1));
        expect(
          title.single.getSemanticsData().flagsCollection.isHeader,
          isTrue,
        );
      } finally {
        handle.dispose();
      }
    });

    testWidgets('How It Works stays one grouped node', (tester) async {
      final handle = tester.ensureSemantics();
      try {
        await pumpHelp(tester);
        final grouped = find.semantics
            .byLabel(RegExp(r'1\. Open EyeCue\.'))
            .evaluate()
            .toList();
        expect(grouped, hasLength(1));
        final label = grouped.single.getSemanticsData().label;
        expect(label, contains('1. Open EyeCue.'));
        expect(label, contains('2. Detection starts automatically'));
        expect(label, contains('EyeCue runs entirely on your device'));
      } finally {
        handle.dispose();
      }
    });
  });

  group('first-use dialog identity', () {
    testWidgets('names the dialog without competing live regions', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      try {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
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
        );
        await tester.tap(find.text('show'));
        await tester.pumpAndSettle();

        // The dialog title is its own header node and is not the disclosure
        // heading.
        final title = find.semantics.byLabel(kSafetyDialogTitle).evaluate();
        expect(title, hasLength(1));
        expect(
          title.single.getSemanticsData().flagsCollection.isHeader,
          isTrue,
        );
        expect(find.text(kSafetyDisclosureTitle), findsOneWidget);

        // No live region remains in the dialog on entry.
        final root = tester
            .binding
            .renderViews
            .first
            .owner!
            .semanticsOwner!
            .rootSemanticsNode!;
        final live = <String>[];
        void walk(SemanticsNode node) {
          final data = node.getSemanticsData();
          if (data.flagsCollection.isLiveRegion && data.label.isNotEmpty) {
            live.add(data.label);
          }
          node.visitChildren((child) {
            walk(child);
            return true;
          });
        }

        walk(root);
        expect(live, isEmpty, reason: 'the disclosure heading announces once');
      } finally {
        handle.dispose();
      }
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
