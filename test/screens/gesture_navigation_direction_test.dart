import 'package:eyecue_flutter/screens/ultralytics_detection_screen.dart'
    as detection_engine;
import 'package:eyecue_flutter/services/gesture_controller.dart';
import 'package:flutter_test/flutter_test.dart';

/// Locks in Product Decision 2 for the Detection engine:
/// a left swipe advances to the next tab (`+1`) and a right swipe returns to
/// the previous tab (`-1`).
///
/// The pure `relativeDirectionForGesture` mapping is tested without a
/// camera/native dependency.
void main() {
  group('Detection gesture → direction', () {
    test('a left swipe advances to the next tab', () {
      expect(
        detection_engine.relativeDirectionForGesture(EyeCueGesture.swipeLeft),
        1,
      );
    });

    test('a right swipe returns to the previous tab', () {
      expect(
        detection_engine.relativeDirectionForGesture(EyeCueGesture.swipeRight),
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
        expect(detection_engine.relativeDirectionForGesture(gesture), isNull);
      }
    });
  });
}
