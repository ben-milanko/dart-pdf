@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:dart_pdf_editor_app/doc_scan_io.dart';

// A valid 1x1 transparent PNG - the smallest real image PdfImageDocument can
// embed, so the assembly path decodes something real.
final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAC0lEQVR42mNk'
  '+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
);

void main() {
  group('scanImageLocations', () {
    test('reads the images/Uri/uri map shapes', () {
      expect(scanImageLocations({'images': ['a', 'b'], 'count': 2}),
          ['a', 'b']);
      expect(scanImageLocations({'Uri': ['x']}), ['x']);
      expect(scanImageLocations({'uri': 'y'}), ['y']);
    });

    test('reads a bare list or string', () {
      expect(scanImageLocations(['p', 'q']), ['p', 'q']);
      expect(scanImageLocations('solo'), ['solo']);
    });

    test('is empty for an unrecognized or null result', () {
      expect(scanImageLocations({'other': 1}), isEmpty);
      expect(scanImageLocations(null), isEmpty);
      expect(scanImageLocations(42), isEmpty);
    });
  });

  group('scanPdfLocation', () {
    test('reads the pdfUri/Uri map shapes and a bare string', () {
      expect(scanPdfLocation({'pdfUri': 'a.pdf', 'pageCount': 3}), 'a.pdf');
      expect(scanPdfLocation({'Uri': 'b.pdf'}), 'b.pdf');
      expect(scanPdfLocation('c.pdf'), 'c.pdf');
    });

    test('is null for an unrecognized or null result', () {
      expect(scanPdfLocation({'nope': 1}), isNull);
      expect(scanPdfLocation(null), isNull);
    });
  });

  group('readScannedFile', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('doc_scan_test'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('reads a plain path and a file:// URI', () async {
      final file = File('${dir.path}/page.bin')..writeAsBytesSync([1, 2, 3]);
      expect(await readScannedFile(file.path), [1, 2, 3]);
      expect(await readScannedFile(file.uri.toString()), [1, 2, 3]);
    });

    test('returns null for content:// and missing files', () async {
      expect(await readScannedFile('content://media/1'), isNull);
      expect(await readScannedFile('${dir.path}/gone.bin'), isNull);
    });
  });

  group('scanResultToPdf', () {
    Future<Uint8List?> constReader(Uint8List? bytes) async => bytes;

    test('assembles images into a PDF', () async {
      final pdf = await scanResultToPdf(
        getImages: () async => {'images': ['a', 'b']},
        getPdf: () async => null,
        readFile: (_) => constReader(_png),
      );
      expect(pdf, isNotNull);
      expect(String.fromCharCodes(pdf!.take(5)), '%PDF-');
    });

    test('falls back to the scanner PDF when no images are readable',
        () async {
      final pdfBytes = Uint8List.fromList('%PDF-fake'.codeUnits);
      final pdf = await scanResultToPdf(
        getImages: () async => const <String>[],
        getPdf: () async => {'pdfUri': 'scan.pdf'},
        readFile: (loc) => constReader(loc == 'scan.pdf' ? pdfBytes : null),
      );
      expect(pdf, pdfBytes);
    });

    test('falls back to the PDF route when getImages throws', () async {
      final pdfBytes = Uint8List.fromList([37, 80, 68, 70]);
      final pdf = await scanResultToPdf(
        getImages: () async => throw StateError('scanner blew up'),
        getPdf: () async => 'scan.pdf',
        readFile: (_) => constReader(pdfBytes),
      );
      expect(pdf, pdfBytes);
    });

    test('is null when neither route yields anything', () async {
      final pdf = await scanResultToPdf(
        getImages: () async => null,
        getPdf: () async => null,
        readFile: (_) => constReader(null),
      );
      expect(pdf, isNull);
    });
  });
}
