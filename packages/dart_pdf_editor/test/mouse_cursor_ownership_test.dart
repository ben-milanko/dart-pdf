import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:dart_pdf_editor/src/mouse_cursor.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:shared_preferences/shared_preferences.dart';

PdfMouseCursorPainter viewerCursor(WidgetTester tester) => tester
    .widget<CustomPaint>(find.byKey(const ValueKey('pdf-viewer-mouse-cursor')))
    .painter! as PdfMouseCursorPainter;

dynamic overlayCursor(WidgetTester tester) => tester
    .widgetList<CustomPaint>(find.byType(CustomPaint))
    .map((paint) => paint.painter)
    .firstWhere(
        (painter) => painter.runtimeType.toString() == '_HoverCursorPainter');

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<TestGesture> hover(WidgetTester tester, Offset point) async {
    final mouse =
        await tester.createGesture(kind: PointerDeviceKind.mouse, pointer: 42);
    await mouse.addPointer(location: const Offset(5, 5));
    await mouse.moveTo(point);
    await tester.pump();
    addTearDown(mouse.removePointer);
    return mouse;
  }

  testWidgets('armed editing keeps a viewer cursor on the surrounding canvas',
      (tester) async {
    final editing = PdfEditingController(buildMultiPagePdf(2))
      ..tool = PdfEditTool.rectangle;
    addTearDown(editing.dispose);
    await tester.pumpWidget(MaterialApp(home: PdfViewer(editing: editing)));
    await tester.pumpAndSettle();
    final mouse = await hover(tester, const Offset(20, 250));
    expect(viewerCursor(tester).kind, PdfMouseCursorKind.grab);
    await mouse.moveTo(const Offset(400, 300));
    await tester.pump();
    expect(viewerCursor(tester).kind, isNull);
    expect(overlayCursor(tester).mouseCursor, PdfMouseCursorKind.precise);
    await mouse.moveTo(const Offset(25, 250));
    await tester.pump();
    expect(viewerCursor(tester).kind, PdfMouseCursorKind.grab);
    final painted = tester.widget<CustomPaint>(
        find.byKey(const ValueKey('pdf-viewer-mouse-cursor')));
    await mouse.moveTo(const Offset(30, 260));
    await tester.pump();
    expect(
        tester.widget<CustomPaint>(
            find.byKey(const ValueKey('pdf-viewer-mouse-cursor'))),
        same(painted),
        reason: 'cursor movement should repaint without rebuilding its widget');
    expect(viewerCursor(tester).position, const Offset(30, 260));
  });

  testWidgets('passive cursor guides leave the glyph to the viewer',
      (tester) async {
    final editing = PdfEditingController(buildMultiPagePdf(1));
    addTearDown(editing.dispose);
    editing.preferences.showVerticalCursorGuide = true;
    await tester.pumpWidget(MaterialApp(home: PdfViewer(editing: editing)));
    await tester.pumpAndSettle();
    await hover(tester, const Offset(400, 300));
    expect(viewerCursor(tester).kind, PdfMouseCursorKind.grab);
    expect(overlayCursor(tester).mouseCursor, isNull);
    expect(overlayCursor(tester).guideCursor, isNotNull);
  });

  testWidgets('inline text editor does not acquire an extra painted glyph',
      (tester) async {
    final editing = PdfEditingController(buildMultiPagePdf(1))
      ..addFreeText(0, const PdfRect(100, 600, 300, 650), 'Original')
      ..selectAnnotation(0, 0);
    addTearDown(editing.dispose);
    await tester.pumpWidget(MaterialApp(
        home: Material(
            child:
                PdfViewer(editing: editing, initialFit: PdfViewerFit.width))));
    await tester.pumpAndSettle();
    final mouse = await hover(tester, const Offset(260, 215));
    await mouse.down(const Offset(260, 215));
    await mouse.up();
    await tester.pumpAndSettle();
    expect(find.byType(EditableText), findsOneWidget);
    await mouse.moveTo(tester.getCenter(find.byType(EditableText)));
    await tester.pump();
    expect(viewerCursor(tester).kind, isNull);
    expect(overlayCursor(tester).mouseCursor, isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('signed signature field owns the only painted cursor',
      (tester) async {
    final editing = PdfEditingController(buildMultiPagePdf(1));
    addTearDown(editing.dispose);
    expect(
        await editing.addSelfSignedSignature(
            PdfSigningIdentity.generate(name: 'Cursor test'),
            appearance: const PdfSignatureAppearance(
                page: 0, rect: PdfRect(72, 640, 320, 720))),
        isTrue);
    final fieldName = editing.signatures.single.field.name;
    await tester.pumpWidget(MaterialApp(
        home: PdfViewer(
            document: editing.document,
            formController: editing,
            initialFit: PdfViewerFit.width)));
    await tester.pumpAndSettle();
    final field = find.byKey(ValueKey('pdf-form-field-0-$fieldName-0'));
    await hover(tester, tester.getCenter(field));
    expect(viewerCursor(tester).kind, isNull);
    final region = tester.renderObject<RenderPdfMouseCursorRegion>(
        find.ancestor(of: field, matching: find.byType(PdfMouseCursorRegion)));
    expect(region.kind, PdfMouseCursorKind.click);
  });
}
