// The 5.5 surfaces: design tokens (PdfEditorThemeData + the extended
// PdfViewerThemeData), the composable header (headerBuilder +
// PdfHeaderParts), menu entry builders, the presenter's actionBar/readout,
// and the viewer's global geometry.

import 'dart:async';

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart' show PdfRect;
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:shared_preferences/shared_preferences.dart';

// 800px viewport over a 612pt page (fit-width)
const _scale = 800 / 612;
Offset _view(double x, double y) => Offset(x * _scale, (792 - y) * _scale);

Widget _viewer(
  PdfEditingController editing,
  PdfViewerController viewer, {
  PdfAnnotationMenuEntriesBuilder? annotationMenuEntries,
  PdfTextMenuEntriesBuilder? textMenuEntries,
}) =>
    MaterialApp(
      home: Scaffold(
        body: ListenableBuilder(
          listenable: editing,
          builder: (context, _) => PdfViewer(
            initialFit: PdfViewerFit.width,
            document: editing.document,
            controller: viewer,
            editing: editing,
            annotationMenuEntries: annotationMenuEntries,
            textMenuEntries: textMenuEntries,
          ),
        ),
      ),
    );

class _HostChromePresenter extends PdfEditorPresenter {
  _HostChromePresenter();

  final actionBars = <PdfActionBarRequest>[];
  final readouts = <PdfReadoutRequest>[];

  @override
  Widget actionBar(BuildContext context, PdfActionBarRequest request) {
    actionBars.add(request);
    return Row(
      key: const ValueKey('host-action-bar'),
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final action in request.actions)
          GestureDetector(
            key: ValueKey('host-${action.id}'),
            onTap: action.onPressed,
            child: Text(action.label),
          ),
      ],
    );
  }

  @override
  Widget readout(BuildContext context, PdfReadoutRequest request) {
    readouts.add(request);
    return Text(request.text, key: const ValueKey('host-readout'));
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('tokens', () {
    test('PdfEditorThemeData merge, copyWith, lerp and equality', () {
      const a = PdfEditorThemeData(
        danger: Color(0xFF000000),
        compactWidth: 600,
        viewer: PdfViewerThemeData(chipColor: Color(0xFF111111)),
      );
      const b = PdfEditorThemeData(
        danger: Color(0xFFFFFFFF),
        viewer: PdfViewerThemeData(marqueeColor: Color(0xFF222222)),
      );
      final merged = a.merge(b);
      expect(merged.danger, const Color(0xFFFFFFFF));
      expect(merged.compactWidth, 600);
      expect(merged.viewer!.chipColor, const Color(0xFF111111));
      expect(merged.viewer!.marqueeColor, const Color(0xFF222222));
      expect(a.copyWith(toastLift: 10).toastLift, 10);
      expect(a.copyWith(toastLift: 10).danger, a.danger);
      final half = PdfEditorThemeData.lerp(a, b, 0.5);
      expect(half.danger, Color.lerp(a.danger, b.danger, 0.5));
      expect(
          a,
          const PdfEditorThemeData(
            danger: Color(0xFF000000),
            compactWidth: 600,
            viewer: PdfViewerThemeData(chipColor: Color(0xFF111111)),
          ));
    });

    test("the fallback tokens are the editor's former literals", () {
      const f = PdfEditorThemeData.fallback;
      expect(f.success!.toARGB32(), Colors.green.toARGB32());
      expect(f.warning!.toARGB32(), Colors.orange.toARGB32());
      expect(f.danger!.toARGB32(), Colors.red.toARGB32());
      expect(f.info!.toARGB32(), Colors.blue.toARGB32());
      expect(f.compactWidth, 700);
      expect(f.compactWidth, pdfShellCompactWidth);
      expect(f.toastLift, 96);
      expect(PdfEditingToolbar.mobileBreakpoint, pdfShellCompactWidth);
    });

    test('PdfViewerThemeData merge, copyWith and lerp cover new tokens', () {
      const a = PdfViewerThemeData(
        handleSize: 8,
        diffInsertedColor: Color(0xFF000000),
        scrollbar: PdfScrollbarThemeData(thumbColor: Color(0xFF010101)),
      );
      const b = PdfViewerThemeData(
        handleSize: 12,
        scrollbar: PdfScrollbarThemeData(markerColor: Color(0xFF020202)),
      );
      final merged = a.merge(b);
      expect(merged.handleSize, 12);
      expect(merged.diffInsertedColor, const Color(0xFF000000));
      expect(merged.scrollbar!.thumbColor, const Color(0xFF010101));
      expect(merged.scrollbar!.markerColor, const Color(0xFF020202));
      expect(a.copyWith(alignmentGuideColor: const Color(0xFF030303)),
          isNot(equals(a)));
      expect(PdfViewerThemeData.lerp(a, b, 0.5)!.handleSize, 10);
      expect(PdfViewerThemeData.lerp(null, null, 0.5), isNull);
    });

    testWidgets('a scope supplies tokens: of(), viewer tokens, toast lift',
        (tester) async {
      late BuildContext inner;
      final editing = PdfEditingController(buildMultiPagePdf(1));
      final viewer = PdfViewerController();
      addTearDown(editing.dispose);
      addTearDown(viewer.dispose);
      await tester.pumpWidget(MaterialApp(
        home: PdfEditorScope(
          presenter: const PdfEditorPresenter(),
          theme: const PdfEditorThemeData(
            toastLift: 40,
            danger: Color(0xFF123456),
            viewer: PdfViewerThemeData(chipColor: Color(0xFF654321)),
          ),
          child: Builder(builder: (context) {
            inner = context;
            return PdfViewer(
              initialFit: PdfViewerFit.width,
              document: editing.document,
              controller: viewer,
              editing: editing,
            );
          }),
        ),
      ));
      await tester.pump();
      final tokens = PdfEditorThemeData.of(inner);
      expect(tokens.danger, const Color(0xFF123456));
      expect(tokens.success!.toARGB32(), Colors.green.toARGB32(),
          reason: 'unset falls back');
      expect(
          pdfFloatingToastMargin(inner).resolve(TextDirection.ltr).bottom, 40);
      // the root widget installs the scope's canvas tokens as a
      // PdfViewerTheme for everything beneath it
      final page = tester.element(find.byType(Scrollable).first);
      expect(PdfViewerTheme.of(page).chipColor, const Color(0xFF654321));
    });

    testWidgets('PdfEditorView(theme:) moves the compact breakpoint',
        (tester) async {
      tester.view.physicalSize = const Size(650, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final bytes = buildMultiPagePdf(1);
      Future<void> pump(PdfEditorThemeData? theme) async {
        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: PdfEditorView(
              bytes: bytes,
              onSave: (_) {},
              theme: theme,
            ),
          ),
        ));
        await tester.pump();
      }

      // 650 < 700: compact header (the Controls button)
      await pump(null);
      expect(find.byKey(const ValueKey('pdf-shell-controls')), findsOneWidget);
      // 650 >= 600: the wide header, save inline
      await pump(const PdfEditorThemeData(compactWidth: 600));
      expect(find.byKey(const ValueKey('pdf-shell-controls')), findsNothing);
      expect(find.byKey(const ValueKey('pdf-shell-save')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('headerBuilder', () {
    testWidgets('composes a header from the stock parts', (tester) async {
      PdfHeaderParts? seen;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: PdfEditorView(
            bytes: buildMultiPagePdf(2),
            onSave: (_) {},
            headerBuilder: (context, parts) {
              seen = parts;
              return parts.bar(
                leading: [if (parts.pageNumber != null) parts.pageNumber!],
                trailing: [
                  const Text('host action', key: ValueKey('host-action')),
                  if (parts.save != null) parts.save!,
                ],
              );
            },
          ),
        ),
      ));
      await tester.pump();
      expect(seen, isNotNull);
      expect(seen!.compact, isFalse);
      expect(seen!.search, isNotNull);
      expect(find.byKey(const ValueKey('host-action')), findsOneWidget);
      expect(find.byKey(const ValueKey('pdf-shell-save')), findsOneWidget);
      expect(find.byType(PdfPageNumberField), findsOneWidget);
      // left out by the host
      expect(find.byType(PdfSearchField), findsNothing);
      expect(find.byKey(const ValueKey('pdf-shell-panels')), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('compact: the controls part can leave save to the host',
        (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: PdfEditorView(
            bytes: buildMultiPagePdf(1),
            onSave: (_) {},
            alwaysAllowSave: true,
            headerBuilder: (context, parts) {
              expect(parts.compact, isTrue);
              return parts.bar(
                leading: [if (parts.pageNumber != null) parts.pageNumber!],
                trailing: [
                  if (parts.save != null) parts.save!,
                  if (parts.controls(includeSave: false) case final c?) c,
                ],
              );
            },
          ),
        ),
      ));
      await tester.pump();
      expect(find.byKey(const ValueKey('pdf-shell-save')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('pdf-shell-controls')));
      await tester.pumpAndSettle();
      // the sheet has the zoom and panels, but save stays in the bar
      expect(find.byKey(const ValueKey('pdf-shell-save')), findsOneWidget);
      expect(find.byKey(const ValueKey('pdf-shell-thumbnails-toggle')),
          findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('menu entries', () {
    testWidgets('annotationMenuEntries drops and adds rows', (tester) async {
      final editing = PdfEditingController(buildMultiPagePdf(1))
        ..addRectangle(0, const PdfRect(100, 600, 300, 700))
        ..tool = PdfEditTool.select;
      final viewer = PdfViewerController();
      addTearDown(editing.dispose);
      addTearDown(viewer.dispose);
      var shared = 0;
      List<String?>? stockIds;
      await tester.pumpWidget(_viewer(editing, viewer,
          annotationMenuEntries: (context, request, stock) {
        stockIds = [for (final e in stock) e.id];
        return [
          ...stock.where((e) => e.id != 'pdf-annot-menu-delete'),
          const PdfMenuDivider(),
          pdfAnnotationMenuEntry(PdfAnnotationMenuItem(
            key: const ValueKey('host-share'),
            label: 'Share',
            onSelected: (request) => shared = request.annotations.length,
          )),
        ];
      }));
      await tester.pump();
      await tester.tapAt(_view(200, 650),
          kind: PointerDeviceKind.mouse, buttons: kSecondaryMouseButton);
      await tester.pumpAndSettle();
      expect(stockIds, contains('pdf-annot-menu-delete'));
      expect(find.byKey(const ValueKey('pdf-annot-menu-delete')), findsNothing);
      expect(find.byKey(const ValueKey('pdf-annot-menu-copy')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('host-share')));
      await tester.pumpAndSettle();
      expect(shared, 1);
    });

    testWidgets('textMenuEntries rewrites the text menu', (tester) async {
      final editing = PdfEditingController(buildMultiPagePdf(1));
      final viewer = PdfViewerController();
      addTearDown(editing.dispose);
      addTearDown(viewer.dispose);
      String? picked;
      await tester.pumpWidget(_viewer(editing, viewer,
          textMenuEntries: (context, request, stock) => [
                for (final e in stock)
                  if (e.id == 'pdf-text-menu-copy') e,
                pdfTextMenuEntry(PdfTextMenuItem(
                  key: const ValueKey('host-define'),
                  label: 'Define',
                  onSelected: (request) => picked = request.selectedText,
                )),
              ]));
      await tester.pump();
      await tester.tapAt(_view(80, 728),
          kind: PointerDeviceKind.mouse, buttons: kSecondaryMouseButton);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('pdf-text-menu-copy')), findsOneWidget);
      expect(
          find.byKey(const ValueKey('pdf-text-menu-highlight')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('host-define')));
      await tester.pumpAndSettle();
      expect(picked, 'Page');
    });

    testWidgets('formFieldMenuEntries rewrites the field menu', (tester) async {
      final editing = PdfEditingController(buildAcroFormPdf());
      addTearDown(editing.dispose);
      final name = editing.acroForm!.fields.first.name;
      late BuildContext context;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: Builder(builder: (c) {
          context = c;
          return const SizedBox.expand();
        })),
      ));
      PdfFormFieldMenuRequest? seen;
      unawaited(showPdfFormFieldMenu(
        context: context,
        position: const Offset(100, 100),
        controller: editing,
        fieldName: name,
        entriesBuilder: (context, request, stock) {
          seen = request;
          return [
            for (final e in stock)
              if (e.id == 'pdf-form-menu-rename') e
          ];
        },
      ));
      await tester.pumpAndSettle();
      expect(seen!.fieldName, name);
      expect(
          find.byKey(const ValueKey('pdf-form-menu-rename')), findsOneWidget);
      expect(find.byKey(const ValueKey('pdf-form-menu-delete')), findsNothing);
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
    });
  });

  group('presenter chrome', () {
    testWidgets('actionBar draws the touch text-selection chip',
        (tester) async {
      final presenter = _HostChromePresenter();
      final viewer = PdfViewerController();
      addTearDown(viewer.dispose);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: PdfViewer(
            initialFit: PdfViewerFit.width,
            document: PdfDocument.open(buildMultiPagePdf(1)),
            controller: viewer,
            presenter: presenter,
          ),
        ),
      ));
      await tester.pump();
      final gesture = await tester.startGesture(_view(100, 720));
      await tester.pump(const Duration(milliseconds: 600));
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();

      expect(
          find.byKey(const ValueKey('pdf-text-selection-chip')), findsNothing);
      expect(find.byKey(const ValueKey('host-action-bar')), findsOneWidget);
      final request = presenter.actionBars.last;
      expect(request.kind, PdfActionBarKind.textSelection);
      expect([
        for (final a in request.actions) a.id
      ], [
        'pdf-text-selection-chip-copy',
        'pdf-text-selection-chip-select-all',
      ]);
      await tester.tap(find
          .byKey(const ValueKey('host-pdf-text-selection-chip-select-all')));
      await tester.pump(const Duration(milliseconds: 400));
      expect(viewer.selectedText, contains('Page'));
    });

    testWidgets('readout draws the drag readout', (tester) async {
      final presenter = _HostChromePresenter();
      final editing = PdfEditingController(buildMultiPagePdf(1));
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
              presenter: presenter,
            ),
          ),
        ),
      ));
      await tester.pump();
      editing
        ..tool = PdfEditTool.rectangle
        ..preferences.strokeWidth = 4
        ..preferences.opacity = 0.5;
      await tester.pump();
      final gesture = await tester.startGesture(_view(150, 600));
      await gesture.moveTo(_view(300, 450));
      await tester.pump();
      expect(find.byKey(const ValueKey('pdf-style-readout')), findsNothing);
      expect(find.byKey(const ValueKey('host-readout')), findsOneWidget);
      expect(presenter.readouts.last.kind, PdfReadoutKind.style);
      expect(presenter.readouts.last.text, '4 pt · 50%');
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 400));
    });
  });

  for (final show in [true, false]) {
    testWidgets('showInlineTextStyleChip: $show', (tester) async {
      final editing = PdfEditingController(buildMultiPagePdf(1));
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
              showInlineTextStyleChip: show,
            ),
          ),
        ),
      ));
      await tester.pump();
      editing.addFreeText(0, const PdfRect(100, 600, 360, 660), 'Hello world');
      await tester.pump();
      editing.tool = PdfEditTool.select;
      await tester.pump();
      for (var i = 0; i < 2; i++) {
        // first tap selects, second edits (touch)
        await tester.tapAt(_view(200, 630));
        await tester.pump(const Duration(milliseconds: 400));
      }
      final field = tester
          .widget<TextField>(find.byKey(const ValueKey('pdf-freetext-editor')));
      field.controller!.value = const TextEditingValue(
        text: 'Hello world',
        selection: TextSelection(baseOffset: 6, extentOffset: 11),
      );
      await tester.pump();
      expect(find.byKey(const ValueKey('pdf-inline-text-style-chip')),
          show ? findsOneWidget : findsNothing);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 400));
    });
  }

  group('geometry', () {
    testWidgets('globalRectOf maps page space onto the screen', (tester) async {
      final editing = PdfEditingController(buildMultiPagePdf(2));
      final viewer = PdfViewerController();
      addTearDown(editing.dispose);
      addTearDown(viewer.dispose);
      await tester.pumpWidget(_viewer(editing, viewer));
      await tester.pump();

      final origin = tester.getTopLeft(find.byType(PdfViewer));
      final rect = viewer.globalRectOf(0, const PdfRect(100, 600, 300, 700))!;
      Offset expected(double x, double y) => origin + _view(x, y);
      expect(rect.left, moreOrLessEquals(expected(100, 700).dx, epsilon: 0.5));
      expect(rect.top, moreOrLessEquals(expected(100, 700).dy, epsilon: 0.5));
      expect(rect.right, moreOrLessEquals(expected(300, 600).dx, epsilon: 0.5));
      expect(
          rect.bottom, moreOrLessEquals(expected(300, 600).dy, epsilon: 0.5));
      expect(viewer.globalRectOf(9, const PdfRect(0, 0, 1, 1)), isNull);

      // scrolling moves it up by the scrolled distance
      await tester.drag(find.byType(PdfViewer), const Offset(0, -200));
      await tester.pumpAndSettle();
      final scrolled =
          viewer.globalRectOf(0, const PdfRect(100, 600, 300, 700))!;
      expect(scrolled.top, lessThan(rect.top - 100));
      expect(scrolled.width, moreOrLessEquals(rect.width));
    });

    testWidgets('selectionGlobalRect follows the annotation selection',
        (tester) async {
      final editing = PdfEditingController(buildMultiPagePdf(1))
        ..addRectangle(0, const PdfRect(100, 600, 300, 700))
        ..tool = PdfEditTool.select;
      final viewer = PdfViewerController();
      addTearDown(editing.dispose);
      addTearDown(viewer.dispose);
      await tester.pumpWidget(_viewer(editing, viewer));
      await tester.pump();

      final seen = <Rect?>[];
      void listener() => seen.add(viewer.selectionGlobalRect.value);
      viewer.selectionGlobalRect.addListener(listener);
      addTearDown(() => viewer.selectionGlobalRect.removeListener(listener));
      expect(viewer.selectionGlobalRect.value, isNull);

      editing.selectAnnotation(0, 0);
      await tester.pump();
      await tester.pump();
      final annotationRect = editing.document.page(0).annotations.single.rect;
      final expected = viewer.globalRectOf(0, annotationRect);
      expect(seen, isNotEmpty);
      expect(seen.last, expected);
      expect(viewer.selectionGlobalRect.value, expected);

      editing.clearAnnotationSelection();
      await tester.pump();
      await tester.pump();
      expect(seen.last, isNull);
    });
  });
}
