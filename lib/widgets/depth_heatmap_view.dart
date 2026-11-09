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

    return IgnorePointer(
      child: ExcludeSemantics(
        child: ClipRect(
          child: FittedBox(
            // `BoxFit.cover` scaled and centred is the same mapping
            // `BoundingBoxPainter` applies with
            // `applyBoxFit(BoxFit.cover, uprightDims, previewSize)`, and the
            // native preview is `PreviewView.ScaleType.FILL_CENTER` (cover).
            // Alignment is stated explicitly rather than defaulted.
            fit: BoxFit.cover,
            alignment: Alignment.center,
            clipBehavior: Clip.hardEdge,
            child: RotatedBox(
              // Layout-aware rotation: the quarter turn happens BEFORE layout,
              // so the sensor-sized child keeps its true aspect instead of
              // being stretched into an upright box and then painted outside
              // its measured bounds (`Transform.rotate` did exactly that).
              quarterTurns: rotation ~/ 90,
              child: SizedBox(
                // Sensor dimensions, laid out exactly: never the upright dims.
                width: current.width.toDouble(),
                height: current.height.toDouble(),
                child: RawImage(image: current, fit: BoxFit.fill),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
