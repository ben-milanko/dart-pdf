import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Choice fields (dropdowns and list boxes) take the form-field style
/// controls too: font, size, colour and alignment, but not multiline.
void main() {
  // buildListBoxFormPdf: 'toppings' list box [72 600 272 700], 'crust' list
  // box [72 500 272 560], 'size' combo box [72 440 272 464] with /V (M).
  PdfEditingController controller() {
    SharedPreferences.setMockInitialValues({});
    return PdfEditingController(buildListBoxFormPdf())..tool = PdfEditTool.form;
  }

  void selectDropdown(PdfEditingController editing) {
    expect(editing.selectFormWidgetAt(0, 172, 452), isTrue);
  }

  group('choice-field style controller API', () {
    test('a selected dropdown is styleable, without multiline', () {
      final editing = controller();
      selectDropdown(editing);
      expect(editing.canStyleSelectedFormField, isTrue);
      expect(editing.selectedFormFieldName, 'size');
      final style = editing.selectedFormFieldStyle!;
      expect(style.supportsMultiline, isFalse);
      expect(style.font, PdfStandardFont.helvetica);
      expect(style.size, 10);
    });

    test('changing a dropdown\'s font regenerates it, keeping the value', () {
      final editing = controller();
      selectDropdown(editing);
      final before = editing.bytes.length;
      expect(
          editing.setSelectedFormFieldStyle(
              font: PdfStandardFont.courierBold, fontSize: 14),
          isTrue);
      final field = editing.acroForm!.fieldNamed('size')!;
      expect(field.defaultAppearance, contains('/CourBold 14 Tf'));
      expect(field.value, 'M');
      expect(editing.selectedFormFieldStyle!.font, PdfStandardFont.courierBold);
      // still selected, one undo step back
      expect(editing.selectedFormFieldName, 'size');
      editing.undo();
      expect(editing.bytes.length, before);
      expect(editing.acroForm!.fieldNamed('size')!.defaultAppearance,
          contains('/Helv 10 Tf'));
    });

    test('setFormFieldStyle by name restyles a list box', () {
      final editing = controller();
      expect(
          editing.setFormFieldStyle('crust',
              font: PdfStandardFont.times, color: 0x0000FF),
          isTrue);
      final field = editing.acroForm!.fieldNamed('crust')!;
      expect(field.defaultAppearance, contains('/TiRo'));
      expect(field.appearanceColor, 0x0000FF);
    });

    test('a multiline-only edit leaves a dropdown alone', () {
      final editing = controller();
      selectDropdown(editing);
      final before = editing.bytes.length;
      expect(editing.setSelectedFormFieldStyle(multiline: true), isFalse);
      expect(editing.bytes.length, before);
    });

    test('a mixed text + dropdown selection restyles both as one revision', () {
      SharedPreferences.setMockInitialValues({});
      final editor = PdfEditor(PdfDocument.open(buildListBoxFormPdf()));
      editor.addTextField(0, 'note', const PdfRect(300, 440, 500, 464));
      final editing = PdfEditingController(editor.save())
        ..tool = PdfEditTool.form;
      selectDropdown(editing);
      expect(editing.selectFormWidgetAt(0, 400, 452, toggle: true), isTrue);
      expect(editing.selectedFormStyleFieldNames, ['note', 'size']);

      final before = editing.bytes.length;
      expect(editing.setSelectedFormFieldStyle(font: PdfStandardFont.courier),
          isTrue);
      for (final name in ['note', 'size']) {
        expect(editing.acroForm!.fieldNamed(name)!.defaultAppearance,
            contains('/Cour '),
            reason: name);
      }
      editing.undo();
      expect(editing.bytes.length, before);

      // multiline reaches the text field only (undo dropped the selection)
      selectDropdown(editing);
      expect(editing.selectFormWidgetAt(0, 400, 452, toggle: true), isTrue);
      expect(editing.setSelectedFormFieldStyle(multiline: true), isTrue);
      expect(editing.acroForm!.fieldNamed('note')!.isMultiline, isTrue);
    });
  });

  testWidgets('properties panel offers font controls for a dropdown',
      (tester) async {
    final editing = controller();
    final viewer = PdfViewerController();
    addTearDown(editing.dispose);
    addTearDown(viewer.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ListenableBuilder(
          listenable: editing,
          builder: (context, _) => Row(children: [
            Expanded(
              child: PdfViewer(
                initialFit: PdfViewerFit.width,
                document: editing.document,
                controller: viewer,
                editing: editing,
              ),
            ),
            PdfAnnotationPropertiesPanel(controller: editing),
          ]),
        ),
      ),
    ));
    await tester.pump();

    selectDropdown(editing);
    await tester.pump();

    expect(find.byKey(const ValueKey('pdf-prop-form-font')), findsOneWidget);
    expect(find.byKey(const ValueKey('pdf-prop-form-color')), findsOneWidget);
    expect(find.byKey(const ValueKey('pdf-prop-form-multiline')), findsNothing);
  });

  testWidgets('toolbar tune popup styles a dropdown, without multiline',
      (tester) async {
    final editing = controller();
    final viewer = PdfViewerController();
    addTearDown(editing.dispose);
    addTearDown(viewer.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ListenableBuilder(
          listenable: editing,
          builder: (context, _) => PdfViewer(
            initialFit: PdfViewerFit.width,
            document: editing.document,
            controller: viewer,
            editing: editing,
          ),
        ),
        bottomNavigationBar:
            PdfEditingToolbar(controller: editing, viewerController: viewer),
      ),
    ));
    await tester.pump();

    selectDropdown(editing);
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.tune));
    await tester.pumpAndSettle();
    expect(
        find.byKey(const ValueKey('pdf-form-style-font-menu')), findsOneWidget);
    expect(
        find.byKey(const ValueKey('pdf-form-style-multiline')), findsNothing);

    // the alignment toggles reach the dropdown
    await tester
        .tap(find.byKey(const ValueKey('pdf-form-style-align-right')).first);
    await tester.pumpAndSettle();
    expect(editing.acroForm!.fieldNamed('size')!.quadding,
        PdfTextAlign.right.quadding);
  });
}
