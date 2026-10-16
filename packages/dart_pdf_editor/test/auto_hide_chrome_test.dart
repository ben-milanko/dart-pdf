import 'package:flutter/gestures.dart' show kDoubleTapTimeout;
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Phone chrome steps aside for reading: on a compact layout the header and
// the docked toolbar slide off as the user scrolls on through the document,
// and come back on a scroll back or a tap on the page.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> pump(WidgetTester tester, Widget body) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: body)));
    await tester.pumpAndSettle();
  }

  void screen(WidgetTester tester, Size size) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  const phone = Size(400, 800);
  final controls = find.byKey(const ValueKey('pdf-shell-controls'));
  final undo = find.byKey(const ValueKey('pdf-undo'));

  // a hidden header has slid up past the top edge
  bool headerShown(WidgetTester tester) => tester.getRect(controls).bottom > 0;
  // a hidden toolbar has slid down past the bottom edge
  bool toolbarShown(WidgetTester tester) =>
      tester.getRect(undo).top < phone.height;

  Future<void> scroll(WidgetTester tester, double dy) async {
    await tester.drag(find.byType(PdfViewer), Offset(0, dy));
    await tester.pumpAndSettle();
  }

  Future<void> tapPage(WidgetTester tester) async {
    await tester.tap(find.byType(PdfViewer));
    // a single tap resolves once the double-tap (zoom) window has passed
    await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 50));
    await tester.pumpAndSettle();
  }

  testWidgets('reader: scrolling on hides the header, back shows it',
      (tester) async {
    screen(tester, phone);
    await pump(tester,
        PdfReader(bytes: buildMultiPagePdf(6), initialFit: PdfViewerFit.width));
    expect(headerShown(tester), isTrue);

    await scroll(tester, -300);
    expect(headerShown(tester), isFalse);

    await scroll(tester, 120);
    expect(headerShown(tester), isTrue);
  });

  testWidgets('reader: a tap on the page toggles the header', (tester) async {
    screen(tester, phone);
    await pump(tester,
        PdfReader(bytes: buildMultiPagePdf(6), initialFit: PdfViewerFit.width));

    await tapPage(tester);
    expect(headerShown(tester), isFalse);
    await tapPage(tester);
    expect(headerShown(tester), isTrue);
  });

  testWidgets('editor: the header and docked toolbar hide together',
      (tester) async {
    screen(tester, phone);
    await pump(
        tester,
        PdfEditorView(
            bytes: buildMultiPagePdf(6), initialFit: PdfViewerFit.width));
    expect(headerShown(tester), isTrue);
    expect(toolbarShown(tester), isTrue);

    await scroll(tester, -300);
    expect(headerShown(tester), isFalse);
    expect(toolbarShown(tester), isFalse);

    await tapPage(tester);
    expect(headerShown(tester), isTrue);
    expect(toolbarShown(tester), isTrue);
  });

  testWidgets('editor: an armed tool keeps the chrome up', (tester) async {
    screen(tester, phone);
    final editing = PdfEditingController(buildMultiPagePdf(6));
    addTearDown(editing.dispose);
    await pump(tester,
        PdfEditorView(controller: editing, initialFit: PdfViewerFit.width));

    await scroll(tester, -300);
    expect(toolbarShown(tester), isFalse);

    // arming a tool brings the hidden chrome straight back
    editing.tool = PdfEditTool.ink;
    await tester.pumpAndSettle();
    expect(headerShown(tester), isTrue);
    expect(toolbarShown(tester), isTrue);
  });

  testWidgets('the feature can be turned off', (tester) async {
    screen(tester, phone);
    await pump(
        tester,
        PdfReader(
          bytes: buildMultiPagePdf(6),
          initialFit: PdfViewerFit.width,
          features: const PdfReaderFeatures(autoHideChrome: false),
        ));

    await scroll(tester, -300);
    expect(headerShown(tester), isTrue);
    await tapPage(tester);
    expect(headerShown(tester), isTrue);
  });

  testWidgets('a wide layout never hides its chrome', (tester) async {
    screen(tester, const Size(1200, 800));
    await pump(tester,
        PdfReader(bytes: buildMultiPagePdf(6), initialFit: PdfViewerFit.width));
    final header = find.byKey(const ValueKey('pdf-page-number-field'));
    final top = tester.getRect(header).top;

    await scroll(tester, -300);
    expect(tester.getRect(header).top, top);
  });
}
