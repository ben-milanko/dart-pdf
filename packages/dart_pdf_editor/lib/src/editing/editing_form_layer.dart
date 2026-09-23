import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf_document/pdf_document.dart';

import '../annotation_tap.dart';
import '../page_geometry.dart';
import '../theme.dart';
import 'editing_controller.dart';
import 'editing_text_menu.dart';
import 'form_tab_navigation.dart';
import 'text_prompt.dart';

TextDirection _flutterTextDirection(String text) =>
    pdfTextLooksRtl(text) ? TextDirection.rtl : TextDirection.ltr;

/// While the form-authoring tool is armed, outlines every form-field
/// widget on a page and tags it with its field name - so empty fields
/// (which render nothing) are discoverable and you can see what each one
/// is named before selecting it.
///
/// Purely informational: it sits under the editing overlay's gestures
/// ([IgnorePointer]) so selecting, moving, and resizing fields is
/// unaffected. Mounted by [PdfViewer] only when
/// [PdfEditingController.tool] is [PdfEditTool.form].
class FormFieldLabelLayer extends StatelessWidget {
  const FormFieldLabelLayer({
    super.key,
    required this.controller,
    required this.pageIndex,
    required this.geometry,
    this.zoom = 1,
  });

  final PdfEditingController controller;
  final int pageIndex;
  final PdfPageGeometry geometry;
  final double zoom;

  double get _chromeScale => zoom.isFinite && zoom > 0 ? 1 / zoom : 1.0;

  @override
  Widget build(BuildContext context) {
    final chrome = PdfViewerTheme.of(context).annotationChromeColor ??
        const Color(0xFF1E88E5);
    final fields = controller.formWidgetsOn(pageIndex);
    final chromeScale = _chromeScale;
    return IgnorePointer(
      child: Stack(children: [
        for (final (field, _, annotation) in fields)
          _label(geometry.toViewRect(annotation.rect), field.name, chrome,
              chromeScale),
      ]),
    );
  }

  Widget _label(Rect rect, String name, Color chrome, double chromeScale) {
    return Positioned.fromRect(
      rect: rect,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: chrome.withValues(alpha: 0.05),
          border: Border.all(
              color: chrome.withValues(alpha: 0.5), width: chromeScale),
        ),
        child: Align(
          alignment: Alignment.topLeft,
          child: Transform.scale(
            scale: chromeScale,
            alignment: Alignment.topLeft,
            child: Container(
              constraints: BoxConstraints(maxWidth: rect.width),
              padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
              color: chrome.withValues(alpha: 0.85),
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: Color(0xFFFFFFFF), fontSize: 10, height: 1.1),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One page's interactive form layer: places a tap target over every
/// visible form-field widget so a reader can fill the form directly -
/// click a text field and type, tap a check box or radio button, pick
/// from a drop-down - without ever arming the form authoring tool.
///
/// [PdfViewer] mounts it over each page whenever an editing controller is
/// present, [PdfViewer.interactiveForms] is on, annotations are shown,
/// and no editing tool (or only the select tool) is armed - so it
/// coexists with plain reading and annotation selection but yields the
/// whole page to the drawing/authoring tools. Tap targets cover only the
/// field rects, leaving the rest of the page transparent so scrolling,
/// link taps, and text selection are untouched. A signed signature field is
/// a selection target too, exposing its confirmed remove action.
///
/// Tab / Shift+Tab moves between fields in the document's
/// [PdfFormTabOrder] (page /Tabs, across pages, wrapping at the ends): a
/// text field commits and the next field opens - its inline editor, a
/// focus ring on a check box or radio button (Space toggles it), or a
/// choice field's menu. The move is posted through [pdfFormTabRequests] so
/// the target page's layer can take it, and [onRevealField] scrolls it in.
class FormInteractionLayer extends StatefulWidget {
  const FormInteractionLayer({
    super.key,
    required this.controller,
    required this.pageIndex,
    required this.geometry,
    required this.pageColor,
    required this.rasterCurrent,
    this.zoom = 1,
    this.formImagePicker,
    this.onAnnotationTap,
    this.onRevealField,
  });

  final PdfEditingController controller;
  final int pageIndex;
  final PdfPageGeometry geometry;
  final Color pageColor;
  final double zoom;

  /// Whether the page's raster reflects the controller's current
  /// revision. While false just after a text commit, the entered value
  /// is painted over the field so it doesn't flash back to the old
  /// rendering until the new raster lands (mirrors the editing overlay).
  final bool rasterCurrent;

  /// Supplies the image bytes for a push-button (signature / logo) field
  /// tap. When null, push buttons take no taps.
  final PdfFormImagePicker? formImagePicker;

  /// See [PdfViewer.onAnnotationTap].
  final PdfAnnotationTapHandler? onAnnotationTap;

  /// Scrolls a field (page space on a page) into view for a Tab move -
  /// [PdfViewerController.revealRect]. When null, Tab still moves but
  /// nothing scrolls.
  final Future<void> Function(int pageIndex, PdfRect rect)? onRevealField;

  @override
  State<FormInteractionLayer> createState() => _FormInteractionLayerState();
}

class _FormInteractionLayerState extends State<FormInteractionLayer> {
  late final TextEditingController _text = TextEditingController()
    ..addListener(_onTextChanged);
  late final FocusNode _focus = FocusNode()..addListener(_onFocusChange);

  // The text field being edited, if any. Fields die with every revision,
  // so the name is the stable handle; the rest is layout captured at open.
  String? _editingField;
  int _editingWidget = 0;
  Rect? _editRect; // view space; derived from _editPageRect per build
  // page space is the source of truth: a zoom that re-lays-out the page
  // (the _layoutZoom regime changes geometry.scale) would leave a cached
  // view rect stale, drifting the editor across the field - build
  // refreshes _editRect from this through the live geometry
  PdfRect? _editPageRect;
  PdfStandardFont _editFont = PdfStandardFont.helvetica;
  double _editSize = 12;
  bool _editMultiline = false;

  // The just-committed value, painted over the field until the new
  // revision's raster lands (see [widget.rasterCurrent]).
  String? _afterValue;
  Rect? _afterRect;
  PdfStandardFont _afterFont = PdfStandardFont.helvetica;
  double _afterSize = 12;
  bool _afterMultiline = false;
  String? _afterFieldName;
  int? _afterRevisionId;

  // Keyboard focus on a check box / radio / choice widget reached by Tab:
  // (field name, widget index), outlined and taking Space / Tab.
  (String, int)? _focusedWidget;
  late final FocusNode _fieldFocus =
      FocusNode(debugLabel: 'pdf-form-field', skipTraversal: true)
        ..addListener(_onFieldFocusChange);
  // true while a Tab move tears the current field down, and while a choice
  // menu (which takes focus) is open over the focused field
  bool _tabbing = false;
  bool _menuOpen = false;

  late ValueNotifier<PdfFormTabRequest?> _tabRequests =
      pdfFormTabRequests(widget.controller);

  @override
  void initState() {
    super.initState();
    _tabRequests.addListener(_onTabRequest);
    // a Tab move onto a page that wasn't built yet: this layer mounting is
    // the page scrolling in - take the move once laid out
    if (_tabRequests.value?.pageIndex == widget.pageIndex) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _onTabRequest();
      });
    }
  }

  @override
  void didUpdateWidget(FormInteractionLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      _tabRequests.removeListener(_onTabRequest);
      _tabRequests = pdfFormTabRequests(widget.controller)
        ..addListener(_onTabRequest);
    }
  }

  @override
  void dispose() {
    _tabRequests.removeListener(_onTabRequest);
    _fieldFocus.removeListener(_onFieldFocusChange);
    _fieldFocus.dispose();
    _focus.removeListener(_onFocusChange);
    _focus.dispose();
    _text.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    if (_editingField != null && mounted) setState(() {});
  }

  PdfEditingController get _controller => widget.controller;

  double get _chromeScale =>
      widget.zoom.isFinite && widget.zoom > 0 ? 1 / widget.zoom : 1.0;

  /// The flutter font family visually matching a base-14 [font] - the
  /// same substitution the renderer and the inline editor use.
  static String _uiFamily(PdfStandardFont font) => switch (font.family) {
        PdfStandardFontFamily.sans => 'Helvetica',
        PdfStandardFontFamily.serif => 'Times New Roman',
        PdfStandardFontFamily.mono => 'Courier',
      };

  void _onFocusChange() {
    if (!_focus.hasFocus) _commitText();
  }

  /// Opens the inline editor over a text field, prefilled with its value
  /// and styled from its /DA font and size.
  void _openTextEditor(PdfFormField field, Rect viewRect,
      {int widgetIndex = 0}) {
    final tf = RegExp(r'/(\S+)\s+(\d+(?:\.\d+)?)\s+Tf')
        .firstMatch(field.defaultAppearance ?? '');
    final size = double.tryParse(tf?.group(2) ?? '') ?? 0;
    _text.text = field.value ?? '';
    setState(() {
      _editingField = field.name;
      _editingWidget = widgetIndex;
      _editRect = viewRect;
      _editPageRect = widget.geometry.toPageRect(viewRect);
      _editMultiline = field.isMultiline;
      _editFont = tf == null
          ? PdfStandardFont.helvetica
          : PdfStandardFont.fromName(tf.group(1)!);
      // an auto-size /DA (0 Tf) edits at a readable default; the committed
      // appearance derives its own size as usual
      _editSize = size > 0 ? size : 12;
      // reopening the field supersedes its afterimage; another field's
      // (the one a Tab just committed) stays until its raster lands
      if (_afterRevisionId != null && _afterFieldName == field.name) {
        _afterValue = null;
      }
    });
    _controller.setEditingText(true);
    // autofocus only fires into an unfocused scope and the tapping
    // gesture left focus on the viewer - claim it for the fresh field
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
    final multiline = _editMultiline;
    _closeEditor();
    final before = _controller.revisionId;
    _controller.setFormFieldText(name, value);
    if (before == _controller.revisionId) return;
    setState(() {
      _afterValue = value;
      _afterRect = rect;
      _afterFont = font;
      _afterSize = size;
      _afterMultiline = multiline;
      _afterFieldName = name;
      _afterRevisionId = _controller.revisionId;
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
        _editPageRect = null;
      });
    } else {
      _editingField = null;
      _editRect = null;
      _editPageRect = null;
    }
    _controller.setEditingText(false);
  }

  Future<void> _onFieldTap(
      PdfFormField field, int widgetIndex, Rect viewRect) async {
    if (_focusedWidget != null && _focusedWidget != (field.name, widgetIndex)) {
      _clearFieldFocus();
    }
    if (field.type == PdfFieldType.signature) {
      if (_isSigned(field)) {
        final pageRect = widget.geometry.toPageRect(viewRect);
        _controller.selectFormWidgetAt(
          widget.pageIndex,
          (pageRect.left + pageRect.right) / 2,
          (pageRect.bottom + pageRect.top) / 2,
        );
      }
      return;
    }
    if (field.isReadOnly) return;
    switch (field.type) {
      case PdfFieldType.text:
        _openTextEditor(field, viewRect, widgetIndex: widgetIndex);
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
        if (bytes != null) {
          await _controller.setFormButtonImageAsync(name, bytes);
        }
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
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
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
            height: 34,
            child: Text(display,
                style: Theme.of(context)
                    .textTheme
                    .labelMedium
                    ?.copyWith(height: 1.1)),
          ),
      ],
    );
    if (picked != null) _controller.setFormChoiceValue(name, picked);
  }

  // ---- Tab / Shift+Tab ----------------------------------------------------

  /// Tab (or Shift+Tab when [backward]) from the field this layer has
  /// active: commit it, then post a move to the next stop in the
  /// document's tab order and scroll it into view.
  void _moveFocus({required bool backward}) {
    final String? name;
    final int widgetIndex;
    if (_editingField != null) {
      (name, widgetIndex) = (_editingField, _editingWidget);
    } else if (_focusedWidget != null) {
      (name, widgetIndex) = _focusedWidget!;
    } else {
      (name, widgetIndex) = (null, 0);
    }
    _tabbing = true;
    try {
      _commitText();
      _clearFieldFocus();
    } finally {
      _tabbing = false;
    }
    final next = pdfFormTabOrderOf(_controller).step(
      pageIndex: widget.pageIndex,
      fieldName: name,
      widgetIndex: widgetIndex,
      backward: backward,
    );
    if (next == null) return;
    final revealed = widget.onRevealField?.call(next.pageIndex, next.rect) ??
        Future<void>.value();
    _tabRequests.value = PdfFormTabRequest(
      pageIndex: next.pageIndex,
      fieldName: next.fieldName,
      widgetIndex: next.widgetIndex,
      revisionId: _controller.revisionId,
      revealed: revealed,
    );
  }

  /// Takes a posted Tab move that lands on this page.
  void _onTabRequest() {
    final request = _tabRequests.value;
    if (request == null || request.pageIndex != widget.pageIndex) return;
    _tabRequests.value = null;
    if (request.revisionId != _controller.revisionId) return;
    for (final (field, widgetIndex, annotation)
        in _controller.formWidgetsOn(widget.pageIndex)) {
      if (field.name != request.fieldName ||
          widgetIndex != request.widgetIndex) {
        continue;
      }
      final viewRect = widget.geometry.toViewRect(annotation.rect);
      switch (field.type) {
        case PdfFieldType.text:
          _openTextEditor(field, viewRect, widgetIndex: widgetIndex);
        case PdfFieldType.checkBox || PdfFieldType.radioGroup:
          _focusFieldWidget(field.name, widgetIndex);
        case PdfFieldType.comboBox || PdfFieldType.listBox:
          _focusFieldWidget(field.name, widgetIndex);
          // anchor the menu where the field lands once scrolled in
          unawaited(request.revealed.whenComplete(() {
            if (mounted && _focusedWidget == (field.name, widgetIndex)) {
              unawaited(_activateFocused());
            }
          }));
        case PdfFieldType.pushButton ||
              PdfFieldType.signature ||
              PdfFieldType.unknown:
          break;
      }
      return;
    }
  }

  /// Puts keyboard focus on a check box / radio / choice widget.
  void _focusFieldWidget(String name, int widgetIndex) {
    setState(() => _focusedWidget = (name, widgetIndex));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _focusedWidget != null) _fieldFocus.requestFocus();
    });
  }

  void _clearFieldFocus() {
    if (_focusedWidget == null) return;
    if (mounted) {
      setState(() => _focusedWidget = null);
    } else {
      _focusedWidget = null;
    }
  }

  void _onFieldFocusChange() {
    // focus went elsewhere (a click off the field): drop the ring - but not
    // while our own choice menu holds focus over it
    if (!_fieldFocus.hasFocus && !_tabbing && !_menuOpen) _clearFieldFocus();
  }

  KeyEventResult _onFieldKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.tab) {
      _moveFocus(backward: HardwareKeyboard.instance.isShiftPressed);
      return KeyEventResult.handled;
    }
    if (event is KeyRepeatEvent) return KeyEventResult.ignored;
    if (key == LogicalKeyboardKey.space ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      unawaited(_activateFocused());
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape) {
      _clearFieldFocus();
      _fieldFocus.unfocus();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// Space on the focused widget: toggle a check box, select a radio
  /// button, open a choice field's menu.
  Future<void> _activateFocused() async {
    final focused = _focusedWidget;
    if (focused == null) return;
    for (final (field, widgetIndex, annotation)
        in _controller.formWidgetsOn(widget.pageIndex)) {
      if (field.name != focused.$1 || widgetIndex != focused.$2) continue;
      if (field.isReadOnly) return;
      switch (field.type) {
        case PdfFieldType.checkBox:
          _controller.toggleFormCheckBox(field.name);
        case PdfFieldType.radioGroup:
          final state = field.widgetOnState(widgetIndex);
          if (state != null) _controller.setFormRadioValue(field.name, state);
        case PdfFieldType.comboBox || PdfFieldType.listBox:
          _menuOpen = true;
          try {
            await _pickChoice(
                field, widget.geometry.toViewRect(annotation.rect));
          } finally {
            _menuOpen = false;
          }
          // the menu took focus; hand it back so Tab carries on from here
          if (mounted && _focusedWidget == focused) _fieldFocus.requestFocus();
        case PdfFieldType.text ||
              PdfFieldType.pushButton ||
              PdfFieldType.signature ||
              PdfFieldType.unknown:
          break;
      }
      return;
    }
  }

  MouseCursor _cursorFor(PdfFormField field) {
    if (field.type == PdfFieldType.signature && _isSigned(field)) {
      return SystemMouseCursors.click;
    }
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
    if (field.type == PdfFieldType.signature) return _isSigned(field);
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

  bool _isSigned(PdfFormField field) =>
      _controller.signatureByFieldName.containsKey(field.name);

  @override
  Widget build(BuildContext context) {
    // the afterimage has served once the committed revision's raster is
    // on screen, or is stale once the document moved past it
    if (_afterRevisionId != null &&
        (widget.rasterCurrent || _afterRevisionId != _controller.revisionId)) {
      _afterValue = null;
      _afterRect = null;
      _afterRevisionId = null;
    }

    final geometry = widget.geometry;
    // re-derive the editor's view rect through the LIVE geometry: a zoom
    // can re-lay-out the page (_layoutZoom) between open and now, so a
    // cached view rect would have drifted off the field
    if (_editPageRect != null) {
      _editRect = geometry.toViewRect(_editPageRect!);
    }
    final fields = _controller.formWidgetsOn(widget.pageIndex);
    // an edited field that vanished (undo, remote change) drops its editor
    if (_editingField != null &&
        !fields.any((f) => f.$1.name == _editingField)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _closeEditor();
      });
    }
    Rect? focusRect;
    final focused = _focusedWidget;
    if (focused != null) {
      for (final (field, widgetIndex, annotation) in fields) {
        if (field.name == focused.$1 && widgetIndex == focused.$2) {
          focusRect = geometry.toViewRect(annotation.rect);
          break;
        }
      }
      // likewise a Tab-focused widget that vanished drops its ring
      if (focusRect == null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _focusedWidget == focused) _clearFieldFocus();
        });
      }
    }

    return Stack(children: [
      for (final (field, widgetIndex, annotation) in fields)
        if (_interactive(field) && field.name != _editingField)
          _tapTarget(field, widgetIndex, annotation,
              geometry.toViewRect(annotation.rect)),
      if (_afterValue != null && _afterRect != null)
        _afterimage(_afterRect!, _afterValue!, _afterFont, _afterSize),
      if (focusRect != null) _focusRing(focusRect),
      if (_editingField != null && _editRect != null) _inlineEditor(),
    ]);
  }

  /// The keyboard-focus outline over a Tab-focused check box / radio /
  /// choice widget; its [Focus] takes Space, Enter, Tab and Escape.
  Widget _focusRing(Rect rect) {
    final chromeScale = _chromeScale;
    final chromeColor = PdfViewerTheme.of(context).annotationChromeColor ??
        const Color(0xFF1E88E5);
    return Positioned.fromRect(
      key: const ValueKey('pdf-form-focus-ring'),
      rect: rect.inflate(2 * chromeScale),
      child: IgnorePointer(
        child: Focus(
          focusNode: _fieldFocus,
          onKeyEvent: _onFieldKey,
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(color: chromeColor, width: 2 * chromeScale),
              borderRadius: BorderRadius.circular(2 * chromeScale),
            ),
          ),
        ),
      ),
    );
  }

  Widget _tapTarget(PdfFormField field, int widgetIndex,
      PdfAnnotation annotation, Rect rect) {
    return Positioned.fromRect(
      rect: rect,
      child: MouseRegion(
        cursor: _cursorFor(field),
        child: GestureDetector(
          key: ValueKey(
            'pdf-form-field-${widget.pageIndex}-${field.name}-$widgetIndex',
          ),
          behavior: HitTestBehavior.opaque,
          onTapUp: (details) {
            final pageViewPosition = rect.topLeft + details.localPosition;
            final (x, y) = widget.geometry.toPagePoint(pageViewPosition);
            widget.onAnnotationTap?.call(PdfAnnotationTapDetails(
              annotation: annotation,
              pageIndex: widget.pageIndex,
              pagePoint: Offset(x, y),
              pageViewPosition: pageViewPosition,
              globalPosition: details.globalPosition,
            ));
            unawaited(_onFieldTap(field, widgetIndex, rect));
          },
        ),
      ),
    );
  }

  Widget _inlineEditor() {
    final rect = _editRect!;
    final scale = widget.geometry.scale;
    final chromeScale = _chromeScale;
    final chromeColor = PdfViewerTheme.of(context).annotationChromeColor ??
        const Color(0xFF1E88E5);
    return Positioned.fromRect(
      // keyed so a Tab from one field of this page to another keeps the
      // same TextField (and its focus) rather than rebuilding it
      key: const ValueKey('pdf-form-inline-editor'),
      rect: rect,
      child: Container(
        // cover the old rendered value so it doesn't ghost under the field
        color: widget.pageColor.withValues(alpha: 0.92),
        foregroundDecoration: BoxDecoration(
          border: Border.all(color: chromeColor, width: 1.5 * chromeScale),
        ),
        // Escape cancels here, nearer to the field's focus than the
        // viewer's shortcuts, so it wins and closes the editor. Tab and
        // Shift+Tab move to the next / previous field - bound here, so a
        // multi-line field never types a tab character and the app's focus
        // traversal never sees the key
        child: CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.escape): _cancelText,
            const SingleActivator(LogicalKeyboardKey.tab): () =>
                _moveFocus(backward: false),
            const SingleActivator(LogicalKeyboardKey.tab, shift: true): () =>
                _moveFocus(backward: true),
          },
          // the same zoom-space caret treatment the free-text editor gets:
          // Apple's device-pixel nudge cancelled, and the caret gutter
          // handed back below so right-aligned (RTL) values stay put
          child: pdfZoomAwareCaret(
            context,
            chromeScale: chromeScale,
            child: TextField(
              key: const ValueKey('pdf-form-text-editor'),
              controller: _text,
              focusNode: _focus,
              autofocus: true,
              // single-line fields commit on Enter, not a newline
              maxLines: _editMultiline ? null : 1,
              expands: _editMultiline,
              onSubmitted: (_) => _commitText(),
              // tapping off the field commits it - the viewer suppresses its
              // own focus steal while editing, so the field keeps focus
              // until this fires
              onTapOutside: (_) => _commitText(),
              // the zoom transform would otherwise scale AND displace the
              // long-press selection menu off-screen
              contextMenuBuilder: (context, editableTextState) =>
                  pdfPlacedTextSelectionMenu(
                editableTextState,
                AdaptiveTextSelectionToolbar.editableText(
                    editableTextState: editableTextState),
              ),
              textDirection: _flutterTextDirection(_text.text),
              textAlign: _flutterTextDirection(_text.text) == TextDirection.rtl
                  ? TextAlign.right
                  : TextAlign.left,
              textAlignVertical: _editMultiline
                  ? TextAlignVertical.top
                  : TextAlignVertical.center,
              cursorColor: const Color(0xFF000000),
              cursorWidth: 2 * chromeScale,
              cursorHeight: pdfZoomAwareCursorHeight(
                context,
                lineHeight: _editSize * scale * 1.2,
                chromeScale: chromeScale,
              ),
              style: TextStyle(
                color: const Color(0xFF000000),
                fontSize: _editSize * scale,
                height: 1.2,
                fontFamily: _uiFamily(_editFont),
                fontWeight:
                    _editFont.isBold ? FontWeight.bold : FontWeight.normal,
                fontStyle:
                    _editFont.isItalic ? FontStyle.italic : FontStyle.normal,
              ),
              decoration: InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
                contentPadding: EdgeInsets.fromLTRB(
                  2 * scale,
                  2 * scale,
                  math.max(0.0, 2 * scale - pdfCaretGutter(chromeScale)),
                  2 * scale,
                ),
              ),
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
      key: const ValueKey('pdf-form-afterimage'),
      rect: rect,
      child: IgnorePointer(
        child: Container(
          color: widget.pageColor.withValues(alpha: 0.92),
          alignment: _flutterTextDirection(value) == TextDirection.rtl
              ? (_afterMultiline ? Alignment.topRight : Alignment.centerRight)
              : (_afterMultiline ? Alignment.topLeft : Alignment.centerLeft),
          padding: EdgeInsets.all(2 * widget.geometry.scale),
          child: Text(
            value,
            textDirection: _flutterTextDirection(value),
            textAlign: _flutterTextDirection(value) == TextDirection.rtl
                ? TextAlign.right
                : TextAlign.left,
            maxLines: _afterMultiline ? null : 1,
            overflow: TextOverflow.clip,
            style: TextStyle(
              color: const Color(0xFF000000),
              fontSize: size * widget.geometry.scale,
              height: 1.2,
              fontFamily: _uiFamily(font),
              fontWeight: font.isBold ? FontWeight.bold : FontWeight.normal,
              fontStyle: font.isItalic ? FontStyle.italic : FontStyle.normal,
            ),
          ),
        ),
      ),
    );
  }
}
