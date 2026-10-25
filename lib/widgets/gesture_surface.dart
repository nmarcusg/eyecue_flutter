import 'package:flutter/widgets.dart';

import '../services/gesture_controller.dart';

/// A transparent touch surface that feeds raw pointer events into a
/// [GestureController].
///
/// Wraps the whole main area (the camera viewport and its state-panel area) so
/// thesis gestures work without relying on visible buttons. It is translucent,
/// so the camera preview and overlays stay fully visible beneath it.
class GestureSurface extends StatefulWidget {
  final GestureController controller;
  final Widget child;

  const GestureSurface({
    super.key,
    required this.controller,
    required this.child,
  });

  @override
  State<GestureSurface> createState() => _GestureSurfaceState();
}

class _GestureSurfaceState extends State<GestureSurface> {
  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (e) =>
          widget.controller.onPointerDown(e.pointer, e.localPosition),
      onPointerMove: (e) =>
          widget.controller.onPointerMove(e.pointer, e.localPosition),
      onPointerUp: (e) =>
          widget.controller.onPointerUp(e.pointer, e.localPosition),
      onPointerCancel: (e) => widget.controller.onPointerCancel(e.pointer),
      child: widget.child,
    );
  }
}
