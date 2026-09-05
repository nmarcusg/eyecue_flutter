import 'dart:ui' show SemanticsAction, Tristate;

import 'package:eyecue_flutter/models/app_settings.dart';
import 'package:eyecue_flutter/models/detection.dart';
import 'package:eyecue_flutter/models/detection_runtime_state.dart';
import 'package:eyecue_flutter/models/detection_info.dart';
import 'package:eyecue_flutter/services/spatial_analysis_service.dart';
import 'package:eyecue_flutter/services/telemetry_service.dart';
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
}
