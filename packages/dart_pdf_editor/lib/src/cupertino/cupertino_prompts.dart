// The prompts PdfCupertinoPresenter asks: CupertinoAlertDialogs with
// CupertinoTextFields, and the form-choice picker. Each mirrors the stock
// prompt's validation and result, and carries its pdf-* keys.

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter/services.dart' show FilteringTextInputFormatter;
import 'package:material_ui/material_ui.dart' show Icons;
import 'package:pdf_document/pdf_document.dart'
    show
        PdfEmbeddedFont,
        PdfSplitter,
        PdfStandardFont,
        PdfStandardFontFamily,
        PdfTextStyle;

import '../design/editor_presenter.dart';
import '../dialog.dart';
import '../editing/editing_controller.dart' show PdfLinkTarget;
import '../editing/models/measurement_scale.dart';
import '../editing/text_style_prompt.dart' show PdfStyledTextEdit;
import '../l10n/pdf_l10n.dart';
import 'cupertino_presenter.dart';

// ---- shared pieces ----------------------------------------------------------

/// A [CupertinoTextField] with the Cupertino text menu.
Widget _field({
  required Key key,
  required TextEditingController controller,
  String? placeholder,
  Widget? prefix,
  bool autofocus = false,
  TextInputType? keyboardType,
  bool digitsOnly = false,
  TextAlign textAlign = TextAlign.start,
  int minLines = 1,
  int maxLines = 1,
  ValueChanged<String>? onSubmitted,
  ValueChanged<String>? onChanged,
}) =>
    CupertinoTextField(
      key: key,
      controller: controller,
      placeholder: placeholder,
      prefix: prefix,
      autofocus: autofocus,
      keyboardType: keyboardType,
      inputFormatters:
          digitsOnly ? [FilteringTextInputFormatter.digitsOnly] : null,
      textAlign: textAlign,
      minLines: minLines,
      maxLines: maxLines,
      onSubmitted: onSubmitted,
      onChanged: onChanged,
      contextMenuBuilder: pdfCupertinoTextContextMenu,
    );

/// A field's leading label inside the field ("From", "URL").
Widget _prefix(String label) => Padding(
      padding: const EdgeInsetsDirectional.only(start: 8),
      child: Builder(
        builder: (context) => Text(label,
            style: TextStyle(
                fontSize: 14,
                color: CupertinoColors.secondaryLabel.resolveFrom(context))),
      ),
    );

/// An alert dialog whose content is a column of [content].
Widget _alert({
  Key? key,
  required String title,
  required List<Widget> content,
  required List<Widget> actions,
}) =>
    CupertinoAlertDialog(
      key: key,
      title: Text(title),
      content: Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: content,
        ),
      ),
      actions: actions,
    );

/// Cancel, then the submit action (Enter runs it too).
List<Widget> _actions(
  BuildContext context, {
  required String label,
  required VoidCallback onSubmit,
  required Key submitKey,
  Key? cancelKey,
  List<Widget> leading = const [],
}) =>
    [
      ...leading,
      CupertinoDialogAction(
        key: cancelKey,
        onPressed: () => Navigator.of(context).pop(),
        child: Text(pdfL10n(context).cancel),
      ),
      PdfDialogSubmit.action(
        onSubmit: onSubmit,
        child: CupertinoDialogAction(
          key: submitKey,
          isDefaultAction: true,
          onPressed: onSubmit,
          child: Text(label),
        ),
      ),
    ];

/// An inline validation message.
Widget _errorText(BuildContext context, String message) => Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Text(message,
          style: TextStyle(
              fontSize: 13,
              color: CupertinoColors.systemRed.resolveFrom(context))),
    );

/// A caption line above a field.
Widget _caption(BuildContext context, String text) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(text,
          style: TextStyle(
              fontSize: 13,
              color: CupertinoColors.secondaryLabel.resolveFrom(context))),
    );

/// A unit shown as a button that opens [units] as an action sheet.
class _UnitButton extends StatelessWidget {
  const _UnitButton({
    super.key,
    required this.presenter,
    required this.value,
    required this.units,
    required this.onChanged,
  });

  final PdfEditorPresenter presenter;
  final String value;
  final List<String> units;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => CupertinoButton(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        minimumSize: const Size(36, 32),
        onPressed: () async {
          final box = context.findRenderObject() as RenderBox?;
          final anchor = box == null
              ? Rect.zero
              : box.localToGlobal(Offset.zero) & box.size;
          final picked = await presenter.menu<String>(
            context,
            PdfMenuRequest(anchor: anchor, entries: [
              for (final unit in units)
                PdfMenuItem(
                  key: ValueKey('pdf-cupertino-unit-$unit'),
                  value: unit,
                  label: unit,
                  checked: unit == value,
                ),
            ]),
          );
          if (picked != null) onChanged(picked);
        },
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(value),
          const Icon(Icons.arrow_drop_down, size: 18),
        ]),
      );
}

/// A positive number typed into [text], or null.
double? _positive(TextEditingController text) {
  final value = double.tryParse(text.text.trim());
  return value == null || value <= 0 ? null : value;
}

// ---- text -------------------------------------------------------------------

/// [PdfCupertinoPresenter.text]'s prompt.
class CupertinoTextPrompt extends StatefulWidget {
  /// Asks for [request]'s text.
  const CupertinoTextPrompt({super.key, required this.request});

  /// What to ask.
  final PdfTextRequest request;

  @override
  State<CupertinoTextPrompt> createState() => _CupertinoTextPromptState();
}

class _CupertinoTextPromptState extends State<CupertinoTextPrompt> {
  late final _text = TextEditingController(text: widget.request.initial);

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _submit() => Navigator.of(context).pop(_text.text);

  @override
  Widget build(BuildContext context) {
    final multiline = widget.request.multiline;
    return _alert(
      key: const ValueKey('pdf-text-prompt'),
      title: widget.request.title,
      content: [
        _field(
          key: const ValueKey('pdf-text-prompt-field'),
          controller: _text,
          autofocus: true,
          minLines: multiline ? 3 : 1,
          maxLines: multiline ? 6 : 1,
          onSubmitted: multiline ? null : (_) => _submit(),
        ),
      ],
      actions: _actions(context,
          label: pdfL10n(context).ok,
          onSubmit: _submit,
          submitKey: const ValueKey('pdf-text-prompt-ok')),
    );
  }
}

// ---- styled text --------------------------------------------------------------

/// [PdfCupertinoPresenter.styledText]'s prompt.
class CupertinoStyledTextPrompt extends StatefulWidget {
  /// Asks for [request]'s replacement text and style.
  const CupertinoStyledTextPrompt({super.key, required this.request});

  /// What to ask.
  final PdfStyledTextRequest request;

  @override
  State<CupertinoStyledTextPrompt> createState() =>
      _CupertinoStyledTextPromptState();
}

class _CupertinoStyledTextPromptState extends State<CupertinoStyledTextPrompt> {
  late final _text = TextEditingController(text: widget.request.initial);

  // Overrides are opt-in, as in the stock prompt: each stays unset (keep
  // the run's value) until its control is touched.
  PdfStandardFont _font = PdfStandardFont.helvetica;
  PdfEmbeddedFont? _embedded;
  bool _styleTouched = false;
  double _size = 14;
  bool _sizeTouched = false;
  Color? _fill;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _submit() {
    final useStd = _embedded == null && _styleTouched;
    Navigator.of(context).pop(PdfStyledTextEdit(
      _text.text,
      PdfTextStyle(
        color: _fill == null ? null : (_fill!.toARGB32() & 0xFFFFFF),
        fontSize: _sizeTouched ? _size : null,
        embeddedFont: _embedded,
        family: useStd ? _font.family : null,
        bold: useStd ? _font.isBold : null,
        italic: useStd ? _font.isItalic : null,
      ),
    ));
  }

  Future<void> _pickFont() async {
    final picked = await widget.request.pickFont!(context);
    if (picked == null || !mounted) return;
    setState(() {
      _styleTouched = true;
      if (picked is PdfEmbeddedFont) {
        _embedded = picked;
      } else if (picked is PdfStandardFont) {
        _embedded = null;
        _font = picked;
      }
    });
  }

  Future<void> _pickColour() async {
    final picked = await pdfPresentColor(
        context, PdfColorRequest(initial: _fill ?? const Color(0xFF000000)));
    if (picked != null && mounted) setState(() => _fill = picked);
  }

  Widget _row(String label, Widget control) => Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Row(children: [
          SizedBox(
            width: 72,
            child: Text(label,
                textAlign: TextAlign.start,
                style: const TextStyle(fontSize: 13)),
          ),
          Expanded(
              child: Align(
                  alignment: AlignmentDirectional.centerStart, child: control)),
        ]),
      );

  Widget _toggle(
      {required Key key,
      required String letter,
      required String label,
      required bool selected,
      required TextStyle style,
      required VoidCallback onTap}) {
    final primary = CupertinoTheme.of(context).primaryColor;
    return Semantics(
      label: label,
      selected: selected,
      button: true,
      child: CupertinoButton(
        key: key,
        padding: EdgeInsets.zero,
        minimumSize: const Size(34, 30),
        color: selected ? primary : null,
        onPressed: onTap,
        child: Text(letter,
            style: style.copyWith(
                color: selected
                    ? CupertinoTheme.of(context).primaryContrastingColor
                    : primary)),
      ),
    );
  }

  Widget _swatch(
      {required Key key,
      required Color? color,
      required bool selected,
      required String label,
      required VoidCallback onTap}) {
    final ring = CupertinoTheme.of(context).primaryColor;
    return Semantics(
      label: label,
      selected: selected,
      button: true,
      child: GestureDetector(
        key: key,
        onTap: onTap,
        child: Container(
          width: 24,
          height: 24,
          margin: const EdgeInsetsDirectional.only(end: 6),
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(
              color: selected
                  ? ring
                  : CupertinoColors.separator.resolveFrom(context),
              width: selected ? 2.5 : 1,
            ),
          ),
          child: color == null
              ? Icon(Icons.block,
                  size: 14,
                  color: CupertinoColors.secondaryLabel.resolveFrom(context))
              : null,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = pdfL10n(context);
    final palette = widget.request.palette;
    final fontLabel = _embedded?.familyName ??
        (_styleTouched ? _font.family.label : l10n.textStyleKeepFont);
    return _alert(
      key: const ValueKey('pdf-cupertino-styled-text'),
      title: l10n.textStyleTitle,
      content: [
        _field(
          key: const ValueKey('pdf-styled-text-field'),
          controller: _text,
          autofocus: true,
          placeholder: l10n.textStyleText,
          onSubmitted: (_) => _submit(),
        ),
        _row(
          l10n.textStyleFontSize,
          Row(children: [
            Expanded(
              child: CupertinoSlider(
                key: const ValueKey('pdf-styled-size'),
                value: _size,
                min: 6,
                max: 96,
                onChanged: (v) => setState(() {
                  _size = v.roundToDouble();
                  _sizeTouched = true;
                }),
              ),
            ),
            SizedBox(
              width: 40,
              child: Text(
                _sizeTouched ? '${_size.round()} pt' : l10n.textStyleKeep,
                textAlign: TextAlign.end,
                style: const TextStyle(fontSize: 13),
              ),
            ),
          ]),
        ),
        _row(
          l10n.textStyleFont,
          widget.request.pickFont != null
              ? CupertinoButton(
                  key: const ValueKey('pdf-styled-font'),
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(0, 30),
                  onPressed: _pickFont,
                  child: Text(fontLabel,
                      overflow: TextOverflow.ellipsis, maxLines: 1),
                )
              : CupertinoSlidingSegmentedControl<PdfStandardFontFamily>(
                  key: const ValueKey('pdf-styled-family'),
                  groupValue: _styleTouched ? _font.family : null,
                  children: {
                    for (final family in PdfStandardFontFamily.values)
                      family: Text(family.label,
                          key: ValueKey('pdf-styled-family-${family.name}'),
                          style: const TextStyle(fontSize: 13)),
                  },
                  onValueChanged: (family) {
                    if (family == null) return;
                    setState(() {
                      _font = PdfStandardFont.styled(family,
                          bold: _font.isBold, italic: _font.isItalic);
                      _styleTouched = true;
                    });
                  },
                ),
        ),
        _row(
          l10n.textStyleStyle,
          Row(mainAxisSize: MainAxisSize.min, children: [
            _toggle(
              key: const ValueKey('pdf-styled-bold'),
              letter: l10n.propBoldLetter,
              label: l10n.propBold,
              selected: _styleTouched && _font.isBold,
              style: const TextStyle(fontWeight: FontWeight.bold),
              onTap: () => setState(() {
                _font = _font.withBold(!_font.isBold);
                _styleTouched = true;
              }),
            ),
            const SizedBox(width: 8),
            _toggle(
              key: const ValueKey('pdf-styled-italic'),
              letter: l10n.propItalicLetter,
              label: l10n.propItalic,
              selected: _styleTouched && _font.isItalic,
              style: const TextStyle(fontStyle: FontStyle.italic),
              onTap: () => setState(() {
                _font = _font.withItalic(!_font.isItalic);
                _styleTouched = true;
              }),
            ),
          ]),
        ),
        _row(
          l10n.textStyleTextFill,
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              _swatch(
                key: const ValueKey('pdf-styled-fill-none'),
                color: null,
                selected: _fill == null,
                label: l10n.textStyleKeep,
                onTap: () => setState(() => _fill = null),
              ),
              for (var i = 0; i < palette.length; i++)
                _swatch(
                  key: ValueKey('pdf-styled-fill-$i'),
                  color: palette[i],
                  selected: _fill != null &&
                      (_fill!.toARGB32() & 0xFFFFFF) ==
                          (palette[i].toARGB32() & 0xFFFFFF),
                  label:
                      '#${(palette[i].toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}',
                  onTap: () => setState(() => _fill = palette[i]),
                ),
              Semantics(
                label: l10n.propMoreColors,
                button: true,
                child: CupertinoButton(
                  key: const ValueKey('pdf-styled-fill-more'),
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(28, 28),
                  onPressed: _pickColour,
                  child: const Icon(Icons.palette_outlined, size: 18),
                ),
              ),
            ]),
          ),
        ),
      ],
      actions: _actions(context,
          label: l10n.apply,
          onSubmit: _submit,
          submitKey: const ValueKey('pdf-styled-ok')),
    );
  }
}

// ---- link -------------------------------------------------------------------

enum _LinkKind { web, page }

/// [PdfCupertinoPresenter.link]'s prompt.
class CupertinoLinkPrompt extends StatefulWidget {
  /// Asks for [request]'s link target.
  const CupertinoLinkPrompt({super.key, required this.request});

  /// What to ask.
  final PdfLinkRequest request;

  @override
  State<CupertinoLinkPrompt> createState() => _CupertinoLinkPromptState();
}

class _CupertinoLinkPromptState extends State<CupertinoLinkPrompt> {
  late final _url = TextEditingController(text: widget.request.initialUrl);
  late final _page = TextEditingController(
      text:
          '${(widget.request.currentPage + 1).clamp(1, widget.request.pageCount)}');
  var _kind = _LinkKind.web;

  @override
  void dispose() {
    _url.dispose();
    _page.dispose();
    super.dispose();
  }

  PdfLinkTarget? _result() {
    if (_kind == _LinkKind.web) {
      final uri = _url.text.trim();
      return uri.isEmpty ? null : PdfLinkTarget.uri(uri);
    }
    final oneBased = int.tryParse(_page.text.trim());
    if (oneBased == null) return null;
    return PdfLinkTarget.page(
        (oneBased - 1).clamp(0, widget.request.pageCount - 1));
  }

  void _submit() => Navigator.of(context).pop(_result());

  @override
  Widget build(BuildContext context) {
    final l10n = pdfL10n(context);
    return _alert(
      key: const ValueKey('pdf-cupertino-link'),
      title: l10n.linkDialogTitle,
      content: [
        CupertinoSlidingSegmentedControl<_LinkKind>(
          key: const ValueKey('pdf-link-kind'),
          groupValue: _kind,
          children: {
            _LinkKind.web: Text(l10n.linkKindWeb,
                key: const ValueKey('pdf-link-kind-web'),
                style: const TextStyle(fontSize: 13)),
            _LinkKind.page: Text(l10n.linkKindPage,
                key: const ValueKey('pdf-link-kind-page'),
                style: const TextStyle(fontSize: 13)),
          },
          onValueChanged: (kind) {
            if (kind != null) setState(() => _kind = kind);
          },
        ),
        const SizedBox(height: 12),
        if (_kind == _LinkKind.web)
          _field(
            key: const ValueKey('pdf-link-url'),
            controller: _url,
            autofocus: true,
            prefix: _prefix(l10n.linkUrlLabel),
            placeholder: 'https://example.com',
            keyboardType: TextInputType.url,
            onSubmitted: (_) => _submit(),
          )
        else
          _field(
            key: const ValueKey('pdf-link-page'),
            controller: _page,
            autofocus: true,
            prefix: _prefix(l10n.linkPageLabel),
            placeholder: '1 – ${widget.request.pageCount}',
            keyboardType: TextInputType.number,
            digitsOnly: true,
            onSubmitted: (_) => _submit(),
          ),
      ],
      actions: _actions(context,
          label: l10n.ok,
          onSubmit: _submit,
          submitKey: const ValueKey('pdf-link-ok')),
    );
  }
}

// ---- form choice ------------------------------------------------------------

/// [PdfCupertinoPresenter.formChoice]'s popup: a [CupertinoPicker] for a
/// single-select field, a checklist for a multi-select one, under a Cancel /
/// Done bar.
class CupertinoFormChoice extends StatefulWidget {
  /// Asks for [request]'s selection.
  const CupertinoFormChoice({super.key, required this.request});

  /// What to ask.
  final PdfFormChoiceRequest request;

  @override
  State<CupertinoFormChoice> createState() => _CupertinoFormChoiceState();
}

class _CupertinoFormChoiceState extends State<CupertinoFormChoice> {
  late final Set<String> _selected = {...widget.request.selected};
  late int _index = () {
    final options = widget.request.options;
    final at =
        options.indexWhere((o) => widget.request.selected.contains(o.$1));
    return at < 0 ? 0 : at;
  }();
  late final _scroll = FixedExtentScrollController(initialItem: _index);

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _done() {
    final request = widget.request;
    if (request.options.isEmpty) {
      Navigator.of(context).pop();
      return;
    }
    Navigator.of(context).pop(request.multiSelect
        ? [
            for (final (export, _) in request.options)
              if (_selected.contains(export)) export,
          ]
        : [request.options[_index].$1]);
  }

  @override
  Widget build(BuildContext context) {
    final request = widget.request;
    final l10n = pdfL10n(context);
    final size = MediaQuery.sizeOf(context);
    final primary = CupertinoTheme.of(context).primaryColor;
    final Widget body;
    if (request.multiSelect) {
      body = ListView(
        shrinkWrap: true,
        children: [
          for (final (export, display) in request.options)
            CupertinoListTile(
              key: ValueKey('${request.optionKeyPrefix}$export'),
              title: Text(display),
              trailing: _selected.contains(export)
                  ? Icon(Icons.check, size: 20, color: primary)
                  : null,
              onTap: () => setState(() {
                if (!_selected.remove(export)) _selected.add(export);
              }),
            ),
        ],
      );
    } else {
      body = SizedBox(
        height: 216,
        child: CupertinoPicker(
          key: const ValueKey('pdf-cupertino-choice-picker'),
          scrollController: _scroll,
          itemExtent: 36,
          onSelectedItemChanged: (i) => _index = i,
          children: [
            for (final (export, display) in request.options)
              Center(
                key: ValueKey('${request.optionKeyPrefix}$export'),
                child: Text(display, overflow: TextOverflow.ellipsis),
              ),
          ],
        ),
      );
    }
    return CupertinoSheetSurface(
      key: const ValueKey('pdf-cupertino-choice'),
      maxHeight: size.height * 0.6,
      showDragHandle: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            CupertinoButton(
              key: const ValueKey('pdf-cupertino-choice-cancel'),
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l10n.cancel),
            ),
            const Spacer(),
            CupertinoButton(
              key: const ValueKey('pdf-cupertino-choice-done'),
              onPressed: _done,
              child: Text(l10n.done,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
          ]),
          Container(
              height: 0.5,
              color: CupertinoColors.separator.resolveFrom(context)),
          Flexible(child: body),
        ],
      ),
    );
  }
}

// ---- measuring ----------------------------------------------------------------

/// [PdfCupertinoPresenter.measurementScale]'s prompt.
class CupertinoScalePrompt extends StatefulWidget {
  /// Asks for [request]'s scale; [presenter] shows the unit menus.
  const CupertinoScalePrompt(
      {super.key, required this.presenter, required this.request});

  /// Shows the unit menus.
  final PdfEditorPresenter presenter;

  /// What to ask.
  final PdfMeasurementScaleRequest request;

  @override
  State<CupertinoScalePrompt> createState() => _CupertinoScalePromptState();
}

class _CupertinoScalePromptState extends State<CupertinoScalePrompt> {
  late final TextEditingController _value;
  late String _unit;
  late String _pageUnit;

  @override
  void initState() {
    super.initState();
    final initial = widget.request.initial;
    _pageUnit = initial != null && pdfPageUnits.contains(initial.pageUnitLabel)
        ? initial.pageUnitLabel
        : pdfDefaultPageUnit();
    final perPageUnit = initial == null
        ? 1.0
        : initial.unitsPerPoint * pdfPointsPerPageUnit(_pageUnit);
    var text = perPageUnit.toStringAsFixed(2);
    if (text.contains('.')) {
      text = text
          .replaceFirst(RegExp(r'0+$'), '')
          .replaceFirst(RegExp(r'\.$'), '');
    }
    _value = TextEditingController(text: text);
    _unit = initial != null && pdfScaleUnits.contains(initial.unitLabel)
        ? initial.unitLabel
        : pdfDefaultMeasurementUnit();
  }

  @override
  void dispose() {
    _value.dispose();
    super.dispose();
  }

  void _submit() {
    final perPageUnit = _positive(_value);
    Navigator.of(context).pop(perPageUnit == null
        ? null
        : PdfMeasurementScale(
            unitsPerPoint: perPageUnit / pdfPointsPerPageUnit(_pageUnit),
            unitLabel: _unit,
            pageUnitLabel: _pageUnit,
          ));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = pdfL10n(context);
    final onCalibrate = widget.request.onCalibrate;
    return _alert(
      key: const ValueKey('pdf-cupertino-scale'),
      title: l10n.measSetScale,
      content: [
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Text('1'),
          _UnitButton(
            key: const ValueKey('pdf-scale-page-unit'),
            presenter: widget.presenter,
            value: _pageUnit,
            units: pdfPageUnits,
            onChanged: (unit) => setState(() => _pageUnit = unit),
          ),
          const Text('='),
          const SizedBox(width: 6),
          SizedBox(
            width: 72,
            child: _field(
              key: const ValueKey('pdf-scale-value'),
              controller: _value,
              autofocus: true,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              textAlign: TextAlign.end,
              onSubmitted: (_) => _submit(),
            ),
          ),
          _UnitButton(
            key: const ValueKey('pdf-scale-unit'),
            presenter: widget.presenter,
            value: _unit,
            units: pdfScaleUnits,
            onChanged: (unit) => setState(() => _unit = unit),
          ),
        ]),
      ],
      actions: _actions(
        context,
        label: l10n.measSetScaleButton,
        onSubmit: _submit,
        submitKey: const ValueKey('pdf-scale-apply'),
        leading: [
          if (onCalibrate != null)
            CupertinoDialogAction(
              key: const ValueKey('pdf-scale-calibrate'),
              onPressed: () {
                Navigator.of(context).pop();
                onCalibrate();
              },
              child: Text(l10n.measCalibrate),
            ),
        ],
      ),
    );
  }
}

/// [PdfCupertinoPresenter.measurementInput]'s prompt.
class CupertinoMeasurementInputPrompt extends StatefulWidget {
  /// Asks for [request]'s number; [presenter] shows the unit menu.
  const CupertinoMeasurementInputPrompt(
      {super.key, required this.presenter, required this.request});

  /// Shows the unit menu.
  final PdfEditorPresenter presenter;

  /// What to ask.
  final PdfMeasurementInputRequest request;

  @override
  State<CupertinoMeasurementInputPrompt> createState() =>
      _CupertinoMeasurementInputPromptState();
}

class _CupertinoMeasurementInputPromptState
    extends State<CupertinoMeasurementInputPrompt> {
  final _value = TextEditingController();
  late String _unit = () {
    final unit = widget.request.unit;
    return widget.request.kind == PdfMeasurementInputKind.calibrationLength &&
            (unit == null || !pdfScaleUnits.contains(unit))
        ? pdfDefaultMeasurementUnit()
        : unit ?? '';
  }();

  bool get _calibrating =>
      widget.request.kind == PdfMeasurementInputKind.calibrationLength;

  @override
  void dispose() {
    _value.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _positive(_value);
    Navigator.of(context).pop(value == null
        ? null
        : PdfMeasurementInput(value,
            unit: _calibrating ? _unit : widget.request.unit));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = pdfL10n(context);
    final field = _field(
      key: ValueKey(_calibrating ? 'pdf-calibrate-value' : 'pdf-depth-value'),
      controller: _value,
      autofocus: true,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      textAlign: TextAlign.end,
      prefix: _calibrating ? null : _prefix(l10n.measDepthLabel.trim()),
      onSubmitted: (_) => _submit(),
    );
    return _alert(
      key: ValueKey(
          _calibrating ? 'pdf-cupertino-calibrate' : 'pdf-cupertino-depth'),
      title: _calibrating ? l10n.measCalibrateScale : l10n.measVolumeDepth,
      content: [
        if (_calibrating) _caption(context, l10n.measLineRepresents),
        Row(children: [
          Expanded(child: field),
          if (_calibrating)
            _UnitButton(
              key: const ValueKey('pdf-calibrate-unit'),
              presenter: widget.presenter,
              value: _unit,
              units: pdfScaleUnits,
              onChanged: (unit) => setState(() => _unit = unit),
            )
          else if (_unit.isNotEmpty) ...[
            const SizedBox(width: 8),
            Text(_unit),
          ],
        ]),
      ],
      actions: _actions(context,
          label: _calibrating ? l10n.ok : l10n.measMeasure,
          onSubmit: _submit,
          submitKey: ValueKey(
              _calibrating ? 'pdf-calibrate-apply' : 'pdf-depth-apply')),
    );
  }
}

// ---- pages --------------------------------------------------------------------

/// [PdfCupertinoPresenter.pageRange]'s prompt.
class CupertinoPageRangePrompt extends StatefulWidget {
  /// Asks for [request]'s range.
  const CupertinoPageRangePrompt({super.key, required this.request});

  /// What to ask.
  final PdfPageRangeRequest request;

  @override
  State<CupertinoPageRangePrompt> createState() =>
      _CupertinoPageRangePromptState();
}

class _CupertinoPageRangePromptState extends State<CupertinoPageRangePrompt> {
  int get _count => widget.request.pageCount;
  late final _from = TextEditingController(
      text: '${(widget.request.initialStart ?? 0).clamp(0, _count - 1) + 1}');
  late final _to = TextEditingController(
      text:
          '${(widget.request.initialEnd ?? _count - 1).clamp(0, _count - 1) + 1}');
  String? _error;

  @override
  void dispose() {
    _from.dispose();
    _to.dispose();
    super.dispose();
  }

  int? _parse(TextEditingController field) {
    final n = int.tryParse(field.text.trim());
    if (n == null || n < 1 || n > _count) return null;
    return n - 1;
  }

  void _submit() {
    final start = _parse(_from);
    final end = _parse(_to);
    if (start == null || end == null) {
      setState(() => _error = pdfL10n(context).pageRangeErrorBounds(_count));
      return;
    }
    if (end < start) {
      setState(() => _error = pdfL10n(context).pageRangeErrorOrder);
      return;
    }
    Navigator.of(context).pop((start: start, end: end));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = pdfL10n(context);
    return _alert(
      key: const ValueKey('pdf-page-range-dialog'),
      title: widget.request.title ?? l10n.pageRangeExportTitle,
      content: [
        _caption(context, l10n.pageRangePageCount(_count)),
        _field(
          key: const ValueKey('pdf-page-range-from'),
          controller: _from,
          prefix: _prefix(l10n.pageRangeFrom),
          keyboardType: TextInputType.number,
          digitsOnly: true,
          textAlign: TextAlign.end,
          onSubmitted: (_) => _submit(),
        ),
        const SizedBox(height: 8),
        _field(
          key: const ValueKey('pdf-page-range-to'),
          controller: _to,
          prefix: _prefix(l10n.pageRangeTo),
          keyboardType: TextInputType.number,
          digitsOnly: true,
          textAlign: TextAlign.end,
          onSubmitted: (_) => _submit(),
        ),
        if (_error != null) _errorText(context, _error!),
      ],
      actions: _actions(context,
          label: widget.request.confirmLabel ?? l10n.pageRangeExportConfirm,
          onSubmit: _submit,
          submitKey: const ValueKey('pdf-page-range-confirm'),
          cancelKey: const ValueKey('pdf-page-range-cancel')),
    );
  }
}

/// [PdfCupertinoPresenter.splitRanges]'s prompt.
class CupertinoSplitPrompt extends StatefulWidget {
  /// Asks how to split [request]'s document.
  const CupertinoSplitPrompt({super.key, required this.request});

  /// What to ask.
  final PdfSplitRangesRequest request;

  @override
  State<CupertinoSplitPrompt> createState() => _CupertinoSplitPromptState();
}

class _CupertinoSplitPromptState extends State<CupertinoSplitPrompt> {
  final _input = TextEditingController();
  var _invalid = false;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _submit() {
    try {
      Navigator.of(context).pop(PdfSplitter.parseRanges(_input.text,
          pageCount: widget.request.pageCount));
    } on FormatException {
      setState(() => _invalid = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = pdfL10n(context);
    final count = widget.request.pageCount;
    return _alert(
      key: const ValueKey('pdf-split-dialog'),
      title: l10n.splitTitle,
      content: [
        _caption(context, l10n.pageRangePageCount(count)),
        _caption(context, l10n.splitHelp),
        _field(
          key: const ValueKey('pdf-split-ranges'),
          controller: _input,
          autofocus: true,
          placeholder: '1-3, 7, 10-12',
          onSubmitted: (_) => _submit(),
          onChanged: (_) {
            if (_invalid) setState(() => _invalid = false);
          },
        ),
        if (_invalid) _errorText(context, l10n.splitInvalidRanges(count)),
      ],
      actions: _actions(context,
          label: l10n.splitConfirm,
          onSubmit: _submit,
          submitKey: const ValueKey('pdf-split-confirm'),
          cancelKey: const ValueKey('pdf-split-cancel')),
    );
  }
}
