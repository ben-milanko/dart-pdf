import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'print_printer.dart';
import 'print_settings.dart';

/// Print choices shared by successive jobs and app launches. Source page lists
/// and crop regions belong to a document and are deliberately never stored.
class PrintPreferences {
  PrintPreferences._(this._storage, this._data);

  // Retain the original key so the DartPDF app keeps its common print choices
  // when upgrading to the plugin. SharedPreferences is scoped to the host app.
  static const storageKey = 'dart_pdf_editor.print.preferences.v1';
  final SharedPreferences? _storage;
  final Map<String, dynamic> _data;
  Future<void> _pending = Future.value();

  static Future<PrintPreferences> load() async {
    SharedPreferences? storage;
    Map<String, dynamic> data = {};
    try {
      storage = await SharedPreferences.getInstance();
      final encoded = storage.getString(storageKey);
      if (encoded != null) {
        final decoded = jsonDecode(encoded);
        if (decoded is Map<String, dynamic>) data = decoded;
      }
    } catch (_) {
      // Missing storage (including embedded/test hosts) leaves usable defaults.
    }
    return PrintPreferences._(storage, data);
  }

  String get range =>
      _data['range'] is String ? _data['range'] as String : 'all';
  String? get customRange =>
      _data['customRange'] is String ? _data['customRange'] as String : null;
  String? get printer =>
      _data['printer'] is String ? _data['printer'] as String : null;

  PrintSettings settingsFor(List<int> pages) {
    final raw = _data['settings'];
    final data = raw is Map ? raw : const <String, dynamic>{};
    T choice<T extends Enum>(String key, List<T> choices, T fallback) =>
        choices.where((value) => value.name == data[key]).firstOrNull ??
        fallback;
    double number(String key, double fallback, double min, double max) {
      final value = data[key];
      return value is num && value.isFinite && value >= min && value <= max
          ? value.toDouble()
          : fallback;
    }

    bool flag(String key, bool fallback) =>
        data[key] is bool ? data[key] as bool : fallback;
    final copies = number('copies', 1, 1, 999);
    final pagesPerSheet = data['pagesPerSheet'];
    return PrintSettings(
      pages: pages,
      paperSize:
          choice('paperSize', PrintPaperSize.values, PrintPaperSize.auto),
      orientation:
          choice('orientation', PrintOrientation.values, PrintOrientation.auto),
      scaling: choice('scaling', PrintScaling.values, PrintScaling.none),
      rotation: choice('rotation', PrintRotation.values, PrintRotation.auto),
      customScale: number('customScale', 100, 1, 1000),
      margin: number('margin', 18, 0, 200),
      offsetX: number('offsetX', 0, -100000, 100000),
      offsetY: number('offsetY', 0, -100000, 100000),
      center: flag('center', true),
      pagesPerSheet:
          pagesPerSheet is int && [2, 4, 6, 9, 16].contains(pagesPerSheet)
              ? pagesPerSheet
              : 2,
      layout:
          choice('layout', PrintPageLayout.values, PrintPageLayout.horizontal),
      printBorder: flag('printBorder', false),
      content: choice(
          'content', PrintContent.values, PrintContent.documentAndMarkups),
      dimPageContent: flag('dimPageContent', false),
      dimMarkups: flag('dimMarkups', false),
      printVisibleHyperlinks: flag('printVisibleHyperlinks', true),
      copies: copies == copies.roundToDouble() ? copies.toInt() : 1,
      collate: flag('collate', true),
      reverse: flag('reverse', false),
    );
  }

  Future<void> saveSettings(PrintSettings settings,
      {required String range, required String customRange}) {
    _data['range'] = range;
    _data['customRange'] = customRange;
    _data['settings'] = {
      'paperSize': settings.paperSize.name,
      'orientation': settings.orientation.name,
      'scaling': settings.scaling.name,
      'rotation': settings.rotation.name,
      'customScale': settings.customScale,
      'margin': settings.margin,
      'offsetX': settings.offsetX,
      'offsetY': settings.offsetY,
      'center': settings.center,
      'pagesPerSheet': settings.pagesPerSheet,
      'layout': settings.layout.name,
      'printBorder': settings.printBorder,
      'content': settings.content.name,
      'dimPageContent': settings.dimPageContent,
      'dimMarkups': settings.dimMarkups,
      'printVisibleHyperlinks': settings.printVisibleHyperlinks,
      'copies': settings.copies,
      'collate': settings.collate,
      'reverse': settings.reverse,
    };
    return _save();
  }

  PrintDestination? destinationFor(String name) {
    final printers = _data['printers'];
    final raw = printers is Map ? printers[name] : null;
    if (raw is! Map) return null;
    final duplex = PrintDuplex.values
        .where((value) => value.name == raw['duplex'])
        .firstOrNull;
    return PrintDestination(
      printer: name,
      color: raw['color'] is bool ? raw['color'] as bool : true,
      duplex: duplex ?? PrintDuplex.simplex,
      tray: raw['tray'] is int ? raw['tray'] as int : 0,
    );
  }

  Future<void> selectPrinter(String name) {
    _data['printer'] = name;
    return _save();
  }

  Future<void> saveDestination(PrintDestination destination) {
    _data['printer'] = destination.printer;
    final raw = _data['printers'];
    final printers =
        raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
    printers[destination.printer] = {
      'color': destination.color,
      'duplex': destination.duplex.name,
      'tray': destination.tray,
    };
    _data['printers'] = printers;
    return _save();
  }

  Future<void> _save() {
    final encoded = jsonEncode(_data);
    // Preserve gesture order even when a platform write completes slowly.
    return _pending = _pending.then((_) async {
      try {
        await _storage?.setString(storageKey, encoded);
      } catch (_) {
        // A storage failure must not prevent printing the current job.
      }
    });
  }
}
