import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'document_tab.dart';

const _windowGeometryChannel =
    MethodChannel('dev.milanko.dartpdf/window_geometry');

/// The native window and Flutter-local point under a desktop drag.
@immutable
class TabDropLocation {
  const TabDropLocation({required this.windowHandle, required this.localPoint});

  final int windowHandle;
  final Offset localPoint;
}

/// Maps a native drag's screen coordinate back into one of DartPDF's views.
///
/// The native drag APIs use different coordinate systems on macOS, Windows,
/// and Linux. Keeping that conversion beside the native runners also lets the
/// Linux implementation ask GDK which surface is under the pointer on Wayland,
/// where a process cannot reliably calculate global window bounds itself.
abstract interface class TabDropLocator {
  Future<TabDropLocation?> locate(
    Iterable<int> windowHandles,
    Offset screenPoint,
  );
}

class NativeTabDropLocator implements TabDropLocator {
  const NativeTabDropLocator();

  @override
  Future<TabDropLocation?> locate(
    Iterable<int> windowHandles,
    Offset screenPoint,
  ) async {
    final handles = windowHandles.toList(growable: false);
    if (handles.isEmpty) return null;
    final value = await _windowGeometryChannel.invokeMapMethod<String, Object?>(
      'locateDrop',
      <String, Object?>{
        'handles': handles,
        'x': screenPoint.dx,
        'y': screenPoint.dy,
      },
    );
    final handle = value?['handle'];
    final x = value?['x'];
    final y = value?['y'];
    if (handle is! int || x is! num || y is! num) return null;
    return TabDropLocation(
      windowHandle: handle,
      localPoint: Offset(x.toDouble(), y.toDouble()),
    );
  }
}

/// One editor window participating in native tab drags.
abstract interface class TabDragWindow {
  int get windowHandle;

  /// Returns a tab insertion index when [localPoint] is inside this window's
  /// tab strip, otherwise null. The index is in the list before any source tab
  /// is removed and may equal the current tab count.
  int? tabInsertionIndex(Offset localPoint);

  bool containsTab(DocumentTab tab);
  bool reorderTab(DocumentTab tab, int insertionIndex);
  bool insertTab(DocumentHandoff handoff, int insertionIndex);
  bool removeTab(DocumentTab tab);
  bool openTabInNewWindow(DocumentHandoff handoff);
}

enum TabDragResult {
  cancelled,
  reordered,
  movedToWindow,
  openedNewWindow,
  failed,
}

class _TabTransfer {
  const _TabTransfer({
    required this.source,
    required this.tab,
    required this.createHandoff,
  });

  final TabDragWindow source;
  final DocumentTab tab;
  final DocumentHandoff Function() createHandoff;
}

/// Process-wide router for native tab drag sessions.
///
/// Native drag-and-drop supplies a pointer across the whole desktop, while
/// the Flutter framework's render hit test is scoped to one view. This router
/// uses Flutter 3.47's native window handles to identify the destination view,
/// then asks that view for the tab insertion slot in its own coordinates.
class TabDragCoordinator {
  TabDragCoordinator({TabDropLocator locator = const NativeTabDropLocator()})
      : _locator = locator;

  final TabDropLocator _locator;
  final Map<int, TabDragWindow> _windows = <int, TabDragWindow>{};
  final Map<String, _TabTransfer> _transfers = <String, _TabTransfer>{};
  int _nextToken = 0;

  void register(TabDragWindow window) {
    _windows[window.windowHandle] = window;
  }

  void unregister(TabDragWindow window) {
    if (identical(_windows[window.windowHandle], window)) {
      _windows.remove(window.windowHandle);
    }
    _transfers.removeWhere((_, transfer) => identical(transfer.source, window));
  }

  /// Begins a transfer and returns the codec-safe token placed in native local
  /// drag data. The actual controllers remain in this isolate, never in the
  /// platform message payload.
  String begin(
    TabDragWindow source,
    DocumentTab tab,
    DocumentHandoff Function() createHandoff, {
    String? token,
  }) {
    final resolvedToken = token ?? '${source.windowHandle}:${_nextToken++}';
    _transfers[resolvedToken] = _TabTransfer(
      source: source,
      tab: tab,
      createHandoff: createHandoff,
    );
    return resolvedToken;
  }

  void cancel(String token) => _transfers.remove(token);

  /// Completes a native drag exactly once.
  ///
  /// The destination always accepts before the source removes. If locating,
  /// snapshotting, or destination creation fails, the live source is retained.
  Future<TabDragResult> finish(
    String token, {
    required bool userCancelled,
    required Offset? screenPoint,
  }) async {
    final transfer = _transfers.remove(token);
    if (transfer == null || userCancelled || screenPoint == null) {
      return TabDragResult.cancelled;
    }
    final source = transfer.source;
    if (!_isRegistered(source) || !source.containsTab(transfer.tab)) {
      return TabDragResult.cancelled;
    }

    TabDropLocation? location;
    try {
      location = await _locator.locate(_windows.keys, screenPoint);
    } on Object {
      return TabDragResult.failed;
    }
    if (!_isRegistered(source) || !source.containsTab(transfer.tab)) {
      return TabDragResult.cancelled;
    }

    try {
      if (location == null) {
        final handoff = transfer.createHandoff();
        if (!source.openTabInNewWindow(handoff)) {
          return TabDragResult.failed;
        }
        return source.removeTab(transfer.tab)
            ? TabDragResult.openedNewWindow
            : TabDragResult.failed;
      }

      final target = _windows[location.windowHandle];
      if (target == null) return TabDragResult.cancelled;
      final insertion = target.tabInsertionIndex(location.localPoint);
      // Releasing over an existing DartPDF window but outside its tab strip is
      // a cancelled move, not a request for a third window.
      if (insertion == null) return TabDragResult.cancelled;

      if (identical(target, source)) {
        return source.reorderTab(transfer.tab, insertion)
            ? TabDragResult.reordered
            : TabDragResult.cancelled;
      }

      // Snapshot as late as possible. A long-running native drag may outlive
      // an auto-committed edit that was still pending when the pointer lifted.
      final handoff = transfer.createHandoff();
      if (!target.insertTab(handoff, insertion)) {
        return TabDragResult.failed;
      }
      return source.removeTab(transfer.tab)
          ? TabDragResult.movedToWindow
          : TabDragResult.failed;
    } on Object {
      return TabDragResult.failed;
    }
  }

  bool _isRegistered(TabDragWindow window) =>
      identical(_windows[window.windowHandle], window);

  void dispose() {
    _transfers.clear();
    _windows.clear();
  }
}
