import 'dart:async';

import 'package:dart_pdf_printing/dart_pdf_printing.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dev.milanko.dart_pdf_printing');
  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
        (call) async {
      calls.add(call);
      return true;
    });
  });
  tearDown(() =>
      binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null));

  Future<void> open(WidgetTester tester, {Locale? locale}) async {
    final document = PdfDocument.open(buildMultiPagePdf(3));
    await tester.pumpWidget(MaterialApp(
      locale: locale,
      localizationsDelegates:
          DartPdfPrintingLocalizations.localizationsDelegates,
      supportedLocales: DartPdfPrintingLocalizations.supportedLocales,
      home: Builder(
          builder: (context) => Scaffold(
                  body: TextButton(
                onPressed: () => printPdfWithPreview(context,
                    document: document, title: 'Report.pdf', currentPage: 1),
                child: const Text('Open'),
              ))),
    ));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  testWidgets('the public flow submits the confirmed physical sheets',
      (tester) async {
    await open(tester);
    await tester.tap(find.byKey(const ValueKey('print-preview-current')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('print-preview-print')));
    await tester.pumpAndSettle();
    expect(calls, hasLength(1));
    expect(calls.single.method, 'printPdf');
    final args = calls.single.arguments as Map;
    expect(args['name'], 'Report');
    expect(args['useDocumentPageSize'], isTrue);
    expect(args['pageWidth'], 612);
    expect(args['pageHeight'], 792);
    expect(PdfDocument.open(args['pdf'] as Uint8List).pageCount, 1);
  });

  testWidgets('canceling the public preview never invokes the printer',
      (tester) async {
    await open(tester);
    await tester.tap(find.byKey(const ValueKey('print-preview-cancel')));
    await tester.pumpAndSettle();
    expect(calls, isEmpty);
  });

  testWidgets('the public Windows flow sends the destination and duplex copies',
      (tester) async {
    final preferences = await PrintPreferences.load();
    await preferences.saveSettings(PrintSettings(pages: [0], copies: 2),
        range: 'current', customRange: '1');
    await preferences.saveDestination(const PrintDestination(
        printer: 'Office',
        color: false,
        duplex: PrintDuplex.longEdge,
        tray: 7));
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
        (call) async {
      calls.add(call);
      return switch (call.method) {
        'listPrinters' => [
            {'name': 'Office', 'isDefault': true}
          ],
        'printerSettings' => {
            'color': true,
            'duplex': 'simplex',
            'tray': 7,
            'supportsColor': true,
            'supportsDuplex': true,
            'trays': [
              {'id': 7, 'name': 'Auto'}
            ],
          },
        'beginJob' => {'vector': true},
        'printPdf' => throw StateError('Direct printing must skip the dialog'),
        _ => true,
      };
    });
    await open(tester);
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const ValueKey('print-preview-print')));
      for (var i = 0; i < 100; i++) {
        if (calls.any((call) => call.method == 'endJob')) break;
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    await tester.pumpAndSettle();
    final args =
        calls.singleWhere((call) => call.method == 'beginJob').arguments;
    expect(args, containsPair('printer', 'Office'));
    expect(args, containsPair('color', false));
    expect(args, containsPair('duplex', 'longEdge'));
    expect(args, containsPair('tray', 7));
    expect(args, containsPair('useDocumentPageSize', true));
    // The current source page and its blank back repeat once per copy.
    expect(
        calls.where((call) => call.method == 'printPageVector'), hasLength(4));
    expect(calls.last.method, 'endJob');
    expect(find.byType(PrintProgressDialog), findsNothing);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets('translations work without the DartPDF app delegate',
      (tester) async {
    await open(tester, locale: const Locale('fr'));
    final context = tester.element(find.byType(PrintPreviewDialog));
    final strings = DartPdfPrintingLocalizations.of(context)!;
    expect(strings.localeName, 'fr');
    expect(find.text(strings.printPreviewTitle), findsOneWidget);
    expect(find.text(strings.printPreviewPrint), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('print-preview-cancel')));
    await tester.pumpAndSettle();
  });

  testWidgets('a failed job closes only its own progress route',
      (tester) async {
    late Completer<void> secondPage;
    late Completer<bool> releasePage;
    var pages = 0;
    var canceled = false;
    Object? error;
    Future<void>? pending;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
        (call) async {
      switch (call.method) {
        case 'printPdf':
          throw MissingPluginException();
        case 'beginJob':
          return {'vector': true};
        case 'printPageVector':
          if (++pages == 2) {
            secondPage.complete();
            return releasePage.future;
          }
          return true;
        case 'cancelJob':
          canceled = true;
          return null;
      }
      return null;
    });
    await tester.pumpWidget(const MaterialApp(home: Scaffold()));
    final hostContext = tester.element(find.byType(Scaffold));
    await tester.runAsync(() async {
      secondPage = Completer<void>();
      releasePage = Completer<bool>();
      pending = printPdfWithProgress(hostContext,
              bytes: buildMultiPagePdf(3), title: 'Report')
          .catchError((Object value) {
        error = value;
      });
      await secondPage.future.timeout(const Duration(seconds: 10));
    });
    await tester.pumpAndSettle();
    expect(find.byType(PrintProgressDialog), findsOneWidget);
    final context = tester.element(find.byType(PrintProgressDialog));
    unawaited(showDialog<void>(
        context: context,
        builder: (_) => const AlertDialog(content: Text('Host dialog'))));
    await tester.pumpAndSettle();
    releasePage.completeError(PlatformException(code: 'printer_failed'));
    await tester.runAsync(() => pending!);
    await tester.pumpAndSettle();
    expect(error, isA<PlatformException>());
    expect(canceled, isTrue);
    expect(find.byType(PrintProgressDialog), findsNothing);
    expect(find.text('Host dialog'), findsOneWidget);
    Navigator.of(tester.element(find.text('Host dialog'))).pop();
    await tester.pumpAndSettle();
  });

  testWidgets('empty documents fail before creating a preview route',
      (tester) async {
    final builder = CosDocumentBuilder();
    final root = builder.add(CosDictionary({
      'Type': const CosName('Catalog'),
      'Pages': builder.add(CosDictionary({
        'Type': const CosName('Pages'),
        'Kids': CosArray([]),
        'Count': const CosInteger(0),
      })),
    }));
    final document = PdfDocument.open(builder.build(root: root));
    await tester.pumpWidget(const MaterialApp(home: Scaffold()));
    final context = tester.element(find.byType(Scaffold));
    expect(
        () =>
            showPrintPreviewDialog(context, document: document, title: 'Empty'),
        throwsArgumentError);
    expect(find.byType(PrintPreviewDialog), findsNothing);
    expect(calls, isEmpty);
  });
}
