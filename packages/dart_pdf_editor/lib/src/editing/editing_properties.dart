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
/// of these apply: color, fill, stroke width, corner radius (rectangles
/// only), opacity (restyled in place via
/// [PdfEditingController.restyleSelected]), font and size for text
/// boxes, the contents text, the author, and the position and size in
/// page points. With several selected, common values are shown normally,
/// mixed values read "Varies", and compatible edits act on the whole
/// selection at once; with none it invites a selection.
///
/// The rows are gathered under collapsible section headers (Appearance,
/// Text, Content, Position & size, …) - tap a header to fold a group away
/// and keep the panel legible as it fills up. The fold state is per-group,
/// held for the panel's lifetime and shared across selections.
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
  double? _draggingCornerRadius;
  double? _draggingScale;
  double? _draggingOpacity;
  double? _draggingFontSize;
  double? _draggingLineSpacing;
  double? _draggingCharSpacing;
  double? _draggingFontWidth;

  /// Whether each collapsible property group is open, keyed by the group's
  /// stable id. Absent means open - groups start expanded, so nothing is
  /// hidden until the user collapses it. The choice is per-group (not
  /// per-annotation), so a collapsed group stays collapsed across selection
  /// changes for the panel's lifetime.
  final Map<String, bool> _expanded = {};

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
                  child: Text(pdfLineEndingLabel(context, ending),
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

  /// A collapsible titled group of property rows. Tapping the header toggles
  /// [_expanded] for [id]; groups start expanded. Grouping keeps the panel
  /// legible as it fills up - a collapsed group hides its rows and just
  /// leaves its header behind.
  Widget _group(String id, String title, List<Widget> children) {
    final expanded = _expanded[id] ?? true;
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          key: ValueKey('pdf-prop-section-$id'),
          onTap: () => setState(() => _expanded[id] = !expanded),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 8, 4),
            child: Row(children: [
              Expanded(
                child: Text(title,
                    style: Theme.of(context).textTheme.labelLarge),
              ),
              Icon(expanded ? Icons.expand_more : Icons.chevron_right,
                  size: 20, color: scheme.onSurfaceVariant),
            ]),
          ),
        ),
        if (expanded) ...children,
      ],
    );
  }

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
      padding: const EdgeInsetsDirectional.only(start: 16, end: 8),
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

  /// The selected annotations that satisfy one semantic capability. Property
  /// controls operate on this compatible subset instead of disappearing just
  /// because the mixed selection also contains another subtype.
  List<PdfAnnotation> _compatible(
    bool Function(PdfAnnotationBehavior) test,
  ) =>
      [
        for (final annotation in _selectedAnnotations)
          if (annotation.behavior.canRestyle && test(annotation.behavior))
            annotation,
      ];

  List<Widget> _styleControls() {
    final children = <Widget>[];
    if (!_controller.canRestyleSelected) return children;
    final annotations = _selectedAnnotations;
    if (annotations.isEmpty) return children;
    // An image stamp (a pasted picture) has no tintable colour - only its
    // opacity applies - so the swatch is hidden for it while opacity stays.
    final colorAnnotations = _compatible((behavior) => behavior.supportsColor);
    if (colorAnnotations.isNotEmpty) {
      final colors = _common<int?>([
        for (final annotation in colorAnnotations)
          annotation.behavior.style.color,
      ]);
      children.add(_swatchRow(
        pdfL10n(context).propColor,
        Color(0xFF000000 | (colors.value ?? 0)),
        key: const ValueKey('pdf-prop-color'),
        onTap: _pickColor,
        varies: colors.varies,
      ));
    }
    final fillAnnotations = _compatible((behavior) => behavior.supportsFill);
    if (fillAnnotations.isNotEmpty) {
      final fills = _common<int?>([
        for (final annotation in fillAnnotations)
          annotation.behavior.style.fillColor,
      ]);
      final fillColor =
          fills.value == null ? null : Color(0xFF000000 | fills.value!);
      children.add(_swatchRow(pdfL10n(context).propFill, fillColor,
          key: const ValueKey('pdf-prop-fill'),
          onTap: () => _pickFill(fillColor),
          onClear: () => _controller.restyleSelected(fill: (null,)),
          varies: fills.varies));
    }
    final strokeAnnotations =
        _compatible((behavior) => behavior.supportsStrokeWidth);
    if (strokeAnnotations.isNotEmpty) {
      final widths = _common<double?>([
        for (final annotation in strokeAnnotations)
          annotation.behavior.style.strokeWidth,
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
    // rounding is rectangle-only (/Square) - the controller's gate keeps it
    // off circles, polygons and everything else
    if (_controller.canRoundSelectedCorners) {
      final radii = _common<double>([
        for (final annotation in annotations)
          if (annotation.subtype == 'Square' &&
              annotation.behavior.canRestyle)
            annotation.cornerRadius,
      ]);
      children.add(_sliderRow(
        pdfL10n(context).propCornerRadius,
        _draggingCornerRadius ?? radii.value,
        key: const ValueKey('pdf-prop-corner-radius'),
        min: 0,
        max: 40,
        fieldMin: 0,
        fieldMax: kPdfTypedSizeMax,
        varies: _draggingCornerRadius == null && radii.varies,
        display: (v) => '${v.round()} pt',
        parse: (s) => double.tryParse(s.replaceAll(RegExp('[^0-9.]'), '')),
        onChanged: (v) => setState(() => _draggingCornerRadius = v),
        onChangeEnd: (v) {
          _controller.restyleSelected(cornerRadius: v.roundToDouble());
          setState(() => _draggingCornerRadius = null);
        },
      ));
    }
    final lineStyleAnnotations =
        _compatible((behavior) => behavior.supportsLineStyle);
    if (lineStyleAnnotations.isNotEmpty &&
        _controller.canSetLineStyleSelected) {
      final lineStyles = _common<PdfLineStyle>([
        for (final annotation in lineStyleAnnotations)
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
      final lineEndingAnnotations = [
        for (final annotation in annotations)
          if (annotation.behavior.supportsLineEndings &&
              annotation.normalAppearance != null)
            annotation,
      ];
      final starts = _common<PdfLineEnding>([
        for (final annotation in lineEndingAnnotations)
          pdfLineEndings(annotation)!.$1,
      ]);
      final ends = _common<PdfLineEnding>([
        for (final annotation in lineEndingAnnotations)
          pdfLineEndings(annotation)!.$2,
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
    final opacityAnnotations =
        _compatible((behavior) => behavior.supportsOpacity);
    if (opacityAnnotations.isNotEmpty) {
      final opacities = _common<double>([
        for (final annotation in opacityAnnotations)
          annotation.behavior.style.opacity,
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

  List<Widget> _textStyleControls() {
    if (!_controller.canRestyleSelectedText) return const [];
    final annotations = [
      for (final annotation in _selectedAnnotations)
        if (annotation.subtype == 'FreeText') annotation,
    ];
    if (annotations.isEmpty) return const [];
    final style = _controller.selectedTextStyle;
    if (style == null) return const [];
    final sizes = _common<double>([
      for (final annotation in annotations)
        annotation.freeTextStyle?.fontSize ?? style.size,
    ]);
    final freeStyles = [
      for (final annotation in annotations)
        annotation.freeTextStyle ??
            PdfFreeTextStyle(
              fontName: style.font.resourceName,
              fontSize: style.size,
              color: annotation.color ?? 0,
            ),
    ];
    final alignments =
        _common<PdfTextAlign>([for (final value in freeStyles) value.alignment]);
    final underlines =
        _common<bool>([for (final value in freeStyles) value.underline]);
    final lineSpacings =
        _common<double>([for (final value in freeStyles) value.lineSpacing]);
    final charSpacings =
        _common<double>([for (final value in freeStyles) value.charSpacing]);
    final fontWidths = _common<double>([
      for (final value in freeStyles) value.horizontalScale,
    ]);
    final borders =
        _common<int?>([for (final value in freeStyles) value.borderColor]);
    final borderColor = borders.value == null
        ? null
        : Color(0xFF000000 | borders.value!);
    return [
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
            align: alignments.value,
            onChanged: (align) => _controller.restyleSelectedText(align: align),
          ),
        ]),
      ),
      _sliderRow(
        pdfL10n(context).propSize,
        _draggingFontSize ?? sizes.value,
        key: const ValueKey('pdf-prop-font-size'),
        min: 6,
        max: 72,
        fieldMin: 1,
        fieldMax: kPdfTypedSizeMax,
        varies: _draggingFontSize == null && sizes.varies,
        onChanged: (v) => setState(() => _draggingFontSize = v),
        onChangeEnd: (v) {
          _controller.restyleSelectedText(size: v.roundToDouble());
          setState(() => _draggingFontSize = null);
        },
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Row(children: [
          Expanded(child: Text(pdfL10n(context).propUnderline)),
          IconButton(
            key: const ValueKey('pdf-prop-text-underline'),
            icon: const Icon(Icons.format_underlined, size: 18),
            tooltip: underlines.varies
                ? pdfL10n(context).propVaries
                : pdfL10n(context).propUnderline,
            isSelected: !underlines.varies && underlines.value,
            onPressed: () => _controller.setSelectedTextBoxStyle(
              underline: underlines.varies || !underlines.value,
            ),
          ),
        ]),
      ),
      _sliderRow(
        pdfL10n(context).propLineSpacing,
        _draggingLineSpacing ?? lineSpacings.value,
        key: const ValueKey('pdf-prop-line-spacing'),
        min: 0.8,
        max: 3,
        fieldMin: 0.1,
        fieldMax: 100,
        varies: _draggingLineSpacing == null && lineSpacings.varies,
        display: (v) => '${v.toStringAsFixed(1)}×',
        onChanged: (v) => setState(() => _draggingLineSpacing = v),
        onChangeEnd: (v) {
          _controller.setSelectedTextBoxStyle(lineSpacing: v);
          setState(() => _draggingLineSpacing = null);
        },
      ),
      _sliderRow(
        pdfL10n(context).propCharSpacing,
        _draggingCharSpacing ?? charSpacings.value,
        key: const ValueKey('pdf-prop-char-spacing'),
        min: -2,
        max: 10,
        fieldMin: -kPdfTypedSizeMax,
        fieldMax: kPdfTypedSizeMax,
        varies: _draggingCharSpacing == null && charSpacings.varies,
        display: (v) => '${v.toStringAsFixed(1)} pt',
        onChanged: (v) => setState(() => _draggingCharSpacing = v),
        onChangeEnd: (v) {
          _controller.setSelectedTextBoxStyle(charSpacing: v);
          setState(() => _draggingCharSpacing = null);
        },
      ),
      _sliderRow(
        pdfL10n(context).propFontWidth,
        _draggingFontWidth ?? fontWidths.value,
        key: const ValueKey('pdf-prop-font-width'),
        min: 50,
        max: 200,
        fieldMin: 1,
        fieldMax: kPdfTypedSizeMax,
        varies: _draggingFontWidth == null && fontWidths.varies,
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
          clearTooltip: pdfL10n(context).propNoOutline,
          varies: borders.varies),
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
    final l = pdfL10n(context);
    final sections = <Widget>[
      ListTile(
        leading: Icon(annotation.isCallout
            ? Icons.chat_bubble_outline
            : pdfAnnotationIcon(annotation.subtype)),
        title: Text(annotation.isCallout
            ? l.propCallout
            : pdfAnnotationLabel(context, annotation.subtype)),
        subtitle: Text(l.propPageNumber(slot.$1 + 1)),
      ),
    ];

    void addGroup(String id, String title, List<Widget> rows) {
      if (rows.isNotEmpty) sections.add(_group(id, title, rows));
    }

    addGroup('appearance', l.propSectionAppearance, _styleControls());
    addGroup('text', l.propSectionText, _textStyleControls());
    // a form widget's /T is its field name, not an author, and /V (not
    // /Contents) is its value - so widgets get a "Field name" group instead
    // of the generic Contents/Author group
    if (annotation.subtype == 'Widget') {
      if (_controller.selectedWidgetFieldName != null) {
        addGroup('form-field', l.propSectionFormField, [
          _textRow(l.propFieldName, _fieldName,
              key: const ValueKey('pdf-prop-field-name'),
              onCommit: _commitFieldName),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(children: [
              Expanded(child: Text(l.propType)),
              PdfSelectedFormFieldTypeMenu(
                controller: _controller,
                buttonKey: const ValueKey('pdf-prop-form-type'),
                itemKeyPrefix: 'pdf-prop-form-type',
                showLabel: true,
              ),
            ]),
          ),
        ]);
      }
      addGroup('form-text', l.propSectionText, _formFieldControls());
    } else {
      addGroup('form-text', l.propSectionText, _formFieldControls());
      addGroup('content', l.propSectionContent, [
        _textRow(l.propContents, _contents,
            key: const ValueKey('pdf-prop-contents'),
            onCommit: _commitContents,
            maxLines: 4),
        if (widget.showAuthor)
          _textRow(l.propAuthor, _author,
              key: const ValueKey('pdf-prop-author'), onCommit: _commitAuthor),
      ]);
    }
    addGroup('position-size', l.propSectionPositionSize, [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Row(children: [
          _geometryField(l.propGeometryX, _x, const ValueKey('pdf-prop-x'),
              enabled: true),
          const SizedBox(width: 8),
          _geometryField(l.propGeometryY, _y, const ValueKey('pdf-prop-y'),
              enabled: true),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Row(children: [
          _geometryField(l.propGeometryWidth, _w, const ValueKey('pdf-prop-w'),
              enabled: _controller.canResizeSelected),
          const SizedBox(width: 8),
          _geometryField(l.propGeometryHeight, _h, const ValueKey('pdf-prop-h'),
              enabled: _controller.canResizeSelected),
        ]),
      ),
    ]);
    sections.add(const SizedBox(height: 16));
    return sections;
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
    final l = pdfL10n(context);
    final sections = <Widget>[
      ListTile(
        leading: const Icon(Icons.select_all),
        title: Text(l.propAnnotationCount(count)),
        subtitle: Text(l.propEditsApplyToAll),
      ),
    ];

    void addGroup(String id, String title, List<Widget> rows) {
      if (rows.isNotEmpty) sections.add(_group(id, title, rows));
    }

    addGroup('selection', l.propSectionSelection, [
      _readOnlyRow(
        l.propType,
        type.varies ? l.propVaries : type.value,
        const ValueKey('pdf-prop-type-value'),
      ),
      _readOnlyRow(
        l.propPageLabel,
        page.varies ? l.propVaries : '${page.value}',
        const ValueKey('pdf-prop-page-value'),
      ),
    ]);
    addGroup('appearance', l.propSectionAppearance, _styleControls());
    addGroup('text', l.propSectionText, _textStyleControls());
    if (!hasWidget) {
      addGroup('content', l.propSectionContent, [
        _textRow(
          l.propContents,
          _contents,
          key: const ValueKey('pdf-prop-contents'),
          onCommit: _commitContents,
          enabled: _controller.canSetSelectedContents,
          maxLines: 4,
          varies: _contentsVaries,
        ),
        if (widget.showAuthor)
          _textRow(
            l.propAuthor,
            _author,
            key: const ValueKey('pdf-prop-author'),
            onCommit: _commitAuthor,
            enabled: _controller.canSetSelectedAuthor,
            varies: _authorVaries,
          ),
      ]);
    }
    sections.add(const SizedBox(height: 16));
    return sections;
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
