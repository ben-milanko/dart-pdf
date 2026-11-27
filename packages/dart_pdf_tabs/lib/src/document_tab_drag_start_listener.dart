import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

/// Starts a drag-reorder of the tab at [index] in the enclosing
/// [SliverReorderableList] (such as [DocumentTabStrip]'s list): immediately
/// for a mouse, after a long-press for touch, so a finger can still scroll the
/// strip. A secondary-button press never starts a drag - it opens the tab's
/// context menu instead.
class DocumentTabDragStartListener extends ReorderableDragStartListener {
  const DocumentTabDragStartListener({
    super.key,
    required super.index,
    required super.child,
  });

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (event) {
        if (event.buttons == kSecondaryButton) return;
        SliverReorderableList.maybeOf(context)?.startItemDragReorder(
          index: index,
          event: event,
          recognizer: (event.kind == PointerDeviceKind.mouse
              ? ImmediateMultiDragGestureRecognizer(debugOwner: this)
              : DelayedMultiDragGestureRecognizer(debugOwner: this))
            ..gestureSettings = MediaQuery.maybeGestureSettingsOf(context),
        );
      },
      child: child,
    );
  }
}
