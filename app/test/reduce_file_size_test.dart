import 'dart:async';
import 'dart:typed_data';

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:dart_pdf_editor_app/editor_screen.dart';
import 'package:dart_pdf_editor_app/file_io.dart';
import 'package:dart_pdf_editor_app/reduce_file_size.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:shared_preferences/shared_preferences.dart';

PdfCompressionResult _result(Uint8List bytes,
        {int? bytesBefore, List<String> warnings = const []}) =>
    PdfCompressionResult(
      bytes: bytes,
      bytesBefore: bytesBefore ?? bytes.length,
      bytesAfter: bytes.length,
      objectsBefore: 5,
      objectsAfter: 4,
      streamsDeflated: 1,
      compacted: bytesBefore != null,
      warnings: warnings,
      steps: [
        PdfCompressionStep(
          kind: PdfCompressionKind.structure,
          bytesBefore: bytesBefore ?? bytes.length,
          bytesAfter: bytes.length,
        ),
      ],
    );

Future<void> _openDialog(
  WidgetTester tester, {
  required PdfCompressionRunner runner,
  bool signed = false,
  double textScale = 1,
  Future<SaveResult> Function(BuildContext, Uint8List, String)? save,
}) async {
  await tester.pumpWidget(MaterialApp(
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: TextScaler.linear(textScale)),
      child: child!,
    ),
    home: Builder(builder: (context) {
      return TextButton(
        onPressed: () => showReduceFileSizeDialog(
          context,
          bytes: buildClassicPdf(),
          title: 'Report.pdf',
          hasSignatures: signed,
          runner: runner,
          saveCopy: save ?? (_, __, ___) async => SaveResult.cancelled,
        ),
        child: const Text('Open'),
      );
    }),
  ));
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, String key) async {
  final target = find.byKey(ValueKey(key));
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pump();
}

void main() {
  test('copy filenames never suggest the original name', () {
    expect(reducedPdfFileName('Report.PDF'), 'Report-reduced.pdf');
    expect(reducedPdfFileName(' report '), 'report-reduced.pdf');
    expect(reducedPdfFileName('.pdf'), 'document-reduced.pdf');
  });

  test('the background worker returns a complete readable PDF', () async {
    final original = buildClassicPdf();
    final result =
        await reducePdfBytes(original, const PdfCompressionOptions());
    expect(result.bytesAfter, lessThanOrEqualTo(original.length));
    expect(PdfDocument.open(result.bytes).pageCount, 1);
  });

  testWidgets('defaults to lossless and reports savings before saving a copy',
      (tester) async {
    PdfCompressionOptions? requested;
    final output = Uint8List(1024);
    var saves = 0;
    await _openDialog(
      tester,
      runner: (bytes, options) async {
        requested = options;
        return _result(output, bytesBefore: 4096);
      },
      save: (_, bytes, name) async {
        saves++;
        expect(bytes, same(output));
        expect(name, 'Report-reduced.pdf');
        return SaveResult.downloaded(name);
      },
    );
    expect(find.text('Lossless — preserve image quality'), findsOneWidget);
    await _tap(tester, 'reduce-size-run');
    await tester.pumpAndSettle();

    expect(requested!.targetDpi, isNull);
    expect(requested!.recompressStreams, isTrue);
    expect(requested!.removeUnusedResources, isTrue);
    expect(requested!.deduplicate, isTrue);
    expect(requested!.subsetFonts, isTrue);
    expect(requested!.allowInvalidateSignatures, isFalse);
    expect(find.byKey(const ValueKey('reduce-size-report')), findsOneWidget);
    expect(find.text('4.0 KiB'), findsOneWidget);
    expect(find.text('1.0 KiB'), findsOneWidget);
    expect(find.text('3.0 KiB (75%)'), findsOneWidget);
    expect(find.text('Document structure'), findsOneWidget);
    expect(saves, 0);

    await _tap(tester, 'reduce-size-save');
    await tester.pumpAndSettle();
    expect(saves, 1);
    expect(find.byKey(const ValueKey('reduce-size-dialog')), findsNothing);
  });

  testWidgets('screen preset and independent advanced options reach the worker',
      (tester) async {
    tester.view.physicalSize = const Size(800, 1200);
    addTearDown(tester.view.resetPhysicalSize);
    PdfCompressionOptions? requested;
    await _openDialog(tester, runner: (bytes, options) async {
      requested = options;
      return _result(bytes);
    });
    await _tap(tester, 'reduce-size-preset');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Screen — 72 DPI, JPEG quality 60').last);
    await tester.pumpAndSettle();
    await _tap(tester, 'reduce-size-advanced');
    await tester.pumpAndSettle();
    await _tap(tester, 'reduce-size-resources');
    await _tap(tester, 'reduce-size-fonts');
    await _tap(tester, 'reduce-size-dpi-72.0');
    await tester.pumpAndSettle();
    await tester.tap(find.text('300 dpi').last);
    await tester.pumpAndSettle();
    final quality = tester
        .widget<Slider>(find.byKey(const ValueKey('reduce-size-jpeg-quality')));
    expect(quality.value, 60);
    quality.onChanged!(82);
    await tester.pump();
    expect(find.text('Custom settings'), findsOneWidget);
    await _tap(tester, 'reduce-size-run');
    await tester.pumpAndSettle();

    expect(requested!.targetDpi, 300);
    expect(requested!.jpegQuality, 82);
    expect(requested!.removeUnusedResources, isFalse);
    expect(requested!.subsetFonts, isFalse);
    expect(requested!.recompressStreams, isTrue);
    expect(requested!.deduplicate, isTrue);
    expect(find.textContaining('original bytes were kept'), findsOneWidget);
  });

  testWidgets('signed document requires explicit consent before optimizing',
      (tester) async {
    PdfCompressionOptions? requested;
    await _openDialog(tester, signed: true, runner: (bytes, options) async {
      requested = options;
      return _result(bytes);
    });
    final run = find.byKey(const ValueKey('reduce-size-run'));
    expect(tester.widget<FilledButton>(run).onPressed, isNull);
    expect(find.textContaining('invalidates its digital signatures'),
        findsOneWidget);
    await _tap(tester, 'reduce-size-signature-consent');
    await _tap(tester, 'reduce-size-run');
    await tester.pumpAndSettle();
    expect(requested!.allowInvalidateSignatures, isTrue);
  });

  testWidgets('cancel while working discards the result and never saves',
      (tester) async {
    final pending = Completer<PdfCompressionResult>();
    var saves = 0;
    await _openDialog(
      tester,
      runner: (_, __) => pending.future,
      save: (_, __, ___) async {
        saves++;
        return SaveResult.cancelled;
      },
    );
    await _tap(tester, 'reduce-size-run');
    await tester.pump();
    expect(find.byKey(const ValueKey('reduce-size-progress')), findsOneWidget);
    // pumpAndSettle cannot finish while an indeterminate spinner runs.
    await tester.tap(find.byKey(const ValueKey('reduce-size-cancel')));
    await tester.pumpAndSettle();
    pending.complete(_result(buildClassicPdf()));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('reduce-size-dialog')), findsNothing);
    expect(saves, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cancel before the next frame never starts optimisation',
      (tester) async {
    var runs = 0;
    await _openDialog(tester, runner: (bytes, _) async {
      runs++;
      return _result(bytes);
    });
    await tester.tap(find.byKey(const ValueKey('reduce-size-run')));
    // Dismiss before endOfFrame resumes _run. The route is still mounted
    // during its reverse transition, so a mounted-only guard is insufficient.
    await tester.tap(find.byKey(const ValueKey('reduce-size-cancel')));
    await tester.pumpAndSettle();
    expect(runs, 0);
    expect(find.byKey(const ValueKey('reduce-size-dialog')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a result arriving during dismissal stays discarded',
      (tester) async {
    final pending = Completer<PdfCompressionResult>();
    await _openDialog(tester, runner: (_, __) => pending.future);
    await _tap(tester, 'reduce-size-run');
    await tester.tap(find.byKey(const ValueKey('reduce-size-cancel')));
    pending.complete(_result(buildClassicPdf()));
    await tester.pump();
    // The closing dialog remains in the tree until its animation completes.
    expect(find.byKey(const ValueKey('reduce-size-report')), findsNothing);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('worker errors leave the settings available for a retry',
      (tester) async {
    var runs = 0;
    await _openDialog(tester, runner: (bytes, _) async {
      if (runs++ == 0) throw StateError('Unsupported document');
      return _result(bytes);
    });
    await _tap(tester, 'reduce-size-run');
    await tester.pumpAndSettle();
    expect(find.textContaining('Unsupported document'), findsOneWidget);
    expect(find.byKey(const ValueKey('reduce-size-run')), findsOneWidget);
    await _tap(tester, 'reduce-size-run');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('reduce-size-error')), findsNothing);
    expect(find.byKey(const ValueKey('reduce-size-report')), findsOneWidget);
  });

  testWidgets(
      'phone layout preserves full preset labels and large-text reports',
      (tester) async {
    tester.view.physicalSize = const Size(390, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const warning = 'Embedded font XYZ+EngineeringFont was preserved because '
        'this font format cannot be safely subset. Images with unsupported '
        'color spaces and transparency masks were kept unchanged.';
    await _openDialog(tester, textScale: 2, runner: (bytes, _) async {
      return _result(bytes, bytesBefore: 1 << 30, warnings: [warning]);
    });
    const label = 'Lossless — preserve image quality';
    final paragraph = tester.renderObject<RenderParagraph>(find.text(label));
    final boxes = paragraph.getBoxesForSelection(
        const TextSelection(baseOffset: 0, extentOffset: label.length));
    // Dense dropdowns can silently clip the lower text lines without throwing
    // a RenderFlex overflow, hiding the actual quality setting on phones.
    expect(boxes.last.bottom, lessThanOrEqualTo(paragraph.size.height + 1));
    expect(tester.takeException(), isNull);
    await _tap(tester, 'reduce-size-run');
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text(warning));
    await tester.pumpAndSettle();
    expect(find.text(warning), findsOneWidget);
    await _tap(tester, 'reduce-size-save');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('reduce-size-report')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cancelled or failed save keeps the report for another attempt',
      (tester) async {
    var saves = 0;
    await _openDialog(
      tester,
      runner: (bytes, _) async => _result(bytes),
      save: (_, __, name) async {
        if (saves++ == 0) return SaveResult.cancelled;
        if (saves == 2) throw StateError('Disk full');
        return SaveResult.downloaded(name);
      },
    );
    await _tap(tester, 'reduce-size-run');
    await tester.pumpAndSettle();
    await _tap(tester, 'reduce-size-save');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('reduce-size-report')), findsOneWidget);
    await _tap(tester, 'reduce-size-save');
    await tester.pumpAndSettle();
    expect(find.textContaining('Disk full'), findsOneWidget);
    await _tap(tester, 'reduce-size-save');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('reduce-size-dialog')), findsNothing);
    expect(saves, 3);
  });

  testWidgets(
      'menu includes current ink and saves a copy without replacing history',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = PdfEditingPreferences();
    addTearDown(prefs.dispose);
    Uint8List? saved;
    var requests = 0;
    await tester.pumpWidget(MaterialApp(
        home: EditorScreen(
      prefs: prefs,
      initialDocument: (bytes: buildClassicPdf(), title: 'Original.pdf'),
      compressDocument: (bytes, _) async {
        requests++;
        final pdf = PdfDocument.open(bytes);
        expect(pdf.page(0).annotations.where((a) => a.subtype == 'Ink'),
            hasLength(1));
        return _result(bytes);
      },
      saveDocumentAs: (_, bytes, name) async {
        saved = bytes;
        expect(name, 'Original-reduced.pdf');
        return SaveResult.saved('/tmp/Original-reduced.pdf');
      },
    )));
    await tester.pumpAndSettle();
    final session =
        tester.widget<PdfEditorView>(find.byType(PdfEditorView)).controller!;
    session.inkCommitDelay = null;
    session.addInkStroke(0, [(100, 500), (200, 550)]);
    expect(session.hasPendingInk, isTrue);
    await tester.tap(find.byTooltip('DartPDF menu'));
    await tester.pumpAndSettle();
    final action = find.byKey(const ValueKey('menu-reduce-file-size'));
    expect(
        tester.getTopLeft(action).dy,
        greaterThan(tester
            .getTopLeft(
                find.byKey(const ValueKey('menu-section-This document')))
            .dy));
    expect(
        tester.getTopLeft(action).dy,
        lessThan(tester
            .getTopLeft(find.byKey(const ValueKey('menu-section-App')))
            .dy));
    await _tap(tester, 'menu-reduce-file-size');
    await tester.pumpAndSettle();
    expect(session.hasPendingInk, isFalse);
    final revision = session.revisionId;
    final original = Uint8List.fromList(session.bytes);
    await _tap(tester, 'reduce-size-run');
    await tester.pumpAndSettle();
    await _tap(tester, 'reduce-size-save');
    await tester.pumpAndSettle();

    expect(requests, 1);
    expect(saved, orderedEquals(original));
    final shell = tester.widget<PdfEditorView>(find.byType(PdfEditorView));
    expect(shell.controller, same(session));
    expect(shell.documentId, 'Original.pdf');
    expect(session.revisionId, revision);
    expect(session.bytes, orderedEquals(original));
    expect(session.canUndo, isTrue);
    expect(session.isModified, isTrue);
  });

  testWidgets('command palette opens the same reduce-file-size tool',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = PdfEditingPreferences();
    addTearDown(prefs.dispose);
    final source = buildClassicPdf();
    var requests = 0;
    await tester.pumpWidget(MaterialApp(
        home: EditorScreen(
      prefs: prefs,
      initialDocument: (bytes: source, title: 'Original.pdf'),
      compressDocument: (bytes, options) async {
        requests++;
        expect(bytes, orderedEquals(source));
        expect(options, isA<PdfCompressionOptions>());
        return _result(bytes);
      },
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('DartPDF menu'));
    await tester.pumpAndSettle();
    await _tap(tester, 'menu-command-palette');
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('command-palette-field')),
        'reduce file size');
    await tester.pumpAndSettle();
    await _tap(tester, 'palette-result-menu-reduce-file-size');
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('command-palette')), findsNothing);
    expect(find.byKey(const ValueKey('reduce-size-dialog')), findsOneWidget);
    expect(requests, 0);
    await _tap(tester, 'reduce-size-run');
    await tester.pumpAndSettle();
    expect(requests, 1);
    expect(find.byKey(const ValueKey('reduce-size-report')), findsOneWidget);
  });

  testWidgets('menu commits inline text before taking its revision snapshot',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = PdfEditingPreferences();
    addTearDown(prefs.dispose);
    String? copiedText;
    await tester.pumpWidget(MaterialApp(
        home: EditorScreen(
      prefs: prefs,
      initialDocument: (bytes: buildClassicPdf(), title: 'Original.pdf'),
      compressDocument: (bytes, _) async {
        copiedText =
            PdfDocument.open(bytes).page(0).annotations.single.contents;
        return _result(bytes);
      },
    )));
    await tester.pumpAndSettle();
    final session =
        tester.widget<PdfEditorView>(find.byType(PdfEditorView)).controller!;
    session.addFreeText(0, const PdfRect(100, 600, 300, 650), 'Before');
    session.selectAnnotation(0, 0);
    await tester.pumpAndSettle();
    expect(session.requestEditSelectedTextInline(), isTrue);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('pdf-freetext-editor')),
        'Currently being typed');
    expect(session.isEditingText, isTrue);
    await tester.tap(find.byTooltip('DartPDF menu'));
    await tester.pumpAndSettle();
    await _tap(tester, 'menu-reduce-file-size');
    await tester.pumpAndSettle();
    await _tap(tester, 'reduce-size-run');
    await tester.pumpAndSettle();
    expect(copiedText, 'Currently being typed');
    expect(session.isEditingText, isFalse);
  });

  testWidgets('encrypted documents are refused before the worker is invoked',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = PdfEditingPreferences();
    addTearDown(prefs.dispose);
    var requests = 0;
    await tester.pumpWidget(MaterialApp(
        home: EditorScreen(
      prefs: prefs,
      initialDocument: (bytes: buildEncryptedPdf(), title: 'Private.pdf'),
      compressDocument: (bytes, _) async {
        requests++;
        return _result(bytes);
      },
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('DartPDF menu'));
    await tester.pumpAndSettle();
    await _tap(tester, 'menu-reduce-file-size');
    await tester.pumpAndSettle();
    expect(find.text('Encrypted PDFs cannot be optimized.'), findsOneWidget);
    expect(requests, 0);
    expect(find.byKey(const ValueKey('reduce-size-dialog')), findsNothing);
  });

  testWidgets('reduce-file-size menu is absent without a document',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = PdfEditingPreferences();
    addTearDown(prefs.dispose);
    await tester.pumpWidget(MaterialApp(home: EditorScreen(prefs: prefs)));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('DartPDF menu'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('menu-reduce-file-size')), findsNothing);
    await _tap(tester, 'menu-command-palette');
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('command-palette-field')),
        'reduce file size');
    await tester.pumpAndSettle();
    final action =
        find.byKey(const ValueKey('palette-result-menu-reduce-file-size'));
    expect(action, findsOneWidget);
    expect(tester.widget<InkWell>(action).onTap, isNull);
    expect(find.text('Needs an open document'), findsOneWidget);
    expect(find.byKey(const ValueKey('reduce-size-dialog')), findsNothing);
  });
}
