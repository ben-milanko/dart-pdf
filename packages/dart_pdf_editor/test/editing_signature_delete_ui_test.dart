import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  List<PdfAnnotation> stamps(PdfEditingController editing, int page) =>
      editing.document
          .page(page)
          .annotations
          .where((annotation) => annotation.subtype == 'Stamp')
          .toList();

  testWidgets('a signed box can be selected and deleted from the toolbar',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final editing = PdfEditingController(buildMultiPagePdf(2));
    final viewer = PdfViewerController();
    addTearDown(editing.dispose);
    addTearDown(viewer.dispose);
    expect(
      await editing.addSelfSignedSignature(
        PdfSigningIdentity.generate(name: 'Ada Lovelace'),
        appearance: const PdfSignatureAppearance(
          page: 0,
          rect: PdfRect(72, 640, 320, 720),
          repeatPages: [1],
        ),
      ),
      isTrue,
    );
    final fieldName = editing.signatures.single.field.name;
    expect(stamps(editing, 1), hasLength(1));

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
        bottomNavigationBar: PdfEditingToolbar(
          controller: editing,
          viewerController: viewer,
        ),
      ),
    ));
    await tester.pump();

    final signedBox = find.byKey(ValueKey('pdf-form-field-0-$fieldName-0'));
    expect(signedBox, findsOneWidget);
    await tester.tap(signedBox, kind: PointerDeviceKind.mouse);
    await tester.pump();

    expect(editing.selectedWidgetFieldName, fieldName);
    final delete = find.byKey(const ValueKey('pdf-selected-signature-delete'));
    expect(delete, findsOneWidget);
    await tester.tap(delete);
    await tester.pumpAndSettle();
    expect(find.text('Remove signature?'), findsOneWidget);

    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle(const Duration(milliseconds: 300));
    expect(editing.signatures, isEmpty);
    expect(stamps(editing, 1), isEmpty,
        reason: 'apply-to-pages appearance copies must be removed too');

    editing.undo();
    expect(editing.signatures, hasLength(1));
    expect(stamps(editing, 1), hasLength(1));
    await tester.pump(const Duration(milliseconds: 400));
  });

  test('Delete/Backspace cleanup removes signature appearance copies',
      () async {
    final editing = PdfEditingController(buildMultiPagePdf(2));
    addTearDown(editing.dispose);
    expect(
      await editing.addSelfSignedSignature(
        PdfSigningIdentity.generate(name: 'Grace Hopper'),
        appearance: const PdfSignatureAppearance(
          page: 0,
          rect: PdfRect(72, 640, 320, 720),
          repeatPages: [1],
        ),
      ),
      isTrue,
    );
    final rect = editing.signatures.single.field.widgetRect(0)!;
    expect(
      editing.selectFormWidgetAt(
        0,
        (rect.left + rect.right) / 2,
        (rect.bottom + rect.top) / 2,
      ),
      isTrue,
    );

    editing.deleteSelected();

    expect(editing.signatures, isEmpty);
    expect(stamps(editing, 1), isEmpty);
  });
}
