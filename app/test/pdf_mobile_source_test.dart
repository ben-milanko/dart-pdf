// PdfMobileByteSource reads a phone/tablet pick by reference over the native
// `mobile_file` method channel: ranged reads, progress, cancellation, an
// unknown (negative) length normalized to null - and it opens a real document
// through PdfDocument.openSource. pickPdfMobileReferences maps the picker's
// native result into typed descriptors. The native handlers themselves
// (Android openFileDescriptor / iOS NSFileCoordinator) need on-device
// verification and can't run here; these cover the Dart contract.
@TestOn('vm')
library;

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:dart_pdf_editor_app/file_io.dart';
import 'package:dart_pdf_editor_app/pdf_mobile_source.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late Uint8List pdfBytes;

  /// Installs a fake native handler on [channel] that serves [bytes] as a
  /// seekable file. [length] overrides the reported size (-1 = unknown).
  void mockFile(MethodChannel channel, Uint8List bytes, {int? length}) {
    messenger.setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'fileLength':
          return length ?? bytes.length;
        case 'readRange':
          final offset = call.arguments['offset'] as int;
          final len = call.arguments['length'] as int;
          final end = (offset + len).clamp(0, bytes.length);
          final start = offset.clamp(0, bytes.length);
          return Uint8List.sublistView(bytes, start, end);
        default:
          return null;
      }
    });
  }

  setUp(() {
    pdfBytes = PdfBlankDocument.create();
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(mobileFileChannel, null);
  });

  test('length reports the native file size', () async {
    const channel = MethodChannel('test/mobile_file_len');
    mockFile(channel, pdfBytes);
    final source = PdfMobileByteSource('tok', channel: channel);
    expect(await source.length, pdfBytes.length);
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('a negative native length normalizes to unknown (null)', () async {
    const channel = MethodChannel('test/mobile_file_unknown');
    mockFile(channel, pdfBytes, length: -1);
    final source = PdfMobileByteSource('tok', channel: channel);
    expect(await source.length, isNull);
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('readRange returns the requested slice and empties past the end',
      () async {
    const channel = MethodChannel('test/mobile_file_range');
    mockFile(channel, pdfBytes);
    final source = PdfMobileByteSource('tok', channel: channel);
    expect(await source.readRange(0, 5), pdfBytes.sublist(0, 5));
    expect(await source.readRange(10, 20), pdfBytes.sublist(10, 20));
    // A negative start clamps to 0; a degenerate range is empty.
    expect(await source.readRange(-5, 3), pdfBytes.sublist(0, 3));
    expect(await source.readRange(30, 30), isEmpty);
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('reports cumulative progress across reads', () async {
    const channel = MethodChannel('test/mobile_file_progress');
    mockFile(channel, pdfBytes);
    final seen = <int>[];
    final source = PdfMobileByteSource(
      'tok',
      channel: channel,
      onProgress: (received, total) => seen.add(received),
    );
    await source.readRange(0, 10);
    await source.readRange(10, 25);
    // Progress is the running total of bytes pulled: 10, then 10 + 15.
    expect(seen, [10, 25]);
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('a fired cancel token aborts reads without touching the channel',
      () async {
    const channel = MethodChannel('test/mobile_file_cancel');
    mockFile(channel, pdfBytes);
    final token = PdfCancelToken();
    final source =
        PdfMobileByteSource('tok', channel: channel, cancelToken: token);
    token.cancel();
    expect(source.readRange(0, 10), throwsA(isA<PdfHttpCancelledException>()));
    expect(source.length, throwsA(isA<PdfHttpCancelledException>()));
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('readSourceFully reassembles the exact file over ranged reads',
      () async {
    const channel = MethodChannel('test/mobile_file_full');
    mockFile(channel, pdfBytes);
    final source = PdfMobileByteSource('tok', channel: channel);
    final full = await readSourceFully(source, chunk: 16);
    expect(full, pdfBytes);
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('PdfDocument.openSource opens the file through the mobile source',
      () async {
    const channel = MethodChannel('test/mobile_file_open');
    mockFile(channel, pdfBytes);
    final source = PdfMobileByteSource('tok', channel: channel);
    final doc = await PdfDocument.openSource(source);
    expect(doc.pageCount, 1);
    expect(doc.cos.bytes.length, pdfBytes.length);
    messenger.setMockMethodCallHandler(channel, null);
  });

  group('pickPdfMobileReferences', () {
    test('maps the native picker result into typed descriptors', () async {
      messenger.setMockMethodCallHandler(mobileFileChannel, (call) async {
        expect(call.method, 'pickDocuments');
        return <Map<Object?, Object?>>[
          {'token': 't1', 'name': 'a.pdf', 'length': 1234, 'seekable': true},
          // Seekability defaults to false when the runner omits it.
          {'token': 't2', 'name': 'b.pdf'},
          // An entry without a token is dropped.
          {'name': 'no-token.pdf'},
        ];
      });
      final picks = await pickPdfMobileReferences();
      expect(picks.length, 2);
      expect(picks[0].token, 't1');
      expect(picks[0].name, 'a.pdf');
      expect(picks[0].length, 1234);
      expect(picks[0].seekable, isTrue);
      expect(picks[1].token, 't2');
      expect(picks[1].seekable, isFalse);
      expect(picks[1].length, isNull);
    });

    test('a cancelled pick (null result) yields an empty list', () async {
      messenger.setMockMethodCallHandler(
          mobileFileChannel, (call) async => null);
      expect(await pickPdfMobileReferences(), isEmpty);
    });
  });

  group('supportsMobileProgressiveOpen', () {
    tearDown(() => debugDefaultTargetPlatformOverride = null);

    test('is true on Android and iOS', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      expect(supportsMobileProgressiveOpen, isTrue);
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      expect(supportsMobileProgressiveOpen, isTrue);
    });

    test('is false on desktop', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      expect(supportsMobileProgressiveOpen, isFalse);
    });
  });
}
