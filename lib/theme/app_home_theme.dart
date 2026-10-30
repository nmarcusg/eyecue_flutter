import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';

/// Home-local light visual theme and decoration tokens.
///
/// The global dark [`buildEyeCueTheme`](app_theme.dart) and `ThemeMode.dark`
/// remain unchanged. This file supplies the light background, ink, cyan accent,
/// and IBM Plex Sans typography to the Home subtree only. It must never be
/// applied above the Home subtree or mutate the global navigation theme.
///
/// IBM Plex Sans is bundled offline under `assets/fonts/` (declared in
/// `pubspec.yaml`). Runtime HTTP fetching is disabled at the top of
/// [buildHomeTheme] so the package never falls back to a network request.

/// Soft shadow used by the preference/status badge.
const List<BoxShadow> kHomeShadowSoft = [
  BoxShadow(
    color: Color(0x140A0A0A), // rgba(10,10,10,0.08)
    offset: Offset(0, 6),
    blurRadius: 18,
  ),
];

/// Builds the Home-local light `ThemeData`.
///
/// Disables runtime font fetching before any `GoogleFonts` call so the bundled
/// IBM Plex Sans assets are always used. The returned theme is scoped to the
/// Home subtree and must not leak into other screens or the shell navigation.
ThemeData buildHomeTheme() {
  GoogleFonts.config.allowRuntimeFetching = false;

  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorScheme: ColorScheme.fromSeed(
      seedColor: kHomeAccentCyan,
      brightness: Brightness.light,
    ),
  );

  final textTheme = GoogleFonts.ibmPlexSansTextTheme(base.textTheme).copyWith(
    displayLarge: GoogleFonts.ibmPlexSans(
      fontSize: 40,
      fontWeight: FontWeight.w700,
      color: kHomeInk,
    ),
    displaySmall: GoogleFonts.ibmPlexSans(
      fontSize: 24,
      fontWeight: FontWeight.w700,
      color: kHomeInk,
    ),
    headlineLarge: GoogleFonts.ibmPlexSans(
      fontSize: 26,
      fontWeight: FontWeight.w700,
      color: kHomeInk,
    ),
    titleLarge: GoogleFonts.ibmPlexSans(
      fontSize: 24,
      fontWeight: FontWeight.w600,
      color: kHomeInk,
    ),
    titleMedium: GoogleFonts.ibmPlexSans(
      fontSize: 18,
      fontWeight: FontWeight.w600,
      color: kHomeInk,
    ),
    bodyLarge: GoogleFonts.ibmPlexSans(
      fontSize: 18,
      fontWeight: FontWeight.w500,
      color: kHomeInk,
    ),
    bodyMedium: GoogleFonts.ibmPlexSans(
      fontSize: 16,
      fontWeight: FontWeight.w400,
      color: kHomeInk,
    ),
    labelLarge: GoogleFonts.ibmPlexSans(
      fontSize: 14,
      fontWeight: FontWeight.w600,
      color: kHomeInk,
    ),
    labelMedium: GoogleFonts.ibmPlexSans(
      fontSize: 14,
      fontWeight: FontWeight.w500,
      color: kHomeInk,
    ),
    labelSmall: GoogleFonts.ibmPlexSans(
      fontSize: 14,
      fontWeight: FontWeight.w500,
      color: kHomeInk,
    ),
  );

  return base.copyWith(
    scaffoldBackgroundColor: kHomeSurfaceBase,
    textTheme: textTheme,
    // Fixed light app-bar surface shared by Settings, Help, and Logs &
    // Reports. The bar and the scrolling body therefore keep one consistent
    // light surface while scrolling (no scroll-driven color transitions).
    appBarTheme: AppBarTheme(
      backgroundColor: kHomeSurfaceBase,
      foregroundColor: kHomeInk,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: textTheme.titleLarge,
    ),
    // Light bottom-navigation presentation for the shell bar. Ownership of the
    // bar (destinations, callbacks, selection, visibility) stays in AppShell;
    // this only supplies the light/Home-theme visual treatment.
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: kHomeSurfaceCard,
      surfaceTintColor: Colors.transparent,
      indicatorColor: kHomeAccentCyanLight,
      elevation: 0,
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return textTheme.labelMedium?.copyWith(
          color: selected ? kHomeInk : kHomeInkMuted,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
        );
      }),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return IconThemeData(
          color: selected ? kHomeAccentCyanDark : kHomeInkMuted,
        );
      }),
    ),
    // Active toggle/radio/slider states use the cyan accent through the light
    // component themes so every control shares one token-backed treatment.
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return kHomeSurfaceCard;
        return null;
      }),
      trackColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return kHomeAccentCyan;
        return null;
      }),
    ),
    radioTheme: RadioThemeData(
      fillColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return kHomeAccentCyan;
        return null;
      }),
    ),
    sliderTheme: base.sliderTheme.copyWith(
      activeTrackColor: kHomeAccentCyan,
      thumbColor: kHomeAccentCyan,
      inactiveTrackColor: kHomeAccentCyanLight,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: kHomeAccentCyan,
        foregroundColor: kHomeInk,
        minimumSize: const Size(64, 56),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        textStyle: textTheme.labelLarge,
      ),
    ),
  );
}
