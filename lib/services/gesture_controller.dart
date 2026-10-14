import 'dart:async';
import 'dart:ui' show Offset;

/// Gestures recognized by EyeCue (thesis-defined vocabulary — nothing extra).
enum EyeCueGesture {
  /// Single finger tap → pause / resume detection.
  singleTap,

  /// Two-finger double tap → start / stop detection.
  twoFingerDoubleTap,

  /// Three-finger tap → quick environmental scan.
  threeFingerTap,

  /// One-finger swipe down → repeat the last audio alert.
  swipeDown,

  /// One-finger horizontal swipe → request one relative primary-tab move.
  swipeLeft,

  /// One-finger horizontal swipe → request one relative primary-tab move.
  swipeRight,
}

/// Detects the thesis gesture vocabulary from raw pointer events.
///
/// Pure Dart state machine so it can be unit-tested without the widget tree.
/// [GestureSurface] forwards `Listener` events into it. Time sources and
/// timers are injectable so tests can drive them deterministically.
class GestureController {
  GestureController({
    this.onGesture,
    DateTime Function()? clock,
    Timer Function(Duration, void Function())? createTimer,
    this.singleTapConfirmDelay = const Duration(milliseconds: 300),
    this.doubleTapWindow = const Duration(milliseconds: 350),
    this.swipeDownThreshold = 80.0,
    this.swipeHorizontalThreshold = 80.0,
    this.directionalDominanceRatio = 1.5,
  }) : _clock = clock ?? DateTime.now,
       _createTimer = createTimer ?? _defaultTimer;

  static Timer _defaultTimer(Duration d, void Function() cb) => Timer(d, cb);

  void Function(EyeCueGesture)? onGesture;

  /// Delay before a single tap is confirmed (so a quick double tap collapses
  /// into a single tap — one-finger double tap is not a thesis gesture).
  final Duration singleTapConfirmDelay;

  /// Window within which two two-finger taps combine into a double tap.
  final Duration doubleTapWindow;

  /// Downward distance (px) that classifies a one-finger drag as a swipe-down.
  final double swipeDownThreshold;

  /// Horizontal distance (px) that classifies a one-finger drag as a
  /// horizontal navigation swipe. Provisional/tunable.
  final double swipeHorizontalThreshold;

  /// How much the dominant axis must exceed the other axis for a directional
  /// intent to be committed. Provisional/tunable.
  final double directionalDominanceRatio;

  final DateTime Function() _clock;
  final Timer Function(Duration, void Function()) _createTimer;

  final Set<int> _activePointers = {};
  final Map<int, Offset> _downPositions = {};
  int _groupMaxPointers = 0;
  bool _swipeFired = false;
  bool _suppressTapAfterSwipe = false;
  DateTime? _lastTwoFingerTapAt;
  Timer? _singleTapTimer;

  /// True once a one-pointer directional intent (down or horizontal) has been
  /// committed for the current sequence. Locks the sequence so a later
  /// perpendicular move cannot emit a second, conflicting intent.
  bool _directionCommitted = false;

  /// True when a second pointer joined a sequence that had begun as a
  /// one-pointer sequence. Invalidates one-pointer directional classification
  /// for the rest of that sequence.
  bool _multiPointerInvalidated = false;

  bool get isTouching => _activePointers.isNotEmpty;

  /// Handles a pointer-down event.
  void onPointerDown(int pointer, Offset position) {
    _downPositions[pointer] = position;
    final wasEmpty = _activePointers.isEmpty;
    _activePointers.add(pointer);
    // Any new gesture cancels a pending single-tap confirmation.
    _cancelPendingSingleTap();
    if (wasEmpty) {
      _groupMaxPointers = 1;
      _swipeFired = false;
      _suppressTapAfterSwipe = false;
      _directionCommitted = false;
      _multiPointerInvalidated = false;
    } else {
      _groupMaxPointers = _activePointers.length > _groupMaxPointers
          ? _activePointers.length
          : _groupMaxPointers;
      // A second pointer invalidates one-pointer directional classification
      // for the rest of this sequence, even if it later lifts.
      _multiPointerInvalidated = true;
    }
  }

  /// Handles a pointer-move event (one-finger swipe-down or horizontal move).
  ///
  /// The first committed directional intent locks the sequence: a horizontal
  /// commit prevents a later downward repeat, and a downward commit prevents a
  /// later horizontal navigation. Ambiguous diagonals emit nothing.
  void onPointerMove(int pointer, Offset position) {
    if (!_activePointers.contains(pointer)) return;
    if (_activePointers.length != 1 || _swipeFired) return;
    if (_multiPointerInvalidated || _directionCommitted) return;
    final start = _downPositions[pointer];
    if (start == null) return;
    final dx = position.dx - start.dx;
    final dy = position.dy - start.dy;
    final absDx = dx.abs();
    final absDy = dy.abs();

    // Downward-dominant: preserve the existing repeat action.
    if (dy > swipeDownThreshold && absDy >= absDx * directionalDominanceRatio) {
      _swipeFired = true;
      _suppressTapAfterSwipe = true;
      _directionCommitted = true;
      _fire(EyeCueGesture.swipeDown);
      return;
    }

    // Horizontal-dominant: request one relative primary-tab move.
    if (absDx > swipeHorizontalThreshold &&
        absDx >= absDy * directionalDominanceRatio) {
      _swipeFired = true;
      _suppressTapAfterSwipe = true;
      _directionCommitted = true;
      _fire(dx < 0 ? EyeCueGesture.swipeLeft : EyeCueGesture.swipeRight);
    }
  }

  /// Handles a pointer-up event; classifies the gesture once the group ends.
  void onPointerUp(int pointer, Offset position) {
    if (!_activePointers.contains(pointer)) return;
    _activePointers.remove(pointer);
    _downPositions.remove(pointer);
    if (_activePointers.isEmpty) {
      _handleGroupEnd();
    }
  }

  /// Handles pointer-cancel (e.g. palm rejection / interruption).
  void onPointerCancel(int pointer) {
    if (!_activePointers.contains(pointer)) return;
    _activePointers.remove(pointer);
    _downPositions.remove(pointer);
    if (_activePointers.isEmpty) {
      _cancelPendingSingleTap();
    }
  }

  void _handleGroupEnd() {
    _cancelPendingSingleTap();
    if (_swipeFired) {
      _swipeFired = false;
      _suppressTapAfterSwipe = false;
      _directionCommitted = false;
      _multiPointerInvalidated = false;
      return;
    }
    if (_groupMaxPointers >= 3) {
      _fire(EyeCueGesture.threeFingerTap);
      return;
    }
    if (_groupMaxPointers == 2) {
      final now = _clock();
      final last = _lastTwoFingerTapAt;
      if (last != null && now.difference(last) < doubleTapWindow) {
        _lastTwoFingerTapAt = null;
        _fire(EyeCueGesture.twoFingerDoubleTap);
      } else {
        // Wait for a possible second two-finger tap.
        _lastTwoFingerTapAt = now;
      }
      return;
    }
    // Single pointer.
    if (_suppressTapAfterSwipe) {
      _suppressTapAfterSwipe = false;
      return;
    }
    _singleTapTimer = _createTimer(singleTapConfirmDelay, () {
      _singleTapTimer = null;
      _fire(EyeCueGesture.singleTap);
    });
  }

  void _cancelPendingSingleTap() {
    _singleTapTimer?.cancel();
    _singleTapTimer = null;
  }

  void _fire(EyeCueGesture gesture) => onGesture?.call(gesture);

  /// Resets all internal state (also used by tests).
  void reset() {
    _cancelPendingSingleTap();
    _activePointers.clear();
    _downPositions.clear();
    _groupMaxPointers = 0;
    _swipeFired = false;
    _suppressTapAfterSwipe = false;
    _lastTwoFingerTapAt = null;
    _directionCommitted = false;
    _multiPointerInvalidated = false;
  }
}
