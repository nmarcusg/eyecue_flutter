import 'dart:async';
import 'dart:io';

import 'package:eyecue_flutter/models/alert_lifecycle.dart';
import 'package:eyecue_flutter/models/app_settings.dart';
import 'package:eyecue_flutter/models/detection.dart';
import 'package:eyecue_flutter/models/detection_correction.dart';
import 'package:eyecue_flutter/models/detection_info.dart';
import 'package:eyecue_flutter/models/detector_model.dart';
import 'package:eyecue_flutter/screens/logs_reports_screen.dart';
import 'package:eyecue_flutter/services/correction_service.dart';
import 'package:eyecue_flutter/services/research_session_service.dart';
import 'package:eyecue_flutter/services/telemetry_export_service.dart';
import 'package:eyecue_flutter/services/telemetry_service.dart';
import 'package:eyecue_flutter/services/telemetry_upload_service.dart';
import 'package:eyecue_flutter/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show SystemUiOverlayStyle;
import 'package:flutter_test/flutter_test.dart';

/// A well-formed study upload token: 44 token-safe characters, the shape a
/// researcher pastes into the manual upload dialog.
const String screenUploadToken = 'q3Yd0n4N0m8Lw2Xc9Vb6Tz1Rf5Jk7Hp0Sg4Da2Em6Ui8';

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
    required TelemetrySource telemetry,
    AppSettings? settings,
    Directory? directory,
    String stemSuffix = '',
  }) async {
    jsonWrites++;
    if (completer != null) await completer!.future;
    if (throwOnWrite) throw const FileSystemException('write failed');
    return File('/tmp/20260101120000-telemetry.json');
  }

  @override
  Future<File> writeCsv({
    required TelemetrySource telemetry,
    AppSettings? settings,
    Directory? directory,
    String stemSuffix = '',
  }) async {
    csvWrites++;
    if (completer != null) await completer!.future;
    if (throwOnWrite) throw const FileSystemException('write failed');
    return File('/tmp/20260101120000-telemetry.csv');
  }
}

/// A [TelemetryUploadService] that answers with one fixed result, so the
/// screen's duplicate-versus-success message branch runs without a network.
class _FakeUploadService extends TelemetryUploadService {
  _FakeUploadService(this.result);

  final TelemetryUploadResult result;
  int uploads = 0;

  /// What the dialog handed over, so a test can prove the token reached the
  /// service in memory without ever reaching the screen.
  ResearchSessionMetadata? lastMetadata;

  @override
  bool get isConfigured => true;

  @override
  Future<TelemetryUploadResult> upload({
    required TelemetrySource telemetry,
    required ResearchSessionMetadata metadata,
    AppSettings? settings,
  }) async {
    uploads++;
    lastMetadata = metadata;
    return result;
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
  TelemetryUploadService? uploadService,
  ResearchSessionService? researchSessions,
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
          uploadService: uploadService,
          researchSessions: researchSessions,
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

/// Scrolls the Overview list until [finder] is built and visible.
///
/// The Overview is a lazy ListView, so sections below the viewport are not
/// built until the list is scrolled to them.
Future<void> scrollOverviewTo(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    300,
    scrollable: find
        .descendant(
          of: find.byType(ListView),
          matching: find.byType(Scrollable),
        )
        .first,
  );
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

  group('inference cadence block', () {
    testWidgets('empty telemetry renders the no-sample note', (tester) async {
      await pumpLogsScreen(tester, telemetry: buildTelemetry());

      expect(find.text('Inference Cadence'), findsOneWidget);
      expect(find.text('No inference sample recorded yet.'), findsOneWidget);
    });

    testWidgets('a sample without cadence values renders unknown, never zero', (
      tester,
    ) async {
      await pumpLogsScreen(tester, telemetry: buildTelemetry(populated: true));

      expect(find.text('Requested detector rate'), findsOneWidget);
      // No cadence data at all is unknown; Automatic needs its own flag.
      expect(find.text('Automatic'), findsNothing);
      expect(find.text('Effective detector rate'), findsOneWidget);
      expect(find.text('uncapped'), findsOneWidget);
      // Requested detector, both depth rates, observed rate, latency, status.
      expect(find.text('unknown'), findsNWidgets(6));
      expect(find.text('0 Hz'), findsNothing);
      expect(find.text('Low power clamp'), findsNothing);
      expect(find.text('Source limited'), findsNothing);
    });

    testWidgets('automatic detection with no depth cadence never shows 0 Hz', (
      tester,
    ) async {
      final telemetry = buildTelemetry();
      telemetry.recordSample(
        latencyMs: 100,
        inferenceFps: 5,
        objectCount: 0,
        engine: InferenceEngine.ultralytics,
        detectionCadenceAutomatic: true,
      );
      await pumpLogsScreen(tester, telemetry: telemetry);

      expect(find.text('Automatic'), findsOneWidget);
      // Requested/effective depth rate plus the unobserved depth fields.
      expect(find.text('unknown'), findsNWidgets(5));
      expect(find.text('0 Hz'), findsNothing);
    });

    testWidgets('recorded cadence renders rates, status, and qualifiers', (
      tester,
    ) async {
      final telemetry = buildTelemetry();
      telemetry.recordSample(
        latencyMs: 100,
        inferenceFps: 5,
        objectCount: 1,
        engine: InferenceEngine.ultralytics,
        requestedDetectionHz: 8,
        effectiveDetectionHz: 5,
        requestedDepthHz: 4,
        effectiveDepthHz: 2,
        depthObservedHz: 1.5,
        depthLatencyMs: 210,
        depthStatus: 'gpu',
        lowPowerClamped: true,
        sourceLimited: true,
      );
      await pumpLogsScreen(tester, telemetry: telemetry);

      expect(find.text('8 Hz'), findsOneWidget);
      expect(find.text('5 Hz'), findsOneWidget);
      expect(find.text('4 Hz'), findsOneWidget);
      expect(find.text('2 Hz'), findsOneWidget);
      expect(find.text('1.5 Hz'), findsOneWidget);
      expect(find.text('210 ms'), findsOneWidget);
      expect(find.text('gpu'), findsOneWidget);
      expect(find.text('Low power clamp'), findsOneWidget);
      expect(find.text('Source limited'), findsOneWidget);
      expect(find.text('applied'), findsNWidgets(2));
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
      // The session bar sits above this section, so reveal it before tapping.
      await scrollOverviewTo(tester, find.text('Save JSON export'));
      await tester.ensureVisible(find.text('Save JSON export'));
      await tester.pumpAndSettle();

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
      await scrollOverviewTo(tester, find.text('Save JSON export'));
      await tester.ensureVisible(find.text('Save JSON export'));
      await tester.pumpAndSettle();

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
      await scrollOverviewTo(tester, find.text('Save CSV export'));
      await tester.ensureVisible(find.text('Save CSV export'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Save CSV export'));
      await tester.pumpAndSettle();

      expect(exporter.csvWrites, 1);
      expect(
        find.text('Export could not be saved. Try again.'),
        findsOneWidget,
      );
    });
  });

  group('upload messages', () {
    Future<void> uploadOnce(
      WidgetTester tester,
      TelemetryUploadService fake, {
      TelemetryService? telemetry,
      TelemetryExportService? exportService,
    }) async {
      await pumpLogsScreen(
        tester,
        telemetry: telemetry ?? buildTelemetry(),
        uploadService: fake,
        exportService: exportService,
      );
      final button = find.text('Upload session to research database');
      // The card is built lazily below the viewport; scrolling alone leaves it
      // off-screen, so it is revealed before the tap.
      await scrollOverviewTo(tester, button);
      await tester.ensureVisible(button);
      await tester.pumpAndSettle();
      await tester.tap(button);
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).at(0), 'P-001');
      await tester.enterText(
        find.byType(TextField).at(1),
        'indoor-obstacle-course',
      );
      await tester.enterText(find.byType(TextField).at(2), screenUploadToken);
      await tester.tap(find.text('Confirm upload'));
      await tester.pumpAndSettle();
    }

    testWidgets('the confirm dialog states the one-upload-per-run rule', (
      tester,
    ) async {
      // The rule has to be readable *before* the researcher commits, not only
      // in the duplicate message after the second attempt.
      await pumpLogsScreen(
        tester,
        telemetry: buildTelemetry(),
        uploadService: _FakeUploadService(
          const TelemetryUploadResult.success(),
        ),
      );
      final button = find.text('Upload session to research database');
      await scrollOverviewTo(tester, button);
      await tester.ensureVisible(button);
      await tester.pumpAndSettle();
      await tester.tap(button);
      await tester.pumpAndSettle();

      // Scoped to the dialog: a screen-wide match would not prove the sentence
      // is part of what the researcher is confirming.
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.textContaining(
            'Each participant and trial is stored once: re-sending the same '
            'trial is deduplicated by the research server, and later '
            'recording belongs to a new trial.',
          ),
        ),
        findsOneWidget,
      );
    });

    testWidgets('a duplicate upload says so instead of reporting success', (
      tester,
    ) async {
      final fake = _FakeUploadService(
        const TelemetryUploadResult.alreadyUploaded(),
      );

      await uploadOnce(tester, fake);

      expect(fake.uploads, 1);
      expect(find.textContaining('already uploaded earlier'), findsOneWidget);
      expect(
        find.text('Session uploaded to the research database.'),
        findsNothing,
      );

      // A duplicate is success-like: the row exists in the database. It must
      // not be painted with the SnackBar's error container, and it must stay a
      // polite live region so a screen reader announces it without alert tone.
      final snackBar = tester.widget<SnackBar>(find.byType(SnackBar));
      expect(
        snackBar.backgroundColor,
        isNull,
        reason: 'a duplicate is not an error and must not be error-coloured',
      );
      final liveRegions = tester
          .widgetList<Semantics>(find.byType(Semantics))
          .where(
            (widget) => (widget.properties.label ?? '').contains(
              'already uploaded earlier',
            ),
          )
          .toList();
      expect(liveRegions, hasLength(1));
      expect(liveRegions.single.properties.liveRegion, isTrue);
    });

    testWidgets('a stored upload keeps the plain success text', (tester) async {
      final fake = _FakeUploadService(const TelemetryUploadResult.success());

      await uploadOnce(tester, fake);

      expect(fake.uploads, 1);
      expect(
        find.text('Session uploaded to the research database.'),
        findsOneWidget,
      );
      expect(find.textContaining('already uploaded earlier'), findsNothing);
    });

    testWidgets('the dialog requires a study upload token', (tester) async {
      final fake = _FakeUploadService(const TelemetryUploadResult.success());
      await pumpLogsScreen(
        tester,
        telemetry: buildTelemetry(),
        uploadService: fake,
      );
      final button = find.text('Upload session to research database');
      await scrollOverviewTo(tester, button);
      await tester.ensureVisible(button);
      await tester.pumpAndSettle();
      await tester.tap(button);
      await tester.pumpAndSettle();

      // The field is part of what the researcher confirms, and says it is
      // required before the upload button becomes usable.
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Study upload token'),
        ),
        findsOneWidget,
      );

      Future<void> confirm() async {
        await tester.tap(find.text('Confirm upload'));
        await tester.pumpAndSettle();
      }

      await tester.enterText(find.byType(TextField).at(0), 'P-001');
      await tester.enterText(find.byType(TextField).at(1), 'lab');

      // No token: the dialog stays open and nothing is sent.
      await confirm();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(fake.uploads, 0);

      // A padded token is refused as well: the shape is checked, not repaired.
      await tester.enterText(
        find.byType(TextField).at(2),
        ' $screenUploadToken ',
      );
      await confirm();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(fake.uploads, 0);
      // The field says why instead of the button doing nothing, and it says it
      // in its own words: nothing was sent, so the server's sentence would
      // misdescribe this refusal.
      expect(
        find.text(TelemetryUploadResult.tokenShapeMessage),
        findsOneWidget,
      );
      expect(
        find.text(TelemetryUploadResult.invalidUploadTokenMessage),
        findsNothing,
      );

      // A well-formed token closes the dialog and reaches the service.
      await tester.enterText(find.byType(TextField).at(2), screenUploadToken);
      await confirm();
      expect(find.byType(AlertDialog), findsNothing);
      expect(fake.uploads, 1);
    });

    testWidgets('the token is handed over in memory and never rendered', (
      tester,
    ) async {
      final fake = _FakeUploadService(const TelemetryUploadResult.success());
      final exporter = _FakeExportService();

      await uploadOnce(tester, fake, exportService: exporter);

      // It reached the service, so the dialog really passed it on…
      expect(fake.lastMetadata!.uploadToken, screenUploadToken);
      // …and it is nowhere the user can see or keep.
      expect(find.textContaining(screenUploadToken), findsNothing);
      expect(find.textContaining('q3Yd0n4N'), findsNothing);
      // The upload path writes no file, so the token cannot reach an export.
      expect(exporter.jsonWrites, 0);
      expect(exporter.csvWrites, 0);
    });

    testWidgets('a token refusal is explained without echoing the token', (
      tester,
    ) async {
      final service = TelemetryUploadService(
        configuration: const TelemetryUploadConfiguration(
          ingestUrl:
              'https://example.supabase.co/functions/v1/ingest-telemetry',
          publishableKey: 'sb_publishable_secret',
        ),
        debugMode: false,
        exportService: _FakeExportService(),
        sender: (_) async => const TelemetryUploadResponse(
          403,
          '{"error":"upload_token_exhausted"}',
        ),
      );
      final localTelemetry = buildTelemetry(populated: true);

      await uploadOnce(tester, service, telemetry: localTelemetry);

      expect(find.textContaining('no uploads left'), findsOneWidget);
      // Neither the token nor the publishable key is ever shown.
      expect(find.textContaining(screenUploadToken), findsNothing);
      expect(find.textContaining('sb_publishable_secret'), findsNothing);
      // The session survives, so a local export still recovers it.
      expect(localTelemetry.totalDetections, 1);
      expect(localTelemetry.samples, hasLength(1));
    });

    testWidgets('an insecure endpoint is explained and the session survives', (
      tester,
    ) async {
      var sends = 0;
      // A real service, so the button's enabled state and the message both come
      // from the same gate the shipped build uses: an endpoint that is present
      // but not usable — the case that used to read "not configured".
      final service = TelemetryUploadService(
        configuration: const TelemetryUploadConfiguration(
          ingestUrl: 'http://example.com/functions/v1/ingest-telemetry',
          publishableKey: 'sb_publishable_secret',
        ),
        debugMode: false,
        exportService: _FakeExportService(),
        sender: (_) async {
          sends++;
          return const TelemetryUploadResponse(201);
        },
      );
      final localTelemetry = buildTelemetry(populated: true);

      await uploadOnce(tester, service, telemetry: localTelemetry);

      expect(sends, 0, reason: 'nothing may be sent to an insecure endpoint');
      expect(find.textContaining('requires an HTTPS address'), findsOneWidget);

      // Surfaced through the existing accessible path: one polite live region.
      final liveRegions = tester
          .widgetList<Semantics>(find.byType(Semantics))
          .where(
            (widget) => (widget.properties.label ?? '').contains(
              'requires an HTTPS address',
            ),
          )
          .toList();
      expect(liveRegions, hasLength(1));
      expect(liveRegions.single.properties.liveRegion, isTrue);

      // The session is untouched, and neither the endpoint nor the key is
      // echoed back to the user.
      expect(localTelemetry.totalDetections, 1);
      expect(localTelemetry.samples, hasLength(1));
      expect(localTelemetry.alertRecords, hasLength(2));
      expect(find.textContaining('example.com'), findsNothing);
      expect(find.textContaining('sb_publishable_secret'), findsNothing);
    });
  });

  group('correction reports', () {
    testWidgets('empty corrections show the exact empty text', (tester) async {
      await pumpLogsScreen(
        tester,
        telemetry: buildTelemetry(),
        corrections: buildCorrections(),
      );
      final emptyText = find.text(
        'No correction reports have been recorded in this session.',
      );
      await scrollOverviewTo(tester, emptyText);

      expect(emptyText, findsOneWidget);
    });

    testWidgets('populated corrections render the record details', (
      tester,
    ) async {
      await pumpLogsScreen(
        tester,
        telemetry: buildTelemetry(),
        corrections: buildCorrections(populated: true),
      );
      final correctionRow = find.textContaining('person: Incorrect as bicycle');
      await scrollOverviewTo(tester, correctionRow);

      // Detection label, feedback, corrected label, engine, and threshold.
      expect(correctionRow, findsOneWidget);
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
        // The correction section is below the session bar; build it first.
        await scrollOverviewTo(
          tester,
          find.textContaining('person: Incorrect as bicycle'),
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

      // The Overview is a lazy ListView. At this viewport the notes at the end
      // of the list are outside the built extent until the list is scrolled to
      // them, so scroll instead of weakening the assertions.
      await scrollOverviewTo(tester, find.text('Usability (SUS)'));

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
      await pumpLogsScreen(
        tester,
        telemetry: buildTelemetry(populated: true),
        textScale: 2.0,
      );
      // The section sits below the built extent of the lazy list at this scale.
      await scrollOverviewTo(tester, find.text('Alert Latency'));
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

  group('detector model attribution', () {
    const builtInRef = DetectorModelRef(
      id: 'builtin',
      name: 'Built-in YOLOv8n',
      fingerprint: DetectorModel.builtInFingerprint,
      classCount: 80,
    );
    const customRef = DetectorModelRef(
      id: 'custom:0a1b2c3d4e5f',
      name: 'Obstacle Detector v2',
      fingerprint: '0a1b2c3d4e5f6071-4200',
      classCount: 12,
    );

    /// One sample per detector, in order.
    TelemetryService buildTelemetryFor(List<DetectorModelRef> refs) {
      final service = TelemetryService(
        clock: () => DateTime.utc(2026, 1, 1, 12, 0, 0),
        sessionId: 'session-models',
      );
      service.startSession();
      for (final ref in refs) {
        service.recordSample(
          latencyMs: 100,
          inferenceFps: 10,
          objectCount: 1,
          engine: InferenceEngine.ultralytics,
          detectorModel: ref,
        );
      }
      return service;
    }

    /// One sample and one detection from each of two detectors.
    TelemetryService buildTwoModelTelemetry() {
      final service = TelemetryService(
        clock: () => DateTime.utc(2026, 1, 1, 12, 0, 0),
        sessionId: 'session-models',
      );
      service.startSession();
      for (final ref in [builtInRef, customRef]) {
        service.recordSample(
          latencyMs: 100,
          inferenceFps: 10,
          objectCount: 1,
          engine: InferenceEngine.ultralytics,
          detectorModel: ref,
        );
        service.recordDetection(
          DetectionInfo(
            detection: const Detection(
              classId: 0,
              label: 'cone',
              confidence: 0.8,
              box: Rect.fromLTWH(0.1, 0.2, 0.3, 0.4),
            ),
            position: RelativePosition.center,
            priority: ObjectPriority.medium,
            proximity: ProximityBand.near,
          ),
          100,
          engine: InferenceEngine.ultralytics,
          detectorModel: ref,
        );
      }
      return service;
    }

    testWidgets('a log row names the model that produced the numbers', (
      tester,
    ) async {
      await pumpLogsScreen(tester, telemetry: buildTwoModelTelemetry());
      await selectTab(tester, 'Logs');

      expect(
        find.textContaining('Built-in YOLOv8n · Ultralytics · center · 100 ms'),
        findsOneWidget,
      );
      expect(
        find.textContaining(
          'Obstacle Detector v2 · Ultralytics · center · 100 ms',
        ),
        findsOneWidget,
      );
    });

    testWidgets('unfiltered summaries are labelled mixed-model data', (
      tester,
    ) async {
      await pumpLogsScreen(tester, telemetry: buildTwoModelTelemetry());

      // The averages above combine both detectors, and say so.
      expect(find.textContaining('Mixed-model data —'), findsOneWidget);
      // The Engine Comparison card blends the same two models, and says so on
      // its own line — not appended to the ellipsized value.
      expect(find.text('Mixed-model data'), findsOneWidget);
      expect(find.textContaining('frames —'), findsNothing);

      await selectTab(tester, 'Charts');
      expect(
        find.text('Inference Latency — Mixed-model data (300 ms benchmark)'),
        findsOneWidget,
      );
      expect(find.text('All models (mixed)'), findsOneWidget);
    });

    testWidgets('filtering to one model names it in the chart cards', (
      tester,
    ) async {
      await pumpLogsScreen(tester, telemetry: buildTwoModelTelemetry());
      await selectTab(tester, 'Charts');

      await tester.tap(find.byType(DropdownButton<String?>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Obstacle Detector v2').last);
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Inference Latency — Obstacle Detector v2 (300 ms benchmark)',
        ),
        findsOneWidget,
      );
      expect(
        find.text('Frames Per Second — Obstacle Detector v2 (15 FPS target)'),
        findsOneWidget,
      );
      expect(
        find.text('Inference Latency — Mixed-model data (300 ms benchmark)'),
        findsNothing,
      );
    });

    /// The paragraph that actually paints [text], so a test can assert on what
    /// is rendered instead of on the string a widget happens to carry.
    RenderParagraph paintedParagraph(WidgetTester tester, String text) {
      final finder = find.text(text);
      expect(finder, findsOneWidget);
      return tester.renderObject<RenderParagraph>(finder);
    }

    testWidgets('a single model is named on the engine comparison card', (
      tester,
    ) async {
      final telemetry = buildTelemetryFor(const [customRef]);
      await pumpLogsScreen(tester, telemetry: telemetry);

      expect(find.text('Obstacle Detector v2'), findsOneWidget);
      expect(find.textContaining('Mixed-model data'), findsNothing);
      expect(find.textContaining('frames —'), findsNothing);
    });

    testWidgets('the mixed-model claim is painted whole at 390 px', (
      tester,
    ) async {
      await pumpLogsScreen(
        tester,
        telemetry: buildTwoModelTelemetry(),
        size: const Size(390 * 3, 844 * 3),
      );
      await scrollOverviewTo(tester, find.text('Mixed-model data'));

      final claim = paintedParagraph(tester, 'Mixed-model data');
      expect(claim.didExceedMaxLines, isFalse);
      expect(claim.size.width, greaterThan(0));
    });

    testWidgets('a 40-character model name is painted whole at 390 px', (
      tester,
    ) async {
      // 40 characters is the longest name the importer accepts.
      const longName = DetectorModelRef(
        id: 'custom:0a1b2c3d4e5f',
        name: 'Obstacle Detector v2 corrected import r2',
        fingerprint: '0a1b2c3d4e5f6071-4200',
        classCount: 12,
      );
      await pumpLogsScreen(
        tester,
        telemetry: buildTelemetryFor(const [longName]),
        size: const Size(390 * 3, 844 * 3),
      );
      await scrollOverviewTo(tester, find.text(longName.name));

      final claim = paintedParagraph(tester, longName.name);
      expect(claim.didExceedMaxLines, isFalse);
      expect(find.textContaining('Mixed-model data'), findsNothing);
    });

    testWidgets('a renamed graph is named, not called mixed, on both surfaces', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      const renamed = DetectorModelRef(
        id: 'custom:0a1b2c3d4e5f',
        name: 'Obstacle Detector v2 fixed',
        fingerprint: '0a1b2c3d4e5f6071-4200',
        classCount: 12,
      );
      await pumpLogsScreen(
        tester,
        telemetry: buildTelemetryFor(const [customRef, renamed]),
      );
      await selectTab(tester, 'Charts');

      // One identity under two names: the card title names its current name...
      expect(
        find.text(
          'Inference Latency — Obstacle Detector v2 fixed (300 ms benchmark)',
        ),
        findsOneWidget,
      );
      // ...and the chart summaries agree with the title.
      expect(
        find.bySemanticsLabel(
          RegExp('detector model Obstacle Detector v2 fixed'),
        ),
        findsNWidgets(2),
      );
      expect(find.textContaining('Mixed-model data'), findsNothing);
      expect(find.bySemanticsLabel(RegExp('mixed-model data')), findsNothing);
      handle.dispose();
    });

    testWidgets('a stale filter draws all models and says so', (tester) async {
      final telemetry = buildTelemetryFor(const [customRef]);
      await pumpLogsScreen(tester, telemetry: telemetry);
      await selectTab(tester, 'Charts');

      await tester.tap(find.byType(DropdownButton<String?>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Obstacle Detector v2').last);
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Inference Latency — Obstacle Detector v2 (300 ms benchmark)',
        ),
        findsOneWidget,
      );

      // 402 samples is past the 400-sample cap, so the oldest row — the filtered
      // model's only sample — is evicted while its key stays selected. The
      // charts fall back to every model, and the title follows.
      for (var i = 0; i <= 400; i++) {
        telemetry.recordSample(
          latencyMs: 100,
          inferenceFps: 10,
          objectCount: 1,
          engine: InferenceEngine.ultralytics,
          detectorModel: builtInRef,
        );
      }
      await tester.pumpAndSettle();

      expect(find.text('All models (mixed)'), findsOneWidget);
      expect(
        find.text('Inference Latency — Built-in YOLOv8n (300 ms benchmark)'),
        findsOneWidget,
      );
      expect(find.textContaining('Mixed-model data'), findsNothing);
    });

    testWidgets('two graphs with one name stay distinguishable in the filter', (
      tester,
    ) async {
      const first = DetectorModelRef(
        id: 'custom:aaaaaaaaaaaa',
        name: 'Obstacle Detector v2',
        fingerprint: 'aaaaaaaaaaaa0000-4200',
        classCount: 12,
      );
      const second = DetectorModelRef(
        id: 'custom:bbbbbbbbbbbb',
        name: 'Obstacle Detector v2',
        fingerprint: 'bbbbbbbbbbbb0000-4200',
        classCount: 12,
      );
      await pumpLogsScreen(
        tester,
        telemetry: buildTelemetryFor(const [first, second]),
      );
      await selectTab(tester, 'Charts');

      await tester.tap(find.byType(DropdownButton<String?>).first);
      await tester.pumpAndSettle();
      // Same display name, different graph: the short fingerprint tells them
      // apart instead of showing two identical entries.
      expect(find.text('Obstacle Detector v2 · aaaaaaaa'), findsWidgets);
      expect(find.text('Obstacle Detector v2 · bbbbbbbb'), findsWidgets);

      await tester.tap(find.text('Obstacle Detector v2 · bbbbbbbb').last);
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Inference Latency — Obstacle Detector v2 · bbbbbbbb '
          '(300 ms benchmark)',
        ),
        findsOneWidget,
      );
    });

    testWidgets('a rename is a new filter entry, not a stale label', (
      tester,
    ) async {
      const renamed = DetectorModelRef(
        id: 'custom:0a1b2c3d4e5f',
        name: 'Obstacle Detector v2 fixed',
        fingerprint: '0a1b2c3d4e5f6071-4200',
        classCount: 12,
      );
      await pumpLogsScreen(
        tester,
        telemetry: buildTelemetryFor(const [customRef, renamed]),
      );
      await selectTab(tester, 'Charts');

      await tester.tap(find.byType(DropdownButton<String?>).first);
      await tester.pumpAndSettle();
      expect(find.text('Obstacle Detector v2'), findsWidgets);
      expect(find.text('Obstacle Detector v2 fixed'), findsWidgets);
    });

    testWidgets('the log list filters to one model but keeps the filter', (
      tester,
    ) async {
      await pumpLogsScreen(tester, telemetry: buildTwoModelTelemetry());
      await selectTab(tester, 'Logs');
      expect(find.text('cone — 80%'), findsNWidgets(2));

      await tester.tap(find.byType(DropdownButton<String?>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Built-in YOLOv8n').last);
      await tester.pumpAndSettle();

      // Only the built-in rows remain, and the model name still shows.
      expect(find.text('cone — 80%'), findsOneWidget);
      expect(
        find.textContaining('Built-in YOLOv8n · Ultralytics · center · 100 ms'),
        findsOneWidget,
      );
      expect(find.textContaining('Obstacle Detector v2 · '), findsNothing);
    });
  });

  group('research session bar', () {
    testWidgets('recording starts only after the explicit Start dialog', (
      tester,
    ) async {
      final telemetry = buildTelemetry();
      final sessions = ResearchSessionService(
        telemetry: telemetry,
        store: InMemoryResearchSessionStore(),
        clock: () => DateTime.utc(2026, 1, 1, 12, 0, 0),
      );
      await pumpLogsScreen(
        tester,
        telemetry: telemetry,
        researchSessions: sessions,
      );

      expect(find.text('Not recording'), findsOneWidget);
      expect(find.text('Pause logging'), findsNothing);
      expect(find.text('Resume logging'), findsNothing);

      await tester.tap(find.text('Start logging'));
      await tester.pumpAndSettle();

      // The confirmation names the detector that will produce the trial.
      expect(
        find.textContaining('Detector: Built-in YOLOv8n.'),
        findsOneWidget,
      );
      expect(sessions.state, isNot(ResearchSessionState.recording));

      await tester.enterText(find.byType(TextField).at(0), 'P-001');
      await tester.enterText(find.byType(TextField).at(1), 'trial-1');
      await tester.tap(find.text('Start trial'));
      await tester.pumpAndSettle();

      expect(sessions.state, ResearchSessionState.recording);
      expect(find.text('Recording'), findsOneWidget);
      expect(find.text('Pause logging'), findsOneWidget);
      expect(
        find.textContaining('Participant P-001 · trial trial-1'),
        findsOneWidget,
      );

      await tester.tap(find.text('Pause logging'));
      await tester.pumpAndSettle();
      expect(find.text('Paused'), findsOneWidget);
      expect(find.text('Resume logging'), findsOneWidget);
      expect(find.text('Finish session'), findsOneWidget);
    });

    testWidgets('a finished trial is listed with its own controls', (
      tester,
    ) async {
      final telemetry = buildTelemetry();
      final sessions = ResearchSessionService(
        telemetry: telemetry,
        store: InMemoryResearchSessionStore(),
        clock: () => DateTime.utc(2026, 1, 1, 12, 0, 0),
      );
      await sessions.start(
        participantCode: 'P-001',
        trialLabel: 'trial-1',
        detector: const DetectorModelRef(
          id: 'builtin',
          name: 'Built-in YOLOv8n',
          fingerprint: DetectorModel.builtInFingerprint,
          classCount: 80,
        ),
      );
      expect((await sessions.finish())!.saved, isTrue);

      await pumpLogsScreen(
        tester,
        telemetry: telemetry,
        researchSessions: sessions,
      );

      expect(find.text('Stored trials (1 of 20)'), findsOneWidget);
      expect(find.text('P-001 · trial-1'), findsOneWidget);
      expect(find.text('Saved on this device.'), findsOneWidget);
      expect(find.text('Upload trial'), findsOneWidget);
      expect(find.text('Export trial'), findsOneWidget);
      expect(find.text('Discard trial'), findsOneWidget);
    });

    testWidgets('the Detection Frequency chart follows the model filter', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      const builtIn = DetectorModelRef(
        id: 'builtin',
        name: 'Built-in YOLOv8n',
        fingerprint: DetectorModel.builtInFingerprint,
        classCount: 80,
      );
      const custom = DetectorModelRef(
        id: 'custom:0a1b2c3d4e5f',
        name: 'Obstacle Detector v2',
        fingerprint: '0a1b2c3d4e5f6071-4200',
        classCount: 12,
      );
      final telemetry = TelemetryService(
        clock: () => DateTime.utc(2026, 1, 1, 12, 0, 0),
        sessionId: 'session-n3',
      );
      telemetry.startSession();
      addTearDown(telemetry.dispose);
      for (final ref in [builtIn, custom, builtIn]) {
        telemetry.recordDetection(
          DetectionInfo(
            detection: const Detection(
              classId: 0,
              label: 'cone',
              confidence: 0.8,
              box: Rect.fromLTWH(0.1, 0.2, 0.3, 0.4),
            ),
            position: RelativePosition.center,
            priority: ObjectPriority.medium,
            proximity: ProximityBand.near,
          ),
          100,
          engine: InferenceEngine.ultralytics,
          detectorModel: ref,
        );
      }
      await pumpLogsScreen(tester, telemetry: telemetry);
      await selectTab(tester, 'Charts');

      // Unfiltered: every model's detections, labelled as mixed.
      expect(
        find.text('Detection Frequency — Mixed-model data'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(
          RegExp('Detection frequency chart. 3 detections'),
        ),
        findsOneWidget,
      );

      await tester.tap(find.byType(DropdownButton<String?>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Built-in YOLOv8n').last);
      await tester.pumpAndSettle();

      // Filtered: only the built-in model's detections, and the chart says so.
      expect(
        find.text('Detection Frequency — Built-in YOLOv8n'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(
          RegExp('Detection frequency chart. 2 detections'),
        ),
        findsOneWidget,
      );
      handle.dispose();
    });
  });
}
