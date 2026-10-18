import 'package:eyecue_flutter/models/alert_lifecycle.dart';
import 'package:eyecue_flutter/models/app_settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final analysis = DateTime.utc(2026, 1, 1, 12);
  final started = analysis.add(const Duration(milliseconds: 10));
  final completed = analysis.add(const Duration(milliseconds: 80));
  final received = analysis.add(const Duration(milliseconds: 90));

  FrameLatency frame(int number) => FrameLatency(
    frameNumber: number,
    analysisReceivedAt: analysis,
    inferenceStartedAt: started,
    inferenceCompletedAt: completed,
    resultReceivedAt: received,
  );

  group('FrameLatencySlot', () {
    test('installed snapshot is consumed exactly once', () {
      final slot = FrameLatencySlot();
      final snapshot = frame(7);
      slot.install(snapshot);

      expect(slot.take(), same(snapshot));
      expect(slot.take(), isNull);
    });

    test('keeps the newest frame number without mixing frames', () {
      final slot = FrameLatencySlot();
      slot.install(frame(1));
      slot.install(frame(2));

      final taken = slot.take();
      expect(taken!.frameNumber, 2);
      expect(taken.analysisReceivedAt, frame(2).analysisReceivedAt);
      expect(slot.take(), isNull);
    });

    test('clear drops an unconsumed snapshot', () {
      final slot = FrameLatencySlot();
      slot.install(frame(3));
      slot.clear();

      expect(slot.take(), isNull);
    });
  });

  test('withDetectionAcceptedAt preserves every frame anchor', () {
    final accepted = received.add(const Duration(milliseconds: 5));
    final timing = frame(9).withDetectionAcceptedAt(accepted);

    expect(timing.frameNumber, 9);
    expect(timing.analysisReceivedAt, analysis);
    expect(timing.inferenceStartedAt, started);
    expect(timing.inferenceCompletedAt, completed);
    expect(timing.resultReceivedAt, received);
    expect(timing.detectionAcceptedAt, accepted);
  });

  test('record JSON adds timing metadata only', () {
    final accepted = received.add(const Duration(milliseconds: 5));
    final record = AlertLifecycleRecord(
      origin: AlertOrigin.detection,
      engine: InferenceEngine.custom,
      requestedAt: accepted,
      submittedAt: accepted,
      alertStartedAt: accepted,
      terminalAt: accepted,
      terminalState: AlertTerminalState.completed,
      terminalCause: null,
      hadStarted: true,
      reconciledAt: accepted,
      frameNumber: 9,
      analysisReceivedAt: analysis,
      inferenceStartedAt: started,
      inferenceCompletedAt: completed,
      resultReceivedAt: received,
      detectionAcceptedAt: accepted,
    );

    final json = record.toJson();
    expect(json['frameNumber'], 9);
    expect(json['analysisReceivedAt'], analysis.toIso8601String());
    expect(json['inferenceStartedAt'], started.toIso8601String());
    expect(json['inferenceCompletedAt'], completed.toIso8601String());
    expect(json['resultReceivedAt'], received.toIso8601String());
    expect(json['detectionAcceptedAt'], accepted.toIso8601String());
    expect(json.keys.where((key) => key.contains('box')), isEmpty);
  });
}
