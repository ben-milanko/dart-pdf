import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'editing_color_picker.dart';
import 'editing_controller.dart';
import 'editing_preferences.dart';

/// Shows the document color-processing dialog and returns the number of
/// page-content color operators rewritten, or null when cancelled.
Future<int?> showPdfColorProcessingDialog(
  BuildContext context, {
  required PdfEditingController controller,
  required PdfEditingPreferences preferences,
}) {
  return showDialog<int>(
    context: context,
    builder: (context) => _ColorProcessingDialog(
      controller: controller,
      preferences: preferences,
    ),
  );
}

class _ColorProcessingDialog extends StatefulWidget {
  const _ColorProcessingDialog({
    required this.controller,
    required this.preferences,
  });

  final PdfEditingController controller;
  final PdfEditingPreferences preferences;

  @override
  State<_ColorProcessingDialog> createState() => _ColorProcessingDialogState();
}

class _ColorProcessingDialogState extends State<_ColorProcessingDialog> {
  Color _find = const Color(0xFF000000);
  final Set<int> _selectedDocumentColorRgbs = {};
  late Color _replace;
  late bool _selectedPages;
  List<Color> _documentColors = const [];
  var _documentColorScan = 0;
  var _documentColorProgress = 0;
  var _documentColorTotal = 0;
  var _documentColorsLoading = false;
  var _tolerance = 0;
  var _fill = true;
  var _stroke = true;
  var _replaceTransparent = false;
  var _applying = false;

  @override
  void initState() {
    super.initState();
    _replace = widget.controller.color;
    _selectedPages = widget.controller.selectedPageCount > 0;
    _refreshDocumentColors(preferFirst: true);
  }

  @override
  void dispose() {
    _documentColorScan++;
    super.dispose();
  }

  Future<void> _pickFind() => _pickColor(_find, (value) {
        _find = value;
        _selectedDocumentColorRgbs.clear();
      });
  Future<void> _pickReplace() =>
      _pickColor(_replace, (value) => _replace = value);

  Future<void> _pickColor(Color initial, ValueChanged<Color> setColor) async {
    // The dialog already lists the document's page-content colours, so the
    // picker only adds the "Recent" grid here (no document grid).
    final color = await showPdfColorPicker(
      context,
      initial: initial,
      initialFormat: widget.preferences.colorPickerFormat,
      onFormatChanged: (format) =>
          widget.preferences.colorPickerFormat = format,
      recentColors: widget.preferences.recentColors,
    );
    if (color == null || !mounted) return;
    widget.preferences.noteRecentColor(color);
    setState(() => setColor(color));
  }

  Iterable<int>? get _targetPages =>
      _selectedPages ? widget.controller.selectedPages : null;

  List<int> get _targetPageList {
    final pageCount = widget.controller.document.pageCount;
    return (_targetPages ?? Iterable<int>.generate(pageCount))
        .where((index) => index >= 0 && index < pageCount)
        .toSet()
        .toList()
      ..sort();
  }

  void _refreshDocumentColors({bool preferFirst = false}) {
    final generation = ++_documentColorScan;
    final pages = _targetPageList;
    final fill = _fill;
    final stroke = _stroke;
    _documentColors = const [];
    _documentColorProgress = 0;
    _documentColorTotal = pages.length;
    _documentColorsLoading = pages.isNotEmpty && (fill || stroke);
    if (!_documentColorsLoading) return;
    SchedulerBinding.instance.addPostFrameCallback(
      (_) => unawaited(_scanDocumentColors(
        generation,
        pages,
        fill: fill,
        stroke: stroke,
        preferFirst: preferFirst,
      )),
    );
    SchedulerBinding.instance.ensureVisualUpdate();
  }

  Future<void> _scanDocumentColors(
    int generation,
    List<int> pages, {
    required bool fill,
    required bool stroke,
    required bool preferFirst,
  }) async {
    if (!mounted || generation != _documentColorScan) return;
    final colors = await widget.controller.documentContentColorsAsync(
      pages: pages,
      fill: fill,
      stroke: stroke,
      isCancelled: () => !mounted || generation != _documentColorScan,
      onProgress: (completed, total) {
        if (!mounted || generation != _documentColorScan) return;
        setState(() {
          _documentColorProgress = completed;
          _documentColorTotal = total;
        });
      },
      yieldAfterPage: () => SchedulerBinding.instance.endOfFrame,
    );
    if (!mounted || generation != _documentColorScan) return;
    setState(() {
      _documentColors = colors;
      _documentColorsLoading = false;
      final available = {for (final color in colors) _rgb(color)};
      _selectedDocumentColorRgbs.removeWhere((rgb) => !available.contains(rgb));
      if (preferFirst && colors.isNotEmpty) {
        _find = colors.first;
        _selectedDocumentColorRgbs
          ..clear()
          ..add(_rgb(colors.first));
      } else if (_selectedDocumentColorRgbs.isNotEmpty) {
        final selected = _selectedDocumentColorRgbs.first;
        _find = colors.firstWhere((color) => _rgb(color) == selected);
      }
    });
  }

  void _cancelDocumentColorScan() {
    _documentColorScan++;
    _documentColorsLoading = false;
    _documentColorProgress = 0;
    _documentColorTotal = 0;
    _documentColors = const [];
  }

  void _restartDocumentColorScan({bool preferFirst = false}) {
    if (!_fill && !_stroke) {
      _cancelDocumentColorScan();
    } else {
      _refreshDocumentColors(preferFirst: preferFirst);
    }
  }

  void _setSelectedPages(bool value) {
    if (value && widget.controller.selectedPageCount == 0) return;
    setState(() {
      _selectedPages = value;
      _restartDocumentColorScan();
    });
  }

  void _setFill(bool value) {
    setState(() {
      _fill = value;
      _restartDocumentColorScan();
    });
  }

  void _setStroke(bool value) {
    setState(() {
      _stroke = value;
      _restartDocumentColorScan();
    });
  }

  static int _rgb(Color color) => color.toARGB32() & 0xFFFFFF;

  List<Color> get _findColors {
    if (_selectedDocumentColorRgbs.isEmpty) return [_find];
    return [
      for (final rgb in _selectedDocumentColorRgbs) Color(0xFF000000 | rgb),
    ];
  }

  String? get _findValueText => _selectedDocumentColorRgbs.length <= 1
      ? null
      : '${_selectedDocumentColorRgbs.length} colors selected';

  void _toggleDocumentColor(Color color) {
    final rgb = _rgb(color);
    setState(() {
      if (!_selectedDocumentColorRgbs.remove(rgb)) {
        _selectedDocumentColorRgbs.add(rgb);
        _find = color;
      } else if (_selectedDocumentColorRgbs.isNotEmpty) {
        final selected = _selectedDocumentColorRgbs.first;
        _find = _documentColors.firstWhere(
          (candidate) => _rgb(candidate) == selected,
          orElse: () => Color(0xFF000000 | selected),
        );
      }
    });
  }

  Future<void> _apply() async {
    if (_applying) return;
    setState(() => _applying = true);
    await SchedulerBinding.instance.endOfFrame;
    final count = await widget.controller.replaceDocumentColorsAsync(
      pages: _targetPages,
      findColors: _findColors,
      replace: _replaceTransparent ? null : _replace,
      tolerance: _tolerance,
      fill: _fill,
      stroke: _stroke,
      transparent: _replaceTransparent,
    );
    if (!mounted) return;
    Navigator.of(context).pop(count);
  }

  @override
  Widget build(BuildContext context) {
    final selectedCount = widget.controller.selectedPageCount;
    final canApply =
        (_fill || _stroke) && !_documentColorsLoading && !_applying;
    return PopScope(
      canPop: !_applying,
      child: AlertDialog(
        title: const Text('Color processing'),
        content: SizedBox(
          width: 360,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _ColorRow(
                  key: const ValueKey('pdf-color-process-find'),
                  label: 'Find',
                  color: _find,
                  valueText: _findValueText,
                  pickerKey: const ValueKey('pdf-color-process-find-picker'),
                  onTap: _pickFind,
                  enabled: !_applying,
                ),
                const SizedBox(height: 10),
                _DocumentColors(
                  colors: _documentColors,
                  selectedRgbs: _selectedDocumentColorRgbs,
                  loading: _documentColorsLoading,
                  progress: _documentColorProgress,
                  total: _documentColorTotal,
                  onSelected: _applying ? (_) {} : _toggleDocumentColor,
                ),
                const SizedBox(height: 8),
                _ColorRow(
                  key: const ValueKey('pdf-color-process-replace'),
                  label: 'Replace',
                  color: _replace,
                  transparent: _replaceTransparent,
                  enabled: !_replaceTransparent && !_applying,
                  pickerKey: const ValueKey('pdf-color-process-replace-picker'),
                  onTap: _pickReplace,
                ),
                CheckboxListTile(
                  key: const ValueKey('pdf-color-process-transparent'),
                  value: _replaceTransparent,
                  onChanged: _applying
                      ? null
                      : (value) =>
                          setState(() => _replaceTransparent = value ?? false),
                  title: const Text('Replace with transparent'),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    const Expanded(child: Text('Tolerance')),
                    Text('$_tolerance'),
                  ],
                ),
                Slider(
                  key: const ValueKey('pdf-color-process-tolerance'),
                  min: 0,
                  max: 255,
                  divisions: 255,
                  value: _tolerance.toDouble(),
                  label: '$_tolerance',
                  onChanged: _applying
                      ? null
                      : (value) => setState(() => _tolerance = value.round()),
                ),
                const SizedBox(height: 4),
                RadioGroup<bool>(
                  groupValue: _selectedPages,
                  onChanged: (value) {
                    if (_applying || value == null) return;
                    _setSelectedPages(value);
                  },
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      RadioListTile<bool>(
                        key: const ValueKey('pdf-color-process-selected-pages'),
                        value: true,
                        enabled: selectedCount > 0 && !_applying,
                        title: Text('Selected pages ($selectedCount)'),
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                      RadioListTile<bool>(
                        key: const ValueKey('pdf-color-process-whole-document'),
                        value: false,
                        enabled: !_applying,
                        title: const Text('Whole document'),
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                CheckboxListTile(
                  key: const ValueKey('pdf-color-process-fill'),
                  value: _fill,
                  onChanged:
                      _applying ? null : (value) => _setFill(value ?? false),
                  title: const Text('Fill colors'),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                ),
                CheckboxListTile(
                  key: const ValueKey('pdf-color-process-stroke'),
                  value: _stroke,
                  onChanged:
                      _applying ? null : (value) => _setStroke(value ?? false),
                  title: const Text('Stroke colors'),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                ),
                if (_applying) ...[
                  const SizedBox(height: 12),
                  const LinearProgressIndicator(
                    key: ValueKey('pdf-color-process-apply-progress'),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Applying color changes…',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _applying ? null : () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const ValueKey('pdf-color-process-apply'),
            onPressed: canApply ? () => unawaited(_apply()) : null,
            child: const Text('Apply'),
          ),
        ],
      ),
    );
  }
}

class _ColorRow extends StatelessWidget {
  const _ColorRow({
    super.key,
    required this.label,
    required this.color,
    required this.onTap,
    this.valueText,
    this.pickerKey,
    this.transparent = false,
    this.enabled = true,
  });

  final String label;
  final Color color;
  final String? valueText;
  final VoidCallback onTap;
  final Key? pickerKey;
  final bool transparent;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final rgb = color.toARGB32() & 0xFFFFFF;
    final hex = '#${rgb.toRadixString(16).toUpperCase().padLeft(6, '0')}';
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: enabled ? onTap : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            SizedBox(width: 68, child: Text(label)),
            _SwatchBox(color: color, transparent: transparent),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                valueText ?? (transparent ? 'Transparent' : hex),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            IconButton(
              key: pickerKey,
              onPressed: enabled ? onTap : null,
              tooltip: 'Pick color',
              icon: const Icon(Icons.colorize),
            ),
          ],
        ),
      ),
    );
  }
}

class _DocumentColors extends StatelessWidget {
  const _DocumentColors({
    required this.colors,
    required this.selectedRgbs,
    required this.loading,
    required this.progress,
    required this.total,
    required this.onSelected,
  });

  final List<Color> colors;
  final Set<int> selectedRgbs;
  final bool loading;
  final int progress;
  final int total;
  final ValueChanged<Color> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (colors.isEmpty && !loading) {
      return Text(
        'No page-content colors found',
        style: theme.textTheme.bodySmall,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Document colors', style: theme.textTheme.labelLarge),
            if (loading) ...[
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  total <= 0 ? 'Scanning…' : 'Scanning $progress / $total',
                  key: const ValueKey('pdf-color-process-scan-progress'),
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ],
          ],
        ),
        if (loading) ...[
          const SizedBox(height: 8),
          LinearProgressIndicator(
            key: const ValueKey('pdf-color-process-scan-bar'),
            value: total <= 0 ? null : progress / total,
          ),
        ],
        const SizedBox(height: 8),
        if (colors.isEmpty)
          Text('No colors found yet', style: theme.textTheme.bodySmall)
        else
          Wrap(
            key: const ValueKey('pdf-color-process-document-colors'),
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final color in colors)
                _ColorOption(
                  color: color,
                  selected: selectedRgbs.contains(
                    color.toARGB32() & 0xFFFFFF,
                  ),
                  onTap: () => onSelected(color),
                ),
            ],
          ),
      ],
    );
  }
}

class _ColorOption extends StatelessWidget {
  const _ColorOption({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final rgb = color.toARGB32() & 0xFFFFFF;
    final hex = '#${rgb.toRadixString(16).toUpperCase().padLeft(6, '0')}';
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: hex,
      child: InkResponse(
        key: ValueKey('pdf-color-process-color-$rgb'),
        onTap: onTap,
        radius: 20,
        child: Container(
          width: 34,
          height: 34,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            border: Border.all(
              color: selected ? scheme.primary : scheme.outlineVariant,
              width: selected ? 2 : 1,
            ),
            borderRadius: BorderRadius.circular(6),
          ),
          child: _SwatchBox(color: color),
        ),
      ),
    );
  }
}

class _SwatchBox extends StatelessWidget {
  const _SwatchBox({
    required this.color,
    this.transparent = false,
  });

  final Color color;
  final bool transparent;

  @override
  Widget build(BuildContext context) {
    final outline = Theme.of(context).colorScheme.outline;
    return CustomPaint(
      size: const Size.square(28),
      painter: _SwatchPainter(
        color: color,
        transparent: transparent,
        outline: outline,
      ),
    );
  }
}

class _SwatchPainter extends CustomPainter {
  const _SwatchPainter({
    required this.color,
    required this.transparent,
    required this.outline,
  });

  final Color color;
  final bool transparent;
  final Color outline;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(4));
    canvas.save();
    canvas.clipRRect(rrect);
    if (transparent) {
      final light = Paint()..color = const Color(0xFFFFFFFF);
      final dark = Paint()..color = const Color(0xFFE0E0E0);
      const cell = 7.0;
      for (var y = 0.0; y < size.height; y += cell) {
        for (var x = 0.0; x < size.width; x += cell) {
          final even = ((x / cell).floor() + (y / cell).floor()).isEven;
          canvas.drawRect(Rect.fromLTWH(x, y, cell, cell), even ? light : dark);
        }
      }
    } else {
      canvas.drawRect(rect,
          Paint()..color = Color(0xFF000000 | (color.toARGB32() & 0xFFFFFF)));
    }
    canvas.restore();
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = outline,
    );
  }

  @override
  bool shouldRepaint(covariant _SwatchPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.transparent != transparent ||
      oldDelegate.outline != outline;
}
