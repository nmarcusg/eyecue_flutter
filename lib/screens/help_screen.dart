import 'package:flutter/material.dart';

/// Help & Gestures — an auditory- and visual-friendly user manual explaining
/// how EyeCue works, the gesture controls, confirmation feedback, and Android
/// usage tips (chest mounting, earphones).
class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Help & Gestures')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: const [
          _HelpCard(
            icon: Icons.timeline_rounded,
            title: 'How It Works',
            body:
                '1. Open EyeCue.\n'
                '2. Detection starts (or press Start).\n'
                '3. Walk naturally with your phone.\n'
                '4. Listen for audio cues about nearby objects.\n'
                '5. Adjust your path safely.\n\n'
                'EyeCue runs entirely on your device — no internet needed.',
          ),
          _HelpCard(
            icon: Icons.touch_app_rounded,
            title: 'Gesture Controls',
            body:
                '• Two-finger double tap — start or exit detection mode.\n'
                '• Single tap — pause or resume detection.\n'
                '• Three-finger tap — quick environmental scan.\n'
                '• One-finger swipe down — repeat the most recent audio alert.',
          ),
          _HelpCard(
            icon: Icons.vibration_rounded,
            title: 'Gesture Confirmation',
            body:
                'Every gesture gives instant feedback: an audio announcement '
                'plus a short vibration pulse, so you always know the action '
                'was recognized — no need to look at the screen.',
          ),
          _HelpCard(
            icon: Icons.phone_android_rounded,
            title: 'Best Use Tip (Android)',
            body:
                '• Mount or carry the phone at chest height for the best view.\n'
                '• Use earphones so audio cues are easy to hear.\n'
                '• Keep the camera lens clean and pointed ahead.\n'
                '• In Low Power Mode detection runs at a slower rate to save '
                'battery.',
          ),
        ],
      ),
    );
  }
}

class _HelpCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;

  const _HelpCard({
    required this.icon,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: theme.colorScheme.primary, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(body, style: theme.textTheme.bodyLarge?.copyWith(height: 1.4)),
          ],
        ),
      ),
    );
  }
}
