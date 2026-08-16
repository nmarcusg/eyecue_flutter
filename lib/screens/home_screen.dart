import 'package:flutter/material.dart';

import '../services/settings_service.dart';
import '../widgets/accessible_button.dart';

/// Home — the application entry point.
///
/// Branding + subtitle, a detection status card (reflecting Auto-Start), and a
/// primary "Go to Live Camera" action. The bottom navigation bar (in the shell)
/// provides access to the rest of the app.
class HomeScreen extends StatelessWidget {
  final SettingsService settings;
  final VoidCallback onGoToDetection;

  const HomeScreen({
    super.key,
    required this.settings,
    required this.onGoToDetection,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight - 48),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 24),
                    Icon(
                      Icons.remove_red_eye_rounded,
                      size: 96,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'EyeCue',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.displaySmall?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Smart navigation assistance for visually impaired users.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 32),
                    _StatusCard(settings: settings),
                    const SizedBox(height: 20),
                    AccessibleButton(
                      label: 'Go to Live Camera',
                      icon: Icons.videocam_rounded,
                      prominent: true,
                      onPressed: onGoToDetection,
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Status card that reflects the Auto-Start setting (thesis: Home shows
/// whether "Detection is already running").
class _StatusCard extends StatelessWidget {
  final SettingsService settings;

  const _StatusCard({required this.settings});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) {
        final on = settings.autoStartDetection;
        final text = on
            ? 'Detection is already running. Auto-Start is on. The camera began '
                  'detecting when the app opened. No action needed.'
            : 'Auto-Start is off. Open Detection and press Start to begin.';
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Icon(
                on ? Icons.bolt : Icons.power_settings_new,
                size: 28,
                color: on ? const Color(0xFFFFD600) : theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(text, style: theme.textTheme.bodyLarge),
              ),
            ],
          ),
        );
      },
    );
  }
}
