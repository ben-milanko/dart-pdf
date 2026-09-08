import 'dart:convert';

import 'package:dart_pdf_editor_app/print_preferences.dart';
import 'package:dart_pdf_editor_app/print_printer.dart';
import 'package:dart_pdf_editor_app/print_settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('every app print choice survives a new preference instance', () async {
    final preferences = await PrintPreferences.load();
    await preferences.saveSettings(
      PrintSettings(
        pages: [7, 8],
        paperSize: PrintPaperSize.a3,
        orientation: PrintOrientation.landscape,
        scaling: PrintScaling.multiple,
        rotation: PrintRotation.clockwise270,
        customScale: 127.5,
        margin: 22,
        offsetX: -5,
        offsetY: 8,
        center: false,
        pagesPerSheet: 6,
        layout: PrintPageLayout.verticalReverse,
        printBorder: true,
        content: PrintContent.markupsOnly,
        dimPageContent: true,
        dimMarkups: true,
        printVisibleHyperlinks: false,
        copies: 4,
        collate: false,
        reverse: true,
        region: const PdfRect(1, 2, 3, 4),
      ),
      range: 'custom',
      customRange: '8-9',
    );
    final restored = await PrintPreferences.load();
    final settings = restored.settingsFor([1]);
    expect(settings.pages, [1]);
    expect(settings.region, isNull);
    expect(settings.paperSize, PrintPaperSize.a3);
    expect(settings.orientation, PrintOrientation.landscape);
    expect(settings.scaling, PrintScaling.multiple);
    expect(settings.rotation, PrintRotation.clockwise270);
    expect(settings.customScale, 127.5);
    expect(settings.margin, 22);
    expect(settings.offsetX, -5);
    expect(settings.offsetY, 8);
    expect(settings.center, isFalse);
    expect(settings.pagesPerSheet, 6);
    expect(settings.layout, PrintPageLayout.verticalReverse);
    expect(settings.printBorder, isTrue);
    expect(settings.content, PrintContent.markupsOnly);
    expect(settings.dimPageContent, isTrue);
    expect(settings.dimMarkups, isTrue);
    expect(settings.printVisibleHyperlinks, isFalse);
    expect(settings.copies, 4);
    expect(settings.collate, isFalse);
    expect(settings.reverse, isTrue);
    expect(restored.range, 'custom');
    expect(restored.customRange, '8-9');
  });

  test('printer choices are independent for each printer', () async {
    final preferences = await PrintPreferences.load();
    await preferences.saveDestination(const PrintDestination(
        printer: 'Office',
        color: false,
        duplex: PrintDuplex.longEdge,
        tray: 2));
    await preferences.saveDestination(const PrintDestination(
        printer: 'Plotter', color: true, duplex: PrintDuplex.simplex, tray: 7));
    final restored = await PrintPreferences.load();
    expect(restored.printer, 'Plotter');
    expect(restored.destinationFor('Office')!.color, isFalse);
    expect(restored.destinationFor('Office')!.duplex, PrintDuplex.longEdge);
    expect(restored.destinationFor('Office')!.tray, 2);
    expect(restored.destinationFor('Plotter')!.tray, 7);
    expect(restored.destinationFor('Other'), isNull);
  });

  test('corrupt and obsolete settings fall back field by field', () async {
    SharedPreferences.setMockInitialValues({
      PrintPreferences.storageKey: jsonEncode({
        'customRange': 17,
        'printer': false,
        'settings': {
          'paperSize': 'oldSize',
          'margin': 300,
          'offsetX': 'bad',
          'copies': 2.5,
          'pagesPerSheet': 2.0,
          'customScale': -1,
          'center': 'bad',
          'reverse': true
        },
      })
    });
    final preferences = await PrintPreferences.load();
    final settings = preferences.settingsFor([0]);
    expect(settings.paperSize, PrintPaperSize.auto);
    expect(settings.margin, 18);
    expect(settings.offsetX, 0);
    expect(settings.copies, 1);
    expect(settings.pagesPerSheet, 2);
    expect(settings.customScale, 100);
    expect(settings.center, isTrue);
    expect(settings.reverse, isTrue);
    expect(preferences.customRange, isNull);
    expect(preferences.printer, isNull);
  });

  test('malformed JSON leaves default preferences usable', () async {
    SharedPreferences.setMockInitialValues({PrintPreferences.storageKey: '{'});
    final preferences = await PrintPreferences.load();
    expect(preferences.settingsFor([0]).copies, 1);
    await preferences.saveSettings(PrintSettings(pages: [0], copies: 3),
        range: 'all', customRange: '1');
    expect((await PrintPreferences.load()).settingsFor([0]).copies, 3);
  });
}
