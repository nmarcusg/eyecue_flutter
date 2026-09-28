import 'package:flutter/gestures.dart';
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

/// Arena-aware, **exactly-one-active-pointer** horizontal drag recognizer.
///
/// A standard [HorizontalDragGestureRecognizer] does not expose invalidation
/// when a second pointer joins an in-progress drag, so this recognizer
/// structurally enforces the one-finger contract: any second pointer
/// invalidates the complete physical-drag transaction, even if that pointer
/// later lifts. It accumulates one horizontal displacement and commits at
/// most once, in the drag-end callback.
class _SingleFingerHorizontalDragRecognizer
    extends HorizontalDragGestureRecognizer {
  _SingleFingerHorizontalDragRecognizer({
    required this.onCommit,
    required this.commitDistance,
    this.enabled,
  }) {
    onStart = _handleStart;
    onUpdate = _handleUpdate;
    onEnd = _handleEnd;
    onCancel = _handleCancel;
  }

  /// Called once with the committed direction (`-1` left, `+1` right).
  final void Function(int direction) onCommit;

  /// Minimum absolute accumulated horizontal displacement to commit.
  final double commitDistance;

  /// Whether the shell may own a horizontal drag at all.
  ///
  /// Detection (index 1) owns horizontal navigation inside its own viewport
  /// through its raw [GestureSurface] `Listener`. That surface does not compete
  /// in the gesture arena, so if the shell recognizer also accepted the same
  /// physical swipe it would produce two primary-tab moves. When this returns
  /// `false` the recognizer never claims the pointer, so Detection is the
  /// single owner of horizontal navigation inside its viewport.
  final bool Function()? enabled;

  /// True once a second pointer has joined the current sequence.
  bool _invalidated = false;
  double _accumulatedDx = 0;

  /// Pointers currently tracked by this recognizer for the active sequence.
  final Set<int> _trackedPointers = {};

  @override
  void addAllowedPointer(PointerDownEvent event) {
    // When the active page owns horizontal navigation (Detection), the shell
    // must not claim the pointer at all. Rejecting here keeps the recognizer
    // out of the arena for the whole sequence, so it can never commit a second
    // navigation for the same physical swipe.
    if (!(enabled?.call() ?? true)) {
      resolve(GestureDisposition.rejected);
      return;
    }
    // A second pointer joining invalidates the whole sequence.
    if (_trackedPointers.isNotEmpty) {
      _invalidated = true;
    } else {
      // First pointer of a new sequence: reset the accumulator.
      _accumulatedDx = 0;
    }
    _trackedPointers.add(event.pointer);
    super.addAllowedPointer(event);
  }

  @override
  void didStopTrackingLastPointer(int pointer) {
    _trackedPointers.remove(pointer);
    _invalidated = false;
    super.didStopTrackingLastPointer(pointer);
  }

  @override
  void rejectGesture(int pointer) {
    _invalidated = false;
    super.rejectGesture(pointer);
  }

  void _handleStart(DragStartDetails details) {
    // The accumulator is reset in addAllowedPointer (before any movement) so
    // the initial slop movement is not discarded here.
  }

  void _handleUpdate(DragUpdateDetails details) {
    _accumulatedDx += details.delta.dx;
  }

  void _handleEnd(DragEndDetails details) {
    final dx = _accumulatedDx;
    _accumulatedDx = 0;
    if (_invalidated || dx.abs() < commitDistance) return;
    // Product Decision 2: a left swipe (dx < 0) advances to the next tab and a
    // right swipe (dx > 0) returns to the previous tab.
    onCommit(dx < 0 ? 1 : -1);
  }

  void _handleCancel() {
    _accumulatedDx = 0;
  }
}

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
  /// Provisional/tunable commit distance for a primary horizontal drag.
  static const double _primarySwipeCommitDistance = 80.0;

  /// Concise destination names for wayfinding speech.
  static const List<String> _destinationNames = [
    'Home',
    'Detection',
    'Settings',
    'Help',
  ];

  int _index = 0;
  final List<bool> _visited = [true, false, false, false];
  final List<Widget?> _pages = List.filled(4, null);

  @override
  void initState() {
    super.initState();
    _syncAudio();
    widget.settings.addListener(_syncAudio);
    widget.settings.addListener(_handleSettingsChanged);
  }

  @override
  void dispose() {
    widget.settings.removeListener(_syncAudio);
    widget.settings.removeListener(_handleSettingsChanged);
    super.dispose();
  }

  void _syncAudio() {
    widget.tts.setAudioEnabled(widget.settings.audioEnabled);
  }

  /// Rebuilds the shell when the persisted hide-bar preference changes.
  void _handleSettingsChanged() {
    if (mounted) setState(() {});
  }

  /// Switches to a bottom-nav tab (used by Home's "Go to Live Camera" CTA).
  ///
  /// This is the direct, feedback-free path: it is shared by the visible
  /// navigation bar, the Home CTA, and Back, none of which should emit
  /// gesture-origin wayfinding feedback.
  void goToTab(int index) {
    if (index < 0 || index > 3) return;
    setState(() {
      _visited[index] = true;
      _index = index;
    });
  }

  /// Moves one tab in [direction] (`-1` toward Home, `+1` toward Help).
  ///
  /// Linear, non-wrapping: an out-of-range move stays on the current tab and
  /// emits boundary feedback once. This is the only path that produces
  /// gesture-origin wayfinding feedback.
  void navigateRelative(int direction) {
    if (direction == 0) return;
    final target = _index + (direction < 0 ? -1 : 1);
    if (target < 0 || target > 3) {
      _emitBoundaryFeedback();
      return;
    }
    setState(() {
      _visited[target] = true;
      _index = target;
    });
    _emitNavigationFeedback(target);
  }

  /// Gesture-origin success feedback: light tick + destination speech.
  void _emitNavigationFeedback(int target) {
    widget.haptics.lightTick();
    if (_accessibleNavigation) return;
    widget.tts.speakWayfinding(_destinationNames[target]);
  }

  /// Gesture-origin boundary feedback: medium tick + boundary speech.
  void _emitBoundaryFeedback() {
    widget.haptics.mediumTick();
    if (_accessibleNavigation) return;
    widget.tts.speakWayfinding('End of navigation');
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
          onNavigateRelative: navigateRelative,
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

  /// Whether Android accessibility navigation is currently active.
  ///
  /// Read from the [MediaQuery] aspect so the shell rebuilds when the feature
  /// changes. This is never written back to the persisted settings.
  bool get _accessibleNavigation => MediaQuery.accessibleNavigationOf(context);

  /// Effective bottom-bar visibility: the persisted preference, overridden to
  /// visible while accessibility navigation is active.
  bool get _effectiveHideBar =>
      widget.settings.hideBottomNavigation && !_accessibleNavigation;

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
        body: RawGestureDetector(
          behavior: HitTestBehavior.opaque,
          gestures: {
            _SingleFingerHorizontalDragRecognizer:
                GestureRecognizerFactoryWithHandlers<
                  _SingleFingerHorizontalDragRecognizer
                >(
                  () => _SingleFingerHorizontalDragRecognizer(
                    onCommit: navigateRelative,
                    commitDistance: _primarySwipeCommitDistance,
                    // Detection (index 1) owns horizontal navigation inside
                    // its own viewport via its raw GestureSurface; the shell
                    // recognizer must not claim the pointer there, or one
                    // physical swipe would move two primary tabs.
                    enabled: () => _index != 1,
                  ),
                  (recognizer) {},
                ),
          },
          child: IndexedStack(
            index: _index,
            children: [for (var i = 0; i < 4; i++) _ensurePage(i)],
          ),
        ),
        bottomNavigationBar: _effectiveHideBar
            ? null
            : NavigationBar(
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
