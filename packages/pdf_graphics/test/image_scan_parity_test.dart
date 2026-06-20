// The image-scan interpreter mode (`scanImagesOnly: true`) must discover
// exactly the same image draw requests as a full interpretation — otherwise a
// rendered page would be missing (or needlessly decode) an image. This walks
// the checked-in corpora and, page by page, asserts the two passes collect the
// identical set of image streams.
//
//   cd packages/pdf_graphics && fvm dart test test/image_scan_parity_test.dart
import 'dart:io';
import 'dart:typed_data';

import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_graphics/pdf_graphics.dart';
import 'package:test/test.dart';

/// Records the image requests an interpreter emits, keyed so the same image
/// maps to the same key across two passes: XObject images by stream identity
/// (the xref cache hands back the same instance), inline images by content.
class _ImageRecorder implements PdfDevice {
  final List<String> keys = [];

  @override
  void drawImage(PdfImageRequest request) {
    if (request.isInline) {
      final bytes = request.stream.rawBytes;
      var sum = 0;
      for (final b in bytes) {
        sum = (sum + b) % 0x7fffffff;
      }
      keys.add('inline:${request.stream.dictionary}:${bytes.length}:$sum');
    } else {
      keys.add('xobj:${identityHashCode(request.stream)}');
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

Set<String> _collect(PdfDocument doc, int pageIndex, {required bool scan}) {
  final page = doc.page(pageIndex);
  final rec = _ImageRecorder();
  PdfInterpreter(cos: doc.cos, device: rec, scanImagesOnly: scan)
    ..drawPage(page)
    ..drawAnnotations(page);
  return rec.keys.toSet();
}

void main() {
  for (final corpus in ['../../test_corpora/ghent', '../../test_corpora/pdfjs']) {
    final dir = Directory(corpus);
    if (!dir.existsSync()) continue;
    final files = dir
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.toLowerCase().endsWith('.pdf'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));

    group('image-scan parity: ${corpus.split('/').last}', () {
      for (final file in files) {
        test(file.path.split('/').last, () {
          final Uint8List bytes;
          final PdfDocument doc;
          try {
            bytes = file.readAsBytesSync();
            doc = PdfDocument.open(bytes);
          } catch (_) {
            return; // unopenable fixture — not this test's concern
          }
          final int pages;
          try {
            pages = doc.pageCount;
          } catch (_) {
            return;
          }
          final limit = pages < 10 ? pages : 10;
          for (var i = 0; i < limit; i++) {
            Set<String> full, scan;
            try {
              full = _collect(doc, i, scan: false);
            } catch (_) {
              continue; // a page the full interpreter can't even walk
            }
            scan = _collect(doc, i, scan: true);
            // The scan must never MISS an image the full pass draws. (It may,
            // in principle, over-collect; that only wastes a decode — so the
            // strong check is full ⊆ scan, and we also assert equality to catch
            // any divergence early.)
            expect(scan.containsAll(full), isTrue,
                reason: 'page $i: scan missed ${full.difference(scan)}');
            expect(scan, equals(full),
                reason: 'page $i: scan/full image sets differ');
          }
        });
      }
    });
  }
}
