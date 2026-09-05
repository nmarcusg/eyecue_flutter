import 'package:flutter/material.dart';

/// Large, high-contrast, accessibility-friendly button.
///
/// Enforces a >= 48dp-height touch target and exposes a semantic label so it
/// works with TalkBack. Used both as the visible fallback for gestures and on
/// the Home screen's primary CTA.
class AccessibleButton extends StatelessWidget {
  final String label;
  final IconData icon;

  /// When null the button is rendered disabled.
  final VoidCallback? onPressed;
  final bool prominent;

  const AccessibleButton({
    super.key,
    required this.label,
    required this.icon,
    this.onPressed,
    this.prominent = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      label: label,
      enabled: onPressed != null,
      hint: onPressed == null ? 'Unavailable' : 'Double tap to activate',
      onTap: onPressed,
      child: ExcludeSemantics(
        child: ElevatedButton.icon(
          onPressed: onPressed,
          icon: Icon(icon, size: 26),
          label: Text(
            label,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          style: ElevatedButton.styleFrom(
            minimumSize: const Size(64, 56),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            backgroundColor: prominent
                ? theme.colorScheme.primary
                : theme.colorScheme.surfaceContainerHighest,
            foregroundColor: prominent
                ? theme.colorScheme.onPrimary
                : theme.colorScheme.onSurface,
          ),
        ),
      ),
    );
  }
}
