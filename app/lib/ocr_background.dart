import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

/// Extends execution only through the OS's supported user-visible mechanism.
/// No platform promise replaces durable page checkpoints.
class OcrBackground {
  static const _channel = MethodChannel('dev.milanko.dartpdf/ocr_background');
  bool expired = false;
  bool _enabled = false;

  Future<void> begin(String title, int count,
      {required bool automatic, Future<void> Function()? onCancel}) async {
    if (kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.android &&
            defaultTargetPlatform != TargetPlatform.iOS)) {
      return;
    }
    _enabled = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'expired') expired = true;
      if (call.method == 'cancel') await onCancel?.call();
    });
    try {
      await _channel.invokeMethod<void>('begin', {
        'title': title,
        'count': count,
        'automatic': automatic,
      });
    } on MissingPluginException {
      // Background hosting is optional under embedded/test hosts.
      // Test/embedded hosts still checkpoint and resume after interruption.
    } on PlatformException {
      // The OS may reject or end an advisory background grant.
      // An OS may deny a background grant. Continue in foreground, retaining
      // the checkpoints, rather than abandoning the user's request.
    }
  }

  Future<void> progress(int completed, int count) async {
    if (!_enabled) return;
    try {
      await _channel.invokeMethod<void>(
          'progress', {'completed': completed, 'count': count});
    } on MissingPluginException {
      // Background hosting is optional under embedded/test hosts.
    } on PlatformException {
      // The system may have already ended the background task.
    }
  }

  Future<void> end({required bool success}) async {
    if (!_enabled) return;
    try {
      await _channel.invokeMethod<void>('end', success);
    } on MissingPluginException {
      // Background hosting is optional under embedded/test hosts.
    } on PlatformException {
      // The system may have already ended the background task.
    }
    _channel.setMethodCallHandler(null);
  }
}
