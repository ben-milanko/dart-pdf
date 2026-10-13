import 'package:dart_pdf_editor/src/editing/editing_text_menu.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  group('pdfTextMenuAnchorsClearOf', () {
    const anchors = TextSelectionToolbarAnchors(
      primaryAnchor: Offset(200, 300),
      secondaryAnchor: Offset(200, 400),
    );

    test('no chip leaves the anchors alone', () {
      expect(pdfTextMenuAnchorsClearOf(anchors, null), same(anchors));
      expect(pdfTextMenuAnchorsClearOf(anchors, Rect.zero), same(anchors));
    });

    test('a chip above the selection lifts the menu over it', () {
      final moved = pdfTextMenuAnchorsClearOf(
          anchors, const Rect.fromLTRB(100, 250, 300, 290));
      expect(moved.primaryAnchor, const Offset(200, 250));
      expect(moved.secondaryAnchor, const Offset(200, 400));
    });

    test('a chip below the selection drops the flipped menu under it', () {
      final moved = pdfTextMenuAnchorsClearOf(
          anchors, const Rect.fromLTRB(100, 410, 300, 450));
      expect(moved.primaryAnchor, const Offset(200, 300));
      expect(moved.secondaryAnchor, const Offset(200, 450));
    });

    test('a chip outside the menu band leaves the anchors alone', () {
      expect(
          pdfTextMenuAnchorsClearOf(
              anchors, const Rect.fromLTRB(100, 100, 300, 140)),
          same(anchors));
      expect(
          pdfTextMenuAnchorsClearOf(
              anchors, const Rect.fromLTRB(100, 600, 300, 640)),
          same(anchors));
    });
  });
}
