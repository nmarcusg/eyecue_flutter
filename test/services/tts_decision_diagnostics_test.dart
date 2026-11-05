import 'dart:ui';

import 'package:eyecue_flutter/models/detection.dart';
import 'package:eyecue_flutter/services/alert_policy.dart';
import 'package:eyecue_flutter/services/spatial_analysis_service.dart';
import 'package:eyecue_flutter/services/tts_service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'tts_service_test.dart' as helpers;

void main() {
  final normal = SpatialAnalysisService.analyze(
    const Detection(
      classId: 0,
      label: 'person',
      confidence: 0.9,
      box: Rect.fromLTWH(0.3, 0.2, 0.4, 0.5),
    ),
    meters: 1.8,
  );

  test(
    'configuration discards pending work while active speech and Repeat survive',
    () async {
      final engine = helpers.FakeTtsEngine()..mode = helpers.FakeMode.startOnly;
      final service = TtsService(engine: engine);
      addTearDown(service.dispose);
      await service.init();
      final active = service.speak('An existing message');
      final pending = service.announceDetections([normal]);
      expect(engine.spoken, ['An existing message']);
      service.applyAutomaticDistanceConfig(
        const AutomaticDistanceAlertConfig(
          normalMaxMeters: 3,
          urgentBelowMeters: 1,
        ),
      );
      expect(await pending, false);
      expect(engine.stopCalls, 0);
      expect(service.isSpeaking, true);
      expect(service.lastUtterance, 'An existing message');
      engine.emitComplete();
      engine.resolveCurrent(1);
      expect(await active, true);
      expect(engine.spoken, ['An existing message']);
    },
  );

  test(
    'pending refresh preserves first eligibility in opt-in monotonic trace',
    () async {
      final engine = helpers.FakeTtsEngine()..mode = helpers.FakeMode.startOnly;
      var monotonic = Duration.zero;
      final service = TtsService(
        engine: engine,
        enableDecisionDiagnostics: true,
        monotonicClock: () => monotonic,
      );
      addTearDown(service.dispose);
      await service.init();
      final active = service.speak('An existing message');
      monotonic = const Duration(milliseconds: 10);
      final first = service.announceDetections([normal]);
      monotonic = const Duration(milliseconds: 40);
      final latest = service.announceDetections([normal]);
      expect(await first, false);
      monotonic = const Duration(milliseconds: 60);
      engine.emitComplete();
      engine.resolveCurrent(1);
      await active;
      final submitted = service.decisionDiagnostics.firstWhere(
        (e) => e.stage == 'submitted',
      );
      expect(submitted.firstEligibleAt, const Duration(milliseconds: 10));
      expect(submitted.firstObservedAt, const Duration(milliseconds: 10));
      expect(
        submitted.at - submitted.firstEligibleAt!,
        const Duration(milliseconds: 50),
      );
      expect(submitted.metricMeters, 1.8);
      expect(
        service.decisionDiagnostics.where((e) => e.stage == 'eligible').length,
        1,
      );
      expect(
        service.decisionDiagnostics.any(
          (e) => e.stage == 'discarded' && e.reason == 'superseded',
        ),
        true,
      );
      engine.emitComplete();
      engine.resolveCurrent(1);
      expect(await latest, true);
    },
  );

  test('rejections expose policy cause without fabricated start', () async {
    final service = TtsService(
      engine: helpers.FakeTtsEngine(),
      enableDecisionDiagnostics: true,
    );
    addTearDown(service.dispose);
    await service.init();
    final far = SpatialAnalysisService.analyze(normal.detection, meters: 5);
    expect(await service.announceDetections([far]), false);
    final rejection = service.decisionDiagnostics.single;
    expect(rejection.stage, 'rejected');
    expect(rejection.reason, 'suppressedNoCandidates');
    expect(rejection.metricMeters, 5);
    expect(rejection.firstEligibleAt, isNull);
  });

  test('active old-policy trace retains its original thresholds', () async {
    final engine = helpers.FakeTtsEngine()..mode = helpers.FakeMode.manual;
    final service = TtsService(engine: engine, enableDecisionDiagnostics: true);
    addTearDown(service.dispose);
    await service.init();
    final active = service.announceDetections([normal]);
    service.applyAutomaticDistanceConfig(
      const AutomaticDistanceAlertConfig(
        normalMaxMeters: 3,
        urgentBelowMeters: 1,
      ),
    );
    engine.emitStart();
    engine.emitComplete();
    engine.resolveCurrent(1);
    expect(await active, true);
    final traces = service.decisionDiagnostics;
    expect(traces.any((e) => e.stage == 'started'), true);
    for (final trace in traces) {
      expect(trace.normalMaxMeters, 2);
      expect(trace.urgentBelowMeters, 1.5);
      expect(trace.configurationGeneration, 0);
    }
    expect(service.lastUtterance, isNotNull);
    expect(engine.stopCalls, 0);
  });

  test(
    'diagnostics are disabled by default and bounded when enabled',
    () async {
      final defaultService = TtsService(engine: helpers.FakeTtsEngine());
      await defaultService.init();
      await defaultService.announceDetections([normal]);
      expect(defaultService.decisionDiagnostics, isEmpty);
      defaultService.dispose();

      final tracedService = TtsService(
        engine: helpers.FakeTtsEngine(),
        enableDecisionDiagnostics: true,
      );
      addTearDown(tracedService.dispose);
      await tracedService.init();
      for (var i = 0; i < 100; i++) {
        await tracedService.announceDetections([normal], force: true);
      }
      expect(tracedService.decisionDiagnostics.length, 256);
      expect(
        () => tracedService.decisionDiagnostics.clear(),
        throwsUnsupportedError,
      );
    },
  );
}
