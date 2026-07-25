@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dart_pdf_editor_app/doc_scan_io.dart';

void main() {
  test('documentScanSupported is true only on mobile', () {
    for (final platform in TargetPlatform.values) {
      debugDefaultTargetPlatformOverride = platform;
      final expected = platform == TargetPlatform.android ||
          platform == TargetPlatform.iOS;
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
      expect(await readScannedFile(file.path), [37, 80, 68]);
      expect(await readScannedFile(file.uri.toString()), [37, 80, 68]);
    });

    test('returns null for a content:// URI it cannot read', () async {
      expect(await readScannedFile('content://media/document/1'), isNull);
    });

    test('returns null for a missing file', () async {
      expect(await readScannedFile('${dir.path}/does-not-exist.pdf'), isNull);
    });
  });
}
