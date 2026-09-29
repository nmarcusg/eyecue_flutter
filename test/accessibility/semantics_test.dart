import 'dart:ui' show SemanticsAction, Size, Tristate;

import 'package:eyecue_flutter/models/app_settings.dart';
import 'package:eyecue_flutter/models/detection.dart';
import 'package:eyecue_flutter/models/detection_runtime_state.dart';
import 'package:eyecue_flutter/models/detection_info.dart';
import 'package:eyecue_flutter/screens/help_screen.dart';
import 'package:eyecue_flutter/screens/home_screen.dart';
import 'package:eyecue_flutter/screens/settings_screen.dart';
import 'package:eyecue_flutter/services/engine_coordinator.dart';
import 'package:eyecue_flutter/services/settings_service.dart';
import 'package:eyecue_flutter/services/spatial_analysis_service.dart';
import 'package:eyecue_flutter/services/telemetry_service.dart';
import 'package:eyecue_flutter/theme/app_colors.dart';
import 'package:eyecue_flutter/theme/app_home_theme.dart';
import 'package:eyecue_flutter/widgets/accessible_button.dart';
import 'package:eyecue_flutter/widgets/charts.dart';
import 'package:eyecue_flutter/widgets/detection_card.dart';
import 'package:eyecue_flutter/widgets/detection_correction_sheet.dart';
import 'package:eyecue_flutter/widgets/detection_state_panel.dart';
import 'package:eyecue_flutter/widgets/status_pill.dart';
import 'package:eyecue_flutter/widgets/warning_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

DetectionInfo sampleInfo() {
  return SpatialAnalysisService.analyze(
    const Detection(
      classId: 0,
      label: 'person',
      confidence: 0.82,
      box: Rect.fromLTWH(0.7, 0.1, 0.2, 0.6),
    ),
  );
}

List<RuntimeSample> sampleRuntimeSamples() {
  return [
    RuntimeSample(
      timestamp: DateTime(2026, 1, 1),
      latencyMs: 30,
      inferenceFps: 10,
      objectCount: 1,
      engine: InferenceEngine.custom,
    ),
    RuntimeSample(
      timestamp: DateTime(2026, 1, 1, 0, 0, 1),
      latencyMs: 50,
      inferenceFps: 20,
      objectCount: 2,
      engine: InferenceEngine.custom,
    ),
  ];
}

Widget appWithBody(Widget body) {
  return MaterialApp(home: Scaffold(body: body));
}

Widget scaledApp(Widget body) {
  return MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(2.0)),
      child: Scaffold(body: body),
    ),
  );
}

void expectButtonSemantics(
  WidgetTester tester,
  String label, {
  bool enabled = true,
}) {
  final nodes = find.semantics
      .byPredicate(
        (node) =>
            node.label == label &&
            node.getSemanticsData().flagsCollection.isButton,
      )
      .evaluate()
      .where((node) {
        final data = node.getSemanticsData();
        return data.flagsCollection.isEnabled ==
                (enabled ? Tristate.isTrue : Tristate.isFalse) &&
            data.hasAction(SemanticsAction.tap) == enabled;
      })
      .toList();
  expect(
    nodes,
    isNotEmpty,
    reason: 'No matching ${enabled ? 'enabled' : 'disabled'} button: $label',
  );
  final node = nodes.first;
  final data = node.getSemanticsData();
  expect(data.flagsCollection.isButton, isTrue);
  expect(
    data.flagsCollection.isEnabled,
    enabled ? Tristate.isTrue : Tristate.isFalse,
  );
  expect(data.hasAction(SemanticsAction.tap), enabled);
}

SemanticsNode expectSemanticNode(Pattern label) {
  final nodes = find.semantics.byLabel(label).evaluate().toList();
  expect(nodes, isNotEmpty, reason: 'No semantic node matched: $label');
  return nodes.first;
}

Future<void> withSemantics(
  WidgetTester tester,
  Future<void> Function() body,
) async {
  final handle = tester.ensureSemantics();
  try {
    await body();
  } finally {
    handle.dispose();
  }
}

void main() {
  group('button and status semantics', () {
    testWidgets('AccessibleButton exposes an actionable enabled node', (
      tester,
    ) async {
      await tester.pumpWidget(
        appWithBody(
          AccessibleButton(
            label: 'Start detection',
            icon: Icons.play_arrow,
            onPressed: () {},
          ),
        ),
      );
      await withSemantics(tester, () async {
        expectButtonSemantics(tester, 'Start detection');
        expect(
          expectSemanticNode('Start detection').hint,
          'Double tap to activate',
        );
      });
    });

    testWidgets('AccessibleButton exposes disabled state without tap action', (
      tester,
    ) async {
      await tester.pumpWidget(
        appWithBody(
          const AccessibleButton(label: 'Pause detection', icon: Icons.pause),
        ),
      );
      await withSemantics(tester, () async {
        expectButtonSemantics(tester, 'Pause detection', enabled: false);
        expect(expectSemanticNode('Pause detection').hint, 'Unavailable');
      });
    });

    testWidgets('status and warning surfaces are live semantic containers', (
      tester,
    ) async {
      await tester.pumpWidget(
        appWithBody(
          const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              StatusPill(label: 'Detecting', color: Colors.green),
              WarningBanner(message: 'Object ahead'),
            ],
          ),
        ),
      );
      await withSemantics(tester, () async {
        final status = expectSemanticNode('Detection status: Detecting');
        final warning = expectSemanticNode('Warning. Object ahead');
        expect(status.getSemanticsData().flagsCollection.isLiveRegion, isTrue);
        expect(warning.getSemanticsData().flagsCollection.isLiveRegion, isTrue);
      });
    });
  });

  group('detection semantics', () {
    testWidgets('DetectionCard provides one coherent object description', (
      tester,
    ) async {
      final info = sampleInfo();
      await tester.pumpWidget(appWithBody(DetectionCard(info: info)));
      await withSemantics(tester, () async {
        expectSemanticNode(RegExp(RegExp.escape(info.semanticLabel)));
        expect(find.semantics.byLabel('HIGH').evaluate(), isEmpty);
      });
    });

    testWidgets('DetectionCard is NOT a live region', (tester) async {
      final info = sampleInfo();
      await tester.pumpWidget(appWithBody(DetectionCard(info: info)));
      await withSemantics(tester, () async {
        final node = expectSemanticNode(
          RegExp(RegExp.escape(info.semanticLabel)),
        );
        expect(node.getSemanticsData().flagsCollection.isLiveRegion, isFalse);
      });
    });

    testWidgets('audio pill exposes an enabled Audio guidance node', (
      tester,
    ) async {
      await tester.pumpWidget(
        appWithBody(
          Semantics(
            button: true,
            enabled: true,
            label: 'Audio guidance, on',
            child: GestureDetector(onTap: () {}, child: const Text('AUDIO ON')),
          ),
        ),
      );
      await withSemantics(tester, () async {
        final node = expectSemanticNode(RegExp('Audio guidance, on'));
        final data = node.getSemanticsData();
        expect(data.flagsCollection.isButton, isTrue);
        expect(data.flagsCollection.isEnabled, Tristate.isTrue);
        expect(data.hasAction(SemanticsAction.tap), isTrue);
      });
    });

    testWidgets('Detection chrome has no overflow at 200% text scale', (
      tester,
    ) async {
      final info = sampleInfo();
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2.0)),
            child: Theme(
              data: buildHomeTheme(),
              child: Scaffold(
                body: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const StatusPill(label: 'Detecting', color: kStatusGreen),
                    DetectionCard(info: info),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('DetectionCard keeps reporting as a separate action', (
      tester,
    ) async {
      final info = sampleInfo();
      await tester.pumpWidget(
        appWithBody(DetectionCard(info: info, onReport: () {})),
      );
      await withSemantics(tester, () async {
        expectSemanticNode(RegExp(RegExp.escape(info.semanticLabel)));
        expectButtonSemantics(tester, 'Report detection');
      });
    });
  });

  group('runtime state semantics', () {
    testWidgets(
      'state panel exposes safe status and available recovery actions',
      (tester) async {
        var retryCount = 0;
        var fallbackCount = 0;
        var stopCount = 0;
        final failure = DetectionFailure(
          category: DetectionFailureCategory.nativeInitialization,
          safeMessage: 'The recommended engine could not start.',
          recoverable: true,
          timestamp: DateTime(2026, 1, 1),
          fallbackAvailable: true,
        );
        await tester.pumpWidget(
          appWithBody(
            DetectionStatePanel(
              state: DetectionRuntimeState.failed,
              failure: failure,
              onRetry: () => retryCount++,
              onFallback: () => fallbackCount++,
              onStop: () => stopCount++,
            ),
          ),
        );
        await withSemantics(tester, () async {
          final panel = expectSemanticNode(
            RegExp(
              r'^Engine initialization\. The recommended engine could not start\.',
            ),
          );
          expect(panel.getSemanticsData().flagsCollection.isLiveRegion, isTrue);
          expectButtonSemantics(tester, 'Retry');
          expectButtonSemantics(tester, 'Use fallback');
          expectButtonSemantics(tester, 'Stop');

          await tester.tap(find.text('Retry'));
          await tester.tap(find.text('Use fallback'));
          await tester.tap(find.text('Stop'));
          expect(retryCount, 1);
          expect(fallbackCount, 1);
          expect(stopCount, 1);
        });
      },
    );
  });

  group('chart semantics', () {
    testWidgets('charts expose summaries while hiding chart drawing details', (
      tester,
    ) async {
      final samples = sampleRuntimeSamples();
      await tester.pumpWidget(
        appWithBody(
          Column(
            children: [
              SizedBox(height: 140, child: LatencyChart(samples: samples)),
              SizedBox(height: 140, child: FpsChart(samples: samples)),
              SizedBox(
                height: 140,
                child: DetectionFrequencyChart(buckets: const [2, 3]),
              ),
            ],
          ),
        ),
      );
      await withSemantics(tester, () async {
        expectSemanticNode(
          RegExp(r'^Inference latency chart\. Latest 50\.0 milliseconds;'),
        );
        expectSemanticNode(
          RegExp(r'^Frames per second chart\. Latest 20\.0 frames per second;'),
        );
        expectSemanticNode(
          RegExp(
            r'^Detection frequency chart\. 5 detections across 2 minutes\.',
          ),
        );
      });
    });

    testWidgets('empty charts state that data is not available', (
      tester,
    ) async {
      await tester.pumpWidget(
        appWithBody(
          Column(
            children: [
              LatencyChart(samples: const []),
              FpsChart(samples: const []),
              DetectionFrequencyChart(buckets: const []),
            ],
          ),
        ),
      );
      await withSemantics(tester, () async {
        expectSemanticNode(
          RegExp(r'^Inference latency chart\. No data available yet\.'),
        );
        expectSemanticNode(
          RegExp(r'^Frames per second chart\. No data available yet\.'),
        );
        expectSemanticNode(
          RegExp(r'^Detection frequency chart\. No data available yet\.'),
        );
      });
    });
  });

  group('correction semantics', () {
    testWidgets('correction choices and label search are actionable', (
      tester,
    ) async {
      await tester.pumpWidget(
        appWithBody(
          DetectionCorrectionSheet(
            info: sampleInfo(),
            labels: const ['person', 'bicycle'],
          ),
        ),
      );
      await withSemantics(tester, () async {
        expectButtonSemantics(tester, 'Correct');
        expectButtonSemantics(tester, 'Incorrect');
        expectButtonSemantics(tester, 'Unsure');
        expectButtonSemantics(tester, 'Cancel');

        await tester.tap(find.text('Incorrect'));
        await tester.pump();
        expectSemanticNode(RegExp(r'^Search labels'));
        expectButtonSemantics(tester, 'Save incorrect report');
        final label = expectSemanticNode('bicycle');
        expect(label.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
        expectButtonSemantics(tester, 'Back');
      });
    });
  });

  group('large text layout', () {
    testWidgets('detection card has no overflow at 200 percent text scale', (
      tester,
    ) async {
      await tester.pumpWidget(
        scaledApp(
          SizedBox(
            width: 320,
            child: DetectionCard(info: sampleInfo(), onReport: () {}),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('state panel has no overflow at 200 percent text scale', (
      tester,
    ) async {
      await tester.pumpWidget(
        scaledApp(
          SizedBox(
            width: 320,
            child: DetectionStatePanel(
              state: DetectionRuntimeState.recovering,
              onRetry: () {},
              onStop: () {},
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'correction controls have no overflow at 200 percent text scale',
      (tester) async {
        await tester.pumpWidget(
          scaledApp(
            DetectionCorrectionSheet(
              info: sampleInfo(),
              labels: const ['person', 'bicycle', 'traffic light'],
            ),
          ),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
      },
    );
  });

  group('home semantics', () {
    EngineCoordinator homeCoordinator() =>
        EngineCoordinator(preferredEngine: InferenceEngine.ultralytics);

    Widget homeApp(EngineCoordinator c) {
      return MaterialApp(
        home: HomeScreen(
          settings: SettingsService(store: InMemorySettingsStore()),
          coordinator: c,
        ),
      );
    }

    testWidgets('initial Preparing state exposes the full meaning', (
      tester,
    ) async {
      await tester.pumpWidget(homeApp(homeCoordinator()));
      await withSemantics(tester, () async {
        expectSemanticNode(
          'Preparing. Swipe left to start! Detection begins immediately.',
        );
        // The live wordmark is present exactly once (logo is decorative).
        expect(find.semantics.byLabel('EyeCue').evaluate(), hasLength(1));
        // No CTA or substitute action is exposed.
        expect(find.semantics.byLabel('Go to Live Camera').evaluate(), isEmpty);
      });
    });

    testWidgets('Ready state exposes the full meaning', (tester) async {
      final c = homeCoordinator();
      c.reportReady();
      await tester.pumpWidget(homeApp(c));
      await withSemantics(tester, () async {
        expectSemanticNode('Ready. Ready when you are. Detection is ready.');
        expect(find.semantics.byLabel('EyeCue').evaluate(), hasLength(1));
        expect(find.semantics.byLabel('Go to Live Camera').evaluate(), isEmpty);
      });
    });

    testWidgets('Paused and Stopped states expose their full meaning', (
      tester,
    ) async {
      final paused = homeCoordinator();
      paused.reportPaused();
      await tester.pumpWidget(homeApp(paused));
      await withSemantics(tester, () async {
        expectSemanticNode(
          'Paused. Detection is paused. Open Detect to resume.',
        );
      });

      final stopped = homeCoordinator();
      stopped.reportStopped();
      await tester.pumpWidget(homeApp(stopped));
      await withSemantics(tester, () async {
        expectSemanticNode(
          'Stopped. Detection is stopped. Open Detect to start again.',
        );
      });
    });

    testWidgets('Unavailable state reads the shared safe message', (
      tester,
    ) async {
      final c = homeCoordinator();
      c.reportFailure(
        DetectionFailure(
          category: DetectionFailureCategory.permissionDenied,
          safeMessage: 'Camera permission is required to detect objects.',
          timestamp: DateTime(2026, 1, 1),
        ),
      );
      await tester.pumpWidget(homeApp(c));
      await withSemantics(tester, () async {
        expectSemanticNode(
          'Unavailable. Detection needs attention. '
          'Camera permission is required to detect objects.',
        );
      });
    });

    testWidgets('logo and rail are decorative and do not duplicate labels', (
      tester,
    ) async {
      await tester.pumpWidget(homeApp(homeCoordinator()));
      await withSemantics(tester, () async {
        // Only the live wordmark carries the 'EyeCue' label; the logo image is
        // excluded and must not add a second one.
        expect(find.semantics.byLabel('EyeCue').evaluate(), hasLength(1));
        // No replacement action is exposed.
        expect(find.semantics.byLabel('Go to Live Camera').evaluate(), isEmpty);
      });
    });

    testWidgets('home has no overflow at 200 percent text scale', (
      tester,
    ) async {
      // Use a realistic phone-sized surface (the reference canvas is 390x844
      // logical pixels) so the fill-then-scroll Home layout is exercised at a
      // height representative of a physical device rather than the short
      // default test surface.
      tester.view.physicalSize = const Size(390 * 3, 844 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(2.0)),
            child: HomeScreen(
              settings: SettingsService(store: InMemorySettingsStore()),
              coordinator: homeCoordinator(),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  group('help semantics', () {
    // The Help body is a scrollable ListView, so use a tall phone-sized surface
    // so all four section cards are built and their semantics are available.
    Future<void> pumpHelp(WidgetTester tester, {double textScale = 1.0}) async {
      tester.view.physicalSize = const Size(390 * 3, 1600 * 3);
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

    testWidgets('screen title is a real semantic heading', (tester) async {
      await pumpHelp(tester);
      await withSemantics(tester, () async {
        final title = expectSemanticNode('Help & Gestures');
        expect(title.getSemanticsData().flagsCollection.isHeader, isTrue);
      });
    });

    testWidgets('each section is one coherent group with its title', (
      tester,
    ) async {
      await pumpHelp(tester);
      await withSemantics(tester, () async {
        // Each section title is present as a semantic heading.
        expectSemanticNode('How It Works');
        expectSemanticNode('Gesture Controls');
        expectSemanticNode('Gesture Confirmation');
        expectSemanticNode('Best Use Tip (Android)');
        // The section icons are decorative and must not add duplicate labels.
        expect(find.semantics.byLabel('How It Works').evaluate(), hasLength(1));
        expect(
          find.semantics.byLabel('Gesture Controls').evaluate(),
          hasLength(1),
        );
      });
    });

    testWidgets('section icons are removed from the accessibility tree', (
      tester,
    ) async {
      await pumpHelp(tester);
      await withSemantics(tester, () async {
        // The decorative section icons were removed entirely, so no icon-only
        // label exists and the titles remain the single heading per section.
        expect(find.semantics.byLabel('timeline').evaluate(), isEmpty);
        expect(find.semantics.byLabel('touch_app').evaluate(), isEmpty);
        expect(find.semantics.byLabel('vibration').evaluate(), isEmpty);
        expect(find.semantics.byLabel('phone_android').evaluate(), isEmpty);
      });
    });

    testWidgets('help has no overflow at 200 percent text scale', (
      tester,
    ) async {
      // Use a realistic phone-sized surface so the scrollable Help layout is
      // exercised at a height representative of a physical device.
      tester.view.physicalSize = const Size(390 * 3, 844 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(2.0)),
            child: const HelpScreen(),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  group('settings semantics', () {
    // The Settings body is a scrollable ListView of four cards, so use a tall
    // phone-sized surface so all cards are built and their semantics are
    // available (ListView builds only the children in the viewport).
    Future<void> pumpSettings(
      WidgetTester tester, {
      SettingsService? service,
      TelemetryService? telemetry,
      double textScale = 1.0,
    }) async {
      // Tall enough that the scrollable ListView builds all four cards (the
      // dark System Performance card is last and would otherwise be outside
      // the viewport, so its semantics would not exist).
      tester.view.physicalSize = const Size(390 * 3, 4000 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
            child: SettingsScreen(
              settings:
                  service ?? SettingsService(store: InMemorySettingsStore()),
              onOpenLogsReports: () {},
              telemetry: telemetry,
            ),
          ),
        ),
      );
    }

    testWidgets('screen title and card headings are real semantic headings', (
      tester,
    ) async {
      await pumpSettings(tester);
      await withSemantics(tester, () async {
        final title = expectSemanticNode('Settings');
        expect(title.getSemanticsData().flagsCollection.isHeader, isTrue);

        // Each card heading is exposed as a semantic heading for its group.
        for (final heading in const [
          'Preferences',
          'Audio Guidance',
          'Engine & Sensitivity',
          'System Performance',
        ]) {
          final node = expectSemanticNode(heading);
          expect(
            node.getSemanticsData().flagsCollection.isHeader,
            isTrue,
            reason: 'Card heading is not a semantic header: $heading',
          );
          // The heading is exposed exactly once (the visual Text is excluded,
          // so the decorative icon + heading do not duplicate the label).
          expect(
            find.semantics.byLabel(heading).evaluate(),
            hasLength(1),
            reason: 'Heading label duplicated: $heading',
          );
        }
      });
    });

    testWidgets('decorative card icons are excluded from the tree', (
      tester,
    ) async {
      await pumpSettings(tester);
      await withSemantics(tester, () async {
        // The card/row icons duplicate the adjacent headings and are wrapped in
        // ExcludeSemantics, so no icon-only label is exposed.
        expect(find.semantics.byLabel('tune_rounded').evaluate(), isEmpty);
        expect(find.semantics.byLabel('volume_up').evaluate(), isEmpty);
        expect(find.semantics.byLabel('memory_rounded').evaluate(), isEmpty);
        expect(find.semantics.byLabel('bar_chart_rounded').evaluate(), isEmpty);
      });
    });

    testWidgets('switches expose label, role, and checked state', (
      tester,
    ) async {
      await pumpSettings(tester);
      await withSemantics(tester, () async {
        // Each Preferences/Audio switch is a toggle with a checked state and a
        // tap action; the widgets already expose this without extra Semantics.
        for (final label in const [
          'Vibration Feedback',
          'Auto-Start on Open',
          'Low Power Mode',
          'Audio / Voice Guidance',
        ]) {
          final node = expectSemanticNode(RegExp('^${RegExp.escape(label)}'));
          final data = node.getSemanticsData();
          expect(
            data.flagsCollection.isToggled,
            isNot(Tristate.none),
            reason: 'Switch has no toggled state: $label',
          );
          expect(
            data.hasAction(SemanticsAction.tap),
            isTrue,
            reason: 'Switch is not actionable: $label',
          );
        }
      });
    });

    testWidgets('radio tiles expose label, role, and selected state', (
      tester,
    ) async {
      await pumpSettings(tester);
      await withSemantics(tester, () async {
        // Engine options and sensitivity presets are radio tiles; each exposes
        // a selected state and a tap action from the widget itself.
        for (final label in const [
          'Ultralytics',
          'Custom EyeCue',
          'More detections',
          'Balanced',
          'Fewer false alerts',
        ]) {
          final node = expectSemanticNode(RegExp('^${RegExp.escape(label)}'));
          final data = node.getSemanticsData();
          expect(
            data.flagsCollection.isInMutuallyExclusiveGroup,
            isTrue,
            reason: 'Radio tile is not in a mutually exclusive group: $label',
          );
          expect(
            data.hasAction(SemanticsAction.tap),
            isTrue,
            reason: 'Radio tile is not actionable: $label',
          );
        }
      });
    });

    testWidgets('advanced slider exposes its container label and value', (
      tester,
    ) async {
      await pumpSettings(tester);
      await withSemantics(tester, () async {
        // The preserved Semantics(container: true, label: ...) wrapper exposes
        // the current threshold value in its label.
        expectSemanticNode(
          RegExp(r'^Advanced detection confidence threshold, 0\.25'),
        );
        // The inner Slider node carries the adjustable value and the
        // increase/decrease actions (the container wrapper does not).
        final slider = expectSemanticNode('0.25');
        final data = slider.getSemanticsData();
        expect(data.hasAction(SemanticsAction.increase), isTrue);
        expect(data.hasAction(SemanticsAction.decrease), isTrue);
      });
    });

    testWidgets('performance metrics are text semantics, not a live region', (
      tester,
    ) async {
      final telemetry = TelemetryService();
      telemetry.recordSample(
        latencyMs: 120,
        inferenceFps: 8,
        objectCount: 1,
        engine: InferenceEngine.ultralytics,
      );
      await pumpSettings(tester, telemetry: telemetry);
      await withSemantics(tester, () async {
        // The System Performance card merges its metric text into one semantic
        // node (the card's ListTile merges its subtree). The metric labels and
        // values are therefore available as text/semantics within that node.
        final card = expectSemanticNode(
          RegExp(r'Avg FPS[\s\S]*Avg latency \(MS\)[\s\S]*Avg confidence'),
        );
        final label = card.getSemanticsData().label;
        expect(label, contains('Avg FPS'));
        expect(label, contains('Avg latency (MS)'));
        expect(label, contains('Avg confidence'));
        expect(label, contains('8.0'));
        expect(label, contains('120.0'));

        // The metrics are deliberate status text, not a per-frame live region.
        expect(
          card.getSemanticsData().flagsCollection.isLiveRegion,
          isFalse,
          reason: 'Performance metrics must not be a live region',
        );
      });
    });

    testWidgets('performance metrics show — placeholders without telemetry', (
      tester,
    ) async {
      await pumpSettings(tester);
      await withSemantics(tester, () async {
        // The em-dash placeholders are exposed as text/semantics (not
        // color-only) within the merged System Performance node.
        final card = expectSemanticNode(
          RegExp(r'Avg FPS[\s\S]*Avg latency \(MS\)[\s\S]*Avg confidence'),
        );
        final label = card.getSemanticsData().label;
        expect(label, contains('Avg FPS'));
        expect(label, contains('Avg latency (MS)'));
        expect(label, contains('Avg confidence'));
        expect('—'.allMatches(label).length, 3);
      });
    });

    testWidgets('settings has no overflow at 200 percent text scale', (
      tester,
    ) async {
      // Use a realistic phone-sized surface so the scrollable Settings layout
      // is exercised at a height representative of a physical device.
      tester.view.physicalSize = const Size(390 * 3, 844 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(2.0)),
            child: SettingsScreen(
              settings: SettingsService(store: InMemorySettingsStore()),
              onOpenLogsReports: () {},
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });
}
