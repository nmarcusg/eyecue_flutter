import 'package:flutter/material.dart';

/// Semantic color tokens for EyeCue.
///
/// These values are extracted verbatim from the existing UI (theme in
/// `main.dart` plus the widgets/screens that previously hardcoded them) so
/// that this refactor changes *where* values live, never the rendered output.
/// Do not invent new colors here; add a token only when a value is actually
/// used by UI code.
///
/// Prefer these tokens over raw `Color(...)`/`Colors.*` literals in new UI.
/// Colors that are already derived from the active `ThemeData`/`ColorScheme`
/// (e.g. `theme.colorScheme.surface`) are intentionally NOT duplicated here.
/// Brand / seed color used to derive the Material 3 dark `ColorScheme`.
const Color kSeedColor = Color(0xFFFFC107);

/// Global scaffold background.
const Color kScaffoldBackground = Color(0xFF121212);

/// App bar and navigation bar background.
const Color kSurfaceBar = Color(0xFF1E1E1E);

/// Navigation bar selected indicator background.
const Color kNavIndicator = Color(0xFF3E2C00);

/// Primary accent used for emphasis (charts axis, home status "on").
const Color kAccent = Color(0xFFFFC107);

/// Warning / high-priority red (banner background, high badge).
const Color kWarningRed = Color(0xFFB71C1C);

/// Medium-priority amber badge background.
const Color kMediumAmber = Color(0xFFF9A825);

/// Low-priority green badge background.
const Color kLowGreen = Color(0xFF1B5E20);

/// Detecting / active green status.
const Color kStatusGreen = Color(0xFF1B5E20);

/// Paused amber status.
const Color kStatusAmber = Color(0xFFF57F17);

/// Stopped blue-grey status.
const Color kStatusBlueGrey = Color(0xFF455A64);

/// Loading blue status.
const Color kStatusBlue = Color(0xFF0D47A1);

/// Semi-transparent black overlay (gesture pill, debug overlay).
const Color kOverlayBlack = Color(0xCC000000);

/// White text / foreground used on colored surfaces.
const Color kOnAccentWhite = Colors.white;

/// Dark text used on light/amber surfaces (medium badge foreground).
const Color kOnAmberDark = Color(0xFF1A1A1A);

/// Priority accent colors used in Logs & Reports summary rows.
const Color kPriorityHigh = Color(0xFFEF5350);
const Color kPriorityMedium = Color(0xFFFFCA28);
const Color kPriorityLow = Color(0xFF66BB6A);

// ---------------------------------------------------------------------------
// Home-local light semantic color tokens.
//
// These are the approved values from the authoritative extracted design-token
// Markdown source. They are scoped to the Home subtree's light visual theme and
// must not replace the global dark tokens above or reinterpret `kAccent`.
// ---------------------------------------------------------------------------

/// Home content background (light surface).
const Color kHomeSurfaceBase = Color(0xFFF5F5F5);

/// Light CTA/badge/card surface when needed.
const Color kHomeSurfaceCard = Color(0xFFFFFFFF);

/// Preference/status badge surface (96% white).
const Color kHomeSurfaceCard96 = Color(0xF5FFFFFF);

/// Wordmark and primary Home text.
const Color kHomeInk = Color(0xFF0A0A0A);

/// Supporting copy and off-state dot.
const Color kHomeInkMuted = Color(0xFF667085);

/// Ready dot, primary Home accent, active light treatment.
const Color kHomeAccentCyan = Color(0xFF22C7F2);

/// Static rail accent.
const Color kHomeAccentCyanLight = Color(0xFFB9EFFF);

/// Accessible dark cyan variant for a Home-specific pressed/glyph treatment.
const Color kHomeAccentCyanDark = Color(0xFF087A9E);

/// Reserved for the deferred Preparing variant; not used to imply Auto-Start off.
const Color kHomeWarningAmber = Color(0xFFF5B942);

/// Inner surface for the `View Logs & Reports` action area on the dark
/// System Performance card (11% white). Scoped to that action area only.
const Color kHomeOverlayWhite11 = Color(0x1CFFFFFF);
