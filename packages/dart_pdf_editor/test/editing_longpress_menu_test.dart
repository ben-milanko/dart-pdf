import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Touch long-press opens the context menu mice reach by right-clicking:
// on an annotation (select mode or reader mode), on empty page area when
// the clipboard has something to paste, and on a form field with the
// form tool armed. The recognizer only claims when the press point has a
// menu to offer, so text selection keeps its long press everywhere else.

// 800×600 viewport, fit-width: 612pt page → view scale
const scale = 800 / 612;

Offset viewPoint(double x, double y) => Offset(x * scale, (792 - y) * scale);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<PdfEditingController> pumpViewer(WidgetTester tester,
      {Uint8List? bytes}) async {
    final editing = PdfEditingController(bytes ?? buildMultiPagePdf(1));
    addTearDown(editing.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ListenableBuilder(
          listenable: editing,
          builder: (context, _) => PdfViewer(
            initialFit: PdfViewerFit.width,
            document: editing.document,
            editing: editing,
          ),
        ),
      ),
    ));
    await tester.pump();
    return editing;
  }

  /// Holds a touch pointer until the long-press deadline fires and any
  /// menu route settles, then lifts.
  Future<void> longPressAt(WidgetTester tester, Offset at) async {
    final gesture =
        await tester.startGesture(at, kind: PointerDeviceKind.touch);
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    await gesture.up();
    await tester.pumpAndSettle();
  }

  group('select mode', () {
    testWidgets('long-press on an annotation selects it and opens the menu',
        (tester) async {
      final editing = await pumpViewer(tester);
      editing
        ..addRectangle(0, const PdfRect(300, 400, 400, 450))
        ..tool = PdfEditTool.select;
      await tester.pump();

      await longPressAt(tester, viewPoint(350, 425));
      expect(editing.selectedAnnotationSlots, [(0, 0)]);
      expect(
          find.byKey(const ValueKey('pdf-annot-menu-delete')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('pdf-annot-menu-delete')));
      await tester.pumpAndSettle();
      expect(editing.document.page(0).annotations, isEmpty);
      await tester.pump(const Duration(milliseconds: 400));
    });

    testWidgets('long-press on empty area pastes from the clipboard',
        (tester) async {
      final editing = await pumpViewer(tester);
      editing
        ..addRectangle(0, const PdfRect(300, 400, 400, 450))
        ..tool = PdfEditTool.select
        ..selectAnnotation(0, 0)
        ..copySelectedAnnotations()
        ..clearAnnotationSelection();
      await tester.pump();

      // press point must sit inside the 800×600 viewport (view y ≈ 408)
      await longPressAt(tester, viewPoint(200, 480));
      final paste =
          tester.widget(find.byKey(const ValueKey('pdf-annot-menu-paste')))
              as PopupMenuItem;
      expect(paste.enabled, isTrue);
      await tester.tap(find.byKey(const ValueKey('pdf-annot-menu-paste')));
      await tester.pumpAndSettle();

      final annotations = editing.document.page(0).annotations;
      expect(annotations, hasLength(2));
      // pasted centered on the press point
      expect(annotations[1].rect.left + annotations[1].rect.width / 2,
          closeTo(200, 1));
      expect(annotations[1].rect.bottom + annotations[1].rect.height / 2,
          closeTo(480, 1));
      await tester.pump(const Duration(milliseconds: 400));
    });

    testWidgets('long-press on empty area without a clipboard does nothing',
        (tester) async {
      final editing = await pumpViewer(tester);
      editing
        ..addRectangle(0, const PdfRect(300, 400, 400, 450))
        ..tool = PdfEditTool.select;
      await tester.pump();

      await longPressAt(tester, viewPoint(350, 200));
      expect(find.byKey(const ValueKey('pdf-annot-menu-delete')), findsNothing);
      expect(find.byKey(const ValueKey('pdf-annot-menu-paste')), findsNothing);
      await tester.pump(const Duration(milliseconds: 400));
    });
  });

  group('reader mode', () {
    testWidgets('long-press on an annotation opens the menu without a tool',
        (tester) async {
      final editing = await pumpViewer(tester);
      editing.addRectangle(0, const PdfRect(300, 400, 400, 450));
      await tester.pump();
      expect(editing.tool, isNull);

      await longPressAt(tester, viewPoint(350, 425));
      expect(editing.selectedAnnotationSlots, [(0, 0)]);
      expect(
          find.byKey(const ValueKey('pdf-annot-menu-delete')), findsOneWidget);
      // dismiss
      await tester.tapAt(const Offset(780, 580));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 400));
    });

    testWidgets('long-press on page text still selects the word',
        (tester) async {
      // the controller must ride the viewer from the first build - it
      // attaches in initState
      final controller = PdfViewerController();
      final editing = PdfEditingController(buildMultiPagePdf(1));
      addTearDown(editing.dispose);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ListenableBuilder(
            listenable: editing,
            builder: (context, _) => PdfViewer(
              initialFit: PdfViewerFit.width,
              document: editing.document,
              controller: controller,
              editing: editing,
            ),
          ),
        ),
      ));
      await tester.pump();

      // 'Page 1' baseline at (72, 720), 24pt - press mid-word
      await longPressAt(tester, viewPoint(100, 726));
      expect(controller.selectedText, 'Page');
      expect(find.byKey(const ValueKey('pdf-annot-menu-delete')), findsNothing);
      await tester.pump(const Duration(milliseconds: 400));
    });
  });

  group('form tool', () {
    testWidgets('long-press on a field opens the field menu', (tester) async {
      final editing = await pumpViewer(tester, bytes: buildAcroFormPdf());
      editing.tool = PdfEditTool.form;
      await tester.pump();

      // the 'name' text field at [72 700 300 724]
      await longPressAt(tester, viewPoint(180, 712));
      expect(
          find.byKey(const ValueKey('pdf-form-menu-rename')), findsOneWidget);
      // dismiss without acting
      await tester.tapAt(const Offset(780, 580));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 400));
    });
  });
}
