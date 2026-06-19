import 'package:flutter/material.dart';
import 'package:pdf_document/pdf_document.dart';

import '../scrollbar.dart';
import 'editing_color_picker.dart';
import 'editing_controller.dart';
import 'editing_font_controls.dart';
import 'editing_fonts.dart';
import 'editing_panel.dart';
import 'editing_preferences.dart';
import 'text_prompt.dart';
import 'line_style.dart';

/// A panel showing — and editing — the selected annotation's properties.
///
/// With one annotation selected it shows its type and page plus whatever
/// of these apply: color, fill, stroke width, opacity (restyled in place
/// via [PdfEditingController.restyleSelected]), font and size for text
/// boxes, the contents text, the author, and the position and size in
/// page points. With several selected, the shared style controls act on
/// the whole selection at once; with none it invites a selection.
///
/// The inner edge is draggable ([resizable]); the chosen width persists
/// via [PdfEditingPreferences.propertiesPanelWidth].
///
/// Place it beside the viewer, typically in a [Row] next to (or instead
/// of) the annotation list:
///
/// ```dart
/// Row(children: [
///   Expanded(child: PdfViewer(...)),
///   PdfAnnotationPropertiesPanel(controller: editing),
/// ])
/// ```
class PdfAnnotationPropertiesPanel extends StatefulWidget {
  const PdfAnnotationPropertiesPanel({
    super.key,
    required this.controller,
    this.width = 260,
    this.side = PdfSidebarSide.right,
    this.resizable = true,
    this.minWidth = 200,
    this.maxWidth = 420,
    this.showAuthor = true,
    this.bottomSheet = false,
    this.fontPicker,
  });

  final PdfEditingController controller;

  /// How the font row's menu loads a custom `.ttf`/`.otf` font; null hides
  /// the "Load font…" entry (bundled and standard fonts still show).
  final PdfFontPicker? fontPicker;

  /// The default width — a user-dragged width, persisted in
  /// [PdfEditingPreferences.propertiesPanelWidth], wins over it.
  final double width;

  /// Which side of the viewer the panel sits on; the resize grip rides
  /// the opposite (inner) edge.
  final PdfSidebarSide side;

  /// Whether the inner edge can be dragged to resize the panel.
  final bool resizable;

  /// Clamps for the dragged width.
  final double minWidth;
  final double maxWidth;

  /// Whether the "Author" row is shown. With it false the selected
  /// annotation's author can't be edited here — for hosts that set the
  /// author programmatically and lock it.
  final bool showAuthor;

  /// Lays the panel out to fill its parent (full width, no side resize
  /// grip) for hosting inside a bottom sheet on a small screen, rather
  /// than as a fixed-width docked column.
  final bool bottomSheet;

  @override
  State<PdfAnnotationPropertiesPanel> createState() =>
      _PdfAnnotationPropertiesPanelState();
}

class _PdfAnnotationPropertiesPanelState
    extends State<PdfAnnotationPropertiesPanel> {
  final ScrollController _scroll = ScrollController();

  final TextEditingController _contents = TextEditingController();
  final TextEditingController _author = TextEditingController();
  final TextEditingController _x = TextEditingController();
  final TextEditingController _y = TextEditingController();
  final TextEditingController _w = TextEditingController();
  final TextEditingController _h = TextEditingController();

  /// What the text fields were last synced from: the document revision
  /// and the primary selection slot. While it's unchanged the user owns
  /// the field text; any revision or selection change re-syncs.
  (PdfDocument, (int, int)?)? _syncedFor;

  /// Slider values while a drag is in flight — each restyle commits one
  /// revision, so it lands on release, and the thumb shows the dragged
  /// value meanwhile.
  double? _draggingStroke;
  double? _draggingOpacity;
  double? _draggingFontSize;

  /// The panel width while a resize drag is in flight.
  double? _dragWidth;

  PdfEditingController get _controller => widget.controller;

  PdfEditingPreferences get _preferences => _controller.preferences;

  double get _width =>
      (_dragWidth ?? _preferences.propertiesPanelWidth ?? widget.width)
          .clamp(widget.minWidth, widget.maxWidth);

  @override
  void initState() {
    super.initState();
    _preferences.addListener(_onPreferences);
  }

  @override
  void didUpdateWidget(PdfAnnotationPropertiesPanel old) {
    super.didUpdateWidget(old);
    if (!identical(old.controller.preferences, _preferences)) {
      old.controller.preferences.removeListener(_onPreferences);
      _preferences.addListener(_onPreferences);
    }
  }

  @override
  void dispose() {
    _preferences.removeListener(_onPreferences);
    _scroll.dispose();
    _contents.dispose();
    _author.dispose();
    _x.dispose();
    _y.dispose();
    _w.dispose();
    _h.dispose();
    super.dispose();
  }

  void _onPreferences() {
    if (mounted) setState(() {});
  }

  void _onResizeDelta(double delta) => setState(() {
        _dragWidth = (_width + delta).clamp(widget.minWidth, widget.maxWidth);
      });

  void _onResizeEnd() {
    if (_dragWidth == null) return;
    _preferences.propertiesPanelWidth = _dragWidth;
    setState(() => _dragWidth = null);
  }

  static String _label(String subtype) => switch (subtype) {
        'StrikeOut' => 'Strike-out',
        'FreeText' => 'Text box',
        'Text' => 'Note',
        'Widget' => 'Form field',
        _ => subtype,
      };

  static IconData _icon(String subtype) => switch (subtype) {
        'Highlight' => Icons.border_color,
        'Underline' => Icons.format_underlined,
        'StrikeOut' => Icons.format_strikethrough,
        'Squiggly' => Icons.gesture,
        'Ink' => Icons.draw,
        'Square' => Icons.rectangle_outlined,
        'Circle' => Icons.circle_outlined,
        'FreeText' => Icons.text_fields,
        'Text' => Icons.sticky_note_2_outlined,
        'Stamp' => Icons.approval,
        _ => Icons.bookmark_border,
      };

  /// Page points, shown without a trailing .0.
  static String _fmt(double value) {
    final fixed = value.toStringAsFixed(1);
    return fixed.endsWith('.0') ? fixed.substring(0, fixed.length - 2) : fixed;
  }

  void _syncFields(PdfAnnotation? annotation) {
    final key = (_controller.document, _controller.selectedAnnotationSlot);
    if (_syncedFor == key) return;
    _syncedFor = key;
    _contents.text = annotation?.contents ?? '';
    _author.text = annotation?.author ?? '';
    final rect = annotation?.rect;
    _x.text = rect == null ? '' : _fmt(rect.left);
    _y.text = rect == null ? '' : _fmt(rect.bottom);
    _w.text = rect == null ? '' : _fmt(rect.width);
    _h.text = rect == null ? '' : _fmt(rect.height);
  }

  void _commitContents() => _controller.setSelectedContents(_contents.text);

  void _commitAuthor() => _controller.setSelectedAuthor(_author.text);

  void _commitGeometry() {
    final annotation = _controller.selectedAnnotation;
    if (annotation == null) return;
    final rect = annotation.rect;
    final x = double.tryParse(_x.text) ?? rect.left;
    final y = double.tryParse(_y.text) ?? rect.bottom;
    final w = double.tryParse(_w.text) ?? rect.width;
    final h = double.tryParse(_h.text) ?? rect.height;
    if ((w != rect.width || h != rect.height) &&
        _controller.canResizeSelected &&
        w >= 1 &&
        h >= 1) {
      // anchored at the bottom-left corner, like the X/Y fields say
      _controller.resizeSelected(PdfRect(x, y, x + w, y + h));
    } else if (x != rect.left || y != rect.bottom) {
      _controller.moveSelected(x - rect.left, y - rect.bottom);
    } else {
      // unparsable input — put the real values back
      _syncedFor = null;
      setState(() {});
    }
  }

  Future<void> _pickColor() async {
    final initial =
        _controller.selectedAnnotationStyle?.color ?? _controller.color;
    final picked = await showPdfColorPicker(context,
        initial: initial,
        initialFormat: _preferences.colorPickerFormat,
        onFormatChanged: (format) => _preferences.colorPickerFormat = format);
    if (picked != null) _controller.restyleSelected(color: picked);
  }

  Future<void> _pickFill(Color? current) async {
    final picked = await showPdfColorPicker(context,
        initial: current ?? const Color(0xFFFFF59D),
        initialFormat: _preferences.colorPickerFormat,
        onFormatChanged: (format) => _preferences.colorPickerFormat = format);
    if (picked != null) _controller.restyleSelected(fill: (picked,));
  }

  static int? _rgb(Color? color) =>
      color == null ? null : color.toARGB32() & 0xFFFFFF;

  Future<void> _pickTextBorder(Color? current) async {
    final picked = await showPdfColorPicker(context,
        initial: current ?? const Color(0xFF000000),
        initialFormat: _preferences.colorPickerFormat,
        onFormatChanged: (format) => _preferences.colorPickerFormat = format);
    if (picked != null) {
      _controller.restyleSelectedText(
          border: (_rgb(picked),),
          borderWidth: _controller.strokeWidth);
    }
  }

  Widget _section(String title) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text(title, style: Theme.of(context).textTheme.labelLarge),
      );

  Widget _swatchRow(String label, Color? color,
      {required Key key,
      required VoidCallback onTap,
      VoidCallback? onClear,
      String clearTooltip = 'No fill'}) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(children: [
        Expanded(child: Text(label)),
        if (onClear != null)
          IconButton(
            icon: const Icon(Icons.format_color_reset_outlined, size: 18),
            tooltip: clearTooltip,
            visualDensity: VisualDensity.compact,
            onPressed: color == null ? null : onClear,
          ),
        InkWell(
          key: key,
          onTap: onTap,
          child: Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: color ?? Colors.transparent,
              border: Border.all(color: scheme.outline),
              borderRadius: BorderRadius.circular(4),
            ),
            child: color == null
                ? Icon(Icons.block, size: 16, color: scheme.outline)
                : null,
          ),
        ),
      ]),
    );
  }

  Widget _sliderRow(String label, double value,
      {required Key key,
      required double min,
      required double max,
      required ValueChanged<double> onChanged,
      required ValueChanged<double> onChangeEnd,
      String Function(double)? display}) {
    return Padding(
      padding: const EdgeInsets.only(left: 16, right: 8),
      child: Row(children: [
        Text(label),
        Expanded(
          child: Slider(
            key: key,
            value: value.clamp(min, max),
            min: min,
            max: max,
            onChanged: onChanged,
            onChangeEnd: onChangeEnd,
          ),
        ),
        SizedBox(
          width: 36,
          child: Text((display ?? _fmt)(value),
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.right),
        ),
        const SizedBox(width: 8),
      ]),
    );
  }

  Widget _textRow(String label, TextEditingController controller,
      {required Key key,
      required VoidCallback onCommit,
      bool enabled = true,
      int maxLines = 1}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Focus(
        onFocusChange: (focused) {
          if (!focused && enabled) onCommit();
        },
        child: TextField(
          key: key,
          controller: controller,
          enabled: enabled,
          maxLines: maxLines,
          minLines: 1,
          decoration: InputDecoration(
            labelText: label,
            isDense: true,
            border: const OutlineInputBorder(),
          ),
          onSubmitted: (_) => onCommit(),
        ),
      ),
    );
  }

  Widget _geometryField(String label, TextEditingController controller, Key key,
      {required bool enabled}) {
    return Expanded(
      child: Focus(
        onFocusChange: (focused) {
          if (!focused && enabled) _commitGeometry();
        },
        child: TextField(
          key: key,
          controller: controller,
          enabled: enabled,
          keyboardType: const TextInputType.numberWithOptions(
              decimal: true, signed: true),
          decoration: InputDecoration(
            labelText: label,
            isDense: true,
            border: const OutlineInputBorder(),
          ),
          onSubmitted: (_) => _commitGeometry(),
        ),
      ),
    );
  }

  /// Whether every selected annotation has [subtype] in [subtypes].
  bool _allSelected(Set<String> subtypes) {
    final slots = _controller.selectedAnnotationSlots;
    if (slots.isEmpty) return false;
    for (final (page, index) in slots) {
      final annotation = _controller.annotationAt(page, index);
      if (annotation == null || !subtypes.contains(annotation.subtype)) {
        return false;
      }
    }
    return true;
  }

  static const _fillable = {'Square', 'Circle', 'Polygon', 'FreeText'};
  static const _stroked = {'Square', 'Circle', 'Polygon', 'Ink'};
  static const _lineStyled = {
    'Square', 'Circle', 'Line', 'PolyLine', 'Polygon', //
  };
  static const _translucent = {
    'Square', 'Circle', 'Polygon', 'Ink', 'Highlight', 'Underline',
    'StrikeOut', 'Squiggly', 'Stamp', //
  };

  List<Widget> _styleControls(PdfAnnotation annotation) {
    final children = <Widget>[];
    if (!_controller.canRestyleSelected) return children;
    final style = _controller.selectedAnnotationStyle;
    if (style == null) return children;
    children.add(_section('Appearance'));
    children.add(_swatchRow('Color', style.color,
        key: const ValueKey('pdf-prop-color'), onTap: _pickColor));
    if (_allSelected(_fillable)) {
      final fill = annotation.subtype == 'FreeText'
          ? annotation.freeTextStyle?.fillColor
          : annotation.interiorColor;
      final fillColor = fill == null ? null : Color(0xFF000000 | fill);
      children.add(_swatchRow('Fill', fillColor,
          key: const ValueKey('pdf-prop-fill'),
          onTap: () => _pickFill(fillColor),
          onClear: () => _controller.restyleSelected(fill: (null,))));
    }
    if (_allSelected(_stroked)) {
      children.add(_sliderRow(
        'Stroke',
        _draggingStroke ?? style.strokeWidth ?? _controller.strokeWidth,
        key: const ValueKey('pdf-prop-stroke'),
        min: 0.5,
        max: 16,
        onChanged: (v) => setState(() => _draggingStroke = v),
        onChangeEnd: (v) {
          _controller.restyleSelected(strokeWidth: v);
          setState(() => _draggingStroke = null);
        },
      ));
    }
    if (_allSelected(_lineStyled) && _controller.canSetLineStyleSelected) {
      children.add(Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Row(children: [
          const Expanded(child: Text('Line type')),
          DropdownButton<PdfLineStyle>(
            key: const ValueKey('pdf-prop-line-type'),
            value: _controller.selectedLineStyle ?? PdfLineStyle.solid,
            isDense: true,
            items: [
              for (final style in PdfLineStyle.values)
                DropdownMenuItem(
                    value: style,
                    key: ValueKey('pdf-prop-line-type-${style.name}'),
                    child: Text(style.label)),
            ],
            onChanged: (style) {
              if (style != null) _controller.restyleSelected(lineStyle: style);
            },
          ),
        ]),
      ));
    }
    if (_allSelected(_translucent)) {
      children.add(_sliderRow(
        'Opacity',
        _draggingOpacity ?? style.opacity,
        key: const ValueKey('pdf-prop-opacity'),
        min: 0.05,
        max: 1,
        display: (v) => '${(v * 100).round()}%',
        onChanged: (v) => setState(() => _draggingOpacity = v),
        onChangeEnd: (v) {
          _controller.restyleSelected(opacity: v);
          setState(() => _draggingOpacity = null);
        },
      ));
    }
    return children;
  }

  List<Widget> _textStyleControls(PdfAnnotation annotation) {
    if (!_controller.canRestyleSelectedText) return const [];
    final style = _controller.selectedTextStyle;
    if (style == null) return const [];
    final border = annotation.subtype == 'FreeText'
        ? annotation.freeTextStyle?.borderColor
        : null;
    final borderColor = border == null ? null : Color(0xFF000000 | border);
    return [
      _section('Text'),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Row(children: [
          const Expanded(child: Text('Font')),
          DropdownButton<PdfStandardFontFamily>(
            key: const ValueKey('pdf-prop-font'),
            value: style.font.family,
            isDense: true,
            items: const [
              DropdownMenuItem(
                  value: PdfStandardFontFamily.sans, child: Text('Sans')),
              DropdownMenuItem(
                  value: PdfStandardFontFamily.serif, child: Text('Serif')),
              DropdownMenuItem(
                  value: PdfStandardFontFamily.mono, child: Text('Mono')),
            ],
            onChanged: (family) {
              if (family != null) {
                _controller.restyleSelectedText(
                    font: PdfStandardFont.styled(family,
                        bold: style.font.isBold, italic: style.font.isItalic));
              }
            },
          ),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Row(children: [
          const Expanded(child: Text('Style')),
          FontStyleToggles(
            keyPrefix: 'pdf-prop-font',
            font: style.font,
            onChanged: (font) => _controller.restyleSelectedText(font: font),
          ),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Row(children: [
          const Expanded(child: Text('More fonts')),
          PdfFontMenuButton(
            controller: _controller,
            fontPicker: widget.fontPicker,
          ),
        ]),
      ),
      _sliderRow(
        'Size',
        _draggingFontSize ?? style.size,
        key: const ValueKey('pdf-prop-font-size'),
        min: 6,
        max: 72,
        onChanged: (v) => setState(() => _draggingFontSize = v),
        onChangeEnd: (v) {
          _controller.restyleSelectedText(size: v.roundToDouble());
          setState(() => _draggingFontSize = null);
        },
      ),
      if (annotation.subtype == 'FreeText')
        _swatchRow('Outline', borderColor,
            key: const ValueKey('pdf-prop-text-border'),
            onTap: () => _pickTextBorder(borderColor),
            onClear: () => _controller.restyleSelectedText(border: (null,)),
            clearTooltip: 'No outline'),
    ];
  }

  List<Widget> _buildSingle(PdfAnnotation annotation) {
    final slot = _controller.selectedAnnotationSlot!;
    return [
      ListTile(
        leading: Icon(_icon(annotation.subtype)),
        title: Text(_label(annotation.subtype)),
        subtitle: Text('Page ${slot.$1 + 1}'),
      ),
      ..._styleControls(annotation),
      ..._textStyleControls(annotation),
      _section('Content'),
      _textRow('Contents', _contents,
          key: const ValueKey('pdf-prop-contents'),
          onCommit: _commitContents,
          maxLines: 4),
      if (widget.showAuthor)
        _textRow('Author', _author,
            key: const ValueKey('pdf-prop-author'), onCommit: _commitAuthor),
      _section('Position & size (pt)'),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Row(children: [
          _geometryField('X', _x, const ValueKey('pdf-prop-x'), enabled: true),
          const SizedBox(width: 8),
          _geometryField('Y', _y, const ValueKey('pdf-prop-y'), enabled: true),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Row(children: [
          _geometryField('W', _w, const ValueKey('pdf-prop-w'),
              enabled: _controller.canResizeSelected),
          const SizedBox(width: 8),
          _geometryField('H', _h, const ValueKey('pdf-prop-h'),
              enabled: _controller.canResizeSelected),
        ]),
      ),
      const SizedBox(height: 16),
    ];
  }

  List<Widget> _buildMulti(PdfAnnotation primary, int count) {
    return [
      ListTile(
        leading: const Icon(Icons.select_all),
        title: Text('$count annotations'),
        subtitle: const Text('Style edits apply to all'),
      ),
      ..._styleControls(primary),
      if (widget.showAuthor) ...[
        _section('Content'),
        _textRow('Author', _author,
            key: const ValueKey('pdf-prop-author'), onCommit: _commitAuthor),
      ],
      const SizedBox(height: 16),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final showGrip = widget.resizable && !widget.bottomSheet;
    final onLeftEdge = !widget.bottomSheet && widget.side == PdfSidebarSide.left;
    final content = Material(
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            child: ListenableBuilder(
              listenable: _controller,
              builder: (context, _) {
                final annotation = _controller.selectedAnnotation;
                _syncFields(annotation);
                if (annotation == null) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('Select an annotation to see its properties',
                          textAlign: TextAlign.center),
                    ),
                  );
                }
                final count = _controller.selectedAnnotationSlots.length;
                final children = count == 1
                    ? _buildSingle(annotation)
                    : _buildMulti(annotation, count);
                final barClearance = PdfScrollbar.hitExtent +
                    (showGrip && onLeftEdge ? PdfSidebarResizeGrip.width : 0);
                return Stack(children: [
                  ScrollConfiguration(
                    behavior: ScrollConfiguration.of(context)
                        .copyWith(scrollbars: false),
                    child: ListView(
                        controller: _scroll,
                        padding: EdgeInsets.only(right: barClearance),
                        children: children),
                  ),
                  Positioned(
                    top: 0,
                    bottom: 0,
                    right:
                        showGrip && onLeftEdge ? PdfSidebarResizeGrip.width : 0,
                    child: PdfScrollbar(
                      scroll: _scroll,
                      thumbKey:
                          const ValueKey('pdf-properties-scrollbar-thumb'),
                    ),
                  ),
                ]);
              },
            ),
          );
    if (widget.bottomSheet) return content;
    return SizedBox(
      width: _width,
      child: Stack(children: [
        Positioned.fill(child: content),
        if (showGrip)
          Positioned(
            top: 0,
            bottom: 0,
            left: widget.side == PdfSidebarSide.right ? 0 : null,
            right: widget.side == PdfSidebarSide.left ? 0 : null,
            child: PdfSidebarResizeGrip(
              key: const ValueKey('pdf-properties-resize-grip'),
              side: widget.side,
              onWidthDelta: _onResizeDelta,
              onResizeEnd: _onResizeEnd,
            ),
          ),
      ]),
    );
  }
}
