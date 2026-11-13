import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_cos/pdf_cos.dart';
import 'package:dart_pdf_editor/src/editing/editing_form_style.dart';
import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  PdfEditingController controller() {
    SharedPreferences.setMockInitialValues({});
    return PdfEditingController(buildAcroFormPdf());
  }

  // Use arbitrary resource keys to exercise the /DA -> /DR lookup, not the
  // old heuristic that guessed a family from a resource key's spelling.
  void setFontResource(PdfFormField field, String baseFont,
      {String resourceName = 'CustomFace'}) {
    final cos = field.form.document.cos;
    final fonts =
        cos.resolve(field.form.defaultResources!['Font']) as CosDictionary;
    fonts[resourceName] = CosDictionary({
      'Type': CosName('Font'),
      'Subtype': CosName('Type1'),
      'BaseFont': CosName(baseFont),
    });
    field.dict['DA'] = CosString.fromText('/$resourceName 12 Tf 0 g');
  }

  group('form field style controller API', () {
    test('font family and style follow the /DR resource, not its alias', () {
      final editing = controller();
      addTearDown(editing.dispose);
      final field = editing.acroForm!.fieldNamed('name')!;
      setFontResource(field, 'Times-BoldItalic');
      final style = PdfFormFieldStyle.of(field);
      expect(style.font, PdfStandardFont.timesBoldItalic);
      expect(style.fontLabel, 'Serif');
    });

    test('custom and unavailable font names are not falsely labelled Sans', () {
      final editing = controller();
      addTearDown(editing.dispose);
      final field = editing.acroForm!.fieldNamed('name')!;
      setFontResource(field, 'ABCDEF+Spectral-Regular');
      expect(PdfFormFieldStyle.of(field).fontLabel, 'Spectral-Regular');
      field.dict['DA'] = CosString.fromText('/MissingFont 12 Tf 0 g');
      expect(PdfFormFieldStyle.of(field).fontLabel, 'MissingFont');
    });

    test('embedded font label survives style changes and save/reopen', () {
      final editing = controller();
      addTearDown(editing.dispose);
      final embedded = PdfEmbeddedFont.parse(
          File('../pdf_document/test/fonts/DejaVuSans.ttf').readAsBytesSync());
      expect(editing.setFormFieldStyle('name', font: embedded), isTrue);
      expect(editing.selectFormFieldByName('name'), isTrue);
      expect(
          editing.selectedFormFieldStyle!.fontLabel, embedded.postScriptName);
      expect(
          editing.setSelectedFormFieldStyle(
              color: 0x0000FF, align: PdfTextAlign.center),
          isTrue);
      final reopened = PdfEditingController(editing.bytes);
      addTearDown(reopened.dispose);
      expect(reopened.selectFormFieldByName('name'), isTrue);
      expect(
          reopened.selectedFormFieldStyle!.fontLabel, embedded.postScriptName);
      final field = reopened.acroForm!.fieldNamed('name')!;
      final cos = field.form.document.cos;
      final fonts =
          cos.resolve(field.form.defaultResources!['Font']) as CosDictionary;
      final resourceName = RegExp(r'/(\S+)\s+[\d.]+\s+Tf')
          .firstMatch(field.defaultAppearance!)!
          .group(1)!;
      final resource = cos.resolve(fonts[resourceName]) as CosDictionary;
      final recovered =
          PdfEmbeddedFont.fromFontDict(cos, resource, resourceName)!;
      expect(recovered.fontBytes, embedded.fontBytes);
    });

    test('choice fields resolve custom font metadata too', () {
      SharedPreferences.setMockInitialValues({});
      final editing = PdfEditingController(buildListBoxFormPdf());
      addTearDown(editing.dispose);
      for (final name in ['toppings', 'size']) {
        final field = editing.acroForm!.fieldNamed(name)!;
        setFontResource(field, 'ABCDEF+Spectral-Regular');
        expect(PdfFormFieldStyle.of(field).fontLabel, 'Spectral-Regular');
      }
    });

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
    testWidgets('both controls show the custom font and mixed fonts vary',
        (tester) async {
      tester.view.physicalSize = const Size(1200, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final editing = controller();
      addTearDown(editing.dispose);
      setFontResource(
          editing.acroForm!.fieldNamed('name')!, 'ABCDEF+Spectral-Regular',
          resourceName: 'SpectralFace');
      expect(editing.selectFormFieldByName('name'), isTrue);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          PdfAnnotationPropertiesPanel(controller: editing),
          SizedBox(
              width: 320,
              child: PdfFormFieldStyleControls(controller: editing)),
        ])),
      ));
      await tester.pump();
      for (final key in ['pdf-prop-form-font', 'pdf-form-style-font-menu']) {
        final button = find.byKey(ValueKey(key));
        expect(button, findsOneWidget);
        expect(
            find.descendant(
                of: button, matching: find.text('Spectral-Regular')),
            findsOneWidget);
        expect(find.descendant(of: button, matching: find.text('Sans')),
            findsNothing);
      }
      // Both custom faces map to the same standard fallback. Their names
      // must still be compared so the panel does not claim a common font.
      setFontResource(
          editing.acroForm!.fieldNamed('address')!, 'UVWXYZ+Lobster-Regular');
      expect(editing.selectFormWidgetAt(0, 186, 640, toggle: true), isTrue);
      await tester.pump();
      expect(find.byKey(const ValueKey('pdf-prop-form-font-varies')),
          findsOneWidget);
    });

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

      // the popup's multiline switch reaches the text field
      await tester.tap(find.byKey(const ValueKey('pdf-form-style-multiline')));
      await tester.pumpAndSettle();
      expect(editing.acroForm!.fieldNamed('name')!.isMultiline, isTrue);
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
