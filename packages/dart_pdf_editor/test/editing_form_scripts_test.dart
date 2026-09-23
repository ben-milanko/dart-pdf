import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The interactive form layer honours recognised AF* field scripts:
/// keystroke helpers filter typing, keystroke/validate refusals are shown
/// and leave the value alone, and valid entries store normalised values.
void main() {
  const scale = 800 / 612;
  Offset view(double x, double y) => Offset(x * scale, (792 - y) * scale);
  final nameField = view(186, 712);
  final editorKey = find.byKey(const ValueKey('pdf-form-text-editor'));

  /// The fixture form with its 'name' text field turned into a currency
  /// amount between 0 and 1000 (keystroke, format and validate scripts).
  Uint8List scriptedForm() {
    CosDictionary js(String script) => CosDictionary({
          'S': const CosName('JavaScript'),
          'JS': CosString.fromText(script),
        });
    final editor = PdfEditor(PdfDocument.open(buildAcroFormPdf()));
    final field = editor.acroForm!.fieldNamed('name')!;
    field.dict['AA'] = CosDictionary({
      'K': js('AFNumber_Keystroke(2, 0, 0, 0, "\$", true);'),
      'F': js('AFNumber_Format(2, 0, 0, 0, "\$", true);'),
      'V': js('AFRange_Validate(true, 0, true, 1000);'),
    });
    editor.setTextValue(field, '5');
    return editor.save();
  }

  Future<PdfEditingController> pumpViewer(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final session = PdfEditingController(scriptedForm());
    final viewer = PdfViewerController();
    addTearDown(session.dispose);
    addTearDown(viewer.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ListenableBuilder(
          listenable: session,
          builder: (context, _) => PdfViewer(
            initialFit: PdfViewerFit.width,
            document: session.document,
            controller: viewer,
            editing: session,
          ),
        ),
      ),
    ));
    await tester.pump();
    return session;
  }

  Future<void> open(WidgetTester tester) async {
    await tester.tapAt(nameField);
    await tester.pump(const Duration(milliseconds: 400));
    expect(editorKey, findsOneWidget);
  }

  testWidgets('the keystroke script filters what can be typed', (tester) async {
    final session = await pumpViewer(tester);
    await open(tester);
    // the editor shows the raw value, not the formatted "$5.00"
    expect(tester.widget<TextField>(editorKey).controller!.text, '5');

    await tester.enterText(editorKey, '12.5');
    expect(tester.widget<TextField>(editorKey).controller!.text, '12.5');
    await tester.enterText(editorKey, '12.5x');
    expect(tester.widget<TextField>(editorKey).controller!.text, '12.5',
        reason: 'a letter is refused by AFNumber_Keystroke');

    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle(const Duration(milliseconds: 300));
    final field = session.acroForm!.fieldNamed('name')!;
    expect(field.value, '12.5');
    expect(field.formattedValue, r'$12.50');
  });

  testWidgets('Enter on a refused value keeps the editor open with the reason',
      (tester) async {
    final session = await pumpViewer(tester);
    await open(tester);
    await tester.enterText(editorKey, '2000');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(editorKey, findsOneWidget);
    expect(find.byKey(const ValueKey('pdf-form-input-error-label')),
        findsOneWidget);
    expect(find.textContaining('less than or equal to 1000'), findsOneWidget);
    expect(session.acroForm!.fieldNamed('name')!.value, '5');

    // editing clears the message; a valid value then commits
    await tester.enterText(editorKey, '999');
    await tester.pump();
    expect(
        find.byKey(const ValueKey('pdf-form-input-error-label')), findsNothing);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle(const Duration(milliseconds: 300));
    expect(editorKey, findsNothing);
    expect(session.acroForm!.fieldNamed('name')!.value, '999');
  });

  testWidgets('leaving a refused value drops it and says why', (tester) async {
    final session = await pumpViewer(tester);
    await open(tester);
    await tester.enterText(editorKey, '-3');
    await tester.tapAt(view(450, 620)); // outside the field
    await tester.pump(const Duration(milliseconds: 400));

    expect(editorKey, findsNothing);
    expect(session.acroForm!.fieldNamed('name')!.value, '5');
    expect(find.byKey(const ValueKey('pdf-form-input-error')), findsOneWidget);
    expect(find.textContaining('greater than or equal to 0'), findsOneWidget);
    await tester.pumpAndSettle(const Duration(seconds: 5));
  });

  test('controller checks and normalises without editing', () {
    final session = PdfEditingController(scriptedForm());
    addTearDown(session.dispose);
    expect(session.checkFormFieldText('name', r'$1,000.00').value, '1000.00');
    expect(session.checkFormFieldText('name', 'x').isValid, isFalse);
    expect(session.setFormFieldText('name', 'x'), isFalse);
    expect(session.setFormFieldText('name', r'$7'), isTrue);
    expect(session.acroForm!.fieldNamed('name')!.value, '7');
    // an unknown name has nothing to check
    expect(session.checkFormFieldText('nope', 'x').isValid, isTrue);
  });
}
