import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_home_theme.dart';
import '../theme/app_radii.dart';
import '../theme/app_spacing.dart';
import 'accessible_button.dart';
import 'warning_banner.dart';

/// The single source of the user-facing safety disclosure.
///
/// The permanent Help section and the first-use acknowledgement both render
/// these values, so the two surfaces can never drift apart. The Play Store
/// listing's safety/accessibility statement (item K) must mirror this wording.
const String kSafetyDisclosureTitle = 'Safety and Limitations';

/// The five disclosure points, in reading order.
const List<String> kSafetyDisclosurePoints = [
  'EyeCue is an experimental research and assistive application. Treat it as a '
      'prototype: it is not a medical device, and it cannot guarantee your '
      'safety.',
  'Object detection and estimated distances may be delayed, inaccurate or '
      'incomplete, so check what is around you yourself.',
  'EyeCue does not replace a white cane, a guide dog, trained orientation and '
      'mobility practice, your own situational awareness, or any other primary '
      'mobility aid.',
  'Do not rely on EyeCue as the only way to avoid hazards or to navigate '
      'independently.',
  'Stop using EyeCue if it becomes unsafe or distracting.',
];

/// The heading plus the five points, exposed as one semantic group in reading
/// order. The heading node is the group's semantic header, and the inner title
/// [Text] is excluded so the title is never announced twice.
class SafetyDisclosureBody extends StatelessWidget {
  const SafetyDisclosureBody({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      container: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            container: true,
            header: true,
            label: kSafetyDisclosureTitle,
            child: ExcludeSemantics(
              child: Text(
                kSafetyDisclosureTitle,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
          const SizedBox(height: kSpace12),
          for (final point in kSafetyDisclosurePoints) ...[
            // Each point is its own semantic node so TalkBack can move through
            // the disclosure one point at a time, in reading order.
            Semantics(
              container: true,
              child: Text(
                '• $point',
                style: theme.textTheme.bodyLarge?.copyWith(height: 1.4),
              ),
            ),
            const SizedBox(height: kSpace8),
          ],
        ],
      ),
    );
  }
}

/// The permanent Help-screen copy: the same light card treatment as the other
/// Help sections.
class SafetyDisclosureCard extends StatelessWidget {
  const SafetyDisclosureCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: kSpace16),
      padding: const EdgeInsets.all(kSpace16),
      decoration: BoxDecoration(
        color: kHomeSurfaceCard,
        borderRadius: BorderRadius.circular(kRadius24),
        boxShadow: kHomeShadowSoft,
      ),
      child: const SafetyDisclosureBody(),
    );
  }
}

/// The first-use acknowledgement.
///
/// A modal surface, not a transient message: the only exit is the explicit
/// [onAcknowledge] action (the route cannot be popped or barrier-dismissed).
class SafetyDisclosureDialog extends StatelessWidget {
  final VoidCallback onAcknowledge;

  const SafetyDisclosureDialog({super.key, required this.onAcknowledge});

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: AlertDialog(
        // Scrolls at large text scales instead of clipping the points.
        scrollable: true,
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Announces the surface on open; the lead line is not one of the
            // five points, so nothing is read twice.
            const WarningBanner(
              message: 'Read this before you rely on EyeCue.',
            ),
            const SizedBox(height: kSpace8),
            const SafetyDisclosureBody(),
            const SizedBox(height: kSpace8),
            AccessibleButton(
              label: 'I understand',
              icon: Icons.check_rounded,
              onPressed: onAcknowledge,
              prominent: true,
            ),
          ],
        ),
      ),
    );
  }
}
