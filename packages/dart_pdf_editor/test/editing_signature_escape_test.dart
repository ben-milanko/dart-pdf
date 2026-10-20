import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets(
      'Escape disarms a signature box immediately after a toolbar click',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final editing = PdfEditingController(buildMultiPagePdf(1));
    final viewer = PdfViewerController();
    addTearDown(editing.dispose);
    addTearDown(viewer.dispose);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Column(children: [
      PdfEditingToolbar(
          controller: editing, viewerController: viewer, compact: false),
      Expanded(
          child: PdfViewer(
              document: editing.document,
              editing: editing,
              controller: viewer)),
    ]))));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('pdf-group-insert')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('pdf-tool-signatureBox')));
    await tester.pump();
    expect(editing.tool, PdfEditTool.signatureBox);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(editing.tool, PdfEditTool.select);
    expect(editing.isModified, isFalse);
  });
}
