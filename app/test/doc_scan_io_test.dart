// Reading back what the device document scanner produced. iOS hands over a
// bare filesystem path; Android hands over a Uri into ML Kit's own scratch
// space whose scheme depends on the Play Services build, so the plain-path read
// is only the fast path there and the runner's ContentResolver
// (`mobile_file`'s `readUri`) is the fallback. The native handler itself needs
// on-device verification; these cover the Dart contract.
@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dart_pdf_editor_app/doc_scan_io.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  const channel = MethodChannel('test/doc_scan_uri');

  /// Installs a fake runner that serves [bytes] for any `readUri` call,
  /// recording the tokens it was asked for. A null [bytes] fails the read.
  List<String> mockReadUri(Uint8List? bytes) {
    final tokens = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method != 'readUri') return null;
      tokens.add(call.arguments['token'] as String);
      if (bytes == null) {
        throw PlatformException(code: 'read_failed', message: 'no such uri');
      }
      return bytes;
    });
    return tokens;
  }

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    debugDefaultTargetPlatformOverride = null;
  });

  test('documentScanSupported is true only on mobile', () {
    for (final platform in TargetPlatform.values) {
      debugDefaultTargetPlatformOverride = platform;
      final expected =
          platform == TargetPlatform.android || platform == TargetPlatform.iOS;
      expect(documentScanSupported, expected, reason: '$platform');
    }
    debugDefaultTargetPlatformOverride = null;
  });

  group('readScannedFile', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('doc_scan_test'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('reads a plain path (iOS) and a file:// URI (Android)', () async {
      final file = File('${dir.path}/scan.pdf')..writeAsBytesSync([37, 80, 68]);
      // iOS hands back a bare filesystem path; Android a file:// URI.
      expect(await readScannedFile(file.path, channel: channel), [37, 80, 68]);
      expect(
        await readScannedFile(file.uri.toString(), channel: channel),
        [37, 80, 68],
      );
    });

    test('reads a readable path without touching the runner', () async {
      final file = File('${dir.path}/scan.pdf')..writeAsBytesSync([37, 80, 68]);
      final tokens = mockReadUri(Uint8List.fromList([1, 2, 3]));
      expect(await readScannedFile(file.path, channel: channel), [37, 80, 68]);
      expect(tokens, isEmpty);
    });

    test('reads a content:// URI through the runner', () async {
      // The shape that made scanning look like a no-op on Android: dart:io
      // can't open it, so the read has to go through the ContentResolver.
      final tokens = mockReadUri(Uint8List.fromList([37, 80, 68, 70]));
      expect(
        await readScannedFile('content://media/document/1', channel: channel),
        [37, 80, 68, 70],
      );
      expect(tokens, ['content://media/document/1']);
    });

    test('falls back to the runner for a file:// URI it cannot open', () async {
      // ML Kit's cache Uri can name a path the app can't open by path; the
      // ContentResolver still resolves it.
      final missing = File('${dir.path}/gone.pdf').uri.toString();
      final tokens = mockReadUri(Uint8List.fromList([37, 80, 68, 70]));
      expect(
        await readScannedFile(missing, channel: channel),
        [37, 80, 68, 70],
      );
      expect(tokens, [missing]);
    });

    test('returns null when the runner cannot read it either', () async {
      mockReadUri(null);
      expect(
        await readScannedFile('content://media/document/1', channel: channel),
        isNull,
      );
      expect(await readScannedFile('${dir.path}/nope.pdf', channel: channel),
          isNull);
    });

    test('returns null on an older runner without readUri', () async {
      // No mock handler installed: invokeMethod throws MissingPluginException.
      expect(
        await readScannedFile('content://media/document/1', channel: channel),
        isNull,
      );
    });

    test('treats an empty scan file as unreadable', () async {
      final empty = File('${dir.path}/empty.pdf')..writeAsBytesSync([]);
      mockReadUri(null);
      expect(await readScannedFile(empty.path, channel: channel), isNull);
    });

    test('does not reach for the runner off Android', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final tokens = mockReadUri(Uint8List.fromList([37, 80, 68]));
      expect(
        await readScannedFile('content://media/document/1', channel: channel),
        isNull,
      );
      expect(tokens, isEmpty);
      debugDefaultTargetPlatformOverride = null;
    });
  });
}
