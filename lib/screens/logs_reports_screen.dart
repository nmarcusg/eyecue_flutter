import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemUiOverlayStyle;

import '../models/alert_lifecycle.dart';
import '../models/app_settings.dart';
import '../models/detection_correction.dart';
import '../models/detection_info.dart';
import '../models/detector_model.dart';
import '../models/model_config.dart';
import '../models/research_session.dart';
import '../services/correction_service.dart';
import '../services/detector_model_service.dart';
import '../services/research_session_service.dart';
import '../services/settings_service.dart';
import '../services/telemetry_export_service.dart';
import '../services/telemetry_service.dart';
import '../services/telemetry_upload_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_home_theme.dart';
import '../theme/app_radii.dart';
import '../theme/app_spacing.dart';
import '../widgets/accessible_button.dart';
import '../widgets/charts.dart';

/// Logs & Reports — researcher/developer-facing telemetry dashboard.
///
/// Deliberately reached from Settings (not the main navigation) so it does not
/// add cognitive load for visually impaired users, per the thesis. Tabs:
/// Overview, Charts, Logs.
///
/// Honesty rules implemented here:
///  * Accuracy/Precision/Recall/F1/mAP are **not** computed — they require
///    ground-truth labels and are shown as unavailable.
///  * Raw confidence is never labeled as accuracy.
class LogsReportsScreen extends StatefulWidget {
  final TelemetryService telemetry;
  final SettingsService? settings;
  final CorrectionService? corrections;
  final TelemetryExportService? exportService;
  final TelemetryUploadService? uploadService;

  /// The app's research-session service. Optional only so widget tests can
  /// build the screen without file-system channels.
  final ResearchSessionService? researchSessions;

  /// The loaded detector selection, named on the Start-logging confirmation.
  final DetectorModelService? detectorModel;

  const LogsReportsScreen({
    super.key,
    required this.telemetry,
    this.settings,
    this.corrections,
    this.exportService,
    this.uploadService,
    this.researchSessions,
    this.detectorModel,
  });

  @override
  State<LogsReportsScreen> createState() => _LogsReportsScreenState();
}

class _LogsReportsScreenState extends State<LogsReportsScreen> {
  late final TelemetryExportService _exportService =
      widget.exportService ?? TelemetryExportService();
  late final TelemetryUploadService _uploadService =
      widget.uploadService ?? TelemetryUploadService();
  late final ResearchSessionService _sessions =
      widget.researchSessions ??
      ResearchSessionService(telemetry: widget.telemetry);
  bool _exporting = false;
  bool _uploading = false;

  @override
  void initState() {
    super.initState();
    // The trial reacts to the app-wide selection itself, so a model change
    // pauses logging even when the Detection page was never built.
    final detectorModel = widget.detectorModel;
    if (detectorModel != null) {
      _sessions.watchDetectorModel(
        detectorModel,
        () => detectorModel.current.ref,
      );
    }
  }

  /// The detector a new trial would be recorded with.
  DetectorModelRef get _detectorRef =>
      widget.detectorModel?.current.ref ??
      const DetectorModelRef(
        id: 'builtin',
        name: 'Built-in YOLOv8n',
        fingerprint: DetectorModel.builtInFingerprint,
        classCount: 0,
      );

  /// Selected detector model id for the charts and the log list; `null` is the
  /// explicit "All models (mixed)" option.
  String? _modelFilter;

  @override
  Widget build(BuildContext context) {
    // Route-local light theme: reuse the established Home-local light builder
    // for this pushed route only. The global dark theme and the underlying
    // shell navigation bar are unchanged, and popping the route leaves the
    // other tabs untouched.
    return Theme(
      data: buildHomeTheme(),
      // The route uses a light surface, so the status bar icons must be dark to
      // remain visible against it. This AnnotatedRegion is scoped to the pushed
      // route only, matching the existing Settings and Help light routes.
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.dark,
        child: DefaultTabController(
          length: 3,
          child: Scaffold(
            appBar: AppBar(
              title: const Text('Logs & Reports'),
              bottom: const TabBar(
                tabs: [
                  Tab(text: 'Overview'),
                  Tab(text: 'Charts'),
                  Tab(text: 'Logs'),
                ],
              ),
            ),
            body: ListenableBuilder(
              listenable: Listenable.merge([
                widget.telemetry,
                _sessions,
                if (widget.corrections != null) widget.corrections!,
              ]),
              builder: (context, _) {
                return TabBarView(
                  children: [
                    _OverviewTab(
                      exporting: _exporting,
                      onExportJson: () => _export(csv: false),
                      onExportCsv: () => _export(csv: true),
                      uploading: _uploading,
                      uploadConfigured: _uploadService.isConfigured,
                      onUpload: _upload,
                      sessions: _sessions,
                      currentDetectorName: _detectorRef.name,
                      onStart: _startSession,
                      onPause: _pauseSession,
                      onResume: _resumeSession,
                      onFinish: _finishSession,
                      onUploadStored: _uploadStored,
                      onExportStored: _exportStored,
                      onDiscardStored: _discardStored,
                    ),
                    _ChartsTab(
                      modelFilter: _modelFilter,
                      onModelFilterChanged: _selectModelFilter,
                    ),
                    _LogsTab(
                      modelFilter: _modelFilter,
                      onModelFilterChanged: _selectModelFilter,
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  void _selectModelFilter(String? modelId) =>
      setState(() => _modelFilter = modelId);

  Future<void> _upload() async {
    if (_uploading || !_uploadService.isConfigured) return;
    if (_sessions.state != ResearchSessionState.idle) {
      // Once a trial exists in this run the live buffer holds that respondent's
      // rows under the app-lifetime id, so only the finished trial is uploaded.
      _showMessage(
        'A research trial was started in this run. Upload the finished trial '
        'from the stored trials list instead of this app session.',
        isError: true,
      );
      return;
    }
    final metadata = await _requestUploadMetadata();
    if (metadata == null || !mounted) return;

    setState(() => _uploading = true);
    try {
      final result = await _uploadService.upload(
        telemetry: widget.telemetry,
        settings: widget.settings?.settings,
        metadata: metadata,
      );
      if (!mounted) return;
      // A replay writes nothing, so it gets its own message rather than the
      // plain success text. Still success-like, so not styled as an error.
      _showMessage(
        result.isAlreadyUploaded
            ? result.message!
            : result.isSuccess
            ? 'Session uploaded to the research database.'
            : result.errorMessage!,
        isError: !result.isSuccess,
      );
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<ResearchSessionMetadata?> _requestUploadMetadata() => showDialog(
    context: context,
    builder: (_) => const _UploadMetadataDialog(),
  );

  Future<void> _export({required bool csv}) async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      final file = csv
          ? await _exportService.writeCsv(
              telemetry: widget.telemetry,
              settings: widget.settings?.settings,
            )
          : await _exportService.writeJson(
              telemetry: widget.telemetry,
              settings: widget.settings?.settings,
            );
      if (!mounted) return;
      final filename = file.uri.pathSegments.isEmpty
          ? 'telemetry export'
          : file.uri.pathSegments.last;
      _showMessage('Export saved: $filename');
    } catch (_) {
      if (!mounted) return;
      _showMessage('Export could not be saved. Try again.', isError: true);
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _startSession() async {
    final request = await showDialog<_StartSessionRequest>(
      context: context,
      builder: (_) => _StartSessionDialog(detectorName: _detectorRef.name),
    );
    if (request == null || !mounted) return;
    final error = await _sessions.start(
      participantCode: request.participantCode,
      trialLabel: request.trialLabel,
      detector: _detectorRef,
    );
    if (!mounted) return;
    if (error != null) {
      _showMessage(error, isError: true);
      return;
    }
    _showMessage(
      'Recording trial ${request.trialLabel.trim()} with '
      '${_detectorRef.name}.',
    );
  }

  Future<void> _pauseSession() => _sessions.pause();

  Future<void> _resumeSession() => _sessions.resume();

  Future<void> _finishSession() async {
    final result = await _sessions.finish();
    if (!mounted || result == null) return;
    if (result.saved) {
      _showMessage('Trial finished and saved on this device.');
      return;
    }
    _showMessage(
      _sessions.lastSaveError ??
          'The trial was finished but could not be saved on this device.',
      isError: true,
    );
  }

  Future<void> _uploadStored(ResearchSession session) async {
    if (_sessions.isUploading || !_uploadService.isConfigured) return;
    final metadata = await showDialog<ResearchSessionMetadata>(
      context: context,
      builder: (_) => _UploadMetadataDialog(
        initialParticipantCode: session.participantCode,
        initialScenario: session.trialLabel,
        lockIdentity: true,
      ),
    );
    if (metadata == null || !mounted) return;
    final result = await _sessions.upload(
      session: session,
      metadata: metadata,
      settings: widget.settings?.settings,
    );
    if (!mounted) return;
    _showMessage(
      result.isAlreadyUploaded
          ? result.message!
          : result.isSuccess
          ? 'Trial uploaded to the research database.'
          : result.errorMessage!,
      isError: !result.isSuccess,
    );
  }

  Future<void> _exportStored(ResearchSession session) async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      final file = await _exportService.writeJson(
        telemetry: session,
        settings: widget.settings?.settings,
        // Two trials exported in the same second must not overwrite each other.
        stemSuffix: '-${session.id}',
      );
      if (!mounted) return;
      final filename = file.uri.pathSegments.isEmpty
          ? 'trial export'
          : file.uri.pathSegments.last;
      _showMessage('Export saved: $filename');
    } catch (_) {
      if (!mounted) return;
      _showMessage('Export could not be saved. Try again.', isError: true);
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _discardStored(ResearchSession session) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Discard this trial?'),
        content: Text(
          'This deletes only the stored trial ${session.trialLabel} '
          '(${session.participantCode}) from this device. It cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Discard trial'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _sessions.discard(session);
    if (!mounted) return;
    _showMessage('Trial discarded.');
  }

  void _showMessage(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: isError
            ? Theme.of(context).colorScheme.errorContainer
            : null,
        content: Semantics(
          container: true,
          liveRegion: true,
          label: message,
          child: Text(message),
        ),
      ),
    );
  }
}

/// Participant/study prompt for one upload.
///
/// The dialog owns its text controllers: disposing them in the caller leaves the
/// closing route rebuilding a disposed controller for the length of its exit
/// animation.
class _UploadMetadataDialog extends StatefulWidget {
  /// Prefilled from a stored trial; the identity is frozen with the trial, so a
  /// typo here cannot move the data to another participant.
  final String? initialParticipantCode;
  final String? initialScenario;
  final bool lockIdentity;

  const _UploadMetadataDialog({
    this.initialParticipantCode,
    this.initialScenario,
    this.lockIdentity = false,
  });

  @override
  State<_UploadMetadataDialog> createState() => _UploadMetadataDialogState();
}

class _UploadMetadataDialogState extends State<_UploadMetadataDialog> {
  late final TextEditingController _participantController =
      TextEditingController(text: widget.initialParticipantCode ?? '');
  late final TextEditingController _scenarioController = TextEditingController(
    text: widget.initialScenario ?? '',
  );

  /// The study upload token is held here only for the lifetime of the dialog.
  /// It is never written to preferences, an export, telemetry or a message;
  /// disposing the dialog drops it.
  final TextEditingController _tokenController = TextEditingController();

  /// Set when confirm is pressed with a token of the wrong shape, so the field
  /// says why instead of the button doing nothing.
  String? _tokenError;

  @override
  void dispose() {
    _participantController.dispose();
    _scenarioController.dispose();
    _tokenController.dispose();
    super.dispose();
  }

  void _confirm() {
    final value = ResearchSessionMetadata(
      participantCode: _participantController.text,
      studyScenario: _scenarioController.text,
      uploadToken: _tokenController.text,
    );
    if (!value.hasValidUploadToken) {
      // A local sentence: the token was never sent, so the server's own
      // "did not recognise" answer would misdescribe this refusal.
      setState(() => _tokenError = TelemetryUploadResult.tokenShapeMessage);
      return;
    }
    if (!value.isValid) return;
    Navigator.pop(context, value);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Upload this session?'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'This manually sends one finished, image-free trial to the research '
            'database. It does not include camera frames or device IDs. Use only '
            'a study participant code, never a name or email address. The study '
            'upload token comes from the study coordinator; it is used for this '
            'upload only and is not saved. Each participant and trial is stored '
            'once: re-sending the same trial is deduplicated by the research '
            'server, and later recording belongs to a new trial.',
          ),
          const SizedBox(height: kSpace12),
          TextField(
            controller: _participantController,
            maxLength: 64,
            readOnly: widget.lockIdentity,
            decoration: const InputDecoration(
              labelText: 'Participant code',
              hintText: 'P-001',
            ),
          ),
          TextField(
            controller: _scenarioController,
            maxLength: 80,
            readOnly: widget.lockIdentity,
            decoration: const InputDecoration(
              labelText: 'Study scenario',
              hintText: 'indoor-obstacle-course',
            ),
          ),
          TextField(
            controller: _tokenController,
            maxLength: 128,
            autocorrect: false,
            enableSuggestions: false,
            // Typing clears the refusal, so the field stops shouting as soon as
            // the researcher acts on it.
            onChanged: (_) {
              if (_tokenError != null) setState(() => _tokenError = null);
            },
            decoration: InputDecoration(
              labelText: 'Study upload token',
              helperText: 'Required. Supplied by the study coordinator.',
              errorText: _tokenError,
            ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: _confirm, child: const Text('Confirm upload')),
    ],
  );
}

/// Participant code and trial label collected before a trial starts.
class _StartSessionRequest {
  const _StartSessionRequest(this.participantCode, this.trialLabel);

  final String participantCode;
  final String trialLabel;
}

/// Explicit Start confirmation: coded participant, trial label and the detector
/// that will produce the trial's rows.
class _StartSessionDialog extends StatefulWidget {
  final String detectorName;

  const _StartSessionDialog({required this.detectorName});

  @override
  State<_StartSessionDialog> createState() => _StartSessionDialogState();
}

class _StartSessionDialogState extends State<_StartSessionDialog> {
  final TextEditingController _participantController = TextEditingController();
  final TextEditingController _trialController = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _participantController.dispose();
    _trialController.dispose();
    super.dispose();
  }

  void _confirm() {
    final request = _StartSessionRequest(
      _participantController.text.trim(),
      _trialController.text.trim(),
    );
    // Same rules the upload applies, so an unusable trial cannot be started.
    final metadata = ResearchSessionMetadata(
      participantCode: request.participantCode,
      studyScenario: request.trialLabel,
      uploadToken: '',
    );
    if (!metadata.isValid) {
      setState(() {
        _error =
            'Use letters, digits, - or _ for the participant code, and a trial '
            'label of at most 80 characters.';
      });
      return;
    }
    Navigator.pop(context, request);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Start logging?'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Recording starts now and keeps only what is captured until you '
            'finish the trial. Nothing recorded before Start is included, and '
            'pausing logging does not pause detection. Use only a study '
            'participant code, never a name or email address. Detector: '
            '${widget.detectorName}.',
          ),
          const SizedBox(height: kSpace12),
          TextField(
            controller: _participantController,
            maxLength: 64,
            decoration: const InputDecoration(
              labelText: 'Participant code',
              hintText: 'P-001',
            ),
          ),
          TextField(
            controller: _trialController,
            maxLength: 80,
            decoration: const InputDecoration(
              labelText: 'Trial label',
              hintText: 'indoor-course-1',
            ),
          ),
          if (_error != null)
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: _confirm, child: const Text('Start trial')),
    ],
  );
}

class _OverviewTab extends StatelessWidget {
  final bool exporting;
  final VoidCallback onExportJson;
  final VoidCallback onExportCsv;
  final bool uploading;
  final bool uploadConfigured;
  final VoidCallback onUpload;
  final ResearchSessionService sessions;
  final String currentDetectorName;
  final VoidCallback onStart;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onFinish;
  final ValueChanged<ResearchSession> onUploadStored;
  final ValueChanged<ResearchSession> onExportStored;
  final ValueChanged<ResearchSession> onDiscardStored;

  const _OverviewTab({
    required this.exporting,
    required this.onExportJson,
    required this.onExportCsv,
    required this.uploading,
    required this.uploadConfigured,
    required this.onUpload,
    required this.sessions,
    required this.currentDetectorName,
    required this.onStart,
    required this.onPause,
    required this.onResume,
    required this.onFinish,
    required this.onUploadStored,
    required this.onExportStored,
    required this.onDiscardStored,
  });

  @override
  Widget build(BuildContext context) {
    return Builder(
      builder: (context) {
        final telemetry = _of(context);
        final models = _modelOptions(telemetry);
        final modelClaim = _modelClaim(models, null);
        final duration = telemetry.sessionDuration;
        final hours = duration.inHours;
        final minutes = duration.inMinutes % 60;
        final seconds = duration.inSeconds % 60;
        return _BoundedScrollView(
          children: [
            const _SectionHeading('Research Session'),
            const SizedBox(height: kSpace8),
            _SessionSection(
              sessions: sessions,
              currentDetectorName: currentDetectorName,
              onStart: onStart,
              onPause: onPause,
              onResume: onResume,
              onFinish: onFinish,
              onUploadStored: onUploadStored,
              onExportStored: onExportStored,
              onDiscardStored: onDiscardStored,
            ),
            const SizedBox(height: kSpace24),
            const _SectionHeading('Real-Time Performance'),
            const SizedBox(height: kSpace8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _MetricCard(
                  label: 'Avg FPS',
                  value: _fmt(telemetry.averageInferenceFps),
                ),
                const SizedBox(width: kSpace12),
                _MetricCard(
                  label: 'Avg Latency',
                  value: '${_fmt(telemetry.averageLatencyMs)} ms',
                ),
              ],
            ),
            // These two averages cover every recorded sample, so they must say
            // so when more than one detector contributed to them.
            if (_identities(models).length > 1) ...[
              const SizedBox(height: kSpace8),
              const _MixedModelNote(),
            ],
            const SizedBox(height: kSpace24),
            const _SectionHeading('Inference Cadence'),
            const SizedBox(height: kSpace8),
            // Non-const on purpose: a const child is retained across the
            // ListenableBuilder rebuild and would read a stale sample.
            _InferenceCadenceSection(),
            const SizedBox(height: kSpace24),
            const _SectionHeading('Engine Comparison'),
            const SizedBox(height: kSpace8),
            // Each engine card blends whatever models contributed, so it
            // carries the same claim the metric cards above do.
            for (final engine in InferenceEngine.values)
              _EngineSummaryCard(
                summary: telemetry.summaryFor(engine),
                modelClaim: modelClaim,
              ),
            const SizedBox(height: kSpace24),
            const _SectionHeading('Session Summary'),
            const SizedBox(height: kSpace8),
            _SummaryCard(
              children: [
                _SummaryRow(
                  label: 'Total detections',
                  value: '${telemetry.totalDetections}',
                ),
                _SummaryRow(
                  label: 'High-priority alerts',
                  value: '${telemetry.highPriorityAlerts}',
                ),
                _SummaryRow(
                  label: 'Frames processed',
                  value: '${telemetry.framesProcessed}',
                ),
                _SummaryRow(
                  label: 'Session duration',
                  value: '$hours h $minutes m $seconds s',
                ),
                _SummaryRow(
                  label: 'Avg confidence',
                  value: telemetry.records.isEmpty
                      ? '—'
                      : '${(telemetry.averageConfidence * 100).toStringAsFixed(0)}%',
                ),
              ],
            ),
            const SizedBox(height: kSpace24),
            const _SectionHeading('Alert Latency'),
            const SizedBox(height: kSpace8),
            // Non-const on purpose: a const child is retained across the
            // ListenableBuilder rebuild and would read stale telemetry.
            _AlertLatencySection(),
            const SizedBox(height: kSpace24),
            _ExportSection(
              exporting: exporting,
              onExportJson: onExportJson,
              onExportCsv: onExportCsv,
              uploading: uploading,
              uploadConfigured: uploadConfigured,
              liveUploadBlocked: sessions.state != ResearchSessionState.idle,
              onUpload: onUpload,
            ),
            const SizedBox(height: kSpace24),
            const _CorrectionSummary(),
            const SizedBox(height: kSpace24),
            const _UnavailableNote(
              title: 'Model Evaluation Metrics',
              body:
                  'Accuracy, Precision, Recall, F1, and mAP are not shown because '
                  'they require ground-truth labels (offline evaluation), which a '
                  'live camera feed cannot provide.',
            ),
            const SizedBox(height: kSpace12),
            const _UnavailableNote(
              title: 'Usability (SUS)',
              body:
                  'SUS is collected through a post-test questionnaire with '
                  'participants — it is not derived from runtime data.',
            ),
          ],
        );
      },
    );
  }
}

/// Compact view of the inference cadence recorded with the latest sample.
///
/// Values recorded before cadence telemetry, and single fields the engine never
/// observed, render `unknown` — never a fabricated zero.
class _InferenceCadenceSection extends StatelessWidget {
  const _InferenceCadenceSection();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final samples = _of(context).samples;
    final sample = samples.isEmpty ? null : samples.last;
    if (sample == null) {
      return _SummaryCard(
        children: [
          Text(
            'No inference sample recorded yet.',
            style: theme.textTheme.bodyMedium?.copyWith(color: kHomeInkMuted),
          ),
        ],
      );
    }
    final requestedDetection = sample.requestedDetectionHz;
    final effectiveDetection = sample.effectiveDetectionHz;
    final requestedDepth = sample.requestedDepthHz;
    final effectiveDepth = sample.effectiveDepthHz;
    final observedHz = sample.depthObservedHz;
    final latencyMs = sample.depthLatencyMs;
    return _SummaryCard(
      children: [
        _SummaryRow(
          label: 'Requested detector rate',
          value: requestedDetection == null
              ? (sample.detectionCadenceAutomatic ? 'Automatic' : 'unknown')
              : '$requestedDetection Hz',
        ),
        _SummaryRow(
          label: 'Effective detector rate',
          value: effectiveDetection == null
              ? 'uncapped'
              : '$effectiveDetection Hz',
        ),
        _SummaryRow(
          label: 'Requested depth rate',
          value: requestedDepth == null ? 'unknown' : '$requestedDepth Hz',
        ),
        _SummaryRow(
          label: 'Effective depth rate',
          value: effectiveDepth == null ? 'unknown' : '$effectiveDepth Hz',
        ),
        _SummaryRow(
          label: 'Observed depth rate',
          value: observedHz == null
              ? 'unknown'
              : '${observedHz.toStringAsFixed(1)} Hz',
        ),
        // Depth is its own model: naming it here keeps depth timings from
        // reading as the selected detector's performance.
        const _SummaryRow(
          label: 'Depth model',
          value: EyeCueModelConfig.depthModelId,
        ),
        _SummaryRow(
          label: 'Depth latency',
          value: latencyMs == null ? 'unknown' : '$latencyMs ms',
        ),
        _SummaryRow(
          label: 'Depth status',
          value: sample.depthStatus ?? 'unknown',
        ),
        if (sample.lowPowerClamped)
          const _SummaryRow(label: 'Low power clamp', value: 'applied'),
        if (sample.sourceLimited)
          const _SummaryRow(label: 'Source limited', value: 'applied'),
      ],
    );
  }
}

/// Compact alert-latency distributions and scheduler health.
///
/// Engine groups and interval labels mirror the telemetry contract. Empty
/// distributions render `No samples`, never a fabricated `0 ms` percentile.
class _AlertLatencySection extends StatelessWidget {
  const _AlertLatencySection();

  @override
  Widget build(BuildContext context) {
    final telemetry = _of(context);
    final theme = Theme.of(context);
    final counters = telemetry.alertCounters;
    return Semantics(
      container: true,
      label: 'Alert latency and scheduler health',
      child: _LightCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Alert latency and scheduler health',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            for (final engine in InferenceEngine.values) ...[
              const SizedBox(height: kSpace12),
              Text(
                engine.label,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: kSpace4),
              for (final interval in AlertLatencyInterval.values)
                _AlertIntervalRow(
                  label: interval.label(engine),
                  summary: telemetry.alertLatencySummary(engine, interval),
                ),
            ],
            const SizedBox(height: kSpace16),
            Text(
              'Scheduler health',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: kSpace4),
            _SummaryRow(label: 'Dropped', value: '${counters.dropped}'),
            _SummaryRow(
              label: 'Cancelled before start',
              value: '${counters.cancelledBeforeStart}',
            ),
            _SummaryRow(
              label: 'Cancelled after start',
              value: '${counters.cancelledAfterStart}',
            ),
            _SummaryRow(
              label: 'Failed before start',
              value: '${counters.failedBeforeStart}',
            ),
            _SummaryRow(
              label: 'Failed after start',
              value: '${counters.failedAfterStart}',
            ),
            _SummaryRow(
              label: 'Reconciliation timeout',
              value: '${counters.reconciliationTimeout}',
            ),
            _SummaryRow(
              label: 'Watchdog recovery',
              value: '${counters.watchdogRecovery}',
            ),
            _SummaryRow(
              label: 'Quiet-period cap reached',
              value: '${counters.quietPeriodCapReached}',
            ),
            _SummaryRow(
              label: 'Recovery failed',
              value: '${counters.recoveryFailed}',
            ),
            _SummaryRow(
              label: 'Quarantined callback',
              value: '${counters.quarantinedCallback}',
            ),
            _SummaryRow(
              label: 'Late callback ignored',
              value: '${counters.lateCallbackIgnored}',
            ),
            _SummaryRow(
              label: 'Callback order violation',
              value: '${counters.callbackOrderViolation}',
            ),
            _SummaryRow(
              label: 'Preemption requested',
              value: '${counters.preemptionRequested}',
            ),
            _SummaryRow(
              label: 'Confirmed preempted',
              value: '${counters.preempted}',
            ),
            _SummaryRow(
              label: 'Superseded (all alert types)',
              value: '${counters.superseded}',
            ),
            _SummaryRow(
              label: 'Muted (all alert types)',
              value: '${counters.muted}',
            ),
            _SummaryRow(
              label: 'Stale decision',
              value: '${counters.staleDecision}',
            ),
            _SummaryRow(
              label: 'Rejected after recovery',
              value: '${counters.rejectedAfterRecovery}',
            ),
            for (final entry in counters.rejectedByReason.entries)
              _SummaryRow(
                label: 'Rejected: ${entry.key}',
                value: '${entry.value}',
              ),
          ],
        ),
      ),
    );
  }
}

class _AlertIntervalRow extends StatelessWidget {
  final String label;
  final AlertLatencySummary summary;

  const _AlertIntervalRow({required this.label, required this.summary});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final value = summary.sampleCount == 0
        ? 'No samples'
        : 'p50 ${_fmt(summary.p50Ms)} ms · p95 ${_fmt(summary.p95Ms)} ms · '
              'max ${_fmt(summary.maxMs)} ms · n ${summary.sampleCount}';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: kSpace4),
      child: Semantics(
        container: true,
        label: '$label: $value',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: theme.textTheme.bodyMedium),
            Text(
              value,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ExportSection extends StatelessWidget {
  final bool exporting;
  final VoidCallback onExportJson;
  final VoidCallback onExportCsv;
  final bool uploading;
  final bool uploadConfigured;

  /// True once a trial was started in this run: the live session then holds
  /// trial rows under the app-lifetime id and must not be uploaded.
  final bool liveUploadBlocked;
  final VoidCallback onUpload;

  const _ExportSection({
    required this.exporting,
    required this.onExportJson,
    required this.onExportCsv,
    required this.uploading,
    required this.uploadConfigured,
    required this.liveUploadBlocked,
    required this.onUpload,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      container: true,
      label: 'Offline telemetry export',
      child: _LightCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Offline telemetry export',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: kSpace4),
            Text(
              'Save the current image-free session as a versioned JSON or '
              'CSV file. Exports contain no camera frames or device IDs.',
              style: theme.textTheme.bodyMedium?.copyWith(color: kHomeInkMuted),
            ),
            const SizedBox(height: kSpace12),
            Wrap(
              spacing: kSpace8,
              runSpacing: kSpace8,
              children: [
                AccessibleButton(
                  label: 'Save JSON export',
                  icon: Icons.data_object,
                  onPressed: exporting ? null : onExportJson,
                ),
                AccessibleButton(
                  label: 'Save CSV export',
                  icon: Icons.table_chart_outlined,
                  onPressed: exporting ? null : onExportCsv,
                ),
              ],
            ),
            if (exporting) ...[
              const SizedBox(height: kSpace8),
              Text(
                'Saving export…',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: kHomeInkMuted,
                ),
              ),
            ],
            const SizedBox(height: kSpace16),
            const Divider(),
            const SizedBox(height: kSpace12),
            Text(
              'Research database upload',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: kSpace4),
            Text(
              !uploadConfigured
                  ? 'Online research upload is not configured in this build. '
                        'Offline exports remain available.'
                  : liveUploadBlocked
                  ? 'A research trial was started in this run, so this live '
                        'session cannot be uploaded. Upload the finished trial '
                        'from the stored trials list instead.'
                  : 'Manually upload this image-free app session (not a trial) '
                        'after confirming participant consent and the study '
                        'context.',
              style: theme.textTheme.bodyMedium?.copyWith(color: kHomeInkMuted),
            ),
            const SizedBox(height: kSpace12),
            AccessibleButton(
              label: 'Upload session to research database',
              icon: Icons.cloud_upload_outlined,
              onPressed: !uploadConfigured || uploading || liveUploadBlocked
                  ? null
                  : onUpload,
            ),
            if (uploading) ...[
              const SizedBox(height: kSpace8),
              Text(
                'Uploading session…',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: kHomeInkMuted,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CorrectionSummary extends StatelessWidget {
  const _CorrectionSummary();

  @override
  Widget build(BuildContext context) {
    final corrections = context
        .findAncestorWidgetOfExactType<LogsReportsScreen>()
        ?.corrections
        ?.records;
    if (corrections == null || corrections.isEmpty) {
      return const _UnavailableNote(
        title: 'Correction reports',
        body: 'No correction reports have been recorded in this session.',
      );
    }
    final theme = Theme.of(context);
    return Semantics(
      container: true,
      label: 'Correction reports, ${corrections.length} recorded',
      child: _LightCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Correction reports',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: kSpace8),
            for (var index = corrections.length - 1; index >= 0; index--)
              _CorrectionSummaryRow(correction: corrections[index]),
          ],
        ),
      ),
    );
  }
}

class _CorrectionSummaryRow extends StatelessWidget {
  final DetectionCorrection correction;

  const _CorrectionSummaryRow({required this.correction});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final feedback = correction.correctedLabel == null
        ? correction.feedback.label
        : '${correction.feedback.label} as ${correction.correctedLabel}';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: kSpace4),
      child: Semantics(
        container: true,
        label:
            '${correction.detection.label}, $feedback, '
            '${correction.engine.label}, threshold '
            '${correction.confidenceThreshold.toStringAsFixed(2)}',
        child: Text(
          '${correction.detection.label}: $feedback · '
          '${correction.engine.label} · threshold '
          '${correction.confidenceThreshold.toStringAsFixed(2)}',
          style: theme.textTheme.bodyMedium,
        ),
      ),
    );
  }
}

class _ChartsTab extends StatelessWidget {
  final String? modelFilter;
  final ValueChanged<String?> onModelFilterChanged;

  const _ChartsTab({
    required this.modelFilter,
    required this.onModelFilterChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Builder(
      builder: (context) {
        final telemetry = _of(context);
        final models = _modelOptions(telemetry);
        final selected = _selectedModel(models, modelFilter);
        final samples = _samplesFor(telemetry, selected);
        // The card title names what the charts actually draw. A selection whose
        // rows are gone falls back to all models, exactly as the samples do, so
        // a title can never claim a model the chart does not contain.
        final claim = _modelClaim(models, selected?.key);
        return _BoundedScrollView(
          children: [
            _ModelFilter(
              models: models,
              value: modelFilter,
              onChanged: onModelFilterChanged,
            ),
            const SizedBox(height: kSpace24),
            _ChartCard(
              title: 'Inference Latency$claim (300 ms benchmark)',
              child: LatencyChart(samples: samples),
            ),
            const SizedBox(height: kSpace24),
            _ChartCard(
              title: 'Frames Per Second$claim (15 FPS target)',
              child: FpsChart(samples: samples),
            ),
            const SizedBox(height: kSpace24),
            // The filter reaches detections too: a chart under a model filter
            // must not draw every model's rows, and it names what it draws like
            // the two charts above.
            _ChartCard(
              title: 'Detection Frequency$claim',
              child: DetectionFrequencyChart(
                buckets: telemetry.detectionFrequencyByMinute(
                  include: selected == null
                      ? null
                      : (record) => selected.matches(
                          record.detectorModelId,
                          record.detectorModelName,
                          record.detectorModelFingerprint,
                        ),
                ),
              ),
            ),
            const SizedBox(height: kSpace24),
          ],
        );
      },
    );
  }
}

class _LogsTab extends StatelessWidget {
  final String? modelFilter;
  final ValueChanged<String?> onModelFilterChanged;

  const _LogsTab({
    required this.modelFilter,
    required this.onModelFilterChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Builder(
      builder: (context) {
        final telemetry = _of(context);
        final theme = Theme.of(context);
        final models = _modelOptions(telemetry);
        final selected = _selectedModel(models, modelFilter);
        final records = [
          for (final record in telemetry.records)
            if (selected == null ||
                selected.matches(
                  record.detectorModelId,
                  record.detectorModelName,
                  record.detectorModelFingerprint,
                ))
              record,
        ];
        if (records.isEmpty) {
          // The filter stays reachable: a filtered-empty list must not trap the
          // researcher on a model with no rows.
          return _BoundedScrollView(
            children: [
              _ModelFilter(
                models: models,
                value: modelFilter,
                onChanged: onModelFilterChanged,
              ),
              const SizedBox(height: kSpace24),
              Text(
                modelFilter == null
                    ? 'No detections recorded yet.'
                    : 'No detections recorded for this model.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: kHomeInkMuted,
                ),
              ),
            ],
          );
        }
        return LayoutBuilder(
          builder: (context, constraints) {
            final boundedWidth = constraints.maxWidth > 480
                ? 480.0
                : constraints.maxWidth;
            return Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: boundedWidth),
                child: ListView.builder(
                  // One extra row carries the model filter above the list.
                  itemCount: records.length + 1,
                  padding: const EdgeInsets.symmetric(vertical: kSpace8),
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: kSpace8),
                        child: _ModelFilter(
                          models: models,
                          value: modelFilter,
                          onChanged: onModelFilterChanged,
                        ),
                      );
                    }
                    final r = records[records.length - index]; // newest first
                    final time =
                        '${r.timestamp.hour.toString().padLeft(2, '0')}:'
                        '${r.timestamp.minute.toString().padLeft(2, '0')}:'
                        '${r.timestamp.second.toString().padLeft(2, '0')}';
                    return ListTile(
                      dense: true,
                      leading: _PriorityDot(priority: r.priority),
                      title: Text(
                        '${r.label} — ${(r.confidence * 100).toStringAsFixed(0)}%',
                      ),
                      subtitle: Text(
                        [
                          // The readable model name comes first: it is what the
                          // numbers below belong to.
                          if (r.detectorModelName != null) r.detectorModelName!,
                          r.engine.label,
                          r.position,
                          '${r.latencyMs.toStringAsFixed(0)} ms',
                        ].join(' · '),
                      ),
                      trailing: Text(
                        time,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: kHomeInkMuted,
                        ),
                      ),
                    );
                  },
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _EngineSummaryCard extends StatelessWidget {
  final EngineTelemetrySummary summary;

  /// What the numbers below may claim: one model's name, or mixed-model data.
  final String modelClaim;

  const _EngineSummaryCard({required this.summary, required this.modelClaim});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasData = summary.sampleCount > 0;
    // The claim is its own line. Trailing the value line it needed ~307 px
    // where the value column has ~171 px on a 390 px phone, so it was always
    // ellipsized away.
    // shortcut: two lines hold the longest accepted (40-character) model name.
    final claim = modelClaim.startsWith(' — ')
        ? modelClaim.substring(3)
        : modelClaim;
    return Container(
      margin: const EdgeInsets.only(bottom: kSpace8),
      padding: const EdgeInsets.all(kSpace12),
      decoration: BoxDecoration(
        color: kHomeSurfaceCard,
        borderRadius: BorderRadius.circular(kRadius14),
        boxShadow: kHomeShadowSoft,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                summary.engine.label,
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: kSpace8),
              Expanded(
                child: Text(
                  hasData
                      ? '${summary.averageInferenceFps.toStringAsFixed(1)} FPS · '
                            '${summary.averageLatencyMs.toStringAsFixed(1)} ms · '
                            '${summary.sampleCount} frames'
                      : 'No samples',
                  textAlign: TextAlign.end,
                  maxLines: 2,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: kHomeInkMuted,
                  ),
                ),
              ),
            ],
          ),
          if (claim.isNotEmpty) ...[
            const SizedBox(height: kSpace4),
            Text(
              claim,
              textAlign: TextAlign.end,
              maxLines: 2,
              style: theme.textTheme.bodySmall?.copyWith(color: kHomeInkMuted),
            ),
          ],
        ],
      ),
    );
  }
}

class _PriorityDot extends StatelessWidget {
  final ObjectPriority priority;

  const _PriorityDot({required this.priority});

  @override
  Widget build(BuildContext context) {
    final color = switch (priority) {
      ObjectPriority.high => kPriorityHigh,
      ObjectPriority.medium => kPriorityMedium,
      ObjectPriority.low => kPriorityLow,
    };
    final wording = switch (priority) {
      ObjectPriority.high => 'High priority',
      ObjectPriority.medium => 'Medium priority',
      ObjectPriority.low => 'Low priority',
    };
    // The dot is decorative; the priority wording is exposed as a semantic
    // label so priority is never conveyed by color alone.
    return Semantics(
      label: wording,
      child: ExcludeSemantics(
        child: Icon(Icons.circle, color: color, size: 14),
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  final String label;
  final String value;

  const _MetricCard({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(kSpace16),
        decoration: BoxDecoration(
          color: kHomeSurfaceCard,
          borderRadius: BorderRadius.circular(kRadius14),
          boxShadow: kHomeShadowSoft,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: kSpace4),
            Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(color: kHomeInkMuted),
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final String label;
  final String value;

  const _SummaryRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: kSpace6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: Text(label, style: theme.textTheme.bodyLarge)),
          const SizedBox(width: kSpace12),
          Text(
            value,
            textAlign: TextAlign.end,
            style: theme.textTheme.bodyLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _UnavailableNote extends StatelessWidget {
  final String title;
  final String body;

  const _UnavailableNote({required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(kSpace16),
      decoration: BoxDecoration(
        color: kHomeSurfaceCard,
        borderRadius: BorderRadius.circular(kRadius14),
        boxShadow: kHomeShadowSoft,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: kSpace4),
          Text(
            body,
            style: theme.textTheme.bodyMedium?.copyWith(color: kHomeInkMuted),
          ),
        ],
      ),
    );
  }
}

/// Centered, bounded, vertically scrollable content column.
///
/// Uses the existing centered bounded secondary-screen precedent: content is
/// capped at ~480 logical pixels on wider windows and contracts to the
/// available width on narrower windows. The bound is derived from constraints,
/// never from a device-type check, orientation branch, or fixed canvas.
class _BoundedScrollView extends StatelessWidget {
  final List<Widget> children;

  const _BoundedScrollView({required this.children});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final contentWidth = constraints.maxWidth;
          final boundedWidth = contentWidth > 480 ? 480.0 : contentWidth;
          return Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: boundedWidth),
              child: ListView(
                padding: const EdgeInsets.symmetric(
                  horizontal: kSpace16,
                  vertical: kSpace16,
                ),
                children: children,
              ),
            ),
          );
        },
      ),
    );
  }
}

/// A light grouped card surface used for Overview sections.
class _LightCard extends StatelessWidget {
  final Widget child;

  const _LightCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(kSpace16),
      decoration: BoxDecoration(
        color: kHomeSurfaceCard,
        borderRadius: BorderRadius.circular(kRadius14),
        boxShadow: kHomeShadowSoft,
      ),
      child: child,
    );
  }
}

/// A section heading, visually distinct from metric labels and tab labels.
class _SectionHeading extends StatelessWidget {
  final String title;

  const _SectionHeading(this.title);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      title,
      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
    );
  }
}

/// A light grouped card wrapping the Session Summary metric rows.
class _SummaryCard extends StatelessWidget {
  final List<Widget> children;

  const _SummaryCard({required this.children});

  @override
  Widget build(BuildContext context) {
    return _LightCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }
}

/// A light chart card: a heading plus the chart drawn inside the existing
/// [kChartHeight] allocation. The chart widget itself owns its data binding,
/// dynamic bounds, benchmark lines, and semantics summary.
class _ChartCard extends StatelessWidget {
  final String title;
  final Widget child;

  const _ChartCard({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _LightCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: kSpace8),
          SizedBox(height: kChartHeight, child: child),
        ],
      ),
    );
  }
}

/// Helper to reach the TelemetryService from a descendant builder without
/// passing it through every private widget.
TelemetryService _of(BuildContext context) =>
    (context.findAncestorWidgetOfExactType<LogsReportsScreen>()!).telemetry;

String _fmt(double v) => v.toStringAsFixed(1);

/// The explicit "no filter" choice, so an unfiltered summary never reads as one
/// model's performance.
const String _allModelsLabel = 'All models (mixed)';

/// The label a summary carries when its numbers span more than one detector.
const String _mixedModelLabel = 'Mixed-model data';

/// One detector model identity present in the recorded rows.
class _ModelOption {
  /// This view's key for the identity. It is built by walking records then
  /// samples, while the export's `detectorModels` table walks samples then
  /// records, so a duplicate identity's `~n` suffix can differ: the keys are
  /// per-view and are not comparable across views.
  final String key;
  final String id;
  final String name;
  final String? fingerprint;

  /// What the dropdown and chart titles show: the name, plus a short
  /// fingerprint suffix when two models share a display name.
  final String label;

  /// Whether this is the name the identity was most recently recorded under,
  /// so a summary can name a renamed graph by its current name.
  final bool isLatest;

  const _ModelOption(
    this.key,
    this.id,
    this.name,
    this.fingerprint,
    this.label, {
    this.isLatest = false,
  });

  /// Whether a row was recorded with this identity. Two graphs sharing a name
  /// differ here, and a renamed graph does not match its old rows.
  bool matches(String? rowId, String? rowName, String? rowFingerprint) =>
      id == rowId && name == rowName && fingerprint == rowFingerprint;
}

/// The discriminating tail of a fingerprint, for same-named graphs.
String _shortFingerprint(String? fingerprint) {
  final hex = fingerprint?.split('-').first;
  if (hex == null || hex.isEmpty) return '';
  return hex.length <= 8 ? hex : hex.substring(0, 8);
}

/// Distinct `(id, name, fingerprint)` identities present in the data, keyed
/// with the same rule as the export's `detectorModels` table. Row order
/// differs between the two views, so the keys themselves are not comparable.
List<_ModelOption> _modelOptions(TelemetryService telemetry) {
  final table = DetectorModelTable();
  final seen = <String, _ModelOption>{};
  final latestKeyById = <String, String>{};
  void add(String? id, String? name, String? fingerprint) {
    final modelId = id;
    final modelKey = table.keyFor(modelId, name, fingerprint);
    if (modelId == null || modelKey == null) return;
    // Every row moves the identity's current name forward, including a row of
    // an identity already listed (a rename reuses the id).
    latestKeyById[modelId] = modelKey;
    if (seen.containsKey(modelKey)) return;
    // A row with no recorded name falls back to its id, as the filter always
    // has; the identity key still keeps it distinct from a named graph.
    seen[modelKey] = _ModelOption(
      modelKey,
      modelId,
      name ?? modelId,
      fingerprint,
      '',
    );
  }

  for (final record in telemetry.records) {
    add(
      record.detectorModelId,
      record.detectorModelName,
      record.detectorModelFingerprint,
    );
  }
  for (final sample in telemetry.samples) {
    add(
      sample.detectorModelId,
      sample.detectorModelName,
      sample.detectorModelFingerprint,
    );
  }

  final nameCounts = <String, int>{};
  for (final option in seen.values) {
    nameCounts.update(option.name, (count) => count + 1, ifAbsent: () => 1);
  }
  final options = <_ModelOption>[];
  for (final option in seen.values) {
    final ambiguous = (nameCounts[option.name] ?? 0) > 1;
    options.add(
      _ModelOption(
        option.key,
        option.id,
        option.name,
        option.fingerprint,
        ambiguous
            ? '${option.name} · ${_shortFingerprint(option.fingerprint)}'
            : option.name,
        isLatest: latestKeyById[option.id] == option.key,
      ),
    );
  }
  options.sort((a, b) => a.label.compareTo(b.label));
  return options;
}

/// The model the filter selects, if its rows are still present.
_ModelOption? _selectedModel(List<_ModelOption> options, String? key) {
  for (final option in options) {
    if (option.key == key) return option;
  }
  return null;
}

/// The samples a chart may draw: all of them, or one model's.
List<RuntimeSample> _samplesFor(
  TelemetryService telemetry,
  _ModelOption? model,
) => model == null
    ? telemetry.samples
    : [
        for (final sample in telemetry.samples)
          if (model.matches(
            sample.detectorModelId,
            sample.detectorModelName,
            sample.detectorModelFingerprint,
          ))
            sample,
      ];

/// The distinct detector identities among [options]. One graph renamed
/// mid-session stays one identity, so it is not "mixed".
Set<String> _identities(List<_ModelOption> options) => {
  for (final option in options) option.id,
};

/// What a chart or average built from [key] may claim.
String _modelClaim(List<_ModelOption> options, String? key) {
  if (key != null) {
    for (final option in options) {
      if (option.key == key) return ' — ${option.label}';
    }
  }
  if (_identities(options).length > 1) return ' — $_mixedModelLabel';
  if (options.isEmpty) return '';
  // One identity: name it with the name it was last recorded under, the same
  // rule the chart summary uses, so title and summary cannot disagree.
  final latest = options.where((option) => option.isLatest);
  return ' — ${(latest.isEmpty ? options : latest).first.label}';
}

/// Model filter shown above the charts and the log list.
class _ModelFilter extends StatelessWidget {
  final List<_ModelOption> models;
  final String? value;
  final ValueChanged<String?> onChanged;

  const _ModelFilter({
    required this.models,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // A selection whose rows are gone must not crash the dropdown.
    final selected = models.any((model) => model.key == value) ? value : null;
    return _LightCard(
      child: Row(
        children: [
          Text('Detector model', style: theme.textTheme.bodyLarge),
          const SizedBox(width: kSpace12),
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String?>(
                isExpanded: true,
                value: selected,
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text(
                      _allModelsLabel,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  for (final model in models)
                    DropdownMenuItem<String?>(
                      value: model.key,
                      child: Text(model.label, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: onChanged,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Visible label for numbers that combine more than one detector model.
class _MixedModelNote extends StatelessWidget {
  const _MixedModelNote();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      '$_mixedModelLabel — these numbers combine more than one detector model.',
      style: theme.textTheme.bodySmall?.copyWith(color: kHomeInkMuted),
    );
  }
}

String _durationText(Duration duration) {
  final hours = duration.inHours;
  final minutes = duration.inMinutes % 60;
  final seconds = duration.inSeconds % 60;
  return hours > 0 ? '$hours h $minutes m $seconds s' : '$minutes m $seconds s';
}

/// The explicit Start → Pause/Resume → Finish → Upload controls plus the stored
/// trial list. Study recording is independent of camera/detection playback.
class _SessionSection extends StatelessWidget {
  final ResearchSessionService sessions;
  final String currentDetectorName;
  final VoidCallback onStart;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onFinish;
  final ValueChanged<ResearchSession> onUploadStored;
  final ValueChanged<ResearchSession> onExportStored;
  final ValueChanged<ResearchSession> onDiscardStored;

  const _SessionSection({
    required this.sessions,
    required this.currentDetectorName,
    required this.onStart,
    required this.onPause,
    required this.onResume,
    required this.onFinish,
    required this.onUploadStored,
    required this.onExportStored,
    required this.onDiscardStored,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = sessions.state;
    final active =
        state == ResearchSessionState.recording ||
        state == ResearchSessionState.paused;
    final latest = sessions.sessions.isEmpty ? null : sessions.sessions.first;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          container: true,
          label: 'Research session: ${sessions.stateLabel}',
          child: _LightCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  sessions.stateLabel,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: kSpace4),
                Text(
                  'Study logging is separate from camera playback: pausing it '
                  'does not pause detection, depth or speech.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: kHomeInkMuted,
                  ),
                ),
                const SizedBox(height: kSpace8),
                if (active) ...[
                  Text(
                    'Participant ${sessions.participantCode} · trial '
                    '${sessions.trialLabel}',
                    style: theme.textTheme.bodyMedium,
                  ),
                  Text(
                    'Detector ${sessions.detectorName}',
                    style: theme.textTheme.bodyMedium,
                  ),
                  Text(
                    'Active ${_durationText(sessions.activeDuration)} · wall '
                    'clock ${_durationText(sessions.wallClockDuration)}',
                    style: theme.textTheme.bodyMedium,
                  ),
                ] else if (state == ResearchSessionState.finished &&
                    latest != null) ...[
                  Text(
                    'Last finished trial: ${latest.participantCode} · '
                    '${latest.trialLabel}',
                    style: theme.textTheme.bodyMedium,
                  ),
                  Text(
                    'Detector ${latest.detectorName} · active '
                    '${_durationText(latest.sessionDuration)} · wall clock '
                    '${_durationText(latest.wallClockDuration)}',
                    style: theme.textTheme.bodyMedium,
                  ),
                ] else
                  Text(
                    'Nothing is recorded until you press Start logging. '
                    'Current detector: $currentDetectorName.',
                    style: theme.textTheme.bodyMedium,
                  ),
                const SizedBox(height: kSpace12),
                Wrap(
                  spacing: kSpace8,
                  runSpacing: kSpace8,
                  children: [
                    if (!active)
                      AccessibleButton(
                        label: 'Start logging',
                        icon: Icons.fiber_manual_record,
                        onPressed: onStart,
                      ),
                    if (state == ResearchSessionState.recording)
                      AccessibleButton(
                        label: 'Pause logging',
                        icon: Icons.pause,
                        onPressed: onPause,
                      ),
                    if (state == ResearchSessionState.paused)
                      AccessibleButton(
                        label: 'Resume logging',
                        icon: Icons.play_arrow,
                        onPressed: onResume,
                      ),
                    if (active)
                      AccessibleButton(
                        label: 'Finish session',
                        icon: Icons.stop_circle_outlined,
                        onPressed: sessions.isFinishing ? null : onFinish,
                      ),
                    if (state == ResearchSessionState.finished &&
                        latest != null &&
                        !sessions.isUploading)
                      AccessibleButton(
                        label: 'Upload session',
                        icon: Icons.cloud_upload_outlined,
                        onPressed: () => onUploadStored(latest),
                      ),
                  ],
                ),
                if (state == ResearchSessionState.paused) ...[
                  const SizedBox(height: kSpace8),
                  Text(
                    'Paused: resume to keep recording this trial. Paused time '
                    'is not counted in the active duration.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: kHomeInkMuted,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: kSpace16),
        Text(
          'Stored trials (${sessions.sessions.length} of '
          '${sessions.maxStoredSessions})',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: kSpace8),
        if (sessions.sessions.isEmpty)
          _LightCard(
            child: Text(
              'No finished trials are stored on this device yet.',
              style: theme.textTheme.bodyMedium?.copyWith(color: kHomeInkMuted),
            ),
          )
        else
          for (final session in sessions.sessions) ...[
            _StoredTrialCard(
              session: session,
              sessions: sessions,
              onUpload: () => onUploadStored(session),
              onExport: () => onExportStored(session),
              onDiscard: () => onDiscardStored(session),
            ),
            const SizedBox(height: kSpace8),
          ],
      ],
    );
  }
}

/// One stored, immutable trial with its own Upload/Export/Discard controls.
class _StoredTrialCard extends StatelessWidget {
  final ResearchSession session;
  final ResearchSessionService sessions;
  final VoidCallback onUpload;
  final VoidCallback onExport;
  final VoidCallback onDiscard;

  const _StoredTrialCard({
    required this.session,
    required this.sessions,
    required this.onUpload,
    required this.onExport,
    required this.onDiscard,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final saved = sessions.isSaved(session);
    final uploadStatus = sessions.uploadStatusFor(session);
    final uploading = sessions.uploadingSessionId == session.id;
    return _LightCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${session.participantCode} · ${session.trialLabel}',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            'Detector ${session.detectorName}',
            style: theme.textTheme.bodyMedium,
          ),
          Text(
            'Active ${_durationText(session.sessionDuration)} · wall clock '
            '${_durationText(session.wallClockDuration)} · '
            '${session.totalDetections} detections',
            style: theme.textTheme.bodyMedium,
          ),
          Text(
            saved
                ? 'Saved on this device.'
                : 'Not saved on this device — export it now to keep the data.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: saved ? kHomeInkMuted : theme.colorScheme.error,
            ),
          ),
          if (uploadStatus != null && !uploading)
            Text(
              uploadStatus,
              style: theme.textTheme.bodySmall?.copyWith(color: kHomeInkMuted),
            ),
          const SizedBox(height: kSpace8),
          Wrap(
            spacing: kSpace8,
            runSpacing: kSpace8,
            children: [
              AccessibleButton(
                label: 'Upload trial',
                icon: Icons.cloud_upload_outlined,
                onPressed: sessions.isUploading ? null : onUpload,
              ),
              AccessibleButton(
                label: 'Export trial',
                icon: Icons.data_object,
                onPressed: onExport,
              ),
              AccessibleButton(
                label: 'Discard trial',
                icon: Icons.delete_outline,
                onPressed: onDiscard,
              ),
            ],
          ),
          if (uploading) ...[
            const SizedBox(height: kSpace8),
            Text(
              'Uploading…',
              style: theme.textTheme.bodyMedium?.copyWith(color: kHomeInkMuted),
            ),
          ],
        ],
      ),
    );
  }
}
