import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/alert_lifecycle.dart';
import '../models/app_settings.dart';
import '../models/detection_correction.dart';
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
  /// [directory] overrides the documents directory (tests use a temp dir).
  FileResearchSessionStore([this._directory]);

  static const String draftFileName = 'draft.json';

  Directory? _directory;
  bool _cleanedTempFiles = false;

  Future<Directory> _directoryHandle() async {
    var dir = _directory;
    if (dir == null) {
      final documents = await getApplicationDocumentsDirectory();
      dir = Directory('${documents.path}/eyecue_research_sessions');
      await dir.create(recursive: true);
      _directory = dir;
    }
    if (!_cleanedTempFiles) {
      _cleanedTempFiles = true;
      await _deleteTempFiles(dir);
    }
    return dir;
  }

  /// Best effort: an orphan `<id>.json.tmp` from a process death between write
  /// and rename is never read again, so it is only wasted space. A missing or
  /// locked file must not stop the app from starting.
  static Future<void> _deleteTempFiles(Directory dir) async {
    try {
      await for (final entity in dir.list()) {
        if (entity is! File || !entity.path.endsWith('.tmp')) continue;
        try {
          await entity.delete();
        } catch (_) {}
      }
    } catch (_) {}
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

  /// Write a temp file, then rename: an interrupted write leaves the previous
  /// good file in place instead of a truncated one.
  static Future<void> _writeAtomically(File file, String contents) async {
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(contents, flush: true);
    await temp.rename(file.path);
  }

  @override
  Future<void> writeFinished(String id, String contents) async {
    final dir = await _directoryHandle();
    await _writeAtomically(File('${dir.path}/${_safeId(id)}.json'), contents);
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
    await _writeAtomically(file, contents);
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
    Map<String, dynamic> closedAlertCounters = const {},
    Map<String, dynamic> baselineAlertCounters = const {},
    this.rowsIncomplete = false,
  }) : detectors = List.of(detectors),
       intervals = List.of(intervals),
       closedAlertCounters = Map.of(closedAlertCounters),
       baselineAlertCounters = Map.of(baselineAlertCounters);

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

  /// Sum of the per-interval [AlertCounters] deltas.
  Map<String, dynamic> closedAlertCounters;

  /// Captured rows, owned by this draft: the live telemetry rings may evict
  /// theirs without touching these. Only rows written while recording enter.
  final List<TelemetryRecord> records = [];
  final List<RuntimeSample> samples = [];
  final List<TelemetryFailureRecord> failures = [];
  final List<EngineFallbackRecord> fallbacks = [];
  final List<InferenceRecoveryRecord> recoveries = [];
  final List<DetectionCorrection> corrections = [];
  final List<AlertLifecycleRecord> alertRecords = [];

  /// Each captured row's JSON, encoded once at capture time (microseconds), so a
  /// checkpoint joins fragments instead of serialising the history again.
  final List<String> _recordsJson = [];
  final List<String> _samplesJson = [];
  final List<String> _failuresJson = [];
  final List<String> _fallbacksJson = [];
  final List<String> _recoveriesJson = [];
  final List<String> _correctionsJson = [];
  final List<String> _alertRecordsJson = [];

  void addRecord(TelemetryRecord record) {
    records.add(record);
    _recordsJson.add(jsonEncode(record.toJson()));
  }

  void addSample(RuntimeSample sample) {
    samples.add(sample);
    _samplesJson.add(jsonEncode(sample.toJson()));
  }

  void addFailure(TelemetryFailureRecord failure) {
    failures.add(failure);
    _failuresJson.add(jsonEncode(failure.toJson()));
  }

  void addFallback(EngineFallbackRecord fallback) {
    fallbacks.add(fallback);
    _fallbacksJson.add(jsonEncode(fallback.toJson()));
  }

  void addRecovery(InferenceRecoveryRecord recovery) {
    recoveries.add(recovery);
    _recoveriesJson.add(jsonEncode(recovery.toJson()));
  }

  void addCorrection(DetectionCorrection correction) {
    corrections.add(correction);
    _correctionsJson.add(jsonEncode(correction.toJson()));
  }

  void addAlertRecord(AlertLifecycleRecord record) {
    alertRecords.add(record);
    _alertRecordsJson.add(jsonEncode(record.toJson()));
  }

  /// True when the draft predates row capture, so its counters exist without
  /// their measurements. Marked instead of fabricating rows.
  final bool rowsIncomplete;

  /// Cumulative counters as they stood when the running interval opened.
  Map<String, dynamic> baselineAlertCounters;

  /// The draft document: the scalars are encoded here, and every row collection
  /// is the fragments its capture already encoded. Called from the queued
  /// checkpoint, never from the detection path.
  String encode(DateTime savedAt) {
    final header = jsonEncode({
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
      'closedAlertCounters': closedAlertCounters,
      'baselineAlertCounters': baselineAlertCounters,
      'rowsIncomplete': rowsIncomplete,
    });
    final rows = <String, List<String>>{
      'records': _recordsJson,
      'samples': _samplesJson,
      'failures': _failuresJson,
      'fallbacks': _fallbacksJson,
      'recoveries': _recoveriesJson,
      'corrections': _correctionsJson,
      'alertRecords': _alertRecordsJson,
    };
    // Drop the header's closing brace, append the fragments, close again.
    final buffer = StringBuffer(header.substring(0, header.length - 1));
    for (final entry in rows.entries) {
      buffer
        ..write(',')
        ..write(jsonEncode(entry.key))
        ..write(':[')
        ..write(entry.value.join(','))
        ..write(']');
    }
    return (buffer..write('}')).toString();
  }

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
    Map<String, dynamic> counters(Object? value) =>
        value is Map ? value.cast<String, dynamic>() : const {};
    final draft = _Draft(
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
      closedAlertCounters: counters(json['closedAlertCounters']),
      baselineAlertCounters: counters(json['baselineAlertCounters']),
      // A schema-1 draft written before rows were persisted has counters but no
      // measurements: it restores visibly incomplete, never with invented rows.
      rowsIncomplete:
          json['rowsIncomplete'] == true || !json.containsKey('records'),
    );
    // Restored rows are re-encoded once here, off the detection path, so a
    // restored draft checkpoints from fragments like a live one.
    for (final entry in maps(json['records'])) {
      draft.addRecord(TelemetryRecord.fromJson(entry));
    }
    for (final entry in maps(json['samples'])) {
      draft.addSample(RuntimeSample.fromJson(entry));
    }
    for (final entry in maps(json['failures'])) {
      draft.addFailure(TelemetryFailureRecord.fromJson(entry));
    }
    for (final entry in maps(json['fallbacks'])) {
      draft.addFallback(EngineFallbackRecord.fromJson(entry));
    }
    for (final entry in maps(json['recoveries'])) {
      draft.addRecovery(InferenceRecoveryRecord.fromJson(entry));
    }
    for (final entry in maps(json['corrections'])) {
      draft.addCorrection(DetectionCorrection.fromJson(entry));
    }
    for (final entry in maps(json['alertRecords'])) {
      draft.addAlertRecord(AlertLifecycleRecord.fromJson(entry));
    }
    return draft;
  }
}

/// Explicit research-data recording, independent of the detection lifecycle.
///
/// Nothing is collected before [start]; [pause] freezes study accumulation only
/// — detection, depth, speech and guidance keep running — and [finish] freezes
/// an immutable [ResearchSession] that is persisted before any upload happens.
class ResearchSessionService extends ChangeNotifier implements TelemetrySink {
  ResearchSessionService({
    required TelemetryService telemetry,
    ResearchSessionStore? store,
    TelemetryUploadService? uploadService,
    DateTime Function()? clock,
    this.maxStoredSessions = 20,
    this.maxTrialRecords = 10000,
    this.maxTrialSamples = 2000,
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

  /// Per-trial capture capacity, 5× the live record and sample rings. Reaching
  /// it pauses collection visibly and keeps every captured row — there is no
  /// roll-over and nothing is trimmed, so a trial never silently loses data.
  final int maxTrialRecords;
  final int maxTrialSamples;

  ResearchSessionState _state = ResearchSessionState.idle;
  _Draft? _draft;
  final List<ResearchSession> _sessions = [];
  final Set<String> _unsavedIds = {};
  final Map<String, String> _uploadStatus = {};
  bool _finishing = false;
  String? _uploadingId;
  String? _lastSaveError;
  String? _pauseReason;
  Listenable? _watchedDetectorChanges;
  DetectorModelRef Function()? _detectorIdentity;

  /// Serialises draft writes: an older queued checkpoint must never land after a
  /// newer Pause, nor after the delete that follows Finish.
  Future<void> _writeChain = Future<void>.value();
  int _draftSequence = 0;
  int _writtenSequence = 0;
  int _capturedSinceCheckpoint = 0;
  DateTime? _lastCheckpointAt;

  static const Duration _checkpointInterval = Duration(seconds: 5);
  static const int _checkpointRows = 100;

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

  /// Why collection stopped on its own; null when the researcher paused.
  String? get pauseReason => _pauseReason;

  /// Whether [session] reached local storage.
  bool isSaved(ResearchSession session) => !_unsavedIds.contains(session.id);

  // --- TelemetrySink: the trial owns every row it captured -------------------

  @override
  void onDetection(TelemetryRecord record) =>
      _capture(record.timestamp, (draft) => draft.addRecord(record));

  @override
  void onSample(RuntimeSample sample) =>
      _capture(sample.timestamp, (draft) => draft.addSample(sample));

  @override
  void onFailure(TelemetryFailureRecord record) =>
      _capture(record.failure.timestamp, (draft) => draft.addFailure(record));

  @override
  void onFallback(EngineFallbackRecord record) =>
      _capture(record.timestamp, (draft) => draft.addFallback(record));

  @override
  void onRecovery(InferenceRecoveryRecord record) =>
      _capture(record.timestamp, (draft) => draft.addRecovery(record));

  @override
  void onCorrection(DetectionCorrection correction) => _capture(
    correction.timestamp,
    (draft) => draft.addCorrection(correction),
  );

  @override
  void onAlertLifecycle(AlertLifecycleRecord record) =>
      _capture(record.terminalAt, (draft) => draft.addAlertRecord(record));

  /// Appends one live row to the trial only when it belongs to a recorded
  /// interval of a recording trial, so paused activity, post-finish rows and a
  /// delayed event outside the intervals never enter.
  void _capture(DateTime timestamp, void Function(_Draft draft) add) {
    final draft = _draft;
    // A finish in progress has already taken its snapshot, so a row arriving
    // now could only be captured and then discarded: it is not captured.
    if (_finishing ||
        _state != ResearchSessionState.recording ||
        draft == null) {
      return;
    }
    if (!draft.intervals.any((interval) => interval.contains(timestamp))) {
      return;
    }
    add(draft);
    _checkpointIfDue();
    if (draft.records.length >= maxTrialRecords ||
        draft.samples.length >= maxTrialSamples) {
      // The row that reaches capacity is kept: stop visibly instead of trimming.
      _pauseReason =
          'This trial reached its capture capacity ($maxTrialRecords detections '
          'and $maxTrialSamples samples), so logging paused. Everything already '
          'captured is kept — finish and export it.';
      unawaited(pause());
    }
  }

  /// A bounded checkpoint: every ~5 s of recording or every 100 captured rows,
  /// whichever comes first. Never per frame and never awaited by the writer, so
  /// the frame that produced the row is not blocked by a file write.
  void _checkpointIfDue() {
    _capturedSinceCheckpoint++;
    final now = _clock();
    final last = _lastCheckpointAt;
    if (_capturedSinceCheckpoint < _checkpointRows &&
        last != null &&
        now.difference(last) < _checkpointInterval) {
      return;
    }
    _capturedSinceCheckpoint = 0;
    _lastCheckpointAt = now;
    unawaited(_persistDraft());
  }

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
  ///
  /// The running interval is counted up to the injected clock, so the number
  /// grows while recording instead of reading zero until the first pause.
  Duration get activeDuration {
    final draft = _draft;
    if (draft == null) return Duration.zero;
    var total = Duration.zero;
    for (final interval in draft.intervals) {
      final end = interval.end;
      if (end != null) {
        total += end.difference(interval.start);
        continue;
      }
      final now = _clock();
      if (now.isAfter(interval.start)) {
        total += now.difference(interval.start);
      }
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
    if (_draft != null) {
      // A failed finish kept the draft as the only durable copy of that trial,
      // so a new Start must not overwrite it.
      return 'The last trial could not be saved and is held as a draft on this '
          'device. Retry Finish before starting another.';
    }
    if (_sessions.length >= maxStoredSessions) {
      // Uploading keeps the stored trial, so it cannot be offered here as the
      // way to free a slot.
      return 'Stored trials are full ($maxStoredSessions). Discard a stored '
          'trial before starting another; uploading keeps it stored and does '
          'not free a slot, and nothing has been deleted.';
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
    // Capture is per service: subscribing here leaves any other service's own
    // trial publishing to itself.
    _telemetry.subscribe(this);
    _lastSaveError = null;
    _pauseReason = null;
    _capturedSinceCheckpoint = 0;
    _lastCheckpointAt = now;
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
    _telemetry.subscribe(this);
    // A capacity self-stop keeps explaining itself until a new trial starts,
    // because resuming does not create room.
    _capturedSinceCheckpoint = 0;
    _lastCheckpointAt = _clock();
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
    // A notification that does not change the identity is not a boundary, so it
    // neither pauses nor appends. The selection notifies on a no-op re-select.
    if (detector != null &&
        draft.detectors.isNotEmpty &&
        draft.detectors.last == detector) {
      return;
    }
    if (_state == ResearchSessionState.recording) await pause();
    if (detector == null) return;
    draft.detectors.add(detector);
    notifyListeners();
    await _persistDraft();
  }

  /// Pauses on a detector change from wherever the selection is committed.
  ///
  /// Owning the reaction here — not in the Detection page, which the shell
  /// builds lazily — is what makes a model switch pause logging even when that
  /// page was never opened. Idempotent: the same notifier is subscribed once,
  /// and [noteDetectorChange] ignores a repeat of the current identity.
  void watchDetectorModel(
    Listenable changes,
    DetectorModelRef Function() identity,
  ) {
    if (identical(changes, _watchedDetectorChanges)) return;
    _watchedDetectorChanges?.removeListener(_handleDetectorModelChanged);
    _watchedDetectorChanges = changes;
    _detectorIdentity = identity;
    changes.addListener(_handleDetectorModelChanged);
  }

  void _handleDetectorModelChanged() {
    unawaited(noteDetectorChange(_detectorIdentity?.call()));
  }

  @override
  void dispose() {
    _watchedDetectorChanges?.removeListener(_handleDetectorModelChanged);
    // Never leave a disposed service receiving live rows.
    _telemetry.unsubscribe(this);
    super.dispose();
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
      // A retried Finish after a failed save re-persists the snapshot it
      // already froze, so the stored bytes and the in-memory trial stay
      // identical instead of drifting to a second finish time.
      ResearchSession? pending;
      for (final stored in _sessions) {
        if (stored.id == draft.id && !isSaved(stored)) pending = stored;
      }
      if (pending != null) {
        final saved = await _persist(pending);
        if (saved) await _dropDraft();
        return FinishResult(session: pending, saved: saved);
      }
      final now = _clock();
      if (_state == ResearchSessionState.recording) {
        _closeInterval(draft, now);
      }
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
        // The trial's own capture, including rows written since the last
        // checkpoint. Never the live rings: they are capped, shared with
        // ordinary use, and empty in a fresh app process.
        records: List.of(draft.records),
        samples: List.of(draft.samples),
        failures: List.of(draft.failures),
        fallbacks: List.of(draft.fallbacks),
        recoveries: List.of(draft.recoveries),
        corrections: List.of(draft.corrections),
        alertRecords: List.of(draft.alertRecords),
        rowsIncomplete: draft.rowsIncomplete,
        // Interval deltas, like every other counter: the live snapshot is
        // cumulative over the whole app run.
        alertCounters: AlertCounters.fromJson(draft.closedAlertCounters),
        appVersion: _appVersion,
      );
      final saved = await _persist(session);
      _sessions.insert(0, session);
      _state = ResearchSessionState.finished;
      if (saved) {
        // Only a saved trial may lose its draft.
        await _dropDraft();
      } else {
        // A failed write leaves the draft as the only durable copy of the whole
        // trial, so it is kept — brought up to the closed interval and counters
        // so a restart restores exactly this trial — and the save error stays
        // the message the researcher sees.
        final saveError = _lastSaveError;
        await _persistDraft();
        _lastSaveError = saveError;
      }
      return FinishResult(session: session, saved: saved);
    } finally {
      _finishing = false;
      _telemetry.unsubscribe(this);
      notifyListeners();
    }
  }

  /// Deletes the draft after its trial is durable. Queued on the draft chain,
  /// so no older checkpoint can land after this delete and resurrect it.
  Future<void> _dropDraft() async {
    _draft = null;
    await _persistDraft();
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
    if (_draft?.id == session.id) {
      // The draft of an unsaved trial is the only copy left: discarding must
      // drop it too, or a restart would resurrect the discarded trial.
      _state = ResearchSessionState.idle;
      _telemetry.unsubscribe(this);
      await _dropDraft();
      notifyListeners();
    }
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
      _telemetry.detectionCount,
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
    draft.closedAlertCounters = _addCounters(
      draft.closedAlertCounters,
      _counterDelta(
        _telemetry.alertCounters.toJson(),
        draft.baselineAlertCounters,
      ),
    );
  }

  /// Cumulative counters only ever grow, so a baseline ahead of the current
  /// value (a restart) is clamped to zero rather than subtracting from the trial.
  /// Detections come from [TelemetryService.detectionCount], not from the capped
  /// record buffer, so eviction cannot flatten that delta.
  static int _delta(int current, int baseline) =>
      current > baseline ? current - baseline : 0;

  void _resetBaselines(_Draft draft) {
    draft.baselineDetections = _telemetry.detectionCount;
    draft.baselineAlerts = _telemetry.highPriorityAlerts;
    draft.baselineFrames = _telemetry.framesProcessed;
    draft.baselineAlertCounters = _telemetry.alertCounters.toJson();
  }

  /// Per-field difference of two cumulative counter snapshots.
  static Map<String, dynamic> _counterDelta(
    Map<String, dynamic> current,
    Map<String, dynamic> baseline,
  ) {
    int count(Map<String, dynamic> counters, String key) =>
        (counters[key] as num?)?.toInt() ?? 0;
    final delta = <String, dynamic>{
      for (final key in current.keys)
        if (key != 'rejectedByReason')
          key: _delta(count(current, key), count(baseline, key)),
      'rejectedByReason': _reasonDelta(current, baseline),
    };
    return delta;
  }

  /// Field-wise sum of two interval deltas.
  static Map<String, dynamic> _addCounters(
    Map<String, dynamic> a,
    Map<String, dynamic> b,
  ) {
    int count(Map<String, dynamic> counters, String key) =>
        (counters[key] as num?)?.toInt() ?? 0;
    final sum = <String, dynamic>{
      for (final key in {...a.keys, ...b.keys})
        if (key != 'rejectedByReason') key: count(a, key) + count(b, key),
    };
    final reasons = _reasons(a);
    for (final entry in _reasons(b).entries) {
      reasons.update(
        entry.key,
        (value) => value + entry.value,
        ifAbsent: () => entry.value,
      );
    }
    sum['rejectedByReason'] = reasons;
    return sum;
  }

  static Map<String, int> _reasonDelta(
    Map<String, dynamic> current,
    Map<String, dynamic> baseline,
  ) {
    final now = _reasons(current);
    final before = _reasons(baseline);
    final delta = <String, int>{};
    for (final reason in {...before.keys, ...now.keys}) {
      final difference = _delta(now[reason] ?? 0, before[reason] ?? 0);
      if (difference > 0) delta[reason] = difference;
    }
    return delta;
  }

  static Map<String, int> _reasons(Map<String, dynamic> counters) => {
    for (final entry
        in ((counters['rejectedByReason'] as Map?) ?? const {}).entries)
      '${entry.key}': (entry.value as num?)?.toInt() ?? 0,
  };

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

  /// Every draft write goes through one chain with an increasing sequence, so a
  /// slow older checkpoint can never overwrite a later Pause, and the delete
  /// after Finish can never be overtaken by a checkpoint queued before it.
  Future<void> _persistDraft() async {
    final draft = _draft;
    final sequence = ++_draftSequence;
    final write = _writeChain.then((_) async {
      if (sequence <= _writtenSequence) return;
      // Assembled here, in the queued write, never on the caller's stack: the
      // detection path only ever encodes the single row it captured.
      final contents = draft?.encode(_clock());
      await _store.writeDraft(contents);
      _writtenSequence = sequence;
    });
    // The chain must survive a failed write, or every later checkpoint dies.
    _writeChain = write.catchError((Object _) {});
    try {
      await write;
      if (_draft != null) _lastSaveError = null;
    } catch (_) {
      // Nothing is durable yet: the rows stay in memory, the failure is
      // reported, and [finish] still returns its own write result.
      if (_draft != null) {
        _lastSaveError =
            'This trial is kept in memory but could not be checkpointed on this '
            'device. Finish it and export the data to keep it.';
        notifyListeners();
      }
    }
  }

  String _newId(DateTime now) =>
      'trial-${now.microsecondsSinceEpoch}-'
      '${_random.nextInt(0x100000).toRadixString(16)}';
}
