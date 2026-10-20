import 'dart:async' show unawaited;

import 'package:desktop_drop/desktop_drop.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

const _channel = MethodChannel('dev.milanko.dartpdf/windows_drop');

enum _NativeWindowDropEventKind { entered, updated, exited, dropped }

class _NativeWindowDropEvent {
  const _NativeWindowDropEvent(this.kind, this.position, this.paths);

  final _NativeWindowDropEventKind kind;
  final Offset position;
  final List<String> paths;
}

typedef _NativeWindowDropListener = void Function(_NativeWindowDropEvent event);

/// Routes the engine-scoped drop channel to the Flutter view whose native
/// window (HWND on Windows, NSWindow on macOS) received the drop.
/// `desktop_drop` cannot do this itself because it registers only against the
/// registrar's implicit view; DartPDF's multi-window runner intentionally has
/// no such view, so on macOS `desktop_drop` installs nothing at all.
class _NativeWindowDropRouter {
  _NativeWindowDropRouter._() {
    _channel.setMethodCallHandler(_handleCall);
  }

  static final instance = _NativeWindowDropRouter._();

  final Map<int, Set<_NativeWindowDropListener>> _listeners = {};

  void attach(int handle, _NativeWindowDropListener listener) {
    final listeners = _listeners.putIfAbsent(handle, () => {});
    final first = listeners.isEmpty;
    listeners.add(listener);
    if (first) {
      unawaited(_channel.invokeMethod<void>(
          'register', <String, Object>{'handle': handle}).catchError((_) {}));
    }
  }

  void detach(int handle, _NativeWindowDropListener listener) {
    final listeners = _listeners[handle];
    if (listeners == null) return;
    listeners.remove(listener);
    if (listeners.isNotEmpty) return;
    _listeners.remove(handle);
    unawaited(_channel.invokeMethod<void>(
        'unregister', <String, Object>{'handle': handle}).catchError((_) {}));
  }

  Future<void> _handleCall(MethodCall call) async {
    final args = call.arguments;
    if (args is! Map) return;
    final handle = args['handle'];
    if (handle is! int) return;
    final listeners = _listeners[handle];
    if (listeners == null || listeners.isEmpty) return;
    final x = args['x'];
    final y = args['y'];
    final position = Offset(
      x is num ? x.toDouble() : 0,
      y is num ? y.toDouble() : 0,
    );
    final paths = switch (args['paths']) {
      final List values => values.whereType<String>().toList(growable: false),
      _ => const <String>[],
    };
    final kind = switch (call.method) {
      'entered' => _NativeWindowDropEventKind.entered,
      'updated' => _NativeWindowDropEventKind.updated,
      'exited' => _NativeWindowDropEventKind.exited,
      'performOperation' => _NativeWindowDropEventKind.dropped,
      _ => null,
    };
    if (kind == null) return;
    final event = _NativeWindowDropEvent(kind, position, paths);
    for (final listener in List<_NativeWindowDropListener>.of(listeners)) {
      listener(event);
    }
  }
}

/// A per-native-window counterpart to [DropTarget] for DartPDF's Windows and
/// macOS multi-window runners (`windows_drop.cpp`, `WindowDropService.swift`).
///
/// The native bridge includes the receiving window handle with each event, so a drop in
/// one window cannot accidentally notify the identically-positioned body of a
/// second window.
class NativeWindowDropTarget extends StatefulWidget {
  const NativeWindowDropTarget({
    super.key,
    required this.windowHandle,
    required this.child,
    this.onDragEntered,
    this.onDragUpdated,
    this.onDragExited,
    this.onDragDone,
  });

  final int windowHandle;
  final Widget child;
  final OnDragCallback<DropEventDetails>? onDragEntered;
  final OnDragCallback<DropEventDetails>? onDragUpdated;
  final OnDragCallback<DropEventDetails>? onDragExited;
  final OnDragDoneCallback? onDragDone;

  @override
  State<NativeWindowDropTarget> createState() => _NativeWindowDropTargetState();
}

class _NativeWindowDropTargetState extends State<NativeWindowDropTarget> {
  bool _inside = false;

  @override
  void initState() {
    super.initState();
    _NativeWindowDropRouter.instance.attach(widget.windowHandle, _onEvent);
  }

  @override
  void didUpdateWidget(NativeWindowDropTarget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.windowHandle == widget.windowHandle) return;
    _NativeWindowDropRouter.instance.detach(oldWidget.windowHandle, _onEvent);
    _NativeWindowDropRouter.instance.attach(widget.windowHandle, _onEvent);
    _inside = false;
  }

  void _onEvent(_NativeWindowDropEvent event) {
    if (!mounted) return;
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return;
    final ratio = MediaQuery.devicePixelRatioOf(context);
    final global = event.position / ratio;
    final local = box.globalToLocal(global);
    final inBounds = box.paintBounds.contains(local);
    final details = DropEventDetails(
      localPosition: local,
      globalPosition: global,
    );
    switch (event.kind) {
      case _NativeWindowDropEventKind.entered:
        if (!inBounds) return;
        _inside = true;
        widget.onDragEntered?.call(details);
      case _NativeWindowDropEventKind.updated:
        if (inBounds) {
          if (!_inside) {
            _inside = true;
            widget.onDragEntered?.call(details);
          } else {
            widget.onDragUpdated?.call(details);
          }
        } else if (_inside) {
          _inside = false;
          widget.onDragExited?.call(details);
        }
      case _NativeWindowDropEventKind.exited:
        if (!_inside) return;
        _inside = false;
        widget.onDragExited?.call(details);
      case _NativeWindowDropEventKind.dropped:
        if (!_inside || !inBounds) return;
        _inside = false;
        widget.onDragDone?.call(DropDoneDetails(
          files: [for (final path in event.paths) DropItemFile(path)],
          localPosition: local,
          globalPosition: global,
        ));
    }
  }

  @override
  void dispose() {
    _NativeWindowDropRouter.instance.detach(widget.windowHandle, _onEvent);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
