import 'dart:async' show unawaited;

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const _channel = MethodChannel('dev.milanko.dartpdf/windows_drop');

enum _WindowsDropEventKind { entered, updated, exited, dropped }

class _WindowsDropEvent {
  const _WindowsDropEvent(this.kind, this.position, this.paths);

  final _WindowsDropEventKind kind;
  final Offset position;
  final List<String> paths;
}

typedef _WindowsDropListener = void Function(_WindowsDropEvent event);

/// Routes the engine-scoped Windows channel to the Flutter view whose HWND
/// received the native OLE drop. `desktop_drop` cannot do this itself because
/// it registers only against the registrar's implicit view; DartPDF's
/// multi-window runner intentionally has no such view.
class _WindowsDropRouter {
  _WindowsDropRouter._() {
    _channel.setMethodCallHandler(_handleCall);
  }

  static final instance = _WindowsDropRouter._();

  final Map<int, Set<_WindowsDropListener>> _listeners = {};

  void attach(int handle, _WindowsDropListener listener) {
    final listeners = _listeners.putIfAbsent(handle, () => {});
    final first = listeners.isEmpty;
    listeners.add(listener);
    if (first) {
      unawaited(_channel.invokeMethod<void>(
          'register', <String, Object>{'handle': handle}).catchError((_) {}));
    }
  }

  void detach(int handle, _WindowsDropListener listener) {
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
      'entered' => _WindowsDropEventKind.entered,
      'updated' => _WindowsDropEventKind.updated,
      'exited' => _WindowsDropEventKind.exited,
      'performOperation' => _WindowsDropEventKind.dropped,
      _ => null,
    };
    if (kind == null) return;
    final event = _WindowsDropEvent(kind, position, paths);
    for (final listener in List<_WindowsDropListener>.of(listeners)) {
      listener(event);
    }
  }
}

/// A per-native-window counterpart to [DropTarget] for DartPDF's Windows
/// multi-window runner.
///
/// The native bridge includes the receiving HWND with each event, so a drop in
/// one window cannot accidentally notify the identically-positioned body of a
/// second window.
class WindowsDropTarget extends StatefulWidget {
  const WindowsDropTarget({
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
  State<WindowsDropTarget> createState() => _WindowsDropTargetState();
}

class _WindowsDropTargetState extends State<WindowsDropTarget> {
  bool _inside = false;

  @override
  void initState() {
    super.initState();
    _WindowsDropRouter.instance.attach(widget.windowHandle, _onEvent);
  }

  @override
  void didUpdateWidget(WindowsDropTarget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.windowHandle == widget.windowHandle) return;
    _WindowsDropRouter.instance.detach(oldWidget.windowHandle, _onEvent);
    _WindowsDropRouter.instance.attach(widget.windowHandle, _onEvent);
    _inside = false;
  }

  void _onEvent(_WindowsDropEvent event) {
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
      case _WindowsDropEventKind.entered:
        if (!inBounds) return;
        _inside = true;
        widget.onDragEntered?.call(details);
      case _WindowsDropEventKind.updated:
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
      case _WindowsDropEventKind.exited:
        if (!_inside) return;
        _inside = false;
        widget.onDragExited?.call(details);
      case _WindowsDropEventKind.dropped:
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
    _WindowsDropRouter.instance.detach(widget.windowHandle, _onEvent);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
