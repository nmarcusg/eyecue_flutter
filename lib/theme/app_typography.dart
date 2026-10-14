import 'package:flutter/material.dart';

/// High-contrast typography for EyeCue.
///
/// This is the single source of truth for the concrete high-contrast
/// `TextTheme` (white text, M3 sizes scaled ~1.12x for readability). It was
/// previously defined inline in `main.dart` as `_highContrastTextTheme()`.
///
/// Explicit concrete font sizes are required here: the default M3 `TextTheme`
/// is color-only (`fontSize == null`; geometry is merged per locale at render
/// time), so `TextTheme.apply(fontSizeFactor:)` would assert. These are the M3
/// sizes scaled ~1.12x for high-contrast readability, all in white.
TextTheme highContrastTextTheme() {
  const white = Colors.white;
  return const TextTheme(
    displayLarge: TextStyle(fontSize: 64, color: white),
    displayMedium: TextStyle(fontSize: 50, color: white),
    displaySmall: TextStyle(fontSize: 40, color: white),
    headlineLarge: TextStyle(
      fontSize: 36,
      color: white,
      fontWeight: FontWeight.w600,
    ),
    headlineMedium: TextStyle(
      fontSize: 31,
      color: white,
      fontWeight: FontWeight.w600,
    ),
    headlineSmall: TextStyle(
      fontSize: 27,
      color: white,
      fontWeight: FontWeight.w600,
    ),
    titleLarge: TextStyle(
      fontSize: 25,
      color: white,
      fontWeight: FontWeight.w700,
    ),
    titleMedium: TextStyle(
      fontSize: 18,
      color: white,
      fontWeight: FontWeight.w600,
    ),
    titleSmall: TextStyle(
      fontSize: 16,
      color: white,
      fontWeight: FontWeight.w600,
    ),
    bodyLarge: TextStyle(fontSize: 18, color: white),
    bodyMedium: TextStyle(fontSize: 16, color: white),
    bodySmall: TextStyle(fontSize: 13, color: white),
    labelLarge: TextStyle(
      fontSize: 16,
      color: white,
      fontWeight: FontWeight.w700,
    ),
    labelMedium: TextStyle(
      fontSize: 13,
      color: white,
      fontWeight: FontWeight.w600,
    ),
    labelSmall: TextStyle(
      fontSize: 12,
      color: white,
      fontWeight: FontWeight.w500,
    ),
  );
}
