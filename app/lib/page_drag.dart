import 'dart:async' show unawaited;

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'tab_drag.dart';

/// One editor window that can receive pages dragged out of another window's
/// thumbnail strip.
abstract interface class PageDropWindow {
  int get windowHandle;

  /// Whether [controller] is one of this window's edit sessions - a drag
  /// released over the window it started in is not a transfer.
  bool ownsSession(PdfEditingController controller);

  /// Marks (and returns) the page slot a drop at [localPoint] would land
  /// in, or null when the point isn't over a thumbnail panel.
  int? pageDropIndexAt(Offset localPoint);

  /// Clears the insertion marker [pageDropIndexAt] painted.
  void clearPageDropMarker();

  /// Inserts the [pageCount] pages held by [bytes] (a self-contained PDF) at
  /// [at] - null picks the window's own default - and returns whether they
  /// landed.
  bool acceptDroppedPages(Uint8List bytes, int pageCount, {int? at});
}

enum PageDragResult { cancelled, moved, copied, failed }

/// Routes page drags between editor windows.
///
/// A thumbnail strip only sees its own window; when a tile drag leaves it the
/// strip reports the pointer through [PdfThumbnailDropController]'s drag-out
/// callbacks, and this coordinator asks the native side which window is under
/// the cursor (the same lookup [TabDragCoordinator] uses for tabs). Hovering
/// another window's thumbnail panel marks the slot the pages would take; the
/// release moves them: the destination inserts first, then the source
/// removes, so a failure never loses a page. Dragging every page of a
/// document out copies them - a document can't be left empty.
class PageDragCoordinator {
  PageDragCoordinator({TabDropLocator locator = const NativeTabDropLocator()})
      : _locator = locator;

  final TabDropLocator _locator;
  final Map<int, PageDropWindow> _windows = <int, PageDropWindow>{};
  PageDropWindow? _marked;
  PdfPageDragOut? _queued;
  bool _lookupInFlight = false;

  /// Bumped when a drag ends, so a hover lookup still in flight can't paint a
  /// marker after the drop has cleared it.
  int _generation = 0;

  void register(PageDropWindow window) {
    _windows[window.windowHandle] = window;
  }

  void unregister(PageDropWindow window) {
    if (identical(_windows[window.windowHandle], window)) {
      _windows.remove(window.windowHandle);
    }
    if (identical(_marked, window)) _marked = null;
  }

  /// A page drag moved outside its window ([drag]), or came back / ended
  /// (null). Pointer moves outpace the platform channel, so only the newest
  /// position is looked up while a lookup runs.
  void update(PdfPageDragOut? drag) {
    if (drag == null) {
      _generation++;
      _queued = null;
      _clearMarker();
      return;
    }
    _queued = drag;
    if (_lookupInFlight) return;
    _lookupInFlight = true;
    unawaited(_drainUpdates());
  }

  Future<void> _drainUpdates() async {
    while (_queued != null) {
      final drag = _queued!;
      _queued = null;
      final generation = _generation;
      try {
        final location = await _locator.locate(_windows.keys);
        if (generation != _generation) continue;
        final target = _targetAt(location, drag);
        if (!identical(target, _marked)) _clearMarker();
        if (target != null) {
          _marked = target;
          target.pageDropIndexAt(location!.localPoint);
        }
      } on Object {
        // A failed hover lookup only costs the marker; the drop re-locates.
      }
    }
    _lookupInFlight = false;
  }

  /// Completes a drag released outside its window: moves [drag]'s pages into
  /// the window under the cursor. Released over no window (the desktop) or
  /// back over its own, nothing happens.
  Future<PageDragResult> drop(PdfPageDragOut drag) async {
    _generation++;
    _queued = null;
    final source = drag.controller;
    final sourceWindow = _sourceWindow(source);
    final revision = source.document;
    if (sourceWindow == null) {
      _clearMarker();
      return PageDragResult.cancelled;
    }
    TabDropLocation? location;
    try {
      location = await _locator.locate(_windows.keys);
    } on Object {
      _clearMarker();
      return PageDragResult.failed;
    }
    // The platform channel yields: a close, undo, or page edit can run while
    // it locates the destination. Slot numbers only identify pages in the
    // revision that was released, and a closed session must not be edited.
    if (!identical(_sourceWindow(source), sourceWindow) ||
        !identical(source.document, revision)) {
      _clearMarker();
      return PageDragResult.cancelled;
    }
    final target = _targetAt(location, drag);
    final at = target?.pageDropIndexAt(location!.localPoint);
    target?.clearPageDropMarker();
    _clearMarker();
    if (target == null) return PageDragResult.cancelled;

    final count = source.document.pageCount;
    final pages = [
      for (final page in drag.pages)
        if (page >= 0 && page < count) page,
    ];
    if (pages.isEmpty) return PageDragResult.cancelled;
    try {
      final bytes = source.exportPages(pages);
      if (!target.acceptDroppedPages(bytes, pages.length, at: at)) {
        return PageDragResult.failed;
      }
    } on Object catch (error) {
      debugPrint('page drag failed: $error');
      return PageDragResult.failed;
    }
    // removePages refuses to empty the document: that drop is a copy
    return source.removePages(pages)
        ? PageDragResult.moved
        : PageDragResult.copied;
  }

  PageDropWindow? _sourceWindow(PdfEditingController controller) {
    for (final window in _windows.values) {
      if (window.ownsSession(controller)) return window;
    }
    return null;
  }

  PageDropWindow? _targetAt(TabDropLocation? location, PdfPageDragOut drag) {
    if (location == null) return null;
    final target = _windows[location.windowHandle];
    if (target == null || target.ownsSession(drag.controller)) return null;
    return target;
  }

  void _clearMarker() {
    final marked = _marked;
    _marked = null;
    marked?.clearPageDropMarker();
  }

  void dispose() {
    _generation++;
    _queued = null;
    _windows.clear();
    _marked = null;
  }
}
