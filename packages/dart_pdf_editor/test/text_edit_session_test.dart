// The inline text-editing session without a widget: what it opens with, how
// restyling changes its runs, and what committing decides to write.

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:material_ui/material_ui.dart';

const _rect = PdfRect(100, 600, 360, 660);
const _black = PdfTextEditStyle(
    font: PdfStandardFont.helvetica, size: 14, color: Color(0xFF000000));

PdfTextEditSession _existing(String text,
        {PdfTextEditStyle style = _black, List<PdfFreeTextRun>? runs}) =>
    PdfTextEditSession(
        target: const PdfExistingTextBox(0, (0, 0)),
        rect: _rect,
        style: style,
        text: text,
        runs: runs);

PdfTextEditSession _fresh(PdfTextEditTarget target, String text) =>
    PdfTextEditSession(target: target, rect: _rect, style: _black, text: text);

void _select(PdfTextEditSession session, int start, int end) =>
    session.buffer.selection =
        TextSelection(baseOffset: start, extentOffset: end);

void main() {
  group('commit decision for an existing box', () {
    test('untouched writes nothing; edited text sets it', () {
      final session = _existing('Hello');
      expect(session.decide(savedText: 'Hello'), const PdfTextEditNoChange());
      session.buffer.text = 'Hello there  ';
      expect(session.decide(savedText: 'Hello'),
          const PdfTextEditSetText('Hello there'));
    });

    test('restyling the caret only commits just the fields that changed', () {
      final session = _existing('Hello');
      session.restyle(color: 0xFF0000);
      expect(session.style.color, const Color(0xFFFF0000));
      expect(session.buffer.hasRichStyles, isFalse,
          reason: 'a uniform box stays uniform');
      expect(session.decide(savedText: 'Hello'),
          const PdfTextEditRestyle('Hello', color: 0xFF0000));

      session.restyle(size: 20, underline: true);
      expect(
          session.decide(savedText: 'Hello'),
          const PdfTextEditRestyle('Hello',
              color: 0xFF0000, size: 20, underline: true));
    });

    test('restyling back to the open style is no restyle', () {
      final session = _existing('Hello')
        ..restyle(font: PdfStandardFont.times)
        ..restyle(font: PdfStandardFont.helvetica);
      expect(session.decide(savedText: 'Hello'), const PdfTextEditNoChange());
    });

    test('restyling a selection commits rich runs', () {
      final session = _existing('Hello world');
      _select(session, 6, 11);
      session.restyle(font: PdfStandardFont.helveticaBold);
      final commit = session.decide(savedText: 'Hello world');
      expect(commit, isA<PdfTextEditSetRichText>());
      final runs = (commit as PdfTextEditSetRichText).runs;
      expect([
        for (final r in runs) (r.text, r.font)
      ], [
        ('Hello ', PdfStandardFont.helvetica),
        ('world', PdfStandardFont.helveticaBold),
      ]);
    });

    test('a caret restyle of a mixed box restyles every run', () {
      final session = _existing('ab', runs: const [
        PdfFreeTextRun('a', fontSize: 14),
        PdfFreeTextRun('b', fontSize: 14, color: 0x00FF00),
      ]);
      session.restyle(size: 30);
      final runs = (session.decide() as PdfTextEditSetRichText).runs;
      expect([
        for (final r in runs) (r.text, r.fontSize, r.color)
      ], [
        ('a', 30.0, 0x000000),
        ('b', 30.0, 0x00FF00),
      ]);
      expect(session.style.size, 30, reason: 'what is typed next follows');
    });
  });

  group('commit decision for a new annotation', () {
    test('empty adds nothing', () {
      expect(_fresh(const PdfNewTextBox(0), '  \n').decide(),
          const PdfTextEditNoChange());
    });

    test('a box adds its trimmed text, with runs only when styled', () {
      final plain =
          _fresh(const PdfNewTextBox(2), 'Note \n').decide() as PdfTextEditAdd;
      expect((plain.target.page, plain.rect, plain.text, plain.runs),
          (2, _rect, 'Note', null));

      final styled = _fresh(const PdfNewTextBox(2), 'Note');
      _select(styled, 0, 2);
      styled.restyle(underline: true);
      final rich = styled.decide() as PdfTextEditAdd;
      expect([for (final r in rich.runs!) (r.text, r.underline)],
          [('No', true), ('te', false)]);
    });

    test('callouts add as their target, without runs', () {
      final callout = _fresh(const PdfNewCallout(0, (10, 20)), 'Look');
      _select(callout, 0, 4);
      callout.restyle(color: 0x0000FF);
      final add = callout.decide() as PdfTextEditAdd;
      expect(add.target, isA<PdfNewCallout>());
      expect(add.runs, isNull);

      const region = PdfRect(10, 10, 50, 50);
      final cloud = _fresh(const PdfNewCloudCallout(0, region), 'Here').decide()
          as PdfTextEditAdd;
      expect((cloud.target as PdfNewCloudCallout).region, region);
    });
  });

  group('box layout', () {
    test('a new box follows the creation defaults, an existing one does not',
        () {
      final fresh = _fresh(const PdfNewTextBox(0), 'x');
      var repaints = 0;
      fresh.addListener(() => repaints++);
      fresh.adoptBoxDefaults(
          align: PdfTextAlign.center,
          verticalAlign: PdfTextVerticalAlign.bottom,
          lineSpacing: 2,
          charSpacing: 1,
          opacity: 0.5,
          underline: true);
      expect(fresh.layout.align, PdfTextAlign.center);
      expect(fresh.layout.opacity, 0.5);
      expect(fresh.style.underline, isTrue);
      expect(repaints, 1);
      fresh.adoptBoxDefaults(
          align: PdfTextAlign.center,
          verticalAlign: PdfTextVerticalAlign.bottom,
          lineSpacing: 2,
          charSpacing: 1,
          opacity: 0.5,
          underline: true);
      expect(repaints, 1, reason: 'nothing changed');

      final existing = _existing('x');
      existing.adoptBoxDefaults(
          align: PdfTextAlign.center,
          verticalAlign: PdfTextVerticalAlign.bottom,
          lineSpacing: 2,
          charSpacing: 1,
          opacity: 0.5,
          underline: true);
      expect(existing.layout, const PdfTextEditLayout());
      existing.followAppearance(opacity: 0.25);
      expect(existing.layout.opacity, 0.25);
    });
  });

  group('style toggles', () {
    test('bold toggles from the selection, else the base-14 face', () {
      final session = _existing('Hi');
      expect(session.toggledFace(italic: false), PdfStandardFont.helveticaBold);
      _select(session, 0, 2);
      session.restyle(font: PdfStandardFont.times);
      expect(session.toggledFace(italic: true), PdfStandardFont.timesItalic);
    });

    test('retyping an empty box resets its typing style', () {
      final session = _fresh(const PdfNewTextBox(0), '');
      session.retypeEmpty(font: PdfStandardFont.courierBold);
      expect(session.style.font, PdfStandardFont.courierBold);
      expect(session.standardFace, PdfStandardFont.courierBold);
      session.retypeEmpty(underline: true);
      expect((session.style.font, session.style.underline),
          (PdfStandardFont.courierBold, true));
    });
  });

  group('rich runs follow their characters', () {
    test('typing before a styled run shifts it', () {
      final session = _existing('ab');
      _select(session, 1, 2);
      session.restyle(font: PdfStandardFont.helveticaBold);
      session.buffer.value = const TextEditingValue(text: 'Xab');
      final runs = session.buffer.toPdfRuns();
      expect([
        for (final r in runs) (r.text, r.font)
      ], [
        ('Xa', PdfStandardFont.helvetica),
        ('b', PdfStandardFont.helveticaBold),
      ]);
    });
  });

  group('focus holds', () {
    test('holds count, release once, and carry into a reopened editor', () {
      final first = _existing('x');
      final a = first.holdCommit();
      final b = first.holdCommit();
      a
        ..release()
        ..release();
      expect(first.isCommitHeld, isTrue);
      final reopened = PdfTextEditSession(
          target: first.target, rect: _rect, style: _black, holdsFrom: first);
      expect(reopened.isCommitHeld, isTrue);
      b.release();
      expect(reopened.isCommitHeld, isFalse);

      final keep = reopened.keepFocused();
      expect(reopened.keepsFocus, isTrue);
      reopened.close();
      expect(reopened.keepsFocus, isFalse, reason: 'a closed editor holds no');
      keep.release();
    });
  });

  group('through the controller', () {
    test('an existing box opens with its style and commits a caret restyle',
        () {
      final editing = PdfEditingController(buildMultiPagePdf(1))
        ..addFreeText(0, _rect, 'Hello');
      expect(editing.selectAnnotation(0, 0), isTrue);
      final session = editing.beginTextEdit(
          PdfExistingTextBox(0, editing.selectedAnnotationSlot),
          rect: _rect);
      expect(editing.textEditSession, same(session));
      expect(editing.isEditingText, isTrue);
      expect(session.buffer.text, 'Hello');
      expect(session.openStyle.size, editing.preferences.fontSize);

      expect(editing.restyleEditingTextSelection(color: 0x0000FF), isTrue);
      final commit = session.decide(savedText: editing.selectedText);
      expect(commit, const PdfTextEditRestyle('Hello', color: 0x0000FF));
      editing.endTextEdit(session);
      expect(editing.isEditingText, isFalse);
      expect(editing.restyleEditingTextSelection(color: 0), isFalse);

      editing.applyTextEditCommit(commit);
      final annotation = editing.document.page(0).annotations.single;
      expect(annotation.contents, 'Hello');
      expect(annotation.behavior.style.color, 0x0000FF);
    });

    test('a new box opens on the creation defaults and adds itself', () {
      final editing = PdfEditingController(buildMultiPagePdf(1));
      editing.preferences.textAlign = PdfTextAlign.right;
      final session =
          editing.beginTextEdit(const PdfNewTextBox(0), rect: _rect);
      expect(session.layout.align, PdfTextAlign.right);
      session.buffer.text = 'New';
      final commit = session.decide();
      editing
        ..endTextEdit(session)
        ..applyTextEditCommit(commit);
      final annotation = editing.document.page(0).annotations.single;
      expect(annotation.subtype, 'FreeText');
      expect(annotation.contents, 'New');
    });
  });
}
