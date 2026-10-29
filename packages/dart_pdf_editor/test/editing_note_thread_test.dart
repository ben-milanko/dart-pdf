// A note's comment thread on the page: Acrobat (and this editor) stack each
// reply on its note's /Rect and the page never paints replies, so a tap on
// the note must select the note - not the invisible reply on top - and the
// properties panel shows the whole conversation under it.

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  /// A note on page 0 with [replies] stacked on it, each replying to the
  /// previous one's root (the note).
  PdfEditingController noteWithReplies(List<String> replies) {
    final editing = PdfEditingController(buildMultiPagePdf(1))
      ..preferences.author = 'Jake'
      ..addNote(0, 100, 700, 'The initial contact should be network control');
    for (final reply in replies) {
      final note =
          editing.document.page(0).annotations.firstWhere((a) => !a.isReply);
      editing.replyToAnnotation(0, note, reply);
    }
    return editing;
  }

  group('on-page hit test', () {
    test('a tap on a note with stacked replies selects the note', () {
      final editing = noteWithReplies(['Agreed', 'Also update the ICP']);
      addTearDown(editing.dispose);
      final annotations = editing.document.page(0).annotations;
      final note = annotations.firstWhere((a) => !a.isReply);
      // the replies sit exactly on the note, later in /Annots (on top)
      expect(annotations.where((a) => a.isReply), hasLength(2));
      for (final reply in annotations.where((a) => a.isReply)) {
        expect(reply.rect.left, note.rect.left);
        expect(reply.rect.top, note.rect.top);
      }

      final center = (
        (note.rect.left + note.rect.right) / 2,
        (note.rect.bottom + note.rect.top) / 2,
      );
      expect(editing.selectAnnotationAt(0, center.$1, center.$2), isTrue);
      expect(editing.selectedAnnotationSlots, hasLength(1));
      expect(editing.selectedAnnotation?.isReply, isFalse);
      expect(editing.selectedAnnotation?.contents,
          'The initial contact should be network control');
    });

    test('a rubber band leaves the replies out of the selection', () {
      final editing = noteWithReplies(['Agreed']);
      addTearDown(editing.dispose);
      expect(editing.selectAnnotationsIn(0, const PdfRect(0, 0, 612, 792)), 1);
      expect(editing.selectedAnnotation?.isReply, isFalse);
    });
  });

  group('properties panel thread', () {
    Future<void> pumpPanel(
        WidgetTester tester, PdfEditingController editing) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Row(children: [
            const Expanded(child: SizedBox()),
            PdfAnnotationPropertiesPanel(controller: editing, width: 300),
          ]),
        ),
      ));
      await tester.pump();
    }

    int noteSlot(PdfEditingController editing) => editing.document
        .page(0)
        .annotations
        .indexWhere((a) => a.subtype == 'Text' && !a.isReply);

    testWidgets('lists every reply under the selected note', (tester) async {
      final editing = noteWithReplies(['Agreed', 'Also update the ICP']);
      addTearDown(editing.dispose);
      await pumpPanel(tester, editing);
      editing.selectAnnotation(0, noteSlot(editing));
      await tester.pump();

      expect(find.text('Comments'), findsOneWidget);
      expect(find.byKey(const ValueKey('pdf-prop-reply-0')), findsOneWidget);
      expect(find.byKey(const ValueKey('pdf-prop-reply-1')), findsOneWidget);
      expect(find.text('Agreed'), findsOneWidget);
      expect(find.text('Also update the ICP'), findsOneWidget);
      // the author rides each reply's header
      for (final row in ['pdf-prop-reply-0', 'pdf-prop-reply-1']) {
        expect(
            find.descendant(
                of: find.byKey(ValueKey(row)),
                matching: find.textContaining('Jake')),
            findsOneWidget);
      }
    });

    testWidgets('a reply typed in the panel joins the thread', (tester) async {
      final editing = noteWithReplies(const []);
      addTearDown(editing.dispose);
      await pumpPanel(tester, editing);
      editing.selectAnnotation(0, noteSlot(editing));
      await tester.pump();

      expect(find.byKey(const ValueKey('pdf-prop-reply-0')), findsNothing);
      final send = find.byKey(const ValueKey('pdf-prop-reply-send'));
      expect(tester.widget<IconButton>(send).onPressed, isNull);

      await tester.enterText(
          find.byKey(const ValueKey('pdf-prop-reply-field')), 'Looks fine');
      await tester.pump();
      await tester.tap(send);
      await tester.pump();

      final reply =
          editing.document.page(0).annotations.singleWhere((a) => a.isReply);
      expect(reply.contents, 'Looks fine');
      expect(reply.author, 'Jake');
      // the note stays selected, the reply shows, and the field is clear
      expect(editing.selectedAnnotation?.isReply, isFalse);
      expect(find.text('Looks fine'), findsOneWidget);
      expect(
          tester
              .widget<TextField>(
                  find.byKey(const ValueKey('pdf-prop-reply-field')))
              .controller!
              .text,
          isEmpty);
    });

    testWidgets('no thread section for a form widget', (tester) async {
      final editing = PdfEditingController(buildAcroFormPdf());
      addTearDown(editing.dispose);
      await pumpPanel(tester, editing);
      editing.selectAnnotation(0, 0);
      await tester.pump();
      expect(find.text('Comments'), findsNothing);
    });
  });
}
