import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Draws the colourised depth map over the camera preview.
///
/// The image is in SENSOR orientation and is rotated for display; the preview
/// uses a centre-crop (`BoxFit.cover`) fill, so the heatmap uses the same fit.
/// Decorative only: pointer-inert and excluded from semantics.
class DepthHeatmapView extends StatelessWidget {
  final ui.Image? image;

  /// Clockwise degrees that map the sensor image onto the upright display.
  final int rotationDegrees;

  const DepthHeatmapView({
    super.key,
    required this.image,
    required this.rotationDegrees,
  });

  @override
  Widget build(BuildContext context) {
    final current = image;
    if (current == null) return const SizedBox.shrink();
    final rotation = ((rotationDegrees % 360) + 360) % 360;
    final swapped = rotation == 90 || rotation == 270;
    final uprightWidth = (swapped ? current.height : current.width).toDouble();
    final uprightHeight = (swapped ? current.width : current.height).toDouble();

    return IgnorePointer(
      child: ExcludeSemantics(
        child: ClipRect(
          child: FittedBox(
            fit: BoxFit.cover,
            clipBehavior: Clip.hardEdge,
            child: SizedBox(
              width: uprightWidth,
              height: uprightHeight,
              child: Transform.rotate(
                angle: rotation * math.pi / 180,
                child: SizedBox(
                  width: current.width.toDouble(),
                  height: current.height.toDouble(),
                  child: RawImage(image: current, fit: BoxFit.fill),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
