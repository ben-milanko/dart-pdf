import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:shared_preferences/shared_preferences.dart';

Uint8List labelledPdf() {
  final editor = PdfEditor(PdfDocument.open(buildMultiPagePdf(4)))
    ..setPageLabel(0, style: PdfPageLabelStyle.romanLower)
    ..setPageLabel(2, style: PdfPageLabelStyle.decimal, start: 1);
  return editor.save();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> pump(WidgetTester tester, Widget body) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: body)));
    await tester.pump();
  }

  testWidgets('the page field shows the logical label, not the raw number',
      (tester) async {
    final controller = PdfViewerController();
    addTearDown(controller.dispose);
    await pump(tester, PdfReader(bytes: labelledPdf(), controller: controller));

    expect(controller.hasPageLabels, isTrue);
    expect(controller.pageLabel(0), 'i');
    expect(controller.pageLabel(2), '1');

    final field = tester.widget<TextField>(
        find.byKey(const ValueKey('pdf-page-number-field')));
    expect(field.controller!.text, 'i');
    // physical position is still shown beside the label
    expect(find.text('  (1 / 4)'), findsOneWidget);
  });

  testWidgets('a plain document keeps the numeric field', (tester) async {
    final controller = PdfViewerController();
    addTearDown(controller.dispose);
    await pump(tester,
        PdfReader(bytes: buildMultiPagePdf(3), controller: controller));

    expect(controller.hasPageLabels, isFalse);
    final field = tester.widget<TextField>(
        find.byKey(const ValueKey('pdf-page-number-field')));
    expect(field.controller!.text, '1');
    expect(find.text(' / 3'), findsOneWidget);
  });

  testWidgets('pageForLabel resolves typed labels and physical numbers',
      (tester) async {
    final controller = PdfViewerController();
    addTearDown(controller.dispose);
    await pump(tester, PdfReader(bytes: labelledPdf(), controller: controller));

    expect(controller.pageForLabel('ii'), 1);
    expect(controller.pageForLabel('2'), 3); // page index 3 -> label "2"
    expect(controller.pageForLabel('nope'), isNull);
  });
}
