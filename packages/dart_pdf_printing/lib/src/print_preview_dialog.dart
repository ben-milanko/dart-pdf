import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_cos/pdf_cos.dart';

import '../l10n/print_l10n.dart';
import '../l10n/dart_pdf_printing_localizations.dart';
import 'printing.dart' show printJobName;
import 'print_settings.dart';
import 'print_composer.dart';
import 'print_preferences.dart';
import 'print_printer.dart';

/// The source document and options confirmed for this print job.
class PrintPreviewResult {
  const PrintPreviewResult(
      {required this.document, required this.settings, this.destination});

  final PdfDocument document;
  final PrintSettings settings;
  final PrintDestination? destination;
}

/// Which pages a print job covers.
enum PrintPageRange { all, current, selected, custom }

/// Parses one-based comma-separated pages and inclusive ranges. Duplicate
/// pages are emitted once, in the order entered; invalid input returns null.
List<int>? parsePrintPageRange(String input, int pageCount) {
  final result = <int>{};
  for (final part in input.split(',')) {
    final match = RegExp(r'^\s*(\d+)\s*(?:-\s*(\d+)\s*)?$').firstMatch(part);
    if (match == null) return null;
    final first = int.tryParse(match[1]!);
    final last = int.tryParse(match[2] ?? match[1]!);
    if (first == null ||
        last == null ||
        first < 1 ||
        last < 1 ||
        first > pageCount ||
        last > pageCount) {
      return null;
    }
    final step = first <= last ? 1 : -1;
    for (var page = first;; page += step) {
      result.add(page - 1);
      if (page == last) break;
    }
  }
  return result.isEmpty ? null : result.toList();
}

/// Formats zero-based [pages] as the one-based input [parsePrintPageRange]
/// reads, collapsing consecutive runs: `[0, 1, 2, 4]` becomes `1-3, 5`.
String formatPrintPageRange(List<int> pages) {
  final parts = <String>[];
  for (var i = 0; i < pages.length;) {
    var end = i;
    while (end + 1 < pages.length && pages[end + 1] == pages[end] + 1) {
      end++;
    }
    parts.add(
        end == i ? '${pages[i] + 1}' : '${pages[i] + 1}-${pages[end] + 1}');
    i = end + 1;
  }
  return parts.join(', ');
}

/// Shows the same composed sheets that are sent to the printer.
///
/// Two or more [selectedPages] open it on the Selected range, whatever range
/// the last job used.
Future<PrintPreviewResult?> showPrintPreviewDialog(
  BuildContext context, {
  required PdfDocument document,
  required String title,
  int currentPage = 0,
  List<int> selectedPages = const [],
  Future<List<PdfDocument>> Function()? addFiles,
}) {
  if (document.pageCount == 0) {
    throw ArgumentError.value(document, 'document', 'No printable pages');
  }
  return showPdfDialog<PrintPreviewResult>(
    context: context,
    useRootNavigator: true,
    builder: (_) => PrintPreviewDialog(
      document: document,
      title: title,
      currentPage: currentPage,
      selectedPages: selectedPages,
      addFiles: addFiles,
    ),
  );
}

/// Print settings and, on Windows, destination printer controls. Adding files
/// creates a separate print document.
class PrintPreviewDialog extends StatefulWidget {
  const PrintPreviewDialog({
    super.key,
    required this.document,
    required this.title,
    this.currentPage = 0,
    this.selectedPages = const [],
    this.addFiles,
  });

  final PdfDocument document;
  final String title;
  final int currentPage;
  final List<int> selectedPages;
  final Future<List<PdfDocument>> Function()? addFiles;

  /// Test seam: whether previews are recorded on a background isolate instead
  /// of the UI thread (native only). Production leaves it true. Widget-test suites
  /// that open this dialog set it false in `flutter_test_config.dart`, like
  /// `PdfViewer.debugAutoRenderWorkerEnabled`: a real isolate never completes
  /// under the test binding's fake clock, so the preview would never settle.
  static bool debugRenderWorkerEnabled = true;

  @override
  State<PrintPreviewDialog> createState() => _PrintPreviewDialogState();
}

/// One composed preview sheet, ready to render.
class _ComposedSheet {
  _ComposedSheet(this.bytes, this.document)
      : size = PdfPageRenderer.pageSize(document.page(0));
  final Uint8List bytes;
  final PdfDocument document;
  final Size size;
}

typedef _AreaKey = (String, bool, PrintDuplex, int, double, double);

class _PrintPreviewDialogState extends State<PrintPreviewDialog> {
  // Controller revisions share a mutable COS graph. Retaining their wrapper
  // would let a later edit change the print job while the cached preview
  // still showed the revision that was open when this dialog appeared.
  late PdfDocument _document = _snapshotPrintSource(widget.document);
  late final int _currentPage = widget.currentPage.clamp(0, _pageCount - 1);
  late PrintSettings _settings = PrintSettings(pages: _pages);
  final _rangeInput = TextEditingController();
  // What the user typed for Range mode. Outside Range the field mirrors the
  // pages the chosen chip covers, so this keeps the typed list for when
  // Range is picked again.
  late String _customRange = _defaultCustomRange;
  final _previewAnchor = GlobalKey();
  final _numbers = <String, TextEditingController>{};
  final _invalidNumbers = <String>{};
  late PrintPageRange _range =
      _followsSelection ? PrintPageRange.selected : PrintPageRange.all;
  int _previewSlot = 0;
  bool _rangeInvalid = false;
  bool _choosingRegion = false;
  bool _addingFiles = false;
  String? _error;
  // The sheet on screen. A newer one is composed after the frame that asked
  // for it, so typing into a field never composes inside build, and the old
  // sheet stays visible until its replacement exists.
  (PdfDocument, PrintSettings, int)? _composedFor;
  (PdfDocument, PrintSettings, int)? _composeWanted;
  _ComposedSheet? _composed;
  bool _composeFailed = false;
  bool _composeScheduled = false;
  PdfRenderWorker? _sheetWorker;
  PdfRenderWorker? _sourceWorker;
  PdfDocument? _sourceWorkerFor;
  // Hardware margins per printer, its options and sheet size. Kept for the
  // dialog's lifetime: flipping between paper sizes doesn't ask the driver
  // again.
  final _printableAreas = <_AreaKey, PrintPrintableArea?>{};
  final _areaRequests = <_AreaKey>{};
  PrintPreferences? _preferences;
  String? _preset;
  bool _loadingPreferences = true;
  List<PrintPrinter> _printers = const [];
  String? _printer;
  PrintPrinterSettings? _printerSettings;
  PrintDestination? _destination;
  // The last destination the driver confirmed. Drawn (disabled) while a newly
  // chosen printer loads, in place of an empty gap.
  PrintDestination? _shownDestination;
  bool _loadingPrinters = false;
  bool _loadingPrinter = false;
  String? _printerError;
  String? _missingPrinter;
  int _printerRequest = 0;

  bool get _directWindows =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;
  bool get _printerReady =>
      !_directWindows ||
      (!_loadingPrinters && !_loadingPrinter && _destination != null);

  int get _pageCount => _document.pageCount;
  List<int> get _allPages => List.generate(_pageCount, (i) => i);
  List<int> get _selectedPages => widget.selectedPages
      .where((page) => page >= 0 && page < _pageCount)
      .toSet()
      .toList()
    ..sort();
  // A plain thumbnail click selects (and navigates to) one page, so only a
  // deliberate multi-page selection in the strip decides what prints.
  bool get _followsSelection => _selectedPages.length > 1;
  String get _defaultCustomRange => '${_currentPage + 1}-$_pageCount';
  bool get _marginMode =>
      _settings.scaling == PrintScaling.fitMargins ||
      _settings.scaling == PrintScaling.reduceMargins ||
      _settings.scaling == PrintScaling.multiple;

  @override
  void initState() {
    super.initState();
    _previewSlot = _currentPage;
    _syncRangeInput();
    unawaited(_loadPreferences());
  }

  Future<void> _loadPreferences() async {
    final preferences = await PrintPreferences.load();
    if (!mounted) return;
    setState(() {
      _preferences = preferences;
      final saved = PrintPageRange.values
              .where((value) => value.name == preferences.range)
              .firstOrNull ??
          PrintPageRange.all;
      // The strip's selection is fresher intent than the last job's range,
      // and a remembered Selected with nothing selected now would print no
      // pages. Neither overrides the saved range until the user changes it.
      _range = _followsSelection
          ? PrintPageRange.selected
          : saved == PrintPageRange.selected && _selectedPages.isEmpty
              ? PrintPageRange.all
              : saved;
      // A typed page list belongs to the document it was typed for. Only
      // bring it back when the job resumes in Range mode; otherwise the field
      // keeps this document's own default instead of, say, a previous
      // 14-page file's "1-14".
      if (_range == PrintPageRange.custom) {
        _customRange = preferences.customRange ?? _customRange;
      }
      _syncRangeInput();
      _settings = preferences.settingsFor(_pages);
      _preset = preferences.activePreset;
      _rangeInvalid = _pages.isEmpty;
      if (_range == PrintPageRange.current) _previewSlot = 0;
      _clampPreview();
      _loadingPreferences = false;
    });
    if (_directWindows) await _loadPrinters();
  }

  void _savePreferences() {
    final preferences = _preferences;
    if (preferences != null) {
      unawaited(preferences.saveSettings(_settings,
          range: _range.name, customRange: _customRange));
    }
  }

  Future<void> _loadPrinters() async {
    final request = ++_printerRequest;
    setState(() {
      _loadingPrinters = true;
      _loadingPrinter = false;
      _destination = null;
      _printerError = null;
      _missingPrinter = null;
    });
    try {
      final printers = await listPrintPrinters();
      if (!mounted || request != _printerRequest) return;
      final preset = _preset == null ? null : _preferences?.preset(_preset!);
      final saved = preset?.destination?.printer ?? _preferences?.printer;
      final savedExists = printers.any((printer) => printer.name == saved);
      final name = saved != null
          ? (savedExists ? saved : null)
          : printers.where((printer) => printer.isDefault).firstOrNull?.name;
      setState(() {
        _printers = printers;
        _printer = name;
        _loadingPrinters = false;
        _missingPrinter = saved != null && !savedExists ? saved : null;
        if (name == null) _printerSettings = null;
        if (printers.isEmpty) {
          _printerError = printL10n(context).printOptionsNoPrinters;
        }
      });
      if (name != null) {
        await _selectPrinter(name, preferred: preset?.destination);
      }
    } catch (_) {
      if (!mounted || request != _printerRequest) return;
      setState(() {
        _loadingPrinters = false;
        _printerSettings = null;
        _printerError = printL10n(context).printOptionsPrinterError;
      });
    }
  }

  /// [preferred] (a preset's choices) wins over what was last used with
  /// [name]. The previous printer's controls stay on screen, disabled, while
  /// the driver answers, so the panel doesn't collapse and re-grow.
  Future<void> _selectPrinter(String name,
      {PrintDestination? preferred}) async {
    final request = ++_printerRequest;
    setState(() {
      _printer = name;
      _destination = null;
      _loadingPrinter = true;
      _printerError = null;
      _missingPrinter = null;
    });
    unawaited(_preferences!.selectPrinter(name));
    try {
      final settings = await loadPrintPrinterSettings(name);
      if (!mounted || request != _printerRequest) return;
      _acceptPrinterSettings(
          name, settings, preferred ?? _preferences!.destinationFor(name));
    } catch (_) {
      if (!mounted || request != _printerRequest) return;
      setState(() {
        _loadingPrinter = false;
        _printerSettings = null;
        _printerError = printL10n(context).printOptionsPrinterError;
      });
    }
  }

  void _acceptPrinterSettings(
      String name, PrintPrinterSettings settings, PrintDestination? saved) {
    final tray = saved?.tray ?? settings.tray;
    final defaultTray = settings.trays.any((item) => item.id == settings.tray)
        ? settings.tray
        : 0;
    final destination = PrintDestination(
      printer: name,
      color: settings.supportsColor && (saved?.color ?? settings.color),
      duplex: settings.supportsDuplex
          ? saved?.duplex ?? settings.duplex
          : PrintDuplex.simplex,
      tray: tray == 0 || settings.trays.any((item) => item.id == tray)
          ? tray
          : defaultTray,
    );
    setState(() {
      _printerSettings = settings;
      _destination = destination;
      _shownDestination = destination;
      _loadingPrinter = false;
      _printerError = null;
    });
    unawaited(_preferences!.saveDestination(destination));
  }

  void _changeDestination({bool? color, PrintDuplex? duplex, int? tray}) {
    final current = _destination!;
    final destination = PrintDestination(
        printer: current.printer,
        color: color ?? current.color,
        duplex: duplex ?? current.duplex,
        tray: tray ?? current.tray);
    setState(() => _destination = _shownDestination = destination);
    unawaited(_preferences!.saveDestination(destination));
  }

  Future<void> _printerProperties() async {
    final name = _printer!;
    final previous = _destination;
    final request = ++_printerRequest;
    setState(() => _loadingPrinter = true);
    try {
      final settings =
          await showPrintPrinterProperties(name, settings: previous);
      if (!mounted || request != _printerRequest) return;
      if (settings != null) {
        _acceptPrinterSettings(name, settings, null);
      } else {
        setState(() => _loadingPrinter = false);
      }
    } catch (_) {
      if (!mounted || request != _printerRequest) return;
      setState(() {
        _loadingPrinter = false;
        _printerError = printL10n(context).printOptionsPropertiesError;
      });
    }
  }

  @override
  void dispose() {
    _sheetWorker?.dispose();
    _sourceWorker?.dispose();
    _rangeInput.dispose();
    for (final controller in _numbers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  List<int> get _pages => switch (_range) {
        PrintPageRange.all => _allPages,
        PrintPageRange.current => [_currentPage],
        PrintPageRange.selected => _selectedPages,
        PrintPageRange.custom =>
          parsePrintPageRange(_rangeInput.text, _pageCount) ?? [],
      };

  void _change(PrintSettings settings) {
    setState(() {
      _settings = settings;
      _error = null;
      _clampPreview();
    });
    _savePreferences();
  }

  /// Shows the pages the current mode covers in the range field: the typed
  /// list in Range mode, otherwise the chip's own pages (All on a 14-page
  /// file reads `1-14`, not a stale `3-14`).
  void _syncRangeInput() {
    final text = _range == PrintPageRange.custom
        ? _customRange
        : formatPrintPageRange(_pages);
    // Typing already put this text in the field; reassigning it would only
    // move the caret.
    if (_rangeInput.text != text) _rangeInput.text = text;
  }

  void _setRange(PrintPageRange range) {
    setState(() {
      _range = range;
      _syncRangeInput();
      _rangeInvalid = false;
      _error = null;
      _settings = _settings.copyWith(
          pages: _pages, clearRegion: range != PrintPageRange.current);
      _choosingRegion = false;
      if (range == PrintPageRange.current) _previewSlot = 0;
      _clampPreview();
    });
    _savePreferences();
  }

  void _clampPreview() {
    final count = printSheetCount(_settings);
    _previewSlot = count == 0 ? 0 : _previewSlot.clamp(0, count - 1);
  }

  void _defaults() {
    setState(() {
      _range = PrintPageRange.all;
      _customRange = _defaultCustomRange;
      _syncRangeInput();
      _settings = PrintSettings(pages: _allPages);
      _previewSlot = _currentPage;
      _rangeInvalid = false;
      _choosingRegion = false;
      _error = null;
      _preset = null;
      _syncNumberFields();
    });
    unawaited(_preferences?.selectPreset(null));
    _savePreferences();
  }

  /// Points every number field at [_settings], discarding any invalid text.
  void _syncNumberFields() {
    _invalidNumbers.clear();
    for (final entry in _numbers.entries) {
      entry.value.text = _format(switch (entry.key) {
        'copies' => _settings.copies.toDouble(),
        'scale' => _settings.customScale,
        'margin' => _settings.margin,
        'offset-x' => _settings.offsetX,
        'offset-y' => _settings.offsetY,
        _ => 0,
      });
    }
  }

  void _applyPreset(String? name) {
    final preset = name == null ? null : _preferences?.preset(name);
    setState(() {
      _preset = preset?.name;
      if (preset != null) {
        _settings =
            preset.settingsFor(_pages).copyWith(region: _settings.region);
        _error = null;
        _syncNumberFields();
        _clampPreview();
      }
    });
    unawaited(_preferences?.selectPreset(preset?.name));
    if (preset == null) return;
    _savePreferences();
    final destination = preset.destination;
    if (_directWindows && destination != null) {
      if (_printers.any((printer) => printer.name == destination.printer)) {
        unawaited(_selectPrinter(destination.printer, preferred: destination));
      } else if (!_loadingPrinters) {
        setState(() => _missingPrinter = destination.printer);
      }
    }
  }

  Future<void> _savePreset() async {
    final preferences = _preferences;
    if (preferences == null) return;
    final result = await showPdfDialog<(String, bool)>(
      context: context,
      builder: (_) => _SavePresetDialog(
        initialName: _preset ?? '',
        existing: preferences.presetNames,
        printer: _directWindows ? _destination?.printer : null,
        includePrinter: _preset == null ||
            preferences.preset(_preset!)?.destination != null,
      ),
    );
    if (!mounted || result == null) return;
    final (name, includePrinter) = result;
    await preferences.savePreset(name, _settings,
        destination: includePrinter ? _destination : null);
    if (mounted) setState(() => _preset = name);
  }

  Future<void> _deletePreset() async {
    final name = _preset;
    if (name == null) return;
    setState(() => _preset = null);
    await _preferences?.deletePreset(name);
    if (mounted) setState(() {});
  }

  Future<void> _addFiles() async {
    setState(() => _addingFiles = true);
    try {
      final incoming = await widget.addFiles!();
      if (!mounted || incoming.isEmpty) return;
      final merged = _mergePrintSources([_document, ...incoming]);
      if (!mounted) return;
      setState(() {
        _document = merged;
        _syncRangeInput();
        _settings = _settings.copyWith(pages: _pages);
        _error = null;
      });
    } catch (_) {
      if (mounted) {
        setState(() => _error = printL10n(context).printOptionsAddFailed);
      }
    } finally {
      if (mounted) setState(() => _addingFiles = false);
    }
  }

  void _print() {
    if (_loadingPreferences || !_printerReady) return;
    if (_settings.pages.isEmpty || _invalidNumbers.isNotEmpty) {
      setState(() => _rangeInvalid = _settings.pages.isEmpty);
      return;
    }
    try {
      validatePrintSettings(_document, _settings);
    } catch (_) {
      setState(() => _error = printL10n(context).printOptionsInvalidLayout);
      return;
    }
    try {
      preparePrintDocument(_document, _settings,
          includeCopies: false, sheetIndex: _previewSlot);
    } catch (_) {
      setState(() => _error = printL10n(context).printOptionsInvalidLayout);
      return;
    }
    Navigator.of(context).pop(PrintPreviewResult(
        document: _document, settings: _settings, destination: _destination));
  }

  /// The sheet to show, asking for a fresh one when the job has changed
  /// since it was composed. Safe to call from build: composition runs after
  /// the frame, once, however many settings changed during it.
  _ComposedSheet? _sheet() {
    if (_loadingPreferences || _settings.pages.isEmpty) return null;
    final key = (_document, _settings, _previewSlot);
    if (_composedFor != key) {
      _composeWanted = key;
      if (!_composeScheduled) {
        _composeScheduled = true;
        SchedulerBinding.instance.addPostFrameCallback((_) => _compose());
      }
    }
    return _composed;
  }

  void _compose() {
    _composeScheduled = false;
    final key = _composeWanted;
    if (!mounted || key == null || key == _composedFor) return;
    final (document, settings, slot) = key;
    _ComposedSheet? sheet;
    try {
      final bytes = preparePrintDocument(document, settings,
          includeCopies: false, sheetIndex: slot);
      sheet = _ComposedSheet(bytes, PdfDocument.open(bytes));
    } catch (_) {
      sheet = null;
    }
    _sheetWorker?.dispose();
    _sheetWorker = sheet != null && _offThreadRenders
        ? PdfRenderWorker.startUncached(sheet.bytes)
        : null;
    setState(() {
      _composedFor = key;
      _composed = sheet;
      _composeFailed = sheet == null;
    });
  }

  // Each composed sheet gets a fresh worker. A native isolate spawns in
  // milliseconds; a Web Worker boots a ~1 MB script (over a second on a
  // phone), far too slow to start per settings change, so web keeps its
  // on-thread render.
  bool get _offThreadRenders =>
      PrintPreviewDialog.debugRenderWorkerEnabled && !kIsWeb;

  PdfRenderWorker? _workerForSource() {
    if (!_offThreadRenders) return null;
    if (!identical(_sourceWorkerFor, _document)) {
      _sourceWorker?.dispose();
      _sourceWorkerFor = _document;
      _sourceWorker = PdfRenderWorker.startUncached(_document.cos.bytes,
          populatedRanges: _document.cos.populatedRanges);
    }
    return _sourceWorker;
  }

  /// The selected printer's unprintable edges for a sheet of [size], or null
  /// while unknown (not Windows, no printer yet, or the driver hasn't
  /// answered). Asks the driver in the background the first time.
  PrintPrintableArea? _printableArea(Size size) {
    final destination = _destination;
    if (!_directWindows || destination == null) return null;
    final key = (
      destination.printer,
      destination.color,
      destination.duplex,
      destination.tray,
      size.width,
      size.height,
    );
    if (_printableAreas.containsKey(key)) return _printableAreas[key];
    if (_areaRequests.add(key)) {
      () async {
        PrintPrintableArea? area;
        try {
          area = await loadPrintPrintableArea(
              destination, size.width, size.height);
        } catch (_) {
          area = null;
        }
        _areaRequests.remove(key);
        if (!mounted) return;
        setState(() => _printableAreas[key] = area);
      }();
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = printL10n(context);
    final theme = Theme.of(context);
    final media = MediaQuery.of(context);
    final narrow = media.size.width < 800;
    final size = Size(
        (media.size.width - (narrow ? 24 : 48)).clamp(0, 1160),
        (media.size.height - media.viewInsets.bottom - (narrow ? 24 : 48))
            .clamp(0, 860));
    final options = _loadingPreferences
        ? const Center(child: CircularProgressIndicator())
        : _options(l10n);
    final preview = _preview(l10n);
    return Dialog(
      key: const ValueKey('print-preview-dialog'),
      insetPadding: EdgeInsets.all(narrow ? 12 : 24),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: size.width,
        height: size.height,
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
            child: Row(children: [
              const Icon(Icons.print_outlined),
              const SizedBox(width: 12),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(l10n.printPreviewTitle,
                        style: theme.textTheme.titleLarge),
                    Text(printJobName(widget.title),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall),
                  ])),
            ]),
          ),
          const Divider(height: 1),
          Expanded(
              child: narrow
                  ? SingleChildScrollView(
                      key: const ValueKey('print-options-scroll'),
                      padding: const EdgeInsets.all(16),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SizedBox(height: 310, child: preview),
                            const Divider(height: 24),
                            options,
                          ]),
                    )
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                          SizedBox(
                              width: 360,
                              child: SingleChildScrollView(
                                  key: const ValueKey('print-options-scroll'),
                                  padding: const EdgeInsets.all(20),
                                  child: options)),
                          const VerticalDivider(width: 1),
                          Expanded(
                              child: Padding(
                                  padding: const EdgeInsets.all(20),
                                  child: preview)),
                        ])),
          const Divider(height: 1),
          Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_error != null ||
                      _rangeInvalid ||
                      _invalidNumbers.isNotEmpty)
                    Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                            _error ??
                                (_rangeInvalid
                                    ? l10n.printPreviewRangeError(_pageCount)
                                    : l10n.printOptionsInvalidNumber),
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: theme.colorScheme.error))),
                  OverflowBar(
                      alignment: MainAxisAlignment.spaceBetween,
                      overflowAlignment: OverflowBarAlignment.end,
                      spacing: 8,
                      children: [
                        TextButton(
                            key: const ValueKey('print-options-defaults'),
                            onPressed: _loadingPreferences ? null : _defaults,
                            child: Text(l10n.printOptionsDefaults)),
                        Row(mainAxisSize: MainAxisSize.min, children: [
                          TextButton(
                              key: const ValueKey('print-preview-cancel'),
                              onPressed: () => Navigator.of(context).pop(),
                              child: Text(l10n.cancel)),
                          const SizedBox(width: 8),
                          PdfDialogSubmit.action(
                              onSubmit: _addingFiles ||
                                      _loadingPreferences ||
                                      !_printerReady
                                  ? null
                                  : _print,
                              child: FilledButton(
                                  key: const ValueKey('print-preview-print'),
                                  onPressed: _addingFiles ||
                                          _loadingPreferences ||
                                          !_printerReady
                                      ? null
                                      : _print,
                                  child: Text(l10n.printPreviewPrint))),
                        ]),
                      ]),
                ],
              )),
        ]),
      ),
    );
  }

  Widget _section(String title, List<Widget> children) => Padding(
        padding: const EdgeInsets.only(bottom: 20),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(title, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 10),
          ...children,
        ]),
      );

  Widget _dropdown<T>(String key, String label, T? value,
          Map<T, String> options, ValueChanged<T> changed,
          {String? hint}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: InputDecorator(
          decoration: InputDecoration(
              labelText: label,
              isDense: true,
              border: const OutlineInputBorder()),
          child: PdfDropdown<T>(
            key: ValueKey('print-options-$key'),
            value: value,
            hint: hint == null ? null : Text(hint),
            isExpanded: true,
            isDense: true,
            underline: const SizedBox.shrink(),
            items: [
              for (final entry in options.entries)
                PdfDropdownItem(
                    value: entry.key,
                    label: entry.value,
                    child: Text(entry.value, overflow: TextOverflow.ellipsis))
            ],
            onChanged: changed,
          ),
        ),
      );

  Widget _check(
          String key, String label, bool value, ValueChanged<bool> changed,
          {bool enabled = true}) =>
      CheckboxListTile(
        key: ValueKey('print-options-$key'),
        value: value,
        title: Text(label),
        dense: true,
        contentPadding: EdgeInsets.zero,
        controlAffinity: ListTileControlAffinity.leading,
        onChanged: enabled ? (value) => changed(value!) : null,
      );

  Widget _number(
      String key, String label, double value, ValueChanged<double> changed,
      {double min = -100000, double max = 100000, bool integer = false}) {
    final controller = _numbers.putIfAbsent(
        key, () => TextEditingController(text: _format(value)));
    return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
          key: ValueKey('print-options-$key'),
          controller: controller,
          contextMenuBuilder: pdfTextContextMenu,
          keyboardType: TextInputType.numberWithOptions(
              decimal: !integer, signed: min < 0),
          decoration: InputDecoration(
              labelText: label,
              isDense: true,
              border: const OutlineInputBorder(),
              errorText: _invalidNumbers.contains(key)
                  ? printL10n(context).printOptionsInvalidValue
                  : null),
          onChanged: (text) {
            final number = double.tryParse(text);
            if (number == null ||
                !number.isFinite ||
                number < min ||
                number > max ||
                (integer && number != number.roundToDouble())) {
              setState(() => _invalidNumbers.add(key));
            } else {
              _invalidNumbers.remove(key);
              changed(number);
            }
          },
        ));
  }

  double _pageUnit(PdfPage page) {
    final value = _document.cos.resolve(page.dict['UserUnit']);
    final unit = switch (value) {
      CosInteger(:final value) => value.toDouble(),
      CosReal(:final value) => value,
      _ => 1.0
    };
    return unit.isFinite && unit > 0 ? unit : 1.0;
  }

  String _format(double value) => value == value.roundToDouble()
      ? value.toInt().toString()
      : value.toStringAsFixed(1);

  Widget _printerOptions(DartPdfPrintingLocalizations l10n) {
    if (!_directWindows) {
      return _section(l10n.printOptionsPrinter, [
        Text(l10n.printOptionsNativePrinter,
            style: Theme.of(context).textTheme.bodySmall),
      ]);
    }
    final destination = _destination;
    final shown = destination ?? _shownDestination;
    final settings = _printerSettings;
    return _section(l10n.printOptionsPrinter, [
      Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(l10n.printOptionsDirectPrinter,
              style: Theme.of(context).textTheme.bodySmall)),
      // One fixed-height slot for either query, so the controls below never
      // shift when a progress bar comes and goes.
      SizedBox(
          height: 4,
          child: _loadingPrinters
              ? LinearProgressIndicator(
                  key: const ValueKey('print-printers-loading'),
                  semanticsLabel: l10n.printOptionsLoadingPrinters)
              : _loadingPrinter
                  ? LinearProgressIndicator(
                      key: const ValueKey('print-printer-loading'),
                      semanticsLabel: l10n.printOptionsLoadingPrinters)
                  : null),
      const SizedBox(height: 8),
      if (_printers.isNotEmpty || _loadingPrinters)
        AbsorbPointer(
            absorbing: _loadingPrinters,
            child: _dropdown<String>(
                'printer',
                l10n.printOptionsPrinter,
                _printer,
                {for (final printer in _printers) printer.name: printer.name},
                (value) => unawaited(_selectPrinter(value)),
                hint: _loadingPrinters
                    ? l10n.printOptionsLoadingPrinters
                    : l10n.printOptionsChoosePrinter)),
      if (_missingPrinter != null)
        Text(l10n.printOptionsPrinterUnavailable(_missingPrinter!),
            key: const ValueKey('print-printer-missing'),
            style: TextStyle(color: Theme.of(context).colorScheme.error)),
      if (_printerError != null)
        Text(_printerError!,
            key: const ValueKey('print-printer-error'),
            style: TextStyle(color: Theme.of(context).colorScheme.error)),
      if (settings != null && shown != null)
        AbsorbPointer(
            absorbing: _loadingPrinter || destination == null,
            child: Opacity(
                opacity: _loadingPrinter ? 0.6 : 1,
                child: Column(children: [
                  _dropdown<bool>(
                      'color',
                      l10n.printOptionsColor,
                      shown.color,
                      {
                        if (settings.supportsColor)
                          true: l10n.printOptionsColor,
                        false: l10n.printOptionsGrayscale
                      },
                      (value) => _changeDestination(color: value)),
                  _dropdown<PrintDuplex>(
                      'duplex',
                      l10n.printOptionsDuplex,
                      shown.duplex,
                      {
                        PrintDuplex.simplex: l10n.printOptionsSimplex,
                        if (settings.supportsDuplex) ...{
                          PrintDuplex.longEdge: l10n.printOptionsLongEdge,
                          PrintDuplex.shortEdge: l10n.printOptionsShortEdge,
                        }
                      },
                      (value) => _changeDestination(duplex: value)),
                  _dropdown<int>(
                      'tray',
                      l10n.printOptionsTray,
                      shown.tray,
                      {
                        0: l10n.printOptionsDefaultTray,
                        for (final tray in settings.trays) tray.id: tray.name,
                      },
                      (value) => _changeDestination(tray: value)),
                ]))),
      Wrap(spacing: 8, children: [
        TextButton.icon(
            key: const ValueKey('print-printer-retry'),
            onPressed: _loadingPrinters || _loadingPrinter
                ? null
                : () => unawaited(_loadPrinters()),
            icon: const Icon(Icons.refresh),
            label: Text(l10n.printOptionsRetry)),
        if (shown != null)
          TextButton(
              key: const ValueKey('print-printer-properties'),
              onPressed: _loadingPrinter || destination == null
                  ? null
                  : () => unawaited(_printerProperties()),
              child: Text(l10n.printOptionsProperties)),
      ]),
    ]);
  }

  Widget _presetOptions(DartPdfPrintingLocalizations l10n) {
    final preferences = _preferences!;
    final names = preferences.presetNames;
    final preset = _preset == null ? null : preferences.preset(_preset!);
    final modified = preset != null &&
        !preset.matches(_settings,
            current: _directWindows && !_loadingPrinter ? _destination : null);
    return _section(l10n.printPresets, [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
            child: _dropdown<String>(
                'preset',
                l10n.printPresetLabel,
                preset?.name ?? '',
                {
                  '': names.isEmpty
                      ? l10n.printPresetNoneSaved
                      : l10n.printPresetNone,
                  for (final name in names) name: name,
                },
                (value) => _applyPreset(value.isEmpty ? null : value))),
        const SizedBox(width: 4),
        IconButton(
            key: const ValueKey('print-preset-save'),
            tooltip: l10n.printPresetSave,
            onPressed: _savePreset,
            icon: const Icon(Icons.save_outlined)),
        IconButton(
            key: const ValueKey('print-preset-delete'),
            tooltip: l10n.printPresetDelete,
            onPressed: preset == null ? null : _deletePreset,
            icon: const Icon(Icons.delete_outline)),
      ]),
      if (modified)
        Text(l10n.printPresetModified,
            key: const ValueKey('print-preset-modified'),
            style: Theme.of(context).textTheme.bodySmall),
    ]);
  }

  Widget _options(DartPdfPrintingLocalizations l10n) =>
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _presetOptions(l10n),
        _printerOptions(l10n),
        _section(l10n.printOptionsPages, [
          Wrap(spacing: 8, runSpacing: 4, children: [
            for (final entry in {
              PrintPageRange.all: l10n.printPreviewAll,
              PrintPageRange.current: l10n.printPreviewCurrent,
              if (_selectedPages.isNotEmpty ||
                  _range == PrintPageRange.selected)
                PrintPageRange.selected: l10n.printOptionsSelected,
              PrintPageRange.custom: l10n.printPreviewRange,
            }.entries)
              ChoiceChip(
                  key: ValueKey('print-preview-${entry.key.name}'),
                  label: Text(entry.value),
                  selected: _range == entry.key,
                  onSelected: (_) => _setRange(entry.key)),
          ]),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('print-preview-range'),
            controller: _rangeInput,
            contextMenuBuilder: pdfTextContextMenu,
            decoration: InputDecoration(
                labelText: l10n.printOptionsPageRange,
                hintText: '1, 3-5',
                isDense: true,
                border: const OutlineInputBorder()),
            onChanged: (text) {
              _customRange = text;
              _setRange(PrintPageRange.custom);
            },
          ),
          const SizedBox(height: 8),
          Text(l10n.printPreviewSelection(_settings.pages.length),
              style: Theme.of(context).textTheme.bodySmall),
          if (widget.addFiles != null)
            Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                    key: const ValueKey('print-options-add-files'),
                    onPressed: _addingFiles ? null : _addFiles,
                    icon: const Icon(Icons.note_add_outlined),
                    label: Text(l10n.printOptionsAddFiles))),
          Wrap(spacing: 8, children: [
            OutlinedButton.icon(
                key: const ValueKey('print-options-window'),
                onPressed: () {
                  final choosing = !_choosingRegion;
                  _setRange(PrintPageRange.current);
                  setState(() => _choosingRegion = choosing);
                  if (choosing) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      final previewContext = _previewAnchor.currentContext;
                      if (mounted && previewContext != null) {
                        Scrollable.ensureVisible(previewContext,
                            duration: const Duration(milliseconds: 200));
                      }
                    });
                  }
                },
                icon: const Icon(Icons.crop),
                label: Text(l10n.printOptionsGetWindow)),
            if (_settings.region != null)
              TextButton(
                  key: const ValueKey('print-options-clear-window'),
                  onPressed: () =>
                      _change(_settings.copyWith(clearRegion: true)),
                  child: Text(l10n.printOptionsClearWindow)),
          ]),
          if (_settings.region case final region?)
            Text(
                l10n.printOptionsAreaSize(
                    _format(
                        region.width * _pageUnit(_document.page(_currentPage))),
                    _format(region.height *
                        _pageUnit(_document.page(_currentPage)))),
                style: Theme.of(context).textTheme.bodySmall),
        ]),
        _section(l10n.printOptionsPaper, [
          _dropdown(
              'paper',
              l10n.printOptionsPaperSize,
              _settings.paperSize,
              {
                PrintPaperSize.auto: l10n.printOptionsPageSize,
                for (final paper in PrintPaperSize.values
                    .where((p) => p != PrintPaperSize.auto))
                  paper: paper.name.toUpperCase(),
              },
              (value) => _change(_settings.copyWith(paperSize: value))),
          _dropdown(
              'orientation',
              l10n.printOptionsOrientation,
              _settings.orientation,
              {
                PrintOrientation.auto: l10n.printOptionsAuto,
                PrintOrientation.portrait: l10n.printOptionsPortrait,
                PrintOrientation.landscape: l10n.printOptionsLandscape,
              },
              (value) => _change(_settings.copyWith(orientation: value))),
        ]),
        _section(l10n.printOptionsCopies, [
          _number(
              'copies',
              l10n.printOptionsCopies,
              _settings.copies.toDouble(),
              (value) => _change(_settings.copyWith(copies: value.toInt())),
              min: 1,
              max: 999,
              integer: true),
          _check('collate', l10n.printOptionsCollate, _settings.collate,
              (value) => _change(_settings.copyWith(collate: value))),
          _check('reverse', l10n.printOptionsReverse, _settings.reverse,
              (value) => _change(_settings.copyWith(reverse: value))),
        ]),
        _section(l10n.printOptionsLayout, [
          _dropdown('scaling', l10n.printOptionsScaling, _settings.scaling, {
            PrintScaling.none: l10n.printOptionsScaleNone,
            PrintScaling.fitPaper: l10n.printOptionsFitPaper,
            PrintScaling.reducePaper: l10n.printOptionsReducePaper,
            PrintScaling.fitMargins: l10n.printOptionsFitMargins,
            PrintScaling.reduceMargins: l10n.printOptionsReduceMargins,
            PrintScaling.custom: l10n.printOptionsCustomScale,
            PrintScaling.multiple: l10n.printOptionsMultiple,
          }, (value) {
            if (_invalidNumbers.remove('scale')) {
              _numbers['scale']?.text = _format(_settings.customScale);
            }
            if (_invalidNumbers.remove('margin')) {
              _numbers['margin']?.text = _format(_settings.margin);
            }
            _change(_settings.copyWith(scaling: value));
          }),
          if (_settings.scaling == PrintScaling.custom)
            _number(
                'scale',
                l10n.printOptionsScalePercent,
                _settings.customScale,
                (value) => _change(_settings.copyWith(customScale: value)),
                min: 1,
                max: 1000),
          if (_marginMode)
            _number('margin', l10n.printOptionsMargin, _settings.margin,
                (value) => _change(_settings.copyWith(margin: value)),
                min: 0, max: 200),
          if (_settings.scaling == PrintScaling.multiple) ...[
            _dropdown(
                'pages-per-sheet',
                l10n.printOptionsPagesPerSheet,
                _settings.pagesPerSheet,
                {
                  for (final count in [2, 4, 6, 9, 16]) count: '$count'
                },
                (value) => _change(_settings.copyWith(pagesPerSheet: value))),
            _dropdown(
                'page-layout',
                l10n.printOptionsPageOrder,
                _settings.layout,
                {
                  PrintPageLayout.horizontal: l10n.printOptionsHorizontal,
                  PrintPageLayout.horizontalReverse:
                      l10n.printOptionsHorizontalReverse,
                  PrintPageLayout.vertical: l10n.printOptionsVertical,
                  PrintPageLayout.verticalReverse:
                      l10n.printOptionsVerticalReverse,
                },
                (value) => _change(_settings.copyWith(layout: value))),
            _check('border', l10n.printOptionsBorder, _settings.printBorder,
                (value) => _change(_settings.copyWith(printBorder: value))),
          ],
          _dropdown(
              'rotation',
              l10n.printOptionsRotation,
              _settings.rotation,
              {
                PrintRotation.auto: l10n.printOptionsAuto,
                PrintRotation.none: l10n.printOptionsNoRotation,
                PrintRotation.clockwise90: '90°',
                PrintRotation.halfTurn: '180°',
                PrintRotation.clockwise270: '270°',
              },
              (value) => _change(_settings.copyWith(rotation: value))),
          _check('center', l10n.printOptionsCenter, _settings.center,
              (value) => _change(_settings.copyWith(center: value))),
          Row(children: [
            Expanded(
                child: _number(
                    'offset-x',
                    l10n.printOptionsOffsetX,
                    _settings.offsetX,
                    (value) => _change(_settings.copyWith(offsetX: value)))),
            const SizedBox(width: 12),
            Expanded(
                child: _number(
                    'offset-y',
                    l10n.printOptionsOffsetY,
                    _settings.offsetY,
                    (value) => _change(_settings.copyWith(offsetY: value)))),
          ]),
        ]),
        _section(l10n.printOptionsContents, [
          _dropdown(
              'content',
              l10n.printOptionsContents,
              _settings.content,
              {
                PrintContent.documentAndMarkups:
                    l10n.printOptionsDocumentAndMarkups,
                PrintContent.documentOnly: l10n.printOptionsDocumentOnly,
                PrintContent.markupsOnly: l10n.printOptionsMarkupsOnly,
              },
              (value) => _change(_settings.copyWith(content: value))),
          _check('dim-page', l10n.printOptionsDimPage, _settings.dimPageContent,
              (value) => _change(_settings.copyWith(dimPageContent: value)),
              enabled: _settings.content != PrintContent.markupsOnly),
          _check(
              'dim-markups',
              l10n.printOptionsDimMarkups,
              _settings.dimMarkups,
              (value) => _change(_settings.copyWith(dimMarkups: value)),
              enabled: _settings.content != PrintContent.documentOnly),
          _check(
              'hyperlinks',
              l10n.printOptionsHyperlinks,
              _settings.printVisibleHyperlinks,
              (value) =>
                  _change(_settings.copyWith(printVisibleHyperlinks: value))),
        ]),
      ]);

  Widget _preview(DartPdfPrintingLocalizations l10n) {
    final composed = _sheet();
    final sheet = _choosingRegion ? _document : composed?.document;
    final pageIndex = _choosingRegion ? _currentPage : 0;
    final hardware = _choosingRegion || composed == null
        ? null
        : _printableArea(composed.size);
    final count = printSheetCount(_settings);
    final orderedPages =
        _settings.reverse ? _settings.pages.reversed.toList() : _settings.pages;
    final sourceIndex = _settings.pages.isEmpty
        ? _currentPage
        : orderedPages[(_previewSlot *
                (_settings.scaling == PrintScaling.multiple
                    ? _settings.pagesPerSheet
                    : 1))
            .clamp(0, _settings.pages.length - 1)];
    final sourcePage = _document.page(sourceIndex);
    final unit = _pageUnit(sourcePage);
    final source = PdfPageRenderer.pageSize(sourcePage) * unit;
    final size = _choosingRegion ? null : composed?.size;
    return Column(
        key: _previewAnchor,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_choosingRegion)
            Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(l10n.printOptionsWindowHint)),
          Expanded(
              child: ColoredBox(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: sheet == null
                          ? Center(
                              child: _settings.pages.isEmpty ||
                                      (_composeFailed && !_choosingRegion)
                                  ? Text(_settings.pages.isEmpty
                                      ? l10n.printPreviewRangeError(_pageCount)
                                      : l10n.printPreviewUnavailable)
                                  : const SizedBox(
                                      width: 24,
                                      height: 24,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2)))
                          : _PagePreview(
                              document: sheet,
                              pageIndex: pageIndex,
                              worker: _choosingRegion
                                  ? _workerForSource()
                                  : _sheetWorker,
                              stale: !_choosingRegion &&
                                  (_composeFailed ||
                                      _composedFor !=
                                          (_document, _settings, _previewSlot)),
                              printableArea: hardware,
                              margin: !_choosingRegion && _marginMode
                                  ? _settings.margin
                                  : 0,
                              region: _choosingRegion ? _settings.region : null,
                              onRegionSelected: !_choosingRegion
                                  ? null
                                  : (region) {
                                      setState(() {
                                        _settings =
                                            _settings.copyWith(region: region);
                                        _choosingRegion = false;
                                      });
                                    },
                            )))),
          const SizedBox(height: 8),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            IconButton(
                key: const ValueKey('print-preview-previous'),
                icon: const Icon(Icons.chevron_left),
                tooltip: l10n.printPreviewPreviousPage,
                onPressed: !_choosingRegion && _previewSlot > 0
                    ? () => setState(() => _previewSlot--)
                    : null),
            Flexible(
                child: Text(_choosingRegion
                    ? l10n.printPreviewPageOf(_currentPage + 1, _pageCount)
                    : _settings.scaling == PrintScaling.multiple
                        ? l10n.printOptionsSheetOf(
                            count == 0 ? 0 : _previewSlot + 1, count)
                        : l10n.printPreviewPageOf(
                            sourceIndex + 1, _pageCount))),
            IconButton(
                key: const ValueKey('print-preview-next'),
                icon: const Icon(Icons.chevron_right),
                tooltip: l10n.printPreviewNextPage,
                onPressed: !_choosingRegion && _previewSlot < count - 1
                    ? () => setState(() => _previewSlot++)
                    : null),
          ]),
          Text(
              l10n.printOptionsSourceSize(
                  _format(source.width), _format(source.height)),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall),
          if (size != null && !_choosingRegion)
            Text(
                l10n.printOptionsSheetSize(
                    _format(size.width), _format(size.height)),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall),
          if (_marginMode && !_choosingRegion)
            Text(l10n.printOptionsMarginGuide,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall),
          if (hardware != null && !hardware.supported)
            Text(l10n.printOptionsPaperUnsupported,
                key: const ValueKey('print-paper-unsupported'),
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: Theme.of(context).colorScheme.error))
          else if (hardware != null && hardware.hasMargins)
            Text(
                l10n.printOptionsPrinterMargins(
                    _format(hardware.left),
                    _format(hardware.top),
                    _format(hardware.right),
                    _format(hardware.bottom)),
                key: const ValueKey('print-printer-margins'),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall),
        ]);
  }
}

PdfDocument _snapshotPrintSource(PdfDocument source) {
  if (!source.cos.isEncrypted) {
    // Reopen the immutable revision bytes into an independent object graph.
    // This preserves the complete catalog without copying the byte buffer.
    return PdfDocument.open(source.cos.bytes,
        populatedRanges: source.cos.populatedRanges);
  }
  // The source is already unlocked. Importing copies/decrypts its objects
  // without asking for the password again or flattening its annotations.
  return _mergePrintSources([source]);
}

PdfDocument _mergePrintSources(List<PdfDocument> sources) {
  final builder = CosDocumentBuilder();
  final pages = builder.add(CosDictionary({
    'Type': const CosName('Pages'),
    'Count': const CosInteger(0),
    'Kids': CosArray([]),
  }));
  final catalog = builder
      .add(CosDictionary({'Type': const CosName('Catalog'), 'Pages': pages}));
  final editor = PdfEditor(PdfDocument.open(builder.build(root: catalog)));
  for (final source in sources) {
    editor.appendPagesFrom(source);
  }
  return PdfDocument.open(editor.save());
}

/// Fits the raster and its interactive crop area to exactly the same bounds.
///
/// The page is recorded on [worker] when one is live, so a heavy drawing
/// never interprets on the UI thread; replay and rasterization stay here.
/// Until a new page has rendered the previous image stays up (at its own
/// proportions) under a small progress mark, rather than blanking.
class _PagePreview extends StatefulWidget {
  const _PagePreview(
      {required this.document,
      required this.pageIndex,
      this.worker,
      this.stale = false,
      this.margin = 0,
      this.printableArea,
      this.region,
      this.onRegionSelected});
  final PdfDocument document;
  final int pageIndex;
  final PdfRenderWorker? worker;

  /// A newer sheet is being composed; show that this one is on its way out.
  final bool stale;
  final double margin;
  final PrintPrintableArea? printableArea;
  final PdfRect? region;
  final ValueChanged<PdfRect>? onRegionSelected;

  @override
  State<_PagePreview> createState() => _PagePreviewState();
}

class _PagePreviewState extends State<_PagePreview> {
  ui.Image? _image;
  // What [_image] shows. Its proportions frame the preview until the
  // current page has rendered.
  (PdfDocument, int)? _imageOf;
  Size? _imageSize;
  int _token = 0;
  (PdfDocument, int, int)? _rendered;
  bool _failed = false;
  Offset? _dragStart;
  Rect? _dragRect;

  @override
  void dispose() {
    _token++;
    _image?.dispose();
    super.dispose();
  }

  void _renderIfNeeded(double width, double ratio) {
    final bucket = (width / 32).ceil();
    final key = (widget.document, widget.pageIndex, bucket);
    if (_rendered == key) return;
    _rendered = key;
    final token = ++_token;
    final document = widget.document;
    final pageIndex = widget.pageIndex;
    final worker = widget.worker;
    final page = document.page(pageIndex);
    final size = PdfPageRenderer.pageSize(page);
    final pixelRatio = math.min(
        (bucket * 32 * ratio / math.max(1, size.width)).clamp(0.01, 4.0),
        math.min(4096 / math.max(size.width, size.height),
            math.sqrt(4000000 / math.max(1, size.width * size.height))));
    () async {
      try {
        ui.Image? image;
        if (worker != null && worker.isActive) {
          final commands =
              await worker.record(pageIndex, imagePixelRatio: pixelRatio);
          // Superseded while the worker was busy: skip the replay, and above
          // all don't fall back to the UI-thread render below.
          if (!mounted || token != _token) return;
          if (commands != null) {
            final picture = await PdfPageRenderer.pictureFromCommands(
                page, commands,
                maxImagePixelRatio: pixelRatio);
            try {
              image =
                  await PdfPageRenderer.rasterize(picture, size, pixelRatio);
            } finally {
              picture.dispose();
            }
          }
        }
        image ??=
            await PdfPageRenderer.renderImage(page, pixelRatio: pixelRatio);
        if (!mounted || token != _token) {
          image.dispose();
          return;
        }
        setState(() {
          _image?.dispose();
          _image = image;
          _imageOf = (document, pageIndex);
          _imageSize = size;
          _failed = false;
        });
      } catch (_) {
        if (!mounted || token != _token) return;
        setState(() {
          _image?.dispose();
          _image = null;
          _imageOf = null;
          _failed = true;
        });
      }
    }();
  }

  @override
  Widget build(BuildContext context) {
    final targetSize =
        PdfPageRenderer.pageSize(widget.document.page(widget.pageIndex));
    final ratio = MediaQuery.of(context).devicePixelRatio;
    final current = _imageOf == (widget.document, widget.pageIndex);
    return LayoutBuilder(builder: (context, constraints) {
      final target =
          applyBoxFit(BoxFit.contain, targetSize, constraints.biggest)
              .destination;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _renderIfNeeded(target.width, ratio);
      });
      final image = _image;
      if (image == null) {
        return Center(
            child: _failed
                ? Text(printL10n(context).printPreviewUnavailable)
                : const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2)));
      }
      final pageSize = current ? targetSize : _imageSize!;
      final fit = current
          ? target
          : applyBoxFit(BoxFit.contain, pageSize, constraints.biggest)
              .destination;
      final selecting = widget.onRegionSelected != null && current;
      final pending = !current || widget.stale;
      Offset clamp(Offset point) =>
          Offset(point.dx.clamp(0, fit.width), point.dy.clamp(0, fit.height));
      final page = SizedBox(
          width: fit.width,
          height: fit.height,
          child: MouseRegion(
            cursor: selecting ? SystemMouseCursors.precise : MouseCursor.defer,
            child: GestureDetector(
              dragStartBehavior: DragStartBehavior.down,
              behavior: HitTestBehavior.opaque,
              onPanStart: !selecting
                  ? null
                  : (details) => setState(() {
                        _dragStart = clamp(details.localPosition);
                        _dragRect = Rect.fromPoints(_dragStart!, _dragStart!);
                      }),
              onPanUpdate: !selecting
                  ? null
                  : (details) => setState(() {
                        _dragRect = Rect.fromPoints(
                            _dragStart!, clamp(details.localPosition));
                      }),
              onPanEnd: !selecting
                  ? null
                  : (_) {
                      final rect = _dragRect;
                      setState(() {
                        _dragStart = null;
                        _dragRect = null;
                      });
                      if (rect == null || rect.width < 3 || rect.height < 3) {
                        return;
                      }
                      widget.onRegionSelected!(PdfRect(
                          rect.left / fit.width * pageSize.width,
                          rect.top / fit.height * pageSize.height,
                          rect.right / fit.width * pageSize.width,
                          rect.bottom / fit.height * pageSize.height));
                    },
              onPanCancel: !selecting
                  ? null
                  : () => setState(() {
                        _dragStart = null;
                        _dragRect = null;
                      }),
              child: CustomPaint(
                  key: const ValueKey('print-preview-page'),
                  painter: _PagePreviewPainter(image, pageSize,
                      margin: widget.margin,
                      printableArea: current ? widget.printableArea : null,
                      crop: _dragRect ??
                          (widget.region == null || !current
                              ? null
                              : Rect.fromLTRB(
                                  widget.region!.left /
                                      pageSize.width *
                                      fit.width,
                                  widget.region!.bottom /
                                      pageSize.height *
                                      fit.height,
                                  widget.region!.right /
                                      pageSize.width *
                                      fit.width,
                                  widget.region!.top /
                                      pageSize.height *
                                      fit.height)))),
            ),
          ));
      return Center(
          child: Stack(clipBehavior: Clip.none, children: [
        page,
        // Delay the mark so a quick re-render never flashes it.
        if (pending)
          const Positioned(
              right: 6,
              top: 6,
              child: _DelayedProgress(key: ValueKey('print-preview-pending'))),
      ]));
    });
  }
}

/// A small spinner that only appears if the wait outlasts a beat.
class _DelayedProgress extends StatefulWidget {
  const _DelayedProgress({super.key});

  @override
  State<_DelayedProgress> createState() => _DelayedProgressState();
}

class _DelayedProgressState extends State<_DelayedProgress> {
  Timer? _timer;
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer(const Duration(milliseconds: 250), () {
      if (mounted) setState(() => _visible = true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedOpacity(
      opacity: _visible ? 1 : 0,
      duration: const Duration(milliseconds: 150),
      child: const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2)));
}

class _PagePreviewPainter extends CustomPainter {
  const _PagePreviewPainter(this.image, this.pageSize,
      {this.margin = 0, this.printableArea, this.crop});
  final ui.Image image;
  final Size pageSize;
  final double margin;
  final PrintPrintableArea? printableArea;
  final Rect? crop;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawImageRect(
        image,
        Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
        Offset.zero & size,
        Paint()..filterQuality = FilterQuality.medium);
    if (printableArea case final area? when area.hasMargins) {
      _paintUnprintable(canvas, size, area);
    }
    if (margin > 0) {
      final inset = margin / pageSize.width * size.width;
      final rect = (Offset.zero & size).deflate(inset);
      if (!rect.isEmpty) {
        canvas.drawRect(
            rect,
            Paint()
              ..color = const Color(0xCCEF4444)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1);
      }
    }
    if (crop case final rect?) {
      final shade = Path()
        ..fillType = PathFillType.evenOdd
        ..addRect(Offset.zero & size)
        ..addRect(rect);
      canvas.drawPath(shade, Paint()..color = const Color(0x66000000));
      canvas.drawRect(
          rect,
          Paint()
            ..color = const Color(0xFF2196F3)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2);
    }
  }

  /// Hatches the band around the edge the printer can't reach, the way a
  /// prepress preview does: whatever lies under it won't come out on paper.
  void _paintUnprintable(Canvas canvas, Size size, PrintPrintableArea area) {
    final sx = size.width / pageSize.width;
    final sy = size.height / pageSize.height;
    final paper = Offset.zero & size;
    final printable = Rect.fromLTRB(area.left * sx, area.top * sy,
        size.width - area.right * sx, size.height - area.bottom * sy);
    final band = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(paper)
      ..addRect(printable.isEmpty ? Rect.zero : printable);
    canvas.save();
    canvas.clipPath(band);
    canvas.drawRect(paper, Paint()..color = const Color(0x33808080));
    final hatch = Paint()
      ..color = const Color(0x8C6B7280)
      ..strokeWidth = 1;
    const spacing = 6.0;
    for (var x = -size.height; x < size.width; x += spacing) {
      canvas.drawLine(
          Offset(x, size.height), Offset(x + size.height, 0), hatch);
    }
    canvas.restore();
    if (!printable.isEmpty) {
      final edge = Paint()
        ..color = const Color(0xFF6B7280)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1;
      _dashedRect(canvas, printable, edge);
    }
  }

  static void _dashedRect(Canvas canvas, Rect rect, Paint paint) {
    const dash = 4.0, gap = 3.0;
    void line(Offset a, Offset b) {
      final length = (b - a).distance;
      if (length == 0) return;
      final step = (b - a) / length;
      for (var t = 0.0; t < length; t += dash + gap) {
        canvas.drawLine(
            a + step * t, a + step * math.min(t + dash, length), paint);
      }
    }

    line(rect.topLeft, rect.topRight);
    line(rect.topRight, rect.bottomRight);
    line(rect.bottomRight, rect.bottomLeft);
    line(rect.bottomLeft, rect.topLeft);
  }

  @override
  bool shouldRepaint(_PagePreviewPainter old) =>
      !identical(old.image, image) ||
      old.pageSize != pageSize ||
      old.margin != margin ||
      old.printableArea != printableArea ||
      old.crop != crop;
}

/// Names a print preset. Returns the trimmed name and whether to remember the
/// printer with it, or null when cancelled.
class _SavePresetDialog extends StatefulWidget {
  const _SavePresetDialog({
    required this.initialName,
    required this.existing,
    required this.printer,
    required this.includePrinter,
  });

  final String initialName;
  final List<String> existing;

  /// The printer that would be saved with the preset; null hides the choice.
  final String? printer;
  final bool includePrinter;

  @override
  State<_SavePresetDialog> createState() => _SavePresetDialogState();
}

class _SavePresetDialogState extends State<_SavePresetDialog> {
  late final _name = TextEditingController(text: widget.initialName)
    ..selection =
        TextSelection(baseOffset: 0, extentOffset: widget.initialName.length);
  late bool _includePrinter = widget.includePrinter;

  String get _trimmed => _name.text.trim();

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _save() {
    if (_trimmed.isEmpty) return;
    Navigator.of(context)
        .pop((_trimmed, widget.printer != null && _includePrinter));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = printL10n(context);
    final replaces = widget.existing.contains(_trimmed);
    return AlertDialog(
      key: const ValueKey('print-preset-dialog'),
      title: Text(l10n.printPresetSaveTitle),
      content: SizedBox(
        width: 360,
        child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                key: const ValueKey('print-preset-name'),
                controller: _name,
                autofocus: true,
                maxLength: 60,
                contextMenuBuilder: pdfTextContextMenu,
                decoration: InputDecoration(
                    labelText: l10n.printPresetName,
                    border: const OutlineInputBorder(),
                    helperText: replaces ? l10n.printPresetReplaces : null),
                onChanged: (_) => setState(() {}),
              ),
              if (widget.printer case final printer?)
                CheckboxListTile(
                  key: const ValueKey('print-preset-include-printer'),
                  value: _includePrinter,
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: Text(l10n.printPresetIncludePrinter(printer)),
                  onChanged: (value) =>
                      setState(() => _includePrinter = value ?? false),
                ),
            ]),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.cancel)),
        PdfDialogSubmit.action(
            onSubmit: _trimmed.isEmpty ? null : _save,
            child: FilledButton(
                key: const ValueKey('print-preset-confirm'),
                onPressed: _trimmed.isEmpty ? null : _save,
                child: Text(l10n.printPresetSaveAction))),
      ],
    );
  }
}
