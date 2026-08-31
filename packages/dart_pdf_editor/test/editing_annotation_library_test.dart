import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PdfAnnotationSnapshotClipboard.instance.clear();
  });

  test('saved annotation snapshot and preferences round-trip', () async {
    final preferences = PdfEditingPreferences();
    await preferences.ready;
    final editing = PdfEditingController(
      buildMultiPagePdf(1),
      preferences: preferences,
      annotationClipboard: PdfAnnotationSnapshotClipboard(),
    )..addRectangle(0, const PdfRect(100, 650, 250, 750));
    addTearDown(editing.dispose);
    expect(editing.selectAnnotation(0, 0), isTrue);

    final saved = editing.saveSelectedAnnotation('Review box')!;
    expect(saved.snapshot.subtype, 'Square');
    final decoded = PdfSavedAnnotation.decode(saved.encode())!;
    expect(decoded.name, 'Review box');
    expect(decoded.snapshot.rect, const PdfRect(100, 650, 250, 750));

    await pumpEventQueue();
    final reopened = PdfEditingPreferences();
    await reopened.ready;
    expect(reopened.savedAnnotations, hasLength(1));
    expect(reopened.savedAnnotations.single.name, 'Review box');
    expect(reopened.savedAnnotations.single.snapshot.subtype, 'Square');
  });

  test('library item places repeatedly and into another PDF with fresh names',
      () async {
    final preferences = PdfEditingPreferences();
    await preferences.ready;
    final source = PdfEditingController(
      buildMultiPagePdf(1),
      preferences: preferences,
      annotationClipboard: PdfAnnotationSnapshotClipboard(),
    )..addEllipse(0, const PdfRect(100, 650, 220, 730));
    addTearDown(source.dispose);
    source.selectAnnotation(0, 0);
    final saved = source.saveSelectedAnnotation('Inspection circle')!;

    expect(source.placeSavedAnnotation(saved, 0, at: (350, 500)), isTrue);
    expect(source.placeSavedAnnotation(saved, 0, at: (350, 300)), isTrue);
    final sourceCopies = source.document.page(0).annotations.skip(1).toList();
    expect(sourceCopies, hasLength(2));
    expect(sourceCopies[0].name, isNot(sourceCopies[1].name));

    final target = PdfEditingController(
      buildMultiPagePdf(1),
      preferences: preferences,
      annotationClipboard: PdfAnnotationSnapshotClipboard(),
    );
    addTearDown(target.dispose);
    expect(target.placeSavedAnnotation(saved, 0, at: (200, 400)), isTrue);
    final targetCopy = target.document.page(0).annotations.single;
    expect(targetCopy.subtype, 'Circle');
    expect(targetCopy.name, isNot(sourceCopies[0].name));
    expect(targetCopy.name, isNot(sourceCopies[1].name));
  });

  testWidgets('stock library dialog previews and places an item',
      (tester) async {
    final editing = PdfEditingController(
      buildMultiPagePdf(1),
      annotationClipboard: PdfAnnotationSnapshotClipboard(),
    )..addRectangle(0, const PdfRect(100, 650, 250, 750));
    addTearDown(editing.dispose);
    editing.selectAnnotation(0, 0);
    editing.saveSelectedAnnotation('Reusable box');
    editing.deleteSelected();

    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => FilledButton(
          onPressed: () => showPdfAnnotationLibrary(
            context,
            controller: editing,
            pageIndex: 0,
          ),
          child: const Text('library'),
        ),
      ),
    ));
    await tester.tap(find.text('library'));
    await tester.pumpAndSettle();
    expect(find.byType(PdfSavedAnnotationPreview), findsOneWidget);
    expect(find.text('Reusable box'), findsOneWidget);
    expect(find.textContaining('Links and form fields cannot be saved'),
        findsOneWidget);

    await tester
        .tap(find.byKey(const ValueKey('pdf-annotation-library-item-0')));
    await tester.pumpAndSettle();
    expect(find.byType(PdfAnnotationLibraryDialog), findsNothing);
    expect(editing.document.page(0).annotations.single.subtype, 'Square');
    expect(editing.hasAnnotationClipboard, isTrue,
        reason: 'the chosen item stays ready for repeat Paste');
  });

  testWidgets('annotation menu saves a supported selection to the library',
      (tester) async {
    final editing = PdfEditingController(buildMultiPagePdf(1))
      ..addRectangle(0, const PdfRect(100, 650, 250, 750));
    addTearDown(editing.dispose);
    editing.selectAnnotation(0, 0);

    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => FilledButton(
          onPressed: () => showPdfAnnotationMenu(
            context: context,
            position: const Offset(100, 100),
            controller: editing,
            pageIndex: 0,
            textPrompt: (context,
                    {required title, initial = '', multiline = true}) async =>
                'Saved box',
          ),
          child: const Text('menu'),
        ),
      ),
    ));
    await tester.tap(find.text('menu'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('pdf-annot-menu-save-library')),
        findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('pdf-annot-menu-save-library')));
    await tester.pumpAndSettle();
    expect(editing.savedAnnotations.single.name, 'Saved box');
  });
}
