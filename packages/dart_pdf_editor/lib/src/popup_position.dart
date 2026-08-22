import 'package:flutter/material.dart';

/// Positions a popup at a pointer location expressed in global coordinates.
///
/// [showMenu] interprets its [RelativeRect] in the coordinate system of the
/// navigator overlay that receives the route. A nested navigator can have a
/// non-zero global origin, so passing the pointer position through unchanged
/// shifts the popup by that origin a second time.
RelativeRect pdfPopupPosition(BuildContext context, Offset globalPosition) {
  final overlay = Overlay.of(context).context.findRenderObject()! as RenderBox;
  final overlayPosition = overlay.globalToLocal(globalPosition);
  return RelativeRect.fromRect(
    overlayPosition & Size.zero,
    Offset.zero & overlay.size,
  );
}
