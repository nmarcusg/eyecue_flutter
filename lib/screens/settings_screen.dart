import 'package:flutter/material.dart';

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
                subtitle: const Text('Begin detection automatically when EyeCue opens'),
                value: settings.autoStartDetection,
                onChanged: settings.setAutoStartDetection,
              ),
              SwitchListTile(
                secondary: const Icon(Icons.battery_saver),
                title: const Text('Low Power Mode'),
                subtitle: const Text('Reduce inference rate to conserve battery'),
                value: settings.lowPowerMode,
                onChanged: settings.setLowPowerMode,
              ),
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
