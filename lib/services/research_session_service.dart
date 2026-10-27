import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/app_settings.dart';
import '../models/detector_model.dart';
import '../models/research_session.dart';
import 'telemetry_service.dart';
import 'telemetry_upload_service.dart';

/// Lifecycle of the explicit respondent-logging trial.
enum ResearchSessionState { idle, recording, paused, finished }

/// Persistence seam for finished trials and the one interrupted draft.
///
/// Mirrors [SettingsStore]: a small abstraction over one JSON file per trial,
/// so the service is unit-testable without platform channels.
abstract class ResearchSessionStore {
  /// Stored finished trials by id, as raw JSON.
  Future<Map<String, String>> readFinished();

  /// The in-flight draft, if the app stopped before the trial was finished.
  Future<String?> readDraft();

  /// Persists one finished trial. A thrown error is reported to the researcher
  /// as "not saved"; it is never swallowed by the service.
  Future<void> writeFinished(String id, String contents);

  Future<void> deleteFinished(String id);

  /// Writes the draft, or deletes it when [contents] is null.
  Future<void> writeDraft(String? contents);
}

/// File-backed store: `documents/eyecue_research_sessions/<id>.json` plus
/// `draft.json`.
class FileResearchSessionStore implements ResearchSessionStore {
  static const String draftFileName = 'draft.json';

  Directory? _directory;

  Future<Directory> _directoryHandle() async {
    final cached = _directory;
    if (cached != null) return cached;
    final documents = await getApplicationDocumentsDirectory();
    final dir = Directory('${documents.path}/eyecue_research_sessions');
    await dir.create(recursive: true);
    return _directory = dir;
  }

  static String _safeId(String id) =>
      id.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');

  @override
  Future<Map<String, String>> readFinished() async {
    try {
      final dir = await _directoryHandle();
      final finished = <String, String>{};
      await for (final entity in dir.list()) {
        if (entity is! File) continue;
        final name = entity.uri.pathSegments.last;
        if (name == draftFileName || !name.endsWith('.json')) continue;
        finished[name.substring(0, name.length - '.json'.length)] = await entity
            .readAsString();
      }
      return finished;
    } catch (_) {
      // A missing/corrupt directory must not stop the app from starting.
      return const {};
    }
  }

  @override
  Future<String?> readDraft() async {
    try {
      final dir = await _directoryHandle();
      final file = File('${dir.path}/$draftFileName');
      if (!await file.exists()) return null;
      return await file.readAsString();
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> writeFinished(String id, String contents) async {
    final dir = await _directoryHandle();
    final file = File('${dir.path}/${_safeId(id)}.json');
    await file.writeAsString(contents, flush: true);
  }

  @override
  Future<void> deleteFinished(String id) async {
    try {
      final dir = await _directoryHandle();
      final file = File('${dir.path}/${_safeId(id)}.json');
      if (await file.exists()) await file.delete();
    } catch (_) {
      // Deleting is best effort; the in-memory list is the source of truth.
    }
  }

  @override
  Future<void> writeDraft(String? contents) async {
    final dir = await _directoryHandle();
    final file = File('${dir.path}/$draftFileName');
    if (contents == null) {
      if (await file.exists()) await file.delete();
      return;
    }
    await file.writeAsString(contents, flush: true);
  }
}

/// In-memory [ResearchSessionStore] used by tests.
class InMemoryResearchSessionStore implements ResearchSessionStore {
  InMemoryResearchSessionStore({this.failWrites = false});

  /// When true every write throws, so the "not saved" path is exercised.
  bool failWrites;

  final Map<String, String> finished = {};
  String? draft;

  @override
  Future<Map<String, String>> readFinished() async => Map.of(finished);

  @override
  Future<String?> readDraft() async => draft;

  @override
  Future<void> writeFinished(String id, String contents) async {
    if (failWrites) throw const FileSystemException('write failed');
    finished[id] = contents;
  }

  @override
  Future<void> deleteFinished(String id) async => finished.remove(id);

  @override
  Future<void> writeDraft(String? contents) async {
    if (failWrites) throw const FileSystemException('write failed');
    draft = contents;
  }
}

/// Outcome of [ResearchSessionService.finish].
class FinishResult {
  const FinishResult({required this.session, required this.saved});

  /// The frozen trial. It exists even when [saved] is false.
  final ResearchSession session;

  /// Whether the trial reached local storage before this result was returned.
  final bool saved;
}

/// One in-flight trial, persisted so an interrupted app run restores it paused.
class _Draft {
  _Draft({
    required this.id,
    required this.participantCode,
    required this.trialLabel,
    required List<DetectorModelRef> detectors,
    required List<ResearchInterval> intervals,
    this.closedDetections = 0,
    this.closedAlerts = 0,
    this.closedFrames = 0,
    this.baselineDetections = 0,
    this.baselineAlerts = 0,
    this.baselineFrames = 0,
  }) : detectors = List.of(detectors),
       intervals = List.of(intervals);

  final String id;
  final String participantCode;
  final String trialLabel;
  final List<DetectorModelRef> detectors;
  final List<ResearchInterval> intervals;
  int closedDetections;
  int closedAlerts;
  int closedFrames;
  int baselineDetections;
  int baselineAlerts;
  int baselineFrames;

  Map<String, dynamic> toJson(DateTime savedAt) => {
    'schemaVersion': 1,
    'id': id,
    'participantCode': participantCode,
    'trialLabel': trialLabel,
    'savedAt': savedAt.toUtc().toIso8601String(),
    'detectors': [
      for (final detector in detectors)
        {
          'id': detector.id,
          'name': detector.name,
          'fingerprint': detector.fingerprint,
          'classCount': detector.classCount,
        },
    ],
    'intervals': [for (final interval in intervals) interval.toJson()],
    'closedDetections': closedDetections,
    'closedAlerts': closedAlerts,
    'closedFrames': closedFrames,
    'baselineDetections': baselineDetections,
    'baselineAlerts': baselineAlerts,
    'baselineFrames': baselineFrames,
  };

  /// Restores a draft as interrupted: an interval left open by a crash is
  /// closed at the last persisted moment, so app-down time is never counted as
  /// active recording and never picks up later rows.
  static _Draft? fromJson(Map<String, dynamic> json) {
    final id = json['id'] as String?;
    if (id == null || id.isEmpty) return null;
    List<Map<String, dynamic>> maps(Object? value) => value is List
        ? [
            for (final entry in value)
              if (entry is Map) entry.cast<String, dynamic>(),
          ]
        : const [];
    final savedAt =
        DateTime.tryParse(json['savedAt'] as String? ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    final intervals = <ResearchInterval>[];
    for (final entry in maps(json['intervals'])) {
      final interval = ResearchInterval.fromJson(entry);
      if (interval.isClosed) {
        intervals.add(interval);
        continue;
      }
      final end = savedAt.isAfter(interval.start) ? savedAt : interval.start;
      intervals.add(ResearchInterval(interval.start, end));
    }
    if (intervals.isEmpty) return null;
    int count(String key) => (json[key] as num?)?.toInt() ?? 0;
    return _Draft(
      id: id,
      participantCode: json['participantCode'] as String? ?? '',
      trialLabel: json['trialLabel'] as String? ?? '',
      detectors: [
        for (final entry in maps(json['detectors']))
          DetectorModelRef(
            id: entry['id'] as String? ?? 'builtin',
            name: entry['name'] as String? ?? '',
            fingerprint: entry['fingerprint'] as String? ?? '',
            classCount: (entry['classCount'] as num?)?.toInt() ?? 0,
          ),
      ],
      intervals: intervals,
      closedDetections: count('closedDetections'),
      closedAlerts: count('closedAlerts'),
      closedFrames: count('closedFrames'),
      baselineDetections: count('baselineDetections'),
      baselineAlerts: count('baselineAlerts'),
      baselineFrames: count('baselineFrames'),
    );
  }
}

/// Explicit research-data recording, independent of the detection lifecycle.
///
/// Nothing is collected before [start]; [pause] freezes study accumulation only
/// — detection, depth, speech and guidance keep running — and [finish] freezes
/// an immutable [ResearchSession] that is persisted before any upload happens.
class ResearchSessionService extends ChangeNotifier {
  ResearchSessionService({
    required TelemetryService telemetry,
    ResearchSessionStore? store,
    TelemetryUploadService? uploadService,
    DateTime Function()? clock,
    this.maxStoredSessions = 20,
  }) : _telemetry = telemetry,
       _store = store ?? FileResearchSessionStore(),
       _uploadService = uploadService ?? TelemetryUploadService(),
       _clock = clock ?? DateTime.now,
       _appVersion = telemetry.appVersion;

  final TelemetryService _telemetry;
  final ResearchSessionStore _store;
  final TelemetryUploadService _uploadService;
  final DateTime Function() _clock;
  final String _appVersion;
  final Random _random = Random();

  /// Visible storage bound. A full store refuses [start] instead of evicting an
  /// unuploaded trial.
  final int maxStoredSessions;

  ResearchSessionState _state = ResearchSessionState.idle;
  _Draft? _draft;
  final List<ResearchSession> _sessions = [];
  final Set<String> _unsavedIds = {};
  final Map<String, String> _uploadStatus = {};
  bool _finishing = false;
  String? _uploadingId;
  String? _lastSaveError;

  ResearchSessionState get state => _state;

  /// True while the trial is actively collecting. [pause] sets this false
  /// without touching detection, so the detection screen can pause study
  /// logging before a model switch.
  bool get isRecording => _state == ResearchSessionState.recording;

  bool get isFinishing => _finishing;

  bool get isUploading => _uploadingId != null;

  String? get uploadingSessionId => _uploadingId;

  /// Finished trials, newest first.
  List<ResearchSession> get sessions => List.unmodifiable(_sessions);

  String? get lastSaveError => _lastSaveError;

  /// Whether [session] reached local storage.
  bool isSaved(ResearchSession session) => !_unsavedIds.contains(session.id);

  String get stateLabel => switch (_state) {
    ResearchSessionState.idle => 'Not recording',
    ResearchSessionState.recording => 'Recording',
    ResearchSessionState.paused => 'Paused',
    ResearchSessionState.finished => 'Finished',
  };

  String? get participantCode => _draft?.participantCode;

  String? get trialLabel => _draft?.trialLabel;

  String get detectorName {
    final draft = _draft;
    if (draft == null || draft.detectors.isEmpty) return '';
    return draft.detectors.map((detector) => detector.name).toSet().join(' → ');
  }

  /// Recorded time of the in-flight trial, excluding pauses.
  Duration get activeDuration {
    final draft = _draft;
    if (draft == null) return Duration.zero;
    var total = Duration.zero;
    for (final interval in draft.intervals) {
      total += interval.duration;
    }
    return total;
  }

  /// Wall-clock span of the in-flight trial, pauses included.
  Duration get wallClockDuration {
    final draft = _draft;
    if (draft == null || draft.intervals.isEmpty) return Duration.zero;
    return _clock().difference(draft.intervals.first.start);
  }

  /// Loads stored trials and restores an interrupted draft as paused.
  Future<void> load() async {
    try {
      final stored = await _store.readFinished();
      final restored = <ResearchSession>[];
      for (final contents in stored.values) {
        try {
          final json = jsonDecode(contents) as Map<String, dynamic>;
          restored.add(ResearchSession.fromJson(json));
        } catch (_) {
          // One unreadable file must not hide the other stored trials.
        }
      }
      restored.sort((a, b) => b.wallClockStart.compareTo(a.wallClockStart));
      _sessions
        ..clear()
        ..addAll(restored);
      final rawDraft = await _store.readDraft();
      if (rawDraft != null) {
        try {
          final draft = _Draft.fromJson(
            jsonDecode(rawDraft) as Map<String, dynamic>,
          );
          if (draft != null) {
            _draft = draft;
            _state = ResearchSessionState.paused;
            _resetBaselines(draft);
          }
        } catch (_) {
          // A corrupt draft is discarded rather than restored as recording.
        }
      }
    } finally {
      notifyListeners();
    }
  }

  /// Creates a fresh, opaque trial id and starts recording. Returns an
  /// actionable refusal message, or null on success.
  Future<String?> start({
    required String participantCode,
    required String trialLabel,
    required DetectorModelRef detector,
  }) async {
    if (_state == ResearchSessionState.recording ||
        _state == ResearchSessionState.paused) {
      return 'A trial is already running. Finish it before starting another.';
    }
    if (_sessions.length >= maxStoredSessions) {
      return 'Stored trials are full ($maxStoredSessions). Upload or discard a '
          'stored trial before starting another; nothing has been deleted.';
    }
    // Same rule the upload enforces, so a trial cannot be created that can
    // never be uploaded.
    final metadata = ResearchSessionMetadata(
      participantCode: participantCode,
      studyScenario: trialLabel,
      uploadToken: '',
    );
    if (!metadata.isValid) {
      return 'Enter a participant code (letters, digits, - or _) and a trial '
          'label of at most 80 characters.';
    }
    final now = _clock();
    final draft = _Draft(
      id: _newId(now),
      participantCode: participantCode.trim(),
      trialLabel: trialLabel.trim(),
      detectors: [detector],
      intervals: [ResearchInterval(now)],
    );
    _resetBaselines(draft);
    _draft = draft;
    _state = ResearchSessionState.recording;
    _lastSaveError = null;
    notifyListeners();
    await _persistDraft();
    return null;
  }

  /// Closes the current interval. Detection is untouched.
  Future<void> pause() async {
    final draft = _draft;
    if (_state != ResearchSessionState.recording || draft == null) return;
    _closeInterval(draft, _clock());
    _state = ResearchSessionState.paused;
    notifyListeners();
    await _persistDraft();
  }

  /// Opens a new interval; increments during the pause were never counted.
  Future<void> resume() async {
    final draft = _draft;
    if (_state != ResearchSessionState.paused || draft == null) return;
    draft.intervals.add(ResearchInterval(_clock()));
    _resetBaselines(draft);
    _state = ResearchSessionState.recording;
    notifyListeners();
    await _persistDraft();
  }

  /// A model switch is a study pause plus a recorded boundary.
  ///
  /// The detection screen calls this before replacing the model: study logging
  /// pauses, later rows carry the new identity, and an explicit [resume] is
  /// required so setup time never enters the trial.
  Future<void> noteDetectorChange(DetectorModelRef? detector) async {
    final draft = _draft;
    if (draft == null) return;
    if (_state == ResearchSessionState.recording) await pause();
    if (detector == null) return;
    if (draft.detectors.isNotEmpty && draft.detectors.last == detector) return;
    draft.detectors.add(detector);
    notifyListeners();
    await _persistDraft();
  }

  /// Freezes the trial and persists it before returning.
  ///
  /// Returns null when there is no in-flight trial or a finish is already in
  /// progress, so a concurrent second finish cannot alter the snapshot.
  Future<FinishResult?> finish() async {
    if (_finishing) return null;
    final draft = _draft;
    if (draft == null) return null;
    _finishing = true;
    notifyListeners();
    try {
      final now = _clock();
      if (_state == ResearchSessionState.recording) {
        _closeInterval(draft, now);
      }
      bool inTrial(DateTime timestamp) =>
          draft.intervals.any((interval) => interval.contains(timestamp));

      var activeMs = 0;
      for (final interval in draft.intervals) {
        activeMs += interval.duration.inMilliseconds;
      }
      final session = ResearchSession(
        id: draft.id,
        participantCode: draft.participantCode,
        trialLabel: draft.trialLabel,
        detectors: draft.detectors,
        wallClockStart: draft.intervals.first.start,
        wallClockEnd: now,
        intervals: draft.intervals,
        activeDurationMs: activeMs,
        totalDetections: draft.closedDetections,
        highPriorityAlerts: draft.closedAlerts,
        framesProcessed: draft.closedFrames,
        records: _telemetry.records
            .where((record) => inTrial(record.timestamp))
            .toList(),
        samples: _telemetry.samples
            .where((sample) => inTrial(sample.timestamp))
            .toList(),
        failures: _telemetry.failures
            .where((record) => inTrial(record.failure.timestamp))
            .toList(),
        fallbacks: _telemetry.fallbacks
            .where((record) => inTrial(record.timestamp))
            .toList(),
        recoveries: _telemetry.recoveries
            .where((record) => inTrial(record.timestamp))
            .toList(),
        corrections: _telemetry.corrections
            .where((record) => inTrial(record.timestamp))
            .toList(),
        alertRecords: _telemetry.alertRecords
            .where((record) => inTrial(record.terminalAt))
            .toList(),
        alertCounters: _telemetry.alertCounters,
        appVersion: _appVersion,
      );
      final saved = await _persist(session);
      _sessions.insert(0, session);
      _draft = null;
      _state = ResearchSessionState.finished;
      try {
        await _store.writeDraft(null);
      } catch (_) {
        // The finished file is authoritative; a stale draft restores as paused.
      }
      return FinishResult(session: session, saved: saved);
    } finally {
      _finishing = false;
      notifyListeners();
    }
  }

  /// Uploads one finished trial through the frozen snapshot.
  ///
  /// The trial's own participant code and label are used, so a typo in a dialog
  /// cannot move data to another participant; only the transient study token
  /// comes from [metadata]. The trial id becomes `session.id`, which the server
  /// keys idempotency on, so a retry is a duplicate rather than a second row.
  Future<TelemetryUploadResult> upload({
    required ResearchSession session,
    required ResearchSessionMetadata metadata,
    AppSettings? settings,
  }) async {
    if (_uploadingId != null) {
      return const TelemetryUploadResult.failure(
        'An upload is already in progress. Wait for it to finish.',
      );
    }
    _uploadingId = session.id;
    notifyListeners();
    try {
      final result = await _uploadService.upload(
        telemetry: session,
        metadata: ResearchSessionMetadata(
          participantCode: session.participantCode,
          studyScenario: session.trialLabel,
          uploadToken: metadata.uploadToken,
        ),
        settings: settings,
      );
      if (_sessions.any((stored) => stored.id == session.id)) {
        _uploadStatus[session.id] = result.isSuccess
            ? 'Uploaded'
            : 'Upload failed';
      }
      return result;
    } finally {
      _uploadingId = null;
      notifyListeners();
    }
  }

  /// Per-trial upload state text, or null when the trial was never uploaded.
  String? uploadStatusFor(ResearchSession session) {
    if (_uploadingId == session.id) return 'Uploading';
    return _uploadStatus[session.id];
  }

  /// Deletes one stored trial. Nothing else is touched.
  Future<void> discard(ResearchSession session) async {
    _sessions.removeWhere((stored) => stored.id == session.id);
    _unsavedIds.remove(session.id);
    _uploadStatus.remove(session.id);
    notifyListeners();
    await _store.deleteFinished(session.id);
  }

  void _closeInterval(_Draft draft, DateTime now) {
    if (draft.intervals.isEmpty) {
      draft.intervals.add(ResearchInterval(now));
      return;
    }
    final last = draft.intervals.last;
    if (last.isClosed) return;
    draft.intervals[draft.intervals.length - 1] = last.closedAt(
      now.isAfter(last.start) ? now : last.start,
    );
    draft.closedDetections += _delta(
      _telemetry.totalDetections,
      draft.baselineDetections,
    );
    draft.closedAlerts += _delta(
      _telemetry.highPriorityAlerts,
      draft.baselineAlerts,
    );
    draft.closedFrames += _delta(
      _telemetry.framesProcessed,
      draft.baselineFrames,
    );
  }

  /// Cumulative counters only ever grow, but the record buffer is capped, so a
  /// negative difference (eviction) is treated as zero rather than as loss of
  /// earlier increments.
  static int _delta(int current, int baseline) =>
      current > baseline ? current - baseline : 0;

  void _resetBaselines(_Draft draft) {
    draft.baselineDetections = _telemetry.totalDetections;
    draft.baselineAlerts = _telemetry.highPriorityAlerts;
    draft.baselineFrames = _telemetry.framesProcessed;
  }

  Future<bool> _persist(ResearchSession session) async {
    try {
      await _store.writeFinished(session.id, jsonEncode(session.toJson()));
      _unsavedIds.remove(session.id);
      _lastSaveError = null;
      return true;
    } catch (_) {
      _unsavedIds.add(session.id);
      _lastSaveError =
          'The trial was finished but could not be saved on this device. '
          'Export it now to keep the data.';
      return false;
    }
  }

  Future<void> _persistDraft() async {
    final draft = _draft;
    try {
      await _store.writeDraft(
        draft == null ? null : jsonEncode(draft.toJson(_clock())),
      );
    } catch (_) {
      // A draft write failure must not interrupt recording; the trial is still
      // in memory and [finish] reports its own save result.
    }
  }

  String _newId(DateTime now) =>
      'trial-${now.microsecondsSinceEpoch}-'
      '${_random.nextInt(0x100000).toRadixString(16)}';
}
