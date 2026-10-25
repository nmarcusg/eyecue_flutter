import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../screens/engine_detection_screen.dart';
import '../screens/help_screen.dart';
import '../screens/home_screen.dart';
import '../screens/logs_reports_screen.dart';
import '../screens/settings_screen.dart';
import '../services/correction_service.dart';
import '../services/engine_coordinator.dart';
import '../services/haptics_service.dart';
import '../services/settings_service.dart';
import '../services/telemetry_service.dart';
import '../services/tts_service.dart';
import '../theme/app_home_theme.dart';
import '../widgets/safety_disclosure.dart';

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
  /// Detection (index 1) owns horizontal navigation over its whole main area
  /// through its raw [GestureSurface] `Listener`. That surface does not compete
  /// in the gesture arena, so if the shell recognizer also accepted the same
  /// physical swipe it would produce two primary-tab moves. When this returns
  /// `false` the recognizer never claims the pointer, so Detection is the
  /// single owner of horizontal navigation over its whole main area.
  final bool Function()? enabled;

  /// True once a second pointer has joined the current sequence.
  ///
  /// Stays true until the next sequence starts, so a second pointer that
  /// entered and then lifted can never re-arm the remaining pointer.
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
    if (_trackedPointers.isEmpty) {
      // First pointer of a new sequence: reset the accumulator and the
      // invalidation carried by the previous sequence.
      _accumulatedDx = 0;
      _invalidated = false;
    } else {
      // A second pointer joining invalidates the whole sequence.
      _invalidated = true;
    }
    _trackedPointers.add(event.pointer);
    super.addAllowedPointer(event);
  }

  @override
  void didStopTrackingLastPointer(int pointer) {
    _trackedPointers.remove(pointer);
    // super() dispatches the drag end, so the invalidation flag must still be
    // visible to [_handleEnd] here; only a new sequence clears it.
    super.didStopTrackingLastPointer(pointer);
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

  /// Test hook — supply a coordinator so tests can observe the shared
  /// lifecycle/start-intent state the shell owns. Production leaves this null
  /// and the shell constructs its own instance.
  final EngineCoordinator? coordinatorOverride;

  const AppShell({
    super.key,
    required this.settings,
    required this.tts,
    required this.telemetry,
    this.corrections,
    required this.haptics,
    this.pagesOverride,
    this.coordinatorOverride,
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

  /// The single app-shell-owned Detection lifecycle/status source.
  ///
  /// Home, Custom Detection, and Ultralytics Detection all render their
  /// user-facing lifecycle status from this one instance. It is created once
  /// from the already-loaded persisted preferred engine and disposed with the
  /// shell.
  late final EngineCoordinator _coordinator =
      widget.coordinatorOverride ??
      EngineCoordinator(
        preferredEngine: widget.settings.inferenceEngine,
        telemetry: widget.telemetry,
      );

  @override
  void initState() {
    super.initState();
    _syncAudio();
    widget.settings.addListener(_syncAudio);
    widget.settings.addListener(_handleSettingsChanged);
    _applyLaunchPolicy();
    _scheduleFirstUseSafetyDisclosure();
  }

  /// Shows the first-use safety disclosure after the first frame, until the
  /// acknowledgement is persisted.
  ///
  /// It is a modal that cannot be dismissed without the explicit action, and it
  /// is never a transient message. The Help tab holds the permanent copy, so
  /// this is the only first-use surface and there is no second one to compete
  /// with it.
  void _scheduleFirstUseSafetyDisclosure() {
    if (widget.settings.safetyAcknowledged) return;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || widget.settings.safetyAcknowledged) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        useSafeArea: true,
        builder: (dialogContext) => SafetyDisclosureDialog(
          onAcknowledge: () {
            Navigator.of(dialogContext).pop();
            widget.settings.setSafetyAcknowledged(true);
          },
        ),
      );
    });
  }

  /// Applies the finalized startup policy from the already-loaded preference.
  ///
  /// Auto-start ON: mark Detect visited/cached before the first shell build and
  /// issue one silent launch start intent while Home remains selected. The
  /// cached engine mounts behind visible Home and initializes in the
  /// background.
  ///
  /// Auto-start OFF: leave Detect unbuilt and the coordinator idle. Detection
  /// starts only on an intentional entry into the Detect tab.
  ///
  /// A persisted Auto-start change while the app is already running is out of
  /// scope for this task and receives no reactive behavior here.
  void _applyLaunchPolicy() {
    if (!widget.settings.autoStartDetection) return;
    _visited[1] = true;
    _coordinator.requestStart(StartIntentOrigin.launch);
  }

  @override
  void dispose() {
    widget.settings.removeListener(_syncAudio);
    widget.settings.removeListener(_handleSettingsChanged);
    _coordinator.disposeCoordinator();
    super.dispose();
  }

  void _syncAudio() {
    widget.tts.setAudioEnabled(widget.settings.audioEnabled);
  }

  /// Rebuilds the shell when the persisted hide-bar preference changes.
  void _handleSettingsChanged() {
    if (mounted) setState(() {});
  }

  /// Switches to a bottom-nav tab.
  ///
  /// This is the direct, feedback-free path: it is shared by the visible
  /// navigation bar and Back, neither of which should emit gesture-origin
  /// wayfinding feedback.
  void goToTab(int index) {
    if (index < 0 || index > 3) return;
    setState(() {
      _visited[index] = true;
      _index = index;
    });
    _requestEntryStartIfEnteringDetection(index);
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
    _requestEntryStartIfEnteringDetection(target);
  }

  /// Requests one entry start when the user intentionally enters Detect.
  ///
  /// Only the initial [DetectionRuntimeState.idle] state accepts an automatic
  /// entry start; paused, stopped, busy, ready, fallback, and failed states
  /// reject it so a retained-session manual pause/stop is never auto-restarted.
  /// This never writes the persisted Auto-start preference.
  void _requestEntryStartIfEnteringDetection(int index) {
    if (index != 1) return;
    _coordinator.requestEntryStartIfIdle();
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
        return HomeScreen(settings: widget.settings, coordinator: _coordinator);
      case 1:
        return EngineDetectionScreen(
          settings: widget.settings,
          tts: widget.tts,
          telemetry: widget.telemetry,
          corrections: widget.corrections,
          haptics: widget.haptics,
          coordinator: _coordinator,
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
                    // Detection (index 1) owns horizontal navigation over its
                    // whole main area via its raw GestureSurface; the shell
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
            // Presentation-only refresh: the light/Home-theme bar treatment is
            // supplied by buildHomeTheme()'s NavigationBarThemeData. Ownership
            // of the bar (destinations, order, callbacks, selection, visibility)
            // stays here and is unchanged.
            : Theme(
                data: buildHomeTheme(),
                child: NavigationBar(
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
      ),
    );
  }
}
