import 'package:flutter/material.dart';

import '../screens/engine_detection_screen.dart';
import '../screens/help_screen.dart';
import '../screens/home_screen.dart';
import '../screens/logs_reports_screen.dart';
import '../screens/settings_screen.dart';
import '../services/correction_service.dart';
import '../services/haptics_service.dart';
import '../services/settings_service.dart';
import '../services/telemetry_service.dart';
import '../services/tts_service.dart';

/// Root scaffold with the 4-tab bottom navigation (Home, Detect, Settings,
/// Help). Logs & Reports is pushed as a separate full-screen route from
/// Settings, keeping it out of the primary user workflow (per the thesis).
///
/// Pages are built lazily and kept alive via an [IndexedStack], so the
/// Detection screen's camera state is preserved when switching tabs.
class AppShell extends StatefulWidget {
  final SettingsService settings;
  final TtsService tts;
  final TelemetryService telemetry;
  final CorrectionService? corrections;
  final HapticsService haptics;

  /// Test hook — supply your own page widgets instead of the real screens.
  final List<Widget> Function(BuildContext context, AppShellState shell)?
  pagesOverride;

  const AppShell({
    super.key,
    required this.settings,
    required this.tts,
    required this.telemetry,
    this.corrections,
    required this.haptics,
    this.pagesOverride,
  });

  @override
  State<AppShell> createState() => AppShellState();
}

class AppShellState extends State<AppShell> {
  int _index = 0;
  final List<bool> _visited = [true, false, false, false];
  final List<Widget?> _pages = List.filled(4, null);

  @override
  void initState() {
    super.initState();
    _syncAudio();
    widget.settings.addListener(_syncAudio);
  }

  @override
  void dispose() {
    widget.settings.removeListener(_syncAudio);
    super.dispose();
  }

  void _syncAudio() {
    widget.tts.setAudioEnabled(widget.settings.audioEnabled);
  }

  /// Switches to a bottom-nav tab (used by Home's "Go to Live Camera" CTA).
  void goToTab(int index) {
    if (index < 0 || index > 3) return;
    setState(() {
      _visited[index] = true;
      _index = index;
    });
  }

  /// Opens the researcher-facing Logs & Reports screen (from Settings).
  void openLogsReports() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => LogsReportsScreen(
          telemetry: widget.telemetry,
          settings: widget.settings,
          corrections: widget.corrections,
        ),
      ),
    );
  }

  Widget _buildPage(int index) {
    if (widget.pagesOverride != null) {
      return widget.pagesOverride!(context, this)[index];
    }
    switch (index) {
      case 0:
        return HomeScreen(
          settings: widget.settings,
          onGoToDetection: () => goToTab(1),
        );
      case 1:
        return EngineDetectionScreen(
          settings: widget.settings,
          tts: widget.tts,
          telemetry: widget.telemetry,
          corrections: widget.corrections,
          haptics: widget.haptics,
        );
      case 2:
        return SettingsScreen(
          settings: widget.settings,
          onOpenLogsReports: openLogsReports,
          telemetry: widget.telemetry,
        );
      case 3:
        return const HelpScreen();
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _ensurePage(int index) {
    if (!_visited[index]) return const SizedBox.shrink();
    return _pages[index] ??= _buildPage(index);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _index == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _index != 0) {
          goToTab(0);
        }
      },
      child: Scaffold(
        body: IndexedStack(
          index: _index,
          children: [for (var i = 0; i < 4; i++) _ensurePage(i)],
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: goToTab,
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home_rounded),
              label: 'Home',
            ),
            NavigationDestination(
              icon: Icon(Icons.center_focus_strong_outlined),
              selectedIcon: Icon(Icons.center_focus_strong_rounded),
              label: 'Detect',
            ),
            NavigationDestination(
              icon: Icon(Icons.settings_outlined),
              selectedIcon: Icon(Icons.settings_rounded),
              label: 'Settings',
            ),
            NavigationDestination(
              icon: Icon(Icons.help_outline_rounded),
              selectedIcon: Icon(Icons.help_rounded),
              label: 'Help',
            ),
          ],
        ),
      ),
    );
  }
}
