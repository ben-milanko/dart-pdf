import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Form authoring for radio groups, choice fields and empty signature
/// fields in the editing UI (#934).
void main() {
  PdfEditingController blank() {
    SharedPreferences.setMockInitialValues({});
    return PdfEditingController(buildClassicPdf());
  }

  group('controller authoring API', () {
    test('addFormField creates every new kind', () {
      final editing = blank();
      addTearDown(editing.dispose);
      final radio = editing.addFormField(
          PdfFormFieldKind.radioGroup, 0, const PdfRect(50, 700, 66, 716))!;
      final combo = editing.addFormField(
          PdfFormFieldKind.comboBox, 0, const PdfRect(50, 650, 250, 672))!;
      final list = editing.addFormField(
          PdfFormFieldKind.listBox, 0, const PdfRect(50, 560, 250, 640))!;
      final sig = editing.addFormField(
          PdfFormFieldKind.signature, 0, const PdfRect(50, 480, 250, 540))!;

      final form = PdfAcroForm.of(PdfDocument.open(editing.bytes))!;
      final radioField = form.fieldNamed(radio)!;
      expect(radioField.type, PdfFieldType.radioGroup);
      expect(radioField.onStates, ['Choice1']);
      expect(form.fieldNamed(combo)!.type, PdfFieldType.comboBox);
      expect(form.fieldNamed(list)!.type, PdfFieldType.listBox);
      final sigField = form.fieldNamed(sig)!;
      expect(sigField.type, PdfFieldType.signature);
      expect(sigField.dict['V'], isNull);
      expect(form.dict['SigFlags'], const CosInteger(1));
      for (final kind in PdfFormFieldKind.values) {
        expect(PdfFormFieldKind.of(kind.fieldType), kind);
      }
    });

    test('addFormRadioButton grows the group and selects the new button', () {
      final editing = blank();
      addTearDown(editing.dispose);
      final name = editing.addFormField(
          PdfFormFieldKind.radioGroup, 0, const PdfRect(50, 700, 66, 716))!;
      expect(editing.addFormRadioButton(name), 'Choice2');
      final field = editing.acroForm!.fieldNamed(name)!;
      expect(field.onStates, ['Choice1', 'Choice2']);
      // same size, stacked below the last button
      expect(field.widgetRect(1), const PdfRect(50, 676, 66, 692));
      expect(editing.selectedWidgetFieldName, name);

      expect(editing.setFormRadioValue(name, 'Choice2'), isTrue);
      expect(editing.acroForm!.fieldNamed(name)!.value, 'Choice2');
      // the group was one revision per step: undo the fill, then the add
      editing.undo();
      editing.undo();
      expect(editing.acroForm!.fieldNamed(name)!.onStates, ['Choice1']);

      expect(editing.addFormRadioButton('missing'), isNull);
      final text = editing.addFormField(
          PdfFormFieldKind.text, 0, const PdfRect(300, 700, 400, 720))!;
      expect(editing.addFormRadioButton(text), isNull);
    });

    test('a button at the page bottom goes beside, not off the page', () {
      final editing = blank();
      addTearDown(editing.dispose);
      final name = editing.addFormField(
          PdfFormFieldKind.radioGroup, 0, const PdfRect(50, 4, 66, 20))!;
      editing.addFormRadioButton(name);
      expect(editing.acroForm!.fieldNamed(name)!.widgetRect(1),
          const PdfRect(74, 4, 90, 20));
    });

    test('setFormFieldOptions edits options and flags', () {
      final editing = blank();
      addTearDown(editing.dispose);
      final combo = editing.addFormField(
          PdfFormFieldKind.comboBox, 0, const PdfRect(50, 650, 250, 672))!;
      expect(
          editing.setFormFieldOptions(combo, const [('a', 'Apple'), ('b', 'b')],
              editable: true),
          isTrue);
      expect(
          editing.setFormFieldOptions(combo, const [('a', 'Apple'), ('b', 'b')],
              editable: true),
          isFalse,
          reason: 'unchanged');
      final field =
          PdfAcroForm.of(PdfDocument.open(editing.bytes))!.fieldNamed(combo)!;
      expect(field.options, const [('a', 'Apple'), ('b', 'b')]);
      expect(field.flags & PdfFormField.editFlag, isNot(0));
      expect(editing.setFormChoiceValue(combo, 'Apple'), isTrue);
      expect(editing.acroForm!.fieldNamed(combo)!.value, 'a');

      expect(editing.setFormFieldOptions('missing', const []), isFalse);
    });

    test('changeFormFieldKind reaches the new kinds', () {
      SharedPreferences.setMockInitialValues({});
      final editing = PdfEditingController(buildAcroFormPdf());
      addTearDown(editing.dispose);
      expect(editing.changeFormFieldKind('name', PdfFormFieldKind.comboBox),
          isTrue);
      expect(editing.acroForm!.fieldNamed('name')!.type, PdfFieldType.comboBox);
      expect(editing.changeFormFieldKind('name', PdfFormFieldKind.signature),
          isTrue);
      expect(
          editing.acroForm!.fieldNamed('name')!.type, PdfFieldType.signature);
      expect(editing.changeFormFieldKind('color', PdfFormFieldKind.listBox),
          isTrue);
      expect(editing.acroForm!.fieldNamed('color')!.options,
          const [('Red', 'Red'), ('Blue', 'Blue')]);
    });

    test('a placed signature field is signed later by name', () {
      final editing = blank();
      addTearDown(editing.dispose);
      final name = editing.addFormField(
          PdfFormFieldKind.signature, 0, const PdfRect(50, 480, 250, 540))!;
      final signed = PdfEditor(PdfDocument.open(editing.bytes)).saveSigned(
        privateKey: RsaPrivateKey.fromPem(testSignerKeyPem),
        certificates: [pemBytes(testSignerCertPem)],
        fieldName: name,
      );
      final signature = PdfSignature.of(PdfDocument.open(signed)).single;
      expect(signature.field.name, name);
      expect(signature.validate().intact, isTrue);
    });
  });

  group('form authoring UI', () {
    // 800px viewport over a 612pt page
    const scale = 800 / 612;
    Offset view(double x, double y) => Offset(x * scale, (792 - y) * scale);

    Future<PdfEditingController> pumpEditor(WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({});
      final editing = PdfEditingController(buildAcroFormPdf());
      final viewer = PdfViewerController();
      addTearDown(editing.dispose);
      addTearDown(viewer.dispose);
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 800,
            child: PdfViewer(
              initialFit: PdfViewerFit.width,
              controller: viewer,
              editing: editing,
            ),
          ),
          bottomNavigationBar: PdfEditingToolbar(
            controller: editing,
            viewerController: viewer,
          ),
        ),
      ));
      await tester.pump();
      return editing;
    }

    Future<void> selectField(WidgetTester tester, Offset at) async {
      await tester.tapAt(at,
          kind: PointerDeviceKind.mouse, buttons: kSecondaryMouseButton);
      await tester.pumpAndSettle();
    }

    Future<void> drag(WidgetTester tester, Offset from, Offset to) async {
      final gesture = await tester.startGesture(from);
      await gesture.moveTo(Offset.lerp(from, to, 0.5)!);
      await gesture.moveTo(to);
      await gesture.up();
      await tester.pump();
    }

    testWidgets('dragging with a new kind armed places that field',
        (tester) async {
      final editing = await pumpEditor(tester);
      editing.tool = PdfEditTool.form;
      editing.newFormFieldKind = PdfFormFieldKind.signature;
      await tester.pump();
      await drag(tester, view(350, 300), view(550, 240));
      final field = editing.acroForm!.fieldNamed('Field 1')!;
      expect(field.type, PdfFieldType.signature);
      await tester.pumpAndSettle(const Duration(milliseconds: 300));
    });

    testWidgets('the selected radio group takes another button',
        (tester) async {
      final editing = await pumpEditor(tester);
      await selectField(tester, view(82, 510)); // "color", Red
      expect(editing.selectedWidgetFieldName, 'color');
      final add = find.byKey(const ValueKey('pdf-selected-form-add-radio'));
      expect(add, findsOneWidget);
      expect(find.byKey(const ValueKey('pdf-selected-form-options')),
          findsNothing);
      await tester.tap(add);
      await tester.pumpAndSettle();
      final field = editing.acroForm!.fieldNamed('color')!;
      expect(field.widgets, hasLength(3));
      expect(field.onStates.last, 'Choice3');
      expect(editing.selectedWidgetFieldName, 'color');
    });

    testWidgets('the options editor rewrites a combo box', (tester) async {
      final editing = await pumpEditor(tester);
      await selectField(tester, view(136, 472)); // "size"
      expect(editing.selectedWidgetFieldName, 'size');
      await tester.tap(find.byKey(const ValueKey('pdf-selected-form-options')));
      await tester.pumpAndSettle();
      expect(find.byType(PdfFormOptionsEditor), findsOneWidget);
      // the fixture's three options are listed; drop the first, add one
      expect(find.byKey(const ValueKey('pdf-form-options-export-2')),
          findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('pdf-form-options-remove-0')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('pdf-form-options-add')));
      await tester.pump();
      await tester.enterText(
          find.byKey(const ValueKey('pdf-form-options-export-2')), 'XL');
      await tester.enterText(
          find.byKey(const ValueKey('pdf-form-options-display-2')),
          'Extra large');
      await tester.tap(find.byKey(const ValueKey('pdf-form-options-flag')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('pdf-form-options-save')));
      await tester.pumpAndSettle();

      final field = editing.acroForm!.fieldNamed('size')!;
      expect(field.options,
          const [('Medium', 'Medium'), ('L', 'Large'), ('XL', 'Extra large')]);
      expect(field.flags & PdfFormField.editFlag, isNot(0));
      expect(field.value, 'Medium', reason: 'still offered, so kept');
    });

    testWidgets('the field-type menu converts to the new kinds',
        (tester) async {
      final editing = await pumpEditor(tester);
      await selectField(tester, view(186, 712)); // "name"
      await tester
          .tap(find.byKey(const ValueKey('pdf-selected-form-field-type')));
      await tester.pumpAndSettle();
      for (final key in ['radio', 'combo', 'list', 'signature']) {
        expect(find.byKey(ValueKey('pdf-selected-form-type-$key')),
            findsOneWidget);
      }
      await tester
          .tap(find.byKey(const ValueKey('pdf-selected-form-type-list')));
      await tester.pumpAndSettle();
      expect(editing.acroForm!.fieldNamed('name')!.type, PdfFieldType.listBox);
      expect(editing.selectedWidgetFieldName, 'name');
    });
  });

  group('form field menu', () {
    Future<PdfEditingController> openMenu(
        WidgetTester tester, String fieldName) async {
      SharedPreferences.setMockInitialValues({});
      final editing = PdfEditingController(buildAcroFormPdf());
      addTearDown(editing.dispose);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () => showPdfFormFieldMenu(
                  context: context,
                  position: const Offset(200, 200),
                  controller: editing,
                  fieldName: fieldName,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      return editing;
    }

    testWidgets('a radio group offers another button and new conversions',
        (tester) async {
      final editing = await openMenu(tester, 'color');
      expect(find.byKey(const ValueKey('pdf-form-menu-options')), findsNothing);
      for (final key in ['combo', 'list', 'signature']) {
        expect(find.byKey(ValueKey('pdf-form-menu-$key')), findsOneWidget);
      }
      await tester.tap(find.byKey(const ValueKey('pdf-form-menu-add-radio')));
      await tester.pumpAndSettle();
      expect(editing.acroForm!.fieldNamed('color')!.widgets, hasLength(3));
    });

    testWidgets('a combo box opens the options editor', (tester) async {
      await openMenu(tester, 'size');
      expect(
          find.byKey(const ValueKey('pdf-form-menu-add-radio')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('pdf-form-menu-options')));
      await tester.pumpAndSettle();
      expect(find.byType(PdfFormOptionsEditor), findsOneWidget);
      expect(find.text('Allow custom text'), findsOneWidget);
    });
  });
}
