import 'dart:async';

import 'package:eyecue_flutter/services/gesture_controller.dart';
import 'package:flutter_test/flutter_test.dart';

/// A controllable [Timer] so the single-tap debounce can be driven manually.
class FakeTimer implements Timer {
  FakeTimer(this.callback);

  final void Function() callback;
  bool _cancelled = false;

  @override
  void cancel() => _cancelled = true;

  @override
  bool get isActive => !_cancelled;

  @override
  int get tick => 0;

  void fire() {
    if (!_cancelled) callback();
  }
}

void main() {
  late DateTime now;
  late List<FakeTimer> timers;
  late List<EyeCueGesture> fired;
  late GestureController controller;

  setUp(() {
    now = DateTime(2026, 1, 1, 12, 0, 0);
    timers = [];
    fired = [];
    controller = GestureController(
      onGesture: fired.add,
      clock: () => now,
      createTimer: (duration, cb) {
        final t = FakeTimer(cb);
        timers.add(t);
        return t;
      },
    );
  });

  void firePendingTimers() {
    for (final t in timers.toList()) {
      t.fire();
    }
    timers.clear();
  }

  void singleTap(int pointer, Offset at) {
    controller.onPointerDown(pointer, at);
    controller.onPointerUp(pointer, at);
  }

  void multiTap(List<int> pointers, Offset at) {
    for (final p in pointers) {
      controller.onPointerDown(p, at);
    }
    for (final p in pointers) {
      controller.onPointerUp(p, at);
    }
  }

  test('single tap fires after the confirm delay', () {
    singleTap(1, const Offset(100, 100));
    expect(fired, isEmpty); // debounce pending
    now = now.add(const Duration(milliseconds: 300));
    firePendingTimers();
    expect(fired, [EyeCueGesture.singleTap]);
  });

  test('a quick one-finger double tap collapses to a single tap', () {
    singleTap(1, const Offset(100, 100));
    now = now.add(const Duration(milliseconds: 100));
    singleTap(2, const Offset(110, 100)); // new group cancels the pending timer
    now = now.add(const Duration(milliseconds: 300));
    firePendingTimers();
    expect(fired, [EyeCueGesture.singleTap]);
  });

  test('two-finger double tap fires only after two two-finger taps', () {
    multiTap([1, 2], const Offset(100, 100));
    expect(fired, isEmpty); // waiting for a possible second tap

    now = now.add(const Duration(milliseconds: 150));
    multiTap([3, 4], const Offset(120, 100));
    expect(fired, [EyeCueGesture.twoFingerDoubleTap]);
  });

  test('two separate two-finger taps outside the window do not combine', () {
    multiTap([1, 2], const Offset(100, 100));
    now = now.add(const Duration(seconds: 2));
    multiTap([3, 4], const Offset(120, 100));
    expect(fired, isEmpty);
  });

  test('three-finger tap fires immediately', () {
    multiTap([1, 2, 3], const Offset(100, 100));
    expect(fired, [EyeCueGesture.threeFingerTap]);
  });

  test('one-finger swipe down fires and suppresses the tap', () {
    controller.onPointerDown(1, const Offset(100, 100));
    controller.onPointerMove(1, const Offset(100, 200)); // dy = 100 > 80
    expect(fired, [EyeCueGesture.swipeDown]);

    controller.onPointerUp(1, const Offset(100, 200));
    now = now.add(const Duration(milliseconds: 300));
    firePendingTimers();
    expect(fired, [EyeCueGesture.swipeDown]); // no extra single tap
  });

  test('a short downward move does not trigger a swipe', () {
    controller.onPointerDown(1, const Offset(100, 100));
    controller.onPointerMove(1, const Offset(100, 140)); // dy = 40
    expect(fired, isEmpty);
    controller.onPointerUp(1, const Offset(100, 140));
    now = now.add(const Duration(milliseconds: 300));
    firePendingTimers();
    expect(fired, [EyeCueGesture.singleTap]);
  });

  test('reset clears all state', () {
    controller.onPointerDown(1, const Offset(100, 100));
    controller.reset();
    controller.onPointerUp(1, const Offset(100, 100)); // no group end → nothing
    now = now.add(const Duration(milliseconds: 300));
    firePendingTimers();
    expect(fired, isEmpty);
  });
}
