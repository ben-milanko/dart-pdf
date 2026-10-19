import 'dart:typed_data';
import 'dart:ui';

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _region = PdfRect(100, 200, 220, 260);
const _marks = [
  (130.0, 215.0, 0xFF0000),
  (190.0, 215.0, 0x00FF00),
  (130.0, 245.0, 0x0000FF),
  (190.0, 245.0, 0xFFFF00),
];

Uint8List _source(int rotation) {
  final editor = PdfEditor(PdfDocument.open(buildMultiPagePdf(1)));
  editor.stampPage(0, (stamp) {
    for (final (x, y, color) in _marks) {
      stamp.rect(x - 30, y - 15, 60, 30, fillColor: color);
    }
  });
  editor.rotatePages([0], rotation);
  return editor.save();
}

PdfPageGeometry _geometry(PdfPage page) => PdfPageGeometry(
      cropBox: page.cropBox,
      rotation: page.rotation,
      viewSize: page.rotation == 90 || page.rotation == 270
          ? Size(page.cropBox.height, page.cropBox.width)
          : Size(page.cropBox.width, page.cropBox.height),
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final sourceRotation in [0, 90, 180, 270]) {
    for (final targetRotation in [0, 90, 180, 270]) {
      testWidgets(
          'snapshot $sourceRotation° → $targetRotation° keeps displayed size and colors',
          (tester) async {
        await tester.runAsync(() async {
          final clipboard = PdfSnapshotClipboard();
          final source = PdfEditingController(_source(sourceRotation),
              snapshotClipboard: clipboard);
          final sourceGeometry = _geometry(source.document.page(0));
          final sourceRect = sourceGeometry.toViewRect(_region);
          source.copyVectorSnapshot(0, _region);
          source.dispose(); // The captured page need not remain open.

          final targetEditor = PdfEditor(PdfDocument.open(buildMultiPagePdf(1)))
            ..rotatePages([0], targetRotation);
          final target = PdfEditingController(targetEditor.save(),
              snapshotClipboard: clipboard);
          addTearDown(target.dispose);
          expect(target.pasteSnapshot(0, at: (300, 400)), isTrue);
          target.undo();
          expect(target.document.page(0).annotations, isEmpty);
          target.redo();

          // Reopen the saved revision before checking the actual artwork.
          final reopened = PdfDocument.open(target.bytes);
          final page = reopened.page(0);
          final geometry = _geometry(page);
          final rect = geometry.toViewRect(page.annotations.single.rect);
          expect(rect.width, closeTo(sourceRect.width, 1e-6));
          expect(rect.height, closeTo(sourceRect.height, 1e-6));
          expect(rect.center, geometry.toViewOffset(300, 400));

          final image = await PdfPageRenderer.renderImage(page);
          final pixels = (await image.toByteData())!;
          try {
            for (final (x, y, color) in _marks) {
              final inSource = sourceGeometry.toViewOffset(x, y);
              final at = rect.topLeft + (inSource - sourceRect.topLeft);
              final index = (at.dy.round() * image.width + at.dx.round()) * 4;
              expect(
                [for (var c = 0; c < 3; c++) pixels.getUint8(index + c)],
                [(color >> 16) & 255, (color >> 8) & 255, color & 255],
                reason: 'captured mark ($x, $y) must keep its visible position',
              );
            }
          } finally {
            image.dispose();
          }
        });
      });
    }
  }

  for (final rotation in [0, 90, 180, 270]) {
    test('default paste at $rotation° keeps position and cascades down-right',
        () {
      final editing = PdfEditingController(_source(rotation),
          snapshotClipboard: PdfSnapshotClipboard());
      addTearDown(editing.dispose);
      final geometry = _geometry(editing.document.page(0));
      final original = geometry.toViewRect(_region);
      editing.copyVectorSnapshot(0, _region);
      expect(editing.pasteSnapshot(0), isTrue);
      final first =
          geometry.toViewRect(editing.document.page(0).annotations.last.rect);
      expect(first, original);
      expect(editing.pasteSnapshot(0), isTrue);
      final second =
          geometry.toViewRect(editing.document.page(0).annotations.last.rect);
      expect(second, first.shift(const Offset(12, 12)));
    });
  }
}
