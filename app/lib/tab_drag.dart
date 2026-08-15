import 'dart:async' show unawaited;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'document_tab.dart';

const _windowGeometryChannel =
    MethodChannel('dev.milanko.dartpdf/window_geometry');

/// The native window and Flutter-local point under the current cursor.
@immutable
class TabDropLocation {
  const TabDropLocation({required this.windowHandle, required this.localPoint});

  final int windowHandle;
  final Offset localPoint;
}

/// Locates the current desktop cursor in one of DartPDF's native views.
///
/// The native drag APIs use different coordinate systems on macOS, Windows,
/// and Linux. Keeping that conversion beside the native runners also lets the
/// Linux implementation ask GDK which surface is under the pointer on Wayland,
/// where a process cannot reliably calculate global window bounds itself.
abstract interface class TabDropLocator {
  Future<TabDropLocation?> locate(Iterable<int> windowHandles);
}

class NativeTabDropLocator implements TabDropLocator {
  const NativeTabDropLocator();

  @override
  Future<TabDropLocation?> locate(Iterable<int> windowHandles) async {
    final handles = windowHandles.toList(growable: false);
    if (handles.isEmpty) return null;
    final value = await _windowGeometryChannel.invokeMapMethod<String, Object?>(
      'locateDrop',
      <String, Object?>{
        'handles': handles,
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

/// One editor window participating in process-wide tab drags.
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

  /// Closes this native window when the completed transfer removed its final
  /// tab. Implementations may defer until the current frame has finished.
  void closeWindowIfEmpty();
}

/// The live destination resolved for a process-wide tab drag.
@immutable
class TabDragPreview {
  const TabDragPreview({
    required this.tab,
    required this.targetWindowHandle,
    required this.insertionIndex,
  });

  final DocumentTab tab;
  final int? targetWindowHandle;
  final int? insertionIndex;

  bool get isOverTabStrip =>
      targetWindowHandle != null && insertionIndex != null;
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

/// Process-wide router for tab drag sessions.
///
/// Flutter captures the pointer in the source view, but its render hit test is
/// scoped to that view. At release, this router uses Flutter 3.47's native
/// window handles to identify the destination view, then asks that view for
/// the tab insertion slot in its own coordinates.
class TabDragCoordinator extends ChangeNotifier {
  TabDragCoordinator({TabDropLocator locator = const NativeTabDropLocator()})
      : _locator = locator;

  final TabDropLocator _locator;
  final Map<int, TabDragWindow> _windows = <int, TabDragWindow>{};
  final Map<String, _TabTransfer> _transfers = <String, _TabTransfer>{};
  int _nextToken = 0;
  TabDragPreview? _preview;
  String? _previewToken;
  String? _queuedPreviewToken;
  bool _previewLookupInFlight = false;

  /// The current resolved destination, or null before the first pointer poll.
  TabDragPreview? get preview => _preview;

  /// Returns the insertion marker that [windowHandle] should paint.
  int? insertionIndexFor(int windowHandle) =>
      _preview?.targetWindowHandle == windowHandle
          ? _preview?.insertionIndex
          : null;

  /// Returns the current visual state only when [tab] owns the active drag.
  TabDragPreview? previewFor(DocumentTab tab) =>
      identical(_preview?.tab, tab) ? _preview : null;

  void register(TabDragWindow window) {
    _windows[window.windowHandle] = window;
  }

  void unregister(TabDragWindow window) {
    if (identical(_windows[window.windowHandle], window)) {
      _windows.remove(window.windowHandle);
    }
    final removedTokens = <String>[];
    _transfers.removeWhere((token, transfer) {
      final remove = identical(transfer.source, window);
      if (remove) removedTokens.add(token);
      return remove;
    });
    if (removedTokens.contains(_previewToken) ||
        _preview?.targetWindowHandle == window.windowHandle) {
      _clearPreview();
    }
  }

  /// Begins a transfer and returns its process-local token.
  String begin(
    TabDragWindow source,
    DocumentTab tab,
    DocumentHandoff Function() createHandoff, {
    String? token,
  }) {
    final resolvedToken = token ?? '${source.windowHandle}:${_nextToken++}';
    if (_previewToken != null && _previewToken != resolvedToken) {
      _clearPreview();
    }
    _transfers[resolvedToken] = _TabTransfer(
      source: source,
      tab: tab,
      createHandoff: createHandoff,
    );
    return resolvedToken;
  }

  void cancel(String token) {
    _transfers.remove(token);
    if (_previewToken == token) _clearPreview();
  }

  /// Refreshes the live drop target from the native cursor position.
  ///
  /// Pointer updates can arrive faster than the platform channel can answer.
  /// Keep only the newest token while one lookup is running; the drain performs
  /// at most one follow-up lookup and stale sessions can never repaint a newer
  /// drag's destination.
  void update(String token) {
    if (!_transfers.containsKey(token)) return;
    _queuedPreviewToken = token;
    if (_previewLookupInFlight) return;
    _previewLookupInFlight = true;
    unawaited(_drainPreviewUpdates());
  }

  Future<void> _drainPreviewUpdates() async {
    while (_queuedPreviewToken != null) {
      final token = _queuedPreviewToken!;
      _queuedPreviewToken = null;
      final transfer = _transfers[token];
      if (transfer == null) continue;
      try {
        final location = await _locator.locate(_windows.keys);
        if (!identical(_transfers[token], transfer)) continue;
        _setPreview(token, _previewAt(transfer, location));
      } on Object {
        // A transient hover lookup failure must not alter the last trustworthy
        // marker. [finish] performs its own lookup and retains the source tab
        // if that final query fails.
      }
    }
    _previewLookupInFlight = false;
    // An update can be queued between the loop condition and clearing the
    // in-flight flag. Re-enter once so it cannot be stranded.
    if (_queuedPreviewToken != null) update(_queuedPreviewToken!);
  }

  /// Completes a drag exactly once.
  ///
  /// The destination always accepts before the source removes. If locating,
  /// snapshotting, or destination creation fails, the live source is retained.
  Future<TabDragResult> finish(
    String token, {
    required bool userCancelled,
  }) async {
    final transfer = _transfers.remove(token);
    if (_previewToken == token) _clearPreview();
    if (transfer == null || userCancelled) {
      return TabDragResult.cancelled;
    }
    final source = transfer.source;
    if (!_isRegistered(source) || !source.containsTab(transfer.tab)) {
      return TabDragResult.cancelled;
    }

    TabDropLocation? location;
    try {
      location = await _locator.locate(_windows.keys);
    } on Object {
      return TabDragResult.failed;
    }
    if (!_isRegistered(source) || !source.containsTab(transfer.tab)) {
      return TabDragResult.cancelled;
    }

    try {
      final target = location == null ? null : _windows[location.windowHandle];
      final insertion = target?.tabInsertionIndex(location!.localPoint);
      if (target == null || insertion == null) {
        final handoff = transfer.createHandoff();
        if (!source.openTabInNewWindow(handoff)) {
          return TabDragResult.failed;
        }
        if (!source.removeTab(transfer.tab)) return TabDragResult.failed;
        source.closeWindowIfEmpty();
        return TabDragResult.openedNewWindow;
      }

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
      if (!source.removeTab(transfer.tab)) return TabDragResult.failed;
      source.closeWindowIfEmpty();
      return TabDragResult.movedToWindow;
    } on Object {
      return TabDragResult.failed;
    }
  }

  bool _isRegistered(TabDragWindow window) =>
      identical(_windows[window.windowHandle], window);

  TabDragPreview _previewAt(
    _TabTransfer transfer,
    TabDropLocation? location,
  ) {
    final target = location == null ? null : _windows[location.windowHandle];
    final insertion = target?.tabInsertionIndex(location!.localPoint);
    return TabDragPreview(
      tab: transfer.tab,
      targetWindowHandle: insertion == null ? null : target!.windowHandle,
      insertionIndex: insertion,
    );
  }

  void _setPreview(String token, TabDragPreview preview) {
    if (_previewToken == token &&
        identical(_preview?.tab, preview.tab) &&
        _preview?.targetWindowHandle == preview.targetWindowHandle &&
        _preview?.insertionIndex == preview.insertionIndex) {
      return;
    }
    _previewToken = token;
    _preview = preview;
    notifyListeners();
  }

  void _clearPreview() {
    if (_preview == null && _previewToken == null) return;
    _preview = null;
    _previewToken = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _queuedPreviewToken = null;
    _transfers.clear();
    _windows.clear();
    _preview = null;
    _previewToken = null;
    super.dispose();
  }
}
