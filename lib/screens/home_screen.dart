import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemUiOverlayStyle;

import '../services/settings_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_home_theme.dart';
import '../theme/app_radii.dart';
import '../theme/app_spacing.dart';
import '../widgets/accessible_button.dart';

/// Home — the application entry point.
///
/// Branding + a preference/status badge (reflecting Auto-Start), a centered
/// decorative mark with a live `EyeCue` wordmark, and a lower instruction
/// region with a truthful headline, supporting copy, the primary
/// "Go to Live Camera" action, and a static decorative cyan rail.
///
/// The Home subtree uses a locally scoped light visual theme
/// ([buildHomeTheme]); the global dark theme and the shell navigation bar are
/// unchanged. The bottom navigation bar (in the shell) provides access to the
/// rest of the app.
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
    return Theme(
      data: buildHomeTheme(),
      // The Home subtree uses a light surface, so the status bar icons must be
      // dark to remain visible against it. The global dark theme keeps light
      // icons on the other (dark) screens; this AnnotatedRegion is scoped to
      // the Home subtree only.
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.dark,
        child: Scaffold(
          body: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final contentWidth = constraints.maxWidth;
                // Bounded, centered width for the brand group and the lower
                // instruction region so text and the rail stay readable on wide
                // constraints. Derived from available width, not the screenshot.
                final boundedWidth = contentWidth > 480 ? 480.0 : contentWidth;
                // A scrollable column with generous vertical gaps between the
                // badge, brand group, and instruction region. This keeps the
                // composition airy on tall screens while scrolling gracefully
                // (never overflowing) when the content is taller than the
                // viewport, e.g. at 200% text scale.
                // CustomScrollView + SliverFillRemaining(hasScrollBody: false)
                // fills the available viewport when the content is shorter than
                // it and lets the whole column scroll when the content is
                // taller (e.g. at 200% text scale). The badge is pinned to the
                // top, the brand group is vertically centered in the remaining
                // space, and the instruction region is anchored toward the
                // bottom, matching the reference composition.
                return CustomScrollView(
                  slivers: [
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: kSpace16,
                        vertical: kSpace24,
                      ),
                      sliver: SliverFillRemaining(
                        hasScrollBody: false,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // Leading preference/status badge near the top.
                            Align(
                              alignment: Alignment.centerLeft,
                              child: _StatusBadge(settings: settings),
                            ),
                            const Spacer(flex: 2),
                            // Centered brand group: decorative mark + wordmark.
                            Center(
                              child: ConstrainedBox(
                                constraints: BoxConstraints(
                                  maxWidth: boundedWidth,
                                ),
                                child: Column(
                                  children: [
                                    // Decorative mark; excluded from semantics
                                    // because the adjacent live wordmark carries
                                    // the meaning.
                                    ExcludeSemantics(
                                      child: Image.asset(
                                        'assets/logo.png',
                                        width: 110,
                                        height: 110,
                                        fit: BoxFit.contain,
                                      ),
                                    ),
                                    const SizedBox(height: kSpace12),
                                    Text(
                                      'EyeCue',
                                      textAlign: TextAlign.center,
                                      style: Theme.of(
                                        context,
                                      ).textTheme.displayLarge,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const Spacer(flex: 2),
                            // Lower instruction region anchored toward the
                            // bottom.
                            Center(
                              child: ConstrainedBox(
                                constraints: BoxConstraints(
                                  maxWidth: boundedWidth,
                                ),
                                child: _InstructionRegion(
                                  settings: settings,
                                  onGoToDetection: onGoToDetection,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
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
}

/// Preference/status badge that reflects the Auto-Start setting.
///
/// This is a non-interactive semantic container. `READY` is a presentation of
/// the `autoStartDetection` preference only — it is not evidence that the
/// camera, model, engine, or detection runtime is ready or running.
class _StatusBadge extends StatelessWidget {
  final SettingsService settings;

  const _StatusBadge({required this.settings});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) {
        final on = settings.autoStartDetection;
        final label = on ? 'READY' : 'AUTO-START OFF';
        final meaning = on
            ? 'Auto-Start is on. Detection will begin when you open Detect.'
            : 'Auto-Start is off. Open Detect and press Start to begin.';
        final dotColor = on ? kHomeAccentCyan : kHomeInkMuted;
        return Semantics(
          container: true,
          label: meaning,
          child: ExcludeSemantics(
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: kSpace16,
                vertical: kSpace8,
              ),
              decoration: BoxDecoration(
                color: kHomeSurfaceCard96,
                borderRadius: BorderRadius.circular(kRadius24),
                boxShadow: kHomeShadowSoft,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: kSpace8,
                    height: kSpace8,
                    decoration: BoxDecoration(
                      color: dotColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: kSpace8),
                  Text(
                    label,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: kHomeInk,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Lower instruction region: truthful headline, supporting copy, the retained
/// accessible CTA, and a static decorative cyan rail.
class _InstructionRegion extends StatelessWidget {
  final SettingsService settings;
  final VoidCallback onGoToDetection;

  const _InstructionRegion({
    required this.settings,
    required this.onGoToDetection,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) {
        final on = settings.autoStartDetection;
        final headline = on ? 'Ready when you are' : 'Start when you are ready';
        final supporting = on
            ? 'Auto-Start is on. Detection will begin when you open Detect.'
            : 'Auto-Start is off. Open Detect and press Start to begin.';
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              headline,
              textAlign: TextAlign.left,
              style: Theme.of(context).textTheme.headlineLarge,
            ),
            const SizedBox(height: kSpace8),
            Text(
              supporting,
              textAlign: TextAlign.left,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: kHomeInkMuted),
            ),
            const SizedBox(height: kSpace20),
            AccessibleButton(
              label: 'Go to Live Camera',
              icon: Icons.videocam_rounded,
              prominent: true,
              onPressed: onGoToDetection,
            ),
            const SizedBox(height: kSpace24),
            // Static decorative cyan rail. Not an interactive track, progress
            // indicator, or gesture affordance; excluded from semantics.
            ExcludeSemantics(
              child: Container(
                height: kSpace6,
                decoration: BoxDecoration(
                  color: kHomeAccentCyanLight,
                  borderRadius: BorderRadius.circular(kRadius3),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
