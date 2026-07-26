import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/pdf_l10n.dart';

/// The value-entry formats [PdfColorPicker] can show: hex (the default),
/// RGB (0–255), HSL (degrees and percentages), and CMYK (percentages -
/// a naive device conversion for entry and display; the committed color
/// is still RGB, no color management is applied).
enum PdfColorFormat {
  hex('HEX'),
  rgb('RGB'),
  hsl('HSL'),
  cmyk('CMYK');

  const PdfColorFormat(this.label);

  /// The switcher's display name.
  final String label;
}

/// A compact full-spectrum color picker: a saturation/value area, a hue
/// slider, a value row - hex, RGB, HSL, or CMYK, switchable - kept in
/// sync, and a grid of quick-pick swatches (a fixed palette plus, when
/// supplied, the colours recently chosen and the colours already used in
/// the document). Annotation opacity is a separate controller property,
/// so the picker deals in opaque colors.
///
/// Used by [showPdfColorPicker]; embed it directly for custom chrome.
class PdfColorPicker extends StatefulWidget {
  const PdfColorPicker({
    super.key,
    required this.color,
    required this.onChanged,
    this.initialFormat = PdfColorFormat.hex,
    this.onFormatChanged,
    this.swatches = defaultSwatches,
    this.recentColors = const [],
    this.documentColors = const [],
  });

  final Color color;
  final ValueChanged<Color> onChanged;

  /// The value row's starting format; the user can switch from there.
  final PdfColorFormat initialFormat;

  /// Reports format switches so the host can persist the choice (see
  /// [showPdfColorPicker]).
  final ValueChanged<PdfColorFormat>? onFormatChanged;

  /// The fixed palette shown in the "Palette" swatch grid. Defaults to
  /// [defaultSwatches]; pass an empty list to hide the row.
  final List<Color> swatches;

  /// Colours the user picked recently, most-recent first - shown in a
  /// "Recent" grid when non-empty. See `PdfEditingPreferences.recentColors`.
  final List<Color> recentColors;

  /// Colours already used in the open document (annotation strokes and
  /// fills) - shown in an "In document" grid when non-empty.
  final List<Color> documentColors;

  /// A general-purpose palette: a grayscale ramp plus a spread of hues.
  /// Alpha is ignored - the picker deals in opaque colours.
  static const defaultSwatches = [
    Color(0xFF000000),
    Color(0xFF5F6368),
    Color(0xFF9AA0A6),
    Color(0xFFDADCE0),
    Color(0xFFFFFFFF),
    Color(0xFFD32F2F),
    Color(0xFFE53935),
    Color(0xFFF4511E),
    Color(0xFFFB8C00),
    Color(0xFFFDD835),
    Color(0xFFC0CA33),
    Color(0xFF43A047),
    Color(0xFF00897B),
    Color(0xFF1E88E5),
    Color(0xFF3949AB),
    Color(0xFF8E24AA),
    Color(0xFFD81B60),
    Color(0xFF6D4C41),
  ];

  @override
  State<PdfColorPicker> createState() => _PdfColorPickerState();
}

class _PdfColorPickerState extends State<PdfColorPicker> {
  late HSVColor _hsv = HSVColor.fromColor(widget.color);
  late PdfColorFormat _format = widget.initialFormat;
  late final TextEditingController _hex =
      TextEditingController(text: _hexOf(widget.color));
  late final List<TextEditingController> _channels =
      List.generate(4, (_) => TextEditingController());

  static String _hexOf(Color color) => (color.toARGB32() & 0xFFFFFF)
      .toRadixString(16)
      .toUpperCase()
      .padLeft(6, '0');

  Color get _color => _hsv.toColor().withValues(alpha: 1);

  static const _labels = {
    PdfColorFormat.rgb: ['R', 'G', 'B'],
    PdfColorFormat.hsl: ['H', 'S', 'L'],
    PdfColorFormat.cmyk: ['C', 'M', 'Y', 'K'],
  };

  /// Each channel's maximum, defining both the parse clamp and the
  /// field's digit budget.
  static const _maxima = {
    PdfColorFormat.rgb: [255, 255, 255],
    PdfColorFormat.hsl: [360, 100, 100],
    PdfColorFormat.cmyk: [100, 100, 100, 100],
  };

  @override
  void initState() {
    super.initState();
    _syncFields();
  }

  @override
  void dispose() {
    _hex.dispose();
    for (final channel in _channels) {
      channel.dispose();
    }
    super.dispose();
  }

  static List<int> _valuesOf(PdfColorFormat format, Color color) {
    switch (format) {
      case PdfColorFormat.rgb:
        return [
          (color.r * 255).round(),
          (color.g * 255).round(),
          (color.b * 255).round(),
        ];
      case PdfColorFormat.hsl:
        final hsl = HSLColor.fromColor(color);
        return [
          hsl.hue.round() % 360,
          (hsl.saturation * 100).round(),
          (hsl.lightness * 100).round(),
        ];
      case PdfColorFormat.cmyk:
        final k = 1 - math.max(color.r, math.max(color.g, color.b));
        if (k > 1 - 1e-6) return [0, 0, 0, 100];
        int part(double channel) =>
            (((1 - channel - k) / (1 - k)) * 100).round();
        return [part(color.r), part(color.g), part(color.b), (k * 100).round()];
      case PdfColorFormat.hex:
        throw ArgumentError('hex has no channels');
    }
  }

  static Color _colorOf(PdfColorFormat format, List<int> values) {
    switch (format) {
      case PdfColorFormat.rgb:
        return Color.fromARGB(255, values[0], values[1], values[2]);
      case PdfColorFormat.hsl:
        return HSLColor.fromAHSL(
                1, values[0] % 360.0, values[1] / 100, values[2] / 100)
            .toColor();
      case PdfColorFormat.cmyk:
        int channel(int part) =>
            ((1 - part / 100) * (1 - values[3] / 100) * 255).round();
        return Color.fromARGB(
            255, channel(values[0]), channel(values[1]), channel(values[2]));
      case PdfColorFormat.hex:
        throw ArgumentError('hex has no channels');
    }
  }

  /// Writes the current color into the visible value fields. Called for
  /// model changes the fields didn't cause (SV/hue drags, format
  /// switches) - never while the user is typing in them.
  void _syncFields() {
    if (_format == PdfColorFormat.hex) {
      _hex.text = _hexOf(_color);
      return;
    }
    final values = _valuesOf(_format, _color);
    for (var i = 0; i < values.length; i++) {
      _channels[i].text = '${values[i]}';
    }
  }

  /// From the SV area or hue slider: update the model and the fields.
  void _setHsv(HSVColor hsv) {
    setState(() => _hsv = hsv);
    _syncFields();
    widget.onChanged(_color);
  }

  void _setHex(String text) {
    if (text.length != 6) return;
    final value = int.tryParse(text, radix: 16);
    if (value == null) return;
    setState(() => _hsv = HSVColor.fromColor(Color(0xFF000000 | value)));
    widget.onChanged(_color);
  }

  /// From a swatch tap: adopt the swatch's (opaque) colour into the model
  /// and refresh the SV area, hue slider, and value fields.
  void _selectSwatch(Color color) {
    setState(() => _hsv = HSVColor.fromColor(color.withValues(alpha: 1)));
    _syncFields();
    widget.onChanged(_color);
  }

  /// Any channel edit: parse the whole visible row (the other fields
  /// already show their values). Incomplete input - an emptied field
  /// mid-edit - leaves the model alone.
  void _setChannels() {
    final maxima = _maxima[_format]!;
    final values = <int>[];
    for (var i = 0; i < maxima.length; i++) {
      final value = int.tryParse(_channels[i].text);
      if (value == null) return;
      values.add(value.clamp(0, maxima[i]));
    }
    setState(() => _hsv = HSVColor.fromColor(_colorOf(_format, values)));
    widget.onChanged(_color);
  }

  void _switchFormat(PdfColorFormat format) {
    if (format == _format) return;
    setState(() => _format = format);
    _syncFields();
    widget.onFormatChanged?.call(format);
  }

  Widget _valueFields(BuildContext context) {
    if (_format == PdfColorFormat.hex) {
      return TextField(
        key: const ValueKey('pdf-color-hex'),
        controller: _hex,
        onChanged: _setHex,
        maxLength: 6,
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp('[0-9a-fA-F]')),
        ],
        decoration: const InputDecoration(
          prefixText: '#',
          counterText: '',
          isDense: true,
          border: OutlineInputBorder(),
        ),
      );
    }
    final labels = _labels[_format]!;
    final maxima = _maxima[_format]!;
    return Row(children: [
      for (var i = 0; i < labels.length; i++) ...[
        if (i > 0) const SizedBox(width: 4),
        Expanded(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              key: ValueKey('pdf-color-channel-$i'),
              controller: _channels[i],
              onChanged: (_) => _setChannels(),
              maxLength: '${maxima[i]}'.length,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                counterText: '',
                isDense: true,
                // zero side padding: four CMYK fields share ~130px, and
                // a centered three-digit value needs the full box
                contentPadding: EdgeInsets.symmetric(vertical: 9),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 2),
            Text(labels[i], style: Theme.of(context).textTheme.labelSmall),
          ]),
        ),
      ],
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 260,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SaturationValueArea(hsv: _hsv, onChanged: _setHsv),
          const SizedBox(height: 12),
          _HueSlider(hsv: _hsv, onChanged: _setHsv),
          const SizedBox(height: 12),
          Row(children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: _color,
                shape: BoxShape.circle,
                border:
                    Border.all(color: Theme.of(context).colorScheme.outline),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(child: _valueFields(context)),
            const SizedBox(width: 8),
            // channel rows carry labels below the fields; pin the
            // switcher to the field row's height so it lines up
            SizedBox(
              height: 38,
              child: PopupMenuButton<PdfColorFormat>(
                key: const ValueKey('pdf-color-format'),
                tooltip: pdfL10n(context).colorColorFormat,
                initialValue: _format,
                onSelected: _switchFormat,
                itemBuilder: (context) => [
                  for (final format in PdfColorFormat.values)
                    PopupMenuItem(value: format, child: Text(format.label)),
                ],
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(_format.label,
                        style: Theme.of(context).textTheme.labelMedium),
                    const Icon(Icons.arrow_drop_down, size: 18),
                  ]),
                ),
              ),
            ),
          ]),
          ..._gridSections(context),
        ],
      ),
    );
  }

  /// The swatch grids shown below the value row: the fixed palette, then
  /// (when supplied) recents and the document's own colours. Each is a
  /// labelled [_SwatchGrid]; empty inputs drop out entirely.
  List<Widget> _gridSections(BuildContext context) {
    final currentRgb = _color.toARGB32() & 0xFFFFFF;
    final l10n = pdfL10n(context);
    final sections = <(String, String, List<Color>)>[
      (l10n.colorPalette, 'palette', widget.swatches),
      (l10n.colorRecent, 'recent', widget.recentColors),
      (l10n.colorInDocument, 'document', widget.documentColors),
    ];
    final grids = <Widget>[];
    for (final (label, keyPart, colors) in sections) {
      if (colors.isEmpty) continue;
      grids
        ..add(const SizedBox(height: 12))
        ..add(_SwatchGrid(
          key: ValueKey('pdf-color-grid-$keyPart'),
          label: label,
          keyPart: keyPart,
          colors: colors,
          selectedRgb: currentRgb,
          onSelected: _selectSwatch,
        ));
    }
    return grids;
  }
}

/// A labelled row of quick-pick colour swatches that wraps to fit the
/// picker's width. Deduplicates by RGB (alpha is ignored) so a colour
/// never appears twice in one grid, and rings the swatch matching the
/// picker's current colour.
class _SwatchGrid extends StatelessWidget {
  const _SwatchGrid({
    super.key,
    required this.label,
    required this.keyPart,
    required this.colors,
    required this.selectedRgb,
    required this.onSelected,
  });

  final String label;
  final String keyPart;
  final List<Color> colors;
  final int selectedRgb;
  final ValueChanged<Color> onSelected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final seen = <int>{};
    final swatches = <Widget>[];
    for (final color in colors) {
      final rgb = color.toARGB32() & 0xFFFFFF;
      if (!seen.add(rgb)) continue;
      final hex = rgb.toRadixString(16).toUpperCase().padLeft(6, '0');
      swatches.add(Tooltip(
        message: '#$hex',
        child: InkWell(
          key: ValueKey('pdf-color-swatch-$keyPart-$hex'),
          onTap: () => onSelected(Color(0xFF000000 | rgb)),
          customBorder: const CircleBorder(),
          child: Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: Color(0xFF000000 | rgb),
              shape: BoxShape.circle,
              border: Border.all(
                color: rgb == selectedRgb ? scheme.primary : scheme.outline,
                width: rgb == selectedRgb ? 3 : 1,
              ),
            ),
          ),
        ),
      ));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelSmall),
        const SizedBox(height: 6),
        Wrap(spacing: 6, runSpacing: 6, children: swatches),
      ],
    );
  }
}

/// The square: saturation left→right, value bottom→top, at the current hue.
class _SaturationValueArea extends StatelessWidget {
  const _SaturationValueArea({required this.hsv, required this.onChanged});

  final HSVColor hsv;
  final ValueChanged<HSVColor> onChanged;

  void _pick(Offset position, Size size) {
    onChanged(hsv
        .withSaturation((position.dx / size.width).clamp(0.0, 1.0))
        .withValue(1 - (position.dy / size.height).clamp(0.0, 1.0)));
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 160,
      child: LayoutBuilder(builder: (context, constraints) {
        final size = constraints.biggest;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanDown: (d) => _pick(d.localPosition, size),
          onPanUpdate: (d) => _pick(d.localPosition, size),
          child: CustomPaint(
            painter: _SaturationValuePainter(hsv),
            size: size,
          ),
        );
      }),
    );
  }
}

class _SaturationValuePainter extends CustomPainter {
  const _SaturationValuePainter(this.hsv);

  final HSVColor hsv;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final hue = HSVColor.fromAHSV(1, hsv.hue, 1, 1).toColor();
    canvas
      ..drawRect(
          rect,
          Paint()
            ..shader =
                LinearGradient(colors: [Colors.white, hue]).createShader(rect))
      ..drawRect(
          rect,
          Paint()
            ..shader = const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.transparent, Colors.black],
            ).createShader(rect));
    final thumb =
        Offset(hsv.saturation * size.width, (1 - hsv.value) * size.height);
    canvas
      ..drawCircle(
          thumb, 8, Paint()..color = hsv.toColor().withValues(alpha: 1))
      ..drawCircle(
          thumb,
          8,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = Colors.white);
  }

  @override
  bool shouldRepaint(_SaturationValuePainter old) => old.hsv != hsv;
}

class _HueSlider extends StatelessWidget {
  const _HueSlider({required this.hsv, required this.onChanged});

  final HSVColor hsv;
  final ValueChanged<HSVColor> onChanged;

  void _pick(Offset position, Size size) {
    onChanged(
        hsv.withHue((position.dx / size.width).clamp(0.0, 1.0) * 360 % 360));
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 20,
      child: LayoutBuilder(builder: (context, constraints) {
        final size = constraints.biggest;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanDown: (d) => _pick(d.localPosition, size),
          onPanUpdate: (d) => _pick(d.localPosition, size),
          child: CustomPaint(painter: _HuePainter(hsv.hue), size: size),
        );
      }),
    );
  }
}

class _HuePainter extends CustomPainter {
  const _HuePainter(this.hue);

  final double hue;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(10)),
        Paint()
          ..shader = LinearGradient(colors: [
            for (var h = 0; h <= 360; h += 60)
              HSVColor.fromAHSV(1, h % 360.0, 1, 1).toColor(),
          ]).createShader(rect));
    final x = hue / 360 * size.width;
    canvas
      ..drawCircle(Offset(x, size.height / 2), 8,
          Paint()..color = HSVColor.fromAHSV(1, hue, 1, 1).toColor())
      ..drawCircle(
          Offset(x, size.height / 2),
          8,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = Colors.white);
  }

  @override
  bool shouldRepaint(_HuePainter old) => old.hue != hue;
}

/// Shows [PdfColorPicker] in a dialog. Returns the chosen color, or null
/// when dismissed.
///
/// Pass [initialFormat]/[onFormatChanged] to keep the value row's format
/// across openings - the stock chrome wires them to
/// `PdfEditingPreferences.colorPickerFormat` so the choice persists on
/// the device. [recentColors] and [documentColors] feed the picker's
/// quick-pick grids (see [PdfColorPicker]); `pickEditingColor` wires
/// them from the controller and preferences.
Future<Color?> showPdfColorPicker(
  BuildContext context, {
  required Color initial,
  PdfColorFormat initialFormat = PdfColorFormat.hex,
  ValueChanged<PdfColorFormat>? onFormatChanged,
  List<Color> recentColors = const [],
  List<Color> documentColors = const [],
}) {
  var current = initial;
  return showDialog<Color>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(pdfL10n(context).colorColorTitle),
      content: SingleChildScrollView(
        child: PdfColorPicker(
          color: initial,
          onChanged: (color) => current = color,
          initialFormat: initialFormat,
          onFormatChanged: onFormatChanged,
          recentColors: recentColors,
          documentColors: documentColors,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(pdfL10n(context).cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(current),
          child: Text(pdfL10n(context).ok),
        ),
      ],
    ),
  );
}
