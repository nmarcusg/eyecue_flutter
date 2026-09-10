import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_typography.dart';

/// Builds the EyeCue high-contrast, dark-mode-friendly, accessibility-first
/// theme.
///
/// This was previously defined inline in `main.dart` as `_buildTheme()` and
/// is now the single source of truth for the app theme. It consumes the
/// semantic color tokens in `app_colors.dart` and the high-contrast
/// typography in `app_typography.dart`. No visual output has changed.
ThemeData buildEyeCueTheme() {
  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: ColorScheme.fromSeed(
      seedColor: kSeedColor,
      brightness: Brightness.dark,
    ),
  );
  return base.copyWith(
    scaffoldBackgroundColor: kScaffoldBackground,
    appBarTheme: const AppBarTheme(
      backgroundColor: kSurfaceBar,
      centerTitle: false,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: kSurfaceBar,
      indicatorColor: kNavIndicator,
    ),
    textTheme: highContrastTextTheme(),
  );
}
