import 'dart:async';

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Connects the mobile platform's keyboard inventory to all app routes.
class KeyboardAvailability extends StatefulWidget {
  const KeyboardAvailability({super.key, required this.child});

  final Widget child;

  @override
  State<KeyboardAvailability> createState() => _KeyboardAvailabilityState();
}

class _KeyboardAvailabilityState extends State<KeyboardAvailability>
    with WidgetsBindingObserver {
  static const _channel = MethodChannel('dev.milanko.dartpdf/keyboard');
  final _mobile = switch (defaultTargetPlatform) {
    TargetPlatform.android ||
    TargetPlatform.iOS ||
    TargetPlatform.fuchsia =>
      true,
    _ => false,
  };
  late bool _connected = !_mobile;
  int _revision = 0;

  bool get _usesNativeSignal => _mobile && !kIsWeb;

  @override
  void initState() {
    super.initState();
    if (!_usesNativeSignal) return;
    WidgetsBinding.instance.addObserver(this);
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'changed' && call.arguments is bool) {
        _revision++;
        _update(call.arguments as bool);
      }
    });
    unawaited(_refresh());
  }

  Future<void> _refresh() async {
    final revision = ++_revision;
    try {
      final connected = await _channel.invokeMethod<bool>('isConnected');
      // A connection notification is newer than an in-flight inventory read.
      if (revision == _revision && connected != null) _update(connected);
    } on MissingPluginException {
      // Unsupported hosts retain the conservative mobile default.
    } on PlatformException {
      // Keep the last known state if a lifecycle refresh fails.
    }
  }

  void _update(bool connected) {
    if (mounted && connected != _connected) {
      setState(() => _connected = connected);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_refresh());
  }

  @override
  void dispose() {
    if (_usesNativeSignal) {
      WidgetsBinding.instance.removeObserver(this);
      _channel.setMethodCallHandler(null);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PdfKeyboardAvailability(
        connected: _connected,
        child: widget.child,
      );
}
