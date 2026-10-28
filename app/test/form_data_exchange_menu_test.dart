// The Acrobat exchange formats (FDF, XFDF, XDP) are wired into the DartPDF
// app menu when a document is open; the XDP open path turns a package into
// the PDF it embeds. Picking and saving need platform channels, so the menu
// tests stop at the wiring.
import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dart_pdf_editor/dart_pdf_editor.dart' hide PdfDocument;
import 'package:dart_pdf_editor_app/editor_screen.dart';
import 'package:dart_pdf_editor_app/file_io.dart';

const _menuIds = [
  'menu-import-form-data',
  'menu-export-fdf',
  'menu-export-xfdf',
  'menu-export-xdp',
];

void main() {
  late PdfEditingPreferences prefs;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    prefs = PdfEditingPreferences();
  });
  tearDown(() => prefs.dispose());

  testWidgets('the menu offers form-data import and export with a document',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: EditorScreen(
        prefs: prefs,
        initialDocument: (bytes: buildAcroFormPdf(), title: 'Form.pdf'),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.byTooltip('DartPDF menu'));
    await tester.pumpAndSettle();

    for (final id in _menuIds) {
      expect(find.byKey(ValueKey(id)), findsOneWidget, reason: id);
    }
    expect(find.text('Import form data or comments…'), findsOneWidget);
    expect(find.text('Export form data as FDF…'), findsOneWidget);
    expect(find.text('Export form data as XFDF…'), findsOneWidget);
    expect(find.text('Export as XDP…'), findsOneWidget);
  });

  testWidgets('no form-data entries without a document', (tester) async {
    await tester.pumpWidget(MaterialApp(home: EditorScreen(prefs: prefs)));
    await tester.pump();

    await tester.tap(find.byTooltip('DartPDF menu'));
    await tester.pumpAndSettle();

    for (final id in _menuIds) {
      expect(find.byKey(ValueKey(id)), findsNothing, reason: id);
    }
  });

  group('opening an XDP package', () {
    test('yields the embedded PDF with its data filled in', () {
      final xdp = utf8.encode(
          '<?xml version="1.0"?><xdp:xdp xmlns:xdp="http://ns.adobe.com/xdp/">'
          '<xfa:datasets xmlns:xfa="http://www.xfa.org/schema/xfa-data/1.0/">'
          '<xfa:data><form><name>From XDP</name></form></xfa:data>'
          '</xfa:datasets><pdf xmlns="http://ns.adobe.com/xdp/pdf/"><document>'
          '<chunk>${base64Encode(buildAcroFormPdf())}</chunk></document></pdf>'
          '</xdp:xdp>');
      final pdf = pdfFromXdpPackage(xdp);
      expect(pdf, isNotNull);
      final form = PdfAcroForm.of(PdfDocument.open(pdf!))!;
      expect(form.fieldNamed('name')!.value, 'From XDP');
    });

    test('leaves PDFs and other files alone', () {
      expect(pdfFromXdpPackage(buildAcroFormPdf()), isNull);
      expect(pdfFromXdpPackage(PdfFormData().toXfdf()), isNull);
    });

    test('titles the result as a PDF', () {
      expect(pdfTitleForXdp('Claim form.xdp'), 'Claim form.pdf');
      expect(pdfTitleForXdp('noext'), 'noext.pdf');
    });
  });
}
