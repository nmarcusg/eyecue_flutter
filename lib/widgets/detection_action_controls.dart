import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../services/engine_coordinator.dart';
import '../theme/app_colors.dart';
import '../theme/app_radii.dart';
import '../theme/app_spacing.dart';

/// The exact total physical hold duration that completes a lifecycle action.
///
/// Progress begins at 0% on pointer down and advances continuously across this
/// full duration. [kLongPressTimeout] only classifies the continued press as a
/// hold attempt; it never starts, restarts, or resets this timeline.
const Duration kLifecycleHoldDuration = Duration(seconds: 3);

/// The secondary instruction shown before a hold attempt is classified.
const String kHoldInstruction = 'HOLD 3 SEC TO STOP';

/// The secondary instruction shown once a hold attempt is classified.
const String kKeepHoldingInstruction = 'KEEP HOLDING';

/// The secondary instruction for the stopped outcome.
const String kHoldToStartInstruction = 'HOLD 3 SEC';

/// The consolidated, coordinator-driven physical lifecycle control row.
///
/// This widget renders exactly two side-by-side physical controls: the left
/// lifecycle control (Pause/Resume/Start/Preparing/Unavailable) and the
/// tap-only Quick Scan control. It owns only local pointer timing and progress
/// presentation; every visible label, enabled state, and semantics value is
/// derived from the supplied [outcome], never from engine-local booleans.
///
/// The widget never owns a coordinator, camera controller, native controller,
/// TTS service, haptics service, or app setting. Completed TTS and haptic
/// feedback remain the sole responsibility of the invoked engine action
/// callbacks.
class DetectionActionControls extends StatefulWidget {
  const DetectionActionControls({
    super.key,
    required this.outcome,
    this.onPause,
    this.onResume,
    this.onStop,
    this.onStart,
    this.onQuickScan,
  });

  /// The coordinator-derived lifecycle outcome that selects labels, enabled
  /// state, and Quick Scan gating.
  final DetectionStatusOutcome outcome;

  /// Invoked on a completed tap while [outcome] is [DetectionStatusOutcome.ready].
  final VoidCallback? onPause;

  /// Invoked on a completed tap while [outcome] is [DetectionStatusOutcome.paused].
  final VoidCallback? onResume;

  /// Invoked on a completed three-second hold while [outcome] is
  /// [DetectionStatusOutcome.ready] or [DetectionStatusOutcome.paused].
  final VoidCallback? onStop;

  /// Invoked on a completed three-second hold while [outcome] is
  /// [DetectionStatusOutcome.stopped].
  final VoidCallback? onStart;

  /// Invoked on a completed tap of the physical Quick Scan control.
  final VoidCallback? onQuickScan;

  @override
  State<DetectionActionControls> createState() =>
      _DetectionActionControlsState();
}

class _DetectionActionControlsState extends State<DetectionActionControls> {
  /// Whether a physical pointer is currently held on the lifecycle control.
  bool _holding = false;

  /// Whether the continued press has passed [kLongPressTimeout] and is
  /// therefore classified as a hold attempt.
  bool _holdAttempt = false;

  /// Whether the completed hold has already dispatched its one action. While
  /// true the control is locked against duplicate dispatch until the outcome
  /// changes.
  bool _consumed = false;

  /// The current horizontal progress in the range 0.0–1.0.
  double _progress = 0;

  Timer? _progressTimer;
  Timer? _holdAttemptTimer;
  Timer? _completionTimer;

  @override
  void didUpdateWidget(covariant DetectionActionControls oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Any lifecycle outcome change invalidates a pending hold: cancel tracking
    // with no action, feedback, or retained progress, and release the lock.
    if (oldWidget.outcome != widget.outcome) {
      // A rebuild is already in progress; reset fields without setState.
      _cancelHold(notify: false);
      _consumed = false;
    }
  }

  @override
  void dispose() {
    _cancelHold(notify: false);
    super.dispose();
  }

  /// Whether the lifecycle control currently accepts a physical interaction.
  bool get _lifecycleEnabled =>
      widget.outcome == DetectionStatusOutcome.ready ||
      widget.outcome == DetectionStatusOutcome.paused ||
      widget.outcome == DetectionStatusOutcome.stopped;

  /// Whether the physical Quick Scan control is enabled.
  ///
  /// Enabled only for Ready (including healthy fallback) and never while a
  /// physical lifecycle hold is active.
  bool get _quickScanEnabled =>
      widget.outcome == DetectionStatusOutcome.ready && !_holding;

  /// The primary label for the current outcome.
  String get _primaryLabel => switch (widget.outcome) {
    DetectionStatusOutcome.ready => 'PAUSE',
    DetectionStatusOutcome.paused => 'RESUME',
    DetectionStatusOutcome.stopped => 'START',
    DetectionStatusOutcome.preparing => 'PREPARING',
    DetectionStatusOutcome.unavailable => 'UNAVAILABLE',
  };

  /// The secondary instruction for the current outcome and hold state.
  String? get _secondaryLabel {
    if (_holdAttempt) return kKeepHoldingInstruction;
    return switch (widget.outcome) {
      DetectionStatusOutcome.ready ||
      DetectionStatusOutcome.paused => kHoldInstruction,
      DetectionStatusOutcome.stopped => kHoldToStartInstruction,
      DetectionStatusOutcome.preparing ||
      DetectionStatusOutcome.unavailable => null,
    };
  }

  void _startHold() {
    if (!_lifecycleEnabled || _consumed) return;
    _progressTimer?.cancel();
    _holdAttemptTimer?.cancel();
    _completionTimer?.cancel();
    setState(() {
      _holding = true;
      _holdAttempt = false;
      _progress = 0;
    });
    // Advance progress continuously across the full three-second hold.
    _progressTimer = Timer.periodic(const Duration(milliseconds: 50), (_) {
      if (!mounted || !_holding) return;
      setState(() {
        _progress = (_progress + 0.05 / 3).clamp(0.0, 1.0);
      });
    });
    // Classify the continued press as a hold attempt at kLongPressTimeout
    // without restarting or resetting progress.
    _holdAttemptTimer = Timer(kLongPressTimeout, () {
      if (!mounted || !_holding) return;
      setState(() => _holdAttempt = true);
    });
    // Dispatch exactly once at three seconds total.
    _completionTimer = Timer(kLifecycleHoldDuration, _completeHold);
  }

  void _completeHold() {
    if (!mounted || !_holding || _consumed) return;
    _progressTimer?.cancel();
    _holdAttemptTimer?.cancel();
    _completionTimer?.cancel();
    setState(() {
      _progress = 1;
      _consumed = true;
      _holding = false;
      _holdAttempt = false;
    });
    switch (widget.outcome) {
      case DetectionStatusOutcome.ready:
      case DetectionStatusOutcome.paused:
        widget.onStop?.call();
      case DetectionStatusOutcome.stopped:
        widget.onStart?.call();
      case DetectionStatusOutcome.preparing:
      case DetectionStatusOutcome.unavailable:
        break;
    }
  }

  void _endHold() {
    if (!_holding) return;
    final wasHoldAttempt = _holdAttempt;
    _progressTimer?.cancel();
    _holdAttemptTimer?.cancel();
    _completionTimer?.cancel();
    setState(() {
      _holding = false;
      _holdAttempt = false;
      _progress = 0;
    });
    if (wasHoldAttempt) {
      // Abandoned hold: no lifecycle action and no tap fallback.
      return;
    }
    // Normal tap: apply the mapped tap behavior.
    _dispatchTap();
  }

  /// Applies the mapped tap behavior for the current outcome.
  ///
  /// Shared by the physical pointer-up path and the TalkBack semantic `onTap`
  /// path so a screen-reader double-tap reaches the same Pause/Resume behavior
  /// as a physical tap. Stopped remains an intentional no-operation.
  void _dispatchTap() {
    switch (widget.outcome) {
      case DetectionStatusOutcome.ready:
        widget.onPause?.call();
      case DetectionStatusOutcome.paused:
        widget.onResume?.call();
      case DetectionStatusOutcome.stopped:
        // Stopped tap is intentionally a no-operation.
        break;
      case DetectionStatusOutcome.preparing:
      case DetectionStatusOutcome.unavailable:
        break;
    }
  }

  void _cancelHold({bool notify = true}) {
    _progressTimer?.cancel();
    _holdAttemptTimer?.cancel();
    _completionTimer?.cancel();
    _progressTimer = null;
    _holdAttemptTimer = null;
    _completionTimer = null;
    final changed = _holding || _holdAttempt || _progress != 0;
    _holding = false;
    _holdAttempt = false;
    _progress = 0;
    if (changed && notify && mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: _buildLifecycleControl(context)),
        const SizedBox(width: kSpace12),
        Expanded(child: _buildQuickScanControl(context)),
      ],
    );
  }

  Widget _buildLifecycleControl(BuildContext context) {
    final theme = Theme.of(context);
    final enabled = _lifecycleEnabled && !_consumed;
    final secondary = _secondaryLabel;
    final hint = _lifecycleHint();

    return Semantics(
      button: true,
      enabled: enabled,
      label: _primaryLabel,
      value: secondary ?? _primaryLabel,
      hint: hint,
      // A TalkBack double-tap invokes this directly (no pointer-down), so it
      // must dispatch the mapped tap behavior rather than the pointer-up path.
      onTap: enabled ? _dispatchTap : null,
      child: ExcludeSemantics(
        child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: enabled ? (_) => _startHold() : null,
          onPointerUp: enabled ? (_) => _endHold() : null,
          onPointerCancel: enabled ? (_) => _cancelHold() : null,
          child: Container(
            constraints: const BoxConstraints(
              minWidth: kMinTouchWidth,
              minHeight: kMinTouchHeight,
            ),
            decoration: BoxDecoration(
              color: enabled
                  ? theme.colorScheme.surfaceContainerHighest
                  : theme.colorScheme.surfaceContainerHighest.withValues(
                      alpha: 0.5,
                    ),
              borderRadius: BorderRadius.circular(kRadius14),
            ),
            child: Stack(
              children: [
                if (_holding)
                  Positioned.fill(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: FractionallySizedBox(
                        widthFactor: _progress,
                        child: Container(
                          decoration: BoxDecoration(
                            color: kHomeAccentCyan.withValues(alpha: 0.35),
                            borderRadius: BorderRadius.circular(kRadius14),
                          ),
                        ),
                      ),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: kSpace12,
                    vertical: kSpace10,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(
                        _primaryLabel,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: enabled
                              ? kHomeInk
                              : kHomeInk.withValues(alpha: 0.5),
                        ),
                      ),
                      if (secondary != null) ...[
                        const SizedBox(height: kSpace2),
                        Text(
                          secondary,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: kHomeInkMuted,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _lifecycleHint() {
    if (!_lifecycleEnabled) {
      return widget.outcome == DetectionStatusOutcome.preparing
          ? 'Detection is preparing'
          : 'Detection is unavailable';
    }
    return switch (widget.outcome) {
      DetectionStatusOutcome.ready =>
        'Double tap to pause. Hold for three seconds to stop.',
      DetectionStatusOutcome.paused =>
        'Double tap to resume. Hold for three seconds to stop.',
      DetectionStatusOutcome.stopped =>
        'Hold for three seconds to start detection.',
      DetectionStatusOutcome.preparing ||
      DetectionStatusOutcome.unavailable => 'Unavailable',
    };
  }

  Widget _buildQuickScanControl(BuildContext context) {
    final theme = Theme.of(context);
    final enabled = _quickScanEnabled;

    return Semantics(
      button: true,
      enabled: enabled,
      label: 'QUICK SCAN',
      hint: enabled
          ? 'Double tap to scan the scene'
          : 'Quick Scan is available only while detection is ready',
      onTap: enabled ? widget.onQuickScan : null,
      child: ExcludeSemantics(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: enabled ? widget.onQuickScan : null,
          child: Container(
            constraints: const BoxConstraints(
              minWidth: kMinTouchWidth,
              minHeight: kMinTouchHeight,
            ),
            decoration: BoxDecoration(
              color: enabled
                  ? theme.colorScheme.surfaceContainerHighest
                  : theme.colorScheme.surfaceContainerHighest.withValues(
                      alpha: 0.5,
                    ),
              borderRadius: BorderRadius.circular(kRadius14),
            ),
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(
              horizontal: kSpace12,
              vertical: kSpace10,
            ),
            child: Text(
              'QUICK SCAN',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: enabled ? kHomeInk : kHomeInk.withValues(alpha: 0.5),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
