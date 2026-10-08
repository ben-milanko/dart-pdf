import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Bulk editing of several selected form fields (#1041): one style or size
/// edit applies to every selected field as a single revision.
void main() {
  // buildAcroFormPdf's text fields: 'name' [72 700 300 724], 'address'
  // [72 600 300 680] (multiline), 'serial' [72 420 200 444] (read-only);
  // 'agree' is a check box at [72 540 92 560].
  PdfEditingController controller() {
    SharedPreferences.setMockInitialValues({});
    return PdfEditingController(buildAcroFormPdf())..tool = PdfEditTool.form;
  }

  void selectNameAndAddress(PdfEditingController editing) {
    expect(editing.selectFormWidgetAt(0, 186, 712), isTrue);
    expect(editing.selectFormWidgetAt(0, 186, 640, toggle: true), isTrue);
  }

  group('bulk form-field controller API', () {
    test('several selected text fields are styleable together', () {
      final editing = controller();
      selectNameAndAddress(editing);
      expect(editing.selectedFormWidgetCount, 2);
      expect(editing.canStyleSelectedFormField, isTrue);
      // the single-field handle is for one field only
      expect(editing.selectedFormFieldName, isNull);
      // primary (most recently selected) first
      expect(editing.selectedFormStyleFieldNames, ['address', 'name']);
      final styles = editing.selectedFormFieldStyles;
      expect(styles, hasLength(2));
      expect(styles.map((s) => s.multiline), [true, false]);
      expect(editing.selectedFormFieldStyle!.multiline, isTrue);
    });

    test('setSelectedFormFieldStyle restyles every field as one revision', () {
      final editing = controller();
      selectNameAndAddress(editing);
      final before = editing.bytes.length;
      expect(
          editing.setSelectedFormFieldStyle(
              font: PdfStandardFont.courier,
              fontSize: 10,
              color: 0xFF0000,
              align: PdfTextAlign.right),
          isTrue);
      for (final name in ['name', 'address']) {
        final field = editing.acroForm!.fieldNamed(name)!;
        expect(field.appearanceFontSize, 10, reason: name);
        expect(field.appearanceColor, 0xFF0000, reason: name);
        expect(field.quadding, PdfTextAlign.right.quadding, reason: name);
        expect(field.defaultAppearance, contains('/Cour 10 Tf'), reason: name);
      }
      // the selection survives the edit
      expect(editing.selectedFormWidgetCount, 2);

      // one undo step reverts both
      editing.undo();
      expect(editing.bytes.length, before);
      expect(editing.acroForm!.fieldNamed('name')!.appearanceFontSize, 12);
      expect(editing.acroForm!.fieldNamed('address')!.quadding,
          isNot(PdfTextAlign.right.quadding));
    });

    test('non-text and read-only widgets in the selection are skipped', () {
      final editing = controller();
      expect(editing.selectFormWidgetAt(0, 186, 712), isTrue); // name
      expect(editing.selectFormWidgetAt(0, 82, 550, toggle: true), isTrue);
      expect(editing.selectFormWidgetAt(0, 136, 432, toggle: true), isTrue);
      expect(editing.selectedFormWidgetCount, 3);
      // the check box isn't a text field; the read-only one is listed
      expect(editing.selectedFormStyleFieldNames, ['serial', 'name']);

      expect(editing.setSelectedFormFieldStyle(fontSize: 9), isTrue);
      expect(editing.acroForm!.fieldNamed('name')!.appearanceFontSize, 9);
      expect(
          editing.acroForm!.fieldNamed('serial')!.appearanceFontSize, isNot(9));
    });

    test('only a check box selected leaves nothing to style', () {
      final editing = controller();
      expect(editing.selectFormWidgetAt(0, 82, 550), isTrue);
      expect(editing.canStyleSelectedFormField, isFalse);
      expect(editing.setSelectedFormFieldStyle(fontSize: 9), isFalse);
    });

    test('resizeSelectedFormWidgets sets one size, keeping top-left corners',
        () {
      final editing = controller();
      selectNameAndAddress(editing);
      final before = editing.bytes.length;
      expect(editing.resizeSelectedFormWidgets(height: 20), isTrue);
      final name = editing.acroForm!.fieldNamed('name')!.widgetRect(0)!;
      final address = editing.acroForm!.fieldNamed('address')!.widgetRect(0)!;
      expect(
          [name.left, name.bottom, name.right, name.top], [72, 704, 300, 724]);
      expect([address.left, address.bottom, address.right, address.top],
          [72, 660, 300, 680]);

      expect(editing.resizeSelectedFormWidgets(width: 150), isTrue);
      expect(editing.acroForm!.fieldNamed('name')!.widgetRect(0)!.width, 150);
      expect(
          editing.acroForm!.fieldNamed('address')!.widgetRect(0)!.width, 150);

      // unchanged or invalid sizes add no revision
      final after = editing.bytes.length;
      expect(
          editing.resizeSelectedFormWidgets(width: 150, height: 20), isFalse);
      expect(editing.resizeSelectedFormWidgets(height: 0), isFalse);
      expect(editing.resizeSelectedFormWidgets(), isFalse);
      expect(editing.bytes.length, after);

      editing.undo();
      editing.undo();
      expect(editing.bytes.length, before);
    });

    test('selectFormWidgetsIn rubber-bands widgets', () {
      final editing = controller();
      // a band over the name and address fields only
      expect(
          editing.selectFormWidgetsIn(0, const PdfRect(60, 590, 320, 730)), 2);
      expect(editing.selectedFormWidgetCount, 2);
      // add joins the check box
      expect(
          editing.selectFormWidgetsIn(0, const PdfRect(70, 530, 95, 565),
              add: true),
          1);
      expect(editing.selectedFormWidgetCount, 3);
      // a plain band replaces
      expect(
          editing.selectFormWidgetsIn(0, const PdfRect(70, 530, 95, 565)), 1);
      expect(editing.selectedFormWidgetCount, 1);
    });
  });

  group('bulk form-field UI', () {
    const scale = 800 / 612;
    Offset view(double x, double y) => Offset(x * scale, (792 - y) * scale);

    Future<PdfEditingController> pumpEditor(WidgetTester tester,
        {bool panel = false}) async {
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
              if (panel) PdfAnnotationPropertiesPanel(controller: editing),
            ]),
          ),
        ),
      ));
      await tester.pump();
      return editing;
    }

    testWidgets('shift-drag in the form tool rubber-bands fields',
        (tester) async {
      final editing = await pumpEditor(tester);
      final fieldCount = editing.acroForm!.fields.length;

      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      final gesture = await tester.startGesture(view(320, 735),
          kind: PointerDeviceKind.mouse);
      await gesture.moveTo(view(200, 680));
      await tester.pump();
      await gesture.moveTo(view(60, 590));
      await tester.pump();
      await gesture.up();
      await tester.pump();
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);

      expect(editing.selectedFormWidgetCount, 2);
      expect(editing.selectedFormStyleFieldNames.toSet(), {'name', 'address'});
      // the drag selected - it did not draw a new field
      expect(editing.acroForm!.fields, hasLength(fieldCount));
      await tester.pumpAndSettle(const Duration(milliseconds: 300));
    });

    testWidgets('properties panel edits every selected field', (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final editing = await pumpEditor(tester, panel: true);
      selectNameAndAddress(editing);
      await tester.pump();

      // the multi-selection gets the form text group and bulk size fields
      expect(find.byKey(const ValueKey('pdf-prop-form-multiline')),
          findsOneWidget);
      // multiline differs between the two fields
      expect(
          find.descendant(
              of: find.byKey(const ValueKey('pdf-prop-form-multiline')),
              matching: find.text('Varies')),
          findsOneWidget);
      // the widths match, the heights don't
      final width = find.byKey(const ValueKey('pdf-prop-w'));
      final height = find.byKey(const ValueKey('pdf-prop-h'));
      expect(tester.widget<TextField>(width).controller!.text, '228');
      expect(tester.widget<TextField>(height).controller!.text, isEmpty);

      await tester.enterText(height, '20');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(editing.acroForm!.fieldNamed('name')!.widgetRect(0)!.height, 20);
      expect(
          editing.acroForm!.fieldNamed('address')!.widgetRect(0)!.height, 20);
      expect(editing.acroForm!.fieldNamed('name')!.widgetRect(0)!.width, 228);
      expect(tester.widget<TextField>(height).controller!.text, '20');

      // the multiline switch sets every field to the primary's toggled value
      await tester.tap(find.byKey(const ValueKey('pdf-prop-form-multiline')));
      await tester.pump();
      expect(editing.acroForm!.fieldNamed('name')!.isMultiline, isFalse);
      expect(editing.acroForm!.fieldNamed('address')!.isMultiline, isFalse);
      await tester.pumpAndSettle(const Duration(milliseconds: 300));
    });
  });
}
