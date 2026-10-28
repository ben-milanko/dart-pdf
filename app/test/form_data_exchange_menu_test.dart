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

  Future<void> pumpWithForm(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: EditorScreen(
        prefs: prefs,
        initialDocument: (bytes: buildAcroFormPdf(), title: 'Form.pdf'),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  void expectEntries() {
    for (final id in _menuIds) {
      expect(find.byKey(ValueKey(id)), findsOneWidget, reason: id);
    }
    expect(find.text('Import form data or comments…'), findsOneWidget);
    expect(find.text('Export form data as FDF…'), findsOneWidget);
    expect(find.text('Export form data as XFDF…'), findsOneWidget);
    expect(find.text('Export as XDP…'), findsOneWidget);
  }

  testWidgets('the menu keeps form-data import and export in a submenu',
      (tester) async {
    await pumpWithForm(tester);

    await tester.tap(find.byTooltip('DartPDF menu'));
    await tester.pumpAndSettle();

    // folded away: only the submenu row shows in the menu itself
    for (final id in _menuIds) {
      expect(find.byKey(ValueKey(id)), findsNothing, reason: id);
    }
    final group = find.byKey(const ValueKey('menu-group-form-data'));
    expect(group, findsOneWidget);
    expect(find.text('Form data and comments'), findsOneWidget);

    await tester.ensureVisible(group);
    await tester.pumpAndSettle();
    await tester.tap(group);
    await tester.pumpAndSettle();
    expectEntries();
  });

  testWidgets('the phone sheet folds them into their own page', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pumpWithForm(tester);

    await tester.tap(find.byTooltip('DartPDF menu'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('app-menu-sheet')), findsOneWidget);
    final group = find.byKey(const ValueKey('menu-group-form-data'));
    expect(group, findsOneWidget);
    expect(find.byKey(const ValueKey('menu-export-fdf')), findsNothing);

    await tester.ensureVisible(group);
    await tester.pumpAndSettle();
    await tester.tap(group);
    await tester.pumpAndSettle();
    expect(
        find.byKey(const ValueKey('app-menu-sheet-form-data')), findsOneWidget);
    expectEntries();
  });

  testWidgets('no form-data entries without a document', (tester) async {
    await tester.pumpWidget(MaterialApp(home: EditorScreen(prefs: prefs)));
    await tester.pump();

    await tester.tap(find.byTooltip('DartPDF menu'));
    await tester.pumpAndSettle();

    for (final id in _menuIds) {
      expect(find.byKey(ValueKey(id)), findsNothing, reason: id);
    }
    expect(find.byKey(const ValueKey('menu-group-form-data')), findsNothing);
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
