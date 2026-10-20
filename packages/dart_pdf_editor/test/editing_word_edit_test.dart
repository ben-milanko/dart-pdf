import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Many generators draw a page a glyph at a time - one show operator per
// letter, word gaps by positioning. Editing must still work on words: a tap
// on one letter edits its word, and a selected word or phrase is rewritten
// across the runs it spans.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  // "Hello world" at 12pt from (36, 720): each glyph advances 6pt, so the
  // letters of "Hello" sit at x 36..66 and "world" at 72..102.
  PdfEditingController glyphRuns() {
    final editing = PdfEditingController(buildGlyphRunsPdf('Hello world'));
    addTearDown(editing.dispose);
    return editing;
  }

  String pageText(PdfEditingController editing) => [
        for (final element in editing.elementsOn(0).elements)
          if (element.kind == PdfElementKind.text) element.text ?? '',
      ].join();

  group('content tool', () {
    test('a tapped letter edits its whole word', () {
      final editing = glyphRuns();
      expect(editing.selectElementAt(0, 45, 723), isTrue);
      expect(editing.selectedElement!.text, 'e');
      expect(editing.selectedElementWord.map((e) => e.text).join(), 'Hello');
      expect(editing.selectedElementEditText, 'Hello');
      final word = editing.selectedElementWordBounds!;
      expect(word.left, closeTo(36, 0.5));
      expect(word.right, closeTo(66, 0.5));

      expect(editing.replaceSelectedElementText('Howdy'), greaterThan(0));
      expect(pageText(editing), 'Howdyworld');
      expect(editing.canUndo, isTrue);
    });

    test('the word stops at a word gap', () {
      final editing = glyphRuns();
      expect(editing.selectElementAt(0, 87, 723), isTrue);
      expect(editing.selectedElementEditText, 'world');
    });

    test('a single-run word needs no word box', () {
      final editing =
          PdfEditingController(buildTextLinesPdf(const ['Hello world']));
      addTearDown(editing.dispose);
      expect(editing.selectElementAt(0, 40, 723), isTrue);
      expect(editing.selectedElementEditText, 'Hello world');
      expect(editing.selectedElementWordBounds, isNull);
    });
  });

  group('viewer selection', () {
    test('a selected word split across runs resolves to its slices', () {
      final editing = glyphRuns();
      final parts = editing.textPartsForSelection(
          0, const [PdfRect(36, 716, 66, 730)], 'Hello');
      expect(parts, isNotNull);
      expect(parts!.map((p) => p.find).toList(), ['H', 'e', 'l', 'l', 'o']);

      expect(editing.replaceTextInParts(0, parts, 'Bye'), greaterThan(0));
      expect(pageText(editing), 'Byeworld');
    });

    test('a phrase matches across the positioned word gap', () {
      final editing = glyphRuns();
      final parts = editing.textPartsForSelection(
          0, const [PdfRect(36, 716, 102, 730)], 'Hello world');
      expect(parts, hasLength(10));
      expect(editing.replaceTextInParts(0, parts!, 'Hi there'), greaterThan(0));
      expect(pageText(editing), 'Hi there');
    });

    test('a styled replacement still clears the rest of the word', () {
      // the styled rewrite adds colour operators, shifting every later run
      final editing = glyphRuns();
      final parts = editing.textPartsForSelection(
          0, const [PdfRect(72, 716, 102, 730)], 'world');
      expect(
          editing.replaceTextInParts(0, parts!, 'World',
              style: const PdfTextStyle(color: 0xCC0000)),
          greaterThan(1));
      expect(pageText(editing), 'HelloWorld');
    });

    test('part of a word edits just those letters', () {
      final editing = glyphRuns();
      final parts = editing.textPartsForSelection(
          0, const [PdfRect(72, 716, 90, 730)], 'wor');
      expect(parts!.map((p) => p.find).join(), 'wor');
      editing.replaceTextInParts(0, parts, 'WOR');
      expect(pageText(editing), 'HelloWORld');
    });

    test('a selection that does not match the runs is refused', () {
      final editing = glyphRuns();
      expect(
          editing.textPartsForSelection(
              0, const [PdfRect(36, 716, 66, 730)], 'Help'),
          isNull);
    });

    test('search Replace rewrites a hit split across runs', () {
      final editing = glyphRuns();
      expect(
          editing.replaceMatchText(
              0, const [PdfRect(72, 716, 102, 730)], 'world', 'there'),
          greaterThan(0));
      expect(pageText(editing), 'Hellothere');
    });
  });
}
