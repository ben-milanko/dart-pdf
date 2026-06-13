import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf_document/pdf_document.dart';

import '../page_geometry.dart';
import '../theme.dart';
import 'editing_controller.dart';
import 'text_prompt.dart';

/// One page's interactive form layer: places a tap target over every
/// visible form-field widget so a reader can fill the form directly —
/// click a text field and type, tap a check box or radio button, pick
/// from a drop-down — without ever arming the form authoring tool.
///
/// [PdfViewer] mounts it over each page whenever an editing controller is
/// present, [PdfViewer.interactiveForms] is on, annotations are shown,
/// and no editing tool (or only the select tool) is armed — so it
/// coexists with plain reading and annotation selection but yields the
/// whole page to the drawing/authoring tools. Tap targets cover only the
/// field rects, leaving the rest of the page transparent so scrolling,
/// link taps, and text selection are untouched.
class FormInteractionLayer extends StatefulWidget {
  const FormInteractionLayer({
    super.key,
    required this.controller,
    required this.pageIndex,
    required this.geometry,
    required this.pageColor,
    required this.rasterCurrent,
    this.formImagePicker,
  });

  final PdfEditingController controller;
  final int pageIndex;
  final PdfPageGeometry geometry;
  final Color pageColor;

  /// Whether the page's raster reflects the controller's current
  /// revision. While false just after a text commit, the entered value
  /// is painted over the field so it doesn't flash back to the old
  /// rendering until the new raster lands (mirrors the editing overlay).
  final bool rasterCurrent;

  /// Supplies the image bytes for a push-button (signature / logo) field
  /// tap. When null, push buttons take no taps.
  final PdfFormImagePicker? formImagePicker;

  @override
  State<FormInteractionLayer> createState() => _FormInteractionLayerState();
}

class _FormInteractionLayerState extends State<FormInteractionLayer> {
  final TextEditingController _text = TextEditingController();
  late final FocusNode _focus = FocusNode()..addListener(_onFocusChange);

  // The text field being edited, if any. Fields die with every revision,
  // so the name is the stable handle; the rest is layout captured at open.
  String? _editingField;
  Rect? _editRect;
  PdfStandardFont _editFont = PdfStandardFont.helvetica;
  double _editSize = 12;
  bool _editMultiline = false;

  // The just-committed value, painted over the field until the new
  // revision's raster lands (see [widget.rasterCurrent]).
  String? _afterValue;
  Rect? _afterRect;
  PdfStandardFont _afterFont = PdfStandardFont.helvetica;
  double _afterSize = 12;
  PdfDocument? _afterDocument;

  @override
  void dispose() {
    _focus.removeListener(_onFocusChange);
    _focus.dispose();
    _text.dispose();
    super.dispose();
  }

  PdfEditingController get _controller => widget.controller;

  /// The flutter font family visually matching a base-14 [font] — the
  /// same substitution the renderer and the inline editor use.
  static String _uiFamily(PdfStandardFont font) => switch (font) {
        PdfStandardFont.helvetica => 'Helvetica',
        PdfStandardFont.times => 'Times New Roman',
        PdfStandardFont.courier => 'Courier',
      };

  void _onFocusChange() {
    if (!_focus.hasFocus) _commitText();
  }

  /// Opens the inline editor over a text field, prefilled with its value
  /// and styled from its /DA font and size.
  void _openTextEditor(PdfFormField field, Rect viewRect) {
    final tf = RegExp(r'/(\S+)\s+(\d+(?:\.\d+)?)\s+Tf')
        .firstMatch(field.defaultAppearance ?? '');
    final size = double.tryParse(tf?.group(2) ?? '') ?? 0;
    _text.text = field.value ?? '';
    setState(() {
      _editingField = field.name;
      _editRect = viewRect;
      _editMultiline = field.isMultiline;
      _editFont = tf == null
          ? PdfStandardFont.helvetica
          : PdfStandardFont.fromName(tf.group(1)!);
      // an auto-size /DA (0 Tf) edits at a readable default; the committed
      // appearance derives its own size as usual
      _editSize = size > 0 ? size : 12;
      _afterValue = null; // any prior afterimage is superseded
    });
    _controller.setEditingText(true);
    // autofocus only fires into an unfocused scope and the tapping
    // gesture left focus on the viewer — claim it for the fresh field
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _editingField != null) _focus.requestFocus();
    });
  }

  /// Commits the inline editor into the field's /V. Empty is a legitimate
  /// value (clearing the field). Keeps the entered text painted over the
  /// field until the new raster lands so it doesn't flash.
  void _commitText() {
    final name = _editingField;
    final rect = _editRect;
    if (name == null || rect == null) return;
    final value = _text.text;
    final font = _editFont;
    final size = _editSize;
    _closeEditor();
    final before = _controller.document;
    _controller.setFormFieldText(name, value);
    if (identical(before, _controller.document)) return;
    setState(() {
      _afterValue = value;
      _afterRect = rect;
      _afterFont = font;
      _afterSize = size;
      _afterDocument = _controller.document;
    });
  }

  /// Escape: discard the edit and close (the typed value is dropped).
  void _cancelText() => _closeEditor();

  void _closeEditor() {
    if (_editingField == null) return;
    if (mounted) {
      setState(() {
        _editingField = null;
        _editRect = null;
      });
    } else {
      _editingField = null;
      _editRect = null;
    }
    _controller.setEditingText(false);
  }

  Future<void> _onFieldTap(
      PdfFormField field, int widgetIndex, Rect viewRect) async {
    if (field.isReadOnly) return;
    switch (field.type) {
      case PdfFieldType.text:
        _openTextEditor(field, viewRect);
      case PdfFieldType.checkBox:
        _controller.toggleFormCheckBox(field.name);
      case PdfFieldType.radioGroup:
        final state = field.widgetOnState(widgetIndex);
        if (state != null) _controller.setFormRadioValue(field.name, state);
      case PdfFieldType.comboBox || PdfFieldType.listBox:
        await _pickChoice(field, viewRect);
      case PdfFieldType.pushButton:
        final picker = widget.formImagePicker;
        if (picker == null) return;
        final name = field.name;
        final bytes = await picker(context, field);
        if (bytes != null) _controller.setFormButtonImage(name, bytes);
      case PdfFieldType.signature || PdfFieldType.unknown:
        break;
    }
  }

  /// A choice field's options as a menu anchored under the widget.
  Future<void> _pickChoice(PdfFormField field, Rect viewRect) async {
    final options = field.options;
    if (options.isEmpty) return;
    final name = field.name;
    final box = context.findRenderObject() as RenderBox?;
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (box == null || overlay == null) return;
    final topLeft = box.localToGlobal(viewRect.bottomLeft, ancestor: overlay);
    final picked = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
          topLeft & Size.zero, Offset.zero & overlay.size),
      items: [
        for (final (export, display) in options)
          PopupMenuItem(
            key: ValueKey('pdf-form-option-$export'),
            value: export,
            child: Text(display),
          ),
      ],
    );
    if (picked != null) _controller.setFormChoiceValue(name, picked);
  }

  MouseCursor _cursorFor(PdfFormField field) {
    if (field.isReadOnly) return SystemMouseCursors.basic;
    return switch (field.type) {
      PdfFieldType.text => SystemMouseCursors.text,
      PdfFieldType.signature ||
      PdfFieldType.unknown =>
        SystemMouseCursors.basic,
      _ => SystemMouseCursors.click,
    };
  }

  bool _interactive(PdfFormField field) {
    if (field.isReadOnly) return false;
    return switch (field.type) {
      PdfFieldType.text ||
      PdfFieldType.checkBox ||
      PdfFieldType.radioGroup ||
      PdfFieldType.comboBox ||
      PdfFieldType.listBox =>
        true,
      // push buttons only fill when the host supplies an image picker
      PdfFieldType.pushButton => widget.formImagePicker != null,
      PdfFieldType.signature || PdfFieldType.unknown => false,
    };
  }

  @override
  Widget build(BuildContext context) {
    // the afterimage has served once the committed revision's raster is
    // on screen, or is stale once the document moved past it
    if (_afterDocument != null &&
        (widget.rasterCurrent ||
            !identical(_afterDocument, _controller.document))) {
      _afterValue = null;
      _afterRect = null;
      _afterDocument = null;
    }

    final geometry = widget.geometry;
    final fields = _controller.formWidgetsOn(widget.pageIndex);
    // an edited field that vanished (undo, remote change) drops its editor
    if (_editingField != null &&
        !fields.any((f) => f.$1.name == _editingField)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _closeEditor();
      });
    }

    return Stack(children: [
      for (final (field, widgetIndex, annotation) in fields)
        if (_interactive(field) && field.name != _editingField)
          _tapTarget(field, widgetIndex, geometry.toViewRect(annotation.rect)),
      if (_afterValue != null && _afterRect != null)
        _afterimage(_afterRect!, _afterValue!, _afterFont, _afterSize),
      if (_editingField != null && _editRect != null) _inlineEditor(),
    ]);
  }

  Widget _tapTarget(PdfFormField field, int widgetIndex, Rect rect) {
    return Positioned.fromRect(
      rect: rect,
      child: MouseRegion(
        cursor: _cursorFor(field),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _onFieldTap(field, widgetIndex, rect),
        ),
      ),
    );
  }

  Widget _inlineEditor() {
    final rect = _editRect!;
    final scale = widget.geometry.scale;
    final chromeColor =
        PdfViewerTheme.of(context).annotationChromeColor ??
            const Color(0xFF1E88E5);
    return Positioned.fromRect(
      rect: rect,
      child: Container(
        // cover the old rendered value so it doesn't ghost under the field
        color: widget.pageColor.withValues(alpha: 0.92),
        foregroundDecoration: BoxDecoration(
          border: Border.all(color: chromeColor, width: 1.5),
        ),
        // Escape cancels here, nearer to the field's focus than the
        // viewer's shortcuts, so it wins and closes the editor
        child: CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.escape): _cancelText,
          },
          child: TextField(
            key: const ValueKey('pdf-form-text-editor'),
            controller: _text,
            focusNode: _focus,
            autofocus: true,
            // single-line fields commit on Enter, not a newline
            maxLines: _editMultiline ? null : 1,
            expands: _editMultiline,
            onSubmitted: (_) => _commitText(),
            // tapping off the field commits it — the viewer suppresses its
            // own focus steal while editing, so the field keeps focus
            // until this fires
            onTapOutside: (_) => _commitText(),
            textAlignVertical: _editMultiline
                ? TextAlignVertical.top
                : TextAlignVertical.center,
            cursorColor: const Color(0xFF000000),
            style: TextStyle(
              color: const Color(0xFF000000),
              fontSize: _editSize * scale,
              height: 1.2,
              fontFamily: _uiFamily(_editFont),
            ),
            decoration: InputDecoration(
              isCollapsed: true,
              border: InputBorder.none,
              contentPadding: EdgeInsets.all(2 * scale),
            ),
          ),
        ),
      ),
    );
  }

  /// The committed value frozen over the field until the new raster lands.
  Widget _afterimage(
      Rect rect, String value, PdfStandardFont font, double size) {
    return Positioned.fromRect(
      rect: rect,
      child: IgnorePointer(
        child: Container(
          color: widget.pageColor.withValues(alpha: 0.92),
          alignment:
              _editMultiline ? Alignment.topLeft : Alignment.centerLeft,
          padding: EdgeInsets.all(2 * widget.geometry.scale),
          child: Text(
            value,
            maxLines: _editMultiline ? null : 1,
            overflow: TextOverflow.clip,
            style: TextStyle(
              color: const Color(0xFF000000),
              fontSize: size * widget.geometry.scale,
              height: 1.2,
              fontFamily: _uiFamily(font),
            ),
          ),
        ),
      ),
    );
  }
}
