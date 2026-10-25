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

  test('one-finger swipe down commits on release and suppresses the tap', () {
    controller.onPointerDown(1, const Offset(100, 100));
    controller.onPointerMove(1, const Offset(100, 200)); // dy = 100 > 80
    expect(fired, isEmpty); // no mid-gesture commit

    controller.onPointerUp(1, const Offset(100, 200));
    expect(fired, [EyeCueGesture.swipeDown]);
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

  group('horizontal navigation intents', () {
    test('a leftward swipe fires swipeLeft once, on release', () {
      controller.onPointerDown(1, const Offset(300, 100));
      controller.onPointerMove(1, const Offset(100, 100)); // dx = -200
      expect(fired, isEmpty); // nothing before the finger lifts
      controller.onPointerUp(1, const Offset(100, 100));
      expect(fired, [EyeCueGesture.swipeLeft]); // exactly one action
    });

    test('a rightward swipe fires swipeRight once, on release', () {
      controller.onPointerDown(1, const Offset(100, 100));
      controller.onPointerMove(1, const Offset(300, 100)); // dx = +200
      expect(fired, isEmpty);
      controller.onPointerUp(1, const Offset(300, 100));
      expect(fired, [EyeCueGesture.swipeRight]);
    });

    test('a short horizontal move does not navigate', () {
      controller.onPointerDown(1, const Offset(100, 100));
      controller.onPointerMove(1, const Offset(140, 100)); // dx = 40
      expect(fired, isEmpty);
      controller.onPointerUp(1, const Offset(140, 100));
      now = now.add(const Duration(milliseconds: 300));
      firePendingTimers();
      expect(fired, [EyeCueGesture.singleTap]);
    });

    test('an ambiguous diagonal emits no directional intent', () {
      controller.onPointerDown(1, const Offset(100, 100));
      controller.onPointerMove(1, const Offset(200, 190)); // dx=100, dy=90
      expect(fired, isEmpty);
      // The release must not turn the ambiguous diagonal into a directional
      // intent: it falls back to the tap it always was.
      controller.onPointerUp(1, const Offset(200, 190));
      expect(fired, isEmpty);
      now = now.add(const Duration(milliseconds: 300));
      firePendingTimers();
      expect(fired, [EyeCueGesture.singleTap]);
    });

    test('a horizontal commit prevents a later downward repeat', () {
      controller.onPointerDown(1, const Offset(300, 100));
      controller.onPointerMove(1, const Offset(100, 100)); // horizontal commit
      controller.onPointerMove(1, const Offset(100, 400)); // later downward
      controller.onPointerUp(1, const Offset(100, 400));
      expect(fired, [EyeCueGesture.swipeLeft]);
    });

    test('a downward commit prevents a later horizontal navigation', () {
      controller.onPointerDown(1, const Offset(100, 100));
      controller.onPointerMove(1, const Offset(100, 300)); // downward commit
      controller.onPointerMove(1, const Offset(400, 300)); // later horizontal
      controller.onPointerUp(1, const Offset(400, 300));
      expect(fired, [EyeCueGesture.swipeDown]);
    });

    test('a second pointer invalidates one-pointer direction', () {
      controller.onPointerDown(1, const Offset(300, 100));
      controller.onPointerDown(2, const Offset(320, 120)); // second pointer
      controller.onPointerMove(1, const Offset(100, 100)); // would be left
      expect(fired, isEmpty);
      controller.onPointerUp(1, const Offset(100, 100));
      controller.onPointerUp(2, const Offset(320, 120));
      // The released sequence fires nothing at all.
      expect(fired, isEmpty);
    });

    test('pointer cancellation suppresses directional action', () {
      controller.onPointerDown(1, const Offset(300, 100));
      controller.onPointerCancel(1);
      controller.onPointerMove(1, const Offset(100, 100));
      expect(fired, isEmpty);
    });

    test('two-finger double tap with horizontal jitter does not navigate', () {
      controller.onPointerDown(1, const Offset(100, 100));
      controller.onPointerDown(2, const Offset(140, 100));
      controller.onPointerMove(1, const Offset(60, 100)); // jitter
      controller.onPointerUp(1, const Offset(60, 100));
      controller.onPointerUp(2, const Offset(140, 100));
      now = now.add(const Duration(milliseconds: 150));
      controller.onPointerDown(3, const Offset(100, 100));
      controller.onPointerDown(4, const Offset(140, 100));
      controller.onPointerUp(3, const Offset(100, 100));
      controller.onPointerUp(4, const Offset(140, 100));
      expect(fired, [EyeCueGesture.twoFingerDoubleTap]);
    });

    test('three-finger tap with horizontal jitter does not navigate', () {
      controller.onPointerDown(1, const Offset(100, 100));
      controller.onPointerDown(2, const Offset(140, 100));
      controller.onPointerDown(3, const Offset(180, 100));
      controller.onPointerMove(1, const Offset(40, 100)); // jitter
      controller.onPointerUp(1, const Offset(40, 100));
      controller.onPointerUp(2, const Offset(140, 100));
      controller.onPointerUp(3, const Offset(180, 100));
      expect(fired, [EyeCueGesture.threeFingerTap]);
    });
  });

  group('pointer contract (one pointer, commit on release)', () {
    test('a long swipe commits one intent, only on release', () {
      controller.onPointerDown(1, const Offset(360, 200));
      for (var x = 340.0; x >= 40; x -= 20) {
        controller.onPointerMove(1, Offset(x, 200));
        expect(fired, isEmpty); // never mid-gesture
      }
      controller.onPointerUp(1, const Offset(40, 200));
      expect(fired, [EyeCueGesture.swipeLeft]);
    });

    test('a fast swipe commits one intent, only on release', () {
      controller.onPointerDown(1, const Offset(360, 200));
      controller.onPointerMove(1, const Offset(40, 200)); // one large jump
      expect(fired, isEmpty);
      controller.onPointerUp(1, const Offset(40, 200));
      expect(fired, [EyeCueGesture.swipeLeft]);
    });

    test('a second pointer invalidates the whole sequence', () {
      controller.onPointerDown(1, const Offset(360, 200));
      controller.onPointerDown(2, const Offset(380, 220));
      controller.onPointerMove(1, const Offset(40, 200));
      controller.onPointerUp(2, const Offset(380, 220));
      controller.onPointerUp(1, const Offset(40, 200));
      expect(fired, isEmpty);
    });

    test('a second pointer discards a classification already made', () {
      // down → move past the threshold → second pointer down → both up. The
      // intent classified before the second pointer joined is discarded with
      // the invalidation, so the ordering of the pointers cannot commit it.
      controller.onPointerDown(1, const Offset(360, 200));
      controller.onPointerMove(1, const Offset(40, 200)); // classified left
      controller.onPointerDown(2, const Offset(380, 220));
      controller.onPointerUp(1, const Offset(40, 200));
      controller.onPointerUp(2, const Offset(380, 220));
      expect(fired, isEmpty);
    });

    test('a second pointer that leaves cannot re-arm the sequence', () {
      controller.onPointerDown(1, const Offset(360, 200));
      controller.onPointerDown(2, const Offset(380, 220));
      controller.onPointerUp(
        2,
        const Offset(380, 220),
      ); // second pointer leaves
      controller.onPointerMove(1, const Offset(40, 200)); // first still down
      controller.onPointerUp(1, const Offset(40, 200));
      expect(fired, isEmpty);
    });

    test('a cancelled directional move never navigates', () {
      controller.onPointerDown(1, const Offset(360, 200));
      controller.onPointerMove(1, const Offset(40, 200));
      controller.onPointerCancel(1);
      expect(fired, isEmpty);
    });

    test('a clean sequence after an invalidated one still navigates', () {
      controller.onPointerDown(1, const Offset(360, 200));
      controller.onPointerDown(2, const Offset(380, 220));
      controller.onPointerUp(1, const Offset(360, 200));
      controller.onPointerUp(2, const Offset(380, 220));
      expect(fired, isEmpty);

      controller.onPointerDown(3, const Offset(360, 200));
      controller.onPointerMove(3, const Offset(40, 200));
      expect(fired, isEmpty);
      controller.onPointerUp(3, const Offset(40, 200));
      expect(fired, [EyeCueGesture.swipeLeft]);
    });
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
