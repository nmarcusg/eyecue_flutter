import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemUiOverlayStyle;

import '../theme/app_colors.dart';
import '../theme/app_home_theme.dart';
import '../theme/app_spacing.dart';
import '../widgets/help_section_card.dart';
import '../widgets/safety_disclosure.dart';

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
          // The app-bar title uses the same `titleLarge` + ink treatment as the
          // Detection screen's `Detection Mode` header so the two top bars
          // share one typographic style. Background, elevation, and all other
          // app-bar behavior are unchanged.
          appBar: AppBar(
            title: Builder(
              builder: (context) => Text(
                'Help & Gestures',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(color: kHomeInk),
              ),
            ),
          ),
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
                        // The permanent copy of the safety disclosure. The
                        // first-use acknowledgement renders the same wording.
                        SafetyDisclosureCard(),
                        HelpSectionCard(
                          title: 'How It Works',
                          body:
                              '1. Open EyeCue.\n'
                              '2. Detection starts automatically, or use the '
                              'Start control.\n'
                              '3. Walk naturally with your phone.\n'
                              '4. Listen for audio cues about nearby objects.\n'
                              '5. Adjust your path safely.\n\n'
                              'EyeCue runs entirely on your device — no '
                              'internet needed.',
                        ),
                        // Per-item reading stops: one node per bullet.
                        HelpSectionCard(
                          title: 'Gesture Controls',
                          items: [
                            'Two-finger double tap — start or exit '
                                'detection mode.',
                            'Single tap — pause or resume detection.',
                            'Three-finger tap — quick environmental scan.',
                            'One-finger swipe down — repeat the most recent '
                                'audio alert.',
                          ],
                        ),
                        HelpSectionCard(
                          title: 'Gesture Confirmation',
                          body:
                              'Every gesture gives instant feedback: an audio '
                              'announcement plus a short vibration pulse, so '
                              'you always know the action was recognized — no '
                              'need to look at the screen.',
                        ),
                        // Per-item reading stops: one node per bullet.
                        HelpSectionCard(
                          title: 'Best Use Tip (Android)',
                          items: [
                            'Mount or carry the phone at chest height for '
                                'the best view.',
                            'Use earphones so audio cues are easy to hear.',
                            'Keep the camera lens clean and pointed ahead.',
                            'In Low Power Mode detection runs at a slower '
                                'rate to save battery.',
                          ],
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
