import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemUiOverlayStyle;

import '../theme/app_home_theme.dart';
import '../theme/app_radii.dart';
import '../theme/app_spacing.dart';

/// Help & Gestures — an auditory- and visual-friendly user manual explaining
/// how EyeCue works, the gesture controls, confirmation feedback, and Android
/// usage tips (chest mounting, earphones).
///
/// The Help subtree uses a locally scoped light visual theme
/// ([buildHomeTheme]) matching the Home light surface; the global dark theme
/// and the shell navigation bar are unchanged. The light surface is scoped to
/// the Help subtree only and must not leak into other tabs or the shell
/// navigation bar.
class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: buildHomeTheme(),
      // The Help subtree uses a light surface, so the status bar icons must be
      // dark to remain visible against it. The global dark theme keeps light
      // icons on the other (dark) screens; this AnnotatedRegion is scoped to
      // the Help subtree only.
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.dark,
        child: Scaffold(
          appBar: AppBar(title: const Text('Help & Gestures')),
          body: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final contentWidth = constraints.maxWidth;
                // Bounded, centered width so the cards and text stay readable
                // on wide constraints. Derived from available width, not the
                // screenshot.
                final boundedWidth = contentWidth > 480 ? 480.0 : contentWidth;
                return Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: boundedWidth),
                    child: ListView(
                      padding: const EdgeInsets.symmetric(
                        horizontal: kSpace16,
                        vertical: kSpace16,
                      ),
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
                              'EyeCue runs entirely on your device — no '
                              'internet needed.',
                        ),
                        _HelpCard(
                          icon: Icons.touch_app_rounded,
                          title: 'Gesture Controls',
                          body:
                              '• Two-finger double tap — start or exit '
                              'detection mode.\n'
                              '• Single tap — pause or resume detection.\n'
                              '• Three-finger tap — quick environmental '
                              'scan.\n'
                              '• One-finger swipe down — repeat the most '
                              'recent audio alert.',
                        ),
                        _HelpCard(
                          icon: Icons.vibration_rounded,
                          title: 'Gesture Confirmation',
                          body:
                              'Every gesture gives instant feedback: an audio '
                              'announcement plus a short vibration pulse, so '
                              'you always know the action was recognized — no '
                              'need to look at the screen.',
                        ),
                        _HelpCard(
                          icon: Icons.phone_android_rounded,
                          title: 'Best Use Tip (Android)',
                          body:
                              '• Mount or carry the phone at chest height for '
                              'the best view.\n'
                              '• Use earphones so audio cues are easy to '
                              'hear.\n'
                              '• Keep the camera lens clean and pointed '
                              'ahead.\n'
                              '• In Low Power Mode detection runs at a slower '
                              'rate to save battery.',
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// A light Help section card: a decorative icon + title header and the body
/// copy, exposed as one coherent semantic group with the title as the heading.
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
    return Container(
      margin: const EdgeInsets.only(bottom: kSpace16),
      padding: const EdgeInsets.all(kSpace16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(kRadius24),
        boxShadow: kHomeShadowSoft,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Decorative icon: it duplicates the adjacent title, so it is
              // excluded from the accessibility tree.
              ExcludeSemantics(
                child: Icon(icon, color: theme.colorScheme.primary, size: 28),
              ),
              const SizedBox(width: kSpace12),
              Expanded(
                child: Semantics(
                  // The section title is the semantic heading for the group.
                  // The inner Text is excluded so the title is exposed exactly
                  // once (no duplicate label from the visual text).
                  container: true,
                  header: true,
                  label: title,
                  child: ExcludeSemantics(
                    child: Text(
                      title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: kSpace12),
          Text(body, style: theme.textTheme.bodyLarge?.copyWith(height: 1.4)),
        ],
      ),
    );
  }
}
