import 'package:flutter/services.dart';

/// Wraps device haptic feedback using Flutter's built-in [HapticFeedback]
/// (no extra dependency). Respects the Vibration Feedback setting through an
/// injected enabled-check so it stays decoupled from SettingsService.
///
/// Backends are injectable so widget/unit tests can substitute counting fakes
/// and never hit platform channels.
class HapticsService {
  HapticsService({
    bool Function()? isEnabled,
    Future<void> Function()? light,
    Future<void> Function()? medium,
    Future<void> Function()? heavy,
  })  : isEnabled = isEnabled ?? _alwaysEnabled,
        _light = light ?? _hapticLight,
        _medium = medium ?? _hapticMedium,
        _heavy = heavy ?? _hapticHeavy;

  final bool Function() isEnabled;
  final Future<void> Function() _light;
  final Future<void> Function() _medium;
  final Future<void> Function() _heavy;

  static bool _alwaysEnabled() => true;
  static Future<void> _hapticLight() => HapticFeedback.lightImpact();
  static Future<void> _hapticMedium() => HapticFeedback.mediumImpact();
  static Future<void> _hapticHeavy() => HapticFeedback.heavyImpact();

  /// Short tick — used for single-tap (pause/resume) feedback.
  Future<void> lightTick() async {
    if (!isEnabled()) return;
    await _light();
  }

  /// Medium pulse — used for two-finger double-tap (start/stop) and repeat.
  Future<void> mediumTick() async {
    if (!isEnabled()) return;
    await _medium();
  }

  /// Strong double-style confirmation — used for the quick scan.
  Future<void> heavyTick() async {
    if (!isEnabled()) return;
    await _heavy();
  }
}
