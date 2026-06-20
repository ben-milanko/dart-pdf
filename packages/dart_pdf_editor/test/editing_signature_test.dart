import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('PdfInkSignature', () {
    test('normalizes pad strokes and round-trips through JSON', () {
      final signature = PdfInkSignature.fromPad(
        [
          [const Offset(10, 20), const Offset(110, 70)],
          [const Offset(60, 20)],
        ],
        [
          [0.2, 0.9],
          null,
        ],
        const Color(0xFF1A3E8C),
      )!;
      expect(signature.aspect, 2.0); // 100 wide, 50 tall
      expect(signature.color, 0x1A3E8C);
      expect(signature.strokes.first.first, (0.0, 0.0));
      expect(signature.strokes.first.last, (1.0, 1.0));
      expect(signature.strokes.last.single, (0.5, 0.0));

      final decoded = PdfInkSignature.decode(signature.encode())!;
      expect(decoded.strokes, signature.strokes);
      expect(decoded.pressures, signature.pressures);
      expect(decoded.color, signature.color);
      expect(decoded.aspect, signature.aspect);
    });

    test('an empty pad yields no signature; junk decodes to null', () {
      expect(PdfInkSignature.fromPad([], [], const Color(0xFF000000)), isNull);
      expect(PdfInkSignature.decode('not json'), isNull);
      expect(PdfInkSignature.decode('{"color": 1}'), isNull);
    });

    test('persists through PdfEditingPreferences', () async {
      SharedPreferences.setMockInitialValues({});
      final a = PdfEditingPreferences();
      await a.ready;
      a.signature = PdfInkSignature.fromPad(
        [
          [const Offset(0, 0), const Offset(80, 40)]
        ],
        [null],
        const Color(0xFF000000),
      );
      await pumpEventQueue();

      final b = PdfEditingPreferences();
      await b.ready;
      expect(b.signature, isNotNull);
      expect(b.signature!.aspect, 2.0);
      expect(b.signature!.strokes.single.last, (1.0, 1.0));

      a.signature = null;
      await pumpEventQueue();
      final c = PdfEditingPreferences();
      await c.ready;
      expect(c.signature, isNull);
    });
  });

  group('placeSignature', () {
    PdfInkSignature signature() => PdfInkSignature.fromPad(
          [
            [const Offset(0, 0), const Offset(100, 50)]
          ],
          [
            [0.2, 1.0]
          ],
          const Color(0xFF1A3E8C),
        )!;

    test('stamps a centered, y-flipped Ink annotation', () {
      final editing = PdfEditingController(buildMultiPagePdf(1))
        ..color = const Color(0xFF1A3E8C)
        ..signature = signature();
      expect(editing.placeSignature(0, 300, 400, width: 100), isTrue);

      final ink = editing.document.page(0).annotations.single;
      expect(ink.subtype, 'Ink');
      // the signature follows the selected toolbar colour
      expect(ink.color, 0x1A3E8C);
      // 100×50 centered on (300, 400): strokes span 250..350, 375..425
      // (the /Rect is padded for the stroke width)
      expect(ink.rect.left, lessThan(250));
      expect(ink.rect.right, greaterThan(350));
      expect(ink.rect.bottom, lessThan(375));
      expect(ink.rect.top, greaterThan(425));
      expect(ink.rect.width, lessThan(120));
    });

    test('clamps so the whole signature stays on the page', () {
      final editing = PdfEditingController(buildMultiPagePdf(1))
        ..signature = signature();
      final box = editing.document.page(0).cropBox;
      expect(editing.placeSignature(0, box.right, box.bottom), isTrue);

      final ink = editing.document.page(0).annotations.single;
      // padded /Rect may poke out by the stroke margin, but the strokes
      // themselves stay inside the crop box
      expect(ink.rect.right, lessThan(box.right + 5));
      expect(ink.rect.bottom, greaterThan(box.bottom - 5));
    });

    test('the placed signature follows the selected colour, not the drawn one',
        () {
      final editing = PdfEditingController(buildMultiPagePdf(1))
        ..signature = signature() // drawn in 0x1A3E8C
        ..color = const Color(0xFF00AA00);
      expect(editing.placeSignature(0, 300, 400, width: 100), isTrue);
      expect(editing.document.page(0).annotations.single.color, 0x00AA00);
    });

    test('without a saved signature nothing happens', () {
      final editing = PdfEditingController(buildMultiPagePdf(1));
      expect(editing.placeSignature(0, 300, 400), isFalse);
      expect(editing.document.page(0).annotations, isEmpty);
      expect(editing.isModified, isFalse);
    });
  });

  group('signature tool in the viewer', () {
    testWidgets('draw in the dialog, then tap pages to place', (tester) async {
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

      // the signature tool lives in the Insert group's strip
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
      final insertChip = find.byKey(const ValueKey('pdf-group-insert'));
      await tester.scrollUntilVisible(insertChip, 80,
          scrollable: dockScrollable);
      await tester.tap(insertChip);
      await tester.pump();

      // no saved signature: the tool button opens the pad dialog first
      await tester.scrollUntilVisible(
          find.byTooltip('Signature — tap a page to place it (G)'), 100,
          scrollable: stripScrollable);
      await tester.tap(find.byTooltip('Signature — tap a page to place it (G)'));
      await tester.pumpAndSettle();
      expect(find.byType(PdfSignatureDialog), findsOneWidget);

      // Done is disabled until something is drawn
      expect(
          tester
              .widget<FilledButton>(find.widgetWithText(FilledButton, 'Done'))
              .onPressed,
          isNull);

      final pad = find.byKey(const ValueKey('pdf-signature-pad'));
      await tester.timedDrag(
          pad, const Offset(120, 30), const Duration(milliseconds: 200));
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Done'));
      await tester.pumpAndSettle();

      expect(editing.signature, isNotNull);
      expect(editing.tool, PdfEditTool.signature);

      // tap the page; the double-tap recognizer holds taps ~300ms
      await tester.tapAt(tester.getCenter(find.byType(PdfViewer)));
      await tester.pumpAndSettle(const Duration(milliseconds: 350));

      final ink = editing.document.page(0).annotations.single;
      expect(ink.subtype, 'Ink');

      // armed again later, the saved signature is reused without a dialog
      editing.tool = null;
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
          find.byTooltip('Signature — tap a page to place it (G)'), 100,
          scrollable: stripScrollable);
      await tester.tap(find.byTooltip('Signature — tap a page to place it (G)'));
      await tester.pumpAndSettle();
      expect(find.byType(PdfSignatureDialog), findsNothing);
      expect(editing.tool, PdfEditTool.signature);
    });

    testWidgets('Clear wipes the pad and disables Done', (tester) async {
      PdfInkSignature? result;
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => Center(
            child: FilledButton(
              onPressed: () async {
                result = await showPdfSignatureDialog(context);
              },
              child: const Text('sign'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('sign'));
      await tester.pumpAndSettle();

      final pad = find.byKey(const ValueKey('pdf-signature-pad'));
      await tester.timedDrag(
          pad, const Offset(80, 20), const Duration(milliseconds: 200));
      await tester.pump();
      await tester.tap(find.text('Clear'));
      await tester.pump();
      expect(
          tester
              .widget<FilledButton>(find.widgetWithText(FilledButton, 'Done'))
              .onPressed,
          isNull);

      // draw again and finish
      await tester.timedDrag(
          pad, const Offset(60, -15), const Duration(milliseconds: 200));
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Done'));
      await tester.pumpAndSettle();
      expect(result, isNotNull);
      expect(result!.strokes, hasLength(1));
    });
  });
}
