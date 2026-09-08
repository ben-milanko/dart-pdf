import 'package:dart_pdf_printing/dart_pdf_printing.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dev.milanko.dart_pdf_printing');
  final messenger = binding.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('printer discovery preserves Unicode queue names and OS default',
      () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'listPrinters');
      return [
        {'name': 'Office', 'isDefault': false},
        {'name': r'\\server\Étage 印刷', 'isDefault': true},
      ];
    });
    final printers = await listPrintPrinters();
    expect(printers.map((printer) => printer.name),
        ['Office', r'\\server\Étage 印刷']);
    expect(printers.map((printer) => printer.isDefault), [false, true]);
  });

  test('driver capabilities include the actual tray IDs', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'printerSettings');
      expect(call.arguments, {'printer': 'Office'});
      return {
        'color': false,
        'duplex': 'shortEdge',
        'tray': 257,
        'supportsColor': true,
        'supportsDuplex': true,
        'trays': [
          {'id': 257, 'name': 'Letterhead'}
        ],
      };
    });
    final settings = await loadPrintPrinterSettings('Office');
    expect(settings.color, isFalse);
    expect(settings.duplex, PrintDuplex.shortEdge);
    expect(settings.tray, 257);
    expect(settings.supportsColor, isTrue);
    expect(settings.supportsDuplex, isTrue);
    expect(settings.trays.single.id, 257);
    expect(settings.trays.single.name, 'Letterhead');
  });

  test('advanced preferences receive current common options; cancel is inert',
      () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'printerProperties');
      expect(call.arguments, {
        'printer': 'Office',
        'color': false,
        'duplex': 'longEdge',
        'tray': 7,
      });
      return null;
    });
    expect(
        await showPrintPrinterProperties('Office',
            settings: const PrintDestination(
              printer: 'Office',
              color: false,
              duplex: PrintDuplex.longEdge,
              tray: 7,
            )),
        isNull);
  });

  test('an unavailable driver does not become an empty set of defaults',
      () async {
    messenger.setMockMethodCallHandler(channel, (_) async => null);
    await expectLater(
        loadPrintPrinterSettings('Gone'), throwsA(isA<PlatformException>()));
  });
}
