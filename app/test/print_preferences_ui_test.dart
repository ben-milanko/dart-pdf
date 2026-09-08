import 'dart:async';

import 'package:dart_pdf_editor_app/print_preferences.dart';
import 'package:dart_pdf_editor_app/print_preview_dialog.dart';
import 'package:dart_pdf_editor_app/print_printer.dart';
import 'package:dart_pdf_editor_app/print_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _channel = MethodChannel('dev.milanko.dartpdf/native_print');
const _settings = <String, Object>{
  'color': true,
  'duplex': 'simplex',
  'tray': 1,
  'supportsColor': true,
  'supportsDuplex': true,
  'trays': [
    {'id': 1, 'name': 'Main tray'},
    {'id': 2, 'name': 'Bypass'}
  ],
};
const _printers = [
  {'name': 'Office', 'isDefault': true},
  {'name': 'Plotter', 'isDefault': false},
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() => TestDefaultBinaryMessengerBinding
      .instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_channel, null));

  Future<PrintPreviewResult? Function()> open(WidgetTester tester,
      {int currentPage = 0,
      int pageCount = 5,
      bool settle = true,
      List<int> selectedPages = const []}) async {
    tester.view.physicalSize = const Size(1200, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    PrintPreviewResult? result;
    await tester.pumpWidget(MaterialApp(
        key: UniqueKey(),
        home: Builder(
            builder: (context) => Scaffold(
                body: TextButton(
                    onPressed: () async {
                      result = await showPrintPreviewDialog(context,
                          document:
                              PdfDocument.open(buildMultiPagePdf(pageCount)),
                          title: 'Test.pdf',
                          currentPage: currentPage,
                          selectedPages: selectedPages);
                    },
                    child: const Text('Open print'))))));
    await tester.tap(find.text('Open print'));
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    }
    return () => result;
  }

  Future<void> choose(WidgetTester tester, String key, String label) async {
    final finder = find.byKey(ValueKey('print-options-$key'));
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await tester.pumpAndSettle();
    await tester.tap(find.text(label).last);
    await tester.pumpAndSettle();
  }

  Future<void> cancel(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('print-preview-cancel')));
    await tester.pumpAndSettle();
  }

  testWidgets('changes survive Cancel and Defaults persists across reopening',
      (tester) async {
    await open(tester);
    await choose(tester, 'paper', 'A3');
    await tester
        .ensureVisible(find.byKey(const ValueKey('print-options-copies')));
    await tester.enterText(
        find.byKey(const ValueKey('print-options-copies')), '7');
    await tester.pumpAndSettle();
    await cancel(tester);
    final result = await open(tester);
    expect(
        tester
            .widget<DropdownButton<PrintPaperSize>>(
                find.byKey(const ValueKey('print-options-paper')))
            .value,
        PrintPaperSize.a3);
    expect(
        tester
            .widget<TextField>(
                find.byKey(const ValueKey('print-options-copies')))
            .controller!
            .text,
        '7');
    await tester.tap(find.byKey(const ValueKey('print-options-defaults')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('print-preview-print')));
    await tester.pumpAndSettle();
    expect(result()!.settings.copies, 1);
    final next = await open(tester);
    await tester.tap(find.byKey(const ValueKey('print-preview-print')));
    await tester.pumpAndSettle();
    expect(next()!.settings.paperSize, PrintPaperSize.auto);
    expect(next()!.settings.copies, 1);
  });

  testWidgets('custom input remains editable when saved pages do not exist',
      (tester) async {
    final preferences = await PrintPreferences.load();
    await preferences.saveSettings(PrintSettings(pages: [7, 8], copies: 3),
        range: 'custom', customRange: '8-9');
    await open(tester, pageCount: 3);
    expect(
        tester
            .widget<TextField>(
                find.byKey(const ValueKey('print-preview-range')))
            .controller!
            .text,
        '8-9');
    await tester.tap(find.byKey(const ValueKey('print-preview-print')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('print-preview-dialog')), findsOneWidget);
    await tester.enterText(
        find.byKey(const ValueKey('print-preview-range')), '2-3');
    await tester.pumpAndSettle();
    await cancel(tester);
    final restored = await PrintPreferences.load();
    expect(restored.customRange, '2-3');
    expect(restored.settingsFor([0]).copies, 3);
  });

  testWidgets(
      'current and selected ranges resolve from the newly opened document',
      (tester) async {
    final preferences = await PrintPreferences.load();
    await preferences.saveSettings(PrintSettings(pages: [0]),
        range: 'current', customRange: '1');
    final current = await open(tester, currentPage: 3);
    await tester.tap(find.byKey(const ValueKey('print-preview-print')));
    await tester.pumpAndSettle();
    expect(current()!.settings.pages, [3]);
    await preferences.saveSettings(PrintSettings(pages: [0]),
        range: 'selected', customRange: '1');
    final selected = await open(tester, selectedPages: [4, 2]);
    await tester.tap(find.byKey(const ValueKey('print-preview-print')));
    await tester.pumpAndSettle();
    expect(selected()!.settings.pages, [2, 4]);
    await open(tester);
    await tester.tap(find.byKey(const ValueKey('print-preview-print')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('print-preview-dialog')), findsOneWidget);
    expect(find.text('Pages to print: 0'), findsOneWidget);
  });

  group('Windows destinations', () {
    void mock(FutureOr<Object?> Function(MethodCall) handler) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_channel, (call) async => handler(call));
    }

    testWidgets('loading and stale settings cannot target the wrong printer',
        (tester) async {
      final office = Completer<Object?>();
      mock((call) {
        if (call.method == 'listPrinters') return _printers;
        return call.arguments['printer'] == 'Office'
            ? office.future
            : _settings;
      });
      final result = await open(tester, settle: false);
      expect(
          tester
              .widget<FilledButton>(
                  find.byKey(const ValueKey('print-preview-print')))
              .onPressed,
          isNull);
      final selector = tester.widget<DropdownButton<String>>(
          find.byKey(const ValueKey('print-options-printer')));
      selector.onChanged!('Plotter');
      await tester.pumpAndSettle();
      office.complete({..._settings, 'duplex': 'longEdge'});
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('print-preview-print')));
      await tester.pumpAndSettle();
      expect(result()!.destination!.printer, 'Plotter');
      expect(result()!.destination!.duplex, PrintDuplex.simplex);
    }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

    testWidgets(
        'printer settings failure blocks printing until another queue is chosen',
        (tester) async {
      mock((call) {
        if (call.method == 'listPrinters') return _printers;
        if (call.arguments['printer'] == 'Office') {
          throw PlatformException(code: 'unavailable');
        }
        return _settings;
      });
      final result = await open(tester);
      expect(find.byKey(const ValueKey('print-printer-error')), findsOneWidget);
      expect(
          tester
              .widget<FilledButton>(
                  find.byKey(const ValueKey('print-preview-print')))
              .onPressed,
          isNull);
      await choose(tester, 'printer', 'Plotter');
      await tester.tap(find.byKey(const ValueKey('print-preview-print')));
      await tester.pumpAndSettle();
      expect(result()!.destination!.printer, 'Plotter');
    }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

    testWidgets(
        'restores printer choices, prints directly, and opens properties only on request',
        (tester) async {
      final calls = <MethodCall>[];
      mock((call) {
        calls.add(call);
        return switch (call.method) {
          'listPrinters' => _printers,
          'printerSettings' => _settings,
          'printerProperties' => {
              ..._settings,
              'color': false,
              'duplex': 'shortEdge',
              'tray': 2
            },
          _ => throw StateError(call.method),
        };
      });
      final preferences = await PrintPreferences.load();
      await preferences.saveDestination(const PrintDestination(
          printer: 'Plotter',
          color: false,
          duplex: PrintDuplex.longEdge,
          tray: 2));
      final result = await open(tester);
      expect(
          tester
              .widget<DropdownButton<String>>(
                  find.byKey(const ValueKey('print-options-printer')))
              .value,
          'Plotter');
      expect(
          tester
              .widget<DropdownButton<PrintDuplex>>(
                  find.byKey(const ValueKey('print-options-duplex')))
              .value,
          PrintDuplex.longEdge);
      expect(
          calls.where((call) => call.method == 'printerProperties'), isEmpty);
      await tester.tap(find.byKey(const ValueKey('print-printer-properties')));
      await tester.pumpAndSettle();
      expect(calls.last.method, 'printerProperties');
      expect(calls.last.arguments, containsPair('duplex', 'longEdge'));
      await tester.tap(find.byKey(const ValueKey('print-preview-print')));
      await tester.pumpAndSettle();
      expect(result()!.destination!.printer, 'Plotter');
      expect(result()!.destination!.duplex, PrintDuplex.shortEdge);
      expect(result()!.destination!.color, isFalse);
      expect(result()!.destination!.tray, 2);
      expect((await PrintPreferences.load()).destinationFor('Plotter')!.duplex,
          PrintDuplex.shortEdge);
    }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

    testWidgets(
        'a missing saved printer requires an explicit replacement choice',
        (tester) async {
      mock((call) => call.method == 'listPrinters' ? _printers : _settings);
      await (await PrintPreferences.load())
          .selectPrinter('Disconnected printer');
      final result = await open(tester);
      expect(
          find.byKey(const ValueKey('print-printer-missing')), findsOneWidget);
      expect(
          tester
              .widget<FilledButton>(
                  find.byKey(const ValueKey('print-preview-print')))
              .onPressed,
          isNull);
      expect(
          tester
              .widget<DropdownButton<String>>(
                  find.byKey(const ValueKey('print-options-printer')))
              .value,
          isNull);
      await choose(tester, 'printer', 'Office');
      await tester.tap(find.byKey(const ValueKey('print-preview-print')));
      await tester.pumpAndSettle();
      expect(result()!.destination!.printer, 'Office');
    }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

    testWidgets(
        'empty and failed printer discovery keep Print disabled until retry succeeds',
        (tester) async {
      var attempt = 0;
      mock((call) {
        if (call.method != 'listPrinters') return _settings;
        attempt++;
        if (attempt == 1) throw PlatformException(code: 'unavailable');
        return attempt == 2 ? [] : _printers;
      });
      await open(tester);
      expect(find.byKey(const ValueKey('print-printer-error')), findsOneWidget);
      expect(
          tester
              .widget<FilledButton>(
                  find.byKey(const ValueKey('print-preview-print')))
              .onPressed,
          isNull);
      await tester.tap(find.byKey(const ValueKey('print-printer-retry')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('print-printer-error')), findsOneWidget);
      expect(
          tester
              .widget<FilledButton>(
                  find.byKey(const ValueKey('print-preview-print')))
              .onPressed,
          isNull);
      await tester.tap(find.byKey(const ValueKey('print-printer-retry')));
      await tester.pumpAndSettle();
      expect(
          tester
              .widget<FilledButton>(
                  find.byKey(const ValueKey('print-preview-print')))
              .onPressed,
          isNotNull);
    }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

    testWidgets('saved capabilities are normalized and changes survive Cancel',
        (tester) async {
      mock((call) => call.method == 'listPrinters'
          ? _printers
          : {
              ..._settings,
              'supportsColor': false,
              'supportsDuplex': false,
            });
      await (await PrintPreferences.load()).saveDestination(
          const PrintDestination(
              printer: 'Office',
              color: true,
              duplex: PrintDuplex.longEdge,
              tray: 99));
      await open(tester);
      expect(
          tester
              .widget<DropdownButton<bool>>(
                  find.byKey(const ValueKey('print-options-color')))
              .value,
          isFalse);
      expect(
          tester
              .widget<DropdownButton<PrintDuplex>>(
                  find.byKey(const ValueKey('print-options-duplex')))
              .value,
          PrintDuplex.simplex);
      expect(
          tester
              .widget<DropdownButton<int>>(
                  find.byKey(const ValueKey('print-options-tray')))
              .value,
          1);
      await choose(tester, 'tray', 'Bypass');
      await cancel(tester);
      expect((await PrintPreferences.load()).destinationFor('Office')!.tray, 2);
    }, variant: TargetPlatformVariant.only(TargetPlatform.windows));
  });
}
