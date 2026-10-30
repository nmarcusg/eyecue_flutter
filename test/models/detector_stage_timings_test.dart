import 'package:eyecue_flutter/models/detector_stage_timings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ultralytics_yolo/ultralytics_yolo.dart';

void main() {
  test('maps the stage timings a full streaming payload carries', () {
    final timings = DetectorStageTimings.fromMetrics(
      YOLOPerformanceMetrics.fromMap({
        'fps': 18.25,
        'processingTimeMs': 31.5,
        'preMs': 4.0,
        'inferenceMs': 21.5,
        'postMs': 6.0,
      }),
    );

    expect(timings.preMs, 4.0);
    expect(timings.inferenceMs, 21.5);
    expect(timings.postMs, 6.0);
    expect(timings.fps, 18.25);
  });

  test('an unreported stage is null, never 0', () {
    // The native map omits the stage keys unless the include flags are on, and
    // the plugin defaults them to 0.
    final timings = DetectorStageTimings.fromMetrics(
      YOLOPerformanceMetrics.fromMap({'processingTimeMs': 31.5}),
    );

    expect(timings.preMs, isNull);
    expect(timings.inferenceMs, isNull);
    expect(timings.postMs, isNull);
    expect(timings.fps, isNull);
  });
}
