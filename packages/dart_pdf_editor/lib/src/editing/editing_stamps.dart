import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:pdf_document/pdf_document.dart';

import '../l10n/pdf_l10n.dart';
import 'editing_color_picker.dart';
import 'editing_controller.dart';
import 'editing_signature.dart';
import 'text_prompt.dart';

String _twoDigits(int value) => value.toString().padLeft(2, '0');

String _fourDigits(int value) => value.toString().padLeft(4, '0');

const _monthNames = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// Date formats used by the built-in `{{date}}` and `{{datetime}}` stamp
/// template fields.
enum PdfStampDateFormat {
  iso,
  dayMonthYear,
  monthDayYear,
  dayMonthNameYear,
  monthNameDayYear;

  String format(DateTime value) {
    final year = _fourDigits(value.year);
    final month = _twoDigits(value.month);
    final day = _twoDigits(value.day);
    final monthName = _monthNames[value.month - 1];
    return switch (this) {
      PdfStampDateFormat.iso => '$year-$month-$day',
      PdfStampDateFormat.dayMonthYear => '$day/$month/$year',
      PdfStampDateFormat.monthDayYear => '$month/$day/$year',
      PdfStampDateFormat.dayMonthNameYear => '${value.day} $monthName $year',
      PdfStampDateFormat.monthNameDayYear => '$monthName ${value.day}, $year',
    };
  }
}

/// Time formats used by the built-in `{{time}}` and `{{datetime}}` stamp
/// template fields.
enum PdfStampTimeFormat {
  twentyFourHour,
  twelveHour,
  twentyFourHourSeconds,
  twelveHourSeconds;

  String format(DateTime value) {
    final hour = _twoDigits(value.hour);
    final minute = _twoDigits(value.minute);
    final second = _twoDigits(value.second);
    final suffix = value.hour < 12 ? 'AM' : 'PM';
    final hour12 = value.hour % 12 == 0 ? 12 : value.hour % 12;
    return switch (this) {
      PdfStampTimeFormat.twentyFourHour => '$hour:$minute',
      PdfStampTimeFormat.twelveHour => '$hour12:$minute $suffix',
      PdfStampTimeFormat.twentyFourHourSeconds => '$hour:$minute:$second',
      PdfStampTimeFormat.twelveHourSeconds => '$hour12:$minute:$second $suffix',
    };
  }
}

/// A reusable rubber stamp: visual template plus optional app metadata.
///
/// Custom stamps are saved on the local device through
/// [PdfEditingPreferences.customStamps], so they survive app restarts and
/// are shared across documents. Host apps can also supply non-persisted stamps
/// through [PdfEditingController.providedCustomStamps] or the editor shell's
/// custom-stamps parameter. The stamp tool places the
/// [PdfEditingController.activeStamp] with a tap; with none active it falls
/// back to the classic flow (drag a box, type the caption).
///
/// Serializes to JSON so [PdfEditingPreferences] can persist it.
class PdfCustomStamp {
  const PdfCustomStamp({
    required this.text,
    required this.color,
    this.template,
    this.type,
    this.tags = const [],
  });

  /// The caption drawn inside the stamp's rounded border.
  final String text;

  /// RGB border and caption color.
  final int color;

  /// Editable vector template for newer stamps. Null means this is a legacy
  /// text-only stamp and should be rendered with the classic appearance.
  final PdfStampTemplate? template;

  /// App-defined stamp kind, e.g. "Approval", "Audit", or "Tested".
  final String? type;

  /// App-defined labels for filtering, grouping, or reporting stamps.
  final List<String> tags;

  bool hasTag(String tag) {
    final normalized = tag.trim().toLowerCase();
    if (normalized.isEmpty) return false;
    return tags.any((value) => value.trim().toLowerCase() == normalized);
  }

  String encode() => jsonEncode({
        'text': text,
        'color': color,
        if (template != null) 'template': template!.toJson(),
        if (type != null && type!.trim().isNotEmpty) 'type': type,
        if (tags.isNotEmpty) 'tags': tags,
      });

  /// Parses [encode]'s output; null for anything malformed.
  static PdfCustomStamp? decode(String json) {
    try {
      final map = jsonDecode(json) as Map<String, dynamic>;
      return PdfCustomStamp(
        text: map['text'] as String,
        color: map['color'] as int,
        template: PdfStampTemplate.fromJson(map['template']),
        type: map['type'] is String ? map['type'] as String : null,
        tags: [
          if (map['tags'] is List)
            for (final tag in map['tags'] as List)
              if (tag is String && tag.trim().isNotEmpty) tag
        ],
      );
    } catch (_) {
      return null;
    }
  }

  @override
  bool operator ==(Object other) =>
      other is PdfCustomStamp &&
      other.text == text &&
      other.color == color &&
      other.template == template &&
      other.type == type &&
      _stringListEquals(other.tags, tags);

  @override
  int get hashCode => Object.hash(text, color, template, type,
      Object.hashAll(tags.map((tag) => tag.trim().toLowerCase())));
}

/// Saves user-managed custom stamps somewhere outside the editor package.
///
/// The stock picker passes only [PdfEditingController.savedCustomStamps];
/// host-provided stamps are managed by the host and are not exported here.
typedef PdfStampExportCallback = Future<void> Function(
  BuildContext context,
  List<PdfCustomStamp> stamps,
);

/// Loads user-managed custom stamps from somewhere outside the editor package.
///
/// Return null when the user cancels. Returned stamps are merged into the
/// saved custom stamp list, skipping exact duplicates already shown.
typedef PdfStampImportCallback = Future<List<PdfCustomStamp>?> Function(
  BuildContext context,
);

/// Shows the stamp picker: choose the stamp the stamp tool places,
/// create a new one, or delete saved ones. Selections apply directly to
/// [controller].
Future<void> showPdfStampPicker(BuildContext context,
        {required PdfEditingController controller,
        PdfImagePicker? imagePicker,
        PdfStampExportCallback? onExportStamps,
        PdfStampImportCallback? onImportStamps}) =>
    showDialog<void>(
      context: context,
      builder: (context) => PdfStampPickerDialog(
        controller: controller,
        imagePicker: imagePicker,
        onExportStamps: onExportStamps,
        onImportStamps: onImportStamps,
      ),
    );

/// The stamp picker dialog behind [showPdfStampPicker].
class PdfStampPickerDialog extends StatelessWidget {
  const PdfStampPickerDialog({
    super.key,
    required this.controller,
    this.imagePicker,
    this.onExportStamps,
    this.onImportStamps,
  });

  final PdfEditingController controller;
  final PdfImagePicker? imagePicker;
  final PdfStampExportCallback? onExportStamps;
  final PdfStampImportCallback? onImportStamps;

  Future<void> _create(BuildContext context) async {
    final created = await showPdfStampEditor(context,
        fields: controller.stampTemplateFieldNames, imagePicker: imagePicker);
    if (created == null) return;
    controller.saveCustomStamp(created);
    controller.activeStamp = created;
    if (context.mounted) Navigator.of(context).pop();
  }

  Future<void> _edit(BuildContext context, PdfCustomStamp stamp) async {
    final edited = await showPdfStampEditor(
      context,
      fields: controller.stampTemplateFieldNames,
      imagePicker: imagePicker,
      initial: stamp,
    );
    if (edited == null) return;
    controller.replaceCustomStamp(stamp, edited);
  }

  Future<void> _export(BuildContext context) async {
    final stamps = controller.savedCustomStamps;
    if (stamps.isEmpty) return;
    await onExportStamps?.call(context, stamps);
  }

  Future<void> _import(BuildContext context) async {
    final imported = await onImportStamps?.call(context);
    if (imported == null || imported.isEmpty) return;
    final existing = controller.customStamps.toSet();
    PdfCustomStamp? firstAdded;
    for (final stamp in imported) {
      if (existing.contains(stamp)) continue;
      controller.saveCustomStamp(stamp);
      existing.add(stamp);
      firstAdded ??= stamp;
    }
    if (firstAdded != null) controller.activeStamp = firstAdded;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(pdfL10n(context).stampStamps),
      content: SizedBox(
        width: 340,
        child: ListenableBuilder(
          listenable: controller,
          builder: (context, _) => SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final stamp in controller.customStamps)
                  ListTile(
                    title: Align(
                      alignment: Alignment.centerLeft,
                      child: PdfStampPreview(
                          stamp: stamp,
                          templateValues:
                              controller.resolvedStampTemplateValues),
                    ),
                    selected: stamp == controller.activeStamp,
                    onTap: () {
                      controller.activeStamp = stamp;
                      Navigator.of(context).pop();
                    },
                    subtitle: _stampDetail(stamp) == null
                        ? null
                        : Text(_stampDetail(stamp)!),
                    trailing: controller.isSavedCustomStamp(stamp)
                        ? Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.edit_outlined),
                                tooltip: pdfL10n(context).stampEditStamp,
                                onPressed: () => _edit(context, stamp),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline),
                                tooltip: pdfL10n(context).stampDeleteStamp,
                                onPressed: () =>
                                    controller.removeCustomStamp(stamp),
                              ),
                            ],
                          )
                        : null,
                  ),
                const Divider(height: 24),
                _StampDateTimeFormatControls(controller: controller),
              ],
            ),
          ),
        ),
      ),
      actions: [
        if (onImportStamps != null)
          TextButton.icon(
            key: const ValueKey('pdf-stamp-import'),
            onPressed: () => _import(context),
            icon: const Icon(Icons.file_upload_outlined),
            label: Text(pdfL10n(context).stampImport),
          ),
        if (onExportStamps != null)
          ListenableBuilder(
            listenable: controller,
            builder: (context, _) => TextButton.icon(
              key: const ValueKey('pdf-stamp-export'),
              onPressed: controller.savedCustomStamps.isEmpty
                  ? null
                  : () => _export(context),
              icon: const Icon(Icons.file_download_outlined),
              label: Text(pdfL10n(context).stampExport),
            ),
          ),
        TextButton(
          onPressed: () => _create(context),
          child: Text(pdfL10n(context).stampNewStamp),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(pdfL10n(context).close),
        ),
      ],
    );
  }
}

class _StampDateTimeFormatControls extends StatelessWidget {
  const _StampDateTimeFormatControls({required this.controller});

  final PdfEditingController controller;

  static String _timePreview(PdfStampTimeFormat format, DateTime sample) {
    final suffix = switch (format) {
      PdfStampTimeFormat.twentyFourHour ||
      PdfStampTimeFormat.twentyFourHourSeconds =>
        '24 hr',
      PdfStampTimeFormat.twelveHour ||
      PdfStampTimeFormat.twelveHourSeconds =>
        '12 hr',
    };
    return '${format.format(sample)} ($suffix)';
  }

  @override
  Widget build(BuildContext context) {
    final sample = controller.stampTemplateClock();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        KeyedSubtree(
          key: ValueKey(
              'pdf-stamp-date-format-field-${controller.preferences.stampDateFormat.name}'),
          child: DropdownButtonFormField<PdfStampDateFormat>(
            key: const ValueKey('pdf-stamp-date-format'),
            initialValue: controller.preferences.stampDateFormat,
            decoration:
                InputDecoration(labelText: pdfL10n(context).stampDateFormat),
            items: [
              for (final format in PdfStampDateFormat.values)
                DropdownMenuItem<PdfStampDateFormat>(
                  key: ValueKey('pdf-stamp-date-format-${format.name}'),
                  value: format,
                  child: Text(format.format(sample)),
                ),
            ],
            onChanged: (value) {
              if (value != null) controller.preferences.stampDateFormat = value;
            },
          ),
        ),
        const SizedBox(height: 8),
        KeyedSubtree(
          key: ValueKey(
              'pdf-stamp-time-format-field-${controller.preferences.stampTimeFormat.name}'),
          child: DropdownButtonFormField<PdfStampTimeFormat>(
            key: const ValueKey('pdf-stamp-time-format'),
            initialValue: controller.preferences.stampTimeFormat,
            decoration:
                InputDecoration(labelText: pdfL10n(context).stampTimeFormat),
            items: [
              for (final format in PdfStampTimeFormat.values)
                DropdownMenuItem<PdfStampTimeFormat>(
                  key: ValueKey('pdf-stamp-time-format-${format.name}'),
                  value: format,
                  child: Text(_timePreview(format, sample)),
                ),
            ],
            onChanged: (value) {
              if (value != null) controller.preferences.stampTimeFormat = value;
            },
          ),
        ),
      ],
    );
  }
}

/// Shows the stamp creation dialog; resolves to the new stamp, or null
/// on cancel. Saving it is the caller's job (the picker saves through
/// the controller).
Future<PdfCustomStamp?> showPdfStampEditor(BuildContext context,
        {Iterable<String> fields =
            PdfEditingController.stampTemplateBuiltinFields,
        PdfImagePicker? imagePicker,
        PdfCustomStamp? initial}) =>
    showDialog<PdfCustomStamp>(
      context: context,
      builder: (context) => PdfStampEditorDialog(
        fields: fields,
        imagePicker: imagePicker,
        initial: initial,
      ),
    );

/// The stamp creation dialog behind [showPdfStampEditor]: caption field,
/// color choice, and a live preview matching the placed appearance.
class PdfStampEditorDialog extends StatefulWidget {
  const PdfStampEditorDialog({
    super.key,
    this.fields = const [],
    this.imagePicker,
    this.initial,
  });

  final Iterable<String> fields;
  final PdfImagePicker? imagePicker;
  final PdfCustomStamp? initial;

  @override
  State<PdfStampEditorDialog> createState() => _PdfStampEditorDialogState();
}

class _PdfStampEditorDialogState extends State<PdfStampEditorDialog> {
  static const _inks = [0xC03030, 0x2E7D32, 0x1A3E8C, 0xEF6C00, 0x000000];

  late final TextEditingController _text;
  late final TextEditingController _width;
  late final TextEditingController _height;
  late List<PdfStampTemplateComponent> _components;
  late final List<String> _fields;
  int? _selected;
  late int _color;
  late double _templateWidth;
  late double _templateHeight;

  @override
  void initState() {
    super.initState();
    _fields = _normalizeFields(widget.fields);
    final initial = widget.initial;
    final template = initial?.template ??
        PdfStampTemplate.text(
          initial?.text ?? 'APPROVED',
          initial?.color ?? _inks.first,
        );
    _templateWidth = template.width;
    _templateHeight = template.height;
    _components = List.of(template.components);
    _selected = _initialSelection(_components);
    _color = initial?.color ?? _primaryColor;
    final selected = _selectedComponent;
    _text = TextEditingController(
      text: selected?.type == PdfStampTemplateComponentType.text
          ? selected!.text
          : initial?.text ?? 'APPROVED',
    );
    _width = TextEditingController(text: _templateWidth.round().toString());
    _height = TextEditingController(text: _templateHeight.round().toString());
  }

  @override
  void dispose() {
    _text.dispose();
    _width.dispose();
    _height.dispose();
    super.dispose();
  }

  PdfStampTemplateComponent? get _selectedComponent =>
      _selected == null ? null : _components[_selected!];

  int? _initialSelection(List<PdfStampTemplateComponent> components) {
    for (var i = 0; i < components.length; i++) {
      if (components[i].type == PdfStampTemplateComponentType.text) return i;
    }
    return components.isEmpty ? null : 0;
  }

  String get _caption {
    for (final component in _components) {
      if (component.type == PdfStampTemplateComponentType.text &&
          component.text.trim().isNotEmpty) {
        return component.text.trim();
      }
    }
    return 'Custom stamp';
  }

  int get _primaryColor =>
      _components.isEmpty ? _color : _components.first.color;

  PdfStampTemplate get _template => PdfStampTemplate(
        width: _templateWidth,
        height: _templateHeight,
        components: List.unmodifiable(_components),
      );

  Size get _templateSize => Size(_templateWidth, _templateHeight);

  void _syncTextField(PdfStampTemplateComponent component) {
    if (component.type != PdfStampTemplateComponentType.text) return;
    _text.value = TextEditingValue(
      text: component.text,
      selection: TextSelection.collapsed(offset: component.text.length),
    );
  }

  void _select(int? index) {
    setState(() {
      _selected = index;
      final component = _selectedComponent;
      if (component != null) _syncTextField(component);
    });
  }

  void _replaceSelected(PdfStampTemplateComponent component) {
    final index = _selected;
    if (index == null) return;
    setState(() => _components[index] = component);
  }

  void _setTemplateSize({double? width, double? height}) {
    final nextWidth = (width ?? _templateWidth).clamp(80.0, 640.0).toDouble();
    final nextHeight =
        (height ?? _templateHeight).clamp(32.0, 640.0).toDouble();
    if (nextWidth == _templateWidth && nextHeight == _templateHeight) return;
    final sx = nextWidth / _templateWidth;
    final sy = nextHeight / _templateHeight;
    setState(() {
      _templateWidth = nextWidth;
      _templateHeight = nextHeight;
      _width.text = nextWidth.round().toString();
      _height.text = nextHeight.round().toString();
      _components = [
        for (final component in _components) _scaleComponent(component, sx, sy),
      ];
    });
  }

  PdfStampTemplateComponent _scaleComponent(
      PdfStampTemplateComponent component, double sx, double sy) {
    final scaled = component.copyWith(
      x: component.x * sx,
      y: component.y * sy,
      width: component.width * sx,
      height: component.height * sy,
    );
    final fontSize = component.fontSize;
    return fontSize == null
        ? scaled
        : scaled.copyWith(fontSize: fontSize * math.min(sx, sy));
  }

  void _commitSize() {
    final width = double.tryParse(_width.text.trim());
    final height = double.tryParse(_height.text.trim());
    _setTemplateSize(width: width, height: height);
    _width.text = _templateWidth.round().toString();
    _height.text = _templateHeight.round().toString();
  }

  void _insertField(String field) {
    final selected = _selectedComponent;
    if (selected?.type != PdfStampTemplateComponentType.text) return;
    final token = '{{$field}}';
    final value = _text.value;
    final selection = value.selection.isValid
        ? value.selection
        : TextSelection.collapsed(offset: value.text.length);
    final start = selection.start.clamp(0, value.text.length).toInt();
    final end = selection.end.clamp(0, value.text.length).toInt();
    final nextText = value.text.replaceRange(start, end, token);
    final offset = start + token.length;
    _text.value = TextEditingValue(
      text: nextText,
      selection: TextSelection.collapsed(offset: offset),
    );
    _replaceSelected(selected!.copyWith(text: nextText));
  }

  void _moveSelected(Offset delta) {
    final component = _selectedComponent;
    if (component == null) return;
    final x = (component.x + delta.dx)
        .clamp(0.0, _templateWidth - component.width)
        .toDouble();
    final y = (component.y + delta.dy)
        .clamp(0.0, _templateHeight - component.height)
        .toDouble();
    _replaceSelected(component.copyWith(x: x, y: y));
  }

  void _resizeSelected(_StampHandle handle, Offset delta) {
    final component = _selectedComponent;
    if (component == null) return;
    final minWidth =
        component.type == PdfStampTemplateComponentType.text ? 28.0 : 16.0;
    final minHeight =
        component.type == PdfStampTemplateComponentType.text ? 14.0 : 16.0;
    var left = component.x;
    var top = component.y;
    var right = component.x + component.width;
    var bottom = component.y + component.height;
    // Each handle moves only the edge(s) it owns; the opposite edge stays put,
    // clamped so the box keeps a minimum size and never leaves the template.
    if (handle.dx < 0) {
      left = (left + delta.dx).clamp(0.0, right - minWidth).toDouble();
    } else if (handle.dx > 0) {
      right =
          (right + delta.dx).clamp(left + minWidth, _templateWidth).toDouble();
    }
    if (handle.dy < 0) {
      top = (top + delta.dy).clamp(0.0, bottom - minHeight).toDouble();
    } else if (handle.dy > 0) {
      bottom = (bottom + delta.dy)
          .clamp(top + minHeight, _templateHeight)
          .toDouble();
    }
    _replaceSelected(component.copyWith(
      x: left,
      y: top,
      width: right - left,
      height: bottom - top,
    ));
  }

  void _setSelectedFont(PdfStandardFont font) {
    final component = _selectedComponent;
    if (component?.type != PdfStampTemplateComponentType.text) return;
    _replaceSelected(component!.copyWith(font: font));
  }

  void _setSelectedColor(int color) {
    setState(() {
      _color = color;
      final index = _selected;
      if (index != null) {
        _components[index] = _components[index].copyWith(color: color);
      }
    });
  }

  Future<void> _pickCustomColor() async {
    final picked = await showPdfColorPicker(
      context,
      initial: Color(0xFF000000 | _color),
    );
    if (!mounted || picked == null) return;
    _setSelectedColor(picked.toARGB32() & 0xFFFFFF);
  }

  void _addText() {
    const text = 'TEXT';
    final component = PdfStampTemplateComponent.text(
      x: 54,
      y: 36,
      width: 132,
      height: 28,
      text: text,
      color: _color,
      fontSize: 22,
    );
    setState(() {
      _components = [..._components, component];
      _selected = _components.length - 1;
      _syncTextField(component);
    });
  }

  void _addBox() {
    final component = PdfStampTemplateComponent.rectangle(
      x: 28,
      y: 22,
      width: 184,
      height: 52,
      color: _color,
      strokeWidth: 2,
      radius: 8,
    );
    setState(() {
      _components = [..._components, component];
      _selected = _components.length - 1;
    });
  }

  void _addCircle() {
    final diameter =
        math.min(64.0, math.min(_templateWidth, _templateHeight) * 0.65);
    final component = PdfStampTemplateComponent.ellipse(
      x: (_templateWidth - diameter) / 2,
      y: (_templateHeight - diameter) / 2,
      width: diameter,
      height: diameter,
      color: _color,
      strokeWidth: 2,
    );
    setState(() {
      _components = [..._components, component];
      _selected = _components.length - 1;
    });
  }

  Future<void> _addImage() async {
    final picker = widget.imagePicker;
    if (picker == null) return;
    final bytes = await picker(context);
    if (bytes == null || !mounted) return;
    final PdfEmbeddableImage image;
    try {
      image = PdfEmbeddableImage.decode(bytes);
    } catch (_) {
      return;
    }
    final aspect = image.height == 0 ? 1.0 : image.width / image.height;
    var width = math.min(96.0, _templateWidth * 0.55);
    var height = width / aspect;
    if (height > _templateHeight * 0.6) {
      height = _templateHeight * 0.6;
      width = height * aspect;
    }
    final component = PdfStampTemplateComponent.image(
      x: (_templateWidth - width) / 2,
      y: (_templateHeight - height) / 2,
      width: width,
      height: height,
      imageBytes: Uint8List.fromList(bytes),
    );
    setState(() {
      _components = [..._components, component];
      _selected = _components.length - 1;
    });
  }

  Future<void> _addSignature() async {
    final signature = await showPdfSignatureDialog(context);
    if (signature == null || !mounted) return;
    final aspect = signature.aspect > 0 ? signature.aspect : 2.0;
    var width = math.min(132.0, _templateWidth * 0.62);
    var height = width / aspect;
    if (height > _templateHeight * 0.55) {
      height = _templateHeight * 0.55;
      width = height * aspect;
    }
    final component = PdfStampTemplateComponent.signature(
      x: (_templateWidth - width) / 2,
      y: (_templateHeight - height) / 2,
      width: width,
      height: height,
      strokes: signature.strokes,
      pressures: signature.pressures,
      color: signature.color,
      strokeWidth: math.max(0.8, width / 75),
    );
    setState(() {
      _color = signature.color;
      _components = [..._components, component];
      _selected = _components.length - 1;
    });
  }

  void _deleteSelected() {
    final index = _selected;
    if (index == null || _components.length <= 1) return;
    setState(() {
      _components = [
        for (var i = 0; i < _components.length; i++)
          if (i != index) _components[i],
      ];
      _selected = math.min(index, _components.length - 1);
      final component = _selectedComponent;
      if (component != null) _syncTextField(component);
    });
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selectedComponent;
    final selectedIsText = selected?.type == PdfStampTemplateComponentType.text;
    return AlertDialog(
      title: Text(widget.initial == null
          ? pdfL10n(context).stampNewStampTitle
          : pdfL10n(context).stampEditStamp),
      content: SizedBox(
        width: 340,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _StampTemplateCanvas(
                key: const ValueKey('pdf-stamp-template-canvas'),
                templateSize: _templateSize,
                components: _components,
                selectedIndex: _selected,
                onSelect: _select,
                onMoveSelected: _moveSelected,
                onResizeSelected: _resizeSelected,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  SizedBox(
                    width: 92,
                    child: TextField(
                      key: const ValueKey('pdf-stamp-width'),
                      controller: _width,
                      keyboardType: TextInputType.number,
                      decoration:
                          InputDecoration(labelText: pdfL10n(context).stampWidth),
                      onSubmitted: (_) => _commitSize(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 92,
                    child: TextField(
                      key: const ValueKey('pdf-stamp-height'),
                      controller: _height,
                      keyboardType: TextInputType.number,
                      decoration:
                          InputDecoration(labelText: pdfL10n(context).stampHeight),
                      onSubmitted: (_) => _commitSize(),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: 300,
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        key: const ValueKey('pdf-stamp-text'),
                        controller: _text,
                        autofocus: true,
                        enabled: selectedIsText,
                        textCapitalization: TextCapitalization.characters,
                        decoration: InputDecoration(
                          labelText: selectedIsText
                              ? pdfL10n(context).stampSelectedText
                              : pdfL10n(context).stampSelectTextToEdit,
                        ),
                        onChanged: selectedIsText
                            ? (value) => _replaceSelected(
                                selected!.copyWith(text: value))
                            : null,
                      ),
                    ),
                    const SizedBox(width: 8),
                    PopupMenuButton<String>(
                      key: const ValueKey('pdf-stamp-field-menu'),
                      tooltip: pdfL10n(context).stampInsertField,
                      enabled: selectedIsText && _fields.isNotEmpty,
                      icon: const Icon(Icons.data_object),
                      onSelected: _insertField,
                      itemBuilder: (context) => [
                        for (final field in _fields)
                          PopupMenuItem<String>(
                            key: ValueKey('pdf-stamp-field-$field'),
                            value: field,
                            height: 34,
                            child: Text(_fieldLabel(field)),
                          ),
                      ],
                    ),
                    PopupMenuButton<PdfStandardFont>(
                      key: const ValueKey('pdf-stamp-font-menu'),
                      tooltip: pdfL10n(context).stampFont,
                      enabled: selectedIsText,
                      icon: const Icon(Icons.font_download_outlined),
                      initialValue: selectedIsText ? selected!.font : null,
                      onSelected: _setSelectedFont,
                      itemBuilder: (context) => [
                        for (final font in PdfStandardFont.values)
                          PopupMenuItem<PdfStandardFont>(
                            key: ValueKey('pdf-stamp-font-${font.name}'),
                            value: font,
                            height: 34,
                            child: Text(
                              _fontLabel(font),
                              style: TextStyle(
                                fontFamily: _uiFamily(font),
                                fontWeight: font.isBold
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                                fontStyle: font.isItalic
                                    ? FontStyle.italic
                                    : FontStyle.normal,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Row(children: [
                for (final ink in _inks)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: InkWell(
                      onTap: () => _setSelectedColor(ink),
                      customBorder: const CircleBorder(),
                      child: Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          color: Color(0xFF000000 | ink),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: _color == ink
                                ? Theme.of(context).colorScheme.primary
                                : Theme.of(context).colorScheme.outline,
                            width: _color == ink ? 3 : 1,
                          ),
                        ),
                      ),
                    ),
                  ),
                IconButton(
                  key: const ValueKey('pdf-stamp-color-custom'),
                  tooltip: pdfL10n(context).stampMoreColors,
                  icon: const Icon(Icons.color_lens_outlined),
                  style: IconButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    minimumSize: const Size(32, 32),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: _pickCustomColor,
                ),
              ]),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    key: const ValueKey('pdf-stamp-add-text'),
                    onPressed: _addText,
                    icon: const Icon(Icons.title),
                    label: Text(pdfL10n(context).stampText),
                  ),
                  OutlinedButton.icon(
                    key: const ValueKey('pdf-stamp-add-box'),
                    onPressed: _addBox,
                    icon: const Icon(Icons.crop_square),
                    label: Text(pdfL10n(context).stampBox),
                  ),
                  OutlinedButton.icon(
                    key: const ValueKey('pdf-stamp-add-circle'),
                    onPressed: _addCircle,
                    icon: const Icon(Icons.radio_button_unchecked),
                    label: Text(pdfL10n(context).stampCircle),
                  ),
                  OutlinedButton.icon(
                    key: const ValueKey('pdf-stamp-add-image'),
                    onPressed: widget.imagePicker == null ? null : _addImage,
                    icon: const Icon(Icons.image_outlined),
                    label: Text(pdfL10n(context).stampImage),
                  ),
                  OutlinedButton.icon(
                    key: const ValueKey('pdf-stamp-add-signature'),
                    onPressed: _addSignature,
                    icon: const Icon(Icons.draw),
                    label: Text(pdfL10n(context).stampSignature),
                  ),
                  IconButton(
                    key: const ValueKey('pdf-stamp-delete-component'),
                    onPressed: _components.length > 1 ? _deleteSelected : null,
                    icon: const Icon(Icons.delete_outline),
                    tooltip: pdfL10n(context).stampDeleteComponent,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(pdfL10n(context).cancel),
        ),
        FilledButton(
          onPressed: _components.isEmpty
              ? null
              : () {
                  final initial = widget.initial;
                  Navigator.of(context).pop(PdfCustomStamp(
                    text: _caption,
                    color: _primaryColor,
                    template: _template,
                    type: initial?.type,
                    tags: initial?.tags ?? const [],
                  ));
                },
          child: Text(pdfL10n(context).save),
        ),
      ],
    );
  }
}

/// Renders a stamp the way it will look on the page: bold caption inside
/// a rounded border, both in the stamp's color.
class PdfStampPreview extends StatelessWidget {
  const PdfStampPreview({
    super.key,
    required this.stamp,
    this.templateValues = const {},
  });

  final PdfCustomStamp stamp;
  final Map<String, String> templateValues;

  @override
  Widget build(BuildContext context) {
    final template = (stamp.template ??
            PdfStampTemplate.text(
                pdfResolveStampTemplateText(stamp.text, templateValues),
                stamp.color))
        .resolveText(templateValues);
    const maxWidth = 220.0;
    const maxHeight = 120.0;
    final scale =
        math.min(maxWidth / template.width, maxHeight / template.height);
    final width = template.width * scale;
    return SizedBox(
      width: width,
      height: template.height * scale,
      child: _StampTemplateSurface(
        templateSize: Size(template.width, template.height),
        components: template.components,
        selectedIndex: null,
        scheme: Theme.of(context).colorScheme,
        showChrome: false,
      ),
    );
  }
}

class _StampTemplateCanvas extends StatefulWidget {
  const _StampTemplateCanvas({
    super.key,
    required this.templateSize,
    required this.components,
    required this.selectedIndex,
    required this.onSelect,
    required this.onMoveSelected,
    required this.onResizeSelected,
  });

  final Size templateSize;
  final List<PdfStampTemplateComponent> components;
  final int? selectedIndex;
  final ValueChanged<int?> onSelect;
  final ValueChanged<Offset> onMoveSelected;
  final void Function(_StampHandle handle, Offset delta) onResizeSelected;

  @override
  State<_StampTemplateCanvas> createState() => _StampTemplateCanvasState();
}

/// Which sides of the selection a resize handle moves: -1 the left/top edge,
/// +1 the right/bottom edge, 0 leaves that axis anchored. (Template space, y
/// down.) Mirrors the on-page editing overlay's `_Handle` convention.
typedef _StampHandle = ({int dx, int dy});

/// The eight resize handles (four corners + four edge midpoints) that ring a
/// selected component, in the same order as the on-page overlay.
const List<_StampHandle> _stampHandles = [
  (dx: -1, dy: -1),
  (dx: 0, dy: -1),
  (dx: 1, dy: -1),
  (dx: -1, dy: 0),
  (dx: 1, dy: 0),
  (dx: -1, dy: 1),
  (dx: 0, dy: 1),
  (dx: 1, dy: 1),
];

/// Side length of a handle square as drawn on the component, in logical pixels.
const double _stampHandleSize = 9;

/// How close (logical pixels) a press must land to a handle to grab it. Matches
/// the overlay's forgiving target so scaling isn't finicky on touch.
const double _stampHandleHitRadius = 14;

/// The center of [handle] on [rect], in template space.
Offset _stampHandleCenter(Rect rect, _StampHandle handle) => Offset(
      rect.center.dx + handle.dx * rect.width / 2,
      rect.center.dy + handle.dy * rect.height / 2,
    );

enum _StampDragKind { move, resize }

class _StampTemplateCanvasState extends State<_StampTemplateCanvas> {
  _StampDragKind? _dragKind;
  _StampHandle? _dragHandle;
  Offset? _lastTemplatePoint;
  _StampDragKind? _pendingKind;
  _StampHandle? _pendingHandle;
  Offset _pendingDelta = Offset.zero;
  bool _pendingFrame = false;

  double _scale(Size size) => size.width / widget.templateSize.width;

  Offset _toTemplate(Offset local, Size size) {
    final scale = _scale(size);
    return Offset(local.dx / scale, local.dy / scale);
  }

  Rect _componentRect(PdfStampTemplateComponent c) =>
      Rect.fromLTWH(c.x, c.y, c.width, c.height);

  /// The resize handle whose forgiving hit target [local] (in logical pixels)
  /// falls within, or null. Handles ride the selected component only, and the
  /// test runs in logical pixels so the target stays the same size at any
  /// template zoom.
  _StampHandle? _handleAt(Offset local, Size size) {
    final selected = widget.selectedIndex;
    if (selected == null || selected >= widget.components.length) return null;
    final scale = _scale(size);
    final rect = _componentRect(widget.components[selected]);
    for (final handle in _stampHandles) {
      final center = _stampHandleCenter(rect, handle) * scale;
      if ((local - center).distance <= _stampHandleHitRadius) return handle;
    }
    return null;
  }

  int? _hitComponent(Offset templatePoint, double scale) {
    final pad = 6 / scale;
    for (var i = widget.components.length - 1; i >= 0; i--) {
      if (_componentRect(widget.components[i])
          .inflate(pad)
          .contains(templatePoint)) {
        return i;
      }
    }
    return null;
  }

  void _panStart(DragStartDetails details, Size size) {
    final local = details.localPosition;
    _lastTemplatePoint = _toTemplate(local, size);
    final handle = _handleAt(local, size);
    if (handle != null) {
      _dragKind = _StampDragKind.resize;
      _dragHandle = handle;
      return;
    }
    final hit = _hitComponent(_lastTemplatePoint!, _scale(size));
    widget.onSelect(hit);
    _dragKind = hit == null ? null : _StampDragKind.move;
    _dragHandle = null;
  }

  void _panUpdate(DragUpdateDetails details, Size size) {
    final point = _toTemplate(details.localPosition, size);
    final last = _lastTemplatePoint;
    _lastTemplatePoint = point;
    if (last == null) return;
    _queueDelta(point - last);
  }

  void _tapUp(TapUpDetails details, Size size) {
    widget.onSelect(_hitComponent(_toTemplate(details.localPosition, size),
        _scale(size)));
  }

  void _queueDelta(Offset delta) {
    if (_dragKind == null || delta == Offset.zero) return;
    _pendingKind ??= _dragKind;
    _pendingHandle ??= _dragHandle;
    _pendingDelta += delta;
    if (_pendingFrame) return;
    _pendingFrame = true;
    SchedulerBinding.instance.scheduleFrameCallback((_) {
      _pendingFrame = false;
      _flushPendingDelta();
    });
    SchedulerBinding.instance.ensureVisualUpdate();
  }

  void _flushPendingDelta() {
    final kind = _pendingKind;
    final handle = _pendingHandle;
    final delta = _pendingDelta;
    _pendingKind = null;
    _pendingHandle = null;
    _pendingDelta = Offset.zero;
    if (!mounted || kind == null || delta == Offset.zero) return;
    switch (kind) {
      case _StampDragKind.move:
        widget.onMoveSelected(delta);
      case _StampDragKind.resize:
        widget.onResizeSelected(handle ?? const (dx: 1, dy: 1), delta);
    }
  }

  void _panEnd() {
    _flushPendingDelta();
    _dragKind = null;
    _dragHandle = null;
    _lastTemplatePoint = null;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    const maxWidth = 340.0;
    const maxHeight = 360.0;
    final scale = math.min(maxWidth / widget.templateSize.width,
        maxHeight / widget.templateSize.height);
    final size = Size(
      widget.templateSize.width * scale,
      widget.templateSize.height * scale,
    );
    return Align(
      child: SizedBox(
        width: size.width,
        height: size.height,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          // Anchor the drag at the press point (like the on-page editing
          // overlay) so a handle grab and a move both start where the finger
          // actually landed, not where the recognizer won the gesture arena.
          // Using the recognizer also gives touch slop, so a tap-to-select no
          // longer jitters the component.
          dragStartBehavior: DragStartBehavior.down,
          onTapUp: (details) => _tapUp(details, size),
          onPanStart: (details) => _panStart(details, size),
          onPanUpdate: (details) => _panUpdate(details, size),
          onPanEnd: (_) => _panEnd(),
          child: _StampTemplateSurface(
            templateSize: widget.templateSize,
            components: widget.components,
            selectedIndex: widget.selectedIndex,
            scheme: scheme,
          ),
        ),
      ),
    );
  }
}

class _StampTemplateSurface extends StatefulWidget {
  const _StampTemplateSurface({
    required this.templateSize,
    required this.components,
    required this.selectedIndex,
    required this.scheme,
    this.showChrome = true,
  });

  final Size templateSize;
  final List<PdfStampTemplateComponent> components;
  final int? selectedIndex;
  final ColorScheme scheme;
  final bool showChrome;

  @override
  State<_StampTemplateSurface> createState() => _StampTemplateSurfaceState();
}

class _StampTemplateSurfaceState extends State<_StampTemplateSurface> {
  final Map<int, ui.Image> _images = {};
  final Set<int> _requested = {};

  @override
  void initState() {
    super.initState();
    _syncImages();
  }

  @override
  void didUpdateWidget(_StampTemplateSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncImages();
  }

  @override
  void dispose() {
    for (final image in _images.values) {
      image.dispose();
    }
    super.dispose();
  }

  void _syncImages() {
    final wanted = _wantedImageKeys();
    for (final key in _images.keys.toList()) {
      if (!wanted.contains(key)) _images.remove(key)?.dispose();
    }
    _requested.removeWhere((key) => !wanted.contains(key));
    for (final component in widget.components) {
      final bytes = component.imageBytes;
      if (component.type != PdfStampTemplateComponentType.image ||
          bytes == null) {
        continue;
      }
      final key = _imageKey(bytes);
      if (_images.containsKey(key) || !_requested.add(key)) continue;
      ui.decodeImageFromList(bytes, (image) {
        if (!mounted || !_wantedImageKeys().contains(key)) {
          image.dispose();
          _requested.remove(key);
          return;
        }
        final old = _images[key];
        setState(() => _images[key] = image);
        old?.dispose();
      });
    }
  }

  Set<int> _wantedImageKeys() => {
        for (final component in widget.components)
          if (component.type == PdfStampTemplateComponentType.image &&
              component.imageBytes != null)
            _imageKey(component.imageBytes!)
      };

  @override
  Widget build(BuildContext context) => CustomPaint(
        painter: _StampTemplatePainter(
          templateSize: widget.templateSize,
          components: widget.components,
          selectedIndex: widget.selectedIndex,
          scheme: widget.scheme,
          showChrome: widget.showChrome,
          images: Map<int, ui.Image>.unmodifiable(_images),
        ),
      );
}

class _StampTemplatePainter extends CustomPainter {
  const _StampTemplatePainter({
    required this.templateSize,
    required this.components,
    required this.selectedIndex,
    required this.scheme,
    required this.images,
    this.showChrome = true,
  });

  final Size templateSize;
  final List<PdfStampTemplateComponent> components;
  final int? selectedIndex;
  final ColorScheme scheme;
  final Map<int, ui.Image> images;
  final bool showChrome;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / templateSize.width;
    canvas.save();
    canvas.scale(scale);
    final templateBounds = Offset.zero & templateSize;
    canvas.drawRRect(
      RRect.fromRectAndRadius(templateBounds, const Radius.circular(10)),
      Paint()..color = scheme.surfaceContainerHighest.withValues(alpha: 0.45),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          templateBounds.deflate(0.5), const Radius.circular(10)),
      Paint()
        ..color = scheme.outlineVariant
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1 / scale,
    );
    for (final component in components) {
      _paintComponent(canvas, component);
    }
    if (showChrome &&
        selectedIndex != null &&
        selectedIndex! < components.length) {
      final rect = _rectOf(components[selectedIndex!]);
      final stroke = Paint()
        ..color = scheme.primary
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5 / scale;
      canvas.drawRect(rect.inflate(2 / scale), stroke);
      final handleSize = _stampHandleSize / scale;
      final fill = Paint()..color = scheme.surface;
      for (final handle in _stampHandles) {
        final box = Rect.fromCenter(
          center: _stampHandleCenter(rect, handle),
          width: handleSize,
          height: handleSize,
        );
        canvas.drawRect(box, fill);
        canvas.drawRect(box, stroke);
      }
    }
    canvas.restore();
  }

  Rect _rectOf(PdfStampTemplateComponent c) =>
      Rect.fromLTWH(c.x, c.y, c.width, c.height);

  void _paintComponent(Canvas canvas, PdfStampTemplateComponent c) {
    final rect = _rectOf(c);
    switch (c.type) {
      case PdfStampTemplateComponentType.rectangle:
        final rrect = RRect.fromRectAndRadius(rect, Radius.circular(c.radius));
        if (c.fillColor != null) {
          canvas.drawRRect(
              rrect, Paint()..color = Color(0xFF000000 | c.fillColor!));
        }
        canvas.drawRRect(
          rrect,
          Paint()
            ..color = Color(0xFF000000 | c.color)
            ..style = PaintingStyle.stroke
            ..strokeWidth = c.strokeWidth,
        );
      case PdfStampTemplateComponentType.ellipse:
        if (c.fillColor != null) {
          canvas.drawOval(
              rect, Paint()..color = Color(0xFF000000 | c.fillColor!));
        }
        canvas.drawOval(
          rect,
          Paint()
            ..color = Color(0xFF000000 | c.color)
            ..style = PaintingStyle.stroke
            ..strokeWidth = c.strokeWidth,
        );
      case PdfStampTemplateComponentType.text:
        final text = c.text.isEmpty ? ' ' : c.text;
        var fontSize = c.fontSize ?? c.height * 0.72;
        TextPainter painterFor(double size) => TextPainter(
              text: TextSpan(
                text: text,
                style: TextStyle(
                  color: Color(0xFF000000 | c.color),
                  fontFamily: _uiFamily(c.font),
                  fontWeight:
                      c.font.isBold ? FontWeight.bold : FontWeight.normal,
                  fontStyle:
                      c.font.isItalic ? FontStyle.italic : FontStyle.normal,
                  fontSize: size,
                  letterSpacing: 1,
                ),
              ),
              textDirection: TextDirection.ltr,
              maxLines: 1,
            )..layout(maxWidth: double.infinity);
        var painter = painterFor(fontSize);
        if (painter.width > rect.width && painter.width > 0) {
          fontSize *= rect.width / painter.width;
          painter = painterFor(fontSize);
        }
        painter.paint(
          canvas,
          Offset(rect.left + (rect.width - painter.width) / 2,
              rect.top + (rect.height - painter.height) / 2),
        );
      case PdfStampTemplateComponentType.image:
        final bytes = c.imageBytes;
        final image = bytes == null ? null : images[_imageKey(bytes)];
        if (image == null) {
          canvas.drawRect(
            rect,
            Paint()
              ..color = scheme.surfaceContainerHighest
              ..style = PaintingStyle.fill,
          );
          canvas.drawRect(
            rect,
            Paint()
              ..color = scheme.outline
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1,
          );
          return;
        }
        canvas.drawImageRect(
          image,
          Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
          rect,
          Paint(),
        );
      case PdfStampTemplateComponentType.signature:
        _paintSignature(canvas, c, rect);
    }
  }

  void _paintSignature(Canvas canvas, PdfStampTemplateComponent c, Rect rect) {
    if (c.strokes.isEmpty || rect.width <= 0 || rect.height <= 0) return;
    final basePaint = Paint()
      ..color = Color(0xFF000000 | c.color)
      ..style = PaintingStyle.stroke
      ..strokeWidth = c.strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    for (var i = 0; i < c.strokes.length; i++) {
      final stroke = [
        for (final (x, y) in c.strokes[i])
          Offset(rect.left + x * rect.width, rect.top + y * rect.height),
      ];
      if (stroke.isEmpty) continue;
      final pressure = i < c.pressures.length ? c.pressures[i] : null;
      final controls =
          pdfInkCurveControls([for (final p in stroke) (p.dx, p.dy)]);
      if (pressure == null || pressure.length != stroke.length) {
        if (stroke.length == 1) {
          canvas.drawCircle(stroke.single, c.strokeWidth / 2,
              Paint()..color = basePaint.color);
          continue;
        }
        final path = Path()..moveTo(stroke.first.dx, stroke.first.dy);
        for (var j = 0; j < stroke.length - 1; j++) {
          final ((c1x, c1y), (c2x, c2y)) = controls[j];
          path.cubicTo(c1x, c1y, c2x, c2y, stroke[j + 1].dx, stroke[j + 1].dy);
        }
        canvas.drawPath(path, basePaint);
        continue;
      }
      if (stroke.length == 1) {
        canvas.drawCircle(
            stroke.single,
            pdfInkStrokeWidth(c.strokeWidth, pressure.first) / 2,
            Paint()..color = basePaint.color);
        continue;
      }
      final segment = Paint()
        ..color = basePaint.color
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      for (var j = 0; j < stroke.length - 1; j++) {
        segment.strokeWidth = pdfInkStrokeWidth(
            c.strokeWidth, (pressure[j] + pressure[j + 1]) / 2);
        final ((c1x, c1y), (c2x, c2y)) = controls[j];
        canvas.drawPath(
            Path()
              ..moveTo(stroke[j].dx, stroke[j].dy)
              ..cubicTo(c1x, c1y, c2x, c2y, stroke[j + 1].dx, stroke[j + 1].dy),
            segment);
      }
    }
  }

  @override
  bool shouldRepaint(_StampTemplatePainter oldDelegate) =>
      oldDelegate.templateSize != templateSize ||
      oldDelegate.selectedIndex != selectedIndex ||
      oldDelegate.scheme != scheme ||
      oldDelegate.showChrome != showChrome ||
      oldDelegate.images != images ||
      !_componentListsEqual(oldDelegate.components, components);
}

bool _componentListsEqual(
    List<PdfStampTemplateComponent> a, List<PdfStampTemplateComponent> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

bool _stringListEquals(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

int _imageKey(Uint8List bytes) => Object.hash(
    bytes.length,
    bytes.isEmpty ? 0 : bytes.first,
    bytes.isEmpty ? 0 : bytes.last,
    Object.hashAll(bytes));

String? _stampDetail(PdfCustomStamp stamp) {
  final parts = [
    if (stamp.type != null && stamp.type!.trim().isNotEmpty) stamp.type!.trim(),
    if (stamp.tags.isNotEmpty) stamp.tags.join(', '),
  ];
  return parts.isEmpty ? null : parts.join(' · ');
}

String _fontLabel(PdfStandardFont font) {
  final family = font.family.label;
  final style = [
    if (font.isBold) 'Bold',
    if (font.isItalic) 'Italic',
  ].join(' ');
  return style.isEmpty ? family : '$family $style';
}

String? _uiFamily(PdfStandardFont font) => switch (font.family) {
      PdfStandardFontFamily.serif => 'Times New Roman',
      PdfStandardFontFamily.mono => 'Courier',
      PdfStandardFontFamily.sans => 'Helvetica',
    };

List<String> _normalizeFields(Iterable<String> fields) {
  final seen = <String>{};
  final normalized = <String>[];
  for (final field in fields) {
    final value = field.trim().toLowerCase();
    if (value.isEmpty || !seen.add(value)) continue;
    normalized.add(value);
  }
  return List.unmodifiable(normalized);
}

String _fieldLabel(String field) => switch (field) {
      'date' => 'Date',
      'time' => 'Time',
      'datetime' => 'Date & time',
      'username' => 'Username',
      _ => field
          .split(RegExp(r'[_\s]+'))
          .where((part) => part.isNotEmpty)
          .map((part) => part[0].toUpperCase() + part.substring(1))
          .join(' '),
    };
