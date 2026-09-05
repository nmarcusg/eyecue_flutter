import 'package:flutter/material.dart';
import '../models/detection.dart';

/// ---------------------------------------------------------------------------
/// BoundingBoxPainter
///
/// A [CustomPainter] that draws YOLO detection bounding boxes, labels, and
/// confidence scores on top of the camera preview.
///
/// Orientation is handled upstream (see `lib/models/box_transform.dart`): the
/// inference isolate rotates/mirrors the input to the upright coordinate
/// system, so the detections this painter receives are ALREADY in upright
/// (display) space. This painter is therefore a pure normalized→pixel mapper
/// and knows nothing about sensor orientation, rotation, or lens direction.
///
/// It maps normalized [0,1] boxes to screen pixels using the same
/// `applyBoxFit` math as the preview layout's `FittedBox`, so boxes align
/// with the rendered pixels exactly:
///   - imageSize = the upright (display) image dimensions (e.g. 240×320 in
///     portrait, 320×240 in landscape) — NOT the sensor dimensions
///   - Preview fit (`BoxFit.contain`/`cover`), identical to the preview
///
/// Paint objects are created once and cached per painter instance to minimise
/// allocations inside [paint].
/// ---------------------------------------------------------------------------
class BoundingBoxPainter extends CustomPainter {
  final List<Detection> detections;
  final Size imageSize;

  /// Must match the [BoxFit] used by the preview layout's `FittedBox`.
  final BoxFit fit;

  BoundingBoxPainter({
    required this.detections,
    required this.imageSize,
    this.fit = BoxFit.contain,
  });

  // ---------------------------------------------------------------------------
  // Cached paint objects — allocated once per painter lifecycle
  // ---------------------------------------------------------------------------
  static final _boxPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2.5
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;

  static final _labelBgPaint = Paint()..style = PaintingStyle.fill;

  static final _labelTextStyle = TextStyle(
    color: Colors.white,
    fontSize: 12,
    fontWeight: FontWeight.w600,
    height: 1.2,
  );

  static final _shadowPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.0
    ..color = const Color(0x40000000); // 25% black shadow

  // ---------------------------------------------------------------------------
  // Colour palette — cycles through distinct colours per class
  // ---------------------------------------------------------------------------
  static const _palette = [
    Color(0xFF00E676), // green
    Color(0xFFFF9100), // orange
    Color(0xFF00B0FF), // light blue
    Color(0xFFFFD600), // yellow
    Color(0xFFFF1744), // red
    Color(0xFFD500F9), // purple
    Color(0xFF76FF03), // lime
    Color(0xFF00E5FF), // cyan
  ];

  Color _colorForClass(int classId) => _palette[classId % _palette.length];

  // ---------------------------------------------------------------------------
  // Coordinate transformation
  // ---------------------------------------------------------------------------

  /// Calculates the [Rect] within [previewSize] where the camera image is
  /// actually rendered, using the same `applyBoxFit` math as the preview
  /// layout's `FittedBox`.
  ///
  /// For [BoxFit.contain] this letterboxes (bars on the shorter axis); for
  /// [BoxFit.cover] it center-crops (fills the screen, hiding the excess).
  /// The result is centered exactly like `FittedBox` centers its child.
  static Rect _calculateImageRect(
    Size previewSize,
    Size imageSize,
    BoxFit fit,
  ) {
    if (imageSize.width <= 0 || imageSize.height <= 0) {
      return Rect.fromLTWH(0, 0, previewSize.width, previewSize.height);
    }

    final FittedSizes fitted = applyBoxFit(fit, imageSize, previewSize);
    final Size scaled = fitted.destination;
    final double offsetX = (previewSize.width - scaled.width) / 2.0;
    final double offsetY = (previewSize.height - scaled.height) / 2.0;

    return Rect.fromLTWH(offsetX, offsetY, scaled.width, scaled.height);
  }

  // ---------------------------------------------------------------------------
  // Paint
  // ---------------------------------------------------------------------------

  // ---------------------------------------------------------------------------
  // Throttle state for debug logging (avoid spamming every frame)
  // ---------------------------------------------------------------------------
  static int _paintCallCount = 0;

  @override
  void paint(Canvas canvas, Size size) {
    _paintCallCount++;

    if (detections.isEmpty || imageSize.width <= 0 || imageSize.height <= 0) {
      return;
    }

    // 1. Determine where the camera image appears on screen (same fit as the
    //    preview layout's FittedBox).
    final imageRect = _calculateImageRect(size, imageSize, fit);

    // Compute scale factor: how many screen pixels per image pixel
    final double scaleX = imageRect.width / imageSize.width;
    final double scaleY = imageRect.height / imageSize.height;

    // --- Painter debug logging (every 30th paint to avoid spam) ---
    if (_paintCallCount % 30 == 1) {
      debugPrint('[Painter] Paint #$_paintCallCount');
      debugPrint('[Painter]   Boxes to render: ${detections.length}');
      debugPrint(
        '[Painter]   Screen: ${size.width.toInt()}×${size.height.toInt()}',
      );
      debugPrint(
        '[Painter]   Image : ${imageSize.width.toInt()}×${imageSize.height.toInt()}',
      );
      debugPrint(
        '[Painter]   Scale : ${scaleX.toStringAsFixed(2)}×${scaleY.toStringAsFixed(2)}',
      );
      debugPrint(
        '[Painter]   Image rect: '
        '(${imageRect.left.toInt()},${imageRect.top.toInt()})-'
        '(${imageRect.right.toInt()},${imageRect.bottom.toInt()})',
      );
    }

    // 2. Draw each detection.
    for (final detection in detections) {
      final Rect normBox = detection.box;

      // --- Map normalised [0,1] coords to screen pixels ---
      double screenLeft = imageRect.left + normBox.left * imageRect.width;
      double screenTop = imageRect.top + normBox.top * imageRect.height;
      double screenWidth = normBox.width * imageRect.width;
      double screenHeight = normBox.height * imageRect.height;

      // Clamp to image rect bounds to prevent boxes drifting into letterbox area
      screenLeft = screenLeft.clamp(
        imageRect.left,
        imageRect.left + imageRect.width,
      );
      screenTop = screenTop.clamp(
        imageRect.top,
        imageRect.top + imageRect.height,
      );
      screenWidth =
          (screenLeft + screenWidth).clamp(imageRect.left, imageRect.right) -
          screenLeft;
      screenHeight =
          (screenTop + screenHeight).clamp(imageRect.top, imageRect.bottom) -
          screenTop;

      if (screenWidth <= 0 || screenHeight <= 0) continue;

      final Rect screenRect = Rect.fromLTWH(
        screenLeft,
        screenTop,
        screenWidth,
        screenHeight,
      );

      // --- Per-box logging (first box only, every 30th paint) ---
      if (_paintCallCount % 30 == 1 && detection == detections.first) {
        debugPrint(
          '[Painter]   Rendered #1 "${detection.label}": '
          '(${screenLeft.toInt()},${screenTop.toInt()})-'
          '(${(screenLeft + screenWidth).toInt()},${(screenTop + screenHeight).toInt()}) '
          '[norm: ${normBox.left.toStringAsFixed(2)},${normBox.top.toStringAsFixed(2)} '
          '${normBox.width.toStringAsFixed(2)}×${normBox.height.toStringAsFixed(2)}]',
        );
      }

      final Color color = _colorForClass(detection.classId);

      // --- Draw shadow (improves visibility on bright backgrounds) ---
      canvas.drawRect(screenRect, _shadowPaint);

      // --- Draw bounding box ---
      _boxPaint.color = color;
      canvas.drawRect(screenRect, _boxPaint);

      // --- Draw label ---
      _drawLabel(
        canvas,
        screenRect,
        detection.label,
        detection.confidence,
        color,
      );
    }
  }

  void _drawLabel(
    Canvas canvas,
    Rect boxRect,
    String label,
    double confidence,
    Color color,
  ) {
    final int pct = (confidence * 100).round();
    final String text = '$label $pct%';

    final TextPainter textPainter = TextPainter(
      text: TextSpan(text: text, style: _labelTextStyle),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: boxRect.width);

    // Position label above the box, or inside if box is at top of screen
    final double labelY = boxRect.top - textPainter.height - 2 > 0
        ? boxRect.top - textPainter.height - 2
        : boxRect.top + 2;

    final double labelX = boxRect.left.clamp(
      0,
      boxRect.right - textPainter.width,
    );

    // Background pill behind text
    final Rect bgRect = Rect.fromLTWH(
      labelX - 4,
      labelY - 1,
      textPainter.width + 8,
      textPainter.height + 2,
    );

    _labelBgPaint.color = color;
    canvas.drawRRect(
      RRect.fromRectAndRadius(bgRect, const Radius.circular(4)),
      _labelBgPaint,
    );

    // Text on top
    textPainter.paint(canvas, Offset(labelX, labelY));
  }

  @override
  bool shouldRepaint(covariant BoundingBoxPainter oldDelegate) {
    // Repaint when detections or image dimensions change. Comparing list
    // identity is sufficient because the isolate always produces a new
    // List<Detection> for each inference result.
    return oldDelegate.detections != detections ||
        oldDelegate.imageSize != imageSize ||
        oldDelegate.fit != fit;
  }
}
