import 'package:flutter/services.dart' show DeviceOrientation;
import 'dart:ui' show Rect;

/// ---------------------------------------------------------------------------
/// BoxTransform — the single, device-independent source of truth for all
/// orientation math in the inference pipeline.
///
/// Nothing is hardcoded. Every angle is derived at runtime from:
///   * CameraDescription.sensorOrientation  (0 / 90 / 180 / 270)
///   * the current device orientation       (0 / 90 / 180 / 270 clockwise
///                                           from natural portrait)
///   * the lens direction                   (front → mirrored display)
///
/// Coordinate spaces used across the pipeline:
///   * SENSOR space — the raw YUV_420_888 frame as delivered by the camera
///     (`_convertYUV420toRGB` consumes this; dimensions W×H, landscape).
///   * UPRIGHT space — the same scene rotated so "up" matches the physical
///     world as displayed by the (plugin-rotated) preview.
///
/// The canonical INFERENCE space is UPRIGHT: the inference isolate rotates
/// the 640×640 NHWC input tensor by [displayRotationDegrees] (and mirrors it
/// for front cameras) BEFORE interpreter.run(). The model, parser, and NMS
/// code is otherwise unchanged, and parser/NMS therefore emit boxes that are
/// already in upright space. The painter consumes those boxes directly with
/// [uprightDims] as its imageSize.
///
/// [rotateRect] / [invertRect] are the pure, mathematically reversible
/// normalized-box transforms (clockwise rotation and its inverse). They are
/// the reference implementation for the box math and are available for unit
/// testing and any future sensor-space consumer; applying [rotateRect] with
/// the inverse angle (or [invertRect]) exactly restores the input.
/// ---------------------------------------------------------------------------
class BoxTransform {
  BoxTransform._();

  /// Rotation (degrees clockwise) that maps a SENSOR frame onto the upright
  /// display, using the standard Camera2/CameraX orientation formula
  /// (identical to the camera plugin's own preview-correction math):
  ///
  ///   back  : (sensorOrientation − deviceDegrees + 360) % 360
  ///   front : (sensorOrientation + deviceDegrees + 360) % 360
  ///
  /// [deviceDegrees] is the device's clockwise rotation from natural
  /// portrait: 0 / 90 / 180 / 270 (portraitUp / landscapeRight /
  /// portraitDown / landscapeLeft). [isFront] selects the front-camera
  /// convention (mirror handled separately by the caller via [mirrorRect] or
  /// the tensor mirror).
  static int displayRotationDegrees({
    required int sensorOrientation,
    required int deviceDegrees,
    required bool isFront,
  }) {
    final s = _norm(sensorOrientation);
    final d = _norm(deviceDegrees);
    return isFront ? (s + d) % 360 : (s - d + 360) % 360;
  }

  /// Maps a Flutter [DeviceOrientation] to clockwise degrees from natural
  /// portrait (0/90/180/270) using the SAME convention the camera plugin
  /// uses for its own preview rotation (verified against
  /// camera_android_camerax `_getRotationConstantFromDeviceOrientation`,
  /// which uses counter-clockwise labels):
  ///   portraitUp → 0, landscapeLeft → 90, portraitDown → 180,
  ///   landscapeRight → 270.
  static int deviceDegreesFor(DeviceOrientation orientation) {
    return switch (orientation) {
      DeviceOrientation.portraitUp => 0,
      DeviceOrientation.landscapeLeft => 90,
      DeviceOrientation.portraitDown => 180,
      DeviceOrientation.landscapeRight => 270,
    };
  }

  /// Dimensions of the upright (display) image for a sensor image of
  /// [w]×[h] rotated by [rotationDegrees].
  static ({int w, int h}) uprightDims({
    required int w,
    required int h,
    required int rotationDegrees,
  }) {
    final r = _norm(rotationDegrees);
    return (r == 90 || r == 270) ? (w: h, h: w) : (w: w, h: h);
  }

  /// Rotates a normalized [0,1] box [degrees] degrees CLOCKWISE.
  ///
  ///   90° : (x, y, w, h) → (1−y−h, x,     h, w)
  ///   180°: (x, y, w, h) → (1−x−w, 1−y−h, w, h)
  ///   270°: (x, y, w, h) → (y,     1−x−w, h, w)
  static Rect rotateRect(Rect box, int degrees) {
    switch (_norm(degrees)) {
      case 90:
        return Rect.fromLTWH(
          1 - box.top - box.height,
          box.left,
          box.height,
          box.width,
        );
      case 180:
        return Rect.fromLTWH(
          1 - box.left - box.width,
          1 - box.top - box.height,
          box.width,
          box.height,
        );
      case 270:
        return Rect.fromLTWH(
          box.top,
          1 - box.left - box.width,
          box.height,
          box.width,
        );
      default:
        return box;
    }
  }

  /// Mathematical inverse of [rotateRect] (rotates counter-clockwise).
  static Rect invertRect(Rect box, int degrees) {
    switch (_norm(degrees)) {
      case 90:
        return Rect.fromLTWH(
          box.top,
          1 - box.left - box.width,
          box.height,
          box.width,
        );
      case 180:
        return Rect.fromLTWH(
          1 - box.left - box.width,
          1 - box.top - box.height,
          box.width,
          box.height,
        );
      case 270:
        return Rect.fromLTWH(
          1 - box.top - box.height,
          box.left,
          box.height,
          box.width,
        );
      default:
        return box;
    }
  }

  /// Mirrors a normalized box horizontally (X-flip in upright space) —
  /// the front-camera mirror display.
  static Rect mirrorRect(Rect box) =>
      Rect.fromLTWH(1 - box.left - box.width, box.top, box.width, box.height);

  static int _norm(int d) => ((d % 360) + 360) % 360;
}
