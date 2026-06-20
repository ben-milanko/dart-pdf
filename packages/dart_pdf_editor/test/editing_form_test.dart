import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:shared_preferences/shared_preferences.dart';

// 2x2 RGBA PNG: red, half-green / transparent blue, near-black at alpha 77
final _png = base64.decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAYAAABytg0kAAAAGUlEQVR4nGP4z8DwHwgb'
    'WBgZ/jNyicr7AgA3BAUOTnqjAAAAAABJRU5ErkJggg==');

void main() {
  PdfEditingController controller() {
    SharedPreferences.setMockInitialValues({});
    return PdfEditingController(buildAcroFormPdf());
  }

  /// The decoded /AP /N content of [field]'s widget [index].
  String widgetAppearance(PdfDocument doc, PdfFormField field,
      [int index = 0]) {
    final cos = doc.cos;
    final ap = cos.resolve(field.widgets[index]['AP']) as CosDictionary;
    var n = cos.resolve(ap['N']);
    if (n is CosDictionary) {
      final state = cos.resolve(field.widgets[index]['AS']);
      n = cos.resolve(n[(state as CosName).value]);
    }
    return latin1.decode(cos.decodeStreamData(n as CosStream));
  }

  group('controller form API', () {
    test('acroForm is cached per revision and formFieldAt resolves hits', () {
      final editing = controller();
      expect(identical(editing.acroForm, editing.acroForm), isTrue);

      final name = editing.formFieldAt(0, 186, 712);
      expect(name, isNotNull);
      expect(name!.$1.name, 'name');
      expect(name.$2, 0);

      // the radio group's second kid resolves with its widget index
      final blue = editing.formFieldAt(0, 130, 510)!;
      expect(blue.$1.name, 'color');
      expect(blue.$2, 1);
      expect(blue.$1.widgetOnState(blue.$2), 'Blue');

      expect(editing.formFieldAt(0, 400, 100), isNull);
    });

    test('fill operations commit one revision each and undo', () {
      final editing = controller();
      expect(editing.setFormFieldText('name', 'Jane'), isTrue);
      expect(editing.acroForm!.fieldNamed('name')!.value, 'Jane');

      expect(editing.toggleFormCheckBox('agree'), isTrue);
      expect(editing.acroForm!.fieldNamed('agree')!.isChecked, isTrue);
      expect(editing.toggleFormCheckBox('agree'), isTrue);
      expect(editing.acroForm!.fieldNamed('agree')!.isChecked, isFalse);

      expect(editing.setFormRadioValue('color', 'Blue'), isTrue);
      expect(editing.acroForm!.fieldNamed('color')!.value, 'Blue');

      expect(editing.setFormChoiceValue('size', 'L'), isTrue);
      expect(editing.acroForm!.fieldNamed('size')!.value, 'L');

      // text + 2 toggles + radio + choice = 5 revisions
      for (var i = 0; i < 5; i++) {
        expect(editing.canUndo, isTrue);
        editing.undo();
      }
      expect(editing.canUndo, isFalse);
      expect(editing.acroForm!.fieldNamed('name')!.value, 'prefilled');
    });

    test('guards: read-only, type mismatch, unchanged value', () {
      final editing = controller();
      expect(editing.setFormFieldText('serial', 'B-2000'), isFalse);
      expect(editing.setFormFieldText('agree', 'x'), isFalse);
      expect(editing.setFormFieldText('name', 'prefilled'), isFalse,
          reason: 'unchanged value must not burn a revision');
      expect(editing.setFormRadioValue('color', 'Green'), isFalse,
          reason: 'unknown state is swallowed, not thrown');
      expect(editing.setFormFieldText('missing', 'x'), isFalse);
      expect(editing.isModified, isFalse);
    });

    test('form tool selects a widget for move/resize/delete', () {
      final editing = controller();
      editing.tool = PdfEditTool.form;

      // a tap selects the text field's widget (not just the sidebar path)
      expect(editing.selectFormWidgetAt(0, 186, 712), isTrue);
      expect(editing.hasAnnotationSelection, isTrue);
      expect(editing.selectedAnnotation!.subtype, 'Widget');
      expect(editing.canResizeSelected, isTrue,
          reason: 'widgets resize while the form tool is armed');

      final before = editing.acroForm!.fieldNamed('name')!.widgetRect(0)!;

      // move translates the widget /Rect
      editing.moveSelected(20, -10);
      final moved = editing.acroForm!.fieldNamed('name')!.widgetRect(0)!;
      expect(moved.left, closeTo(before.left + 20, 1e-6));
      expect(moved.bottom, closeTo(before.bottom - 10, 1e-6));

      // resize regenerates the appearance at the new size
      final target =
          PdfRect(moved.left, moved.bottom, moved.left + 240, moved.bottom + 40);
      editing.resizeSelected(target);
      final resized = editing.acroForm!.fieldNamed('name')!.widgetRect(0)!;
      expect(resized.width, closeTo(240, 1e-6));
      expect(resized.height, closeTo(40, 1e-6));
      // the value is re-laid into the new box, not stretched
      expect(widgetAppearance(editing.document, editing.acroForm!.fieldNamed('name')!),
          contains('prefilled'));

      // delete drops the whole field, not just the /Annots entry
      expect(
          editing.selectFormWidgetAt(0, resized.left + 5, resized.bottom + 5),
          isTrue);
      editing.deleteSelected();
      expect(editing.acroForm!.fieldNamed('name'), isNull);
      expect(editing.hasAnnotationSelection, isFalse);
    });

    test('canResizeSelected needs the form tool for widgets', () {
      final editing = controller();
      editing.tool = PdfEditTool.form;
      expect(editing.selectFormWidgetAt(0, 186, 712), isTrue);
      expect(editing.canResizeSelected, isTrue);
      // arming another tool drops the widget's resize affordance
      editing.tool = PdfEditTool.select;
      expect(editing.canResizeSelected, isFalse);
    });

    test('setFormButtonImage fills a push button, rejects junk', () {
      final editing = controller();
      final name = editing.addFormField(
          PdfFormFieldKind.pushButton, 0, const PdfRect(400, 600, 500, 640))!;
      expect(editing.setFormButtonImage(name, _png), isTrue);
      final field = editing.acroForm!.fieldNamed(name)!;
      expect(widgetAppearance(editing.document, field), contains('/Img0 Do'));
      expect(editing.setFormButtonImage(name, buildClassicPdf()), isFalse,
          reason: 'not an image');
    });

    test('addFormField generates unique names and creates the form', () {
      SharedPreferences.setMockInitialValues({});
      final editing = PdfEditingController(buildClassicPdf());
      expect(editing.acroForm, isNull);
      final first = editing.addFormField(
          PdfFormFieldKind.text, 0, const PdfRect(50, 600, 250, 640));
      expect(first, 'Field 1');
      final second = editing.addFormField(
          PdfFormFieldKind.checkBox, 0, const PdfRect(50, 550, 70, 570));
      expect(second, 'Field 2');
      final form = editing.acroForm!;
      expect(form.fieldNamed('Field 1')!.type, PdfFieldType.text);
      expect(form.fieldNamed('Field 2')!.type, PdfFieldType.checkBox);
    });

    test('renameFormField guards collisions and empty names', () {
      final editing = controller();
      expect(editing.renameFormField('name', 'agree'), isFalse);
      expect(editing.renameFormField('name', ''), isFalse);
      expect(editing.renameFormField('missing', 'x'), isFalse);
      expect(editing.isModified, isFalse);
      expect(editing.renameFormField('name', 'step/1/response'), isTrue);
      expect(
          editing.acroForm!.fieldNamed('step/1/response')!.value, 'prefilled');
      expect(editing.acroForm!.fieldNamed('name'), isNull);
    });

    test('removeFormField and changeFormFieldKind', () {
      final editing = controller();
      expect(editing.removeFormField('address'), isTrue);
      expect(editing.acroForm!.fieldNamed('address'), isNull);

      expect(
          editing.changeFormFieldKind('name', PdfFormFieldKind.text), isFalse,
          reason: 'already a text field');
      expect(editing.changeFormFieldKind('name', PdfFormFieldKind.pushButton),
          isTrue);
      final rebuilt = editing.acroForm!.fieldNamed('name')!;
      expect(rebuilt.type, PdfFieldType.pushButton);
      expect(rebuilt.widgetRect(0), const PdfRect(72, 700, 300, 724));
    });

    test('flattenFormFields bakes values and clears the form', () {
      final editing = controller();
      editing.setFormFieldText('name', 'Jane');
      expect(editing.flattenFormFields(), isTrue);
      expect(editing.acroForm!.fields, isEmpty);
      // one undo restores the whole form
      editing.undo();
      expect(editing.acroForm!.fieldNamed('name')!.value, 'Jane');
    });
  });

  group('form tool in the viewer', () {
    // 800px viewport over a 612pt page
    const scale = 800 / 612;
    Offset view(double x, double y) => Offset(x * scale, (792 - y) * scale);

    Future<void> drag(WidgetTester tester, Offset from, Offset to) async {
      final gesture = await tester.startGesture(from);
      await gesture.moveTo(Offset.lerp(from, to, 0.5)!);
      await gesture.moveTo(to);
      await gesture.up();
      await tester.pump();
    }

    /// Touch taps resolve only after the viewer's double-tap timeout.
    Future<void> tap(WidgetTester tester, Offset position) async {
      await tester.tapAt(position);
      await tester.pump(const Duration(milliseconds: 400));
    }

    /// Two quick taps — the form tool's fill gesture.
    Future<void> doubleTap(WidgetTester tester, Offset position) async {
      await tester.tapAt(position);
      await tester.pump(const Duration(milliseconds: 60));
      await tester.tapAt(position);
      await tester.pump(const Duration(milliseconds: 400));
    }

    Future<void> settle(WidgetTester tester) =>
        tester.pumpAndSettle(const Duration(milliseconds: 300));

    Future<PdfEditingController> pumpEditor(WidgetTester tester,
        {PdfFormImagePicker? imagePicker, bool toolbar = false}) async {
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
              formImagePicker: imagePicker,
            ),
          ),
          bottomNavigationBar: toolbar
              ? PdfEditingToolbar(controller: editing, viewerController: viewer)
              : null,
        ),
      ));
      await tester.pump();
      return editing;
    }

    testWidgets('single-tapping a field selects it (no fill)', (tester) async {
      final editing = await pumpEditor(tester);
      editing.tool = PdfEditTool.form;
      await tester.pump();

      await tap(tester, view(186, 712));
      expect(find.byKey(const ValueKey('pdf-form-text-editor')), findsNothing,
          reason: 'a single tap selects, it does not fill');
      expect(editing.hasAnnotationSelection, isTrue);
      expect(editing.selectedAnnotation!.subtype, 'Widget');
      expect(editing.canResizeSelected, isTrue);
      expect(editing.isModified, isFalse);
      await settle(tester);
    });

    testWidgets('double-tapping a text field opens an inline editor',
        (tester) async {
      final editing = await pumpEditor(tester);
      editing.tool = PdfEditTool.form;
      await tester.pump();

      await doubleTap(tester, view(186, 712));
      final editor = find.byKey(const ValueKey('pdf-form-text-editor'));
      expect(editor, findsOneWidget);
      expect(editing.isEditingText, isTrue);
      // prefilled with the current value
      expect(tester.widget<TextField>(editor).controller!.text, 'prefilled');

      await tester.enterText(editor, 'Jane');
      await tap(tester, view(450, 620)); // outside the field: commit

      expect(find.byKey(const ValueKey('pdf-form-text-editor')), findsNothing);
      expect(editing.isEditingText, isFalse);
      expect(editing.acroForm!.fieldNamed('name')!.value, 'Jane');
      await settle(tester);
    });

    testWidgets('single-line fields commit on Enter', (tester) async {
      final editing = await pumpEditor(tester);
      editing.tool = PdfEditTool.form;
      await tester.pump();

      await doubleTap(tester, view(186, 712));
      final editor = find.byKey(const ValueKey('pdf-form-text-editor'));
      expect(tester.widget<TextField>(editor).maxLines, 1);
      await tester.enterText(editor, 'submitted');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();

      expect(editing.acroForm!.fieldNamed('name')!.value, 'submitted');
      await settle(tester);
    });

    testWidgets('check box and radio double-taps toggle their states',
        (tester) async {
      final editing = await pumpEditor(tester);
      editing.tool = PdfEditTool.form;
      await tester.pump();

      await doubleTap(tester, view(82, 550));
      expect(editing.acroForm!.fieldNamed('agree')!.isChecked, isTrue);
      await doubleTap(tester, view(82, 550));
      expect(editing.acroForm!.fieldNamed('agree')!.isChecked, isFalse);

      await doubleTap(tester, view(130, 510)); // the /Blue kid widget
      expect(editing.acroForm!.fieldNamed('color')!.value, 'Blue');
      await settle(tester);
    });

    testWidgets('a combo box double-tap offers its options in a menu',
        (tester) async {
      final editing = await pumpEditor(tester);
      editing.tool = PdfEditTool.form;
      await tester.pump();

      await doubleTap(tester, view(136, 472));
      await tester.pumpAndSettle(); // the menu's opening animation
      expect(find.text('Small'), findsOneWidget);
      expect(find.text('Large'), findsOneWidget);

      await tester.tap(find.text('Large'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(editing.acroForm!.fieldNamed('size')!.value, 'L',
          reason: 'the export value is stored');
      await settle(tester);
    });

    testWidgets('read-only fields cannot be filled', (tester) async {
      final editing = await pumpEditor(tester);
      editing.tool = PdfEditTool.form;
      await tester.pump();

      await doubleTap(tester, view(136, 432)); // the read-only serial field
      expect(find.byKey(const ValueKey('pdf-form-text-editor')), findsNothing);
      expect(editing.isModified, isFalse);
      await settle(tester);
    });

    testWidgets('dragging on empty page area adds the armed field kind',
        (tester) async {
      final editing = await pumpEditor(tester);
      editing.tool = PdfEditTool.form;
      editing.newFormFieldKind = PdfFormFieldKind.checkBox;
      await tester.pump();

      await drag(tester, view(400, 650), view(480, 600));
      final field = editing.acroForm!.fieldNamed('Field 1');
      expect(field, isNotNull);
      expect(field!.type, PdfFieldType.checkBox);
      await settle(tester);
    });

    testWidgets('dragging a widget moves it instead of creating a field',
        (tester) async {
      final editing = await pumpEditor(tester);
      editing.tool = PdfEditTool.form;
      await tester.pump();

      final before = editing.acroForm!.fieldNamed('name')!.widgetRect(0);
      await drag(tester, view(186, 712), view(286, 712)); // +100pt in x
      expect(editing.acroForm!.fieldNamed('Field 1'), isNull,
          reason: 'a drag on a widget is not a creation gesture');
      final after = editing.acroForm!.fieldNamed('name')!.widgetRect(0)!;
      expect(after.left, closeTo(before!.left + 100, 1));
      await settle(tester);
    });

    testWidgets('double-tapping a push button runs the image picker',
        (tester) async {
      PdfFormField? picked;
      final editing = await pumpEditor(tester, imagePicker: (context, field) {
        picked = field;
        return Future.value(_png);
      });
      editing.tool = PdfEditTool.form;
      editing.newFormFieldKind = PdfFormFieldKind.pushButton;
      await tester.pump();

      await drag(tester, view(380, 360), view(480, 320));
      expect(editing.acroForm!.fieldNamed('Field 1')!.type,
          PdfFieldType.pushButton);

      await doubleTap(tester, view(430, 340));
      expect(picked?.name, 'Field 1');
      await tester.pump();
      final field = editing.acroForm!.fieldNamed('Field 1')!;
      expect(widgetAppearance(editing.document, field), contains('/Img0 Do'));
      await settle(tester);
    });

    testWidgets('right-clicking a field opens the form menu', (tester) async {
      final editing = await pumpEditor(tester);
      editing.tool = PdfEditTool.form;
      await tester.pump();

      await tester.tapAt(view(186, 712),
          kind: PointerDeviceKind.mouse, buttons: kSecondaryMouseButton);
      await tester.pumpAndSettle();
      expect(
          find.byKey(const ValueKey('pdf-form-menu-rename')), findsOneWidget);
      // converting to its current kind is disabled
      final toText = tester.widget<PopupMenuItem<dynamic>>(
          find.byKey(const ValueKey('pdf-form-menu-text')));
      expect(toText.enabled, isFalse);

      await tester.tap(find.byKey(const ValueKey('pdf-form-menu-delete')));
      await tester.pumpAndSettle();
      expect(editing.acroForm!.fieldNamed('name'), isNull);
      await settle(tester);
    });

    testWidgets('the toolbar arms the tool, picks kinds, and flattens',
        (tester) async {
      final editing = await pumpEditor(tester, toolbar: true);

      // the dock (the group chips) and the contextual strip are the two
      // scrollables inside the toolbar
      final dockScrollable = find
          .descendant(
              of: find.byType(PdfEditingToolbar),
              matching: find.byType(Scrollable))
          .last;
      final stripScrollable = find
          .descendant(
              of: find.byType(PdfEditingToolbar),
              matching: find.byType(Scrollable))
          .first;

      // open the Edit group (its chip may sit off the dock's right edge)
      final editChip = find.byKey(const ValueKey('pdf-group-edit'));
      await tester.scrollUntilVisible(editChip, 80, scrollable: dockScrollable);
      await tester.tap(editChip);
      await tester.pump();

      // the form tool now lives in the group's strip
      final formButton = find.byTooltip(
          'Form fields — tap to select, double-tap to fill, drag to add (F)');
      await tester.scrollUntilVisible(formButton, 80,
          scrollable: stripScrollable);
      await tester.tap(formButton);
      await tester.pump();
      expect(editing.tool, PdfEditTool.form);

      final typePicker = find.byKey(const ValueKey('pdf-form-field-type'));
      await tester.scrollUntilVisible(typePicker, 80,
          scrollable: stripScrollable);
      await tester.tap(typePicker);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('pdf-form-type-checkbox')));
      await tester.pumpAndSettle();
      expect(editing.newFormFieldKind, PdfFormFieldKind.checkBox);

      final flatten =
          find.byTooltip('Flatten form — bake values into the pages');
      await tester.scrollUntilVisible(flatten, 80,
          scrollable: stripScrollable);
      await tester.tap(flatten);
      await tester.pump();
      expect(editing.acroForm!.fields, isEmpty);
      await settle(tester);
    });
  });
}
