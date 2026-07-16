// The drawable pasteboard: with PdfViewer.pasteboardMargin set, each page
// is inset inside its tile so a blank band stays beside it, and a pen
// stroke that lands in that band authors an annotation *outside* the page
// box (a negative / off-page coordinate) that saves with the page.
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<PdfEditingController> pumpViewer(WidgetTester tester,
      {double pasteboard = 120}) async {
    final editing = PdfEditingController(buildMultiPagePdf(1));
    addTearDown(editing.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ListenableBuilder(
          listenable: editing,
          builder: (context, _) => PdfViewer(
            initialFit: PdfViewerFit.width,
            document: editing.document,
            editing: editing,
            pasteboardMargin: pasteboard,
          ),
        ),
      ),
    ));
    await tester.pump();
    return editing;
  }

  testWidgets('a pen stroke in the left margin authors an off-page annotation',
      (tester) async {
    final editing = await pumpViewer(tester);
    final cropLeft = editing.document.page(0).cropBox.left;
    editing.tool = PdfEditTool.ink;
    await tester.pump();

    // x = 40 sits inside the 120px left pasteboard band - left of the page.
    // A stylus stroke there must still be captured (the editing overlay
    // spans the whole tile) and map to a page x left of the crop box.
    final g = await tester.startGesture(const Offset(40, 300),
        kind: PointerDeviceKind.stylus);
    await g.moveBy(const Offset(10, 0));
    await g.moveBy(const Offset(10, 10));
    await g.up();
    await tester.pump(const Duration(milliseconds: 900));
    await tester.pump(const Duration(milliseconds: 400));

    final annotations = editing.document.page(0).annotations;
    expect(annotations, hasLength(1),
        reason: 'the margin stroke committed an annotation');
    expect(annotations.single.subtype, 'Ink');
    final stroke = annotations.single.inkList!.single;
    // list of (x, y) points; the first x lands in the off-page band
    expect(stroke.first.$1, lessThan(cropLeft),
        reason: 'the stroke starts left of the page (off-page x)');
  });

  testWidgets('off-page margin ink survives a save/reload round-trip',
      (tester) async {
    final editing = await pumpViewer(tester);
    editing.tool = PdfEditTool.ink;
    await tester.pump();
    final g = await tester.startGesture(const Offset(40, 300),
        kind: PointerDeviceKind.stylus);
    await g.moveBy(const Offset(12, 6));
    await g.up();
    await tester.pump(const Duration(milliseconds: 900));
    await tester.pump(const Duration(milliseconds: 400));

    final saved = editing.document.page(0).annotations.single;
    final savedLeft = saved.rect.left;
    expect(savedLeft, lessThan(editing.document.page(0).cropBox.left));

    // reopen the edited bytes and confirm the off-page rect persisted
    final reopened = PdfDocument.open(editing.bytes);
    final round = reopened.page(0).annotations.single;
    expect(round.subtype, 'Ink');
    expect(round.rect.left, moreOrLessEquals(savedLeft, epsilon: 0.5),
        reason: 'the off-page /Rect round-trips through save/reload');
  });
}
