import 'dart:ui';

import 'package:eyecue_flutter/models/alert_lifecycle.dart';
import 'package:eyecue_flutter/models/detection.dart';
import 'package:eyecue_flutter/models/detection_correction.dart';
import 'package:eyecue_flutter/models/detection_info.dart';
import 'package:eyecue_flutter/models/app_settings.dart';
import 'package:eyecue_flutter/models/detector_model.dart';
import 'package:eyecue_flutter/models/telemetry_export.dart';
import 'package:eyecue_flutter/services/spatial_analysis_service.dart';
import 'package:eyecue_flutter/services/telemetry_service.dart';
import 'package:flutter_test/flutter_test.dart';

class _TestSink implements TelemetrySink {
  int detections = 0;
  int samples = 0;

  @override
  void onDetection(TelemetryRecord record) => detections++;

  @override
  void onSample(RuntimeSample sample) => samples++;

  @override
  void onFailure(TelemetryFailureRecord record) {}

  @override
  void onFallback(EngineFallbackRecord record) {}

  @override
  void onRecovery(InferenceRecoveryRecord record) {}

  @override
  void onCorrection(DetectionCorrection correction) {}

  @override
  void onAlertLifecycle(AlertLifecycleRecord record) {}
}

class _ThrowingSink extends _TestSink {
  @override
  void onDetection(TelemetryRecord record) => throw StateError('sink failed');

  @override
  void onSample(RuntimeSample sample) => throw StateError('sink failed');
}

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
      engine: InferenceEngine.ultralytics,
    );
    telemetry.recordDetection(
      detInfo('car', 2),
      32,
      engine: InferenceEngine.ultralytics,
    );
    telemetry.recordDetection(
      detInfo('toothbrush', 79),
      31,
      engine: InferenceEngine.ultralytics,
    );
    expect(telemetry.totalDetections, 3);
    expect(telemetry.highPriorityAlerts, 2);
  });

  test(
    'throwing sinks do not starve later capture or telemetry completion',
    () {
      final first = _ThrowingSink();
      final second = _TestSink();
      var notifications = 0;
      telemetry
        ..subscribe(first)
        ..subscribe(second)
        ..addListener(() => notifications++);

      telemetry.recordDetection(
        detInfo('person', 0),
        30,
        engine: InferenceEngine.ultralytics,
      );
      telemetry.recordSample(
        latencyMs: 100,
        inferenceFps: 10,
        objectCount: 1,
        engine: InferenceEngine.ultralytics,
      );

      expect(second.detections, 1);
      expect(second.samples, 1);
      expect(telemetry.detectionCount, 1);
      expect(telemetry.highPriorityAlerts, 1);
      expect(telemetry.framesProcessed, 1);
      expect(telemetry.records, hasLength(1));
      expect(telemetry.samples, hasLength(1));
      expect(notifications, 2);
    },
  );

  test('computes average latency and FPS from samples', () {
    telemetry.recordSample(
      latencyMs: 100,
      inferenceFps: 10,
      objectCount: 1,
      engine: InferenceEngine.ultralytics,
    );
    telemetry.recordSample(
      latencyMs: 200,
      inferenceFps: 5,
      objectCount: 2,
      engine: InferenceEngine.ultralytics,
    );
    expect(telemetry.framesProcessed, 2);
    expect(telemetry.averageLatencyMs, 150);
    expect(telemetry.averageInferenceFps, 7.5);
  });

  test('stores and serializes the inference cadence configuration', () {
    telemetry.recordSample(
      latencyMs: 100,
      inferenceFps: 10,
      objectCount: 1,
      engine: InferenceEngine.ultralytics,
      requestedDetectionHz: 8,
      effectiveDetectionHz: 5,
      requestedDepthHz: 4,
      effectiveDepthHz: 2,
      depthObservedHz: 1.5,
      depthLatencyMs: 90,
      depthStatus: 'gpu',
      lowPowerClamped: true,
      sourceLimited: true,
    );

    final sample = telemetry.samples.single;
    expect(sample.requestedDetectionHz, 8);
    expect(sample.detectionCadenceAutomatic, isFalse);
    expect(sample.effectiveDetectionHz, 5);
    expect(sample.requestedDepthHz, 4);
    expect(sample.effectiveDepthHz, 2);
    expect(sample.depthObservedHz, 1.5);
    expect(sample.depthLatencyMs, 90);
    expect(sample.depthStatus, 'gpu');
    expect(sample.lowPowerClamped, isTrue);
    expect(sample.sourceLimited, isTrue);

    final json = sample.toJson();
    expect(json['requestedDetectionHz'], 8);
    expect(json['detectionCadenceAutomatic'], isFalse);
    expect(json['effectiveDetectionHz'], 5);
    expect(json['requestedDepthHz'], 4);
    expect(json['effectiveDepthHz'], 2);
    expect(json['depthObservedHz'], 1.5);
    expect(json['depthLatencyMs'], 90);
    expect(json['depthStatus'], 'gpu');
    expect(json['lowPowerClamped'], isTrue);
    expect(json['sourceLimited'], isTrue);
  });

  test('stores and serializes the detector and depth stage timings', () {
    telemetry.recordSample(
      latencyMs: 100,
      inferenceFps: 10,
      objectCount: 1,
      engine: InferenceEngine.ultralytics,
      detectorPreMs: 3.5,
      detectorInferenceMs: 28.25,
      detectorPostMs: 4.75,
      depthPreMs: 6,
      depthInferenceMs: 61,
      depthPostMs: 9,
      depthAccelerator: 'cpu',
      depthGridWidth: 96,
      depthGridHeight: 72,
      heatmapBuildMs: 11,
      depthDroppedTicks: 37,
    );

    final sample = telemetry.samples.single;
    expect(sample.detectorPreMs, 3.5);
    expect(sample.detectorInferenceMs, 28.25);
    expect(sample.detectorPostMs, 4.75);
    expect(sample.depthPreMs, 6);
    expect(sample.depthInferenceMs, 61);
    expect(sample.depthPostMs, 9);
    expect(sample.depthAccelerator, 'cpu');
    expect(sample.depthGridWidth, 96);
    expect(sample.depthGridHeight, 72);
    expect(sample.heatmapBuildMs, 11);
    expect(sample.depthDroppedTicks, 37);

    final json = sample.toJson();
    expect(json['detectorInferenceMs'], 28.25);
    expect(json['depthAccelerator'], 'cpu');
    expect(json['depthDroppedTicks'], 37);
    // `depthStatus` stays a derived status; the raw accelerator is separate.
    expect(json['depthStatus'], isNull);
    // `inferenceFps` IS the detector observed FPS (`0` = not reported, which
    // the plugin cannot distinguish from unreported), so no second key repeats
    // it, and no Dart-side depth queue exists to report a wait.
    expect(json['inferenceFps'], 10);
    expect(json.containsKey('detectorObservedFps'), isFalse);
    expect(json.containsKey('depthQueueWaitMs'), isFalse);
  });

  test('a schema-3 sample row gains no numbers when read at schema 4', () {
    final v3Row = <String, dynamic>{
      'timestamp': now.toUtc().toIso8601String(),
      'latencyMs': 100.0,
      'inferenceFps': 10.0,
      'objectCount': 1,
      'engine': 'ultralytics',
      'confidenceThreshold': 0.25,
      'depthStatus': 'gpu',
      'depthLatencyMs': 90,
    };
    final restored = TelemetryExport.fromJson({
      'schemaVersion': 3,
      'exportedAt': now.toUtc().toIso8601String(),
      'appVersion': '1.0.0+1',
      'session': {'id': 'legacy', 'start': null, 'durationMs': 0},
      'samples': [v3Row],
    });

    final row = restored.samples.single;
    for (final key in const [
      'detectorPreMs',
      'detectorInferenceMs',
      'detectorPostMs',
      'depthPreMs',
      'depthInferenceMs',
      'depthPostMs',
      'depthAccelerator',
      'depthGridWidth',
      'depthGridHeight',
      'heatmapBuildMs',
      'depthDroppedTicks',
    ]) {
      expect(row[key], isNull, reason: '$key stays unknown, never 0');
    }
    expect(row['depthStatus'], 'gpu', reason: 'the schema-3 value is intact');
    expect(restored.toJson()['samples'], [v3Row]);
  });

  test('old recordSample call sites keep automatic/unknown as null', () {
    telemetry.recordSample(
      latencyMs: 100,
      inferenceFps: 10,
      objectCount: 1,
      engine: InferenceEngine.ultralytics,
    );

    final json = telemetry.samples.single.toJson();
    expect(json['requestedDetectionHz'], isNull);
    expect(json['detectionCadenceAutomatic'], isFalse);
    expect(json['effectiveDetectionHz'], isNull);
    expect(json['requestedDepthHz'], isNull);
    expect(json['effectiveDepthHz'], isNull);
    expect(json['depthObservedHz'], isNull);
    expect(json['depthLatencyMs'], isNull);
    expect(json['depthStatus'], isNull);
  });

  test('keeps only the newest 400 samples', () {
    for (var i = 0; i < 420; i++) {
      telemetry.recordSample(
        latencyMs: i.toDouble(),
        inferenceFps: 10,
        objectCount: 1,
        engine: InferenceEngine.ultralytics,
      );
    }
    expect(telemetry.samples, hasLength(400));
    expect(telemetry.samples.first.latencyMs, 20);
    expect(telemetry.samples.last.latencyMs, 419);
  });

  test('detection frequency buckets per minute', () {
    telemetry.recordDetection(
      detInfo('person', 0),
      30,
      engine: InferenceEngine.ultralytics,
    );
    now = now.add(const Duration(seconds: 30));
    telemetry.recordDetection(
      detInfo('car', 2),
      30,
      engine: InferenceEngine.ultralytics,
    );
    now = now.add(const Duration(minutes: 1, seconds: 5));
    telemetry.recordDetection(
      detInfo('bus', 5),
      30,
      engine: InferenceEngine.ultralytics,
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
      InferenceEngine? engine = InferenceEngine.ultralytics,
      DateTime? requestedAt,
      DateTime? submittedAt,
      DateTime? startedAt,
      DateTime? terminalAt,
      DateTime? analysisReceivedAt,
      DateTime? resultReceivedAt,
      DateTime? detectionAcceptedAt,
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
        analysisReceivedAt: analysisReceivedAt,
        resultReceivedAt: resultReceivedAt,
        detectionAcceptedAt: detectionAcceptedAt,
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
        InferenceEngine.ultralytics,
        [10, 20, 30, 40],
      );
      expect(summary.sampleCount, 4);
      expect(summary.p50Ms, 20);
      expect(summary.p95Ms, 40);
      expect(summary.maxMs, 40);

      final single = AlertLatencySummary.fromDurations(
        InferenceEngine.ultralytics,
        [0],
      );
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
      // Not detection-origin but engine-matching: only the origin guard can
      // exclude it, so this stays falsifiable on its own.
      telemetry.recordAlertLifecycle(
        alert(
          origin: AlertOrigin.wayfinding,
          engine: InferenceEngine.ultralytics,
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

      // Both records now share the single engine; the wayfinding record, the
      // engine-null record, the never-started record and the negative interval
      // stay excluded.
      final ultralytics = telemetry.alertSubmittedToStartedSummary(
        InferenceEngine.ultralytics,
      );
      expect(ultralytics.sampleCount, 2);
      expect(ultralytics.maxMs, 100);
    });

    test('intervals use the result receipt anchor', () {
      final result = now.add(const Duration(milliseconds: 100));
      telemetry.recordAlertLifecycle(
        alert(
          engine: InferenceEngine.ultralytics,
          resultReceivedAt: result,
          detectionAcceptedAt: result.add(const Duration(milliseconds: 5)),
          submittedAt: result.add(const Duration(milliseconds: 8)),
          startedAt: result.add(const Duration(milliseconds: 20)),
        ),
      );

      expect(
        telemetry
            .alertLatencySummary(
              InferenceEngine.ultralytics,
              AlertLatencyInterval.receivedToAccepted,
            )
            .p50Ms,
        5,
      );
      expect(
        telemetry
            .alertLatencySummary(
              InferenceEngine.ultralytics,
              AlertLatencyInterval.acceptedToStarted,
            )
            .p50Ms,
        15,
      );
      expect(
        telemetry
            .alertLatencySummary(
              InferenceEngine.ultralytics,
              AlertLatencyInterval.submittedToStarted,
            )
            .p50Ms,
        12,
      );
      expect(
        telemetry
            .alertLatencySummary(
              InferenceEngine.ultralytics,
              AlertLatencyInterval.receivedToStarted,
            )
            .p50Ms,
        20,
      );
    });

    test(
      'interval summaries exclude null, negative, and non-detection pairs',
      () {
        final base = now.add(const Duration(seconds: 3));
        // Valid 10 ms and a valid 0 ms pair.
        telemetry.recordAlertLifecycle(
          alert(
            resultReceivedAt: base,
            detectionAcceptedAt: base.add(const Duration(milliseconds: 10)),
            submittedAt: base,
            startedAt: base.add(const Duration(milliseconds: 10)),
          ),
        );
        telemetry.recordAlertLifecycle(
          alert(
            resultReceivedAt: base,
            detectionAcceptedAt: base,
            submittedAt: base,
            startedAt: base,
          ),
        );
        // Non-detection origin with every endpoint present and a matching
        // engine, so only the origin guard excludes it.
        telemetry.recordAlertLifecycle(
          alert(
            origin: AlertOrigin.quickScan,
            engine: InferenceEngine.ultralytics,
            resultReceivedAt: base,
            detectionAcceptedAt: base.add(const Duration(milliseconds: 5)),
            submittedAt: base,
            startedAt: base.add(const Duration(milliseconds: 5)),
          ),
        );
        // Detection origin but engine-null.
        telemetry.recordAlertLifecycle(
          alert(
            engine: null,
            resultReceivedAt: base,
            detectionAcceptedAt: base.add(const Duration(milliseconds: 5)),
            submittedAt: base,
            startedAt: base.add(const Duration(milliseconds: 5)),
          ),
        );
        // Reversed analysis -> accepted interval is excluded individually.
        telemetry.recordAlertLifecycle(
          alert(
            resultReceivedAt: base.add(const Duration(milliseconds: 10)),
            detectionAcceptedAt: base,
            submittedAt: base,
            startedAt: base.add(const Duration(milliseconds: 5)),
          ),
        );
        // Missing analysis start: contributes to later intervals only.
        telemetry.recordAlertLifecycle(
          alert(
            detectionAcceptedAt: base,
            submittedAt: base,
            startedAt: base.add(const Duration(milliseconds: 7)),
          ),
        );

        final receivedToAccepted = telemetry.alertLatencySummary(
          InferenceEngine.ultralytics,
          AlertLatencyInterval.receivedToAccepted,
        );
        expect(receivedToAccepted.sampleCount, 2);
        // Nearest rank keeps the valid 0 ms sample rather than dropping it.
        expect(receivedToAccepted.p50Ms, 0);
        expect(receivedToAccepted.p95Ms, 10);
        expect(receivedToAccepted.maxMs, 10);

        final acceptedToStarted = telemetry.alertLatencySummary(
          InferenceEngine.ultralytics,
          AlertLatencyInterval.acceptedToStarted,
        );
        expect(acceptedToStarted.sampleCount, 4);
        expect(acceptedToStarted.maxMs, 7);
      },
    );

    test('nearest-rank percentiles, max, and count across samples', () {
      final base = now.add(const Duration(seconds: 4));
      for (final ms in [60, 10, 20]) {
        telemetry.recordAlertLifecycle(
          alert(
            submittedAt: base,
            startedAt: base.add(Duration(milliseconds: ms)),
          ),
        );
      }
      final summary = telemetry.alertLatencySummary(
        InferenceEngine.ultralytics,
        AlertLatencyInterval.submittedToStarted,
      );
      expect(summary.sampleCount, 3);
      expect(summary.p50Ms, 20);
      expect(summary.p95Ms, 60);
      expect(summary.maxMs, 60);
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

  test('aggregates every sample for the single engine', () {
    telemetry.recordSample(
      latencyMs: 150,
      inferenceFps: 6,
      objectCount: 0,
      engine: InferenceEngine.ultralytics,
    );
    telemetry.recordSample(
      latencyMs: 30,
      inferenceFps: 15,
      objectCount: 1,
      engine: InferenceEngine.ultralytics,
    );

    final summary = telemetry.summaryFor(InferenceEngine.ultralytics);
    expect(summary.averageLatencyMs, 90);
    expect(summary.averageInferenceFps, 10.5);
  });

  test('both writers stamp the detector model they were given', () {
    const ref = DetectorModelRef(
      id: 'custom:0a1b2c3d4e5f',
      name: 'Obstacle Detector v2',
      fingerprint: '0a1b2c3d4e5f6071-4200',
      classCount: 12,
    );
    telemetry.recordDetection(
      detInfo('cone', 3),
      40,
      engine: InferenceEngine.ultralytics,
      detectorModel: ref,
    );
    telemetry.recordSample(
      latencyMs: 40,
      inferenceFps: 10,
      objectCount: 1,
      engine: InferenceEngine.ultralytics,
      detectorModel: ref,
    );

    final record = telemetry.records.single;
    final sample = telemetry.samples.single;
    expect(record.detectorModelId, ref.id);
    expect(record.detectorModelName, 'Obstacle Detector v2');
    expect(record.detectorModelFingerprint, '0a1b2c3d4e5f6071-4200');
    expect(sample.detectorModelId, ref.id);
    expect(sample.detectorModelName, 'Obstacle Detector v2');
    expect(sample.detectorModelFingerprint, '0a1b2c3d4e5f6071-4200');
    // Serialised under the same names the export and the data dictionary use.
    expect(record.toJson()['detectorModelId'], ref.id);
    expect(sample.toJson()['detectorModelFingerprint'], ref.fingerprint);
  });
}
