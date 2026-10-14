import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemUiOverlayStyle;

import '../models/detection_runtime_state.dart';
import '../services/engine_coordinator.dart';
import '../services/settings_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_home_theme.dart';
import '../theme/app_radii.dart';
import '../theme/app_spacing.dart';

/// Home — the application entry point.
///
/// Branding + a shared Detection lifecycle/status badge, a centered decorative
/// mark with a live `EyeCue` wordmark, and a lower instruction region with a
/// truthful headline, supporting copy, and a static decorative cyan rail.
///
/// Home renders its visible lifecycle/status from the app-shell-owned
/// [EngineCoordinator] snapshot only. It never queries settings for status and
/// performs no lifecycle action; there is no CTA.
///
/// The Home subtree uses a locally scoped light visual theme
/// ([buildHomeTheme]); the global dark theme and the shell navigation bar are
/// unchanged. The bottom navigation bar (in the shell) provides access to the
/// rest of the app.
class HomeScreen extends StatelessWidget {
  final SettingsService settings;

  /// The single app-shell-owned Detection lifecycle/status source.
  final EngineCoordinator coordinator;

  const HomeScreen({
    super.key,
    required this.settings,
    required this.coordinator,
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
                // Fixed, non-scrollable normal composition. The badge is pinned
                // to the top, the brand group is vertically centered in the
                // remaining space, and the instruction region is anchored toward
                // the bottom, matching the reference composition. The layout is
                // bounded by the viewport (no scroll container); the brand group
                // and instruction region are wrapped in Flexible so the column
                // can shrink gracefully instead of overflowing when the content
                // is taller than the viewport (e.g. at 200% text scale).
                return Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: kSpace16,
                    vertical: kSpace24,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Leading shared lifecycle/status badge near the top.
                      Align(
                        alignment: Alignment.centerLeft,
                        child: _StatusBadge(coordinator: coordinator),
                      ),
                      const Spacer(),
                      // Centered brand group: decorative mark + wordmark.
                      // The brand group is NOT flexible so the fixed logo
                      // renders at its full, consistent size instead of being
                      // squeezed by the surrounding spacers. The spacers absorb
                      // the remaining space and shrink first on short viewports.
                      Center(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(maxWidth: boundedWidth),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Decorative mark; excluded from semantics
                              // because the adjacent live wordmark carries
                              // the meaning. Fixed, non-flexible logo so it
                              // renders at a consistent, larger size and never
                              // shrinks with the surrounding layout.
                              ExcludeSemantics(
                                child: Image.asset(
                                  'assets/logo.png',
                                  width: 140,
                                  height: 140,
                                  fit: BoxFit.contain,
                                ),
                              ),
                              const SizedBox(height: kSpace12),
                              Text(
                                'EyeCue',
                                textAlign: TextAlign.center,
                                style: Theme.of(context).textTheme.displayLarge,
                              ),
                            ],
                          ),
                        ),
                      ),
                      const Spacer(),
                      // Lower instruction region anchored toward the bottom.
                      Flexible(
                        child: Center(
                          child: ConstrainedBox(
                            constraints: BoxConstraints(maxWidth: boundedWidth),
                            child: _InstructionRegion(coordinator: coordinator),
                          ),
                        ),
                      ),
                    ],
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

/// Shared Detection lifecycle/status badge.
///
/// This is a non-interactive semantic container that renders the app-shell
/// coordinator snapshot. It never reads the Auto-start preference or any
/// engine-local flag; the visible label and meaning come from the single
/// shared lifecycle mapping.
class _StatusBadge extends StatelessWidget {
  final EngineCoordinator coordinator;

  const _StatusBadge({required this.coordinator});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: coordinator,
      builder: (context, _) {
        final presentation = _homeStatusPresentation(
          coordinator.state,
          coordinator.failure,
        );
        return Semantics(
          container: true,
          label: presentation.meaning,
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
                      color: presentation.dotColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: kSpace8),
                  Text(
                    presentation.badge,
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

/// Lower instruction region: shared-lifecycle headline, supporting copy, and a
/// static decorative cyan rail. There is no CTA.
class _InstructionRegion extends StatelessWidget {
  final EngineCoordinator coordinator;

  const _InstructionRegion({required this.coordinator});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: coordinator,
      builder: (context, _) {
        final presentation = _homeStatusPresentation(
          coordinator.state,
          coordinator.failure,
        );
        // The instruction region is bounded by the fixed Home layout, so the
        // text children are Flexible and can shrink (with ellipsis) instead of
        // overflowing when the viewport is short or text is scaled up.
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Flexible(
              child: Text(
                presentation.headline,
                textAlign: TextAlign.left,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.headlineLarge,
              ),
            ),
            const SizedBox(height: kSpace8),
            Flexible(
              child: Text(
                presentation.supporting,
                textAlign: TextAlign.left,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: kHomeInkMuted),
              ),
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

/// The finalized Home presentation for one shared lifecycle outcome.
class _HomeStatusPresentation {
  const _HomeStatusPresentation({
    required this.badge,
    required this.headline,
    required this.supporting,
    required this.meaning,
    required this.dotColor,
  });

  final String badge;
  final String headline;
  final String supporting;
  final String meaning;
  final Color dotColor;
}

/// Maps the shared coordinator snapshot to the finalized Home copy.
///
/// This is the single user-facing lifecycle mapping shared with both Detection
/// engines; it never reads the Auto-start preference or engine-local flags.
_HomeStatusPresentation _homeStatusPresentation(
  DetectionRuntimeState state,
  DetectionFailure? failure,
) {
  switch (detectionStatusOutcomeFor(state)) {
    case DetectionStatusOutcome.preparing:
      // The initial idle state is the Auto-start-OFF, not-started
      // presentation; any other Preparing source is active initialization.
      final isInitialIdle = state == DetectionRuntimeState.idle;
      return _HomeStatusPresentation(
        badge: 'PREPARING',
        headline: isInitialIdle
            ? 'Swipe left to start!'
            : 'Getting things ready',
        supporting: isInitialIdle
            ? 'Detection begins immediately.'
            : 'Detection is preparing.',
        meaning: isInitialIdle
            ? 'Preparing. Swipe left to start! Detection begins immediately.'
            : 'Preparing. Getting things ready. Detection is preparing.',
        dotColor: kHomeWarningAmber,
      );
    case DetectionStatusOutcome.ready:
      return const _HomeStatusPresentation(
        badge: 'READY',
        headline: 'Ready when you are',
        supporting: 'Detection is ready.',
        meaning: 'Ready. Ready when you are. Detection is ready.',
        dotColor: kHomeAccentCyan,
      );
    case DetectionStatusOutcome.paused:
      return const _HomeStatusPresentation(
        badge: 'PAUSED',
        headline: 'Detection is paused',
        supporting: 'Open Detect to resume.',
        meaning: 'Paused. Detection is paused. Open Detect to resume.',
        dotColor: kHomeInkMuted,
      );
    case DetectionStatusOutcome.stopped:
      return const _HomeStatusPresentation(
        badge: 'STOPPED',
        headline: 'Detection is stopped',
        supporting: 'Open Detect to start again.',
        meaning: 'Stopped. Detection is stopped. Open Detect to start again.',
        dotColor: kHomeInkMuted,
      );
    case DetectionStatusOutcome.unavailable:
      final message = failure?.userMessage ?? 'Detection is unavailable.';
      return _HomeStatusPresentation(
        badge: 'UNAVAILABLE',
        headline: 'Detection needs attention',
        supporting: message,
        meaning: 'Unavailable. Detection needs attention. $message',
        dotColor: kWarningRed,
      );
  }
}
