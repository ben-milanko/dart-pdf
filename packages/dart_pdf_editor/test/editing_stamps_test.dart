import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('PdfCustomStamp', () {
    test('round-trips through JSON; junk decodes to null', () {
      const stamp = PdfCustomStamp(text: 'APPROVED', color: 0xC03030);
      expect(PdfCustomStamp.decode(stamp.encode()), stamp);
      expect(PdfCustomStamp.decode('not json'), isNull);
      expect(PdfCustomStamp.decode('{"text": "X"}'), isNull);
    });

    test('persists through PdfEditingPreferences', () async {
      SharedPreferences.setMockInitialValues({});
      final a = PdfEditingPreferences();
      await a.ready;
      a.customStamps = const [
        PdfCustomStamp(text: 'APPROVED', color: 0xC03030),
        PdfCustomStamp(text: 'DRAFT', color: 0x1A3E8C),
      ];
      await pumpEventQueue();

      final b = PdfEditingPreferences();
      await b.ready;
      expect(b.customStamps, const [
        PdfCustomStamp(text: 'APPROVED', color: 0xC03030),
        PdfCustomStamp(text: 'DRAFT', color: 0x1A3E8C),
      ]);

      a.customStamps = const [];
      await pumpEventQueue();
      final c = PdfEditingPreferences();
      await c.ready;
      expect(c.customStamps, isEmpty);
    });
  });

  group('custom stamps on the controller', () {
    const approved = PdfCustomStamp(text: 'APPROVED', color: 0x2E7D32);
    const draft = PdfCustomStamp(text: 'DRAFT', color: 0x1A3E8C);

    test('save, remove, and active-stamp bookkeeping', () {
      final editing = PdfEditingController(buildMultiPagePdf(1));
      editing
        ..saveCustomStamp(approved)
        ..saveCustomStamp(draft);
      expect(editing.customStamps, [approved, draft]);

      editing.activeStamp = draft;
      editing.removeCustomStamp(draft);
      expect(editing.customStamps, [approved]);
      // deleting the active stamp falls back to the classic flow
      expect(editing.activeStamp, isNull);
    });

    test('placeStamp centers an auto-sized Stamp annotation', () {
      final editing = PdfEditingController(buildMultiPagePdf(1))
        ..activeStamp = approved;
      expect(editing.placeStamp(0, 300, 400), isTrue);

      final stamp = editing.document.page(0).annotations.single;
      expect(stamp.subtype, 'Stamp');
      expect(stamp.contents, 'APPROVED');
      expect(stamp.color, 0x2E7D32);
      expect(stamp.rect.height, moreOrLessEquals(40));
      expect((stamp.rect.left + stamp.rect.right) / 2, moreOrLessEquals(300));
      expect((stamp.rect.bottom + stamp.rect.top) / 2, moreOrLessEquals(400));
      // wide enough for the caption, not absurdly so
      expect(stamp.rect.width, greaterThan(80));
      expect(stamp.rect.width, lessThan(250));
    });

    test('clamps so the whole stamp stays on the page', () {
      final editing = PdfEditingController(buildMultiPagePdf(1))
        ..activeStamp = approved;
      final box = editing.document.page(0).cropBox;
      expect(editing.placeStamp(0, box.right, box.top), isTrue);

      final stamp = editing.document.page(0).annotations.single;
      expect(stamp.rect.right, lessThanOrEqualTo(box.right + 0.01));
      expect(stamp.rect.top, lessThanOrEqualTo(box.top + 0.01));
    });

    test('without an active stamp nothing happens', () {
      final editing = PdfEditingController(buildMultiPagePdf(1));
      expect(editing.placeStamp(0, 300, 400), isFalse);
      expect(editing.document.page(0).annotations, isEmpty);
      expect(editing.isModified, isFalse);
    });

    test('placeTextStamp drops a default-sized stamp without an active stamp',
        () {
      final editing = PdfEditingController(buildMultiPagePdf(1))
        ..color = const Color(0xFF1565C0);
      expect(editing.placeTextStamp(0, 300, 400, 'REVIEWED'), isTrue);

      final stamp = editing.document.page(0).annotations.single;
      expect(stamp.subtype, 'Stamp');
      expect(stamp.contents, 'REVIEWED');
      // no colour given, so it follows the selected toolbar colour
      expect(stamp.color, 0x1565C0);
      expect(stamp.rect.height, moreOrLessEquals(40));
      expect((stamp.rect.left + stamp.rect.right) / 2, moreOrLessEquals(300));
      expect((stamp.rect.bottom + stamp.rect.top) / 2, moreOrLessEquals(400));
    });
  });

  group('stamp tool in the viewer', () {
    testWidgets('create a stamp in the picker, then tap to place it',
        (tester) async {
      final editing = PdfEditingController(buildMultiPagePdf(1));
      final viewer = PdfViewerController();
      addTearDown(editing.dispose);
      addTearDown(viewer.dispose);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ListenableBuilder(
            listenable: editing,
            builder: (context, _) => PdfViewer(
              initialFit: PdfViewerFit.width,
              document: editing.document,
              controller: viewer,
              editing: editing,
            ),
          ),
          bottomNavigationBar: PdfEditingToolbar(
            controller: editing,
            viewerController: viewer,
          ),
        ),
      ));
      await tester.pump();

      final dockScrollable = find
          .descendant(
              of: find.byType(PdfEditingToolbar),
              matching: find.byType(Scrollable))
          .last;
      final stripScrollable = find
          .descendant(
              of: find.byType(PdfEditingToolbar),
              matching: find.byType(Scrollable))
          .first;
      // the Stamp tool lives in the Insert group's strip
      final insertChip = find.byKey(const ValueKey('pdf-group-insert'));
      await tester.scrollUntilVisible(insertChip, 80,
          scrollable: dockScrollable);
      await tester.tap(insertChip);
      await tester.pump();
      await tester.scrollUntilVisible(find.byTooltip('Stamp'), 100,
          scrollable: stripScrollable);
      await tester.tap(find.byTooltip('Stamp'));
      await tester.pumpAndSettle();
      expect(editing.tool, PdfEditTool.stamp);

      // the picker button only shows while the stamp tool is armed
      await tester.scrollUntilVisible(find.byTooltip('Custom stamps…'), 100,
          scrollable: stripScrollable);
      await tester.tap(find.byTooltip('Custom stamps…'));
      await tester.pumpAndSettle();
      expect(find.byType(PdfStampPickerDialog), findsOneWidget);

      await tester.tap(find.text('New stamp…'));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byKey(const ValueKey('pdf-stamp-text')), 'PAID');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      // saving selects the new stamp and closes both dialogs
      expect(find.byType(PdfStampPickerDialog), findsNothing);
      expect(editing.customStamps.single.text, 'PAID');
      expect(editing.activeStamp, editing.customStamps.single);

      // tap the page; the double-tap recognizer holds taps ~300ms
      await tester.tapAt(tester.getCenter(find.byType(PdfViewer)));
      await tester.pumpAndSettle(const Duration(milliseconds: 350));

      final stamp = editing.document.page(0).annotations.single;
      expect(stamp.subtype, 'Stamp');
      expect(stamp.contents, 'PAID');
    });

    testWidgets('the picker can revert to typing the caption', (tester) async {
      final editing = PdfEditingController(buildMultiPagePdf(1));
      addTearDown(editing.dispose);
      const paid = PdfCustomStamp(text: 'PAID', color: 0xC03030);
      editing
        ..saveCustomStamp(paid)
        ..activeStamp = paid;

      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => Center(
            child: FilledButton(
              onPressed: () => showPdfStampPicker(context, controller: editing),
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.byType(PdfStampPreview), findsOneWidget);
      await tester.tap(find.text('Type the text for each stamp'));
      await tester.pumpAndSettle();
      expect(editing.activeStamp, isNull);
      expect(find.byType(PdfStampPickerDialog), findsNothing);

      // reopen and delete the saved stamp
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Delete stamp'));
      await tester.pumpAndSettle();
      expect(editing.customStamps, isEmpty);
      expect(find.byType(PdfStampPreview), findsNothing);
    });
  });
}
