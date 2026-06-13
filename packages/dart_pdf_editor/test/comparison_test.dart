import 'dart:typed_data';

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';

import 'render_smoke_test.dart' show loadSystemFonts;

/// A one-page 612×792 PDF drawing each `(x, y, text)` line at 18pt
/// Helvetica.
Uint8List _textPdf(List<(int, int, String)> lines) {
  final content = lines
      .map((l) => 'BT /F1 18 Tf ${l.$1} ${l.$2} Td (${l.$3}) Tj ET')
      .join('\n');
  final objects = <String>[
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R '
        '/Resources << /Font << /F1 5 0 R >> >> >>',
    '<< /Length ${content.length} >>\nstream\n$content\nendstream',
    '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
  ];
  final buffer = StringBuffer('%PDF-1.4\n');
  final offsets = <int>[];
  for (var i = 0; i < objects.length; i++) {
    offsets.add(buffer.length);
    buffer.write('${i + 1} 0 obj\n${objects[i]}\nendobj\n');
  }
  final xrefOffset = buffer.length;
  buffer
    ..write('xref\n0 ${objects.length + 1}\n')
    ..write('0000000000 65535 f \n');
  for (final offset in offsets) {
    buffer.write('${offset.toString().padLeft(10, '0')} 00000 n \n');
  }
  buffer
    ..write('trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\n')
    ..write('startxref\n$xrefOffset\n%%EOF\n');
  return ascii(buffer.toString());
}

void main() {
  group('comparePixels', () {
    test('classifies removed, added, changed and unchanged pixels', () {
      // Four pixels in a 4×1 row: unchanged-black, removed, added, changed.
      final before = Uint8List.fromList([
        0, 0, 0, 255, // unchanged ink
        0, 0, 0, 255, // removed (after is white)
        255, 255, 255, 255, // added (after is ink)
        0, 0, 0, 255, // changed (after is red)
      ]);
      final after = Uint8List.fromList([
        0, 0, 0, 255,
        255, 255, 255, 255,
        0, 0, 0, 255,
        255, 0, 0, 255,
      ]);
      final diff = PdfPageComparison.comparePixels(before, after,
          width: 4, height: 1, style: PdfDiffStyle.beforeAfter);

      expect(diff.differingPixels, 3); // the unchanged pixel is not counted
      expect(diff.differenceFraction, closeTo(0.75, 1e-9));

      final map = diff.debugDiffMap;
      (int, int, int) px(int i) => (map[i * 4], map[i * 4 + 1], map[i * 4 + 2]);
      // unchanged ink → dimmed grey (not dropped, not colored)
      expect(px(0), (204, 204, 204));
      // removed → red
      expect(px(1), (0xE5, 0x39, 0x35));
      // added → green
      expect(px(2), (0x2E, 0x7D, 0x32));
      // changed in place → amber
      expect(px(3), (0xF5, 0x7C, 0x00));
    });

    test('unchanged content is dimmed, not dropped', () {
      final px = Uint8List.fromList([0, 0, 0, 255]); // black, both sides
      final diff = PdfPageComparison.comparePixels(px, px,
          width: 1, height: 1, style: PdfDiffStyle.beforeAfter);
      expect(diff.differingPixels, 0);
      expect(diff.hasChanges, isFalse);
    });

    test('redOnWhite matches the PDF.js diff convention', () {
      final before = Uint8List.fromList([0, 0, 0, 255, 0, 0, 0, 255]);
      final after = Uint8List.fromList([0, 0, 0, 255, 255, 255, 255, 255]);
      final diff = PdfPageComparison.comparePixels(before, after,
          width: 2, height: 1, style: PdfDiffStyle.redOnWhite);
      expect(diff.differingPixels, 1);
    });

    test('clusters changed pixels into regions', () {
      const w = 48, h = 48;
      final before = Uint8List(w * h * 4);
      final after = Uint8List(w * h * 4);
      for (var i = 0; i < before.length; i++) {
        before[i] = 255;
        after[i] = 255;
      }
      // a single 12×12 changed block at (24,24)
      for (var y = 24; y < 36; y++) {
        for (var x = 24; x < 36; x++) {
          final i = (y * w + x) * 4;
          after[i] = 0;
          after[i + 1] = 0;
          after[i + 2] = 0;
        }
      }
      final diff = PdfPageComparison.comparePixels(before, after,
          width: w, height: h);
      final regions = diff.changeRegions();
      expect(regions, hasLength(1));
      expect(regions.single.contains(const Offset(30, 30)), isTrue);
      // the top-left quadrant (unchanged) is not covered
      expect(regions.single.contains(const Offset(5, 5)), isFalse);
    });
  });

  group('comparePages (rendered)', () {
    testWidgets('flags the changed region and not the unchanged one',
        (tester) async {
      await tester.runAsync(() async {
        await loadSystemFonts();
        // A header near the top is identical; B adds a footer low down.
        final a = PdfDocument.open(_textPdf([(72, 720, 'Header')]));
        final b = PdfDocument.open(
            _textPdf([(72, 720, 'Header'), (72, 100, 'Footer note')]));

        final diff = await PdfPageComparison.comparePages(a.page(0), b.page(0),
            pixelRatio: 1.5);
        expect(diff.hasChanges, isTrue);
        expect(diff.regionsAfter, isNotEmpty);

        // Every change sits low on the page (the footer at y≈100), so no
        // region reaches up to the unchanged header at y≈720.
        for (final region in diff.regionsAfter) {
          expect(region.top, lessThan(400),
              reason: 'changes should be confined to the footer area');
        }
      });
    });

    testWidgets('identical pages report no changes', (tester) async {
      await tester.runAsync(() async {
        await loadSystemFonts();
        final a = PdfDocument.open(_textPdf([(72, 720, 'Stable text')]));
        final diff = await PdfPageComparison.comparePages(a.page(0), a.page(0),
            pixelRatio: 1.5);
        expect(diff.hasChanges, isFalse);
        expect(diff.differenceFraction, 0);
      });
    });
  });

  group('PdfComparisonController', () {
    test('lists the text change between two documents', () {
      final controller = PdfComparisonController(
        before: PdfDocument.open(_textPdf([(72, 720, 'the quick brown fox')])),
        after: PdfDocument.open(_textPdf([(72, 720, 'the quick red fox')])),
      )..build();

      expect(controller.hasChanges, isTrue);
      final replaced = controller.changes
          .where((c) => c.kind == PdfDiffChangeKind.replaced)
          .toList();
      expect(replaced, isNotEmpty);
      expect(replaced.first.label, contains('brown'));
      expect(replaced.first.label, contains('red'));
      expect(controller.currentChange, 0);
    });

    test('identical documents have no changes', () {
      final controller = PdfComparisonController(
        before: PdfDocument.open(_textPdf([(72, 720, 'same')])),
        after: PdfDocument.open(_textPdf([(72, 720, 'same')])),
      )..build();
      expect(controller.hasChanges, isFalse);
      expect(controller.currentChange, -1);
    });

    test('pairs an appended page as inserted', () {
      final controller = PdfComparisonController(
        before: PdfDocument.open(buildMultiPagePdf(2)),
        after: PdfDocument.open(buildMultiPagePdf(3)),
      )..build();

      expect(controller.pairs, hasLength(3));
      expect(controller.pairs[2].kind, PdfPagePairKind.inserted);
      final inserted = controller.changes
          .where((c) => c.kind == PdfDiffChangeKind.pageInserted)
          .toList();
      expect(inserted, hasLength(1));
      expect(inserted.single.afterPage, 2);
    });

    test('pairs a removed trailing page as removed', () {
      final controller = PdfComparisonController(
        before: PdfDocument.open(buildMultiPagePdf(3)),
        after: PdfDocument.open(buildMultiPagePdf(2)),
      )..build();

      expect(controller.pairs[2].kind, PdfPagePairKind.removed);
      final removed = controller.changes
          .where((c) => c.kind == PdfDiffChangeKind.pageRemoved)
          .toList();
      expect(removed, hasLength(1));
      expect(removed.single.beforePage, 2);
    });

    test('navigation steps and wraps', () {
      final controller = PdfComparisonController(
        before: PdfDocument.open(_textPdf([(72, 720, 'one two three')])),
        after: PdfDocument.open(_textPdf([(72, 720, 'ONE two THREE')])),
      )..build();
      expect(controller.changes.length, greaterThanOrEqualTo(2));

      controller.goToChange(0);
      controller.nextChange();
      expect(controller.currentChange, 1);
      controller.previousChange();
      expect(controller.currentChange, 0);
      controller.previousChange();
      expect(controller.currentChange, controller.changes.length - 1);
    });
  });
}
