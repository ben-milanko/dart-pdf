import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:pdf_document/pdf_document.dart';

import 'annotation_presentation.dart';
import 'editing_color_pick.dart';
import 'editing_controller.dart';
import 'editing_font_controls.dart';
import 'editing_fonts.dart';
import 'editing_form_style.dart';
import 'editing_panel.dart';
import 'editing_preferences.dart';
import 'editing_value_field.dart';
import 'text_prompt.dart';
import 'line_style.dart';
import '../l10n/pdf_l10n.dart';

/// A panel showing - and editing - the selected annotation's properties.
///
/// With one annotation selected it shows its type and page plus whatever
/// of these apply: color, fill, stroke width, opacity (restyled in place
/// via [PdfEditingController.restyleSelected]), font and size for text
/// boxes, the contents text, the author, and the position and size in
/// page points. With several selected, common values are shown normally,
/// mixed values read "Varies", and compatible edits act on the whole
/// selection at once; with none it invites a selection.
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
    this.dock = PdfPanelDock.right,
    this.resizable = true,
    this.minWidth = 200,
    this.maxWidth = 420,
    this.showAuthor = true,
    this.bottomSheet = false,
    this.onClose,
    this.fontPicker,
  });

  final PdfEditingController controller;

  /// How the font row's menu loads a custom `.ttf`/`.otf` font; null hides
  /// the "Load font…" entry (bundled and standard fonts still show).
  final PdfFontPicker? fontPicker;

  /// The default width - a user-dragged width, persisted in
  /// [PdfEditingPreferences.propertiesPanelWidth], wins over it.
  final double width;

  /// Which edge of the viewer the panel docks on; the resize grip rides
  /// the opposite (inner) edge.
  final PdfPanelDock dock;

  /// Whether the inner edge can be dragged to resize the panel.
  final bool resizable;

  /// Clamps for the dragged width.
  final double minWidth;
  final double maxWidth;

  /// Whether the "Author" row is shown. With it false the selected
  /// annotation's author can't be edited here - for hosts that set the
  /// author programmatically and lock it.
  final bool showAuthor;

  /// Lays the panel out to fill its parent (full width, no side resize
  /// grip) for hosting inside a bottom sheet on a small screen, rather
  /// than as a fixed-width docked column.
  final bool bottomSheet;

  /// Closes the docked panel - the host turns its visibility preference
  /// off. When given (and not a [bottomSheet]) a close (×) button appears
  /// in the panel's header. Null leaves the panel with no close button (a
  /// bottom sheet supplies its own).
  final VoidCallback? onClose;

  @override
  State<PdfAnnotationPropertiesPanel> createState() =>
      _PdfAnnotationPropertiesPanelState();
}

class _PdfAnnotationPropertiesPanelState
    extends State<PdfAnnotationPropertiesPanel> {
  final ScrollController _scroll = ScrollController();

  final TextEditingController _contents = TextEditingController();
  final TextEditingController _author = TextEditingController();
  final TextEditingController _fieldName = TextEditingController();
  final TextEditingController _x = TextEditingController();
  final TextEditingController _y = TextEditingController();
  final TextEditingController _w = TextEditingController();
  final TextEditingController _h = TextEditingController();

  /// What the text fields were last synced from. While the document and full
  /// selection are unchanged the user owns the field text; any revision or
  /// selection change re-syncs (including a secondary slot being toggled
  /// while the primary slot stays put).
  int? _syncedRevisionId;
  List<(int, int)> _syncedSlots = const [];
  bool _contentsVaries = false;
  bool _authorVaries = false;

  /// Slider values while a drag is in flight - each restyle commits one
  /// revision, so it lands on release, and the thumb shows the dragged
  /// value meanwhile.
  double? _draggingStroke;
  double? _draggingScale;
  double? _draggingOpacity;
  double? _draggingFontSize;
  double? _draggingLineSpacing;
  double? _draggingCharSpacing;
  double? _draggingFontWidth;

  PdfEditingController get _controller => widget.controller;

  PdfEditingPreferences get _preferences => _controller.preferences;

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
    _fieldName.dispose();
    _x.dispose();
    _y.dispose();
    _w.dispose();
    _h.dispose();
    super.dispose();
  }

  void _onPreferences() {
    if (mounted) setState(() {});
  }

  String _endingLabel(PdfLineEnding ending) => switch (ending) {
        PdfLineEnding.none => pdfL10n(context).none,
        PdfLineEnding.square => pdfL10n(context).propLineEndingSquare,
        PdfLineEnding.circle => pdfL10n(context).propLineEndingCircle,
        PdfLineEnding.diamond => pdfL10n(context).propLineEndingDiamond,
        PdfLineEnding.openArrow => pdfL10n(context).propLineEndingOpenArrow,
        PdfLineEnding.closedArrow => pdfL10n(context).propLineEndingClosedArrow,
        PdfLineEnding.butt => pdfL10n(context).propLineEndingButt,
        PdfLineEnding.rOpenArrow => pdfL10n(context).propLineEndingOpenArrowRev,
        PdfLineEnding.rClosedArrow =>
          pdfL10n(context).propLineEndingClosedArrowRev,
        PdfLineEnding.slash => pdfL10n(context).propLineEndingSlash,
      };

  Widget _lineEndingRow({
    required String label,
    required Key key,
    required PdfLineEnding? value,
    required ValueChanged<PdfLineEnding> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(children: [
        SizedBox(width: 92, child: Text(label)),
        Expanded(
          child: DropdownButton<PdfLineEnding>(
            key: key,
            value: value,
            hint: Text(pdfL10n(context).propVaries),
            isDense: true,
            isExpanded: true,
            items: [
              for (final ending in PdfLineEnding.values)
                DropdownMenuItem(
                  value: ending,
                  child: Text(_endingLabel(ending),
                      overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: (ending) {
              if (ending != null) onChanged(ending);
            },
          ),
        ),
      ]),
    );
  }

  /// Page points, shown without a trailing .0.
  static String _fmt(double value) {
    final fixed = value.toStringAsFixed(1);
    return fixed.endsWith('.0') ? fixed.substring(0, fixed.length - 2) : fixed;
  }

  void _syncFields(PdfAnnotation? annotation) {
    final slots = _controller.selectedAnnotationSlots;
    if (_syncedRevisionId == _controller.revisionId &&
        listEquals(_syncedSlots, slots)) {
      return;
    }
    _syncedRevisionId = _controller.revisionId;
    _syncedSlots = List.of(slots);
    final selected = _selectedAnnotations;
    if (selected.isEmpty) {
      _contentsVaries = false;
      _authorVaries = false;
      _contents.clear();
      _author.clear();
      _fieldName.clear();
      _x.clear();
      _y.clear();
      _w.clear();
      _h.clear();
      return;
    }
    final contents = _common<String>([
      for (final annotation in selected) annotation.contents ?? '',
    ]);
    final authors = _common<String>([
      for (final annotation in selected) annotation.author ?? '',
    ]);
    _contentsVaries = contents.varies;
    _authorVaries = authors.varies;
    _contents.text = contents.varies ? '' : contents.value;
    _author.text = authors.varies ? '' : authors.value;
    _fieldName.text = _controller.selectedWidgetFieldName ?? '';
    final rect = annotation?.rect;
    _x.text = rect == null ? '' : _fmt(rect.left);
    _y.text = rect == null ? '' : _fmt(rect.bottom);
    _w.text = rect == null ? '' : _fmt(rect.width);
    _h.text = rect == null ? '' : _fmt(rect.height);
  }

  void _commitContents() => _controller.setSelectedContents(_contents.text);

  void _commitAuthor() => _controller.setSelectedAuthor(_author.text);

  void _commitFieldName() {
    final current = _controller.selectedWidgetFieldName;
    final next = _fieldName.text.trim();
    if (current == null || next.isEmpty || next == current) return;
    if (!_controller.renameFormField(current, next)) {
      // a clash or invalid name leaves the field unchanged - restore the
      // text so the row keeps reflecting the real name
      _fieldName.text = current;
    }
  }

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
      // unparsable input - put the real values back
      _syncedRevisionId = null;
      setState(() {});
    }
  }

  List<PdfAnnotation> get _selectedAnnotations => [
        for (final (page, index) in _controller.selectedAnnotationSlots)
          if (_controller.annotationAt(page, index) case final annotation?)
            annotation,
      ];

  ({T value, bool varies}) _common<T>(Iterable<T> values) {
    final iterator = values.iterator;
    if (!iterator.moveNext()) {
      throw StateError('A common property needs at least one value');
    }
    final first = iterator.current;
    while (iterator.moveNext()) {
      if (iterator.current != first) return (value: first, varies: true);
    }
    return (value: first, varies: false);
  }

  Future<void> _pickColor() async {
    final initial =
        _controller.selectedAnnotationStyle?.color ?? _controller.color;
    final picked =
        await pickEditingColor(context, _controller, initial: initial);
    if (picked != null) _controller.restyleSelected(color: picked);
  }

  Future<void> _pickFill(Color? current) async {
    final picked = await pickEditingColor(context, _controller,
        initial: current ?? const Color(0xFFFFF59D));
    if (picked != null) _controller.restyleSelected(fill: (picked,));
  }

  static int? _rgb(Color? color) =>
      color == null ? null : color.toARGB32() & 0xFFFFFF;

  Future<void> _pickTextBorder(Color? current) async {
    final picked = await pickEditingColor(context, _controller,
        initial: current ?? const Color(0xFF000000));
    if (picked != null) {
      _controller.restyleSelectedText(
          border: (_rgb(picked),),
          borderWidth: _controller.preferences.strokeWidth);
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
      String? clearTooltip,
      bool varies = false}) {
    final scheme = Theme.of(context).colorScheme;
    final variesKey = key is ValueKey
        ? ValueKey('${key.value}-varies')
        : ValueKey('$label-varies');
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(children: [
        Expanded(child: Text(label)),
        if (varies) ...[
          Text(
            pdfL10n(context).propVaries,
            key: variesKey,
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(width: 8),
        ],
        if (onClear != null)
          IconButton(
            icon: const Icon(Icons.format_color_reset_outlined, size: 18),
            tooltip: clearTooltip ?? pdfL10n(context).propNoFill,
            visualDensity: VisualDensity.compact,
            onPressed: color == null && !varies ? null : onClear,
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
      String Function(double)? display,
      double? Function(String)? parse,
      double? fieldMin,
      double? fieldMax,
      bool varies = false}) {
    final base = key is ValueKey ? '${key.value}' : '$key';
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
        // the value also reads back as an editable number, so it can be set
        // exactly without nudging the slider (general rule: any slider's
        // value is directly typeable). A typed value may exceed the slider's
        // scale within reason (fieldMin/fieldMax).
        PdfSliderValueField(
          key: ValueKey('$base-input'),
          value: value,
          min: min,
          max: max,
          fieldMin: fieldMin,
          fieldMax: fieldMax,
          display: display ?? _fmt,
          parse: parse,
          varies: varies,
          onSubmit: onChangeEnd,
        ),
        const SizedBox(width: 8),
      ]),
    );
  }

  Widget _textRow(String label, TextEditingController controller,
      {required Key key,
      required VoidCallback onCommit,
      bool enabled = true,
      int maxLines = 1,
      bool varies = false}) {
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
            hintText: varies ? pdfL10n(context).propVaries : null,
            isDense: true,
            border: const OutlineInputBorder(),
          ),
          onSubmitted: (_) => onCommit(),
        ),
      ),
    );
  }

  Widget _readOnlyRow(String label, String value, Key key) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
        child: Row(children: [
          Expanded(child: Text(label)),
          Text(
            value,
            key: key,
            style: TextStyle(
              color: value == pdfL10n(context).propVaries
                  ? Theme.of(context).colorScheme.onSurfaceVariant
                  : null,
            ),
          ),
        ]),
      );

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

  /// Whether every selected annotation satisfies a shared semantic
  /// capability. The subtype matrix lives in pdf_document.
  bool _allSelected(bool Function(PdfAnnotationBehavior) test) {
    final slots = _controller.selectedAnnotationSlots;
    if (slots.isEmpty) return false;
    for (final (page, index) in slots) {
      final annotation = _controller.annotationAt(page, index);
      if (annotation == null || !test(annotation.behavior)) {
        return false;
      }
    }
    return true;
  }

  List<Widget> _styleControls() {
    final children = <Widget>[];
    if (!_controller.canRestyleSelected) return children;
    final annotations = _selectedAnnotations;
    if (annotations.isEmpty) return children;
    final styles = [
      for (final annotation in annotations) annotation.behavior.style
    ];
    final style = _controller.selectedAnnotationStyle;
    if (style == null) return children;
    children.add(_section(pdfL10n(context).propSectionAppearance));
    // An image stamp (a pasted picture) has no tintable colour - only its
    // opacity applies - so the swatch is hidden for it while opacity stays.
    if (_allSelected((behavior) => behavior.supportsColor)) {
      final colors = _common<int?>([for (final style in styles) style.color]);
      children.add(_swatchRow(
        pdfL10n(context).propColor,
        Color(0xFF000000 | (colors.value ?? 0)),
        key: const ValueKey('pdf-prop-color'),
        onTap: _pickColor,
        varies: colors.varies,
      ));
    }
    if (_allSelected((behavior) => behavior.supportsFill)) {
      final fills = _common<int?>([
        for (final style in styles) style.fillColor,
      ]);
      final fillColor =
          fills.value == null ? null : Color(0xFF000000 | fills.value!);
      children.add(_swatchRow(pdfL10n(context).propFill, fillColor,
          key: const ValueKey('pdf-prop-fill'),
          onTap: () => _pickFill(fillColor),
          onClear: () => _controller.restyleSelected(fill: (null,)),
          varies: fills.varies));
    }
    if (_allSelected((behavior) => behavior.supportsStrokeWidth)) {
      final widths = _common<double?>([
        for (final style in styles) style.strokeWidth,
      ]);
      children.add(_sliderRow(
        pdfL10n(context).propStroke,
        _draggingStroke ?? widths.value ?? _controller.preferences.strokeWidth,
        key: const ValueKey('pdf-prop-stroke'),
        min: 0.5,
        max: 16,
        fieldMin: 0,
        fieldMax: kPdfTypedSizeMax,
        varies: _draggingStroke == null && widths.varies,
        onChanged: (v) => setState(() => _draggingStroke = v),
        onChangeEnd: (v) {
          _controller.restyleSelected(strokeWidth: v);
          setState(() => _draggingStroke = null);
        },
      ));
    }
    if (_allSelected((behavior) => behavior.supportsLineStyle) &&
        _controller.canSetLineStyleSelected) {
      final lineStyles = _common<PdfLineStyle>([
        for (final annotation in annotations)
          PdfLineStyle.ofDashArray(annotation.borderDash),
      ]);
      children.add(Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Row(children: [
          Expanded(child: Text(pdfL10n(context).propLineType)),
          DropdownButton<PdfLineStyle>(
            key: const ValueKey('pdf-prop-line-type'),
            value: lineStyles.varies ? null : lineStyles.value,
            hint: Text(pdfL10n(context).propVaries),
            isDense: true,
            items: [
              for (final style in PdfLineStyle.values)
                DropdownMenuItem(
                    value: style,
                    key: ValueKey('pdf-prop-line-type-${style.name}'),
                    child: Text(pdfLineStyleLabel(context, style))),
            ],
            onChanged: (style) {
              if (style != null) _controller.restyleSelected(lineStyle: style);
            },
          ),
        ]),
      ));
      children.add(_sliderRow(
        pdfL10n(context).propScale,
        _draggingScale ??
            _controller.selectedLineScale ??
            _controller.preferences.lineScale,
        key: const ValueKey('pdf-prop-line-scale'),
        min: 0.5,
        max: 4,
        display: (v) => '${v.toStringAsFixed(1)}×',
        onChanged: (v) => setState(() => _draggingScale = v),
        onChangeEnd: (v) {
          _controller.preferences.lineScale = v;
          _controller.restyleSelected(scale: v);
          setState(() => _draggingScale = null);
        },
      ));
    }
    if (_controller.canSetLineEndings) {
      final starts = _common<PdfLineEnding>([
        for (final annotation in annotations) pdfLineEndings(annotation)!.$1,
      ]);
      final ends = _common<PdfLineEnding>([
        for (final annotation in annotations) pdfLineEndings(annotation)!.$2,
      ]);
      children
        ..add(_lineEndingRow(
          label: pdfL10n(context).propLineStart,
          key: const ValueKey('pdf-prop-line-start-ending'),
          value: starts.varies ? null : starts.value,
          onChanged: (ending) =>
              _controller.setSelectedLineEndings(start: ending),
        ))
        ..add(_lineEndingRow(
          label: pdfL10n(context).propLineEnd,
          key: const ValueKey('pdf-prop-line-end-ending'),
          value: ends.varies ? null : ends.value,
          onChanged: (ending) =>
              _controller.setSelectedLineEndings(end: ending),
        ));
    }
    if (_allSelected((behavior) => behavior.supportsOpacity)) {
      final opacities = _common<double>([
        for (final style in styles) style.opacity,
      ]);
      children.add(_sliderRow(
        pdfL10n(context).propOpacity,
        _draggingOpacity ?? opacities.value,
        key: const ValueKey('pdf-prop-opacity'),
        min: 0.05,
        max: 1,
        // a true ratio: typeable down to 0%, never past 100%
        fieldMin: 0,
        fieldMax: 1,
        varies: _draggingOpacity == null && opacities.varies,
        display: (v) => '${(v * 100).round()}%',
        parse: (s) {
          final n = double.tryParse(s.replaceAll('%', '').trim());
          return n == null ? null : n / 100;
        },
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
    final border = annotation.behavior.style.borderColor;
    final borderColor = border == null ? null : Color(0xFF000000 | border);
    return [
      _section(pdfL10n(context).propSectionText),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Row(children: [
          Expanded(child: Text(pdfL10n(context).propFont)),
          PdfFontMenuButton(
            buttonKey: const ValueKey('pdf-prop-font'),
            controller: _controller,
            fontPicker: widget.fontPicker,
            // the box's real face (embedded/bundled shows its own name)
            currentFont: _controller.selectedTextFont ?? style.font,
          ),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Row(children: [
          Expanded(child: Text(pdfL10n(context).propStyle)),
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
          Expanded(child: Text(pdfL10n(context).propAlign)),
          TextAlignToggles(
            keyPrefix: 'pdf-prop-text-align',
            align: _controller.selectedTextAlign ?? PdfTextAlign.left,
            onChanged: (align) => _controller.restyleSelectedText(align: align),
          ),
        ]),
      ),
      _sliderRow(
        pdfL10n(context).propSize,
        _draggingFontSize ?? style.size,
        key: const ValueKey('pdf-prop-font-size'),
        min: 6,
        max: 72,
        fieldMin: 1,
        fieldMax: kPdfTypedSizeMax,
        onChanged: (v) => setState(() => _draggingFontSize = v),
        onChangeEnd: (v) {
          _controller.restyleSelectedText(size: v.roundToDouble());
          setState(() => _draggingFontSize = null);
        },
      ),
      if (annotation.subtype == 'FreeText') ...[
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Row(children: [
            Expanded(child: Text(pdfL10n(context).propUnderline)),
            IconButton(
              key: const ValueKey('pdf-prop-text-underline'),
              icon: const Icon(Icons.format_underlined, size: 18),
              tooltip: pdfL10n(context).propUnderline,
              isSelected: _controller.selectedFreeTextStyle?.underline ?? false,
              onPressed: () => _controller.setSelectedTextBoxStyle(
                  underline:
                      !(_controller.selectedFreeTextStyle?.underline ?? false)),
            ),
          ]),
        ),
        _sliderRow(
          pdfL10n(context).propLineSpacing,
          _draggingLineSpacing ??
              _controller.selectedFreeTextStyle?.lineSpacing ??
              kPdfFreeTextDefaultLineSpacing,
          key: const ValueKey('pdf-prop-line-spacing'),
          min: 0.8,
          max: 3,
          fieldMin: 0.1,
          fieldMax: 100,
          display: (v) => '${v.toStringAsFixed(1)}×',
          onChanged: (v) => setState(() => _draggingLineSpacing = v),
          onChangeEnd: (v) {
            _controller.setSelectedTextBoxStyle(lineSpacing: v);
            setState(() => _draggingLineSpacing = null);
          },
        ),
        _sliderRow(
          pdfL10n(context).propCharSpacing,
          _draggingCharSpacing ??
              _controller.selectedFreeTextStyle?.charSpacing ??
              0,
          key: const ValueKey('pdf-prop-char-spacing'),
          min: -2,
          max: 10,
          fieldMin: -kPdfTypedSizeMax,
          fieldMax: kPdfTypedSizeMax,
          display: (v) => '${v.toStringAsFixed(1)} pt',
          onChanged: (v) => setState(() => _draggingCharSpacing = v),
          onChangeEnd: (v) {
            _controller.setSelectedTextBoxStyle(charSpacing: v);
            setState(() => _draggingCharSpacing = null);
          },
        ),
        _sliderRow(
          pdfL10n(context).propFontWidth,
          _draggingFontWidth ??
              _controller.selectedFreeTextStyle?.horizontalScale ??
              kPdfFreeTextDefaultHorizontalScale,
          key: const ValueKey('pdf-prop-font-width'),
          min: 50,
          max: 200,
          fieldMin: 1,
          fieldMax: kPdfTypedSizeMax,
          display: (v) => '${v.round()}%',
          onChanged: (v) => setState(() => _draggingFontWidth = v),
          onChangeEnd: (v) {
            _controller.setSelectedTextBoxStyle(fontWidth: v);
            setState(() => _draggingFontWidth = null);
          },
        ),
        _swatchRow(pdfL10n(context).propOutline, borderColor,
            key: const ValueKey('pdf-prop-text-border'),
            onTap: () => _pickTextBorder(borderColor),
            onClear: () => _controller.restyleSelectedText(border: (null,)),
            clearTooltip: pdfL10n(context).propNoOutline),
      ],
    ];
  }

  /// Text styling for a selected form text field (font, style, alignment,
  /// auto-size, size, multiline, colour) - regenerated through
  /// [PdfEditingController.setFormFieldStyle].
  List<Widget> _formFieldControls() {
    final name = _controller.selectedFormFieldName;
    final style = _controller.selectedFormFieldStyle;
    if (name == null || style == null) return const [];
    return [
      _section(pdfL10n(context).propSectionText),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Row(children: [
          Expanded(child: Text(pdfL10n(context).propFont)),
          PdfFontMenuButton(
            buttonKey: const ValueKey('pdf-prop-form-font'),
            controller: _controller,
            fontPicker: widget.fontPicker,
            currentFont: style.font,
          ),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Row(children: [
          Expanded(child: Text(pdfL10n(context).propStyle)),
          FontStyleToggles(
            keyPrefix: 'pdf-prop-form-font',
            font: style.font,
            onChanged: (font) =>
                _controller.setFormFieldStyle(name, font: font),
          ),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Row(children: [
          Expanded(child: Text(pdfL10n(context).propAlign)),
          TextAlignToggles(
            keyPrefix: 'pdf-prop-form-align',
            align: style.align,
            onChanged: (align) =>
                _controller.setFormFieldStyle(name, align: align),
          ),
        ]),
      ),
      SwitchListTile(
        key: const ValueKey('pdf-prop-form-autosize'),
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
        title: Text(pdfL10n(context).propAutoSize),
        value: style.autoSize,
        onChanged: (v) => _controller.setFormFieldStyle(name,
            autoSize: v, fontSize: v ? null : style.size),
      ),
      if (!style.autoSize)
        _sliderRow(
          pdfL10n(context).propSize,
          _draggingFontSize ?? style.size,
          key: const ValueKey('pdf-prop-form-size'),
          min: 6,
          max: 72,
          fieldMin: 1,
          fieldMax: kPdfTypedSizeMax,
          onChanged: (v) => setState(() => _draggingFontSize = v),
          onChangeEnd: (v) {
            _controller.setFormFieldStyle(name, fontSize: v.roundToDouble());
            setState(() => _draggingFontSize = null);
          },
        ),
      SwitchListTile(
        key: const ValueKey('pdf-prop-form-multiline'),
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
        title: Text(pdfL10n(context).propMultiline),
        value: style.multiline,
        onChanged: (v) => _controller.setFormFieldStyle(name, multiline: v),
      ),
      _swatchRow(pdfL10n(context).propColor, style.color,
          key: const ValueKey('pdf-prop-form-color'),
          onTap: () => _pickFormColor(name, style.color)),
    ];
  }

  Future<void> _pickFormColor(String name, Color current) async {
    final picked =
        await pickEditingColor(context, _controller, initial: current);
    if (picked != null) {
      _controller.setFormFieldStyle(name, color: picked.toARGB32() & 0xFFFFFF);
    }
  }

  List<Widget> _buildSingle(PdfAnnotation annotation) {
    final slot = _controller.selectedAnnotationSlot!;
    return [
      ListTile(
        leading: Icon(annotation.isCallout
            ? Icons.chat_bubble_outline
            : pdfAnnotationIcon(annotation.subtype)),
        title: Text(annotation.isCallout
            ? pdfL10n(context).propCallout
            : pdfAnnotationLabel(context, annotation.subtype)),
        subtitle: Text(pdfL10n(context).propPageNumber(slot.$1 + 1)),
      ),
      ..._styleControls(),
      ..._textStyleControls(annotation),
      // a form widget's /T is its field name, not an author, and /V (not
      // /Contents) is its value - so widgets get a "Field name" row instead
      // of the generic Contents/Author section
      if (annotation.subtype == 'Widget') ...[
        if (_controller.selectedWidgetFieldName != null) ...[
          _section(pdfL10n(context).propSectionFormField),
          _textRow(pdfL10n(context).propFieldName, _fieldName,
              key: const ValueKey('pdf-prop-field-name'),
              onCommit: _commitFieldName),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(children: [
              Expanded(child: Text(pdfL10n(context).propType)),
              PdfSelectedFormFieldTypeMenu(
                controller: _controller,
                buttonKey: const ValueKey('pdf-prop-form-type'),
                itemKeyPrefix: 'pdf-prop-form-type',
                showLabel: true,
              ),
            ]),
          ),
        ],
        ..._formFieldControls(),
      ] else ...[
        ..._formFieldControls(),
        _section(pdfL10n(context).propSectionContent),
        _textRow(pdfL10n(context).propContents, _contents,
            key: const ValueKey('pdf-prop-contents'),
            onCommit: _commitContents,
            maxLines: 4),
        if (widget.showAuthor)
          _textRow(pdfL10n(context).propAuthor, _author,
              key: const ValueKey('pdf-prop-author'), onCommit: _commitAuthor),
      ],
      _section(pdfL10n(context).propSectionPositionSize),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Row(children: [
          _geometryField(pdfL10n(context).propGeometryX, _x,
              const ValueKey('pdf-prop-x'),
              enabled: true),
          const SizedBox(width: 8),
          _geometryField(pdfL10n(context).propGeometryY, _y,
              const ValueKey('pdf-prop-y'),
              enabled: true),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Row(children: [
          _geometryField(pdfL10n(context).propGeometryWidth, _w,
              const ValueKey('pdf-prop-w'),
              enabled: _controller.canResizeSelected),
          const SizedBox(width: 8),
          _geometryField(pdfL10n(context).propGeometryHeight, _h,
              const ValueKey('pdf-prop-h'),
              enabled: _controller.canResizeSelected),
        ]),
      ),
      const SizedBox(height: 16),
    ];
  }

  List<Widget> _buildMulti(int count) {
    final annotations = _selectedAnnotations;
    final type = _common<String>([
      for (final annotation in annotations)
        annotation.isCallout
            ? pdfL10n(context).propCallout
            : pdfAnnotationLabel(context, annotation.subtype),
    ]);
    final page = _common<int>([
      for (final (page, _) in _controller.selectedAnnotationSlots) page + 1,
    ]);
    final hasWidget = annotations.any((a) => a.subtype == 'Widget');
    return [
      ListTile(
        leading: const Icon(Icons.select_all),
        title: Text(pdfL10n(context).propAnnotationCount(count)),
        subtitle: Text(pdfL10n(context).propEditsApplyToAll),
      ),
      _section(pdfL10n(context).propSectionSelection),
      _readOnlyRow(
        pdfL10n(context).propType,
        type.varies ? pdfL10n(context).propVaries : type.value,
        const ValueKey('pdf-prop-type-value'),
      ),
      _readOnlyRow(
        pdfL10n(context).propPageLabel,
        page.varies ? pdfL10n(context).propVaries : '${page.value}',
        const ValueKey('pdf-prop-page-value'),
      ),
      ..._styleControls(),
      if (!hasWidget) ...[
        _section(pdfL10n(context).propSectionContent),
        _textRow(
          pdfL10n(context).propContents,
          _contents,
          key: const ValueKey('pdf-prop-contents'),
          onCommit: _commitContents,
          enabled: _controller.canSetSelectedContents,
          maxLines: 4,
          varies: _contentsVaries,
        ),
        if (widget.showAuthor)
          _textRow(
            pdfL10n(context).propAuthor,
            _author,
            key: const ValueKey('pdf-prop-author'),
            onCommit: _commitAuthor,
            enabled: _controller.canSetSelectedAuthor,
            varies: _authorVaries,
          ),
      ],
      const SizedBox(height: 16),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return PdfSidebarPanelFrame(
      width: widget.width,
      minWidth: widget.minWidth,
      maxWidth: widget.maxWidth,
      persistedWidth: _preferences.propertiesPanelWidth,
      onPersistWidth: (width) => _preferences.propertiesPanelWidth = width,
      dock: widget.dock,
      panel: PdfDockablePanel.properties,
      resizable: widget.resizable,
      bottomSheet: widget.bottomSheet,
      gripKey: const ValueKey('pdf-properties-resize-grip'),
      onClose: widget.onClose,
      builder: (context, geometry) {
        final moveHandle = geometry.moveHandle(
          key: const ValueKey('pdf-properties-panel-move'),
        );
        final closeButton = geometry.closeButton(
          key: const ValueKey('pdf-properties-panel-close'),
        );
        return Material(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          child: Column(children: [
            if (moveHandle != null || closeButton != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 4, 0),
                child: Row(children: [
                  Expanded(
                    child: Text(pdfL10n(context).propPropertiesTitle,
                        style: Theme.of(context).textTheme.titleSmall),
                  ),
                  if (moveHandle != null) moveHandle,
                  if (closeButton != null) closeButton,
                ]),
              ),
            Expanded(
              child: ListenableBuilder(
                listenable: _controller,
                builder: (context, _) {
                  final annotation = _controller.selectedAnnotation;
                  _syncFields(annotation);
                  if (annotation == null) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                            pdfL10n(context).propSelectAnnotationPrompt,
                            textAlign: TextAlign.center),
                      ),
                    );
                  }
                  final count = _controller.selectedAnnotationSlots.length;
                  final children = count == 1
                      ? _buildSingle(annotation)
                      : _buildMulti(count);
                  return geometry.withScrollbar(
                    scroll: _scroll,
                    thumbKey: const ValueKey('pdf-properties-scrollbar-thumb'),
                    child: ScrollConfiguration(
                      behavior: ScrollConfiguration.of(context)
                          .copyWith(scrollbars: false),
                      child: ListView(
                          controller: _scroll,
                          padding: EdgeInsets.only(
                              right: geometry.scrollbarClearance),
                          children: children),
                    ),
                  );
                },
              ),
            ),
          ]),
        );
      },
    );
  }
}
