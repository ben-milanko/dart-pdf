import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:shared_preferences/shared_preferences.dart';

Uint8List _pdf(List<String> pageContents) {
  final objects = <String>[
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [${[
      for (var i = 0; i < pageContents.length; i++) '${3 + i * 2} 0 R'
    ].join(' ')}] /Count ${pageContents.length} >>',
    for (var i = 0; i < pageContents.length; i++) ...[
      '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 100 100] '
          '/Resources << >> /Contents ${4 + i * 2} 0 R >>',
      '<< /Length ${latin1.encode(pageContents[i]).length} >>\n'
          'stream\n${pageContents[i]}\nendstream',
    ],
  ];
  final buffer = StringBuffer('%PDF-1.4\n');
  final offsets = <int>[];
  for (var i = 0; i < objects.length; i++) {
    offsets.add(buffer.length);
    buffer.write('${i + 1} 0 obj\n${objects[i]}\nendobj\n');
  }
  final xrefOffset = buffer.length;
  buffer
    ..write('xref\n0 ${objects.length + 1}\n')
    ..write('0000000000 65535 f \n');
  for (final offset in offsets) {
    buffer.write('${offset.toString().padLeft(10, '0')} 00000 n \n');
  }
  buffer
    ..write('trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\n')
    ..write('startxref\n$xrefOffset\n%%EOF\n');
  return Uint8List.fromList(latin1.encode(buffer.toString()));
}

String _content(PdfEditingController controller, int page) =>
    latin1.decode(controller.document.page(page).contentBytes());

Future<void> _waitForColorProcessing(
  WidgetTester tester,
  bool Function() isDone,
) async {
  await tester.runAsync(() async {
    for (var i = 0; i < 100; i++) {
      if (isDone()) return;
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  });
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('replaceSelectedPageColors changes only the selected pages', () {
    final controller = PdfEditingController(_pdf([
      '1 0 0 rg 0 0 10 10 re f',
      '1 0 0 rg 0 0 10 10 re f',
    ]));
    addTearDown(controller.dispose);

    controller.selectPage(1);
    final count = controller.replaceSelectedPageColors(
      find: const Color(0xFFFF0000),
      replace: const Color(0xFF0000FF),
    );

    expect(count, 1);
    expect(_content(controller, 0), contains('1 0 0 rg'));
    expect(_content(controller, 1), contains('0 0 1 rg'));

    controller.undo();
    expect(_content(controller, 1), contains('1 0 0 rg'));
  });

  test('replaceDocumentColors processes the whole document by default', () {
    final controller = PdfEditingController(_pdf([
      '1 0 0 rg 0 0 10 10 re f',
      '1 0 0 rg 0 0 10 10 re f',
    ]));
    addTearDown(controller.dispose);

    final count = controller.replaceDocumentColors(
      find: const Color(0xFFFF0000),
      replace: const Color(0xFF0000FF),
    );

    expect(count, 2);
    expect(_content(controller, 0), contains('0 0 1 rg'));
    expect(_content(controller, 1), contains('0 0 1 rg'));
  });

  test('replaceDocumentColors accepts several source colors', () {
    final controller = PdfEditingController(_pdf([
      '1 0 0 rg 0 0 10 10 re f\n'
          '0 1 0 rg 20 20 10 10 re f\n'
          '0 0 1 rg 40 40 10 10 re f',
    ]));
    addTearDown(controller.dispose);

    final count = controller.replaceDocumentColors(
      findColors: const [
        Color(0xFFFF0000),
        Color(0xFF00FF00),
      ],
      replace: const Color(0xFF0000FF),
    );

    expect(count, 2);
    final content = _content(controller, 0);
    expect(RegExp(r'0 0 1 rg').allMatches(content), hasLength(3));
    expect(content, isNot(contains('1 0 0 rg')));
    expect(content, isNot(contains('0 1 0 rg')));
  });

  test('replaceDocumentColorsAsync commits one undoable revision', () async {
    final controller = PdfEditingController(_pdf([
      '1 0 0 rg 0 0 10 10 re f',
      '1 0 0 rg 0 0 10 10 re f',
    ]));
    addTearDown(controller.dispose);

    final count = await controller.replaceDocumentColorsAsync(
      find: const Color(0xFFFF0000),
      replace: const Color(0xFF0000FF),
    );

    expect(count, 2);
    expect(_content(controller, 0), contains('0 0 1 rg'));
    expect(_content(controller, 1), contains('0 0 1 rg'));

    controller.undo();
    expect(_content(controller, 0), contains('1 0 0 rg'));
    expect(_content(controller, 1), contains('1 0 0 rg'));
  });

  testWidgets('PdfEditorView exposes the color processing dialog',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final controller = PdfEditingController(_pdf([
      '0 g 0 0 10 10 re f',
    ]))
      ..color = const Color(0xFF0000FF);
    addTearDown(controller.dispose);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PdfEditorView(
          controller: controller,
          showSaveButton: false,
        ),
      ),
    ));
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('pdf-group-edit')),
        kind: PointerDeviceKind.mouse);
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('pdf-toolbar-color-processing')),
        kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();
    expect(
        find.byKey(const ValueKey('pdf-color-process-apply')), findsOneWidget);
    expect(find.byKey(const ValueKey('pdf-color-process-document-colors')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('pdf-color-process-color-0')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('pdf-color-process-find-picker')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('pdf-color-process-replace-picker')),
        findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('pdf-color-process-apply')),
        kind: PointerDeviceKind.mouse);
    await tester.pump();
    await _waitForColorProcessing(
      tester,
      () => _content(controller, 0).contains('0 0 1 rg'),
    );

    expect(_content(controller, 0), contains('0 0 1 rg'));

    // Drain the result SnackBar's timer.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });

  testWidgets('color processing dialog can select multiple document colors',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final controller = PdfEditingController(_pdf([
      '1 0 0 rg 0 0 10 10 re f\n'
          '1 0 0 rg 20 20 10 10 re f\n'
          '0 1 0 rg 40 40 10 10 re f',
    ]))
      ..color = const Color(0xFF0000FF);
    addTearDown(controller.dispose);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PdfEditorView(
          controller: controller,
          showSaveButton: false,
        ),
      ),
    ));
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('pdf-group-edit')),
        kind: PointerDeviceKind.mouse);
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('pdf-toolbar-color-processing')),
        kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('pdf-color-process-color-16711680')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('pdf-color-process-color-65280')),
        findsOneWidget);

    await tester.tap(
        find.byKey(const ValueKey('pdf-color-process-color-65280')),
        kind: PointerDeviceKind.mouse);
    await tester.pump();

    expect(find.text('2 colors selected'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('pdf-color-process-apply')),
        kind: PointerDeviceKind.mouse);
    await tester.pump();
    await _waitForColorProcessing(
      tester,
      () => RegExp(r'0 0 1 rg').allMatches(_content(controller, 0)).length == 3,
    );

    final content = _content(controller, 0);
    expect(RegExp(r'0 0 1 rg').allMatches(content), hasLength(3));
    expect(content, isNot(contains('1 0 0 rg')));
    expect(content, isNot(contains('0 1 0 rg')));

    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });

  testWidgets('color processing rescans whole-document colors incrementally',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final controller = PdfEditingController(_pdf([
      '1 0 0 rg 0 0 10 10 re f',
      '0 0 1 rg 0 0 10 10 re f',
      '0 1 0 rg 0 0 10 10 re f',
    ]))
      ..selectPage(0);
    addTearDown(controller.dispose);

    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => FilledButton(
          onPressed: () => showPdfColorProcessingDialog(
            context,
            controller: controller,
            preferences: controller.preferences,
          ),
          child: const Text('open'),
        ),
      ),
    ));
    await tester.tap(find.text('open'), kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('pdf-color-process-color-16711680')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('pdf-color-process-color-255')),
        findsNothing);

    await tester.tap(
        find.byKey(const ValueKey('pdf-color-process-whole-document')),
        kind: PointerDeviceKind.mouse);
    await tester.pump();

    expect(find.byKey(const ValueKey('pdf-color-process-scan-progress')),
        findsOneWidget);
    expect(
        tester
            .widget<FilledButton>(
                find.byKey(const ValueKey('pdf-color-process-apply')))
            .onPressed,
        isNull);

    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('pdf-color-process-color-255')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('pdf-color-process-color-65280')),
        findsOneWidget);
    expect(
        tester
            .widget<FilledButton>(
                find.byKey(const ValueKey('pdf-color-process-apply')))
            .onPressed,
        isNotNull);
  });

  testWidgets(
      'color processing dialog can replace a document swatch with '
      'transparent output', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final controller = PdfEditingController(_pdf([
      '1 0 0 rg 0 0 10 10 re f',
    ]));
    addTearDown(controller.dispose);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PdfEditorView(
          controller: controller,
          showSaveButton: false,
        ),
      ),
    ));
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('pdf-group-edit')),
        kind: PointerDeviceKind.mouse);
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('pdf-toolbar-color-processing')),
        kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('pdf-color-process-color-16711680')),
        findsOneWidget);
    await tester.tap(
        find.byKey(const ValueKey('pdf-color-process-transparent')),
        kind: PointerDeviceKind.mouse);
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('pdf-color-process-apply')),
        kind: PointerDeviceKind.mouse);
    await tester.pump();
    await _waitForColorProcessing(
      tester,
      () => _content(controller, 0).contains('n\n'),
    );

    expect(_content(controller, 0), contains('n\n'));

    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });
}
