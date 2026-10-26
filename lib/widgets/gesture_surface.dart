import 'package:flutter/widgets.dart';

import '../services/gesture_controller.dart';

/// A transparent touch surface that feeds raw pointer events into a
/// [GestureController].
///
/// Wraps the live viewport only; non-live panels and the depth notice are
/// outside it. It is translucent, so the camera preview and overlays stay fully
/// visible beneath it.
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
    // shortcut: the placement fix only holds while the wrapped subtree stays
    // pointer-inert. Any interactive child added inside it would compete with
    // this Listener and re-introduce tap→pause classification, so keep buttons
    // outside the surface and revisit this if the viewport itself needs taps.
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
