import 'dart:async';
import 'dart:io';

import 'package:eyecue_flutter/models/alert_lifecycle.dart';
import 'package:eyecue_flutter/models/app_settings.dart';
import 'package:eyecue_flutter/models/detection.dart';
import 'package:eyecue_flutter/models/detection_correction.dart';
import 'package:eyecue_flutter/models/detection_info.dart';
import 'package:eyecue_flutter/screens/logs_reports_screen.dart';
import 'package:eyecue_flutter/services/correction_service.dart';
import 'package:eyecue_flutter/services/telemetry_export_service.dart';
import 'package:eyecue_flutter/services/telemetry_service.dart';
import 'package:eyecue_flutter/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemUiOverlayStyle;
import 'package:flutter_test/flutter_test.dart';

/// A [TelemetryExportService] whose writes are controlled by the test so the
/// busy guard, success SnackBar, and failure SnackBar can be exercised
/// deterministically without touching the filesystem.
class _FakeExportService extends TelemetryExportService {
  _FakeExportService({this.completer, this.throwOnWrite = false});

  /// When supplied, the write awaits this completer so the test can observe the
  /// in-flight busy state before completing it.
  final Completer<void>? completer;

  /// When true, the write throws so the failure SnackBar path is exercised.
  final bool throwOnWrite;

  int jsonWrites = 0;
  int csvWrites = 0;

  @override
  Future<File> writeJson({
    required TelemetryService telemetry,
    AppSettings? settings,
    Directory? directory,
  }) async {
    jsonWrites++;
    if (completer != null) await completer!.future;
    if (throwOnWrite) throw const FileSystemException('write failed');
    return File('/tmp/20260101120000-telemetry.json');
  }

  @override
  Future<File> writeCsv({
    required TelemetryService telemetry,
    AppSettings? settings,
    Directory? directory,
  }) async {
    csvWrites++;
    if (completer != null) await completer!.future;
    if (throwOnWrite) throw const FileSystemException('write failed');
    return File('/tmp/20260101120000-telemetry.csv');
  }
}

/// Builds a telemetry service with a deterministic clock and optional data.
TelemetryService buildTelemetry({
  bool populated = false,
  InferenceEngine engine = InferenceEngine.ultralytics,
}) {
  final service = TelemetryService(
    clock: () => DateTime.utc(2026, 1, 1, 12, 0, 0),
    sessionId: 'session-test',
  );
  service.startSession();
  if (populated) {
    service.recordSample(
      latencyMs: 120,
      inferenceFps: 8,
      objectCount: 1,
      engine: engine,
    );
    service.recordDetection(
      DetectionInfo(
        detection: const Detection(
          classId: 0,
          label: 'person',
          confidence: 0.82,
          box: Rect.fromLTWH(0.1, 0.2, 0.3, 0.4),
        ),
        position: RelativePosition.center,
        priority: ObjectPriority.high,
        proximity: ProximityBand.near,
      ),
      120,
      engine: engine,
    );
    final analysis = DateTime.utc(2026, 1, 1, 12, 0, 0);
    service.recordAlertLifecycle(
      AlertLifecycleRecord(
        origin: AlertOrigin.detection,
        engine: InferenceEngine.ultralytics,
        requestedAt: analysis,
        submittedAt: analysis.add(const Duration(milliseconds: 20)),
        alertStartedAt: analysis.add(const Duration(milliseconds: 50)),
        terminalAt: analysis.add(const Duration(seconds: 1)),
        terminalState: AlertTerminalState.completed,
        terminalCause: null,
        hadStarted: true,
        reconciledAt: analysis.add(const Duration(seconds: 1)),
        frameNumber: 1,
        analysisReceivedAt: analysis,
        detectionAcceptedAt: analysis.add(const Duration(milliseconds: 10)),
      ),
    );
    service.recordAlertLifecycle(
      AlertLifecycleRecord(
        origin: AlertOrigin.detection,
        engine: InferenceEngine.ultralytics,
        requestedAt: analysis,
        submittedAt: analysis.add(const Duration(milliseconds: 110)),
        alertStartedAt: analysis.add(const Duration(milliseconds: 130)),
        terminalAt: analysis.add(const Duration(seconds: 1)),
        terminalState: AlertTerminalState.completed,
        terminalCause: null,
        hadStarted: true,
        reconciledAt: analysis.add(const Duration(seconds: 1)),
        frameNumber: 2,
        resultReceivedAt: analysis.add(const Duration(milliseconds: 100)),
        detectionAcceptedAt: analysis.add(const Duration(milliseconds: 105)),
      ),
    );
    service.recordAlertCounters(
      const AlertCounters(
        dropped: 1,
        muted: 2,
        rejectedByReason: {'lowConfidence': 3},
      ),
    );
  }
  return service;
}

/// Builds a correction service with one populated record when requested.
CorrectionService buildCorrections({bool populated = false}) {
  final service = CorrectionService(
    labels: const ['person', 'bicycle'],
    clock: () => DateTime.utc(2026, 1, 1, 12, 0, 0),
    sessionId: 'session-test',
  );
  if (populated) {
    service.add(
      info: DetectionInfo(
        detection: const Detection(
          classId: 0,
          label: 'person',
          confidence: 0.82,
          box: Rect.fromLTWH(0.1, 0.2, 0.3, 0.4),
        ),
        position: RelativePosition.center,
        priority: ObjectPriority.high,
        proximity: ProximityBand.near,
      ),
      feedback: CorrectionFeedback.incorrect,
      engine: InferenceEngine.ultralytics,
      confidenceThreshold: 0.25,
      correctedLabel: 'bicycle',
    );
  }
  return service;
}

/// Pumps the real [LogsReportsScreen] on a tall phone-sized surface so the
/// scrollable Overview/Charts content is built and visible.
Future<void> pumpLogsScreen(
  WidgetTester tester, {
  required TelemetryService telemetry,
  CorrectionService? corrections,
  TelemetryExportService? exportService,
  double textScale = 1.0,
  Size size = const Size(390 * 3, 2400 * 3),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: LogsReportsScreen(
          telemetry: telemetry,
          corrections: corrections,
          exportService: exportService,
        ),
      ),
    ),
  );
  await tester.pump();
  // Flush the bounded 250 ms counter publication window so no fake-async timer
  // remains pending when the test ends.
  await tester.pump(const Duration(milliseconds: 300));
}

/// Selects a tab by its visible label.
Future<void> selectTab(WidgetTester tester, String label) async {
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

void main() {
  group('route-local light theme scope', () {
    testWidgets('renders under the local buildHomeTheme() light theme', (
      tester,
    ) async {
      await pumpLogsScreen(tester, telemetry: buildTelemetry());

      // The route-local Theme wrapper applies the light Home theme to the
      // pushed route content.
      final theme = Theme.of(tester.element(find.text('Logs & Reports')));
      expect(theme.brightness, Brightness.light);
      expect(theme.scaffoldBackgroundColor, kHomeSurfaceBase);
    });

    testWidgets('app bar and body share the fixed light surface', (
      tester,
    ) async {
      await pumpLogsScreen(tester, telemetry: buildTelemetry());

      // The theme-owned light AppBarTheme keeps the app bar and the scrolling
      // body on one consistent light surface.
      final theme = Theme.of(tester.element(find.text('Logs & Reports')));
      expect(theme.appBarTheme.backgroundColor, kHomeSurfaceBase);
      expect(theme.scaffoldBackgroundColor, kHomeSurfaceBase);
      // The TabBar is part of the same app-bar surface treatment.
      expect(find.byType(TabBar), findsOneWidget);
    });

    testWidgets('scopes the dark status-bar overlay to the pushed route', (
      tester,
    ) async {
      await pumpLogsScreen(tester, telemetry: buildTelemetry());

      // The route wraps its content in an AnnotatedRegion carrying the dark
      // status-bar icon style. MaterialApp/Scaffold also install their own
      // AnnotatedRegions, so match the one whose value is the dark overlay.
      final darkRegions = find
          .byWidgetPredicate(
            (widget) =>
                widget is AnnotatedRegion<SystemUiOverlayStyle> &&
                widget.value == SystemUiOverlayStyle.dark,
          )
          .evaluate();
      expect(darkRegions, isNotEmpty);

      // The route-local light theme is applied to the pushed route content.
      final appTheme = Theme.of(tester.element(find.byType(Scaffold)));
      expect(appTheme.scaffoldBackgroundColor, kHomeSurfaceBase);
    });
  });

  group('tabs', () {
    testWidgets('Overview tab renders its sections when selected', (
      tester,
    ) async {
      await pumpLogsScreen(tester, telemetry: buildTelemetry());

      expect(find.text('Overview'), findsOneWidget);
      expect(find.text('Real-Time Performance'), findsOneWidget);
      expect(find.text('Engine Comparison'), findsOneWidget);
      expect(find.text('Session Summary'), findsOneWidget);
      expect(find.text('Offline telemetry export'), findsWidgets);
    });

    testWidgets('Charts tab renders the three chart regions when selected', (
      tester,
    ) async {
      await pumpLogsScreen(tester, telemetry: buildTelemetry());
      await selectTab(tester, 'Charts');

      expect(find.text('Inference Latency (300 ms benchmark)'), findsOneWidget);
      expect(find.text('Frames Per Second (15 FPS target)'), findsOneWidget);
      expect(find.text('Detection Frequency'), findsOneWidget);
    });

    testWidgets('Logs tab renders its empty state when selected', (
      tester,
    ) async {
      await pumpLogsScreen(tester, telemetry: buildTelemetry());
      await selectTab(tester, 'Logs');

      expect(find.text('No detections recorded yet.'), findsOneWidget);
    });
  });

  group('Overview populated and empty states', () {
    testWidgets('empty telemetry shows 0.0 / 0.0 ms / No samples / —', (
      tester,
    ) async {
      await pumpLogsScreen(tester, telemetry: buildTelemetry());

      // Avg FPS and Avg Latency empty values.
      expect(find.text('0.0'), findsOneWidget);
      expect(find.text('0.0 ms'), findsOneWidget);
      // The engine summary and all four alert intervals are empty.
      expect(find.text('No samples'), findsNWidgets(5));
      // Avg confidence shows the em dash when there are no records.
      expect(find.text('—'), findsOneWidget);
    });

    testWidgets('populated telemetry shows computed averages', (tester) async {
      await pumpLogsScreen(tester, telemetry: buildTelemetry(populated: true));

      // Avg FPS 8.0 and Avg Latency 120.0 ms (exact metric-card values).
      expect(find.text('8.0'), findsOneWidget);
      expect(find.text('120.0 ms'), findsOneWidget);
      // The populated engine summary reports FPS, latency, and frame count.
      expect(find.text('8.0 FPS · 120.0 ms · 1 frames'), findsOneWidget);
      // Avg confidence is a percentage, not an em dash.
      expect(find.text('82%'), findsOneWidget);
    });
  });

  group('alert latency reporting', () {
    testWidgets('empty alert intervals render No samples without percentiles', (
      tester,
    ) async {
      await pumpLogsScreen(tester, telemetry: buildTelemetry());

      expect(find.text('Alert Latency'), findsOneWidget);
      expect(find.text('Alert latency and scheduler health'), findsOneWidget);
      expect(find.text('Scheduler health'), findsOneWidget);
      // All four required interval labels stay visible when empty (one engine).
      expect(find.text('Result received → detection accepted'), findsOneWidget);
      expect(find.text('Detection accepted → alert started'), findsOneWidget);
      expect(find.text('Alert submitted → alert started'), findsOneWidget);
      expect(
        find.text(
          'Result received → alert started (app-side / post-inference)',
        ),
        findsOneWidget,
      );
      // No fabricated observed latency is rendered for empty distributions.
      expect(find.textContaining('p50'), findsNothing);
      expect(find.textContaining('max 0'), findsNothing);
      expect(find.textContaining('n 0'), findsNothing);
    });

    testWidgets('populated alert intervals render p50, p95, max, and count', (
      tester,
    ) async {
      await pumpLogsScreen(tester, telemetry: buildTelemetry(populated: true));

      // Two intervals have one sample, two aggregate two records.
      expect(find.textContaining('n 1'), findsNWidgets(2));
      expect(
        find.text('p50 5.0 ms · p95 5.0 ms · max 5.0 ms · n 1'),
        findsOneWidget,
      );
      expect(
        find.text('p50 30.0 ms · p95 30.0 ms · max 30.0 ms · n 1'),
        findsOneWidget,
      );
      expect(
        find.text('p50 25.0 ms · p95 40.0 ms · max 40.0 ms · n 2'),
        findsOneWidget,
      );
      expect(
        find.text('p50 20.0 ms · p95 30.0 ms · max 30.0 ms · n 2'),
        findsOneWidget,
      );
      // Every interval now belongs to the single engine.
      expect(find.text('No samples'), findsNothing);
    });

    testWidgets(
      'open alert latency section refreshes after the publish window',
      (tester) async {
        final telemetry = buildTelemetry();
        await pumpLogsScreen(tester, telemetry: telemetry);

        // The section is already open and truthfully empty.
        expect(find.text('No samples'), findsNWidgets(5));
        expect(find.text('Rejected: lowConfidence'), findsNothing);

        // The counter snapshot is authoritative immediately, but the open UI
        // only sees it once the bounded trailing publication window elapses.
        telemetry.recordAlertCounters(
          const AlertCounters(
            dropped: 7,
            rejectedByReason: {'lowConfidence': 3},
          ),
        );
        expect(telemetry.alertCounters.dropped, 7);
        expect(find.text('7'), findsNothing);

        await tester.pump(const Duration(milliseconds: 250));

        expect(find.text('7'), findsOneWidget);
        expect(find.text('Rejected: lowConfidence'), findsOneWidget);
        expect(find.text('3'), findsOneWidget);

        // A later lifecycle delta must also refresh the open distributions.
        final analysis = DateTime.utc(2026, 1, 1, 12, 0, 0);
        telemetry.recordAlertLifecycle(
          AlertLifecycleRecord(
            origin: AlertOrigin.detection,
            engine: InferenceEngine.ultralytics,
            requestedAt: analysis,
            submittedAt: analysis.add(const Duration(milliseconds: 20)),
            alertStartedAt: analysis.add(const Duration(milliseconds: 50)),
            terminalAt: analysis.add(const Duration(seconds: 1)),
            terminalState: AlertTerminalState.completed,
            terminalCause: null,
            hadStarted: true,
            reconciledAt: analysis.add(const Duration(seconds: 1)),
            frameNumber: 9,
            resultReceivedAt: analysis,
            detectionAcceptedAt: analysis.add(const Duration(milliseconds: 10)),
          ),
        );
        expect(find.textContaining('n 1'), findsNothing);

        await tester.pump();

        expect(
          find.text('p50 10.0 ms · p95 10.0 ms · max 10.0 ms · n 1'),
          findsOneWidget,
        );
      },
    );

    testWidgets('scheduler health renders required counters and reasons', (
      tester,
    ) async {
      await pumpLogsScreen(tester, telemetry: buildTelemetry(populated: true));

      expect(find.text('Dropped'), findsOneWidget);
      expect(find.text('Cancelled before start'), findsOneWidget);
      expect(find.text('Cancelled after start'), findsOneWidget);
      expect(find.text('Failed before start'), findsOneWidget);
      expect(find.text('Failed after start'), findsOneWidget);
      expect(find.text('Reconciliation timeout'), findsOneWidget);
      expect(find.text('Watchdog recovery'), findsOneWidget);
      expect(find.text('Quiet-period cap reached'), findsOneWidget);
      expect(find.text('Recovery failed'), findsOneWidget);
      expect(find.text('Quarantined callback'), findsOneWidget);
      expect(find.text('Late callback ignored'), findsOneWidget);
      expect(find.text('Callback order violation'), findsOneWidget);
      expect(find.text('Preemption requested'), findsOneWidget);
      expect(find.text('Confirmed preempted'), findsOneWidget);
      expect(find.text('Superseded (all alert types)'), findsOneWidget);
      expect(find.text('Muted (all alert types)'), findsOneWidget);
      expect(find.text('Stale decision'), findsOneWidget);
      expect(find.text('Rejected after recovery'), findsOneWidget);
      expect(find.text('Rejected: lowConfidence'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
    });

    testWidgets('alert latency group exposes accessible semantic labels', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      try {
        await pumpLogsScreen(
          tester,
          telemetry: buildTelemetry(populated: true),
        );

        expect(
          find.semantics
              .byLabel(RegExp(r'^Alert latency and scheduler health'))
              .evaluate(),
          isNotEmpty,
        );
        expect(
          find.semantics
              .byLabel(RegExp('app-side / post-inference'))
              .evaluate(),
          isNotEmpty,
        );
      } finally {
        handle.dispose();
      }
    });
  });

  group('Charts populated and empty states', () {
    testWidgets('empty charts show the No data available yet placeholder', (
      tester,
    ) async {
      await pumpLogsScreen(tester, telemetry: buildTelemetry());
      await selectTab(tester, 'Charts');

      // The rendered placeholder text is 'No data available yet' (the trailing
      // period exists only in the chart's semantic summary label).
      expect(find.text('No data available yet'), findsNWidgets(3));
    });

    testWidgets('empty charts expose the semantic no-data summary', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      try {
        await pumpLogsScreen(tester, telemetry: buildTelemetry());
        await selectTab(tester, 'Charts');

        expect(
          find.semantics.byLabel(RegExp(r'No data available yet\.')).evaluate(),
          isNotEmpty,
        );
      } finally {
        handle.dispose();
      }
    });

    testWidgets('populated charts render without the empty placeholder', (
      tester,
    ) async {
      await pumpLogsScreen(tester, telemetry: buildTelemetry(populated: true));
      await selectTab(tester, 'Charts');

      expect(find.text('No data available yet'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('Logs populated and empty states', () {
    testWidgets('empty logs show the centered empty state', (tester) async {
      await pumpLogsScreen(tester, telemetry: buildTelemetry());
      await selectTab(tester, 'Logs');

      expect(find.text('No detections recorded yet.'), findsOneWidget);
    });

    testWidgets('populated logs render a newest-first row', (tester) async {
      await pumpLogsScreen(tester, telemetry: buildTelemetry(populated: true));
      await selectTab(tester, 'Logs');

      expect(find.text('No detections recorded yet.'), findsNothing);
      // Row title: label — confidence percentage.
      expect(find.text('person — 82%'), findsOneWidget);
      // Row subtitle: engine · position · latency.
      expect(
        find.textContaining('Ultralytics · center · 120 ms'),
        findsOneWidget,
      );
    });
  });

  group('export actions', () {
    testWidgets('both export actions are present and enabled', (tester) async {
      await pumpLogsScreen(tester, telemetry: buildTelemetry());

      expect(find.text('Save JSON export'), findsOneWidget);
      expect(find.text('Save CSV export'), findsOneWidget);
      expect(find.text('Saving export…'), findsNothing);
    });

    testWidgets('busy guard disables both actions and shows Saving export…', (
      tester,
    ) async {
      final completer = Completer<void>();
      final exporter = _FakeExportService(completer: completer);
      await pumpLogsScreen(
        tester,
        telemetry: buildTelemetry(),
        exportService: exporter,
      );

      await tester.tap(find.text('Save JSON export'));
      await tester.pump();

      // While the write is in flight both actions are disabled and the busy
      // text is visible.
      expect(find.text('Saving export…'), findsOneWidget);
      final jsonButton = tester.widget<ElevatedButton>(
        find.ancestor(
          of: find.text('Save JSON export'),
          matching: find.byType(ElevatedButton),
        ),
      );
      final csvButton = tester.widget<ElevatedButton>(
        find.ancestor(
          of: find.text('Save CSV export'),
          matching: find.byType(ElevatedButton),
        ),
      );
      expect(jsonButton.onPressed, isNull);
      expect(csvButton.onPressed, isNull);

      // A second tap while busy must not start another write.
      await tester.tap(find.text('Save CSV export'), warnIfMissed: false);
      await tester.pump();
      expect(exporter.csvWrites, 0);

      completer.complete();
      await tester.pumpAndSettle();
      expect(find.text('Saving export…'), findsNothing);
    });

    testWidgets('success shows the exported filename in a SnackBar', (
      tester,
    ) async {
      final exporter = _FakeExportService();
      await pumpLogsScreen(
        tester,
        telemetry: buildTelemetry(),
        exportService: exporter,
      );

      await tester.tap(find.text('Save JSON export'));
      await tester.pumpAndSettle();

      expect(exporter.jsonWrites, 1);
      expect(
        find.text('Export saved: 20260101120000-telemetry.json'),
        findsOneWidget,
      );
    });

    testWidgets('failure shows the exact retry message', (tester) async {
      final exporter = _FakeExportService(throwOnWrite: true);
      await pumpLogsScreen(
        tester,
        telemetry: buildTelemetry(),
        exportService: exporter,
      );

      await tester.tap(find.text('Save CSV export'));
      await tester.pumpAndSettle();

      expect(exporter.csvWrites, 1);
      expect(
        find.text('Export could not be saved. Try again.'),
        findsOneWidget,
      );
    });
  });

  group('correction reports', () {
    testWidgets('empty corrections show the exact empty text', (tester) async {
      await pumpLogsScreen(
        tester,
        telemetry: buildTelemetry(),
        corrections: buildCorrections(),
      );

      expect(
        find.text('No correction reports have been recorded in this session.'),
        findsOneWidget,
      );
    });

    testWidgets('populated corrections render the record details', (
      tester,
    ) async {
      await pumpLogsScreen(
        tester,
        telemetry: buildTelemetry(),
        corrections: buildCorrections(populated: true),
      );

      // Detection label, feedback, corrected label, engine, and threshold.
      expect(
        find.textContaining('person: Incorrect as bicycle'),
        findsOneWidget,
      );
      expect(find.textContaining('Ultralytics'), findsWidgets);
      expect(find.textContaining('threshold 0.25'), findsOneWidget);
    });

    testWidgets('correction group exposes the record-count semantic label', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      try {
        await pumpLogsScreen(
          tester,
          telemetry: buildTelemetry(),
          corrections: buildCorrections(populated: true),
        );

        // The group label carries the record count; the child text is merged
        // into the same node, so match the label as a prefix.
        expect(
          find.semantics
              .byLabel(RegExp(r'^Correction reports, 1 recorded'))
              .evaluate(),
          isNotEmpty,
        );
      } finally {
        handle.dispose();
      }
    });
  });

  group('unavailable metrics', () {
    testWidgets('Model Evaluation Metrics and Usability are explicit', (
      tester,
    ) async {
      await pumpLogsScreen(tester, telemetry: buildTelemetry());

      expect(find.text('Model Evaluation Metrics'), findsOneWidget);
      expect(find.text('Usability (SUS)'), findsOneWidget);
      // Preserved reasons.
      expect(
        find.textContaining(
          'Accuracy, Precision, Recall, F1, and mAP are not shown because '
          'they require ground-truth labels (offline evaluation)',
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining(
          'SUS is collected through a post-test questionnaire',
        ),
        findsOneWidget,
      );
    });

    testWidgets('confidence is never presented as accuracy', (tester) async {
      await pumpLogsScreen(tester, telemetry: buildTelemetry(populated: true));

      // The confidence metric is explicitly labeled as confidence.
      expect(find.text('Avg confidence'), findsOneWidget);
      // No fabricated accuracy metric value is rendered.
      expect(find.textContaining('Accuracy:'), findsNothing);
      expect(find.textContaining('accuracy:'), findsNothing);
    });
  });

  group('Logs priority semantics', () {
    testWidgets('rows expose High/Medium/Low priority wording via semantics', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      try {
        await pumpLogsScreen(
          tester,
          telemetry: buildTelemetry(populated: true),
        );
        await selectTab(tester, 'Logs');

        // The priority dot is decorative; the wording is exposed as a semantic
        // label so priority is never conveyed by color alone. The ListTile
        // merges its subtree, so match the wording within the merged label.
        expect(
          find.semantics.byLabel(RegExp('High priority')).evaluate(),
          isNotEmpty,
        );
      } finally {
        handle.dispose();
      }
    });
  });

  group('large text layout', () {
    testWidgets('Alert Latency has no overflow at 200 percent text scale', (
      tester,
    ) async {
      // The tall default surface builds the whole Overview, including the
      // counter rows below the fold on a phone-sized viewport.
      await pumpLogsScreen(
        tester,
        telemetry: buildTelemetry(populated: true),
        textScale: 2.0,
      );
      expect(find.text('Alert Latency'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Overview has no overflow at 200 percent text scale', (
      tester,
    ) async {
      await pumpLogsScreen(
        tester,
        telemetry: buildTelemetry(populated: true),
        corrections: buildCorrections(populated: true),
        textScale: 2.0,
        size: const Size(390 * 3, 844 * 3),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('Charts has no overflow at 200 percent text scale', (
      tester,
    ) async {
      await pumpLogsScreen(
        tester,
        telemetry: buildTelemetry(populated: true),
        textScale: 2.0,
        size: const Size(390 * 3, 844 * 3),
      );
      await selectTab(tester, 'Charts');
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('Logs has no overflow at 200 percent text scale', (
      tester,
    ) async {
      await pumpLogsScreen(
        tester,
        telemetry: buildTelemetry(populated: true),
        textScale: 2.0,
        size: const Size(390 * 3, 844 * 3),
      );
      await selectTab(tester, 'Logs');
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });
}
