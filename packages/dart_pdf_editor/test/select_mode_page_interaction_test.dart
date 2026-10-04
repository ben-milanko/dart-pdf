// Select mode is where a document opens, so a click on the page still has to
// do what it does in the reader: follow a link, and reach the app's own page
// widgets. The editing overlay covers the page in Select mode, so both used
// to go dead.
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  // 800px viewport over a 612pt page (fit-width)
  const scale = 800 / 612;
  Offset view(double x, double y) => Offset(x * scale, (792 - y) * scale);

  Future<PdfEditingController> pumpEditor(
    WidgetTester tester, {
    required Uint8List bytes,
    PdfActionHandler? onAction,
    PdfPageOverlayBuilder? pageOverlayBuilder,
  }) async {
    final editing = PdfEditingController(bytes)..tool = PdfEditTool.select;
    addTearDown(editing.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PdfViewer(
          initialFit: PdfViewerFit.width,
          editing: editing,
          onAction: onAction,
          pageOverlayBuilder: pageOverlayBuilder,
        ),
      ),
    ));
    await tester.pump();
    return editing;
  }

  testWidgets('a click on a link follows it in Select mode', (tester) async {
    final actions = <PdfAction>[];
    final editing = await pumpEditor(tester,
        bytes: buildAnnotatedPdf(), onAction: (a, _) => actions.add(a));

    await tester.tapAt(view(136, 652)); // URI link center
    await tester.pump(const Duration(milliseconds: 400));

    expect(actions, hasLength(1));
    expect((actions.single as PdfUriAction).uri, 'app://invoice/42');
    expect(editing.tool, PdfEditTool.select);
    expect(editing.hasAnnotationSelection, isFalse);
  });

  testWidgets('app page widgets take taps in Select mode, not under a tool',
      (tester) async {
    var taps = 0;
    final editing = await pumpEditor(
      tester,
      bytes: buildMultiPagePdf(1),
      pageOverlayBuilder: (context, pageIndex, geometry) => [
        if (pageIndex == 0)
          Positioned.fromRect(
            rect: geometry.toViewRect(const PdfRect(300, 400, 400, 440)),
            child: GestureDetector(
              key: const ValueKey('host-button'),
              behavior: HitTestBehavior.opaque,
              onTap: () => taps++,
            ),
          ),
      ],
    );

    await tester.tap(find.byKey(const ValueKey('host-button')));
    await tester.pump(const Duration(milliseconds: 400));
    expect(taps, 1);

    // an armed drawing tool keeps the page's gestures for itself
    editing.tool = PdfEditTool.rectangle;
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('host-button')),
        warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 400));
    expect(taps, 1);
  });
}
