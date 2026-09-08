import 'package:flutter/services.dart';

const _channel = MethodChannel('dev.milanko.dartpdf/native_print');

/// An installed Windows print queue. Its name is the stable native identifier.
class PrintPrinter {
  const PrintPrinter({required this.name, this.isDefault = false});

  final String name;
  final bool isDefault;
}

enum PrintDuplex { simplex, longEdge, shortEdge }

class PrintPrinterTray {
  const PrintPrinterTray({required this.id, required this.name});

  final int id;
  final String name;
}

/// The chosen queue's driver preferences and currently supported controls.
class PrintPrinterSettings {
  const PrintPrinterSettings({
    this.color = true,
    this.duplex = PrintDuplex.simplex,
    this.tray = 0,
    this.supportsColor = false,
    this.supportsDuplex = false,
    this.trays = const [],
  });

  final bool color;
  final PrintDuplex duplex;
  final int tray;
  final bool supportsColor;
  final bool supportsDuplex;
  final List<PrintPrinterTray> trays;

  factory PrintPrinterSettings.fromMap(Map<dynamic, dynamic> map) =>
      PrintPrinterSettings(
        color: map['color'] == true,
        duplex: PrintDuplex.values.firstWhere(
          (value) => value.name == map['duplex'],
          orElse: () => PrintDuplex.simplex,
        ),
        tray: (map['tray'] as num?)?.toInt() ?? 0,
        supportsColor: map['supportsColor'] == true,
        supportsDuplex: map['supportsDuplex'] == true,
        trays: [
          for (final item in (map['trays'] as List? ?? const []))
            PrintPrinterTray(
              id: (item['id'] as num).toInt(),
              name: item['name'] as String,
            ),
        ],
      );
}

/// Explicitly selecting a destination opts Windows into direct spooling.
/// Other platforms continue to use their native print surfaces.
class PrintDestination {
  const PrintDestination({
    required this.printer,
    this.color = true,
    this.duplex = PrintDuplex.simplex,
    this.tray = 0,
  });

  final String printer;
  final bool color;
  final PrintDuplex duplex;

  /// A native bin ID, or zero to keep the driver's paper-source default.
  final int tray;

  Map<String, Object> toMap() => {
        'printer': printer,
        'color': color,
        'duplex': duplex.name,
        'tray': tray,
      };
}

Future<List<PrintPrinter>> listPrintPrinters() async {
  final items = await _channel.invokeListMethod<dynamic>('listPrinters');
  return [
    for (final item in items ?? const [])
      PrintPrinter(
          name: item['name'] as String, isDefault: item['isDefault'] == true),
  ];
}

Future<PrintPrinterSettings> loadPrintPrinterSettings(String printer) async {
  final result = await _channel.invokeMapMethod<dynamic, dynamic>(
    'printerSettings',
    {'printer': printer},
  );
  if (result == null) {
    throw PlatformException(
        code: 'print_failed', message: 'Printer unavailable');
  }
  return PrintPrinterSettings.fromMap(result);
}

/// Opens the selected driver's advanced preferences only when requested.
/// The native backend preserves its opaque settings across application restarts.
Future<PrintPrinterSettings?> showPrintPrinterProperties(
  String printer, {
  PrintDestination? settings,
}) async {
  final result = await _channel.invokeMapMethod<dynamic, dynamic>(
    'printerProperties',
    {...?settings?.toMap(), 'printer': printer},
  );
  return result == null ? null : PrintPrinterSettings.fromMap(result);
}
