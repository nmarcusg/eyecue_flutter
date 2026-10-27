import 'dart:convert';
import 'dart:ui' show Rect;

import 'package:eyecue_flutter/models/alert_lifecycle.dart';
import 'package:eyecue_flutter/models/app_settings.dart';
import 'package:eyecue_flutter/models/detection.dart';
import 'package:eyecue_flutter/models/detection_info.dart';
import 'package:eyecue_flutter/models/detector_model.dart';
import 'package:eyecue_flutter/models/research_session.dart';
import 'package:eyecue_flutter/services/research_session_service.dart';
import 'package:eyecue_flutter/services/telemetry_export_service.dart';
import 'package:eyecue_flutter/services/telemetry_service.dart';
import 'package:eyecue_flutter/services/telemetry_upload_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// A study upload token of the accepted shape (44 token-safe characters).
const String studyToken = 'q3Yd0n4N0m8Lw2Xc9Vb6Tz1Rf5Jk7Hp0Sg4Da2Em6Ui8';

const DetectorModelRef builtInRef = DetectorModelRef(
  id: 'builtin',
  name: 'Built-in YOLOv8n',
  fingerprint: DetectorModel.builtInFingerprint,
  classCount: 80,
);

const DetectorModelRef customRef = DetectorModelRef(
  id: 'custom:abcdef123456',
  name: 'Custom cones',
  fingerprint: 'abcdef1234567890-1234',
  classCount: 2,
);

class TestClock {
  TestClock(this.now);

  DateTime now;

  void advance(Duration duration) => now = now.add(duration);
}

TelemetryService buildTelemetry(TestClock clock) {
  final telemetry = TelemetryService(
    clock: () => clock.now,
    sessionId: 'session-app-lifetime',
    appVersion: '9.9.9+1',
  );
  telemetry.startSession();
  return telemetry;
}

void recordDetection(TelemetryService telemetry, {DetectorModelRef? model}) {
  telemetry.recordDetection(
    DetectionInfo(
      detection: const Detection(
        classId: 0,
        label: 'person',
        confidence: 0.9,
        box: Rect.fromLTWH(0.1, 0.2, 0.3, 0.4),
      ),
      position: RelativePosition.center,
      priority: ObjectPriority.high,
      proximity: ProximityBand.near,
    ),
    12,
    engine: InferenceEngine.ultralytics,
    detectorModel: model,
  );
}

void recordSample(TelemetryService telemetry, {DetectorModelRef? model}) {
  telemetry.recordSample(
    latencyMs: 42,
    inferenceFps: 8,
    objectCount: 1,
    engine: InferenceEngine.ultralytics,
    detectorModel: model,
  );
}

ResearchSessionService buildService({
  required TelemetryService telemetry,
  required TestClock clock,
  required InMemoryResearchSessionStore store,
  TelemetryUploadService? uploadService,
  int maxStoredSessions = 20,
}) => ResearchSessionService(
  telemetry: telemetry,
  store: store,
  clock: () => clock.now,
  uploadService: uploadService,
  maxStoredSessions: maxStoredSessions,
);

/// A real [TelemetryUploadService] with the network sender replaced, so the
/// exact request bytes are observable without a socket.
TelemetryUploadService buildUploadService({
  required TestClock clock,
  required List<TelemetryUploadRequest> requests,
  DateTime Function()? exportClock,
  TelemetryUploadResponse response = const TelemetryUploadResponse(200),
}) => TelemetryUploadService(
  configuration: const TelemetryUploadConfiguration(
    ingestUrl: 'https://ingest.example.test/functions/v1/ingest-telemetry',
    publishableKey: 'publishable-key',
  ),
  exportService: TelemetryExportService(clock: exportClock ?? () => clock.now),
  clock: () => clock.now,
  sender: (request) async {
    requests.add(request);
    return response;
  },
);

void main() {
  group('1. Start is explicit; an interrupted draft restores paused', () {
    test(
      'nothing before Start reaches the trial, and a draft restores paused',
      () async {
        final clock = TestClock(DateTime.utc(2026, 5, 1, 9));
        final telemetry = buildTelemetry(clock);
        addTearDown(telemetry.dispose);
        final store = InMemoryResearchSessionStore();
        final sessions = buildService(
          telemetry: telemetry,
          clock: clock,
          store: store,
        );

        expect(sessions.state, ResearchSessionState.idle);
        expect(sessions.stateLabel, 'Not recording');
        expect(await sessions.finish(), isNull);

        // Operational data before Start: never part of the trial.
        recordDetection(telemetry);
        recordSample(telemetry);
        clock.advance(const Duration(seconds: 1));

        expect(
          await sessions.start(
            participantCode: 'P-001',
            trialLabel: 'trial-1',
            detector: builtInRef,
          ),
          isNull,
        );
        expect(sessions.state, ResearchSessionState.recording);
        clock.advance(const Duration(seconds: 1));
        recordDetection(telemetry);
        recordSample(telemetry);

        final result = await sessions.finish();
        expect(result, isNotNull);
        expect(result!.session.records, hasLength(1));
        expect(result.session.samples, hasLength(1));

        // A second app run: the in-flight draft must come back paused, never
        // recording.
        final draftStore = InMemoryResearchSessionStore();
        final firstRun = buildService(
          telemetry: telemetry,
          clock: clock,
          store: draftStore,
        );
        await firstRun.start(
          participantCode: 'P-002',
          trialLabel: 'trial-2',
          detector: builtInRef,
        );
        expect(draftStore.draft, isNotNull);

        final restarted = buildService(
          telemetry: telemetry,
          clock: clock,
          store: draftStore,
        );
        await restarted.load();
        expect(restarted.state, ResearchSessionState.paused);
        expect(restarted.isRecording, isFalse);
        expect(restarted.stateLabel, 'Paused');
        expect(restarted.participantCode, 'P-002');
        expect(restarted.trialLabel, 'trial-2');
      },
    );
  });

  group('2. Pause freezes study accumulation, not detection', () {
    test(
      'paused detections and samples are absent while telemetry grows',
      () async {
        final clock = TestClock(DateTime.utc(2026, 5, 1, 10));
        final telemetry = buildTelemetry(clock);
        addTearDown(telemetry.dispose);
        final sessions = buildService(
          telemetry: telemetry,
          clock: clock,
          store: InMemoryResearchSessionStore(),
        );

        await sessions.start(
          participantCode: 'P-001',
          trialLabel: 'trial-1',
          detector: builtInRef,
        );
        recordDetection(telemetry);
        recordSample(telemetry);
        clock.advance(const Duration(seconds: 1));
        await sessions.pause();
        expect(sessions.state, ResearchSessionState.paused);

        clock.advance(const Duration(seconds: 1));
        final detectionsBefore = telemetry.totalDetections;
        final framesBefore = telemetry.framesProcessed;
        recordDetection(telemetry);
        recordSample(telemetry);
        // Detection itself never paused: the live buffer grew while paused.
        expect(telemetry.totalDetections, detectionsBefore + 1);
        expect(telemetry.framesProcessed, framesBefore + 1);

        final result = await sessions.finish();
        expect(result!.session.records, hasLength(1));
        expect(result.session.samples, hasLength(1));
      },
    );
  });

  group('3. Interval counter deltas exclude paused increments', () {
    test('counters are pauseValue - startValue per interval', () async {
      final clock = TestClock(DateTime.utc(2026, 5, 1, 11));
      final telemetry = buildTelemetry(clock);
      addTearDown(telemetry.dispose);
      final sessions = buildService(
        telemetry: telemetry,
        clock: clock,
        store: InMemoryResearchSessionStore(),
      );

      await sessions.start(
        participantCode: 'P-001',
        trialLabel: 'trial-1',
        detector: builtInRef,
      );
      recordDetection(telemetry);
      recordDetection(telemetry);
      recordSample(telemetry);
      recordSample(telemetry);
      clock.advance(const Duration(seconds: 2));
      await sessions.pause();

      clock.advance(const Duration(seconds: 1));
      // Paused increments: three detections and three samples.
      recordDetection(telemetry);
      recordDetection(telemetry);
      recordDetection(telemetry);
      recordSample(telemetry);
      recordSample(telemetry);
      recordSample(telemetry);
      clock.advance(const Duration(seconds: 1));
      await sessions.resume();

      recordDetection(telemetry);
      recordSample(telemetry);
      clock.advance(const Duration(seconds: 1));

      final session = (await sessions.finish())!.session;
      expect(session.totalDetections, 3);
      expect(session.highPriorityAlerts, 3);
      expect(session.framesProcessed, 3);
      // The frozen rows agree with the interval accounting.
      expect(session.records, hasLength(3));
      expect(session.samples, hasLength(3));
    });
  });

  group('4. Wall clock and active duration stay distinct', () {
    test(
      'a pause adds wall-clock time but not active recording time',
      () async {
        final clock = TestClock(DateTime.utc(2026, 5, 1, 12));
        final telemetry = buildTelemetry(clock);
        addTearDown(telemetry.dispose);
        final sessions = buildService(
          telemetry: telemetry,
          clock: clock,
          store: InMemoryResearchSessionStore(),
        );

        await sessions.start(
          participantCode: 'P-001',
          trialLabel: 'trial-1',
          detector: builtInRef,
        );
        clock.advance(const Duration(seconds: 10));
        await sessions.pause();
        clock.advance(const Duration(seconds: 60));
        await sessions.resume();
        clock.advance(const Duration(seconds: 5));

        final session = (await sessions.finish())!.session;
        expect(session.sessionDuration, const Duration(seconds: 15));
        expect(session.wallClockDuration, const Duration(seconds: 75));
        expect(session.wallClockDuration > session.sessionDuration, isTrue);
        expect(session.activeDurationMs, 15000);
      },
    );
  });

  group('5. Finish is immutable and survives a restart', () {
    test(
      'later inference and a model change cannot alter the snapshot',
      () async {
        final clock = TestClock(DateTime.utc(2026, 5, 1, 13));
        final telemetry = buildTelemetry(clock);
        addTearDown(telemetry.dispose);
        final store = InMemoryResearchSessionStore();
        final sessions = buildService(
          telemetry: telemetry,
          clock: clock,
          store: store,
        );

        await sessions.start(
          participantCode: 'P-001',
          trialLabel: 'trial-1',
          detector: builtInRef,
        );
        recordDetection(telemetry);
        clock.advance(const Duration(seconds: 1));
        final first = (await sessions.finish())!.session;
        final frozenJson = jsonEncode(first.toJson());

        // Everything that happens afterwards belongs to no trial.
        recordDetection(telemetry);
        clock.advance(const Duration(seconds: 1));
        await sessions.noteDetectorChange(customRef);
        recordSample(telemetry);
        expect(await sessions.finish(), isNull);
        expect(jsonEncode(first.toJson()), frozenJson);

        // A restart restores the same trial with the same bytes.
        final restarted = buildService(
          telemetry: telemetry,
          clock: clock,
          store: store,
        );
        await restarted.load();
        expect(restarted.sessions, hasLength(1));
        final restored = restarted.sessions.single;
        expect(restored.id, first.id);
        expect(jsonEncode(restored.toJson()), frozenJson);

        // The export of the restored trial is byte-identical to the original's,
        // so an upload after a restart sends the same frozen payload.
        final exporter = TelemetryExportService(clock: () => clock.now);
        expect(
          exporter.toJson(telemetry: restored),
          exporter.toJson(telemetry: first),
        );
      },
    );
  });

  group('6. Trial ids and byte-identical retry', () {
    test('two trials differ; a retry re-sends the same frozen body', () async {
      final clock = TestClock(DateTime.utc(2026, 5, 1, 14));
      final telemetry = buildTelemetry(clock);
      addTearDown(telemetry.dispose);
      final requests = <TelemetryUploadRequest>[];
      final sessions = buildService(
        telemetry: telemetry,
        clock: clock,
        store: InMemoryResearchSessionStore(),
        uploadService: buildUploadService(
          clock: clock,
          requests: requests,
          // A fixed export clock isolates the frozen payload from when the
          // export happened; only the request's own submittedAt moves.
          exportClock: () => DateTime.utc(2026, 5, 1, 14),
        ),
      );
      const metadata = ResearchSessionMetadata(
        participantCode: 'P-001',
        studyScenario: 'trial-1',
        uploadToken: studyToken,
      );

      await sessions.start(
        participantCode: 'P-001',
        trialLabel: 'trial-1',
        detector: builtInRef,
      );
      recordDetection(telemetry);
      clock.advance(const Duration(seconds: 1));
      final trialA = (await sessions.finish())!.session;

      await sessions.start(
        participantCode: 'P-001',
        trialLabel: 'trial-2',
        detector: builtInRef,
      );
      recordDetection(telemetry);
      clock.advance(const Duration(seconds: 1));
      final trialB = (await sessions.finish())!.session;

      expect(trialA.id, isNot(trialB.id));

      final firstUpload = await sessions.upload(
        session: trialA,
        metadata: metadata,
      );
      final retry = await sessions.upload(session: trialA, metadata: metadata);
      expect(firstUpload.isSuccess, isTrue);
      expect(retry.isSuccess, isTrue);
      expect(requests, hasLength(2));
      // Byte-identical: nothing about the frozen trial changed between sends.
      expect(requests[0].body, requests[1].body);
      expect(requests[0].contentLengthBytes, requests[1].contentLengthBytes);

      final payload = jsonDecode(requests[0].body) as Map<String, dynamic>;
      final export = payload['telemetry'] as Map<String, dynamic>;
      final envelopeSession = export['session'] as Map<String, dynamic>;
      // The trial id IS the server's client_session_id.
      expect(envelopeSession['id'], trialA.id);
      expect(envelopeSession['id'], isNot(telemetry.sessionId));
      expect(payload['study'], metadata.toJson());
      // The token crosses in the header only, never in the body.
      expect(requests[0].body.contains(studyToken), isFalse);
      expect(
        requests[0].headers[TelemetryUploadService.uploadTokenHeaderName],
        studyToken,
      );

      // A later retry (moved wall clock) changes only the request timestamp:
      // the frozen payload is the same trial.
      clock.advance(const Duration(minutes: 5));
      await sessions.upload(session: trialA, metadata: metadata);
      final later = jsonDecode(requests[2].body) as Map<String, dynamic>;
      final earlier = jsonDecode(requests[1].body) as Map<String, dynamic>;
      expect(later.remove('submittedAt'), isNot(earlier['submittedAt']));
      earlier.remove('submittedAt');
      expect(jsonEncode(later), jsonEncode(earlier));

      expect(sessions.uploadStatusFor(trialA), 'Uploaded');
      expect(sessions.uploadStatusFor(trialB), isNull);
    });
  });

  group('7. A failed local save is reported and keeps the trial', () {
    test(
      'finish returns saved: false with the in-memory session intact',
      () async {
        final clock = TestClock(DateTime.utc(2026, 5, 1, 15));
        final telemetry = buildTelemetry(clock);
        addTearDown(telemetry.dispose);
        final store = InMemoryResearchSessionStore(failWrites: true);
        final sessions = buildService(
          telemetry: telemetry,
          clock: clock,
          store: store,
        );

        await sessions.start(
          participantCode: 'P-001',
          trialLabel: 'trial-1',
          detector: builtInRef,
        );
        recordDetection(telemetry);
        clock.advance(const Duration(seconds: 1));

        final result = await sessions.finish();
        expect(result, isNotNull);
        expect(result!.saved, isFalse);
        expect(result.session.records, hasLength(1));
        expect(sessions.sessions, contains(result.session));
        expect(sessions.isSaved(result.session), isFalse);
        expect(sessions.lastSaveError, contains('could not be saved'));
        expect(store.finished, isEmpty);
      },
    );
  });

  group('8. The store cap refuses the next start visibly', () {
    test('the 21st start is refused and existing trials remain', () async {
      final clock = TestClock(DateTime.utc(2026, 5, 1, 16));
      final telemetry = buildTelemetry(clock);
      addTearDown(telemetry.dispose);
      final sessions = buildService(
        telemetry: telemetry,
        clock: clock,
        store: InMemoryResearchSessionStore(),
        maxStoredSessions: 20,
      );

      for (var index = 0; index < 20; index++) {
        expect(
          await sessions.start(
            participantCode: 'P-001',
            trialLabel: 'trial-$index',
            detector: builtInRef,
          ),
          isNull,
        );
        clock.advance(const Duration(seconds: 1));
        expect((await sessions.finish())!.saved, isTrue);
      }
      expect(sessions.sessions, hasLength(20));

      final refusal = await sessions.start(
        participantCode: 'P-001',
        trialLabel: 'trial-21',
        detector: builtInRef,
      );
      expect(refusal, isNotNull);
      expect(refusal, contains('Stored trials are full'));
      expect(refusal, contains('Upload or discard'));
      expect(sessions.state, ResearchSessionState.finished);
      expect(sessions.sessions, hasLength(20));

      // Discarding one makes room again, and deletes only that trial.
      final discarded = sessions.sessions.first;
      await sessions.discard(discarded);
      expect(sessions.sessions, hasLength(19));
      expect(
        await sessions.start(
          participantCode: 'P-001',
          trialLabel: 'trial-22',
          detector: builtInRef,
        ),
        isNull,
      );
    });
  });

  group('9. A model change pauses, then resumes with the new identity', () {
    test('setup rows after the switch are not in the trial', () async {
      final clock = TestClock(DateTime.utc(2026, 5, 1, 17));
      final telemetry = buildTelemetry(clock);
      addTearDown(telemetry.dispose);
      final sessions = buildService(
        telemetry: telemetry,
        clock: clock,
        store: InMemoryResearchSessionStore(),
      );

      await sessions.start(
        participantCode: 'P-001',
        trialLabel: 'trial-1',
        detector: builtInRef,
      );
      recordDetection(telemetry, model: builtInRef);
      clock.advance(const Duration(seconds: 1));

      await sessions.noteDetectorChange(customRef);
      expect(sessions.state, ResearchSessionState.paused);
      expect(sessions.isRecording, isFalse);
      expect(sessions.detectorName, contains('Custom cones'));

      // The replacement loading/setup rows are recorded while paused.
      clock.advance(const Duration(seconds: 1));
      recordDetection(telemetry, model: customRef);
      recordSample(telemetry, model: customRef);
      clock.advance(const Duration(seconds: 1));

      await sessions.resume();
      recordDetection(telemetry, model: customRef);
      clock.advance(const Duration(seconds: 1));

      final session = (await sessions.finish())!.session;
      expect(session.records, hasLength(2));
      expect(session.records.map((record) => record.detectorModelId), [
        'builtin',
        'custom:abcdef123456',
      ]);
      expect(session.detectors.map((detector) => detector.id), [
        'builtin',
        'custom:abcdef123456',
      ]);
      expect(session.samples, isEmpty);
      expect(session.detectionsByDetector, {
        'builtin': 1,
        'custom:abcdef123456': 1,
      });
      expect(session.detectorName, 'Built-in YOLOv8n → Custom cones');
    });
  });

  group('10. The study token never reaches a file or an export', () {
    test(
      'no stored draft, stored trial or export contains the token',
      () async {
        final clock = TestClock(DateTime.utc(2026, 5, 1, 18));
        final telemetry = buildTelemetry(clock);
        addTearDown(telemetry.dispose);
        final store = InMemoryResearchSessionStore();
        final requests = <TelemetryUploadRequest>[];
        final sessions = buildService(
          telemetry: telemetry,
          clock: clock,
          store: store,
          uploadService: buildUploadService(clock: clock, requests: requests),
        );

        await sessions.start(
          participantCode: 'P-001',
          trialLabel: 'trial-1',
          detector: builtInRef,
        );
        expect(store.draft, isNotNull);
        expect(store.draft!.contains(studyToken), isFalse);

        recordDetection(telemetry);
        clock.advance(const Duration(seconds: 1));
        final session = (await sessions.finish())!.session;

        final result = await sessions.upload(
          session: session,
          metadata: const ResearchSessionMetadata(
            participantCode: 'P-001',
            studyScenario: 'trial-1',
            uploadToken: studyToken,
          ),
          settings: const AppSettings(),
        );
        expect(result.isSuccess, isTrue);
        expect(requests.single.body.contains(studyToken), isFalse);

        expect(store.finished[session.id], jsonEncode(session.toJson()));
        expect(store.finished[session.id]!.contains(studyToken), isFalse);
        final exported = TelemetryExportService(
          clock: () => clock.now,
        ).toJson(telemetry: session, settings: const AppSettings());
        expect(exported.contains(studyToken), isFalse);
        // No token field exists in the frozen model at all.
        expect(jsonEncode(session.toJson()).contains('token'), isFalse);
      },
    );
  });

  group(
    '11. Trial counters are interval deltas, never app-lifetime totals',
    () {
      test(
        'pre-Start and paused counters stay out of the trial and its export',
        () async {
          final clock = TestClock(DateTime.utc(2026, 5, 1, 19));
          final telemetry = buildTelemetry(clock);
          addTearDown(telemetry.dispose);
          final sessions = buildService(
            telemetry: telemetry,
            clock: clock,
            store: InMemoryResearchSessionStore(),
          );

          // Setup/practice before Start runs under the app-lifetime session.
          telemetry.recordAlertCounters(
            const AlertCounters(
              dropped: 42,
              muted: 3,
              rejectedByReason: {'lowConfidence': 5},
            ),
          );
          recordDetection(telemetry);

          await sessions.start(
            participantCode: 'P-001',
            trialLabel: 'trial-1',
            detector: builtInRef,
          );
          // First active interval.
          telemetry.recordAlertCounters(
            const AlertCounters(
              dropped: 44,
              muted: 3,
              rejectedByReason: {'lowConfidence': 7, 'stale': 2},
            ),
          );
          recordDetection(telemetry);
          clock.advance(const Duration(seconds: 10));
          await sessions.pause();

          // During the pause: recorded live, but never in the trial.
          telemetry.recordAlertCounters(
            const AlertCounters(
              dropped: 60,
              muted: 9,
              rejectedByReason: {'lowConfidence': 7, 'stale': 2, 'late': 1},
            ),
          );
          recordDetection(telemetry);
          clock.advance(const Duration(seconds: 5));
          await sessions.resume();

          // Second active interval.
          telemetry.recordAlertCounters(
            const AlertCounters(
              dropped: 61,
              muted: 9,
              rejectedByReason: {'lowConfidence': 7, 'stale': 2, 'late': 1},
            ),
          );
          recordDetection(telemetry);
          clock.advance(const Duration(seconds: 2));

          final session = (await sessions.finish())!.session;
          expect(session.totalDetections, 2);
          expect(session.alertCounters.dropped, 3);
          expect(session.alertCounters.muted, 0);
          expect(session.alertCounters.rejectedByReason, {
            'lowConfidence': 2,
            'stale': 2,
          });

          // The stored/exported trial carries the delta, not the live snapshot.
          final restored = ResearchSession.fromJson(
            jsonDecode(jsonEncode(session.toJson())) as Map<String, dynamic>,
          );
          expect(
            restored.alertCounters.toJson(),
            session.alertCounters.toJson(),
          );
          final exported =
              jsonDecode(
                    TelemetryExportService(
                      clock: () => clock.now,
                    ).toJson(telemetry: session),
                  )
                  as Map<String, dynamic>;
          final counters = exported['alertCounters'] as Map<String, dynamic>;
          expect(counters['dropped'], 3);
          expect(counters['muted'], 0);
        },
      );
    },
  );

  group('12. A model change pauses without the Detection page', () {
    test('the service owns the reaction and pauses once per boundary', () async {
      final clock = TestClock(DateTime.utc(2026, 5, 1, 20));
      final telemetry = buildTelemetry(clock);
      addTearDown(telemetry.dispose);
      final sessions = buildService(
        telemetry: telemetry,
        clock: clock,
        store: InMemoryResearchSessionStore(),
      );
      final selection = _FakeSelection(builtInRef);
      addTearDown(selection.dispose);
      // No Detection screen is ever built in this test: the subscription is the
      // only thing that can pause the trial.
      sessions.watchDetectorModel(selection, () => selection.ref);
      sessions.watchDetectorModel(selection, () => selection.ref);

      await sessions.start(
        participantCode: 'P-001',
        trialLabel: 'trial-1',
        detector: builtInRef,
      );
      recordDetection(telemetry, model: builtInRef);
      clock.advance(const Duration(seconds: 1));

      selection.select(customRef);
      await pumpEventQueue();

      expect(sessions.state, ResearchSessionState.paused);
      expect(sessions.isRecording, isFalse);
      expect(sessions.detectorName, contains('Custom cones'));

      // The swap's setup rows are outside every interval.
      clock.advance(const Duration(seconds: 1));
      recordDetection(telemetry, model: customRef);
      // A repeat notification of the same identity is not a second boundary.
      selection.repeat();
      await pumpEventQueue();
      expect(sessions.state, ResearchSessionState.paused);
      clock.advance(const Duration(seconds: 1));

      await sessions.resume();
      recordDetection(telemetry, model: customRef);
      clock.advance(const Duration(seconds: 1));

      final session = (await sessions.finish())!.session;
      expect(session.detectors.map((detector) => detector.id), [
        'builtin',
        'custom:abcdef123456',
      ]);
      expect(session.records, hasLength(2));
    });
  });

  group('13. Active duration grows while recording', () {
    test('the open interval counts, and a pause freezes it', () async {
      final clock = TestClock(DateTime.utc(2026, 5, 1, 21));
      final telemetry = buildTelemetry(clock);
      addTearDown(telemetry.dispose);
      final sessions = buildService(
        telemetry: telemetry,
        clock: clock,
        store: InMemoryResearchSessionStore(),
      );

      await sessions.start(
        participantCode: 'P-001',
        trialLabel: 'trial-1',
        detector: builtInRef,
      );
      expect(sessions.activeDuration, Duration.zero);
      clock.advance(const Duration(seconds: 10));
      expect(sessions.activeDuration, const Duration(seconds: 10));
      clock.advance(const Duration(seconds: 5));
      expect(sessions.activeDuration, const Duration(seconds: 15));

      await sessions.pause();
      final frozen = sessions.activeDuration;
      expect(frozen, const Duration(seconds: 15));
      clock.advance(const Duration(minutes: 1));
      expect(sessions.activeDuration, frozen);

      final session = (await sessions.finish())!.session;
      expect(session.activeDurationMs, 15000);
      expect(session.wallClockDuration, const Duration(seconds: 75));
    });
  });

  group('14. Detection deltas survive the record buffer cap', () {
    test('2500 detections count as 2500 in the trial', () async {
      final clock = TestClock(DateTime.utc(2026, 5, 1, 22));
      final telemetry = buildTelemetry(clock);
      addTearDown(telemetry.dispose);
      final sessions = buildService(
        telemetry: telemetry,
        clock: clock,
        store: InMemoryResearchSessionStore(),
      );

      await sessions.start(
        participantCode: 'P-001',
        trialLabel: 'trial-1',
        detector: builtInRef,
      );
      for (var index = 0; index < 2500; index++) {
        recordDetection(telemetry);
      }
      // The shipped buffer is capped; the counter is not.
      expect(telemetry.totalDetections, 2000);
      expect(telemetry.detectionCount, 2500);

      clock.advance(const Duration(seconds: 1));
      final session = (await sessions.finish())!.session;
      expect(session.totalDetections, 2500);
      expect(session.records, hasLength(2000));
    });
  });

  group('15. The boundary is recorded without the Logs & Reports route', () {
    test('a restored paused draft takes the change before any screen', () async {
      final clock = TestClock(DateTime.utc(2026, 5, 1, 23));
      final telemetry = buildTelemetry(clock);
      addTearDown(telemetry.dispose);
      final store = InMemoryResearchSessionStore();

      // A first run leaves an in-flight draft behind.
      final firstRun = buildService(
        telemetry: telemetry,
        clock: clock,
        store: store,
      );
      await firstRun.start(
        participantCode: 'P-001',
        trialLabel: 'trial-1',
        detector: builtInRef,
      );
      recordDetection(telemetry, model: builtInRef);
      clock.advance(const Duration(seconds: 1));

      // Second run: restored as paused before the first frame, and subscribed
      // where `main.dart` creates the services. No Logs & Reports route is built.
      final selection = _FakeSelection(builtInRef);
      addTearDown(selection.dispose);
      final sessions = buildService(
        telemetry: telemetry,
        clock: clock,
        store: store,
      );
      await sessions.load();
      expect(sessions.state, ResearchSessionState.paused);
      sessions.watchDetectorModel(selection, () => selection.ref);

      selection.select(customRef);
      await pumpEventQueue();

      expect(sessions.state, ResearchSessionState.paused);
      expect(sessions.detectorName, contains('Custom cones'));

      // The resumed trial carries both identities.
      await sessions.resume();
      clock.advance(const Duration(seconds: 1));
      recordDetection(telemetry, model: customRef);
      clock.advance(const Duration(seconds: 1));
      final session = (await sessions.finish())!.session;
      expect(session.detectors.map((detector) => detector.id), [
        'builtin',
        'custom:abcdef123456',
      ]);
    });
  });

  group('16. A notification that keeps the identity is not a boundary', () {
    test('re-selecting the active model leaves the trial recording', () async {
      final clock = TestClock(DateTime.utc(2026, 5, 2));
      final telemetry = buildTelemetry(clock);
      addTearDown(telemetry.dispose);
      final sessions = buildService(
        telemetry: telemetry,
        clock: clock,
        store: InMemoryResearchSessionStore(),
      );
      final selection = _FakeSelection(builtInRef);
      addTearDown(selection.dispose);
      sessions.watchDetectorModel(selection, () => selection.ref);

      await sessions.start(
        participantCode: 'P-001',
        trialLabel: 'trial-1',
        detector: builtInRef,
      );
      recordDetection(telemetry, model: builtInRef);
      clock.advance(const Duration(seconds: 1));

      // `selectBuiltIn()` on an already built-in selection notifies anyway.
      selection.repeat();
      await pumpEventQueue();

      expect(sessions.state, ResearchSessionState.recording);
      expect(sessions.isRecording, isTrue);
      expect(sessions.detectorName, 'Built-in YOLOv8n');

      clock.advance(const Duration(seconds: 1));
      recordDetection(telemetry, model: builtInRef);
      clock.advance(const Duration(seconds: 1));
      final session = (await sessions.finish())!.session;
      expect(session.detectors, hasLength(1));
      expect(session.records, hasLength(2));
    });
  });
}

/// A stand-in for the detector selection: a [ChangeNotifier] plus the identity
/// getter the service reads when it fires.
class _FakeSelection extends ChangeNotifier {
  _FakeSelection(this.ref);

  DetectorModelRef ref;

  void select(DetectorModelRef next) {
    ref = next;
    notifyListeners();
  }

  /// Re-notifies without changing the selection.
  void repeat() => notifyListeners();
}
