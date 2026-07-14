import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  PdfEditingController controller() {
    SharedPreferences.setMockInitialValues({});
    return PdfEditingController(buildAcroFormPdf());
  }

  group('form field style controller API', () {
    test('selectedFormFieldStyle reflects a selected text field', () {
      final editing = controller();
      editing.tool = PdfEditTool.form;
      expect(editing.canStyleSelectedFormField, isFalse);

      expect(editing.selectFormWidgetAt(0, 186, 712), isTrue);
      expect(editing.canStyleSelectedFormField, isTrue);
      expect(editing.selectedFormFieldName, 'name');
      final style = editing.selectedFormFieldStyle;
      expect(style, isNotNull);
      expect(style!.multiline, isFalse);
      expect(style.align, PdfTextAlign.left);
    });

    test('a non-text widget is not styleable', () {
      final editing = controller();
      editing.tool = PdfEditTool.form;
      // the 'agree' check box at /Rect [72 540 92 560]
      expect(editing.selectFormWidgetAt(0, 82, 550), isTrue);
      expect(editing.selectedAnnotation!.subtype, 'Widget');
      expect(editing.canStyleSelectedFormField, isFalse);
      expect(editing.selectedFormFieldStyle, isNull);
    });

    test('selected field conversion keeps the rebuilt widget selected', () {
      final editing = controller();
      editing.tool = PdfEditTool.form;
      expect(editing.selectFormWidgetAt(0, 82, 550), isTrue);
      expect(editing.selectedWidgetFieldName, 'agree');
      expect(editing.selectedWidgetFieldType, PdfFieldType.checkBox);

      expect(
        editing.changeSelectedFormFieldKind(PdfFormFieldKind.pushButton),
        isTrue,
      );
      expect(
          editing.acroForm!.fieldNamed('agree')!.type, PdfFieldType.pushButton);
      expect(editing.selectedWidgetFieldName, 'agree');
      expect(editing.selectedWidgetFieldType, PdfFieldType.pushButton);
      expect(editing.hasAnnotationSelection, isTrue);
    });

    test('setFormFieldStyle rewrites /DA, /Q, /Ff and regenerates', () {
      final editing = controller();
      expect(
          editing.setFormFieldStyle('name',
              font: PdfStandardFont.timesBold,
              fontSize: 20,
              color: 0x0000FF,
              align: PdfTextAlign.center,
              multiline: true),
          isTrue);
      final field = editing.acroForm!.fieldNamed('name')!;
      expect(field.appearanceFontSize, 20);
      expect(field.appearanceColor, 0x0000FF);
      expect(field.quadding, 1);
      expect(field.isMultiline, isTrue);
      expect(field.defaultAppearance, contains('/TimesBold 20 Tf'));
    });

    test('autoSize stores /DA size 0; guards reject non-text fields', () {
      final editing = controller();
      expect(editing.setFormFieldStyle('name', autoSize: true), isTrue);
      expect(editing.acroForm!.fieldNamed('name')!.appearanceFontSize, 0);
      // read-only and non-text fields are rejected
      expect(editing.setFormFieldStyle('serial', fontSize: 10), isFalse);
      expect(editing.setFormFieldStyle('agree', fontSize: 10), isFalse);
      expect(editing.setFormFieldStyle('missing', fontSize: 10), isFalse);
    });
  });

  group('form tool UI', () {
    testWidgets('field-name labels show while the form tool is armed',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final editing = PdfEditingController(buildAcroFormPdf());
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
        ),
      ));
      await tester.pump();

      // no label before the form tool is armed
      expect(find.text('name'), findsNothing);
      editing.tool = PdfEditTool.form;
      await tester.pump();
      expect(find.text('name'), findsOneWidget);

      // disarming the tool hides the labels again
      editing.tool = null;
      await tester.pump();
      expect(find.text('name'), findsNothing);
    });

    testWidgets('properties panel shows form text controls for a text field',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final editing = PdfEditingController(buildAcroFormPdf());
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

      editing.tool = PdfEditTool.form;
      expect(editing.selectFormWidgetAt(0, 186, 712), isTrue);
      await tester.pump();

      expect(find.byKey(const ValueKey('pdf-prop-form-multiline')),
          findsOneWidget);
      // a widget's /T is the field name, not an author: the Author/Contents
      // rows are replaced by a "Field name" row showing the real name
      expect(find.byKey(const ValueKey('pdf-prop-author')), findsNothing);
      expect(find.byKey(const ValueKey('pdf-prop-contents')), findsNothing);
      final nameRow = find.byKey(const ValueKey('pdf-prop-field-name'));
      expect(nameRow, findsOneWidget);
      expect(tester.widget<TextField>(nameRow).controller!.text, 'name');

      // toggling multiline through the panel switch reaches the field
      await tester.tap(find.byKey(const ValueKey('pdf-prop-form-multiline')));
      await tester.pump();
      expect(editing.acroForm!.fieldNamed('name')!.isMultiline, isTrue);

      // editing the field-name row renames the field
      await tester.enterText(nameRow, 'fullName');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(editing.acroForm!.fieldNamed('fullName'), isNotNull);
      expect(editing.acroForm!.fieldNamed('name'), isNull);
    });

    testWidgets('toolbar tune popup carries the form style controls',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final editing = PdfEditingController(buildAcroFormPdf());
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

      editing.tool = PdfEditTool.form;
      expect(editing.selectFormWidgetAt(0, 186, 712), isTrue);
      await tester.pumpAndSettle();

      final tune = find.byIcon(Icons.tune);
      expect(tune, findsOneWidget);
      await tester.tap(tune);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('pdf-form-style-multiline')),
          findsOneWidget);
    });

    testWidgets('selected toolbar changes the selected field type',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final editing = PdfEditingController(buildAcroFormPdf());
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

      editing.tool = PdfEditTool.form;
      expect(editing.selectFormWidgetAt(0, 82, 550), isTrue);
      await tester.pumpAndSettle();

      final typeMenu =
          find.byKey(const ValueKey('pdf-selected-form-field-type'));
      expect(typeMenu, findsOneWidget);
      await tester.tap(typeMenu);
      await tester.pumpAndSettle();
      await tester
          .tap(find.byKey(const ValueKey('pdf-selected-form-type-button')));
      await tester.pumpAndSettle();

      expect(
          editing.acroForm!.fieldNamed('agree')!.type, PdfFieldType.pushButton);
      expect(editing.selectedWidgetFieldName, 'agree');
      expect(typeMenu, findsOneWidget);
    });

    testWidgets('properties panel changes the selected field type',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final editing = PdfEditingController(buildAcroFormPdf());
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

      editing.tool = PdfEditTool.form;
      expect(editing.selectFormWidgetAt(0, 82, 550), isTrue);
      await tester.pumpAndSettle();

      final typeMenu = find.byKey(const ValueKey('pdf-prop-form-type'));
      expect(typeMenu, findsOneWidget);
      expect(find.text('Check box'), findsOneWidget);
      await tester.tap(typeMenu);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('pdf-prop-form-type-text')));
      await tester.pumpAndSettle();

      expect(editing.acroForm!.fieldNamed('agree')!.type, PdfFieldType.text);
      expect(editing.selectedWidgetFieldName, 'agree');
      expect(find.text('Text field'), findsOneWidget);
    });
  });
}
