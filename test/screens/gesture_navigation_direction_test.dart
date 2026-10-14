import 'package:eyecue_flutter/screens/detection_screen.dart' as custom_engine;
import 'package:eyecue_flutter/screens/ultralytics_detection_screen.dart'
    as ultralytics_engine;
import 'package:eyecue_flutter/services/gesture_controller.dart';
import 'package:flutter_test/flutter_test.dart';

/// Locks in Product Decision 2 for both Detection engines:
/// a left swipe advances to the next tab (`+1`) and a right swipe returns to
/// the previous tab (`-1`).
///
/// Both engines expose the same pure `relativeDirectionForGesture` mapping, so
/// this test proves direction parity without a camera/native dependency.
void main() {
  group('Custom engine gesture → direction', () {
    test('a left swipe advances to the next tab', () {
      expect(
        custom_engine.relativeDirectionForGesture(EyeCueGesture.swipeLeft),
        1,
      );
    });

    test('a right swipe returns to the previous tab', () {
      expect(
        custom_engine.relativeDirectionForGesture(EyeCueGesture.swipeRight),
        -1,
      );
    });

    test('non-horizontal gestures map to no navigation', () {
      for (final gesture in [
        EyeCueGesture.singleTap,
        EyeCueGesture.twoFingerDoubleTap,
        EyeCueGesture.threeFingerTap,
        EyeCueGesture.swipeDown,
      ]) {
        expect(custom_engine.relativeDirectionForGesture(gesture), isNull);
      }
    });
  });

  group('Ultralytics engine gesture → direction', () {
    test('a left swipe advances to the next tab', () {
      expect(
        ultralytics_engine.relativeDirectionForGesture(EyeCueGesture.swipeLeft),
        1,
      );
    });

    test('a right swipe returns to the previous tab', () {
      expect(
        ultralytics_engine.relativeDirectionForGesture(
          EyeCueGesture.swipeRight,
        ),
        -1,
      );
    });

    test('non-horizontal gestures map to no navigation', () {
      for (final gesture in [
        EyeCueGesture.singleTap,
        EyeCueGesture.twoFingerDoubleTap,
        EyeCueGesture.threeFingerTap,
        EyeCueGesture.swipeDown,
      ]) {
        expect(ultralytics_engine.relativeDirectionForGesture(gesture), isNull);
      }
    });
  });

  test('both engines agree on horizontal direction', () {
    for (final gesture in [EyeCueGesture.swipeLeft, EyeCueGesture.swipeRight]) {
      expect(
        custom_engine.relativeDirectionForGesture(gesture),
        ultralytics_engine.relativeDirectionForGesture(gesture),
      );
    }
  });
}
