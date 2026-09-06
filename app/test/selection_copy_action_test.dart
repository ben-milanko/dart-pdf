import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dart_pdf_editor_app/editor_screen.dart';

void main() {
  late PdfEditingPreferences preferences;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    preferences = PdfEditingPreferences();
  });

  tearDown(() => preferences.dispose());

  Future<PdfViewerController> selectPageText(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: EditorScreen(
        prefs: preferences,
        initialDocument: (
          bytes: buildMultiPagePdf(1),
          title: 'selection.pdf',
        ),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // A document opens in Hand mode, where a mouse drag pans instead of
    // selecting. Leave it the way the toolbar does before dragging out a
    // text selection.
    tester.widget<PdfViewer>(find.byType(PdfViewer)).editing!.tool = null;
    await tester.pump();

    final pageFinder = find.byType(PdfPageView).first;
    final pageTopLeft = tester.getTopLeft(pageFinder);
    final pageSize = tester.getSize(pageFinder);
    final scale = pageSize.width / 612;
    Offset pagePoint(double x, double y) =>
        pageTopLeft + Offset(x * scale, (792 - y) * scale);

    final gesture = await tester.startGesture(
      pagePoint(148, 720),
      kind: PointerDeviceKind.mouse,
    );
    await gesture.moveBy(const Offset(-20, 0));
    await tester.pump();
    await gesture.moveTo(pagePoint(50, 720));
    await tester.pump();
    await gesture.up();
    await tester.pump();

    final viewer = tester.widget<PdfViewer>(find.byType(PdfViewer));
    expect(viewer.controller!.hasSelection, isTrue);
    return viewer.controller!;
  }

  for (final platform in [
    TargetPlatform.macOS,
    TargetPlatform.windows,
    TargetPlatform.linux,
  ]) {
    testWidgets('desktop header omits selection copy on ${platform.name}',
        (tester) async {
      await selectPageText(tester);

      expect(find.byTooltip('Copy selected text (⌘C)'), findsNothing);
    }, variant: TargetPlatformVariant.only(platform));
  }

  testWidgets('mobile header retains selection copy', (tester) async {
    await selectPageText(tester);

    expect(find.byTooltip('Copy selected text (⌘C)'), findsOneWidget);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));
}
