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
import 'package:flutter_doc_scanner/flutter_doc_scanner.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';

import 'package:dart_pdf_editor_app/doc_scan_io.dart';

class _ImageOnlyScanner extends FlutterDocScanner {
  _ImageOnlyScanner(this.locations);

  final List<String> locations;
  var imageCalls = 0;
  var pdfCalls = 0;

  @override
  Future<ImageScanResult?> getScannedDocumentAsImages({
    int page = 4,
    ImageFormat imageFormat = ImageFormat.jpeg,
    double quality = 0.9,
    bool useAutomaticSinglePictureProcessing = false,
  }) async {
    imageCalls++;
    return ImageScanResult(images: locations);
  }

  @override
  Future<PdfScanResult?> getScannedDocumentAsPdf({int page = 4}) async {
    pdfCalls++;
    throw StateError('the plugin PDF route must not be used');
  }
}

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

  test('DocumentScanException names the location it could not read', () {
    // This string is what reaches the dev log behind the "Couldn't scan"
    // toast, so it has to carry the URI that failed.
    const e = DocumentScanException('content://media/document/1');
    expect(e.toString(), contains('content://media/document/1'));
  });

  test('scan uses page images once and assembles its own PDF', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final dir = Directory.systemTemp.createTempSync('doc_scan_images_test');
    try {
      final first = File('${dir.path}/first.jpg')
        ..writeAsBytesSync(buildTestJpeg());
      final second = File('${dir.path}/second.jpg')
        ..writeAsBytesSync(buildTestJpeg());
      final scanner = _ImageOnlyScanner([first.path, second.path]);

      final bytes = await scanDocumentToPdf(scanner: scanner);
      expect(bytes, isNotNull);
      expect(PdfDocument.open(bytes!).pageCount, 2);
      expect(scanner.imageCalls, 1);
      expect(scanner.pdfCalls, 0);
    } finally {
      dir.deleteSync(recursive: true);
      debugDefaultTargetPlatformOverride = null;
    }
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

    test('falls back for a file:// URI that is not a path at all', () async {
      // An authority ("file://host/x.pdf") and a malformed one both blow up in
      // toFilePath/parse; neither may take the read down with it.
      final tokens = mockReadUri(Uint8List.fromList([37, 80, 68, 70]));
      expect(
        await readScannedFile('file://example.com/scan.pdf', channel: channel),
        [37, 80, 68, 70],
      );
      expect(
        await readScannedFile('file://[bad/scan.pdf', channel: channel),
        [37, 80, 68, 70],
      );
      expect(tokens, ['file://example.com/scan.pdf', 'file://[bad/scan.pdf']);
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

  test('scannedImagesToPdf reads Android content URIs in page order', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final tokens = mockReadUri(buildTestJpeg());

    final bytes = await scannedImagesToPdf(
      const ['content://scan/1', 'content://scan/2'],
      channel: channel,
    );

    expect(PdfDocument.open(bytes).pageCount, 2);
    expect(tokens, ['content://scan/1', 'content://scan/2']);
    debugDefaultTargetPlatformOverride = null;
  });
}
