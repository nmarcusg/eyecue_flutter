import 'dart:ui';

import 'package:eyecue_flutter/models/detection.dart';
import 'package:eyecue_flutter/models/detection_info.dart';
import 'package:eyecue_flutter/services/spatial_analysis_service.dart';
import 'package:eyecue_flutter/services/telemetry_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late DateTime now;
  late TelemetryService telemetry;

  setUp(() {
    now = DateTime(2026, 1, 1, 12, 0, 0);
    telemetry = TelemetryService(clock: () => now);
  });

  DetectionInfo detInfo(String label, int classId) {
    return SpatialAnalysisService.analyze(Detection(
      classId: classId,
      label: label,
      confidence: 0.8,
      box: const Rect.fromLTWH(0.1, 0.1, 0.2, 0.3),
    ));
  }

  test('session start and duration are tracked', () {
    telemetry.startSession();
    now = now.add(const Duration(seconds: 65));
    expect(telemetry.sessionDuration.inSeconds, 65);
  });

  test('records detections and counts high-priority alerts', () {
    telemetry.recordDetection(detInfo('person', 0), 30);
    telemetry.recordDetection(detInfo('car', 2), 32);
    telemetry.recordDetection(detInfo('toothbrush', 79), 31);
    expect(telemetry.totalDetections, 3);
    expect(telemetry.highPriorityAlerts, 2);
  });

  test('computes average latency and FPS from samples', () {
    telemetry.recordSample(latencyMs: 100, inferenceFps: 10, objectCount: 1);
    telemetry.recordSample(latencyMs: 200, inferenceFps: 5, objectCount: 2);
    expect(telemetry.framesProcessed, 2);
    expect(telemetry.averageLatencyMs, 150);
    expect(telemetry.averageInferenceFps, 7.5);
  });

  test('detection frequency buckets per minute', () {
    telemetry.recordDetection(detInfo('person', 0), 30);
    now = now.add(const Duration(seconds: 30));
    telemetry.recordDetection(detInfo('car', 2), 30);
    now = now.add(const Duration(minutes: 1, seconds: 5));
    telemetry.recordDetection(detInfo('bus', 5), 30);

    final buckets = telemetry.detectionFrequencyByMinute();
    expect(buckets, [2, 1]);
  });

  test('empty service reports zeroes and no buckets', () {
    expect(telemetry.totalDetections, 0);
    expect(telemetry.averageLatencyMs, 0);
    expect(telemetry.detectionFrequencyByMinute(), isEmpty);
  });
}
