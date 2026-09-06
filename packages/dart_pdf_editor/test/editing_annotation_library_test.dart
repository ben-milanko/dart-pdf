import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:dart_pdf_editor/src/editing/editing_overlay.dart';
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
    expect(editing.groupSavedAnnotation(saved, 'Site review'), isTrue);
    expect(saved.snapshot.subtype, 'Square');
    final grouped = editing.savedAnnotations.single;
    final decoded = PdfSavedAnnotation.decode(grouped.encode())!;
    expect(decoded.name, 'Review box');
    expect(decoded.group, 'Site review');
    expect(decoded.snapshot.rect, const PdfRect(100, 650, 250, 750));

    await pumpEventQueue();
    final reopened = PdfEditingPreferences();
    await reopened.ready;
    expect(reopened.savedAnnotations, hasLength(1));
    expect(reopened.savedAnnotations.single.name, 'Review box');
    expect(reopened.savedAnnotations.single.group, 'Site review');
    expect(reopened.savedAnnotations.single.snapshot.subtype, 'Square');
  });

  test('library groups can move, merge, rename, and remove without data loss',
      () async {
    final editing = PdfEditingController(
      buildMultiPagePdf(1),
      annotationClipboard: PdfAnnotationSnapshotClipboard(),
    )
      ..addRectangle(0, const PdfRect(100, 650, 250, 750))
      ..addEllipse(0, const PdfRect(300, 650, 400, 750));
    addTearDown(editing.dispose);
    editing.selectAnnotation(0, 0);
    final box = editing.saveSelectedAnnotation('Review box')!;
    editing.selectAnnotation(0, 1);
    final circle = editing.saveSelectedAnnotation('Inspection circle')!;

    expect(editing.groupSavedAnnotation(box, 'Review'), isTrue);
    expect(editing.groupSavedAnnotation(circle, 'Inspection'), isTrue);
    expect(editing.savedAnnotationGroups, ['Inspection', 'Review']);
    expect(editing.renameSavedAnnotationGroup('Inspection', 'Review'), isTrue);
    expect(editing.savedAnnotationGroups, ['Review']);
    expect(editing.savedAnnotations.every((entry) => entry.group == 'Review'),
        isTrue);

    expect(editing.removeSavedAnnotationGroup('Review'), isTrue);
    expect(editing.savedAnnotationGroups, isEmpty);
    expect(
        editing.savedAnnotations.every((entry) => entry.group == null), isTrue);
    expect(editing.savedAnnotations, hasLength(2));
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

  testWidgets('legacy library dialog previews and arms an item',
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
    expect(editing.document.page(0).annotations, isEmpty);
    expect(editing.activeSavedAnnotation?.name, 'Reusable box');
    expect(editing.hasAnnotationClipboard, isTrue,
        reason: 'the chosen item is also ready for keyboard/menu Paste');
  });

  testWidgets('panel groups and searches saved annotations', (tester) async {
    final editing = PdfEditingController(
      buildMultiPagePdf(1),
      annotationClipboard: PdfAnnotationSnapshotClipboard(),
    )
      ..addRectangle(0, const PdfRect(100, 650, 250, 750))
      ..addEllipse(0, const PdfRect(300, 650, 400, 750));
    addTearDown(editing.dispose);
    editing.selectAnnotation(0, 0);
    final box = editing.saveSelectedAnnotation('Reusable box')!;
    editing.selectAnnotation(0, 1);
    editing.saveSelectedAnnotation('Inspection circle');
    editing.groupSavedAnnotation(box, 'Review');

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 360,
          child: PdfAnnotationLibraryPanel(
            controller: editing,
            resizable: false,
          ),
        ),
      ),
    ));
    await tester.pump();
    expect(find.text('Review'), findsOneWidget);
    expect(find.text('Ungrouped'), findsOneWidget);
    expect(find.text('Reusable box'), findsOneWidget);
    expect(find.text('Inspection circle'), findsOneWidget);

    await tester.tap(find.text('Reusable box'), kind: PointerDeviceKind.mouse);
    await tester.pump();
    expect(editing.activeSavedAnnotation?.name, 'Reusable box');
    expect(editing.document.page(0).annotations, hasLength(2),
        reason: 'choosing a panel item only arms it');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(editing.activeSavedAnnotation, isNull,
        reason: 'Escape works while keyboard focus remains in the panel');

    await tester.enterText(
        find.byKey(const ValueKey('pdf-annotation-library-search')), 'circle');
    await tester.pump();
    expect(find.text('Reusable box'), findsNothing);
    expect(find.text('Inspection circle'), findsOneWidget);

    await tester.enterText(
        find.byKey(const ValueKey('pdf-annotation-library-search')), 'review');
    await tester.pump();
    expect(find.text('Reusable box'), findsOneWidget,
        reason: 'group names participate in search');
    expect(find.text('Inspection circle'), findsNothing);
  });

  testWidgets('editor toolbar toggles the dockable library panel',
      (tester) async {
    final preferences = PdfEditingPreferences()..showThumbnailSidebar = false;
    final editing = PdfEditingController(
      buildMultiPagePdf(1),
      preferences: preferences,
      annotationClipboard: PdfAnnotationSnapshotClipboard(),
    )..addRectangle(0, const PdfRect(100, 650, 250, 750));
    addTearDown(editing.dispose);
    editing.selectAnnotation(0, 0);
    editing.saveSelectedAnnotation('Reusable box');
    editing.clearAnnotationSelection();
    editing.tool = PdfEditTool.freeText;

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: PdfEditorView(controller: editing)),
    ));
    await tester.pump();
    expect(find.byType(PdfAnnotationLibraryPanel), findsNothing);
    expect(
        find.byKey(const ValueKey('pdf-annotation-library')), findsOneWidget);

    final stripScrollable = find
        .descendant(
          of: find.byType(PdfEditingToolbar),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('pdf-annotation-library')),
      100,
      scrollable: stripScrollable,
    );
    await tester.tap(find.byKey(const ValueKey('pdf-annotation-library')),
        kind: PointerDeviceKind.mouse);
    await tester.pump();
    expect(preferences.showAnnotationLibraryPanel, isTrue);
    expect(find.byType(PdfAnnotationLibraryPanel), findsOneWidget);
  });

  testWidgets('panel item follows the mouse and drops only on page click',
      (tester) async {
    final editing = PdfEditingController(
      buildMultiPagePdf(1),
      annotationClipboard: PdfAnnotationSnapshotClipboard(),
    )..addRectangle(0, const PdfRect(100, 650, 250, 750));
    addTearDown(editing.dispose);
    editing.selectAnnotation(0, 0);
    final saved = editing.saveSelectedAnnotation('Reusable box')!;
    editing.deleteSelected();
    expect(editing.beginSavedAnnotationPlacement(saved), isTrue);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ListenableBuilder(
          listenable: editing,
          builder: (context, _) => PdfViewer(
            initialFit: PdfViewerFit.width,
            document: editing.document,
            editing: editing,
          ),
        ),
      ),
    ));
    await tester.pump();

    const scale = 800 / 612;
    final target = Offset(360 * scale, (792 - 500) * scale);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(5, 5));
    addTearDown(mouse.removePointer);
    await mouse.moveTo(target);
    await tester.pumpAndSettle();

    dynamic cursorPainter() => tester
        .widgetList<CustomPaint>(find.descendant(
          of: find.byType(EditingPageOverlay),
          matching: find.byType(CustomPaint),
        ))
        .map((paint) => paint.painter)
        .singleWhere((painter) =>
            painter.runtimeType.toString() == '_HoverCursorPainter');

    expect(cursorPainter().savedAnnotationPreview, isNotNull);
    expect(cursorPainter().savedAnnotationPreview.picture, isNotNull,
        reason: 'the cursor carries the saved annotation appearance');
    expect(cursorPainter().savedAnnotationPreview.target.center.dx,
        closeTo(target.dx, 0.01));
    expect(editing.document.page(0).annotations, isEmpty,
        reason: 'hovering is preview-only');

    await tester.tapAt(target, kind: PointerDeviceKind.mouse);
    await tester.pump();
    final placed = editing.document.page(0).annotations.single;
    expect(placed.subtype, 'Square');
    expect((placed.rect.left + placed.rect.right) / 2, closeTo(360, 0.01));
    expect((placed.rect.bottom + placed.rect.top) / 2, closeTo(500, 0.01));
    expect(editing.activeSavedAnnotation?.id, saved.id,
        reason: 'the library placement stays armed for repeat drops');

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(editing.activeSavedAnnotation, isNull);
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
