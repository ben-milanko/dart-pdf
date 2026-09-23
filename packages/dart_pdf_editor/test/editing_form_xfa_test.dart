import 'dart:typed_data';

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// XFA forms (#929): a dynamic (XFA-only) form gets a one-time notice
/// instead of silently showing no fields, and filling a hybrid form's
/// AcroForm fields drops the stale XFA copy.
void main() {
  const notice = ValueKey('pdf-xfa-form-notice');

  Future<PdfEditingController> pumpViewer(
    WidgetTester tester,
    Uint8List bytes, {
    bool asReader = true,
    bool interactiveForms = true,
    PdfEditingController? session,
  }) async {
    SharedPreferences.setMockInitialValues({});
    final controller = session ?? PdfEditingController(bytes);
    if (session == null) addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PdfViewer(
          key: UniqueKey(),
          initialFit: PdfViewerFit.width,
          document: controller.document,
          editing: asReader ? null : controller,
          formController: asReader ? controller : null,
          interactiveForms: interactiveForms,
        ),
      ),
    ));
    await tester.pump();
    await tester.pump();
    return controller;
  }

  testWidgets('a dynamic XFA form shows the notice once per session',
      (tester) async {
    final session =
        await pumpViewer(tester, buildXfaFormPdf(withFields: false));
    expect(find.byKey(notice), findsOneWidget);
    expect(find.textContaining('XFA'), findsOneWidget);

    // dismiss it, then remount a viewer on the same session (a tab switch):
    // it must not come back
    ScaffoldMessenger.of(tester.element(find.byType(PdfViewer)))
        .removeCurrentSnackBar();
    await tester.pumpAndSettle();
    await pumpViewer(tester, Uint8List(0), session: session);
    await tester.pumpAndSettle();
    expect(find.byKey(notice), findsNothing);
  });

  testWidgets('the editor path shows the notice too', (tester) async {
    await pumpViewer(tester, buildXfaFormPdf(needsRendering: true),
        asReader: false);
    expect(find.byKey(notice), findsOneWidget);
  });

  testWidgets('a hybrid form and a plain AcroForm show no notice',
      (tester) async {
    await pumpViewer(tester, buildXfaFormPdf());
    expect(find.byKey(notice), findsNothing);
    await pumpViewer(tester, buildAcroFormPdf());
    expect(find.byKey(notice), findsNothing);
  });

  testWidgets('no notice when interactive forms are off', (tester) async {
    await pumpViewer(tester, buildXfaFormPdf(withFields: false),
        interactiveForms: false);
    expect(find.byKey(notice), findsNothing);
  });

  test('filling a hybrid form drops /XFA; undo brings it back', () {
    final session = PdfEditingController(buildXfaFormPdf());
    addTearDown(session.dispose);
    expect(session.acroForm!.hasXfa, isTrue);

    expect(session.setFormFieldText('name', 'fresh'), isTrue);
    final form = session.acroForm!;
    expect(form.hasXfa, isFalse);
    expect(form.fieldNamed('name')!.value, 'fresh');
    // the saved bytes carry the change, not just the in-memory revision
    expect(PdfAcroForm.of(PdfDocument.open(session.bytes))!.hasXfa, isFalse);

    session.undo();
    expect(session.acroForm!.hasXfa, isTrue);
  });
}
