import 'dart:ui';

import 'package:eyecue_flutter/models/alert_lifecycle.dart';
import 'package:eyecue_flutter/models/detection.dart';
import 'package:eyecue_flutter/models/detection_info.dart';
import 'package:eyecue_flutter/models/app_settings.dart';
import 'package:eyecue_flutter/services/spatial_analysis_service.dart';
import 'package:eyecue_flutter/services/telemetry_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late DateTime now;
  late TelemetryService telemetry;

  setUp(() {
    now = DateTime(2026, 1, 1, 12, 0, 0);
    telemetry = TelemetryService(clock: () => now);
    addTearDown(telemetry.dispose);
  });

  DetectionInfo detInfo(String label, int classId) {
    return SpatialAnalysisService.analyze(
      Detection(
        classId: classId,
        label: label,
        confidence: 0.8,
        box: const Rect.fromLTWH(0.1, 0.1, 0.2, 0.3),
      ),
    );
  }

  test('session start and duration are tracked', () {
    telemetry.startSession();
    now = now.add(const Duration(seconds: 65));
    expect(telemetry.sessionDuration.inSeconds, 65);
  });

  test('records detections and counts high-priority alerts', () {
    telemetry.recordDetection(
      detInfo('person', 0),
      30,
      engine: InferenceEngine.custom,
    );
    telemetry.recordDetection(
      detInfo('car', 2),
      32,
      engine: InferenceEngine.custom,
    );
    telemetry.recordDetection(
      detInfo('toothbrush', 79),
      31,
      engine: InferenceEngine.custom,
    );
    expect(telemetry.totalDetections, 3);
    expect(telemetry.highPriorityAlerts, 2);
  });

  test('computes average latency and FPS from samples', () {
    telemetry.recordSample(
      latencyMs: 100,
      inferenceFps: 10,
      objectCount: 1,
      engine: InferenceEngine.custom,
    );
    telemetry.recordSample(
      latencyMs: 200,
      inferenceFps: 5,
      objectCount: 2,
      engine: InferenceEngine.custom,
    );
    expect(telemetry.framesProcessed, 2);
    expect(telemetry.averageLatencyMs, 150);
    expect(telemetry.averageInferenceFps, 7.5);
  });

  test('detection frequency buckets per minute', () {
    telemetry.recordDetection(
      detInfo('person', 0),
      30,
      engine: InferenceEngine.custom,
    );
    now = now.add(const Duration(seconds: 30));
    telemetry.recordDetection(
      detInfo('car', 2),
      30,
      engine: InferenceEngine.custom,
    );
    now = now.add(const Duration(minutes: 1, seconds: 5));
    telemetry.recordDetection(
      detInfo('bus', 5),
      30,
      engine: InferenceEngine.custom,
    );

    final buckets = telemetry.detectionFrequencyByMinute();
    expect(buckets, [2, 1]);
  });

  test('empty service reports zeroes and no buckets', () {
    expect(telemetry.totalDetections, 0);
    expect(telemetry.averageLatencyMs, 0);
    expect(telemetry.detectionFrequencyByMinute(), isEmpty);
  });

  group('alert lifecycle', () {
    AlertLifecycleRecord alert({
      AlertOrigin origin = AlertOrigin.detection,
      InferenceEngine? engine = InferenceEngine.custom,
      DateTime? requestedAt,
      DateTime? submittedAt,
      DateTime? startedAt,
      DateTime? terminalAt,
    }) {
      final submitted = submittedAt ?? now;
      final terminal = terminalAt ?? now.add(const Duration(seconds: 1));
      return AlertLifecycleRecord(
        origin: origin,
        engine: engine,
        requestedAt: requestedAt ?? submitted,
        submittedAt: submitted,
        alertStartedAt: startedAt,
        terminalAt: terminal,
        terminalState: AlertTerminalState.completed,
        terminalCause: null,
        hadStarted: startedAt != null,
        reconciledAt: terminal,
      );
    }

    test('keeps only the newest 500 lifecycle records', () {
      for (var i = 0; i < 520; i++) {
        final submittedAt = now.add(Duration(milliseconds: i));
        telemetry.recordAlertLifecycle(alert(submittedAt: submittedAt));
      }
      expect(telemetry.alertRecords, hasLength(500));
      expect(
        telemetry.alertRecords.first.submittedAt,
        now.add(const Duration(milliseconds: 20)),
      );
      expect(
        telemetry.alertRecords.last.submittedAt,
        now.add(const Duration(milliseconds: 519)),
      );
    });

    test('nearest-rank percentiles, max, and count', () {
      final summary = AlertLatencySummary.fromDurations(
        InferenceEngine.custom,
        [10, 20, 30, 40],
      );
      expect(summary.sampleCount, 4);
      expect(summary.p50Ms, 20);
      expect(summary.p95Ms, 40);
      expect(summary.maxMs, 40);

      final single = AlertLatencySummary.fromDurations(InferenceEngine.custom, [
        0,
      ]);
      expect(single.p50Ms, 0);
      expect(single.p95Ms, 0);

      final empty = AlertLatencySummary.fromDurations(
        InferenceEngine.ultralytics,
        const [],
      );
      expect(empty.sampleCount, 0);
      expect(empty.maxMs, 0);
    });

    test('engine summaries filter origin, engine, and invalid intervals', () {
      final base = now.add(const Duration(seconds: 10));
      telemetry.recordAlertLifecycle(
        alert(
          submittedAt: base,
          startedAt: base.add(const Duration(milliseconds: 100)),
        ),
      );
      telemetry.recordAlertLifecycle(
        alert(
          engine: InferenceEngine.ultralytics,
          submittedAt: base,
          startedAt: base.add(const Duration(milliseconds: 40)),
        ),
      );
      // Not detection-origin: never enters an engine summary.
      telemetry.recordAlertLifecycle(
        alert(
          origin: AlertOrigin.wayfinding,
          engine: null,
          submittedAt: base,
          startedAt: base.add(const Duration(milliseconds: 10)),
        ),
      );
      // Detection-origin but engine-null.
      telemetry.recordAlertLifecycle(
        alert(
          engine: null,
          submittedAt: base,
          startedAt: base.add(const Duration(milliseconds: 10)),
        ),
      );
      // Never started.
      telemetry.recordAlertLifecycle(alert(submittedAt: base));
      // Negative interval: excluded, never displayed.
      telemetry.recordAlertLifecycle(
        alert(
          submittedAt: base,
          startedAt: base.subtract(const Duration(milliseconds: 5)),
        ),
      );

      final custom = telemetry.alertSubmittedToStartedSummary(
        InferenceEngine.custom,
      );
      expect(custom.sampleCount, 1);
      expect(custom.p50Ms, 100);
      expect(custom.p95Ms, 100);

      final ultralytics = telemetry.alertSubmittedToStartedSummary(
        InferenceEngine.ultralytics,
      );
      expect(ultralytics.sampleCount, 1);
      expect(ultralytics.maxMs, 40);
    });

    test('counter snapshots replace instead of accumulating', () {
      telemetry.recordAlertCounters(const AlertCounters(dropped: 2, muted: 1));
      telemetry.recordAlertCounters(const AlertCounters(dropped: 2, muted: 1));
      expect(telemetry.alertCounters.dropped, 2);
      expect(telemetry.alertCounters.muted, 1);

      telemetry.recordAlertCounters(const AlertCounters(dropped: 5));
      expect(telemetry.alertCounters.dropped, 5);
      expect(telemetry.alertCounters.muted, 0);
    });

    test('counter publication is bounded to one trailing window', () async {
      // Own instance so no timer from another test can deliver this callback.
      final local = TelemetryService(clock: () => now);
      addTearDown(local.dispose);
      final seen = <int>[];
      local.addListener(() => seen.add(local.alertCounters.muted));

      local.recordAlertCounters(const AlertCounters(muted: 1));
      expect(seen, isEmpty);
      expect(local.alertCounters.muted, 1);

      // Separate event-loop turns inside the same window must not publish.
      await pumpEventQueue();
      local.recordAlertCounters(const AlertCounters(muted: 2));
      local.recordAlertCounters(const AlertCounters(muted: 3));
      expect(local.alertCounters.muted, 3);
      await pumpEventQueue();
      expect(seen, isEmpty);

      // Exactly one trailing publication, after the 250 ms window, delivering
      // the latest snapshot.
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(seen, [3]);
    });

    test('dispose cancels a pending counter publication', () async {
      var notifications = 0;
      final local = TelemetryService(clock: () => now);
      local.addListener(() => notifications++);
      local.recordAlertCounters(const AlertCounters(muted: 1));
      local.dispose();

      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(notifications, 0);
    });
  });

  test('keeps engine summaries separate', () {
    telemetry.recordSample(
      latencyMs: 150,
      inferenceFps: 6,
      objectCount: 0,
      engine: InferenceEngine.custom,
    );
    telemetry.recordSample(
      latencyMs: 30,
      inferenceFps: 15,
      objectCount: 1,
      engine: InferenceEngine.ultralytics,
    );

    final custom = telemetry.summaryFor(InferenceEngine.custom);
    final ultralytics = telemetry.summaryFor(InferenceEngine.ultralytics);
    expect(custom.averageLatencyMs, 150);
    expect(custom.averageInferenceFps, 6);
    expect(ultralytics.averageLatencyMs, 30);
    expect(ultralytics.averageInferenceFps, 15);
  });
}
