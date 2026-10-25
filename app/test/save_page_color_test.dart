import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dart_pdf_editor_app/editor_screen.dart';
import 'package:dart_pdf_editor_app/file_io.dart';

void main() {
  late PdfEditingPreferences prefs;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    prefs = PdfEditingPreferences();
  });

  tearDown(() => prefs.dispose());

  /// Opens [bytes], draws a stroke, presses Ctrl+S and returns what reached the save seam.
  Future<Uint8List?> save(WidgetTester tester, Uint8List bytes) async {
    Uint8List? saved;
    await tester.pumpWidget(MaterialApp(
        home: EditorScreen(
      prefs: prefs,
      initialDocument: (bytes: bytes, title: 'paper.pdf'),
      saveDocumentAs: (context, bytes, suggestedName) async {
        saved = Uint8List.fromList(bytes);
        return SaveResult.cancelled;
      },
    )));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.byType(PdfViewer), kind: PointerDeviceKind.mouse);
    // Save acts on an edited document
    tester
        .widget<PdfEditorView>(find.byType(PdfEditorView))
        .controller!
        .addInkStroke(0, const [(100, 100), (150, 150)]);
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    return saved;
  }

  String content(Uint8List bytes) =>
      String.fromCharCodes(PdfDocument.open(bytes).page(0).contentBytes());

  testWidgets('the page colour stays display-only by default', (tester) async {
    prefs.pageColor = const Color(0xFFF4ECD8);
    final saved = await save(tester, buildClassicPdf());
    expect(saved, isNotNull);
    expect(content(saved!), isNot(contains('re f')));
  });

  testWidgets('with the option on, Save paints the page colour into the file',
      (tester) async {
    prefs
      ..pageColor = const Color(0xFF000000)
      ..bakePageColor = true;
    final saved = await save(tester, buildClassicPdf());
    expect(saved, isNotNull);
    expect(content(saved!), contains('q 0 0 0 rg'));
  });

  testWidgets('a signed document is saved without the colour', (tester) async {
    prefs
      ..pageColor = const Color(0xFF000000)
      ..bakePageColor = true;
    final signed = PdfEditor(PdfDocument.open(buildClassicPdf()))
        .saveSelfSigned(
            identity: PdfSigningIdentity.generate(name: 'Ada Lovelace'));
    final saved = await save(tester, signed);
    expect(saved, isNotNull);
    expect(content(saved!), isNot(contains('/Background')));
    expect(find.textContaining("wasn't saved into the file"), findsOneWidget);
  });
}
