import 'package:eyecue_flutter/main.dart';
import 'package:eyecue_flutter/services/haptics_service.dart';
import 'package:eyecue_flutter/services/settings_service.dart';
import 'package:eyecue_flutter/services/telemetry_service.dart';
import 'package:eyecue_flutter/services/tts_service.dart';
import 'package:eyecue_flutter/theme/app_colors.dart';
import 'package:eyecue_flutter/theme/app_home_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Fake engine that models the real lifecycle signal order.
///
/// `TtsService.init()` installs all four handlers; `speak()` then models a
/// successful utterance by emitting start, emitting completion, and resolving
/// with result `1`.
class _FakeTtsEngine implements TtsEngine {
  VoidCallback? _onStart;
  VoidCallback? _onComplete;
  VoidCallback? _onCancel;
  void Function(dynamic)? _onError;

  /// When set, the next utterance fails deterministically instead of speaking.
  bool failNext = false;

  @override
  Future<void> dispose() async {}

  @override
  Future<void> init() async {}

  @override
  Future<int> speak(String text) async {
    if (failNext) {
      failNext = false;
      _onError?.call('simulated TTS failure');
      return 0;
    }
    _onStart?.call();
    _onComplete?.call();
    return 1;
  }

  @override
  Future<void> stop() async {
    _onCancel?.call();
  }

  @override
  Future<void> recover() async {}

  @override
  void setStartHandler(VoidCallback? callback) => _onStart = callback;

  @override
  void setCompletionHandler(VoidCallback? callback) => _onComplete = callback;

  @override
  void setCancelHandler(VoidCallback? callback) => _onCancel = callback;

  @override
  void setErrorHandler(void Function(dynamic error)? handler) =>
      _onError = handler;
}

/// Regression test for the startup theme crash:
/// `TextTheme.apply(fontSizeFactor:)` asserted because the default M3
/// TextTheme is color-only (fontSize == null). EyeCue now supplies an explicit
/// high-contrast TextTheme with concrete font sizes, so the app must build and
/// render the Home screen without throwing.
void main() {
  testWidgets('EyeCueApp builds the theme and renders the Home screen', (
    tester,
  ) async {
    final tts = TtsService(engine: _FakeTtsEngine());
    // init() installs the lifecycle handlers the scheduler depends on.
    await tts.init();
    addTearDown(tts.dispose);

    final app = EyeCueApp(
      settings: SettingsService(store: InMemorySettingsStore()),
      tts: tts,
      telemetry: TelemetryService(),
      haptics: HapticsService(),
    );

    await tester.pumpWidget(app);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('EyeCue'), findsOneWidget);
    // The finalized Home has no CTA. The lifecycle copy itself is covered by
    // widget_test.dart with a controlled coordinator; this test protects the
    // startup theme regression only.
    expect(find.text('Go to Live Camera'), findsNothing);

    // The concrete text theme must be in effect (no null-fontSize assertion).
    // The Home screen now applies a Home-local light theme, so the `EyeCue`
    // wordmark resolves to the light ink color rather than the global dark
    // theme's white text. The global dark theme itself is unchanged.
    final context = tester.element(find.text('EyeCue'));
    final bodyMedium = Theme.of(context).textTheme.bodyMedium;
    expect(bodyMedium?.fontSize, isNotNull);
    expect(bodyMedium?.color, const Color(0xFF0A0A0A));
  });

  group('buildHomeTheme light component treatment', () {
    test('supplies a fixed light app-bar surface', () {
      final theme = buildHomeTheme();
      expect(theme.appBarTheme.backgroundColor, kHomeSurfaceBase);
      expect(theme.appBarTheme.foregroundColor, kHomeInk);
      expect(theme.appBarTheme.elevation, 0);
      expect(theme.appBarTheme.scrolledUnderElevation, 0);
      expect(theme.scaffoldBackgroundColor, kHomeSurfaceBase);
    });

    test('supplies a light navigation-bar presentation', () {
      final theme = buildHomeTheme();
      final nav = theme.navigationBarTheme;
      expect(nav.backgroundColor, kHomeSurfaceCard);
      expect(nav.indicatorColor, kHomeAccentCyanLight);
      // Selected icon uses the dark cyan accent; unselected uses muted ink.
      expect(
        nav.iconTheme?.resolve({WidgetState.selected})?.color,
        kHomeAccentCyanDark,
      );
      expect(
        nav.iconTheme?.resolve({WidgetState.selected})?.color,
        isNot(kHomeInkMuted),
      );
    });

    test('active toggle/radio/slider states use the cyan accent', () {
      final theme = buildHomeTheme();
      expect(
        theme.switchTheme.trackColor?.resolve({WidgetState.selected}),
        kHomeAccentCyan,
      );
      expect(
        theme.radioTheme.fillColor?.resolve({WidgetState.selected}),
        kHomeAccentCyan,
      );
      expect(theme.sliderTheme.activeTrackColor, kHomeAccentCyan);
      expect(theme.sliderTheme.thumbColor, kHomeAccentCyan);
    });

    test('overlay-white-11 token matches the supplied value', () {
      expect(kHomeOverlayWhite11, const Color(0x1CFFFFFF));
    });
  });
}
