import 'package:flutter/material.dart';

import '../models/app_settings.dart';
import '../services/settings_service.dart';

/// Settings — runtime configuration for users and facilitators.
///
/// Sections follow the thesis: Haptics (Vibration Feedback), Performance
/// (Auto-Start on Open, Low Power Mode), Audio (Voice guidance), and Research
/// (Logs & Reports entry). Values are persisted by [SettingsService].
class SettingsScreen extends StatelessWidget {
  final SettingsService settings;
  final VoidCallback onOpenLogsReports;

  const SettingsScreen({
    super.key,
    required this.settings,
    required this.onOpenLogsReports,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListenableBuilder(
        listenable: settings,
        builder: (context, _) {
          return ListView(
            children: [
              const _SectionHeader('Haptics'),
              SwitchListTile(
                secondary: const Icon(Icons.vibration),
                title: const Text('Vibration Feedback'),
                subtitle: const Text('Vibrate on detections and gestures'),
                value: settings.vibrationFeedback,
                onChanged: settings.setVibrationFeedback,
              ),
              const _SectionHeader('Performance'),
              SwitchListTile(
                secondary: const Icon(Icons.autorenew),
                title: const Text('Auto-Start on Open'),
                subtitle: const Text(
                  'Begin detection automatically when EyeCue opens',
                ),
                value: settings.autoStartDetection,
                onChanged: settings.setAutoStartDetection,
              ),
              SwitchListTile(
                secondary: const Icon(Icons.battery_saver),
                title: const Text('Low Power Mode'),
                subtitle: const Text(
                  'Reduce inference rate to conserve battery',
                ),
                value: settings.lowPowerMode,
                onChanged: settings.setLowPowerMode,
              ),
              const _SectionHeader('Inference Engine'),
              RadioGroup<InferenceEngine>(
                groupValue: settings.inferenceEngine,
                onChanged: (value) {
                  if (value != null) settings.setInferenceEngine(value);
                },
                child: Column(
                  children: [
                    const ListTile(
                      leading: Icon(Icons.recommend),
                      title: Text('Recommended'),
                      subtitle: Text(
                        'Use the recommended native engine for normal detection.',
                      ),
                    ),
                    RadioListTile<InferenceEngine>(
                      secondary: const Icon(Icons.memory_rounded),
                      title: Text(InferenceEngine.ultralytics.label),
                      subtitle: Text(InferenceEngine.ultralytics.description),
                      value: InferenceEngine.ultralytics,
                    ),
                    const ListTile(
                      leading: Icon(Icons.tune_rounded),
                      title: Text('Advanced / compatibility'),
                      subtitle: Text(
                        'Custom EyeCue is slower and retained for recovery and testing.',
                      ),
                    ),
                    RadioListTile<InferenceEngine>(
                      secondary: const Icon(Icons.code_rounded),
                      title: Text(InferenceEngine.custom.label),
                      subtitle: Text(InferenceEngine.custom.description),
                      value: InferenceEngine.custom,
                    ),
                  ],
                ),
              ),
              const _SectionHeader('Detection Sensitivity'),
              _SensitivityControls(settings: settings),
              const _SectionHeader('Audio'),
              SwitchListTile(
                secondary: const Icon(Icons.volume_up),
                title: const Text('Audio / Voice Guidance'),
                subtitle: const Text('Speak detected objects and guidance'),
                value: settings.audioEnabled,
                onChanged: settings.setAudioEnabled,
              ),
              const _SectionHeader('Research'),
              ListTile(
                leading: const Icon(Icons.bar_chart_rounded),
                title: const Text('View Logs & Reports'),
                subtitle: const Text('Telemetry, charts, and detection logs'),
                trailing: const Icon(Icons.chevron_right),
                onTap: onOpenLogsReports,
              ),
              const SizedBox(height: 24),
            ],
          );
        },
      ),
    );
  }
}

class _SensitivityControls extends StatefulWidget {
  final SettingsService settings;

  const _SensitivityControls({required this.settings});

  @override
  State<_SensitivityControls> createState() => _SensitivityControlsState();
}

class _SensitivityControlsState extends State<_SensitivityControls> {
  late double _draft = widget.settings.detectionConfidence;

  @override
  void initState() {
    super.initState();
    widget.settings.addListener(_handleSettingsChanged);
  }

  @override
  void dispose() {
    widget.settings.removeListener(_handleSettingsChanged);
    super.dispose();
  }

  void _handleSettingsChanged() {
    final confidence = widget.settings.detectionConfidence;
    if (confidence == _draft || !mounted) return;
    setState(() => _draft = confidence);
  }

  @override
  Widget build(BuildContext context) {
    final preset = DetectionSensitivityPreset.fromThreshold(_draft);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RadioGroup<DetectionSensitivityPreset>(
            groupValue: preset,
            onChanged: (value) {
              if (value == null) return;
              setState(() => _draft = value.threshold);
              widget.settings.setDetectionConfidence(value.threshold);
            },
            child: Column(
              children: [
                for (final option in DetectionSensitivityPreset.values)
                  RadioListTile<DetectionSensitivityPreset>(
                    title: Text(option.label),
                    subtitle: Text(option.description),
                    value: option,
                  ),
              ],
            ),
          ),
          Semantics(
            container: true,
            label:
                'Advanced detection confidence threshold, '
                '${_draft.toStringAsFixed(2)}',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Text(
                    'Advanced threshold: ${_draft.toStringAsFixed(2)}',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                Slider(
                  min: AppSettings.minDetectionConfidence,
                  max: AppSettings.maxDetectionConfidence,
                  divisions:
                      ((AppSettings.maxDetectionConfidence -
                                  AppSettings.minDetectionConfidence) /
                              0.05)
                          .round(),
                  value: _draft,
                  label: _draft.toStringAsFixed(2),
                  onChanged: (value) {
                    setState(
                      () => _draft = AppSettings.normalizeDetectionConfidence(
                        value,
                      ),
                    );
                  },
                  onChangeEnd: (value) {
                    final normalized = AppSettings.normalizeDetectionConfidence(
                      value,
                    );
                    setState(() => _draft = normalized);
                    widget.settings.setDetectionConfidence(normalized);
                  },
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    'Lower values find more objects. Higher values reduce false alerts. Changes apply after detection restarts.',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;

  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Text(
        title,
        style: theme.textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w800,
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }
}
